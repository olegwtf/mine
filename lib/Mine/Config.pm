package Mine::Config;

use strict;
use JSON::XS;
use Data::Dumper;
use Carp;
use autodie;

=head1 NAME

Mine::Config - base class to manipulate mine configs

=cut


=head2 new([$cfgpath])

Creates new Mine::Config object with config loaded from specified config path
or empty config if path not specified. Croaks on loading error.

=cut

sub new {
	my ($class, $cfgpath) = @_;
	
	my $self = {};
	if ($cfgpath) {
		$self->{cfgpath} = $cfgpath;
		
		local $/ = undef;
		open my $fh, '<', $cfgpath;
		my $json = <$fh>;
		close $fh;
		
		$self->{data} = decode_json($json);
	}
	
	bless $self, $class;
}

=head2 new_from_default([$cfgpath])

Same as new, but not load config even if $cfgpath specified. Loads default config
instead. Default config is own for each config subclass

=cut

sub new_from_default {
	my ($class, $cfgpath) = @_;
	
	my $self = $class->new();
	$self->{cfgpath} = $cfgpath;
	
	return $self;
}

=head2 save([$cfgpath])

Saves config to specified $cfgpath or path specified in the constructor.
At least one should be specified. If path in the constructor was not specified
$cfgpath becomes default path. If subclass have validate() method, then tryes to
validate first. Croaks on error.

=cut

sub save {
	my ($self, $cfgpath) = @_;
	
	croak 'save(): path not known'
		unless defined($cfgpath) || defined($self->{cfgpath});
		
	if ($self->can('validate')) {
		# subclasses can have validate method
		$self->validate();
	}
	
	unless (defined $self->{cfgpath}) {
		$self->{cfgpath} = $cfgpath;
	}
	
	open my $fh, '>', $cfgpath || $self->{cfgpath};
	my $json = encode_json($self->{data});
	print $fh $json;
	close $fh;
}

#### base validation functions ####
sub _validate_hash_of_scalars($) {
	my ($elt) = @_;
	
	ref($elt) eq 'HASH'
		or die 'validate(): OBJECT expected. Have: ', Dumper($elt);
		
	while (my ($key, $value) = each %$elt) {
		ref($value)
			and die 'validate(): SCALAR expected. Have: ', Dumper($value);
	}
	
	1;
}

sub _validate_array_of_scalars($) {
	my ($elt) = @_;
	
	ref($elt) eq 'ARRAY'
		or die 'validate(): ARRAY expected. Have: ', Dumper($elt);
		
	foreach my $value (@$elt) {
		ref($value)
			and die 'validate(): SCALAR expected. Have: ', Dumper($value);
	}
	
	1;
}

1;
