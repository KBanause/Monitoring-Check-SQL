#!/usr/bin/env perl
use strict;
use warnings;
use Monitoring::Check::SQL::App;
my $app = Monitoring::Check::SQL::App->new_with_options();
$app->run_exit();
