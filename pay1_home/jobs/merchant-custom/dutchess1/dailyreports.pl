#!/usr/local/bin/perl

require 5.001;
local $|=0;

use lib '/home/p/pay1/perl_lib';
use remote_strict;
use PlugNPay::GatewayAccount;
use PlugNPay::Features;
use PlugNPay::Transaction::Logging::Adjustment;
use PlugNPay::Transaction::Adjustment::Settings;
use Net::SFTP;
use strict;
use miscutils;

my (%query);
my ($operation);

my $lookback = $ARGV[0];
my $debug = $ARGV[1];

if ($debug eq "auth") {
  $operation = "postauth";
  $debug = "";
}
else {
  $operation = 'postauth';
}

my $delimeter = ',';
if ($lookback !~ /[0-9]/) {
  $lookback = 0;
}

my $now = gmtime(time());
print "Report Run Time: $now\n";

my $timestr = time();

if ($lookback =~ /^202[0-9]/) {
  $lookback = substr($lookback,0,8) . "000000";
  print "LB:$lookback\n";
  $timestr = &miscutils::strtotime($lookback);
  $lookback = 0;
}

my $deltaDays = (time() - $timestr)/(3600*24);

print "Delta in Days:$deltaDays\n";

## Start Date
my @now = gmtime($timestr - ($lookback+1)*24*3600);
$query{'startdate'} = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

## Start Time
my @now = gmtime($timestr - ($lookback)*24*3600);
$query{'starttime'} = sprintf("%04d%02d%02d000000", $now[5]+1900, $now[4]+1, $now[3]);

## End Date
my @now = gmtime($timestr - ($lookback - 1)*24*3600);
$query{'enddate'} = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

## End Time
my @now = gmtime($timestr - ($lookback - 1)*24*3600);
$query{'endtime'} = sprintf("%04d%02d%02d000000", $now[5]+1900, $now[4]+1, $now[3]);

my $year = $now[5]+1900;

my $firstflag = "1";

$query{'mode'} = "query_trans";
$query{'operation'} = $operation;
$query{'result'} = "success";
#$query{'result'} = "pending";

print "SD:$query{'startdate'}, ST:$query{'starttime'}, ED:$query{'enddate'}, ET:$query{'endtime'}\n";

#exit;

#The important columns are the client lookup (column 9), (acct_code) the amount (col 10, card-amount), the check # ( I think that's col 6) and the date (col 11, trans_date). 
#To be sure we don't need them in this order, and the date can be in a more normal format such as mm/dd/yy or something like that.  
#We may be able to import an existing format that you may have done for some other customer.  The import format is very flexible. It can be Excel, or CSV.

#my @reportFields = ('trans_date','username','acct_code3','orderID','FinalStatus','card-amount','acct_code','baseAmount','adjustment','card-name');
my @reportFields = ('trans_date','acct_code','acct_code2','card-amount','adjustment','card-name');
my @reportFields = ('trans_date','acct_code2','card-amount','card-name','orderID');

my %reportLabels = ('trans_date','Date','acct_code2','LocatorID','card-amount','Amount','card-name','Cardholder Name','orderID','ReceiptID');

my @merchants = ('dutchess1');

my $reportName = substr($query{'starttime'},0,8) . "\_$query{'enddate'}\.txt";
print "RPRT:$reportName\n";

foreach my $merch (@merchants) {

  my $accountFeatures = new PlugNPay::Features($merch,'general');
  my $gatewayAccount = new PlugNPay::GatewayAccount($merch);
  #my $adjustmentSettings = new PlugNPay::Transaction::Adjustment::Settings($merch);
  my $adjustmentLog = new PlugNPay::Transaction::Logging::Adjustment();

  my ($adjustmentFlag, $surchargeFlag) = &getAdjustmentFlags($merch, $accountFeatures, $gatewayAccount);

  my $report = "";
  delete $query{'publisher-name'};
  $query{'publisher-name'} = "$merch";

  my @array = %query;

  foreach my $key (sort keys %query) {
    print "$key:$query{$key}\n";
  }

  my $pnpremote = remote->new(@array);

  my %result = $pnpremote->query_trans();

  my @orderIDs = ();
  my @tranRefs = ();

  foreach my $key (sort keys %result) {
    if ($result{'FinalStatus'} ne "success") {
      print "Start Date: $query{'startdate'}, End Date:$query{'enddate'}, MErrMsg:$result{'MErrMsg'}\n";
      exit;
    }
    my %report = ();

    print "K:$key:$result{$key}\n";

    if ($key =~ /^a\d+$/) {
      foreach my $pair (split('&',$result{$key})) {
        if ($pair =~ /(.*)=(.*)/) { #found key=value;#
          my ($key,$value) = ($1,$2);  #get key, value
         $value =~ s/%(..)/pack('c',hex($1))/eg;
         $report{$key} = $value;
        }
      }
      #if ($report{'orderID'} eq "2022112123255022722") {
      #  next;
      #}
      if ($report{'trans_time'} < $query{'starttime'}) {
        next;
      }
      if ($report{'trans_time'} > $query{'endtime'}) {
        next;
      }
      $report{'username'} = $merch;
      $report{'trans_date'} = substr($report{'trans_date'},4,2) . "/" . substr($report{'trans_date'},6,2) . "/" . substr($report{'trans_date'},0,4);
      if ($report{'orderID'} ne "") {
        print "OID:$report{'orderID'}\n";
        push (@orderIDs,$report{'orderID'});
        push (@tranRefs, \%report)
      }
    }
  }

  foreach my $var (@reportFields) {
    if ($reportLabels{$var} ne "") {
      $report .= "$reportLabels{$var}$delimeter";
    }
    else {
      $var =~ s/$delimeter//g;
      $report .= "$var$delimeter";
    }
  }
  chop $report;
  $report .= "\n";

  foreach my $tranRef (@tranRefs) {
    my %report = %$tranRef;
    my $amt = $report{'card-amount'};
    $amt =~ s/[^0-9\.]//g;
    foreach my $var (@reportFields) {
      $report .= "$report{$var}$delimeter";
    }
    chop $report;
    $report .= "\n";
  }

  print "REPORT:\n$report\n\n";

  my $emailMessage = "Daily Report for $merch: $query{'startdate'} - $query{'enddate'}";

  if (! $debug) {
    &email_file($merch,$emailMessage,$report,$reportName);
  }
}


