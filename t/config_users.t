#!/usr/bin/env perl

use Test::More;
BEGIN {
	use_ok('Mine::Config::Users');
}
use strict;

# new
my $cfg;
$cfg = Mine::Config::Users->new();
ok(defined $cfg, 'new()');
isa_ok($cfg, 'Mine::Config::Users');

# new_from_default
$cfg = Mine::Config::Users->new_from_default();
ok(defined $cfg, 'new_from_default()');
isa_ok($cfg, 'Mine::Config::Users');

# config
my $json;
# minimal valid
$json = '{}';
ok(eval{ Mine::Config::Users->new(\$json) }, "Minimal valid config: $json")
	or diag $@;
# more complete
$json = <<JSON;
	{
		"user1": "password1",
		"user2": "password2",
		"user3": "password3"
	}
JSON
ok(eval{ Mine::Config::Users->new(\$json) }, "More complete valid config: $json")
	or diag $@;
	
# simple invalid config
$json = '[]';
ok(!eval{ Mine::Config::Users->new(\$json) }, "Minimal invalid config: $json");
# more complete invalid config
$json = <<JSON;
	{
		"user1": "password1",
		"user2": ["password2", "password3", "passowrd4"],
		"user3": "password3"
	}
JSON
ok(!eval{ Mine::Config::Users->new(\$json) }, "More complete invalid config: $json");

# saving invalid data config
like(
	eval {
		$cfg = Mine::Config::Users->new_from_default(\$json);
		$cfg->{data} = [];
		$cfg->save();
	} || $@,
	qr/validate/i,
	'Saving incorrect config'
) or diag $@;

done_testing();
