#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::SFTP::Foreign;
use miscutils;
use procutils;

$devprod = "logs";

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
$julian = $julian + 1;
$julian = substr( "000" . $julian, -3, 3 );

( $d1, $today ) = &miscutils::genorderid();
$ttime = &miscutils::strtotime($today);
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 4 ) );
$yesterday = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my $mytime   = gmtime( time() );
my $printstr = "\n\n$mytime in putfiles\n";
&procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "ftplog.txt", "append", "misc", $printstr );

$fileyear = substr( $today, 0, 4 );

$ftphost = "206.253.180.37";    ### DCP 20100528  via IN
$host    = "processor-host";

$ftpun = 'pnptec';              # production
$ftppw = 'ikj78tge';            # production

#$ftpun = 'pnptectest';          # test
#$ftppw = 'ajk9lpnf';            # test

# clean out batchfiles
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 180 ) );
my $deletedate = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my $dbquerystr = <<"dbEOM";
      delete from batchfilessalem
      where trans_date<?
dbEOM
my @dbvalues = ("$deletedate");
&procutils::dbdelete( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

$ftp = Net::SFTP::Foreign->new( 'host' => "$ftphost", 'user' => $ftpun, 'password' => $ftppw, 'port' => 22, 'timeout' => 30 );

$ftp->error and die "cannot connect: " . $ftp->error;
if ( $ftp eq "" ) {
  my $printstr = "Host $host is no good<br>\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "ftplog.txt", "append", "misc", $printstr );
  exit;
}
$ftp->error and die "SSH connection failed: " . $ftp->error;

my $printstr = "logged in\n";
&procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "ftplog.txt", "append", "misc", $printstr );

$mode = "A";

my $dbquerystr = <<"dbEOM";
        select distinct filename
        from batchfilessalem
        where trans_date>=?
        and status='pending'
        and username<>'testptechs'
dbEOM
my @dbvalues = ("$yesterday");
my @sthbatchvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

for ( my $vali = 0 ; $vali < scalar(@sthbatchvalarray) ; $vali = $vali + 1 ) {
  ($filename) = @sthbatchvalarray[ $vali .. $vali + 0 ];

  my $printstr = "$filename\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "ftplog.txt", "append", "misc", $printstr );
  my $fileyear = substr( $filename, 0, 4 ) . "/" . substr( $filename, 4, 2 ) . "/" . substr( $filename, 6, 2 );

  #$ftp->put("/home/pay1/batchfiles/$devprod/paytechsalem/$fileyear/$filename", "test/292961/t$filename");	# test

  my $printstr = "put $filename\n";
  $printstr .= "put /home/pay1/batchfiles/$devprod/paytechsalem/$fileyear/$filename home/292961/t$filename\n";    # production
  $printstr .= "rename home/292961/t$filename home/292961/p$filename\n";                                          # production
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "ftplog.txt", "append", "misc", $printstr );

  my $msg = &procutils::fileencread( "putfiles", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem/$fileyear", "$filename", "" );

  my $printstr = "after fileencread\n";
  $printstr .= "status: " . $ftp->status . "\n";
  $printstr .= "error: " . $ftp->error . "\n\n";
  print "$printstr\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "ftplog.txt", "append", "misc", $printstr );

  if ( length($msg) > 60 ) {
    my $printstr = "before put file   /home/pay1/batchfiles/$devprod/paytechsalem/$fileyear/$filename  home/292961/t$filename\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "ftplog.txt", "append", "misc", $printstr );

    $ftp->put_content( "$msg", "home/292961/t$filename" );

    my $printstr = "after put file\n";
    $printstr .= "status: " . $ftp->status . "\n";
    $printstr .= "error: " . $ftp->error . "\n\n";
    print "$printstr\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "ftplog.txt", "append", "misc", $printstr );

  }

  #$ftp->rename("test/292961/t$filename","test/292961/p$filename");	# test
  my $printstr = "rename home/292961/t$filename home/292961/p$filename\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "ftplog.txt", "append", "misc", $printstr );

  $ftp->rename( "home/292961/t$filename", "home/292961/p$filename" );    # production
  $ftp->error and die "SSH command failed: " . $ftp->error;

  #$ftp->put("/home/pay1/batchfiles/$devprod/paytechsalem/$fileyear/$filename", "test/292961/t$filename");	# test

  my $dbquerystr = <<"dbEOM";
        update batchfilessalem
        set status='locked'
        where trans_date>=?
        and status='pending'
        and filename=?
dbEOM
  my @dbvalues = ( "$yesterday", "$filename" );
  &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my @filenamearray = ();

  my $ls = $ftp->ls("home/292961");

  $ftp->error and die "SSH command failed: " . $ftp->error;

  my $fn = "";
  if ( @$ls == 0 ) {
    my $printstr = "aa no report files\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "ftplog.txt", "append", "misc", $printstr );
  }

  my $printstr = "";
  foreach my $var (@$ls) {
    $fn = $var->{"filename"};

    $printstr .= "bb " . $var->{"filename"} . "\n";
    $printstr .= "aa var: $fn  $filename\n";

    if ( $fn eq "p$filename" ) {
      $printstr .= "file $filename found...deleting locally\n";
      unlink "/home/pay1/batchfiles/$devprod/paytechsalem/$fileyear/$filename";
    }
  }
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "ftplog.txt", "append", "misc", $printstr );

}

exit;

