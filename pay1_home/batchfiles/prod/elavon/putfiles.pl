#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::FTP;
use Net::SFTP::Foreign;
use miscutils;
use procutils;
use strict;

# sftp -oIdentityFile=/home/pay1/batchfiles/prod/elavon/.ssh/id_rsa -oPort=20022 nf001900@filegateway-test.elavon.com # test
# sftp -oIdentityFile=/home/pay1/batchfiles/prod/elavon/.ssh/id_rsa -oPort=20022 nf001900@filegateway.elavon.com # production

my $devprod = "logs";

my $redofile = "";

#my $redofile = "P8836200117184725.auc";

my ( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
my $julian = $julian + 1;
$julian = substr( "000" . $julian, -3, 3 );

my ( $d1, $today ) = &miscutils::genorderid();
my $ttime = &miscutils::strtotime($today);
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 20 ) );
my $yesterday = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
my $printstr = "\n\nin putfiles\n";
$printstr .= "\n$today  $yesterday\n";
&procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );

my %datainfo = ();
my $username = "";
my $filename = "";
my $elavonid = "";
my $bankid   = "";

my $ftpun = 'nf001900';
my $ftppw = 'we3i#f#0';

#my $host = '198.203.191.201';		# test old
#my $host = '192.203.191.38';		# production ip old
#my $host = 'filegateway-test.elavon.com';		# test url
my $host = 'filegateway.elavon.com';    # production url

my $port = '20022';

my %args = ( user => "$ftpun", password => "$ftppw", port => $port );

#my %args = (user => "$ftpun", password => "$ftppw", port => $port,
#            key_path => '/home/pay1/batchfiles/prod/elavon/.ssh/id_rsa');

#my @opts = ('-v','-i','/home/pay1/.ssh/id_rsa');     # put '-v' at the begginning for debugging
#my @opts = ('-v');     # put '-v' at the begginning for debugging
#my %args = (user => "$ftpun", password => "$ftppw", port => $port,
#           key_path => '/home/pay1/.ssh/id_rsa', more=>[@opts]);

my $ftp = Net::SFTP::Foreign->new( "$host", %args );

if ( $ftp eq "" ) {
  my $printstr = "Host $host username $ftpun and key don't work<br>\n";
  &procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );
  exit;
}

$ftp->error and die "login failed: " . $ftp->error;

my $printstr = "logged in\n";
&procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );

if (1) {
  my $files = $ftp->ls("/");

  if ( @$files == 0 ) {
    print "aa no report files\n";
  }
  foreach my $var (@$files) {
    my $fname = $var->{"filename"};

    print "aa " . $var->{"filename"} . "\n";
  }
}

if ( $redofile ne "" ) {
  &sendfile("$redofile");

  #$ftp->quit;
  exit;
}

#$mode = "binary";
#$ftp->type("$mode");

my $dbquerystr = <<"dbEOM";
        select distinct filename
        from accountupd
        where trans_date>=?
        and status in ('pending')
        and processor='elavon'
dbEOM
my @dbvalues = ("$yesterday");
my @sthbatchvalarray = &procutils::dbread( "elavon", "elavon", "pnpmisc", $dbquerystr, @dbvalues );

for ( my $vali = 0 ; $vali < scalar(@sthbatchvalarray) ; $vali = $vali + 1 ) {
  ($filename) = @sthbatchvalarray[ $vali .. $vali + 0 ];

  &sendfile("$filename");
}

#$ftp->quit;

exit;

sub sendfile {
  my ($filename) = @_;

  my $printstr = "$filename\n";
  &procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );

  my $fileyear = "20" . substr( $filename, 5, 2 ) . "/" . substr( $filename, 7, 2 ) . "/" . substr( $filename, 9, 2 );

  #print "$username elavon /home/pay1/batchfiles/logs/elavon/acctlogs/$fileyear $filename\n";

  my $msg = &procutils::fileencread( "elavon", "accountupd", "/home/pay1/batchfiles/logs/elavon/acctlogs/$fileyear", "$filename", "" );

  #print "message:\n$msg bb\n";

  my $printstr = "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear/$filename\n";
  &procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );

  #$ftp->put("/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear/$filename","inbox/$filename");
  $ftp->put_content( "$msg", "/$filename" ) or die "put failed: " . $ftp->error;

  #$ftp->put("/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear/$filename","inbox/$filename",'copy_perm' => 0, 'copy_time' => 0) or die "put failed: " . $ftp->error;
  #rename "/home/p/pay1/batchfiles/$devprod/elavon/$fileyear/$filename", "/home/p/pay1/batchfiles/$devprod/elavon/$fileyear/$filename" . "sav";

  $ftp->error and die "put failed: " . $ftp->error;

  print "status: " . $ftp->status . "\n";
  my $printstr = "status: " . $ftp->status . "\n";
  &procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );

  my $files = $ftp->ls("/");

  if ( @$files == 0 ) {
    my $printstr = "aa no report files\n";
    &procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );
  }
  foreach my $var (@$files) {
    my $fname = $var->{"filename"};

    my $printstr = "aa " . $var->{"filename"} . "\n";
    &procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );
  }

  #$ftp->rename("/ccs/ecommerce/t$filename","/ccs/ecommerce/$filename");

  my $dbquerystr = <<"dbEOM";
        update accountupd
        set status='locked'
        where trans_date>=?
        and status='pending'
        and filename=?
        and processor='elavon'
dbEOM
  my @dbvalues = ( "$yesterday", "$filename" );
  &procutils::dbupdate( "elavon", "elavon", "pnpmisc", $dbquerystr, @dbvalues );

}

