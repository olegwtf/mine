#!/usr/bin/env perl

use ExtUtils::testlib;
use Mine::Lib;
use strict;
use warnings;


my $mine = Mine::Lib->new(autodie => 1);
$mine->connect('localhost', 1135);
$mine->login('root', 'toor');
my $data = 'NEWS';
$mine->event_send("EV_INFO_IN", length($data), $data);
