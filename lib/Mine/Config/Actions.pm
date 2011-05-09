package Mine::Config::Actions;

use strict;
use v5.10;
use Data::Dumper;
use Mine::Utils::IP qw(cidr2long host2long splitbycidr);
use base Mine::Config::;

=head1 NAME

Mine::Config::Actions - mine actions config manipulator class. Inherits from Mine::Config

=cut 


=head2 $ACTION_MAX_RECURSION_LEVEL = 10

Package variable describing maximum recursion level, when validating action arguments
to prevent deep recursion.

=cut

our $ACTION_MAX_RECURSION_LEVEL = 10;

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

=head2 save([$cfgpath])

Same as Mine::Config::save(), but validate config before saving.
Croaks on error.

=cut

sub save {
	my ($self, $cfgpath) = @_;
	
	$self->validate();
	$self->SUPER::save($cfgpath);
}

=head2 validate()

Validate config. Croaks if config is not valid. Both object and static ways to call
available: Mine::Config::Actions::validate($not_blessed_ref) and $actions_cfg->validate()

Valid config form is:

	(root)   (action and conditions)
	array -> hash -> {
		host  => [h1, ..., hn], # optional, hn may be in form of net/cidr
		user  => [u1, ..., un], # optional
		event => [e1, ..., en], #optional
		action => [ # array of actions
			{                                                       <-----------------|
				'Plugin::method': null, # call method from Plugin without arguments   |
				'Plugin::method', [ # with arguments                                  | # same
					arg1, # scalar argument                                           |
					{	# argument may be a hash (method call inside method call) -----
						
					}
				]
			}
		]
	}

=cut

sub validate {
	my ($self) = @_;
	my $cfg = eval{ ref($self) eq 'ARRAY' ? $self : $self->{data} };
	
	ref($cfg) eq 'ARRAY'
		or die 'validate(): ARRAY expected. Have: ', Dumper($cfg);
	
	foreach my $entry (@$cfg) {
		ref($entry) eq 'HASH'
			or die 'validate(): OBJECT expected. Have: ', Dumper($entry);
		
		while (my ($key, $value) = each(%$entry)) {
			given ($key) {
				when (['sender', 'user', 'event']) {
					Mine::Config::_validate_array_of_scalars($value);
				}
				when ('action') {
					ref($value) eq 'ARRAY'
						or die 'validate(): ARRAY expected. Have: ', Dumper($value);
						
					foreach my $e (@$value) {
						ref($e) eq 'HASH'
							or die 'validate(): OBJECT expected. Have: ', Dumper($e);
							
						_validate_action($e, 1);
					}
				}
				default {
					die 'validate(): Invalid option `', $key, '\', rtfm';
				}
			}
		}
	}
	
	1;
}

# part of validate(): validate action hash parameter using recursion
sub _validate_action($$) {
	my ($action, $recur_level) = @_;
	
	if ($recur_level > $ACTION_MAX_RECURSION_LEVEL) {
		die 'validate(): Action max recursion level exceed';
	}
	
	while (my ($func, $arg) = each %$action) {
		$func =~ /[a-z]+::[a-z]+/i
			or die 'validate(): Invalid function name `', $func, '\', should be Plugin::method';
		
		my $ref = ref($arg);
		if ($ref && !($ref ~~ ['ARRAY', 'JSON::XS::Boolean'])) {
			die 'validate(): ARRAY or SCALAR expected. Have: ', Dumper($arg);
		}
		
		if ($ref eq 'ARRAY') {
			foreach my $elt (@$arg) {
				$ref = ref($elt);
				if ($ref && !($ref ~~ ['HASH', 'JSON::XS::Boolean'])) {
					die 'validate(): HASH or SCALAR expected. Have: ', Dumper($elt);
				}
				
				if ($ref eq 'HASH') {
					_validate_action($elt, $recur_level + 1);
				}
			}
		}
	}
	
	1;
}

=head2 get_optimized()

Return config optimized to easy search of the action by host, user and event

Returned config form will be:

	{
		senders => {
			s1 => [act1, ..., actn], # act: {action => hashreftoact, condcnt => numberofconditions}
			...
			s2 => [act1, ..., actn]
		},
		users => {
			u1 => [act1, ..., actn],
			...
			un => [act1, ..., actn]
		},
		events => {
			e1 => [act1, ..., actn],
			...
			en => [act1, ..., actn]
		},
		netmask => [net1, mask1, act1, ..., netn, maskn, actn],
		actions => [act1, ..., actn] # actions that have no conditions
	}

=cut

sub get_optimized {
	my ($self) = @_;
	
	my $cfg = {
		senders => {},
		users   => {},
		events  => {},
		netmask => [],
		actions => [],
	};
	
	foreach my $entry (@{$self->{data}}) {
		next unless exists $entry->{action};
		
		my $conditions = 0;
		$conditions++ if exists $entry->{sender};
		$conditions++ if exists $entry->{user};
		$conditions++ if exists $entry->{event};
		
		unless($conditions) {
			push @{$cfg->{actions}}, $entry->{action};
			next;
		}
		
		my $action = {action => $entry->{action}, condcnt => $conditions};
		
		if (exists $entry->{sender}) {
			foreach my $elt (@{$entry->{sender}}) {
				eval {
					if (my ($net, $cidr) = splitbycidr($elt)) {
						# net + cidr form
						$net  = host2long($net);
						$cidr = cidr2long($cidr);
						push @{$cfg->{netmask}}, $net, $cidr, $action;
					}
					else {
						$elt = host2long($elt);
						push @{$cfg->{senders}{$elt}}, $action;
					}
				};
			}
		}
		if (exists $entry->{user}) {
			foreach my $elt (@{$entry->{user}}) {
				push @{$cfg->{users}{$elt}}, $action;
			}
		}
		if (exists $entry->{event}) {
			foreach my $elt (@{$entry->{event}}) {
				push @{$cfg->{events}{$elt}}, $action;
			}
		}
	}
	
	return $cfg;
}

1;
