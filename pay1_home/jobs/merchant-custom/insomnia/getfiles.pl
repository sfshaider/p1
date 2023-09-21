#!/usr/bin/perl

require 5.001;
$|=1;

use lib '/home/p/pay1/perl_lib';
use lib '/usr/share/import/bin';

use miscutils;
use uploadbatch;
use File::Copy;
use Net::SFTP;
use PlugNPay::GatewayAccount;
use PlugNPay::Features;
#use strict;

## Process path.
## getfiles.pl  - retireves file and preprocesses it then load batches into batch que one at a time.
## retrieve results - gets batch results, write to file and ftp file back to ftp host.

## This script will:
## 1. Retrieve File from FTP Server place in inboundtemp dir.
## 2. Decrypt File and place decrypted version in workingtemp dir.
## 3. Preprocess File and Break Apart into smaller batches if necessary. Store files in inbound dir.
## 4. Take each batch created and upload into que.


## Changes
#  20160516 changed sprintf to create batch ID to support 3 digits.
#  20200409 fixed setting upload batch priority


# File Paths

my $lookback = 1;

$main::base_path = "/home/p/pay1/cronjobs/insomnia/";

## Path for raw files to be split by username
$main::inbound_temp_path = "$main::base_path" . "inboundtemp";

## Path for pre-processed files ready to loaded into batch que.
$main::inbound_path = "$main::base_path" . "inbound";

## Path for original encrypted archived files.
$main::archive_path = "$main::base_path" . "archive";

# File Path for Files already processed
$main::postprocessed_path = "$main::base_path" . "uploaded";

## Multiple Insert Flag
$main::multi_insert_flag = 1;

## SFTP Info
#$main::ftp_host = "52.200.105.167";
$main::ftp_host = "52.45.39.70";  ## As of 12/28/2016
$main::ftp_un = "pgwuser";
$main::ftp_pw = "xEgxQzE5BaHMV2m";  ## as of 04/28/2016
my $filename = "";

my ($orderid,$todaysdate,$time) = &miscutils::gendatetime((-24*$lookback)*3600);

$main::todaysdate = $todaysdate;
$main::todaystime = $time;
$main::currenthour = substr($time,8,2);

#$main::todaysdate = "20181005";

my $yr = substr($main::todaysdate,0,4);
my $mo = substr($main::todaysdate,4,2);
my $dy = substr($main::todaysdate,6,2);

my $fn = $ARGV[0];
$fn =~ s/[^0-9a-zA-Z\.\-\_]//g;

if ($fn =~ /\.txt$/) {
  $filename = $fn;
}
else {
  $filename = "$yr\-$mo\-$dy\-\.txt";
}

#$filename = "custombatch.txt";

my $now = gmtime(time());
print "$now, STARTING FTP\n";

## Retrieve file and place in temp directory.
&get_file_sftp($filename); 

#exit;

# Step One Read in File and Break Apart into max batch size if necessary
# Get File Listing

my @inbound_files = glob("$main::inbound_temp_path/*");

foreach my $file (@inbound_files) {
  ## If file is NOT a plain file, go to next entry.
  if (! -f $file) {
    next;
  }
  ## Preprocess File
  print "FILE:$file\n";

  &preprocess_inbound($file);
  last;

}

&upload_batch();

exit;


sub preprocess_inbound {
  my ($file) = @_;

  my($trancnt,$filecnt,$linenum,$file_header);
  my $filecnt = 1;
  my @vars = ();
  my %merchants = ();
  open (INBOUND,"$file");
  while(<INBOUND>) {
    chop;
    $linenum++;
    #Test First Line for Header.
    if ($linenum == 1) {
      if ($_ !~ /^\!BATCH/) {
      # Exit with Error Message
        print "File $file, Invalid Format\n";
        last;
      }
      else {
        $file_header = $_;
      }
      my $idx=0;
      @vars = split(/\t/,$file_header);
      next;
    }
    $trancnt++;

    my %data = ();
    my $varcnt = @vars;
    my @vals = split(/\t/);
    for (my $idx = 0; $idx <= $varcnt; $idx++) {
      $data{$vars[$idx]}=$vals[$idx];
    } 
    my $merchant = $data{'publisher-name'};
    push (@{$merchant},$_);
    $merchants{$merchant} = 1;
  }

  foreach my $merchant (sort keys %merchants) {
    my ($orderid,$datestr,$timestr) = &miscutils::genorderid();
    print "OPENING:$main::inbound_path/$merchant\_$timestr\_$filecnt\.txt\n";
    open (WORKING,">$main::inbound_path/$merchant\_$timestr\_$filecnt\.txt");
    print WORKING "$file_header\n";
    foreach my $line (@{$merchant}) {
      print WORKING "$line\n";
    }
    close (WORKING);
  }
  close (WORKING);

  ## Remove Temp File.
  unlink("$file");
}

