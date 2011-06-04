package Mine::Plugin::CORE;

use strict;
use AnyEvent::Handle;
use AnyEvent::Socket;
use Mine::Protocol;
use Mine::Constants;
use base Mine::Plugin::;

sub send : EV_SAFE {
	my ($stash, $recipient, $event, $datalen, $data, $login, $password) = @_;
	
	my $nr = parse_ipv4($recipient);
	my $send_auth = sub {
		my ($handle, $response) = @_;
		
		if ($response eq "\01") {
			if (defined $event) {
				$handle->push_write(pack('CCa*', PROTO_EVENT_SND, length($event), $event));
			}
			
			if (defined $datalen) {
				$handle->push_write(pack('CQ', PROTO_DATA_SND, $datalen));
			}
			
			if (defined $data) {
				$handle->push_write($data);
			}
		}
		else {
			$handle->destroy();
		}
	};
	
	if(!exists($stash->{handles}{$nr}) || $stash->{handles}{$nr}->destroyed) {
		$stash->{handles}{$nr} = AnyEvent::Handle->new(
			connect => [$recipient, DEFAULT_PORT], # FIXME
			on_error => sub {},
			on_eof   => sub {}
		);
		
		my $l_len = length $login;
		my $p_len = length $password;
		
		$stash->{handles}{$nr}->push_write(
			pack("CCa${l_len}Ca${p_len}", PROTO_AUTH, $l_len, $login, $p_len, $password)
		);
		$stash->{handles}{$nr}->push_read(chunk => 1, $send_auth);
	}
	else {
		$send_auth->($stash->{handles}{$nr}, "\01");
	}
}

sub log : EV_SAFE {
	
}

1;
