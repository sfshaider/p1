#!/usr/bin/perl

require 5.001;
$|=1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use uploadbatch;
use File::Copy;
use Net::SFTP::Foreign;
use strict;

$main::username = "newprovide";
$main::file_root = "/home/p/pay1/cronjobs/";
$main::filetype = "txt";  ### default option is tab delimeted. options are tsv or csv

# File Paths
## Path for results files archived files.
$main::archive_path = $main::file_root . "$main::username/archive";

## Path for results file
$main::results_path = $main::file_root . "$main::username/results";

$main::trncnt = 0;
my $message = "";

my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = gmtime(time() - (3600 * 24));
my $yesterdaydate = sprintf("%04d%02d%02d",$year+1900,$month+1,$day);

#my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time());
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
my $todaysdate = sprintf("%04d%02d%02d",$year+1900,$mon+1,$mday);

## Need to test ISDST using local time
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time());

#if ($isdst == 1) {
  $main::date = $yesterdaydate;
#}
#else {
#  $main::date = $todaysdate;
#}

#$main::date = "20180705";

$main::starttime = $main::date . "000000";

print "\nDate:$main::date, TIME:$main::starttime\n";

my %result = &retrieve_results();

if ($main::username =~ /demo/) {
  exit;
}

if ($result{'FinalStatus'} eq "success") {
  &put_file();
  $message = "Success";
}
else {
  $message = "$result{'MErrMsg'}";
}
print "MESSAGE:$message\n";


exit;

sub retrieve_results {
  my ($filefoundflg);

  my (%result,$check_str);

  #print "UN:$main::username  ST:$main::starttime\n";
  #my $check_str = "and batchid='20131121_1'";

  #Check that all batches have finished processing
  #$uploadbatch->display_batch_status($uploadbatch::batchid);

  # Get list of all batchid's processed today
  my ($headerflag,$header,$line,$dataline,$status,$batchid,$trans_time);
  my (%batchid_hash,%headerflag_hash,%header_hash,%status_hash);

  my $dbh = &miscutils::dbhconnect("uploadbatch");

  my $sth = $dbh->prepare(qq{
          select batchid,headerflag,header,status,trans_time
          from batchid
          where username='$main::username' 
          and trans_time>=? 
          $check_str
  }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr $main::username");
  $sth->execute($main::date) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr $main::username"); 
  $sth->bind_columns(undef,\($batchid,$headerflag,$header,$status,$trans_time));
  while ($sth->fetch()) {
    $filefoundflg = 1;
    $batchid_hash{"$batchid"} = "1";
    $headerflag_hash{"$batchid"} = "$headerflag";
    $header_hash{"$batchid"} = "$header";
    $status_hash{"$batchid"} = "$status";
    print "$trans_time, $batchid, $headerflag, $header, $status\n";
  }
  $sth->finish;

  if ($filefoundflg != 1) {
    #print "No batch found for: $main::date\n";
    $result{'MErrMsg'} = "No batch found for: $main::date";
    $result{'FinalStatus'} = "problem";
    return %result;
    exit;
  }

  my $dataline = "";
  my $sql ="select line from batchresult where batchid IN (";
  my @array = ();
  my %data = ();
  foreach my $batchid (sort keys %batchid_hash) {
    $sql .= "?,";
    push (@array,"$batchid");
  }
  chop $sql;
  $sql .= ") and username=? ";
  push (@array,$main::username);

  $main::trncnt = 1;
  $dataline = "FinalStatus\tMErrMsg\tresp-code\torderID\tauth-code\tavs-code\tcvvresp\t$header";
  $dataline =~ s/\t$//g;
  if ($main::filetype eq "csv") {
    $dataline =~ s/\t/\"\,\"/g;
    $dataline = "\"" . $dataline . "\"";
  }
  $dataline .= "\n";
  my $sth = $dbh->prepare(qq{$sql}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr $batchid");
  $sth->execute(@array) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr $batchid");
  $sth->bind_columns(undef,\($line));
  while ($sth->fetch()) {
    $main::trncnt++;
    if ($main::filetype eq "csv") {
      $line =~ s/\t/\"\,\"/g;
      $line = "\"" . $line . "\"";
    }
    $dataline .= "$line\n";
  }
  $sth->finish;

  open (RESULTS,">$main::results_path/PNPReturns_$batchid\.$main::filetype");
  print RESULTS "$dataline";
  close(RESULTS);

  $dbh->disconnect;

  if ($main::trncnt > 1) {
    $result{'FinalStatus'} = "success";
  }

  return %result;
}


sub put_file {
  my $ftphost = "sftp.morganwhite.com";

  my $ftpusername = "PlugnPay";
  my $ftppassword = "sFTP\@PlugNPay=5722";
  my $filename = "";
  my $remotedir = "/Incoming";

  my %args = (user => $ftpusername, port => 22, password=>$ftppassword,
              more => [-i => '/home/p/pay1/.ssh/id_rsa'] );

  my $sftp = Net::SFTP::Foreign->new("$ftphost", %args);

  if ($sftp eq "") {
    print "Host $ftphost is no good<br>\n";
    exit;
  }

  my (%processedfiles,%dirlist);
  # Get File Listing
  my @inbound_files = glob("$main::results_path/*");
  foreach my $file (@inbound_files) {
    $file =~ /\/(\w*\.txt)$/;
    my $filename = $1;
    print "FN:$filename, FILE:$file\n";
    print "$main::results_path/$filename\n";
    $sftp->put("$main::results_path/$filename","/$remotedir/$filename");
    copy($file,$main::archive_path);
    unlink($file);
    $processedfiles{$filename} = 0;
  }
  my $file_list = $sftp->ls("$remotedir");
  foreach my $entry (@$file_list) {
    my $filename = $entry->{'filename'};
    $dirlist{$filename} = $entry->{'longname'};
  }
  foreach my $fn (keys %processedfiles) {
    if (! exists $dirlist{$fn}) {
      print "File Upload Problem:$fn\n";
    }
    else {
      print "File Upload Success:$fn\n";
      print "$dirlist{$fn}\n";
    }
  }

  $sftp->disconnect;
}


1;

