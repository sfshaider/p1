package reports;

require 5.001;
$| = 1;

use CGI;
use DBI;
use Time::Local qw(timegm);
use miscutils;
use PlugNPay::Logging::DataLog;

sub new {
  my $type = shift;

  $reports::debug = 1;

  $first_flag = 1;

  $earliest_date = "20070101"; 
  
  %altaccts = ('icommerceg',["icommerceg","icgoceanba","icgcrossco"],'golinte1',["golinte1","golinte6"],'dietsmar',["dietsmar","dietsmar2"]);

  %month_array2 = ("Jan","01","Feb","02","Mar","03","Apr","04","May","05","Jun","06","Jul","07","Aug","08","Sep","09","Oct","10","Nov","11","Dec","12");

  $username = $ENV{"REMOTE_USER"};
 
  $query = new CGI;

  if (&CGI::escapeHTML($query->param('start')) eq "") {
    $startmonth = &CGI::escapeHTML($query->param('startmonth'));
    $startmonth = sprintf("%02d",$startmonth);
    $startyear = &CGI::escapeHTML($query->param('startyear'));
    $startyear = sprintf("%04d",$startyear);
    if ($startyear < 2000) {
      $startyear = "2000";
    }
    $startday = &CGI::escapeHTML($query->param('startday'));
    $startday = sprintf("%02d",$startday);
    $start = $startyear . $startmonth . $startday;
  }
  else {
    $start = &CGI::escapeHTML($query->param('start'));
    $startyear = substr($start,0,4);
    $startmonth = substr($start,4,2);
    $startday = substr($start,6,2);
    $start = $startyear . $startmonth . $startday;
  }

  if (&CGI::escapeHTML($query->param('end')) eq "") {
    $endmonth = &CGI::escapeHTML($query->param('endmonth'));
    $endmonth = sprintf("%02d",$endmonth);
    $endyear = &CGI::escapeHTML($query->param('endyear'));
    $endyear = sprintf("%02d",$endyear);
    if ($endyear < $startyear) {
      $endyear = $startyear;
    }
    $endday = &CGI::escapeHTML($query->param('endday'));
    $endday = sprintf("%02d",$endday);
    $end = $endyear . $endmonth . $endday;
  }
  else {
    $end = &CGI::escapeHTML($query->param('end'));
    $endyear = substr($end,0,4);
    $endmonth = substr($end,4,2);
    $endday = substr($end,6,2);
    $end = $endyear . $endmonth . $endday;
  }

  $function = &CGI::escapeHTML($query->param('function'));
  $mode = &CGI::escapeHTML($query->param('mode'));

  if ($ENV{'SUBACCT'} eq "") {
    $subacct = &CGI::escapeHTML($query->param('subacct'));
  }
  else {
    $subacct = $ENV{'SUBACCT'}; 
  }

  $todadjust = &CGI::escapeHTML($query->param('todadjust'));

  $format = &CGI::escapeHTML($query->param('format'));
  $function = &CGI::escapeHTML($query->param('function'));
  $mode = &CGI::escapeHTML($query->param('mode'));
  $acct_code = &CGI::escapeHTML($query->param('acct_code'));
  $acct_code2 = &CGI::escapeHTML($query->param('acct_code2'));
  $acct_code3 = &CGI::escapeHTML($query->param('acct_code3'));
  $recurring = &CGI::escapeHTML($query->param('recurring'));

  $goodcolor = "#000000";
  $badcolor = "#ff0000";
  $backcolor = "#ffffff";
  $fontface = "Arial,Helvetica,Univers,Zurich BT";

  $sortorder = &CGI::escapeHTML($query->param('sortorder'));  ###  Used to Sort and/or Group Results

  if ($start eq "") {
    my ($trans_date,$trans_time) = &miscutils::gendatetime_only();
    $start = substr($trans_date,0,6);
  }
 
  if ($end eq "") {
    $end = $start;
  }

  if ($start < $earliest_date) {
    $start = $earliest_date;
  } 

  my $starttranstime = &miscutils::strtotime($start);
  my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = gmtime($starttranstime - (3600 * 24 * 30));

  ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = gmtime($starttranstime - (3600 * 24 * 15));
  $starttransdate = sprintf("%04d%02d%02d",$year+1900,$month+1,$day);

  $starttime = $start . "000000";

  $endtimea = &miscutils::strtotime($end);
  $elapse = $endtimea-$starttranstime;

  if ($elapse > (33 * 24 * 3600)) {
    my $message = "Sorry, but no more than 1 months may be queried at one time.  Please use the back button and change your selected date range."; 
    #print "$message\n";
    &response_page($message); 
    exit; 
 
  }


  #  Time Zone Adjustment - Needs some work.
  #$time = &miscutils::strtotime($start);
  #$adjust = time() - $time + ($todadjust * 3600);
  #($dummy,$trans_date,$start_time) = &miscutils::gendatetime(-$adjust);
  #$start = $trans_date;

  #$time = &miscutils::strtotime($end);
  #$adjust = time() - $time + ($todadjust * 3600) - (24 * 3600);
  #($dummy,$trans_date,$end_time) = &miscutils::gendatetime(-$adjust);
  #$end = $trans_date;

  $merchant = &CGI::escapeHTML($query->param('merchant'));

  $dbh = &miscutils::dbhconnect("pnpmisc");

  if (($merchant ne "") && ($ENV{'SCRIPT_NAME'} =~ /overview/)) {
    my $sth = $dbh->prepare(q{
        SELECT overview
        FROM salesforce
        WHERE username=?
      }) or die "Can't do: $DBI::errstr";
    $sth->execute("$ENV{'REMOTE_USER'}") or die "Can't execute: $DBI::errstr";
    ($allow_overview) = $sth->fetchrow;
    $sth->finish;
  }

  if ($allow_overview == 1) {
    if ($merchant =~ /^ALL|EVERY$/) {
      my (@un);
      $sth = $dbh->prepare(q{
          SELECT username
          FROM customers
          WHERE reseller=?
          ORDER BY username
        }) or die "Can't do: $DBI::errstr";
      $sth->execute("$username") or die "Can't execute: $DBI::errstr";
      while (my ($db_uname) = $sth->fetchrow) {
        push(@un,$db_uname);  
      }
      $sth->finish;
      $altaccts{$ENV{'REMOTE_USER'}} = [@un];
    }
    else {
      $username = &overview($ENV{'REMOTE_USER'},$merchant);
      $ENV{'REMOTE_USER'} = $username;
      if ($merchant =~ /icommerceg/) { 
        $subacct = &CGI::escapeHTML($query->param('subacct'));
        if (($ENV{'SUBACCT'} eq "") && ($subacct ne "")) {
          $ENV{'SUBACCT'} = $subacct;
        }
      }
      $detailflag = 1;
    }
  }

  my $sth = $dbh->prepare(q{
      SELECT company 
      FROM customers
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$ENV{'REMOTE_USER'}") or die "Can't execute: $DBI::errstr";
  ($merch_company) = $sth->fetchrow;
  $sth->finish();

  $dbh->disconnect;

  if (($subacct =~ /ipayglobill|ipayfriendf|friendfinde|friendfinde1|friendfinde2/)) {
    $detailflag = 1;
  }

  if (($username =~ /ipayglobill|ipayfriendf|friendfinde|friendfinde1|friendfinde2|nabwpgprod|hvinvestm|tahientert1|ipaydrewnet|igorman/)) {
    $detailflag = 1;
  }

  $reports::start = time();

  if ($reports::debug == 1) {
    open(DEBUG,">>/home/p/pay1/database/debug/report_queries.txt");
    my $now = gmtime(time());
    print DEBUG "$now, IP:$ENV{'REMOTE_ADDR'}, UN:$ENV{'REMOTE_USER'}, PID:$$, ";
    my @params = $query->param;
    foreach my $param (@params) {
      my $s = &CGI::escapeHTML($query->param($param));
      if (length($s) > 50) {
        $s = substr($s,0,50) . ":length($s)";
      }
      print DEBUG "$param:$s, ";
    }
    print DEBUG "\n";
    close(DEBUG);

    #use Datalog
    my $logger = new PlugNPay::Logging::DataLog({collection => 'reports'});
    my %data  = ();
    $data{DATE} = $now;
    $data{IP}   = $ENV{'REMOTE_ADDR'};
    $data{UN}   = $ENV{'REMOTE_USER'};
    $data{PID}  = $$;
    foreach my $param (@params){
      my $s = &CGI::escapeHTML($query->param($param));
      if (length($s) > 50) {
        $s = substr($s,0,50) . ":length($s)";
      }
      $data{$param} = $s;
    }
    $logger->log(\%data);
  }

  return [], $type;
}

sub query_cust {

  my $dbh = &miscutils::dbhconnect("pnpmisc");

  my @placeholder;
  my $qstr = "SELECT name,company,addr1,addr2,city,state,zip,country,reseller,processor";
  $qstr .= " FROM customers";
  if ($subacct ne "") {
    $qstr .= " WHERE subacct=?";
    push(@placeholder, $subacct);
  } 
  else {
    $qstr .= " WHERE username=?";
    push(@placeholder, $username);
  }

  $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  ($name,$company,$addr1,$addr2,$city,$state,$zip,$country,$dbreseller,$processor) = $sth->fetchrow;
  $sth->finish;

  $sth = $dbh->prepare(q{
      SELECT fraud_config
      FROM customers
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$username") or die "Can't execute: $DBI::errstr";
  ($fraud_config) = $sth->fetchrow;
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
 
  $dbh = &miscutils::dbhconnect("pnpdata","","$username");

  $total = 0;

  $start1 = $start;
  $end1 = $end;

  $max = 200;
  $maxmonth = 200;
  $trans_max = 200;
  $trans_maxmonth = 200;

  $tt = time();

  my @placeholder;
  if ($report_time eq "batchtime") {
    $qstr = "SELECT batch_time,";
  }
  else {
    $qstr = "SELECT trans_time,";
  }

  if (($username =~ /barbara|unplugged|cprice/) && ($merchant eq "ALL")) {
    $qstr .= " operation, finalstatus, acct_code, acct_code2, acct_code3, acct_code4, count(username), sum(substr(amount,5)), substr(amount,1,3)"; 
    $qstr .= " FROM trans_log FORCE INDEX(tlog_tdateuname_idx)";
    my ($qmarks,$dateArrayRef) = &miscutils::dateIn($starttransdate,$end,'0');
    $qstr .= " WHERE trans_date IN ($qmarks)";
    push(@placeholder, @$dateArrayRef);
    $qstr .= " AND trans_time>=?";
    push(@placeholder, $starttime);
    $qstr .= " AND operation IN ('auth','postauth','forceauth','void','return') and (duplicate IS NULL or duplicate='')";
    $qstr .= " GROUP BY trans_time, operation, finalstatus, acct_code, acct_code2, acct_code3, acct_code4";
  }
  elsif (($ENV{'REMOTE_USER'} =~ /^(northame|stkittsn|cableand|smart2pa|paymentd|jncb|bdagov)$/) && ($merchant eq "ALL")) {
    $qstr .= " operation, finalstatus, acct_code, acct_code2, acct_code3, acct_code4, count(username), sum(substr(amount,5)), substr(amount,1,3)"; 
    $qstr .= " FROM trans_log FORCE INDEX(tlog_tdateuname_idx)";
    my ($qmarks,$dateArrayRef) = &miscutils::dateIn($starttransdate,$end,'0');
    $qstr .= " WHERE trans_date IN ($qmarks)";
    push(@placeholder, @$dateArrayRef);

    if (exists $altaccts{$username}) {
      my ($temp);
      foreach my $var ( @{ $altaccts{$username} } ) {
        $temp .= "?,";
        push(@placeholder, $var);
      }
      chop $temp;
      $qstr .= " AND username IN ($temp)";
    }
    else {
      $qstr .= " AND username='AAAXXXXAAA'";
    }

    $qstr .= " AND trans_time>=?";
    push(@placeholder, $starttime);
    $qstr .= " AND operation<>'query' AND (duplicate IS NULL OR duplicate='')";
    $qstr .= " GROUP BY trans_time, operation, finalstatus, acct_code, acct_code2, acct_code3, acct_code4, substr(amount,1,3)";
  }
  elsif (($ENV{'REMOTE_USER'} =~ /^(northame|smart2pa|jncb|bdagov)$/) && ($merchant eq "EVERY")) {
    $qstr .= " username, operation, finalstatus, count(username), sum(substr(amount,5)), substr(amount,1,3)";
    $qstr .= " FROM trans_log FORCE INDEX(tlog_tdateuname_idx)";
    my ($qmarks,$dateArrayRef) = &miscutils::dateIn($starttransdate,$end,'0');
    $qstr .= " WHERE trans_date IN ($qmarks)";
    push(@placeholder, @$dateArrayRef);
 
    if (exists $altaccts{$username}) {
      my ($temp);
      foreach my $var ( @{ $altaccts{$username} } ) {
        $temp .= "?,";
        push(@placeholder, $var)
      }
      chop $temp;
      $qstr .= " AND username IN ($temp)";
    }
    else {
      $qstr .= " AND username='AAAXXXXAAA'";
    }

    $qstr .= " AND trans_time>=?"; 
    push(@placeholder, $starttime);
    $qstr .= " AND operation<>'query' AND (duplicate IS NULL OR duplicate='')";
    $qstr .= " GROUP BY trans_time, username, operation, finalstatus,substr(amount,1,3)";
    #print "QSTR:$qstr\n";
    exit;
  }
  elsif (($subacct ne "") && ($format !~ /chargeback/)) {
    $qstr .= " operation, finalstatus, acct_code, acct_code2, acct_code3, acct_code4, count(username), sum(substr(amount,5)), substr(amount,1,3)"; 
    $qstr .= " FROM trans_log FORCE INDEX(tlog_tdateuname_idx)";
    my ($qmarks,$dateArrayRef) = &miscutils::dateIn($starttransdate,$end,'0');
    $qstr .= " WHERE trans_date IN ($qmarks)";
    push(@placeholder, @$dateArrayRef);

    if (exists $altaccts{$username}) {
      my ($temp);
      foreach my $var ( @{ $altaccts{$username} } ) {
        $temp .= "?,";
        push(@placeholder, $var);
      }
      chop $temp;
      $qstr .= " AND username IN ($temp)";
    }
    else {
      $qstr .= " AND username=?";
      push(@placeholder, $username);
    }
 
    $qstr .= " AND trans_time>=?"; 
    push(@placeholder, $starttime);
    $qstr .= " AND subacct=? AND operation<>'query' AND (duplicate IS NULL OR duplicate='')";
    push(@placeholder, $subacct);
    $qstr .= " GROUP BY trans_time, operation, finalstatus, acct_code, acct_code2, acct_code3, acct_code4";
  }
  elsif ($subacct eq "ALL") {
    $qstr .= " operation, finalstatus, subacct, username, count(username), sum(substr(amount,5)), substr(amount,1,3)";
    $qstr .= " FROM trans_log FORCE INDEX(tlog_tdateuname_idx)";
    my ($qmarks,$dateArrayRef) = &miscutils::dateIn($starttransdate,$end,'0');
    $qstr .= " WHERE trans_date IN ($qmarks)";
    push(@placeholder, @$dateArrayRef);

    if (exists $altaccts{$username}) {
      my ($temp);
      foreach my $var ( @{ $altaccts{$username} } ) {
        $temp .= "?,";
        push(@placeholder, $var);
      }
      chop $temp;
      $qstr .= " AND username IN ($temp)";
    }
    else {
      $qstr .= " AND username=?";
      push(@placeholder, $username);
    }

    $qstr .= " AND trans_time>=?";
    push(@placeholder, $starttime);
    $qstr .= " AND operation<>'query' AND (duplicate IS NULL OR duplicate='')";
    $qstr .= " GROUP BY trans_time, operation, finalstatus, subacct";
  }
  elsif ($format =~ /chargeback/) {
    my $start = $start . '000000';
    my $end = $end . '000000';
    $qstr = " SELECT postauthtime, acct_code, acct_code2, cardtype, count(username), sum(substr(amount,5)) ";
    $qstr .= " FROM operation_log";
    $qstr .= " WHERE lastoptime>=? AND lastoptime<?";
    push(@placeholder, $start, $end);

    if ((exists $altaccts{$username}) && ($subacct ne "")) {
      my ($temp);
      foreach my $var ( @{ $altaccts{$username} } ) {
        $temp .= "?,";
        push(@placeholder, $var);
      }
      chop $temp;
      $qstr .= " AND username IN ($temp)";
    }
    else {
      $qstr .= " AND username=?";
      push(@placeholder, $username);
    }

    if ($subacct ne "") {
      $qstr .= " AND subacct=?";
      push(@placeholder, $subacct);
    }

    $qstr .= " AND postauthtime>=? AND postauthtime<?";
    push(@placeholder, $start, $end);
    $qstr .= " AND postauthstatus='success'";
    $qstr .= " GROUP BY postauthtime, acct_code, acct_code2, cardtype";
  }
  else {
    $qstr .= " operation, finalstatus, acct_code, acct_code2, acct_code3, acct_code4, count(username), sum(substr(amount,5)), substr(amount,1,3)";
    $qstr .= " FROM trans_log FORCE INDEX(tlog_tdateuname_idx)";
    my ($qmarks,$dateArrayRef) = &miscutils::dateIn($starttransdate,$end,'0');
    $qstr .= " WHERE trans_date IN ($qmarks)";
    push(@placeholder, @$dateArrayRef);

    if ((exists $altaccts{$username}) && ($username =~ /^golinte/)) {
      my ($temp);
      foreach my $var ( @{ $altaccts{$username} } ) {
        $temp .= "?,";
        push(@placeholder, $var);
      }
      chop $temp;
      $qstr .= " AND username IN ($temp)";
    }
    else {
      $qstr .= " AND username=?";
      push(@placeholder, $username);
    }

    $qstr .= " AND trans_time>=?";
    push(@placeholder, $starttime);
    $qstr .= " AND operation<>'query'";
    $qstr .= " AND (duplicate IS NULL OR duplicate='')";

    if ($recurring eq "yes") {
      $qstr .= " AND transflags LIKE '%recurring%'";
    }
    $qstr .= " GROUP BY trans_time, operation, finalstatus, acct_code, acct_code2, acct_code3, acct_code4, substr(amount,1,3)";
  }

  $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  if ($subacct eq "ALL") {
    $sth->bind_columns(undef,\($trans_date, $operation, $finalstatus, $acct_code, $username, $count, $sum, $curr));
  }
  elsif ($format =~ /chargeback/) {
    $sth->bind_columns(undef,\($trans_date, $acct_code, $acct_code2, $cardtype, $count, $sum));
  }
  elsif (($ENV{'REMOTE_USER'} =~ /^(northame|stkittsn|cableand|smart2pa|jncb|bdagov)$/) && ($merchant eq "EVERY")) {
    $sth->bind_columns(undef,\($trans_date, $username, $operation, $finalstatus, $count, $sum, $curr));
  }
  else {
    $sth->bind_columns(undef,\($trans_date, $operation, $finalstatus, $acct_code, $acct_code2, $acct_code3, $acct_code4, $count, $sum, $curr));
  }

  while ($sth->fetch) {
    #print " ";
    if ($format =~ /chargeback/) {
      if ($cardtype eq "vi") {
        $cardtype = "VISA";
      }
      elsif ($cardtype eq "mc") {
        $cardtype = "MSTR";
      }
      elsif ($cardtype eq "am") {
        $cardtype = "AMEX";
      }
      elsif ($cardtype eq "ds") {
         $cardtype = "DSCR";
      }
      else {
        $cardtype = "OTHER";
      }
      $operation = "postauth";
      $finalstatus = 'success';
    }

    if ($curr ne "") {
      $currency{$curr} = 1;
    }

    if (substr($trans_date,0,8) >= $end) {
      next;
    }

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

    $count{"$trans_date$operation$finalstatus$curr"} += $count;
    $ac_count{"$trans_date$operation$finalstatus$acct_code$curr"} += $count;
    $ac2_count{"$trans_date$operation$finalstatus$acct_code2$curr"} += $count;
    $ac3_count{"$trans_date$operation$finalstatus$acct_code3$curr"} += $count;
    $ac4_count{"$trans_date$operation$finalstatus$acct_code4$curr"} += $count;
    $ct_count{"$trans_date$operation$finalstatus$cardtype$curr"} += $count;

    $count4{"$trans_date$operation$finalstatus$acct_code4$curr"} += $count;
    $ac_count4{"$trans_date$operation$finalstatus$acct_code$acct_code4$curr"} += $count;
    $ac2_count4{"$trans_date$operation$finalstatus$acct_code2$acct_code4$curr"} += $count;
    $ac3_count4{"$trans_date$operation$finalstatus$acct_code3$acct_code4$curr"} += $count;

    $ac_count_ct{"$trans_date$operation$finalstatus$acct_code$cardtype$curr"} += $count;
    $ac2_count_ct{"$trans_date$operation$finalstatus$acct_code2$cardtype$curr"} += $count;
    $ac3_count_ct{"$trans_date$operation$finalstatus$acct_code3$cardtype$curr"} += $count;

    $ac_sum{"$trans_date$operation$finalstatus$acct_code$curr"} += $sum;
    $ac2_sum{"$trans_date$operation$finalstatus$acct_code2$curr"} += $sum;
    $ac3_sum{"$trans_date$operation$finalstatus$acct_code3$curr"} += $sum;
    $ac4_sum{"$trans_date$operation$finalstatus$acct_code4$curr"} += $sum;
    $ct_sum{"$trans_date$operation$finalstatus$cardtype$curr"} += $sum;

    $ac_sum4{"$trans_date$operation$finalstatus$acct_code$acct_code4$curr"} += $sum;
    $ac2_sum4{"$trans_date$operation$finalstatus$acct_code2$acct_code4$curr"} += $sum;
    $ac3_sum4{"$trans_date$operation$finalstatus$acct_code3$acct_code4$curr"} += $sum;

    $ac_sum_ct{"$trans_date$operation$finalstatus$acct_code$cardtype$curr"} += $sum;
    $ac2_sum_ct{"$trans_date$operation$finalstatus$acct_code2$cardtype$curr"} += $sum;
    $ac3_sum_ct{"$trans_date$operation$finalstatus$acct_code3$cardtype$curr"} += $sum;

    $sum{"$trans_date$operation$finalstatus$curr"} += $sum;
    $sum4{"$trans_date$operation$finalstatus$acct_code4$curr"} += $sum;

    $ac_totalcnt{"TOTAL$operation$finalstatus$acct_code$curr"} += $count;
    $ac_totalsum{"TOTAL$operation$finalstatus$acct_code$curr"} += $sum;
    $ac2_totalcnt{"TOTAL$operation$finalstatus$acct_code2$curr"} += $count;
    $ac2_totalsum{"TOTAL$operation$finalstatus$acct_code2$curr"} += $sum;
    $ac3_totalcnt{"TOTAL$operation$finalstatus$acct_code3$curr"} += $count;
    $ac3_totalsum{"TOTAL$operation$finalstatus$acct_code3$curr"} += $sum;
    $ct_totalcnt{"TOTAL$operation$finalstatus$cardtype$curr"} += $count;
    $ct_totalsum{"TOTAL$operation$finalstatus$cardtype$curr"} += $sum;

    $ac_totalcnt4{"TOTAL$operation$finalstatus$acct_code$acct_code4$curr"} += $count;
    $ac_totalsum4{"TOTAL$operation$finalstatus$acct_code$acct_code4$curr"} += $sum;
    $ac2_totalcnt4{"TOTAL$operation$finalstatus$acct_code2$acct_code4$curr"} += $count;
    $ac2_totalsum4{"TOTAL$operation$finalstatus$acct_code2$acct_code4$curr"} += $sum;
    $ac3_totalcnt4{"TOTAL$operation$finalstatus$acct_code3$acct_code4$curr"} += $count;
    $ac3_totalsum4{"TOTAL$operation$finalstatus$acct_code3$acct_code4$curr"} += $sum;

    $totalcnt{"TOTAL$operation$finalstatus$curr"} += $count;
    $totalsum{"TOTAL$operation$finalstatus$curr"} += $sum;

    $totalcnt4{"TOTAL$operation$finalstatus$acct_code4$curr"} += $count;
    $totalsum4{"TOTAL$operation$finalstatus$acct_code4$curr"} += $sum;

    $maxsum1{$curr} = $sum{$trans_date . $operation . "success" . $curr} + $sum{$trans_date . $operation . "badcard" . $curr};

    if ($maxsum1{$curr} > $maxsum{$curr}) {
      $maxsum{$curr} = $maxsum1{$curr};
    }

    $maxcnt1{$curr} = $count{"$trans_date$operation$finalstatus$curr"};

    if ($maxcnt1{$curr} > $maxcnt{$curr}) {
      $maxcnt{$curr} = $maxcnt1{$curr};
    }
  }
  $sth->finish;
  $dbh->disconnect;

  $reports::end = time();
  my $etime = $reports::end - $reports::start;
  if ($reports::debug == 1) {
    open(DEBUG,">>/home/p/pay1/database/debug/report_queries.txt");
    my $now = gmtime(time());
    print DEBUG "$now, ELAPSE:$etime, IP:$ENV{'REMOTE_ADDR'}, UN:$ENV{'REMOTE_USER'}, PID:$$, ";
    print DEBUG "QSTR:$qstr";
    print DEBUG "\n";
    close(DEBUG); 

    #use Datalog
    my $logger = new PlugNPay::Logging::DataLog({collection => 'reports'});
    my %data  = ();
    $data{DATE}   = $now;
    $data{ELAPSE} = $etime;
    $data{IP}     = $ENV{'REMOTE_ADDR'};
    $data{UN}     = $ENV{'REMOTE_USER'};
    $data{PID}    = $$;
    $data{QSTR}   = $qstr;
    $logger->log(\%data);
  }


  if ($fraud_config ne "") {
    $operation = "auth";
    $finalstatus = "fraud";

    my $start1 = $start . "000000";
    my $end1 = $end . "000000";

    my @placeholder;
    my $qstr = "SELECT trans_time, acct_code, acct_code2, acct_code3, subacct";
    $qstr .= " FROM fraud_log";
    $qstr .= " WHERE trans_time>=? AND trans_time<?";
    push(@placeholder, $start1, $end1); 
 
    if ((exists $altaccts{$username}) && ($subacct ne "")) {
      my ($temp);
      foreach my $var ( @{ $altaccts{$username} } ) {
        $temp .= "?,";
        push(@placeholder, $var);
      }
      chop $temp;
      $qstr .= " AND username IN ($temp)";
    }
    else {
      $qstr .= " AND username=?";
      push(@placeholder, $username);
    }

    if ($subacct ne "") {
      $qstr .= "and subacct=?";
      push(@placeholder, $subacct);
    }

    #print "QSTR:$qstr:<p>\n";
    #exit;

    my $dbh = &miscutils::dbhconnect("fraudtrack");

    my $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
    $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
    while (my ($trans_time, $acct_code, $acct_code2, $acct_code3, $subacct) = $sth->fetchrow) {
      #print "A:$trans_time, $acct_code, $acct_code2, $acct_code3<br>\n";
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

      $ac_count{"$trans_date$operation$finalstatus$acct_code"}++;
      $ac2_count{"$trans_date$operation$finalstatus$acct_code2"}++;
      $ac3_count{"$trans_date$operation$finalstatus$acct_code3"}++;
      $count{"$trans_date$operation$finalstatus"}++;

      $countSA{"$trnas_date$operation$finalstatus$subacct"}++;

#      $month = substr($trans_date,0,6);
#      $months{$month} = $month;

#      $ac_count{"$month$operation$finalstatus$acct_code"}++;
#      $ac2_count{"$month$operation$finalstatus$acct_code2"}++;
#      $ac3_count{"$month$operation$finalstatus$acct_code3"}++;
#      $count{"$month$operation$finalstatus"}++;

#      $subaccts{$subacct} = 1;
#      $countSA{"$month$operation$finalstatus$subacct"}++;

      $ac_totalcnt{"TOTAL$operation$finalstatus$acct_code"}++;
      $ac2_totalcnt{"TOTAL$operation$finalstatus$acct_code2"}++;
      $ac3_totalcnt{"TOTAL$operation$finalstatus$acct_code3"}++;
      $totalcnt{"TOTAL$operation$finalstatus"}++;
      $aaaa = $totalcnt{"TOTAL$operation$finalstatus"};

      #print "AAA:$aaaa:$operation:$finalstatus<br>\n";
    }
    $sth->finish;
    $dbh->disconnect;
  }

  #if ($username =~ /icgcrossco/) {
  #  foreach my $key (sort keys %countSA) {
  #    print "KEY:$key:$countSA{$key}<br>\n";
  #  }
  #}

  $noacct_code{'1'} = "";

}

sub sales {
  if ($processor eq "cybercash") {
    $rowspan = 3;
  }
  else {
    $rowspan = 10;
  }

  foreach my $curr (sort keys %currency) {
  print "<div align=center><table border=1 cellspacing=0 cellpadding=2 width=650>\n";
  print "<tr><th colspan=4 bgcolor=\"#99CCFF\">Sales Volume (\$ $curr)</th></tr>\n";
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

  my $max = $maxsum{$curr};
  my $maxmonth = $maxmosum{$curr};

  foreach my $key (sort keys %display) {
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

      $tot_auths =  $values{$date . "authsuccess" . $acct_code . $curr} + $values{$date . "authbadcard" . $acct_code . $curr};
      $width = sprintf("%d",$values{$date . "authsuccess" . $acct_code . $curr} * 300 / $max);
      $width2 = sprintf("%d",$values{$date . "voidsuccess" . $acct_code . $curr} * 300 / $max);
      $width3 = sprintf("%d",$values{$date . "returnsuccess" . $acct_code . $curr} * 300 / $max);
      $width4 = sprintf("%d",$values{$date . "postauthsuccess" . $acct_code . $curr} * 300 / $max);
      $width5 = sprintf("%d",$tot_auths * 300 / $max);
      $width6 = sprintf("%d",$values4{$date . "voidsuccess" . $acct_code . "avs_mismatch" . $curr} * 300 / $max);
      $width7 = sprintf("%d",$values4{$date . "voidsuccess" . $acct_code . "cvv_mismatch" . $curr} * 300 / $max);
      $width8 = sprintf("%d",$values4{$date . "authbadcard" . $acct_code . $curr} * 300 / $max);

        if ($width <= 0) {
          $width = 1;
        }
        if ($width1 <= 0) {
          $width1 = 1;
        }

#if ($ENV{'REMOTE_ADDR'} eq "71.125.61.125") {
#  $test = $values{$date . "authsuccess" . $acct_code . $curr};
#  print "Test:$test<br>\n";
#}
        $values{$date . "netauthsuccess" . $acct_code . $curr} = $values{$date . "authsuccess" . $acct_code . $curr}
                        - $values{$date . "voidsuccess" . $acct_code . $curr};
        $width9 = sprintf("%d",$values{$date . "netauthsuccess" . $acct_code . $curr} * 300 / $max);

        $values{$date . "netauthsuccess" . $acct_code . $curr} = sprintf("%.2f",$values{$date . "netauthsuccess" . $acct_code . $curr});
        $values{$date . "netauthsuccess" . $acct_code . $curr} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$date . "netauthsuccess" . $acct_code . $curr} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

 
        $values{$date . "voidsuccess" . $acct_code . $curr} = $values{$date . "voidsuccess" . $acct_code . $curr}
                        - $values{$date . "voidsuccess" . $acct_code . "avs_mismatch" . $curr}
                        - $values{$date . "voidsuccess" . $acct_code . "cvv_mismatch" . $curr};

        $values{$date . "voidsuccess" . $acct_code . $curr} = sprintf("%.2f",$values{$date . "voidsuccess" . $acct_code . $curr});
        $values{$date . "voidsuccess" . $acct_code . $curr} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$date . "voidsuccess" . $acct_code . $curr} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;
 
        $values{$date . "authsuccess" . $acct_code . $curr} = $values{$date . "authsuccess" . $acct_code . $curr}
                        - $values{$date . "voidsuccess" . $acct_code . "avs_mismatch" . $curr}
                        - $values{$date . "voidsuccess" . $acct_code . "cvv_mismatch" . $curr};

        $values{$date . "authsuccess" . $acct_code . $curr} = sprintf("%.2f",$values{$date . "authsuccess" . $acct_code . $curr});
        $values{$date . "authsuccess" . $acct_code . $curr} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$date . "authsuccess" . $acct_code . $curr} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

        $values{$date . "authbadcard" . $acct_code . $curr} = $values{$date . "authbadcard" . $acct_code . $curr}; 
        $values{$date . "authbadcard" . $acct_code . $curr} = sprintf("%.2f",$values{$date . "authbadcard" . $acct_code . $curr});
        $values{$date . "authbadcard" . $acct_code . $curr} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$date . "authbadcard" . $acct_code . $curr} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;


        $values{$date . "postauthsuccess" . $acct_code . $curr} = sprintf("%.2f",$values{$date . "postauthsuccess" . $acct_code . $curr});

        $net_to_bank = $values{$date . "postauthsuccess" . $acct_code . $curr} - $values{$date . "returnsuccess" . $acct_code . $curr};
        $net_to_bank = sprintf("%.2f",$net_to_bank);
        $net_to_bank =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $net_to_bank =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;


        $values{$date . "postauthsuccess" . $acct_code . $curr} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$date . "postauthsuccess" . $acct_code . $curr} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

        $values{$date . "returnsuccess" . $acct_code . $curr} = sprintf("%.2f",$values{$date . "returnsuccess" . $acct_code . $curr} + $values{$date . "returnpending" . $acct_code . $curr});
        $values{$date . "returnsuccess" . $acct_code . $curr} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$date . "returnsuccess" . $acct_code . $curr} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

        $values4{$date . "voidsuccess" . $acct_code . "avs_mismatch" . $curr} = sprintf("%.2f",$values4{$date . "voidsuccess" . $acct_code . "avs_mismatch" . $curr});
        $values4{$date . "voidsuccess" . $acct_code . "avs_mismatch" . $curr} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values4{$date . "voidsuccess" . $acct_code . "avs_mismatch" . $curr} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

        $values4{$date . "voidsuccess" . $acct_code . "cvv_mismatch" . $curr} = sprintf("%.2f",$values4{$date . "voidsuccess" . $acct_code . "cvv_mismatch" . $curr});
        $values4{$date . "voidsuccess" . $acct_code . "cvv_mismatch" . $curr} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values4{$date . "voidsuccess" . $acct_code . "cvv_mismatch" . $curr} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

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
        print "<td align=right><font size=-1>\$$values{$date . \"authsuccess\" . $acct_code . $curr}</font></td>\n";
        print "<td align=left><img src=\"/images/green.gif\" height=8 width=$width></td>";
        print "</tr>\n";

        print "<tr>\n";
        print "<td><font size=-1> Declined</font></td>\n";
        print "<td align=right><font size=-1>\$$values{$date . \"authbadcard\" . $acct_code . $curr}</font></td>\n";
        print "<td align=left><img src=\"/images/red.gif\" height=8 width=$width8></td>";
        print "</tr>\n";

        print "<tr>\n";
        print "<td><font size=-1> --- AVS Mismatch</font></td>\n";
        print "<td align=right><font size=-1>\$$values4{$date . \"voidsuccess\" . $acct_code . \"avs_mismatch\" . $curr}</font></td>\n";
        print "<td align=left><img src=\"/images/red.gif\" height=8 width=$width6></td>";
        print "</tr>\n";

        print "<tr>\n";
        print "<td><font size=-1> --- CVV Mismatch</font></td>\n";
        print "<td align=right><font size=-1>\$$values4{$date . \"voidsuccess\" . $acct_code . \"cvv_mismatch\" . $curr}</font></td>\n";
        print "<td align=left><img src=\"/images/red.gif\" height=8 width=$width7></td>";
        print "</tr>\n";

        if ($processor ne "cybercash") {
          print "<tr><td><font size=-1>Voids</font></td>";
          print "<td align=right><font size=-1>\$$values{$date . \"voidsuccess\" . $acct_code . $curr}</font></td>\n";
          print "<td align=left><img src=\"/images/red.gif\" height=8 width=$width2></td>";
          print "</tr>\n";

          print "<tr><td><font size=-1>Net Success (Success - Voids)</font></td>"; 
          print "<td align=right><font size=-1>\$$values{$date . \"netauthsuccess\" . $acct_code . $curr}</font></td>\n";
          print "<td align=left><img src=\"/images/green.gif\" height=8 width=$width9></td>";
          print "</tr>\n";

          print "<tr><td><font size=-1>Returns</font></td>";
          print "<td align=right><font size=-1>\$$values{$date . \"returnsuccess\" . $acct_code . $curr}</font></td>\n";
          print "<td align=left><img src=\"/images/red.gif\" height=8 width=$width3></td>";
          print "</tr>\n";
          print "<tr><td><font size=-1>Post Auths</font></td>";
          print "<td align=right><font size=-1>\$$values{$date . \"postauthsuccess\" . $acct_code . $curr}</font></td>\n";
          print "<td align=left><img src=\"/images/green.gif\" height=8 width=$width4></td>";
          print "</tr>\n";

          print "<tr><td><font size=-1>Net to Bank</font></td>";
          print "<td align=right><font size=-1>\$$net_to_bank</font></td>\n";
          print "<td align=left></td>";
          print "</tr>\n";
        }
      }
  }

  $total_net_to_bank = $totalsum{'TOTALpostauthsuccess' . $curr} - $totalsum{'TOTALreturnsuccess' . $curr};
  $total_net_to_bank = sprintf("%.2f",$total_net_to_bank);
  $total_net_to_bank =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $total_net_to_bank =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

  $totalsum{'TOTALauth' . $curr} = sprintf("%.2f",$totalsum{'TOTALauthsuccess' . $curr} + $totalsum{'TOTALauthbadcard' . $curr});
  $totalsum{'TOTALauth' . $curr} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{'TOTALauth' . $curr} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

  $totalsum{'TOTALnetauthsuccess' . $curr} = sprintf("%.2f",$totalsum{'TOTALauthsuccess' . $curr} - $totalsum{'TOTALvoidsuccess' . $curr});

  $totalsum{'TOTALvoidsuccess' . $curr} = sprintf("%.2f",$totalsum{'TOTALvoidsuccess' . $curr} - $totalsum4{'TOTALvoidsuccessavs_mismatch' . $curr}- $totalsum4{'TOTALvoidsuccesscvv_mismatch' . $curr});

  $totalsum{'TOTALauthbadcard' . $curr} = sprintf("%.2f",$totalsum{'TOTALauthbadcard' . $curr});

  $totalsum{'TOTALvoidsuccess' . $curr} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{'TOTALvoidsuccess' . $curr} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

  $totalsum{'TOTALauthbadcard' . $curr} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{'TOTALauthbadcard' . $curr} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

  $totalsum{'TOTALauthsuccess' . $curr} = $totalsum{'TOTALauthsuccess' . $curr}
           - $totalsum4{'TOTALvoidsuccessavs_mismatch' . $curr} 
           - $totalsum4{'TOTALvoidsuccesscvv_mismatch' . $curr};

  $totalsum4{'TOTALvoidsuccessavs_mismatch' . $curr} = sprintf("%.2f",$totalsum4{'TOTALvoidsuccessavs_mismatch' . $curr});
  $totalsum4{'TOTALvoidsuccessavs_mismatch' . $curr} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum4{'TOTALvoidsuccessavs_mismatch' . $curr} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

  $totalsum4{'TOTALvoidsuccesscvv_mismatch' . $curr} = sprintf("%.2f",$totalsum4{'TOTALvoidsuccesscvv_mismatch' . $curr});
  $totalsum4{'TOTALvoidsuccesscvv_mismatch' . $curr} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum4{'TOTALvoidsuccesscvv_mismatch' . $curr} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

  $totalsum{'TOTALauthsuccess' . $curr} = sprintf("%.2f",$totalsum{'TOTALauthsuccess' . $curr});
  $totalsum{'TOTALauthsuccess' . $curr} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{'TOTALauthsuccess' . $curr} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;
  $totalsum{'TOTALpostauthsuccess' . $curr} = sprintf("%.2f",$totalsum{'TOTALpostauthsuccess' . $curr});
  $totalsum{'TOTALpostauthsuccess' . $curr} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{'TOTALpostauthsuccess' . $curr} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

  $totalsum{'TOTALreturnsuccess' . $curr} = sprintf("%.2f",$totalsum{'TOTALreturnsuccess' . $curr} + $totalsum{'TOTALreturnpending' . $curr});
  $totalsum{'TOTALreturnsuccess' . $curr} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{'TOTALreturnsuccess' . $curr} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

  print "<tr>\n";
  print "<th align=left rowspan=$rowspan><font size=-1>Totals</font></th><td><font size=-1>Total Auths.</font></td>\n";
  print "<td align=right><font size=-1>\$$totalsum{'TOTALauth' . $curr}</font></td>\n";
  print "<td align=left></td>";
  print "</tr>\n";

  print "<tr>\n";
  print "<td><font size=-1> Success</font></td>\n";
  print "<td align=right><font size=-1>\$$totalsum{'TOTALauthsuccess' . $curr}</font></td>\n";
  print "<td align=left></td>";
  print "</tr>\n";

  print "<tr>\n";
  print "<td><font size=-1> Declined</font></td>\n";
  print "<td align=right><font size=-1>\$$totalsum{'TOTALauthbadcard' . $curr}</font></td>\n";
  print "<td align=left></td>";
  print "</tr>\n";

  print "<tr>\n";
  print "<td><font size=-1> --- AVS Mismatch</font></td>\n";
  print "<td align=right><font size=-1>\$$totalsum4{'TOTALvoidsuccessavs_mismatch' . $curr}</font></td>\n";
  print "<td align=left></td>";
  print "</tr>\n";

  print "<tr>\n";
  print "<td><font size=-1> --- CVV Mismatch</font></td>\n";
  print "<td align=right><font size=-1>\$$totalsum4{'TOTALvoidsuccesscvv_mismatch' . $curr}</font></td>\n";
  print "<td align=left></td>";
  print "</tr>\n";
  if ($processor ne "cybercash") {
    print "<tr><td><font size=-1>Voids</font></td>";
    print "<td align=right><font size=-1>\$$totalsum{'TOTALvoidsuccess' . $curr}</font></td>\n";
    print "<td align=left></td>";
    print "</tr>\n";
    print "<tr><td><font size=-1>Net Success (Success - Voids)</font></td>";
    print "<td align=right><font size=-1>\$$totalsum{'TOTALnetauthsuccess' . $curr}</font></td>\n";
    print "<td align=left></td>";
    print "</tr>\n";

    print "<tr><td><font size=-1>Returns</font></td>";
    print "<td align=right><font size=-1>\$$totalsum{'TOTALreturnsuccess' . $curr}</font></td>\n";
    print "<td align=left></td>";
    print "</tr>\n";
    print "<tr><td><font size=-1>Post Auths</font></td>";
    print "<td align=right><font size=-1>\$$totalsum{'TOTALpostauthsuccess' . $curr}</font></td>\n";
    print "<td align=left></td>";
    print "</tr>\n";

    print "<tr><td><font size=-1>Net to Bank</font></td>";
    print "<td align=right><font size=-1>\$$total_net_to_bank</font></td>\n";
    print "<td align=left> <!-- Throughput: $throughput\% --> </td>";
    print "</tr>\n";

  }

  print "</table></div>\n";
  }

}


