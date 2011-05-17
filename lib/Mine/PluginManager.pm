package Mine::PluginManager;

use strict;

sub new {
	my ($class, $stash, @extrainc) = @_;
	my $self = {};
	$self->{extrainc} = \@extrainc;
	$self->{stash}  = $stash;
	$self->{plugins} = {};
	
	bless $self, $class;
}

sub load {
	my $plugin = shift;
	
	if (exists $self->{plugins}{$plugin}) {
		return 1;
	}
	
	local @INC;
	push  @INC, @{$self->{extrainc}}
		if @{$self->{extrainc}};
	
	eval "require Mine::Plugin::$plugin"
		or die $@;
	
	$self->{plugins}{$plugin} = 1;
}

sub unload {
	my $plugin = shift;
	
	unless (exists $self->{plugins}{$plugin}) {
		return 1;
	}
	
	delete $self->{plugins}{$plugin};
	"Mine::Plugin::$plugin"->unload();
}

sub exec {
	my $sub = shift;
	
	"Mine::Plugin::$sub"->($self->{stash}, @_);
}

1;
