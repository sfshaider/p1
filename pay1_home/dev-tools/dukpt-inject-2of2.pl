#!/usr/local/bin/perl

$| = 1;

use lib '/home/p/pay1/perl_lib';
use Net::FTP;
use miscutils;
use IO::Socket;
use Socket;
use rsautils;
use smpsutils;
use Crypt::CBC;
use Crypt::DES;
use dukpt;



my ($d1,$trans_date) = &miscutils::genorderid();


# get list of all pending ksn's
my $dbh = &miscutils::dbhconnect("pnpmisc");

my $sth = $dbh->prepare(qq{
        select ksn
        from dukpt
        where trans_date='$trans_date'
        and status='pending'
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%fdms::datainfo);
$sth->execute or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%fdms::datainfo);
$sth->bind_columns(undef,\($chkksn));

while ($sth->fetch) {
  print "$chkksn\n";
}
$sth->finish;

$dbh->disconnect;

print "\n";




print "bdk2: ";
$bdk2 = <stdin>;
chomp $bdk2;

my $ksn = readKsn2();

while ($ksn ne "") {
  &dukpt::injectipek("$ksn","$bdk2");

  print "ksn: ";
  $ksn = <stdin>;
  chop $ksn;
}

sub readKsn2 {
  print "ksn: ";
  $ksn = <stdin>;
  chomp $ksn;
  return $ksn;
}