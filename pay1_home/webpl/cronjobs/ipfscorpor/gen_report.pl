#!/bin/env perl

require 5.001;
$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use JSON::XS;
use Time::Local;
use POSIX;
use recutils;
use remote_strict;
use strict;

my $ftpFile = 1;
my $basePath = '/home/pay1/cronjobs/ipfscorpor';

print "Script Started - " . localtime(time) . "\n\n";

my @now = gmtime(time);
my $timestamp = sprintf("%04d%02d%02d%02d%02d%02d",$now[5]+1900,$now[4]+1,$now[3],$now[2],$now[1],$now[0]);

my $merchant = $ARGV[0];  # merchant username [i.e. ipfscorpor]
$merchant =~ s/[^a-zA-Z0-9]//g;
$merchant = lc($merchant);
if ($merchant eq '') {
  $merchant = 'ipfscorpor';
}
print "MERCHANT: $merchant\n";

my $days = $ARGV[1];  # number of days (backwards from today) to generate the report for [default: 0 days]
$days =~ s/[^0-9]//g;
if ($days > 19700101) {
  ## calculate days based upon date given
  my $delta = time() - &cal2sec($days.'000000');
  $days = floor($delta / 86400); # calc days & round down to nearest whole number
}
elsif ($days eq '0') {
  # if value is explicity '0', then force it to use todays date.
  $days = 0;
}
elsif (($days < 1) || ($days > 31)) {
  # if undefined or over 1 month, assume it needs to run for yesterday transactions
  $days = 0;
}
print "DAYS: $days\n";

my @dayNames = ('Sun','Mon','Tue','Wed','Thur','Fri','Sat');
my $base_time = time-($days*86400);
my @past = localtime($base_time);
my $wday = $past[6];


my $year = $past[5]+1900;
my $month = $past[4]+1;
my $day = $past[3];
my $date = sprintf("%04d%02d%02d", $year, $month, $day);

my @earlier = localtime($base_time - 86400); # calculates the day before 'date'
my $prior_date = sprintf("%04d%02d%02d", $earlier[5]+1900, $earlier[4]+1, $earlier[3]);

### send update holiday date list reminder, if overdue
if ($date >= 20221225) {
  &email_notify();
}

my @logfile_dates = ($date); # assume we need to review merchant log file for report date
foreach (my $i = 1; $i <= 6; $i++) {
  # add 6 additional days backwards of merchant log files to check
  my @prev = localtime($base_time - ($i*86400));
  my $point = sprintf("%04d%02d%02d", $prev[5]+1900, $prev[4]+1, $prev[3]);
  unshift(@logfile_dates, $point);
}

my @filedate = localtime($base_time);

my $path_orderids = sprintf("%s\/%s\/%s", "$basePath/reports", $merchant, 'orderIDs.txt');
my $filename = sprintf("%s%02d%02d%02d\.%s", 'WU', $filedate[4]+1, substr($filedate[5]+1900,2,2), $filedate[3], 'pay');
my $path_report = sprintf("%s\/%s\/%s\.%s", "$basePath/reports", $merchant, $filename, $timestamp);

if (0) {
  ## override settings where files are written to
  $path_orderids = "/home/pay1/webtxt/tech_james/download/orderIDs.txt";
  $path_report = sprintf("%s\/%s", '/home/pay1/webtxt/tech_james/download', $filename);
}

print "FILENAME: $filename\n";
print "REPORT: $path_report\n";

## FTP DATA:  ['host',               'FTPun',  'FTPpw',                      'remotedir',     'sourcefile',   'destfile',  'port', 'mode', 'passive', 'chmod']
my @FTPinfo = ('sftp.securenet.com', 'PP0450', "E6\_sd1\,\,\~Dgt\&U\"kVgbw", 'Outgoing/IPFS', "$path_report", "$filename", '228',  'sftp', '',        'yes');

print "WeekDay:$wday, $dayNames[$wday]\n";
print "Date:$date\n";

my ($rg_dates, $dp_dates);

# Reports should be run as such:
#- execute script 7 days a week, very early in the monting (like 4 am local time), after GMT end of previous day
#- assuming merchant is collecting a new report file each day (including on weekends & holidays)

# RG date logic is as follow:
#- start RG date point from current day [e.g. today]
#- proceed forwards, adding one additional day, until the next open date is found
#- include that open date & then stop
#  (this means the first/last dates in the range are open days, if anything is inbetween, it'll be a holiday or days merchant is closed)
#- then generate a report normally containing those transactions with a business date that falls within that date range calculated

## DP logic is as follow:
#- calculate starting DP date from prevous day [e.g. yesterday]
#- proceed backwards, adding each previous day's date, until the next open date is found
#- include that open date & then stop
#- then generate a report normally containing those transactions with a business date that falls within that date range calculated

  print "\nGenerating Report For: $filename\n";

