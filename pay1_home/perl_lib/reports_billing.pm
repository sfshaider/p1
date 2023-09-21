#!/usr/local/bin/perl
require 5.001;
$| = 1;

package reports;

use miscutils;
use Time::Local qw(timegm);
use sysutils;
use Date::Calc qw(Add_Delta_Days Delta_Days Days_in_Month);


sub new {
  my $type = shift;

  my($reseller) = @_;

  $report::reseller = $reseller;

  my $debug = 1;

  %reports::altaccts = ('cableand',['cableand','cccc','jncb','bdagov'],'stkittsn',['stkittsn','stkitts2']);
  %reports::billingdate = ('cableand','24','jncb','1');

  %reports::include_fees = ('cableand','0');

  if ($reports::billingdate{$reseller} eq "") {
    $reports::billingdate{$reseller} = "1";
  }
  $reports::first_flag = 1;

  %reports::month_array2 = ("Jan","01","Feb","02","Mar","03","Apr","04","May","05","Jun","06","Jul","07","Aug","08","Sep","09","Oct","10","Nov","11","Dec","12");

  ## Start Date
  my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = gmtime(time());
  if ($month == 0) {
    $month = "12";
    $year -= 1;
  }
  $reports::startdate = $year+1900 . sprintf("%02d",$month) . sprintf("%02d",$reports::billingdate{$reseller});
  $reports::starttime = $reports::startdate . "000000";
  
  ## End Date
  my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = gmtime(time());
  $reports::enddate = $year+1900 . sprintf("%02d",$month+1) . sprintf("%02d",$reports::billingdate{$reseller}-1);

  print "RESELLER:$reseller, START:$reports::startdate, END:$reports::enddate\n";

  #$reports::startdate = "20071225";
  #$reports::enddate = "20080101";

  return [], $type;
}

sub query_cust {
  my($usename) = @_;
  my $dbh = &miscutils::dbhconnect("pnpmisc");

  my $qstr = "select processor,merchant_id,merchemail,fax ";
  $qstr .= "from customers where username='$username'";
  my $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
  $sth->execute() or die "Can't execute: $DBI::errstr";
  my $data = $sth->fetchrow_hashref();
  $sth->finish;

  $dbh->disconnect;

  foreach my $key (keys %$data) {
    # encrypt passwords, as necessary
    $tempkey = $key;
    $key =~ tr/A-Z/a-z/;
    $$data{$key} = $$data{$tempkey};
  }
  return %$data;
}


