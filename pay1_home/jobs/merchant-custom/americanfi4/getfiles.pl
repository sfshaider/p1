#!/bin/env perl

require 5.001;
$|=1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use File::Copy;
use Net::SFTP;
use PlugNPay::ResponseLink;
use strict;

## Process path.
## getfiles.pl  - retireves file and preprocesses it.
## uploadbatch.pl - load batches into batch que one at a time.
## retrieve results - gets batch results, write to file and ftp file back to ftp host.

## This script will:
## 1. Retrieve File from FTP Server place in inboundtemp dir.
## 2. Decrypt File and place decrypted version in workingtemp dir.
## 2. Preprocess File and Break Apart into smaller batches if necessary. Store files in inbound dir.


# File Paths
## Path for Enc. Retrieved Files
$main::inboundtemp_path = '/home/pay1/cronjobs/americanfi4/inboundtemp';

## Path for pre-processed files ready to loaded into batch que.
$main::inbound_path = '/home/pay1/cronjobs/americanfi4/inbound';

## Path for original encrypted archived files.
$main::archive_path = '/home/pay1/cronjobs/americanfi4/archive';

# File Path for Files already processed
$main::resultstemp_path = '/home/pay1/cronjobs/americanfi4/resultstemp';

$main::breakapartflg = 0;
$main::preprocessflg = 0;

# Max Batch Size
$main::max_batch_size = 50;

$main::lastorderid = 0;

print "-----------------------------------------------------------------\n";
my ($dummy,$datestr,$timestr) = &miscutils::gendatetime();
print "\n$timestr, Starting Process\n";

&retrieve_files();
&process();
&return_results();

print "-----------------------------------------------------------------\n";
($dummy,$datestr,$timestr) = &miscutils::gendatetime();
print "\n$timestr, Endded Process\n";

exit;

sub retrieve_files {
  print "\n** STAGE #1 - Retrieve Files **\n";

  my $ftphost     = 'sftp.afadvantage.com';
  my $ftpusername = 'plugnpay';
  my $ftppassword = 'HL41jNii';
  my $remotedir   = './fromAFA';

  my $sftp = Net::SFTP->new($ftphost, 'user' => $ftpusername, 'password' => $ftppassword, 'Timeout' => 2400, 'Debug' => 1);
  if ($sftp->status) {
    my $status = $sftp->status;
    print "Host $ftphost is no good [$status]\n";
    exit;
  }

  my ($fname,$detail,$details);
  my @array = $sftp->ls($remotedir, $details);

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  my $trans_date = sprintf("%04d%02d%02d",$year+1900,$mon+1,$mday);

  my ($dummy,$transdate,$transtime) = &miscutils::gendatetime();
  #$transdate = '20160104';

  my $filemask = "CCARDC1[0-3]{1}.FILE[0-9]{3}\.$transdate";
  #print "FM: $filemask\n";

  my @filelist = ();
  foreach my $entry (@array) {
    #print "ENTRY: $entry\n";
    $fname = $entry->{'filename'};
    $detail = $entry->{'longname'};
    
    print "File: $fname,  Details: $detail\n";

    if ($fname =~ /^$filemask/) {
      print "-> Pushing: $fname\n";
      push (@filelist, $fname);
    }
  }

  foreach my $filename (@filelist) {
    print "Retrieving File: $remotedir/$filename -> $main::inboundtemp_path/$filename\n";
    $sftp->get("$remotedir/$filename", "$main::inboundtemp_path/$filename");

    #my @status = $sftp->status;
    #print "STATUS: $status[0] $status[1]\n";

    if (-e "$main::inboundtemp_path/$filename") {
      ### Delete File off Server ?
      $sftp->do_remove("$remotedir/$filename");
      print "-> Removed From Remote: $remotedir/$filename\n";
    }
  }
  #$sftp->do_close();
} 

sub process {
  print "\n** STAGE #2 - Process Files **\n";

  # Get File Listing
  my @inbound_files = glob("$main::inboundtemp_path/*");

  if (@inbound_files == 0) {
    print "No Files Retrieved\n";
    exit;
  }

  foreach my $file (@inbound_files) {
    print "Looking...\n";
    ## If file is NOT a plain file, go to next entry.
    if (! -f $file) {
      next;
    }

    $file =~ /\/([\w\.]+\.XML)$/i;
    my $filename = $1;

    ## Check if file stub exists and skip.  
    if (-e "$main::inbound_path/$filename") {
      #next;
    }

    print "Starting Processing F: $file, FN: $filename\n";
    &post_XML($file,$filename);
  }
}


