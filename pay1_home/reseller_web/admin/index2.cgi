#!/bin/env perl

use strict;

use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Reseller::Admin;

my $resellerAdmin = new PlugNPay::Reseller::Admin();
my $template = $resellerAdmin->getTemplate();

### Insert Content ###
$template->setVariable('content','Content');

my $html = $template->render();

print 'Content-type: text/html' . "\n\n";
print $html . "\n";