if (1) {
  print "RG DATES:\n";
  ## now go forwards, until we hit another open day
  my $rg_cnt = 0;
  for (my $i = 0; $i <= 7; $i++) {
    my @nxt = localtime($base_time + ($i*86400));
    my $wd = $nxt[6];
    my $point = sprintf("%02d/%02d/%04d", $nxt[4]+1, $nxt[3], $nxt[5]+1900);
    my $test = sprintf("%04d%02d%02d", $nxt[5]+1900, $nxt[4]+1, $nxt[3]);

    # its a open day, add & stop
    $rg_dates .= "\|$point";
    $rg_cnt++; # only incriment on days open
    print "ADDED: $point, $dayNames[$wd]\n";

    if ($rg_cnt == 1) { # was set to '2'
      last;
    }
  }
  substr($rg_dates,0,1) = ''; # removes leading pipe

  print "\nDP DATES:\n";
  ## now go backwards, until we hit another open day
  for (my $i = 1; $i <= 7; $i++) {
    my @nxt = localtime($base_time - ($i*86400));
    my $wd = $nxt[6];
    my $point = sprintf("%02d/%02d/%04d", $nxt[4]+1, $nxt[3], $nxt[5]+1900);
    my $test = sprintf("%04d%02d%02d", $nxt[5]+1900, $nxt[4]+1, $nxt[3]);

    if (1) {
      # its a open day, add & stop
      $dp_dates .= "\|$point";
      print "FINAL: $point, $dayNames[$wd]\n";
      last;
    }
    else {
      print "oh fudge, somethings broken!\n\n";
    }
  }
  substr($dp_dates,0,1) = ''; # removes leading pipe
}

print "\nGenerating Report For Date: $path_report\n";

open(ORDERIDS,'>>',"$path_orderids") or die "Cant open orderids file, $path_orderids, for appending. $!";

print ORDERIDS "\!IN REPORT: $path_report\n";

open(REPORT,'>',"$path_report") or die "Cant open report file for writing. $!";

my $data;
foreach my $point (@logfile_dates) {
  my $letters = substr($merchant,0,2);
  my $path_log = sprintf("%s\/%08d\/%2s\/%s\.%08d\.%2s", '/home/pay1/logs/merchant', $point, $letters, $merchant, $point, 'log');

  if (!-e $path_log) {
    print "=> Log Does Not Exist: $path_log\n";
    next
  }

  my %new_data = &gen_trans_list("$merchant","$path_log","$rg_dates","$dp_dates");

  # merge in hashref
  foreach my $key (keys %new_data) {
    if ($key ne '') {
      $data->{$key} = $new_data{$key};
    }
  }
}

# Line #1: 0004032015
# * Date Stamp
# - 00          1-2     line starts with '00'
# - 04032015    3-10    export date (in 'MMDDYYYY' format)
printf REPORT ("%02d%02d%02d%04d\n", '00', $filedate[4]+1, $filedate[3], $filedate[5]+1900);

my $last_branch = '';
my $branch_cnt = 0;   # total number of transactions listed in current branch office
my $total_amt = 0;    # total dollar amount of all transaction within current branch office
my $branch_grps = 0;  # total number of branch offices in report file

