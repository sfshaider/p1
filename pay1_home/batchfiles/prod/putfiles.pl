#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::SFTP::Foreign;
use miscutils;
use PlugNPay::Database;
use strict;

my $devprod = "logs";

my $redofile = "";
my $username = "";

#my $redofile = "20141113153006";	# must uncomment username as well
#my $username = "sssach";

$ENV{PATH} = ".:/usr/ucb:/usr/bin:/usr/local/bin";

my ( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
my $julian = $julian + 1;
$julian = substr( "000" . $julian, -3, 3 );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 30 * 6 ) );
my $sixmonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

print "SIXMONTHSAGO:$sixmonthsago\n";

my ( $d1, $today ) = &miscutils::genorderid();
my $ttime = &miscutils::strtotime($today);
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 16 ) );
my $yesterday = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

#$yesterday = "20141114";

print "\n\nToday:$today  Yesterday:$yesterday\n";

my $root_file_path = "/home/p/pay1/batchfiles/$devprod/mtbankach";

my $filename = "";

if (0) {
  my $ftphost     = "secureftp.mandtbank.com";
  my $ftpusername = "SOVRAN";
  my $ftppassword = "s1o2v3r4";

  #my $remotedir = "/SOVRAN/ACH_IN_TEST/SSH_IN";
  my $remotedir = "/SOVRAN/ACH_IN/SSH_IN";
}

my $ftphost     = "mft.mtb.com";
my $ftpusername = "PlugPay";
my $ftppassword = "GnRLhU0K";
my $remotedir   = "/ACH_IN";

my $filemask    = "";
my $debug_level = 9;

my $sftp = Net::SFTP::Foreign->new( 'host' => "$ftphost", 'user' => $ftpusername, 'password' => $ftppassword, 'timeout' => 240 );
if ( $sftp eq "" ) {
  print "Host $ftphost username $ftpusername and password don't work\n";
  exit;
}

if ( $sftp->error ) {
  print "SSH connection failed: " . $sftp->error . "  trying again...\n";
  $sftp = Net::SFTP::Foreign->new( 'host' => "$ftphost", 'user' => $ftpusername, 'password' => $ftppassword, 'timeout' => 240 );
}

$sftp->error and die "SSH connection failed: " . $sftp->error;

my ($fname);

if ( $sftp eq "" ) {
  print "Host $ftphost is no good\n";
  exit;
} else {
  print "Host $ftphost is good\n";
  my $file_list = $sftp->ls("$remotedir/");
  foreach my $filehash (@$file_list) {
    foreach my $key ( sort keys %$filehash ) {
      print "$key:$$filehash{$key}, ";
    }
    print "\n";
  }
}

my $dbase = new PlugNPay::Database();

my $dbh = &miscutils::dbhconnect("pnpmisc");

my $sthdel = $dbh->prepare(
  qq{
      delete from batchfilesmtbank
      where trans_date<=?
      }
  )
  or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr" );
$sthdel->execute($sixmonthsago) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr" );
$sthdel->finish;

$dbh->disconnect;

if ( $redofile ne "" ) {
  my @requestedData = ('distinct fileext');
  my @params        = ( 'username', $username );
  my @results       = $dbase->databaseQuery( 'pnpmisc', 'mtbankach', \@requestedData, \@params );
  my $Data          = $results[0];
  my $fileext       = $$Data{'fileext'};

  print "Resending:$redofile, FILEEXT:$fileext\n";

  &sendfile( $redofile, $fileext, $remotedir, $dbase, $yesterday );

  my $file_list = $sftp->ls("$remotedir/");
  foreach my $filehash (@$file_list) {
    print "NAME:$$filehash{'filename'}, LONGNAME:$$filehash{'longname'}\n";
  }
  exit;
}

my @requestedData = ( 'distinct filename', 'fileext',     'username', 'trans_date' );
my @params        = ( 'trans_date',        ">$yesterday", 'status',   'pending' );
my @results = $dbase->databaseQuery( 'pnpmisc', 'batchfilesmtbank', \@requestedData, \@params );

#my $Data = $results[0];

foreach my $Data (@results) {
  my $filename   = $$Data{'filename'};
  my $fileext    = $$Data{'fileext'};
  my $trans_date = $$Data{'trans_date'};
  my $username   = $$Data{'username'};

  print "AAAA:$filename, UN:$username\n";
  if ( $filename ne "" ) {
    &sendfile( $filename, $fileext, $remotedir, $dbase, $trans_date, $username );
  } else {
    print "No Batch File Found\n";
  }
}

exit;

sub sendfile {
  my ( $filename, $fileext, $remotedir, $dbase, $trans_date, $username ) = @_;

  print "$filename\n";
  my $fileyear = substr( $filename, -14, 4 ) . "/" . substr( $filename, -10, 2 ) . "/" . substr( $filename, -8, 2 );
  print "fileyear: $fileyear\n";

  my $mm     = substr( $filename, 4, 2 );
  my $dd     = substr( $filename, 6, 2 );
  my $yy     = substr( $filename, 2, 2 );
  my $hhmmss = substr( $filename, 8, 6 );
  my $last4acctnum = "3133";
  if ( $fileext ne "" ) {
    $last4acctnum = $fileext;
  }

  my $local_file_path  = "$root_file_path/$fileyear/$filename\.txt";
  my $remote_file_path = "$remotedir/$filename\.txt";

  if ( !-e $local_file_path ) {
    print "Local File Not Found: $local_file_path, locking row in dbase\n";
    my %updateData = ( 'status', 'locked' );
    my @params = ( 'trans_date', $trans_date, 'status', 'pending', 'filename', $filename, 'username', $username );
    my @results = $dbase->databaseUpdate( 'pnpmisc', 'batchfilesmtbank', \%updateData, \@params );
    return;
  }

  print "Sending $local_file_path --> $remote_file_path\n";

  $sftp->put( "$local_file_path", "$remote_file_path", copy_perm => 0, copy_time => 0, overwrite => 1, ) or die "put failed: " . $sftp->error;

  $sftp->disconnect;

  my $file_flag = 1;

  if ( $file_flag == 1 ) {
    print "file exists (good) - updateing, trans_date:$trans_date, fn:$filename, UN:$username\n";
    my %updateData = ( 'status', 'locked' );
    my @params = ( 'trans_date', $trans_date, 'status', 'pending', 'filename', $filename, 'username', $username );
    my @results = $dbase->databaseUpdate( 'pnpmisc', 'batchfilesmtbank', \%updateData, \@params );
  } else {
    print "Problem with file upload\n";
    &report_error($filename);
  }

  return;

}

sub report_error {

}

exit;

