package Mine::Plugin::CORE;

use strict;
use AnyEvent::Handle;
use AnyEvent::Socket;
use Mine::Protocol;
use Mine::Constants;
use base Mine::Plugin::;

use constant DEBUG => $ENV{MINE_DEBUG}; 

sub send : EV_SAFE {
	my ($stash, $recipient, $event, $datalen, $data, $login, $password) = @_;
	DEBUG && warn "send($stash, $recipient, $event, $datalen, $data, $login, $password)";
	
	my $port;
	if ($recipient =~ /^([^:]+):(\d+)$/) {
		$recipient = $1;
		$port = $2;
	}
	else {
		$port = DEFAULT_PORT;
	}
	
	my $nr = parse_ipv4($recipient); # XXX how about port?
	my $auth_reply = sub {
		my ($handle, $response) = ($_[0], unpack('C', $_[1]));
		DEBUG && warn "send_auth($handle, $response)";
		
		if ($response eq PROTO_AUTH_SUCCESS) {
			if (defined $event) {
				$handle->push_write(pack('CCa*', PROTO_EVENT_SND, length($event), $event));
			}
			
			if (defined $datalen) {
				$handle->push_write(pack('CQ', PROTO_DATA_SND, $datalen));
			}
			
			if (defined $data) {
				$handle->push_write($data);
			}
			
			$handle->{_mine}{ready} = 1;
			
			if (@{$handle->{_mine}{queue}}) {
				my $args = shift @{$handle->{_mine}{queue}};
				Mine::Plugin::CORE::send($stash, $recipient, @$args);
			}
		}
		else {
			$handle->destroy();
		}
	};
	
	my $conn_reply = sub {
		my ($handle, $response) = ($_[0], unpack('C', $_[1]));
		DEBUG && warn "conn_reply($handle, $response)";
		
		if ($response == PROTO_SSL) {
			$handle->starttls('connect');
		}
		
		my $l_len = length $login;
		my $p_len = length $password;
		
		$stash->{handles}{$nr}->push_write(
			my $d = pack("C", $l_len) .
			$login .
			pack("C", $p_len) .
			$password
		);
		
		$stash->{handles}{$nr}->push_read(chunk => 1, $auth_reply);
	};
	
	if(!exists($stash->{handles}{$nr}) || $stash->{handles}{$nr}->destroyed) {
		$stash->{handles}{$nr} = AnyEvent::Handle->new(
			connect => [$recipient, $port],
			on_error => sub {},
			on_eof   => sub {}
		);
		
		$stash->{handles}{$nr}->push_read(chunk => 1, $conn_reply);
		$stash->{handles}{$nr}{_mine}{ready} = 0;
		$stash->{handles}{$nr}{_mine}{queue} = [];
		
	}
	else {
		if ($stash->{handles}{$nr}{_mine}{ready}) {
			$stash->{handles}{$nr}{_mine}{ready} = 0;
			$auth_reply->($stash->{handles}{$nr}, pack('C', PROTO_AUTH_SUCCESS));
		}
		else {
			push @{$stash->{handles}{$nr}{_mine}{queue}}, [$event, $datalen, $data];
		}
	}
}

sub log : EV_SAFE {
	my ($stash, $logpath, $event, $datalen) = @_;
	
	unless (exists $stash->{fh}{$logpath}) {
		open $stash->{fh}{$logpath}, '>>', $logpath;
	}
	
	syswrite($stash->{fh}{$logpath}, "[${\(time)}] $event, $datalen\n");
}

1;
