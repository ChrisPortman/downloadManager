#!/usr/bin/env perl

use strict;
use warnings;

package Downloads::Movies;

use Carp;
use parent qw( Downloads );
use Log::Any qw ( $log );
use WWW::Mechanize;  #for now...

my $OMDB_API_HOST = 'http://www.omdbapi.com/';

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
    
    $log->info("MOVIES: Procesing Downloads:");

    FILE:
    for my $file ( @vidFiles ) {
        $log->info("\tMOVIES: Processing $file");
        my $unsort;
        
        my ($path, $fileNoPath) = $file =~ /^(.+)\/([^\/]+)$/;
        
        my ( $nfoFile, $imdbId, $movieDetails );
        
        if ($nfoFile = $self->findNfo($path)) {
          if ( $imdbId = $self->getImdbId($nfoFile) ) {
            $movieDetails = $self->getImdbDetails($imdbId);
          }
        }

        unless ($movieDetails) {
          $log->warn("\t\tNo luck getting the movie details using an IMDB ID from an NFO.  Trying a manual search");
          my ($title, $year) = $fileNoPath =~ /^(.+).(19\d\d|20\d\d)/;
          $title =~ s/\./ /g;
          $movieDetails = $self->getImdbDetails($title, $year);
        }

        unless ($movieDetails) {
          $log->warn("\t\tHave not been able to find the movie in IMDB. Moving to unsorted");
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
    my $search = shift;
    my $year   = shift || undef;
    my %movieDetails;
    my $browser;
    my $uri;
    my $xml;

    $uri  = $OMDB_API_HOST . '?r=xml&';
    $uri .= $search =~ /^tt\d+$/ ? "i=$search" : "t=$search";
    $uri .= "&y=$year" if $year; 
    
    #get the details of the movie in xml form.
    $browser = WWW::Mechanize->new( autocheck => 1, timeout => 10 );
    $browser->get( $uri )
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
