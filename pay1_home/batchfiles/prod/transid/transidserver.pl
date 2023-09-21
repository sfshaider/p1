#!/usr/local/bin/perl

require 5.001;
$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use PlugNPay::DBConnection;

$devprod = "logs";

# delete rows older than 2 minutes
my $now      = time();
my $deltime  = &miscutils::timetostr( $now - 120 );
my $printstr = "deltime: $deltime\n";
&procutils::filewrite( "$username", "transid", "/home/pay1/batchfiles/devlogs/transid", "miscdebug.txt", "append", "misc", $printstr );

my $dbquerystr = <<"dbEOM";
        delete from processormsg
        where (trans_time<?
          or trans_time is NULL
          or trans_time='')
          and processor='transid'
dbEOM
my @dbvalues = ("$deltime");
&procutils::dbdelete( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

$cleancnt = 0;

while (1) {
  $temptime   = time();
  $outfilestr = "";
  $outfilestr .= "$temptime\n";
  &procutils::filewrite( "$username", "transid", "/home/pay1/batchfiles/$devprod/transid", "accesstime.txt", "write", "", $outfilestr );

  &check();
  select undef, undef, undef, 0.30;
}

exit;

sub check {

  my $dbquerystr = <<"dbEOM";
        select trans_time,processid,username,orderid,message
        from processormsg
        where processor='transid'
        and status='pending'
dbEOM
  my @dbvalues = ();
  my @sthmsgvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  for ( my $vali = 0 ; $vali < scalar(@sthmsgvalarray) ; $vali = $vali + 5 ) {
    ( $trans_time, $processid, $username, $orderid, $message ) = @sthmsgvalarray[ $vali .. $vali + 4 ];

    $processid =~ s/[^0-9A-Za-z]//g;
    $username =~ s/[^0-9A-Za-z]//g;

    $processor = $message;

    my $printstr = "$mytime msgrcv $username $processor $orderid\n";
    &procutils::filewrite( "$username", "transid", "/home/pay1/batchfiles/devlogs/transid", "miscdebug.txt", "append", "misc", $printstr );

    $logfilestr = "";
    $logfilestr .= "$processid $username\n";
    &procutils::filewrite( "$username", "transid", "/home/pay1/batchfiles/$devprod/transid", "serverlogmsg.txt", "append", "", $logfilestr );

    $username =~ s/[^0-9a-zA-Z_]//g;
    %datainfo = ( "username", "$username" );
    my $dbquerystr = <<"dbEOM";
          select username,transseqnum
          from transid
          where username=?
dbEOM
    my @dbvalues = ("$username");
    ( $chkusername, $transseqnum ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    $transseqnum = ( $transseqnum % 100000000 ) + 1;

    if ( $chkusername eq "" ) {
      my $dbquerystr = <<"dbEOM";
          insert into transid
          (username,transseqnum)
          values (?,?)
dbEOM

      my %inserthash = ( "username", "$username", "transseqnum", "$transseqnum" );
      &procutils::dbinsert( $username, $orderid, "pnpmisc", "transid", %inserthash );

    } else {
      my $dbquerystr = <<"dbEOM";
          update transid set transseqnum=?
          where username=?
dbEOM
      my @dbvalues = ( "$transseqnum", "$username" );
      &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    }

    $transseqnum = sprintf( "%010d", $transseqnum + .0001 );

    my $printstr = "transseqnum: $transseqnum\n";
    &procutils::filewrite( "$username", "transid", "/home/pay1/batchfiles/devlogs/transid", "miscdebug.txt", "append", "misc", $printstr );

    $logfilestr = "";
    $logfilestr .= "$processid $username $processor $transseqnum\n";
    &procutils::filewrite( "$username", "transid", "/home/pay1/batchfiles/$devprod/transid", "serverlogmsg.txt", "append", "", $logfilestr );

    &mysqlmsgsnd( $dbhmisc, $processid, "success", "", "$transseqnum" );

  }
  $cleancnt++;
  if ( $cleancnt > 5000 ) {
    PlugNPay::DBConnection::cleanup();
    $cleancnt = 0;
  }

}

sub mysqlmsgsnd {
  my ( $dbhhandle, $processid, $status, $invoicenum, $msg ) = @_;

  %datainfo = ( "processid", "$processid", "status", "$status", "invoicenum", "$invoicenum", "msg", "$msg" );
  my $dbquerystr = <<"dbEOM";
        update processormsg set status=?,invoicenum=?,message=?
        where processid=?
        and processor='transid'
        and status='pending'
dbEOM
  my @dbvalues = ( "$status", "$invoicenum", "$msg", "$processid" );
  &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

}

