#!/bin/env perl

use lib '/home/pay1/perl_lib';
use PlugNPay::Job;

my $job = $ENV{'PNP_JOB'};

my $cronRun = new PlugNPay::Job();
$cronRun->setName($job);
$cronRun->load();
my $script = $cronRun->getPath();
print "Running job [$job:$script]\n";
my $error = $cronRun->execute();

if ($error) {
  print "Job [$job:$script] failed with error: $error\n";
} else {
  print "Job [$job:$script] succeeded.\n";
}
