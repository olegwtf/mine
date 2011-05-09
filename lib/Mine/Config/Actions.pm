package Mine::Config::Actions;

use strict;
use v5.10;
use Mine::Utils::IP qw(cidr2long host2long);
use base Mine::Config::;

=head1 NAME

Mine::Config::Actions - mine actions config manipulator class

=cut 


=head2 $ACTION_MAX_RECURSION_LEVEL = 10

Package variable describing maximum recursion level, when validating action arguments
to prevent deep recursion.

=cut

our $ACTION_MAX_RECURSION_LEVEL = 10;

=head2 new([$cfgpath])

Same as Mine::Config::new(), but in addition tryes to validate config if specified.
Croaks on error

=cut

sub new {
	my ($class, $cfgpath) = @_;
	
	my $self = $class->SUPER::new($cfgpath);
	unless (defined $self->{data}) {
		$self->{data} = [];
	}
	
	$self->validate();
	$self->_make_internal();
	
	return $self;
}

=head2 new_from_default([$cfgpath])

Same as new, but not load config even if $cfgpath specified. Loads default config
instead. Default config for actions is empty array: []

=cut

sub new_from_default {
	my ($class, $cfgpath) = @_;
	
	my $self = $class->new();
	$self->{cfgpath} = $cfgpath;
	
	return $self;
}

=head2 save([$cfgpath])

Same as Mine::Config::save().

=cut

sub save {
	my ($self, $cfgpath) = @_;
	
	$self->_make_external();
	$self->validate();
	$self->SUPER::save($cfgpath);
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
		netmask => [net1, mask1, act1, ..., netn, maskn, actn]
	}

=cut

sub get_optimized {
	my ($self) = @_;
	
	my $cfg = {
		senders => {},
		users   => {},
		events  => {},
		netmask => [],
	};
	
	foreach my $entry (@{$self->{data}}) {
		next unless exists $entry->{action};
		
		my $conditions = 0;
		$conditions++ if exists $entry->{sender};
		$conditions++ if exists $entry->{user};
		$conditions++ if exists $entry->{event};
		
		next unless $conditions;
		my $action = {action => $entry->{action}, condcnt => $conditions};
		
		if (exists $entry->{sender}) {
			foreach my $elt (@{$entry->{sender}}) {
				if (my ($net, $cidr) = $elt =~ m!(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/(\d+)!) {
					# net + cidr form
					eval {
						$net  = host2long($net);
						$cidr = cidr2long($cidr);
						push @{$cfg->{netmask}}, $net, $cidr, $action;
					};
				}
				else {
					push @{$cfg->{senders}{$elt}}, $action;
				}
			}
		}
		if (exists $entry->{user}) {
			foreach my $elt (@{$cfg->{users}}) {
				push @{$cfg->{users}{$elt}}, $action;
			}
		}
		if (exists $entry->{event}) {
			foreach my $elt (@{$cfg->{events}}) {
				push @{$cfg->{events}{$elt}}, $action;
			}
		}
	}
	
	return $cfg;
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
		or die 'validate(): Invalid root element. Should be ARRAY []';
	
	foreach my $entry (@$cfg) {
		ref($entry) eq 'HASH'
			or die 'validate(): Invalid element on second level. Should be OBJECT {}';
		
		while (my ($key, $value) = each(%$entry)) {
			given ($key) {
				when (['sender', 'user', 'event']) {
					ref($value) eq 'ARRAY'
						or die 'validate(): Invalid element with key `', $key, '\'. Should be ARRAY []';
						
					foreach my $e (@$value) {
						ref($e)
							and die 'validate(): Invalid element in the ARRAY with key `', $key, '\'. Should be SCALAR';
					}
				}
				when ('action') {
					ref($value) eq 'ARRAY'
						or die 'validate(): Invalid element with key `', $key, '\'. Should be ARRAY []';
						
					foreach my $e (@$value) {
						ref($e) eq 'HASH'
							or die 'validate(): Invalid action element. Should be OBJECT {}';
							
						_validate_action($e, 0);
					}
				}
				default {
					die 'validate(): Invalid option `', $key, '\', rtfm';
				}
			}
		}
	}
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
		
		if (ref($arg) && ref($arg) ne 'ARRAY') {
			die 'validate(): Invalid element in action with function `', $func, '\'. Should be ARRAY or SCALAR';
		}
		
		if (ref($arg)) {
			foreach my $elt (@$arg) {
				if (ref($elt) && ref($elt) ne 'HASH') {
					die 'validate(): Invalid element in action arguments with function `', $func, '\'. Should be ARRAY or SCALAR';
				}
				
				if (ref($elt)) {
					_validate_action($elt, $recur_level + 1);
				}
			}
		}
	}
}

1;
