#!/usr/local/bin/perl
require 5.001;
$| = 1;

package reports;

use miscutils;
use CGI;
use Time::Local qw(timegm);
use sysutils;
use Date::Calc qw(Add_Delta_Days Delta_Days Days_in_Month);


sub new {
  my $type = shift;

  my $debug = 1;

  $first_flag = 1;

  $earliest_date = "20040101"; 
  
  %altaccts = ('icommerceg',["icommerceg","icgoceanba","icgcrossco"],'golinte1',["golinte1","golinte6"]);

  %month_array2 = ("Jan","01","Feb","02","Mar","03","Apr","04","May","05","Jun","06","Jul","07","Aug","08","Sep","09","Oct","10","Nov","11","Dec","12");

  my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = gmtime(time());

  if ($month == 0) {
    $month = 12;
    $startmonth = sprintf("%02d",$month);
    $endmonth = "01";
  }
  else {
    $startmonth = sprintf("%02d",$month);
    $endmonth = sprintf("%02d",$month+1);
  }

  $endyear = sprintf("%02d",$year+1900);

  if ($startmonth > $endmonth) {
    $startyear = sprintf("%02d",$year+1900-1);
  }
  else {
    $startyear = $endyear;
  }

  $startday = "01";
  $endday = "01";

  print "SMO:$startmonth, EMO:$endmonth, SYR:$startyear, EYR:$endyear\n";

  $username = "northame";

  $mode = "billing";
  $format = "text";

  $goodcolor = "#000000";
  $badcolor = "#ff0000";
  $backcolor = "#ffffff";
  $fontface = "Arial,Helvetica,Univers,Zurich BT";

  $start = $startyear . $startmonth . $startday;
  $end = $endyear . $endmonth . $endday;

  if ($start eq "") {
    my ($dummy,$trans_date,$trans_time) = &miscutils::genorderid();
    $start = substr($trans_date,0,6);
  }
 
  if ($end eq "") {
    $end = $start;
  }

  if ($start < $earliest_date) {
    $start = $earliest_date;
  } 

  my $starttranstime = &miscutils::strtotime($start);
  my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = gmtime($starttranstime - (3600 * 24 * 7));
  $starttransdate = sprintf("%04d%02d%02d",$year+1900,$month+1,$day);

  $starttime = $start . "000000";

  my $endtime = &miscutils::strtotime($end);
  my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = gmtime($endtime - (3600 * 24 * 1));
  $endlabeldate = sprintf("%02d/%02d/%04d",$month+1,$day,$year+1900);


  $merchant = "EVERY";

  $dbh = &miscutils::dbhconnect("pnpmisc");

  if ($merchant =~ /^ALL|EVERY$/) {
    my (@un);
    $sth = $dbh->prepare(qq{
        select username,merchant_id,email,merchemail,processor
        from customers
        where reseller='northame'
        and status='live'
        order by username
       }) or die "Can't do: $DBI::errstr";
    $sth->execute or die "Can't execute: $DBI::errstr";
    $sth->bind_columns(undef,\($db_uname,$merchant_id,$email,$merchemail,$db_processor));
    while ($sth->fetch) {
      $mid{$db_uname} = "$merchant_id";
      $email{$db_uname} = $email;
      $merchemail{$db_uname} = $merchemail;
      $processor{$db_uname} = $db_processor;
      @un = (@un,$db_uname);  
    }

    $sth->finish;
    $altaccts{'northame'} = [@un];
  }
  $dbh->disconnect;

  return [], $type;
}

sub query_cust {
  $dbh = &miscutils::dbhconnect("pnpmisc");

  if ($subacct ne "") {
   $qstr = "select name,company,addr1,addr2,city,state,zip,country,reseller,processor from customers where subacct='$subacct'";
  } 
  else {
    $qstr = "select name,company,addr1,addr2,city,state,zip,country,reseller,processor from customers where username='$username'";
  }

  $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
  $sth->execute() or die "Can't execute: $DBI::errstr";
  ($name,$company,$addr1,$addr2,$city,$state,$zip,$country,$dbreseller,$processor) = $sth->fetchrow;
  $sth->finish;

  $qstr = "select fraud_config from customers where username='$username'";
  $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
  $sth->execute() or die "Can't execute: $DBI::errstr";
  ($fraud_config) = $sth->fetchrow;
  $sth->finish;

  $qstr = "select membership from pnpsetups where username='$username'";

  my $sth = $dbh->prepare(qq{$qstr}) or die "Can't prepare: $DBI::errstr";
  $sth->execute() or die "Can't execute: $DBI::errstr";
  ($membership) = $sth->fetchrow;
  $sth->finish;

  $dbh->disconnect;
}


sub query {
  %dates=();
  %operations=();
  %finalstatus=();
  %cardtypes=();
  %acct_code=();
  %acct_code2=();
  %acct_code3=();
  %acct_code4=();
  %count=();
  %ac_count=();
  %ac2_count=();
  %ac3_count=();
  %ac4_count=();
  %ct_count=();
  %countSA=(); 
  %count4=();
  %ac_count4=();
  %ac2_count4=();
  %ac3_count4=();
  %ac_count_ct=();
  %ac2_count_ct=();
  %ac3_count_ct=();
  %ac_sum=();
  %ac2_sum=();
  %ac3_sum=();
  %ac4_sum=();
  %ct_sum=(); 
  %ac_sum4=();
  %ac2_sum4=();
  %ac3_sum4=();
  %ac_sum_ct=();
  %ac2_sum_ct=();
  %ac3_sum_ct=();
  %sum=();
  %sum4=();
  %ac_totalcnt=();
  %ac_totalsum=();
  %ac2_totalcnt=();
  %ac2_totalsum=();
  %ac3_totalcnt=();
  %ac3_totalsum=();  
  %ac_totalcnt4=();
  %ac_totalsum4=();
  %ac2_totalcnt4=();
  %ac2_totalsum4=();
  %ac3_totalcnt4=();
  %ac3_totalsum4=();
  %totalcnt=();
  %totalsum=();
  %totalcnt4=();
  %totalsum4=();

  my ($subacct);
 
  $dbh = &miscutils::dbhconnect("pnpdata");

  $total = 0;

  $start1 = $start;
  $end1 = $end;

  $max = 200;
  $maxmonth = 200;
  $trans_max = 200;
  $trans_maxmonth = 200;
  $arraylimit = 20;

  $tt = time();

  my ($temp,@temp,@data); 
  $j = 0; 
  foreach my $var ( @{ $altaccts{$username} } ) { 
    $i++; 
    if ($i > $arraylimit) { 
     $j++; 
     $i = 0;  
    } 
    $temp[$j] .= "'$var',"; 
  }
  $j = 0;
  foreach my $tmp (@temp) {
    chop $tmp;
    $data[$j] = $tmp;
    $j++;  
  }

  &dateIN($starttransdate,$end,\@dateArray,\$qmarks);
  my @executeArray = ();

  foreach my $strg (@data) {
    @executeArray = ();
    push (@executeArray,@dateArray,$strg,$starttime);

    $qstr = "select trans_date, ";
    $qstr .= "username, operation, finalstatus, count(username), sum(substr(amount,4)) ";
    $qstr .= "from trans_log force index(tlog_tdateuname_idx) where trans_date IN ($qmarks) ";
    $qstr .= "and username=? ";
    $qstr .= "and trans_time>=? "; 
    $qstr .= "and operation NOT IN ('batch-prep','batchquery','batch-commit','query') and (duplicate IS NULL or duplicate ='') ";
    $qstr .= "group by trans_date, username, operation, finalstatus";

    my $qtime = gmtime(time());
    print "$qtime\nQSTR:$qstr\n\n\n";

    $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
    $sth->execute(@executeArray) or die "Can't execute: $DBI::errstr";
    $sth->bind_columns(undef,\($trans_date, $username, $operation, $finalstatus, $count, $sum));
    while ($sth->fetch) {
      $trans_date = substr($trans_date,0,10);
      $time = &miscutils::strtotime($trans_date);
      $adjust = time() - $time - ($todadjust * 3600);
      my ($dummy,$trans_date,$start_time) = &miscutils::gendatetime(-$adjust);

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
    
      if ($operation =~ /void|return/) {

        if (($acct_code4 eq "") || ($acct_code4 =~ /\.cg/)) {
          $acct_code4 = "no_reason";
        }
        elsif ($acct_code4 =~ /AVS/i) {
          $acct_code4 = "avs_mismatch";
        }
        elsif ($acct_code4 =~ /CVV/i) {
          $acct_code4 = "cvv_mismatch";
        }
        elsif($acct_code4 =~ /chargeback/) {
        $acct_code4 = "chargeback";
        }
        elsif($acct_code4 =~ /Customer Initiated/i) {
          $acct_code4 = "self_initiated";
        }
        elsif($acct_code4 =~ /Merchant Initiated/i) {
          $acct_code4 = "merchant_initiated";
        }
        elsif($acct_code4 =~ /Customer request/i) {
          $acct_code4 = "customer_service";
        }
        elsif($acct_code4 =~ /Bounced Email/i) {
          $acct_code4 = "bounced_email";
        }
        else {
          $acct_code4 = "no_reason";
        }
      }
      else {
        $acct_code4 = "";
      }

      if ($function eq "monthly") {
        $trans_date = substr($trans_date,0,6);
      }

      $dates{$trans_date} = 1;
      $operations{$operation} = 1;
      $finalstatus{$finalstatus} = 1;
      $cardtypes{$cardtype} = 1;
      $acct_code{$acct_code} = $acct_code;
      $acct_code2{$acct_code2} = $acct_code2;
      $acct_code3{$acct_code3} = $acct_code3;
      if ($acct_code4 ne "") {
        $acct_code4{$acct_code4} = $acct_code4;
      }

      $count{"$username$trans_date$operation$finalstatus"} += $count;
      $ac_count{"$username$trans_date$operation$finalstatus$acct_code"} += $count;
      $ac2_count{"$username$trans_date$operation$finalstatus$acct_code2"} += $count;
      $ac3_count{"$username$trans_date$operation$finalstatus$acct_code3"} += $count;
      $ac4_count{"$username$trans_date$operation$finalstatus$acct_code4"} += $count;
      $ct_count{"$username$trans_date$operation$finalstatus$cardtype"} += $count;

      $count4{"$username$trans_date$operation$finalstatus$acct_code4"} += $count;
      $ac_count4{"$username$trans_date$operation$finalstatus$acct_code$acct_code4"} += $count;
      $ac2_count4{"$username$trans_date$operation$finalstatus$acct_code2$acct_code4"} += $count;
      $ac3_count4{"$username$trans_date$operation$finalstatus$acct_code3$acct_code4"} += $count;

      $ac_count_ct{"$username$trans_date$operation$finalstatus$acct_code$cardtype"} += $count;
      $ac2_count_ct{"$username$trans_date$operation$finalstatus$acct_code2$cardtype"} += $count;
      $ac3_count_ct{"$username$trans_date$operation$finalstatus$acct_code3$cardtype"} += $count;

      $ac_sum{"$username$trans_date$operation$finalstatus$acct_code"} += $sum;
      $ac2_sum{"$username$trans_date$operation$finalstatus$acct_code2"} += $sum;
      $ac3_sum{"$username$trans_date$operation$finalstatus$acct_code3"} += $sum;
      $ac4_sum{"$username$trans_date$operation$finalstatus$acct_code4"} += $sum;
      $ct_sum{"$username$trans_date$operation$finalstatus$cardtype"} += $sum;

      $ac_sum4{"$username$trans_date$operation$finalstatus$acct_code$acct_code4"} += $sum;
      $ac2_sum4{"$username$trans_date$operation$finalstatus$acct_code2$acct_code4"} += $sum;
      $ac3_sum4{"$trans_date$operation$finalstatus$acct_code3$acct_code4"} += $sum;

      $ac_sum_ct{"$username$trans_date$operation$finalstatus$acct_code$cardtype"} += $sum;
      $ac2_sum_ct{"$username$trans_date$operation$finalstatus$acct_code2$cardtype"} += $sum;
      $ac3_sum_ct{"$username$trans_date$operation$finalstatus$acct_code3$cardtype"} += $sum;

      $sum{"$username$trans_date$operation$finalstatus"} += $sum;
      $sum4{"$username$trans_date$operation$finalstatus$acct_code4"} += $sum;

      $ac_totalcnt{"TOTAL$username$operation$finalstatus$acct_code"} += $count;
      $ac_totalsum{"TOTAL$username$operation$finalstatus$acct_code"} += $sum;
      $ac2_totalcnt{"TOTAL$username$operation$finalstatus$acct_code2"} += $count;
      $ac2_totalsum{"TOTAL$username$operation$finalstatus$acct_code2"} += $sum;
      $ac3_totalcnt{"TOTAL$username$operation$finalstatus$acct_code3"} += $count;
      $ac3_totalsum{"TOTAL$username$operation$finalstatus$acct_code3"} += $sum;
      $ct_totalcnt{"TOTAL$username$operation$finalstatus$cardtype"} += $count;
      $ct_totalsum{"TOTAL$username$operation$finalstatus$cardtype"} += $sum;

      $ac_totalcnt4{"TOTAL$username$operation$finalstatus$acct_code$acct_code4"} += $count;
      $ac_totalsum4{"TOTAL$username$operation$finalstatus$acct_code$acct_code4"} += $sum;
      $ac2_totalcnt4{"TOTAL$username$operation$finalstatus$acct_code2$acct_code4"} += $count;
      $ac2_totalsum4{"TOTAL$username$operation$finalstatus$acct_code2$acct_code4"} += $sum;
      $ac3_totalcnt4{"TOTAL$username$operation$finalstatus$acct_code3$acct_code4"} += $count;
      $ac3_totalsum4{"TOTAL$username$operation$finalstatus$acct_code3$acct_code4"} += $sum;

      $totalcnt{"TOTAL$username$operation$finalstatus"} += $count;
      $totalsum{"TOTAL$username$operation$finalstatus"} += $sum;

      $totalcnt4{"TOTAL$username$operation$finalstatus$acct_code4"} += $count;
      $totalsum4{"TOTAL$username$operation$finalstatus$acct_code4"} += $sum;

      $maxsum1 = $sum{$username . $trans_date . $operation . "success"} + $sum{$username . $trans_date . $operation . "badcard"};

      if ($maxsum1 > $maxsum) {
        $maxsum = $maxsum1;
      }

      $maxcnt1 = $count{"$username$trans_date$operation$finalstatus"};

      if ($maxcnt1 > $maxcnt) {
        $maxcnt = $maxcnt1;
      }
    }
    $sth->finish;
  }
  $dbh->disconnect;

  $reports::lastusername = $username;
  print "LASTUN:$reports::lastusername\n";

  $noacct_code{'1'} = "";
}

sub query_fraud {
    #($username,$start,$end) = @_;
    $operation = "auth";
    $finalstatus = "fraud";
 
    my $start1 = $start . "000000";
    my $end1 = $end . "000000";
 
    $qstr = "select username, trans_time, acct_code, acct_code2, acct_code3, subacct from fraud_log where trans_time>='$start1' and trans_time<'$end1' ";
 
    print "QSTR:$qstr:<p>\n";
 
    my ($username, $trans_time, $acct_code, $acct_code2, $acct_code3, $subacct);

    my $dbh = &miscutils::dbhconnect("fraudtrack");
 
    my $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
    $sth->execute or die "Can't execute: $DBI::errstr";
    $sth->bind_columns(undef,\($username, $trans_time, $acct_code, $acct_code2, $acct_code3, $subacct));
    while ($sth->fetch) {
      $trans_date = substr($trans_time,0,8);
      if ($function eq "monthly") {
        $trans_date = substr($trans_date,0,6);
      }
 
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
 
      $ac_count{"$username$trans_date$operation$finalstatus$acct_code"}++;
      $ac2_count{"$username$trans_date$operation$finalstatus$acct_code2"}++;
      $ac3_count{"$username$trans_date$operation$finalstatus$acct_code3"}++;
      $count{"$username$trans_date$operation$finalstatus"}++;
 
      $countSA{"$username$trans_date$operation$finalstatus$subacct"}++;
 
      $ac_totalcnt{"TOTAL$username$operation$finalstatus$acct_code"}++;
      $ac2_totalcnt{"TOTAL$username$operation$finalstatus$acct_code2"}++;
      $ac3_totalcnt{"TOTAL$username$operation$finalstatus$acct_code3"}++;
      $totalcnt{"TOTAL$username$operation$finalstatus"}++;
      $aaaa = $totalcnt{"TOTAL$username$operation$finalstatus"};
  } # sweet indentation! and what...this function doesn't do anything with the loaded data....or.... GLOBALS!!!  NO STRICT!!!!!
  $sth->finish;
  $dbh->disconnect;
}


