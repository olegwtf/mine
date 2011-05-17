package Mine::Plugin::CORE;

use strict;
use base Mine::Plugin::;

sub send : EV_SAFE {
	my ($stash) = @_;
}

1;
