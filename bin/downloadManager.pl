#!/usr/bin/env perl

use strict;
use warnings;
use lib '../lib';

#3rd Pty Modules
use Getopt::Long;
use Config::Auto;
use Log::Dispatch;
use Log::Any::Adapter;

#Our modules
use Api::Xbmc;
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
}
else {
    die "The config file ($cfgfile) does not exist.\n";
}

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

#See if we did stuff.  If we did, XBMC needs updating
if ( $tv->filesProcessed() or $movies->filesProcessed() ) {
    #Update XBMC
    $log->info('Updating XBMC Library');
    $xbmc->updateLibrary();
}

exit;
    