for my $key (sort keys %{ $data }) {
  my ($branch, $id) = split('_', $key, 2);


  if ($last_branch eq '') {
    # Line: 10AZP
    # * Specifies Start Of New Branch Group ID
    # - 10              1-2     line starts with '10'
    # - AZP             3-5     3 letter branch group ID (in uppercase) [BranchOffice]
    printf REPORT ("%02d%3s\n", '10', uc($branch));
  }
  elsif (($last_branch ne '') && ($last_branch ne $branch)) {
    ## close out branch office

    # Line: 9100900003764000009
    # * Specifies End Of The Branch Group
    # - 91                      1-2     line starts with '91'
    # - 009                     3-5     batch count
    # - 0003764000              6-15    total dollar amount (w/o decimal point - e.g.  $37,640.00)
    # - 009                     16-18   batch count
    $total_amt =~ s/[^0-9]//g;
    printf REPORT ("%02d%03d%010d%04d\n", '91', $branch_cnt, $total_amt, $branch_cnt);

    ## reset things for new branch office
    $branch_cnt  = 0;
    $total_amt = 0;

    ## incriment branch group count
    $branch_grps++;

    # Line: 10AZP
    # * Specifies Start Of New Branch Group ID
    # - 10              1-2     line starts with '10'
    # - AZP             3-5     3 letter branch group ID (in uppercase) [BranchOffice]
    printf REPORT ("%02d%3s\n", '10', uc($branch));
  }

  $last_branch = $branch;
  $branch_cnt++;
  my $ca = sprintf("%.2f", $data->{$key}->{'card-amount'});
  $total_amt += $ca;
  $total_amt =  sprintf("%.2f",$total_amt+.00001);

  # Line: 200000035064f9c3bf5CLRG00
  # * Specifies Start Of New Transaction Entry
  # - 20                1-2     line starts with '20'
  # - 0000035064        3-12    payment amount (w/o decimal point - e.g. $350.64)
  # - f9c3bf5           13-19   remitter ID [RemitterId]
  # - CL                20-21   source of payment  (CL = client, PR = producer) [SourceOfPayment]
  # - RG                22-23   type of payment (RG = regular payment, DP = down payment) [TypeOfPayment]
  # - 00                23-24   payment descriptor [PaymentDesc]
  my $payment_amt = sprintf("%.2f",$ca);
  $payment_amt =~ s/[^0-9]//g;
  printf REPORT ("%02d%010d%-7s%-2s%-2s%02d\n", '20', $payment_amt, substr($data->{$key}->{'RemitterId'},0,7), uc($data->{$key}->{'SourceOfPayment'}), uc($data->{$key}->{'TypeofPayment'}), uc($data->{$key}->{'PaymentDesc'}));

  # Line: 21Jacob Snyder                 45301 Industrial Place #4                     Fremont                  CA94538
  # * Specifies Customer's Billing Address [fixed width, space padded, exactly 135 chars long]
  # - 21                                1-2             line starts with '21'
  # - Jacob Snyder                      3-37            card_name
  # - 45301 Industrial Place #4         38-67           card_address_1
  # -                                   68-97           card_address_2
  # - Fremont                           98-122          card_city
  # - CA                                123-124         card_state
  # - 94538                             125-134         card_zip
  printf REPORT ("%02d%-35s%-30s%-30s%-25s%-2s%-10s\n", '21', $data->{$key}->{'card-name'}, $data->{$key}->{'card-address1'}, $data->{$key}->{'card-address2'}, $data->{$key}->{'card-city'}, uc($data->{$key}->{'card-state'}), $data->{$key}->{'card-zip'});

  # Line: 25000000286684
  # * Specifies Customer's Account To Credit
  # - 25                        1-2     line starts with '25'
  # - 000000286684              3-14    credit account [credit_account]  (is stored in 'acct_code')
  printf REPORT ("%02d%012d\n", '25', $data->{$key}->{'acct_code'});

}
# (*** the process loops through each new branch group needed until all are listed, then continues below.)

if (($last_branch ne '') && ($branch_cnt > 0) && ($total_amt > 0)) {
  ## force close out final branch, whenever there is activity (do not include otherwize)
  # Line: 9100900003764000009
  # * Specifies End Of The Branch Group
  # - 91                        1-2     line starts with '91'
  # - 009                       3-5     batch count
  # - 0003764000                6-15    total dollar amount (w/o decimal point - e.g.  $37,640.00)
  # - 009                       16-18   batch count
  $total_amt =~ s/[^0-9]//g;
  printf REPORT ("%02d%03d%010d%04d\n", '91', $branch_cnt, $total_amt, $branch_cnt);
}

## incriment branch group count, since we just closed it out.
$branch_grps++;

# Line: 90023
# * Specifies End Of The File
# - 90  1-2     line starts with '90'
# - 023 3-5     branch group count
printf REPORT ("%2d%03d\n", '90', $branch_grps);

close(REPORT);
#chmod('0666',"$sourcefile");
close(ORDERIDS);

print "\nReport Generation Completed...\n";

if ($ftpFile) {
  print "\nUploading File To Remote Server\n\n";

  my $ftpresult = &recutils::recftp(@FTPinfo);
  if ($ftpresult ne 'failure') {
    print "=> File Upload Successful\n";
  }
  else {
    print "=> File Upload Failed\n";
  }
}

print "\nScript Ended - " . localtime(time) . "\n";
print "-------------------------------------------------------------------------\n\n";

exit;

