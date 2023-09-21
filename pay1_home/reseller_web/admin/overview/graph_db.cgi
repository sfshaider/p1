#!/bin/env perl

require 5.001;
$| = 1;

use lib '/home/p/pay1/perl_lib';
use CGI;
use DBI;
use Time::Local qw(timegm);
use miscutils;
use PlugNPay::GatewayAccount;
use PlugNPay::GatewayAccount::Private;

print "Content-Type: text/html\n\n";

#if (($ENV{'REMOTE_USER'} eq "videosecret") && ($ENV{'SERVER_PORT'} ne "455")) {
#  $ENV{'REMOTE_USER'} = "icommerceg";
#  $ENV{'SUBACCT'} = "videosec";
#}
#elsif(($ENV{'REMOTE_USER'} eq "vmicardservice") && ($ENV{'SERVER_PORT'} ne "455")) {
#  $ENV{'REMOTE_USER'} = "icommerceg";
#  $ENV{'SUBACCT'} = "vmicard";
#}

if (-e "/home/p/pay1/outagefiles/highvolume.txt") {
  print "Sorry this program is not available right now.<p>\n";
  print "Please try back later.<p>\n";
  exit;
}

%altaccts = ('icommerceg',["icommerceg","icgoceanba","icgcrossco"]);

%month_array2 = ("Jan","01","Feb","02","Mar","03","Apr","04","May","05","Jun","06","Jul","07","Aug","08","Sep","09","Oct","10","Nov","11","Dec","12");

$username = $ENV{"REMOTE_USER"};
 
$query = new CGI;
$startmonth = &CGI::escapeHTML($query->param('startmonth'));
if ($startmonth =~ /[a-zA-Z]/) {
  $startmonth = $month_array2{$startmonth};
}
$startmonth = sprintf("%02d",$startmonth);
$startyear = &CGI::escapeHTML($query->param('startyear'));
$startyear = sprintf("%04d",$startyear);
if ($startyear < 2000) {
  $startyear = "2000";
}
$startday = &CGI::escapeHTML($query->param('startday'));
$startday = sprintf("%02d",$startday);
$endmonth = &CGI::escapeHTML($query->param('endmonth'));
if ($endmonth =~ /[a-zA-Z]/) {
  $endmonth = $month_array2{$endmonth};
}
$endyear = &CGI::escapeHTML($query->param('endyear'));
if ($endyear < $startyear) {
  $endyear = $startyear;
}
$endday = &CGI::escapeHTML($query->param('endday'));
$endday = sprintf("%02d",$endday);

$function = &CGI::escapeHTML($query->param('function'));
$mode = &CGI::escapeHTML($query->param('mode'));


if ($ENV{'SUBACCT'} eq "") {
  $subacct = &CGI::escapeHTML($query->param('subacct'));
}
else {
  $subacct = $ENV{'SUBACCT'}; 
}

$acct_code = &CGI::escapeHTML($query->param('acct_code'));
$acct_code2 = &CGI::escapeHTML($query->param('acct_code2'));
$acct_code3 = &CGI::escapeHTML($query->param('acct_code3'));

$goodcolor = "#000000";
$badcolor = "#ff0000";
$backcolor = "#ffffff";
$fontface = "Arial,Helvetica,Univers,Zurich BT";

$sortorder = &CGI::escapeHTML($query->param('sortorder'));  ###  Used to Sort and/or Group Results

$start = $startyear . $startmonth . $startday;
$end = $endyear . $endmonth . $endday;

$merchant = &CGI::escapeHTML($query->param('merchant'));
print "<$ENV{'REMOTE_USER'}>\n";
if ($ENV{'REMOTE_USER'} =~ /^(northame|stkittsn|cynergy)$/) {
  print "MER:$merchant, UN:$username, ENV:$ENV{'REMOTE_USER'}<br>\n";
  $dbh = &miscutils::dbhconnect("pnpmisc");

  $sth = $dbh->prepare(qq{
      select username
      from customers
      where reseller='$ENV{'REMOTE_USER'}' and username='$merchant'
      }) or die "Can't do: $DBI::errstr";
  $sth->execute or die "Can't execute: $DBI::errstr";
  ($db_merchant) = $sth->fetchrow;
  $sth->finish;
  $dbh->disconnect;

  if ($merchant =~ /icommerceg/) {
    $subacct = &CGI::escapeHTML($query->param('subacct'));
    if (($ENV{'SUBACCT'} eq "") && ($subacct ne "")) {
      $ENV{'SUBACCT'} = $subacct;
    }
  }

  $username = $db_merchant;
  $ENV{'REMOTE_USER'} = $db_merchant;
  $detailflag = 1;
  print "MER:$merchant, UN:$username, ENV:$ENV{'REMOTE_USER'}<br>\n";

}

if ($start eq "") {
  my ($trans_date,$trans_time) = &miscutils::gendatetime_only();
  $start = substr($trans_date,0,6);
}
if ($end eq "") {
  $end = $start;
}

$dbh = &miscutils::dbhconnect("pnpmisc");

if ($subacct ne "") {
  $qstr = "select name,company,addr1,addr2,city,state,zip,country,fraud_config,reseller,processor from customers where subacct='$subacct'";
  #print "QSTR:$qstr<p>\n";
}
else {
  $qstr = "select name,company,addr1,addr2,city,state,zip,country,fraud_config,reseller,processor from customers where username='$username'";
}

$sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
$sth->execute() or die "Can't execute: $DBI::errstr";
($name,$company,$addr1,$addr2,$city,$state,$zip,$country,$fraud_config,$dbreseller,$processor) = $sth->fetchrow;
$sth->finish;

$dbh->disconnect;

$total = 0;

$start1 = $start;
$end1 = $end;

$max = 200;
$maxmonth = 200;
$trans_max = 200;
$trans_maxmonth = 200;

$tt = time();
#print "Start:$tt:$start<br>Please be patient, creating the graph may take several minutes.<br>\n";


if (($username =~ /barbara|dcprice|cprice/) && ($merchant eq "ALL")) {

  $qstr = "select trans_date, operation, finalstatus, acct_code, acct_code2, acct_code3, acct_code4, count(username), sum(substr(amount,4)) 
       from trans_log where trans_date>='$start' and trans_date<'$end' 
       and operation IN ('auth','postauth','forceauth','void','return') and duplicate IS NULL 
       group by trans_date, operation, finalstatus, acct_code, acct_code2, acct_code3";
}
elsif ($subacct ne "") {
  #$username = "icgoceanba";
  $qstr = "select trans_date, operation, finalstatus, acct_code, acct_code2, acct_code3, acct_code4, count(username), sum(substr(amount,4)) 
       from trans_log where trans_date>='$start' and trans_date<'$end' ";

  if (exists $altaccts{$username}) {
    my ($temp);
    foreach my $var ( @{ $altaccts{$username} } ) {
      $temp .= "'$var',";
    }
    chop $temp;
    $qstr .= "and username IN ($temp) ";
  }
  else {
    $qstr .= "and username='$username' ";
  }
  
  $qstr .= "and subacct='$subacct' and operation<>'query' and duplicate IS NULL ";
  $qstr .= "group by trans_date, operation, finalstatus, acct_code, acct_code2, acct_code3, acct_code4";

#print "SUBACCT:$subacct, $qstr<br>\n";
#exit;
}
elsif ($subacct eq "ALL") {
  $qstr = "select trans_date, operation, finalstatus, subacct, username, count(username), sum(substr(amount,4)) 
       from trans_log where trans_date>='$start' and trans_date<'$end' ";

  if (exists $altaccts{$username}) {
    my ($temp);
    foreach my $var ( @{ $altaccts{$username} } ) {
      $temp .= "'$var',";
    }
    chop $temp;
    $qstr .= "and username IN ($temp) ";
  }
  else {
    $qstr .= "and username='$username' ";
  }

  $qstr .= "and operation<>'query' and duplicate IS NULL ";
  $qstr .= "group by trans_date, operation, finalstatus, subacct";

}
else {
  $qstr = "select trans_date, operation, finalstatus, acct_code, acct_code2, acct_code3, acct_code4, count(username), sum(substr(amount,4)) 
       from trans_log where trans_date>='$start' and trans_date<'$end' ";

  #if (exists $altaccts{$username}) {
  #  my ($temp);
  #  foreach my $var ( @{ $altaccts{$username} } ) {
  #    $temp .= "'$var',";
  #  }
  #  chop $temp;
  #  $qstr .= "and username IN ($temp) ";
  #}
  #else {
    $qstr .= "and username='$username' ";
  #}
 
  $qstr .= "and operation<>'query' and duplicate IS NULL ";
  $qstr .= "group by trans_date, operation, finalstatus, acct_code, acct_code2, acct_code3, acct_code4";

#  $qstr = "select trans_date, operation, finalstatus, acct_code, acct_code2, acct_code3, count(username), sum(substr(amount,4)) 
#       from trans_log where trans_date>='$start' and trans_date<'$end' 
#       and username='$username' and operation<>'query' and duplicate IS NULL 
#       group by trans_date, operation, finalstatus, acct_code, acct_code2, acct_code3";
}

