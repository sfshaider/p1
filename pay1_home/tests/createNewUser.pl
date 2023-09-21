#!/bin/env perl

use strict;
use lib '/home/pay1/perl_lib';
use PlugNPay::Username;

my $username = $ARGV[0];

my $user = new PlugNPay::Username();
$user->setUsername($username);
$user->setGatewayAccount($username);
$user->setSecurityLevel(0);
$user->addAccess('/admin');
$user->setPassword('P@ssword1');
print $user->saveUsername() . "\n";

exit;
