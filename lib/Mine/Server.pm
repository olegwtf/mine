package Mine::Server;

use strict;
use v5.10;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Digest::MD5 qw(md5_hex);
use Mine::Config::Main;
use Mine::Config::Actions;
use Mine::Config::Users;
use Mine::Utils::IP qw(host2long ip_belongs_net);
use Mine::Constants;
use Mine::Protocol;
use Mine::PluginManager;

=head1 NAME

Mine::Server - Mine server class (singleton)

=cut

=head1 ENVIRONMENT

=over

=item MINE_DEBUG

=back

=cut

use constant DEBUG => $ENV{MINE_DEBUG};

# some prototypes
sub _($);

# We are Singleton
my $self;

=head1 METHODS

=head2 new()

=cut

sub new {
	my ($class, %cfg) = @_;
	
	return $self if $self;
	$self = {};
	
	# load configs
	foreach my $name qw(main actions users) {
		my $class = 'Mine::Config::' . ucfirst($name);
		
		eval {
			$self->{cfg}{$name} = $class->new($cfg{$name});
		};
		if ($@) {
			warn $name, ".cfg: ", $@;
			warn $name, ".cfg: using default";
			$self->{cfg}{$name} = $class->new_from_default($cfg{$name});
		}
	}
	
	$self->{cfg}{actions}->load_optimized();
	
	# load hosts config if auth by ip allowed
	if ($self->{cfg}{main}{data}{ipauth}) {
		require Mine::Config::Hosts;
		
		eval {
			$self->{cfg}{hosts} = Mine::Config::Hosts->new($cfg{hosts});
		};
		if ($@) {
			warn "hosts.cfg: ", $@;
			warn "hosts.cfg: using default";
			$self->{cfg}{hosts} = Mine::Config::Hosts->new_from_default($cfg{hosts});
		}
		
		$self->{cfg}{hosts}->load_optimized();
	}
	
	$self->{plugins} = Mine::PluginManager->new();
	
	bless $self, $class;
}

=head2 start()

Start the server

=cut

sub start {
	tcp_server(
		$self->{cfg}{main}{data}{bind_address},
		$self->{cfg}{main}{data}{bind_port},
		\&_cb_accept
	);
	
	$self->{loop} = AnyEvent->condvar;
	$self->{loop}->recv;
}


#### callbacks ####

=head1 PROTOCOL

=head2 Accepting connections

After client connection server sends to client connection
type 1 byte longwithout any encryption. Connection type can be
PROTO_SSL or PROTO_PLAIN. If connection type is PROTO_SSL then server
starts ssl handshaking, so client should start ssl handshaking
too:

  +--------------------------+
  |            1             |
  +--------------------------+
  | PROTO_SSL or PROTO_PLAIN |
  +--------------------------+

=cut

sub _cb_accept {
	my ($sock, $host) = @_;
	
	my @conn_opts;
	if ($self->{cfg}{main}{data}{ssl}) {
		push(
			@conn_opts, pack('C', PROTO_SSL),
			tls => 'accept',
			tls_ctx => {cert_file => CERT_PATH . '/mine.crt', key_file => CERT_PATH . '/mine.key'}
		);
	}
	else {
		push @conn_opts, pack('C', PROTO_PLAIN);
	}
	
	# XXX: Could this write fail somewhere?
	# NOTE: Socket is non-blocking
	# write connection type directly and plain
	syswrite($sock, shift @conn_opts);
	# for other operations will create handle
	# for more easy interact. Possibly with ssl
	my $handle = AnyEvent::Handle->new(
		fh => $sock,
		@conn_opts,
		on_read  => \&_cb_read,
		on_eof   => \&_cb_eof,
		on_error => \&_cb_error
	);
	$handle->{_mine}{state} = PROTO_AUTH;
	$handle->{_mine}{host} = host2long($host);
	$self->{handles}{_$handle} = $handle; # see sub _($)
}

