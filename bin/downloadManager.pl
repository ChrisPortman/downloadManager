#!/usr/bin/env perl

#Core Modules
use strict;
use warnings;
use File::Path qw(remove_tree);

my $path;
BEGIN {
    #Get the lib dir relative to this file.
    use Cwd 'abs_path';
    ($path) = abs_path($0) =~ m|^(.+/)[^/]+$|;
}
use lib $path.'../lib';

#3rd Pty Modules
use Getopt::Long;
use Config::Auto;
use Log::Dispatch;
use Log::Any::Adapter;
use MIME::Lite;

#Our modules
use Api::Xbmc;
use Api::Deluge;
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
    callbacks => [ \&createLogEmail ],
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

my $email;

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
        
        if (@seedTrackers) {
            for my $tracker (@seedTrackers) {
                if ( $tracker =~ /$tor->{'tracker_host'}/ ) {
                    $log->debug("NOT deleting ".$tor->{'name'});
                    next TORRENT;
                }
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
    my $dir      = shift or return;
    my $tvDir    = $config->{'tvDownloadDir'};
    my $movieDir = $config->{'moviesDownloadDir'};
    
    unless (    $dir =~ m{$tvDir}
             or $dir =~ m{$movieDir} ) 
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
    elsif ( -f $dir or -l $dir ) {
        unless (unlink $dir) {
          $log->warn("Could not delete $dir: $!");
          return;
        }
    }
    
    return 1;
}

sub createLogEmail {
    my %args    = @_;
    my $message = $args{'message'};
    
    $email .= $message."\n";
    
    return $message;
}

sub sendEmail {
    if ($config->{'mailLogTo'} ) {
        $mail_server = $config->{'mailServer'} || 'localhost';

        $log->info("Sending mail...");
        MIME::Lite->send('smtp', "localhost");
        my $msg = MIME::Lite->new(
             From     => 'bishop@portman.net.au',
             To       => $config->{'mailLogTo'},
             Subject  => 'Torrent Complete!',
             Data     => "Torrent Complete!\n\n$email",
        );
        $msg->send();
    }
    return 1;
}

#-------------#
#----MAIN-----#
#-------------#

$SIG{__DIE__} = \&sendEmail;

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
removeTorrents();

#See if we did stuff.  If we did, XBMC needs updating
if ( $tv->filesProcessed() or $movies->filesProcessed() ) {
    #Update XBMC
    $log->info('Updating XBMC Library');
    $xbmc->updateLibrary();
}

sendEmail();

exit;
