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

sub act {
	my ($self, $stash, $actions) = splice @_, 0, 3;
	
	my %specvar;
	@specvar{'$EVENT', '$DATALEN', '$DATA'} = \@_[0, 1, 2];
	
	while (my ($sub, $arg) = each %$actions) {
		$self->load( substr($sub, 0, rindex($sub, '::')) );
		$sub = "Mine::Plugin::$sub";
		if ('EV_SAFE' ~~ [attributes::get(\&{$sub})]) {
			$sub->(
				$stash,
				ref($arg) eq 'ARRAY' ?
					map(
						ref($_) eq 'HASH' ?
							$self->act($stash, $_, @_) :
							exists $specvar{$_} ? ${$specvar{$_}} : $_, @$arg
					)
					: exists $specvar{$arg} ? ${$specvar{$arg}} : $arg
			);
		}
	}
}

1;