sub gen_trans_list {
  my ($merchant, $path_log, $rg_dates, $dp_dates) = @_;

  if (!-e "$path_log") {
    return '';
  }

  ## calcualte starting date
  my @start = gmtime(time-604800); # 1 week ago
  my $startdate = sprintf("%04d%02d%02d", $start[5]+1900, $start[4]+1, $start[3]);

  ## calculare ending date
  my @end = gmtime(time+86400); # tomorrow
  my $enddate = sprintf("%04d%02d%02d", $end[5]+1900, $end[4]+1, $end[3]);

  my %voided = &isVoided($merchant,$startdate,$enddate);

  print "CHECKING LOG:$path_log, RG:$rg_dates, DP:$dp_dates\n";

  my %trans_data = ();

  open(LOG,'<',"$path_log") or die "Cant open log file [$path_log] for reading. $!";
  while (<LOG>) {
    my $line = $_;
    chop $line;

    my $hashref = JSON::XS->new->utf8->decode($line);

    ## merge in custom name/value pairs
    for (my $i = 1; $i <= 10; $i++) {
      # "customname1":"SourceOfPayment"
      # "customname2":"BranchOffice"
      # "customname3":"TypeofPayment"
      # "customname4":"PaymentDesc"
      # "customname5":"BusinessDate"
      # "customname6":"MinAmt"
      # "customname7":"MaxAmt"
      # "customname8":"RemitterId"

      my $key = $hashref->{'transactionData'}->{"customname$i"};
      my $val = $hashref->{'transactionData'}->{"customvalue$i"};

      if (($key ne '') && ($val ne '')) {
        $hashref->{'transactionData'}->{$key} = $val;
      }
    }

    my $entry = $hashref->{'transactionData'};

    if ($entry->{'Duplicate'} eq 'yes') {
      print "DUPLICATE: $entry->{'orderID'}\n";
    }
    elsif (($entry->{'FinalStatus'} eq 'success') && ($voided{$entry->{'orderID'}} != 1) && (
         (($entry->{'TypeofPayment'} eq 'RG') && ($entry->{'BusinessDate'} =~ /($rg_dates)/)) ||
         (($entry->{'TypeofPayment'} eq 'DP') && ($entry->{'BusinessDate'} =~ /($dp_dates)/))
       )) {

      print "WAS FOUND: $entry->{'orderID'}\n";

      my $id = sprintf("%s\_%d", $entry->{'BranchOffice'}, $entry->{'orderID'});
      $trans_data{$id} = $entry;

      print ORDERIDS "$entry->{'orderID'}\t$entry->{'TypeofPayment'}\t$entry->{'BusinessDate'}\n";
    }

    if ($voided{$entry->{'orderID'}} == 1) {
      print "WAS VOIDED: $entry->{'orderID'}\n";
    }
  }
  close(LOG);

  return %trans_data;
}

sub cal2sec {
  # converts YYYYMMDDhhmmss date to seconds (in LocalTime Epoch Seconds)
  my ($date) = @_;

  my $year    = substr($date, 0, 4);
  my $month   = substr($date, 4, 2);
  my $day     = substr($date, 6, 2);
  my $hours   = substr($date, 8, 2);
  my $minutes = substr($date, 10, 2);
  my $seconds = substr($date, 12, 2);

  # $day is day in month (1-31)
  # $month is month in year (1-12)
  # $year is four-digit year e.g., 1967
  # $hours, $minutes and $seconds represent UTC time

  #use Time::Local;
  my $time = timelocal($seconds, $minutes, $hours, $day, $month-1, $year-1900);

  return($time);
}

sub email_notify {
  # send email to David & James, reminding them the holiday date list needs to be updated

  my $emailmessage = "Script cronned for merchant 'ipfscorpor' requires your attention.\n";
  $emailmessage .= "\nPlease extend the holiday dates list in the 'gen_report.pl' script for this merchant.\n";
  $emailmessage .= "Failure to address this matter expediently will result in new reports being generated improperly.\n";

  my $emailer = new PlugNPay::Email;
  $emailer->setVersion('legacy');
  $emailer->setGatewayAccount('ipfscorpor');
  $emailer->setFormat('text');
  $emailer->setTo("turajb\@plugnpay.com");
  $emailer->setCC("dprice\@plugnpay.com");
  $emailer->setFrom("noc\@plugnpay.com");
  $emailer->setSubject("Update Script Reminder - ipfscorpor");
  $emailer->setContent($emailmessage);
  $emailer->send();

  return;
}


sub isVoided {
  my ($username,$startdate,$enddate) = @_;
  my %query = ();

  $query{'publisher-name'} = $username;
  $query{'startdate'} = $startdate;
  $query{'enddate'} = $enddate;
  my @array = %query;
  my $pnpremote = remote->new(@array);
  my %result = $pnpremote->query_trans();

  #my %voided = isVoided(\%result);

  my %voided = ();
  foreach my $key (sort keys %result) {
    if ($key =~ /^a\d{5}/) {
      my %res2 = ();
      my @nameval = split(/&/,$result{$key});
      foreach my $temp (@nameval) {
        my ($name,$value) = split(/=/,$temp);
        $res2{$name} = $value;
      }
      if ($res2{'operation'} eq 'void') {
        $voided{$res2{'orderID'}} = 1;
      }
    }
  }
  return %voided;
}

1;