sub post_XML {
  my ($file,$filename) = @_;
  my $pairs = '';

  if (!-e $file) {
    ### Exit and report error
    print "File Not Found - $file\n";
    exit;
  }

  my $log_data = '';
  open(DATA,'<',$file) or print "WARNING: Can't open $file for reading. $!\n";
  while(<DATA>) {
    $pairs .= $_;
    $log_data .= $_;
  }
  close(DATA);

  $log_data =~ s/\<Password\>([\w]*)\<\/Password\>/\<Password\>&filter($1)\<\/Password\>/;

  $pairs =~ s/(\W)/'%' . unpack('H2',$1)/ge;
  my $len = length($pairs);
  my $postLink = 'https://pay1.plugnpay.com/payment/xml.cgi';

  my $rl = new PlugNPay::ResponseLink('processor_plugnpay',$postLink,$pairs,'post','meta');
  $rl->setRequestContentType('application/x-www-form-urlencoded');
  $rl->addRequestHeader('Host','pay1.plugnpay.com:443');
  $rl->addRequestHeader('Accept','*/*');
  $rl->addRequestHeader('Content-Length',$len);
  $rl->doRequest();

  my $response = $rl->getResponseContent;
  my %headers = $rl->getResponseHeaders;
  ##
  my $mytime = localtime(time);
  open(TMPFILE,'>>','/home/pay1/cronjobs/americanfi4/americanfi4_debug.txt') or print "WARNING: Can't open debug file for appending. $!\n";
  print TMPFILE "$mytime,  RA:$ENV{'REMOTE_ADDR'},  PID:$$, PAIRS:$pairs\n";
  print TMPFILE "RESP:$response:\n";
  close(TMPFILE);

  print "Completed Processing $file\n";

  ##  Move File to Inbound Folder
  open (ARCHIVE,'>',"$main::inbound_path/$filename") or print "WARNING: Can't open $main::inbound_path/$filename for writing. $!\n";
  print ARCHIVE $log_data;
  close(ARCHIVE);

  #print "Moving File: $file -> $main::inbound_path/$filename\n";
  move($file, "$main::inbound_path/$filename");

  print "Erasing File: $main::inbound_path/$filename\n";
  ## Erase File but Leave PAth
  #open(INBOUND,'>',"$main::inbound_path/$filename") or print "WARNING: Can't blank file $main::inbound_path/$filename. $!\n";
  #close(INBOUND);

  $filename =~ s/XML/results\.XML/;

  ##  Write Results to Results Folder
  print "Writing Results To: $main::resultstemp_path/$filename\n";
  open(DATA,'>',"$main::resultstemp_path/$filename") or print "WARNING: Can't open $main::resultstemp_path/$filename for writing. $!\n";
  print DATA $response;
  close(DATA);
}


sub return_results {
  print "\n** STAGE #3: Return Results **\n";

  ## Foreach File in $main::resultstemp_path
  ## SFTP back to merchant and move File to Archive.

  my @outbound_files = glob("$main::resultstemp_path/*");

  if (@outbound_files == 0) {
    print "No Files Processed.\n";
    return;
  }

  my $ftphost     = 'sftp.afadvantage.com';
  my $ftpusername = 'plugnpay';
  my $ftppassword = 'HL41jNii';
  my $remotedir   = './toAFA';

  print "Starting FTP\n";
  my $sftp = Net::SFTP->new($ftphost, 'user' => $ftpusername, 'password' => $ftppassword, 'Timeout' => 2400, 'Debug' => 1);
  if ($sftp->status) {
    my $status = $sftp->status;
    print "Host $ftphost is no good [$status]\n";
    exit;
  }

  my ($fname);

  # Get File Listing
  #my @outbound_files = glob("$main::resultstemp_path/*");
  foreach my $file (@outbound_files) {
    ## If file is NOT a plain file, go to next entry.
    if (! -f $file) {
      next;
    }
    $file =~ /resultstemp\/(.+\.results\.XML)$/;
    my $filename = $1;
    print "Uploading File: $filename, $file,\n";

    #next;
    $sftp->put($file, "$remotedir/$filename");

    print "Moving Results to Archive: $file -> $main::archive_path/$filename\n";
    move($file,"$main::archive_path/$filename");
  }
}

sub filter {
  my ($data) = @_;
  $data =~ s/./X/g;
  return $data;
}


1;
