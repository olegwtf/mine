package Mine::Config::Main;

use strict;
use Data::Dumper;
use Mine::Constants;
use base Mine::Config::;

=head1 NAME

Mine::Config::Main - mine main config manipulator class. Inherits from Mine::Config

=cut

=head2 new([$cfgpath])

Same as Mine::Config::new(), but in addition tryes to validate config if specified.
Croaks on error. Default config is {}

=cut

sub new {
	my ($class, $cfgpath) = @_;
	
	my $self = $class->SUPER::new($cfgpath);
	unless (defined $self->{data}) {
		$self->{data} = {};
	}
	$self->{data}{bind_address} = '0.0.0.0' unless exists $self->{data}{bind_address};
	$self->{data}{bind_port} = DEFAULT_PORT unless exists $self->{data}{bind_port};
	$self->{data}{ssl} = JSON::XS::false    unless exists $self->{data}{ssl};
	$self->{data}{ipauth} = JSON::XS::false unless exists $self->{data}{ipauth};
	
	$self->validate();
	return $self;
}

=head2 validate()

Validate config. Croaks if config is not valid. Both object and static ways to call
available: Mine::Config::Main::validate($not_blessed_ref) and $main_cfg->validate()

Valid config forms is:

	{
		bind_address: 'x.x.x.x',
		bind_port: [0-9]+,
		ssl: true|false
		ipauth: true|false
	}

=cut

sub validate {
	my ($self) = @_;
	my $cfg = eval{ ref($self) eq 'HASH' ? $self : $self->{data} };
	
	ref($cfg) eq 'HASH'
		or die 'validate(): OBJECT expected. Have: ', Dumper($cfg);
	
	exists $cfg->{bind_port}
		or die 'validate(): `bind_port\' is not optional';
	$cfg->{bind_port} =~ /^\d+$/
		or die 'validate(): `bind_port\' should be numeric';
	$cfg->{bind_port} > 0 && $cfg->{bind_port} < 65536
		or die 'validate(): `bind_port\' should be > 0 and < 65536';
	
	exists $cfg->{bind_address} && $cfg->{bind_address} !~ /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/
		and die 'validate(): `bind_address\' should be ipv4 address';
	
	exists $cfg->{ssl} && !JSON::XS::is_bool($cfg->{ssl})
		and die 'validate(): `ssl\' should be true or false';
	
	exists $cfg->{ipauth} && !JSON::XS::is_bool($cfg->{ipauth})
		and die 'validate(): `ipauth\' should be true or false';
}

1;
