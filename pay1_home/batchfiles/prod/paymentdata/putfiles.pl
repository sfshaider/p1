#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use Net::SFTP::Foreign;
use strict;

my $devprod = "logs";

my $redofile = "";

#my $redofile = "20090610174746";

my ( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
my $julian = $julian + 1;
$julian = substr( "000" . $julian, -3, 3 );

my ( $d1, $today ) = &miscutils::genorderid();
my $ttime = &miscutils::strtotime($today);
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 20 ) );
my $yesterday = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my $mytime   = gmtime( time() );
my $printstr = "\n\n$today  $yesterday\n";
$printstr .= "$mytime in putfiles.pl\n";
&procutils::filewrite( "paymentdata", "paymentdata", "/home/pay1/batchfiles/$devprod/paymentdata", "ftplog.txt", "append", "misc", $printstr );

my %datainfo      = ();
my $username      = "";
my $filename      = "";
my $paymentdataid = "";
my $bankid        = "";

#my $ftpun = 'PlugNPay';
#my $ftppw = 'frEs7ega';
my $ftpun = 'PlugNPaySftp';

#my $ftppw = 'r82Ef41Km3D';
my $ftppw   = 'salvvTC)Pi&Zn7ng';
my $ftphost = 'ftp.securepds.com';

#my $ftp = Net::FTP->new("ftp.securepds.com", 'Timeout' => 2400, 'Debug' => 1, 'Port' => "21", 'Passive' => 1);
#my $ftp = Net::SFTP->new("ftp.securepds.com",'user' => $ftpun, 'password' => $ftppw, 'Timeout' => 2400, 'Debug' => 1);
my $ftp = Net::SFTP::Foreign->new( 'host' => "ftp.securepds.com", 'user' => $ftpun, 'password' => $ftppw, 'port' => 22, 'timeout' => 30 );
$ftp->error and die "cannot connect: " . $ftp->error;

my $mycnt = 0;
while ( $ftp eq "" ) {
  my $printstr = "Host is no good<br>\n";
  &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/$devprod/paymentdata", "ftplog.txt", "append", "misc", $printstr );
  &miscutils::mysleep(60.0);
  $ftp = Net::SFTP->new( "ftp.securepds.com", 'user' => $ftpun, 'password' => $ftppw, 'Timeout' => 2400, 'Debug' => 1 );
  $mycnt++;
  if ( $mycnt == 20 ) {
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: paymentdata - FAILURE\n";
    print MAILERR "\n";
    print MAILERR "Couldn't connect to host (putfiles.pl).\n";
    print MAILERR "\n";
    print MAILERR "Note: Paymentdata can only handle one file per day.\n\n";
    close MAILERR;

    exit;
  }
}

my $printstr = "logged in\n";
&procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/$devprod/paymentdata", "ftplog.txt", "append", "misc", $printstr );

if (0) {
  my $printstr = "Username $ftpun and password don't work<br>\n";
  &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/$devprod/paymentdata", "ftplog.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: paymentdata - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't connect to host - username/password (putfiles.pl).\n";
  print MAILERR "\n";
  print MAILERR "Note: Paymentdata can only handle one file per day.\n\n";
  close MAILERR;

  exit;
}

#print "logged in  $line\n";
#exit;

if ( $redofile ne "" ) {
  &sendfile($redofile);

  #$ftp->quit;

  exit;
}

#$mode = "binary";
#$ftp->type("$mode");

my $dbquerystr = <<"dbEOM";
        select distinct filename
        from batchfilespdata
        where trans_date>=?
        and status in ('pending')
dbEOM
my @dbvalues = ("$yesterday");
my @sthbatchvalarray = &procutils::dbread( "paymentdata", "paymentdata", "pnpmisc", $dbquerystr, @dbvalues );

for ( my $vali = 0 ; $vali < scalar(@sthbatchvalarray) ; $vali = $vali + 1 ) {
  ($filename) = @sthbatchvalarray[ $vali .. $vali + 0 ];

  &sendfile($filename);
}

