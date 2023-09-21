#!/usr/bin/perl

require 5.001;
$|=1;

use lib '/home/p/pay1/perl_lib';
use miscutils;
use uploadbatch;
use GnuPG qw( :algo );
use File::Copy;
#use Net::SFTP;
use Net::SFTP::Foreign;

use strict;

## Process path.
## getfiles.pl  - retireves file and preprocesses it.
## uploadbatch.pl - load batches into batch que one at a time.
## retrieve results - gets batch results, write to file and ftp file back to ftp host.

## This script will:
## 1. Retrieve File from FTP Server place in inboundtemp dir.
## 2. Decrypt File and place decrypted version in workingtemp dir.
## 2. Preprocess File and Break Apart into smaller batches if necessary. Store files in inbound dir.

$main::username = "newprovide";
$main::deleteFlag = 1;

my $trans_date = $ARGV[0];

# File Paths
## Path for Enc. Retrieved Files
$main::inboundtemp_path = "/home/p/pay1/cronjobs/$main::username/inboundtemp";

## Path for decrypted files
#$main::workingtemp_path = "/home/p/pay1/web/payment/mservices/$main::username/decrypttemp";

## Path for pre-processed files ready to loaded into batch que.
$main::inbound_path = "/home/p/pay1/cronjobs/$main::username/inbound";

## Path for original encrypted archived files.
$main::archive_path = "/home/p/pay1/cronjobs/$main::username/archive";

# File Path for Files already processed
$main::postprocessed_path = "/home/p/pay1/cronjobs/$main::username/uploaded";

# File Path for Problem Files
$main::problem_path = "/home/p/pay1/cronjobs/$main::username/problem";

$main::breakapartflg = 0;
$main::preprocessflg = 0;

# Max Batch Size
$main::max_batch_size = 50;

$main::lastorderid = 0;

$main::dbh = &miscutils::dbhconnect("uploadbatch");

&retrieve_files($trans_date);

&preprocess();

&upload_btch();

$main::dbh->disconnect;

exit;


sub retrieve_files {
  my ($trans_date) = @_;

  my $ftphost = "sftp.morganwhite.com";

  ##  Host name nslookup returns 2 IP's
  #104.232.164.29 
  #12.230.140.222
  my %fileSize = ();

  my $ftpusername = "PlugnPay";
  my $ftppassword = "sFTP\@PlugNPay=5722";
  my $filename = "";
  my $remotedir = "/Outgoing";

  my %args = (user => $ftpusername, port => 22, password=>$ftppassword, 
              more => [-i => '/home/p/pay1/.ssh/id_rsa'] );

  my $sftp = Net::SFTP::Foreign->new("$ftphost", %args);

  if ($sftp eq "") {
    print "Host $ftphost is no good<br>\n";
    exit;
  }

  my ($fname);

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time());

  if ($trans_date < 20161101) {
    $trans_date = sprintf("%04d%02d%02d",$year+1900,$mon+1,$mday);
  }

  my $filemask = "PNPEXPORT_$trans_date";

  my $file_list = $sftp->ls("$remotedir");

  my ($fname);

  my @filelist = ();

  #my $filemask = "PNPEXPORT_$trans_date";

  $sftp->setcwd($remotedir);
  foreach my $entry (@$file_list) {
    $fname = $entry->{'filename'};
    $fname =~ s/[^0-9a-zA-Z\.\_\ ]//g;
    print "FN:$fname\n";
    if ($fname =~ /^$filemask/) {
      push (@filelist, $fname);
      $fileSize{$fname} = $entry->{'a'}->size;
    }
  }

  foreach my $filename (@filelist) {
    print "Getting: $filename\n";
    $sftp->get("$filename", "$main::inboundtemp_path/$filename");
    ### Check if size matches

    my $localSize = -s "$main::inboundtemp_path/$filename";
    if ($localSize == $fileSize{$filename}) {
      print "File:$filename Retrieved Successfully\n";
    }

    if ($main::deleteFlag == 1) {
      if ($localSize == $fileSize{$filename}) {
        ## Remove from remote dir.
        print "Removing $filename\n";
        $sftp->remove("$filename");
      }
    }
  }
  print "New Dir List\n";

  my $file_list = $sftp->ls("/$remotedir");
  foreach my $entry (@$file_list) {
    print $entry->{'filename'};
    print "\n";
  }

  $sftp->disconnect;


} 

sub preprocess {
  # Step One Read in File and Break Apart into max batch size if necessary
  # Get File Listing
  my @inbound_files = glob("$main::inboundtemp_path/*");
  foreach my $file (@inbound_files) {
    ## If file is NOT a plain file, go to next entry.
    if (! -f $file) {
      next;
    }

    $file =~ /\/(\w*\.tsv)$/;
    my $filename = $1;

    print "F:$file, FN:$filename\n";

    if ($main::preprocessflg == 1) {
      ## Preprocess File
      &preprocess_inbound($filename);
    }
    else {
      copy("$file","$main::inbound_path/$filename");
      unlink("$file");
    }
  }
}

sub preprocess_inbound {
  my ($filename) = @_;
  my $file = $main::inboundtemp_path . "/$filename";
  my($trancnt,$filecnt,$linenum,$file_header);
  my $filecnt = 1;
  open (INBOUND,"$file");
  while(<INBOUND>) {
    chop;
    $linenum++;
    #Test First Line for Header.
    if ($linenum == 1) {
      if ($_ !~ /^\!BATCH/) {
      # Exit with Error Message
        print "File $file, Invalid Format or Decryption Error\n";
        last;
      }
      else {
        $file_header = $_;
      }
      next;
    }
    $trancnt++;
 
    if ($trancnt == 1) {
      print "OPENING:$main::inbound_path/$filename\_$filecnt\.txt\n";
      open (WORKING,">$main::inbound_path/$filename\_$filecnt\.txt");
      print WORKING "$file_header\n";
    }
    if (($trancnt == $main::max_batch_size) && ($main::breakapartflg == 1)) {
      print WORKING "$_\n";
      $filecnt++;
      $trancnt = 0;
      close (WORKING);
    } 
    else {
      print WORKING "$_\n";
    }
  }
  close (WORKING);

  ## Remove Temp File.
  unlink("$file");

}


