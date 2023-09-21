

#!/usr/bin/perl

use strict;
use lib $ENV{"PNP_PERL_LIB"};
use Data::Dumper;
use miscutils;
use PlugNPay::Sys::Time;
use PlugNPay::Transaction::TransactionProcessor;
use PlugNPay::Util::UniqueID;
use JSON::XS;
use Time::HiRes;
use MIME::Base64;
my $user = 'anhtraminc';
&this($user);

sub this {
my $username = shift;

#this test is to query brand name for a credit card number and to check if the brand name is allowed.
#return 1/0
my $time = new PlugNPay::Sys::Time();
my $tp = new PlugNPay::Transaction::TransactionProcessor();
my $ok = $tp->isCardBrandAllowed($username, 371746000000009);
my $result_str = $ok? "yes": "no";
print "Card brand allowed? " . $result_str ."\n";

}
