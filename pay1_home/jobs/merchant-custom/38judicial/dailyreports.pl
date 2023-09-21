#!/usr/local/bin/perl

require 5.001;
local $|=0;

use lib '/home/p/pay1/perl_lib';
use miscutils;
use remote_strict;
use PlugNPay::GatewayAccount;
use PlugNPay::Features;
use PlugNPay::Transaction::Logging::Adjustment;
PlugNPay::Transaction::Adjustment::Settings;
use Net::SFTP;
use strict;

my (%query);

my $lookback = $ARGV[0];

my @now = gmtime(time() - ($lookback+1)*24*3600);
my $reportStartTime = sprintf("%04d%02d%02d000000", $now[5]+1900, $now[4]+1, $now[3]);

my @now = gmtime(time() - ($lookback+7)*24*3600);
$query{'startdate'} = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

my @now = gmtime(time() - ($lookback)*24*3600);
$query{'enddate'} = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

my $year = $now[5]+1900;

my $firstflag = "1";

$query{'mode'} = "query_trans";
$query{'operation'} = 'postauth';
$query{'result'} = "success";

#my @reportFields = ('trans_date','orderID','FinalStatus','card-amount','acct_code','baseAmount','adjustment','card-name','card-address1','card-city','card-state','card-zip');
#my @reportFields = ('trans_date','username','acct_code3','orderID','FinalStatus','card-amount','acct_code','baseAmount','adjustment','card-name');
my @reportFields = ('trans_date','username','acct_code3','orderID','FinalStatus','card-amount','adjustment','card-name','acct_code','acct_code2');

my %reportLabels = ('trans_date','Date','username','Account','acct_code3','Login','card-amount','Amount','baseAmount','Base Amount','adjustment','Fee','card-name','Cardholder Name');

my @merchants = ('38judicial','38jdavey1');
#my @merchants = ('taxprodemo');

my $reportName = "$query{'startdate'}\_$query{'enddate'}\.txt";
print "RPT STARTTIME:$reportStartTime, RPRT:$reportName\n";

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

  my $pnpremote = remote->new(@array);

  my %result = $pnpremote->query_trans();

  my @orderIDs = ();
  my @tranRefs = ();

  foreach my $key (sort keys %result) {
    if ($result{'FinalStatus'} ne "success") {
      $report = $result{'MErrMsg'};
      last;
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
      $report{'username'} = $merch;
      if (($report{'orderID'} ne "") && ($report{'trans_time'} > $reportStartTime)) {
        print "OID:$report{'orderID'}\n";
        push (@orderIDs,$report{'orderID'});
        push (@tranRefs, \%report)
      }
    }
  }

  foreach my $var (@reportFields) {
    if ($reportLabels{$var} ne "") {
      $report .= "$reportLabels{$var}\t";
    }
    else {
      $report .= "$var\t";
    }
  }
  $report .= "\n";

  foreach my $tranRef (@tranRefs) {
    my %report = %$tranRef;
    my $amt = $report{'card-amount'};
    $amt =~ s/[^0-9\.]//g;
    foreach my $var (@reportFields) {
      $report .= "$report{$var}\t";
    }
    $report .= "\n";
  }


  my $emailMessage = "Daily Report for $merch: $query{'startdate'} - $query{'enddate'}";

  print "MSG:$emailMessage\n";
  print "REPORT:\n$report\n\n";

  &email_file($merch,$emailMessage,$report,$reportName);
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

  sleep(5);
  my ($message_id,$date,$message_time) = &miscutils::genorderid();
  my ($to,$cc,$from,$subject);

  my $to = "kelly.lopez\@38cscd.org";
  my $cc = "dprice\@plugnpay.com\n";
  #my $cc = "";

  my $from = "support\@paywithcardx.com";
  my $subject = "Pay with CardX Daily Report - $date";
  my $htmlMessage = "";
  

  #print "UN:$username, Mesg:$textMessage, DATA:$data, FN:$filename\n\n";

  #return;

  my $dbh = &miscutils::dbhconnect("emailconf");

  #my $sth_sel = $dbh->prepare(qq{
  #      select to_address
  #      from message_queue
  #      where message_id=? 
  #      and username=?
  #}) or &miscutils::errmail(__LINE__,__FILE__,"\nCan't prepare: $DBI::errstr\n");
  #$sth_sel->execute() or &miscutils::errmail(__LINE__,__FILE__,"\nCan't execute: $DBI::errstr\n");


  print "Insert into Queue\n";
  print "TO:$to, FROM:$from,  CC:$cc, SUBJECT:$subject, MID:$message_id, MESGTIME:$message_time, UN:$username, STATIS:pending,  HTML:$htmlMessage, TXT:$textMessage\n";
  #print "DATA:$data\n";

  my $sth_email = $dbh->prepare(qq{
     insert into message_queue
     (to_address,from_address,cc_address,subject,message_id,insert_time,username,status,html_version,text_version)
     values (?,?,?,?,?,?,?,?,?,?)
  }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth_email->execute($to,$from,$cc,$subject,$message_id,$message_time,$username,'pending',$htmlMessage,$textMessage) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
  $sth_email->finish;

  print "Insert into Attachment\n";
  print "$message_id,$message_id,$message_time,$username,$filename\n";
  #print "DATA:$data\n";

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
