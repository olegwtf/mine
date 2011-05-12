package Mine::Config::Hosts;

use strict;
use Mine::Utils::IP qw(cidr2long host2long splitbycidr);
use base Mine::Config::;

=head1 NAME

Mine::Config::Hosts - mine hosts config manipulator class. Inherits from Mine::Config

=cut

=head2 new([$cfgpath])

Same as Mine::Config::new(), but in addition tryes to validate config if specified.
Croaks on error. Default config is []

=cut

sub new {
	my ($class, $cfgpath) = @_;
	
	my $self = $class->SUPER::new($cfgpath);
	unless (defined $self->{data}) {
		$self->{data} = [];
	}
	
	$self->validate();
	return $self;
}

=head2 validate()

Validate config. Croaks if config is not valid. Both object and static ways to call
available: Mine::Config::Hosts::validate($not_blessed_ref) and $hosts_cfg->validate()

Valid config forms is:

	[
		h1,
		... # hn could be in form of net/cidr
		hn
	]

=cut

sub validate {
	my ($self) = @_;
	my $cfg = eval{ ref($self) eq 'ARRAY' ? $self : $self->{data} };
	
	Mine::Config::_validate_array_of_scalars($cfg);
}

=head2 load_optimized()

Return config optimized to search ip. All ip converted to long

Format is:

	{
		ip => {
			ipaslong1 => 1,
			...
			ipaslongn => 1
		},
		netmask => [
			ipaslong1,
			maskaslong1,
			...
			ipaslongn,
			maskaslongn
		]
	}

=cut

sub load_optimized {
	my ($self) = @_;
	
	my $cfg = {ip => {}, netmask => []};
	foreach my $elt (@{$self->{data}}) {
		eval {
			if (my ($net, $cidr) = splitbycidr($elt)) {
				$net  = host2long($net);
				$cidr = cidr2long($cidr);
				push @{$cfg->{netmask}}, $net, $cidr;
			}
			else {
				push $cfg->{ip}{host2long($elt)} = 1;
			}
		};
	}
	
	return $self->{optimized} = $cfg;
}

1;
