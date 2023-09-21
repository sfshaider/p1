#!/bin/env perl

use strict;
use lib $ENV{"PNP_PERL_LIB"};
use PlugNPay::Security::Redirection;

my $redirector = new PlugNPay::Security::Redirection();
my $valid = $redirector->checkRedirection('/admin/virtualterminal/process.cgi');
print $valid . "\n";
exit;
