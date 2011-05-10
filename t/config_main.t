#!/usr/bin/env perl

use Test::More;
BEGIN {
	use_ok('Mine::Config::Main');
}
use strict;

# new
my $cfg;
$cfg = Mine::Config::Main->new();
ok(defined $cfg, 'new()');
isa_ok($cfg, 'Mine::Config::Main');

# new_from_default
$cfg = Mine::Config::Main->new_from_default();
ok(defined $cfg, 'new_from_default()');
isa_ok($cfg, 'Mine::Config::Main');

# config
my $json;
# incorrect
$json = '[false]';
ok(!eval{Mine::Config::Main->new(\$json)}, "Incorrect config: $json");
# correct
$json = '{}';
ok(eval{Mine::Config::Main->new(\$json)}, "Correct config: $json")
	or diag $@;

# TODO more format tests

# saving invalid data config
like(
	eval {
		$cfg = Mine::Config::Main->new_from_default(\$json);
		$cfg->{data} = [];
		$cfg->save();
	} || $@,
	qr/validate/i,
	'Saving incorrect config'
) or diag $@;

done_testing();
