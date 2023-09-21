#!/bin/env perl

use Data::Dumper;
use PlugNPay::InputValidator;

my $iv = new PlugNPay::InputValidator();
$iv->changeContext('payscreens');

my $iv2 = new PlugNPay::InputValidator();
$iv2->changeContext('idontexist');

my %hash = (
  'months' => 'te2st'
);

print Dumper \%hash;
my %filter = $iv->filterHash(%hash);
print Dumper \%filter;
my $aa = Time::HiRes::time();
$iv->changeContext('global');
%filter = $iv->filterHash(%hash);
print Dumper \%filter;
my $ab = Time::HiRes::time();
$iv->changeContext('payscreens');
my $ac = Time::HiRes::time();
%filter = $iv->filterHash(%hash);
print Dumper \%filter;
print "$aa\n$ab\n$ac\n";
exit;