sub query {
  my $type = shift;  
  my(@merchlist) = @_;

  #foreach my $merchant (@merchlist) {
  #  print "M:$merchant\n";
  #}

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
  $arraylimit = 30;

  $tt = time();

  my ($temp,@temp,@data); 
  $j = 0; 
  foreach my $var (@merchlist) { 
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


  &dateIN($reports::startdate,$reports::enddate,\@dateArray,\$qmarks);
  my @executeArray = ();

  foreach my $strg (@data) {
    @executeArray = ();
    #print "STRG:$strg\n\n";

    $strg =~ s/[^a-z0-9\,]//g;
    my @unArray = split(/\,/,$strg);
    my $qmarks2 = '?,' x @unArray;
    chop $qmarks2;
    push (@executeArray,@dateArray,@unArray,$reports::starttime);

    $qstr = "select trans_date, ";
    $qstr .= "username, operation, finalstatus, count(username), sum(substr(amount,4)) ";
    $qstr .= "from trans_log force index(tlog_tdateuname_idx) where trans_date IN ($qmarks) ";
    $qstr .= "and username IN ($qmarks2) ";
    $qstr .= "and trans_time>=? ";
    $qstr .= "and operation NOT IN ('batch-prep','batchquery','batch-commit','query') and (duplicate IS NULL or duplicate ='') ";
    $qstr .= "group by trans_date, username, operation, finalstatus";

    print "QSTR:$qstr\n\n\n";

    #exit;
    #last;
    #next;

    $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
    $sth->execute(@executeArray) or die "Can't execute: $DBI::errstr";
    $sth->bind_columns(undef,\($trans_date, $username, $operation, $finalstatus, $count, $sum));
    #$sth->bind_columns(undef,\($trans_date,$orderid, $operation, $finalstatus, $amt));
    while ($sth->fetch) {
      #print "AAAAA:$username, $trans_date, $orderid, $operation, $finalstatus, $count, $sum\n";
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

  #last;

  }
  $dbh->disconnect;

  $reports::lastusername = $username;
  print "LASTUN:$reports::lastusername\n";

  $noacct_code{'1'} = "";

}

sub query_fraud {
    $operation = "auth";
    $finalstatus = "fraud";

    my $start = $reports::startdate . "000000";
    my $end = $reports::enddate . "000000";

    $qstr = "select username, trans_time, acct_code, acct_code2, acct_code3, subacct from fraud_log where trans_time>='$start' and trans_time<'$end' ";
    $qstr .= "and username='$reports::username' ";
 
    #print "QSTR:$qstr:\n";
    #exit;
 
    my $dbh = &miscutils::dbhconnect("fraudtrack");
 
    my $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
    $sth->execute or die "Can't execute: $DBI::errstr";
    $sth->bind_columns(undef,\($username, $trans_time, $acct_code, $acct_code2, $acct_code3, $subacct));
    while ($sth->fetch) {
      #print "AAAAAAAAAAAAAAA:$trans_time, $acct_code, $acct_code2, $acct_code3<br>\n";
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

    #print "AAA:$aaaa:$operation:$finalstatus<br>\n";
  }
  $sth->finish;
 $dbh->disconnect;
}



sub billing {

  my (%db,@fixedlist,@feelist,$free250);
  ####  Billing Rates and Fees
  #if ($subacct ne "") {
  #  $qstr = "select feeid,feetype,feedesc,rate,type from billing where username='$username' and subacct='$subacct'";
  #}
  #else {
    $qstr = "select feeid,feetype,feedesc,rate,type from billing where username='$username'";
  #}
  $username = $reports::username;
  my %custdata = &query_cust($username);

  my $time = gmtime(time());
  #print "PRE MERCHINFO TIME1:$time\n";

  $dbh = &miscutils::dbhconnect("merch_info");
  my $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
  $sth->execute() or die "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($db{'feeid'},$db{'feetype'},$db{'desc'},$db{'rate'},$db{'type'}));
  while ($sth->fetch) {
    $db{'type'} = "pertran"; ###  Comment out later.
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
      #if ($db{'rate'} == 250) {
        $free250 = "yes";
      #}
    }
  }
  $sth->finish;
  $dbh->disconnect;

  my $i=0;
  my ($temp,%dates,@temp,%cb,%oiddate,%action);

  %label_hash = ('pertran','','percent','$');
  %rate_hash = ('pertran','$','percent','%');

  #####  DEBUG  DCP
  #print "UN:$username, ";
  #foreach my $key (sort keys %totalcnt) {
  #  print "$key:$totalcnt{$key}, ";
  #}
  #print "\n";

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
#print "AAAAA\n";
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
#print "BBBB\n";
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
  my $header_text .= "MID\tUSERNAME\tEMAIL\tPREMIUM\tPROCESSOR\tFAX\t";
  my $line_text = "$custdata{'merchant_id'}\t$username\t$custdata{'merchemail'}\t$premium\t$custdata{'processor'}\t$custdata{'fax'}\t";

  #print "HT:$header_text\n";

#  print "<div align=\"center\"><table border=1 cellspacing=1 width=\"550\">\n";
#  print "<tr><th colspan=\"3\">Billing</th></tr>\n";

  my ($line);

  if ($reports::include_fees{"$report::reseller"} == 0) {
    $header_text .= "TOT_AUTH_CNT\t";
    $line_text .= "$label_hash{$newauthfee{'type'}}$total_auths_new\t";

    $header_text .= "TOT_AUTH_REC_CNT\t";
    $line_text .= "$label_hash{$recauthfee{'type'}}$total_auths_rec\t";

    $header_text .= "TOT_AUTH_DECL_CNT\t";
    $line_text .= "$label_hash{$declinedfee{'type'}}$total_auths_decl\t";

    $header_text .= "TOT_RETRN_CNT\t";
    $line_text .= "$label_hash{$returnfee{'type'}}$total_retrn\t";

    $header_text .= "TOT_VOID_CNT\t";
    $line_text .= "$label_hash{$voidfee{'type'}}$total_void\t";

    $header_text .= "TOT_FRAUD_CNT\t";
    $line_text .= "$label_hash{$fraudfee{'type'}}$total_fraud\t";

    $header_text .= "TOT_CYBERSRC_CNT\t";
    $line_text .= "$label_hash{$cybersfee{'type'}}$total_cybers\t";
  }
  else {
    $header_text .= "TOT_AUTH_NEW_CNT\tTOT_AUTH_NEW_FEE\t";
    $line_text .= "$label_hash{$newauthfee{'type'}}$total_auths_new\t$total_auths_new_fee\t";

    $header_text .= "TOT_AUTH_REC_CNT\tTOT_AUTH_REC_FEE\t";
    $line_text .= "$label_hash{$recauthfee{'type'}}$total_auths_rec\t$total_auths_rec_fee\t";

    $header_text .= "TOT_AUTH_DECL_CNT\tTOT_AUTH_DECL_FEE\t";
    $line_text .= "$label_hash{$declinedfee{'type'}}$total_auths_decl\t$total_auths_decl_fee\t";

    $header_text .= "TOT_RETRN_CNT\tTOT_RETRN_FEE\t";
    $line_text .= "$label_hash{$returnfee{'type'}}$total_retrn\t$total_retrn_fee\t";

    $header_text .= "TOT_VOID_CNT\tTOT_VOID_FEE\t";
    $line_text .= "$label_hash{$voidfee{'type'}}$total_void\t$total_void_fee\t";

    $header_text .= "TOT_FRAUD_CNT\tTOT_FRAUD_FEE\t";
    $line_text .= "$label_hash{$fraudfee{'type'}}$total_fraud\t$total_fraud_fee\t";

    $header_text .= "TOT_CYBERSRC_CNT\tTOT_CYBERSRC_FEE\t";
    $line_text .= "$label_hash{$cybersfee{'type'}}$total_cybers\t$total_cybers_fee\t";

    $header_text .= "TOT_DISCNT_FEE\t";
    $line_text .= "$total_discnt_fee\t";

  }
  my ($total_fixed);
  foreach $feeid (@fixedlist) {
    $total_fixed += $$feeid{'rate'};
  }

  $header_text .= "TOT_FIXED_FEE\t";
  $line_text .= "$total_fixed\t";

  if ($reports::include_fees{"$report::reseller"} == 0) {

  }
  else {
    $total = $total_auths_new_fee + $total_auths_rec_fee + $total_auths_decl_fee +  $total_retrn_fee + $total_void_fee + $total_fraud_fee + $total_cybers_fee + $total_discnt_fee + $total_fixed;
    $total = sprintf("%0.2f",$total);
    $header_text .= "TOT_FEE";         
    $line_text .= "$total";
  }

  $report::reseller =~ s/[^0-9a-zA-Z]//g;
  if ($reports::first_flag == 1) {
    &sysutils::filelog("write",">/home/p/pay1/web/newreseller/admin/overview/billinglogs/$reports::startdate\_$reports::enddate\_$report::reseller\.txt");
    open (BILLING, ">/home/p/pay1/web/newreseller/admin/overview/billinglogs/$reports::startdate\_$reports::enddate\_$report::reseller\.txt");
  }
  else {
    &sysutils::filelog("append",">>/home/p/pay1/web/newreseller/admin/overview/billinglogs/$reports::startdate\_$reports::enddate\_$report::reseller\.txt");
    open (BILLING, ">>/home/p/pay1/web/newreseller/admin/overview/billinglogs/$reports::startdate\_$reports::enddate\_$report::reseller\.txt");
  }

  if ($reports::first_flag == 1) {
    print "$header_text\n";
    print BILLING "$header_text\n";
    $reports::first_flag = 5;
  }
  print "$line_text\n";
  print BILLING "$line_text\n";
  $line = "";
  
}



sub overview {
  my($reseller,$merchant) = @_;
  my ($db_merchant);

  my $dbh = &miscutils::dbhconnect("pnpmisc");

  if ($reseller eq "cableand") {
    my $sth = $dbh->prepare(qq{
        select username
        from customers
        where reseller IN ('cableand','cccc','jncb','bdagov')
        and username='$merchant'
        }) or die "Can't do: $DBI::errstr";
    $sth->execute or die "Can't execute: $DBI::errstr";
    ($db_merchant) = $sth->fetchrow;
    $sth->finish;
  }
  elsif ($reseller eq "volpayin") {
    my $sth = $dbh->prepare(qq{
        select username 
        from customers
        where processor='volpay'
        and username='$merchant'
    }) or die "Can't prepare: $DBI::errstr";
    $sth->execute or die "Can't execute: $DBI::errstr";
    ($db_merchant) = $sth->fetchrow;
    $sth->finish;
  }
  else {
    my $sth = $dbh->prepare(qq{
        select username
        from customers
        where reseller='$reseller' and username='$merchant'
        }) or die "Can't do: $DBI::errstr";
    $sth->execute or die "Can't execute: $DBI::errstr";
    ($db_merchant) = $sth->fetchrow;
    $sth->finish;
  }

  $dbh->disconnect;

  return $db_merchant;

}


sub merchlist {
  my $reseller = $report::reseller;
  my ($db_merchant,@merchlist);

  if ($reseller eq "") {
    return;
  }

  my $dbh = &miscutils::dbhconnect("pnpmisc");
  if (exists $reports::altaccts{$reseller}) {
    foreach my $var ( @{ $reports::altaccts{$reseller} } ) {
      $str .= "\'$var',";
    }
    chop $str;

    my $sth = $dbh->prepare(qq{
        select username
        from customers
        where reseller IN ($str) 
        }) or die "Can't do: $DBI::errstr";
    $sth->execute or die "Can't execute: $DBI::errstr";
    my $rv = $sth->bind_columns(undef,\($db_merchant));
    while($sth->fetch) {
      $merchlist[++$#merchlist] = "$db_merchant";
    }
    $sth->finish;
  }
  else {
    #print "BBBB\n";
    my $sth = $dbh->prepare(qq{
        select username
        from customers
        where reseller='$reseller' 
        }) or die "Can't do: $DBI::errstr";
    $sth->execute or die "Can't execute: $DBI::errstr";
    my $rv = $sth->bind_columns(undef,\($db_merchant));
    while($sth->fetch) {
      $merchlist[++$#merchlist] = "$db_merchant";
    }
    $sth->finish;
  }
  $dbh->disconnect;

  ### Comment out when Live
  #@merchlist = ('bdaaquariu','firstchurc');

  return @merchlist;
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
