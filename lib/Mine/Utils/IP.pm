package Mine::Utils::IP;

use strict;
use Socket;
use base Exporter::;
use autodie qw(:default unpack inet_aton);

=head1 NAME

Mine::Utils::IP - some utilities to manipulate ip addresses

=cut

=head1 EXPORT

All functions below on request

=cut

our @EXPORT_OK = qw(cidr2long host2long splitbycidr);

=head2 cidr2long($cidr)

Returns cidr (in 10.0.0.0/24 24 is cidr) converted to unsigned long.
Croaks on fail.

=cut

sub cidr2long($) {
	my ($cidr) = @_;
	
	my $mask = join('', '1' x $cidr, '0' x (32-$cidr));
	$mask = unpack('N', pack('B*', $mask));
	
	return $mask;
}

=head2 host2long($host)

Return host which can be ip or hostname converted to unsigned long.
Croaks on fail.

=cut

sub host2long($) {
	my ($host) = @_;
	
	return unpack('N', inet_aton($host));
}

=head2 splitbycidr($netandcidr)

Returns list of net and cidr if $netandcidr contanins net and cidr.
Otherwise returns false.

=cut

sub splitbycidr($) {
	my ($netandcidr) = @_;
	
	my ($net, $cidr) = $netandcidr =~ m!(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/(\d+)!)
		or return;
		
	return ($net, $cidr);
}

1;
