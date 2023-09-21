#!/usr/local/bin/perl

require 5.001;
$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use IO::Socket;
use Socket;

$devprod = "logs";

# delete rows older than 2 minutes
my $now     = time();
my $deltime = &miscutils::timetostr( $now - 120 );
print "deltime: $deltime\n";

my $dbhmisc = &miscutils::dbhconnect("pnpmisc");

my $sth = $dbhmisc->prepare(
  qq{
        delete from processormsg
        where (trans_time<'$deltime'
          or trans_time is NULL
          or trans_time='')
          and processor='transid'
        }
  )
  or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
$sth->execute()
  or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
$sth->finish;

$dbhmisc->disconnect;

while (1) {
  $temptime = time();
  open( outfile, ">/home/p/pay1/batchfiles/$devprod/transid/accesstime.txt" );
  print outfile "$temptime\n";
  close(outfile);

  &check();
  select undef, undef, undef, 0.30;
}

exit;

sub check {

  my $dbhmisc = &miscutils::dbhconnect("pnpmisc");

  my $sthmsg = $dbhmisc->prepare(
    qq{
        select trans_time,processid,username,orderid,message
        from processormsg
        where processor='transid'
        and status='pending'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthmsg->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthmsg->bind_columns( undef, \( $trans_time, $processid, $username, $orderid, $message ) );

  while ( $sthmsg->fetch ) {

    $processid =~ s/[^0-9]//g;
    $username =~ s/[^0-9A-Za-z]//g;

    $processor = $message;

    print "$mytime msgrcv $username $processor $orderid\n";
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/transid/serverlogmsg.txt" );
    print logfile "$processid $username\n";
    close(logfile);

    $username =~ s/[^0-9a-zA-Z_]//g;
    %datainfo = ( "username", "$username" );
    $sth1 = $dbhmisc->prepare(
      qq{
        select username,transseqnum
        from transid
        where username='$username'
        }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sth1->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    ( $chkusername, $transseqnum ) = $sth1->fetchrow;
    $sth1->finish;

    $transseqnum = ( $transseqnum % 100000000 ) + 1;

    if ( $chkusername eq "" ) {
      $sth = $dbhmisc->prepare(
        qq{
          insert into transid
          (username,transseqnum)
          values (?,?)
          }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sth->execute( "$username", "$transseqnum" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sth->finish;
    } else {
      $sth = $dbhmisc->prepare(
        qq{
          update transid set transseqnum=?
          where username='$username'
          }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sth->execute("$transseqnum") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sth->finish;
    }

    $transseqnum = sprintf( "%010d", $transseqnum + .0001 );
    print "transseqnum: $transseqnum\n";
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/transid/serverlogmsg.txt" );
    print logfile "$processid $username $processor $transseqnum\n";
    close(logfile);

    &mysqlmsgsnd( $dbhmisc, $processid, "success", "", "$transseqnum" );

  }
  $dbhmisc->disconnect;
}

sub mysqlmsgsnd {
  my ( $dbhhandle, $processid, $status, $invoicenum, $msg ) = @_;

  %datainfo = ( "processid", "$processid", "status", "$status", "invoicenum", "$invoicenum", "msg", "$msg" );
  my $sth = $dbhhandle->prepare(
    qq{
        update processormsg set status=?,invoicenum=?,message=?
        where processid='$processid'
        and processor='transid'
        and status='pending'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth->execute( "$status", "$invoicenum", "$msg" )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sth->finish;

}

