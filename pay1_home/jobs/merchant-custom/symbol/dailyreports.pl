#!/bin/env perl

require 5.001;
$|=0;

use lib $ENV{'PNP_PERL_LIB'};
use remote_strict;
use PlugNPay::GatewayAccount;
use PlugNPay::GatewayAccount::InternalID;
use PlugNPay::Features;
use PlugNPay::Order::SupplementalData;
use PlugNPay::Transaction::Logging::Adjustment;
use PlugNPay::Transaction::Adjustment::Settings;
use Date::Calc qw(Delta_Days Add_Delta_Days);
use Data::Dumper;
use Net::SFTP;
use strict;
use miscutils;

my %query;
my $operation;

my $lookback = $ARGV[0];
my $debug = $ARGV[1];

if ($debug eq 'auth') {
  $operation = 'auth';
  $debug = '';
}
else {
  $operation = 'postauth';
}

my $delimeter = ',';
if ($lookback !~ /[0-9]/) {
  $lookback = 0;
}

#  Set Amt Field, charged|base
my $amountFlag = "base";


my $now = gmtime(time());
print "Report Run Time: $now\n";

## Start Date
my @now = gmtime(time() - ($lookback+1)*24*3600);
$query{'startdate'} = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

## Start Time
@now = gmtime(time() - ($lookback)*24*3600);
$query{'starttime'} = sprintf("%04d%02d%02d000000", $now[5]+1900, $now[4]+1, $now[3]);

## End Date
@now = gmtime(time() - ($lookback)*24*3600);
$query{'enddate'} = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

## For Testing
#$query{'startdate'} = "20200701";
#$query{'enddate'} =   "20200705";

my $year = $now[5]+1900;

my $firstflag = '1';

$query{'mode'} = 'query_trans';
$query{'operation'} = $operation;
$query{'result'} = 'success';

#The important columns are the client lookup (column 9), (acct_code) the amount (col 10, card-amount), the check # ( I think that's col 6) and the date (col 11, trans_date). 
#To be sure we don't need them in this order, and the date can be in a more normal format such as mm/dd/yy or something like that.  
#We may be able to import an existing format that you may have done for some other customer.  The import format is very flexible. It can be Excel, or CSV.

#my @reportFields = ('trans_date','username','acct_code3','orderID','FinalStatus','card-amount','acct_code','baseAmount','adjustment','card-name');
#my @reportFields = ('trans_date','acct_code','acct_code2','card-amount','adjustment','card-name');
my @reportFields = ('trans_date','acct_code','acct_code2','card-amount','card-name','orderID','runningTotal','fileTotal','PaymentType','PaymentID');

my %reportLabels = ('trans_date','Date','acct_code','Customer Number','acct_code2','InvoiceNum','card-amount','Amount','card-name','Cardholder Name','orderID','TransactionID','PaymentType','PaymentType','runningTotal','RunningTotal','fileTotal','Deposit Amount','PaymentID','PaymentID');

#my @merchants = ('symboldemo');
my @merchants = ('symbolart1');

#my $reportName = substr($query{'starttime'},0,8) . "\_$query{'enddate'}\.txt";
#print "RPRT:$reportName\n";

