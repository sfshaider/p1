#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Environment;
use PlugNPay::AuthCookieDBI;
use PlugNPay::Authentication;
use cookie_security;
use CGI::Cookie;

my $r = shift;
my $env = new PlugNPay::Environment();
my $session = new PlugNPay::Authentication();

my %cookies = fetch CGI::Cookie;
my $cookie = $cookies{$r->auth_name}->value;
$cookie =~ s/ /+/g;

my $error = $session->expireSession({'login' => $env->get('PNP_USER'), 'realm' => $r->auth_name, 'cookie' => $cookie});
$r->content_type("text/html");
$r->status(200);
$r->auth_type->logout($r);

my $cgi = new CGI();
$cgi->redirect('/login/index.html');

exit;
