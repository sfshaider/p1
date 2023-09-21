#!/bin/env perl

require 5.001;
$|=1;

use lib $ENV{'PNP_PERL_LIB'};
use cookie_security;
use CGI;
use strict;

my $query = new CGI();

print "Content-Type: text/html\n\n";

my $action = "/ADMIN";
my $destination = "/admin";

if ($ENV{'REQUEST_URI'} =~ /overview/) {
  $destination = "/admin/overview/";
}

my $message = "";

if (&CGI::escapeHTML($query->param('forward')) eq "1") {
  $message = "The reseller administration area has moved. Please update your bookmarks.<br>";
}

&cookie_security::log_in_cookie($action, $destination, $message);

exit;

1;