foreach my $merch (@merchants) {
  my $reportName = $merch . "_" . substr($query{'starttime'},0,8) . "\_$query{'enddate'}\.txt";
  print "RPRT:$reportName\n";

  my $accountFeatures = new PlugNPay::Features($merch,'general');
  my $gatewayAccount = new PlugNPay::GatewayAccount($merch);
  my $adjustmentSettings = new PlugNPay::Transaction::Adjustment::Settings($merch);
  my $adjustmentLog = new PlugNPay::Transaction::Logging::Adjustment();

  my ($adjustmentFlag, $surchargeFlag) = &getAdjustmentFlags($merch, $accountFeatures, $gatewayAccount);

  my $report = '';
  my $reportHeader = '';

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
  my %masterReport = ();

  my $Dd = Delta_Days(substr($query{'startdate'},0,4), substr($query{'startdate'},4,2), substr($query{'startdate'},6,2), substr($query{'enddate'},0,4), substr($query{'enddate'},4,2), substr($query{'enddate'},6,2));
  my @check_dates = ($query{'startdate'});
  foreach (my $i = 1; $i <= $Dd; $i++) {
    my $point = sprintf("%04d%02d%02d", Add_Delta_Days(substr($query{'startdate'},0,4), substr($query{'startdate'},4,2), substr($query{'startdate'},6,2), $i));
    unshift(@check_dates, $point);
  }
  my $supInfo = &getSupplementalInfoDB($merch, \@check_dates);

  #print Dumper $supInfo;
  #print "\n\n";
  my %runningTotal = ();
  my ($runningTotal);
  my %paymentTypes = ();
  my %acctCodes = ();

  foreach my $key (sort keys %result) {

    ##eg
    ## a00000:trans_date=20200918&trans_time=20200919020707&operation=postauth&FinalStatus=success&card-amount=5.18&amountcharged=5.18
    ## &card-name=Ling L Gregory&card-address1=1&card-city=Ogden&card-state=UT&card-zip=84405&card-country=US&card-exp=12/23&cvvresp=M
    ## &result=20200919020702001&MErrMsg=&acct_code=8245&acct_code2=285190&acct_code3=newcard&acct_code4=auth.cgi&accttype=&auth-code=07553C
    ## &avs-code=N&currency=usd&orderID=2020091822210530220&resp-code=&refnumber=W460262805711628N2BVC&batch_time=20200918222252&receiptcc=XXXXXXXX9744
    ## &card-number=426684**9744&adjustment=0.18&baseAmount=5.00

    if ($result{'FinalStatus'} ne 'success') {
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

      if ($amountFlag eq "base") {
        $report{'card-amount'} = $report{'baseAmount'};
      }
      $report{'PaymentType'} = $supInfo->{$report{'orderID'}}{'paymentType'};
      $paymentTypes{$report{'PaymentType'}} = 1;

      $acctCodes{$report{'acct_code'}} = 1;

      $runningTotal{$report{'acct_code'}}+=$report{'card-amount'};
      $runningTotal+=$report{'card-amount'};

      $report{'PaymentID'} = substr(&miscutils::cardtype($report{'card-number'}),0,1) . substr($report{'receiptcc'}, -4);
      #print "RT:ACT:$report{'acct_code'},AMT:$runningTotal{$report{'acct_code'}}\n";


      #if ($report{'trans_time'} < $query{'starttime'}) {
      #  next;
      #}
      $report{'runningTotal'} = $runningTotal{$report{'acct_code'}};
      $report{'username'} = $merch;
      $report{'trans_date'} = substr($report{'trans_date'},4,2) . '/' . substr($report{'trans_date'},6,2) . '/' . substr($report{'trans_date'},0,4);
      if ($report{'orderID'} ne '') {
        print "OID:$report{'orderID'}\n";
        push (@orderIDs,$report{'orderID'});
        #push (@tranRefs, \%report)
        #push (@$report{'acct_code'}, \%report);
        $masterReport{"$report{'acct_code'}$report{'orderID'}"} = \%report;
      }
    }
  }

  foreach my $var (@reportFields) {
    if ($reportLabels{$var} ne '') {
      $reportHeader .= "$reportLabels{$var}$delimeter";
    }
    else {
      $var =~ s/$delimeter//g;
      $reportHeader .= "$var$delimeter";
    }
  }
  chop $reportHeader;
  $reportHeader .= "\n";

  my %reportHash = ();
  #foreach my $acctCode (sort keys %acctCodes) {
  #  foreach my $tranRef (@{$acctCode}) {
  foreach my $key (sort keys %masterReport) {
    my %report = %{$masterReport{$key}};
    my $paymentType = $supInfo->{$report{'orderID'}}{'paymentType'};
    my $amt = $report{'card-amount'};
    $amt =~ s/[^0-9\.]//g;
    $report{'runningTotal'} = $runningTotal{$report{'acct_code'}};
    $report{'fileTotal'} = $runningTotal;
    foreach my $var (@reportFields) {
      $reportHash{$paymentType} .= "$report{$var}$delimeter";
    }
    chop $reportHash{$paymentType};
    $reportHash{$paymentType} .= "\n";
  }
  #print "REPORT:\n$report\n\n";
  my $emailMessage = "Daily Report for $merch: $query{'startdate'} - $query{'enddate'}";

  #$debug = 1;
  if (! $debug) {
    &email_file($merch,$emailMessage,\%reportHash,$reportName);
  }
}

exit;

### Now FTP the File

