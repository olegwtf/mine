package Mine::Server;

use strict;
use v5.10;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Mine::Config::Main;
use Mine::Config::Actions;
use Mine::Config::Users;

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
	my ($sock, $host, $port) = @_;
	
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
	$handle->{_mine_state} = STATE_AUTH;
}

sub _cb_read {
	my ($handle) = @_;
	
	given ($handle->{_mine_state}) {
		when (STATE_AUTH) {
			
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

1;
