package Mine::Config;

use strict;
use JSON::XS;
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
		open my $fh, $cfgpath;
		my $json = <$fh>;
		close $fh;
		
		$self->{data} = decode_json($json);
	}
	
	bless $self, $class;
}

=head2 save([$cfgpath])

Saves config to specified $cfgpath or path specified in the constructor.
At least one should be specified. If path in the constructor was not specified
$cfgpath becomes default path. Croaks on error.

=cut

sub save {
	my ($self, $cfgpath) = @_;
	
	croak 'save(): path not known'
		unless defined($cfgpath) || defined($self->{cfgpath});
	
	unless (defined $self->{cfgpath}) {
		$self->{cfgpath} = $cfgpath;
	}
	
	open my $fh, '>', $cfgpath || $self->{cfgpath};
	my $json = encode_json($self->{data});
	syswrite($fh, $json);
	close $fh;
}

1;
