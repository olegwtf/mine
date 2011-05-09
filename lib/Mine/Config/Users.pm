package Mine::Config::Users;

use strict;
use base Mine::Config::;

=head1 NAME

Mine::Config::Users - mine users config manipulator class. Inherits from Mine::Config

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
available: Mine::Config::Users::validate($not_blessed_ref) and $users_cfg->validate()

Valid config forms is:

	{
		user1: password1,
		...
		usern: passwordn
	}

=cut

sub validate {
	my ($self) = @_;
	my $cfg = eval{ ref($self) eq 'HASH' ? $self : $self->{data} };
	
	_validate_hash_of_scalars($cfg);
}

1;