sub put_file_sftp {
  my ($filename,$report_name) = @_;

  print "RN:$report_name, FULLPATH:$filename\n";

  my $ftphost = '';
  my $ftpusername = '';
  my $ftppassword = '';
  #my $remotedir = '/';
  my $remotedir = '';
  my $sftp = Net::SFTP->new("$ftphost",'user' => $ftpusername, 'password' => $ftppassword, 'Timeout' => 2400, 'Debug' => 1);

  my $remotefilename = $remotedir . $report_name;

  $sftp->put("$filename","$remotefilename");

  my @file_list = $sftp->ls("$remotedir");
  foreach my $entry (sort @file_list) {
    my $filename = $entry->{'filename'};
    print "FILELISTING:$filename\n";
  }
}

sub email_file {
  my ($username,$textMessage,$data,$filename) = @_;

  #sleep(5);
  my ($message_id,$date,$message_time) = &miscutils::genorderid();
  my ($to,$cc,$from,$subject);

  #$to = "lmilne\@symbolarts.com";
  $to = "accounting\@symbolarts.com";
  $cc = "dprice\@plugnpay.com\n";
  $from = "support\@paywithcardx.com";
  $subject = "Pay with CardX Daily Report for $username - $date";
  my $htmlMessage = '';
  
  #print "UN:$username, Mesg:$textMessage, DATA:$data, FN:$filename\n\n";
  #return;

  my $dbh = &miscutils::dbhconnect('emailconf');

  print "Insert into Queue\n";
  print "TO:$to, FROM:$from,  CC:$cc, SUBJECT:$subject, MSGID:$message_id, MESGTIME:$message_time, UN:$username, STATUS:pending,  HTML:$htmlMessage, TXT:$textMessage\n";
  print "DATA:$data\n";

  my $sth_email = $dbh->prepare(q{
    INSERT INTO message_queue
    (to_address,from_address,cc_address,subject,message_id,insert_time,username,status,html_version,text_version)
    VALUES (?,?,?,?,?,?,?,?,?,?)
  }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth_email->execute($to,$from,$cc,$subject,$message_id,$message_time,$username,'pending',$htmlMessage,$textMessage) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
  $sth_email->finish;

  foreach my $report (keys %{$data}) {
    my ($attachment_id,$dummy1,$dummy2) = &miscutils::genorderid();

    print "Insert into Attachment\n";
    print "$message_id,$attachment_id,$message_time,$username,$filename\n";
    print "DATA:$$data{$report}\n";

    $sth_email = $dbh->prepare(q{
      INSERT INTO message_attachment
      (message_id,attachment_id,insert_time,username,filename,data)
      VALUES (?,?,?,?,?,?)
    }) or (__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
    $sth_email->execute($message_id,$attachment_id,$message_time,$username,$filename,$$data{$report}) or (__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
    $sth_email->finish;

  }

  $dbh->disconnect;
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

sub getSupplementalInfoDB {
  my ($merchant, $check_dates) = @_;

  my @supDates;
  foreach my $point (reverse @$check_dates) {
    if ($point !~ /^(\d{4}-\d{2}-\d{2})$/) {
      $point = sprintf("%04d\-%02d\-%02d", substr($point,0,4), substr($point,4,2), substr($point,6,2));
    }
    push(@supDates, $point); # limit to only last 6 newest dates
  }

  my $id = new PlugNPay::GatewayAccount::InternalID()->getIdFromUsername($merchant);
  my @merchantIds = ($id);
  my $supOptions = {
    'merchant_ids' => [@merchantIds],
    'dates'        => [@supDates]
  };

  foreach my $date (@supDates) {
    print "DATE:$date\n";
  }

  my $suppdata = new PlugNPay::Order::SupplementalData();
  my $supResp = $suppdata->getSupplementalData($supOptions);

  my $supInfo;
  for (my $pos = 0; $pos <= $#{$supResp->{'data'}}; $pos++) {
    foreach my $orderid (sort keys %{$supResp->{'data'}->[$pos]->{'orders'}}) {
      my $customData = $supResp->{'data'}->[$pos]->{'orders'}->{$orderid}->{'supplemental_data'}->{'customData'};
      foreach my $key (sort keys %$customData) {
        $supInfo->{$orderid}->{$key} = $customData->{$key};
      }
    }
  }
  return $supInfo;
}

1
