package Mine::PluginManager;

use strict;
use v5.10;
use attributes;

sub new {
	my ($class, @extrainc) = @_;
	my $self = {};
	$self->{extrainc} = \@extrainc;
	$self->{plugins} = {};
	
	bless $self, $class;
}

sub load {
	my ($self, $plugin) = @_;
	
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
	my ($self, $plugin) = @_;
	
	unless (exists $self->{plugins}{$plugin}) {
		return 1;
	}
	
	delete $self->{plugins}{$plugin};
	"Mine::Plugin::$plugin"->unload();
}

sub exec {
	my ($self, $stash, $sub) = splice @_, 0, 3;
	
	$self->load( substr($sub, 0, rindex($sub, '::')) );
	$sub = "Mine::Plugin::$sub";
	
	if ('EV_SAFE' ~~ [attributes::get(\&{$sub})]) {
		$sub->($stash, @_);
	}
	else {
		# fork
	}
}

1;
