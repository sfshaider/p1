#!/usr/local/bin/perl

require 5.001;
$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;

my ( $d1, $today ) = &miscutils::genorderid();
print "$today\n";

my $dbh = &miscutils::dbhconnect("pnpmisc");

my $sth = $dbh->prepare(
  qq{
        delete from cardinallog
        where trans_date<?
}
  )
  or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
$sth->execute("$today") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
$sth->finish;

$dbh->disconnect;

