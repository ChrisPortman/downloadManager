#!/usr/bin/env perl

use strict;
use warnings;
use lib '../lib';
use File::Path qw(remove_tree);

#3rd Pty Modules
use Getopt::Long;
use Config::Auto;
use Log::Dispatch;
use Log::Any::Adapter;

#Our modules
use Api::Xbmc;
use Downloads::Tv;
use Downloads::Movies;

#-------------#
#---SETUP-----#
#-------------#

#Set up logging
my $log = Log::Dispatch->new(
    outputs => [
        [ 'Screen', min_level => 'info', newline => 1, ],
    ],
);
Log::Any::Adapter->set( 'Dispatch', dispatcher => $log );

$SIG{__DIE__} = sub { $log->crit($_[0]) };

#Get Cmd line opts
my $cfgfile = '/etc/downloadManager.conf';
my $optsOk = GetOptions( 'cfgfile|c=s' => \$cfgfile, );
die "Invalid options.\n" unless $optsOk;

#Suck in the config
my $config;
if ( -f $cfgfile ) {
    my $confObj = Config::Auto->new( source => $cfgfile );
    $config = $confObj->parse();
}
else {
    die "The config file ($cfgfile) does not exist.\n";
}

#-------------#
#----SUBS-----#
#-------------#
sub removeTorrents {
    my $deluge = Api::Deluge->new($config);
    my $torrents = $deluge->getTorrents();
    
    TORRENT:
    for my $torId ( keys %{$torrents} ) {
        my $tor = $torrents->{$torId};
        next unless $tor->{'state'} =~ /seeding/i;
        my @seedTrackers = ref( $config->{'seedTrackers'} )
                           ? @{ $config->{'seedTrackers'} }
                           :  ( $config->{'seedTrackers'} );
        
        for my $tracker (@seedTrackers) {
            if ( $tracker =~ /$tor->{'tracker_host'}/ ) {
                $log->debug("NOT deleting ".$tor->{'name'});
                next TORRENT;
            }
        }
        $log->info("Deleting ".$tor->{'name'}.'...');
        
        deleteDir($tor->{'save_path'}.'/'.$tor->{'name'})
          or $log->warn('Failed to delete torrent Data @ '.$tor->{'save_path'}.'/'.$tor->{'name'});
        
        print $deluge->removeTorrent($torId, 1) 
          ? $log->info("\tSUCCESS") 
          : $log->info("\tFAILED");
    }
}

sub deleteDir {
    my $dir = shift or return;
    
    unless (    $config->{'tvDownloadDir'} =~ /$dir/
             or $config->{'moviesDownloadDir'} =~ /$dir/ ) 
    {
        $log->warn("$dir does not look like a directory we would download to. I'm not deleting it");
        return;
    }
    
    if ( -d $dir ) {
        unless ( remove_tree($dir) ) {
          $log->warn("Could not delete $dir: $!");
          return;
        }
    }
    
    return 1;
}

#-------------#
#----MAIN-----#
#-------------#

#Set up some objects
my $tv     = Downloads::Tv->new($config);
my $movies = Downloads::Movies->new($config);
my $xbmc   = Api::Xbmc->new($config);

#Look for stuff to do.
#Do TV first as its the least ambiguous
$log->info('Checking for TV');
$tv->processTv();

$log->info('Checking for Movies');
$movies->processMovies();

#Clean up torrents


#See if we did stuff.  If we did, XBMC needs updating
if ( $tv->filesProcessed() or $movies->filesProcessed() ) {
    #Update XBMC
    $log->info('Updating XBMC Library');
    $xbmc->updateLibrary();
}

exit;
    
