package fraud;

use strict;
use miscutils;
use rsautils;
use MD5;
use constants qw(%constants::countries3to2);
use sysutils;
use PlugNPay::GatewayAccount;
use PlugNPay::CreditCard;
use PlugNPay::Environment;
use smpsutils;
use PlugNPay::Email;
use PlugNPay::Util::IP::Geo;
use PlugNPay::GatewayAccount;
use PlugNPay::Currency;

sub new {
  my $type = shift;
  my ($fconfig,$status,%query) = @_;
  %fraud::result = ();
  my (%fraud_config);
  %fraud::error = ();
  $fraud::version = "20041102.00001";
  $fraud_config{'status'} = $status;

  my @array = split(/\,/,$fconfig);
  foreach my $entry (@array) {
    my($name,$value) = split(/\=/,$entry);
    $fraud_config{$name} = $value;
    $fraud_config{'fraudtrack'} = 1;
  }

  if (($mckutils::query{'mode'} eq "bill_member") && ($fraud_config{'cvv'} == 1)) {
    $fraud_config{'cvv'} = 0;
  }

  if (($mckutils::query{'subacct'} =~ /vmicard/) && ($mckutils::query{'recflag'} == 1)) {
    $fraud_config{'cvv'} = 0;
  }

  if (($mckutils::query{'magstripe'} ne "") && ($fraud_config{'cvv'} == 1) && ($fraud_config{'cvv_swipe'} == 1)) {
    $fraud_config{'cvv'} = 0;
  }

  %fraud::fraud_config = %fraud_config;

  $fraud::cc = new PlugNPay::CreditCard($query{'card-number'});

  if ($fraud_config{'avs'} > 0) {
    $mckutils::query{'app-level'} = $fraud_config{'avs'};
  }
  if ($fraud_config{'avs_cvv'} == 1) {
    $mckutils::ignore_avs = 1;
  }

  $fraud::gatewayAccount = new PlugNPay::GatewayAccount($mckutils::query{'merchant'});

  return [], $type;
}


sub preauth_fraud_screen {
  my (@array) = @_;
  shift @array;
  my %query = @array;
  my (%error,%result,%timestamps);
  $fraud::shacardnumber = "";
  $fraud::cardnumber = "";
  $fraud::cardbin = substr($query{'card-number'},0,6);
  $fraud::bincountry = "";
  $fraud::cardtype = &miscutils::cardtype($query{'card-number'});
  $fraud::cardcategory = $fraud::cc->getCategory();
  @fraud::cardHashes = ();

  my %fraud_config = %fraud::fraud_config;

  $timestamps{'1start'} = time();

  my $checkProcessor = $fraud::gatewayAccount->getCheckProcessor();

  if (($query{'accttype'} =~ /^(checking|savings)$/) && ($query{'card-number'} eq "")) {
    $query{'accountnum'} =~ s/[^0-9]//g;
    $query{'routingnum'} =~ s/[^0-9]//g;
    if (($checkProcessor =~ /^telecheck/) && ($query{'micr'} =~ /[toaduTOADU]/)) {
      $query{'card-number'} = $query{'micr'};
    }
    elsif (($checkProcessor =~ /^(globaletel|securenetach)$/) && ($query{'micr'} =~ /[toaduTOADU]/)) {
      $query{'card-number'} = "$query{'micr'},$query{'routingnum'},$query{'accountnum'}";
    }
    else {
      $query{'card-number'} = "$query{'routingnum'} $query{'accountnum'}";
    }
  }

  if ($query{'card-number'} ne "") {
    my $cc = new PlugNPay::CreditCard($query{'card-number'});
    $fraud::shacardnumber = $cc->getCardHash();
    @fraud::cardHashes = $cc->getCardHashArray();
    $fraud::cardnumber = $query{'card-number'};
  }

  $timestamps{'2sha'} = time();

  $fraud::dbh = &miscutils::dbhconnect("fraudtrack");

  if ($ENV{'SCRIPT_NAME'} =~ /pnpremote|payremote/) {
    %error = &input_check(\%query);
    $timestamps{'3inputchk'} = time();
  }

  $fraud::exemptflag = &check_exempt(\%query);

  if (($mckutils::feature{'bindetails'} == 1) || ($fraud_config{'chkbin'} == 1) || ($fraud_config{'bankbin_reg'} == 1)) {
    %error = &check_bankbin(\%query);
  }

  if ($fraud_config{'fraudtrack'} == 1) {
    if ($fraud_config{'chkaccts'} ne "") {
      &acct_list(\%query);
    }

    if (($fraud_config{'blkvs'} == "1") || ($fraud_config{'blkmc'} == "1")
       || ($fraud_config{'blkax'} == "1") || ($fraud_config{'blkds'} == "1") || ($fraud_config{'blkdebit'} == 1) || ($fraud_config{'blkcredit'} == 1)) {
      %error = (%error,&check_cardtype(\%query));
    }

    if ($fraud_config{'reqfields'} == 1) {
      if ($mckutils::query{'posflag'} != 1) {
        %error = (%error,&required_fields(\%query));
      }
    }

    if ($fraud_config{'dupchk'} == 1) {
      if ($mckutils::query{'skipdupchk'} != 1) {
        %error = (%error,&check_duplicate(\%query));
      }
    }

    if ($error{'level'} < 1) {
      $timestamps{'4startpre'} = time();

      if ($fraud_config{'chkprice'} == 1) {
        &check_price(\%query);
      }

      if ($fraud::exemptflag != 1) {  ###  Moved This line to also be able to exclude frequency checking of CC#.  02/25/2003
        if (($fraud_config{'tdsRequireEnrollment'} > 0) && ($fraud::gatewayAccount->getTDSProcessor() ne "") && ($query{'tdsflag'} == 1) && ($fraud::cardtype =~ /VISA|MSTR/)) {
          %error = (%error,&check_3dEnrollment(\%query));
        }
        if ($fraud_config{'freqchk'} ne "") {
          %error = (%error,&check_frequency(\%query));  #Put Back
          $timestamps{'5freqchk'} = time();
        }
        if ($fraud::result{'seenbefore_checked'} != 1) {
          #&check_positive(\%query);    ##  Put back
          $timestamps{'6poschk'} = time();
        }
        if (($fraud::result{'seenbefore'} != 1) && ($mckutils::query{'acct_code3'} eq "")) {
          $mckutils::query{'acct_code3'} = "newcard";
        }
        if (($fraud_config{'blkfrgnrvs'} == "1") || ($fraud_config{'blkfrgnrmc'} == "1")) {
          %error = (%error,&block_frgncards(\%query));
          $timestamps{'7forgnchk'} = time();
        }
        if (($fraud_config{'blkcntrys'} == "1") && ($mckutils::feature{'postauthfraud'} !~ /blkcntrys/)) {
          %error = (%error,&block_countries(\%query));
          $timestamps{'8cntrychk'} = time();
        }
        if ($fraud_config{'blkemailaddr'} == "1") {
          %error =  (%error,&block_emailaddr(\%query));
        }
        if ($fraud_config{'blkbin'} == "1") {
          %error =  (%error,&block_bins(\%query));
          $timestamps{'9binchk'} = time();
        }
        elsif ($fraud_config{'allowbin'} == "1") {
          %error =  (%error,&allow_bins(\%query));
          $timestamps{'9binchk'} = time();
        }

        if ($fraud_config{'blkemails'} == "1") {
          %error = (%error,&block_email(\%query));
          $timestamps{'aemailchk'} = time();
        }
        if ($fraud_config{'blkphone'} == "1") {
          %error = (%error,&block_phone(\%query));
          $timestamps{'adphone'} = time();
        }
        if ($fraud_config{'blkipaddr'} == "1") {
          %error =  (%error,&block_ip(\%query));
          $timestamps{'bipaddrchk'} = time();
        }
        if ($fraud_config{'blksrcip'} == "1") {
          %error =  (%error,&block_srcip(\%query));
        }
        if ($fraud_config{'blkipcntry'} == "1") {
          %error =  (%error,&block_ipcntry(\%query));
        }
        if ($fraud_config{'blkproxy'} == "1") {
          %error = (%error,&block_proxy(\%query));
          $timestamps{'cproxychk'} = time();
        }
        if (($fraud_config{'matchcntry'} == "1") && ($mckutils::feature{'postauthfraud'} !~ /matchcntry/)) {
          %error = (%error,&match_cntrys(\%query));
          $timestamps{'dmatchcntrychk'} = time();
        }
        if ($fraud_config{'matchardef'} == "1") {
          %error = (%error,&match_ardef(\%query));
        }
        if ($fraud_config{'chkname'} == "1") {
          %error = (%error,&check_cardname(\%query));
          $timestamps{'echeckcardname'} = time();
        }
        if ($fraud_config{'netwrk'} ne "") {
        #  %error = (%error,&check_netwrk(\%query));
        #  $timestamps{'fchecknetwrk'} = time();
        }
        if ($fraud_config{'matchgeoip'} ne "") {
          %error = (%error,&check_geolocation(\%query));
          $timestamps{'hcheckgeoloc'} = time();
        }
        if ($fraud_config{'billship'} ne "") {
          %error = (%error,&check_billship(\%query));
        }
        if (($fraud_config{'highlimit'} ne "") && ($fraud_config{'fraudhold'} != 1)) {
          %error = (%error,&check_highlimit(\%query));
        }
        if ($fraud_config{'iovation'} ne "") {
          %error = (%error,&check_iovation(\%query));
        }
        if ($fraud_config{'eye4fraud'} ne "") {
          %error = (%error,&check_eye4fraud(\%query));
        }
      }
      else {
        if ($fraud::result{'seenbefore_checked'} != 1) {
          #&check_positive(\%query);   ## Put Back
          $timestamps{'6poschk'} = time();
        }
        if (($fraud::result{'seenbefore'} != 1) && ($mckutils::query{'acct_code3'} eq "")) {
          $mckutils::query{'acct_code3'} = "newcard";
        }
        $mckutils::query{'fexpt'} = "yes";
      }
    }
    if ($error{'level'} < 1) {
      if ($fraud_config{'iTransact'} ne "") {
        %error = (%error,&iTransact(\%query));
        if (exists $error{'iTransactResp'}) {
          %result = %error;
        }
        $timestamps{'gcheckiTrans'} = time();
      }
    }
  }

  if (($fraud_config{'status'} eq "live")
       && ($query{'nofraudcheck'} ne "yes")
       && ($query{'card-number'} ne "4111111111111111")
       && ($query{'paymethod'} ne "spendcash")
       && ($query{'paymethod'} ne "web900")) {
    %error =  (%error,&check_fraud(\%query));
    $timestamps{'efrauddbchk'} = time();
  }

  if ($error{'level'} > 0) {
    if (($mckutils::feature{'fraudhold'} == 1) || ($fraud_config{'fraudhold'} == 1)) {
      $mckutils::query{'fraudholdmsg'} = $error{'MErrMsg'};
      $mckutils::query{'fraudholdstatus'} = "hold";
    }
    else {
      $result{'MStatus'} = "badcard";
      $result{'success'} = "no";
      $result{'FinalStatus'} = "fraud";
      $result{'MErrMsg'} = $error{'MErrMsg'};
      $result{'resp-code'} = $error{'resp-code'};
      $result{'errdetails'} = $error{'errdetails'};
      $result{'errlevel'} = $error{'level'};
      my %query =(%query,%result);
      fraud_log(\%query);
      $timestamps{'ftranlog'} = time();
    }
  }
  elsif ($error{'dupchkstatus'} ne "") {
    $result{'MErrMsg'} = $error{'MErrMsg'};
    $result{'resp-code'} = $error{'resp-code'};
    $result{'errdetails'} = $error{'errdetails'};
    $result{'dupchkstatus'} = $error{'dupchkstatus'};
    $result{'dupchkmerch'} = $error{'dupchkmerch'};
    $result{'dupchkauthcode'} = $error{'dupchkauthcode'};
    $result{'dupchktrantime'} = $error{'dupchktrantime'};
    $result{'refnumber'} = $error{'refnumber'};
    $result{'FinalStatus'} = "fraud";
    my %query =(%query,%result);
    fraud_log(\%query);
    delete $result{'FinalStatus'};
  }

  $fraud::dbh->disconnect;

  my $record_fraud_times = 0;
  if ($record_fraud_times == 1) {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
    my $mo = sprintf("%02d",$mon+1);
    &sysutils::filelog("append",">>/home/p/pay1/database/debug/fraudtimes$mo.txt");
    open (TIMES,">>/home/p/pay1/database/debug/fraudtimes$mo.txt");
    my ($oldtime);
    print TIMES "$query{'merchant'}, ";
    foreach my $key (sort keys %timestamps) {
      my $delta = $timestamps{$key} - $oldtime;
      print TIMES "$key:$delta, ";
      if ($delta > 0) {
        $oldtime = $timestamps{$key};
      }
    }
    print TIMES "\n";
    close (TIMES);
  }

  %fraud::error = %error;
  return %result;
}


sub postauth_fraud_screen {
  my (@array) = @_;
  shift @array;
  my %query = @array;
  my (%result,%error);

  my $avs = substr($query{'avs-code'},0,3);
  $avs =~ s/[^A-Z]//g;
  $avs = substr($avs,-1,1);
  if($avs eq "") {
    $avs = "U";
  }

  if (($fraud::fraud_config{'fraudhold'} == 1) && ($fraud::fraud_config{'highlimit'} ne "")) {
    if (($fraud::fraud_config{'ignhighlimit'} == 1) && ($query{'cvvresp'} eq "M") && ($avs =~ /^(Y|X|D|M|F)$/)) {
      ### Skip High Limit Test
    }
    else {
      ### Do High Limit Test
      %error = (%error,&check_highlimit(\%query));
      if ($error{'level'} > 0) {
        $mckutils::query{'fraudholdmsg'} = $error{'MErrMsg'} . ":$avs:$query{'cvvresp'}";
        $mckutils::query{'fraudholdstatus'} = "hold";
      }
    }
  }

  if (($fraud::fraud_config{'matchcntry'} == "1") && ($mckutils::feature{'postauthfraud'} =~ /matchcntry/)) {
    %result = (%result,&match_cntrys2(\%query));
  }

  if (($fraud::fraud_config{'chkprepaid'} == "1") && ($mckutils::feature{'postauthfraud'} =~ /prepaid/)) {
    %result = (%result,&check_prepaid(\%query));
  }

  if (($fraud::fraud_config{'blkcntrys'} == "1") && ($mckutils::feature{'postauthfraud'} =~ /blkcntrys/)) {
    %result = (%result,&block_countries(\%query));
    if ($result{'level'} > 0) {
      $result{'FinalStatus'} = 'fraud';
    }
  }

  # Disable Cybersource
  #if (($fraud::fraud_config{'cybersource'} > 0) && ($query{'FinalStatus'} eq "success")) {
    #if ($query{'cvvresp'} ne "M") {
    #if ($query{'card-country'} ne "US") {
    #  %result = &cybersource(\%query);
    #}
    #}
  #}

  &insert_positive(\%query);  #Put Back

  return %result;
}


