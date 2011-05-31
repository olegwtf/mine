package Mine::Constants;

use constant {
	CONFIG_PATH  => 'tmp/cfg',
	CERT_PATH    => 'tmp/cert',
	DEFAULT_PORT => 1135,
};

sub import {
	my $caller = caller;
	
	while (my ($name, $symbol) = each %{__PACKAGE__ . '::'}) {
		if (ref $symbol) {
			# only constants
			${$caller . '::'}{$name} = $symbol;
		}
	}
}

1;
