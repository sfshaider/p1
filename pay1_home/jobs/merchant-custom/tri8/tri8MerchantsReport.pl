#!/usr/local/bin/perl

$| = 1;

use lib '/home/p/pay1/perl_lib';
use miscutils;
use Data::Dumper;
use strict;

my $startdate = $ARGV[0];
my $enddate = $ARGV[1];
my $operation = $ARGV[2];
my $mode = $ARGV[3];

my $reportName = "Tri8_Transaction_Report.txt";

if ($operation eq "") {
  $operation = 'postauth';
}

if ($enddate =~ /summary/i) {
  $mode = "summaryonly";
  $enddate="";
}

my($endTime);
if (($startdate ne "") && ($enddate eq "")) {
  $endTime = &miscutils::timetostr(&miscutils::strtotime("$startdate\000000") + (24*3600));
  $enddate = substr($endTime,0,8);
}



my @now = gmtime(time() - (30*24*3600));
my $startdate = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, '01');

my @now = gmtime(time());
my $enddate = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, '01');

print "StartDate:$startdate, ED:$enddate\n";


my $delim = "\t";
#$delim = '|';

my $queryLimit = 250000;
my $merchCntLimit = 350;

if ($startdate < 202001) {
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
  $startdate = sprintf("%04d%02d01",$year+1900,$mon+1);
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time() + (1*24*3600));
  $enddate = sprintf("%04d%02d%02d",$year+1900,$mon+1,$mday);
}
if (($startdate > 202001) && ($enddate eq "")) {
  my $timeStr = $startdate . "000000";
  my $startTime = &miscutils::strtotime($timeStr);
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($startTime+(35*24*3600));
  $enddate = sprintf("%04d%02d01",$year+1900,$mon+1);
}

my $inclusiveDateFlag = 0;
my ($qmarks1,$qmarks2,$i,$j);
my %cntAuth = ();
my %sumAuth = ();
my %cntReturn=();
my %sumReturn=();
my %sumNotSettledAuth = ();
my %cntNotSettledAuth = ();
my %acctCode4Cnt = ();
my %acctCode4Sum = ();
my %companyName = ();
my %startDate = ();
my %binInfoHash = ();
my %amount = ();


my @resellerList = ();
my @merchantArray = ();

&resellerList(\@resellerList);
&merchantList(\@resellerList,\@merchantArray);

my $resellerCnt = @resellerList;
my $merchantCnt = @merchantArray;

print "SD:$startdate, ED:$enddate, RC:$resellerCnt, MC:$merchantCnt\n";
#exit;

my $loopCnt = 0;

my ($qmarks1,$dateArrayRef) = &miscutils::dateIn($startdate,$enddate,$inclusiveDateFlag);
my $dayCnt = @{$dateArrayRef};
my $totMerchCnt = @merchantArray;


while (1) {
  my $loopCnt++;
  my @tempMerchArray = ();
  for ( my $j = 1; $j <= $merchCntLimit; $j++ ) {
    my $merch = shift @merchantArray;
    if ($merch ne "") {
      push (@tempMerchArray, $merch);
    }
    my $merchantCount = @merchantArray;
    if ($merchantCount == 0) {
      last;
    }
  }
  my $Count = @tempMerchArray;
  if ($Count > 0) {
    &queryTransLog(\@tempMerchArray,$startdate,$enddate,$inclusiveDateFlag,\%cntAuth,\%sumAuth,\%amount,$queryLimit);
  }
  else {
    last;
  }
  if ($loopCnt > 10) {
    print "Emrg Exit, Pulling the rip cord\n";
    last;
  }
}


my $report = "";

print "Mode:$mode\n";

my ($payCnt,$payAmt,$totalCnt,$totalAmt,$corpCnt,$corpAmt);
foreach my $username (sort keys %cntAuth) {
  $payCnt += $cntAuth{$username};
  $payAmt += $sumAuth{$username};
  $sumAuth{$username} = sprintf("%0.2f",$sumAuth{$username});

  if ($mode ne "summaryonly") {
    $report .= "$startdate$delim$operation$delim$startDate{$username}$delim$username$delim$cntAuth{$username}$delim$sumAuth{$username}\n";
  }
}

$report .= "\n\n";

my $merchCnt = keys %cntAuth;

my $totalAmt = sprintf("%0.2f",$payAmt);
my $totalCnt = $payCnt;
my $avgDaily = sprintf("%0.2f",$totalAmt/$dayCnt);
my $thirtyDayProj = sprintf("%0.2f",$avgDaily*30);

$payAmt = sprintf("%0.2f",$payAmt);

