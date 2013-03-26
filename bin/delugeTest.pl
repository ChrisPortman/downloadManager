#!/usr/bin/env perl

use strict;
use warnings;
use lib '../lib';

#3rd Pty Modules
use Getopt::Long;
use Config::Auto;
use Log::Dispatch;
use Log::Any::Adapter;
use Data::Dumper;

#Our modules
use Api::Xbmc;
use Api::Deluge;
use Downloads::Tv;
use Downloads::Movies;

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
    print "CONFIG:\n";
    print Dumper($config)."\n";
}
else {
    die "The config file ($cfgfile) does not exist.\n";
}

my $deluge = Api::Deluge->new($config);

$deluge->login();

my $torrents = $deluge->getTorrents();
print Dumper($torrents)."\n";

TORRENT:
for ( keys %{$torrents} ) {
    my $tor = $torrents->{$_};
    next unless $tor->{'state'} =~ /seeding/i;
    my @seedTrackers = ref( $config->{'seedTrackers'} )
                       ? @{ $config->{'seedTrackers'} }
                       :  ( $config->{'seedTrackers'} );
    
    for my $tracker (@seedTrackers) {
        if ( $tracker =~ /$tor->{'tracker_host'}/ ) {
            print "Would NOT delete ".$tor->{'name'}."\n";
            next TORRENT;
        }
    }
    
    print "Would continue to delete ".$tor->{'name'}."\n";
}

exit;
    
