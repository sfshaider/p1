#!/bin/env perl
BEGIN {
  $ENV{'DEBUG'} = undef; # ensure debug is off, it's ugly, and not needed for testing
}

use strict;
use Test::More qw( no_plan );
use Data::Dumper;

use lib $ENV{'PNP_PERL_LIB'};

require_ok('PlugNPay::GatewayAccount::Services::Service');
require_ok('PlugNPay::GatewayAccount');

#testServices();
testServicesPnpdemo();

sub testServices {
  my $s = new PlugNPay::GatewayAccount::Services::Service();
  my $data = $s->getServiceIdList();
  print STDERR Dumper($data);
  foreach my $key (keys %{$data}) {
    is($key,$data->{$key}{'id'},'test service id matches id in list');
  }
}

sub testServicesPnpdemo {
  my $ga = new PlugNPay::GatewayAccount('pnpdemo');
  my $s = new PlugNPay::GatewayAccount::Services::Service({ gatewayAccount => $ga });
  print STDERR Dumper($s);
}