#print "SUBACCT:$subacct, $qstr<br>\n";
#exit;

$dbh = &miscutils::dbhconnect("pnpdata"); ## Trans_Log
$sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
$sth->execute or die "Can't execute: $DBI::errstr";
if ($subacct eq "ALL") {
  $sth->bind_columns(undef,\($trans_date, $operation, $finalstatus, $acct_code, $username, $count, $sum));
}
else {
  $sth->bind_columns(undef,\($trans_date, $operation, $finalstatus, $acct_code, $acct_code2, $acct_code3, $acct_code4, $count, $sum));
}

while ($sth->fetch) {
  if ($username =~ /icommerceg|icgoceanba|icgcrossco/) {
   # print "PP:$trans_date, $operation, $finalstatus, $acct_code, $acct_code2, $acct_code3, $acct_code4, $count, $sum<br>\n";
   #($acct_code4,$scriptname,$ipaddress) = split (':',$acct_code4);
   # print "ACCT:$acct_code4<br>\n";
  }
  
  ($acct_code4,$scriptname,$ipaddress) = split (':',$acct_code4);

  if($acct_code eq "") {
    $acct_code = "none";
  }
  if($acct_code2 eq "") {
    $acct_code2 = "none2";
  }
  if($acct_code3 eq "") {
    $acct_code3 = "none3";
  }

  if($acct_code4 eq "") {
    $acct_code4 = "No Reason on Record.";
  }

  if($acct_code4 =~ /chargeback/) {
    $acct_code4 = "Chargeback";
  }

  $dates{$trans_date} = 1;
  $operations{$operation} = 1;
  $finalstatus{$finalstatus} = 1;
  $acct_code{$acct_code} = $acct_code;
  $acct_code2{$acct_code2} = $acct_code2;
  $acct_code3{$acct_code3} = $acct_code3;
  $acct_code4{$acct_code4} = $acct_code4;

  $ac_count{"$trans_date$operation$finalstatus$acct_code"} += $count;
  $ac2_count{"$trans_date$operation$finalstatus$acct_code2"} += $count;
  $ac3_count{"$trans_date$operation$finalstatus$acct_code3"} += $count;
  $ac4_count{"$trans_date$operation$finalstatus$acct_code4"} += $count;

  $count{"$trans_date$operation$finalstatus"} += $count;
  $ac_sum{"$trans_date$operation$finalstatus$acct_code"} += $sum;
  $ac2_sum{"$trans_date$operation$finalstatus$acct_code2"} += $sum;
  $ac3_sum{"$trans_date$operation$finalstatus$acct_code3"} += $sum;
  $ac4_sum{"$trans_date$operation$finalstatus$acct_code4"} += $sum;

  $sum{"$trans_date$operation$finalstatus"} += $sum;

  $ac_totalcnt{"TOTAL$operation$finalstatus$acct_code"} += $count;
  $ac_totalsum{"TOTAL$operation$finalstatus$acct_code"} += $sum;
  $ac2_totalcnt{"TOTAL$operation$finalstatus$acct_code2"} += $count;
  $ac2_totalsum{"TOTAL$operation$finalstatus$acct_code2"} += $sum;
  $ac3_totalcnt{"TOTAL$operation$finalstatus$acct_code3"} += $count;
  $ac3_totalsum{"TOTAL$operation$finalstatus$acct_code3"} += $sum;

  $ac4_totalcnt{"TOTAL$operation$finalstatus$acct_code4"} += $count;
  $ac4_totalsum{"TOTAL$operation$finalstatus$acct_code4"} += $sum;

  $totalcnt{"TOTAL$operation$finalstatus"} += $count;
  $totalsum{"TOTAL$operation$finalstatus"} += $sum;

  $maxsum1 = $sum{"$trans_date$operation$finalstatus"};
  if ($maxsum1 > $maxsum) {
    $maxsum = $maxsum1;
  }
  $maxcnt1 = $count{"$trans_date$operation$finalstatus"};
  if ($maxcnt1 > $maxcnt) {
    $maxcnt = $maxcnt1;
  }
  $month = substr($trans_date,0,6);
  $months{$month} = $month;
  $ac_count{"$month$operation$finalstatus$acct_code"} += $count;
  $ac2_count{"$month$operation$finalstatus$acct_code2"} += $count;
  $ac3_count{"$month$operation$finalstatus$acct_code3"} += $count;
  $ac4_count{"$month$operation$finalstatus$acct_code4"} += $count;
  $count{"$month$operation$finalstatus"} += $count;
  $ac_sum{"$month$operation$finalstatus$acct_code"} += $sum;
  $ac2_sum{"$month$operation$finalstatus$acct_code2"} += $sum;
  $ac3_sum{"$month$operation$finalstatus$acct_code3"} += $sum;
  $ac4_sum{"$month$operation$finalstatus$acct_code4"} += $sum;
  $sum{"$month$operation$finalstatus"} += $sum;
  $maxmosum1 = $sum{"$month$operation$finalstatus"};
  if ($maxmosum1 > $maxmosum) {
    $maxmosum = $maxmosum1;
  }
  $maxmocnt1 = $count{"$month$operation$finalstatus"};
  if ($maxmocnt1 > $maxmocnt) {
    $maxmocnt = $maxmocnt1;
  }
}
$sth->finish;
$dbh->disconnect;

if ($fraud_config ne "") {
  $operation = "auth";
  $finalstatus = "fraud";
  my $start1 = $start . "000000";
  my $end1 = $end . "000000";
  my $dbh = &miscutils::dbhconnect("fraudtrack");
  my $sth = $dbh->prepare(qq{
  select trans_time, acct_code, acct_code2, acct_code3
       from fraud_log 
       where trans_time>='$start1' and trans_time<'$end1'
       and username='$username' 
  }) or die "Can't do: $DBI::errstr";
  $sth->execute or die "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($trans_time, $acct_code, $acct_code2, $acct_code3));
  while ($sth->fetch) {
    $trans_date = substr($trans_time,0,8);
    if($acct_code eq "") {
      $acct_code = "none";
    }
    if($acct_code2 eq "") {
      $acct_code2 = "none2";
    }
    if($acct_code3 eq "") {
      $acct_code3 = "none3";
    }
    $dates{$trans_date} = 1;
    $acct_code{$acct_code} = $acct_code;
    $acct_code2{$acct_code2} = $acct_code2;
    $acct_code2{$acct_code3} = $acct_code3;
    $ac_count{"$trans_date$operation$finalstatus$acct_code"}++;
    $ac2_count{"$trans_date$operation$finalstatus$acct_code2"}++;
    $ac3_count{"$trans_date$operation$finalstatus$acct_code3"}++;
    $count{"$trans_date$operation$finalstatus"}++;
    $month = substr($trans_date,0,6);
    $months{$month} = $month;
    $ac_count{"$month$operation$finalstatus$acct_code"}++;
    $ac2_count{"$month$operation$finalstatus$acct_code2"}++;
    $ac3_count{"$month$operation$finalstatus$acct_code3"}++;
    $count{"$month$operation$finalstatus"}++;

    $ac_totalcnt{"TOTAL$operation$finalstatus$acct_code"}++;
#    $ac_totalsum{"TOTAL$operation$finalstatus$acct_code"}++;
    $ac2_totalcnt{"TOTAL$operation$finalstatus$acct_code2"}++;
#    $ac2_totalsum{"TOTAL$operation$finalstatus$acct_code2"}++;
    $ac3_totalcnt{"TOTAL$operation$finalstatus$acct_code3"}++;
#    $ac3_totalsum{"TOTAL$operation$finalstatus$acct_code3"}++;
    $totalcnt{"TOTAL$operation$finalstatus"}++;
#    $totalsum{"TOTAL$operation$finalstatus"}++;
  }
  $sth->finish;
  $dbh->disconnect;
}

