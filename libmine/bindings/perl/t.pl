use ExtUtils::testlib;
use Mine::Lib;
use strict;
use warnings;

my $mine = Mine::Lib->new(autodie => 1);
$mine->connect('localhost', 1135);
$mine->login('root', 'toor');
$mine->event_reg("EV_SUX", "0.0.0.0");
my ($event, $datalen, $data);

while (1) {
	while ((my $rv = $mine->event_recv(\$event, \$datalen, \$data)) >= 0) {
		print "$datalen, $rv, $event, $data\n";
	}
}
