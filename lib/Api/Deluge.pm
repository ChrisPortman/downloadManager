#!/usr/bin/env perl

use strict;
use warnings;

package Api::Deluge;

use Carp;
use JSON::RPC::Client;
use Log::Any qw ( $log );
use Data::Dumper;
use JSON::XS;

sub new {
    my $class = shift;
    my %args  = ref $_[0] ? %{$_[0]} : @_;
    
    $class = ref $class || $class;
    my %usableArgs;
    
    #Validate args
    for my $arg ( qw( delugeHost delugePort delugePass ) ) {
        $args{$arg}
          or croak "$class->new() requires $arg\n";
        $usableArgs{$arg} = $args{$arg};
    }
    
    $usableArgs{'callId'} = 1;
    
    my $obj = bless \%usableArgs, $class;
    
    return $obj;
}

sub login {
    my $self = shift;
    my $pass = $self->{'delugePass'};
  
    my %content = (
        'jsonrpc' => '2.0',
        'method'  => 'auth.login',
        'params'  => ["$pass"],
        "id"      => $self->{'callId'}++,
    );
    
    if ( my $result = $self->_callApi( \%content ) ) {
        return 1;
    }
    else {
        $log->error("Deluge API call failed.");
        return;
    }
    
    return;
}

sub getTorrents {    
    my $self = shift;
  
    my %content = (
        'jsonrpc' => '2.0',
        'method'  => 'web.update_ui',
        'params'  => [['name','state','tracker_host','save_path'],{}],
        "id"      => $self->{'callId'}++,
    );
    
    if ( my $result = $self->_callApi( \%content ) ) {
        return wantarray ? %{$result->{'torrents'}} : $result->{'torrents'};
    }
    else {
        $log->error("Deluge API call failed.");
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
    
    my $client     = JSON::RPC::Client->new();
    my $ua         = $client->ua();
    my $can_accept = HTTP::Message::decodable;
    
    $ua->default_header( 'Accept-Encoding' => $can_accept );
    $ua->default_header( 'Cookie' => $self->{'authCookie'} ) if $self->{'authCookie'};
    
    my $pass = $self->{'delugePass'};
    my $host = $self->{'delugeHost'};
    my $port = $self->{'delugePort'};
     
    my $delugeApiUri = 'http://'.$host.':'.$port.'/json';
  
    my $result = $client->call($delugeApiUri, $content);    
    
    #Check the result.
    if($result) {
        if ($result->is_success) {
            my $uaResponse = $result->{'response'};
            my $cookie = $uaResponse->header('set-cookie');
            $self->{'authCookie'} = $cookie if $cookie;
            
            return $result->result();
        }
        else {
            return;
        }
    }
    else {
        $result = $client->status_line;
        unless ( $result and $result =~ /OK/ ) {
            return;
        }
    }
    
    return;
} 


1;