sub sales {
  if ($processor eq "cybercash") {
    $rowspan = 3;
  }
  else {
    $rowspan = 9;
  }
  print "<div align=\"center\"><table border=1 cellspacing=1 width=\"550\">\n";
  print "<tr><th colspan=\"4\">Sales Volume (\$)</th></tr>\n";
  if ($sortorder eq "acctcode") {
    %display = %acct_code;
    %values = %ac_sum;
    %values4 = %ac_sum4;
  }
  elsif ($sortorder eq "acctcode2") {
    %display = %acct_code2;
    %values = %ac2_sum;
    %values4 = %ac2_sum4;
  }
  elsif ($sortorder eq "acctcode3") {
    %display = %acct_code3;
    %values = %ac3_sum;
    %values4 = %ac3_sum4;
  }
  else {
    %display = %noacct_code;
    %values = %sum;
    %values4 = %sum4;
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
    foreach my $date (sort keys %dates) {
      if ($function eq "monthly") {
        $datestr = sprintf("%02d/%04d", substr($date,4,2), substr($date,0,4));
      }
      else {
        $datestr = sprintf("%02d/%02d/%04d", substr($date,4,2), substr($date,6,2), substr($date,0,4));
      }

      if ($max == 0) {
        $max = 1;
      }

      $tot_auths =  $values{$username . $date . "authsuccess" . $acct_code} + $values{$username . $date . "authbadcard" . $acct_code};
      $width = sprintf("%d",$values{$username . $date . "authsuccess" . $acct_code} * 300 / $max);
      $width2 = sprintf("%d",$values{$username . $date . "voidsuccess" . $acct_code} * 300 / $max);
      $width3 = sprintf("%d",$values{$username . $date . "returnsuccess" . $acct_code} * 300 / $max);
      $width4 = sprintf("%d",$values{$username . $date . "postauthsuccess" . $acct_code} * 300 / $max);
      $width5 = sprintf("%d",$tot_auths * 300 / $max);
      $width6 = sprintf("%d",$values4{$username . $date . "voidsuccess" . $acct_code . "avs_mismatch"} * 300 / $max);
      $width7 = sprintf("%d",$values4{$username . $date . "voidsuccess" . $acct_code . "cvv_mismatch"} * 300 / $max);
      $width8 = sprintf("%d",$values4{$username . $date . "authbadcard" . $acct_code} * 300 / $max);

      # hey lets just indent another level starting NOW!  not fixing this now.
        if ($width <= 0) {
          $width = 1;
        }
        if ($width1 <= 0) {
          $width1 = 1;
        }
   
        $values{$username . $date . "voidsuccess" . $acct_code} = $values{$username . $date . "voidsuccess" . $acct_code}
                        - $values4{$username . $date . "voidsuccess" . $acct_code . "avs_mismatch"}
                        - $values4{$username . $date . "voidsuccess" . $acct_code . "cvv_mismatch"};

        $values{$username . $date . "voidsuccess" . $acct_code} = sprintf("%.2f",$values{$username . $date . "voidsuccess" . $acct_code});
        $values{$username . $date . "voidsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
 
        $values{$username . $date . "authsuccess" . $acct_code} = $values{$username . $date . "authsuccess" . $acct_code}
                        - $values4{$username . $date . "voidsuccess" . $acct_code . "avs_mismatch"}
                        - $values4{$username . $date . "voidsuccess" . $acct_code . "cvv_mismatch"};
        $values{$username . $date . "authsuccess" . $acct_code} = sprintf("%.2f",$values{$username . $date . "authsuccess" . $acct_code});
        $values{$username . $date . "authsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;

        $values{$username . $date . "authbadcard" . $acct_code} = $values{$username. $date . "authbadcard" . $acct_code}; 
        $values{$username . $date . "authbadcard" . $acct_code} = sprintf("%.2f",$values{$username . $date . "authbadcard" . $acct_code});
        $values{$username . $date . "authbadcard" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;

        $values{$username . $date . "postauthsuccess" . $acct_code} = sprintf("%.2f",$values{$username . $date . "postauthsuccess" . $acct_code});

        $net_to_bank = $values{$username . $date . "postauthsuccess" . $acct_code} - $values{$username . $date . "returnsuccess" . $acct_code};
        $net_to_bank = sprintf("%.2f",$net_to_bank);
        $net_to_bank =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $net_to_bank =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

        $values{$username . $date . "postauthsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;

        $values{$username . $date . "returnsuccess" . $acct_code} = sprintf("%.2f",$values{$username . $date . "returnsuccess" . $acct_code} + $values{$username . $date . "returnpending" . $acct_code});
        $values{$username . $date . "returnsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;

        $values4{$username . $date . "voidsuccess" . $acct_code . "avs_mismatch"} = sprintf("%.2f",$values4{$username . $date . "voidsuccess" . $acct_code . "avs_mismatch"});
        $values4{$username . $date . "voidsuccess" . $acct_code . "avs_mismatch"} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;

        $values4{$username . $date . "voidsuccess" . $acct_code . "cvv_mismatch"} = sprintf("%.2f",$values4{$username . $date . "voidsuccess" . $acct_code . "cvv_mismatch"});
        $values4{$username . $date . "voidsuccess" . $acct_code . "cvv_mismatch"} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;

        $tot_auths = sprintf("%.2f",$tot_auths);
        $tot_auths =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $tot_auths =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

        print "<tr>\n";
        print "<th align=left rowspan=$rowspan><font size=-1>$datestr</font></th><td><font size=-1>Total Auths.</font></td>\n";
        print "<td align=right><font size=-1>\$$tot_auths</font></td>\n";
        print "<td align=left><img src=\"/images/blue.gif\" height=8 width=$width5></td>";
        print "</tr>\n";

        print "<tr>\n";
        print "<td><font size=-1> Success</font></td>\n";
        print "<td align=right><font size=-1>\$$values{$date . \"authsuccess\" . $acct_code}</font></td>\n";
        print "<td align=left><img src=\"/images/green.gif\" height=8 width=$width></td>";
        print "</tr>\n";

        print "<tr>\n";
        print "<td><font size=-1> Declined</font></td>\n";
        print "<td align=right><font size=-1>\$$values{$date . \"authbadcard\" . $acct_code}</font></td>\n";
        print "<td align=left><img src=\"/images/red.gif\" height=8 width=$width8></td>";
        print "</tr>\n";

        print "<tr>\n";
        print "<td><font size=-1> AVS Mismatch</font></td>\n";
        print "<td align=right><font size=-1>\$$values4{$date . \"voidsuccess\" . $acct_code . \"avs_mismatch\"}</font></td>\n";
        print "<td align=left><img src=\"/images/red.gif\" height=8 width=$width6></td>";
        print "</tr>\n";

        print "<tr>\n";
        print "<td><font size=-1> CVV Mismatch</font></td>\n";
        print "<td align=right><font size=-1>\$$values4{$date . \"voidsuccess\" . $acct_code . \"cvv_mismatch\"}</font></td>\n";
        print "<td align=left><img src=\"/images/red.gif\" height=8 width=$width7></td>";
        print "</tr>\n";

        if ($processor ne "cybercash") {
          print "<tr><td><font size=-1> Voids</font></td>";
          print "<td align=right><font size=-1>\$$values{$date . \"voidsuccess\" . $acct_code}</font></td>\n";
          print "<td align=left><img src=\"/images/red.gif\" height=8 width=$width2></td>";
          print "</tr>\n";
          print "<tr><td><font size=-1>Returns</font></td>";
          print "<td align=right><font size=-1>\$$values{$date . \"returnsuccess\" . $acct_code}</font></td>\n";
          print "<td align=left><img src=\"/images/red.gif\" height=8 width=$width3></td>";
          print "</tr>\n";
          print "<tr><td><font size=-1>Post Auths</font></td>";
          print "<td align=right><font size=-1>\$$values{$date . \"postauthsuccess\" . $acct_code}</font></td>\n";
          print "<td align=left><img src=\"/images/green.gif\" height=8 width=$width4></td>";
          print "</tr>\n";

          print "<tr><td><font size=-1>Net to Bank</font></td>";
          print "<td align=right><font size=-1>\$$net_to_bank</font></td>\n";
          print "<td align=left></td>";
          print "</tr>\n";
        }
      }
  }

  $total_net_to_bank = $totalsum{"TOTAL$username" . 'postauthsuccess'} - $totalsum{"TOTAL$username" . 'returnsuccess'};
  $total_net_to_bank = sprintf("%.2f",$total_net_to_bank);
  $total_net_to_bank =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $total_net_to_bank =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

  $totalsum{"TOTAL$username" . 'auth'} = sprintf("%.2f",$totalsum{"TOTAL$username" . 'authsuccess'} + $totalsum{"TOTAL$username". 'authbadcard'});
  $totalsum{"TOTAL$username" . 'auth'} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{"TOTAL$username" . 'auth'} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

  $totalsum{"TOTAL$username" . 'voidsuccess'} = sprintf("%.2f",$totalsum{"TOTAL$username" . 'voidsuccess'} - $totalsum4{"TOTAL$username" . 'voidsuccessavs_mismatch'}- $totalsum4{"TOTAL$username" . 'voidsuccesscvv_mismatch'});

  $totalsum{"TOTAL$username" . 'authbadcard'} = sprintf("%.2f",$totalsum{"TOTAL$username" . 'authbadcard'});

  $totalsum{"TOTAL$username" . 'voidsuccess'} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{"TOTAL$username" . 'voidsuccess'} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

  $totalsum{"TOTAL$username" . 'authbadcard'} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{"TOTAL$username" . 'authbadcard'} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

  $totalsum{"TOTAL$username" . 'authsuccess'} = $totalsum{"TOTAL$username" . 'authsuccess'}
           - $totalsum4{"TOTAL$username" . 'voidsuccessavs_mismatch'} 
           - $totalsum4{"TOTAL$username" . 'voidsuccesscvv_mismatch'};

  $totalsum4{"TOTAL$username" . 'voidsuccessavs_mismatch'} = sprintf("%.2f",$totalsum4{"TOTAL$username" . 'voidsuccessavs_mismatch'});
  $totalsum4{"TOTAL$username" . 'voidsuccessavs_mismatch'} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum4{"TOTAL$username" . 'voidsuccessavs_mismatch'} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

  $totalsum4{"TOTAL$username" . 'voidsuccesscvv_mismatch'} = sprintf("%.2f",$totalsum4{"TOTAL$username" . 'voidsuccesscvv_mismatch'});
  $totalsum4{"TOTAL$username" . 'voidsuccesscvv_mismatch'} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum4{"TOTAL$username" . 'voidsuccesscvv_mismatch'} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

  $totalsum{"TOTAL$username" . 'authsuccess'} = sprintf("%.2f",$totalsum{"TOTAL$username" . 'authsuccess'});
  $totalsum{"TOTAL$username" . 'authsuccess'} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{"TOTAL$username" . 'authsuccess'} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;
  $totalsum{"TOTAL$username" . 'postauthsuccess'} = sprintf("%.2f",$totalsum{"TOTAL$username" . 'postauthsuccess'});
  $totalsum{"TOTAL$username" . 'postauthsuccess'} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{"TOTAL$username" . 'postauthsuccess'} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

  $totalsum{"TOTAL$username" . 'returnsuccess'} = sprintf("%.2f",$totalsum{"TOTAL$username" . 'returnsuccess'} + $totalsum{"TOTAL$username" . 'returnpending'});
  $totalsum{"TOTAL$username" . 'returnsuccess'} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{"TOTAL$username" . 'returnsuccess'} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

  print "<tr>\n";
  print "<th align=left rowspan=$rowspan><font size=-1>Totals</font></th><td><font size=-1>Total Auths.</font></td>\n";
  print "<td align=right><font size=-1>\$$totalsum{\"TOTAL$username\" . 'auth'}</font></td>\n";
  print "<td align=left></td>";
  print "</tr>\n";

  print "<tr>\n";
  print "<td><font size=-1> Success</font></td>\n";
  print "<td align=right><font size=-1>\$$totalsum{\"TOTAL$username\" . 'authsuccess'}</font></td>\n";
  print "<td align=left></td>";
  print "</tr>\n";

  print "<tr>\n";
  print "<td><font size=-1> Declined</font></td>\n";
  print "<td align=right><font size=-1>\$$totalsum{\"TOTAL$username\" . 'authbadcard'}</font></td>\n";
  print "<td align=left></td>";
  print "</tr>\n";

  print "<tr>\n";
  print "<td><font size=-1> AVS Mismatch</font></td>\n";
  print "<td align=right><font size=-1>\$$totalsum4{\"TOTAL$username\" . 'voidsuccessavs_mismatch'}</font></td>\n";
  print "<td align=left></td>";
  print "</tr>\n";

  print "<tr>\n";
  print "<td><font size=-1> CVV Mismatch</font></td>\n";
  print "<td align=right><font size=-1>\$$totalsum4{\"TOTAL$username\" . 'voidsuccesscvv_mismatch'}</font></td>\n";
  print "<td align=left></td>";
  print "</tr>\n";
  if ($processor ne "cybercash") {
    print "<tr><td><font size=-1> Voids</font></td>";
    print "<td align=right><font size=-1>\$$totalsum{\"TOTAL$username\" . 'voidsuccess'}</font></td>\n";
    print "<td align=left></td>";
    print "</tr>\n";
    print "<tr><td><font size=-1>Returns</font></td>";
    print "<td align=right><font size=-1>\$$totalsum{\"TOTAL$username\" . 'returnsuccess'}</font></td>\n";
    print "<td align=left></td>";
    print "</tr>\n";
    print "<tr><td><font size=-1>Post Auths</font></td>";
    print "<td align=right><font size=-1>\$$totalsum{\"TOTAL$username\" . 'postauthsuccess'}</font></td>\n";
    print "<td align=left></td>";
    print "</tr>\n";

    print "<tr><td><font size=-1>Net to Bank</font></td>";
    print "<td align=right><font size=-1>\$$total_net_to_bank</font></td>\n";
    print "<td align=left> <!-- Throughput: $throughput\% --> </td>";
    print "</tr>\n";

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

    $rows = 7;
    if ($max <= 0) {
      $max = 1;
    }
    foreach my $date (sort keys %dates) {
      if ($function eq "monthly") {
       $datestr = sprintf("%02d/%04d", substr($date,4,2), substr($date,0,4));
      }
      else {
        $datestr = sprintf("%02d/%02d/%04d", substr($date,4,2), substr($date,6,2), substr($date,0,4));
      }

      $total_auths = $values{$username . $date . "authsuccess" . $acct_code} +
                     $values{$username . $date . "authbadcard" . $acct_code} +
                     $values{$username . $date . "authfraud" . $acct_code};

      if ($total_auths < 1) {
        $total_auths = .00001;
      }

      $values{$username . $date . "returnsuccess" . $acct_code} += $values{$username . $date . "returnpending" . $acct_code};

      my @totals = ($total_auths,$values{$username . $date . "authsuccess" . $acct_code},$values{$username . $date . "authbadcard" . $acct_code},
                    $values{$username . $date . "authfraud" . $acct_code},$values{$username . $date . "voidsuccess" . $acct_code},
                    $values{$username . $date . "returnsuccess" . $acct_code},$values{$username . $date . "postauthsuccess" . $acct_code}
                    );

      for(my $j=0; $j<=6; $j++) {
        $width[$j] = sprintf("%d",$totals[$j] * 125 / $max);
        if ($width[$j] <= 0) {
          $width[$j] = 1;
        }
      }

      if ($values{$date . "authsuccess" . $acct_code} > 0) {
        $avgticket = sprintf("%0.2f",$sums{$username . $date . "authsuccess" . $acct_code}/$values{$username . $date . "authsuccess" . $acct_code});
      }

      $total_auths_summ += $total_auths;
      print "<tr>";
      print "<th align=left rowspan=$rows><font size=-1>$datestr<br>Avg: \$$avgticket</font></th>";
      print "<td><font size=-1>Total Auth Attempts</font></td>\n";
      printf ("<td align=right><font size=-1>%2d</font></td>",$total_auths);
      print "<td align=\"center\"><font size=-1>NA</font></td>\n";
      print "<td align=left><img src=\"/images/blue.gif\" height=8 width=$width[0]></td>";
      print "</tr>\n";

      print "<tr>";
      print "<td><font size=-1> Successful Auth</font></td>\n";
      my $a = $username . $date . "authsuccess" . $acct_code; 
      print "<td align=right><font size=-1>$values{$a}</font></td>";
      printf("<td align=right><font size=-1>%.1f \%</font></td>", ($values{$a}/$total_auths)*100);
      print "<td align=left><img src=\"/images/green.gif\" height=8 width=$width[1]></td>";
      print "</tr>\n";

      $trans_auth_success_grandtotal += $values{$a};
      print "<tr><td><font size=-1> Declined Auth - Badcard</font></td>\n";
      $a = $username . $date . "authbadcard" . $acct_code;
      printf("<td align=right><font size=-1>%.0f</font></td>", $values{$a});
      printf("<td align=right><font size=-1>%.1f \%</font></td>", ($values{$a}/$total_auths)*100);
      print "<td align=left><img src=\"/images/red.gif\" height=8 width=$width[2]></td>";
       print "</tr>\n";

      $trans_auth_badcard_grandtotal += $values{$a};
      print "<tr><td><font size=-1> Declined Auth - Fraud Screen</font></td>\n";
      $a = $username . $date . "authfraud" . $acct_code;
      printf("<td align=right><font size=-1>%.0f</font></td>", $values{$a});
      printf("<td align=right><font size=-1>%.1f \%</font></td>", ($values{$a}/$total_auths)*100);
      print "<td align=left><img src=\"/images/red.gif\" height=8 width=$width[3]></td>";
      print "</tr>\n";

      $trans_auth_fraud_grandtotal += $values{$a};
      print "<tr><td><font size=-1>Voids</font>\n";

      if ($detailflag ==1 ) {
        print "<table border=1 width=\"100%\">\n";
        foreach my $reason (sort keys %acct_code4) {
          if ($reason =~ /\.cg/) {
            next;
          }
          print "<tr><td>$reason</td><td align=\"right\">$ac4_count{$username . $date . \"voidsuccess\" . $reason}</td></tr>\n";
        }
        print "</table>\n";
      }

      print "</td>\n";

      $a = $username . $date . "voidsuccess" . $acct_code;
      printf("<td align=right><font size=-1>%.0f</font></td>", $values{$a});
      print "<td align=\"center\"><font size=-1>NA</font>\n";
      print "</td>\n";
      print "<td align=left><img src=\"/images/red.gif\" height=8 width=$width[4]></td>";
      print "</tr>\n";

      $trans_void_success_grandtotal += $values{$a};
      print "<tr><td><font size=-1>Returns</font>\n";
      if ($detailflag ==1 ) {
        print "<table border=1 width=\"100%\">\n";
        foreach my $reason (sort keys %acct_code4) {
          if ($reason =~ /\.cg/) {
            next;
          }
          print "<tr><td>$reason</td><td align=\"right\">$ac4_count{$username . $date . \"returnsuccess\" . $reason}</td></tr>\n";
        }
        print "</table>\n";
      }
      print "</td>\n";
      $a = $username . $date . "returnsuccess" . $acct_code;
      printf("<td align=right><font size=-1>%.0f</font></td>", $values{$a});
      print "<td align=\"center\"><font size=-1>NA</font></td>\n";
      print "<td align=left><img src=\"/images/red.gif\" height=8 width=$width[5]></td>";
      print "</tr>\n";

      $trans_retn_success_grandtotal += $values{$a};
      print "<tr><td><font size=-1>Successful Post Auths</font></td>\n";
      $a = $username . $date . "postauthsuccess" . $acct_code;
      printf("<td align=right><font size=-1>%.0f</font></td>", $values{$a});
      print "<td align=\"center\"><font size=-1>NA</font></td>\n";
      print "<td align=left><img src=\"/images/green.gif\" height=8 width=$width[6]></td>";
      print "</tr>\n";
      $trans_post_success_grandtotal += $values{$a};
    }
    if ($total_auths_summ < 1) {
      $total_auths_summ = 0.0001;
    }
    print "<tr>";
    print "<th align=left rowspan=8><font size=-1>Summary<br></font></th>";
    print "<td><font size=-1>Total Auth Attempts</font></td>\n";
    printf ("<td align=right><font size=-1>%2d</font></td>",$total_auths_summ);
    print "<td align=\"center\"><font size=-1>NA</font></td>\n";
    print "<td align=left>&nbsp;</td>";
    print "</tr>\n";
    print "<tr>";
    print "<td><font size=-1>Successful Auth</font></td>\n";
    print "<td align=right><font size=-1>$trans_auth_success_grandtotal</font></td>";
    printf("<td align=right><font size=-1>%.1f \%</font></td>", ($trans_auth_success_grandtotal/$total_auths_summ)*100);
    print "<td align=left>&nbsp;</td>";
    print "</tr>\n";
    print "<tr><td><font size=-1>Declined Auth - Badcard</font></td>\n";
    printf("<td align=right><font size=-1>%.0f</font></td>", $trans_auth_badcard_grandtotal);
    printf("<td align=right><font size=-1>%.1f \%</font></td>", ($trans_auth_badcard_grandtotal/$total_auths_summ)*100);
    print "<td align=left>&nbsp;</td>";
    print "</tr>\n";
    print "<tr><td><font size=-1>Declined Auth - Fraud Screen</font></td>\n";
    printf("<td align=right><font size=-1>%.0f</font></td>", $trans_auth_fraud_grandtotal);
    printf("<td align=right><font size=-1>%.1f \%</font></td>", ($trans_auth_fraud_grandtotal/$total_auths_summ)*100);
    print "<td align=left>&nbsp;</td>";
    print "</tr>\n";
    print "<tr><td><font size=-1>Voids</font>\n";
    if ($detailflag ==1 ) {
      print "<table border=1 width=\"100%\">\n";
      foreach my $reason (sort keys %acct_code4) {
        if ($reason =~ /\.cg/) {
          next;
        }
        print "<tr><td>$reason</td><td align=\"right\">$totalcnt4{\"TOTAL$username\" . \"voidsuccess\" . $reason}</td></tr>\n";
      }
      print "</table>\n";
    }
    print "</td>\n";

    printf("<td align=right><font size=-1>%.0f</font></td>", $trans_void_success_grandtotal);
    printf("<td align=right><font size=-1>%.1f \%</font></td>", ($trans_void_success_grandtotal/$total_auths_summ)*100);
    print "<td align=left>&nbsp;</td>";
    print "</tr>\n";

    print "<tr><td><font size=-1>Returns</font>\n";
    if ($detailflag ==1 ) {
      print "<table border=1 width=\"100%\">\n";
      foreach my $reason (sort keys %acct_code4) {
        if ($reason =~ /\.cg/) {
          next;
        }
        my $a = $totalcnt4{"TOTAL$username" . "returnsuccess" . $reason} + $totalcnt4{"TOTAL$username" . "returnpending" . $reason};
        print "<tr><td>$reason</td><td align=\"right\">$a</td></tr>\n";
      }
      print "</table>\n";
    }
    print "</td>\n";
    printf("<td align=right><font size=-1>%.0f</font></td>", $trans_retn_success_grandtotal);
    print "<td align=\"center\"><font size=-1>NA</font></td>\n";
    print "<td align=left>&nbsp;</td>";
    print "</tr>\n";

    print "<tr><td><font size=-1>Successful Post Auths</font></td>\n";
    printf("<td align=right><font size=-1>%.0f</font></td>", $trans_post_success_grandtotal);
    printf("<td align=right><font size=-1>%.1f \%</font></td>", ($trans_post_success_grandtotal/$total_auths_summ)*100);
    print "<td align=left>&nbsp;</td>";
    print "</tr>\n";

    print "<tr><td><font size=-1>Chargebacks</font></td>\n";
    printf("<td align=right><font size=-1>%.0f</font></td>", $totcb_cnt);
    if ($trans_post_success_grandtotal > 0) {
      printf("<td align=right><font size=-1>%.1f \%</font></td>", ($totcb_cnt/$trans_post_success_grandtotal)*100);
    }
    else {
      print "<td align=\"center\"><font size=-1>NA</font></td>\n";
    }
    print "<td align=left>&nbsp;</td>";
    print "</tr>\n";
  }
  $trans_month = $trans_auth_success_grandtotal + $trans_auth_badcard_grandtotal + 
                 $trans_auth_fraud_grandtotal + $trans_void_success_grandtotal + $trans_retn_success_grandtotal;
  printf("<tr><th align=left colspan=2><font size=-1>TOTAL:</font></th><td align=right><font size=-1>%.0f</font></td><td></td>",$trans_month);
  print "</table></div>\n";
}


sub batch_summary {
  $rowspan = 9;
  print "<div align=\"center\"><table border=1 cellspacing=1 width=\"550\">\n";
  print "<tr><th colspan=\"5\">Batch Summary (\$)</th></tr>\n";

  %values = %ac_sum;

  print "<tr>";
  print "<th align=left><font size=-1>Date</font></th>";
  print "<th align=left><font size=-1>Card Type</font></th>";
  print "<th align=left><font size=-1>Returns</font></th>";
  print "<th align=left><font size=-1>Postauths</font></th>";
  print "<th align=left><font size=-1>Net to Bank</font></th>";
  print "</tr>\n";
  foreach my $date (sort keys %dates) {
    if ($function eq "monthly") {
      $datestr = sprintf("%02d/%04d", substr($date,4,2), substr($date,0,4));
    }
    else {
      $datestr = sprintf("%02d/%02d/%04d", substr($date,4,2), substr($date,6,2), substr($date,0,4));
    }

    foreach $acct_code (sort keys %acct_code) {
      $values{$username . $date . "postauthsuccess" . $acct_code} = sprintf("%.2f",$values{$username . $date . "postauthsuccess" . $acct_code});

      $net_to_bank = $values{$username . $date . "postauthsuccess" . $acct_code} - $values{$username . $date . "returnsuccess" . $acct_code};
      $net_to_bank = sprintf("%.2f",$net_to_bank);
      $net_to_bank =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
      $net_to_bank =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

      $values{$username . $date . "postauthsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;

      $values{$username . $date . "returnsuccess" . $acct_code} = sprintf("%.2f",$values{$date . "returnsuccess" . $acct_code});
      $values{$username . $date . "returnsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;

      print "<tr><td><font size=-1>$datestr</font></td><td>$acct_code</td>";
      print "<td align=right><font size=-1>\$$values{$username . $date . \"returnsuccess\" . $acct_code}</font></td>\n";
      print "<td align=right><font size=-1>\$$values{$username . $date . \"postauthsuccess\" . $acct_code}</font></td>\n";
      print "<td align=right><font size=-1>\$$net_to_bank</font></td>\n";
      print "<td align=left></td>";
      print "</tr>\n";
    }
  }

  foreach $acct_code (sort keys %acct_code) {

    $total_net_to_bank = $ac_totalsum{"TOTAL$username" . 'postauthsuccess'. $acct_code} - $ac_totalsum{"TOTAL$username" . 'returnsuccess' . $acct_code};
    $total_net_to_bank = sprintf("%.2f",$total_net_to_bank);
    $total_net_to_bank =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
    $total_net_to_bank =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

    $ac_totalsum{"TOTAL$username" . 'postauthsuccess' . $acct_code} = sprintf("%.2f",$ac_totalsum{"TOTAL$username" . 'postauthsuccess' . $acct_code});
    $ac_actotalsum{"TOTAL$username" . 'postauthsuccess' . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
    $ac_totalsum{"TOTAL$username" . 'postauthsuccess' . $acct_code} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

    $ac_totalsum{"TOTAL$username" . 'returnsuccess' . $acct_code} = sprintf("%.2f",$ac_totalsum{"TOTAL$username" . 'returnsuccess' . $acct_code});
    $ac_totalsum{"TOTAL$username" . 'returnsuccess' . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
    $ac_totalsum{"TOTAL$username" . 'returnsuccess' . $acct_code} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

    print "<tr><td><font size=-1>Totals</font></td><td>$acct_code</td>";
    print "<td align=right><font size=-1>\$$ac_totalsum{\"TOTAL$username\" . 'returnsuccess' . $acct_code}</font></td>\n";
    print "<td align=right><font size=-1>\$$ac_totalsum{\"TOTAL$username\" . 'postauthsuccess' . $acct_code}</font></td>\n";
    print "<td align=right><font size=-1>\$$total_net_to_bank</font></td>\n";
    print "</tr>\n";
  }

  $total_net_to_bank = $totalsum{"TOTAL$username" . 'postauthsuccess'} - $totalsum{"TOTAL$username" . 'returnsuccess'};
  $total_net_to_bank = sprintf("%.2f",$total_net_to_bank);
  $total_net_to_bank =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $total_net_to_bank =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

  $totalsum{"TOTAL$username" . 'postauthsuccess'} = sprintf("%.2f",$totalsum{"TOTAL$username" . 'postauthsuccess'});
  $totalsum{"TOTAL$username" . 'postauthsuccess'} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{"TOTAL$username" . 'postauthsuccess'} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

  $totalsum{"TOTAL$username" . 'returnsuccess'} = sprintf("%.2f",$totalsum{"TOTAL$username" . 'returnsuccess'});
  $totalsum{"TOTAL$username" . 'returnsuccess'} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{"TOTAL$username" . 'returnsuccess'} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

  print "<tr><td><font size=-1>Totals</font></td><td>ALL</td>";
  print "<td align=right><font size=-1>\$$totalsum{\"TOTAL$username\" . 'returnsuccess'}</font></td>\n";
  print "<td align=right><font size=-1>\$$totalsum{\"TOTAL$username\" . 'postauthsuccess'}</font></td>\n";
  print "<td align=right><font size=-1>\$$total_net_to_bank</font></td>\n";
  print "</tr>\n";

  print "</table></div>\n";
}



sub tail {
  print <<EOF;
<div align="center">
<form  action=\"/admin/graphs.html\">
<input type=submit name=submit value=\"Main Page\">
</form>
</div>

</body>
</html>
EOF
}

sub billing_tail {
  $tail = "<div align=\"left\">\n";
  $tail .= "</div>\n";
  $tail .= "</body> \n";
  $tail .= "</html>\n";
}


sub report_head {
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
  print "<tr><td align=\"center\" colspan=\"4\"><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corporate Logo\"></td></tr>\n";
  print "<tr><th align=\"left\" colspan=1 bgcolor=\"#4a7394\">Report Period:</th><th bgcolor=\"#4a7394\" colspan=3 align=\"right\"><font size=-1>$startmonth/$startday/$startyear - $endmonth/$endday/$endyear</font></th></tr>\n";

  if ($mode eq "billing") {
    print "<tr><td align=\"left\" colspan=\"4\"><font size=\"3\" face=\"Arial,Helvetica,Univers,Zurich BT\">\n";
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
    print "$company</td></tr>\n";
  }
  print "</table>\n";
  print "</div>\n";

  print "<br>\n";

}


sub billing_head {
  #print "Content-Type: text/html\n\n";
  my $username = $ENV{"REMOTE_USER"};

  $head = "<html>\n";
  $head .= "<head>\n";
  $head .= "<title>Merchant Administration Area</title>\n";
  $head .= "<base href=\"https://www.icommercegateway.com\" x=\"$username\">\n";
  $head .= "</head>\n";
  $head .= "<style type=\"text/css\">\n";
  $head .= "<!--\n";
  $head .= "th { font-family: $fontface; font-size: 75%; color: $goodcolor }\n";
  $head .= "td { font-family: $fontface; font-size: 70%; color: $goodcolor }\n";
  $head .= ".badcolor { color: $badcolor }\n";
  $head .= ".goodcolor { color: $goodcolor }\n";
  $head .= ".larger { font-size: 100% }\n";
  $head .= ".smaller { font-size: 60% }\n";
  $head .= ".short { font-size: 8% }\n";
  $head .= ".itemscolor { background-color: $goodcolor; color: $backcolor }\n";
  $head .= ".itemrows { background-color: #d0d0d0 }\n";
  $head .= ".divider { background-color: #4a7394 }\n";
  $head .= ".items { position: static }\n";
  $head .= "#badcard { position: static; color: red; border: solid red }\n";
  $head .= ".info { position: static }\n";
  $head .= "#tail { position: static }\n";
  $head .= "-->\n";
  $head .= "</style>\n";

  $head .= "<body bgcolor=\"#ffffff\">\n";
  $head .= "<div align=\"center\">\n";
  $head .= "<table cellspacing=\"0\" cellpadding=\"4\" border=\"0\">\n";
  $head .= "<tr><td align=\"center\" colspan=\"1\"><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corporate Logo\"></td></tr>\n";
  $head .= "</table>\n";
  $head .= "</div>\n";
  $head .= "<div align=\"center\">\n";
  $head .= "<table cellspacing=\"0\" cellpadding=\"4\" border=\"0\" width=\"500\">\n";
  if ($subacct ne "") {
    $head .= "<tr><th align=\"left\" colspan=2 bgcolor=\"#4a7394\">Statement Period:</th><th bgcolor=\"#4a7394\" colspan=3 align=\"right\"><font size=-1>$startmonth/$startday/$startyear - $endlabeldate</font></th></tr>\n";
    $head .= "<tr><th align=\"left\" colspan=\"3\"><font size=\"-1\">Pay To:</th></tr>\n";
  }
  else {
    $head .= "<tr><th align=\"left\" colspan=2 bgcolor=\"#4a7394\">Billing Period:</th><th bgcolor=\"#4a7394\" colspan=3 align=\"right\"><font size=-1>$startmonth/$startday/$startyear - $endlabeldate</font></th></tr>\n";
    $head .= "<tr><th align=\"left\" colspan=\"3\"><font size=\"-1\">Bill To:</th></tr>\n";
  }
  $head .= "<tr><th colspan=5 align=\"left\">$name<br>$company<br>\n";
  if ($addr1 ne "") {
    $head .= "$addr1<br>\n";
  }
  if ($addr2 ne "") {
    $head .= "$addr2<br>\n";
  }
  $head .= "$city, $state  $zip<br>$country<p>&nbsp;</th></tr>\n";

  $head .= "<tr><th colspan=5 align=\"left\">Do not pay this bill, your checking account will be debited </th></tr>\n";

}


sub text_head {
  # seriously?
}
 


sub query_cback {

  my $qstr = "select orderid,trans_date,post_date,entered_date,amount,cardtype,country,returnflag from chargeback ";
  if ((exists $altaccts{$username}) && ($subacct ne "")) {
    my ($temp);
    foreach my $var ( @{ $altaccts{$username} } ) {
      $temp .= "username='$var' or ";
    }
    #chop $temp;
    $temp = substr($temp,0,length($temp)-3);
    $qstr .= "where ($temp) ";
  }
  else {
    $qstr .= "where username='$username' ";
  }

  $qstr .= "and post_date>='$start' and post_date<'$end' ";

  if ($subacct ne "") {
    $qstr .= "and subacct='$subacct' ";
  }

  $i=0;
  $dbh = &miscutils::dbhconnect("fraudtrack");
  my $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
  $sth->execute() or die "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($oid,$trans_date,$post_date,$entered_date,$amount,$cardtype,$country,$returnflag));
  while ($sth->fetch) {
    $k++;
    if ($k > 990) {
      $k = 0;
      $i++;
    }
    $temp[$i] .= "'$oid',";
    $cb{$post_date}++;
    $totcb_cnt++;
    $oiddate{$oid} = $post_date;

    $cardtypes{$cardtype} = 1;
    $tot_cbamt += $amount;
    $tot_cbamt{$cardtype} += $amount;
    $totcb_cnt{$cardtype}++;
    $cbamt_type = "cbamt" . $cardtype;
    $cbdeduct_type = "cbdeduct" . $cardtype;
    $$cbamt_type{$oiddate{$oid}} += $amount;
    if ($returnflag eq "1") {
      $$cbdeduct_type{$oiddate{$oid}} += $amount;
      $tot_deductcbamt += $amount;
      $tot_deductcbamt{$cardtype} += $amount;
    }
  }
  $sth->finish;
  $dbh->disconnect;
}


sub cb_report {
  if ($sortorder eq "acctcode") {
    %display = %acct_code;
    %values = %ac_count_ct;
    %sums = %ac_sum_ct;
  }
  elsif ($sortorder eq "acctcode2") {
    %display = %acct_code2;
    %values = %ac2_count_ct;
    %sums = %ac2_sum_ct;
  }
  elsif ($sortorder eq "acctcode3") {
    %display = %acct_code3;
    %values = %ac3_count_ct;
    %sums = %ac3_sum_ct;
  }
  else {
    %display = %noacct_code;
    %values = %ct_count;
    %sums = %ct_sum;
  }

  foreach $key (sort keys %display) {
    $acct_code = $display{$key};
    $label = $acct_code;
    if ($label =~ /^(none|none2|none3)$/) {
      $label = "None";
    }

    foreach $cardtype (sort keys %cardtypes) {
      foreach my $date (sort keys %dates) {
        $a = $sums{$username . $date . 'postauthsuccess' . $acct_code . $cardtype};
        $trancnt{$cardtype} += $values{$username . $date . 'postauthsuccess' . $acct_code . $cardtype};
        $transum{$cardtype} += $sums{$username . $date . 'postauthsuccess' . $acct_code . $cardtype};
      }
    }

    if ($sortorder ne "") {
      print "<tr><th>Acct Code:</th><th>$label</th></tr>\n";
    }

    print "<div align=\"center\"><table border=1 cellspacing=1 width=\"550\">\n";
    print "<tr>";
    print "<th colspan=1><font size=-1>CardType</font></th>";
    print "<th colspan=2><font size=-1>Settled</font></th>";
    print "<th colspan=2><font size=-1>Chargebacks</font></th>";
    print "<th colspan=2><font size=-1>Ratio</font></th>";
    print "</tr>\n";
    print "<tr>";
    print "<th><font size=-1>&nbsp;</font></th>";
    print "<th><font size=-1>\$</font></th>";
    print "<th><font size=-1>\#</font></th>";
    print "<th><font size=-1>\$</font></th>";
    print "<th><font size=-1>\#</font></th>";
    print "<th><font size=-1>\$</font></th>";
    print "<th><font size=-1>\#</font></th>";
    print "</tr>\n";

    foreach $cardtype (sort keys %cardtypes) {
      $transum{$cardtype} = sprintf("%.2f",$transum{$cardtype});
      $tot_cbamt{$cardtype} = sprintf("%.2f",$tot_cbamt{$cardtype});
    }

    foreach $cardtype (sort keys %cardtypes) {
      $cbamt_type = "cbamt" . $cardtype;
      $cbdeduct_type = "cbdeduct" . $cardtype;
      print "<tr>\n";
      print "<th>$cardtype</th>";
      print "<td align=right><font size=-1>\$$transum{$cardtype}</font></td>";
      printf("<td align=right><font size=-1>%.0f</font></td>", $trancnt{$cardtype});
      print "<td align=right><font size=-1>\$$tot_cbamt{$cardtype}</font></td>";
      printf("<td align=right><font size=-1>%.0f</font></td>", $totcb_cnt{$cardtype});
      if ($transum{$cardtype} > 0) {
        printf("<td align=right><font size=-1>%.2f \%</font></td>", ($tot_cbamt{$cardtype}/$transum{$cardtype})*100);
      }
      else {
        print "<td align=right><font size=-1> \%</font></td>\n";
      }
      if ($trancnt{$cardtype} > 0) {
        printf("<td align=right><font size=-1>%.2f \%</font></td>", ($totcb_cnt{$cardtype}/$trancnt{$cardtype})*100);
      }
      else {
        print "<td align=right><font size=-1> \%</font></td>\n";
      }
      print "</tr>\n";
    }
    print "</table></div>\n";

  }
}


sub billing {
  my (%db,@fixedlist,@feelist,$free250);
####  Billing Rates and Fees
  $qstr = "select feeid,feetype,feedesc,rate,type from billing where username='$username'";

  my $time = gmtime(time());
  print "PRE MERCHINFO TIME1:$time\n";

  $dbh = &miscutils::dbhconnect("merch_info");
  my $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
  $sth->execute() or die "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($db{'feeid'},$db{'feetype'},$db{'desc'},$db{'rate'},$db{'type'}));
  while ($sth->fetch) {
    $db{'rate'} =~ s/[^0-9\.]//g;
    $feeid = $db{'feeid'};
    @feelist = (@feelist,$feeid);
    $$feeid{'feetype'} = $db{'feetype'};
    $$feeid{'desc'} = $db{'desc'};
    $$feeid{'rate'} = $db{'rate'};
    $$feeid{'type'} = $db{'type'};
    if ($db{'feetype'} eq "fixed") {
      @fixedlist = (@fixedlist,$feeid);
    }
    if ($db{'feetype'} eq "discntfee") {
      $free250 = "yes";
    }
  }
  $sth->finish;
  $dbh->disconnect;

  my $time = gmtime(time());
  print "POST MERCHINFO TIME:$time\n";

  ####  Chargeback Info
  $qstr = "select orderid,entered_date,returnflag from chargeback ";

  if ((exists $altaccts{$username}) && ($subacct ne "")) {
    my ($temp);
    foreach my $var ( @{ $altaccts{$username} } ) {
      $temp .= "username='$var' or ";
    }
    $temp = substr($temp,0,length($temp)-3);
    $qstr .= "where ($temp) ";
  }
  else {
    $qstr .= "where username='$username' ";
  }

  $qstr .= "and entered_date>='$start' and entered_date<'$end' ";

  if ($subacct ne "") {
    $qstr .= "and subacct='$subacct' ";
  }
  my $i=0;
  my ($temp,%dates,@temp,%cb,%oiddate,%action);

  %label_hash = ('pertran','','percent','$');
  %rate_hash = ('pertran','$','percent','%');

  $total_auths_trans = $totalcnt{"TOTAL$username" . "authsuccess"};

  $free250_net = 0;
  if ($free250 eq "yes") {
    $free250_net = 250;
    if ($total_auths_trans > 250) {
      $total_auths_trans -= 250;
      $free250_net = 0;
    }
    else {
      $total_auths_trans = 0;
      $free250_net = 250 - $total_auths_trans;
    }
  }

  $total_trans_volume_success = $totalsum{"TOTAL$username" . 'postauthsuccess'};
  $total_trans_volume_success = sprintf("%0.2f",$total_trans_volume_success);


  if ($recauthfee{'rate'} eq "") {
    if ($newauthfee{'type'} eq "percent") {
      $total_auths_new = sprintf("%0.2f",$totalsum{"TOTAL$username" . "authsuccess"});
      $total_auths_new = $total_auths_trans;
    }
    else {
      $total_auths_new = $total_auths_trans;
    }
    $total_auths_rec = 0;
  }
  else {
    if ($newauthfee{'type'} eq "percent") {
      $total_auths_new = sprintf("%0.2f",$ac3_totalsum{"TOTAL$username" . "authsuccessnewcard"});
    }
    else {
      $total_auths_new = $ac3_totalcnt{"TOTAL$username" . "authsuccessnewcard"};
    }

    if ($recauthfee{'type'} eq "percent") {
      $total_auths_rec = sprintf("%0.2f",$totalsum{"TOTAL$username" . 'authsuccess'} - $total_auths_new);
    }
    else {
      $total_auths_rec = $total_auths_trans - $total_auths_new;
    }
  }

  if ($declinedfee{'type'} eq "percent") {
    $total_auths_decl = sprintf("%0.2f",$totalsum{"TOTAL$username" . "authbadcard"});
  }
  else {
    $total_auths_decl = $totalcnt{"TOTAL$username" . "authbadcard"};
    ## DCP - UnComment to apply free 250 to badcards too.
    #$total_auths_decl = $totalcnt{"TOTAL$username" . "authbadcard"} - $free250_net;
  }

  if ($fraudfee{'type'} eq "percent") {
    $total_fraud = sprintf("%0.2f",$totalsum{"TOTAL$username" . "authfraud"});
  }
  else {
    $total_fraud = $totalcnt{"TOTAL$username" . "authfraud"};
  }

  if ($returnfee{'type'} eq "percent") {
    $total_retrn = sprintf("%0.2f",$totalsum{"TOTAL$username" . "returnsuccess"} + $totalsum{"TOTAL$username" . "returnpending"});
  }
  else {
    $total_retrn = $totalcnt{"TOTAL$username" . "returnsuccess"} + $totalcnt{"TOTAL$username" . "returnpending"};
  }

  if ($voidfee{'type'} eq "percent") {
    $total_void = sprintf("%0.2f",$totalsum{"TOTAL$username" . "voidsuccess"});
  }
  else {
    $total_void = $totalcnt{"TOTAL$username" . "voidsuccess"};
  }

  if ($cybersfee{'type'} eq "percent") {
    $total_cybers = sprintf("%0.2f",$totalsum{"TOTAL$username" . 'cybersuccess'});
  }
  else {
    $total_cybers = $totalcnt{"TOTAL$username" . "cybersuccess"};
  }

  $total_discnt = sprintf("%0.2f",$totalsum{"TOTAL$username" . 'authsuccess'} + $totalsum{"TOTAL$username" . 'returnsuccess'}); 

  my @transfee = ('newauthfee','recauthfee','declinedfee','returnfee','voidfee','fraudfee','cybersfee','discntfee');

  $total_auths_new_fee = sprintf("%0.2f",$total_auths_new * $newauthfee{'rate'});
  $total_auths_rec_fee = sprintf("%0.2f",$total_auths_rec * $recauthfee{'rate'});
  $total_auths_decl_fee = sprintf("%0.2f",$total_auths_decl * $declinedfee{'rate'});
  $total_fraud_fee = sprintf("%0.2f",$total_fraud * $fraudfee{'rate'});
  $total_retrn_fee = sprintf("%0.2f",$total_retrn * $returnfee{'rate'});
  $total_void_fee = sprintf("%0.2f",$total_void * $voidfee{'rate'});
  $total_cybers_fee = sprintf("%0.2f",$total_cybers * $cybersfee{'rate'});

  $total_discnt_fee = sprintf("%0.2f",$total_discnt * $discntfee{'rate'});

  if ($membership ne "") {
    $premium = "yes";
  }
  else {
    $premium = "";
  }

  my $header_text = "$startmonth/$startday/$startyear - $endmonth/$endday/$endyear\n";
  my $header_text .= "MID\tUSERNAME\tEMAIL\tPREMIUM\tPROCESSOR\t";
  my $line_text = "$mid{$username}\t$username\t$merchemail{$username}\t$premium\t$processor{$username}\t";

  my ($line);
  if ($subacct ne "") {
    #$dates{$trans_date} = 1;

    foreach $date (sort keys %dates) {
      my $date1 = substr($date,4,2) . "/" . substr($date,6,2) . "/" . substr($date,0,4);
      $line .= "<tr>";
      $line .= "<th align=\"left\" bgcolor=\"#4a7394\" colspan=4> $date1 </th>\n";
      $line .= "</tr>\n";

      my $sum = $sum{$username . $date . 'postauthsuccess'};
      $tot_sum += $sum;
      $sum = sprintf("%0.2f",$sum + 0.0001);


      $line .= "<tr>";
      $line .= "<th align=\"left\"><font size=-1>Settled Auths</font></th>\n";
      $line .= "<td align=right><font size=-1>$label_hash{$newauthfee{'type'}}$sum</font></td>";
      $line .= "<td align=right><font size=-1> &nbsp; </font></td>";
      $line .= "<th align=\"right\"><font size=-1> &nbsp; </font></th>\n";
      $line .= "</tr>\n";

      my $ret = $sum{$username . $date . 'returnsuccess'} + $sum{$username . $date . 'returnpending'} - $cb_deductamt{$date};
      $tot_ret += $ret;
      $ret = sprintf("%0.2f",$ret + 0.0001);

      $line .= "<tr>";
      $line .= "<th align=\"left\"><font size=-1>Returns</font></th>\n";
      $line .= "<td align=right><font size=-1>$label_hash{$newauthfee{'type'}}$ret</font></td>";
      $line .= "<td align=right><font size=-1> &nbsp; </font></td>";
      $line .= "<th align=\"right\"><font size=-1> &nbsp; </font></th>\n";
      $line .= "</tr>\n";

      $resrv_fee = ($sum * $resrvfee{'rate'}) + 0.001;
      $resrv_fee = sprintf("%0.2f",$resrv_fee);
      $tot_resrv_fee += $resrv_fee;

      $line .= "<tr>";
      $line .= "<th align=\"left\"><font size=-1>Reserves</font></th>\n";
      $line .= "<td align=right><font size=-1>$label_hash{$newauthfee{'type'}}$resrv_fee</font></td>";
      $line .= "<td align=right><font size=-1> &nbsp; </font></td>";
      $line .= "<th align=\"right\"><font size=-1> &nbsp; </font></th>\n";
      $line .= "</tr>\n";

      $header_text .= "RESERV_FEE";
      $line_text .= "$resrv_fee\t";

      $discnt_fee = ($sum * $discntfee{'rate'}) + 0.001;
      $discnt_fee = sprintf("%0.2f",$discnt_fee);
      $tot_discnt_fee += $discnt_fee;

      $line .= "<tr>";
      $line .= "<th align=\"left\"><font size=-1>Discount</font></th>\n";
      $line .= "<td align=right><font size=-1>$label_hash{$newauthfee{'type'}}$discnt_fee</font></td>";
      $line .= "<td align=right><font size=-1> &nbsp; </font></td>";
      $line .= "<th align=\"right\"><font size=-1> &nbsp; </font></th>\n";
      $line .= "</tr>\n";

      $cb_cnt = $cb{$date};
      $tot_cb_cnt += $cb_cnt;

      #$line .= "<tr><td>DATE:$date, CBCNT:$cb{$date}, CBAMT:$cbamt{$date}</td></tr>\n";

      $chargebck_fee = (($cb_cnt * $chargebck{'rate'})+$cbamt{$date}) + 0.001;
      $chargebck_fee = sprintf("%0.2f",$chargebck_fee);

      $tot_chargebck_fee += $chargebck_fee;
      $tot_chargebck_fee = sprintf("%0.2f",$tot_chargebck_fee);

      #$header_text .= "CHRGEBCK_FEE";
      #$line_text .= "$chargebck_fee\t";

      $line .= "<tr>";
      $line .= "<th align=\"left\"><font size=-1>Chargebacks</font></th>\n";
      $line .= "<td align=right><font size=-1>$label_hash{$chargebck{'type'}}$chargebck_fee</font></td>";
      $line .= "<td align=right><font size=-1> &nbsp; </font></td>";
      $line .= "<th align=\"right\"><font size=-1> &nbsp; </font></th>\n";
      $line .= "</tr>\n";

      #$line .= "SUM:$sum, RET:$ret, DISCT:$discnt_fee, RESERV:$resrv_fee , CBFEE:$chargebck_fee<br>\n";

      my $owed = $sum - $ret - $discnt_fee - $resrv_fee - $chargebck_fee; 
      $owed = sprintf("%.2f",$owed);
     
      if ($subacct =~ /crowngatei|greenstedc|vmicards1/) {
        my $declcnt = $count{$date . 'authbadcard'};
        $decl_fee = ($declcnt * $declinedfee{'rate'}) + 0.001;
        $decl_fee = sprintf("%0.2f",$decl_fee);
        $tot_decl_fee += $decl_fee;

        $line .= "<tr><th colspan=2  align=\"left\">Transaction Fees</th></tr>\n";
        $line .= "<tr><th align=\"left\"><font size=-1>Declined Auths</font></th>\n";
        $line .= "<td align=right><font size=-1>$label_hash{$declinedfee{'type'}}$declcnt</font></td>";
        $line .= "<td align=right><font size=-1>$rate_hash{$declinedfee{'type'}}$declinedfee{'rate'}</font></td>";
        $line .= "<th align=\"right\"><font size=-1>\$$decl_fee</font></th>\n";
        $line .= "</tr>\n";

        my $fraudcnt = $count{$date . 'authfraud'};
        $fraud_fee = ($fraudcnt * $fraudfee{'rate'}) + 0.001;
        $fraud_fee = sprintf("%0.2f",$fraud_fee);
        $tot_fraud_fee += $fraud_fee;

        $line .= "<tr><th align=\"left\"><font size=-1>Fraud Screen</font></th>\n";
        $line .= "<td align=right><font size=-1>$label_hash{$fraudfee{'type'}}$fraudcnt</font></td>";
        $line .= "<td align=right><font size=-1>$rate_hash{$fraudfee{'type'}}$fraudfee{'rate'}</font></td>";
        $line .= "<th align=\"right\"><font size=-1>\$$fraud_fee</font></th>\n";
        $line .= "</tr>\n";
        $owed = $owed - $decl_fee - $fraud_fee;
        $owed = sprintf("%.2f",$owed);
      }

      $tot_owed += $owed;

      $line .= "<tr>";
      $line .= "<th align=\"left\"><font size=-1>Amount Owed</font></th>\n";
      $line .= "<td align=right><font size=-1> &nbsp; </font></td>";
      $line .= "<td align=right><font size=-1> &nbsp; </font></td>";
      $line .= "<th align=\"right\" bgcolor=\"#4a7394\"><font size=-1> $owed </font></th>\n";
      $line .= "</tr>\n";

      $line .= "<tr>";
      $line .= "<th align=\"left\" colspan=4> &nbsp; </th>\n";
      $line .= "</tr>\n";
    }
  } else {
    $line .= "<tr><th colspan=5 bgcolor=\"#4a7394\" align=left>Transaction Fees:</th></tr>\n";
    $line .= "<tr><td rowspan=8>&nbsp; &nbsp;</td></tr>\n";
    $line .= "<tr>";
    $line .= "<th align=\"left\"><font size=-1>New Auths</font></th>\n";
    $line .= "<td align=right><font size=-1>$label_hash{$newauthfee{'type'}}$total_auths_new</font></td>";
    $line .= "<td align=right><font size=-1>$rate_hash{$newauthfee{'type'}}$newauthfee{'rate'}</font></td>";
    $line .= "<th align=\"right\"><font size=-1>\$$total_auths_new_fee</font></th>\n";
    $line .= "</tr>\n";

    $header_text .= "TOT_AUTH_NEW_CNT\tTOT_AUTH_NEW_FEE\t";
    $line_text .= "$label_hash{$newauthfee{'type'}}$total_auths_new\t$total_auths_new_fee\t";

    if ($total_auths_rec ne "") {
      $line .= "<tr><th align=\"left\"><font size=-1>Rec Auths</font></th>\n";
      $line .= "<td align=right><font size=-1>$label_hash{$recauthfee{'type'}}$total_auths_rec</font></td>";
      $line .= "<td align=right><font size=-1>$rate_hash{$recauthfee{'type'}}$recauthfee{'rate'}</font></td>";
      $line .= "<th align=\"right\"><font size=-1>\$$total_auths_rec_fee</font></th>\n";
      $line .= "</tr>\n";
    }
    $header_text .= "TOT_AUTH_REC_CNT\tTOT_AUTH_REC_FEE\t";
    $line_text .= "$label_hash{$recauthfee{'type'}}$total_auths_rec\t$total_auths_rec_fee\t";

    $line .= "<tr><th align=\"left\"><font size=-1>Declined Auths</font></th>\n";
    $line .= "<td align=right><font size=-1>$label_hash{$declinedfee{'type'}}$total_auths_decl</font></td>";
    $line .= "<td align=right><font size=-1>$rate_hash{$declinedfee{'type'}}$declinedfee{'rate'}</font></td>";
    $line .= "<th align=\"right\"><font size=-1>\$$total_auths_decl_fee</font></th>\n";
    $line .= "</tr>\n";

    $header_text .= "TOT_AUTH_DECL_CNT\tTOT_AUTH_DECL_FEE\t";
    $line_text .= "$label_hash{$declinedfee{'type'}}$total_auths_decl\t$total_auths_decl_fee\t";

    $line .= "<tr><th align=\"left\"><font size=-1>Returns/Credits</font></th>\n";
    $line .= "<td align=right><font size=-1>$label_hash{$returnfee{'type'}}$total_retrn</font></td>";
    $line .= "<td align=right><font size=-1>$rate_hash{$returnfee{'type'}}$returnfee{'rate'}</font></td>";
    $line .= "<th align=\"right\"><font size=-1>\$$total_retrn_fee</font></th>\n";
    $line .= "</tr>\n";

    $header_text .= "TOT_RETRN_CNT\tTOT_RETRN_FEE\t";
    $line_text .= "$label_hash{$returnfee{'type'}}$total_retrn\t$total_retrn_fee\t";

    $line .= "<tr><th align=\"left\"><font size=-1>Voids</font></th>\n";
    $line .= "<td align=right><font size=-1>$label_hash{$voidfee{'type'}}$total_void</font></td>";
    $line .= "<td align=right><font size=-1>$rate_hash{$voidfee{'type'}}$voidfee{'rate'}</font></td>";
    $line .= "<th align=\"right\"><font size=-1>\$$total_void_fee</font></th>\n";
    $line .= "</tr>\n";

    $header_text .= "TOT_VOID_CNT\tTOT_VOID_FEE\t";
    $line_text .= "$label_hash{$voidfee{'type'}}$total_void\t$total_void_fee\t";

    $line .= "<tr><th align=\"left\"><font size=-1>Fraud Screen</font></th>\n";
    $line .= "<td align=right><font size=-1>$label_hash{$fraudfee{'type'}}$total_fraud</font></td>";
    $line .= "<td align=right><font size=-1>$rate_hash{$fraudfee{'type'}}$fraudfee{'rate'}</font></td>";
    $line .= "<th align=\"right\"><font size=-1>\$$total_fraud_fee</font></th>\n";
    $line .= "</tr>\n";

    $header_text .= "TOT_FRAUD_CNT\tTOT_FRAUD_FEE\t";
    $line_text .= "$label_hash{$fraudfee{'type'}}$total_fraud\t$total_fraud_fee\t";

    $line .= "<tr><th align=\"left\"><font size=-1>CyberSource</font></th>\n";
    $line .= "<td align=right><font size=-1>$label_hash{$cybersfee{'type'}}$total_cybers</font></td>";
    $line .= "<td align=right><font size=-1>$rate_hash{$cybersfee{'type'}}$cybersfee{'rate'}</font></td>";
    $line .= "<th align=\"right\"><font size=-1>\$$total_cybers_fee</font></th>\n";
    $line .= "</tr>\n";

    $header_text .= "TOT_CYBERSRC_CNT\tTOT_CYBERSRC_FEE\t";
    $line_text .= "$label_hash{$cybersfee{'type'}}$total_cybers\t$total_cybers_fee\t";

  }
  if ($subacct ne "") {
    #$total_discnt_fee = ($total_trans_volume_success * $discntfee{'rate'}) + 0.001;
    $tot_discnt_fee = sprintf("%0.2f",$tot_discnt_fee);

    #$total_resrv_fee = ($total_trans_volume_success * $resrvfee{'rate'}) + 0.001;
    $tot_resrv_fee = sprintf("%0.2f",$tot_resrv_fee);

    $tot_sum = sprintf("%0.2f",$tot_sum);
    $tot_ret = sprintf("%0.2f",$tot_ret);

    $line .= "<tr><th colspan=5 bgcolor=\"#4a7394\" align=\"left\">Totals:</th></tr>\n";

    $line .= "<tr><th align=\"left\"><font size=-1>Settled Auths</font></th>\n";
    $line .= "<td align=right><font size=-1>\$$tot_sum</font></td>";
    $line .= "<td align=right><font size=-1></font></td>";
    $line .= "<th align=\"right\"><font size=-1>\$$tot_sum</font></th>\n";
    $line .= "</tr>\n";

    $line .= "<tr><th align=\"left\"><font size=-1>Returns</font></th>\n";
    $line .= "<td align=right><font size=-1>\$$tot_ret</font></td>";
    $line .= "<td align=right><font size=-1></font></td>";
    $line .= "<th align=\"right\"><font size=-1>\$$tot_ret</font></th>\n";
    $line .= "</tr>\n";

    $line .= "<tr><th align=\"left\"><font size=-1>Reserve</font></th>\n";
    $line .= "<td align=right><font size=-1>\$$tot_sum</font></td>";
    $line .= "<td align=right><font size=-1>$rate_hash{$resrvfee{'type'}}$resrvfee{'rate'}</font></td>";
    $line .= "<th align=\"right\"><font size=-1>\$$tot_resrv_fee</font></th>\n";
    $line .= "</tr>\n";

    $line .= "<tr><th align=\"left\"><font size=-1>Discount</font></th>\n";
    $line .= "<td align=right><font size=-1>\$$tot_sum</font></td>";
    $line .= "<td align=right><font size=-1>$rate_hash{$discntfee{'type'}}$discntfee{'rate'}</font></td>";
    $line .= "<th align=\"right\"><font size=-1>\$$tot_discnt_fee</font></th>\n";
    $line .= "</tr>\n";

    $line .= "<tr><th align=\"left\"><font size=-1>Chargebacks</font></th>\n";
    $line .= "<td align=right><font size=-1>$tot_cb_cnt</font></td>";
    $line .= "<td align=right><font size=-1>$rate_hash{$chargebck{'rate'}}$chargebck{'rate'}</font></td>";
    $line .= "<th align=\"right\"><font size=-1>\$$tot_chargebck_fee</font></th>\n";
    $line .= "</tr>\n";

    $header_text .= "TOT_SETTLD_AUTH\tTOT_RETURNS\tRESERVE\tDISCOUNT\tCHARGEBACKS\t";
    $line_text .= "$tot_sum\t$tot_ret\t$tot_resrv_fee\t$tot_discnt_fee\t$tot_chargebck_fee\t";

    if ($subacct =~ /crowngatei|greenstedc|vmicards1/) {
      $line .= "<tr><th colspan=2  align=\"left\">Transaction Fees</th></tr>\n";
      $line .= "<tr><th align=\"left\"><font size=-1>Declined Auths</font></th>\n";
      $line .= "<td align=right><font size=-1>$label_hash{$declinedfee{'type'}}$total_auths_decl</font></td>";
      $line .= "<td align=right><font size=-1>$rate_hash{$declinedfee{'type'}}$declinedfee{'rate'}</font></td>";
      $line .= "<th align=\"right\"><font size=-1>\$$total_auths_decl_fee</font></th>\n";
      $line .= "</tr>\n";
      $line .= "<tr><th align=\"left\"><font size=-1>Fraud Screen</font></th>\n";
      $line .= "<td align=right><font size=-1>$label_hash{$fraudfee{'type'}}$total_fraud</font></td>";
      $line .= "<td align=right><font size=-1>$rate_hash{$fraudfee{'type'}}$fraudfee{'rate'}</font></td>";
      $line .= "<th align=\"right\"><font size=-1>\$$total_fraud_fee</font></th>\n";
      $line .= "</tr>\n";

      $header_text .= "TOT_AUTH_DECL_FEE\tTOT_FRAUD_FEE\t";
      $line_text .= "$total_auths_decl_fee\t$total_fraud_fee\t";
    }
  } else {
    $line .= "<tr><th colspan=5 bgcolor=\"#4a7394\" align=\"left\">Discount Fees:</th></tr>\n";
    $line .= "<tr><td rowspan=2>&nbsp; &nbsp;</td></tr>\n";
    $line .= "<tr><th align=\"left\"><font size=-1>Discount Rate</font></th>\n";
    $line .= "<td align=right><font size=-1>\$$total_discnt</font></td>";
    $line .= "<td align=right><font size=-1>$rate_hash{$discntfee{'type'}}$discntfee{'rate'}</font></td>";
    $line .= "<th align=\"right\"><font size=-1>\$$total_discnt_fee</font></th>\n";
    $line .= "</tr>\n";

    $header_text .= "TOT_DISCNT_FEE\t";
    $line_text .= "$total_discnt_fee\t";
  }
  $line .= "<tr><th colspan=5 bgcolor=\"#4a7394\" align=\"left\">Monthly Fees:</th></tr>\n";

  my ($total_fixed);
  foreach $feeid (@fixedlist) {
    $line .= "<tr><td>&nbsp; &nbsp;</td><th align=\"left\"><font size=-1>$$feeid{'desc'}</font></th>\n";
    $line .= "<td align=right><font size=-1>Monthly</font></td>";
    $line .= "<td align=right><font size=-1>&nbsp;</font></td>";
    $line .= "<th align=\"right\"><font size=-1>\$$$feeid{'rate'}</font></th>\n";
    $line .= "</tr>\n";
    $total_fixed += $$feeid{'rate'};
  }

  $header_text .= "TOT_FIXED_FEE\t";
  $line_text .= "$total_fixed\t";

  $total = $total_auths_new_fee + $total_auths_rec_fee + $total_auths_decl_fee +  $total_retrn_fee + $total_void_fee + $total_fraud_fee + $total_cybers_fee + $total_discnt_fee + $total_fixed;

  if ($subacct ne "") {
    $tot_owed = sprintf("%0.2f",$tot_owed);
    $line .= "<tr><th align=\"left\" bgcolor=\"#4a7394\" colspan=4><font size=3>Total Due</font></td>\n";
    $line .= "<th align=\"right\" bgcolor=\"#4a7394\"><font size=3>\$$tot_owed</font></th>\n";
    $line .= "</tr>\n";

    $header_text .= "TOT_OWED\n"; 
    $line_text .= "$tot_owed\n";

  }
  else {
    $total = sprintf("%0.2f",$total);
    $line .= "<tr><th align=\"left\" bgcolor=\"#4a7394\" colspan=4><font size=3>Total Owed</font></td>\n";
    $line .= "<th align=\"right\" bgcolor=\"#4a7394\"><font size=3>\$$total</font></th>\n";
    $line .= "</tr>\n";

    $header_text .= "TOT_FEE";         
    $line_text .= "$total";

  }
  $line .= "</table></div>\n";

  $merchant =~ s/[^0-9a-zA-Z]//g;
  if ($first_flag == 1) {
    &sysutils::filelog("write",">/home/p/pay1/web/NAB/billinglogs/$start$end$merchant\.txt");
    open (BILLING, ">/home/p/pay1/web/NAB/billinglogs/$start$end$merchant\.txt");
  } else {
    &sysutils::filelog("append",">>/home/p/pay1/web/NAB/billinglogs/$start$end$merchant\.txt");
    open (BILLING, ">>/home/p/pay1/web/NAB/billinglogs/$start$end$merchant\.txt");
  } 

  if ($first_flag == 1) {
    &sysutils::filelog("write",">/home/p/pay1/web/NAB/billinglogs/$start$end$merchant\.html"); 
    open (BILLINGHTML, ">/home/p/pay1/web/NAB/billinglogs/$start$end$merchant\.html"); 
  } else { 
    &sysutils::filelog("append",">>/home/p/pay1/web/NAB/billinglogs/$start$end$merchant\.html"); 
    open (BILLINGHTML, ">>/home/p/pay1/web/NAB/billinglogs/$start$end$merchant\.html"); 
  } 


  if ($first_flag == 1) {
    print "$header_text\n";
    print BILLING "$header_text\n";
    $first_flag = 5;
  }
  print "$line_text\n";
  print BILLING "$line_text\n";
  print BILLINGHTML "$head\n";
  print BILLINGHTML "$line\n";
  print BILLINGHTML "$tail\n";

  if ($emailbillflag == 1) {
    &email_bill($username,$head,$line,$tail);
  }
  $line = "";
  
}


sub email_bill {
  my ($username,$head,$line,$tail) = @_;
  my(@header);

  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setGatewayAccount($username);
  $emailObj->setType('html');
  $emailObj->setTo($email{$username});
  $emailObj->setFrom('billing@nabancard.com');
  $emailObj->setSubject("$username Monthly Billing - IcommerceGateway");

  my $content = join("\n",$head,$line,$tail);
  $emailObj->setContent($content);

  $eamilObj->send();
}

sub rec_report {
  print "REPORT\n";
  if ($processor eq "cybercash") {
    $rowspan = 1;
  }
  else {
    $rowspan = 1;
  }
  print "<div align=\"center\"><table border=1 cellspacing=1 width=\"550\">\n";
  %display = %noacct_code;
  %values = %sum;
  %valuescnt = %count;
  %sums = %sum;

  $total_auths_summ = 0.0000001;

  foreach $key (sort keys %display) {
    $acct_code = $display{$key};

    print "<tr><th>&nbsp;</th><th colspan=5>Dollar Volume</th><th colspan=5>Transaction Volume</th></tr>";
    print "<tr>";
    print "<th align=left><font size=-1>Date</font></th>";
    print "<th align=left><font size=-1>Auths</font></th>";
    print "<th align=left><font size=-1>New Sales</font></th>";
    print "<th align=left><font size=-1>Recurring</font></th>";
    print "<th align=left><font size=-1>Returns</font></th>";
    print "<th align=left><font size=-1>Total</font></th>";
    print "<th align=left><font size=-1>Auths</font></th>";
    print "<th align=left><font size=-1>New Sales</font></th>";
    print "<th align=left><font size=-1>Recurring</font></th>";
    print "<th align=left><font size=-1>Returns</font></th>";
    print "<th align=left><font size=-1>Total</font></th>";

    print "</tr>\n";
    if ($function eq "daily") {
      foreach my $date (sort keys %dates) {
        $datestr = sprintf("%02d/%02d/%04d", substr($date,4,2), substr($date,6,2), substr($date,0,4));

        $total_auths = $valuescnt{$username . $date . "authsuccess" . $acct_code} +
                       $valuescnt{$username . $date . "authbadcard" . $acct_code} +
                       $valuescnt{$username . $date . "authfraud" . $acct_code} + 000001;

        $total_auths_summ = $total_auths_summ + $total_auths;

#        print "DATE:$date<br>\n";
        $newsales = $values{$username . $date . "postauthsuccess" . $acct_code} - $ac3_sum{$username . $date . "postauthsuccessrecurring"};
        $newsales = sprintf("%.2f",$newsales);
        $newsales =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $newcnt = $valuescnt{$username . $date . "postauthsuccess" . $acct_code} - $ac3_sum{$username . $date . "postauthsuccessrecurring"};
        $newcnt = sprintf("%.2f",$newcnt);
        $newcnt =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $netsales = $values{$username . $date . "postauthsuccess" . $acct_code} - $values{$username . $date . "returnsuccess" . $acct_code};
        $netsales = sprintf("%.2f",$netsales);
        $netsales =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $netcnt = $valuescnt{$username . $date . "postauthsuccess" . $acct_code} - $valuescnt{$username . $date . "returnsuccess" . $acct_code};
        $netcnt = sprintf("%.2f",$netcnt);
        $netcnt =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$username . $date . "authsuccess" . $acct_code} = sprintf("%.2f",$values{$username . $date . "authsuccess" . $acct_code});
        $values{$username . $date . "authsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$username . $date . "postauthsuccess" . $acct_code} = sprintf("%.2f",$values{$username . $date . "postauthsuccess" . $acct_code});
        $values{$username . $date . "postauthsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$username . $date . "returnsuccess" . $acct_code} = sprintf("%.2f",$values{$username . $date . "returnsuccess" . $acct_code});
        $values{$username . $date . "returnsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$username . $date . "voidsuccess" . $acct_code} = sprintf("%.2f",$values{$username . $date . "voidsuccess" . $acct_code});
        $values{$username . $date . "voidsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $valuescnt{$username . $date . "returnsuccess" . $acct_code} = sprintf("%2d",$valuescnt{$username . $date . "returnsuccess" . $acct_code});
        $ac3_cnt{$username . $date . "postauthsuccessrecurring"} = sprintf("%2d",$ac3_cnt{$username . $date . "postauthsuccessrecurring"});

        print "<tr>\n";
        print "<th align=left rowspan=$rowspan><font size=-1>$datestr</font></th>\n";
        print "<td align=right><font size=-1>\$$values{$date . \"authsuccess\" . $acct_code}</font></td>\n";
        if ($processor ne "cybercash") {

          print "<td align=right><font size=-1>\$$newsales</font></td>\n"; ## New Sales
          print "<td align=right><font size=-1>\$$ac3_sum{$username . $date . \"postauthsuccessrecurring\"}</font></td>\n"; ## Rec Sales
          print "<td align=right><font size=-1>\$$values{$username . $date . \"returnsuccess\" . $acct_code}</font></td>\n";   ## Returns
          print "<td align=right><font size=-1>\$$netsales</font></td>\n";   ## Net
        }
        print "<td align=right><font size=-1>$valuescnt{$username . $date . \"authsuccess\" . $acct_code}</font></td>\n";
        if ($processor ne "cybercash") {
          print "<td align=right><font size=-1>$newcnt</font></td>\n"; ## New Sales
          print "<td align=right><font size=-1>$ac3_cnt{$username . $date . \"postauthsuccessrecurring\"}</font></td>\n"; ## Rec Sales
          print "<td align=right><font size=-1>$valuescnt{$username . $date . \"returnsuccess\" . $acct_code}</font></td>\n";   ## Returns
          print "<td align=right><font size=-1>$netcnt</font></td>\n";   ## Net
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

        $values{$username . $date . "authsuccess" . $acct_code} = sprintf("%.2f",$values{$username . $date . "authsuccess" . $acct_code});
        $values{$username . $date . "authsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$username . $date . "authsuccess" . $acct_code} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;
        $values{$username . $date . "postauthsuccess" . $acct_code} = sprintf("%.2f",$values{$username . $date . "postauthsuccess" . $acct_code});
        $values{$username . $date . "postauthsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$username . $date . "postauthsuccess" . $acct_code} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;
        $values{$username . $date . "returnsuccess" . $acct_code} = sprintf("%.2f",$values{$username . $date . "returnsuccess" . $acct_code});
        $values{$username . $date . "returnsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$username . $date . "returnsuccess" . $acct_code} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;
        $values{$username . $date . "voidsuccess" . $acct_code} = sprintf("%.2f",$values{$username . $date . "voidsuccess" . $acct_code});
        $values{$username . $date . "voidsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$username . $date . "voidsuccess" . $acct_code} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

        $record = "<tr>";
        $record .= "<th align=left rowspan=$rowspan><font size=-1>$datestr</font></th><th><font size=-1>Net Sales</font></th>";
        $record .= "<td align=right><font size=-1>\$$values{$username . $date . \"authsuccess\" . $acct_code}</font></td>\n";
        if ($processor ne "cybercash") {
          $record .= "<td align=right><font size=-1>\$$values{$username . $date . \"voidsuccess\" . $acct_code}</font></td>\n";
          $record .= "<td align=right><font size=-1>\$$values{$username . $date . \"returnsuccess\" . $acct_code}</font></td>\n";
          $record .= "<td align=right><font size=-1>\$$values{$username . $date . \"postauthsuccess\" . $acct_code}</font></td>\n";
          $record .= "<td align=right><font size=-1>\$$values{$username . $date . \"voidsuccess\" . $acct_code}</font></td>\n";

          $record .= "</tr>\n";
        }
        $record .= "\n";
        print $record;
      }
    }
  }
  $totalsum{"TOTAL$username" . 'authsuccess'} = sprintf("%.2f",$totalsum{"TOTAL$username" . 'authsuccess'});
  $totalsum{"TOTAL$username" . 'authsuccess'} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{"TOTAL$username" . 'authsuccess'} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;
  $totalsum{"TOTAL$username" . 'postauthsuccess'} = sprintf("%.2f",$totalsum{"TOTAL$username" . 'postauthsuccess'});
  $totalsum{"TOTAL$username" . 'postauthsuccess'} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{"TOTAL$username" . 'postauthsuccess'} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;
  $totalsum{"TOTAL$username" . 'returnsuccess'} = sprintf("%.2f",$totalsum{"TOTAL$username" . 'returnsuccess'});
  $totalsum{"TOTAL$username" . 'returnsuccess'} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{"TOTAL$username" . 'returnsuccess'} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;
  $totalsum{"TOTAL$username" . 'voidsuccess'} = sprintf("%.2f",$totalsum{"TOTAL$username" . 'voidsuccess'});
  $totalsum{"TOTAL$username" . 'voidsuccess'} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{"TOTAL$username" . 'voidsuccess'} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

  print "<tr><th align=left rowspan=4><font size=-1>TOTALS:</font></th>\n";
  print "<th><font size=-1>Net Sales</font></th><td align=right><font size=-1>\$$totalsum{\"TOTAL$username\" . 'authsuccess'}</font></td><td></td>";
  if ($processor ne "cybercash") {
    print "<tr><th><font size=-1>Voids</font></th><td align=right><font size=-1>\$$totalsum{\"TOTAL$username\" . 'voidsuccess'}</font> </td><td></td>";
    print "<tr><th><font size=-1>Returns</font></th><td align=right><font size=-1>\$$totalsum{\"TOTAL$username\" . 'returnsuccess'}</font> </td><td></td>";
    print "<tr><th><font size=-1>Post Auths</font></th><td align=right><font size=-1>\$$totalsum{\"TOTAL$username\" . 'postauthsuccess'}</font></td><td></td>";
  }
  print "</table></div>\n";
}


sub report2 {

  $cardtype = $query->param('cardtype');
  $form_txntype = $query->param('txntype');
  $txnstatus = $query->param('txnstatus');
  $startdate = $query->param('startdate');
  $enddate = $query->param('enddate');
  $lowamount = $query->param('lowamount');
  $highamount = $query->param('highamount');
  $orderid = $query->param('orderid');

  $shortcard = substr($cardnumber,0,4) . "**" . substr($cardnumber,-2,2);

  @orderidarray = ($orderid);

  if ($format ne "text"){
    if ($firstflag == 0) {
      print "<table border=1>\n";
      print "<tr>\n";
      print "<th align=left>Name</th>";
      print "<th align=left>OrderID</th>";
      print "<th>Date Auth.<font size=-1>(GMT)<br>MM/DD/YY HH:MM:SS</font></th>";
      print "<th align=left>Amount</th>";
      print "<th align=left>Card Type</th>";
      print "<th>Date Set.<font size=-1>(GMT)<br>MM/DD/YY HH:MM:SS</font></th>";
      print "<th align=left>Set. Status</th>";
      $firstflag = 1;
    }
  }
  else {
    print "Name\tDateAuth\tAmount\tCardType\tDateSet\tFinalStatus\n";
  }


  $starttime = sprintf("%08d000000", $start);
  $endtime = sprintf("%08d000000", $end);

  $i = 0;

#print "UN:$username, start-time:$starttime, end-time:$endtime, txn-status:$txnstatus\n";
#exit;

  %result = &miscutils::sendmserver("$username",'query',
            'accttype',"$accttype",
            'start-time', "$starttime",
            'end-time', "$endtime",
            'acct_code', "$acct_code"
  );

  @values = values %result;
  foreach $var (sort @values) {
    %res2 = ();
    @nameval = split(/&/,$var);
     foreach $temp (@nameval) {
      ($name,$value) = split(/=/,$temp);
      $res2{$name} = $value;
    }

    if ($res2{'time'} ne "") {
      $time = $res2{"time"};

      $timestr = substr($time,4,2) . "/" . substr($time,6,2) . "/" . substr($time,0,4) . " ";
      $timestr = $timestr . substr($time,8,2) . ":" . substr($time,10,2) . ":" . substr($time,12,2);
      $trans_date = substr($time,0,8);

      $orderid = $res2{"order-id"};
      $txntype = $res2{"txn-type"};
      $status = $res2{"txn-status"};

      $time{"$orderid$txntype$status"} = $res2{"time"};
      $trans_date{"$orderid$txntype$status"} = $trans_date;
      $cardnumber{"$orderid$txntype$status"} = $res2{"card-number"};
      my $cardbin = substr($res2{'card-number'},0,4);
      if ($cardbin =~ /^(4)/) {
        $cardtype = "VISA";
      }
      elsif ($cardbin =~ /^(51|52|53|54|55)/) {
        $cardtype = "MSTR";
      }
      elsif ($cardbin =~ /^(37|34)/) {
        $cardtype = "AMEX";
      }
      elsif ($cardbin =~ /^(30|36|38[0-8])/) {
        $cardtype = "DNRS";
      }
      elsif ($cardbin =~ /^(389)/) {
        $cardtype = "CRTB";
      }
      elsif ($cardbin =~ /^(6011)/) {
        $cardtype = "DSCR";
      }
      elsif ($cardbin =~ /^(3528)/) {
        $cardtype = "JCB";
      }
      elsif ($cardbin =~ /^(1800|2131)/) {
        $cardtype = "JAL";
      }
      elsif ($cardbin =~ /^(7)/) {
        $cardtype = "MYAR";
      }

      ($dummy, $amount) = split(/ /,$res2{'amount'});
      if ($txntype =~ /^(auth|postauth|return)$/) {
        $cardname{"$orderid"} = $res2{'card-name'};
        $cardtype{"$orderid"} = $cardtype;
        $acctcode{"$orderid"} = $res2{'acct_code'};
        $acctcode2{"$orderid"} = $res2{'acct_code2'};
        $acctcode2{"$orderid"} = $res2{'acct_code3'};
        $cnt{"$trans_date$txntype$cardtype$status"}++;
        $aamounts{$amount} = 1;
      }
      if (($txntype =~ /^auth/) && ($status eq "success")) { 
        $orderids{"$trans_date$orderid"} = 1;
        $amount{"$trans_date$orderid$txntype$status"} = $amount;
        $authdates{$orderid} = $trans_date;
        my $ikey = $trans_date . "auth";
        $$ikey{$amount}++;
        my $ikey = $trans_date . "auth" . $cardtype;
        $$ikey{$amount}++;
      }
      elsif (($txntype =~ /^(postauth)/) && ($status eq "success")) {
        $postauth_orderids{"$trans_date$orderid"} = 1;
        $dates{$trans_date} = 1;
        $pstatus{$orderid} = $status;
        $setldates{"$orderid$txntype$status"} = $trans_date;
        $amount{"$trans_date$orderid$txntype$status"} = $amount;
        $tsum{"$trans_date$txntype$cardtype$status"} += $amount;
        my $ikey = $trans_date . "postauth";
        $$ikey{$amount}++;
        my $ikey = $trans_date . "postauth" . $cardtype;
        $$ikey{$amount}++;
      }
      elsif (($txntype =~ /^(return)/) && ($status eq "success")) {
        $return_orderids{"$trans_date$orderid"} = 1;
        $amount = $amount * (-1);
        $amount = sprintf("%0.2f",$amount);
        $dates{$trans_date} = 1;
        $rstatus{$orderid} = $status;
        $retndates{"$orderid$txntype$status"} = $trans_date;
        $amount{"$trans_date$orderid$txntype$status"} = $amount;
        $tsum{"$trans_date$txntype$cardtype$status"} += $amount;
        my $ikey = $trans_date . "return";
        $$ikey{$amount}++;
        my $ikey = $trans_date . "return" . $cardtype;
        $$ikey{$amount}++;
      }
    }
  }
  
  if ($format ne "text"){
    foreach $key (sort keys %postauth_orderids) {
      $orderid = substr($key,8);
      $trans_date = substr($key,0,8);
      print "<tr>";
      print "<td>$cardname{$orderid}</td>\n";
      print "<td>$orderid</td>\n";
      print "<td>$authdates{$orderid}</td>\n";
      $ikey = $trans_date . $orderid . "postauthsuccess";
      printf ("<td>%0.2f</td>\n",$amount{$ikey});
      print "<td>$cardtype{$orderid}</td>\n";
      $ikey = $orderid . "postauth" . $pstatus{$orderid};
      print "<td>$setldates{$ikey}</td>\n";
      print "<td>$pstatus{$orderid}</td>\n";
      print "\n";
    }
    foreach $key (sort keys %return_orderids) {
      $orderid = substr($key,8);
      $trans_date = substr($key,0,8);
      print "<tr>";
      print "<td>$cardname{$orderid}</td>\n";
      print "<td>$orderid</td>\n";
      print "<td>$trans_date</td>\n";
      $ikey = $trans_date . $orderid . "returnsuccess";
      printf ("<td><font color=\"red\">%0.2f</font></td>\n",$amount{$ikey});
      print "<td>$cardtype{$orderid}</td>\n";
      $ikey = $orderid . "return" . $rstatus{$orderid};
      print "<td>$retndates{$ikey}</td>\n";
      print "<td>$rstatus{$orderid}</td>\n";
      print "\n";
    }
    print "</table>\n";
  }
  else {
    $amount =~ s/[^0-9\.]//g;
    print "$txntype\t$cardname\t$status\t$orderid\t$timestr\t$cardnumber\t$exp\t";
  }
  if ($format ne "text"){
    print "<table border=1>\n";
    print "<tr><th>Date</th><th>Card Type</th><th>Settled Amount</th><th>Settled Cnt</th><th>Returned Amount</th><th>Returned Cnt</th></tr>\n";
    foreach $trans_date (sort keys %dates) {
      print "<tr>";
      print "<th rowspan=4>$trans_date</th>\n";
      print "<td>VISA</td>\n";
      $ikey = $trans_date . "postauthVISAsuccess";
      printf ("<td align=\"right\">%0.2f</td>\n",$tsum{$ikey});
      print "<td align=\"center\">$cnt{$ikey}</td>\n";
      $ikey = $trans_date . "returnVISAsuccess";
      printf ("<td align=\"right\"><font color=\"red\">%0.2f</font></td>\n",$tsum{$ikey});
      print "<td align=\"center\">$cnt{$ikey}</td>\n";
      print "</tr>\n";

      print "<tr><td>MSTR</td>\n";
      $ikey = $trans_date . "postauthMSTRsuccess";
      printf ("<td align=\"right\">%0.2f</td>\n",$tsum{$ikey});
      print "<td align=\"center\">$cnt{$ikey}</td>\n";
      $ikey = $trans_date . "returnMSTRsuccess";
      printf ("<td align=\"right\"><font color=\"red\">%0.2f</font></td>\n",$tsum{$ikey});
      print "<td align=\"center\">$cnt{$ikey}</td>\n";
      print "</tr>\n";

      print "<tr><td>AMEX</td>\n";
      $ikey = $trans_date . "postauthAMEXsuccess";
      printf ("<td align=\"right\">%0.2f</td>\n",$tsum{$ikey});
      print "<td align=\"center\">$cnt{$ikey}</td>\n";
      $ikey = $trans_date . "returnAMEXsuccess";
      printf ("<td align=\"right\"><font color=\"red\">%0.2f</font></td>\n",$tsum{$ikey});
      print "<td align=\"center\">$cnt{$ikey}</td>\n";
      print "</tr>\n";

      print "<tr><td>DSCR</td>\n";
      $ikey = $trans_date . "postauthDSCRsuccess";
      printf ("<td align=\"right\">%0.2f</td>\n",$tsum{$ikey});
      print "<td align=\"center\">$cnt{$ikey}</td>\n";
      $ikey = $trans_date . "returnDSCRsuccess";
      printf ("<td align=\"right\"><font color=\"red\">%0.2f</font></td>\n",$tsum{$ikey});
      print "<td align=\"center\">$cnt{$ikey}</td>\n";
      print "</tr>\n";
    }
  }
  else {
    $amount =~ s/[^0-9\.]//g;
    print "$txntype\t$cardname\t$status\t$orderid\t$timestr\t$cardnumber\t$exp\t";
  }
  if ($format ne "text"){
    foreach $amount (sort keys %aamounts) {
      @amounts = (@amounts,$amount);
    }
    print "<table border=1>\n";
    print "<tr><th rowspan=3>Date</th><th rowspan=3>Type</th><th colspan=\"@amounts\">Transaction Counts</th></tr>\n";
    print "<tr>";
    foreach my $amount (@amounts) {
      print "<th rowspan=1 colspan=5>\$$amount</th>";
    }
    print "</tr>\n";
    print "<tr>";
    foreach my $var (@amounts) {
      print "<th>VS</th><th>MC</th><th>AX</th><th>DS</th><th>TO</th>\n";
    }
    print "</tr>\n";
    foreach $trans_date (sort keys %dates) {
      print "<tr>";
      print "<th rowspan=3>$trans_date</th>\n";
      print "<th>Auth</th>";
      my $ikey = $trans_date . "auth";
      my $vkey = $trans_date . "authVISA";
      my $mkey = $trans_date . "authMSTR";
      my $akey = $trans_date . "authAMEX";
      my $dkey = $trans_date . "authDSCR";
      foreach my $amount (@amounts) {
        print "<td align=\"center\">$$vkey{$amount}</td><td align=\"center\">$$mkey{$amount}</td><td align=\"center\">$$akey{$amount}</td><td align=\"center\">$$dkey{$amount}</td><td align=\"center\">$$ikey{$amount}</td>\n";
        $authtotalcnt{$amount} += $$ikey{$amount};
        my $vtkey = $amount . "VISA";
        my $mtkey = $amount . "MSTR";
        my $atkey = $amount . "AMEX";
        my $dtkey = $amount . "DSCR";
        $authtotalcnt{$vtkey} += $$vkey{$amount};
        $authtotalcnt{$mtkey} += $$mkey{$amount};
        $authtotalcnt{$atkey} += $$akey{$amount};
        $authtotalcnt{$dtkey} += $$dkey{$amount};
      }
      print "</tr>\n";

      print "<tr><th>Settled</th>\n";
      my $ikey = $trans_date . "postauth";
      my $vkey = $trans_date . "postauthVISA";
      my $mkey = $trans_date . "postauthMSTR";
      my $akey = $trans_date . "postauthAMEX";
      my $dkey = $trans_date . "postauthDSCR";

      foreach my $amount (@amounts) {
        print "<td align=\"center\">$$vkey{$amount}</td><td align=\"center\">$$mkey{$amount}</td><td align=\"center\">$$akey{$amount}</td><td align=\"center\">$$dkey{$amount}</td><td align=\"center\">$$ikey{$amount}</td>\n";
        $postauthtotalcnt{$amount} += $$ikey{$amount};
        my $vtkey = $amount . "VISA";
        my $mtkey = $amount . "MSTR";
        my $atkey = $amount . "AMEX";
        my $dtkey = $amount . "DSCR";
        $postauthtotalcnt{$vtkey} += $$vkey{$amount};
        $postauthtotalcnt{$mtkey} += $$mkey{$amount};
        $postauthtotalcnt{$atkey} += $$akey{$amount};
        $postauthtotalcnt{$dtkey} += $$dkey{$amount};

      }
      print "</tr>\n";
      print "<tr><th>Returns</th>\n";
      my $ikey = $trans_date . "return";
      my $vkey = $trans_date . "returnVISA";
      my $mkey = $trans_date . "returnMSTR";
      my $akey = $trans_date . "returnAMEX";
      my $dkey = $trans_date . "returnDSCR";

      foreach my $amount (@amounts) {
        print "<td align=\"center\">$$vkey{$amount}</td><td align=\"center\">$$mkey{$amount}</td><td align=\"center\">$$akey{$amount}</td><td align=\"center\">$$dkey{$amount}</td><td align=\"center\">$$ikey{$amount}</td>\n";
        $returntotalcnt{$amount} += $$ikey{$amount};
        my $vtkey = $amount . "VISA";
        my $mtkey = $amount . "MSTR";
        my $atkey = $amount . "AMEX";
        my $dtkey = $amount . "DSCR";
        $returntotalcnt{$vtkey} += $$vkey{$amount};
        $returntotalcnt{$mtkey} += $$mkey{$amount};
        $returntotalcnt{$atkey} += $$akey{$amount};
        $returntotalcnt{$dtkey} += $$dkey{$amount};
      }
      print "</tr>\n";
    }
    print "<tr>";
    print "<th rowspan=3>Totals</th>\n";
    print "<th>Auth</th>";
      my $ikey = $trans_date . "return";
      my $vkey = $trans_date . "returnVISA";
      my $mkey = $trans_date . "returnMSTR";
      my $akey = $trans_date . "returnAMEX";
      my $dkey = $trans_date . "returnDSCR";

    foreach my $amount (@amounts) {
      my $vkey = $amount . "VISA";
      my $mkey = $amount . "MSTR";
      my $akey = $amount . "AMEX";
      my $dkey = $amount . "DSCR";
      print "<td align=\"center\">$authtotalcnt{$vkey}</td><td align=\"center\">$authtotalcnt{$mkey}</td><td align=\"center\">$authtotalcnt{$akey}</td><td align=\"center\">$authtotalcnt{$dkey}</td><td align=\"center\">$authtotalcnt{$amount}</td>\n";
    }
    print "</tr>\n";

    print "<tr><th>Postauth</th>\n";
    my $ikey = $trans_date . "postauthtotal";
    foreach my $amount (@amounts) {
      my $vkey = $amount . "VISA";
      my $mkey = $amount . "MSTR";
      my $akey = $amount . "AMEX";
      my $dkey = $amount . "DSCR";
      print "<td align=\"center\">$postauthtotalcnt{$vkey}</td><td align=\"center\">$postauthtotalcnt{$mkey}</td><td align=\"center\">$postauthtotalcnt{$akey}</td><td align=\"center\">$postauthtotalcnt{$dkey}</td><td align=\"center\">$postauthtotalcnt{$amount}</td>\n";
    }
    print "</tr>\n";
    print "<tr><th>Returns</th>\n";
    my $ikey = $trans_date . "returntotal";
    foreach my $amount (@amounts) {
      my $vkey = $amount . "VISA";
      my $mkey = $amount . "MSTR";
      my $akey = $amount . "AMEX";
      my $dkey = $amount . "DSCR";
      print "<td align=\"center\">$returntotalcnt{$vkey}</td><td align=\"center\">$returntotalcnt{$mkey}</td><td align=\"center\">$returntotalcnt{$akey}</td><td align=\"center\">$returntotalcnt{$dkey}</td><td align=\"center\">$authtotalcnt{$amount}</td>\n";
    }
    print "</tr>\n";

  }
  else {
    $amount =~ s/[^0-9\.]//g;
    print "$txntype\t$cardname\t$status\t$orderid\t$timestr\t$cardnumber\t$exp\t";
  }

}


sub query1 {

  $dbh = &miscutils::dbhconnect("pnpdata");

  $total = 0;

  $start1 = $start;
  $end1 = $end;

  $max = 200;
  $maxmonth = 200;
  $trans_max = 200;
  $trans_maxmonth = 200;

  $tt = time();

  if ($report_time eq "batchtime") {
    $qstr = "select batch_time, ";
  }
  else {
    $qstr = "select trans_date, ";
  }

  if ($subacct ne "") {
    $qstr .= "operation, finalstatus, substr(card_number,0,3), count(username), sum(substr(amount,4)) 
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
    $qstr .= "group by trans_date, operation, finalstatus, substr(card_number,0,2) ";

  }
  elsif ($subacct eq "ALL") {
    $qstr = "operation, finalstatus, subacct, username, count(username), sum(substr(amount,4)) 
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
    $qstr .= "operation, finalstatus, substr(card_number,0,3), count(username), sum(substr(amount,4)) 
       from trans_log where trans_date>='$start' and trans_date<'$end' ";
    $qstr .= "and username='$username' ";
 
    $qstr .= "and operation<>'query' and duplicate IS NULL ";
    $qstr .= "group by trans_date, operation, finalstatus, substr(card_number,0,3)";

  }

  $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
  $sth->execute or die "Can't execute: $DBI::errstr";
  if ($subacct eq "ALL") {
    $sth->bind_columns(undef,\($trans_date, $operation, $finalstatus, $acct_code, $username, $count, $sum));
  }
  else {
    $sth->bind_columns(undef,\($trans_date, $operation, $finalstatus, $cardbin, $count, $sum));
  }

  while ($sth->fetch) {
    if ($cardbin =~ /^(4)/) {
      $cardtype = "VISA";
    }
    elsif ($cardbin =~ /^(51|52|53|54|55)/) {
      $cardtype = "MSTR";
    }
    elsif ($cardbin =~ /^(37|34)/) {
      $cardtype = "AMEX";
    }
    elsif ($cardbin =~ /^(30|36|38[0-8])/) {
      $cardtype = "DNRS";
    }
    elsif ($cardbin =~ /^(389)/) {
      $cardtype = "CRTB";
    }
    elsif ($cardbin =~ /^(6011)/) {
      $cardtype = "DSCR";
    }
    elsif ($cardbin =~ /^(3528)/) {
      $cardtype = "JCB";
    }
    elsif ($cardbin =~ /^(1800|2131)/) {
      $cardtype = "JAL";
    }
    elsif ($cardbin =~ /^(7)/) {
      $cardtype = "MYAR";
    }

    $acct_code = $cardtype;

    $trans_date = substr($trans_date,0,10);
    $time = &miscutils::strtotime($trans_date);
    $adjust = time() - $time - ($todadjust * 3600);
    my ($dummy,$trans_date,$start_time) = &miscutils::gendatetime(-$adjust);

    if ($function eq "monthly") {
      $trans_date = substr($trans_date,0,6);
    }

    $dates{$trans_date} = 1;
    $operations{$operation} = 1;
    $finalstatus{$finalstatus} = 1;

    if ($cardtype ne "") {
      $acct_code{$acct_code} = $acct_code;
    } 

    $count{"$trans_date$operation$finalstatus"} += $count;
    $ac_count{"$trans_date$operation$finalstatus$acct_code"} += $count;

    $ac_sum{"$trans_date$operation$finalstatus$acct_code"} += $sum;
    $sum{"$trans_date$operation$finalstatus"} += $sum;

    $ac_totalcnt{"TOTAL$operation$finalstatus$acct_code"} += $count;
    $ac_totalsum{"TOTAL$operation$finalstatus$acct_code"} += $sum;

    $totalcnt{"TOTAL$operation$finalstatus"} += $count;
    $totalsum{"TOTAL$operation$finalstatus"} += $sum;

  }
  $sth->finish;
  $dbh->disconnect;

}


sub report {
  $function = $query->param('function');
  #$acct_code = $query->param('acct_code');
  $startmonth = $query->param('startmonth');
  $startyear = $query->param('startyear');
  $startday = $query->param('startday');
  $endmonth = $query->param('endmonth');
  $endyear = $query->param('endyear');
  $endday = $query->param('endday');

  if (($startmonth eq "") && ($startday eq "") && ($startyear eq "")) {
    $startday = 1;
    $startmonth = $smonth + 1;
    $startyear = $yyear;
    $startmonth = $month_array{$startmonth};
  }

  if (($endmonth eq "") && ($endday eq "") && ($endyear eq "")) {
    $endday = 1;
    $endmonth = $smonth + 2;
    $endyear = $yyear;
    if ($endmonth > 12) {
      $endmonth = 1;
      $endyear = $yyear + 1;
    }
    $endmonth = $month_array{$endmonth};
  }

  $start = sprintf("%04d%02d%02d", $startyear,$month_array2{$startmonth}, $startday);
  $end = sprintf("%04d%02d%02d", $endyear,$month_array2{$endmonth}, $endday);
  $reportstart = sprintf("%02d/%02d/%02d", $month_array2{$startmonth}, $startday, $startyear);
  $reportend = sprintf("%02d/%02d/%02d", $month_array2{$endmonth}, $endday, $endyear);
  $total = 0;

  $qstr = "select username,name,company,commission from $merchantdb";
  if (($acct_code ne "") && ($acct_code ne "All")) {
    $qstr .= " where username=\'$acct_code\'";
  }
  else {
    $qstr .= " order by username";
  }

#print "SEARCH $qstr:  UN:$username <br>\n";

  $sth_customer = $dbh_aff->prepare(qq{$qstr}) or die "Cant do: $DBI::errstr";

  $sth_customer->execute or die "Cant execute: $DBI::errstr";
  $sth_customer->bind_columns(undef,\($username,$name,$company,$commission));
#print "POST EXECUTE <br>\n";
  while($sth_customer->fetch) {
#print "TST: $username <br>\n";
    $$username{'name'} = $name;
    $$username{'company'} = $company;
    ($$username{'commission'},$$username{'commission_type'}) = split(/\|/,$commission,2);
    $affiliates{$username} = 1;
    #print "IN FETCH $username,$name,$company,$commission <br>\n";
  }
#print "PRE FINISH <br>\n";
  $sth_customer->finish;
#print "POST Fetch <br>\n";
#  $dbh_aff->disconnect;

  print "<html>\n";
  print "<head>\n";
  print "<title>Affiliate Reports</title>\n";
#  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"/payment/affiliate/stylesheet.css\">\n";
  print "</head>\n";
  print "<body bgcolor=\"#ffffff\" link=\"#000000\">\n";
#  print "<div align=\"left\">\n";
  foreach $username (sort keys %affiliates) {
    $acct_code = $username;
    $company = $$username{'company'};
    $name = $$username{'name'};
    $commission = $$username{'commission'};
    $commission_type = $$username{'commission_type'};
    my (%date,%orderid,%cardname,$amount,$total);
    print "<h3>Sales Report for ";
    if ($company ne "") { 
      print "$company ";
    }
    print "Affiliate Account: $acct_code</h3>\n";
    print "Report Period: $reportstart to $reportend<p>\n"; 
    print "<font style=\"bold\">NOTE: Amounts in <font color=\"#ff0000\">RED</font> are voided transactions, returned transactions or transactions which failed the <b>A</b>ddress <b>V</b>erification <b>S</b>ystem (<b>AVS</b>) test and have been deducted from the sales totals.</font><p>\n";
    print "<table border=\"1\">\n";
    print "<tr><th align=\"left\">Date</th><th align=\"left\">Time</th><th align=\"left\">Order ID</th><th align=\"left\">Amount</th>\n"; 

  $max = 200;
  $maxmonth = 200;

  $dbh = &miscutils::dbhconnect("pnpdata") or die "failed connect<br>\n";

  $searchstr = "select orderid,card_name,trans_date,trans_time,amount,shipping,tax";
  $searchstr = $searchstr . " from ordersummary";
  $searchstr = $searchstr . " where trans_date>\'$start\' and trans_date<=\'$end\'";
  $searchstr = $searchstr . " and username=\'$merchant\'";
  if ($acct_code eq "") {
    $searchstr = $searchstr . " and acct_code IS NULL";
  }
  else {
    $searchstr = $searchstr . " and acct_code=\'$acct_code\'";
  }
  $searchstr = $searchstr . " and result=\'success\'";
  $searchstr = $searchstr . " order by trans_date,trans_time";

  $sth = $dbh->prepare($searchstr) or die "Can't do: $DBI::errstr";
  $sth->execute or die "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($orderid,$card_name,$trans_date,$trans_time,$amount,$shipping,$tax));

#print "SEARCH: $searchstr <br>\n";

  while($sth->fetch) {
    $amount =~ s/[^0-9\.]//g;
    $amount = sprintf("%.2f",$amount);

    if ($trans_date ne $trans_dateold) {
      $date = sprintf("%02d/%02d/%04d", substr($trans_date,4,2), substr($trans_date,6,2), substr($trans_date,0,4));
    }
    else {
      $date = "";
    }
    %entry_hash = ();
    $entry_hash{'orderid'} = $orderid;
    $entry_hash{'card-name'} = $card_name;
    $entry_hash{'trans_date'} = $trans_date;
    $entry_hash{'trans_time'} = $trans_time;
    $entry_hash{'amount'} = $amount;
    $entry_hash{'acct_code'} = $acct_code;
    $entry_hash{'operation'} = "auth";
    
    $transaction_array[++$#transaction_array] = {%entry_hash};
  }
  $sth->finish;

  $total_transactions = $#transaction_array + 1;

  $searchstr = "select orderid,card_name,trans_date,trans_time,amount,operation";
  $searchstr = $searchstr . " from trans_log";
  $searchstr = $searchstr . " where trans_date between \'$start\' and \'$end\'";
  $searchstr = $searchstr . " and username=\'$merchant\'";
  $searchstr = $searchstr . " and operation IN (\'void\',\'return\')";
  if ($acct_code eq "") {
    $searchstr = $searchstr . " and acct_code IS NULL";
  }
  else {
    $searchstr = $searchstr . " and acct_code=\'$acct_code\'";
  }
  $searchstr = $searchstr . " and result=\'success\'";
  $searchstr = $searchstr . " order by trans_date,trans_time";

  $sth = $dbh->prepare(qq{$searchstr}) or die "failed prepare<br>\n";
  $sth->execute or die "failed execute<br>\n";
  $sth->bind_columns(undef,\($orderid,$card_name,$trans_date,$trans_time,$amount,$operation));

#  print "Test<br>\n";
  while ($sth->fetch) {
#print "$orderid,$card_name,$trans_date,$trans_time,$amount,$operation<br>\n";
    $amount =~ s/[^0-9\.]//g;
    $amount = sprintf("%.2f",$amount);
    %entry_hash = ();
    $entry_hash{'orderid'} = $orderid;
    $entry_hash{'card-name'} = $card_name;
    $entry_hash{'trans_date'} = $trans_date;
    $entry_hash{'trans_time'} = $trans_time;
    $entry_hash{'amount'} = $amount;
    $entry_hash{'operation'} = $operation;
    $transaction_array[++$#transaction_array] = {%entry_hash};
  }

  $sth->finish;
  $dbh->disconnect;
  
    for ($i=0;$i<=$#transaction_array;$i++) {
      if ($transaction_array[$i]{'operation'} eq "auth") {
        $amount_hash{$transaction_array[$i]{'orderid'}} += $transaction_array[$i]{'amount'};
      }
      if (($transaction_array[$i]{'operation'} eq "return") || ($transaction_array[$i]{'operation'} eq "void")) {
        $amount_hash{$transaction_array[$i]{'orderid'}} -= $transaction_array[$i]{'amount'};
      }
    }

    for ($i=0;$i<=$#transaction_array;$i++) {
      if ((($transaction_array[$i]{'shipping'} ne "") || ($transaction_array[$i]{'tax'} ne "")) && ($amount_hash{$transaction_array[$i]{'orderid'}} != 0)) {
        $amount_hash{$transaction_array[$i]{'orderid'}} -= $transaction_array[$i]{'shipping'};
        $amount_hash{$transaction_array[$i]{'orderid'}} -= $transaction_array[$i]{'tax'};
      }
      $total += $amount_hash{$transaction_array[$i]{'orderid'}};
    }
    for ($i=0;$i<=$#transaction_array;$i++) {
      $date = $transaction_array[$i]{'trans_date'};
      $date = sprintf("%02d/%02d/%04d", substr($date,4,2), substr($date,6,2), substr($date,0,4));
      $time = substr($transaction_array[$i]{'trans_time'},8,2) . ":" . substr($transaction_array[$i]{'trans_time'},10,2) . ":" . substr($transaction_array[$i]{'trans_time'},12,2);
      $oid = $transaction_array[$i]{'orderid'};
      $operation = $transaction_array[$i]{'operation'};
      $amount = $transaction_array[$i]{'amount'};

  #print "OID:$oid,DATe:$date,TIME:$time,AMT:$amount,OP:$operation<br>\n";
 
      if ($old_date ne $date) {
        $header_date = $date;
      }
      else {
        $header_date = "";
      }

      #&table_row();
 
      if ($operation ne "auth") {
        print "<tr><th align=\"left\">$header_date</th><td>$time</td><td>$oid</td><td align=\"right\"><font color=\"#ff0000\">$amount</font></td></tr>\n";
      }
      else {
        $total = $total + $$operation{$oid};
        print "<tr><th align=\"left\">$header_date</th><td>$time</td><td>$oid</td><td align=\"right\">$amount</td></tr>\n";
      }
      $old_date = $date;
    }
    if (($commission_type eq "p") || ($commission_type eq "")) {
      $amt_due = $total * $commission;
    }
    elsif ($commission_type eq "f") {
      $amt_due = $total_transactions * $commission;
    }
    printf("<tr><th align=\"left\">TOTAL:</th><td colspan=\"2\">&nbsp;</td><td align=\"right\"><b>\$%.2f</b></td>\n", $total);
    print "<tr><th align=\"left\">TRANSACTIONS:</th><td colspan=\"2\">&nbsp;</td><td align=\"right\"><b>$total_transactions</b></td>\n";
    printf("<tr><th align=\"left\">AMT DUE:</th><td colspan=\"2\">&nbsp;</td><td align=\"right\"><b>\$%.2f</b></td>\n", $amt_due);
    print "</table><p><p>\n";
    $total_transactions = 0;
    $total = 0;
    $amt_due = 0;
    @transaction_array = ();
    %amount_hash = ();
    }
#  } 
#  elsif ($acct_code eq "All") {
#
#  }
  print "</div>\n";
  print "</body>\n";
  print "</html>\n";
}

sub table_header_row {
  print "<h3>Sales Report for ";
  if ($company ne "") {
    print "$company ";
  }
  print "Affiliate Account: $acct_code</h3>\n";
  print "Report Period: $reportstart to $reportend<p>\n";
  print "<font style=\"bold\">NOTE: Amounts in <font color=\"#ff0000\">RED</font> are voided transactions, returned transactions or transactions which failed the <b>A</b>ddress <b>V</b>erification <b>S</b>ystem (<b>AVS</b>) test and have been deducted from the sales totals.</font><p>\n";
  print "<table border=\"1\">\n";
  print "<tr><th align=\"left\">Date</th><th align=\"left\">Time</th><th align=\"left\">Order ID</th><th align=\"left\">Amount</th>\n";
}

sub table_row {
  if ($operation ne "auth") {
    print "<tr><th align=\"left\">$header_date</th><td>$time</td><td>$oid</td><td align=\"right\"><font color=\"#ff0000\">$amount</font></td></tr>\n";
  }
  else {
    $total = $total + $$operation{$oid};
    print "<tr><th align=\"left\">$header_date</th><td>$time</td><td>$oid</td><td align=\"right\">$amount &nbsp;</td></tr>\n";
  }
}

sub admin_report {
  $function = $query->param('function');
  #$acct_code = $query->param('acct_code');
  $startmonth = $query->param('startmonth');
  $startyear = $query->param('startyear');
  $startday = $query->param('startday');
  $endmonth = $query->param('endmonth');
  $endyear = $query->param('endyear');
  $endday = $query->param('endday');

  if (($startmonth eq "") && ($startday eq "") && ($startyear eq "")) {
    $startday = 1;
    $startmonth = $smonth + 1;
    $startyear = $yyear;
    $startmonth = $month_array{$startmonth};
  }

  if (($endmonth eq "") && ($endday eq "") && ($endyear eq "")) {
    $endday = 1;
    $endmonth = $smonth + 2;
    $endyear = $yyear;
    if ($endmonth > 12) {
      $endmonth = 1;
      $endyear = $yyear + 1;
    }
    $endmonth = $month_array{$endmonth};
  }

  $start = sprintf("%04d%02d%02d", $startyear,$month_array2{$startmonth}, $startday);
  $end = sprintf("%04d%02d%02d", $endyear,$month_array2{$endmonth}, $endday);
  $reportstart = sprintf("%02d/%02d/%02d", $month_array2{$startmonth}, $startday, $startyear);
  $reportend = sprintf("%02d/%02d/%02d", $month_array2{$endmonth}, $endday, $endyear);
  $total = 0;

  $qstr = "select username,name,company,commission from $merchantdb";
  if (($acct_code ne "") && ($acct_code ne "All")) {
    $qstr .= " where username=\'$acct_code\'";
  }
  else {
    $qstr .= " order by username";
  }

  $sth_customer = $dbh_aff->prepare(qq{$qstr}) or die "Cant do: $DBI::errstr";

  $sth_customer->execute or die "Cant execute: $DBI::errstr";
  $sth_customer->bind_columns(undef,\($username,$name,$company,$commission));

  while($sth_customer->fetch) {
    $$username{'name'} = $name;
    $$username{'company'} = $company;
    ($$username{'commission'},$$username{'commission_type'}) = split(/\|/,$commission,2);
    $affiliates{$username} = 1;
  }

  $sth_customer->finish;

  print "<html>\n";
  print "<head>\n";
  print "<title>Affiliate Reports</title>\n";
  print "</head>\n";
  print "<body bgcolor=\"#ffffff\" link=\"#000000\">\n";
  print "Report Period: $reportstart to $reportend<p>\n";
  print "<table>\n";
  foreach $username (sort keys %affiliates) {
    $acct_code = $username;
    $company = $$username{'company'};
    $name = $$username{'name'};
    $commission = $$username{'commission'};
    $commission_type = $$username{'commission_type'};
    my (%date,%orderid,%cardname,$amount,$total);

    $max = 200;
    $maxmonth = 200;

    $dbh = &miscutils::dbhconnect("pnpdata") or die "failed connect<br>\n";

    $searchstr = "select orderid,card_name,trans_date,trans_time,amount,shipping,tax";
    $searchstr = $searchstr . " from ordersummary";
    $searchstr = $searchstr . " where trans_date>\'$start\' and trans_date<=\'$end\'";
    $searchstr = $searchstr . " and username=\'$merchant\'";
    if ($acct_code eq "") {
      $searchstr = $searchstr . " and acct_code IS NULL";
    }
    else {
      $searchstr = $searchstr . " and acct_code=\'$acct_code\'";
    }
    $searchstr = $searchstr . " and result=\'success\'";
    $searchstr = $searchstr . " order by trans_date,trans_time";

    $sth = $dbh->prepare($searchstr) or die "Can't do: $DBI::errstr";
    $sth->execute or die "Can't execute: $DBI::errstr";
    $sth->bind_columns(undef,\($orderid,$card_name,$trans_date,$trans_time,$amount,$shipping,$tax));

    while($sth->fetch) {
      $amount =~ s/[^0-9\.]//g;
      $amount = sprintf("%.2f",$amount);
      if ($trans_date ne $trans_dateold) {
        $date = sprintf("%02d/%02d/%04d", substr($trans_date,4,2), substr($trans_date,6,2), substr($trans_date,0,4));
      }
      else {
        $date = "";
      }
      %entry_hash = ();
      $entry_hash{'orderid'} = $orderid;
      $entry_hash{'card-name'} = $card_name;
      $entry_hash{'trans_date'} = $trans_date;
      $entry_hash{'trans_time'} = $trans_time;
      $entry_hash{'amount'} = $amount;
      $entry_hash{'acct_code'} = $acct_code;
      $entry_hash{'operation'} = "auth";

      $transaction_array[++$#transaction_array] = {%entry_hash};
    }
    $sth->finish;

    $total_transactions = $#transaction_array + 1;

    $searchstr = "select orderid,card_name,trans_date,trans_time,amount,operation";
    $searchstr = $searchstr . " from trans_log";
    $searchstr = $searchstr . " where trans_date between \'$start\' and \'$end\'";
    $searchstr = $searchstr . " and username=\'$merchant\'";
    $searchstr = $searchstr . " and operation IN (\'void\',\'return\')";
    if ($acct_code eq "") {
      $searchstr = $searchstr . " and acct_code IS NULL";
    }
    else {
      $searchstr = $searchstr . " and acct_code=\'$acct_code\'";
    }
    $searchstr = $searchstr . " and result=\'success\'";
    $searchstr = $searchstr . " order by trans_date,trans_time";

    $sth = $dbh->prepare(qq{$searchstr}) or die "failed prepare<br>\n";
    $sth->execute or die "failed execute<br>\n";
    $sth->bind_columns(undef,\($orderid,$card_name,$trans_date,$trans_time,$amount,$operation));

    while ($sth->fetch) {
      $amount =~ s/[^0-9\.]//g;
      $amount = sprintf("%.2f",$amount);
      %entry_hash = ();
      $entry_hash{'orderid'} = $orderid;
      $entry_hash{'card-name'} = $card_name;
      $entry_hash{'trans_date'} = $trans_date;
      $entry_hash{'trans_time'} = $trans_time;
      $entry_hash{'amount'} = $amount;
      $entry_hash{'operation'} = $operation;
      $transaction_array[++$#transaction_array] = {%entry_hash};
    }

    $sth->finish;
    $dbh->disconnect;

    for ($i=0;$i<=$#transaction_array;$i++) {
      if ($transaction_array[$i]{'operation'} eq "auth") {
        $amount_hash{$transaction_array[$i]{'orderid'}} += $transaction_array[$i]{'amount'};
      }
      if (($transaction_array[$i]{'operation'} eq "return") || ($transaction_array[$i]{'operation'} eq "void")) {
        $amount_hash{$transaction_array[$i]{'orderid'}} -= $transaction_array[$i]{'amount'};
      }
    }

    for ($i=0;$i<=$#transaction_array;$i++) {
      if ((($transaction_array[$i]{'shipping'} ne "") || ($transaction_array[$i]{'tax'} ne "")) && ($amount_hash{$transaction_array[$i]{'orderid'}} != 0)) {
        $amount_hash{$transaction_array[$i]{'orderid'}} -= $transaction_array[$i]{'shipping'};
        $amount_hash{$transaction_array[$i]{'orderid'}} -= $transaction_array[$i]{'tax'};
      }
      $total += $amount_hash{$transaction_array[$i]{'orderid'}};
    }
    for ($i=0;$i<=$#transaction_array;$i++) {
      $date = $transaction_array[$i]{'trans_date'};
      $date = sprintf("%02d/%02d/%04d", substr($date,4,2), substr($date,6,2), substr($date,0,4));
      $time = substr($transaction_array[$i]{'trans_time'},8,6);
      $oid = $transaction_array[$i]{'orderid'};
      $operation = $transaction_array[$i]{'operation'};
      $amount = $transaction_array[$i]{'amount'};

      if ($old_date ne $date) {
        $header_date = $date;
      }
      else {
        $header_date = "";
      }
      $old_date = $date;
    }
    if (($commission_type eq "p") || ($commission_type eq "")) {
      $amt_due = $total * $commission;
    }
    elsif ($commission_type eq "f") {
      $amt_due = $total_transactions * $commission;
    }

    print "<tr><th>Account:</th><td>$acct_code</td><th>Company:</th></td>$company</td></tr>";
    printf("<tr><th align=\"left\">TOTAL:</th><td colspan=\"2\">&nbsp;</td><td align=\"right\"><b>\$%.2f</b></td>\n", $total);
    print "<tr><th align=\"left\">TRANSACTIONS:</th><td colspan=\"2\">&nbsp;</td><td align=\"right\"><b>$total_transactions</b></td>\n";
    printf("<tr><th align=\"left\">AMT DUE:</th><td colspan=\"2\">&nbsp;</td><td align=\"right\"><b>\$%.2f</b></td>\n", $amt_due);
    $total_transactions = 0;
    $total = 0;
    $amt_due = 0;
    @transaction_array = ();
    %amount_hash = ();
  }
  print "</table><p><p>\n";
  print "</div>\n";
  print "</body>\n";
  print "</html>\n";
}


sub summarygraph {
  $function = $query->param('function');
  $graphtype = $query->param('graphtype');
  $acct_code = $query->param('acct_code');
  $startmonth = $query->param('startmonth');
  $startyear = $query->param('startyear');
  $startday = $query->param('startday');
  $endmonth = $query->param('endmonth');
  $endyear = $query->param('endyear');
  $endday = $query->param('endday');

  $start = sprintf("%04d%02d%02d", $startyear,$month_array2{$startmonth}, $startday);
  $end = sprintf("%04d%02d%02d", $endyear,$month_array2{$endmonth}, $endday);


  $total = 0;

  print "<html>\n";
  print "<head>\n";
  print "<title>Graphs</title>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"/payment/affiliate/stylesheet.css\">\n";
  #print "<style text=\"text/css\">\n";
  #print "<\!--\n";
  #print "H3 \{font-family: Arial, Helvetica, sans-serif; font-size: 10pt\}\n";
  #print "TH, TD \{font-family: Arial, Helvetica, sans-serif; font-size: 8pt\}\n";
  #print "-->\n";
  #print "</style>\n";

  print "</head>\n";
  print "<body bgcolor=\"#ffffff\" link=\"#000000\">\n";
  print "<div align=\"center\">\n";
  print "<h3>$startmonth $startday, $startyear - $endmonth $endday, $endyear</h3>\n";
  print "</div>\n";

  $max = 200;
  $maxmonth = 200;


  $dbh = &miscutils::dbhconnect("pnpdata");

  $searchstr = "select orderid,card_name,trans_date,trans_time,amount,operation";
  $searchstr = $searchstr . " from trans_log";
  $searchstr = $searchstr . " where trans_date>='$start' and trans_date<='$end'";
  $searchstr = $searchstr . " and username='$merchant'";
  if ($acct_code eq "") {
    $searchstr = $searchstr . " and acct_code IS NULL";
  }
  else {
    $searchstr = $searchstr . " and acct_code='$acct_code'";
  }
  $searchstr = $searchstr . " and result='success' and operation<>'query'";

#print "SRCH:$searchstr\n";

#exit;

$st = time();

  my $sth_orders = $dbh->prepare(qq{
        select orderid,shipping,tax
        from ordersummary
        where trans_date>'$start' and trans_date<='$end' and username='$merchant' and result='success'
        }) or die "Can't do: $DBI::errstr";
  $sth_orders->execute or die "Can't execute: $DBI::errstr";
  $sth_orders->bind_columns(undef,\($orderid,$shipping,$tax));
  while($sth_orders->fetch) {
    $tax{$orderid} = $tax;
    $shipping{$orderid} = $shipping;
  }
  $sth_orders->finish;

$ed = time();

$el = $ed - $st;


  $sth = $dbh->prepare($searchstr) or die "Can't do: $DBI::errstr";
  $sth->execute or die "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($orderid,$card_name,$trans_date,$trans_time,$amount,$operation));
  while($sth->fetch) {
    #print "$orderid,$card_name,$trans_date,$trans_time,$amount:$acct_code<br>\n";
    $amount =~ s/[^0-9\.]//g;
    $amount = $amount - $shipping{$orderid} - $tax{$orderid};
    $amount = sprintf("%.2f",$amount);
    $$operation{$orderid} = $amount;
    $orderid{$orderid} = 1;
    $$orderid{$operation} = 1;
    $date{$orderid} = $trans_date;
  }
  $sth->finish;
  $dbh->disconnect;


  foreach $oid (sort keys %date) {
    foreach $operation (sort keys %$oid) {
      $trans_date = $date{$oid};
      $date2 = substr($trans_date,0,6);
      $$operation{$oid};
      if ($operation ne "auth") {
        $total{$trans_date} = $total{$trans_date} - $$operation{$oid};
        $total_month{$date2} = $total_month{$date2} - $$operation{$oid};
        $grandtotal = $grandtotal - $$operation{$oid};
        $total_month{$acct_code} = $total_month{$acct_code} - $$operation{$oid};
        #$total = $total - $$operation{$oid};
      }
      else {
        $total{$trans_date} = $total{$trans_date} + $$operation{$oid};
        $total_month{$date2} = $total_month{$date2} + $$operation{$oid};
        $grandtotal = $grandtotal + $$operation{$oid};
        $total_month{$acct_code} = $total_month{$acct_code} + $$operation{$oid};
        #$total = $total + $$operation{$oid};
      }
      if ($total_month{$acct_code} > $maxmonth) {
        $maxmonth = $total_month{$acct_code};
      }
    }
  }

#print "AFFDFD\n";

#  while($sth->fetch) {
    #$amount = substr($amount,4);
    #$total_month{$acct_code} = $total_month{$acct_code} + $amount;
    #$grandtotal = $grandtotal + $amount;
    #if ($total_month{$acct_code} > $maxmonth) {
    #  $maxmonth = $total_month{$acct_code};
    #}
 # }

  $sth->finish;
  $dbh->disconnect;

  print "<table border=1>\n";

  foreach $key (sort keys %total_month) {

    $width = sprintf("%d",$total_month{$key} * 500 / $maxmonth);

    print "<tr>";
    print "<th align=left>$key</th>";
    printf("<td align=right>%.2f</td>", $total_month{$key});
    print "<td align=left><img src=\"/payment/affiliate/blue.gif\" height=5 width=$width></td>";
    print "\n";
  }

  printf("<tr><th align=left>TOTAL:</th><td align=right>%.2f</td><td></td>", $grandtotal);

  print "</table>\n";

  print "<form  action=\"index.html\">\n";
  print "<input type=submit name=submit value=\"Main Page\">\n";
  print "</form>\n";

  print "</div>\n";

  print "</body>\n";
  print "</html>\n";
}


sub graph {
  $function = $query->param('function');
  $graphtype = $query->param('graphtype');
  $acct_code = $username;
  $startmonth = $query->param('startmonth');
  $startyear = $query->param('startyear');
  $startday = $query->param('startday');
  $endmonth = $query->param('endmonth');
  $endyear = $query->param('endyear');
  $endday = $query->param('endday');

  $start = sprintf("%04d%02d%02d", $startyear,$month_array2{$startmonth}, $startday);
  $end = sprintf("%04d%02d%02d", $endyear,$month_array2{$endmonth}, $endday);
  $reportstart = sprintf("%02d/%02d/%02d", $month_array2{$startmonth}, $startday, $startyear);
  $reportend = sprintf("%02d/%02d/%02d", $month_array2{$endmonth}, $endday, $endyear);


  $total = 0;

  print "<html>\n";
  print "<head>\n";
  print "<title>Affiliate Reports - Graphs</title>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"/payment/affiliate/stylesheet.css\">\n";
  print "</head>\n";
  print "<body bgcolor=\"#ffffff\" link=\"#000000\">\n";
  print "<div align=\"left\">\n";
  print "<h3>Sales Graph for ";
  if ($company ne "") {
    print "$company ";
  }
  print "Affiliate Account: $acct_code</h3>\n";
  print "Report Period: $reportstart to $reportend<p>\n";

  $max = 200;
  $maxmonth = 200;


  $dbh = &miscutils::dbhconnect("pnpdata");

  $searchstr = "select t.orderid,t.card_name,t.trans_date,t.trans_time,t.amount,t.operation";
  $searchstr = $searchstr . " from trans_log t";
  $searchstr = $searchstr . " where t.trans_date>='$start' and t.trans_date<='$end'";
  $searchstr = $searchstr . " and t.username='$merchant'";
  if ($acct_code eq "") {
    $searchstr = $searchstr . " and t.acct_code IS NULL";
  }
  else {
    $searchstr = $searchstr . " and t.acct_code='$acct_code'";
  }
  $searchstr = $searchstr . " and t.result='success'";

  my $sth_orders = $dbh->prepare(qq{
        select orderid,shipping,tax
        from ordersummary
        where trans_date>'$start' and trans_date<='$end' and username='$merchant' and result='success'
        }) or die "Can't do: $DBI::errstr";
  $sth_orders->execute or die "Can't execute: $DBI::errstr";
  $sth_orders->bind_columns(undef,\($orderid,$shipping,$tax));
  while($sth_orders->fetch) {
    $tax{$orderid} = $tax;
    $shipping{$orderid} = $shipping;
  }
  $sth_orders->finish;

  $sth = $dbh->prepare($searchstr) or die "Can't do: $DBI::errstr";
  $sth->execute or die "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($orderid,$card_name,$trans_date,$trans_time,$amount,$operation));
  while($sth->fetch) {
    $amount =~ s/[^0-9\.]//g;
    $amount = $amount - $shipping{$orderid} - $tax{$orderid};
    $amount = sprintf("%.2f",$amount);
    $$operation{$orderid} = $amount;
    $orderid{$orderid} = 1;
    $$orderid{$operation} = 1;
    $date{$orderid} = $trans_date;
  }
  $sth->finish;
  $dbh->disconnect;
  foreach $oid (sort keys %date) {
    foreach $operation (sort keys %$oid) {
      $trans_date = $date{$oid};
      $date2 = substr($trans_date,0,6);
      $$operation{$oid};
      if ($operation ne "auth") {
        $total{$trans_date} = $total{$trans_date} - $$operation{$oid};
        $total_month{$date2} = $total_month{$date2} - $$operation{$oid};
        $grandtotal = $grandtotal - $$operation{$oid};
        #$total = $total - $$operation{$oid};
      }
      else {
        $total{$trans_date} = $total{$trans_date} + $$operation{$oid};
        $total_month{$date2} = $total_month{$date2} + $$operation{$oid};
        $grandtotal = $grandtotal + $$operation{$oid};
        #$total = $total + $$operation{$oid};
      }
      if($total{$trans_date} > $max) {
        $max = $total{$trans_date};
      }
      if($total_month{$date2} > $maxmonth) {
        $maxmonth = $total_month{$date2};
      }
    }
  }
#  while($sth->fetch) {
#    $amount =~ s/[^0-9\.]//g;
#    $amount = $amount - $shipping - $tax;
#    $amount = substr($amount,4);

#    $total{$trans_date} = $total{$trans_date} + $amount;
#    $date2 = substr($trans_date,0,6);
#    $total_month{$date2} = $total_month{$date2} + $amount;
#    $grandtotal = $grandtotal + $amount;

#    if($total{$trans_date} > $max) {
#      $max = $total{$trans_date};
#    }

#    if($total_month{$date2} > $maxmonth) {
#      $maxmonth = $total_month{$date2};
#    }
#  }

#  $sth->finish;
#  $dbh->disconnect;

  print "<table border=1>\n";

  if ($graphtype eq "daily") {
    $period_start = timegm(0,0,0,substr($start,6,2),substr($start,4,2)-1,substr($start,0,4)-1900);
    $period_end = timegm(0,0,0,substr($end,6,2),substr($end,4,2)-1,substr($end,0,4)-1900);
    $period_end2 = time();
    if ($period_end2 < $period_end) {
      $period_end = $period_end2;
    }

    for ($i=$period_start; $i<=$period_end; $i=$i+(3600*24)) {

      ($dummy1,$dummy2,$dummy3,$day1,$month1,$year1,$dummy4) = gmtime($i);
      $date = sprintf("%04d%02d%02d", ($year1 + 1900), ($month1 + 1), $day1);
      $datestr = sprintf("%02d/%02d/%04d", ($month1 + 1), $day1, ($year1 + 1900));
      $width = sprintf("%d",$total{$date} * 500 / $max);

      print "<tr>";
      print "<th align=left>$datestr</th>";
      printf("<td align=right>%.2f</td>", $total{$date});
      print "<td align=left><img src=\"/payment/affiliate/blue.gif\" height=5 width=$width></td>";
      print "\n";
    }

    printf("<tr><th align=left>TOTAL:</th><td align=right>%.2f</td><td></td>", $grandtotal);
  }
  else {
    foreach $key (sort keys %total_month) {
      $datestr = sprintf("%02d/%04d", substr($key,4,2), substr($key,0,4));
      $width = sprintf("%d",$total_month{$key} * 500 / $maxmonth);
      print "<tr>";
      print "<th align=left>$datestr</th>";
      printf("<td align=right>%.2f</td>", $total_month{$key});
      print "<td align=left><img src=\"/payment/affiliate/blue.gif\" height=5 width=$width></td>";
      print "\n";
    }
    printf("<tr><th align=left>TOTAL:</th><td align=right>%.2f</td><td></td>", $grandtotal);
  }
  print "</table>\n";
  print "<form  action=\"index.html\">\n";
  print "<input type=submit name=submit value=\"Main Page\">\n";
  print "</form>\n";
  print "</div>\n";
  print "</body>\n";
  print "</html>\n";
}

sub checkcard {
  my ($cardnumber) = @_;

  my $cabbrev = substr($cardnumber,0,4);

  if ($cardnumber =~ /^4/) {
    $cardtype = 'vi';                    # visa
  }
  elsif ($cardnumber =~ /^5[12345]/) {
    $cardtype = 'mc';                    # mastercard
  }
  elsif ($cardnumber =~ /^3[47]/) {
    $cardtype = 'ax';                    # amex
  }
  elsif ($cardnumber =~ /^3[068]/) {
    $cardtype = 'dc';                    # diners club/carte blanche
  }
  elsif ($cardnumber =~ /^6011/) {
    $cardtype = 'ds';                    # discover
  }
  elsif ( ($cardnumber =~ /^(3088|3096|3112|3158|3337)/) || (($cabbrev >= 3528) && ($cabbrev < 3590)) ) {    # jcb
    $cardtype = 'jc';                    # jcb
  }
  else {
    $cardtype = 'ot';
  }

  return $cardtype;
}


sub dateIN {
  my ($start,$end,$dateArray,$qmarks) = @_;

  my $year = substr($start,0,4);
  my $month = substr($start,4,2);
  my $day = substr($start,6,2);

  my $endYear = substr($end,0,4);
  my $endMon = substr($end,4,2);
  my $endDay = substr($end,6,2);

  my $daysInMonth = Days_in_Month($endYear,$endMon);

  if ($endDay > $daysInMonth) {
    $endDay = $daysInMonth;
  }
  push (@$dateArray,$start);

  my $Dd = Delta_Days($year,$month,$day,$endYear,$endMon,$endDay);
  for(my $i=1; $i<=$Dd; $i++) {
    ($year,$month,$day) = Add_Delta_Days($year,$month,$day,1);
    my $incrementedDate = $year . sprintf("%02d",$month) . sprintf("%02d",$day);
    push (@$dateArray,$incrementedDate);
  }
  $$qmarks = '?,' x @$dateArray;
  chop $$qmarks;

  return;
}


1;
