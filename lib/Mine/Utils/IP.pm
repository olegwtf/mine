package Mine::Utils::IP;

use strict;
use Socket;
use base Exporter::;
use autodie qw(:default unpack inet_aton);

our @EXPORT_OK = qw(cidr2long host2long);

sub cidr2long($) {
	my ($cidr) = @_;
	
	my $mask = join('', '1' x $cidr, '0' x (32-$cidr));
	$mask = unpack('N', pack('B*', $mask));
	
	return $mask;
}

sub host2long($) {
	my ($host) = @_;
	
	return unpack('N', inet_aton($host));
}

1;