sub _cb_read {
	my ($handle) = @_;
	
	given ($handle->{_mine}{state}) {
		when (PROTO_WAITING) {
			my $state = unpack('C', _strshift($handle->{rbuf}));
			
			$handle->{_mine}{state} = $state;
			goto &_cb_read if length $handle->{rbuf} > 0;
		}

=head2 Authorization

Right after connection client should send username and password.
Username and passsword could be empty:

  +------------+------+-------+------+-------+
  |     1      |   1  | 0-255 |   1  | 0-255 |
  -------------+------+-------+------+-------+
  | PROTO_AUTH | ulen | user  | plen | pass  |
  +------------+------+-------+------+-------+

Server response contains information about login success or fail.
If login failed server immediately close connection:

  +-----------------------------------------+
  |                   1                     |
  +-----------------------------------------+
  | PROTO_AUTH_SUCCESS or PROTO_AUTH_FAILED |
  +-----------------------------------------+

If authorization by ip enabled and client ip marked as allowed
server must admit such client.

=cut
		when (PROTO_AUTH) {
			unless (exists $handle->{_mine}{user}) {
				# reading username
				my $ulen = unpack('C', $handle->{rbuf});
				
				if ($ulen == 0) {
					# anonymous
					$handle->{_mine}{user} = '';
				}
				elsif (length($handle->{rbuf}) > $ulen) {
					# username
					_strshift($handle->{rbuf});
					$handle->{_mine}{user} = _strshift($handle->{rbuf}, $ulen);
				}
			}
			
			if (length($handle->{rbuf}) > 0) {
				my $plen = unpack('C', $handle->{rbuf});
				
				if ($plen == 0) {
					# anonymous
					$handle->{_mine}{password} = '';
				}
				elsif (length($handle->{rbuf}) > $plen) {
					# password
					_strshift($handle->{rbuf});
					$handle->{_mine}{password} = _strshift($handle->{rbuf}, $plen);
				}
				else {
					# still not authorized
					return;
				}
				
				if (_can_auth($handle->{_mine}{host}, $handle->{_mine}{user}, $handle->{_mine}{password})) {
					$handle->push_write(pack('C', PROTO_AUTH_SUCCESS));
					$handle->{_mine}{state} = PROTO_WAITING;
				}
				else {
					$handle->push_write(pack('C', PROTO_AUTH_FAILED));
					delete $self->{handles}{_$handle};
					$handle->destroy();
				}
			}
		}

=head2 Event registration

Client could register the event it wants to receive
from the server:

  +-----------------+------+-------+-----+
  |         1       |  1   | 1-255 |  4  |
  +-----------------+------+-------+-----+
  | PROTO_EVENT_REG | elen | event |  ip |
  +-----------------+------+-------+-----+

Ip could be "0.0.0.0" that means "any ip". Server will
resent event and data to clients in the same format it
receivs from clients.

=cut
		when (PROTO_EVENT_REG) {
			my $elen = unpack('C', $handle->{rbuf});
			
			if (length($handle->{rbuf}) > $elen+4) {
				my (undef, undef, $event, $ip) = 
					unpack('C2a'.$elen.'a4', _strshift($handle->{rbuf}, $elen+5));
					
				my $key = $ip.$event;
				$self->{waiting}{$key}{_$handle} = $handle;
				$self->{handles}{_$handle} = $key;
				$handle->{_mine}{state} = PROTO_WAITING;
			}
		}

=head2 Event receiving

Event from the client format should be:

  +------+--------+
  |   1  |  1-255 |
  +------+--------+
  | elen |  event |
  +------+--------+

After that actions associated with this event in the config will be
invoked througn L<Mine::PluginManager|Mine::PluginManager> class.
Special arguments state:

=over

=item $EVENT = event

=item $DATALEN = undef

=item $DATA = undef

=back

Event will be resent to all subscribers except sender.

=cut
		when (PROTO_EVENT_RCV) {
			my $elen = unpack('C', $handle->{rbuf});
			if (length($handle->{rbuf}) > $elen) {
				_strshift($handle->{rbuf});
				$handle->{_mine}{event} = _strshift($handle->{rbuf}, $elen);
				$handle->{_mine}{state} = PROTO_WAITING;
				
				_resend_event($handle);
				_do_actions($handle, $handle->{_mine}{event});
			}
		}

=head2 Event data receiving

After event client could send data:

  +----------------+------+--------------------------+
  |        1       |   8  |   0-18446744073709551615 |
  +----------------+------+--------------------------+
  | PROTO_DATA_SND | dlen |           data           |
  +----------------+------+--------------------------+

All actions associated with event will be invoked all time
wile new chunk of data will be available.
Special arguments state:

=over

=item $EVENT = undef

=item $DATALEN = dlen (if first call) or undef

=item $DATA = data or undef (if no data available, but only dlen)

=back

Event data will be resent to all subscribers except sender.

=cut
		when (PROTO_DATA_RCV) {
			my @specvars = (undef);
			if (!$handle->{_mine}{datalen}) {
				$handle->{_mine}{datalen} = unpack('Q', _strshift($handle->{rbuf}, 8));
				push @specvars, $handle->{_mine}{datalen};
			}
			else {
				push @specvars, undef;
			}
			
			if ((my $buflen = length($handle->{rbuf})) > 0) {
				my $bytes = $buflen > $handle->{_mine}{datalen} ? $handle->{_mine}{datalen} : $buflen;
				push @specvars, _strshift($handle->{rbuf}, $bytes);
				unless ($handle->{_mine}{datalen} -= $bytes) {
					$handle->{_mine}{state} = PROTO_WAITING; # all data received
				}
			}
			else {
				push @specvars, undef;
			}
			
			_resend_data($handle, @specvars[1,2]);
			_do_actions($handle, @specvars);
		}
	}
}

