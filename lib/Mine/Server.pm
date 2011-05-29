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
use Mine::Protocol;
use Mine::PluginManager;

# some prototypes
sub _($);

# We are Singleton
my $self;

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
sub _cb_accept {
	my ($sock, $host) = @_;
	
	my @conn_opts;
	if ($self->{cfg}{main}{data}{ssl}) {
		push(
			@conn_opts, "\01",
			tls => 'accept',
			tls_ctx => {cert_file => '/tmp/ca.crt', key_file => '/tmp/ca.key'} # XXX
		);
	}
	else {
		push @conn_opts, "\00";
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
	$handle->{_mine}{state} = PROTO_MAGIC_AUTH;
	$handle->{_mine}{host} = host2long($host);
	$self->{handles}{_$handle} = $handle; # see sub _($)
}

sub _cb_read {
	my ($handle) = @_;
	
	given ($handle->{_mine}{state}) {
		when (PROTO_MAGIC_WAITING) {
			my $state = unpack('C', _strshift($handle->{rbuf}));
			given ($state) {
				when (PROTO_MAGIC_EVENT_RCV) {
					$handle->{_mine}{event} = undef;
				}
				when (PROTO_MAGIC_DATA) {
					# continuation of the event data
					$state = PROTO_MAGIC_EVENT_RCV;
				}
				default {
					return;
				}
			}
			
			$handle->{_mine}{state} = $state;
			goto &_cb_read if length $handle->{rbuf} > 0;
		}
		when (PROTO_MAGIC_AUTH) {
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
				
				if (_can_auth($handle->{_mine}{host}, $handle->{_mine}{login}, $handle->{_mine}{password})) {
					$handle->push_write("\01");
					$handle->{_mine}{state} = PROTO_MAGIC_WAITING;
				}
				else {
					$handle->push_write("\00");
					delete $self->{handles}{_$handle};
					$handle->destroy();
				}
			}
		}
		when (PROTO_MAGIC_EVENT_RCV) {
			unless ($handle->{_mine}{event}) {
				my $elen = unpack('C', $handle->{rbuf});
				
				if ($elen == 0) {
					$handle->{_mine}{state} = PROTO_MAGIC_WAITING;
				}
				elsif (length($handle->{rbuf}) > $elen) {
					_strshift($handle->{rbuf});
					$handle->{_mine}{event} = _strshift($handle->{rbuf}, $elen);
					$handle->{_mine}{state} = PROTO_MAGIC_WAITING;
				}
			}
			else {
				unless ($handle->{_mine}{datalen}) {
					if (length($handle->{rbuf}) >= 8) {
						$handle->{_mine}{datalen} = unpack('Q', _strshift($handle->{rbuf}, 8));
					}
				}
				
				if (length($handle->{rbuf}) > 0) {
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
					
					push @acting, @{$self->{cfg}{actions}{optimized}{actions}};
					foreach my $act (@acting) {
						$self->{plugins}->act($handle->{_mine}{stash}, $act);
					}
				}
			}
		}
		when (PROTO_MAGIC_EVENT_REG) {
			my $elen = unpack('C', $handle->{rbuf});
			
			if (length($handle->{rbuf}) > $elen+4) {
				my (undef, undef, $event, $ip) = 
					unpack('C2a'.$elen.'a4', _strshift($handle->{rbuf}, $elen+5));
					
				my $key = $ip.$event;
				$self->{waiting}{$key} = $handle;
				$self->{handles}{_$handle} = $key;
				$handle->{_mine}{state} = PROTO_MAGIC_WAITING;
			}
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
	
	if ($login && $self->{cfg}{users}{data}{$login} eq md5_hex($login)) {
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

sub _($) {
	substr($_[0], 22, -1);
}

sub _strshift($$;$) {
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
