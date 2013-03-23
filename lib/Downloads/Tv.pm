#!/usr/bin/env perl

use strict;
use warnings;

package Downloads::Tv;

use Carp;
use parent qw( Downloads );
use Log::Any qw ( $log );

sub new {
    my $class = shift;
    my %args  = ref $_[0] ? %{$_[0]} : @_;
    
    $class = ref $class || $class;
    my %usableArgs;
    
    #Validate args
    $log->debug('Checking configurables:');
    for my $arg ( qw( tvDownloadDir tvShowDir 
                      unsortedDir 
                      fileOwn fileGrp fileMode symlinks    ) )
    {
        $args{$arg}
          or croak "$class->new() requires $arg\n";
        $usableArgs{$arg} = $args{$arg};
        $log->debug("\tTV: $arg set to $usableArgs{$arg}");
    }
    
    for my $dir ( qw( tvDownloadDir tvShowDir unsortedDir ) ) {
        $usableArgs{$dir} =~ s|/$||;
    }
    
    $usableArgs{'fileMode'} =~ /^\d\d\d\d$/
      or die "File mode from config not valid\n";
    
    $usableArgs{'processedFiles'} = 0;
    
    my $obj = bless \%usableArgs, $class;
    
    return $obj;
}

sub processTv {
    my $self = shift;
    
    #Get all the shows that we track.
    my @tvShows     = $self->getShows();
    my @tvDownloads = $self->findMedia($self->{tvDownloadDir});
    
    $log->info("TV: Procesing Downloads:");

    FILE:
    for my $file ( @tvDownloads ) {
        $log->info("\tTV: Processing $file");
        my ($fileNoPath) = $file =~ /([^\/]+)$/; 
        
        my $bestScore = 0;
        my $bestMatch;
        
        SHOW:
        for my $show ( @tvShows ) {
            $log->debug("\t\tTesting $file against show $show");
            my $score = 0;
            
            MATCHPART:
            for my $part ( split(/\s/, $show) ) {
                next SHOW unless $fileNoPath =~ /$part/i;
                $score ++;
            }
            
            if ($score > $bestScore) {
                $bestScore = $score;
                $bestMatch = $show;
            }
        }
        
        if ($bestScore and $bestMatch) {
            $log->info("\t\tDetermined this an episode of $bestMatch");
            my ($season, $episode, $ext) = $self->getEpisodeDetails($fileNoPath);
            
            if ( $season and $episode and $ext ) {
                my $destFileName = 'Episode '.$season.'x'.$episode.'.'.$ext;
                my $destFile = $self->{tvShowDir}.'/'.$bestMatch.'/Season '.$season.'/'.$destFileName;
                
                $self->storeFile($file, $destFile);
    
                $self->{'processedFiles'} ++;
            }
            else {
                $log->warn("\t\tCould not determine episode details. It will go to unsorted");
                $self->unsort($file);
            }
        }
        else {
            $log->warn("\t\tCould not determine TV show, moving to unsorted");
            $self->unsort($file);
        }
    }
    
    return $self->{'processedFiles'};
}

sub getShows {
    my $self = shift;
    my $showDir = $self->{'tvShowDir'};
    
    opendir(my $dh, $showDir)
      or die "Can't open directory $showDir: $!\n";
    
    #All the folders in the TV Show dir represent a show by name.
    my @shows = grep { $_ !~ /^\./ and -d $showDir.'/'.$_ } readdir($dh);
    
    $log->debug('TV: Found these shows:');
    for my $show ( @shows ) {
        $log->debug("\t$show");
    }
    
    return wantarray ? @shows : \@shows;    
}
    
sub getEpisodeDetails {
    my $self = shift;
    my $file = shift || die "No file supplied to getEpisodeDetails()\n";
    my ($season, $episode, $ext);
    
    #Remove the SD/HD indicators to simplify the Season/Episode regex
    $file =~ s/720|1080//;

    if ( $file =~ m/(?|
                    #matches S01E01 notations:
                    s(\d\d?)\s?e(\d\d?(?:\DE?\d\d?)*).*\.(\w\w\w)$|
                    
                    #matches 1x01 or 10 x 01 or 10 x1 or 10x 1 etc
                    (\d\d?)\s?x\s?(\d\d?(?:\DE?\d\d?)*).*\.(\w\w\w)$|
                    
                    #matches 101 notations NOTE: purposfully wont manage 4 digits to avoid years
                    \D(\d)(\d\d)\D.*\.(\w\w\w)$               
                    )/xi
    ) {
        $season  = $1;
        $episode = $2;
        $ext     = $3;
        
        #Remove any leading 0's
        $season  =~ s/^0+//;
        $episode =~ s/^0+//;
        
        $log->info("\t\tTV: This is episode $episode of Season $season");
    }
    
    return ($season, $episode, $ext);
}


1;