sub trans {
  my $max = $maxcnt;

  foreach my $curr (sort keys %currency) {

  print "<p><div align=center><p><table border=1 cellspacing=0 cellpadding=2 width=650>\n";
  print "<tr><th colspan=5 bgcolor=\"#99CCFF\">Transaction Volume - $curr</th></tr>\n";
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

  foreach my $key (sort keys %display) {
    $acct_code = $display{$key};
    $label = $acct_code;
    if ($label =~ /^(none|none2|none3)$/) {
      $label = "None";
    }

    if ($sortorder ne "") {
      print "<tr><th>Acct Code:</th><th>$label</th></tr>\n";
    }

    print "<tr>";
    print "  <th align=left><nobr><font size=-1> Date </font></nobr></th>";
    print "  <th align=left><nobr><font size=-1> Type </font></nobr></th>";
    print "  <th align=center><nobr><font size=-1> Qty </font></nobr></th>";
    print "  <th align=center><nobr><font size=-1> % Declined </font></nobr></th>";
    print "  <th align=left><nobr><font size=-1> Graph </font></nobr></th>";
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

      $total_auths = $values{$date . "authsuccess" . $acct_code . $curr} +
                     $values{$date . "authbadcard" . $acct_code . $curr} +
                     $values{$date . "authfraud" . $acct_code . $curr};

      if ($total_auths < 1) {
        $total_auths = .00001;
      }

      $values{$date . "returnsuccess" . $acct_code} += $values{$date . "returnpending" . $acct_code . $curr};

      my @totals = ($total_auths,$values{$date . "authsuccess" . $acct_code},$values{$date . "authbadcard" . $acct_code . $curr},
                    $values{$date . "authfraud" . $acct_code},$values{$date . "voidsuccess" . $acct_code . $curr},
                    $values{$date . "returnsuccess" . $acct_code},$values{$date . "postauthsuccess" . $acct_code . $curr}
                    );

      for($j=0; $j<=6; $j++) {
        $width[$j] = sprintf("%d",$totals[$j] * 125 / $max);
        if ($width[$j] <= 0) {
          $width[$j] = 1;
        }
      }

      if ($values{$date . "authsuccess" . $acct_code} > 0) {
        $avgticket = sprintf("%0.2f",$sums{$date . "authsuccess" . $acct_code . $curr}/$values{$date . "authsuccess" . $acct_code . $curr});
      }

      $total_auths_summ += $total_auths;
      print "<tr>\n";
      print "  <th align=left rowspan=$rows><nobr><font size=-1>$datestr<br>Avg: \$$avgticket</font></nobr></th>\n";
      print "  <td><nobr><font size=-1>Total Auth Attempts</font></nobr></td>\n";
      printf ("  <td align=right><nobr><font size=-1>%2d</font></nobr></td>\n",$total_auths);
      print "  <td align=center><nobr><font size=-1>NA</font></nobr></td>\n";
      print "  <td align=left><img src=\"/images/blue.gif\" height=8 width=$width[0]></td>\n";
      print "</tr>\n";

      print "<tr>\n";
      print "  <td><nobr><font size=-1> Successful Auth</font></nobr></td>\n";
      my $a = $date . "authsuccess" . $acct_code . $curr;
      print "  <td align=right><nobr><font size=-1>$values{$a}</font></nobr></td>\n";
      #print "  <td align=center><nobr><font size=-1>NA</font></nobr></td>\n";
      printf("  <td align=right><nobr><font size=-1>%.1f \%</font></nobr></td>\n", ($values{$a}/$total_auths)*100);
      print "  <td align=left><img src=\"/images/green.gif\" height=8 width=$width[1]></td>\n";
      print "</tr>\n";

      $trans_auth_success_grandtotal += $values{$a};
      print "<tr>\n";
      print "  <td><nobr><font size=-1> Declined Auth - Badcard</font></nobr></td>\n";
      $a = $date . "authbadcard" . $acct_code . $curr;
      printf("  <td align=right><nobr><font size=-1>%.0f</font></nobr></td>\n", $values{$a});
      printf("  <td align=right><nobr><font size=-1>%.1f \%</font></nobr></td>\n", ($values{$a}/$total_auths)*100);
      print "  <td align=left><img src=\"/images/red.gif\" height=8 width=$width[2]></td>\n";
      print "</tr>\n";

      $trans_auth_badcard_grandtotal += $values{$a};
      print "<tr>\n";
      print "  <td><nobr><font size=-1> Declined Auth - Fraud Screen</font></nobr></td>\n";
      $a = $date . "authfraud" . $acct_code . $curr;
      printf("  <td align=right><nobr><font size=-1>%.0f</font></nobr></td>\n", $values{$a});
      printf("  <td align=right><nobr><font size=-1>%.1f \%</font></nobr></td>\n", ($values{$a}/$total_auths)*100);
      print "  <td align=left><img src=\"/images/red.gif\" height=8 width=$width[3]></td>\n";
      print "</tr>\n";

      $trans_auth_fraud_grandtotal += $values{$a};
      print "<tr>\n";
      print "  <td><nobr><font size=-1>Voids</font>\n";
      if ($detailflag ==1 ) {
        print "<table border=1 width=\"100%\">\n";
        foreach my $reason (sort keys %acct_code4) {
          if ($reason =~ /\.cg/) {
            next;
          }
          print "<tr>\n";
          print "  <td><nobr>$reason</nobr></td>\n";
          print "  <td align=right><nobr>$ac4_count{$date . \"voidsuccess\" . $reason . $curr}</nobr></td>\n";
          print "</tr>\n";
        }
        print "</table>\n";
      }
      print "</nobr></td>\n";
      $a = $date . "voidsuccess" . $acct_code . $curr;
      printf("  <td align=right><nobr><font size=-1>%.0f</font></nobr></td>\n", $values{$a});
      print "  <td align=center><nobr><font size=-1>NA</font></nobr></td>\n";
      print "  <td align=left><img src=\"/images/red.gif\" height=8 width=$width[4]></td>\n";
      print "</tr>\n";

      $trans_void_success_grandtotal += $values{$a};
      print "<tr>\n";
      print "  <td><nobr><font size=-1>Returns</font>\n";
      if ($detailflag ==1 ) {
        print "<table border=1 width=\"100%\">\n";
        foreach my $reason (sort keys %acct_code4) {
          if ($reason =~ /\.cg/) {
            next;
          }
          print "<tr>\n";
          print "  <td><nobr>$reason</nobr></td>\n";
          print "  <td align=right><nobr>$ac4_count{$date . \"returnsuccess\" . $reason . $curr}</nobr></td>\n";
          print "</tr>\n";
        }
        print "</table>\n";
      }
      print "</nobr></td>\n";
      $a = $date . "returnsuccess" . $acct_code . $curr;
      printf("  <td align=right><nobr><font size=-1>%.0f</font></nobr></td>\n", $values{$a});
      print "  <td align=center><nobr><font size=-1>NA</font></nobr></td>\n";
      print "  <td align=left><img src=\"/images/red.gif\" height=8 width=$width[5]></td>\n";
      print "</tr>\n";

      $trans_retn_success_grandtotal += $values{$a};
      print "<tr>\n";
      print "  <td><nobr><font size=-1>Successful Post Auths</font></nobr></td>\n";
      $a = $date . "postauthsuccess" . $acct_code . $curr;
      printf("  <td align=right><nobr><font size=-1>%.0f</font></nobr></td>\n", $values{$a});
      print "  <td align=center><nobr><font size=-1>NA</font></nobr></td>\n";
      print "  <td align=left><img src=\"/images/green.gif\" height=8 width=$width[6]></td>\n";
      print "</tr>\n";
      $trans_post_success_grandtotal += $values{$a};
    }
    if ($total_auths_summ < 1) {
      $total_auths_summ = 0.0001;
    }
    print "<tr>\n";
    print "  <th align=left rowspan=8><nobr><font size=-1>Summary<br></font></nobr></th>\n";
    print "  <td><nobr><font size=-1>Total Auth Attempts</font></nobr></td>\n";
    printf ("  <td align=right><nobr><font size=-1>%2d</font></nobr></td>\n",$total_auths_summ);
    print "  <td align=center><nobr><font size=-1>NA</font></nobr></td>\n";
    print "  <td align=left><nobr>&nbsp;</nobr></td>\n";
    print "</tr>\n";

    print "<tr>\n";
    print "  <td><nobr><font size=-1>Successful Auth</font></nobr></td>\n";
    print "  <td align=right><nobr><font size=-1>$trans_auth_success_grandtotal</font></nobr></td>\n";
    printf("  <td align=right><nobr><font size=-1>%.1f \%</font></nobr></td>\n", ($trans_auth_success_grandtotal/$total_auths_summ)*100);
    #print "  <td align=center><nobr><font size=-1>NA</font></nobr></td>\n";
    print "  <td align=left><nobr>&nbsp;</nobr></td>\n";
    print "</tr>\n";

    print "<tr>\n";
    print "  <td><nobr><font size=-1>Declined Auth - Badcard</font></nobr></td>\n";
    printf("  <td align=right><nobr><font size=-1>%.0f</font></nobr></td>\n", $trans_auth_badcard_grandtotal);
    printf("  <td align=right><nobr><font size=-1>%.1f \%</font></nobr></td>\n", ($trans_auth_badcard_grandtotal/$total_auths_summ)*100);
    print "  <td align=left><nobr>&nbsp;</nobr></td>\n";
    print "</tr>\n";

    print "<tr>\n";
    print "  <td><nobr><font size=-1>Declined Auth - Fraud Screen</font></nobr></td>\n";
    printf("  <td align=right><nobr><font size=-1>%.0f</font></nobr></td>\n", $trans_auth_fraud_grandtotal);
    printf("  <td align=right><nobr><font size=-1>%.1f \%</font></nobr></td>\n", ($trans_auth_fraud_grandtotal/$total_auths_summ)*100);
    print "  <td align=left><nobr>&nbsp;</nobr></td>\n";
    print "</tr>\n";

    print "<tr>\n";
    print "  <td><nobr><font size=-1>Voids</font>\n";
    if ($detailflag ==1 ) {
      print "<table border=1 width=\"100%\">\n";
      foreach my $reason (sort keys %acct_code4) {
        if ($reason =~ /\.cg/) {
          next;
        }
        print "<tr>\n";
        print "  <td><nobr>$reason</nobr></td>\n";
        print "  <td align=right><nobr>$totalcnt4{\"TOTALvoidsuccess\" . $reason . $curr}</nobr></td>\n";
        print "</tr>\n";
      }
      print "</table>\n";
    }
    print "</nobr></td>\n";
    printf("  <td align=right><nobr><font size=-1>%.0f</font></nobr></td>\n", $trans_void_success_grandtotal);
    printf("  <td align=right><nobr><font size=-1>%.1f \%</font></nobr></td>\n", ($trans_void_success_grandtotal/$total_auths_summ)*100);
    #print "  <td align=center><nobr><font size=-1>NA</font></nobr></td>\n";
    print "  <td align=left><nobr>&nbsp;</nobr></td>\n";
    print "</tr>\n";

    print "<tr>";
    print "  <td><nobr><font size=-1>Returns</font>\n";
    if ($detailflag ==1 ) {
      print "<table border=1 width=\"100%\">\n";
      foreach my $reason (sort keys %acct_code4) {
        if ($reason =~ /\.cg/) {
          next;
        }
        my $a = $totalcnt4{"TOTALreturnsuccess" . $reason . $curr} + $totalcnt4{"TOTALreturnpending" . $reason . $curr};
        print "<tr>\n";
        print "  <td><nobr>$reason</nobr></td>\n";
        print "  <td align=right><nobr>$a</nobr></td>\n";
        print "</tr>\n";
      }
      print "</table>\n";
    }
    print "</nobr></td>\n";
    printf("  <td align=right><nobr><font size=-1>%.0f</font></nobr></td>\n", $trans_retn_success_grandtotal);
    print "  <td align=center><nobr><font size=-1>NA</font></nobr></td>\n";
    print "  <td align=left><nobr>&nbsp;</nobr></td>\n";
    print "</tr>\n";

    print "<tr>\n";
    print "  <td><nobr><font size=-1>Successful Post Auths</font></nobr></td>\n";
    printf("  <td align=right><nobr><font size=-1>%.0f</font></nobr></td>\n", $trans_post_success_grandtotal);
    printf("  <td align=right><nobr><font size=-1>%.1f \%</font></nobr></td>\n", ($trans_post_success_grandtotal/$total_auths_summ)*100);
    #print "  <td align=center><nobr><font size=-1>NA</font></nobr></td>\n";
    print "  <td align=left><nobr>&nbsp;</nobr></td>\n";
    print "</tr>\n";

    print "<tr>\n";
    print "  <td><nobr><font size=-1>Chargebacks</font></nobr></td>\n";
    printf("  <td align=right><nobr><font size=-1>%.0f</font></nobr></td>\n", $totcb_cnt);
    if ($trans_post_success_grandtotal > 0) {
      printf("  <td align=right><nobr><font size=-1>%.1f \%</font></nobr></td>\n", ($totcb_cnt/$trans_post_success_grandtotal)*100);
    }
    else {
      print "<td align=center><nobr><font size=-1>NA</font></nobr></td>\n";
    }
    print "  <td align=left><nobr>&nbsp;</nobr></td>\n";
    print "</tr>\n";
  }
  $trans_month = $trans_auth_success_grandtotal + $trans_auth_badcard_grandtotal + 
                 $trans_auth_fraud_grandtotal + $trans_void_success_grandtotal + $trans_retn_success_grandtotal;
  print "<tr>\n";
  print "  <th align=left colspan=2><nobr><font size=-1>TOTAL:</font></nobr></th>\n";
  printf("  <td align=right><nobr><font size=-1>%.0f</font></nobr></td>\n",$trans_month);
  print "  <td><nobr>&nbsp;</nobr></td>\n";
  print "</table></div>\n";

  }
}