sub fraud_log {
  my ($datainfo) = @_;
  my ($connectflag);

  my ($trans_date,$trans_time) = &miscutils::gendatetime_only();

  open (FRAUD,">>/home/p/pay1/database/debug/fraud_debug_1.txt");
  print FRAUD "UN:$$datainfo{'publisher-name'}, OID:$$datainfo{'orderID'}, TIME:$trans_time, VER:$fraud::version";
  foreach my $key (sort keys %$datainfo) {
    if ($key =~ /^card-number|card_num|cardnum/i) {
      my $first6 = substr($$datainfo{$key},0,6);
      my $last2 = substr($$datainfo{$key},-2);
      my $CClen = length($$datainfo{$key});
      my $tmpCC = $$datainfo{$key};
      $tmpCC =~ s/./X/g;
      $tmpCC = $first6 . substr($tmpCC,6,$CClen - 8) . $last2;
      print FRAUD "$key:$tmpCC, ";
    }
    elsif (($key =~ /^(TrakData|magstripe)$/) && ($$datainfo{$key} ne "")) {
      print FRAUD "$key:Data Present:" . substr($$datainfo{$key},0,6) . "****" . substr($$datainfo{$key},-4) . ", ";
    }
    elsif ($key =~ /(card\-cvv|publisher\-password|card_code)/i) {
      my $aaaa = $$datainfo{$key};
      $aaaa =~ s/./X/g;
      print FRAUD "$key:$aaaa, ";
    }
    elsif ($$datainfo{$key} =~ /(3|4|5|6|7)\d{12,15}/) {
      my $tempVal = $$datainfo{$key};
      $tempVal =~ s/./X/g;
      print FRAUD "$key:$tempVal, ";
    }
    else {
      print FRAUD "$key:$$datainfo{$key}, ";
    }
  }
  print FRAUD "\n";
  close (FRAUD);

  my $acct_code  = substr($$datainfo{'acct_code'},0,20);
  my $acct_code2 = substr($$datainfo{'acct_code2'},0,20);
  my $acct_code3 = substr($$datainfo{'acct_code3'},0,20);
  my $subacct = substr($$datainfo{'subacct'},0,19);

  my $merrloc = "PlugnPay: Failed Fraud Screen ErrLevel:$$datainfo{'errlevel'} ";

  if (! $fraud::dbh) {
    $fraud::dbh = &miscutils::dbhconnect("fraudtrack");
    $connectflag = 1;
  }
  my $sth = $fraud::dbh->prepare(q{
        insert into fraud_log
        (username,orderid,trans_time,status,descr,acct_code,acct_code2,acct_code3,subacct)
        values (?,?,?,?,?,?,?,?,?)
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$datainfo);
  $sth->execute("$$datainfo{'publisher-name'}","$$datainfo{'orderID'}","$trans_time","badcard",
                "$merrloc","$acct_code","$acct_code2","$acct_code3","$subacct")
             or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$datainfo);
  $sth->finish;

  if ($connectflag == 1) {
    $fraud::dbh->disconnect;
  }

}

sub check_3dEnrollment {
  my ($query) = @_;
  # tdsEnrolledStatus = N | P

  my %error;
  if (($$query{'tdsEnrolledStatus'} eq "N") && ($fraud::fraud_config{'tdsRequireEnrollment'} > 0)) {
    $error{'level'} = 12;
    $error{'errdetails'} .= "card-number\|Non Enrolled in 3D program.\|";
    $error{'MErrMsg'} = "Authentication Failed - Your financial institution has indicated that your card is not enrolled in a 3D program.<br>\n";
    $error{'MErrMsg'} .= "To protect against unauthorized use, this card cannot be used to complete your purchase.  <br>You may complete the purchase by selecting another 3D enrolled credit card.";
  }
  elsif (($$query{'tdsEnrolledStatus'} eq "P") && ($fraud::fraud_config{'tdsRequireEnrollment'} > 1)) {
    $error{'level'} = 12;
    $error{'errdetails'} .= "card-number\|Non Enrolled in 3D program.\|";
    $error{'MErrMsg'} = "Authentication Failed - Your financial institution has indicated that it could not successfully authenticate this transaction.<br>\n";
    $error{'MErrMsg'} .= "To protect against unauthorized use, this card cannot be used to complete your purchase.  <br>You may complete the purchase by selecting another form of payment.";
  }
  return %error;
}

