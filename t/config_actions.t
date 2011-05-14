#!/usr/bin/env perl

use Test::More;
BEGIN {
	use_ok('Mine::Config::Actions');
}
use strict;

# new
my $cfg;
$cfg = Mine::Config::Actions->new();
ok(defined $cfg, 'new()');
isa_ok($cfg, 'Mine::Config::Actions');

# new_from_default
$cfg = Mine::Config::Actions->new_from_default();
ok(defined $cfg, 'new_from_default()');
isa_ok($cfg, 'Mine::Config::Actions');

# invalid config
my $json;
$json = '{}';
ok(!eval{ Mine::Config::Actions->new(\$json) }, "Invalid config: $json");

# valid config
# minimal
$json = '[]';
ok(eval{ Mine::Config::Actions->new(\$json) }, "Valid config: $json")
	or diag($@);
# complete
$json = <<JSON;
	[
		{
			"sender": ["10.0.0.1", "10.0.0.2", "10.0.0.0/24"],
			"user": ["oleg"],
			"event": ["MSG_IN"],
			"action": [
				{
					"CORE::send": null,
					"CORE::log": ["\$SENDER", "\$EVENT"]
				}
			]
		},
		{
			"action": [
				{
					"Mail::send": ["\$DATA"]
				}
			]
		}
	]
JSON
ok(eval{ Mine::Config::Actions->new(\$json) }, "Valid config:\n$json")
	or diag($@);
	
# invalid json
$json = <<JSON;
	[
		[
			"action": [
				[
					"CORE::send": null,
					"CORE::log": ["\$SENDER", "\$EVENT"]
				]
			]
		]
	]
JSON
ok(!eval{ Mine::Config::Actions->new(\$json) }, "Invalid json:\n$json");

# recursion
$json = <<JSON;
	[
		{
			"event": ["LIGHT_OFF"],
			"action": [
				{
					"Plugin::light": [
						{
							"Plugin::bright": [{
								"Plugin::radiance": false
							}]
						}
					]
				}
			]
		}
	]
JSON
ok(eval{ Mine::Config::Actions->new(\$json) }, "Config with recursion:\n$json")
	or diag($@);
	
# maximum recursion level
$json = <<JSON;
	[
		{
			"event": ["SMT_ELSE"],
			"action": [
				{
					"Plugin::one": [
						{
							"Plugin::two": [{
								"Plugin::three": [{
									"Plugin::four":
									[{
										"Plugin::five":[{
										  "Plugin::six":[{
										    "Plugin::seven":[{
										      "Plugin::eight":[{
										        "Plugin::nine":[{
										          "Plugin::ten": [false, "\$DATA"]
										        }]
										      }]
										    }]
										  }]
										}]
									}]
								}]
							}]
						}
					]
				}
			]
		}
	]
JSON
ok(eval{ Mine::Config::Actions->new(\$json) }, "Config with DEEP recursion:\n$json")
	or diag($@);

# recursion level exceed
$json = <<JSON;
	[
		{
			"event": ["SMT_ELSE"],
			"action": [
				{
					"Plugin::one": [
						{
							"Plugin::two": [{
								"Plugin::three": [{
									"Plugin::four":
									[{
										"Plugin::five":[{
										  "Plugin::six":[{
										    "Plugin::seven":[{
										      "Plugin::eight":[{
										        "Plugin::nine":[{
										          "Plugin::ten": [false, {"Plugin::eleven": null}]
										        }]
										      }]
										    }]
										  }]
										}]
									}]
								}]
							}]
						}
					]
				}
			]
		}
	]
JSON
like(eval{ Mine::Config::Actions->new(\$json) } || $@, qr/recursion/i, "Config recursion level exceed:\n$json" );

# enlarge recursion level
$Mine::Config::Actions::ACTION_MAX_RECURSION_LEVEL++;
ok(eval{ Mine::Config::Actions->new(\$json) }, "Increase recursion level by 1" )
	or diag($@);

# bad function name
$json = <<JSON;
	[{"event": ["LIGHT_OFF"],"action": [{"Plugin:light": null}]}]
JSON
like(eval{ Mine::Config::Actions->new(\$json) } || $@, qr/function\s+name/i, "Invalid function name:\n$json");

# stic::validate()
ok(eval{ Mine::Config::Actions::validate( $cfg->{data} ) }, "validate() as static method")
	or diag($@);

# check value
$json = <<JSON;
	[
	  {
	    "action": [{"Plugin::first": null}]
	  },
	  {
	    "user": ["root", "pinokio"],
	    "action": [{
			"A::b": [{
				"C::d": [8, 10, 12]
			}]
	    }]
	  }
	]
JSON
is(
	eval {
		Mine::Config::Actions->new(\$json)->{data}->[1]->{action}->[0]->{'A::b'}->[0]->{'C::d'}->[-1];
	},
	12,
	'Deep value check'
) or diag $@;

# load_optimized() tests
ok(
	eval {
		$cfg = Mine::Config::Actions->new(\$json);
		my $opt = $cfg->load_optimized();
		$opt->{users}{pinokio}[0]{action} == $cfg->{data}->[1]->{action}
		&&
		$opt->{users}{pinokio}[0]{condcnt} == 1
	},
	'Optimized config check some values'
) or diag $@;

# deep comprasion
$json = <<JSON;
	[
		{
			"sender": ["10.1.0.0/20", "192.168.0.0/12"],
			"event": ["MAMBA", "NUMBA"],
			"action": [
				{
					"A::a": null,
					"B::b": "a"
				}
			]
		},
		{
			"action": [{
				"C::c": null
			}]
		},
		{
			"event": ["NUMBA"],
			"action": [ { "D::d": 5 } ]
		}
	]
JSON
is_deeply(
	eval {
		Mine::Config::Actions->new(\$json)->load_optimized()
	},
	
	{
		senders => {},
		users   => {},
		events  => {
			MAMBA => [
				{
					action => [
						{
							'A::a' => undef,
							'B::b' => 'a'
						}
					],
					condcnt => 2
				}
			],
			NUMBA => [
				{
					action => [
						{
							'A::a' => undef,
							'B::b' => 'a'
						}
					],
					condcnt => 2
				},
				{
					action => [
						{
							'D::d' => 5
						}
					],
					condcnt => 1
				}
			]
		},
		netmask => [
			167837696, 4294963200,
			{
				action => [
					{
						'A::a' => undef,
						'B::b' => 'a'
					}
				],
				condcnt => 2
			},
			3232235520, 4293918720,
			{
				action => [
					{
						'A::a' => undef,
						'B::b' => 'a'
					}
				],
				condcnt => 2
			},
		],
		actions => [
			[
				{
					'C::c' => undef
				}
			]
		],
	},
	
	'Optimized config deep comprasion'
);

# saving test
ok(
	eval {
		$cfg = Mine::Config::Actions->new_from_default(\$json);
		$cfg->{data}[0] = { action => [ { 'A::b' => 11 } ] };
		$cfg->save();
		
		$cfg = Mine::Config::Actions->new(\$json);
		$cfg->{data}[0]{action}[0]{'A::b'} == 11;
	},
	'Saving'
) or diag $@;
# saving invalid data config
$json = '[]';
like(
	eval {
		$cfg = Mine::Config::Actions->new(\$json);
		$cfg->{data}[0] = [];
		$cfg->save();
	} || $@,
	qr/validate/i,
	'Saving incorrect config'
) or diag $@;

done_testing();