$noacct_code{'1'} = "";

#$tt = time();
#print "End Calc Time:$tt:<br>\n";

if ($mode eq "billing") {
  &billing_head();
  &billing();
  &billing_tail();
}
else {
  &report_head();
  &sales();
  &trans();
  &tail();
}

$et = time();
$delta = $et-$tt;
open(tmpfile,">>/home/p/pay1/webtxt/admin/graph_log.txt");
print tmpfile "$username\t$start\t$end\t$ENV{'REMOTE_USER'}\t$ENV{'REMOTE_ADDR'}\t$ENV{'HTTP_USER_AGENT'}\t$delta\n";
close(tmpfile);

exit;


sub sales {
  if ($processor eq "cybercash") {
    $rowspan = 1;
  }
  else {
    $rowspan = 4;
  }
  print "<div align=\"center\"><table border=1 cellspacing=1 width=\"550\">\n";
  print "<tr><th colspan=\"4\">Sales Volume (\$)</th></tr>\n";
  if ($sortorder eq "acctcode") {
    %display = %acct_code;
    %values = %ac_sum;
  }
  elsif ($sortorder eq "acctcode2") {
    %display = %acct_code2;
    %values = %ac2_sum;
  }
  elsif ($sortorder eq "acctcode3") {
    %display = %acct_code3;
    %values = %ac3_sum;
  }
  else {
    %display = %noacct_code;
    %values = %sum;
  }

  my $max = $maxsum;
  my $maxmonth = $maxmosum;

  foreach $key (sort keys %display) {
    $acct_code = $display{$key};
    $label = $acct_code;
    if ($label =~ /^(none|none2|none3)$/) {
      $label = "None";
    }
    if ($sortorder ne "") {
      print "<tr><th>Acct Code:</th><th>$label</th></tr>\n";
    }

    print "<tr>";
    print "<th align=left><font size=-1>Date</font></th>";
    print "<th align=left><font size=-1>&nbsp;</font></th>";
    print "<th align=left><font size=-1>Amount</font></th>";
    print "<th align=left><font size=-1>Graph</font></th>";
    print "</tr>\n";
    if ($function eq "daily") {
      foreach my $date (sort keys %dates) {
#        print "DATE:$date<br>\n";
        $datestr = sprintf("%02d/%02d/%04d", substr($date,4,2), substr($date,6,2), substr($date,0,4));
        if ($max == 0) {
          $max = 1;
        }
        $width = sprintf("%d",$values{$date . "authsuccess" . $acct_code} * 300 / $max);
        $width2 = sprintf("%d",$values{$date . "voidsuccess" . $acct_code} * 300 / $max);
        $width3 = sprintf("%d",$values{$date . "returnsuccess" . $acct_code} * 300 / $max);
        $width4 = sprintf("%d",$values{$date . "postauthsuccess" . $acct_code} * 300 / $max);

        if ($width <= 0) {
          $width = 1;
        }
        if ($width1 <= 0) {
          $width1 = 1;
        }
    
        $values{$date . "authsuccess" . $acct_code} = sprintf("%.2f",$values{$date . "authsuccess" . $acct_code});
        $values{$date . "authsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$date . "postauthsuccess" . $acct_code} = sprintf("%.2f",$values{$date . "postauthsuccess" . $acct_code});
        if ($ENV{"REMOTE_USER"} eq "northame") {
        #  $values{$date . "postauthsuccess" . $acct_code} = sprintf("%.2f",$values{$date . "postauthsuccess" . $acct_code}+ $values{$date . "postauthpending" . $acct_code});
        }
        $values{$date . "postauthsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$date . "returnsuccess" . $acct_code} = sprintf("%.2f",$values{$date . "returnsuccess" . $acct_code});
        $values{$date . "returnsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$date . "voidsuccess" . $acct_code} = sprintf("%.2f",$values{$date . "voidsuccess" . $acct_code});
        $values{$date . "voidsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;

        print "<tr>\n";
        print "<th align=left rowspan=$rowspan><font size=-1>$datestr</font></th><th><font size=-1>Authorizations</font></th>\n";
        print "<td align=right><font size=-1>\$$values{$date . \"authsuccess\" . $acct_code}</font></td>\n";
        print "<td align=left><img src=\"/images/blue.gif\" height=8 width=$width></td>";
        print "</tr>\n";
        if ($processor ne "cybercash") {
          print "<tr><th><font size=-1>Voids</font></th>";
          print "<td align=right><font size=-1>\$$values{$date . \"voidsuccess\" . $acct_code}</font></td>\n";
          print "<td align=left><img src=\"/images/red.gif\" height=8 width=$width2></td>";
          print "</tr>\n";
          print "<tr><th><font size=-1>Returns</font></th>";
          print "<td align=right><font size=-1>\$$values{$date . \"returnsuccess\" . $acct_code}</font></td>\n";
          print "<td align=left><img src=\"/images/red.gif\" height=8 width=$width3></td>";
          print "</tr>\n";
          print "<tr><th><font size=-1>Post Auths</font></th>";
          print "<td align=right><font size=-1>\$$values{$date . \"postauthsuccess\" . $acct_code}</font></td>\n";
          print "<td align=left><img src=\"/images/green.gif\" height=8 width=$width4></td>";
          print "</tr>\n";
        }
      }
    }
    else {
      foreach my $date (sort keys %months) {
        #print "DATE:$date<br>\n";
        $datestr = sprintf("%02d/%04d", substr($date,4,2), substr($date,0,4));
        if ($maxmonth == 0) {
          $maxmonth = 1;
        }

        $width = sprintf("%d",$values{$date . "authsuccess" . $acct_code} * 300 / $maxmonth);
        $width2 = sprintf("%d",$values{$date . "voidsuccess" . $acct_code} * 300 / $maxmonth);
        $width3 = sprintf("%d",$values{$date . "returnsuccess" . $acct_code} * 300 / $maxmonth);
        $width4 = sprintf("%d",$values{$date . "postauthsuccess" . $acct_code} * 300 / $maxmonth);

        if ($width <= 0) {
          $width = 1;
        }
        if ($width1 <= 0) {
          $width1 = 1;
        }

        $values{$date . "authsuccess" . $acct_code} = sprintf("%.2f",$values{$date . "authsuccess" . $acct_code});
        $values{$date . "authsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$date . "authsuccess" . $acct_code} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;
        $values{$date . "postauthsuccess" . $acct_code} = sprintf("%.2f",$values{$date . "postauthsuccess" . $acct_code});
        $values{$date . "postauthsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$date . "postauthsuccess" . $acct_code} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;
        $values{$date . "returnsuccess" . $acct_code} = sprintf("%.2f",$values{$date . "returnsuccess" . $acct_code});
        $values{$date . "returnsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$date . "returnsuccess" . $acct_code} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;
        $values{$date . "voidsuccess" . $acct_code} = sprintf("%.2f",$values{$date . "voidsuccess" . $acct_code});
        $values{$date . "voidsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$date . "voidsuccess" . $acct_code} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;



        $record = "<tr>";
        $record .= "<th align=left rowspan=$rowspan><font size=-1>$datestr</font></th><th><font size=-1>Net Sales</font></th>";
        $record .= "<td align=right><font size=-1>\$$values{$date . \"authsuccess\" . $acct_code}</font></td>\n";
        $record .= "<td align=left><img src=\"/images/blue.gif\" height=5 width=$width></td></tr>";
        if ($processor ne "cybercash") {
          $record .= "<tr><th><font size=-1>Voids</font></th>";
          $record .= "<td align=right><font size=-1>\$$values{$date . \"voidsuccess\" . $acct_code}</font></td>\n";
          $record .= "<td align=left><img src=\"/images/red.gif\" height=8 width=$width2></td>";
          $record .= "</tr>\n";
          $record .= "<tr><th><font size=-1>Returns</font></th>";
          $record .= "<td align=right><font size=-1>\$$values{$date . \"returnsuccess\" . $acct_code}</font></td>\n";
          $record .= "<td align=left><img src=\"/images/red.gif\" height=8 width=$width3></td>";
          $record .= "</tr>\n";
          $record .= "<tr><th><font size=-1>Post Auths</font></th>";
          $record .= "<td align=right><font size=-1>\$$values{$date . \"postauthsuccess\" . $acct_code}</font></td>\n";
          $record .= "<td align=left><img src=\"/images/green.gif\" height=8 width=$width4></td>";
          $record .= "</tr>\n";
        }
        $record .= "\n";
        print $record;
      }
    }
  }
  $totalsum{'TOTALauthsuccess'} = sprintf("%.2f",$totalsum{'TOTALauthsuccess'});
  $totalsum{'TOTALauthsuccess'} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{'TOTALauthsuccess'} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;
  $totalsum{'TOTALpostauthsuccess'} = sprintf("%.2f",$totalsum{'TOTALpostauthsuccess'});
  $totalsum{'TOTALpostauthsuccess'} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{'TOTALpostauthsuccess'} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;
  $totalsum{'TOTALreturnsuccess'} = sprintf("%.2f",$totalsum{'TOTALreturnsuccess'});
  $totalsum{'TOTALreturnsuccess'} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{'TOTALreturnsuccess'} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;
  $totalsum{'TOTALvoidsuccess'} = sprintf("%.2f",$totalsum{'TOTALvoidsuccess'});
  $totalsum{'TOTALvoidsuccess'} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{'TOTALvoidsuccess'} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;


  print "<tr><th align=left rowspan=4><font size=-1>TOTALS:</font></th>\n";
  print "<th><font size=-1>Net Sales</font></th><td align=right><font size=-1>\$$totalsum{'TOTALauthsuccess'}</font></td><td></td>";
  if ($processor ne "cybercash") {
    print "<tr><th><font size=-1>Voids</font></th><td align=right><font size=-1>\$$totalsum{'TOTALvoidsuccess'}</font> </td><td></td>";
    print "<tr><th><font size=-1>Returns</font></th><td align=right><font size=-1>\$$totalsum{'TOTALreturnsuccess'}</font> </td><td></td>";
    print "<tr><th><font size=-1>Post Auths</font></th><td align=right><font size=-1>\$$totalsum{'TOTALpostauthsuccess'}</font></td><td></td>";
  }
  print "</table></div>\n";
}


sub trans {
  my $max = $maxcnt;

  print "<p><div align=\"center\"><p><table border=1 cellspacing=1 width=\"650\">\n";
  print "<tr><th colspan=\"5\">Transaction Volume</th></tr>\n";
  if ($sortorder eq "acctcode") {
    %display = %acct_code;
    %values = %ac_count;
    %sums = %ac_sum;
  }
  elsif ($sortorder eq "acctcode2") {
    %display = %acct_code2;
    %values = %ac2_count;
    %sums = %ac2_sum;
  }
  elsif ($sortorder eq "acctcode3") {
    %display = %acct_code3;
    %values = %ac3_count;
    %sums = %ac3_sum;
  }
  else {
    %display = %noacct_code;
    %values = %count;
    %sums = %sum;
  }

  $total_auths_summ = 0.0000001;
 
  foreach $key (sort keys %display) {
    $acct_code = $display{$key};
    $label = $acct_code;
    if ($label =~ /^(none|none2|none3)$/) {
      $label = "None";
    }

    if ($sortorder ne "") {
      print "<tr><th>Acct Code:</th><th>$label</th></tr>\n";
    }

    print "<tr>";
    print "<th align=left><font size=-1> Date </font></th>";
    print "<th align=left><font size=-1> Type </font></th>";
    print "<th align=center><font size=-1> Qty </font></th>";
    print "<th align=center><font size=-1> % Declined </font></th>";
    print "<th align=left><font size=-1> Graph </font></th>";
    print "</tr>\n";

    if ($function eq "daily") {
      $rows = 6;
      if ($max <= 0) {
        $max = 1;
      }
      foreach my $date (sort keys %dates) {
        $datestr = sprintf("%02d/%02d/%04d", substr($date,4,2), substr($date,6,2), substr($date,0,4));
        my @totals = ($values{$date . "authsuccess" . $acct_code},$values{$date . "authbadcard" . $acct_code},
                      $values{$date . "authfraud" . $acct_code},$values{$date . "voidsuccess" . $acct_code},
                      $values{$date . "returnsuccess" . $acct_code},$values{$date . "postauthsuccess" . $acct_code});

        for($j=0; $j<=5; $j++) {
          $width[$j] = sprintf("%d",$totals[$j] * 125 / $max);
          if ($width[$j] <= 0) {
            $width[$j] = 1;
          }
        }
        $total_auths = $values{$date . "authsuccess" . $acct_code} + 
                       $values{$date . "authbadcard" . $acct_code} + 
                       $values{$date . "authfraud" . $acct_code} + 000001;

        $total_auths_summ = $total_auths_summ + $total_auths;
        if ($values{$date . "authsuccess" . $acct_code} > 0) {
          $avgticket = sprintf("%0.2f",$sums{$date . "authsuccess" . $acct_code}/$values{$date . "authsuccess" . $acct_code});
        }

        print "<tr>";
        print "<th align=left rowspan=$rows><font size=-1>$datestr<br>Avg: \$$avgticket</font></th>";
        print "<td><font size=-1>Successful Auth</font></td>\n";
        my $a = $date . "authsuccess" . $acct_code; 
        print "<td align=right><font size=-1>$values{$a}</font></td>";
        print "<td align=\"center\"><font size=-1>NA</font></td>\n";
        print "<td align=left><img src=\"/images/blue.gif\" height=8 width=$width[0]></td>";
        print "</tr>\n";
        $trans_auth_success_grandtotal += $values{$a};
        print "<td><font size=-1>Declined Auth - Badcard</font></td>\n";
        $a = $date . "authbadcard" . $acct_code;
        printf("<td align=right><font size=-1>%.0f</font></td>", $values{$a});
        printf("<td align=right><font size=-1>%.1f \%</font></td>", ($values{$a}/$total_auths)*100);
        print "<td align=left><img src=\"/images/green.gif\" height=8 width=$width[1]></td>";
        print "</tr>\n";
        $trans_auth_badcard_grandtotal += $values{$a};
        print "<td><font size=-1>Declined Auth - Fraud Screen</font></td>\n";
        $a = $date . "authfraud" . $acct_code;
        printf("<td align=right><font size=-1>%.0f</font></td>", $values{$a});
        printf("<td align=right><font size=-1>%.1f \%</font></td>", ($values{$a}/$total_auths)*100);
        print "<td align=left><img src=\"/images/green.gif\" height=8 width=$width[2]></td>";
        print "</tr>\n";
        $trans_auth_fraud_grandtotal += $values{$a};
        print "<td><font size=-1>Voids</font>\n";

        if ($detailflag ==1 ) {
          print "<table border=1 width=\"100%\">\n";
          foreach my $reason (sort keys %acct_code4) {
            if ($reason =~ /\.cg/) {
              next;
            }
            print "<tr><td>$reason</td><td>$ac4_count{$date . \"voidsuccess\" . $reason}</td></tr>\n";
          }
          print "</table>\n";
        }

        print "</td>\n";

        $a = $date . "voidsuccess" . $acct_code;
        printf("<td align=right><font size=-1>%.0f</font></td>", $values{$a});
        print "<td align=\"center\"><font size=-1>NA</font>\n";
        print "</td>\n";
        print "<td align=left><img src=\"/images/red.gif\" height=8 width=$width[3]></td>";
        print "</tr>\n";
        $trans_void_success_grandtotal += $values{$a};
        print "<td><font size=-1>Returns</font></td>\n";
        $a = $date . "returnsuccess" . $acct_code;
        printf("<td align=right><font size=-1>%.0f</font></td>", $values{$a});
        print "<td align=\"center\"><font size=-1>NA</font></td>\n";
        print "<td align=left><img src=\"/images/red.gif\" height=8 width=$width[4]></td>";
        print "</tr>\n";
        $trans_retn_success_grandtotal += $values{$a};
        print "<td><font size=-1>Successful Post Auths</font></td>\n";
        $a = $date . "postauthsuccess" . $acct_code;
        printf("<td align=right><font size=-1>%.0f</font></td>", $values{$a});
        print "<td align=\"center\"><font size=-1>NA</font></td>\n";
        print "<td align=left><img src=\"/images/red.gif\" height=8 width=$width[5]></td>";
        print "</tr>\n";
        $trans_post_success_grandtotal += $values{$a};
      }
      print "<tr>";
      print "<th align=left rowspan=6><font size=-1>Summary<br></font></th>";
      print "<td><font size=-1>Successful Auth</font></td>\n";
      print "<td align=right><font size=-1>$trans_auth_success_grandtotal</font></td>";
      print "<td align=\"center\"><font size=-1>NA</font></td>\n";
      print "<td align=left>&nbsp;</td>";
      print "</tr>\n";
      print "<td><font size=-1>Declined Auth - Badcard</font></td>\n";
      printf("<td align=right><font size=-1>%.0f</font></td>", $trans_auth_badcard_grandtotal);
      printf("<td align=right><font size=-1>%.1f \%</font></td>", ($trans_auth_badcard_grandtotal/$total_auths_summ)*100);
      print "<td align=left>&nbsp;</td>";
      print "</tr>\n";
      print "<td><font size=-1>Declined Auth - Fraud Screen</font></td>\n";
      printf("<td align=right><font size=-1>%.0f</font></td>", $trans_auth_fraud_grandtotal);
      printf("<td align=right><font size=-1>%.1f \%</font></td>", ($trans_auth_fraud_grandtotal/$total_auths_summ)*100);
      print "<td align=left>&nbsp;</td>";
      print "</tr>\n";
      print "<td><font size=-1>Voids</font></td>\n";
      printf("<td align=right><font size=-1>%.0f</font></td>", $trans_void_success_grandtotal);
      print "<td align=\"center\"><font size=-1>NA</font></td>\n";
      print "<td align=left>&nbsp;</td>";
      print "</tr>\n";
      print "<td><font size=-1>Returns</font></td>\n";
      printf("<td align=right><font size=-1>%.0f</font></td>", $trans_retn_success_grandtotal);
      print "<td align=\"center\"><font size=-1>NA</font></td>\n";
      print "<td align=left>&nbsp;</td>";
      print "</tr>\n";
      print "<td><font size=-1>Successful Post Auths</font></td>\n";
      printf("<td align=right><font size=-1>%.0f</font></td>", $trans_post_success_grandtotal);
      print "<td align=\"center\"><font size=-1>NA</font></td>\n";
      print "<td align=left>&nbsp;</td>";
      print "</tr>\n";
    }
    else {
      $rows = 6;
      foreach my $date (sort keys %months) {
        $datestr = sprintf("%02d/%04d", substr($date,4,2), substr($date,0,4));
        my @totals = ($values{$date . "authsuccess" . $acct_code},$values{$date . "authbadcard" . $acct_code},
                      $values{$date . "authfraud" . $acct_code},$values{$date . "voidsuccess" . $acct_code},
                      $values{$date . "returnsuccess" . $acct_code},$values{$date . "postauthsuccess" . $acct_code});

        for($j=0; $j<=5; $j++) {
          $width[$j] = sprintf("%d",$totals[$j] * 125 / $maxmocnt);
          if ($width[$j] <= 0) {
            $width[$j] = 1;
          }
        }
        $total_auths = $values{$date . "authsuccess" . $acct_code} +
                       $values{$date . "authbadcard" . $acct_code} +
                       $values{$date . "authfraud" . $acct_code} + 000001;

        $total_auths_summ = $total_auths_summ + $total_auths;
        if ($values{$date . "authsuccess" . $acct_code} > 0) {
          $avgticket = sprintf("%0.2f",$sums{$date . "authsuccess" . $acct_code}/$values{$date . "authsuccess" . $acct_code});
        }

        print "<tr>";
        print "<th align=left rowspan=$rows><font size=-1>$datestr<br>Avg: \$$avgticket</font></th>";
        print "<td><font size=-1>Successful Auth</font></td>\n";
        my $a = $date . "authsuccess" . $acct_code;
        print "<td align=right><font size=-1>$values{$a}</font></td>";
        print "<td align=\"center\"><font size=-1>NA</font></td>\n";
        print "<td align=left><img src=\"/images/blue.gif\" height=8 width=$width[0]></td>";
        print "</tr>\n";
        $trans_auth_success_grandtotal += $values{$a};
        print "<td><font size=-1>Declined Auth - Badcard</font></td>\n";
        $a = $date . "authbadcard" . $acct_code;
        printf("<td align=right><font size=-1>%.0f</font></td>", $values{$a});
        printf("<td align=right><font size=-1>%.1f \%</font></td>", ($values{$a}/$total_auths)*100);
        print "<td align=left><img src=\"/images/green.gif\" height=8 width=$width[1]></td>";
        print "</tr>\n";
        $trans_auth_badcard_grandtotal += $values{$a};
        print "<td><font size=-1>Declined Auth - Fraud Screen</font></td>\n";
        $a = $date . "authfraud" . $acct_code;
        printf("<td align=right><font size=-1>%.0f</font></td>", $values{$a});
        printf("<td align=right><font size=-1>%.1f \%</font></td>", ($values{$a}/$total_auths)*100);
        print "<td align=left><img src=\"/images/green.gif\" height=8 width=$width[2]></td>";
        print "</tr>\n";
        $trans_auth_fraud_grandtotal += $values{$a};
        print "<td><font size=-1>Voids</font></td>\n";
        $a = $date . "voidsuccess" . $acct_code;
        $b = $date . "voidpending" . $acct_code;
        printf("<td align=right><font size=-1>%.0f </font></td>", $values{$a});
        print "<td align=\"center\"><font size=-1>NA</font></td>\n";
        print "<td align=left><img src=\"/images/red.gif\" height=8 width=$width[3]></td>";
        print "</tr>\n";
        $trans_void_success_grandtotal += $values{$a};
        print "<td><font size=-1>Returns</font></td>\n";
        $a = $date . "returnsuccess" . $acct_code;
        printf("<td align=right><font size=-1>%.0f</font></td>", $values{$a});
        print "<td align=\"center\"><font size=-1>NA</font></td>\n";
        print "<td align=left><img src=\"/images/red.gif\" height=8 width=$width[4]></td>";
        print "</tr>\n";
        $trans_retn_success_grandtotal += $values{$a};
        print "<td><font size=-1>Successful Post Auths</font></td>\n";
        $a = $date . "postauthsuccess" . $acct_code;
        printf("<td align=right><font size=-1>%.0f</font></td>", $values{$a});
        print "<td align=\"center\"><font size=-1>NA</font></td>\n";
        print "<td align=left><img src=\"/images/red.gif\" height=8 width=$width[5]></td>";
        print "</tr>\n";
        $trans_post_success_grandtotal += $values{$a};
      }
    }
  }
  $trans_month = $trans_auth_success_grandtotal + $trans_auth_badcard_grandtotal + 
                 $trans_auth_fraud_grandtotal + $trans_void_success_grandtotal + $trans_retn_success_grandtotal;
  printf("<tr><th align=left colspan=2><font size=-1>TOTAL:</font></th><td align=right><font size=-1>%.0f</font></td><td></td>",$trans_month);
  print "</table></div>\n";
}

sub tail {
  print <<EOF;
<div align="center">
<form  action=\"/admin/graphs.cgi\">
<input type=submit name=submit value=\"Main Page\">
</form>
</div>

</body>
</html>
EOF
}

sub billing_tail {
  print "<div align=\"left\">\n";
  #print "<form action=\"billing.cgi\" method=\"post\"><input type=\"mode\" value=\"mail\"></form>\n";
  #print "<a href=\"javascript:self.close();\">Close</a> | <a href=\"javascript:self.print();\">Print</a>\n";
  print "</div>\n";
  print "</body> \n";
  print "</html>\n";
}


sub report_head {
  #print "Content-Type: text/html\n\n";
  print "<html>\n";
  print "<head>\n";
  print "<title>Merchant Administration Area</title>\n";
  print "<base href=\"https://pay1.plugnpay.com\">\n";
  print "</head>\n";
  print "<script Language=\"Javascript\">\n";
  print "<!-- Start Script\n";
  print "function uncheck(thisForm) {\n";
  print "for (var k in thisForm.listval) {\n";
  print "  document.assemble.listval[k].checked = false\;\n";
  print "}\n";
  print "}\n";
  print "function check(thisForm) {\n";
  print "  for (var i in thisForm.listval) {\n";
  print "    document.assemble.listval[i].checked = true\;\n";
  print "  }\n";
  print "}\n";

  print "function notice() \{\n";
  print "  alert('Please be patient, creating the report may take several minutes.');\n";
  print "}\n\n";


  print "// end script-->\n";
  print "</script>\n";

  print "<body bgcolor=\"#ffffff\">\n";

  print "<div align=\"center\">\n";
  print "<table cellspacing=\"0\" cellpadding=\"4\" border=\"0\">\n";
  print "<tr><td align=\"center\" colspan=\"1\"><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corporate Logo\"></td></tr>\n";
  print "<tr><td align=\"center\" colspan=\"1\"><font size=\"4\" face=\"Arial,Helvetica,Univers,Zurich BT\">\n";
  if ($mode eq "billing") {
    print "<tr><td align=\"left\" colspan=\"1\"><font size=\"3\" face=\"Arial,Helvetica,Univers,Zurich BT\">\n";
    print "Bill To:<p>\n"; 
    print "$name<br>$company<br>\n";
    if ($addr1 ne "") {
      print "$addr1<br>\n";
    }
    if ($addr2 ne "") {
      print "$addr2<br>\n";
    }
    print "$city, $state  $zip<br>$country<p>&nbsp;</td></tr>\n";
  }
  else {
    print "<tr><td align=\"center\" colspan=\"1\"><font size=\"3\" face=\"Arial,Helvetica,Univers,Zurich BT\">\n";
    print "Graphs \& Reports";
    print "<br>$company</td></tr>\n";
  }
  print "</table>\n";
  print "</div>\n";

  print "<br>\n";

}


sub billing_head {
  #print "Content-Type: text/html\n\n";
  my $username = $ENV{"REMOTE_USER"};
  print "<html>\n";
  print "<head>\n";
  print "<title>Merchant Administration Area</title>\n";
  if ($username eq "northame") {
    print "<base href=\"https://www.icommercegateway.com\">\n";
  }
  else {
    print "<base href=\"https://pay1.plugnpay.com\">\n";
  }
  print "</head>\n";
  print "<style type=\"text/css\">\n";
  print "<!--\n";
  print "th { font-family: $fontface; font-size: 75%; color: $goodcolor }\n";
  print "td { font-family: $fontface; font-size: 70%; color: $goodcolor }\n";
  print ".badcolor { color: $badcolor }\n";
  print ".goodcolor { color: $goodcolor }\n";
  print ".larger { font-size: 100% }\n";
  print ".smaller { font-size: 60% }\n";
  print ".short { font-size: 8% }\n";
  print ".itemscolor { background-color: $goodcolor; color: $backcolor }\n";
  print ".itemrows { background-color: #d0d0d0 }\n";
  print ".divider { background-color: #4a7394 }\n";
  print ".items { position: static }\n";
  print "#badcard { position: static; color: red; border: solid red }\n";
  print ".info { position: static }\n";
  print "#tail { position: static }\n";
  print "-->\n";
  print "</style>\n";

  print "<body bgcolor=\"#ffffff\">\n";
  print "<div align=\"center\">\n";
  print "<table cellspacing=\"0\" cellpadding=\"4\" border=\"0\">\n";
  print "<tr><td align=\"center\" colspan=\"1\"><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corporate Logo\"></td></tr>\n";
  print "</table>\n";
  print "</div>\n";
  print "<div align=\"center\">\n";
  print "<table cellspacing=\"0\" cellpadding=\"4\" border=\"0\" width=\"500\">\n";
  if ($subacct ne "") {
    print "<tr><th align=\"left\" colspan=2 bgcolor=\"#4a7394\">Statement Period:</th><th bgcolor=\"#4a7394\" colspan=3 align=\"right\"><font size=-1>$startmonth/$startday/$startyear - $endmonth/$endday/$endyear</font></th></tr>\n";
    print "<tr><th align=\"left\" colspan=\"3\"><font size=\"-1\">Pay To:</th></tr>\n";
  }
  else {
    print "<tr><th align=\"left\" colspan=2 bgcolor=\"#4a7394\">Billing Period:</th><th bgcolor=\"#4a7394\" colspan=3 align=\"right\"><font size=-1>$startmonth/$startday/$startyear - $endmonth/$endday/$endyear</font></th></tr>\n";
    print "<tr><th align=\"left\" colspan=\"3\"><font size=\"-1\">Bill To:</th></tr>\n";
  }
  print "<tr><th colspan=5 align=\"left\">$name<br>$company<br>\n";
  if ($addr1 ne "") {
    print "$addr1<br>\n";
  }
  if ($addr2 ne "") {
    print "$addr2<br>\n";
  }
  print "$city, $state  $zip<br>$country<p>&nbsp;</th></tr>\n";

}

sub billing {
  if ($subacct ne "") {
    $qstr = "select feeid,feetype,feedesc,rate,type from billing where username='$username' and subacct='$subacct'";
  }
  else {
    $qstr = "select feeid,feetype,feedesc,rate,type from billing where username='$username'";
  }

  $dbh = &miscutils::dbhconnect("merch_info");
  my $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
  $sth->execute() or die "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($db{'feeid'},$db{'feetype'},$db{'desc'},$db{'rate'},$db{'type'}));
  while ($sth->fetch) {
  #  print "UN:$username, ID:$db{'feeid'},TYPE:$db{'feetype'},DESC:$db{'desc'},RATE:$db{'rate'},TYPE:$db{'type'}<br>\n";
    $feeid = $db{'feeid'};
    @feelist = (@feelist,$feeid);
    $$feeid{'feetype'} = $db{'feetype'};
    $$feeid{'desc'} = $db{'desc'};
    $$feeid{'rate'} = $db{'rate'};
    $$feeid{'type'} = $db{'type'};
    if ($db{'feetype'} eq "fixed") {
      @fixedlist = (@fixedlist,$feeid);
    }
  }
  $sth->finish;
  $dbh->disconnect;

  %label_hash = ('pertran','','percent','$');
  %rate_hash = ('pertran','$','percent','%');

  #$ac_count{"$trans_date$operation$finalstatus$acct_code"} += $count;
  #$ac2_count{"$trans_date$operation$finalstatus$acct_code2"} += $count;
  #$ac3_count{"$trans_date$operation$finalstatus$acct_code3"} += $count;
  #$count{"$trans_date$operation$finalstatus"} += $count;
  #$ac_sum{"$trans_date$operation$finalstatus$acct_code"} += $sum;
  #$ac2_sum{"$trans_date$operation$finalstatus$acct_code2"} += $sum;
  #$ac3_sum{"$trans_date$operation$finalstatus$acct_code3"} += $sum;
  #$sum{"$trans_date$operation$finalstatus"} += $sum;
  #$totalcnt{"TOTAL$operation$finalstatus"} += $count;
  #$totalsum{"TOTAL$operation$finalstatus"} += $sum;

  $total_auths_trans = $totalcnt{"TOTALauthsuccess"};

  #$total_trans_volume_success = $totalsum{'TOTALauthsuccess'} + $totalsum{'TOTALreturnsuccess'} - $totalsum{"TOTALvoidsuccess"} + 0.0001;
  $total_trans_volume_success = $totalsum{'TOTALpostauthsuccess'};
  $total_trans_volume_success = sprintf("%0.2f",$total_trans_volume_success);

  if ($newauthfee{'type'} eq "pertran") {
    $total_auths_new = $ac3_totalcnt{"TOTALauthsuccessnewcard"};
  }
  else {
    $total_auths_new = sprintf("%0.2f",$ac3_totalsum{"TOTALauthsuccessnewcard"});
  }
  if ($recauthfee{'type'} eq "pertran") {
    $total_auths_rec = $total_auths_trans - $total_auths_new;
  }
  else {
    $total_auths_rec = sprintf("%0.2f",$totalsum{'TOTALauthsuccess'} - $total_auths_new);
  }
  if ($declinedfee{'type'} eq "pertran") {
    $total_auths_decl = $totalcnt{"TOTALauthbadcard"};
  }
  else {
    $total_auths_decl = sprintf("%0.2f",$totalsum{"TOTALauthbadcard"});
  }
  if ($fraudfee{'type'} eq "pertran") {
    $total_fraud = $totalcnt{"TOTALauthfraud"};
  }
  else {
    $total_fraud = sprintf("%0.2f",$totalsum{"TOTALauthfraud"});
  }
  if ($returnfee{'type'} eq "pertran") {
    $total_retrn = $totalcnt{"TOTALreturnsuccess"};
  }
  else {
    $total_retrn = sprintf("%0.2f",$totalsum{"TOTALreturnsuccess"});
  }
  if ($voidfee{'type'} eq "pertran") {
    $total_void = $totalcnt{"TOTALvoidsuccess"};
  }
  else {
    $total_void = sprintf("%0.2f",$totalsum{"TOTALvoidsuccess"});
  }
  if ($cybersfee{'type'} eq "pertran") {
    $total_cybers = $totalcnt{"TOTALcybersuccess"};
  }
  else {
    $total_cybers = sprintf("%0.2f",$totalsum{'TOTALcybersuccess'});
  }

  $total_discnt = sprintf("%0.2f",$totalsum{'TOTALauthsuccess'} + $totalsum{'TOTALreturnsuccess'}); 

  my @transfee = ('newauthfee','recauthfee','declinedfee','returnfee','voidfee','fraudfee','cybersfee','discntfee');

  $total_auths_new_fee = sprintf("%0.2f",$total_auths_new * $newauthfee{'rate'});
  $total_auths_rec_fee = sprintf("%0.2f",$total_auths_rec * $recauthfee{'rate'});
  $total_auths_decl_fee = sprintf("%0.2f",$total_auths_decl * $declinedfee{'rate'});
  $total_fraud_fee = sprintf("%0.2f",$total_fraud * $fraudfee{'rate'});
  $total_retrn_fee = sprintf("%0.2f",$total_retrn * $returnfee{'rate'});
  $total_void_fee = sprintf("%0.2f",$total_void * $voidfee{'rate'});
  $total_cybers_fee = sprintf("%0.2f",$total_cybers * $cybersfee{'rate'});

  $total_discnt_fee = sprintf("%0.2f",$total_discnt * $discntfee{'rate'});

  #print "TRANS:$NOACCTCODEtrans_auth_badcard_grandtotal, DOLL:$NOACCTCODEtotalbadcrds\n";


#  print "<div align=\"center\"><table border=1 cellspacing=1 width=\"550\">\n";
#  print "<tr><th colspan=\"3\">Billing</th></tr>\n";
  if ($subacct ne "") {
  #$count{"$trans_date$operation$finalstatus"} += $count;
  #$ac_sum{"$trans_date$operation$finalstatus$acct_code"} += $sum;
    #$dates{$trans_date} = 1;
    foreach $date (sort keys %dates) {
      my $date1 = substr($date,4,2) . "/" . substr($date,6,2) . "/" . substr($date,0,4);
      print "<tr>";
      print "<th align=\"left\" bgcolor=\"#4a7394\" colspan=4> $date1 </th>\n";
      print "</tr>\n";

      my $sum = $sum{$date . 'postauthsuccess'};
      $tot_sum += $sum;
      $sum = sprintf("%0.2f",$sum + 0.0001);

      print "<tr>";
      print "<th align=\"left\"><font size=-1>Settled Auths</font></th>\n";
      print "<td align=right><font size=-1>$label_hash{$newauthfee{'type'}}$sum</font></td>";
      print "<td align=right><font size=-1> &nbsp; </font></td>";
      print "<th align=\"right\"><font size=-1> &nbsp; </font></th>\n";
      print "</tr>\n";

      my $ret = $sum{$date . 'returnsuccess'} + $sum{$date . 'returnpending'};
      $tot_ret += $ret;
      $ret = sprintf("%0.2f",$ret + 0.0001);

      print "<tr>";
      print "<th align=\"left\"><font size=-1>Returns</font></th>\n";
      print "<td align=right><font size=-1>$label_hash{$newauthfee{'type'}}$ret</font></td>";
      print "<td align=right><font size=-1> &nbsp; </font></td>";
      print "<th align=\"right\"><font size=-1> &nbsp; </font></th>\n";
      print "</tr>\n";

      $resrv_fee = ($sum * $resrvfee{'rate'}) + 0.001;
      $resrv_fee = sprintf("%0.2f",$resrv_fee);
      $tot_resrv_fee += $resrv_fee;

      print "<tr>";
      print "<th align=\"left\"><font size=-1>Reserves</font></th>\n";
      print "<td align=right><font size=-1>$label_hash{$newauthfee{'type'}}$resrv_fee</font></td>";
      print "<td align=right><font size=-1> &nbsp; </font></td>";
      print "<th align=\"right\"><font size=-1> &nbsp; </font></th>\n";
      print "</tr>\n";


      $discnt_fee = ($sum * $discntfee{'rate'}) + 0.001;
      $discnt_fee = sprintf("%0.2f",$discnt_fee);
      $tot_discnt_fee += $discnt_fee;

      print "<tr>";
      print "<th align=\"left\"><font size=-1>Discount</font></th>\n";
      print "<td align=right><font size=-1>$label_hash{$newauthfee{'type'}}$discnt_fee</font></td>";
      print "<td align=right><font size=-1> &nbsp; </font></td>";
      print "<th align=\"right\"><font size=-1> &nbsp; </font></th>\n";
      print "</tr>\n";

      #$acct_code4{$acct_code4} = $acct_code4;
      #$ac4_count{"$trans_date$operation$finalstatus$acct_code4"};
      #$ac4_sum{"$trans_date$operation$finalstatus$acct_code4"};

      $cb_cnt = $ac4_count{$date . "returnsuccessChargeback"} + $ac4_count{$date . "returnpendingChargeback"};

      $tot_cb_cnt += $cb_cnt;

      $chargebck_fee = ($cb_cnt * $chargebck{'rate'}) + 0.001;
      $chargebck_fee = sprintf("%0.2f",$chargebck_fee);

      $tot_chargebck_fee += $chargebck_fee;
      $tot_chargebck_fee = sprintf("%0.2f",$tot_chargebck_fee);

      print "<tr>";
      print "<th align=\"left\"><font size=-1>Chargebacks</font></th>\n";
      print "<td align=right><font size=-1>$label_hash{$chargebck{'type'}}$chargebck_fee</font></td>";
      print "<td align=right><font size=-1> &nbsp; </font></td>";
      print "<th align=\"right\"><font size=-1> &nbsp; </font></th>\n";
      print "</tr>\n";

      my $owed = $sum - $ret - $discnt_fee - $resrv_fee - $chargebck_fee; 
      $owed = sprintf("%.2f",$owed);
      $tot_owed += $owed;

      print "<tr>";
      print "<th align=\"left\"><font size=-1>Amount Owed</font></th>\n";
      print "<td align=right><font size=-1> &nbsp; </font></td>";
      print "<td align=right><font size=-1> &nbsp; </font></td>";
      print "<th align=\"right\" bgcolor=\"#4a7394\"><font size=-1> $owed </font></th>\n";
      print "</tr>\n";

      print "<tr>";
      print "<th align=\"left\" colspan=4> &nbsp; </th>\n";
      print "</tr>\n";


    }
  }
  else {
    print "<tr><th colspan=5 bgcolor=\"#4a7394\" align=left>Transaction Fees:</th></tr>\n";
    print "<tr><td rowspan=8>&nbsp; &nbsp;</td></tr>\n";
    print "<tr>";
    print "<th align=\"left\"><font size=-1>New Auths</font></th>\n";
    print "<td align=right><font size=-1>$label_hash{$newauthfee{'type'}}$total_auths_new</font></td>";
    print "<td align=right><font size=-1>$rate_hash{$newauthfee{'type'}}$newauthfee{'rate'}</font></td>";
    print "<th align=\"right\"><font size=-1>\$$total_auths_new_fee</font></th>\n";
    print "</tr>\n";
    print "<tr><th align=\"left\"><font size=-1>Rec Auths</font></th>\n";
    print "<td align=right><font size=-1>$label_hash{$recauthfee{'type'}}$total_auths_rec</font></td>";
    print "<td align=right><font size=-1>$rate_hash{$recauthfee{'type'}}$recauthfee{'rate'}</font></td>";
    print "<th align=\"right\"><font size=-1>\$$total_auths_rec_fee</font></th>\n";
    print "</tr>\n";
    print "<tr><th align=\"left\"><font size=-1>Declined Auths</font></th>\n";
    print "<td align=right><font size=-1>$label_hash{$declinedfee{'type'}}$total_auths_decl</font></td>";
    print "<td align=right><font size=-1>$rate_hash{$declinedfee{'type'}}$declinedfee{'rate'}</font></td>";
    print "<th align=\"right\"><font size=-1>\$$total_auths_decl_fee</font></th>\n";
    print "</tr>\n";
    print "<tr><th align=\"left\"><font size=-1>Returns/Credits</font></th>\n";
    print "<td align=right><font size=-1>$label_hash{$returnfee{'type'}}$total_retrn</font></td>";
    print "<td align=right><font size=-1>$rate_hash{$returnfee{'type'}}$returnfee{'rate'}</font></td>";
    print "<th align=\"right\"><font size=-1>\$$total_retrn_fee</font></th>\n";
    print "</tr>\n";
    print "<tr><th align=\"left\"><font size=-1>Voids</font></th>\n";
    print "<td align=right><font size=-1>$label_hash{$voidfee{'type'}}$total_void</font></td>";
    print "<td align=right><font size=-1>$rate_hash{$voidfee{'type'}}$voidfee{'rate'}</font></td>";
    print "<th align=\"right\"><font size=-1>\$$total_void_fee</font></th>\n";
    print "</tr>\n";
    print "<tr><th align=\"left\"><font size=-1>Fraud Screen</font></th>\n";
    print "<td align=right><font size=-1>$label_hash{$fraudfee{'type'}}$total_fraud</font></td>";
    print "<td align=right><font size=-1>$rate_hash{$fraudfee{'type'}}$fraudfee{'rate'}</font></td>";
    print "<th align=\"right\"><font size=-1>\$$total_fraud_fee</font></th>\n";
    print "</tr>\n";
    print "<tr><th align=\"left\"><font size=-1>CyberSource</font></th>\n";
    print "<td align=right><font size=-1>$label_hash{$cybersfee{'type'}}$total_cybers</font></td>";
    print "<td align=right><font size=-1>$rate_hash{$cybersfee{'type'}}$cybersfee{'rate'}</font></td>";
    print "<th align=\"right\"><font size=-1>\$$total_cybers_fee</font></th>\n";
    print "</tr>\n";
  }
  if ($subacct ne "") {
    #$total_discnt_fee = ($total_trans_volume_success * $discntfee{'rate'}) + 0.001;
    $tot_discnt_fee = sprintf("%0.2f",$tot_discnt_fee);

    #$total_resrv_fee = ($total_trans_volume_success * $resrvfee{'rate'}) + 0.001;
    $tot_resrv_fee = sprintf("%0.2f",$tot_resrv_fee);

    $tot_sum = sprintf("%0.2f",$tot_sum);
    $tot_ret = sprintf("%0.2f",$tot_ret);

    print "<tr><th colspan=5 bgcolor=\"#4a7394\" align=\"left\">Totals:</th></tr>\n";

    print "<tr><th align=\"left\"><font size=-1>Settled Auths</font></th>\n";
    print "<td align=right><font size=-1>\$$tot_sum</font></td>";
    print "<td align=right><font size=-1></font></td>";
    print "<th align=\"right\"><font size=-1>\$$tot_sum</font></th>\n";
    print "</tr>\n";

    print "<tr><th align=\"left\"><font size=-1>Returns</font></th>\n";
    print "<td align=right><font size=-1>\$$tot_ret</font></td>";
    print "<td align=right><font size=-1></font></td>";
    print "<th align=\"right\"><font size=-1>\$$tot_ret</font></th>\n";
    print "</tr>\n";

    print "<tr><th align=\"left\"><font size=-1>Reserve</font></th>\n";
    print "<td align=right><font size=-1>\$$tot_sum</font></td>";
    print "<td align=right><font size=-1>$rate_hash{$resrvfee{'type'}}$resrvfee{'rate'}</font></td>";
    print "<th align=\"right\"><font size=-1>\$$tot_resrv_fee</font></th>\n";
    print "</tr>\n";

    print "<tr><th align=\"left\"><font size=-1>Discount</font></th>\n";
    print "<td align=right><font size=-1>\$$tot_sum</font></td>";
    print "<td align=right><font size=-1>$rate_hash{$discntfee{'type'}}$discntfee{'rate'}</font></td>";
    print "<th align=\"right\"><font size=-1>\$$tot_discnt_fee</font></th>\n";
    print "</tr>\n";

    print "<tr><th align=\"left\"><font size=-1>Chargebacks</font></th>\n";
    print "<td align=right><font size=-1>$tot_cb_cnt</font></td>";
    print "<td align=right><font size=-1>$rate_hash{$chargebck{'rate'}}$chargebck{'rate'}</font></td>";
    print "<th align=\"right\"><font size=-1>\$$tot_chargebck_fee</font></th>\n";
    print "</tr>\n";

  }
  else {
    print "<tr><th colspan=5 bgcolor=\"#4a7394\" align=\"left\">Discount Fees:</th></tr>\n";
    print "<tr><td rowspan=2>&nbsp; &nbsp;</td></tr>\n";
    print "<tr><th align=\"left\"><font size=-1>Discount Rate</font></th>\n";
    print "<td align=right><font size=-1>\$$total_discnt</font></td>";
    print "<td align=right><font size=-1>$rate_hash{$discntfee{'type'}}$discntfee{'rate'}</font></td>";
    print "<th align=\"right\"><font size=-1>\$$total_discnt_fee</font></th>\n";
    print "</tr>\n";
  }
  print "<tr><th colspan=5 bgcolor=\"#4a7394\" align=\"left\">Monthly Fees:</th></tr>\n";
  #print "<tr><td rowspan=1>&nbsp; &nbsp;</td></tr>\n";

  foreach $feeid (@fixedlist) {
    print "<tr><td>&nbsp; &nbsp;</td><th align=\"left\"><font size=-1>$$feeid{'desc'}</font></th>\n";
    print "<td align=right><font size=-1>Monthly</font></td>";
    print "<td align=right><font size=-1>&nbsp;</font></td>";
    print "<th align=\"right\"><font size=-1>\$$$feeid{'rate'}</font></th>\n";
    print "</tr>\n";
    $total_fixed = $total_fixed + $$feeid{'rate'};
  }
  $total = $total_auths_new_fee + $total_auths_rec_fee + $total_auths_decl_fee + $total_cybers_fee + $total_discnt_fee + $total_fraud_fee + $total_retrn_fee + $total_fixed;

  if ($subacct ne "") {
    print "<tr><th align=\"left\" bgcolor=\"#4a7394\" colspan=4><font size=3>Total Due</font></td>\n";
    print "<th align=\"right\" bgcolor=\"#4a7394\"><font size=3>\$$tot_owed</font></th>\n";
    print "</tr>\n";
  }
  else {
    print "<tr><th align=\"left\" bgcolor=\"#4a7394\" colspan=4><font size=3>Total Owed</font></td>\n";
    print "<th align=\"right\" bgcolor=\"#4a7394\"><font size=3>\$$total</font></th>\n";
    print "</tr>\n";
  }
  print "</table></div>\n";
}

