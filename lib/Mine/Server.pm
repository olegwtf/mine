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

use constant {
	STATE_AUTH      => 1,
	STATE_EVENT_RCV => 2,
	STATE_EVENT_REG => 3,
	STATE_WAITING   => 4,
};

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
	$handle->{_mine}{state} = STATE_AUTH;
	$handle->{_mine}{host} = host2long($host);
}

sub _cb_read {
	my ($handle) = @_;
	
	given ($handle->{_mine}{state}) {
		when (STATE_AUTH) {
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
					$handle->{_mine}{state} = STATE_WAITING;
				}
				else {
					$handle->push_write("\00");
					$handle->destroy();
				}
			}
		}
		when (STATE_EVENT_RCV) {
			
		}
		when (STATE_EVENT_REG) {
			
		}
		when (STATE_WAITING) {
			
		}
		default {
			
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
sub _can_auth {
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
	for (my $i=0, $l=@$netmask; $i<$l; $i+=2) {
		if (ip_belongs_net($host, $netmask->[$i], $netmask[$i+1])) {
			return 1;
		}
	}
	
	return 0;
}

sub _strshift {
	my $rv = substr($_[0], 0, defined($_[1]) ? $_[1] : 1)
		if defined wantarray();
		
	substr($_[0], 0, defined($_[1]) ? $_[1] : 1) = '';
	$rv;
}

1;