sub check_cardname {
  my ($query) = @_;
  my ($fname,$lname,$flen1,$llen1,$flen2,$llen2,%error);
  my $testname = $$query{'card-name'};
  $testname =~ s/[^a-zA-Z\ ]//g;
  my (@names) = split(/ +/,$testname);
  $fname = $names[0];
  $lname = $names[$#names];
  if (($lname =~ /(i|ii|iii|iv|v|vi|vii|viii|ix|x|jr|sr)\.?$/i) && ($#names > 1)) {
    $lname = $names[$#names-1] . " " . $names[$#names];
  }
  $flen1 = length($fname);
  $fname =~ s/aeiouy//g;
  $flen2 = length($fname);

  $llen1 = length($lname);
  $lname =~ s/aeiouy//g;
  $llen2 = length($lname);

  if (($llen1 < 2) || ($llen2 < 1) || (@names < 2)) {
    $error{'level'} = 12;
    $error{'errdetails'} .= "card-name\|Improper or illegal format for billing name.\|";
    $error{'MErrMsg'} .= "Improper or illegal format for billing name.\|";
  }
  return %error;
}

sub check_cardtype {
  my (%error);
  if (($fraud::fraud_config{'blkcredit'} == 1) && ($fraud::cardcategory !~ /debit/i)) {
    $error{'level'} = 14;
    $error{'errdetails'} .= "card-number\|Credit Cards are Blocked.\|";
    $error{'MErrMsg'} .= "Credit cards are not accepted.\|";
    return %error;
  }
  if (($fraud::fraud_config{'blkdebit'} == 1) && ($fraud::cardcategory =~ /debit/i)) {
    $error{'level'} = 14;
    $error{'errdetails'} .= "card-number\|Debit Cards are Blocked.\|";
    $error{'MErrMsg'} .= "Debit cards are not accepted.\|";
    return %error;
  }
  if (($fraud::fraud_config{'blkvs'} == 1) && ($fraud::cardtype eq "VISA")) {
    $error{'level'} = 14;
    $error{'errdetails'} .= "card-number\|Visas are Blocked.\|";
    $error{'MErrMsg'} .= "Visas Cards are not accepted.\|";
  }
  if (($fraud::fraud_config{'blkmc'} == 1) && ($fraud::cardtype eq "MSTR")) {
    $error{'level'} = 14;
    $error{'errdetails'} .= "card-number\|MasterCards are Blocked.\|";
    $error{'MErrMsg'} .= "MasterCards are not accepted.\|";
  }
  if (($fraud::fraud_config{'blkax'} == 1) && ($fraud::cardtype eq "AMEX")) {
    $error{'level'} = 14;
    $error{'errdetails'} .= "card-number\|AMEX cards are Blocked.\|";
    $error{'MErrMsg'} .= "AMEX Cards are not accepted.\|";
  }
  if (($fraud::fraud_config{'blkds'} == 1) && ($fraud::cardtype eq "DSCR")) {
    $error{'level'} = 14;
    $error{'errdetails'} .= "card-number\|Discover Cards are Blocked.\|";
    $error{'MErrMsg'} .= "Discover cards are not accepted.\|";
  }
  return %error;
}


sub check_price {
  my ($query) = @_;
  open (FRAUD,">>/home/p/pay1/database/debug/fraud_debug_chkprice.txt");
  print FRAUD "UN:$$query{'merchant'}, OID:$$query{'orderID'}, EC:$$query{'easycart'}, ";

  if ($$query{'easycart'} == 1) {
    for(my $i=1; $i<=$mckutils::max; $i++) {
      my $item = $$query{"item$i"};
      my $sth = $fraud::dbh->prepare(qq{
      select cost
      from costdata
      where entry=?
      and username=?
      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query);
      $sth->execute($item,$$query{'merchant'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
      my ($price) = $sth->fetchrow;
      $price =~ s/[^0-9\.]//g;
      $sth->finish;
      if ($price > $mckutils::query{"cost$i"}) {
        $$query{"cost$i"} = $price;
        $mckutils::query{"cost$i"} = $price;
      }
      print FRAUD "$item:$price:$mckutils::query{\"cost$i\"}, ";
    }
    &mckutils::shopdata();
    &mckutils::calculate_discnt();
    $mckutils::query{'card-amount'} = $mckutils::query{'subtotal'} + $mckutils::query{'shipping'} + $mckutils::query{'tax'};
    $mckutils::query{'card-amount'} = sprintf("%.2f", $mckutils::query{'card-amount'});
    $$query{'card-amount'} = $mckutils::query{'card-amount'};
  }

  print FRAUD "\n";
  close (FRAUD);
  return;
}

sub check_frequency {
  my ($query) = @_;

  if (-e "/home/p/pay1/outagefiles/stop_positive.txt") {
    return;
  }
  my ($level,$days,$hours) = split(/\:/,$fraud::fraud_config{'freqchk'});

  my $timeadjust = ($days * 24 * 3600) + ($hours * 3600);
  my ($dummy1,$datestr1,$timestr1) = &miscutils::gendatetime("-$timeadjust");

  my ($db_cyberscore,$trans_time,$result,%result,%error);
  my $freq_cnt = 0;

  if ($fraud::shacardnumber ne "") {
    my $cardHashQmarks = '?' . ',?'x($#fraud::cardHashes);
    my $sth = $fraud::dbh->prepare(qq{
        select cyber_score,trans_time,result
        from positive
        where shacardnumber IN ($cardHashQmarks)
        and trans_time>?
        and username=?
        and result=?
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
    $sth->execute(@fraud::cardHashes,$timestr1,$$query{'merchant'},'success') or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
    $sth->bind_columns(undef,\($db_cyberscore,$trans_time,$result));
    while ($sth->fetch) {
      $freq_cnt++;
      if ($db_cyberscore >= 0) {  ####  Remove for Production
        $fraud::result{'seenbefore'} = 1;
      }
    }
    $sth->finish;
  }

  if ($fraud::result{'seenbefore'} == 1 ) {
    $fraud::result{'seenbefore_checked'} = 1;
  }
  $mckutils::freqcnt = "CNT:$freq_cnt:LEV:$level";
  if (($freq_cnt >= $level) && ($ENV{'SCRIPT_NAME'} !~ /smps\.cgi$/)) {
    my ($trans_date,$trans_time) = &miscutils::gendatetime_only();
    open (FRAUD,">>/home/p/pay1/database/debug/fraud_debug_freqcnt.txt");
    print FRAUD "PCHNG TIME:$trans_time, UN:$$query{'merchant'}, FREQCNT:$mckutils::freqcnt, OID:$$query{'orderID'}\n";
    close (FRAUD);
  }

  if (($freq_cnt >= $level) && ($ENV{'SCRIPT_NAME'} !~ /smps\.cgi$/)) {
    $error{'level'} = 10;
    $error{'errdetails'} .= "card-number\|Too many transactions within allotted time.\|";
    $error{'MErrMsg'} .= "Too many transactions within allotted time.\|";
    $error{'resp-code'} = "P73";
  }
  return %error;
}


sub check_positive {
  my ($query) = @_;
  my $timeadjust = (180 * 24 * 3600);
  my ($dummy1,$datestr1,$timestr1) = &miscutils::gendatetime("-$timeadjust");
  my ($db_cyberscore,$trans_time,$result);
  $fraud::result{'seenbefore'} = 0;
  if ($fraud::shacardnumber ne "") {
    my $cardHashQmarks = '?' . ',?'x($#fraud::cardHashes);
    my $sth = $fraud::dbh->prepare(qq{
        select cyber_score,trans_time,result
        from positive
        where shacardnumber IN ($cardHashQmarks)
        and trans_time>?
        and username=?
        and result=?
        and cyber_score<=?
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query);
    $sth->execute(@fraud::cardHashes,$timestr1,$$query{'merchant'},'success',$fraud::fraud_config{'cybersource'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
    $sth->bind_columns(undef,\($db_cyberscore,$trans_time,$result));
    while ($sth->fetch) {
      $fraud::result{'seenbefore'} = 1;
    }
    $sth->finish;
  }
  $fraud::result{'seenbefore_checked'} = 1;
}


sub check_duplicate {
  my ($query) = @_;
  my ($timeadjust,%error);

  if ($$query{'acct_code'} eq "PremierGift") {
    return;
  }

  $fraud::fraud_config{'dupchktime'} =~ s/[^0-9]//g;
  if (($fraud::fraud_config{'dupchktime'} < 1) || ($fraud::fraud_config{'dupchktime'} > 9999)) {
    $fraud::fraud_config{'dupchktime'} = "5";
  }
  $timeadjust = $fraud::fraud_config{'dupchktime'} * 60;

  my ($dummy1,$datestr1,$timestr1) = &miscutils::gendatetime("-$timeadjust");
  my $price = "$$query{'currency'} $$query{'card-amount'}";
  my $cardHashQmarks = '?' . ',?'x($#fraud::cardHashes);

  my @qarray = ();
  my $qqstr = "";
  my $qstr = "select username,authstatus,orderid,auth_code,authtime ";
  $qstr .= "from operation_log FORCE INDEX(oplog_tdatesha_idx) where trans_date>=? and shacardnumber IN ($cardHashQmarks) and username IN (";
  @qarray = ($datestr1,@fraud::cardHashes);

  my @merchtest = ();
  my @un_array = ();
  if (exists $mckutils::feature{'dupchklist'}) {
    @merchtest = split(/\|/,$mckutils::feature{'dupchklist'});
    foreach my $var (@merchtest) {
      $qqstr .= "?,";
      push @un_array, $var;
    }
    chop $qqstr;
  }
  else {
    push @un_array, $$query{'merchant'};
    $qqstr = "?";
  }
  push @qarray, @un_array;

  $qstr .= "$qqstr) ";
  $qstr .= "and authtime>=? and authstatus=? and amount=? and (voidstatus is NULL or voidstatus='') ";
  push @qarray, $timestr1, 'success',  $price, ;

  if ($fraud::fraud_config{'dupchkvar'} =~ /^(acct_code|acct_code2|acct_code3)$/) {
    $qstr .= "and $fraud::fraud_config{'dupchkvar'}=?  ";
    push @qarray, $$query{$fraud::fraud_config{'dupchkvar'}};
  }

  my ($test,$finalstatus,$orderid,$auth_code,$trans_time);

  if ($fraud::shacardnumber ne "") {
    my $dbh = &miscutils::dbhconnect("pnpdata"); ## Trans_log
    my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query);
    $sth->execute(@qarray) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
    ($test,$finalstatus,$orderid,$auth_code,$trans_time) = $sth->fetchrow;
    $sth->finish;
    $dbh->disconnect;
  }

  if ($test ne "") {
    if ($fraud::fraud_config{'dupchkresp'} ne "echo") {
      $error{'level'} = 17;
      $error{'errdetails'} .= "card-number\|Duplicate.  Same Cardnumber and dollar amount processed within allowed window.\|";
      $error{'MErrMsg'} .= "Duplicate Transaction Suspected with $orderid, $test.  If this is an error, Wait $fraud::fraud_config{'dupchktime'} minutes and try again.|";
      $error{'resp-code'} = "P76";
      $error{'dupchkmerch'} = $test;
      $error{'dupchktrantime'} = $trans_time;
    }
    else {
      $error{'dupchkstatus'} = $finalstatus;
      $error{'MErrMsg'} .= "Duplicate Transaction Suspected with $orderid, $test.";
      #$error{'refnumber'} = "$orderid:" . substr($auth_code,0,6);
      $error{'refnumber'} = "$orderid";
      $error{'errdetails'} .= "card-number\|Duplicate.  Same Cardnumber and dollar amount processed within allowed window.\|";
      $error{'resp-code'} = "P76";
      $error{'dupchkmerch'} = $test;
      $error{'dupchkauthcode'} = substr($auth_code,0,6);
      $error{'dupchktrantime'} = $trans_time;
    }
  }
  return %error;
}


sub check_exempt {
  my ($query) = @_;
  my ($exemptflag);
  if ($fraud::shacardnumber ne "") {
    my $cardHashQmarks = '?' . ',?'x($#fraud::cardHashes);
    my $sth = $fraud::dbh->prepare(qq{
        select username
        from fraud_exempt
        where shacardnumber IN ($cardHashQmarks)
        and username=?
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query);
    $sth->execute(@fraud::cardHashes,$$query{'merchant'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
    my ($test) = $sth->fetchrow;
    $sth->finish;
    if ($test ne "") {
      $exemptflag = 1;
    }
  }
  return $exemptflag;
}

sub check_negative {
  my ($query) = @_;
  my (%error);
  my $timeadjust = (180 * 24 * 3600);
  my ($dummy1,$datestr1,$timestr1) = &miscutils::gendatetime("-$timeadjust");
  if ($fraud::shacardnumber ne "") {
    my $cardHashQmarks = '?' . ',?'x($#fraud::cardHashes);
    my $sth = $fraud::dbh->prepare(qq{
        select trans_time
        from negative
        where shacardnumber IN ($cardHashQmarks)
        and username=?
        and trans_time>?
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query);
    $sth->execute(@fraud::cardHashes,$$query{'merchant'},$timestr1) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query);
    my ($test) = $sth->fetchrow;
    $sth->finish;
    if ($test ne "") {
      $error{'level'} = 11;
      $error{'errdetails'} .= "card-number\|Credit Card Number appears in negative database.\|";
      $error{'MErrMsg'} .= "Credit Card Number appears in negative database.|";
    }
  }
  return %error;
}


sub insert_positive {
  #if ($fraud::result{'seenbefore'} == 1) {
  #  return;
  #}
  my ($query) = @_;

  my ($trans_date,$trans_time) = &miscutils::gendatetime_only();
  if ($fraud::shacardnumber ne "") {
    my $dbh = &miscutils::dbhconnect("fraudtrack");
    my $sth = $dbh->prepare(qq{
        insert into positive
        (shacardnumber,username,trans_time,cyber_score,result,orderid)
        values (?,?,?,?,?,?)
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query);
    $sth->execute("$fraud::shacardnumber","$$query{'publisher-name'}","$trans_time","$$query{'score_score_result'}","$$query{'FinalStatus'}","$$query{'orderID'}")
             or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
    $sth->finish;
    $dbh->disconnect;
  }
  else {
    open (FRAUD,">>/home/p/pay1/database/debug/missing_sha_debug.txt");
    print FRAUD "MISSING SHA:$$query{'merchant'},$trans_time,$$query{'FinalStatus'},$$query{'orderID'}\n";
    close (FRAUD);
  }
}

sub check_geolocation {
  my ($query) = @_;
  my (%error,$w,$x,$y,$z,$elapse,$stime,$etime,$country,$ipnum_from,$ipnum_to,$ipnum,$ipaddr);

  if (($ENV{'SCRIPT_NAME'} =~ /pnpremote|systech|xml/)) {
    $ipaddr = $$query{'ipaddress'};
  }
  else {
    my $environment = new PlugNPay::Environment();
    $ipaddr = $environment->get('PNP_CLIENT_IP');
  }

  if ($ipaddr !~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/) {
    return;
  }

  $w = $1;
  $x = $2;
  $y = $3;
  $z = $4;

  if (-e "/home/p/pay1/outagefiles/stop_geolocation.txt") {
    return;
  }

  $ipnum = int(16777216*$w + 65536*$x + 256*$y + $z);

  if (length($ipnum) > 11) {
    return;
  }

  $stime = time();

  my $geoIP = new PlugNPay::Util::IP::Geo();
  $country = $geoIP->lookupCountryCode($ipaddr);

  if ($country =~ /^(UK|GB)$/) {
    $country = "UK|GB";
  }

  $etime = time();
  $elapse = $etime - $stime;

  my ($dummy,$datestr,$timestr) = &miscutils::gendatetime();
  open (LOG,">>/home/p/pay1/database/debug/geolocation_cnt.txt");
  print LOG "DATE:$datestr, UN:$$query{'publisher-name'}, IP:$ipaddr, Co:$country, ETIME:$elapse, SCRIPT:$ENV{'SCRIPT_NAME'}, OID:$$query{'orderID'}, ";
  print LOG "\n";
  close (LOG);

  if (($country ne "") && ($$query{'card-country'} ne "") && ($$query{'card-country'} !~ /^($country)$/)) {
    $error{'level'} = 17;
    $error{'errdetails'} .= "card-country\|Billing country does not match ipaddress country.\|";
    $error{'MErrMsg'} .= "Billing country does not match ipaddress country.|";
    $error{'resp-code'} = "P68";
    $$query{'ipcountry'} = $country;
  }

  $$query{'geocountry'} = "$country";

  return %error;
}

sub check_billship {
  my ($query) = @_;
  my (%error);

  my $billaddress = "$$query{'card-address1'}$$query{'card-address2'}$$query{'card-city'}$$query{'card-state'}$$query{'card-zip'}";
  my $shipaddress = "$$query{'address1'}$$query{'address2'}$$query{'city'}$$query{'state'}$$query{'zip'}";

  $billaddress =~ tr/A-Z/a-z/;
  $billaddress =~ s/[^a-z0-9]//g;

  $shipaddress =~ tr/A-Z/a-z/;
  $shipaddress =~ s/[^a-z0-9]//g;

  if (($shipaddress ne "") && ($billaddress ne "") && ($billaddress ne $shipaddress)) {
    $error{'level'} = 19;
    $error{'errdetails'} .= "card-address1\|Billing address does not match Shipping address.\|";
    $error{'MErrMsg'} .= "Billing address does not match Shipping address.|";
    $error{'resp-code'} = "P68";
  }

  return %error;
}

sub check_highlimit {
  my ($query) = @_;
  my (%error);

  if ($$query{'card-amount'} > $fraud::fraud_config{'highlimit'}) {
    $error{'level'} = 20;
    $error{'errdetails'} .= "card-amount\|Transaction amount exceeds limit.\|";
    $error{'MErrMsg'} .= "Transaction amount exceeds limit.|";
    $error{'resp-code'} = "P68";
  }

  return %error;
}

sub input_check {
  my ($query) = @_;
  # Allowed Card Lengths
  my(%calc_state,%error);

  if ($$query{'paymethod'} =~ /web900/i) {
    if ($$query{'web900-pin'} eq "") {
      $error{'level'} = 1;
      $error{'errdetails'} = "web900-pin\|No web 900 pin number entered.\|";
      $error{'MErrMsg'} = "Pin number Missing.\|";
      $error{'resp-code'} = "P51";
    }
  }
  elsif ($$query{'paymethod'} =~ /teleservice/i) {
    my (%pin,$pin,$amt,$status);
    $$query{'pinnumber'} =~ s/[^0-9a-zA_Z]//g;
    my $publishername = $$query{'publisher-name'};
    $publishername =~ s/[^0-9a-zA-Z]//g;
    &sysutils::filelog("read","/home/p/pay1/web/payment/recurring/$publishername/admin/web900.txt");
    open(PIN,"/home/p/pay1/web/payment/recurring/$publishername/admin/web900.txt");
    while(<PIN>) {
      chop;
      ($pin,$amt,$status) = split('\t');
      $pin{$_} = $status;
    }
    close(PIN);
    if ((length($$query{'pinnumber'}) < 5) || ($pin{$$query{'pinnumber'}} ne "") || ($$query{'card-amount'} ne $amt)) {
      $error{'level'} = 1;
      $error{'errdetails'} = "pinnumber\|PIN Invalid.\|";
      $error{'MErrMsg'} = "Pin number missing or invalid.\|";
      $error{'resp-code'} = "P51";
    }
  }
  elsif (($$query{'paymethod'} =~ /onlinecheck/i) || ($$query{'accttype'} =~ /^(checking|savings)$/)) {
    if (length($$query{'accountnum'}) < 5) {
      $error{'level'} = 1;
      $error{'errdetails'} = "accountnum\|Account Number less than 5 characters.\|";
      $error{'MErrMsg'} = "Invalid Bank Account Number.\|";
      $error{'resp-code'} = "P52";
    }
    $$query{'routingnum'} =~ s/[^0-9]//g;
    my $test = &miscutils::mod10($$query{'routingnum'});
    if ((length($$query{'routingnum'}) != 9) || ($test eq "failure")){
      $error{'level'} = 1;
      $error{'errdetails'} .= "routingnum\|Routing  Number failed MOD10 test.\|";
      $error{'MErrMsg'} .= "Invalid Bank Routing  Number.\|";
      $error{'resp-code'} = "P53";
    }
    #if (length($$query{'checknum'}) < 1) {
    #  $error{'level'} = 1;
    #  $error{'errdetails'} .= "checknum\|Check Sequence Number Missing.\|";
    #  $error{'MErrMsg'} .= "Check Sequence Number Missing.\|";
    #  $error{'resp-code'} = "P54";
    #}
  }
  elsif ($$query{'paymethod'} =~ /invoice/i) {

  }
  elsif ($$query{'paymethod'} =~ /mocapay/i) {
    if ($$query{'phone'} eq "") {
      $error{'level'} = 1;
      $error{'errdetails'} = "phone\|No phone number entered.\|";
      $error{'MErrMsg'} = "Phone number Missing.\|";
      $error{'resp-code'} = "P51";
    }
    if ($$query{'card-number'} eq "") {
      $error{'level'} = 1;
      $error{'errdetails'} = "card-number\|MocaPay Code Missing.\|";
      $error{'MErrMsg'} = "MocaPay Code Missing.\|";
      $error{'resp-code'} = "P51";
    }
  }
  elsif ( (($$query{'paymethod'} eq "mpgiftcard") || ($$query{'mpgiftcard'} ne "")) && ($mckutils::feature{'acceptgift'} == 1)) {
    if (length $$query{'mpgiftcard'} < 10) {
      $error{'level'} = 1;
      $error{'MErrMsg'} = "No Gift Card number entered or invalid length.";
      $error{'errdetails'} = "mpgiftcard\|Invalid Length.\|";
      $error{'resp-code'} = "P54";
    }
  }
  elsif (($mckutils::processor eq "psl")  && ($$query{'transflags'} =~ /issue/i)) {

  }
  elsif ($fraud::cardtype =~ /^(PL)$/) {

  }
  else {
    my $CCtest = $$query{'card-number'};
    $CCtest =~ s/[^0-9]//g;
    my $luhntest = &miscutils::luhn10($CCtest);
    if ($luhntest eq "failure") {
      $error{'level'} = 1;
      $error{'errdetails'} =  "card-number\|Card Number fails LUHN - 10 check.\|";
      $error{'MErrMsg'} =  "Invalid Credit Card Number.\|";
      $error{'resp-code'} = "P55";
    }
# && ($$query{'card-cvv'} ne "")  Why was this in the line below ?
    if (($fraud::fraud_config{'cvv'} == 1) && ($fraud::cardtype =~ /^(VISA|MSTR)/) && (! exists $$query{'magstripe'}) && ($$query{'transflags'} !~ /recurring/) && ($$query{'acct_code4'} !~ /authprev/)) {
      if ((length($$query{'card-cvv'}) != 3) && (length($$query{'card-cvv'}) != 4)) {
        $error{'level'} = 1;
        $error{'errdetails'} .= "card-cvv\|CVV invalid length.\|";
        $error{'MErrMsg'} .= "Invalid Credit Card CVV2/CVC2 Number.\|";
        $error{'resp-code'} = "P56";
      }
      my $a = substr($$query{'card-number'},-4);
      if ($$query{'card-cvv'} eq $a) {
        $error{'level'} = 1;
        $error{'errdetails'} .= "card-cvv\|CVV invalid format.\|";
        $error{'MErrMsg'} .= "Invalid Credit Card CVV2/CVC2 Format.\|";
        $error{'resp-code'} = "P64";
      }
    }
    elsif (($fraud::cardtype =~ /^(KC1)/) && (! exists $$query{'magstripe'}) && ($$query{'transflags'} !~ /recurring/) && ($$query{'acct_code4'} !~ /authprev/)) {
      my ($expmo,$expyr) = split('\/',$$query{'card-exp'});
      my $datetest = "20" . $expyr . $expmo;
      if (    ( (substr($$query{'card-number'},0,9) >= 777000000) && (substr($$query{'card-number'},0,9) < 777580000) && ($datetest > 200810) )
           || ( (substr($$query{'card-number'},0,9) >= 777581000) && (substr($$query{'card-number'},0,9) < 777773000) && ($datetest > 200810) )
           || ( (substr($$query{'card-number'},0,9) >= 777740000) && (substr($$query{'card-number'},0,9) < 777777055) && ($datetest > 200810) )
           || ( (substr($$query{'card-number'},0,9) >= 777777055) && (substr($$query{'card-number'},0,9) < 777777056) && ($datetest > 201411) )
           || ( (substr($$query{'card-number'},0,9) >= 777777056) && (substr($$query{'card-number'},0,9) < 777777800) && ($datetest > 200810) )
         ) {
        if ((length($$query{'card-cvv'}) != 3) && (length($$query{'card-cvv'}) != 4)) {
          $error{'level'} = 1;
          $error{'errdetails'} .= "card-cvv\|CVV invalid length.\|";
          $error{'MErrMsg'} .= "Invalid Credit Card CVV2/CVC2 Number.\|";
          $error{'resp-code'} = "P56";
        }
      }
    }
    my ($dummy,$date);
    ($date) = &miscutils::gendatetime_only();
    my $year_exp = substr($$query{'card-exp'},-2);
    my $exptst1 =  $year_exp + 2000;
    my $mon_exp = substr($$query{'card-exp'},0,2);
    $exptst1 .= $mon_exp;
    my $exptst2 =  substr($date,0,6);

    ### Added DCP 20080916 For Testing.
    if (($exptst1 < $exptst2) && ($$query{'transflags'} !~ /recurring/)) {
      $error{'level'} = 1;
      $error{'errdetails'} .= "card-exp\|Expiration Date Expired.\|";
      $error{'MErrMsg'} .= "Credit Card Expiration Date Expired.\|";
      $error{'resp-code'} = "P57";
    }
  }
  if (exists $$query{'required'}) {
    $$query{'required'} =~ s/\,/\|/g;
  }
  my (@check) = split('\|',$$query{'required'});
  my ($var);
  foreach $var (@check) {
    my $val = $$query{$var};
    $val =~ s/[^a-zA-Z0-9]//g;
    if (length($val) < 1) {
      $error{'level'} = 1;
      $error{'errdetails'} .= "$var\|Data Missing/Invalid.\|";
      $error{'MErrMsg'} .= "Data Missing/Invalid: $var.\|";
      $error{'resp-code'} = "P58";
    }
  }

  # Zip Code Test
  #my $path_zipcode = "/home/p/pay1/web/payment/zipdb";
  my ($reject_on_mismatch,%zipcode);
  #dbmopen(%zipcode,"$path_zipcode",0666);
  if (($$query{'card-country'} eq "US") && ($$query{'card-zip'} ne "") && ($$query{'card-state'} ne "")) {
    $$query{'card-state'} =~ tr/a-z/A-Z/;
    my $teststate = $$query{'card-state'};
    $teststate =~ s/[^A-Z]//g;
    $teststate = substr($teststate,0,2);

    $$query{'card-zip'} =~ s/[^0-9]//g;
    my $zipkey = substr($$query{'card-zip'},0,5);

    my $sth = $fraud::dbh->prepare(qq{
          select state,city,county
          from zipcodes
          where zipcode=?
       }) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
    $sth->execute($zipkey) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
    my ($zipstate,$zipcity,$zipcounty) = $sth->fetchrow;
    $sth->finish;

    if (($zipstate ne "AP") && ($zipstate !~ /$teststate/i) && ($fraud::fraud_config{'matchzip'} == 1)) {
      $error{'level'} = 1;
      $error{'errdetails'} .= "card-zip\|Zip Code/Billing State do not match.\|";
      $error{'MErrMsg'} .= "Zip Code does not match Billing State.\|";
      $error{'resp-code'} = "P60";
    }
    if (($zipstate eq "") && ($fraud::fraud_config{'matchzip'} == 1)) {
      $error{'level'} = 1;
      $error{'errdetails'} .= "card-zip\|Invalid Billing Zip Code.\|";
      $error{'MErrMsg'} .= "Billing Address Zip Code is invalid.\|";
      $error{'resp-code'} = "P61";
    }
    $fraud::calc_state{'card-state'} = $zipstate;
  }
  if (($$query{'shipinfo'} eq "1") && ($$query{'zip'} ne "") && ($$query{'country'} eq "US")
       && ($$query{'state'} ne "") && ($fraud::fraud_config{'matchzip'} == 1)) {
    $$query{'state'} =~ tr/a-z/A-Z/;
    my $teststate = $$query{'state'};
    $teststate =~ s/[^A-Z]//g;
    $teststate = substr($teststate,0,2);

    $$query{'zip'} =~ s/[^0-9]//g;
    my $zipkey = substr($$query{'zip'},0,5);

    my $sth = $fraud::dbh->prepare(qq{
          select state,city,county
          from zipcodes
          where zipcode=?
       }) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
    $sth->execute($zipkey) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
    my ($zipstate,$zipcity,$zipcounty) = $sth->fetchrow;
    $sth->finish;

    if (($zipstate ne "AP") && ($zipstate !~ /$teststate/i)) {
      $error{'level'} = 1;
      $error{'errdetails'} .= "zip\|Zip Code/Shipping State do not match.";
      $error{'MErrMsg'} .= "Zip Code does not match Shipping State.";
      $error{'resp-code'} = "P62";
    }
    if ($zipstate eq "") {
      $error{'level'} = 1;
      $error{'errdetails'} .= "zip\|Invalid Shipping Zip Code.\|";
      $error{'MErrMsg'} .= "Shipping Address Zip Code is invalid.\|";
      $error{'resp-code'} = "P63";
    }
    $fraud::calc_state{'state'} = $zipstate;
  }
  #dbmclose(%zipcode);


  #Email Test
  if ($$query{'required'} =~ /email/) {
    my $position = index($$query{'email'},"\@");
    my $position1 = rindex($$query{'email'},"\.");
    my $elength  = length($$query{'email'});
    my $pos1 = $elength - $position1;

    if (($position < 1)
       || ($position1 < $position)
       || ($position1 >= $elength - 2)
       || ($elength < 5)
       || ($position > $elength - 5)
    ) {
      $error{'level'} = 1;
      $error{'errdetails'} .= "email\|Invalid/Missing Email Address. \|";
      $error{'MErrMsg'} .= "Invalid/Missing Email Address.\|";
      $error{'resp-code'} = "P59";
    }
  }
  return %error;
}

sub match_cntrys {
  my ($query) = @_;
  my (%error);
  if ($fraud::bincountry eq "") {
    my $sth = $fraud::dbh->prepare(qq{
           select country
           from master_bins
           where binnumber=?
    });
    $sth->execute($fraud::cardbin) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
    ($fraud::bincountry) = $sth->fetchrow;
    $sth->finish;
  }
  open (DEBUG,">>/home/p/pay1/database/debug/bindebug.txt");
  print DEBUG "COUNTRY:$fraud::bincountry, CARDBIN:$fraud::cardbin, CARDDOUNTRY:$$query{'card-country'}\n";
  close(DEBUG);

  if (($fraud::bincountry ne "") && ($fraud::bincountry ne $$query{'card-country'})) {
    if (($fraud::bincountry =~ /^(AU|NZ)$/) && ($$query{'card-country'} =~ /^(AU|NZ)$/)) {
      return;
    }
    $error{'level'} = 9;
    $error{'errdetails'} .= "card-country\|Billing country does not match card issuing country. - $$query{'card-country'}:$fraud::bincountry\|";
    $error{'MErrMsg'} .= "Billing country does not match card issuing country.|";
    my @array = (%$query,%error);
    #&support_email(@array);
  }
  #return %error;
  return;
}


sub match_cntrys1 {
  my ($query) = @_;
  my (%error);
  if ($fraud::bincountry eq "") {
    my $sth = $fraud::dbh->prepare(qq{
           select country
           from master_bins1
           where startbin<=?
           and endbin>?
    });
    $sth->execute($fraud::cardbin,$fraud::cardbin) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
    ($fraud::bincountry) = $sth->fetchrow;
    $sth->finish;
  }
  if (($fraud::bincountry ne "") && ($fraud::bincountry ne $$query{'card-country'})) {
    $error{'level'} = 9;
    $error{'errdetails'} .= "card-country\|Billing country does not match card issuing country.\|";
    $error{'MErrMsg'} .= "Billing country does not match card issuing country.|";
  }
  return %error;
}



sub match_cntrys2 {
  ## DCP 20110115 - PostAuth Fraud Chk of country
  my ($query) = @_;
  my (%error);

  if (($mckutils::query{'bbin_country'} eq "") || ($$query{'card-country'} eq "")) {
    return;
  }
  elsif (($mckutils::query{'bbin_country'} ne $$query{'card-country'})) {
    $error{'FinalStatus'} = "fraud";
    $error{'level'} = 9;
    $error{'errdetails'} .= "card-country\|Billing country does not match card issuing country.\|";
    $error{'MErrMsg'} .= "Billing country does not match card issuing country.|";
  }
  return %error;
}


sub check_prepaid {
  ## DCP 20110115 - PostAuth Fraud Chk of Prepaid Cards
  my ($query) = @_;
  my (%error);

  if ($mckutils::query{'bbin_debit'} eq "") {
    return;
  }
  elsif ($mckutils::query{'bbin_debit'} eq "PPD") {
    $error{'FinalStatus'} = "fraud";
    $error{'level'} = 9;
    $error{'errdetails'} .= "card-number\|Prepaid cards not accepted.\|";
    $error{'MErrMsg'} .= "Prepaid cards not accepted.|";
  }
  return %error;
}


sub match_ardef {
  my ($query) = @_;
  my (%error,$testcurr);
  my $testbin = $fraud::cardbin . "000";
  if ($fraud::bincountry eq "") {
    my $sth = $fraud::dbh->prepare(qq{
           select currency
           from master_ardef
           where startbin<=?
           and endbin>=?
    });
    $sth->execute($testbin,$testbin) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
    ($testcurr) = $sth->fetchrow;
    $sth->finish;
  }

  my $currencyObj = new PlugNPay::Currency($testcurr);
  my $ardefcurr = $currencyObj->getCurrencyCode();
  #  Skips Test if Bin not present in File - Under Review 11/01/2000
  open (DEBUG,">>/home/p/pay1/database/debug/ardefdebug.txt");
  print DEBUG "COUNTRY:$ardefcurr, CURR:$testcurr, CARDBIN:$fraud::cardbin, CARDDOUNTRY:$$query{'card-country'}, TESTBIN:$testbin\n";
  close(DEBUG);
  $$query{'cardcurrency'} = $ardefcurr;
  if (($ardefcurr ne "") && ($ardefcurr ne $$query{'card-country'})) {
    if (($ardefcurr =~ /^(AU|NZ)$/) && ($$query{'card-country'} =~ /^(AU|NZ)$/)) {
      return;
    }
    $error{'level'} = 9;
    $error{'errdetails'} .= "card-country\|Billing country does not match currency of card. - $$query{'card-country'}:$ardefcurr\|";
    $error{'MErrMsg'} .= "Billing country does not match currency of card.|";
    my @array = (%$query,%error);
  }
  #return %error;
  return;
}

sub block_frgncards {
  my ($query) = @_;
  my (%error);
  if ($fraud::bincountry eq "") {
    my $sth = $fraud::dbh->prepare(qq{
           select country
           from master_bins
           where binnumber=?
    });
    $sth->execute($fraud::cardbin) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
    ($fraud::bincountry) = $sth->fetchrow;
    $sth->finish;
  }

  if (($fraud::bincountry ne "US") && ($fraud::fraud_config{'blkfrgnvs'} == 1) && ($fraud::cardtype eq "VISA")) {
    $error{'level'} = 2;
    $error{'errdetails'} .= "card-number\|Foreign Visas are Blocked. - $fraud::bincountry\|";
    $error{'MErrMsg'} .= "Foreign Visas are not accepted.\|";
  }
  if (($fraud::bincountry ne "US") && ($fraud::fraud_config{'blkfrgnmc'} == 1) && ($fraud::cardtype eq "MSTR")) {
    $error{'level'} = 2;
    $error{'errdetails'} .= "card-number\|Foreign MasterCards are Blocked. - $fraud::bincountry\|";
    $error{'MErrMsg'} .= "Foreign MasterCards are not accepted.\|";
  }

  if ($error{'level'} == 2) {
    my @array = (%$query,%error);
  }

  ###  Need to Comment Out following Line when database is proved good.
  %error=();

  my $sth = $fraud::dbh->prepare(qq{
           select username
           from country_fraud
           where entry=?
           and username=?
           });
  $sth->execute($fraud::bincountry,$$query{'merchant'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
  my ($test) = $sth->fetchrow;
  $sth->finish;
  if ($test ne "") {
    $error{'level'} = 2;
    $error{'errdetails'} .= "country\|Bank Bin Country on Blocked List.\|";
    $error{'MErrMsg'} .= "Credit Cards issued from this country are currently not being accepted.\|";
  }
  return %error;
}


sub block_frgncards1 {
  my ($query) = @_;
  my (%error);
  if ($fraud::bincountry eq "") {
    my $sth = $fraud::dbh->prepare(qq{
           select country
           from master_bins1
           where startbin<=? and endbin>?
    });
    $sth->execute($fraud::cardbin,$fraud::cardbin) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
    ($fraud::bincountry) = $sth->fetchrow;
    $sth->finish;
  }

  if (($fraud::bincountry ne "US") && ($fraud::fraud_config{'blkfrgnvs'} == 1) && ($fraud::cardtype eq "VISA")) {
    $error{'level'} = 2;
    $error{'errdetails'} .= "card-number\|Foreign Visas are Blocked.\|";
    $error{'MErrMsg'} .= "Foreign Visas are not accepted.\|";
  }
  if (($fraud::bincountry ne "US") && ($fraud::fraud_config{'blkfrgnmc'} == 1) && ($fraud::cardtype eq "MSTR")) {
    $error{'level'} = 2;
    $error{'errdetails'} .= "card-number\|Foreign MasterCards are Blocked.\|";
    $error{'MErrMsg'} .= "Foreign MasterCards are not accepted.\|";
  }

  my $sth = $fraud::dbh->prepare(qq{
           select username
           from country_fraud
           where entry=?
           and username=?
           });
  $sth->execute($fraud::bincountry,$$query{'merchant'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
  my ($test) = $sth->fetchrow;
  $sth->finish;
  if ($test ne "") {
    $error{'level'} = 2;
    $error{'errdetails'} .= "country\|Bank Bin Country on Blocked List.\|";
    $error{'MErrMsg'} .= "Credit Cards issued from this country are currently not being accepted.\|";
  }
  return %error;
}


sub block_countries {
  my ($query) = @_;
  my (%error);
  my ($test_country);

  if ($mckutils::query{'bbin_country'} ne "") {
    $test_country = $mckutils::query{'bbin_country'};
  }
  else {
    $test_country = $$query{'card-country'};
  }

#  open (FRAUD,">>/home/p/pay1/database/fraud_debug.txt");
  my $sth = $fraud::dbh->prepare(qq{
         select username
         from country_fraud
         where entry=?
         and username=?
         });
  $sth->execute("$test_country","$$query{'merchant'}") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
  my ($test) = $sth->fetchrow;
  $sth->finish;

  if ($test ne "") {
    $error{'level'} = 3;
    $error{'errdetails'} .= "country\|Billing Country on Blocked List.\|";
    $error{'MErrMsg'} .= "Credit Cards issued from this country are currently not being accepted.\|";
    $error{'resp-code'} = "P70";
  }
  return %error;
}

sub block_emailaddr {
  my ($query) = @_;
  my (%error);
  my $emailaddr = $$query{'email'};
  $emailaddr =~ s/\;/\,/g;
  my @emails = split(',',$emailaddr);

  foreach my $email (@emails) {
    $email =~ s/[^_0-9a-zA-Z\-\@\.]//g;
    $email =~ tr/A-Z/a-z/;
    my $sth = $fraud::dbh->prepare(qq{
          select username
          from emailaddr_fraud
          where entry=?
          and username=?
          });
    $sth->execute($email,$$query{'merchant'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
    my ($test) = $sth->fetchrow;
    $sth->finish;
    if ($test ne "") {
      $error{'level'} = 4;
      $error{'errdetails'} .= "email\|Email Address on Blocked List.\|";
      $error{'MErrMsg'} .= "Credit Cards issued with this Email Address are currently not being accepted.\|";
      $error{'resp-code'} = "P71";
      last;
    }
  }
  return %error;
}

sub block_bins {
  my ($query) = @_;
  my (%error);
  $fraud::cardbin = substr($$query{'card-number'},0,6);
  my $sth = $fraud::dbh->prepare(qq{
          select username
          from bin_fraud
          where entry=?
          and username=?
          });
  $sth->execute($fraud::cardbin,$$query{'merchant'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
  my ($test) = $sth->fetchrow;
  $sth->finish;

  if ($test ne "") {
    $error{'level'} = 4;
    $error{'errdetails'} .= "card-number\|Card Bin on Blocked List.\|";
    $error{'MErrMsg'} .= "Credit Cards issued from this bank are currently not being accepted.\|";
    $error{'resp-code'} = "P71";
  }
  return %error;
}

sub allow_bins {
  my ($query) = @_;
  my (%error);
  $fraud::cardbin = substr($$query{'card-number'},0,6);
  my $sth = $fraud::dbh->prepare(qq{
          select username
          from bin_fraud
          where entry=?
          and username=?
          });
  $sth->execute($fraud::cardbin,$$query{'merchant'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
  my ($test) = $sth->fetchrow;
  $sth->finish;

  if ($test eq "") {
    $error{'level'} = 4;
    $error{'errdetails'} .= "card-number\|Card Bin not on Allowed List.\|";
    $error{'MErrMsg'} .= "Credit Cards issued from this bank are currently not being accepted.\|";
    $error{'resp-code'} = "P71";
  }
  return %error;
}

sub block_email {
  my ($query) = @_;
  my (%error);
  my ($stuff,$emaildomain) = split(/\@/,$$query{'email'});

  my $sth = $fraud::dbh->prepare(qq{
          select username
          from email_fraud
          where entry=?
          and username=?
          });
  $sth->execute($emaildomain,$$query{'merchant'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
  my ($test) = $sth->fetchrow;
  $sth->finish;

  if ($test ne "") {
    $error{'level'} = 5;
    $error{'errdetails'} .= "email\|Email Domain on Blocked List.\|";
    $error{'MErrMsg'} .= "Email Address is on Blocked List.\|";
    $error{'resp-code'} = "P75";
  }
  return %error;
}


sub block_phone {
  my ($query) = @_;
  my (%error);
  my $phone = $$query{'phone'};
  $phone =~ s/[^0-9]//g;

  if (substr($phone,0,1) eq "1") {
    $phone = substr($phone,1);
  }

  if ($phone eq "") {
    return;
  }

  my $sth = $fraud::dbh->prepare(qq{
          select username
          from phone_fraud
          where entry=?
          and username=?
          });
  $sth->execute($phone,$$query{'merchant'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
  my ($test) = $sth->fetchrow;
  $sth->finish;

  if ($test ne "") {
    $error{'level'} = 4;
    $error{'errdetails'} .= "phone\|Phone Number on Blocked List.\|";
    $error{'MErrMsg'} .= "Sales for this phone number are currently not being accepted.\|";
    $error{'resp-code'} = "P74";
  }
  return %error;
}

sub block_ipaddr {  ### Not Necesary ?
  my ($query) = @_;
  my (%error);
  my $sth = $fraud::dbh->prepare(qq{
         select username
         from ip_fraud
         where entry=?
         and username=?
         });
  $sth->execute($$query{'ipaddress'},$$query{'merchant'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
  my ($test) = $sth->fetchrow;
  $sth->finish;

  if ($test ne "") {
    $error{'level'} = 6;
    $error{'errdetails'} .= "ipaddress\|IP Address on Blocked List.\|";
    $error{'MErrMsg'} .= "Your IP Address is on Blocked List.\|";
  }
  return %error;
}


sub block_ip {
  my ($query) = @_;
  my (%error);
  if ($$query{'ipaddress'} ne "") {
    $$query{'ipaddress'} =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/;
    my $srch_ip = $1 . "\." . $2 . "\." . $3 . "\.";
    my $sth = $fraud::dbh->prepare(qq{
          select username
          from ip_fraud
          where ( entry=? or entry=? )
          and username=?
          });
    $sth->execute($$query{'ipaddress'},$srch_ip,$$query{'merchant'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
    my ($test) = $sth->fetchrow;
    $sth->finish;

    if ($test ne "") {
      $error{'level'} = 6;
      $error{'errdetails'} .= "ipaddress\|IP Address on Blocked IP List.\|";
      $error{'MErrMsg'} .= "Your IP Address is on Blocked List.\|";
      $error{'resp-code'} = "P67";
    }
  }
  else {
    #$error{'level'} = 6;
    #$error{'errdetails'} .= "ipaddress\|IP Address Missing.\|";
    #$error{'MErrMsg'} .= "IP Address Missing.\|";
  }
  return %error;
}

sub block_srcip {
  my ($query) = @_;
  my (%error);
  my $environment = new PlugNPay::Environment();
  my $remoteIP = $environment->get('PNP_CLIENT_IP');
  $remoteIP =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/;
  my $srch_ip = $1 . "\." . $2 . "\." . $3 . "\.";
  my $sth = $fraud::dbh->prepare(qq{
        select username
        from ip_fraud
        where ( entry=? or entry=? )
        and username=?
        });
  $sth->execute($remoteIP,$srch_ip,$$query{'merchant'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
  my ($test) = $sth->fetchrow;
  $sth->finish;

  if ($test ne "") {
    $error{'level'} = 6;
    $error{'errdetails'} .= "ipaddress\|Source IP Address on Blocked IP List.\|";
    $error{'MErrMsg'} .= "Your Sourve IP Address is on Blocked List.\|";
    $error{'resp-code'} = "P67";
  }
  return %error;
}

sub block_ipcntry {
  my ($query) = @_;
  my (%error,$continent,$country,$state,$city,$datasrc);

  if (-e "/home/p/pay1/outagefiles/stop_geolocation.txt") {
    return;
  }

  my ($w,$x,$y,$z,$elapse,$stime,$etime,$ipnum_from,$ipnum_to,$ipnum,$ipaddr);

  my $environment = new PlugNPay::Environment();
  my $remoteIP = $environment->get('PNP_CLIENT_IP');
  if ($ENV{'HTTP_PNP_GEOLOCATION'} =~ /([A-Z]{2}) ([A-Z]{2}) \{([a-zA-Z ]*)\} \{([a-zA-Z ]*)\}/) {
    $continent = $1;
    $country = $2;
    $state = $3;
    $city = $4;
    $datasrc = "ENV";
  } elsif ($remoteIP =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/) {
    $w = $1;
    $x = $2;
    $y = $3;
    $z = $4;
    $ipnum = int(16777216*$w + 65536*$x + 256*$y + $z);

    if (length($ipnum) > 11) {
      return;
    }

    my $sth = $fraud::dbh->prepare(qq{
        select ipnum_from, ipnum_to, country_code
        from ip_country
        where ipnum_to >= ?
        ORDER BY ipnum_to ASC LIMIT 1
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",$query);
    $sth->execute($ipnum) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",$query);
    ($ipnum_from, $ipnum_to, $country) = $sth->fetchrow;
    $sth->finish;

    if (($ipnum < $ipnum_from) || ($ipnum > $ipnum_to)) {
      $country = "";
    }

    if ($country =~ /^(UK|GB)$/) {
      $country = "UK|GB";
    }
    $datasrc = "MAXMIND";

  }

  my ($d1,$datestr,$d2) = &miscutils::gendatetime();
  open (LOG,">>/home/p/pay1/database/debug/blockipcountry.txt");
  print LOG "DATE:$datestr, UN:$$query{'publisher-name'}, IP:$remoteIP, CNTRY:$country, SCRIPT:$ENV{'SCRIPT_NAME'}, OID:$$query{'orderID'}, DATASRC:$datasrc, ";
  foreach my $key (sort keys %fraud::fraud_config) {
    if ($key =~ /allow_src|blk_src/) {
      print LOG "$key:$fraud::fraud_config{$key}, ";
    }
  }
  print LOG "\n";
  close (LOG);

  if ($country eq "") {
    return;
  }
  my $test = 1;  ## Default to block all

  if ($fraud::fraud_config{'allow_src_all'} == 1)  {
    $test = "";
  }
  else {
    if (($fraud::fraud_config{'allow_src_us'} == 1) && ($country =~ /US/i)) {
      $test = "";
    }
    if (($fraud::fraud_config{'allow_src_ca'} == 1) && ($country =~ /CA/i)) {
      $test = "";
    }
    if (($fraud::fraud_config{'allow_src_mx'} == 1) && ($country =~ /MX/i)) {
      $test = "";
    }
    if (($fraud::fraud_config{'allow_src_eu'} == 1) && ($country =~ /UK|GB|DE|ES|IE|IT|FR/i)) {
      $test = "";
    }
    if (($fraud::fraud_config{'allow_src_lac'} == 1) && ($country =~ /AAAACA|AAAAAAMX/i)) {
      $test = "";
    }
  }
  if (($fraud::fraud_config{'blk_src_eastern'} == 1) && ($country =~ /RS|UA|PL|HU|RU/i)) {
    $test = "1";
  }
  else {
    my $sth = $fraud::dbh->prepare(qq{
         select username
         from ipcountry_fraud
         where entry=?
         and username=?
         });
    $sth->execute("$country","$$query{'merchant'}") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
    ($test) = $sth->fetchrow;
    $sth->finish;
  }
  if ($test ne "") {
    $error{'level'} = 6;
    $error{'errdetails'} .= "ipaddress\|Country of Source IP Address on Blocked IP List.\|";
    $error{'MErrMsg'} .= "This source IP is currently being blocked.\|";
    $error{'resp-code'} = "P77";
  }
  return %error;
}

sub block_proxy {
  my ($query) = @_;
  if (($$query{'ipaddress'} ne "") && ($$query{'ipaddress'} ne "127.0.0.1")) {
    my $sth = $fraud::dbh->prepare(qq{
         select entry
         from proxy_fraud
         where entry=?
         });
    $sth->execute($$query{'ipaddress'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
    my ($test) = $sth->fetchrow;
    $sth->finish;

    if ($test ne "") {
      my $emailObj = new PlugNPay::Email('legacy');
      $emailObj->setFormat('text');
      $emailObj->setTo('dprice@plugnpay.com');
      $emailObj->setFrom('fraud_lib@plugnpay.com');
      $emailObj->setSubject("Fraud Lib. - Blocked Proxy");

      my $message = '';
      $message .= "MERCHANT: $$query{'publisher-name'}\n\n";
      $message .= "BLOCKED PROXY: $$query{'ipaddress'}\n\n";

      $emailObj->setContent($message);
      $emailObj->send();
    }
  }
}


sub cybersource {

  my($query) = @_;
  require ICS;

  my (%result,%req,%res,$end_check_positive,%seenbefore);

  my $loctime = localtime(time());
  my $start_cyber = time();

  $end_check_positive = time();

  my $delta1 = $end_check_positive - $start_cyber;

  $seenbefore{'1'} = "Seen Before";

  open (FRAUD,">>/home/p/pay1/database/debug/fraud_debug.txt");
  print FRAUD "$loctime, $$query{'merchant'}, 4 CYBERTEST:IP:$$query{'ipaddress'},SEENBEFORE:$seenbefore{$$query{'seenbefore'}},TIMEDELTA POSCHK:$delta1\n";
  close (FRAUD);

  if ($$query{'seenbefore'} == 1) {
    return;
  }

  if ($$query{'merchant'} =~ /pnpdemo|pnptest|pnpdev/) {
    $req{'merchant_id'} = "plugpaytec";
  }
  elsif ($$query{'merchant'} =~ /motis|nabdemo|nimbustelec/) {
    $req{'merchant_id'} = "nabancard";
    $req{'server_host'} = "ics2test.ic3.com"; ## Test Server
  }
  else {
    $req{'merchant_id'} = $$query{'merchant'};
    $req{'merchant_id'} = "plugpaytec";
    $req{'server_host'} = "ics2test.ic3.com"; ## Test Server
  }

  $req{'server_port'} = 80;
  $req{'ics_applications'} = "ics_score";
  $req{'merchant_ref_number'} = "$$query{'orderID'}";

  # Translate Variable Names
  $$query{'card-name'} =~ /([a-zA-Z]*?) (.*)/;
  my ($fname,$lname) = ($1,$2);
  $req{'customer_ipaddress'} = "$$query{'ipaddress'}";
  $req{'avs'} = $$query{'avs-code'};
  $req{'customer_firstname'} = "$fname";
  $req{'customer_lastname'} = "$lname";
  $req{'customer_email'} = $$query{'email'};
  $req{'customer_phone'}= $$query{'phone'};
  $req{'currency'}= "USD";
  $req{'bill_address1'} = "$$query{'card-address1'} $$query{'card-address2'}";
  $req{'bill_city'} = $$query{'card-city'};
  $$query{'card-state'} =~ tr/a-z/A-Z/;
  if (exists $mckutils::US_CN_states{$$query{'card-state'}}) {
    $req{'bill_state'} = $$query{'card-state'};
  }
  else {
    $req{'bill_state'} = $fraud::calc_state{'card-state'};
  }
  $req{'bill_zip'} = $$query{'card-zip'};
  $req{'bill_country'} = $$query{'card-country'};
  $req{'customer_cc_number'} = $fraud::cardnumber;
  $req{'customer_cc_expmo'} = substr($$query{'card-exp'},0,2);
  $req{'customer_cc_expyr'} = substr($$query{'card-exp'},-2);

  my $cyb_cnt = $mckutils::max;
  if ($cyb_cnt < 1) {
    $cyb_cnt = 1;
  }
  for(my $i=1; $i<=$cyb_cnt; $i++) {
    if ($$query{"description$i"} eq "") {
      $$query{"description$i"} = "Default Product Description";
    }
    if ($$query{"item$i"} eq "") {
      $$query{"item$i"} = "DFLT101";
    }
    if ($$query{"cost$i"} eq "") {
      $$query{"cost$i"} = "$$query{'card-amount'}";
    }
    if ($$query{"quantity$i"} eq "") {
      $$query{"quantity$i"} = 1;
    }
    my $offer = $i-1;
    $req{"offer$offer"} = " product_name:" . $$query{"description$i"} . "^merchant_product_sku:" . $$query{"item$i"} . "^amount:" . $$query{"cost$i"} . "^quantity:" . $$query{"quantity$i"};
  }
  open (FRAUD,">>/home/p/pay1/database/debug/cybersource_debug.txt");

  #%res = &ICS::ics_send(%req);

  if ($$query{'merchant'} =~ /^(pnpdev|nabdemo|nimbustelec)$/) {
    $ENV{ICSPATH} = "/opt/CyberSource/SDK" unless $ENV{ICSPATH};
    my $ftime = time();
    my $fpid = $$;
    my $tempname = "CYBS_ICSFRAUD_" . $ftime . "_" . $fpid;
    &sysutils::filelog("write",">/home/p/pay1/database/cybersource/$tempname");
    open (TEMPCYB,">/home/p/pay1/database/cybersource/$tempname") or &miscutils::errmail('1196','fraud.pm',"Can't prepare:",%$query);
    print TEMPCYB "ICSFRAUD\n";
    close(TEMPCYB);

    my @array = %req;
    %res = &ics_send(@array) ;
  }

  my $end_cyber = time();

  %result = %res;

  my $delta2 = $end_cyber - $end_check_positive;
  print FRAUD "TIME: $loctime, $$query{'orderID'}, CYBERPOST: ";
  foreach my $key (sort keys %req) {
    print FRAUD "$key=$req{$key}, ";
  }
  print FRAUD "\n\n";
  print FRAUD "CYBER TIMETEST:POSCheck: $delta1, CSCHECK: $delta2, ";

  foreach my $key (sort keys %result) {
    print FRAUD "$key:$result{$key},";
  }

  print FRAUD "\n\n\n";
  close (FRAUD);

  if ($res{'ics_rcode'} >= 0 ) { # some error occurred.
    if ($res{'score_score_result'} > $fraud::fraud_config{'cybersource'}) {
      $result{'FinalStatus'} = "fraud";       #####  UN-Comment for Production
    }
  }

  return %result;
}

sub check_bankbin {
  my ($query) = @_;
  my (%error,$test);

  my ($start1,$end1,$debitflg,$cardtype1,$region1,$country1,$producttype,$productid,$chipcrdflg);
  my ($start2,$end2,$ica,$region2,$country2,$electflg,$acquirer,$cardtype2,$mapping,$alm_part,$alm_date);

  my %binregion1 = ('1','USA','2','CAN','3','EUR','4','AP','5','LAC','6','SAMEA');
  my %binregion2 = ('1','USA','A','CAN','B','LAC','C','AP','D','EUR','E','SAMEA');
  my %bindebitflg = ('D','DBT','C','CRD','F','CHK');
  my %ardefpt = ('A','ATM','B','VISA-BUSINESS','C','VISA-CLASSIC','D','VISA-COMMERCE','E','ELECTRON','F','Visa-Check-Card2','G','Visa-Travel-Money','H','Visa-Infinite','H','Visa-Sig-Preferred',
                 'J','Visa-Platinum','K','Visa-Signature','L','VISA-PRIVATE-LABEL','M','MASTERCARD','O','V-Signature-Business','P','VISA-GOLD','Q','VISA-Proprietary','R','CORP-T-E',
                 'S','PURCHASING','T','TRAVEL-VOUCHER','V','VPAY','X','RESERVED-FUTURE','B','VISA-BIZ','H','VISA-BUSINESS','S','VISA-BUSINESS','O','VISA-BUSINESS');

  my %ardefpid = ('A','VS-TRADITIONAL','AX','VS-AMEX','B','VS-TRAD-REWARDS','C','VS-SIGNATURE','D','VS-SIG-PREFERRED','DI','VS-DISCOVER','E','VS-RESERVED-E','F','VS-RESERVED-F','G','VS-BUSINESS',
                   'G1','VS-SIG-BUSINESS','G2','VS-BUS-CHECK-CARD','H','VS-CHECK-CARD','I','VS-COMMERCE','J','VS-RESERVED-J','J1','VS-GEN-PREPAID','J2','VS-PREPAID-GIFT','J3','VS-PREPAID-HEALTH',
                   'J4','VS-PREPAID-COMM','K','VS-CORPORATE','K1','VS-GSA-CORP-TE','L','VS-RESERVED-L','M','VS-MASTERCARD','N','VS-RESERVED-N','O','VS-RESERVED-O','P','VS-RESERVED-P','Q','VS-PRIVATE',
                   'Q1','VS-PRIV-PREPAID','R','VS-PROPRIETARY','S','VS-PURCHASING','S1','VS-PURCH-FLEET','S2','VS-GSA-PURCH','S3','VS-GSA-PURCH-FLEET','T','VS-INTERLINK','U','VS-TRAVELMONEY','V','VS-RESERVED-V');

  my %icaxrfpt = ('MCC','norm','MCE','electronic','MCF','fleet','MGF','fleet','MPK','fleet','MNF','fleet','MCG','gold','MCP','purchasing','MCS','standard','MCU','standard','MCW','world',
                 'MNW','world','MWE','world-elite','MCD','MC-debit','MDS','MC-debit','MDG','gold-debit','TCG','gold-debit','MDO','other-debit','MDH','other-debit','MDJ','other-debit',
                 'MDP','platinum-debit','MDR','brokerage-debit','MXG','x-gold-debit','MXO','x-other-debit','MXP','x-platinum-debit','TPL','x-platinum-debit','MXR','x-brokerage-debit',
                 'MXS','x-standard-debit','MPP','prepaid-debit','MPL','platinum','MCT','platinum','PVL','private-label','MAV','activation','MBE','electronic-bus','MWB','world-bus',
                 'MAB','world-elite-bus','MWO','world-corp','MAC','world-elite-corp','MCB','distribution-card','MDP','premium-debit','MDT','business-debit','MDH','debit-other','MDJ','debit-other2',
                 'MDL','biz-debit-other','MCF','mid-market-fleet','MCP','mid-market-pruch','MCO','mid-market-corp','MCO','corp-card','MEO','large-market-exe','MDQ','middle-market-corp',
                 'MPC','small-bus-card','MPC','small-bus-card','MEB','exe-small-bus-card','MDU','x-debit-unembossed','MEP','x-premium-debit','MUP','x-premium-debit-ue','MGF','gov-comm-card',
                 'MPK','gov-comm-card-pre','MNF','pub-sec-comm-card','MRG','prepaid-consumer','MPG','db-prepd-gen-spend','MRC','prepaid-electronic','MRW','prepaid-bus-nonus','MEF','elect-pmt-acct',
                 'MBK','black','MPB','pref-biz','DLG','debit-gold-delayed','DLH','debit-emb-delayed','DLS','debit-st-delayed','DLP','debit-plat-delayed','MCV','merchant-branded',
                 'MPJ','debit-gold-prepaid','MRJ','gold-prepaid','MRK','comm-public-sector','TBE','elect-bus-debit','TCB','bus-debit','TCC','imm-debit','TCE','elect-debit','TCF','fleet-debit',
                 'TCO','corp-debit','TCP','purch-debit','TCS','std-debit','TCW','signia-debit','TNF','comm-pub-sect-dbt','TNW','new-world-debit','TPB','pref-bus-debit');


  if ($$query{'card-number'} eq "") {
    return;
  }

  my $ardef_bin = substr($$query{'card-number'},0,9);
  my $sth = $fraud::dbh->prepare(qq{
        select data
        from ardef
        where startbin <= ?
        ORDER BY startbin DESC LIMIT 1
  }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute($ardef_bin) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
  my ($ardef_data) = $sth->fetchrow;
  $sth->finish;


  $end1 = substr($ardef_data,0,9);
  $end1 =~ s/[^0-9]//g;
  $start1 = substr($ardef_data,9,9);
  $start1 =~ s/[^0-9]//g;
  $debitflg = substr($ardef_data,18,1);
  $cardtype1 =  substr($ardef_data,19,1);
  $region1 =  substr($ardef_data,20,1);
  $country1 =  substr($ardef_data,21,2);
  $producttype = substr($ardef_data,23,1);
  $productid = substr($ardef_data,24,2);
  $chipcrdflg = substr($ardef_data,26,1);

  if ($mckutils::feature{'bindetails'} == 1) {
    $mckutils::query{'bbin_region'} = $binregion1{"$region1"};
    $mckutils::query{'bbin_country'} = $country1;
    $mckutils::query{'bbin_debit'} = $bindebitflg{"$debitflg"};
    $mckutils::query{'bbin_prodtype'} = $ardefpt{"$cardtype1"};
    if (($productid ne "") && (exists $ardefpid{"$productid"})) {
      $mckutils::query{'bbin_prodtype'} = $ardefpid{"$productid"};
    }

    if ($mckutils::query{'bbin_prodtype'} =~ /prepaid/i) {   ###  PrePaid Cards
      $mckutils::query{'bbin_debit'} = 'PPD';
    }

  }

  my $icaxrf_bin = substr($$query{'card-number'},0,11);
  $icaxrf_bin .= "0000000000";
  $icaxrf_bin  = substr($icaxrf_bin,0,19);

  if ($icaxrf_bin =~ /^5/) {
    my $sth = $fraud::dbh->prepare(qq{
          select data
          from icaxrf
          where startbin <= ?
          ORDER BY startbin DESC LIMIT 1
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
    $sth->execute($icaxrf_bin) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
    my ($icaxrf_data) = $sth->fetchrow;
    $sth->finish;

    $end2 = substr($icaxrf_data,0,19);
    $end2 =~ s/[^0-9]//g;
    $start2 = substr($icaxrf_data,19,19);
    $start2 =~ s/[^0-9]//g;
    $ica = substr($icaxrf_data,38,11);
    $region2 =  substr($icaxrf_data,49,1);
    $country2 =  substr($icaxrf_data,50,3);
    $electflg = substr($icaxrf_data,53,2);
    $acquirer = substr($icaxrf_data,55,1);
    $cardtype2 = substr($icaxrf_data,56,3);
    $mapping = substr($icaxrf_data,59,1);
    $alm_part = substr($icaxrf_data,60,1);
    $alm_date = substr($icaxrf_data,61,6);

    if ($mckutils::feature{'bindetails'} == 1) {    ###  MC Debit
      if ($icaxrfpt{"$cardtype2"} =~ /debit/i) {
        $mckutils::query{'bbin_debit'} = 'DBT';
      }
      if ($icaxrfpt{"$cardtype2"} =~ /prepaid/i) {   ###  PrePaid Cards
        $mckutils::query{'bbin_debit'} = 'PPD';
      }
      $mckutils::query{'bbin_country'} = $country2;
      $mckutils::query{'bbin_region'} = $binregion2{"$region2"};
      $mckutils::query{'bbin_prodtype'} = $icaxrfpt{"$cardtype2"};
    }
  }

  if ($fraud::fraud_config{'bankbin_reg'} == 1) {
    if ($fraud::fraud_config{'bankbin_reg_action'} eq "block") {
      if (($fraud::fraud_config{'bin_reg_us'} == 1) && ($mckutils::query{'bbin_region'} eq "USA")) {
        $test = "Fail";
      }
      elsif (($fraud::fraud_config{'bin_reg_ca'} == 1) && ($mckutils::query{'bbin_region'} eq "CAN")) {
        $test = "Fail";
      }
      elsif (($fraud::fraud_config{'bin_reg_lac'} == 1) && ($mckutils::query{'bbin_region'} eq "LAC")) {
        $test = "Fail";
      }
      elsif (($fraud::fraud_config{'bin_reg_ap'} == 1) && ($mckutils::query{'bbin_region'} eq "AP")) {
        $test = "Fail";
      }
      elsif (($fraud::fraud_config{'bin_reg_eu'} == 1) && ($mckutils::query{'bbin_region'} eq "EUR")) {
        $test = "Fail";
      }
      elsif (($fraud::fraud_config{'bin_reg_samea'} == 1) && ($mckutils::query{'bbin_region'} eq "SAMEA")) {
        $test = "Fail";
      }
    }
    elsif ($fraud::fraud_config{'bankbin_reg_action'} eq "allow") {
      $test = "Fail";
      if (($fraud::fraud_config{'bin_reg_us'} == 1) && ($mckutils::query{'bbin_region'} eq "USA")) {
        $test = "";
      }
      if (($fraud::fraud_config{'bin_reg_ca'} == 1) && ($mckutils::query{'bbin_region'} eq "CAN")) {
        $test = "";
      }
      if (($fraud::fraud_config{'bin_reg_lac'} == 1) && ($mckutils::query{'bbin_region'} eq "LAC")) {
        $test = "";
      }
      if (($fraud::fraud_config{'bin_reg_ap'} == 1) && ($mckutils::query{'bbin_region'} eq "AP")) {
        $test = "";
      }
      if (($fraud::fraud_config{'bin_reg_eu'} == 1) && ($mckutils::query{'bbin_region'} eq "EUR")) {
        $test = "";
      }
      if (($fraud::fraud_config{'bin_reg_samea'} == 1) && ($mckutils::query{'bbin_region'} eq "SAMEA")) {
        $test = "";
      }
    }
  }

  if ($test ne "") {
    $error{'level'} = 6;
    $error{'errdetails'} .= "bankbin\|BankBin Region not allowed.\|";
    $error{'MErrMsg'} .= "Credit Cards issued from your geographic region iare not on allowed list.\|";
    $error{'resp-code'} = "P67";
  }
  return %error;

}

sub check_netwrk {
  my($query) = @_;
  my (%result,%req,%error,$res,$pairs,$res_level,$res_msg);
  my $start_netwrk = time();
  my %netwrk_config = ('pnpdemo','1d251ff79ad34e3e9c9f305fe9a513a3','pnpdemo','1d251ff79ad34e3e9c9f305fe9a513a3');

  $req{'gateway'} = "1d251ff79ad34e3e9c9f305fe9a513a3";
  $req{'merchant'} = $$query{'merchant'};
  #$req{'merchant'} = "99999999"; # Test Merchant ID
  my $addr = "https://secure.onlineaccess.net/nm/fraud/";

  # Translate Variable Names
  $req{'ip'} = "$$query{'ipaddress'}";
  $req{'email'} = $$query{'email'};
  $req{'ccnumber'} = $fraud::cardnumber;
  $req{'amount'} = $$query{'card-amount'};

  foreach my $key (keys %req) {
    $req{$key} =~ s/(\W)/'%' . unpack("H2",$1)/ge;
    if($pairs ne "") {
      $pairs = "$pairs\&$key=$req{$key}" ;
    } else {
      $pairs = "$key=$req{$key}" ;
    }
  }

  $res = &miscutils::formpostpl($addr,$pairs,'','','raw');
  $res =~ s/[^0-9\-a-zA-Z: ]//g;
  ($res_level,$res_msg) = split(':',$res);

  my $end_netwrk = time();

  if ($res_level < 0 ) {    # -1 = Internal Error
    $error{'level'} = 13;
    $error{'errdetails'} .= "cardnumber\|Transaction Failed NMFF: $res_msg.\|";
    $error{'MErrMsg'} .= "Transaction Failed NMFF: $res_msg.\|";
  }
  elsif($res_level == 0) {   #  0 = Passed, Charge the card
  }
  elsif($res_level == 1) {   #  1 = Flagged for review, Charge the card
  }
  elsif($res_level == 2) {   #  2 = Denied, Deny the transaction
    $error{'level'} = 13;
    $error{'errdetails'} .= "cardnumber\|Transaction Failed NMFF:  $res_msg.\|";
    $error{'MErrMsg'} .= "Transaction Failed NMFF: $res_msg.\|";
  }
  my $environment = new PlugNPay::Environment();
  my $remoteIP = $environment->get('PNP_CLIENT_IP');
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
  my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
  open (FRAUD,">>/home/p/pay1/database/debug/network_merchant_debug.txt");
  print FRAUD "DATE:$now IP:$remoteIP, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, BROWSER:$ENV{'HTTP_USER_AGENT'}, PID:$$, ";
  print FRAUD "RESPONSE LEVEL:$res_level, RESPONSEMSG:$res_msg ERROR:";
  foreach my $key (sort keys %error) {
    print FRAUD "$key:$error{$key}, ";
  }
  print FRAUD "\n";
  close (FRAUD);
  return %error;
}

sub iTransact {
  my($query) = @_;
  my (%result,%req,%error,$res,$pairs,$res_level,$res_msg,$tranID,$addr);
  my $environment = new PlugNPay::Environment();
  my $remoteIP = $environment->get('PNP_CLIENT_IP');

  my %iTransact_config = ('pnpdemo',['2504','change_me','tier2']);

  if ($$query{'iTransactPass'} == 2) {
    %req = %$query;
  }
  else {

    # Translate Variable Names
    $$query{'card-name'} =~ /([a-zA-Z]*?) (.*)/;
    my ($fname,$lname) = ($1,$2);

    $req{'AM'} = sprintf("%.2f",$$query{'card-amount'});
    $req{'AM'} =~ s/[^0-9]//g;

    $req{'OI'} = $$query{'orderID'};

    $req{'SN'} = $$query{'ssnum4'};
    $req{'FN'} = $fname;
    $req{'LN'} = $lname;
    $req{'SA'} = $$query{'card-address1'};
    $req{'CT'} = $$query{'card-city'};
    $req{'ST'} = $$query{'card-state'};
    $req{'ZP'} = $$query{'card-zip'};

  }

  $req{'DB'} = "1";  # Enable Debug Mode
  $req{'TN'} = "2";
  $req{'OI'} = "abc123";

  #my @config = @{ $iTransact_config{$$query{'merchant'}} };
  my @config = split(/:/,$fraud::fraud_config{'iTransConfig'});

  $req{'MN'} = $config[0];
  $req{'PW'} = $config[1];
  my $level = $config[2]; ## Options include: tier1, tier2, auto
  my $rule = $config[3];  ## Exception Rulesets

  if ($level eq "tier1") {
    $addr = "https://verify.ishopsecure.com/transactsecure/dt1.cgi";
  }
  elsif ($level eq "tier2") {
    if ($$query{'iTransactPass'} == 2) {
      $addr = "https://verify.ishopsecure.com/transactsecure/dt2b.cgi";
    }
    else {
      $addr = "https://verify.ishopsecure.com/transactsecure/dt2a.cgi";
    }
  }
  elsif ($level eq "auto") {
    $addr = "https://verify.ishopsecure.com/transactsecure/dts.cgi";
  }

  foreach my $key (keys %req) {
    $req{$key} =~ s/(\W)/'%' . unpack("H2",$1)/ge;
    if($pairs ne "") {
      $pairs = "$pairs\&$key=$req{$key}" ;
    }
    else{
      $pairs = "$key=$req{$key}" ;
    }
  }

  if ($addr ne "") {
    $res = &miscutils::formpostpl($addr,$pairs,'','','raw');
  }

  $res =~ s/\r\n/\n/g;
  my @res = split('\n',$res);
  $res = $res[0];
  $res =~ s/[^0-9\-a-zA-Z= _]//g;

  ($res_level,$res_msg) = split(/ /,$res);
  $res_msg =~ s/[^0-9a-zA-Z=_]//g;

  if ($res_level eq "error" ) {    # Processing Error
    if ($res_msg =~ /^(posting_reqs|login|comm)$/) {
      my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
      my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
      open (FRAUD,">>/home/p/pay1/database/debug/iTransact_debug.txt");
      print FRAUD "ERROR RESPONSE DATE:$now IP:$remoteIP, SCRIPT:$ENV{'SCRIPT_NAME'}, ";
      print FRAUD "HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, BROWSER:$ENV{'HTTP_USER_AGENT'}, PID:$$, ADDR:$addr,";
      print FRAUD "REQLEVEL:$level, RESPONSE LEVEL:$res_level, RESPONSEMSG:$res_msg RAW_RESP:";
      foreach my $var (@res) {
        print FRAUD "$var, ";
      }
      print FRAUD "\n";
      close (FRAUD);
    }
    elsif ($res_msg eq "possible_fraud") {
      $error{'level'} = 14;
      $error{'errdetails'} .= "cardnumber\|Transaction Failed iTransact: $res_msg.\|";
      $error{'MErrMsg'} .= "Transaction Failed iTransact Secure Fraud Filter: $res_msg.\|";
    }
  }
  elsif($res_level eq "passed") {   #  0 = Passed, Charge the card
    $tranID =~ /^tn=\"([0-9]*)$/;
    $tranID = $1;
  }
  elsif($res_level eq "failed") {   #  2 = Denied, Deny the transaction
    $tranID =~ /^tn=\"([0-9]*)$/;
    $tranID = $1;

    $error{'level'} = 13;
    $error{'errdetails'} .= "cardnumber\|Transaction Failed iTransact:  $res_msg.\|";
    $error{'MErrMsg'} .= "Transaction Failed iTransact Secure Fraud Filter:\|";
  }
  elsif($res_level =~ /^OK$/i) {   #  Tier 2 Request
    my $resp_page = "<html>\n<head>\n<title>iTransact Fraud Filter Request</title>\n</head>\n<body>\n";

    my $align = $$query{'image-placement'};
    if ($align eq "") {
      $align = "center";
    }
    if ($$query{'image-link'} ne ""){
       $resp_page .=  "<div align=\"$align\">\n";
       $resp_page .=  "<img src=\"$$query{'image-link'}\">\n";
       $resp_page .=  "</div>\n\n";
    }
    $resp_page .= "<font size=\"2\">Due to the nature of this transaction we will require the following questions to be answered successfully in order to complete your purchase request.</font><p>\n";
    $resp_page .= "<form method=\"post\" name=\"iTransact\" action=\"/payment/$$query{'publisher-name'}.cgi\"> \n";
    $resp_page .= "<input type=\"hidden\" name=\"iTransactPass\" value=\"2\">\n";

    for (my $i=1; $i<=@res; $i++) {
      $resp_page .= "$res[$i]\n";
    }

    foreach my $key (sort keys %$query) {
      $resp_page .= "<input type=\"hidden\" name=\"$key\" value=\"$$query{$key}\">\n";
    }

    $resp_page .= "<input type=\"submit\">\n</form>\n</body>\n</html>\n";

    $error{'iTransactResp'} = "$resp_page";
  }

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
  my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
  open (FRAUD,">>/home/p/pay1/database/debug/iTransact_debug.txt");
  print FRAUD "DATE:$now IP:$remoteIP, SCRIPT:$ENV{'SCRIPT_NAME'}, ";
  print FRAUD "HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, BROWSER:$ENV{'HTTP_USER_AGENT'}, PID:$$, ";
  print FRAUD "REQLEVEL:$level, RESPONSE LEVEL:$res_level, RESPONSEMSG:$res_msg QUERYDATA:";
  foreach my $key (sort keys %req) {
    print FRAUD "$key:$req{$key}, ";
  }
  print FRAUD "\nERROR RESP:";
  foreach my $key (sort keys %error) {
    print FRAUD "$key:$error{$key}, ";
  }
  print FRAUD "\n";
  close (FRAUD);
  return %error;
}

sub check_precharge {
  my($query) = @_;
  my (%req,%error,$res,$pairs);
  my $start_netwrk = time();
  my ($merch_id,$sec1,$sec2,$misc_field_1,$misc_field_2,$misc_field_3,$misc_field_4,$misc_field_5) = split('\|',$fraud::fraud_config{'precharge'});
  my $addr = "https://api.precharge.net/charge";

  my %min_map = ('ecom_billto_online_ip','ipaddress','ecom_billto_postal_postalcode','card-zip','ecom_billto_postal_countrycode','card-country','ecom_billto_telecom_phone_number','phone','ecom_billto_online_email','email','ecom_transaction_amount','card-amount','ecom_payment_card_number','card-number');

  my %addl_map = ('invoice_number','orderID','product_description','description1','client_id','publisher-name','currency','currency','ecom_billto_postal_street_line1','card-address1','ecom_billto_postal_street_line2','card-address2','ecom_billto_postal_city','card-city','ecom_billto_postal_stateprov','card-state');

  my %misc_map = ('misc_field_1',$misc_field_1,'misc_field_2',$misc_field_2,'misc_field_3',$misc_field_3,'misc_field_4',$misc_field_4,'misc_field_5',$misc_field_5);

  my (%map) = (%min_map,%addl_map);
  foreach my $key (keys %map) {
    if (exists $$query{$map{$key}}) {
      $req{$key} = $$query{$map{$key}};
    }
  }
  foreach my $key (keys %misc_map) {
    if (($misc_map{$key} ne "") && (exists $$query{$misc_map{$key}})) {
      $req{$key} = $$query{$misc_map{$key}};
    }
  }

  # Translate Variable Names
  ($req{'ecom_billto_postal_name_first'},$req{'ecom_billto_postal_name_last'}) = split('\ ',$$query{'card-name'});
  ($req{'ecom_payment_card_expdate_month'},$req{'ecom_payment_card_expdate_year'}) = split('\/',$$query{'card-exp'});

  foreach my $key (keys %req) {
    $req{$key} =~ s/(\W)/'%' . unpack("H2",$1)/ge;
    if($pairs ne "") {
      $pairs = "$pairs\&$key=$req{$key}" ;
    }
    else{
      $pairs = "$key=$req{$key}" ;
    }
  }
  $res = &miscutils::formpostpl($addr,$pairs,'','','raw');
  $res =~ s/[^0-9\-a-zA-Z\, ]//g;
  my %res = split('\,',$res);

  my $end_netwrk = time();
  my $elapse_time = $end_netwrk - $start_netwrk;

  ## Returned Response Keys:response, error, score

  my %error_map = ('101','Invalid Request Method','102','Invalid Request URL Requires SSL enabled','103','Invalid Security Code','104','Merchant Status Not Verified','105','Merchant Feed Disabled','106','Invalid Request Type','107','Missing IP Address IP Address not submitted.','108','Invalid IP Address Syntax IP Address syntax invalid.','109','Missing First Name First Name not submitted.','110','Invalid First Name','111','Missing Last Name','112','Invalid Last Name','113','Invalid Address 1','114','Invalid Address 2','115','Invalid City','116','Invalid State','117','Invalid Country','118','Missing Postal Code','119','Invalid Postal Code','120','Missing Phone Number','121','Invalid Phone Number','122','Missing Expiration Month','123','Invalid Expiration Month','124','Missing Expiration Year','125','Invalid Expiration Year','126','Expired Credit Card','127','Missing Credit Card Number','128','Invalid Credit Card Number','129','Missing Email Address','131','Duplicate Transaction','132','Invalid Transaction Amount','133','Invalid Currency','998','Unknown Error','999','Service Unavailable');

  if($res{'response'} == 1) {   #  1 = Passed, Charge the card
  }
  elsif($res{'response'} == 2) {   #  2 = Fail, Deny transactions
    $error{'level'} = 13;
    $error{'errdetails'} .= "precharge\|preCharge Decline:  $res{'score'}.\|";
    $error{'MErrMsg'} .= "Transaction Failed preCharge: $res{'score'}\|";
  }
  elsif($res{'response'} == 3) {   #  3 = Denied, Error
    $error{'level'} = 13;
    $error{'errdetails'} .= "precharge\|preCharge Error:  $res{'error'}.\|";
    $error{'MErrMsg'} .= "Transaction Failed preCharge: $res{'error'}:$error_map{$res{'error'}}\|";
  }
  else {

  }

  my $environment = new PlugNPay::Environment();
  my $remoteIP = $environment->get('PNP_CLIENT_IP');
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
  my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
  open (FRAUD,">>/home/p/pay1/database/debug/precharge_debug.txt");
  print FRAUD "DATE:$now IP:$remoteIP, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, BROWSER:$ENV{'HTTP_USER_AGENT'}, PID:$$, TIME:$elapse_time, ";
  print FRAUD "PAIRS:$pairs, RESPONSE:$res{'response'}, SCORE:$res{'score'}, ERROR:$res{'error'}, ";
  foreach my $key (sort keys %error) {
    print FRAUD "$key:$error{$key}, ";
  }
  print FRAUD "\n";
  close (FRAUD);
  return %error;
}

sub check_iovation {
  my($query) = @_;
  if ($mckutils::feature{'iovation'} eq "") {
    return;
  }

  require iovation;

  my (%result,%req,%error,$res,$pairs,$message,$resp,$header);
  my ($subscriberid,$subscriberaccount,$subscriberpasscode) = split('\|',$mckutils::feature{'iovation'});
  my %res = &iovation::check_transaction($query,$subscriberid,$subscriberaccount,$subscriberpasscode);

  foreach my $key (keys %res) {
    $$query{$key} = $res{$key};
  }

  if ($res{'ioresult'} eq "D") {
    $error{'level'} = 6;
    $error{'errdetails'} .= "iovation\|System Blocked by IOvation.\|";
    $error{'MErrMsg'} .= "Your system is on the IOvation block list.\|";
    $error{'resp-code'} = "P67";
    my $environment = new PlugNPay::Environment();
    my $remoteIP = $environment->get('PNP_CLIENT_IP');
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
    my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
    open (FRAUD,">>/home/p/pay1/database/debug/iovation_debug.txt");
    print FRAUD "DATE:$now IP:$remoteIP , SCRIPT:$ENV{'SCRIPT_NAME'}, ";
    print FRAUD "HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, BROWSER:$ENV{'HTTP_USER_AGENT'}, PID:$$, ";
    foreach my $key (sort keys %res) {
      print FRAUD "$key:$res{$key}, ";
    }
    print FRAUD "\nERROR RESP:";
    foreach my $key (sort keys %error) {
      print FRAUD "$key:$error{$key}, ";
    }
    print FRAUD "\n";
    close (FRAUD);
    return %error;
  }
  else {
    return;
  }
}

sub check_eye4fraud {
  my($query) = @_;

  if ($mckutils::feature{'eye4fraud'} eq "") {
    return;
  }

  require eye4fraud;
  my (%result,%req,%error,$res,$pairs,$message,$resp,$header);
  my ($APILogin,$APIKey,$SiteName) = split('\|',$mckutils::feature{'eye4fraud'});
  my %res = &eye4fraud::check_transaction($query,$APILogin,$APIKey,$SiteName,$mckutils::max);

  my $environment = new PlugNPay::Environment();
  my $remoteIP = $environment->get('PNP_CLIENT_IP');

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
  my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
  open (FRAUD,">>/home/p/pay1/database/debug/eye4fraud_debug.txt");
  print FRAUD "DATE:$now IP:$remoteIP, SCRIPT:$ENV{'SCRIPT_NAME'}, ";
  print FRAUD "HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, BROWSER:$ENV{'HTTP_USER_AGENT'}, PID:$$, ";
  foreach my $key (sort keys %res) {
    print FRAUD "$key:$res{$key}, ";
  }
  print FRAUD "\n";
  close (FRAUD);
  return;
}

sub check_fraud {
  my ($query) = @_;
  my ($ipaddr2,$ipaddr3,%error,%timestamps);
  $timestamps{'1start'} = time();
  my $environment = new PlugNPay::Environment();
  my $remoteIP = $environment->get('PNP_CLIENT_IP');

  if ($ENV{'SCRIPT_NAME'} =~ /pnpremote|payremote|remotepay|gcstravels|smps|virtualterm|systech|xml/) {
    if ($$query{'ipaddress'} ne "") {
      $ipaddr2 = $$query{'ipaddress'};
      $$query{'IPaddress'} = $$query{'ipaddress'};
      $mckutils::query{'IPaddress'} = $$query{'ipaddress'};
    }
  }
  else {
    $ipaddr2 = $remoteIP;
  }

  if (($$query{'paymethod'} ne "onlinecheck") && ($$query{'paymethod'} ne "invoice")
       && ($$query{'card-number'} ne "") && ($fraud::fraud_config{'negative'} ne "skip")) {
    my $cardnumber = $$query{'card-number'};
    my $md5 = new MD5;
    $md5->add("$cardnumber");
    my $cardnumber_md5 = $md5->hexdigest();

    my $dbh_fraud = &miscutils::dbhconnect("pnpmisc");

    my @qarray = ($cardnumber_md5);
    my $qstr = "select enccardnumber,trans_date,card_number,username,descr from fraud where enccardnumber=? ";
    if ($fraud::fraud_config{'negative'} eq "self" ) {
      $qstr .= "and username=? ";
      push @qarray, $mckutils::query{'publisher-name'};
    }
    my $sth_fraud = $dbh_fraud->prepare(qq{$qstr});
    $sth_fraud->execute(@qarray);
    my ($test,$orgdate,$fraudnumber,$submitted,$reason) = $sth_fraud->fetchrow;
    $sth_fraud->finish;
    $dbh_fraud->disconnect;

    if ($test ne "") {
      my $fcardnumber = substr($$query{'card-number'},0,4) . '**' . substr($$query{'card-number'},length($cardnumber)-2,2);
      $error{'level'} = 8;
      $error{'FraudMsg'} .= "Card Number: $fraudnumber:$fcardnumber, was found in the Master Fraud Database";
      $error{'errdetails'} .= "card-number\|Credit Card number appears in fraud database.\|";
      $error{"MErrMsg"} .= "Credit Card number has been flagged and can not be used to access this service.\|";
      $error{'resp-code'} = "P66";
      my @array = (%$query,%error);
      #&support_email(@array);
    }
    $timestamps{'2frauddbase'} = time();
  }

  my @fraudip = ('194.133.122.44','139.92.34.','199.203.109.251','202.146.244.','202.146.253.','202.152.13.','212.189.236.');
  foreach my $var (@fraudip) {
    if ($$query{'IPaddress'} =~ $var) {
      $error{'level'} = 9;
      $error{'FraudMsg'} .= "IP Address: $$query{'IPaddress'}, has been flagged as a possible source of fraud.";
      $error{'errdetails'} .= "ipaddress\|IP Address on Blocked IP List.\|";
      $error{'MErrMsg'} .= "IP Address is on Blocked List.\|";
      $error{'resp-code'} = "P67";

      #my %input = (%query,%error);
      &fraud_database(\%$query, \%error);
      #&support_email(\%$query, \%error);
    }
  }
  $timestamps{'3ipchk'} = time();

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
  my $datestr2 = sprintf("%04d%02d%02d%02d%02d%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
  my $datestr3 = time();

  ###
  #$ipaddr2 = "";

  my $ipfreqskip = 0;
  if ($fraud::fraud_config{'ipexempt'} == 1) {
    my ($ipaddr);
    my $dbh = &miscutils::dbhconnect("pnpmisc");
    my $sth = $dbh->prepare(qq{
        select ipaddress
        from ipaddress
        where username=?
        and ipaddress=?
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
    $sth->execute("$mckutils::query{'publisher-name'}","$ipaddr2") or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
   ($ipaddr) = $sth->fetchrow;
    $sth->finish;

    if ($ipaddr eq "") {
      my $ipaddr2 =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/;
      my $testip = "$1\.$2\.$3\.0";
      my $sth = $dbh->prepare(qq{
          select ipaddress
          from ipaddress
          where username=?
          and ipaddress=?
          }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
      $sth->execute("$mckutils::query{'publisher-name'}","$testip") or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
      ($ipaddr) = $sth->fetchrow;
      $sth->finish;
    }
    $dbh->disconnect;
    if ($ipaddr ne "") {
      $ipfreqskip = 1;
    }
  }

  if (($ipaddr2 ne "") && ($fraud::fraud_config{'ipskip'} != 1) && ($ipfreqskip != 1)) {
    my ($test,$fraudcount2,$fraudcount);

    my $sth = $fraud::dbh->prepare(qq{
        insert into freq_log
        (ipaddr,rawtime,trans_time)
        values (?,?,?)
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
    $sth->execute("$ipaddr2","$datestr3","$datestr2") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
    $sth->finish;

    my $timetest = $datestr3 - 3600;

    $sth = $fraud::dbh->prepare(qq{
        select ipaddr
        from freq_log
        where ipaddr=? and rawtime>?
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
    $sth->execute ($ipaddr2,$timetest) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
    $sth->bind_columns(undef,\($test));
    while ($sth->fetch) {
      if ($test !~ /0\.0\.0\.0/) {
        $fraudcount++;
      }
    }
    $sth->finish;

    if ($fraud::fraud_config{'ipfreq'} < 1) {
      $fraud::fraud_config{'ipfreq'} = 5;
    }

    if (($fraudcount > $fraud::fraud_config{'ipfreq'}) && ($ENV{'SCRIPT_NAME'} !~ /(smps\.cgi|virtualterm\.cgi|mpgiftcard\.cgi)$/)) {
      $error{'level'} = 7;
      $error{'errdetails'} .= "ipaddress\|Exceeded maximum attempts.";
      $error{'MErrMsg'} .= "Maximum number of attempts has been exceeded.";
      $error{'resp-code'} = "P65";
    }
  }
  $timestamps{'4freqchk'} = time();

  #open (TIMES,">>/home/p/pay1/database/fraudtimesdbase.txt");
  #my ($oldtime);
  #print TIMES "$$query{'merchant'}, ";
  #foreach my $key (sort keys %timestamps) {
  #  my $delta = $timestamps{$key} - $oldtime;
  #  print TIMES "$key:$delta, ";
  #  $oldtime = $timestamps{$key};
  #}
  #print TIMES "\n";
  #close (TIMES);

  return %error;
}


sub support_email {
  my (%error) = @_;
  if (exists $error{'card-number'}) {
    $error{'card-number'} = substr($error{'card-number'},0,6);
  }

  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setFormat('text');
  $emailObj->setTo('fraudproblems@plugnpay.com');
  $emailObj->setFrom('fraud@plugnpay.com');
  $emailObj->setSubject('Fraud Test Failure');

  my $message = '';
  $message .= "$error{'publisher-name'}\n\n";
  $message .= "$error{'MErrMsg'}\n\n";
  $message .= "$error{'errdetails'}\n";
  foreach my $key (sort keys %error) {
    $message .= "$key:$error{$key}\n";
  }

  $emailObj->setContent($message);
  $emailObj->send();
}


sub fraud_database {
  my ($query) = @_;
  my ($now) = &miscutils::gendatetime_only();
  my (%result,$cardnumber);

  my $username = $$query{'publisher-name'};
  my $orderid = $$query{'orderID'};
  my $trans_time = $$query{'transtime'};
  my $trans_date = substr($trans_time,0,8);
  my ($reason);

  if ($$query{'reason'} ne "") {
    $reason = $$query{'reason'};
  }
  else {
    $reason = "Potential Fraud";
  }

  #print "CN:$cardnumber, OID:$orderid, DS:$trans_date\n";

  if (($cardnumber eq "") && ($orderid ne "")) {
     my $enccardnumber = &smpsutils::getcardnumber($username,$orderid,'fraud_database','',{suppressAlert => 1});
    if ($enccardnumber ne "") {
      $cardnumber = &rsautils::rsa_decrypt_file($enccardnumber,'1',"print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");
    }
  }

  if ((length($cardnumber) < 13) || (length($cardnumber) > 20)) {
    $result{'FinalStatus'} = "failure";
    $result{'MErrMsg'} = "Unable to retrieve credit card number.";
    return %result;
  }

  my $md5 = new MD5;
  $md5->add($cardnumber);
  my $cardnumber_md5 = $md5->hexdigest();
  $cardnumber = substr($cardnumber,0,4) . '**' . substr($cardnumber,length($cardnumber)-2,2);

  my $dbh_fraud = &miscutils::dbhconnect("pnpmisc");
  my $sth = $dbh_fraud->prepare(qq{
    select enccardnumber,trans_date,card_number
    from fraud
    where enccardnumber=?
  }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query);
  $sth->execute($cardnumber_md5) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query);
  my ($test,$orgdate,$cardnumber1) = $sth->fetchrow;
  $sth->finish;

  if ($test eq "") {
    my $sth_insert = $dbh_fraud->prepare(qq{
      insert into fraud
      (enccardnumber,username,trans_date,descr,card_number)
      values (?,?,?,?,?)
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query);
    $sth_insert->execute("$cardnumber_md5","$username","$now","$reason","$cardnumber") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
    $sth_insert->finish;
    $result{'FinalStatus'} = "success";
    $result{'MErrMsg'} = "This credit card number has been successfully added to the negative database.";
  }
  else {
    $result{'FinalStatus'} = "failure";
    $result{'MErrMsg'} = "This credit card number has been previously added to the negative database.";
  }
  $dbh_fraud->disconnect;

  open(FRAUDBASE,">>/home/p/pay1/database/debug/fraud_attempts.txt");
  my $time = gmtime(time());
  print FRAUDBASE $time . ">";
  print FRAUDBASE $$query{'publisher-name'} . ">";
  print FRAUDBASE $$query{'IPaddress'} . ">";
  print FRAUDBASE $$query{'User-Agent'} . ">";
  print FRAUDBASE $$query{'referrer'} . ">";
  print FRAUDBASE $$query{'card-name'} . ">";
  print FRAUDBASE $$query{'card-address1'} . ">";
  print FRAUDBASE $$query{'card-address2'} . ">";
  print FRAUDBASE $$query{'card-city'} . ">";
  print FRAUDBASE $$query{'card-state'} . ">";
  print FRAUDBASE $$query{'card-zip'} . ">";
  print FRAUDBASE $$query{'card-country'} . ">";
  print FRAUDBASE $$query{'card-number'} . ">";
  print FRAUDBASE $$query{'card-exp'} . ">";
  print FRAUDBASE $$query{'card-amount'} . ">";
  print FRAUDBASE $$query{'order-id'} . ">";
  print FRAUDBASE $$query{'orderID'} . ">";
  print FRAUDBASE $$query{'success-link'} . ">";
  print FRAUDBASE $$query{'publisher-email'} . ">";
  print FRAUDBASE $$query{'email'} . ">";
  print FRAUDBASE $$query{'phone'} . ">";
  print FRAUDBASE $$query{'name'} . ">";
  print FRAUDBASE $$query{'address1'} . " " . $$query{'address2'} . ">";
  print FRAUDBASE $$query{'city'} . ">";
  print FRAUDBASE $$query{'state'} . ">";
  print FRAUDBASE $$query{'zip'} . ">";
  print FRAUDBASE $result{'avs-code'} . ">";
  print FRAUDBASE $result{'Duplicate'} . ">";
  print FRAUDBASE %$query . ">\n";
  close(FRAUDBASE);

  return %result;
}

##############  Everything below here taken from ics2-lib.pl  #################

###########################################################################
# set_error():  Set severity, decline, and errmsg to the passed-in array
#
# example:  set_error(\%arr, 0, 'NCURR', 'no curency provided');
###########################################################################

sub ics_send {
  my %request = @_;
  my $DEBUG = 0;
  my $reqmsg = &ICS::init($DEBUG);
  &set_client_lib_ver(\$request{client_lib_version});
  my $n;
  foreach $n (keys %request) {
    &ICS::fadd($reqmsg, $n, $request{$n});
  }
  my $repmsg = &ICS::send($reqmsg);
  my $count = &ICS::fcount($repmsg);
  my %reply;
  for (0..$count-1) {
    $reply{&ICS::fname($repmsg, $_)} = &ICS::fget($repmsg, $_);
  }
  # (XS code takes care of freeing $reqmsg and $repmsg memory)
  return %reply;
}

###  Following For Cybersource
sub ics_print {
  my %ics_msg = @_;
  foreach my $key (sort keys %ics_msg) {
    print "$key=$ics_msg{$key}\n";
  }
  return 1;
}

###  Following For Cybersource
sub set_client_lib_ver {
  my $ref = shift;
  $$ref .= "/" if $$ref;
  #$$ref .= "Perl$]/$Config{osname}$Config{osvers}/$VERSION";
  $$ref .= "Perl$]/Solaris 2.8/ICS-3.4.9";
}

###  Following For Cybersource
sub set_error {
    my($arr) = shift;
    my($severity, $decline, $errmsg) = @_;

    $$arr{ics_rcode} = $severity;
    $$arr{ics_rflag} = $decline;
    $$arr{ics_rmsg} = $errmsg;
}


sub check_volume {
  my ($query) = @_;
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
  my $date = sprintf("%04d%02d%02d",$year+1900,$mon+1,$mday);
  my (%error);
  my $sth = $fraud::dbh->prepare(qq{
        select volume
        from dailyvolume
        where username=? and trans_date=?
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query);
  $sth->execute($$query{'publisher-name'},$date) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
  my ($volume) = $sth->fetchrow;
  $sth->finish;

  open (FRAUD,">>/home/p/pay1/database/debug/fraud_debug_2.txt");
  print FRAUD "UN:$$query{'publisher-name'}, ";
  foreach my $key (sort keys %$query) {
    print FRAUD "$key:$$query{$key},";
  }
  print FRAUD "\n";
  foreach my $key (sort keys %fraud::fraud_config) {
    print FRAUD "$key:$fraud::fraud_config{$key},";
  }
  print FRAUD "\n";
  print FRAUD "\n";
  close (FRAUD);

  if ($volume > $fraud::fraud_config{'volimit'}) {
    $error{'level'} = 15;
    $error{'errdetails'} .= "card-number\|Daily volume exceeded.\|";
    $error{'MErrMsg'} .= "Daily volume exceeded.\|";
    $error{'resp-code'} = "P72";
  }
  return %error;
}

sub check_age {
  my ($query) = @_;

  if (-e "/home/p/pay1/outagefiles/stop_positive.txt") {
    return;
  }

  my $days = $fraud::fraud_config{'allowedage'};
  my $timeadjust = ($days * 24 * 3600);
  my ($dummy1,$datestr1,$timestr1) = &miscutils::gendatetime("-$timeadjust");
  my ($trans_time,$result,$found,%error);

  if ($fraud::shacardnumber ne "") {
    my $cardHashQmarks = '?' . ',?'x($#fraud::cardHashes);
    my $sth = $fraud::dbh->prepare(qq{
        select trans_time
        from positive
        where shacardnumber IN ($cardHashQmarks)
        and trans_time<=?
        and result=?
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query);
    $sth->execute(@fraud::cardHashes,$timestr1.'success') or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
    $sth->bind_columns(undef,\($trans_time));
    while ($sth->fetch) {
      $found = 1;
    }
    $sth->finish;
  }
  if ($found != 1) {
    $error{'level'} = 16;
    $error{'errdetails'} .= "card-number\|Allowed age of card requirements not met.\|";
    $error{'MErrMsg'} .= "Allowed age of card requirements not met.\|";
  }
  return %error;
}

sub acct_list {
  my ($query) = @_;
  my (%error,%fc,%fraud_config);

  ###  Need to grab fraud config settings for alt acounts.

  if ($fraud::fraud_config{'acctlist'} ne "") {
    my @acctlist = split('\|',$fraud::fraud_config{'acctlist'});
    foreach my $acct (@acctlist) {
      $acct =~ s/[^0-9a-zA-Z]//g;
      my $gatewayAccount = new PlugNPay::GatewayAccount($acct);
      $fc{$acct} = $gatewayAccount->getFraudConfig();
    }

    my %temp = %$query;
    foreach my $acct (@acctlist) {
      my (%error);
      $acct =~ s/[^0-9a-zA-Z]//g;
      my @array = split(/\,/,$fc{$acct});
      foreach my $entry (@array) {
        my($name,$value) = split(/\=/,$entry);
        $fraud_config{$name} = $value;
        $fraud_config{'fraudtrack'} = 1;
      }

      %fraud::fraud_config = %fraud_config;

      $temp{'publisher-name'} = $acct;
      @array = %temp;
      if (($fraud::fraud_config{'blkfrgnrvs'} == "1") || ($fraud::fraud_config{'blkfrgnrmc'} == "1")) {
        %error = &block_frgncards(\%temp);
      }
      if ($error{'level'} < 1) {
        %error = &check_volume(\%temp);
      }
      if ($error{'level'} < 1) {
      #  %error = &check_age(\%temp);
      }
      if ($error{'level'} < 1) {
        $mckutils::query{'publisher-name'} = $acct;
        $$query{'publisher-name'} = $acct;
        last;
      }
    }
  }
}

sub required_fields {
  my ($query) = @_;
  my (@check,%error);

  if ($fraud::fraud_config{'reqaddr'} == 1) {
    @check = (@check,'card-address1');
  }
  if ($fraud::fraud_config{'reqzip'} == 1) {
    @check = (@check,'card-zip');
  }
  if ($fraud::fraud_config{'reqcountry'} == 1) {
    @check = (@check,'card-country');
  }

  my ($var);
  foreach $var (@check) {
    my $val = $$query{$var};
    $val =~ s/[^a-zA-Z0-9]//g;
    if (length($val) < 1) {
      $error{'level'} = 1;
      $error{'errdetails'} .= "$var\|Data Missing/Invalid.\|";
      $error{'MErrMsg'} .= "Data Missing/Invalid: $var.\|";
      $error{'resp-code'} = "P58";
    }
  }
  return %error;
}

1;
