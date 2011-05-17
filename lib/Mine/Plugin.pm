package Mine::Plugin;

use strict;
use v5.10;
use Class::Unload;

my %attrs;

sub FETCH_CODE_ATTRIBUTES {
	my ($pkg, $ref) = @_;
	return exists($attrs{$pkg}{$ref}) ? @{$attrs{$pkg}{$ref}} : ();
}

sub MODIFY_CODE_ATTRIBUTES {
	my ($pkg, $ref) = splice @_, 0, 2;
	
	if (@_ && !('EV_SAFE' ~~ @_)) {
		warn $pkg, '::', $ref, " has attributes, but not EV_SAFE";
	}
	$attrs{$pkg}{$ref} = \@_;
	return;
}

sub unload {
	my $pkg = shift;
	
	delete $attrs{$pkg};
	Class::Unload->unload($pkg);
}

1;
