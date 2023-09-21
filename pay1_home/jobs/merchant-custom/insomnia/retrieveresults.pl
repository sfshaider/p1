#!/usr/bin/perl

require 5.001;
$|=1;

use lib '/home/p/pay1/perl_lib';
use miscutils;
use uploadbatch;
use File::Copy;
use Math::BigInt;
use GnuPG qw( :algo );
use Net::SFTP;
use strict;


$main::base_path = "/home/p/pay1/cronjobs/insomnia";

# File Paths

# File Path for Files already processed
$main::postprocessed_path = "$main::base_path\/uploaded";

## Path for results file
$main::results_path = "$main::base_path\/results";

$main::username = "insomnia";


## SFTP Info
#$main::ftp_host = "52.200.105.167";
$main::ftp_host = "52.45.39.70"; ## As of 12/28/2016
$main::ftp_un = "pgwuser";
$main::ftp_pw = "xEgxQzE5BaHMV2m";  ## as of 04/28/2016
my $filename = "";


$main::trncnt = 0;
my $message = "";

my ($dummy,$todaysdate,$dummy) = &miscutils::gendatetime();
$main::date = $todaysdate;

my ($dummy,$todaysdate,$dummy) = &miscutils::gendatetime(-24*3600);
$main::batchdate = $todaysdate;
## Edit Below to Manually Return Results

#$main::date = "20211202";
#$main::batchdate = "20211201";  ###  Batchdate is typically 1 day earlier then main date

print "DATE:$main::date,  BATCH DATE:$main::batchdate, STARTING NEW BATCH\n";

my ($results_file,%result) = &retrieve_results();

print "RESULTSFILE:$results_file\n";

&put_file_sftp($results_file);

exit;

if ($result{'FinalStatus'} eq "success") {
  &put_file_sftp($results_file); 
  $message = "Success";
}
else {
  $message = "$result{'MErrMsg'}";
}
print "DATE:$main::date, MESSAGE:$message\n";

exit;

sub retrieve_results {

  my (%result,$check_str,$kk,$batchfoundflag,%uploadtrancnt);

  #my $check_str = "and batchid LIKE '%2015022221' ";
  #$main::date = "20080905";

  #Check that all batches have finished processing
  #$uploadbatch->display_batch_status($uploadbatch::batchid);

  # Get list of all batchid's processed today
  my ($headerflag,$header,$line,$dataline,$status,$batchid,$trans_time,$firstorderid,$lastorderid);
  my (%batchid_hash,%headerflag_hash,%header_hash,%status_hash);

  #and batchid LIKE '%main::batchdate%'


#          where (username LIKE '$main::username%' 
#            or username LIKE 'dbanamein%')
#          and trans_time LIKE '$main::date%'
#          and batchid LIKE '%$main::batchdate%'

  my $dbh = &miscutils::dbhconnect("uploadbatch");

  my $sth = $dbh->prepare(qq{
          select batchid,headerflag,header,status,trans_time,firstorderid,lastorderid
          from batchid
          where batchid LIKE 'ICOOK_%$main::batchdate%'
          and trans_time LIKE '$main::date%'
          $check_str
  }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr $main::username"); 
  $sth->execute or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr $main::username"); 
  $sth->bind_columns(undef,\($batchid,$headerflag,$header,$status,$trans_time,$firstorderid,$lastorderid));
  while ($sth->fetch()) {
    $batchfoundflag = 1;
    $batchid_hash{"$batchid"} = "1";
    $headerflag_hash{"$batchid"} = "$headerflag";
    $header_hash{"$batchid"} = "$header";
    $status_hash{"$batchid"} = "$status";
    $header =~ s/\ttransflags//;
    print "DATE:$main::date, $trans_time, $batchid, $headerflag, $header, $status, $lastorderid, $firstorderid\n";
  }
  $sth->finish;

  my ($uploadtrancnt);
  if ($batchfoundflag == 1) {
    $lastorderid = Math::BigInt->new("$lastorderid");
    $firstorderid = Math::BigInt->new("$firstorderid");
    $uploadtrancnt = $lastorderid - $firstorderid + 1;
    $uploadtrancnt{$batchid} = $uploadtrancnt;
  }
  else {
    exit;
  }
  #print "UPLDCNT:$uploadtrancnt\n";

  #exit;

  my $dataline = "FinalStatus\tMErrMsg\tresp-code\torderID\tauth-code\tavs-code\tcvvresp\t$header\n";

  #print "HEADER:$header:\n";
  #print "DL:$dataline:\n";
  $main::successcnt = 0;
  $main::badcnt = 0;
  $main::probcnt = 0; 
  my ($i);
  foreach my $batchid (sort keys %batchid_hash) { 
    my $sth = $dbh->prepare(qq{
          select line 
          from batchresult 
          where batchid='$batchid' 
          and username LIKE '$main::username%' 
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr $batchid");
    $sth->execute or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr $batchid");
    $sth->bind_columns(undef,\($line)); 
    while ($sth->fetch()) { 
      $i++;
      $main::trncnt++;
      ###  DCP 20080714  Added to strip out commas from dollar amounts.
      $line =~ s/\,//g;
      $dataline .= $line . "\t\n";

    } 
    $sth->finish; 
  }
  $dbh->disconnect;

  my $file_path = "$main::results_path\/$main::batchdate\.results.txt";

  print "DATE:$main::date, BATCHID:$batchid, ProcessedCNT:$main::trncnt, UPLOADCNT:$uploadtrancnt{$batchid}, FP:$file_path \n";


  open (RESULTS,">$file_path");
  print RESULTS "$dataline";

  close(RESULTS);

  if ($main::trncnt eq $uploadtrancnt) {
    $result{'FinalStatus'} = "success";
  }
  else {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Transaction Count Mismatch: BatchCNT:$uploadtrancnt, ProcessedCNT:$main::trncnt";
  }

  return $file_path, %result;
}


sub put_file_sftp {
  my ($file) = @_;
  my $remotedir = "";
  my $sftp = Net::SFTP->new("$main::ftp_host",'user' => $main::ftp_un, 'password' => $main::ftp_pw, 'Timeout' => 2400, 'Debug' => 1);



  ######   Need to stip out path to get just file name.
  my $remotedir = ".";

  my ($fname);
  my $remotefilename = $main::batchdate . "\.results\.txt";

  $sftp->put("$file","$remotefilename");

  my @file_list = $sftp->ls("$remotedir");
  foreach my $entry (@file_list) {
    my $filename = $entry->{'filename'};
    print "FILELISTING:$filename\n";
  }

}


1;
