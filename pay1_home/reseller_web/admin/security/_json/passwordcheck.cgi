#!/bin/env perl

# Note: does not use input valdiator since all password characters are acceptible. 

use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Environment;
use PlugNPay::Username;
use JSON::XS;
use CGI;

my $env = new PlugNPay::Environment();
my $username = $env->get('PNP_USER');

my $q = new CGI();
my $password = $q->param('password');

my $u = new PlugNPay::Username($username);

my $verified = $u->verifyPassword($password) || 0;

print 'Content-type: application/json' . "\n\n";
print encode_json({verified => $verified}) . "\n";