exit;

### Now FTP the File


sub put_file_sftp {
  my ($filename,$report_name) = @_;

  print "RN:$report_name, FULLPATH:$filename\n";

  my $ftphost = "";
  my $ftpusername = "";
  my $ftppassword = "";
  my $remotedir = "/";
  my $remotedir = "";
  my $sftp = Net::SFTP->new("$ftphost",'user' => $ftpusername, 'password' => $ftppassword, 'Timeout' => 2400, 'Debug' => 1);

  my ($fname);

  my $remotefilename = $remotedir . $report_name;

  $sftp->put("$filename","$remotefilename");

  my @file_list = $sftp->ls("$remotedir");
  foreach my $entry (@file_list) {
    my $filename = $entry->{'filename'};
    print "FILELISTING:$filename\n";
  }
}


sub email_file {
  my ($username,$textMessage,$data,$filename) = @_;

  #sleep(5);
  my ($message_id,$date,$message_time) = &miscutils::genorderid();
  my ($to,$cc,$from,$subject);

  my $to = "dcwwabilling\@dutchessny.gov";
  #my $to = "dprice\@plugnpay.com";
  my $cc = "dprice\@plugnpay.com\n";
  my $from = "support\@paywithcardx.com";
  my $subject = "Pay with CardX Daily Report - $date";
  my $htmlMessage = "";
  

  #print "UN:$username, Mesg:$textMessage, DATA:$data, FN:$filename\n\n";

  #return;

  my $dbh = &miscutils::dbhconnect("emailconf");

  print "Insert into Queue\n";
  print "TO:$to, FROM:$from,  CC:$cc, SUBJECT:$subject, MSGID:$message_id, MESGTIME:$message_time, UN:$username, STATUS:pending,  HTML:$htmlMessage, TXT:$textMessage\n";
  print "DATA:$data\n";

  my $sth_email = $dbh->prepare(qq{
     insert into message_queue
     (to_address,from_address,cc_address,subject,message_id,insert_time,username,status,html_version,text_version)
     values (?,?,?,?,?,?,?,?,?,?)
  }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth_email->execute($to,$from,$cc,$subject,$message_id,$message_time,$username,'pending',$htmlMessage,$textMessage) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
  $sth_email->finish;

  print "Insert into Attachment\n";
  print "$message_id,$message_id,$message_time,$username,$filename\n";
  print "DATA:$data\n";

  my $sth_email = $dbh->prepare(qq{
     insert into message_attachment
     (message_id,attachment_id,insert_time,username,filename,data)
     values (?,?,?,?,?,?)
  }) or (__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  #&miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth_email->execute($message_id,$message_id,$message_time,$username,$filename,$data) or (__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  #or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
  $sth_email->finish;


  $dbh->disconnect;

  return;

}


sub getAdjustmentFlags {
  my $username = shift;
  my $accountFeatures = shift;
  my $gatewayAccount = shift;

  my $adjustmentFlag = 0;
  my $surchargeFlag = 0;

  if ($accountFeatures->get('convfee')) {
    my $cf = new PlugNPay::ConvenienceFee($username);
    if ($cf->getEnabled()) {
      $adjustmentFlag = 1;
      if ($cf->isSurcharge()) {
        $surchargeFlag = 1;
      }
    }
  }
  elsif ($accountFeatures->get('cardcharge')) {
    my $coa = new PlugNPay::COA($username);
    if ($coa->getEnabled()) {
      $adjustmentFlag = 1;
      if ($coa->isSurcharge()) {
        $surchargeFlag = 1;
      }
    }
  }
  return ($adjustmentFlag, $surchargeFlag);
}


sub loadMultipleAdjustments {
  my $username = shift;
  my $orderIDs = shift;
  my $adjustmentLog = shift;
  $adjustmentLog->setGatewayAccount($username);
  my $adjustments = $adjustmentLog->loadMultiple($orderIDs);

  return $adjustments;
}


1;