sub _cb_eof {
	my ($handle) = @_;
}

sub _cb_error {
	my ($handle, $fatal, $message) = @_;
}

#### other routines ####
sub _can_auth($$$) {
	my ($host, $login, $password) = @_;
	DEBUG && warn "_can_auth($host, $login, $password)";
	
	if ($login && $self->{cfg}{users}{data}{$login} eq md5_hex($password)) {
		# auth by password ok
		return 1;
	}
	
	unless ($self->{cfg}{main}{data}{ipauth}) {
		# authorization by ip disabled
		return 0;
	}
	
	if (exists $self->{cfg}{main}{optimized}{ip}{$host}) {
		# auth by ip ok
		return 1;
	}
	
	my $netmask = $self->{cfg}{main}{optimized}{netmask};
	for (my $i=0, my $l=@$netmask; $i<$l; $i+=2) {
		if (ip_belongs_net($host, $netmask->[$i], $netmask->[$i+1])) {
			return 1;
		}
	}
	
	return 0;
}

sub _resend_event($) {
	my $handle = shift;
	
	foreach my $key (
		pack('Na*', $handle->{_mine}{host}, $handle->{_mine}{event}), # ip + event
		"\0\0\0\0" . $handle->{_mine}{event}                          # any_ip + event
	) {
		if (exists $self->{waiting}{$key}) {
			while (my (undef, $w_handle) = each %{$self->{waiting}{$key}}) {
				if ($w_handle != $handle) {
					$w_handle->push_write(pack('Ca*', PROTO_EVENT_SND, $handle->{_mine}{event}));
				}
			}
		}
	}
}

sub _resend_data($$$) {
	my $handle = shift;
	
	foreach my $key (
		pack('Na*', $handle->{_mine}{host}, $handle->{_mine}{event}), # ip + event
		"\0\0\0\0" . $handle->{_mine}{event}                          # any_ip + event
	) {
		if (exists $self->{waiting}{$key}) {
			while (my (undef, $w_handle) = each %{$self->{waiting}{$key}}) {
				if ($w_handle != $handle) {
					if ($_[0]) { # datalen
						$w_handle->push_write(pack('CQ'), PROTO_DATA_SND, $_[0]);
					}
					
					if ($_[1]) { # data
						$w_handle->push_write($_[1]);
					}
				}
			}
		}
	}
}

sub _do_actions($@) {
	my $handle = shift;
	
	my @actions_array;
	if (my $act_sender = $self->{cfg}{actions}{optimized}{senders}{$handle->{_mine}{host}}) {
		push @actions_array, [@$act_sender];
	}
	if (my $act_user = $self->{cfg}{actions}{optimized}{users}{$handle->{_mine}{user}}) {
		push @actions_array, [@$act_user];
	}
	if (my $act_event = $self->{cfg}{actions}{optimized}{events}{$handle->{_mine}{event}}) {
		push @actions_array, [@$act_event];
	}
	my $netmask = $self->{cfg}{actions}{optimized}{netmask};
	
	my @acting;
	my ($i, $j) = (0, 0);
	foreach my $actions (@actions_array) {
		foreach my $action (@$actions) {
			my $cond = $action->{condcnt} - 1;
			for ($j=$i; $cond>0, $j<@actions_array; $j++) {
				if ((my $index = _arrayindex($actions_array[$j], $action)) != -1) {
					$cond--;
					splice @{$actions_array[$j]}, $index, 1; # delete used action
				}
			}
			
			if ($cond > 0) {
				for ($j=0; $j<@$netmask; $j+=3) {
					if ($action == $netmask->[$j+2] &&
						ip_belongs_net($handle->{_mine}{host}, $netmask->[$j], $netmask->[$j+1])) {
						$cond--;
						last;
					}
				}
			}
			
			if ($cond <= 0) {
				push @acting, $action->{action};
			}
		}
		
		$i++;
	}
	
	foreach my $act (@acting, @{$self->{cfg}{actions}{optimized}{actions}}) {
		$self->{plugins}->act($handle->{_mine}{stash}, $act, @_);
	}
}

sub _($) {
	substr($_[0], 22, -1);
}

sub _strshift($$) {
	my $rv = substr($_[0], 0, defined($_[1]) ? $_[1] : 1)
		if defined wantarray();
		
	substr($_[0], 0, defined($_[1]) ? $_[1] : 1) = '';
	$rv;
}

sub _arrindex($$) {
	my ($array, $elt) = @_;
	
	my $i = 0;
	foreach my $e (@$array) {
		if ($e eq $elt) {
			return $i;
		}
		$i++;
	}
	
	return -1;
}

1;
