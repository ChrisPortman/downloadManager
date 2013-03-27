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
    
    my $obj = bless \%usableArgs, $class;
    $obj->{'rpcClient'} = JSON::RPC::Client->new();
    $obj->{'callId'}    = 1;

    
    $obj->login();
    
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
        if ($result->is_success) {
            $log->debug("Deluge Login success");
            return 1;
        }
        else {
            $log->debug("Deluge Login failed");
            my $error = $result->error_message();
            $self->error($error) if $error;
            return;
        }
    }
    else {
        $log->error("Login: Deluge API call failed.");
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
        if ($result->is_success) {
            $result = $result->result();
            return wantarray ? %{$result->{'torrents'}} : $result->{'torrents'};
        }
        else {
            my $error = $result->error_message();
            $self->error($error) if $error;
            $log->error("GetTorrents: Deluge API call failed: $error.");
            return;
        }
    }

    $log->error("GetTorrents: Deluge API call failed: Unknown error.");
    return;
}

sub removeTorrent {    
    my $self = shift;
    my $id   = shift or croak "removeTorrent() requires a torrent ID\n";
    my $data = shift;
    
    $data = $data ? 1 : 0; #Make a definate bool.
  
    my %content = (
        'jsonrpc' => '2.0',
        'method'  => 'core.remove_torrent',
        'params'  => ["$id", $data],
        "id"      => $self->{'callId'}++,
    );
    
    if ( my $result = $self->_callApi( \%content ) ) {
        if ($result->is_success) {
            return 1;
        }
        else {
            my $error = $result->error_message();
            $self->error($error) if $error;
            return;
        }

        return 1
    }
    else {
        $log->error("RemoveTorrents: Deluge API call failed.");
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
    
    my $client = $self->{'rpcClient'};

    my $pass = $self->{'delugePass'};
    my $host = $self->{'delugeHost'};
    my $port = $self->{'delugePort'};
     
    my $delugeApiUri = 'http://'.$host.':'.$port.'/json';
  
    my $result = $client->call($delugeApiUri, $content);    
    
    #Check the result.
    if($result) {
        unless ($result->is_success) {
            return;
        }

        #Return the full result regardless of error and let the original
        #method determine how to deal with it.
        return $result;
    }
    else {
        $result = $client->status_line;
        unless ( $result and $result =~ /OK/ ) {
            return;
        }
    }
    return;
} 

sub error {
    my $self  = shift;
    my $error = shift;
    
    my $return = $self->{'error'};
    $self->{'error'} = $error;
    
    return $return;
}
    

1;
