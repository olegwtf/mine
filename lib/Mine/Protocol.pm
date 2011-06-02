package Mine::Protocol;

use constant {
	PROTO_MAGIC_DATA      => 0,
	PROTO_MAGIC_AUTH      => 1,
	PROTO_MAGIC_EVENT_RCV => 2,
	PROTO_MAGIC_EVENT_REG => 3,
	PROTO_MAGIC_WAITING   => 4,
	PROTO_AUTH_SUCCESS    => 1,
	PROTO_AUTH_FAILED     => 0,
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
