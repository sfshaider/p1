#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::SFTP::Foreign;
use miscutils;

#use strict;

$devprod = "logs";

# sftp -oIdentityFile=.ssh/id_rsa -oPort=22 plugdp@fc1.citynational.com

my $redofile = "";

#my $redofile = "20090827164605";	# must uncomment username as well
#my $username = "windhaven";

$ENV{PATH} = ".:/usr/ucb:/usr/bin:/usr/local/bin";

my ( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
my $julian = $julian + 1;
$julian = substr( "000" . $julian, -3, 3 );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 30 * 8 ) );
$sixmonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $d1, $today ) = &miscutils::genorderid();
my $ttime = &miscutils::strtotime($today);
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 16 ) );
my $yesterday = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
print "\n\n$today  $yesterday\n";

my %datainfo  = ();
my $filename  = "";
my $citynatid = "";
my $bankid    = "";

my $ftpun = 'plugdp';

#my $ftppw = 'p#n3!a9y';
my $host = 'fc1.citynational.com';

#open(outfile,">/home/p/pay1/batchfiles/$devprod/citynat/2009/test.inst");
#print outfile "ls /in\n";
#close(outfile);

#$result = `echo p#n3!a9y | sftp -v -b /home/p/pay1/batchfiles/$devprod/citynat/2009/test.inst $ftpun\@$host`;
#print "aaaa $result bbbb\n";
#exit;

my $dbh = &miscutils::dbhconnect("pnpmisc");

my %args = (
  user => "$ftpun",
  port => 22,
  more => [ -i => '/home/p/pay1/batchfiles/prod/citynat/.ssh/id_rsa' ]
);

#my $ftp = Net::FTP->new("65.242.43.200", 'Timeout' => 2400, 'Debug' => 1, 'Port' => "21");
#$ftp = Net::SFTP->new("$host",'user' => $ftpun, 'password' => $ftppw, 'Timeout' => 2400, 'Debug' => 1, 'LocalAddr' => '209.51.176.199');
#$ftp = Net::SFTP::Foreign->new('host' => "$host",'user' => $ftpun, 'password' => $ftppw, 'timeout' => 240);
#$ftp = Net::SFTP::Foreign->new('host' => "$host",'user' => $ftpun, 'password' => $ftppw, 'more' => '-v', 'timeout' => 2400);
my $ftp = Net::SFTP::Foreign->new( "$host", %args );

if ( $ftp eq "" ) {
  print "Host $host username $ftpun and key don't work<br>\n";
  exit;
}

if ( $ftp->error ) {
  print "SSH connection failed: " . $ftp->error . "  trying again...\n";
  $ftp = Net::SFTP::Foreign->new( 'host' => "$host", 'user' => $ftpun, 'password' => $ftppw, 'timeout' => 240 );
}

$ftp->error and die "SSH connection failed: " . $ftp->error;

print "logged in\n";

my $sthdel = $dbh->prepare(
  qq{
        delete from batchfilescity
        where trans_date<='$sixmonthsago'
        }
  )
  or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
$sthdel->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
$sthdel->finish;

if ( $redofile ne "" ) {
  my $sthext = $dbh->prepare(
    qq{
          select distinct fileext
          from citynat
          where username='$username'
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthext->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ($fileext) = $sthext->fetchrow;
  $sthext->finish;

  &sendfile( $redofile, $fileext );

  $ftp->disconnect;
  $dbh->disconnect;
  exit;
}

#$mode = "binary";
#$ftp->type("$mode");

my $sthbatch = $dbh->prepare(
  qq{
        select distinct filename,fileext
        from batchfilescity
        where trans_date>='$yesterday'
        and status='pending'
        }
  )
  or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
$sthbatch->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
$sthbatch->bind_columns( undef, \( $filename, $fileext ) );

while ( $sthbatch->fetch ) {
  print "aaaa $filename\n";
  &sendfile( $filename, $fileext );
}
$sthbatch->finish;

$ftp->disconnect;

$dbh->disconnect;

sub sendfile {
  my ( $filename, $fileext ) = @_;

  #my ($lsec,$lmin,$lhour,$lday,$lmonth,$lyear,$wday,$yday,$isdst) = localtime(time());
  #my $ltrandate = sprintf("%04d%02d%02d%02d%02d%02d", 1900+$lyear, $lmonth+1, $lday, $lhour, $lmin, $lsec);
  print "$filename\n";

  #my $fileyear = substr($filename,-14,4);
  my $fileyear = substr( $filename, -14, 4 ) . "/" . substr( $filename, -10, 2 ) . "/" . substr( $filename, -8, 2 );
  print "fileyear: $fileyear\n";

  my $mm     = substr( $filename, 4, 2 );
  my $dd     = substr( $filename, 6, 2 );
  my $yy     = substr( $filename, 2, 2 );
  my $hhmmss = substr( $filename, 8, 6 );
  my $custcode     = "HAVE";
  my $last4acctnum = "3133";
  if ( $fileext ne "" ) {
    $last4acctnum = $fileext;
  }

  my $achfilename = "A$mm$dd$yy$hhmmss$custcode$last4acctnum.TXT";

  #print "/home/p/pay1/batchfiles/$devprod/citynat/$fileyear/$filename.txt  \'To CNB/t$achfilename\'\n";	# test
  print "/home/p/pay1/batchfiles/$devprod/citynat/$fileyear/$filename.txt  \'To CNB/$achfilename\'\n";    # production
  $ftp->put( "/home/p/pay1/batchfiles/$devprod/citynat/$fileyear/$filename.txt", "To CNB/$achfilename", 'copy_perm' => 0, 'copy_time' => 0 );

  #$ftp->put("/home/p/pay1/batchfiles/$devprod/citynat/$fileyear/$filename.txt", "To CNB/t$achfilename", 'copy_perm' => 0);
  $ftp->error and die "SSH command failed: " . $ftp->error;

  #$ftp->rename("/ccs/ecommerce/t$filename","/ccs/ecommerce/$filename");

  my $sthupd = $dbh->prepare(
    qq{
        update batchfilescity
        set status='locked'
        where trans_date>='$yesterday'
        and status='pending'
        and filename='$filename'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthupd->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthupd->finish;

  #$ftp->cwd("ftp_dir/out");
  print "cccc\n";

  #my @files = $ftp->ls("");
  my $ls = $ftp->cwd();
  print "$ls\n";
  my $ls = $ftp->ls( "To CNB/", 'wanted' => qr/$achfilename/ );
  $ftp->error and die "SSH command failed: " . $ftp->error;

  #my @files = $ftp->ls("/in/$achfilename");

  my $file1flag = 0;
  my $file2flag = 0;
  foreach my $var (@$ls) {

    #if ($var->{"filename"} =~ /$filefilter/) {
    print "bb " . $var->{"filename"} . "\n";

    #}
    if ( $var->{"filename"} eq "$achfilename" ) {
      $file1flag = 1;
    }

    #if ($var->{"filename"} eq "$filename3") {
    #  $file2flag = 1;
    #}
    #foreach my $key (sort keys %$var){
    #  print "bb the value is $key =>" .  $var->{$key} . "\n";
    #}
  }

  if ( $file1flag == 1 ) {
    print "file exists (good)\n";

    #unlink "/home/p/pay1/batchfiles/$devprod/citynat/$fileyear/$filename.txt";
  }

  #    if (@list == 0) {
  #      print "aa no report files\n";
  #    }
  #    foreach my $var (@list) {
  #      print "aa var: $var\n";
  #      unlink "/home/p/pay1/batchfiles/$devprod/citynat/$fileyear/$filename";
  #    }

}

exit;