## Upload Batch Section

sub upload_batch {
  my $now = gmtime(time());
  my ($oldorderid,$dummy,$time) = &miscutils::genorderid;

  # Get File Listing

  my @inbound_files = glob("$main::inbound_path/*");

  if (@inbound_files < 1) {
    print "$now, No Files Found";
    exit;
  }

  my (%result);
  my $message = "";

  foreach my $file (@inbound_files) {
    my ($trans_id,$dummy,$dummy) = &miscutils::incorderid($oldorderid);
    $oldorderid = $trans_id;

    $main::trncnt = 0;
    my $data = "";

    if (! -f $file) {
      next;
    }

    print "$now, $file\n";

    $file =~ /\/(\d*\.txt)$/;
    my $filename = $1;

    open (INPUT,"$file");
    while(<INPUT>) {
      s/%(..)/pack('c',hex($1))/eg;
      s/\+/ /g;  #substitue spaces for + sign
      if ($_ =~ /\w/) {
        $data .= $_;
        $main::trncnt++;
      }
    }
    close(INPUT);

    my $tempdata = $data;
    $tempdata =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\r\n\t \,\!\+\|\$]/x/g;
    my @tdata = split(/\r\n|\n/,$tempdata);
    my $f4 = $tdata[0] . $tdata[1] . $tdata[2] . $tdata[3];
    
    #print "$now\nDATA:$f4:\n\n";
    #print "$now, File:$file\n\n";
    #print "$now, FName:$filename\n\n";

    #exit;

    %result = &batch_file($data,$trans_id);

    if ($result{'FinalStatus'} eq "success") {
      print "$now, MOVING $file to $main::postprocessed_path/$filename\n";

      ## Move File to PostProcessed Directory for Archive Debug Purposes
      copy("$file","$main::postprocessed_path/$filename");
      ## Delete File
      unlink("$file");
      $message = "Success";
    }
    else {
      $message = "$result{'MErrMsg'}";
      ## Delete File
      unlink("$file");
    }
    print "$time, MESSAGE:$message\n";

    ## Commenting out 20080202  DCP.  To allow processing multiple files.
    #last;
  }
}


