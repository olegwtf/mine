#!/usr/bin/env perl

use Test::More;
BEGIN {
	use_ok('Mine::Config::Hosts');
}
use strict;

# new
my $cfg;
$cfg = Mine::Config::Hosts->new();
ok(defined $cfg, 'new()');
isa_ok($cfg, 'Mine::Config::Hosts');

# new_from_default
$cfg = Mine::Config::Hosts->new_from_default();
ok(defined $cfg, 'new_from_default()');
isa_ok($cfg, 'Mine::Config::Hosts');

# config
my $json;
# minimal valid
$json = '[]';
ok(eval{Mine::Config::Hosts->new(\$json)}, "Minimal vlid config: $json")
	or diag $@;
# more complete
$json = '["10.0.0.1", "10.0.0.2", "256.192.0.8", "10.10.0.0/20", "10.0.9.3"]';
ok(eval{Mine::Config::Hosts->new(\$json)}, "More complete vlid config: $json")
	or diag $@;
# optimized
is_deeply(
	eval {
		Mine::Config::Hosts->new(\$json)->load_optimized();
	},
	
	{
		ip => {
			167772161 => 1,
			167772162 => 1,
			167774467 => 1,
		},
		netmask => [168427520, 4294963200],
	},
	
	"Optimized config deep comrasion: $json"
);

# saving invalid data config
like(
	eval {
		$cfg = Mine::Config::Hosts->new_from_default(\$json);
		$cfg->{data} = {};
		$cfg->save();
	} || $@,
	qr/validate/i,
	'Saving incorrect config'
) or diag $@;

done_testing();
