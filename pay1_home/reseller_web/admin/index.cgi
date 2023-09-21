#!/bin/env perl

use strict;

use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Environment;
use PlugNPay::CGI;

my $env = new PlugNPay::Environment();
my $account = $env->get('PNP_ACCOUNT');
my $ga = new PlugNPay::GatewayAccount($account);
my $f = $ga->getFeatures();

my $cgi = new PlugNPay::CGI();
if ($f->get('reseller_ui') eq 'legacy') {
  print $cgi->redirect('/admin/index_v1.cgi');
} else {
  print $cgi->redirect('/admin/v2/merchants/')
}
