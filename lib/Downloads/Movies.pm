#!/usr/bin/env perl

use strict;
use warnings;

package Downloads::Movies;

use Carp;
use parent qw( Downloads );
use Log::Any qw ( $log );
use WWW::Mechanize;  #for now...

sub new {
    my $class = shift;
    my %args  = ref $_[0] ? %{$_[0]} : @_;
    
    $class = ref $class || $class;
    my %usableArgs;
    
    #Validate args
    $log->debug('Checking configurables:');
    for my $arg ( qw( moviesDownloadDir moviesDir 
                      unsortedDir 
                      fileOwn fileGrp fileMode symlinks    ) )
    {
        $args{$arg}
          or croak "$class->new() requires $arg\n";
        $usableArgs{$arg} = $args{$arg};
        $log->debug("\tTV: $arg set to $usableArgs{$arg}");
    }
    
    for my $dir ( qw( moviesDownloadDir moviesDir unsortedDir ) ) {
        $usableArgs{$dir} =~ s|/$||;
    }
    
    $usableArgs{'fileMode'} =~ /^\d\d\d\d$/
      or die "File mode from config not valid\n";
    
    $usableArgs{'processedFiles'} = 0;
    
    my $obj = bless \%usableArgs, $class;
    
    return $obj;
}

sub processMovies {
    my $self = shift;
    
    #Get all the shows that we track.
    my @vidFiles = $self->findMedia($self->{moviesDownloadDir});
    
    $log->debug("\tMOVIES: Procesing Downloads:");

    FILE:
    for my $file ( @vidFiles ) {
        $log->info("\tMOVIES: Processing $file");
        my $unsort;
        
        my ($path, $fileNoPath) = $file =~ /^(.+)\/([^\/]+)$/;
        
        my ( $nfoFile, $imdbId, $movieDetails );
        
        unless ($nfoFile = $self->findNfo($path)) {
            $log->warn("\t\tNo nfo file with $fileNoPath, will be in unsorted");
            $self->unsort($file);
            next;
        }
        
        unless ( $imdbId = $self->getImdbId($nfoFile) ) {
            $log->warn("\t\tNo IMDB ID for $fileNoPath, will be in unsorted");
            $self->unsort($file);
            next;
        }
        
        unless ( $movieDetails = $self->getImdbDetails($imdbId) ) {
            $log->warn("\t\tNo details from IMDB for $fileNoPath, will be in unsorted");
            $self->unsort($file);
            next;
        }
        
        my $title = $movieDetails->{title};
        my $year  = $movieDetails->{year};
        
        $log->info("\t\tThis movie is: $title");
        
        my ($res) = $file =~ /(720|1080)/;
        my ($ext) = $file =~ /\.(\w\w\w)$/;
        
        my $filename  = "$title ($year)";
        $filename    .= " ($res)" if $res;
        $filename    .= ".$ext";
        
        $self->storeFile( $file, $self->{moviesDir}.'/'.$filename );
        
        $self->{'processedFiles'} ++;
    }
    
    return $self->{'processedFiles'};
}

sub findNfo {
    my $self = shift;
    my $path = shift;
    
    $path =~ s/\/$//;
    
    unless ($path and -d $path) {
        $log->error("findNfo not provided a path");
        return;
    }
    
    my $dh;
    unless ( opendir($dh, $path) ) {
        $log->error("Cant open $path: $!");
        return;
    }
    
    my ($nfo) = map { $path.'/'.$_ } grep { /\.nfo$/i } readdir($dh);
    
    closedir($dh);
    
    return $nfo;
}

sub getImdbId {
    my $self = shift;
    my $nfo  = shift || return;
    my ($imdbId, $fh);
    
    unless ( -f $nfo ) {
        $log->error("$nfo is not a file");
        return;
    }
    
    unless ( open ($fh, '<', $nfo) ) {
        $log->error("Cant open $nfo: $!");
        return;
    }

    {
        local $/ = undef;
        my $contents = <$fh>;
        ($imdbId) = $contents =~ /(tt\d+)/;
    }
    
    close $fh;
    
    return $imdbId if $imdbId;
    return;
}

sub getImdbDetails {
    #declare some vars
    my $self   = shift;
    my $imdbID = shift;
    my %movieDetails;
    my $browser;
    my $imdbUri;
    my $xml;
    
    #get the details of the movie in xml form.
    $imdbUri = 'http://www.imdbapi.com/?r=xml&i=' . $imdbID;
    $browser = WWW::Mechanize->new( autocheck => 1, timeout => 10 );
    $browser->get( $imdbUri )
      or return 0;
    $xml = $browser->content();
    
    #search throug the xml for the title and year
    if ( $xml =~ m|<movie\stitle="(.+)"\syear="(\d+)"|i ) {
        %movieDetails = ( title => $1,
                          year  => $2,
        );
    } 
    else {
        return 0;
    }
    
    #return a reference to %movieDetails
    return wantarray ? %movieDetails : \%movieDetails;
}



1;
