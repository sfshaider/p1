#!/bin/env perl

require 5.001;
local $|=0;

use lib $ENV{'PNP_PERL_LIB'};
use remote_strict;
use Net::SFTP;
use PlugNPay::Transaction::TransactionProcessor;
use strict;

my (%query);

my $lookback = $ARGV[0];

my @now = gmtime(time() - ($lookback+1)*24*3600);
my $reportStartTime = sprintf("%04d%02d%02d050000", $now[5]+1900, $now[4]+1, $now[3]);
my $reportStartDate = substr($reportStartTime,0,8);

@now = gmtime(time() - ($lookback+7)*24*3600);
$query{'startdate'} = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

@now = gmtime(time() - ($lookback)*24*3600);
$query{'enddate'} = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);
my $reportEndTime = $query{'enddate'} . "050000";

my $year = $now[5]+1900;

my $firstflag = "1";

$query{'mode'} = "query_trans";
$query{'operation'} = 'postauth';
$query{'result'} = "success";

my @merchants = ('batevlutil','batevlmuni');

my $reportName = "$reportStartDate\_$query{'enddate'}\.txt";
print "RPRT:$reportName, StartDate:$query{'startdate'}, StartTime:$reportStartTime, EndDate:$query{'enddate'}, ET:$reportEndTime\n";

foreach my $merch (@merchants) {
  my $report = "";
  my $dataFound = 0;

  delete $query{'publisher-name'};
  $query{'publisher-name'} = "$merch";

  my @array = %query;

  my $pnpremote = remote->new(@array);

  my %result = $pnpremote->query_trans();

  foreach my $key (sort keys %result) {
    if ($result{'FinalStatus'} ne "success") {
      $report = $result{'MErrMsg'};
      last;
    }
    my %report = ();

    #print "K:$key:$result{$key}\n";

    if ($key =~ /^a\d+$/) {
      foreach my $pair (split('&',$result{$key})) {
        if ($pair =~ /(.*)=(.*)/) { #found key=value;#
          my ($key,$value) = ($1,$2);  #get key, value
         $value =~ s/%(..)/pack('c',hex($1))/eg;
         $report{$key} = $value;
        }
      }

      if (($report{'orderID'} ne "") && ($report{'trans_time'} >= $reportStartTime) && ($report{'trans_time'} < $reportEndTime)) {
        #print "K:$key:$result{$key}\n";
        print "OID:$report{'orderID'}, TranTime:$report{'trans_time'}. ReportStart:$reportStartTime, EndDate:$query{'enddate'}, EndTime:$reportEndTime\n";
        my $amt = $report{'card-amount'};
        $amt =~ s/[^0-9\.]//g;
        $report .= "$report{'acct_code'},$report{'acct_code2'},$amt\n";
        $dataFound++;
      }
      else {
        next;
      }
    }
    $report .= "\n";
  }
  my $emailMessage = "Daily Report for $merch: $reportStartDate - $query{'enddate'}";

  if ($dataFound) {
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
  #my $remotedir = "/";
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

  my ($message_id,$date,$message_time) = &miscutils::genorderid();
  $message_id = new PlugNPay::Transaction::TransactionProcessor()->generateOrderID();

  my %emailAddresses = ('batevlutil','lisah\@panola.com','batevlmuni','reneh\@panola.com');

  my $to = "lisah\@panola.com";
  my $cc = "dprice\@plugnpay.com\n";

  #my $cc = "";

  my $to = $emailAddresses{$username};

  my $from = "support\@paywithcardx.com";
  my $subject = "Pay with CardX Daily Report - $date";
  my $htmlMessage = "";
  
  print "UN:$username, Mesg:$textMessage, DATA:$data, FN:$filename\n\n";

  #return;

  my $dbh = &miscutils::dbhconnect("emailconf");

  #my $sth_sel = $dbh->prepare(q{
  #    SELECT to_address
  #    FROM message_queue
  #    WHERE message_id=? 
  #    AND username=?
  #  }) or &miscutils::errmail(__LINE__,__FILE__,"\nCan't prepare: $DBI::errstr\n");
  #$sth_sel->execute() or &miscutils::errmail(__LINE__,__FILE__,"\nCan't execute: $DBI::errstr\n");

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

  $dbh->disconnect;

  return;
}

1;