$report .= "\n\n";

my ($newMerchCnt);
foreach my $username (sort keys %startDate) {
  my $startYrMo = substr($startdate,0,6);
  if ($startDate{$username} =~ /^$startYrMo/) {
    $newMerchCnt++;
  }
}

$report .= "Totals - $startdate - $enddate\n";
$report .= "Pay CNT:$payCnt\n";
$report .= "Pay Amt:$payAmt\n\n";

my $emailMessage = "Tri8 Monthly Report for: $startdate - $enddate";

print "MSG:$emailMessage\n";
print "REPORT:\n$report\n\n";

&email_file('Tri8',$emailMessage,$report,$reportName);



exit;


sub queryTransLog {
  my ($merchantArray,$startdate,$enddate,$inclusiveDateFlag,$cntAuth,$sumAuth,$amount,$queryLimit) = @_;

  my @executeArray = ();
  my ($qmarks1,$dateArrayRef) = &miscutils::dateIn($startdate,$enddate,$inclusiveDateFlag);
  my @executeArray = @{$dateArrayRef};
  my $dayCnt = @{$dateArrayRef};


  $qmarks2 = '?,' x @$merchantArray;
  chop $qmarks2;

  push (@executeArray, @$merchantArray);


  my $dateCnt = @{$dateArrayRef};
  my $totMerchCnt = @$merchantArray;

  my $i = 0;
  my $lineCnt = 0;

  while (1) {
    $i++;

    if ($i > 10) {
      ## 0Safety Exit
      print "Safety Exit\n";
      last;
    }

    my $qstr = "select username,orderid,trans_date,substr(amount,5) as amountcharged,acct_code,acct_code2,acct_code3,acct_code4
            from trans_log FORCE INDEX(tlog_tdateuname_idx)
            where trans_date IN ($qmarks1) 
            and username in ($qmarks2) 
            and operation in ('$operation') 
            and finalstatus = 'success'
            limit $lineCnt, $queryLimit ";


    #print "WASTR:$qstr\n";
    #foreach my $aa (@executeArray) {
    #  print "$aa\n";
    #}

    my $dbh = &miscutils::dbhconnect("pnpdata");

    my $rowCnt = 0;
    my $sth = $dbh->prepare(qq{$qstr})  or die "Can't prepare: $DBI::errstr";
    $sth->execute(@executeArray) or die "Can't execute: $DBI::errstr";
    while (my $data = $sth->fetchrow_hashref) {
      $rowCnt++;
      $$cntAuth{$data->{'username'}}++;
      $$sumAuth{$data->{'username'}} += $data->{'amountcharged'};
      $$amount{$data->{'orderid'}} = $data->{'amountcharged'};

    }

    if ($rowCnt < $queryLimit) {
      last;
    }

    $lineCnt += $queryLimit;

  }


}

exit;

sub merchantList {
  my ($resellerList,$merchantArray) = @_;

  my $i = "";
  my ($qmarks);
  foreach my $var ( @$resellerList ) {
    $qmarks .= '?,';
  }
  chop $qmarks;

  my $dbh = &miscutils::dbhconnect("pnpmisc");

  my $sth = $dbh->prepare(qq{
      select username
      from customers
      where reseller IN ($qmarks)
      order by reseller
      }) or die "Can't prepare: $DBI::errstr";
  $sth->execute(@resellerList) or die "Can't prepare: $DBI::errstr";
  my $array = $sth->fetchall_arrayref({});
  foreach my $data (@$array) {
    push (@$merchantArray,$$data{'username'});
  }

  return;
}


sub resellerList {
  my ($resellerList) = @_;

  @$resellerList = ('avrub');

  if (0) {
 
  my $dbh = &miscutils::dbhconnect("pnpmisc");

  my $sth = $dbh->prepare(qq{
      select username
      from salesforce
      where salesagent LIKE '%noble%'
      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute() or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  my $array = $sth->fetchall_arrayref({});
  $sth->finish;

  foreach my $data (@$array) {
    push (@$resellerList, $$data{'username'});
  }

  }

}


sub email_file {
  my ($username,$textMessage,$data,$filename) = @_;

  sleep(5);
  my ($message_id,$date,$message_time) = &miscutils::genorderid();
  my ($to,$cc,$from,$subject);

  my $to = "dan\@tri8.com";
  my $cc = "dprice\@plugnpay.com\n";
  #my $cc = "";

  my $from = "support\@plugnpay.com";
  my $subject = "Tri8 Monthyly Report - $date";
  my $htmlMessage = "";

  my $dbh = &miscutils::dbhconnect("emailconf");

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


