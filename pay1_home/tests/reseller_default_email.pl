#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Reseller;

my $reseller = new PlugNPay::Reseller('bryaninc');
$reseller->loadEmailData();

print "Admin Domain: " . $reseller->getAdminDomain() . "\n";
print "Email Domain: " . $reseller->getEmailDomain() . "\n";
print "Subject Prefix: " . $reseller->getSubjectPrefixEmail() . "\n";
print "NoReply Email: " . $reseller->getNoReplyEmail() . "\n";
print "Support Email: " . $reseller->getSupportEmail() . "\n";
print "Registration Email: " . $reseller->getRegistrationEmail() . "\n";
print "Private Label Email: " . $reseller->getPrivateLabelEmail() . "\n";

exit;
