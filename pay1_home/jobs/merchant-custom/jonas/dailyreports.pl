#!/bin/env perl

require 5.001;
local $|=0;

use lib $ENV{'PNP_PERL_LIB'};
use remote_strict;
use Net::SFTP;
use PlugNPay::Transaction::TransactionProcessor;
use PlugNPay::Features;
use strict;

my (%query);

my $lookback = $ARGV[0];
my $debugFlg = $ARGV[1];
my $cancelEmailFlg = $ARGV[2];

my @merchList = ();
my %cutOffTime = ();
my %emailAddress = ();

&merchantList(\@merchList,\%cutOffTime,\%emailAddress);

#my @merchants = ('roguevall1','beaverdam1');
#my %cutOffTime = ('roguedemo','8','roguevall1','0','beaverdam1','0');

my @gmtNow = gmtime(time());
my @localNow = localtime(time());

if ($gmtNow[3] != $localNow[3]) {
  $lookback++;
}

my $firstflag = "1";
my $delim = ",";


#Field    Maximum   Data                                   
#Number    Length   Required                               
#     1         6   Date (MMDDYY)                          
#     2        10   Member Number                          
#     3        30   Member Name                            
#     4        10   Check Number                           
#     5        10   Check Amount (no Dollar signs or commas)


$query{'mode'} = "query_trans";
$query{'operation'} = 'postauth';
$query{'result'} = "success";

#my $reportName = "$reportStartDate\_$query{'enddate'}\.txt";
#print "RPRT:$reportName, StartDate:$query{'startdate'}, StartTime:$reportStartTime, EndDate:$query{'enddate'}, ET:$reportEndTime\n";

foreach my $merch (@merchList) {
  my $report = "";
  my $dataFound = 0;

  if ($cutOffTime{$merch} eq "") {
    $cutOffTime{$merch} = '0';
  }
  

  my @now = gmtime(time() - ($lookback)*24*3600 + ($cutOffTime{$merch} * 3600) ) ;
  my $reportStartDate = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);
  my $reportStartTime = sprintf("%04d%02d%02d%02d0000",$now[5]+1900,$now[4]+1,$now[3],$cutOffTime{$merch});


  @now = gmtime(time() - ($lookback+7)*24*3600 + ($cutOffTime{$merch} * 3600));
  $query{'startdate'} = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

  @now = gmtime(time() - ($lookback-1)*24*3600 + ($cutOffTime{$merch} * 3600));
  my $reportEndDate = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);
  my $reportEndTime = sprintf("%04d%02d%02d%02d0000",$now[5]+1900,$now[4]+1,$now[3],$cutOffTime{$merch});

  $query{'enddate'} = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

  my $year = $now[5]+1900;

  my $reportName = "$reportStartDate\_$query{'enddate'}\.txt";

  print  "Merch:$merch, ST:$reportStartTime, ET:$reportEndTime, SD:$query{'startdate'}, ED:$query{'enddate'}, CUTOFF:$cutOffTime{$merch}, EMAILADDY:$emailAddress{$merch}\n";

  #next;
  #exit;

  delete $query{'publisher-name'};
  $query{'publisher-name'} = "$merch";

  my @array = %query;

  my $pnpremote = remote->new(@array);

  my %result = $pnpremote->query_trans();
  my $reportTotal = 0;

  foreach my $key (sort keys %result) {
    print "New Tran New Tran\n";
    if ($result{'FinalStatus'} ne "success") {
      $report = $result{'MErrMsg'};
      last;
    }
    my %report = ();

    print "K:$key:$result{$key}\n\n";

    if ($key =~ /^a\d+$/) {
      foreach my $pair (split('&',$result{$key})) {
        if ($pair =~ /(.*)=(.*)/) { #found key=value;#
          my ($key,$value) = ($1,$2);  #get key, value
         $value =~ s/%(..)/pack('c',hex($1))/eg;
         $report{$key} = $value;
        }
      }

      print "OID:$report{'orderID'}, TT:$report{'trans_time'}, ST:$reportStartTime, ET:$reportEndTime\n\n";

      my $comp1 = substr($report{'trans_time'},0,8);
      my $comp2 = substr($reportStartTime,0,8);

      if (($report{'orderID'} ne "") && (substr($report{'trans_time'},0,8) eq substr($reportStartTime,0,8) ) ) {
        #print "IN REPORT IN REPORT IN REPORT IN REPORT IN REPORT IN REPORT OID:$report{'orderID'}\n";

        $report{'card-amount'} =~ s/[^0-9\.]//g;
  
        my $reportDate = substr($report{'trans_time'},4,2) . substr($report{'trans_time'},6,2) . substr($report{'trans_time'},2,2);

        ## Member Name
        my $memberName = $report{'acct_code'};
        $memberName =~ tr/a-z/A-Z/;
        $memberName =~ s/[^A-Z 0-9]//g;
        $memberName = substr($memberName,0,30);

        ## Member Number
        my $memberNumber = $report{'acct_code2'};
        $memberNumber =~ tr/a-z/A-Z/;
        $memberNumber =~ s/[^A-Z 0-9]//g;
        #$memberNumber = substr($memberNumber . " " x 10,0,10);
        $memberNumber = substr($memberNumber,0,10);

        #my $checkNumber = substr($report{'card-number'} . " " x 10,0,10);
        my $checkNumber = '****-' . substr($report{'card-number'},-4);

        $report{'baseAmount'} =~ s/[^0-9\.]//g;
        my $checkAmount = substr($report{'baseAmount'},0,10);

        $reportTotal += $report{'card-amount'};

        #print "K:$key:$result{$key}\n";
        #print "AAAAAAAAAAAAAAAAA  OID:$report{'orderID'}, TranTime:$report{'trans_time'}, Mbrnum:$memberNumber, Mbrname:$memberName, ReportStart:$reportStartTime, EndDate:$query{'enddate'}, EndTime:$reportEndTime\n";

        $report .= $reportDate . $delim . $memberNumber . $delim . $memberName . $delim . $checkNumber . $delim . $checkAmount;
        $report .= "\n";

        #print "\n\nREPORT:$report\n\n";
        $dataFound++;
      }
      else {
        #print "NO MATCH NO MATCH NO MATCH: OID:$report{'orderID'}\n\n";
        next;
      }
    }
  }
  my $emailMessage = "Daily Report for $merch: $reportStartDate - $query{'enddate'}";

  if ($dataFound) {
    print "Report Total:$reportTotal\n\n";
    print "$report\n\n";
    if (! $cancelEmailFlg) {
      &email_file($merch,$emailMessage,$report,$reportName,$emailAddress{$merch},$debugFlg);
    }
  }
}

