#!/bin/env perl

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use CGI;
use strict;
use URI::Escape;

my $q = new CGI();

my $username = $q->param('username');

my $error;
my $result;

if ($username =~ /[^a-z0-9]/) { # invalid characters in username, return error;
  $error = 'Invalid characters in username';
} elsif (length($username) > 12 || length($username) < 3) {
  $error = 'Invalid username length';
} else {
  my $dbh = miscutils::dbhconnect('pnpmisc');
  my $query = q{
    SELECT processor,
           reseller,
           proc_type,
           status,
           state
    FROM customers
    WHERE username = ?
  };
  my $sth = $dbh->prepare($query);
  $username =~ s/[^a-z0-9]//g; # just to be sure!
  $sth->execute($username);
  $result = $sth->fetchrow_hashref;
  $sth->finish;
  $dbh->disconnect;
}

print 'Content/type: text/html' . "\n\n";
printf('error=%s&status=%s&proc_type=%s&reseller=%s&processor=%s&state=%s&admindomain=%s',
       uri_escape($error),
       uri_escape($result->{'status'}),
       uri_escape($result->{'proc_type'}),
       uri_escape($result->{'reseller'}),
       uri_escape($result->{'processor'}),
       uri_escape($result->{'state'}),
       uri_escape($result->{'admindomain'})
      );