sub batch_summary {
  $rowspan = 9;
  print "<div align=center><table border=1 cellspacing=1 width=650>\n";
  print "<tr><th colspan=5>Batch Summary (\$)</th></tr>\n";

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

    foreach my $acct_code (sort keys %acct_code) {
      $values{$date . "postauthsuccess" . $acct_code} = sprintf("%.2f",$values{$date . "postauthsuccess" . $acct_code});

      $net_to_bank = $values{$date . "postauthsuccess" . $acct_code} - $values{$date . "returnsuccess" . $acct_code};
      $net_to_bank = sprintf("%.2f",$net_to_bank);
      $net_to_bank =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
      $net_to_bank =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

      $values{$date . "postauthsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;

      $values{$date . "returnsuccess" . $acct_code} = sprintf("%.2f",$values{$date . "returnsuccess" . $acct_code});
      $values{$date . "returnsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;

      print "<tr><td><font size=-1>$datestr</font></td><td>$acct_code</td>";
      print "<td align=right><font size=-1>\$$values{$date . \"returnsuccess\" . $acct_code}</font></td>\n";
      print "<td align=right><font size=-1>\$$values{$date . \"postauthsuccess\" . $acct_code}</font></td>\n";
      print "<td align=right><font size=-1>\$$net_to_bank</font></td>\n";
      print "<td align=left></td>";
      print "</tr>\n";
    }
  }

  foreach my $acct_code (sort keys %acct_code) {

    $total_net_to_bank = $ac_totalsum{'TOTALpostauthsuccess'. $acct_code} - $ac_totalsum{'TOTALreturnsuccess' . $acct_code};
    $total_net_to_bank = sprintf("%.2f",$total_net_to_bank);
    $total_net_to_bank =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
    $total_net_to_bank =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

    $ac_totalsum{'TOTALpostauthsuccess' . $acct_code} = sprintf("%.2f",$ac_totalsum{'TOTALpostauthsuccess' . $acct_code});
    $ac_actotalsum{'TOTALpostauthsuccess' . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
    $ac_totalsum{'TOTALpostauthsuccess' . $acct_code} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

    $ac_totalsum{'TOTALreturnsuccess' . $acct_code} = sprintf("%.2f",$ac_totalsum{'TOTALreturnsuccess' . $acct_code});
    $ac_totalsum{'TOTALreturnsuccess' . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
    $ac_totalsum{'TOTALreturnsuccess' . $acct_code} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

    print "<tr><td><font size=-1>Totals</font></td><td>$acct_code</td>";
    print "<td align=right><font size=-1>\$$ac_totalsum{'TOTALreturnsuccess' . $acct_code}</font></td>\n";
    print "<td align=right><font size=-1>\$$ac_totalsum{'TOTALpostauthsuccess' . $acct_code}</font></td>\n";
    print "<td align=right><font size=-1>\$$total_net_to_bank</font></td>\n";
    print "</tr>\n";
  }

  $total_net_to_bank = $totalsum{'TOTALpostauthsuccess'} - $totalsum{'TOTALreturnsuccess'};
  $total_net_to_bank = sprintf("%.2f",$total_net_to_bank);
  $total_net_to_bank =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $total_net_to_bank =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

  $totalsum{'TOTALpostauthsuccess'} = sprintf("%.2f",$totalsum{'TOTALpostauthsuccess'});
  $totalsum{'TOTALpostauthsuccess'} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{'TOTALpostauthsuccess'} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

  $totalsum{'TOTALreturnsuccess'} = sprintf("%.2f",$totalsum{'TOTALreturnsuccess'});
  $totalsum{'TOTALreturnsuccess'} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
  $totalsum{'TOTALreturnsuccess'} =~ s/(\d{1})(\d{3})\,/$1\,$2\,/;

  print "<tr><td><font size=-1>Totals</font></td><td>ALL</td>";
  print "<td align=right><font size=-1>\$$totalsum{'TOTALreturnsuccess'}</font></td>\n";
  print "<td align=right><font size=-1>\$$totalsum{'TOTALpostauthsuccess'}</font></td>\n";
  print "<td align=right><font size=-1>\$$total_net_to_bank</font></td>\n";
  print "</tr>\n";

  print "</table></div>\n";
}


## Commented out, as 'tail' sub-function is overwritten further down.
#sub tail {
#  print <<EOF;
#<div align="center">
#<form  action=\"/admin/graphs.cgi\">
#<input type=submit name=submit value=\"Main Page\">
#</form>
#</div>
#
#</body>
#</html>
#EOF
#}

sub billing_tail {
  print "<div align=left>\n";
  #print "<form action=\"billing.cgi\" method=post><input type=\"mode\" value=\"mail\"></form>\n";
  #print "<a href=\"javascript:self.close();\">Close</a> | <a href=\"javascript:self.print();\">Print</a>\n";
  print "</div>\n";
  print "</body> \n";
  print "</html>\n";
}


sub report_head {
  #print "Content-Type: text/html\n\n";

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Merchant Administration Area</title>\n";
  #print "<base href=\"https://pay1.plugnpay.com\">\n";
  print "<link href=\"/css/style_reports.css\" type=\"text/css\" rel=\"stylesheet\">\n";

  print "<script type=\"text/javascript\">\n";
  print "<!-- Start Script\n";
  print "function uncheck(thisForm) {\n";
  print "  for (var k in thisForm.listval) {\n";
  print "    document.assemble.listval[k].checked = false\;\n";
  print "  }\n";
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

  print "</head>\n";

  print "<body bgcolor=\"#ffffff\">\n";

  print "<div align=center>\n";
  print "<table cellspacing=0 cellpadding=4 border=0 width=650>\n";
  print "<tr><td align=center colspan=4><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corporate Logo\"></td></tr>\n";
  print "<tr><td align=center colspan=4><font size=4 face=\"Arial,Helvetica,Univers,Zurich BT\">$merch_company</font></td></tr>\n";

  print "<tr><th align=left colspan=1 bgcolor=\"#4a7394\"><font size=-1>Report Period:</font></th><th bgcolor=\"#4a7394\" colspan=3 align=right><font size=-1>$startmonth/$startday/$startyear - $endmonth/$endday/$endyear</font></th></tr>\n";

  if ($mode eq "billing") {
    print "<tr><td align=left colspan=4><font size=3 face=\"Arial,Helvetica,Univers,Zurich BT\">\n";
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
  elsif ($company ne "") {
    print "<tr><td align=center colspan=4><font size=3 face=\"Arial,Helvetica,Univers,Zurich BT\">\n";
    #print "Graphs \& Reports<br>";
    print "$company</td></tr>\n";
  }
  print "</table>\n";
  print "</div>\n";

  print "<br>\n";
}


sub billing_head {
  #print "Content-Type: text/html\n\n";
  my $username = $ENV{"REMOTE_USER"};

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Merchant Administration Area</title>\n";
  if ($ENV{"REMOTE_USER"} =~ /northame|icommerceg/) {
    print "<base href=\"https://www.icommercegateway.com\" x=\"$username\">\n";
  }
  else {
    print "<base href=\"https://pay1.plugnpay.com\" x=\"$username\">\n";
  }
  print "<link href=\"/css/style_reports.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  
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

  print "</head>\n";

  print "<body bgcolor=\"#ffffff\">\n";
  print "<div align=center>\n";
  print "<table cellspacing=0 cellpadding=4 border=0>\n";
  print "<tr><td align=center colspan=1><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corporate Logo\"></td></tr>\n";
  print "<tr><td align=center colspan=1><font size=4 face=\"Arial,Helvetica,Univers,Zurich BT\">$merch_company</font></td></tr>\n";
  print "</table>\n";
  print "</div>\n";
  print "<div align=center>\n";
  print "<table cellspacing=0 cellpadding=4 border=0 width=500>\n";
  if ($subacct ne "") {
    print "<tr><th align=left colspan=2 bgcolor=\"#4a7394\">Statement Period:</th><th bgcolor=\"#4a7394\" colspan=3 align=right><font size=-1>$startmonth/$startday/$startyear - $endmonth/$endday/$endyear</font></th></tr>\n";
    print "<tr><th align=left colspan=3><font size=\"-1\">Pay To:</th></tr>\n";
  }
  else {
    print "<tr><th align=left colspan=2 bgcolor=\"#4a7394\">Billing Period:</th><th bgcolor=\"#4a7394\" colspan=3 align=right><font size=-1>$startmonth/$startday/$startyear - $endmonth/$endday/$endyear</font></th></tr>\n";
    print "<tr><th align=left colspan=3><font size=\"-1\">Bill To:</th></tr>\n";
  }
  print "<tr><th colspan=5 align=left>$name<br>$company<br>\n";
  if ($addr1 ne "") {
    print "$addr1<br>\n";
  }
  if ($addr2 ne "") {
    print "$addr2<br>\n";
  }
  print "$city, $state  $zip<br>$country<p>&nbsp;</th></tr>\n";

}


sub text_head {
  print "$startmonth/$startday/$startyear - $endmonth/$endday/$endyear\n";
}


sub query_cback {

  my @placeholder;
  my $qstr = "SELECT orderid,trans_date,post_date,entered_date,amount,cardtype,country,returnflag";
  $qstr .= " FROM chargeback";

  if ((exists $altaccts{$username}) && ($subacct ne "")) {
    my ($temp);
    foreach my $var ( @{ $altaccts{$username} } ) {
      $temp .= "?,";
      push(@placeholder, $var);
   }
    chop $temp;
    $qstr .= " WHERE username IN ($temp)";
  }
  else {
    $qstr .= " WHERE username=?";
    push(@placeholder, $username);
  }

  $qstr .= " AND post_date>=? AND post_date<?";
  push(@placeholder, $start, $end);

  if ($subacct ne "") {
    $qstr .= " AND subacct=?";
    push(@placeholder, $subacct);
  }
  #$qstr .= " ORDER BY trans_date";

  $i=0;
  $dbh = &miscutils::dbhconnect("fraudtrack");
  my $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  while (my ($oid,$trans_date,$post_date,$entered_date,$amount,$cardtype,$country,$returnflag) = $sth->fetchrow) {
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

  return;

  #print "CNT:$totcb_cnt<br>\n";
  if (@temp > 0) {
    my $timeadjust = (180 * 24 * 3600);
    my ($dummy1,$start,$timestr) = &miscutils::gendatetime("-$timeadjust");
    foreach my $temp (@temp) {
      chop $temp;
      my @placeholder;
      my $qstr = "SELECT substr(amount,5),orderid,card_number";
      $qstr .= " FROM operation_log";
      $qstr .= " WHERE postauthtime>=?";
      push(@placeholder, $timestr);

      if ((exists $altaccts{$username}) && ($subacct ne "")) {
        my ($temp1);
        foreach my $var ( @{ $altaccts{$username} } ) {
          $temp1 .= "?,";
          push(@placeholder, $var);
        }
        chop $temp1;
        $qstr .= " AND username IN ($temp1)";
      }
      else {
        $qstr .= " AND username=?";
        push(@placeholder, $username)
      }

      $qstr .= " AND orderid IN ($temp)";

      $qstr .= " AND postauthstatus='success'";

      my $dbh_cb = &miscutils::dbhconnect("pnpdata","","$username");

      my $sth1 = $dbh_cb->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
      $sth1->execute(@placeholder) or die "Can't execute: $DBI::errstr";
      while (my ($amount, $orderid, $cardnumber) = $sth1->fetchrow) {
        $cardtype = &checkcard($cardnumber);
        $cardtypes{$cardtype} = 1;

        #print "A:$amount, OID:$orderid, CN:$cardnumber, CT:$cardtype<br>\n";
        $tot_cbamt += $amount;
        $tot_cbamt{$cardtype} += $amount;
        #$totcb_cnt++;
        #$totcb_cnt{$cardtype}++;
        #$cbamt_type = "cbamt" . $cardtype;
        #$cbdeduct_type = "cbdeduct" . $cardtype;
        #$$cbamt_type{$oiddate{$orderid}} += $amount;
        #if ($action{$orderid} eq "R") {
        #  $$cbdeduct_type{$oiddate{$orderid}} += $amount;
        #  $tot_deductcbamt += $amount;
        #  $tot_deductcbamt{$cardtype} += $amount;
        #}
      }
      $sth1->finish;
      $dbh_cb->disconnect;
    }
  }
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

  #foreach my $key (sort keys %values) {
  #  print "$key=$values{$key}\n";
  #}

  foreach my $key (sort keys %display) {
    my $acct_code = $display{$key};
    $label = $acct_code;
    if ($label =~ /^(none|none2|none3)$/) {
      $label = "None";
    }

    foreach my $cardtype (sort keys %cardtypes) {
      foreach my $date (sort keys %dates) {
        $a = $sums{$date . 'postauthsuccess' . $acct_code . $cardtype};
        #print "AAA:$a, CT:$cardtype, DATE:$date, AC:$acct_code<br>\n";
        $trancnt{$cardtype} += $values{$date . 'postauthsuccess' . $acct_code . $cardtype};
        $transum{$cardtype} += $sums{$date . 'postauthsuccess' . $acct_code . $cardtype};
      }
    }

    if ($sortorder ne "") {
      print "<tr><th>Acct Code:</th><th>$label</th></tr>\n";
    }

    print "<div align=center><table border=1 cellspacing=1 width=650>\n";
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

    foreach my $cardtype (sort keys %cardtypes) {
      $transum{$cardtype} = sprintf("%.2f",$transum{$cardtype});
      #$transum{$cardtype} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
      $tot_cbamt{$cardtype} = sprintf("%.2f",$tot_cbamt{$cardtype});
      #$tot_cbamt{$cardtype} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
    }
    #  $cardtypes{$cardtype} = 1;
    #  $$cbamt_type{$oiddate{$orderid}} += $amount;
    #  $$cbdeduct_type{$oiddate{$orderid}} += $amount;

    foreach my $cardtype (sort keys %cardtypes) {
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

  my @placeholder;
  my $qstr = "SELECT feeid,feetype,feedesc,rate,type";
  $qstr .= " FROM billing";
  $qstr .= " WHERE username=?";
  push(@placeholder, $username);

  if ($subacct ne "") {
    $qstr .= " AND subacct=?";
    push(@placeholder, $subacct);
  }

  $dbh = &miscutils::dbhconnect("merch_info");
  my $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($db{'feeid'},$db{'feetype'},$db{'desc'},$db{'rate'},$db{'type'}));
  while ($sth->fetch) {
    #print "UN:$username, ID:$db{'feeid'},TYPE:$db{'feetype'},DESC:$db{'desc'},RATE:$db{'rate'},TYPE:$db{'type'}<br>\n";
    #if ($db{'feeid'} =~ /fraud/) {
    #  next;
    #}

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

  ####  Chargeback Info
  $qstr = "SELECT orderid,entered_date,returnflag FROM chargeback ";

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
  #$qstr .= "order by trans_date";

  #print "QSTR:$qstr<p>\n";
  #exit;

  $dbh = &miscutils::dbhconnect("fraudtrack");
  my $i=0;
  my ($temp,@temp,%cb,%oiddate,%action);
  my $sth2 = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
  $sth2->execute() or die "Can't execute: $DBI::errstr";
  while (my ($oid,$trans_date,$returnflag) = $sth2->fetchrow) {
    $dates{$trans_date} = 1;
    my ($action);
    $k++;
    $temp .= "'$oid',";
    if ($k > 990) {
      $i++;
      $k=0;
      $temp = "";
    }
    $temp[$i] = $temp;
    #($oid,$action) = split(/ /,$dboid);
    #$temp .= "'$oid',";
    $cb{$trans_date}++;
    $oiddate{$oid} = $trans_date;
    if ($returnflag == 1) {
      $action ="R";
    }
    $action{$oid} = $action;
    #print "CNT:$cb{$trans_date}, OID:$oid, ACT:$action, DATE:$trans_date, RF:$returnflag<br>\n";
  }
  $sth2->finish;
  $dbh->disconnect;

  if (@temp > 0) {
    my $timeadjust = (400 * 24 * 3600);
    my ($dummy1,$start,$timestr) = &miscutils::gendatetime("-$timeadjust");
    chop $temp;

    my @placeholder;
    $qstr = "SELECT substr(amount,5),orderid";
    $qstr .= " FROM operation_log";

    my ($qmarks,$dateArrayRef) = &miscutils::dateIn($start,$end,'0');
    $qstr .= " WHERE trans_date IN ($qmarks)";
    push(@placeholder, @$dateArrayRef);

    if (@temp > 1) {
      $qstr .= " AND (orderid IN ";
      foreach my $var (@temp) {
        chop $var;
        $qstr .= " ($var) OR orderid IN ";
      }
      $qstr = substr($qstr,0,length($qstr)-15);
      $qstr .= ")";
    }
    else {
     chop $temp[0];
     $qstr .= " AND orderid IN ($temp[0]) ";
    }

    if ((exists $altaccts{$username}) && ($subacct ne "")) {
      my ($temp);
      foreach my $var ( @{ $altaccts{$username} } ) {
        $temp .= "?,";
        push(@placeholder, $var);
      }
      chop $temp;
      $qstr .= " AND username IN ($temp) ";
    }
    else {
      $qstr .= " AND username=?";
      push(@placeholder, $username);
    }
    $qstr .= " AND authstatus='success'";
    
    #print "QSTR:$qstr<br>\n";
    #exit;

    #my (%cbamt,%action,%cb_deductamt);

    my $dbh_cb = &miscutils::dbhconnect("pnpdata","","$username");

    my $sth1 = $dbh_cb->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
    $sth1->execute(@placeholder) or die "Can't execute: $DBI::errstr";
    while (my ($amount, $orderid) = $sth1->fetchrow) {
      $cnt++;
      #print "CNT:$cnt, RUNAMT:$cbamt{$oiddate{$orderid}}, AMOUNT:$amount, DATE: $oiddate{$orderid}, ACTION:$action{$orderid}<br>\n";
      $cbamt{$oiddate{$orderid}} += $amount;
      if ($action{$orderid} eq "R") {
        $cb_deductamt{$oiddate{$orderid}} += $amount;
      }
    }
    $sth1->finish;
    $dbh_cb->disconnect;
  }

  #foreach my $key (sort keys %cbamt) {
  #  print "K:$key:$cbamt{$key}<br>\n";
  #}

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

  #print "DFFDF:$free250:\n";
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

  #$total_trans_volume_success = $totalsum{'TOTALauthsuccess'} + $totalsum{'TOTALreturnsuccess'} - $totalsum{"TOTALvoidsuccess"} + 0.0001;
  $total_trans_volume_success = $totalsum{'TOTALpostauthsuccess'};
  $total_trans_volume_success = sprintf("%0.2f",$total_trans_volume_success);

  if ($recauthfee{'rate'} eq "") {
    if ($newauthfee{'type'} eq "pertran") {
      $total_auths_new = $total_auths_trans;
    }
    else {
      $total_auths_new = sprintf("%0.2f",$totalsum{"TOTALauthsuccess"});
    }
  }
  else {
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
  }

  if ($declinedfee{'type'} eq "pertran") {
    $total_auths_decl = $totalcnt{"TOTALauthbadcard"};
    #DCP
    #$total_auths_decl = $totalcnt{"TOTALauthbadcard"} - $free250_net;
  }
  else {
    $total_auths_decl = sprintf("%0.2f",$totalsum{"TOTALauthbadcard"});
  }
  if ($fraudfee{'type'} eq "pertran") {
    $total_fraud = $totalcnt{"TOTALauthfraud"};
#print "<p>A:$total_fraud";
  }
  else {

    $total_fraud = sprintf("%0.2f",$totalsum{"TOTALauthfraud"});
#print "<p>B:$total_fraud";
  }
  if ($returnfee{'type'} eq "pertran") {
    $total_retrn = $totalcnt{"TOTALreturnsuccess"} + $totalcnt{"TOTALreturnpending"};
  }
  else {
    $total_retrn = sprintf("%0.2f",$totalsum{"TOTALreturnsuccess"} + $totalsum{"TOTALreturnpending"});
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

  my $header_text = "USERNAME\t";
  my $line_text = "$username\t";

  #print "HT:$header_text\n";

#  print "<div align=center><table border=1 cellspacing=1 width=650>\n";
#  print "<tr><th colspan=3>Billing</th></tr>\n";

  my ($line);
  if ($subacct ne "") {
  #$count{"$trans_date$operation$finalstatus"} += $count;
  #$ac_sum{"$trans_date$operation$finalstatus$acct_code"} += $sum;
    #$dates{$trans_date} = 1;

    foreach my $date (sort keys %dates) {
      my $date1 = substr($date,4,2) . "/" . substr($date,6,2) . "/" . substr($date,0,4);
      $line .= "<tr>";
      $line .= "<th align=left bgcolor=\"#4a7394\" colspan=4> $date1 </th>\n";
      $line .= "</tr>\n";

      my $sum = $sum{$date . 'postauthsuccess'};
      $tot_sum += $sum;
      $sum = sprintf("%0.2f",$sum + 0.0001);


      $line .= "<tr>";
      $line .= "<th align=left><font size=-1>Settled Auths</font></th>\n";
      $line .= "<td align=right><font size=-1>$label_hash{$newauthfee{'type'}}$sum</font></td>";
      $line .= "<td align=right><font size=-1> &nbsp; </font></td>";
      $line .= "<th align=right><font size=-1> &nbsp; </font></th>\n";
      $line .= "</tr>\n";

      #$header_text = "DATE\tSETTLED_AUTH_FEE";
      #$line_text .= "$date1\t$sum\t";

      my $ret = $sum{$date . 'returnsuccess'} + $sum{$date . 'returnpending'} - $cb_deductamt{$date};
      $tot_ret += $ret;
      $ret = sprintf("%0.2f",$ret + 0.0001);

      $line .= "<tr>";
      $line .= "<th align=left><font size=-1>Returns</font></th>\n";
      $line .= "<td align=right><font size=-1>$label_hash{$newauthfee{'type'}}$ret</font></td>";
      $line .= "<td align=right><font size=-1> &nbsp; </font></td>";
      $line .= "<th align=right><font size=-1> &nbsp; </font></th>\n";
      $line .= "</tr>\n";

      #$header_text .= "RETURN_FEE";
      #$line_text .= "$ret\t";

      $resrv_fee = ($sum * $resrvfee{'rate'}) + 0.001;
      $resrv_fee = sprintf("%0.2f",$resrv_fee);
      $tot_resrv_fee += $resrv_fee;

      $line .= "<tr>";
      $line .= "<th align=left><font size=-1>Reserves</font></th>\n";
      $line .= "<td align=right><font size=-1>$label_hash{$newauthfee{'type'}}$resrv_fee</font></td>";
      $line .= "<td align=right><font size=-1> &nbsp; </font></td>";
      $line .= "<th align=right><font size=-1> &nbsp; </font></th>\n";
      $line .= "</tr>\n";

      $header_text .= "RESERV_FEE";
      $line_text .= "$resrv_fee\t";

      $discnt_fee = ($sum * $discntfee{'rate'}) + 0.001;
      $discnt_fee = sprintf("%0.2f",$discnt_fee);
      $tot_discnt_fee += $discnt_fee;

      $line .= "<tr>";
      $line .= "<th align=left><font size=-1>Discount</font></th>\n";
      $line .= "<td align=right><font size=-1>$label_hash{$newauthfee{'type'}}$discnt_fee</font></td>";
      $line .= "<td align=right><font size=-1> &nbsp; </font></td>";
      $line .= "<th align=right><font size=-1> &nbsp; </font></th>\n";
      $line .= "</tr>\n";

      #$header_text .= "DISCNT_FEE";
      #$line_text .= "$discnt_fee\t";

      #$acct_code4{$acct_code4} = $acct_code4;
      #$ac4_count{"$trans_date$operation$finalstatus$acct_code4"};
      #$ac4_sum{"$trans_date$operation$finalstatus$acct_code4"};

      
      #$cb_cnt = $ac4_count{$date . "returnsuccessChargeback"} + $ac4_count{$date . "returnpendingChargeback"};
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
      $line .= "<th align=left><font size=-1>Chargebacks</font></th>\n";
      $line .= "<td align=right><font size=-1>$label_hash{$chargebck{'type'}}$chargebck_fee</font></td>";
      $line .= "<td align=right><font size=-1> &nbsp; </font></td>";
      $line .= "<th align=right><font size=-1> &nbsp; </font></th>\n";
      $line .= "</tr>\n";

      #$line .= "SUM:$sum, RET:$ret, DISCT:$discnt_fee, RESERV:$resrv_fee , CBFEE:$chargebck_fee<br>\n";

      my $owed = $sum - $ret - $discnt_fee - $resrv_fee - $chargebck_fee; 
      $owed = sprintf("%.2f",$owed);
     
      if ($subacct =~ /crowngatei|greenstedc|vmicards1/) {
        my $declcnt = $count{$date . 'authbadcard'};
        $decl_fee = ($declcnt * $declinedfee{'rate'}) + 0.001;
        $decl_fee = sprintf("%0.2f",$decl_fee);
        $tot_decl_fee += $decl_fee;

        $line .= "<tr><th colspan=2  align=left>Transaction Fees</th></tr>\n";
        $line .= "<tr><th align=left><font size=-1>Declined Auths</font></th>\n";
        $line .= "<td align=right><font size=-1>$label_hash{$declinedfee{'type'}}$declcnt</font></td>";
        $line .= "<td align=right><font size=-1>$rate_hash{$declinedfee{'type'}}$declinedfee{'rate'}</font></td>";
        $line .= "<th align=right><font size=-1>\$$decl_fee</font></th>\n";
        $line .= "</tr>\n";

        #$header_text .= "AUTH_DECL_FEE";
        #$line_text .= "$decl_fee\t";

        my $fraudcnt = $count{$date . 'authfraud'};
        $fraud_fee = ($fraudcnt * $fraudfee{'rate'}) + 0.001;
        $fraud_fee = sprintf("%0.2f",$fraud_fee);
        $tot_fraud_fee += $fraud_fee;

        $line .= "<tr><th align=left><font size=-1>Fraud Screen</font></th>\n";
        $line .= "<td align=right><font size=-1>$label_hash{$fraudfee{'type'}}$fraudcnt</font></td>";
        $line .= "<td align=right><font size=-1>$rate_hash{$fraudfee{'type'}}$fraudfee{'rate'}</font></td>";
        $line .= "<th align=right><font size=-1>\$$fraud_fee</font></th>\n";
        $line .= "</tr>\n";
        $owed = $owed - $decl_fee - $fraud_fee;
        $owed = sprintf("%.2f",$owed);

        #$header_text .= "FRAUD_FEE";
        #$line_text .= "$fraud_fee\t";

      }

      $tot_owed += $owed;

      $line .= "<tr>";
      $line .= "<th align=left><font size=-1>Amount Owed</font></th>\n";
      $line .= "<td align=right><font size=-1> &nbsp; </font></td>";
      $line .= "<td align=right><font size=-1> &nbsp; </font></td>";
      $line .= "<th align=right bgcolor=\"#4a7394\"><font size=-1> $owed </font></th>\n";
      $line .= "</tr>\n";

      $line .= "<tr>";
      $line .= "<th align=left colspan=4> &nbsp; </th>\n";
      $line .= "</tr>\n";

      #$header_text .= "TOT_OWED\n";  
      #$line_text .= "$owed\n";

      #print "$line";
      #$line = "";
    }
  }
  else {
    $line .= "<tr><th colspan=5 bgcolor=\"#4a7394\" align=left>Transaction Fees:</th></tr>\n";
    $line .= "<tr><td rowspan=8>&nbsp; &nbsp;</td></tr>\n";
    $line .= "<tr>";
    $line .= "<th align=left><font size=-1>New Auths</font></th>\n";
    $line .= "<td align=right><font size=-1>$label_hash{$newauthfee{'type'}}$total_auths_new</font></td>";
    $line .= "<td align=right><font size=-1>$rate_hash{$newauthfee{'type'}}$newauthfee{'rate'}</font></td>";
    $line .= "<th align=right><font size=-1>\$$total_auths_new_fee</font></th>\n";
    $line .= "</tr>\n";

    $header_text .= "TOT_AUTH_NEW_CNT\tTOT_AUTH_NEW_FEE\t";
    $line_text .= "$label_hash{$newauthfee{'type'}}$total_auths_new\t$total_auths_new_fee\t";

    if ($total_auths_rec ne "") {
      $line .= "<tr><th align=left><font size=-1>Rec Auths</font>";
      if ($free250 eq "yes") {
        $line .= "&nbsp; - (First 250 Free) ";
      } 
      $line .= "</th>\n";
      $line .= "<td align=right><font size=-1>$label_hash{$recauthfee{'type'}}$total_auths_rec</font></td>";
      $line .= "<td align=right><font size=-1>$rate_hash{$recauthfee{'type'}}$recauthfee{'rate'}</font></td>";
      $line .= "<th align=right><font size=-1>\$$total_auths_rec_fee</font></th>\n";
      $line .= "</tr>\n";
    }
    $header_text .= "TOT_AUTH_REC_CNT\tTOT_AUTH_REC_FEE\t";
    $line_text .= "$label_hash{$recauthfee{'type'}}$total_auths_rec\t$total_auths_rec_fee\t";

    $line .= "<tr><th align=left><font size=-1>Declined Auths</font></th>\n";
    $line .= "<td align=right><font size=-1>$label_hash{$declinedfee{'type'}}$total_auths_decl</font></td>";
    $line .= "<td align=right><font size=-1>$rate_hash{$declinedfee{'type'}}$declinedfee{'rate'}</font></td>";
    $line .= "<th align=right><font size=-1>\$$total_auths_decl_fee</font></th>\n";
    $line .= "</tr>\n";

    $header_text .= "TOT_AUTH_DECL_CNT\tTOT_AUTH_DECL_FEE\t";
    $line_text .= "$total_auths_decl_fee\t";

    $line .= "<tr><th align=left><font size=-1>Returns/Credits</font></th>\n";
    $line .= "<td align=right><font size=-1>$label_hash{$returnfee{'type'}}$total_retrn</font></td>";
    $line .= "<td align=right><font size=-1>$rate_hash{$returnfee{'type'}}$returnfee{'rate'}</font></td>";
    $line .= "<th align=right><font size=-1>\$$total_retrn_fee</font></th>\n";
    $line .= "</tr>\n";

    $header_text .= "TOT_RETRN_CNT\tTOT_RETRN_FEE\t";
    $line_text .= "$label_hash{$returnfee{'type'}}$total_retrn\t$total_retrn_fee\t";

    $line .= "<tr><th align=left><font size=-1>Voids</font></th>\n";
    $line .= "<td align=right><font size=-1>$label_hash{$voidfee{'type'}}$total_void</font></td>";
    $line .= "<td align=right><font size=-1>$rate_hash{$voidfee{'type'}}$voidfee{'rate'}</font></td>";
    $line .= "<th align=right><font size=-1>\$$total_void_fee</font></th>\n";
    $line .= "</tr>\n";

    $header_text .= "TOT_VOID_CNT\tTOT_VOID_FEE\t";
    $line_text .= "$label_hash{$voidfee{'type'}}$total_void\t$total_void_fee\t";

    $line .= "<tr><th align=left><font size=-1>Fraud Screen</font></th>\n";
    $line .= "<td align=right><font size=-1>$label_hash{$fraudfee{'type'}}$total_fraud</font></td>";
    $line .= "<td align=right><font size=-1>$rate_hash{$fraudfee{'type'}}$fraudfee{'rate'}</font></td>";
    $line .= "<th align=right><font size=-1>\$$total_fraud_fee</font></th>\n";
    $line .= "</tr>\n";

    $header_text .= "TOT_FRAUD_CNT\tTOT_FRAUD_FEE\t";
    $line_text .= "$label_hash{$fraudfee{'type'}}$total_fraud\t$total_fraud_fee\t";

    $line .= "<tr><th align=left><font size=-1>CyberSource</font></th>\n";
    $line .= "<td align=right><font size=-1>$label_hash{$cybersfee{'type'}}$total_cybers</font></td>";
    $line .= "<td align=right><font size=-1>$rate_hash{$cybersfee{'type'}}$cybersfee{'rate'}</font></td>";
    $line .= "<th align=right><font size=-1>\$$total_cybers_fee</font></th>\n";
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

    $line .= "<tr><th colspan=5 bgcolor=\"#4a7394\" align=left>Totals:</th></tr>\n";

    $line .= "<tr><th align=left><font size=-1>Settled Auths</font></th>\n";
    $line .= "<td align=right><font size=-1>\$$tot_sum</font></td>";
    $line .= "<td align=right><font size=-1></font></td>";
    $line .= "<th align=right><font size=-1>\$$tot_sum</font></th>\n";
    $line .= "</tr>\n";

    $line .= "<tr><th align=left><font size=-1>Returns</font></th>\n";
    $line .= "<td align=right><font size=-1>\$$tot_ret</font></td>";
    $line .= "<td align=right><font size=-1></font></td>";
    $line .= "<th align=right><font size=-1>\$$tot_ret</font></th>\n";
    $line .= "</tr>\n";

    $line .= "<tr><th align=left><font size=-1>Reserve</font></th>\n";
    $line .= "<td align=right><font size=-1>\$$tot_sum</font></td>";
    $line .= "<td align=right><font size=-1>$rate_hash{$resrvfee{'type'}}$resrvfee{'rate'}</font></td>";
    $line .= "<th align=right><font size=-1>\$$tot_resrv_fee</font></th>\n";
    $line .= "</tr>\n";

    $line .= "<tr><th align=left><font size=-1>Discount</font></th>\n";
    $line .= "<td align=right><font size=-1>\$$tot_sum</font></td>";
    $line .= "<td align=right><font size=-1>$rate_hash{$discntfee{'type'}}$discntfee{'rate'}</font></td>";
    $line .= "<th align=right><font size=-1>\$$tot_discnt_fee</font></th>\n";
    $line .= "</tr>\n";

    $line .= "<tr><th align=left><font size=-1>Chargebacks</font></th>\n";
    $line .= "<td align=right><font size=-1>$tot_cb_cnt</font></td>";
    $line .= "<td align=right><font size=-1>$rate_hash{$chargebck{'rate'}}$chargebck{'rate'}</font></td>";
    $line .= "<th align=right><font size=-1>\$$tot_chargebck_fee</font></th>\n";
    $line .= "</tr>\n";

    $header_text .= "TOT_SETTLD_AUTH\tTOT_RETURNS\tRESERVE\tDISCOUNT\tCHARGEBACKS\t";
    $line_text .= "$tot_sum\t$tot_ret\t$tot_resrv_fee\t$tot_discnt_fee\t$tot_chargebck_fee\t";

    if ($subacct =~ /crowngatei|greenstedc|vmicards1/) {
      $line .= "<tr><th colspan=2  align=left>Transaction Fees</th></tr>\n";
      $line .= "<tr><th align=left><font size=-1>Declined Auths</font></th>\n";
      $line .= "<td align=right><font size=-1>$label_hash{$declinedfee{'type'}}$total_auths_decl</font></td>";
      $line .= "<td align=right><font size=-1>$rate_hash{$declinedfee{'type'}}$declinedfee{'rate'}</font></td>";
      $line .= "<th align=right><font size=-1>\$$total_auths_decl_fee</font></th>\n";
      $line .= "</tr>\n";
      $line .= "<tr><th align=left><font size=-1>Fraud Screen</font></th>\n";
      $line .= "<td align=right><font size=-1>$label_hash{$fraudfee{'type'}}$total_fraud</font></td>";
      $line .= "<td align=right><font size=-1>$rate_hash{$fraudfee{'type'}}$fraudfee{'rate'}</font></td>";
      $line .= "<th align=right><font size=-1>\$$total_fraud_fee</font></th>\n";
      $line .= "</tr>\n";

      $header_text .= "TOT_AUTH_DECL_FEE\tTOT_FRAUD_FEE\t";
      $line_text .= "$total_auths_decl_fee\t$total_fraud_fee\t";

    }
  }
  else {
    $line .= "<tr><th colspan=5 bgcolor=\"#4a7394\" align=left>Discount Fees:</th></tr>\n";
    $line .= "<tr><td rowspan=2>&nbsp; &nbsp;</td></tr>\n";
    $line .= "<tr><th align=left><font size=-1>Discount Rate</font></th>\n";
    $line .= "<td align=right><font size=-1>\$$total_discnt</font></td>";
    $line .= "<td align=right><font size=-1>$rate_hash{$discntfee{'type'}}$discntfee{'rate'}</font></td>";
    $line .= "<th align=right><font size=-1>\$$total_discnt_fee</font></th>\n";
    $line .= "</tr>\n";

    $header_text .= "TOT_DISCNT_FEE\t";
    $line_text .= "$total_discnt_fee\t";


  }
  $line .= "<tr><th colspan=5 bgcolor=\"#4a7394\" align=left>Monthly Fees:</th></tr>\n";
  #$line .= "<tr><td rowspan=1>&nbsp; &nbsp;</td></tr>\n";

  foreach my $feeid (@fixedlist) {
    $line .= "<tr><td>&nbsp; &nbsp;</td><th align=left><font size=-1>$$feeid{'desc'}</font></th>\n";
    $line .= "<td align=right><font size=-1>Monthly</font></td>";
    $line .= "<td align=right><font size=-1>&nbsp;</font></td>";
    $line .= "<th align=right><font size=-1>\$$$feeid{'rate'}</font></th>\n";
    $line .= "</tr>\n";
    $total_fixed += $$feeid{'rate'};
  }

  $header_text .= "TOT_FIXED_FEE\t";
  $line_text .= "$total_fixed\t";


  $total = $total_auths_new_fee + $total_auths_rec_fee + $total_auths_decl_fee +  $total_retrn_fee + $total_void_fee + $total_fraud_fee + $total_cybers_fee + $total_discnt_fee + $total_fixed;

  #$line .= "$total_auths_new_fee, $total_auths_rec_fee, $total_auths_decl_fee, $total_cybers_fee, $total_discnt_fee, $total_fraud_fee, $total_retrn_fee, $total_fixed <br>\n";

  if ($subacct ne "") {
    $tot_owed = sprintf("%0.2f",$tot_owed);
    $line .= "<tr><th align=left bgcolor=\"#4a7394\" colspan=4><font size=3>Total Due</font></td>\n";
    $line .= "<th align=right bgcolor=\"#4a7394\"><font size=3>\$$tot_owed</font></th>\n";
    $line .= "</tr>\n";

    $header_text .= "TOT_OWED\n"; 
    $line_text .= "$tot_owed\n";

  }
  else {
    $total = sprintf("%0.2f",$total);
    $line .= "<tr><th align=left bgcolor=\"#4a7394\" colspan=4><font size=3>Total Owed</font></td>\n";
    $line .= "<th align=right bgcolor=\"#4a7394\"><font size=3>\$$total</font></th>\n";
    $line .= "</tr>\n";

    $header_text .= "TOT_FEE";         
    $line_text .= "$total";

  }
  $line .= "</table></div>\n";
  if ($format eq "text") {
    if ($first_flag == 1) {
      print "$header_text\n";
    }
    else {
     $first_flag = 5;
    }
    print "$line_text\n";
  }
  else {
    print "$line";
  }
  $line = "";
  
}


sub rec_report {
  print "REPORT\n";
  if ($processor eq "cybercash") {
    $rowspan = 1;
  }
  else {
    $rowspan = 1;
  }
  print "<div align=center><table border=1 cellspacing=1 width=650>\n";
  %display = %noacct_code;
  %values = %sum;
  %valuescnt = %count;
  %sums = %sum;

  $total_auths_summ = 0.0000001;

  foreach my $key (sort keys %display) {
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
#           print "<td align=right><font size=-1>\$$values{$date . \"voidsuccess\" . $acct_code}</font></td>\n";
    if ($function eq "daily") {
      foreach my $date (sort keys %dates) {
        $datestr = sprintf("%02d/%02d/%04d", substr($date,4,2), substr($date,6,2), substr($date,0,4));

        $total_auths = $valuescnt{$date . "authsuccess" . $acct_code} +
                       $valuescnt{$date . "authbadcard" . $acct_code} +
                       $valuescnt{$date . "authfraud" . $acct_code} + 000001;

        $total_auths_summ = $total_auths_summ + $total_auths;

#        print "DATE:$date<br>\n";
        $newsales = $values{$date . "postauthsuccess" . $acct_code} - $ac3_sum{$date . "postauthsuccessrecurring"};
        $newsales = sprintf("%.2f",$newsales);
        $newsales =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $newcnt = $valuescnt{$date . "postauthsuccess" . $acct_code} - $ac3_sum{$date . "postauthsuccessrecurring"};
        $newcnt = sprintf("%.2f",$newcnt);
        $newcnt =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $netsales = $values{$date . "postauthsuccess" . $acct_code} - $values{$date . "returnsuccess" . $acct_code};
        $netsales = sprintf("%.2f",$netsales);
        $netsales =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $netcnt = $valuescnt{$date . "postauthsuccess" . $acct_code} - $valuescnt{$date . "returnsuccess" . $acct_code};
        $netcnt = sprintf("%.2f",$netcnt);
        $netcnt =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$date . "authsuccess" . $acct_code} = sprintf("%.2f",$values{$date . "authsuccess" . $acct_code});
        $values{$date . "authsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$date . "postauthsuccess" . $acct_code} = sprintf("%.2f",$values{$date . "postauthsuccess" . $acct_code});
        $values{$date . "postauthsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$date . "returnsuccess" . $acct_code} = sprintf("%.2f",$values{$date . "returnsuccess" . $acct_code});
        $values{$date . "returnsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $values{$date . "voidsuccess" . $acct_code} = sprintf("%.2f",$values{$date . "voidsuccess" . $acct_code});
        $values{$date . "voidsuccess" . $acct_code} =~ s/(\d{1})(\d{3})(\.\d{2})$/$1\,$2$3/;
        $valuescnt{$date . "returnsuccess" . $acct_code} = sprintf("%2d",$valuescnt{$date . "returnsuccess" . $acct_code});
        $ac3_cnt{$date . "postauthsuccessrecurring"} = sprintf("%2d",$ac3_cnt{$date . "postauthsuccessrecurring"});

        print "<tr>\n";
        print "<th align=left rowspan=$rowspan><font size=-1>$datestr</font></th>\n";
        print "<td align=right><font size=-1>\$$values{$date . \"authsuccess\" . $acct_code}</font></td>\n";
        if ($processor ne "cybercash") {

          print "<td align=right><font size=-1>\$$newsales</font></td>\n"; ## New Sales
          print "<td align=right><font size=-1>\$$ac3_sum{$date . \"postauthsuccessrecurring\"}</font></td>\n"; ## Rec Sales
          print "<td align=right><font size=-1>\$$values{$date . \"returnsuccess\" . $acct_code}</font></td>\n";   ## Returns
          print "<td align=right><font size=-1>\$$netsales</font></td>\n";   ## Net
        }
        print "<td align=right><font size=-1>$valuescnt{$date . \"authsuccess\" . $acct_code}</font></td>\n";
        if ($processor ne "cybercash") {
          print "<td align=right><font size=-1>$newcnt</font></td>\n"; ## New Sales
          print "<td align=right><font size=-1>$ac3_cnt{$date . \"postauthsuccessrecurring\"}</font></td>\n"; ## Rec Sales
          print "<td align=right><font size=-1>$valuescnt{$date . \"returnsuccess\" . $acct_code}</font></td>\n";   ## Returns
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
        if ($processor ne "cybercash") {
          $record .= "<td align=right><font size=-1>\$$values{$date . \"voidsuccess\" . $acct_code}</font></td>\n";
          $record .= "<td align=right><font size=-1>\$$values{$date . \"returnsuccess\" . $acct_code}</font></td>\n";
          $record .= "<td align=right><font size=-1>\$$values{$date . \"postauthsuccess\" . $acct_code}</font></td>\n";
          $record .= "<td align=right><font size=-1>\$$values{$date . \"voidsuccess\" . $acct_code}</font></td>\n";

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


sub report2 {

  $cardtype = &CGI::escapeHTML($query->param('cardtype'));
  $form_txntype = &CGI::escapeHTML($query->param('txntype'));
  $txnstatus = &CGI::escapeHTML($query->param('txnstatus'));
  $startdate = &CGI::escapeHTML($query->param('startdate'));
  $enddate = &CGI::escapeHTML($query->param('enddate'));
  $lowamount = &CGI::escapeHTML($query->param('lowamount'));
  $highamount = &CGI::escapeHTML($query->param('highamount'));
  $orderid = &CGI::escapeHTML($query->param('orderid'));

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
  foreach my $var (sort @values) {
    %res2 = ();
    @nameval = split(/&/,$var);
     foreach my $temp (@nameval) {
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
      elsif ($cardbin =~ /^(51|52|53|54|55|56|57|58)/) {
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
        $ikey = $trans_date . "auth" . $cardtype;
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
        $ikey = $trans_date . "postauth" . $cardtype;
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
        $ikey = $trans_date . "return" . $cardtype;
        $$ikey{$amount}++;
      }
    }
  }
  
  if ($format ne "text"){
    foreach my $key (sort keys %postauth_orderids) {
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
    foreach my $key (sort keys %return_orderids) {
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
    foreach my $trans_date (sort keys %dates) {
      print "<tr>";
      print "<th rowspan=4>$trans_date</th>\n";
      print "<td>VISA</td>\n";
      $ikey = $trans_date . "postauthVISAsuccess";
      printf ("<td align=right>%0.2f</td>\n",$tsum{$ikey});
      print "<td align=center>$cnt{$ikey}</td>\n";
      $ikey = $trans_date . "returnVISAsuccess";
      printf ("<td align=right><font color=\"red\">%0.2f</font></td>\n",$tsum{$ikey});
      print "<td align=center>$cnt{$ikey}</td>\n";
      print "</tr>\n";

      print "<tr><td>MSTR</td>\n";
      $ikey = $trans_date . "postauthMSTRsuccess";
      printf ("<td align=right>%0.2f</td>\n",$tsum{$ikey});
      print "<td align=center>$cnt{$ikey}</td>\n";
      $ikey = $trans_date . "returnMSTRsuccess";
      printf ("<td align=right><font color=\"red\">%0.2f</font></td>\n",$tsum{$ikey});
      print "<td align=center>$cnt{$ikey}</td>\n";
      print "</tr>\n";

      print "<tr><td>AMEX</td>\n";
      $ikey = $trans_date . "postauthAMEXsuccess";
      printf ("<td align=right>%0.2f</td>\n",$tsum{$ikey});
      print "<td align=center>$cnt{$ikey}</td>\n";
      $ikey = $trans_date . "returnAMEXsuccess";
      printf ("<td align=right><font color=\"red\">%0.2f</font></td>\n",$tsum{$ikey});
      print "<td align=center>$cnt{$ikey}</td>\n";
      print "</tr>\n";

      print "<tr><td>DSCR</td>\n";
      $ikey = $trans_date . "postauthDSCRsuccess";
      printf ("<td align=right>%0.2f</td>\n",$tsum{$ikey});
      print "<td align=center>$cnt{$ikey}</td>\n";
      $ikey = $trans_date . "returnDSCRsuccess";
      printf ("<td align=right><font color=\"red\">%0.2f</font></td>\n",$tsum{$ikey});
      print "<td align=center>$cnt{$ikey}</td>\n";
      print "</tr>\n";
    }
  }
  else {
    $amount =~ s/[^0-9\.]//g;
    print "$txntype\t$cardname\t$status\t$orderid\t$timestr\t$cardnumber\t$exp\t";
  }
  if ($format ne "text"){
    foreach my $amount (sort keys %aamounts) {
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
    foreach my $trans_date (sort keys %dates) {
      print "<tr>";
      print "<th rowspan=3>$trans_date</th>\n";
      print "<th>Auth</th>";
      my $ikey = $trans_date . "auth";
      my $vkey = $trans_date . "authVISA";
      my $mkey = $trans_date . "authMSTR";
      my $akey = $trans_date . "authAMEX";
      my $dkey = $trans_date . "authDSCR";
      foreach my $amount (@amounts) {
        print "<td align=center>$$vkey{$amount}</td><td align=center>$$mkey{$amount}</td><td align=center>$$akey{$amount}</td><td align=center>$$dkey{$amount}</td><td align=center>$$ikey{$amount}</td>\n";
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
      $ikey = $trans_date . "postauth";
      $vkey = $trans_date . "postauthVISA";
      $mkey = $trans_date . "postauthMSTR";
      $akey = $trans_date . "postauthAMEX";
      $dkey = $trans_date . "postauthDSCR";

      foreach my $amount (@amounts) {
        print "<td align=center>$$vkey{$amount}</td><td align=center>$$mkey{$amount}</td><td align=center>$$akey{$amount}</td><td align=center>$$dkey{$amount}</td><td align=center>$$ikey{$amount}</td>\n";
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
      $ikey = $trans_date . "return";
      $vkey = $trans_date . "returnVISA";
      $mkey = $trans_date . "returnMSTR";
      $akey = $trans_date . "returnAMEX";
      $dkey = $trans_date . "returnDSCR";

      foreach my $amount (@amounts) {
        print "<td align=center>$$vkey{$amount}</td><td align=center>$$mkey{$amount}</td><td align=center>$$akey{$amount}</td><td align=center>$$dkey{$amount}</td><td align=center>$$ikey{$amount}</td>\n";
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
      print "<td align=center>$authtotalcnt{$vkey}</td><td align=center>$authtotalcnt{$mkey}</td><td align=center>$authtotalcnt{$akey}</td><td align=center>$authtotalcnt{$dkey}</td><td align=center>$authtotalcnt{$amount}</td>\n";
    }
    print "</tr>\n";

    print "<tr><th>Postauth</th>\n";
    $ikey = $trans_date . "postauthtotal";
    foreach my $amount (@amounts) {
      my $vkey = $amount . "VISA";
      my $mkey = $amount . "MSTR";
      my $akey = $amount . "AMEX";
      my $dkey = $amount . "DSCR";
      print "<td align=center>$postauthtotalcnt{$vkey}</td><td align=center>$postauthtotalcnt{$mkey}</td><td align=center>$postauthtotalcnt{$akey}</td><td align=center>$postauthtotalcnt{$dkey}</td><td align=center>$postauthtotalcnt{$amount}</td>\n";
    }
    print "</tr>\n";
    print "<tr><th>Returns</th>\n";
    $ikey = $trans_date . "returntotal";
    foreach my $amount (@amounts) {
      my $vkey = $amount . "VISA";
      my $mkey = $amount . "MSTR";
      my $akey = $amount . "AMEX";
      my $dkey = $amount . "DSCR";
      print "<td align=center>$returntotalcnt{$vkey}</td><td align=center>$returntotalcnt{$mkey}</td><td align=center>$returntotalcnt{$akey}</td><td align=center>$returntotalcnt{$dkey}</td><td align=center>$authtotalcnt{$amount}</td>\n";
    }
    print "</tr>\n";

  }
  else {
    $amount =~ s/[^0-9\.]//g;
    print "$txntype\t$cardname\t$status\t$orderid\t$timestr\t$cardnumber\t$exp\t";
  }

}


sub query1 {

  #$dbh = &miscutils::dbhconnect("pnpdata");
  $dbh = &miscutils::dbhconnect("pnpdata","","$username");

  $total = 0;

  $start1 = $start;
  $end1 = $end;

  $max = 200;
  $maxmonth = 200;
  $trans_max = 200;
  $trans_maxmonth = 200;

  $tt = time();

  my @placeholder;
  if ($report_time eq "batchtime") {
    $qstr = "SELECT batch_time,";
  }
  else {
    $qstr = "SELECT trans_date,";
  }

  if ($subacct ne "") {
    $qstr .= " operation, finalstatus, substr(card_number,0,3), count(username), sum(substr(amount,5)) ";
    $qstr .= " FROM trans_log";
 
    my ($qmarks,$dateArrayRef) = &miscutils::dateIn($start,$end,'0');
    $qstr .= "  WHERE trans_date IN ($qmarks)";
    push(@placeholder, @$dateArrayRef);

    if (exists $altaccts{$username}) {
      my ($temp);
      foreach my $var ( @{ $altaccts{$username} } ) {
        $temp .= "?,";
        push(@placeholder, $var);
      }
      chop $temp;
      $qstr .= " AND username IN ($temp)";
    }
    else {
      $qstr .= " AND username=?";
      push(@placeholder, $username);
    }
  
    $qstr .= " AND subacct=? AND operation<>'query' AND (duplicate IS NULL OR duplicate='')";
    push(@placeholder, $subacct);
    $qstr .= " GROUP BY trans_date, operation, finalstatus, substr(card_number,0,2) ";

  }
  elsif ($subacct eq "ALL") {
    $qstr .= " operation, finalstatus, subacct, username, count(username), sum(substr(amount,5))";
    $qstr .= " FROM trans_log";

    my ($qmarks,$dateArrayRef) = &miscutils::dateIn($start,$end,'0');
    $qstr .= "  WHERE trans_date IN ($qmarks)";
    push(@placeholder, @$dateArrayRef);

    if (exists $altaccts{$username}) {
      my ($temp);
      foreach my $var ( @{ $altaccts{$username} } ) {
        $temp .= "?,";
        push(@placeholder, $var);
      }
      chop $temp;
      $qstr .= " AND username IN ($temp)";
    }
    else {
      $qstr .= " AND username=?";
      push(@placeholder, $username);
    }

    $qstr .= " AND operation<>'query' AND (duplicate IS NULL OR duplicate='')";
    $qstr .= " GROUP BY trans_date, operation, finalstatus, subacct";

  }
  else {
    $qstr .= " operation, finalstatus, substr(card_number,0,3), count(username), sum(substr(amount,5))"; 
    $qstr .= " FROM trans_log";

    my ($qmarks,$dateArrayRef) = &miscutils::dateIn($start,$end,'0');
    $qstr .= "  WHERE trans_date IN ($qmarks)";
    push(@placeholder, @$dateArrayRef);

    $qstr .= " AND username=?";
    push(@placeholder, $username);
 
    $qstr .= " AND operation<>'query' AND (duplicate IS NULL or duplicate='')";
    $qstr .= " GROUP BY trans_date, operation, finalstatus, substr(card_number,0,3)";
  }

  $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
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
    elsif ($cardbin =~ /^(51|52|53|54|55|56|57|58)/) {
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
  $function = &CGI::escapeHTML($query->param('function'));
  #$acct_code = &CGI::escapeHTML($query->param('acct_code'));
  #$startmonth = &CGI::escapeHTML($query->param('startmonth'));
  #$startyear = &CGI::escapeHTML($query->param('startyear'));
  #$startday = &CGI::escapeHTML($query->param('startday'));
  #$endmonth = &CGI::escapeHTML($query->param('endmonth'));
  #$endyear = &CGI::escapeHTML($query->param('endyear'));
  #$endday = &CGI::escapeHTML($query->param('endday'));

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

  $qstr = "SELECT username,name,company,commission FROM $merchantdb";
  if (($acct_code ne "") && ($acct_code ne "All")) {
    $qstr .= " WHERE username=\'$acct_code\'";
  }
  else {
    $qstr .= " ORDER BY username";
  }

#print "SEARCH $qstr:  UN:$username <br>\n";

  $sth_customer = $dbh_aff->prepare(qq{$qstr}) or die "Cant do: $DBI::errstr";

  $sth_customer->execute() or die "Cant execute: $DBI::errstr";
  while(my ($username,$name,$company,$commission) = $sth_customer->fetchrow) {
    $$username{'name'} = $name;
    $$username{'company'} = $company;
    ($$username{'commission'},$$username{'commission_type'}) = split(/\|/,$commission,2);
    $affiliates{$username} = 1;
    #print "IN FETCH $username,$name,$company,$commission <br>\n";
  }
  $sth_customer->finish;

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Affiliate Reports</title>\n";
  #print "<link rel=\"stylesheet\" type=\"text/css\" href=\"/payment/affiliate/stylesheet.css\">\n";
  print "<link href=\"/css/style_reports.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  print "</head>\n";

  print "<body bgcolor=\"#ffffff\" link=\"#000000\">\n";
  #print "<div align=left>\n";
  foreach my $username (sort keys %affiliates) {
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
    print "<table border=1>\n";
    print "<tr><th align=left>Date</th><th align=left>Time</th><th align=left>Order ID</th><th align=left>Amount</th>\n"; 

  $max = 200;
  $maxmonth = 200;

  $dbh = &miscutils::dbhconnect("pnpdata","","$merchant") or die "failed connect<br>\n";

  my @placeholder;
  $searchstr = "SELECT orderid,card_name,trans_date,trans_time,amount,shipping,tax";
  $searchstr .= " FROM ordersummary";

  my ($qmarks,$dateArrayRef) = &miscutils::dateIn($start,$end,'0');
  $searchsrt .= " WHERE trans_date IN ($qmarks)";
  push(@placeholder, @$dateArrayRef);

  $searchstr .= " AND username=?";
  push(@placeholder, $merchant);
  if ($acct_code eq "") {
    $searchstr .= " AND (acct_code IS NULL or acct_code='')";
  }
  else {
    $searchstr .= " AND acct_code=?";
    push(@placeholder, $acct_code);
  }
  $searchstr .= " AND result='success'";
  $searchstr .= " ORDER BY trans_date,trans_time";

  $sth = $dbh->prepare(qq{$searchstr}) or die "Can't do: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  while(my ($orderid,$card_name,$trans_date,$trans_time,$amount,$shipping,$tax) = $sth->fetchrow) {
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

  my @placeholder2;
  my $searchstr2 = "SELECT orderid,card_name,trans_date,trans_time,amount,operation";
  $searchstr2 .= " FROM trans_log";

  my ($qmarks2,$dateArrayRef2) = &miscutils::dateIn($start,$end,'0');
  $searchstr2 .= " WHERE trans_date IN ($qmarks2)";
  push(@placeholder2, @$dateArrayRef2);

  $searchstr2 .= " AND username=?";
  push(@placeholder2, $merchant);
  $searchstr2 .= " AND operation IN ('void','return')";
  if ($acct_code eq "") {
    $searchstr2 .= " AND (acct_code IS NULL or acct_code='')";
  }
  else {
    $searchstr2 .= " AND acct_code=?";
    push(@placeholder2, $acct_code);
  }
  $searchstr2 .= " AND result='success'";
  $searchstr2 .= " ORDER BY trans_date,trans_time";

  $sth = $dbh->prepare(qq{$searchstr}) or die "failed prepare<br>\n";
  $sth->execute(@placeholder2) or die "failed execute<br>\n";
  while (my ($orderid,$card_name,$trans_date,$trans_time,$amount,$operation) = $sth->fetchrow) {
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
        print "<tr><th align=left>$header_date</th><td>$time</td><td>$oid</td><td align=right><font color=\"#ff0000\">$amount</font></td></tr>\n";
      }
      else {
        $total = $total + $$operation{$oid};
        print "<tr><th align=left>$header_date</th><td>$time</td><td>$oid</td><td align=right>$amount</td></tr>\n";
      }
      $old_date = $date;
    }
    if (($commission_type eq "p") || ($commission_type eq "")) {
      $amt_due = $total * $commission;
    }
    elsif ($commission_type eq "f") {
      $amt_due = $total_transactions * $commission;
    }
    printf("<tr><th align=left>TOTAL:</th><td colspan=2>&nbsp;</td><td align=right><b>\$%.2f</b></td>\n", $total);
    print "<tr><th align=left>TRANSACTIONS:</th><td colspan=2>&nbsp;</td><td align=right><b>$total_transactions</b></td>\n";
    printf("<tr><th align=left>AMT DUE:</th><td colspan=2>&nbsp;</td><td align=right><b>\$%.2f</b></td>\n", $amt_due);
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
  print "<table border=1>\n";
  print "<tr><th align=left>Date</th><th align=left>Time</th><th align=left>Order ID</th><th align=left>Amount</th>\n";
}

sub table_row {
  if ($operation ne "auth") {
    print "<tr><th align=left>$header_date</th><td>$time</td><td>$oid</td><td align=right><font color=\"#ff0000\">$amount</font></td></tr>\n";
  }
  else {
    $total = $total + $$operation{$oid};
    print "<tr><th align=left>$header_date</th><td>$time</td><td>$oid</td><td align=right>$amount &nbsp;</td></tr>\n";
  }
}

sub admin_report {
  $function = &CGI::escapeHTML($query->param('function'));
  #$acct_code = &CGI::escapeHTML($query->param('acct_code'));
  #$startmonth = &CGI::escapeHTML($query->param('startmonth'));
  #$startyear = &CGI::escapeHTML($query->param('startyear'));
  #$startday = &CGI::escapeHTML($query->param('startday'));
  #$endmonth = &CGI::escapeHTML($query->param('endmonth'));
  #$endyear = &CGI::escapeHTML($query->param('endyear'));
  #$endday = &CGI::escapeHTML($query->param('endday'));

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

  $qstr = "SELECT username,name,company,commission FROM $merchantdb";
  if (($acct_code ne "") && ($acct_code ne "All")) {
    $qstr .= " WHERE username='$acct_code'";
  }
  else {
    $qstr .= " ORDER BY username";
  }

  $sth_customer = $dbh_aff->prepare(qq{$qstr}) or die "Cant do: $DBI::errstr";
  $sth_customer->execute() or die "Cant execute: $DBI::errstr";
  while(my ($username,$name,$company,$commission) = $sth_customer->fetchrow) {
    $$username{'name'} = $name;
    $$username{'company'} = $company;
    ($$username{'commission'},$$username{'commission_type'}) = split(/\|/,$commission,2);
    $affiliates{$username} = 1;
  }
  $sth_customer->finish;

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Affiliate Reports</title>\n";
  print "<link href=\"/css/style_reports.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  print "</head>\n";

  print "<body bgcolor=\"#ffffff\" link=\"#000000\">\n";
  print "Report Period: $reportstart to $reportend<p>\n";
  print "<table>\n";
  foreach my $username (sort keys %affiliates) {
    $acct_code = $username;
    $company = $$username{'company'};
    $name = $$username{'name'};
    $commission = $$username{'commission'};
    $commission_type = $$username{'commission_type'};
    my (%date,%orderid,%cardname,$amount,$total);

    $max = 200;
    $maxmonth = 200;

    $dbh = &miscutils::dbhconnect("pnpdata","","$merchant") or die "failed connect<br>\n";

    my @placeholder;
    $searchstr = "SELECT orderid,card_name,trans_date,trans_time,amount,shipping,tax";
    $searchstr .= " FROM ordersummary";

    my ($qmarks,$dateArrayRef) = &miscutils::dateIn($start,$end,'0');
    $searchstr .= " WHERE trans_date IN ($qmarks)";
    push(@placeholder, @$dateArrayRef);

    $searchstr .= " AND username=?";
    push(@placeholder, $merchant);
    if ($acct_code eq "") {
      $searchstr .= " AND (acct_code IS NULL OR acct_code='')";
    }
    else {
      $searchstr .= " AND acct_code=?";
      push(@placeholder, $acct_code);
    }
    $searchstr .= " AND result='success'";
    $searchstr .= " ORDER BY trans_date,trans_time";

    $sth = $dbh->prepare(qq{$searchstr}) or die "Can't do: $DBI::errstr";
    $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";

    while(my ($orderid,$card_name,$trans_date,$trans_time,$amount,$shipping,$tax) = $sth->fetchrow) {
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

    my @placeholder2;
    $searchstr2 = "SELECT orderid,card_name,trans_date,trans_time,amount,operation";
    $searchstr2 .= " FROM trans_log";

    my ($qmarks2,$dateArrayRef2) = &miscutils::dateIn($start,$end,'0');
    $searchstr2 .= " WHERE trans_date IN ($qmarks2)";
    push(@placeholder2, @$dateArrayRef2);

    $searchstr2 .= " AND username=?";
    push(@placeholder2, $merchant);
    $searchstr2 .= " AND operation IN ('void','return')";
    if ($acct_code eq "") {
      $searchstr2 .= " AND (acct_code IS NULL OR acct_code='')";
    }
    else {
      $searchstr2 .= " AND acct_code=?";
      push(@placeholder2, $acct_code);
    }
    $searchstr2 .= " AND result='success'";
    $searchstr2 .= " ORDER BY trans_date,trans_time";

    $sth = $dbh->prepare(qq{$searchstr2}) or die "failed prepare<br>\n";
    $sth->execute(@placeholder2) or die "failed execute<br>\n";

    while (my ($orderid,$card_name,$trans_date,$trans_time,$amount,$operation) = $sth->fetchrow) {
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
    printf("<tr><th align=left>TOTAL:</th><td colspan=2>&nbsp;</td><td align=right><b>\$%.2f</b></td>\n", $total);
    print "<tr><th align=left>TRANSACTIONS:</th><td colspan=2>&nbsp;</td><td align=right><b>$total_transactions</b></td>\n";
    printf("<tr><th align=left>AMT DUE:</th><td colspan=2>&nbsp;</td><td align=right><b>\$%.2f</b></td>\n", $amt_due);
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
  $function = &CGI::escapeHTML($query->param('function'));
  $graphtype = &CGI::escapeHTML($query->param('graphtype'));
  $acct_code = &CGI::escapeHTML($query->param('acct_code'));
  #$startmonth = &CGI::escapeHTML($query->param('startmonth'));
  #$startyear = &CGI::escapeHTML($query->param('startyear'));
  #$startday = &CGI::escapeHTML($query->param('startday'));
  #$endmonth = &CGI::escapeHTML($query->param('endmonth'));
  #$endyear = &CGI::escapeHTML($query->param('endyear'));
  #$endday = &CGI::escapeHTML($query->param('endday'));

  $start = sprintf("%04d%02d%02d", $startyear,$month_array2{$startmonth}, $startday);
  $end = sprintf("%04d%02d%02d", $endyear,$month_array2{$endmonth}, $endday);


  $total = 0;

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
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
  print "<div align=center>\n";
  print "<h3>$startmonth $startday, $startyear - $endmonth $endday, $endyear</h3>\n";
  print "</div>\n";

  $max = 200;
  $maxmonth = 200;

  $dbh = &miscutils::dbhconnect("pnpdata","","$merchant");

  my @placeholder;
  $searchstr = "SELECT orderid,card_name,trans_date,trans_time,amount,operation";
  $searchstr .= " FROM trans_log";

  my ($qmarks,$dateArrayRef) = &miscutils::dateIn($start,$end,'0');
  $searchstr .= " WHERE trans_date IN ($qmarks)";
  push(@placeholder, @$dateArrayRef);

  $searchstr .= " AND username='$merchant'";
  push(@placeholder, $merchant);
  if ($acct_code eq "") {
    $searchstr .= " AND (acct_code IS NULL or acct_code='')";
  }
  else {
    $searchstr .= " AND acct_code='$acct_code'";
    push(@placeholder, $acct_code);
  }
  $searchstr .= " AND result='success' AND operation<>'query'";

#print "SRCH:$searchstr\n";
#exit;

$st = time();

  my @placeholder2;
  my $searchstr2 = "SELECT orderid,shipping,tax";
  $searchstr2 .= " FROM ordersummary";
  my ($qmarks2,$dateArrayRef2) = &miscutils::dateIn($start,$end,'0');
  $searchstr2 .= " WHERE trans_date IN ($qmarks2)";
  push(@placeholder2, @$dateArrayRef2);
  $searchstr2 .= " AND username=?";
  push(@placeholder2, $merchant);
  $searchstr2 .= " AND result='success'";

  my $sth_orders = $dbh->prepare(qq{ $searchstr2 }) or die "Can't do: $DBI::errstr";
  $sth_orders->execute(placeholder2) or die "Can't execute: $DBI::errstr";
  while(my ($orderid,$shipping,$tax) = $sth_orders->fetchrow) {
    $tax{$orderid} = $tax;
    $shipping{$orderid} = $shipping;
  }
  $sth_orders->finish;

$ed = time();

$el = $ed - $st;

  $sth = $dbh->prepare(qq{$searchstr}) or die "Can't do: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  while(my ($orderid,$card_name,$trans_date,$trans_time,$amount,$operation) = $sth->fetchrow) {
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

  foreach my $oid (sort keys %date) {
    foreach my $operation (sort keys %$oid) {
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

  $sth->finish;
  $dbh->disconnect;

  print "<table border=1>\n";

  foreach my $key (sort keys %total_month) {

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
  $function = &CGI::escapeHTML($query->param('function'));
  $graphtype = &CGI::escapeHTML($query->param('graphtype'));
  $acct_code = $username;
  $start = sprintf("%04d%02d%02d", $startyear,$month_array2{$startmonth}, $startday);
  $end = sprintf("%04d%02d%02d", $endyear,$month_array2{$endmonth}, $endday);
  $reportstart = sprintf("%02d/%02d/%02d", $month_array2{$startmonth}, $startday, $startyear);
  $reportend = sprintf("%02d/%02d/%02d", $month_array2{$endmonth}, $endday, $endyear);

  $total = 0;

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Affiliate Reports - Graphs</title>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"/payment/affiliate/stylesheet.css\">\n";
  print "</head>\n";

  print "<body bgcolor=\"#ffffff\" link=\"#000000\">\n";
  print "<div align=left>\n";
  print "<h3>Sales Graph for ";
  if ($company ne "") {
    print "$company ";
  }
  print "Affiliate Account: $acct_code</h3>\n";
  print "Report Period: $reportstart to $reportend<p>\n";

  $max = 200;
  $maxmonth = 200;

  $dbh = &miscutils::dbhconnect("pnpdata","","$merchant");

  my @placeholder;
  $searchstr = "SELECT t.orderid,t.card_name,t.trans_date,t.trans_time,t.amount,t.operation";
  $searchstr .= " FROM trans_log t";

  my ($qmarks,$dateArrayRef) = &miscutils::dateIn($start,$end,'0');
  $searchstr .= " WHERE t.trans_date IN ($qmarks)";
  push(@placeholder, @$dateArrayRef);

  $searchstr .= " AND t.username=?";
  push(@placeholder, $merchant);
  if ($acct_code eq "") {
    $searchstr .= " AND (t.acct_code IS NULL or t.acct_code='')";
  }
  else {
    $searchstr .= " AND t.acct_code=?";
    push(@placeholder, $acct_code);
  }
  $searchstr .= " AND t.result='success'";


  my @placeholder2;
  my $searchstr2 = "SELECT orderid,shipping,tax";
  $searchstr2 .= " FROM ordersummary";
  my ($qmarks2,$dateArrayRef2) = &miscutils::dateIn($start,$end,'0');
  $searchstr2 .= " WHERE t.trans_date IN ($qmarks2)";
  push(@placeholder2, @$dateArrayRef2);
  $searchstr2 .= " AND username=? AND result='success'";
  push(@placeholder2, $merchant);

  my $sth_orders = $dbh->prepare(qq{ $searchstr2 }) or die "Can't do: $DBI::errstr";
  $sth_orders->execute(@placeholder2) or die "Can't execute: $DBI::errstr";
  while(my ($orderid,$shipping,$tax) = $sth_orders->fetchrow) {
    $tax{$orderid} = $tax;
    $shipping{$orderid} = $shipping;
  }
  $sth_orders->finish;

  $sth = $dbh->prepare(qq{$searchstr}) or die "Can't do: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  while(my ($orderid,$card_name,$trans_date,$trans_time,$amount,$operation) = $sth->fetchrow) {
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
  foreach my $oid (sort keys %date) {
    foreach my $operation (sort keys %$oid) {
      $trans_date = $date{$oid};
      $date2 = substr($trans_date,0,6);
      $$operation{$oid};
      if ($operation ne "auth") {
        $total{$trans_date} = $total{$trans_date} - $$operation{$oid};
        $total_month{$date2} = $total_month{$date2} - $$operation{$oid};
        $grandtotal = $grandtotal - $$operation{$oid};
      }
      else {
        $total{$trans_date} = $total{$trans_date} + $$operation{$oid};
        $total_month{$date2} = $total_month{$date2} + $$operation{$oid};
        $grandtotal = $grandtotal + $$operation{$oid};
      }
      if($total{$trans_date} > $max) {
        $max = $total{$trans_date};
      }
      if($total_month{$date2} > $maxmonth) {
        $maxmonth = $total_month{$date2};
      }
    }
  }
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
    foreach my $key (sort keys %total_month) {
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

sub response_page {
  print "Content-Type: text/html\n\n";
  my($message) = @_;

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Response Page</title>\n";
  print "<link href=\"/css/style_reports.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  print "</head>\n";

  print "<body bgcolor=\"#ffffff\">\n";
  print "<table border=0 cellspacing=0 cellpadding=1 width=650>\n";
  print "<tr><td align=center colspan=4><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corporate Logo\"></td></tr>\n";
  print "<tr><td align=center colspan=4 class=\"larger\" bgcolor=\"#000000\"><font size=-1>Response Message</font></td></tr>\n";
  print "<tr><td>&nbsp;</td><td>&nbsp;</td><td colspan=2>&nbsp;</td></tr>\n";
  print "<tr><td colspan=4>$message</td></tr>\n";
  print "</table>\n";

  print "</body>\n";
  print "</html>\n";
  exit;
}


sub overview { 
  my ($reseller,$merchant) = @_;
  my ($db_merchant);
     
  my $dbh = &miscutils::dbhconnect("pnpmisc");
   
  if ($reseller eq "cableand") { 
    my $sth = $dbh->prepare(q{
        SELECT username  
        FROM customers
        WHERE reseller IN ('cableand','cccc','jncb','bdagov') 
        AND username=?
      }) or die "Can't do: $DBI::errstr";
    $sth->execute("$merchant") or die "Can't execute: $DBI::errstr";
    ($db_merchant) = $sth->fetchrow;  
    $sth->finish; 
  }  
  elsif ($reseller eq "stkittsn") {
    my $sth = $dbh->prepare(q{
        SELECT username
        FROM customers
        WHERE reseller IN ('skittsn','stkitts2')
        AND status<>'cancelled'
      }) or die "Can't prepare: $DBI::errstr";
    $sth->execute() or die "Can't execute: $DBI::errstr";
    while (my ($db_merchant) = $sth->fetchrow) {
      #push(@merchlist,"$db_merchant");
      $merchlist[++$#merchlist] = "$db_merchant";
    }
    $sth->finish;
  }
  else {
    my $sth = $dbh->prepare(q{ 
        SELECT username 
        FROM customers 
        WHERE reseller=?
        AND username=?
      }) or die "Can't do: $DBI::errstr";
    $sth->execute("$reseller","$merchant") or die "Can't execute: $DBI::errstr";
    ($db_merchant) = $sth->fetchrow; 
    $sth->finish;
  }
 
  $dbh->disconnect;
 
  return $db_merchant;
 
}

sub deny {
  &head();
  print "      <tr><td colspan=3 align=center> Currently unavailable.</td></tr>\n";
  print "      <tr><td colspan=3 align=center><input type=button value=\"Close Window\" onClick=\"window.close()\"></td></tr>\n";
  &tail();
}

sub head {
  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Merchant Administration Area</title>\n";
  #print "<base href=\"https://pay1.plugnpay.com\">\n";
  print "<link href=\"/css/style_reports.css\" type=\"text/css\" rel=\"stylesheet\">\n";

  print "<script type=\"text/javascript\">\n";
  print "<!-- Start Script\n";
  print "function uncheck(thisForm) {\n";
  print "  for (var k in thisForm.listval) {\n";
  print "    document.assemble.listval[k].checked = false\;\n";
  print "  }\n";
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

  print "</head>\n";

  print "<body bgcolor=\"#ffffff\">\n";

  print "<div align=center>\n";
  print "<table cellspacing=0 cellpadding=4 border=0 width=650>\n";
  print "<tr><td align=center colspan=4><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corporate Logo\"></td></tr>\n";
  #print "<tr><td align=center colspan=1><font size=4 face=\"Arial,Helvetica,Univers,Zurich BT\">\n";
}

sub tail {
  print "      </table>\n";
  print "    </div>\n";
  print "  </body>\n";
  print "</html>\n";
}

