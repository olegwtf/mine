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
$json = '{"bind_port": 85}';
ok(eval{Mine::Config::Main->new(\$json)}, "Minimal correct config: $json")
	or diag $@;
# incorrect bind port
$json = '{"bind_port": 90000}';
like(eval{Mine::Config::Main->new(\$json)}||$@, qr/65536/, "Too big `bind_port': $json")
	or diag $@;
$json = '{"bind_port": "port"}';
like(eval{Mine::Config::Main->new(\$json)}||$@, qr/numeric/, "Not numeric `bind_port': $json")
	or diag $@;
# complete correct config
$json = <<JSON;
{
	"bind_port": 90,
	"bind_address": "192.168.0.1",
	"ssl": false,
	"ipauth": true
}
JSON
ok(eval{Mine::Config::Main->new(\$json)}, "Complete correct config: $json")
	or diag $@;
# number instead of boolean
$json = '{"ssl":"bool", "bind_port":30}';
like(eval{Mine::Config::Main->new(\$json)}||$@, qr/true or false/, "Not boolean `ssl' value: $json")
	or diag $@;

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