sub upload_btch {
  # Get File Listing
  my @inbound_files = glob("$main::inbound_path/PNPEXPORT*");

  if (@inbound_files < 1) {
    print "No Files Found\n";
    exit;
  }

  my (%result);
  my $message = "";

  my $filecnt = @inbound_files;
  print "FILECNT:$filecnt\n";
  #exit;

  foreach my $file (@inbound_files) {
    $main::trncnt = 0;
    my $data = "";

    if (! -f $file) {
      next;
    }

    print "XXXXX:$file\n";
    $file =~ /\/(\w*\.txt)$/;
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

    #print "DATA:$data:\n\n";
    #print "FN:$filename\n\n";

    #next;
    #exit;

    %result = &batch_file($filename,$data);

    print "STATUS:$result{'FinalStatus'}\n";

    if ($result{'FinalStatus'} eq "success") {
      ## Move File to PostProcessed Directory for ARchive Debug Purposes
      #copy("$file","$main::postprocessed_path/$filename");
      ## Delete File
      unlink("$file");
      $message = "Success";
    }
    else {
      ## Move File to Problem Directory for Debug Purposes
      copy("$file","$main::problem_path/$filename");
      ## Delete File
      unlink("$file"); 
      $message = "$result{'MErrMsg'}";
    }
    print "MESSAGE:$message\n";
  }
}

sub batch_file {
  my ($filename,$data) = @_;
  $main::loopcnt++;
  if ($main::loopcnt > 15) {
    print "Main Loop Cnt exceeded.  Exiting\n";
    exit;
  }
  #$dbh = &miscutils::dbhconnect("uploadbatch");

  #my $sndmail = $main::query->param('sndmail');
  #my $emailresults = $main::query->param('emailresults');
  #my $format = $main::query->param('header_format');

  my $merchant = "$main::username";
  my $sndmail = "no";
  my $emailresults = "";
  my $format = "yes";
  my $firstorderid = "";

  print "FN:$filename\n";
  #return;

  my $uploadbatch = uploadbatch->new($main::query);

  my (%result, $errvar);
  my $filelimit = 5000;
  my ($fileid,$date,$time) = &miscutils::genorderid();
 
  $data =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\r\n\t \,\!\+\|\$]/x/g;

  #return;
 
  my @data = split(/\r\n|\n/,$data);
 
  if (@data > $filelimit) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "File exceeds maximum transaction limit of $filelimit.";
    $uploadbatch::dbh->disconnect;
    return %result;
  }

  #return;
 
  my $trn_cnt = 1;
  my ($trans_id) = &miscutils::genorderid;

  my $lastorderid = "";
  my ($junk1,$junk2,$trans_time) = &miscutils::gendatetime();
  my $header = "";
 
  $header = shift @data;
  $filename =~ /^PNPEXPORT_([0-9]*)\.txt/;
  #PNPEXPORT_20160719090444.txt
  $uploadbatch::batchid = $1;
  #$uploadbatch::batchid .= "a";
  $uploadbatch::batchid =~ s/[^0-9_a-zA-Z]//g;

  if ($main::lastorderid > 0) {
    $firstorderid = &miscutils::incorderid($main::lastorderid);
  }
  else {
    $firstorderid = $trans_id;
  }

  $trans_id = $firstorderid;

  print "BatchID:$uploadbatch::batchid, First OID:$firstorderid\n";

  #return;
  if ($uploadbatch::batchid eq "") {
    print "Missing BatchID\n";
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Missing Batch ID.";
    $uploadbatch::dbh->disconnect;
    return %result;
  }

  # Make sure this batchid does not exist.
  my $sth = $main::dbh->prepare(qq{
          select batchid
          from batchfile
          where batchid='$uploadbatch::batchid'
  }) or &miscutils::errmail("__LINE__,__FILE__,Can't prepare: $DBI::errstr");
  $sth->execute or &miscutils::errmail("__LINE__,__FILE__,Can't prepare: $DBI::errstr");
  my ($batchid_exists) = $sth->fetchrow;
  $sth->finish;

  if ($batchid_exists ne "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "This Batch ID already exists.";
    $uploadbatch::dbh->disconnect;
    return %result;
  }

  foreach my $line (@data) {
    if ($line ne "") {
      $trn_cnt++;
      &uploadbatch::insert_transaction($uploadbatch::batchid,$trans_id,$merchant,$line,$trans_time,"$trn_cnt","","$header","$format");
    }
    $lastorderid = $trans_id;
    $trans_id = &miscutils::incorderid($trans_id);
  }
 
  &uploadbatch::insert_batch($uploadbatch::batchid,$firstorderid,$lastorderid,$merchant,$header,$format,$emailresults,$sndmail);
 
  &uploadbatch::finalize_batch($uploadbatch::batchid);

  $main::lastorderid = $lastorderid;

  if ($main::trncnt == $trn_cnt) {
    $result{'FinalStatus'} = "success";
    $result{'aux-msg'} =  "Batch uploaded successfully.";
  }
  else {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Transaction count mismatch. $trn_cnt:$main::trncnt";
  }

  $uploadbatch::dbh->disconnect;

  return %result;
}

1;

