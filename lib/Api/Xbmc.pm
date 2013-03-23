#!/usr/bin/env perl

use strict;
use warnings;

package Api::Xbmc;

use Carp;
use JSON::RPC::Client;
use Log::Any qw ( $log );

sub new {
    my $class = shift;
    my %args  = ref $_[0] ? %{$_[0]} : @_;
    
    $class = ref $class || $class;
    my %usableArgs;
    
    #Validate args
    for my $arg ( qw( xbmcHost xbmcPort xbmcUser xbmcPass ) ) {
        $args{$arg}
          or croak "$class->new() requires $arg\n";
        $usableArgs{$arg} = $args{$arg};
    }
    
    my $obj = bless \%usableArgs, $class;
    
    return $obj;
}

sub updateLibrary {    
    my $self = shift;
  
    my %content = (
        'jsonrpc' => '2.0',
        'method'  => 'VideoLibrary.Scan',
        'params'  => {},
    );
    
    if ( $self->_callApi( \%content ) ) {
        $log->info("\tLibrary update successful.");
        return 1;
    }
    else {
        $log->error("\tLibrary update failed.");
        return;
    }
    
    return;
}

sub _callApi {
    my $self    = shift;
    my $content = ref $_[0] ? shift : { @_ };
    
    unless ( ref $content and ref $content eq 'HASH' ) {
        die "Content must be a hash ref for _callApi.\n";
    }
    
    my $client = JSON::RPC::Client->new();
    
    my $user = $self->{'xbmcUser'};
    my $pass = $self->{'xbmcPass'};
    my $host = $self->{'xbmcHost'};
    my $port = $self->{'xbmcPort'};
     
    my $xbmcApiUri = 'http://'.$user.':'.$pass.'@'.$host.':'.$port.'/jsonrpc';
  
    my $result = $client->call($xbmcApiUri, $content);    
    
    #Check the result.
    if($result) {
        if ($result->is_error) {
            return;
        }
    }
    else {
        $result = $client->status_line;
        unless ( $result and $result =~ /OK/ ) {
            return;
        }
    }
    
    return 1;
} 


1;