sub batch_file {
  my ($data,$trans_id) = @_;

  my $dbh = &miscutils::dbhconnect("uploadbatch");

  my $merchant = "";
  my $sndmail = "no";
  my $emailresults = "";
  my $format = "yes";

  my $uploadbatch = uploadbatch->new();
 
  my (%result, $errvar);
  my $filelimit = 15000;
  my ($fileid,$date,$time) = &miscutils::genorderid();
 
  $data =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\r\n\t \,\!\+\|\$]/x/g;
 
  my @data = split(/\r\n|\n/,$data);
 
  if (@data > $filelimit) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "File exceeds maximum transaction limit of $filelimit.";
    return %result;
  }
 
  my $trn_cnt = 1;
  #my ($trans_id) = &miscutils::genorderid;

  my $lastorderid = "";
  my ($junk1,$batchid,$trans_time) = &miscutils::gendatetime();
  my $header = "";
 
  $header = shift @data;

  my (@fields) = split('\t',$header);

  ## Grab BatchID
  my $firstline = @data[0];
  my (@merchdata) = split('\t',$firstline);
  my %merchdata = ();
  my $i = 0;
  foreach my $var (@fields) {
    $merchdata{$var} = $merchdata[$i];
    $i++;
  }
  $merchant = $merchdata{'publisher-name'};
  my $bid = $merchant;
  $bid = "ICOOK_" . $bid . "_" . $main::todaysdate . $main::currenthour;
  $uploadbatch::batchid = $bid;


  $uploadbatch::upload_batch_priority = &batchPriority($merchant);

  my $now = gmtime(time());
  print "$now, BATCHID:$uploadbatch::batchid\n";

  if ($uploadbatch::batchid eq "") {
    print "Missing BatchID. - Exiting\n";
    exit;
  }

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
  #my $oid = sprintf("%04d%02d%02d%02d",$year,$mon,$mday,$hour);

  #$trans_id = substr($trans_time,0,10) . "00001";

  my $firstorderid = $trans_id;

  # Make sure this batchid does not exist.
  my $sth = $dbh->prepare(qq{
          select batchid
          from batchfile
          where batchid='$uploadbatch::batchid'
  }) or &miscutils::errmail("__LINE__,__FILE__,Can't prepare: $DBI::errstr");
  $sth->execute or &miscutils::errmail("__LINE__,__FILE__,Can't prepare: $DBI::errstr");
  my ($batchid_exists) = $sth->fetchrow;
  $sth->finish;

  if ($batchid_exists ne "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "This Batch ID,$uploadbatch::batchid,  already exists.";
    return %result;
  }

  if (1) {
    my $insert_tran_cnt = 20;
    my @array1 = ();
    my @array2 = ();
    foreach my $line (@data) {
      my $temp_line = $line;
      $temp_line =~ s/\t//g;
      if (($line ne "")&& ($temp_line ne "") && ($line !~ /^\!batch/i)) {
        $trn_cnt++;
        @array2 = ("$uploadbatch::batchid","$trans_id","$merchant","$line","$trans_time","$trn_cnt","","$header","");
        $array1[++$#array1] = [@array2];
        $lastorderid = $trans_id;
        $trans_id = &miscutils::incorderid($trans_id);
        if (@array1 == $insert_tran_cnt) {
          &uploadbatch::insert_transaction_multi(\@array1);
          @array1 = ();
        }
      }
    } 
    ## Last
    if (@array1 > 0) {
      &uploadbatch::insert_transaction_multi(\@array1);
      @array1 = ();
    }
  }

  print "INSERTBATCH: $uploadbatch::batchid,$firstorderid,$lastorderid,$merchant,$header,$format,$emailresults,$sndmail\n";

  &uploadbatch::insert_batch($uploadbatch::batchid,$firstorderid,$lastorderid,$merchant,$header,$format,$emailresults,$sndmail);
 
  print "FINALIZE BATCH: $uploadbatch::batchid\n";

  &uploadbatch::finalize_batch($uploadbatch::batchid);

  $dbh->disconnect;

  if ($main::trncnt == $trn_cnt) {
    $result{'FinalStatus'} = "success";
    $result{'aux-msg'} =  "Batch uploaded successfully.";
  }
  else {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Transaction count mismatch. $trn_cnt:$main::trncnt";
  }
  return %result;
}



sub get_file_sftp {
  my($filename) = @_;
  my ($orderid,$dummy,$time) = &miscutils::genorderid;

  my $remotedir = "./";

  my $local_filename = "$main::inbound_temp_path/pnpay.outbound.$time";
  my $remote_filename = $remotedir . "$filename";

  print "Attempting to retrieve: $remote_filename\n";

  my $sftp = Net::SFTP->new("$main::ftp_host",'user' => $main::ftp_un, 'password' => $main::ftp_pw, 'Timeout' => 2400, 'Debug' => 1);

  my @file_list = $sftp->ls("$remotedir");
  foreach my $entry (@file_list) {
    my $filename = $entry->{'filename'};
    print "FILELISTING:$filename\n";
  }

  my ($fname);

  $sftp->get("$remote_filename","$local_filename");

  print "$local_filename\n";


}

sub batchPriority {
  my ($username) = @_;
  my ($upload_batch_priority);
  my $gatewayAccount = new PlugNPay::GatewayAccount($username);
  my $accountFeatures = $gatewayAccount->getFeatures();
  if (($accountFeatures->get('upload_batch_priority') > 0) || ($accountFeatures->get('upload_batch_priority') < 0 )) {
    $upload_batch_priority = $accountFeatures->get('upload_batch_priority');
  }
  else {
    $upload_batch_priority = 0;
  }
  $upload_batch_priority = substr($upload_batch_priority,0,2);

  return $upload_batch_priority;
}



1;

