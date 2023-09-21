#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;
use lib $ENV{'PNP_PERL_LIB'};
use Test::More qw( no_plan );
use PlugNPay::Stats::Query;


sub rangeTestData {
  my $data = {};
  $data->{'data'}{'mode'} = 'auth';
  $data->{'data'}{'currency'} = 'USD';
  $data->{'data'}{'identifier'} = 'dpezella';
  $data->{'data'}{'status'} = 'Failure';

  $data->{'dateRange'} = ['20190914', '20190916'];
  $data->{'type'} = 'range';

  return $data;
}

sub multiTestData {
  my $data = {};

  $data->{'data'}{'mode'} = 'auth';
  $data->{'data'}{'currency'} = 'USD';
  $data->{'data'}{'identifier'} = 'dpezella';
  $data->{'data'}{'status'} = 'Failure';

  $data->{'dateRange'} = ["20190915", "20190911", "20190916", "20190922"];
  $data->{'type'} = 'multi';

  return $data;
}

sub singleTestData {
  my $data = {};

  $data->{'data'}{'mode'} = 'auth';
  $data->{'data'}{'currency'} = 'USD';
  $data->{'data'}{'identifier'} = 'dpezella';
  $data->{'data'}{'status'} = 'Failure';

  $data->{'dateRange'} = ['20190916'];
  $data->{'type'} = 'single';

  return $data;
}

sub getQueryStatsRangeTest {
  my $stat = new PlugNPay::Stats::Query();

  my $data = &rangeTestData();
  $stat->setDates($data->{'type'}, $data->{'dateRange'});
  $stat->addData($data->{'data'});
  my $result = $stat->getQueryStats();
  return ($result->{'status'} eq 'success' ? 1 : 0);
}

sub getQueryStatsMultiTest {
  my $stat = new PlugNPay::Stats::Query();

  my $data = &multiTestData();
  $stat->setDates($data->{'type'}, $data->{'dateRange'});
  $stat->addData($data->{'data'});
  my $result = $stat->getQueryStats();
  return ($result->{'status'} eq 'success' ? 1 : 0);
}

sub getQueryStatsSingleTest {
  my $stat = new PlugNPay::Stats::Query();

  my $data = &singleTestData();
  $stat->setDates($data->{'type'}, $data->{'dateRange'});
  $stat->addData($data->{'data'});
  my $result = $stat->getQueryStats();
  return ($result->{'status'} eq 'success' ? 1 : 0);
}

is(&getQueryStatsRangeTest,1,'Range data test');
is(&getQueryStatsMultiTest,1,'Multi data test');
is(&getQueryStatsSingleTest,1,'Single data test');

1;