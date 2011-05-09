package Mine::Config::Main;

use strict;
use Data::Dumper;
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
		$self->{data} = {}; # FIXME default values
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
available: Mine::Config::Main::validate($not_blessed_ref) and $main_cfg->validate()

Valid config forms is:

	

=cut

sub validate {
	my ($self) = @_;
	my $cfg = eval{ ref($self) eq 'HASH' ? $self : $self->{data} };
	
	ref($cfg) eq 'HASH'
		or die 'validate(): OBJECT expected. Have: ', Dumper($cfg);
	# FIXME incomplete
}

1;
