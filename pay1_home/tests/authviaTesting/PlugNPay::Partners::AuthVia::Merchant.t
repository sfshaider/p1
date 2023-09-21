#!/usr/bin/perl
  
use strict;
use lib $ENV{'PNP_PERL_LIB'};
use Test::More qw( no_plan );
use PlugNPay::Partners::AuthVia::Merchant;

my $username = $ARGV[0] || 'dylaninc';
my $partner = 'dylaninc';

sub createMerchant {
  my $merchant = new PlugNPay::Partners::AuthVia::Merchant();
  $merchant->setGatewayAccount($username);
  $merchant->setPartner($partner);
  my $res = $merchant->create();

  return ($res->{'id'} ? 1 : 0);
}

sub readMerchant {
  my $merchant = new PlugNPay::Partners::AuthVia::Merchant();
  $merchant->setGatewayAccount($username);
  $merchant->setPartner($partner);
  my $res = $merchant->read();
  return ($res->{'id'} ? 1 : 0);
}

sub updateMerchant {
  my $merchant = new PlugNPay::Partners::AuthVia::Merchant();
  $merchant->setGatewayAccount($username);
  $merchant->setPartner($partner);
  my $res = $merchant->update();
  
  return ($res->{'id'} ? 1 : 0);
}

sub isEnrolled {
  my $merchant = new PlugNPay::Partners::AuthVia::Merchant();
  $merchant->setGatewayAccount($username);
  $merchant->setPartner($partner);
 
  return ($merchant->isEnrolled() ? 1 : 0);
}

is(&createMerchant, 1, 'Create Merchant');
is(&updateMerchant, 1, 'Update Merchant');
is(&readMerchant, 1, 'Read Merchant');
is(&isEnrolled, 1, 'Check Enrollemnt');
