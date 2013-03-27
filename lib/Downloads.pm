#!/usr/bin/env perl

use strict;
use warnings;

package Downloads;

use File::Unpack;
use JSON::XS;
use Data::Dumper;
use Log::Any qw ( $log );

sub decompress {
    my $self = shift;
    my $file = shift || die "Decompress() did not get a file\n";
    my @files;
    my $result;
    my ($dir) = $file =~ /(.+\/)/;
    $dir or die "Decompress couldnt determine dir from filename\n";
    
    if ($file =~ /(rar|r00)$/) {
        my $rarlog;

        my $unpacker = File::Unpack->new(
            logfile             => \$rarlog,
            destdir             => $dir,
            maxfilesize         => '10G',
            world_readable      => 1,
            archive_name_as_dir => 0,
        );
        
        $unpacker->unpack($file);
        $result = decode_json($rarlog);
    }
    
    my ($vidFile) = grep { /(mkv|avi|mp4)$/ and not /sample/i } keys %{$result->{'unpacked'}};
    
    unless ($vidFile) {
        $log->warn('Decompress: Did not unpack any video files');
        return;
    }
    
    $log->info("Decompress: Unpacked video file $vidFile");
    return $dir.'/'.$vidFile;
}

sub unpackRar {
    my $self = shift;
    my $file = shift || die "unpackRar() did not get a file\n";
    
    #check for a done file so we dont do this file again.
    return if -e $file.'.done';

    $log->debug("\tUnpacking file $file");

    my ($dir) = $file =~ /(.+\/)/;
    $dir or die "UnpackRar couldnt determine dir from $file\n";
    
    my $result;
    if ($file =~ /(rar|r00)$/) {
        my $rarlog;

        my $unpacker = File::Unpack->new(
            logfile             => \$rarlog,
            destdir             => $dir,
            maxfilesize         => '100G',
            world_readable      => 1,
            archive_name_as_dir => 0,
        );
        
        $unpacker->unpack($file);
        $result = decode_json($rarlog);
    }
    
    my (%files) = map { $_ => 1 }
                  map { /^([^\/]+)/; $1 }
                  grep { not /\.(?:rar|r00)/i }
                  keys %{$result->{'unpacked'}};

    #create a done file for this rar so we dont do it again.
    open (my $fh, '>', $file.'.done')
      or die "Could not create a done file for rar achive $file\n";
    print $fh 'done';
    close $fh;
    
    return wantarray ? keys %files : [ keys %files ];
}

sub findMedia {
    my $self = shift;
    my $dir  = shift or die "findMedia requires a directory to look in\n";
    
    $log->debug("Looking for media in $dir");
    
    -d $dir 
      or die "For some reason findMedia was given a dir that is not a dir\b";
    
    $dir =~ s|/$||;
    
    opendir (my $dh, $dir)
      or die "Could not open $dir: $!\n";
    
    my @contents = #nothing that starts with dot (.) or has sample in it and no symlinks
                   #after that, only dirs and media or rar files. 
                   grep { not(-l) and not(/sample/i) and ( /(mkv|avi|mp4|rar|r00)$/ or -d )  } 
                   map  { $dir.'/'. $_ }
                   grep { not /^\./ } # not . files
                   readdir($dh);
    
    my @mediaFiles;
    
    CONTENT:
    for (@contents) {
        if ( -d ) {
            push @mediaFiles, $self->findMedia($_);
        }
        elsif ( /(rar|r00)$/i ) {
            if ( /r00$/i ) {
                #look for a rar, we'd rather act on that
                for (@contents) {
                    next CONTENT if /rar$/i;
                }
            }
            for ( $self->unpackRar($_) ) {
                push @contents, $dir.'/'.$_;
            }
        }
        else {
            $log->debug("\tFound: $_");
            push @mediaFiles, $_;
        }
    }
    
    $self->{media} = \@mediaFiles;
    
    return wantarray ? @mediaFiles : \@mediaFiles;
}
    
sub storeFile {
    my $self   = shift;
    my $source = shift;
    my $dest   = shift;
    my $unsort;
    
    my ($destDir, $destFile) = $dest =~ m|^(.+)/([^/]+)$|;
    
    #build the Dir path if its not already there.
    my $path;
    for my $part ( split(m|/|, $destDir) ) {
        $path .= "/$part";
        
        unless ( -e $path ) {
            mkdir $path;
        }
        
        unless ( -d $path ) {
            die "$path does not exist and it should\n";
        }
    } 
    
    if ( -e $dest ) {
        $log->warn("$dest already exists. $source will be unsorted");
        $self->unsort($source);
        return;
    }
    
    $log->info("\t\tNew file: $dest");
    $log->debug("\t\tMoving $source to $dest");
    if (-f $source) {
        rename $source, $dest
          or die "Could not move $source to $dest: $!\n";
        
        $self->setFilePerms($dest);
        
        if ($self->{'symlinks'}) {
            $log->info("\t\tCreating symlink");
            $log->debug("\t\tLinking $dest to $source");
            symlink $dest, $source
              or die "Could not create synlink from $dest to $source: $!\n";
        }
        
        return 1;
    }
    
    return;
}

sub unsort {
    my $self   = shift;
    my $source = shift or die "No file to be moved to unsorted supplied\n";
    
    $self->{unsortedDir}
      or die "Destination for unsorted not supplied in config (unsortedDir)\n";
    
    -d $self->{unsortedDir}
      or die "Destination for unsorted supplied is not a directory\n";
      
    -f $source
      or die "$source is not a file\n";
      
    my ($filename) = $source =~ m|([^/]+)$|;
    my $dest = $self->{unsortedDir}.'/'.$filename;
    
    rename $source, $dest
      or die "Could not move $source to $dest: $!\n";
    
    if ($self->{'symlinks'}) {
        $log->info("\t\tCreating symlink. NOTE: When you come to sort manually, you will need to update the symlink!");
        $log->debug("\t\tLinking $dest to $source");
        symlink $dest, $source
          or die "Could not create synlink from $dest to $source: $!\n";
    }
}    

sub setFilePerms {
    my $self = shift;
    my $file = shift or die "Cant set file permissions without a file.";
    
    #Set the ownership and permissions on the new file
    my ($login,$pass,$uid) = getpwnam($self->{fileOwn})
      or die $self->{fileOwn}." is not a valid user\n";

    my ($name,$passwd,$gid) = getgrnam($self->{fileGrp})
      or die $self->{fileGrp}." is not a valid group\n";
      
    chown $uid, $gid, $file
      or die "Could not set the ownership of $file: $!\n";

    chmod oct($self->{fileMode}), $file
      or die "Could not set permissions of $file: $!\n";
    
    return 1;
}

sub filesProcessed {
    my $self = shift;
    return $self->{processedFiles};
}


1;