exit;

sub email_file {
  my ($username,$textMessage,$data,$filename,$emailAddress,$debugFlg) = @_;

  my ($message_id,$date,$message_time) = &miscutils::genorderid();
  $message_id = new PlugNPay::Transaction::TransactionProcessor()->generateOrderID();

  #my %emailAddresses = ('pnpdemo2','dprice\@plugnpay.com','roguedemoX','dprice\@plugnpay.com','roguedemo','dolson\@rvcc.com','roguevall1','dolson\@rvcc.com','beaverdam1','debbie\@beaverdam.org');

  my $cc = "dprice\@plugnpay.com\n";
  #my $cc = "";
  my $to = $emailAddress;

  #print "TO:$emailAddress\n";

  my $from = "no_reply\@plugnpay.com";
  my $subject = "Plug & Pay Daily Report - $date";
  my $htmlMessage = "";

  if ($to eq "") {
    ## Generate an Error Email
    $to = "david\@plugnpay.com\n";
    $subject = "ERROR - Plug & Pay Jonas Report - $date";
    $textMessage = "Missing TO Address for UN:$username";
  }
  

  if ($debugFlg) {
    $to = "david\@plugnpay.com\n";
    print "UN:$username, Mesg:$textMessage, DATA:\n$data\n, FN:$filename\n\n";
    #return;
  }

  my $dbh = &miscutils::dbhconnect("emailconf");


  print "Insert into Queue\n";
  print "TO:$to, FROM:$from,  CC:$cc, SUBJECT:$subject, MID:$message_id, MESGTIME:$message_time, UN:$username, STATIS:pending,  HTML:$htmlMessage, TXT:$textMessage\n";
  print "DATA:$data\n";

  my $sth_email = $dbh->prepare(q{
      INSERT INTO message_queue
      (to_address,from_address,cc_address,subject,message_id,insert_time,username,status,html_version,text_version)
      VALUES (?,?,?,?,?,?,?,?,?,?)
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",'Username',$username,'MsgID',$message_id);
  $sth_email->execute($to,$from,$cc,$subject,$message_id,$message_time,$username,'pending',$htmlMessage,$textMessage) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
  $sth_email->finish;

  if ($data ne "") {
    print "Insert into Attachment\n";
    print "$message_id,$message_id,$message_time,$username,$filename\n";
    print "DATA:$data\n";

    $sth_email = $dbh->prepare(q{
        INSERT INTO message_attachment
        (message_id,attachment_id,insert_time,username,filename,data)
        VALUES (?,?,?,?,?,?)
      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",'Username',$username,'MsgID',$message_id);
    $sth_email->execute($message_id,$message_id,$message_time,$username,$filename,$data) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
    $sth_email->finish;
  }

  $dbh->disconnect;

  return;
}

sub merchantList {
  my ($merchList,$cutOffTime,$email) = @_;

  my ($username,$features);

  my $dbh = &miscutils::dbhconnect("pnpmisc");

  my $sth = $dbh->prepare(qq{
      select username
      from customers
      where status IN ('live','debug')
      and features LIKE '%jonaslockbox%'
      order BY username
      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute() or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  my $rv1 = $sth->bind_columns(undef,\($username));
  while($sth->fetch) {
    my $accountFeatures = new PlugNPay::Features($username,'general');
    if ($accountFeatures->get('jonaslockbox') ne "") {
      $accountFeatures->get('jonaslockbox') =~ /([0-9]*)\|([0-9a-zA-Z\@\.\-]*)/;
      push (@$merchList, $username);
      $$cutOffTime{$username} = $1;
      $$email{$username} = $2;
    }
  }
  $sth->finish();
  return;
}



1;