#$ftp->quit;

sub sendfile {
  my ($filename) = @_;

  #my ($lsec,$lmin,$lhour,$lday,$lmonth,$lyear,$wday,$yday,$isdst) = localtime(time());
  #my $ltrandate = sprintf("%04d%02d%02d%02d%02d%02d", 1900+$lyear, $lmonth+1, $lday, $lhour, $lmin, $lsec);
  my $printstr = "$filename\n";
  &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/$devprod/paymentdata", "ftplog.txt", "append", "misc", $printstr );

  #my $fileyear = substr($filename,-14,4);
  my $fileyear = substr( $filename, -14, 4 ) . "/" . substr( $filename, -10, 2 ) . "/" . substr( $filename, -8, 2 );

  my $achfilename = "PNP." . substr( $filename, -14, 14 ) . ".ach";
  $ftp->put( "/home/pay1/batchfiles/$devprod/paymentdata/$fileyear/$filename", "/In/$achfilename" );

  my $msg = &procutils::fileencread( "putfiles", "paymentdata", "/home/pay1/batchfiles/$devprod/paymentdata/$fileyear", "$filename", "" );

  my $printstr = "after fileencread\n";
  &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/$devprod/paymentdata", "ftplog.txt", "append", "misc", $printstr );

  if ( length($msg) > 60 ) {
    my $printstr = "before put file   /home/pay1/batchfiles/$devprod/paymentdata/$fileyear/$filename  /In/$achfilename\n";
    &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/$devprod/paymentdata", "ftplog.txt", "append", "misc", $printstr );

    $ftp->put_content( "$msg", "/In/$achfilename" );
  }

  my $printstr = "after put file\n";
  $printstr .= "status: " . $ftp->status . "\n";
  $printstr .= "error: " . $ftp->error . "\n";
  print "$printstr\n";
  &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/$devprod/paymentdata", "ftplog.txt", "append", "misc", $printstr );

  #my $tmpstr = Net::SFTP::Util::fx2txt($ftp->status);
  #print "aaaa $tmpstr\n";

  #$ftp->rename("/ccs/ecommerce/t$filename","/ccs/ecommerce/$filename");

  my $dbquerystr = <<"dbEOM";
        update batchfilespdata
        set status='locked'
        where trans_date>=?
        and status='pending'
        and filename=?
dbEOM
  my @dbvalues = ( "$yesterday", "$filename" );
  &procutils::dbupdate( "paymentdata", "paymentdata", "pnpmisc", $dbquerystr, @dbvalues );

  #$ftp->cwd("ftp_dir/out");
  my $ls = $ftp->ls("/In");

  my $fileflag = 0;
  foreach my $var (@$ls) {
    my $printstr = "bb " . $var->{"filename"} . "\n";
    &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/$devprod/paymentdata", "ftplog.txt", "append", "misc", $printstr );

    if ( $var->{"filename"} eq "$achfilename" ) {
      $fileflag = 1;
    }

    #foreach $key (sort keys %$var){
    #  print "bb the value is $key =>" .  $var->{$key} . "\n";
    #}
  }

  if ( $fileflag == 0 ) {
    my $printstr = "aa no report file\n";
    &procutils::filewrite( "$username", "paymentdata", "/home/pay1/batchfiles/$devprod/paymentdata", "ftplog.txt", "append", "misc", $printstr );

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: paymentdata - FAILURE\n";
    print MAILERR "\n";
    print MAILERR "Couldn't upload file logs/$fileyear/$filename (putfiles.pl).\n";
    print MAILERR "\n";
    print MAILERR "Note: Paymentdata can only handle one file per day.\n\n";
    close MAILERR;
  } else {
    unlink "/home/pay1/batchfiles/$devprod/paymentdata/$fileyear/$filename";
  }

}

exit;

