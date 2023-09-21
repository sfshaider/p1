#!/usr/bin/perl

use strict;
use warnings;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::CreditCard;
use Data::Dumper;


my $card = new PlugNPay::CreditCard('4444333322221111');

if($card->getCategory() =~ /business/i) {
  print "Yes\n";
} else {
  print "No";
}

