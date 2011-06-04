package Mine::Protocol;

use constant {
	PROTO_PLAIN          => 0,
	PROTO_SSL            => 1,
	PROTO_DATA_RCV       => 0,
	PROTO_DATA_SND       => 0,
	PROTO_AUTH           => 1,
	PROTO_EVENT_RCV      => 2,
	PROTO_EVENT_SND      => 2,
	PROTO_EVENT_REG      => 3,
	PROTO_WAITING        => 4,
	PROTO_AUTH_SUCCESS   => 1,
	PROTO_AUTH_FAILED    => 0,
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
