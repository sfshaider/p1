#!/bin/env perl

# Last Updated: 11/07/12

require 5.001;
$| = 1;

#use lib '/home/p/pay1/perl_lib/';
use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use constants qw(%countries);
use CGI;
use DBI;
use MD5;
use rsautils;
use smpsutils;
use PlugNPay::GatewayAccount;
use PlugNPay::GatewayAccount::Services;
#use strict;

my %query;
my $query = new CGI;

if ($ENV{'SEC_LEVEL'} > 8) {
  my $message = "Your current security level is not cleared for this operation. <p>Please contact Technical Support if you believe this to be in error. ";
  &response_page($message);
  exit;
}

&init_vars();

if ($function eq "Export Bin Fraud") {
  print "Content-Type: text/plain\n\n";
}
else {
  print "Content-Type: text/html\n\n";
}

if ($function eq "") {
  &default_page();
}
elsif ($function eq "update config") {
  &update_config();
  $function = "";
  $query->param(-name=>'ffunction',-value=>'');
  &init_vars();
  &default_page();
}
elsif ($function eq "add ip") {
  $ip_block =~ s/[^0-9\.]//g;
  &update_entry("ip_fraud","add",$ip_block);
  &init_vars();
  &default_page();
}
elsif ($function eq "remove ip") {
  &update_entry("ip_fraud","remove",\@ip_block_array);
  &init_vars();
  &default_page();
}
elsif ($function eq "add bin") {
  &update_entry("bin_fraud","add",$bin_block);
  &init_vars();
  &default_page();
}
elsif ($function eq "remove bin") {
  &update_entry("bin_fraud","remove",\@bin_block_array);
  &init_vars();
  &default_page();
}
elsif ($function eq "add phone") {
  &update_entry("phone_fraud","add",$phone_block);
  &init_vars();
  &default_page();
}
elsif ($function eq "remove phone") {
  &update_entry("phone_fraud","remove",\@phone_block_array);
  &init_vars();
  &default_page();
}
elsif ($function eq "add domain") {
  #&update_entry("email_fraud","add",$email_block);
  #&init_vars();
  #&default_page();
}
elsif ($function eq "remove domain") {
  #&update_entry("email_fraud","remove",\@email_block_array);
  #&init_vars();
  #&default_page();
}
elsif ($function eq "update domain") {
  #print @email_block_array;
  &update_entry("email_fraud","update",\@email_block_array);
  &init_vars();
  &default_page();
}
elsif ($function eq "Update Countries") {
  &update_countries();
  $function = "update config";
  $query->param(-name=>'ffunction',-value=>'update config');
  &init_vars();
  &update_config();
  $function = "";
  $query->param(-name=>'ffunction',-value=>'');
  &init_vars();
  &default_page();
}
elsif ($function eq "Update IPCountries") {
  &update_ipcountries();
  $function = "update config";
  $query->param(-name=>'ffunction',-value=>'update config');
  &init_vars();
  &update_config();
  $function = "";
  $query->param(-name=>'ffunction',-value=>'');
  &init_vars();
  &default_page();
}
elsif ($function eq "Add Card to Fraud Database") {
  &add_to_cc_fraud;
}
elsif ($function eq "Add Card to Positive Database") {
  &add_to_positive;
}
elsif ($function eq "Remove Card from Positive Database") {
  &remove_from_positive;
}
elsif ($function eq "remove emailaddr") {
  &update_entry("emailaddr_fraud","remove",\@emailaddr_block_array);
  &init_vars();
  &default_page();
}
elsif ($function eq "add emailaddr") {
  $emailaddr_block =~ s/[^_0-9a-zA-Z\-\@\.]//g;
  $emailaddr_block =~ tr/A-Z/a-z/;
  &update_entry("emailaddr_fraud","add",$emailaddr_block);
  &init_vars();
  &default_page();
}
elsif ($function eq "update emailaddr") {
  &update_entry("emailaddr_fraud","update",\@emailaddr_block_array);
  &init_vars();
  &default_page();
}
elsif ($function eq "Export Bin Fraud") {
  my @blocked_bin_array = &get_blocked_array("bin_fraud");
  foreach my $var (@blocked_bin_array) {
    print "$var\n";
  }
  #&default_page();
}

sub init_vars {

  $dbh = &miscutils::dbhconnect("pnpmisc");

  $username = $ENV{"REMOTE_USER"};
  my $gatewayAccount = new PlugNPay::GatewayAccount($username);

  $merchant = &CGI::escapeHTML($query->param('merchant'));
  $merchant =~ s/[^a-zA-Z0-9]//g;

  $subacct = &CGI::escapeHTML($query->param('subacct'));
  $subacct =~ s/[^a-zA-Z0-9]//g;

  my ($allow_overview);

  if (($merchant ne "") && ($ENV{'SCRIPT_NAME'} =~ /overview/)) {
    my $sth = $dbh->prepare(qq{
        select overview
        from salesforce
        where username=?
        }) or die "Can't do: $DBI::errstr";
    $sth->execute("$ENV{'REMOTE_USER'}") or die "Can't execute: $DBI::errstr";
    ($allow_overview) = $sth->fetchrow;
    $sth->finish;
  }

  my %overview = ();
  if ($allow_overview ne "") {
    ($username,$company,$status,$feature) = &overview($ENV{'REMOTE_USER'},$merchant);
    $reseller = $ENV{'REMOTE_USER'};
    if ($merchant =~ /icommerceg/) {
      my $subacct = &CGI::escapeHTML($fraud::query->param('subacct'));
      $subacct =~ s/[^a-zA-Z0-9]//g;

      if (($ENV{'SUBACCT'} eq "") && ($subacct ne "")) {
        $ENV{'SUBACCT'} = $subacct;
      }
    }
    if ($allow_overview ne "") {
      my @array = split(/\|/,$allow_overview);
      foreach my $entry (@array) {
        $overview{$entry} = 1;
      }
    }
  }
  else {
    $reseller = $gatewayAccount->getReseller();
    $company = $gatewayAccount->getCompanyName();
    $status = $gatewayAccount->getStatus();
    $feature = $gatewayAccount->getRawFeatures();
    $tdsprocessor = $gatewayAccount->getTDSProcessor();
  }

  if ($feature =~ /(.*)=(.*)/) {
    my @array = split(/\,/,$feature);
    foreach my $entry (@array) {
      my($name,$value) = split(/\=/,$entry);
      $feature{$name} = $value;
    }
  }

  my $services = new PlugNPay::GatewayAccount::Services($username);
  $fraudtrack = $services->getFraudTrack();

  my $subusername;
  if ($subacct ne "") {
    $subusername = $gatewayAccount->getSubAccount() eq $subacct ? $username : "";
  }

  $dbh->disconnect;

  if ($overview{'fraudtrack'} == 1) {
    $fraudtrack = "yes";
  }

  my $dbh = &miscutils::dbhconnect("fraudtrack");
  my $sth2 = $dbh->prepare(qq{
        select count(shacardnumber)
        from fraud_exempt
        where username=?
        }) or die "Can't do: $DBI::errstr";
  $sth2->execute("$username") or die "Can't execute: $DBI::errstr";
  ($positive_cnt) = $sth2->fetchrow;
  $sth2->finish;
  $dbh->disconnect;

  if (($reseller eq "northame") && ($merchant ne "")) {
    $username = $merchant;
  }

  if ($subusername ne "") {
    $username = $subusername;
  }

  $frauddb = "fraudtrack";

  %countries = %constants::countries;
  delete $countries{''};
  %ipcountries = %countries;

  $function = &CGI::escapeHTML($query->param("ffunction"));
  $function =~ s/[^a-zA-Z0-9\_\-\ ]//g;

  $ip_block = &CGI::escapeHTML($query->param("ip_block"));
  @ip_block_array = $query->param("ip_block_list");

  $emailaddr_block = &CGI::escapeHTML($query->param("emailaddr_block"));
  @emailaddr_block_array = $query->param("emailaddr_block_list");

  $bin_block = &CGI::escapeHTML($query->param("bin_block"));
  $bin_block =~ s/[^0-9]//g;
  if (length($bin_block) != 6) {
    $bin_block = "";
  }
  @bin_block_array = $query->param("bin_block_list");

  $email_block = &CGI::escapeHTML($query->param("email_block"));
  @email_block_array = $query->param("email_block_list2");

  $phone_block = &CGI::escapeHTML($query->param("phone_block"));
  $phone_block =~ s/[^0-9]//g;
  if (substr($phone_block,0,1) eq "1") {
    $phone_block = substr($phone_block,1);
  }
  @phone_block_array = $query->param("phone_block_list");

  $fraud_config = $gatewayAccount->getFraudConfig();

  my $datetime = gmtime(time());
  open (DEBUG, ">>/home/p/pay1/database/debug/fraudtrack_change_log.txt");
  print DEBUG "DATE:$datetime, UN:$username, FUNC:$function, RU:$ENV{'REMOTE_USER'}, IP:$ENV{'REMOTE_ADDR'}, FC:$fraud_config, ";
  #if ($function eq "update config") {
    #print DEBUG "FUNC:$function: ";
    my @params = $query->param;
    foreach my $param (@params) {
      my $s = &CGI::escapeHTML($query->param($param));
      if (($s =~ /^\d{13,16}$/)) {
        my $cctype = &miscutils::cardtype($s);
        if ($cctype ne "failure") {
          my $tempVal = $s;
          $tempVal =~ s/./X/g;
          $s = $tempVal;
        }
      }
      $p = $param;
      if ($p =~ /^\d{13,16}$/) {
        my $cctype = &miscutils::cardtype($p);
        if ($cctype ne "failure") {
          my $tempVal = $p;
          $tempVal =~ s/./X/g;
          $p = $tempVal;
        }
      }
      print DEBUG "$p:$s, ";
    }
  #}
  print DEBUG "\n";
  close (DEBUG);

  #$username = "icgoceanba";

  #if ($username eq "icommerceg") {
  #  print "FC:$fraud_config\n";
  #}

  %checkbox_hash = ("on","1","off","0","1","checked","0","");
  %fraud_config_hash = ();
  if (($fraud_config ne "") && ($function ne "update config")) {
    my @fraud_config_array = split(/\,/,$fraud_config);
    foreach my $entry (@fraud_config_array) {
      my($name,$value) = split(/\=/,$entry);
      $fraud_config_hash{$name} = $value;
    }
    $fraud_config_hash{'cvv'} = $checkbox_hash{$fraud_config_hash{'cvv'}};
    $fraud_config_hash{'cvv_avs'} = $checkbox_hash{$fraud_config_hash{'cvv_avs'}};
    $fraud_config_hash{'int_avs'} = $checkbox_hash{$fraud_config_hash{'int_avs'}};
    $fraud_config_hash{'cvv_xpl'} = $checkbox_hash{$fraud_config_hash{'cvv_xpl'}};
    $fraud_config_hash{'cvv_ign'} = $checkbox_hash{$fraud_config_hash{'cvv_ign'}};
    $fraud_config_hash{'cvv_3dign'} = $checkbox_hash{$fraud_config_hash{'cvv_3dign'}};
    $fraud_config_hash{'cvv_vt'} = $checkbox_hash{$fraud_config_hash{'cvv_vt'}};
    $fraud_config_hash{'cvv_swipe'} = $checkbox_hash{$fraud_config_hash{'cvv_swipe'}};
    $fraud_config_hash{'noemail'} = $checkbox_hash{$fraud_config_hash{'noemail'}};
    $fraud_config_hash{'nomrchemail'} = $checkbox_hash{$fraud_config_hash{'nomrchemail'}};
    $fraud_config_hash{'blkfrgnrvs'} = $checkbox_hash{$fraud_config_hash{'blkfrgnrvs'}};
    $fraud_config_hash{'blkfrgnmc'} = $checkbox_hash{$fraud_config_hash{'blkfrgnmc'}};
    $fraud_config_hash{'blkvs'} = $checkbox_hash{$fraud_config_hash{'blkvs'}};
    $fraud_config_hash{'blkmc'} = $checkbox_hash{$fraud_config_hash{'blkmc'}};
    $fraud_config_hash{'blkax'} = $checkbox_hash{$fraud_config_hash{'blkax'}};
    $fraud_config_hash{'blkds'} = $checkbox_hash{$fraud_config_hash{'blkds'}};
    $fraud_config_hash{'blkdebit'} = $checkbox_hash{$fraud_config_hash{'blkdebit'}};
    $fraud_config_hash{'blkcredit'} = $checkbox_hash{$fraud_config_hash{'blkcredit'}};

    $fraud_config_hash{'ipskip'} = $checkbox_hash{$fraud_config_hash{'ipskip'}};
    $fraud_config_hash{'ipexempt'} = $checkbox_hash{$fraud_config_hash{'ipexempt'}};
    $fraud_config_hash{'dupchk'} = $checkbox_hash{$fraud_config_hash{'dupchk'}};
    $fraud_config_hash{'blkusip'} = $checkbox_hash{$fraud_config_hash{'blkusip'}};
    $fraud_config_hash{'reqfields'} = $checkbox_hash{$fraud_config_hash{'reqfields'}};
    $fraud_config_hash{'reqaddr'} = $checkbox_hash{$fraud_config_hash{'reqaddr'}};
    $fraud_config_hash{'reqzip'} = $checkbox_hash{$fraud_config_hash{'reqzip'}};

    $fraud_config_hash{'billship'} = $checkbox_hash{$fraud_config_hash{'billship'}};
    $fraud_config_hash{'fraudhold'} = $checkbox_hash{$fraud_config_hash{'fraudhold'}};
    $fraud_config_hash{'cvvhold'} = $checkbox_hash{$fraud_config_hash{'cvvhold'}};
    $fraud_config_hash{'avshold'} = $checkbox_hash{$fraud_config_hash{'avshold'}};
    $fraud_config_hash{'ignhighlimit'} = $checkbox_hash{$fraud_config_hash{'ignhighlimit'}};

    $fraud_config_hash{'blkcntrys'} = $checkbox_hash{$fraud_config_hash{'blkcntrys'}};
    $fraud_config_hash{'blkemails'} = $checkbox_hash{$fraud_config_hash{'blkemails'}};
    $fraud_config_hash{'blkphone'} = $checkbox_hash{$fraud_config_hash{'blkphone'}};
#    $fraud_config_hash{'bounced'} = $checkbox_hash{$fraud_config_hash{'bounced'}};
    $fraud_config_hash{'blkipaddr'} = $checkbox_hash{$fraud_config_hash{'blkipaddr'}};

    $fraud_config_hash{'blkipcntry'} = $checkbox_hash{$fraud_config_hash{'blkipcntry'}};
    $fraud_config_hash{'allow_src_us'} = $checkbox_hash{$fraud_config_hash{'allow_src_us'}};
    $fraud_config_hash{'allow_src_ca'} = $checkbox_hash{$fraud_config_hash{'allow_src_ca'}};
    $fraud_config_hash{'allow_src_mx'} = $checkbox_hash{$fraud_config_hash{'allow_src_mx'}};
    $fraud_config_hash{'allow_src_eu'} = $checkbox_hash{$fraud_config_hash{'allow_src_eu'}};
    $fraud_config_hash{'allow_src_lac'} = $checkbox_hash{$fraud_config_hash{'allow_src_lac'}};
    $fraud_config_hash{'allow_src_all'} = $checkbox_hash{$fraud_config_hash{'allow_src_all'}};
    $fraud_config_hash{'blk_src_eastern'} = $checkbox_hash{$fraud_config_hash{'blk_src_eastern'}};


    $fraud_config_hash{'bankbin_reg'} = $checkbox_hash{$fraud_config_hash{'bankbin_reg'}};
    $fraud_config_hash{'bin_reg_us'} = $checkbox_hash{$fraud_config_hash{'bin_reg_us'}};
    $fraud_config_hash{'bin_reg_eu'} = $checkbox_hash{$fraud_config_hash{'bin_reg_eu'}};
    $fraud_config_hash{'bin_reg_lac'} = $checkbox_hash{$fraud_config_hash{'bin_reg_lac'}};
    $fraud_config_hash{'bin_reg_ca'} = $checkbox_hash{$fraud_config_hash{'bin_reg_ca'}};
    $fraud_config_hash{'bin_reg_ap'} = $checkbox_hash{$fraud_config_hash{'bin_reg_ap'}};
    $fraud_config_hash{'bin_reg_samea'} = $checkbox_hash{$fraud_config_hash{'bin_reg_samea'}};


    $fraud_config_hash{'blksrcip'} = $checkbox_hash{$fraud_config_hash{'blksrcip'}};
    $fraud_config_hash{'blkemailaddr'} = $checkbox_hash{$fraud_config_hash{'blkemailaddr'}};
    $fraud_config_hash{'blkbin'} = $checkbox_hash{$fraud_config_hash{'blkbin'}};
    $fraud_config_hash{'allowbin'} = $checkbox_hash{$fraud_config_hash{'allowbin'}};
    $fraud_config_hash{'blkproxy'} = $checkbox_hash{$fraud_config_hash{'blkproxy'}};
    $fraud_config_hash{'matchcntry'} = $checkbox_hash{$fraud_config_hash{'matchcntry'}};
    $fraud_config_hash{'matchardef'} = $checkbox_hash{$fraud_config_hash{'matchardef'}};
    $fraud_config_hash{'matchgeoip'} = $checkbox_hash{$fraud_config_hash{'matchgeoip'}};
    $fraud_config_hash{'iovation'} = $checkbox_hash{$fraud_config_hash{'iovation'}};
    $fraud_config_hash{'eye4fraud'} = $checkbox_hash{$fraud_config_hash{'eye4fraud'}};
    $fraud_config_hash{'matchzip'} = $checkbox_hash{$fraud_config_hash{'matchzip'}};
    $fraud_config_hash{'chkname'} = $checkbox_hash{$fraud_config_hash{'chkname'}};
    $fraud_config_hash{'chkprice'} = $checkbox_hash{$fraud_config_hash{'chkprice'}};
    $fraud_config_hash{'netwrk'} = $checkbox_hash{$fraud_config_hash{'netwrk'}};
    #$fraud_config_hash{'precharge'} = $checkbox_hash{$fraud_config_hash{'precharge'}};
    $fraud_config_hash{'iTransact'} = $checkbox_hash{$fraud_config_hash{'iTransact'}};
    $fraud_config_hash{'chkaccts'} = $checkbox_hash{$fraud_config_hash{'chkaccts'}};
  }
  elsif ($function eq "update config") {
    $fraud_config_hash{'avs'} = &CGI::escapeHTML($query->param("avs"));
    $fraud_config_hash{'tdsRequireEnrollment'} = &CGI::escapeHTML($query->param("tdsRequireEnrollment"));
    $fraud_config_hash{'negative'} = &CGI::escapeHTML($query->param("negative"));
    $fraud_config_hash{'cvv'} = &CGI::escapeHTML($checkbox_hash{$query->param("cvv")});
    $fraud_config_hash{'cvv_avs'} = &CGI::escapeHTML($checkbox_hash{$query->param("cvv_avs")});
    $fraud_config_hash{'int_avs'} = &CGI::escapeHTML($checkbox_hash{$query->param("int_avs")});
    $fraud_config_hash{'cvv_xpl'} = &CGI::escapeHTML($checkbox_hash{$query->param("cvv_xpl")});
    $fraud_config_hash{'cvv_ign'} = &CGI::escapeHTML($checkbox_hash{$query->param("cvv_ign")});
    $fraud_config_hash{'cvv_3dign'} = &CGI::escapeHTML($checkbox_hash{$query->param("cvv_3dign")});
    $fraud_config_hash{'cvv_vt'} = &CGI::escapeHTML($checkbox_hash{$query->param("cvv_vt")});
    $fraud_config_hash{'cvv_swipe'} = &CGI::escapeHTML($checkbox_hash{$query->param("cvv_swipe")});
    $fraud_config_hash{'noemail'} = &CGI::escapeHTML($checkbox_hash{$query->param("noemail")});
    $fraud_config_hash{'nomrchemail'} = &CGI::escapeHTML($checkbox_hash{$query->param("nomrchemail")});
    $fraud_config_hash{'cybersource'} = &CGI::escapeHTML($query->param("cybersource"));
    $fraud_config_hash{'bounced_email'} = &CGI::escapeHTML($query->param("bounced_email"));
    $fraud_config_hash{'bounced_url'} = &CGI::escapeHTML($query->param("bounced_url"));
    if (($fraud_config_hash{'bounced_url'} ne "") && ($fraud_config_hash{'bounced_url'} !~ /^(http)/)) {
      $fraud_config_hash{'bounced_url'} = "http://" . $fraud_config_hash{'bounced_url'};
    }

    $fraud_config_hash{'ipskip'} = &CGI::escapeHTML($checkbox_hash{$query->param("ipskip")});
    $fraud_config_hash{'ipexempt'} = &CGI::escapeHTML($checkbox_hash{$query->param("ipexempt")});
    $fraud_config_hash{'ipfreq'} = &CGI::escapeHTML($query->param("ipfreq"));

    $fraud_config_hash{'dupchk'} = &CGI::escapeHTML($checkbox_hash{$query->param("dupchk")});
    $fraud_config_hash{'dupchktime'} = &CGI::escapeHTML($query->param("dupchktime"));
    $fraud_config_hash{'dupchkvar'} = &CGI::escapeHTML($query->param("dupchkvar"));
    $fraud_config_hash{'dupchkresp'} = &CGI::escapeHTML($query->param("dupchkresp"));

    $fraud_config_hash{'ignhighlimit'} = &CGI::escapeHTML($checkbox_hash{$query->param("ignhighlimit")});

    $fraud_config_hash{'highlimit'} = &CGI::escapeHTML($query->param("highlimit"));
    $fraud_config_hash{'highlimit'} =~ s/[^0-9\.]//g;

    $fraud_config_hash{'matchcntry'} = &CGI::escapeHTML($checkbox_hash{$query->param("matchcntry")});
    $fraud_config_hash{'matchardef'} = &CGI::escapeHTML($checkbox_hash{$query->param("matchardef")});
    $fraud_config_hash{'matchgeoip'} = &CGI::escapeHTML($checkbox_hash{$query->param("matchgeoip")});
    $fraud_config_hash{'iovation'} = &CGI::escapeHTML($checkbox_hash{$query->param("iovation")});
    $fraud_config_hash{'eye4fraud'} = &CGI::escapeHTML($checkbox_hash{$query->param("eye4fraud")});
    $fraud_config_hash{'chkname'} = &CGI::escapeHTML($checkbox_hash{$query->param("chkname")});
    $fraud_config_hash{'chkprice'} = &CGI::escapeHTML($checkbox_hash{$query->param("chkprice")});
    $fraud_config_hash{'netwrk'} = &CGI::escapeHTML($checkbox_hash{$query->param("netwrk")});
    #$fraud_config_hash{'precharge'} = &CGI::escapeHTML($checkbox_hash{$query->param("precharge")});
    $fraud_config_hash{'iTransact'} = &CGI::escapeHTML($checkbox_hash{$query->param("iTransact")});
    $iTransUN = &CGI::escapeHTML($query->param("iTransactUN"));
    $iTransPW = &CGI::escapeHTML($query->param("iTransactPW"));
    $iTransLevel = &CGI::escapeHTML($query->param("iTransactLevel"));
    $iTransRule = &CGI::escapeHTML($query->param("iTransactRule"));

    if (&CGI::escapeHTML($checkbox_hash{$query->param("iTransact")}) == 1) {
      $fraud_config_hash{'iTransConfig'}  = "$iTransUN:$iTransPW:$iTransLevel:$iTransRule";
    }

    # preCharge
    $precharge = &CGI::escapeHTML($query->param("precharge"));
    $merch_id = &CGI::escapeHTML($query->param("merch_id"));
    $sec1 = &CGI::escapeHTML($query->param("sec1"));
    $sec2 = &CGI::escapeHTML($query->param("sec2"));
    $misc_field1 = &CGI::escapeHTML($query->param("misc_field_1"));
    $misc_field2 = &CGI::escapeHTML($query->param("misc_field_2"));
    $misc_field3 = &CGI::escapeHTML($query->param("misc_field_3"));
    $misc_field4 = &CGI::escapeHTML($query->param("misc_field_4"));
    $misc_field5 = &CGI::escapeHTML($query->param("misc_field_5"));

    if ($precharge eq "on") {
      $fraud_config_hash{'precharge'}  = "on|$merch_id|$sec1|$sec2|$misc_field1|$misc_field2|$misc_field3|$misc_field4|$misc_field5";
    }
    else {
      $fraud_config_hash{'precharge'}  = "off|$merch_id|$sec1|$sec2|$misc_field1|$misc_field2|$misc_field3|$misc_field4|$misc_field5";
    }

    $freqlev = &CGI::escapeHTML($query->param("freqlev"));
    $freqdays = &CGI::escapeHTML($query->param("freqdays"));
    $freqhours = &CGI::escapeHTML($query->param("freqhours"));
    if ($freqlev > 0) {
      $fraud_config_hash{'freqchk'} = "$freqlev:$freqdays:$freqhours";
    }
    else {
      $fraud_config_hash{'freqchk'} = "";
    }
    $fraud_config_hash{'blkfrgnrvs'} = &CGI::escapeHTML($checkbox_hash{$query->param("blkfrgnrvs")});
    $fraud_config_hash{'blkfrgnmc'} = &CGI::escapeHTML($checkbox_hash{$query->param("blkfrgnmc")});

    $fraud_config_hash{'blkvs'} = &CGI::escapeHTML($checkbox_hash{$query->param("blkvs")});
    $fraud_config_hash{'blkmc'} = &CGI::escapeHTML($checkbox_hash{$query->param("blkmc")});
    $fraud_config_hash{'blkax'} = &CGI::escapeHTML($checkbox_hash{$query->param("blkax")});
    $fraud_config_hash{'blkds'} = &CGI::escapeHTML($checkbox_hash{$query->param("blkds")});
    $fraud_config_hash{'blkdebit'} = &CGI::escapeHTML($checkbox_hash{$query->param("blkdebit")});
    $fraud_config_hash{'blkcredit'} = &CGI::escapeHTML($checkbox_hash{$query->param("blkcredit")});

    $fraud_config_hash{'blkusip'} = &CGI::escapeHTML($checkbox_hash{$query->param("blkusip")});

    $fraud_config_hash{'reqfields'} = &CGI::escapeHTML($checkbox_hash{$query->param("reqfields")});
    $fraud_config_hash{'reqaddr'} = &CGI::escapeHTML($checkbox_hash{$query->param("reqaddr")});
    $fraud_config_hash{'reqzip'} = &CGI::escapeHTML($checkbox_hash{$query->param("reqzip")});


    $fraud_config_hash{'billship'} = &CGI::escapeHTML($checkbox_hash{$query->param("billship")});
    $fraud_config_hash{'fraudhold'} = &CGI::escapeHTML($checkbox_hash{$query->param("fraudhold")});
    $fraud_config_hash{'cvvhold'} = &CGI::escapeHTML($checkbox_hash{$query->param("cvvhold")});
    $fraud_config_hash{'avshold'} = &CGI::escapeHTML($checkbox_hash{$query->param("avshold")});

    #print "AA:$fraud_config_hash{'blkusip'}, $checkbox_hash{$fraud_config_hash{'blkusip'}}\n";

    $fraud_config_hash{'blkcntrys'} = &CGI::escapeHTML($checkbox_hash{$query->param("blkcntrys")});
    $fraud_config_hash{'blkemails'} = &CGI::escapeHTML($checkbox_hash{$query->param("blkemails")});
    $fraud_config_hash{'blkphone'} = &CGI::escapeHTML($checkbox_hash{$query->param("blkphone")});
    $fraud_config_hash{'bounced'} = &CGI::escapeHTML($query->param("bounced"));
    $fraud_config_hash{'blkipaddr'} = &CGI::escapeHTML($checkbox_hash{$query->param("blkipaddr")});

    $fraud_config_hash{'blkipcntry'} = &CGI::escapeHTML($checkbox_hash{$query->param("blkipcntry")});
    $fraud_config_hash{'allow_src_us'} = &CGI::escapeHTML($checkbox_hash{$query->param("allow_src_us")});
    $fraud_config_hash{'allow_src_ca'} = &CGI::escapeHTML($checkbox_hash{$query->param("allow_src_ca")});
    $fraud_config_hash{'allow_src_mx'} = &CGI::escapeHTML($checkbox_hash{$query->param("allow_src_mx")});
    $fraud_config_hash{'allow_src_eu'} = &CGI::escapeHTML($checkbox_hash{$query->param("allow_src_eu")});
    $fraud_config_hash{'allow_src_lac'} = &CGI::escapeHTML($checkbox_hash{$query->param("allow_src_lac")});
    $fraud_config_hash{'allow_src_all'} = &CGI::escapeHTML($checkbox_hash{$query->param("allow_src_all")});
    $fraud_config_hash{'blk_src_eastern'} = &CGI::escapeHTML($checkbox_hash{$query->param("blk_src_eastern")});

    $fraud_config_hash{'bankbin_reg_action'} = &CGI::escapeHTML($query->param("bankbin_reg_action"));
    $fraud_config_hash{'bankbin_reg'} = &CGI::escapeHTML($checkbox_hash{$query->param("bankbin_reg")});
    $fraud_config_hash{'bin_reg_us'} = &CGI::escapeHTML($checkbox_hash{$query->param("bin_reg_us")});
    $fraud_config_hash{'bin_reg_ca'} = &CGI::escapeHTML($checkbox_hash{$query->param("bin_reg_ca")});
    $fraud_config_hash{'bin_reg_eu'} = &CGI::escapeHTML($checkbox_hash{$query->param("bin_reg_eu")});
    $fraud_config_hash{'bin_reg_ap'} = &CGI::escapeHTML($checkbox_hash{$query->param("bin_reg_ap")});
    $fraud_config_hash{'bin_reg_lac'} = &CGI::escapeHTML($checkbox_hash{$query->param("bin_reg_lac")});
    $fraud_config_hash{'bin_reg_samea'} = &CGI::escapeHTML($checkbox_hash{$query->param("bin_reg_samea")});

    $fraud_config_hash{'blksrcip'} = &CGI::escapeHTML($checkbox_hash{$query->param("blksrcip")});
    $fraud_config_hash{'blkemailaddr'} = &CGI::escapeHTML($checkbox_hash{$query->param("blkemailaddr")});

    $bankbin = &CGI::escapeHTML($query->param("bankbin"));
    if ($bankbin eq "block") {
      $fraud_config_hash{'blkbin'} = "1";
    }
    elsif ($bankbin eq "allow") {
      $fraud_config_hash{'allowbin'} = "1";
    }
    #print "BNKBIN:$bankbin, $fraud_config_hash{'blkbin'}:$fraud_config_hash{'allowbin'}<p>\n";

    $fraud_config_hash{'blkproxy'} = &CGI::escapeHTML($checkbox_hash{$query->param("blkproxy")});
    $fraud_config_hash{'matchzip'} = &CGI::escapeHTML($checkbox_hash{$query->param("matchzip")});

    $fraud_config_hash{'chkaccts'} = &CGI::escapeHTML($checkbox_hash{$query->param("chkaccts")});
    $fraud_config_hash{'acctlist'} = &CGI::escapeHTML($query->param("acctlist"));
    $fraud_config_hash{'allowedage'} = &CGI::escapeHTML($query->param("allowedage"));
    $fraud_config_hash{'volimit'} = &CGI::escapeHTML($query->param("volimit"));

#   foreach my $key (sort keys %fraud_config_hash) {
#      print "$key=$fraud_config_hash{$key}<br>\n";
#   }
#   print "FREQLEV:$freqlev<br>\n";

  }
  elsif ($reseller =~ /(northame)/) {
    $fraud_config_hash{'avs'} = 0;
    $fraud_config_hash{'cvv'} = "checked";
    $fraud_config_hash{'email'} = "";
    $fraud_config_hash{'cybersource'} = "50";
    $fraud_config_hash{'blkfrgnrvs'} = "checked";
    $fraud_config_hash{'ipfreq'} = "5";
    $fraud_config_hash{'blkfrgnmc'} = "checked";
    $fraud_config_hash{'blkcntrys'} = "";
    $fraud_config_hash{'blkipaddr'} = "checked";
    $fraud_config_hash{'blkproxy'} = "";
    $fraud_config_hash{'blkemails'} = "checked";
  }
  @blocked_ip_array = &get_blocked_array("ip_fraud");
  @blocked_bin_array = &get_blocked_array("bin_fraud");
  @blocked_email_array = &get_blocked_array("email_fraud");
  @blocked_phone_array = &get_blocked_array("phone_fraud");
  @blocked_emailaddr_array = &get_blocked_array("emailaddr_fraud");

  @blocked_country_array = &get_blocked_array("country_fraud");

  @blocked_ipcountry_array = &get_blocked_array("ipcountry_fraud");

  @default_blocked_email_array = ('gmail.com','hotmail.com','juno.com','yahoo.com','rocket.com','poboxes.com','hotbot.com','rocketmail.com','excite.com','nightmail.com','mail.com','bigfoot.com','address.com','ivillage.com');
  @new_blocked_email_array = ();
  for (my $i=0; $i<=$#default_blocked_email_array; $i++) {
    push(@new_blocked_email_array,$default_blocked_email_array[$i]);
    foreach my $value (@blocked_email_array) {
      if ($value eq $default_blocked_email_array[$i]) {
        pop @new_blocked_email_array;
      }
    }
  }
  @default_blocked_email_array = @new_blocked_email_array;

  if (@blocked_email_array < 1) {
    #@blocked_email_array = ('hotmail.com','yahoo.com','rocket.com');
  }
  if (@blocked_country_array < 1) {
    #@blocked_country_array = ('DZ','AO','AZ','BY','CU','GE','IR','IQ','LY','MM','SD','RU','NG','KP','YU');
  }


  #@blocked_country_array = ("AD");
  %blocked_country_hash = ();
  foreach my $brief (@blocked_country_array) {
    $blocked_country_hash{$brief} = $countries{$brief};
    delete $countries{$brief};
  }

  %blocked_ipcountry_hash = ();
  foreach my $brief (@blocked_ipcountry_array) {
    if ($brief eq "") {
      next;
    }
    $blocked_ipcountry_hash{$brief} = $ipcountries{$brief};
    delete $ipcountries{$brief};
  }

  #foreach my $key (sort keys %blocked_ipcountry_hash) {
  #  print "K:$key:$blocked_ipcountry_hash{$key}<br>\n";
  #}

  ## for testing only comment out otherwise
  #@blocked_email_array = ("yahoo.com","hotmail.com","aol.com");
  #@blocked_ip_array = ("1.1.1.1","2.2.2.2","3.3.3.3");
  #@blocked_country_array = ("AD");
}

sub update_countries {
  my @block_list = $query->param("country_block_list2");
  my %block_list = ();

  foreach my $var (@block_list) {
    $var =~ s/[^A-Z]//g;
    $block_list{$var} = 1;
  }

  $db_query = "delete from country_fraud where username=? ";

  $dbh = &miscutils::dbhconnect("fraudtrack");
  $sth = $dbh->prepare(qq{$db_query});
  $sth->execute($username);
  $sth->finish();

  $db_query = "insert into country_fraud (username,entry) values (?,?)";
  $sth = $dbh->prepare(qq{$db_query}) or die "insert country prepare fail";

  foreach my $country (sort keys %block_list) {
    if (($country ne "") && (length($country) == 2)){
      $sth->execute($username,$country) or die "insert country execute fail";
    }
  }
  $sth->finish();
  $dbh->disconnect();
}

sub update_ipcountries {
  my @block_list = $query->param("ipcountry_block_list2");
  my %block_list = ();

  foreach my $var (@block_list) {
    $var =~ s/[^A-Z]//g;
    $block_list{$var} = 1;
  }

  $dbh = &miscutils::dbhconnect("fraudtrack");

  $sth = $dbh->prepare(qq{
    delete from ipcountry_fraud
    where username=?
  }) or die "prepare fail";
  $sth->execute($username)or die "delete failed";
  $sth->finish();

  $db_query = "insert into ipcountry_fraud (username,entry) values (?,?)";

  $sth = $dbh->prepare(qq{$db_query}) or die "insert country prepare fail";

  foreach my $country (sort keys %block_list) {
    if (($country ne "") && (length($country) == 2)){
      $sth->execute($username,$country) or die "insert country execute fail";
    }
  }
  $sth->finish();

  my @testarray = &get_blocked_array("ipcountry_fraud");

  $dbh->disconnect();
}


sub get_blocked_array {
  my ($table) = @_;
  my @blocked_array = ();
  $db_query = "select entry from $table where username=? ";
  $dbh = &miscutils::dbhconnect("$frauddb");
  $sth = $dbh->prepare(qq{$db_query}) or die "failed prepare";
  $sth->execute($username) or die "failed execute";
  $sth->bind_columns(undef,\($blocked_entry));
  while ($sth->fetch) {
    $blocked_array[++$#blocked_array] = $blocked_entry;
  }
  $sth->finish();
  $dbh->disconnect();

  return @blocked_array;
}

sub update_config {
  my $config_string = "";
  if ($fraud_config_hash{'avs'} == -1) {
    delete $fraud_config_hash{'avs'};
  }
  foreach my $name (keys %fraud_config_hash) {
    $config_string .= $name . "\=" . $fraud_config_hash{$name} . "\,";
  }
  chop $config_string;

  my $gatewayAccount = new PlugNPay::GatewayAccount($username);
  $gatewayAccount->setFraudConfig($config_string);
  $gatewayAccount->save();
}

sub update_entry {
  my($table,$action,$block_list) = @_;

  if ($action eq "update") {
    foreach my $var (@$block_list)  {
      if ($var ne "") {
        $list{$var} = 1;
      }
    }
    @$block_list = (keys %list);

    my $dbh = &miscutils::dbhconnect("$frauddb");

    my $sth = $dbh->prepare(qq{
        delete from $table
        where username=?
    }) or die "failed prepare1.";
    $transaction_status = $sth->execute("$username") or die "failed execute.";
    $sth->finish();

    my $sth2 = $dbh->prepare(qq{
        insert into $table
        (username,entry)
        values(?,?)
    }) or die "failed prepare.";
    foreach my $entryvalue (@$block_list) {
      $sth2->execute("$username","$entryvalue");
    }
    $sth2->finish;

    $dbh->disconnect;
  }
  elsif (($action eq "add") && ($block_list ne "")) {

    my $dbh = &miscutils::dbhconnect("$frauddb");

    my $sth = $dbh->prepare(qq{
        select entry
        from $table
        where username=? and entry=?
        }) or die "Can't do: $DBI::errstr";
    $sth->execute("$username", "$block_list") or die "Can't execute: $DBI::errstr";
    my ($test) = $sth->fetchrow;
    $sth->finish;

    if ($test eq "") {
      my $sth = $dbh->prepare(qq{
          insert into $table
          (username,entry)
          values (?,?)
      }) or die "failed insert prepare.";
      $sth->execute("$username","$block_list");
      $sth->finish;
    }
    $dbh->disconnect;
  }
  elsif ($action eq "remove") {
    my $dbh = &miscutils::dbhconnect("$frauddb");
    foreach my $entryvalue (@$block_list) {
      my $sth = $dbh->prepare(qq{
          delete from $table
          where username=? and entry=?
       }) or die "failed prepare.";
       $sth->execute("$username","$entryvalue") or die "failed execute.";
       $sth->finish;
    }
    $dbh->disconnect;
  }
}

sub default_page {
  &default_head("FraudTrack");

  if (($username =~ /^(niche|pnpdemo2x)$/) || ($feature{'setholdbetaflg'} == 1)) {
    &fraudhold();
  }

  &highlimit();

  &app_level_select();

  &required_fields();

  if ($username =~ /^(niche|pnpdemo2x)$/) {
    &billship();
  }

  &cvv_input();

  if (($fraudtrack ne "") || ($reseller =~ /^(northame|stkittsn|cynergy|smart2pa|tri8inc|affinisc|lawpay)$/)) {
    #&email_input();
    #&mrchemail_input();
    if ($username =~ /^(pnpdev|motis|vmicardserv|nimbustelec|empiretowe|nabdemo)/) {
      &cybersource_input();
    }
    if (($username =~ /^(pnpdev)$/) || ($reseller =~ /^creditc3$/)) {
      &chk_netwrk();
    }
    if (($username =~ /^(pnpdevxxx)$/)) {
      &chk_precharge();
    }

    #if ($username =~ /^(pnpdev|pnpdemo)$/) {
    #  &chk_iTransact();
    #}
    &chk_cardname();

    if ($feature{'costdata'} == 1) {
      &chk_price();
    }

    &ipfrequency_input();
    &match_geolocation();
    &check_frequency();
    &duplicate_check();
    #&match_country();
    if (($ENV{'REMOTE_ADDR'} =~ /(96.56.10.12)/) || ($merchant =~ /^(pnpdev)/)) {
      &match_ardef();
    }
    &match_zip();
    #&block_foreign_input();
    #&block_us_input();

    &block_cardtypes_input();


    if ($tdsprocessor ne "") {
      &tds_enrollment_select();
    }

    &select_negative_level();

    if ($username =~ /^(pnpdemo2)/) {
      &iovation();
    }
    if (($username =~ /^(pnpdemo2)/) || ($reseller =~ /eye4frau/)) {
      &eye4fraud();
    }

    &block_ip();
    &block_ip_cntry();

    &block_bin();
    &block_bin_region();
    &block_proxy();
    &block_email_domain();
    if ($username =~ /^(niche|pnpdemo2x|paysvgtech)$/) {
      &block_emailaddr();
    }
    if (($ENV{'REMOTE_ADDR'} eq "96.56.10.12") || ($merchant =~ /^motis/)) {
      &acct_list_rules();
    }
    &block_phone();
    &block_country();

  }
  else {
    &ipfrequency_input();
    &select_negative_level();
    &submit_button();
  }
  &the_rest();
}

sub submit_button {
  print "  <tr>\n";
  print "    <td colspan=4 align=\"center\"><input type=\"button\" value=\"Update Fraud Screen Configuration\" onClick=\"updateConfigCheck();\"></td>\n";
  print "  </tr>\n";
}

sub default_head {
my ($title) = @_;

  print "<html>\n";
  print "<head>\n";

  print "<title>FraudTrak2 Administration </title>\n";
  print "<link href=\"/css/style_fraudtrak2.css\" type=\"text/css\" rel=\"stylesheet\">\n";

  # js logout prompt
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/javascript/jquery.min.js\"></script>\n";
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/javascript/jquery_ui/jquery-ui.min.js\"></script>\n";
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/javascript/jquery_cookie.js\"></script>\n";
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/_js/admin/autologout.js\"></script>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"/javascript/jquery_ui/jquery-ui.css\">\n";

  print "<script type='text/javascript'>\n";
  print "       /** Run with defaults **/\n";
  print "       \$(document).ready(function(){\n";
  print "         \$(document).idleTimeout();\n";
  print "        });\n";
  print "</script>\n";
  # end logout js


print <<EOF;
<SCRIPT LANGUAGE="Javascript">
//<!--
function help_win(helpurl,swidth,sheight) {
  SmallWin = window.open(helpurl, 'HelpWindow','scrollbars=yes,resizable=yes,toolbar=no,menubar=no,height='+sheight+',width='+swidth);
}

function change_win(helpurl,swidth,sheight) {
  SmallWin = window.open(helpurl, 'FunctionWindow',
  'scrollbars=yes,resizable=yes,status=yes,toolbar=yes,menubar=yes,height='+sheight+',width='+swidth);
}

function results() {
  resultsWindow = window.open("/payment/recurring/blank.html","results","menubar=no,status=no,scrollbars=yes,resizable=yes,width=400,height=300");
}

function deleteOption(object,index) {
  object.options[index] = null;
  //history.go(0);
}

function addOption(object,text,value) {
  var defaultSelected = true;
  var selected = true;
  var optionName = new Option(text, value, defaultSelected, selected);
  object.options[object.length] = optionName;
}

function copySelected(fromObject,toObject) {
  for (var i=0, l=fromObject.options.length;i<l;i++) {
    if (fromObject.options[i].selected) {
      addOption(toObject,fromObject.options[i].text,fromObject.options[i].value);
    }
  }
  for (var i=fromObject.options.length-1;i>-1;i--) {
    if (fromObject.options[i].selected) {
      deleteOption(fromObject,i);
    }
  }
}

function copyAll(fromObject,toObject) {
  for (var i=0, l=fromObject.options.length;i<l;i++) {
    addOption(toObject,fromObject.options[i].text,fromObject.options[i].value);
  }
  for (var i=fromObject.options.length-1;i>-1;i--) {
    deleteOption(fromObject,i);
  }
}

function selectAllSubmit(formobject,value) {
  for (var i=0;i<formobject.options.length;i++) {
    formobject.options[i].selected=true;
  }
  submitForm(value);
}

function setAll(formobject1,formobject2,value) {
  for (var i=0;i<formobject1.options.length;i++) {
    formobject1.options[i].selected=value;
  }
  for (var i=0;i<formobject2.options.length;i++) {
    formobject2.options[i].selected=value;
  }
}

function updateConfigCheck() {
  if (document.fraudtrack.cybersource) {
    if (document.fraudtrack.cybersource.value < 0) {
      alert("Cybersource should be at least 0.");
    }
    else if (document.fraudtrack.cybersource.value > 100) {
      alert("Cybersource cannot be greater than 100.");
    }
    else {
      document.fraudtrack.ffunction.value="update config";
      document.fraudtrack.submit();
    }
  }
  else {
    document.fraudtrack.ffunction.value="update config";
    document.fraudtrack.submit();
  }
}

function submitForm(value) {
  document.fraudtrack.ffunction.value=value;
  document.fraudtrack.submit();
}

function NetwrkMngmt() {
  NMFFWin = window.open("https://secure.onlineaccess.net/nm/?merchant=$username&gateway=1d251ff79ad34e3e9c9f305fe9a513a3","FraudManagementSystem","toolbar=no,menubar=no,location=no,scrollbars=yes,resizable=no,width=650,height=500");
}

//-->
</SCRIPT>
EOF

  print "<script Language=\"Javascript\">\n";
  print "//<!-- Start Script\n";

  print "function change_helpwin(helpurl,swidth,sheight,windowname) {\n";
  print "  SmallWin = window.open(helpurl, windowname,'scrollbars=yes,resizable=yes,status=yes,toolbar=yes,menubar=yes,height='+sheight+',width='+swidth);\n";
  print "}\n";

  print "function closewin() {\n";
  print "  self.close();\n";
  print "}\n";

  print "//-->\n";
  print "</script>\n";

  print "</head>\n";

  print "<body bgcolor=\"#ffffff\">\n";

  print "<table width=\"760\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\" id=\"header\">\n";
  print "  <tr>\n";
  print "    <td colspan=\"3\" align=\"left\">";
  if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
    print "<img src=\"/images/global_header_gfx.gif\" width=\"760\" alt=\"Plug 'n Pay Technologies - we make selling simple.\" height=\"44\" border=\"0\">";
  }
  else {
    print "<img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Logo\">";
  }
  print "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"3\" align=\"left\"><img src=\"/css/header_bottom_bar_gfx.gif\" width=\"760\" height=\"14\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table border=\"0\" cellspacing=\"0\" cellpadding=\"5\" width=\"760\">\n";
  print "  <tr>\n";
  print "    <td colspan=\"2\"><h1><a href=\"$ENV{'SCRIPT_NAME'}\">FraudTrak2 Administration</a> - $company</h1>\n";

  print "<table cellspacing=\"0\" cellpadding=\"0\" border=\"1\">\n";

  if ($feature{'setholdbetaflg'} == 1) {
    &holdrelease();
  }

  print "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\" name=\"fraudtrack\">\n";
  print "<input type=\"hidden\" name=\"ffunction\" value=\"\">\n";
  print "<input type=\"hidden\" name=\"merchant\" value=\"$username\">\n";
  print "<input type=\"hidden\" name=\"subacct\" value=\"$subacct\">\n";

  print "  <tr class=\"sectionmenu_title\">\n";
  print "    <th colspan=4>Fraud Screening</th>\n";
  print "  </tr>\n";

  return;
}

sub app_level_select {
  if (($username =~ /^(niche|pnpdemo2x)$/) || ($feature{'setholdbetaflg'} == 1)) {
    $rowspan = 2;
  }
  else {
    $rowspan = 1;
  }
  print "  <tr>\n";
  print "    <td class=\"menuleftside\" rowspan=$rowspan><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=AVS\&section=fraudtrack\',300,200)\"><nobr>AVS:</nobr></a></td>\n";

  if (($username =~ /^(niche|pnpdemo2x)$/) || ($feature{'setholdbetaflg'} == 1)) {
    print "    <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"avshold\" $fraud_config_hash{'avshold'}></td>\n";
    print "    <td class=\"menurightside\" colspan=2> Check to freeze AVS mismatch.</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
  }

  print "    <td class=\"menurightside\" colspan=3> \n";

  %avs_levels =(
    "-1", "Allow AVS Level to be set dynamically.",
    "0", "Allow all transactions. No transaction is rejected based on AVS",
    "1", "Requires match of Zip or Address, but allows where AVS is unavailable",
    "3", "Requires match of Zip or Address. All other transactions voided; including when AVS is unavailable.",
    "4", "Requires match of Address or a exact match (Zip & Address). All other trans voided; including when AVS is unavailable.",
    "5", "Requires exact match of Zip & Address. All other trans voided; including when AVS is unavailable.",
    "6", "Requires exact match of Zip & Address, but allows where AVS is unavailable."
  );


  print "<select name=\"avs\">\n";

  $selected{$fraud_config_hash{'avs'}} = " selected";
  foreach my $key (sort keys %avs_levels) {
    print "<option value=\"$key\" $selected{$key}>Level:$key - $avs_levels{$key}</option>\n";
  }
  print "</select>\n";

  print "</td>\n";
  print "  </tr>\n";
}


sub tds_enrollment_select {
  my (%selected);
  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=3DEnrollment\&section=fraudtrack\',300,200)\"><nobr>3D Enrollment Check:</nobr></a></td>\n";
  print "    <td class=\"menurightside\" colspan=3>\n";

  my %tds_levels =(
    "0", "Ignore 3D Enrollment Status - Default. No transaction is rejected based on the enrollment status check.",
    "1", "Reject if credit card is not enrolled in 3D.  Allows transactions to proceed if enrollment status check fails.",
    "2", "Reject all transaction request unless credit card is expressly validated as being enrolled.",
  );

  print "<select name=\"tdsRequireEnrollment\">\n";

  $selected{$fraud_config_hash{'tdsRequireEnrollment'}} = " selected";
  foreach my $key (sort keys %tds_levels) {
    print "<option value=\"$key\" $selected{$key}>Level:$key - $tds_levels{$key}</option>\n";
  }
  print "</select>\n";

  print "</td>\n";
  print "  </tr>\n";
}


sub cvv_input {
  if (($username =~ /^(niche|pnpdemo2x)$/) || ($feature{'setholdbetaflg'} == 1)) {
    $rowspan = 8;
  }
  else {
    $rowspan = 7;
  }

  print "  <tr>\n";
  print "    <td class=\"menuleftside\" rowspan=$rowspan><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=CVV\&section=fraudtrack\',300,200)\"><nobr>CVV2/CVC2:</nobr></a></td>\n";

  if (($username =~ /^(pnpdemo2x)$/) || ($feature{'setholdbetaflg'} == 1)) {
    print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"cvvhold\" $fraud_config_hash{'cvvhold'}></td>\n";
    print "    <td class=\"menurightside2\" colspan=2> Check to freeze CVV2/CVC2 mismatch.</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
  }

  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"cvv\" $fraud_config_hash{'cvv'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> Check to require CVV2/CVC2 data be submitted.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"cvv_swipe\" $fraud_config_hash{'cvv_swipe'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> Check to create exception for CVV2/CVC2 requirement for swiped cards.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"cvv_avs\" $fraud_config_hash{'cvv_avs'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> Check to ignore AVS response if CVV2/CVC2 data matches.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"cvv_xpl\" $fraud_config_hash{'cvv_xpl'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> Check to reject if CVV2/CVC2 information is not available from card holders bank.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"cvv_ign\" $fraud_config_hash{'cvv_ign'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> Check to ignore CVV2/CVC2 response.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"cvv_vt\" $fraud_config_hash{'cvv_vt'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> Check to require CVV2/CVC2 on Virtual Terminal authorizations.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"cvv_3dign\" $fraud_config_hash{'cvv_3dign'}></td>\n";
  print "    <td class=\"menurightside\" colspan=2> Check to ignore CVV2/CVC2 and AVS response on 3D authenticated transactions.</td>\n";
  print "  </tr>\n";


}

sub email_input {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><nobr>Customer Emails:</nobr></td>\n";
  print "    <td class=\"menurightside\" valign=\"top\"><!--<input type=\"checkbox\" name=\"noemail\" $fraud_config_hash{'noemail'}>--></td>\n";
  print "    <td class=\"menurightside\" colspan=2> This option is now set through the Email Management Area accessible from the main Admin menu.\n";
  print "<!-- Check to disable sending of confirming emails to customer on purchase. --></td>\n";
  print "  </tr>\n";
}

sub mrchemail_input {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><nobr>Merchant Emails:</nobr></td>\n";
  print "    <td class=\"menurightside\" valign=\"top\"><!--<input type=\"checkbox\" name=\"nomrchemail\" $fraud_config_hash{'nomrchemail'}>--></td>\n";
  print "    <td class=\"menurightside\" colspan=2> This option is now set through the Email Management Area accessible from the main Admin menu.\n";
  print "<!-- Check to disable sending of confirming emails to merchant on purchase.--></td>\n";
  print "  </tr>\n";
}

sub cybersource_input {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=cybersource\&section=fraudtrack\',300,200)\"><nobr>Cybersource:</nobr></a></td>\n";
  print "    <td class=\"menurightside\"><input type=\"text\" name=\"cybersource\" value=\"$fraud_config_hash{'cybersource'}\" size=2 maxlength=2></td>\n";
  print "    <td class=\"menurightside\" colspan=2> 0-99 Recommended starting point is 50. The higher the number the lower the security level.</td>\n";
  print "  </tr>\n";
}

sub ipfrequency_input {
  my $rows = 2;
  if ($fraudtrack eq "") {
    $rows = 1;
  }

  print "  <tr>\n";
  print "    <td class=\"menuleftside\" rowspan=$rows><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=ipfreq\&section=fraudtrack\',300,200)\"><nobr>IP Address<br>Frequency Check:</nobr></a></td>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"ipskip\" $fraud_config_hash{'ipskip'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> Check to skip IP frequency check, OR\n";
  print "<br> Only allow <input type=\"text\" name=\"ipfreq\" value=\"$fraud_config_hash{'ipfreq'}\" size=2 maxlength=2> Transactions per hour from the same IP address (Excluding AOL). 5-99 [Default is '5']</td>\n";
  print "  </tr>\n";

  if (($fraudtrack ne "") || ($reseller =~ /^(northame|stkittsn|cynergy|smart2pa|tri8inc|affinisc|lawpay)$/)) {
    print "  <tr>\n";
    #print "    <td class=\"menuleftside\"> &nbsp; </td>\n";
    print "    <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"ipexempt\" $fraud_config_hash{'ipexempt'}></td>\n";
    print "    <td class=\"menurightside\" colspan=2> Check to exempt IP's registered in Security Admin from IP frequency check.</td>\n";
    print "  </tr>\n";
  }
}

sub duplicate_check {
  my (%selected);
  if ($fraud_config_hash{'dupchkvar'} eq "acct_code") {
    $selected{'acct_code'} = " checked";
  }
  else {
    $selected{'noaction'} = " checked";
  }
  $selected{$fraud_config_hash{'dupchkresp'}} = " checked";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=dupchk\&section=fraudtrack\',300,200)\"><nobr>Duplicate Check:</nobr></a></td>\n";
  print "    <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"dupchk\" $fraud_config_hash{'dupchk'}></td>\n";
  print "    <td class=\"menurightside\" colspan=2> Check to enable duplicate checking.\n";
  print "<br> <input type=\"text\" name=\"dupchktime\" value=\"$fraud_config_hash{'dupchktime'}\" size=4 maxlength=4> Minute Window within which a transaction with same card number and dollar amount will be treated as a duplicate. 5-9999 [Default is '5']\n";
  print "<br> Select additional field to match: <input type=\"radio\" name=\"dupchkvar\" value=\"\" $selected{'noaction'}> None <input type=\"radio\" name=\"dupchkvar\" value=\"acct_code\" $selected{'acct_code'}> Acct. Code\n";
  print "<br> Select response: <input type=\"radio\" name=\"dupchkresp\" value=\"problem\" $selected{'problem'}> Problem <input type=\"radio\" name=\"dupchkresp\" value=\"echo\" $selected{'echo'}> Echo original status.</td>\n";
  print "  </tr>\n";
}

sub holdrelease {
  print "  <tr class=\"menusection_title\">\n";
  print "    <td colspan=4>Hold / Release Review</th>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=freeze\&section=fraudtrack\',300,200)\"><nobr>Frozen Transaction Review:</nobr></a></td>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2><form method=\"post\" action=\"holdrelease.cgi\">\n";
  print "<input type=\"hidden\" name=\"merchant\" value=\"$username\">\n";
  print "<input type=\"hidden\" name=\"subacct\" value=\"$subacct\">\n";
  print "<input type=submit value=\"Review Frozen Transaction\">\n";
  print "</td></form>\n";
  print "  </tr>\n";
}

sub check_frequency {
  my ($freqlev,$freqdays,$freqhours) = split(/\:/,$fraud_config_hash{'freqchk'});

  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=cardfreq\&section=fraudtrack\',300,200)\"><nobr>Card Number<br>Frequency Check:</nobr></a></td>\n";
  print "  <td class=\"menurightside\">&nbsp;</td>\n";
  print "  <td class=\"menurightside\" colspan=2> Only allow <select name=\"freqlev\">\n";
  print "<option value=\"\">Unlimited</option>\n";
  %selected = ();
  $selected{"$freqlev"} = " selected";
  for (my $i=1; $i<=12; $i++) {
    print "<option value=\"$i\" $selected{$i}>$i</option>\n";
  }
  %selected = ();
  print "</select> Sales within a timer period of ";
  $selected{"$freqdays"} = " selected";
  print "<select name=\"freqdays\">\n";
  for (my $i=0; $i<=33; $i++) {
    print "<option value=\"$i\" $selected{$i}>$i</option>\n";
  }
  print "</select> Days ";
  %selected = ();
  $selected{"$freqhours"} = " selected";
  print "<select name=\"freqhours\">\n";
  for (my $i=0; $i<=23; $i++) {
    print "<option value=\"$i\" $selected{$i}>$i</option>\n";
  }
  print "</select> Hours</td>\n";
  print "  </tr>\n";
}

sub block_foreign_input {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=foreign\&section=fraudtrack\',300,200)\"><nobr>Block Foreign Cards:</nobr></a></td>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2> Visa: <input type=\"checkbox\" name=\"blkfrgnrvs\" $fraud_config_hash{'blkfrgnrvs'}>\n";
  print " Mastercard: <input type=\"checkbox\" name=\"blkfrgnmc\" $fraud_config_hash{'blkfrgnmc'}>\n";
  print "    </td>\n";
  print "  </tr>\n";
}

sub block_cardtypes_input {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=types\&section=fraudtrack\',300,200)\"><nobr>Block Card Types:</nobr></a></td>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2> Visa: <input type=\"checkbox\" name=\"blkvs\" $fraud_config_hash{'blkvs'}>\n";
  print "      Mastercard: <input type=\"checkbox\" name=\"blkmc\" $fraud_config_hash{'blkmc'}>\n";
  #print "      Amex: <input type=\"checkbox\" name=\"blkax\" $fraud_config_hash{'blkax'}>\n";
  #print "      Discover: <input type=\"checkbox\" name=\"blkds\" $fraud_config_hash{'blkds'}>\n";
  print "      All Debit Cards: <input type=\"checkbox\" name=\"blkdebit\" $fraud_config_hash{'blkdebit'}>\n";
  print "      All Credit Cards: <input type=\"checkbox\" name=\"blkcredit\" $fraud_config_hash{'blkcredit'}>\n";
  print "</td>\n";
  print "  </tr>\n";
}

sub block_us_input {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=blockusinput\&section=fraudtrack\',300,200)\"><nobr>Block US IP Addresses:</nobr></a></td>\n";
  print "    <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"blkusip\" $fraud_config_hash{'blkusip'}></td>\n";
  print "    <td class=\"menurightside\" colspan=2> Check to block transactions originating from IP Addresses hosted within the United States.</td>\n";
  print "  </tr>\n";
}

sub fraudhold {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=freeze\&section=fraudtrack\',300,200)\"><nobr>Freeze or Block:</nobr></a></td>\n";
  print "    <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"fraudhold\" $fraud_config_hash{'fraudhold'}></td>\n";
  print "    <td class=\"menurightside\" colspan=2> Check to freeze fraudulent transactions. [Default is to BLOCK transactions flagged as fraudulent.]</td>\n";
  print "  </tr>\n";
}

sub billship {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=requiredfields\&section=fraudtrack\',300,200)\"><nobr>Billing/Shipping Addresses:</nobr></a></td>\n";
  print "    <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"billship\" $fraud_config_hash{'billship'}></td>\n";
  print "    <td class=\"menurightside\" colspan=2> Check to flag if Billing and Shipping Adress do NOT match.</td>\n";
  print "  </tr>\n";
}

sub highlimit {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\" rowspan=2><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=highlimit\&section=fraudtrack\',300,200)\"><nobr>High Limit Check:</nobr></a></td>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2> Transaction Amount <input type=\"text\" name=\"highlimit\" value=\"$fraud_config_hash{'highlimit'}\" size=9 maxlength=9> High Limit.</td>\n";
  print "  </tr>\n";
  print "    <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"ignhighlimit\" $fraud_config_hash{'ignhighlimit'}></td>\n";
  print "    <td class=\"menurightside\" colspan=2> Check to ignore High Limit if AVS and CVV match.</td>\n";
  print "  </tr>\n";
  #print "  <tr>\n";
}

sub required_fields {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=requiredfields\&section=fraudtrack\',300,200)\"><nobr>Require Addresses Fields:</nobr></a></td>\n";
  print "    <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"reqfields\" $fraud_config_hash{'reqfields'}></td>\n";
  print "    <td class=\"menurightside\" colspan=2> Check to require specified fields. <input type=\"checkbox\" name=\"reqaddr\" $fraud_config_hash{'reqaddr'}> Street Address  &nbsp; <input type=\"checkbox\" name=\"reqzip\" $fraud_config_hash{'reqzip'}> ZIP/Postal Code</td>\n";
  print "  </tr>\n";
}

sub block_ip {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\" rowspan=3><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=ipblock\&section=fraudtrack\',300,200)\"><nobr>Block IP Addr:</nobr></a></td>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"blkipaddr\" $fraud_config_hash{'blkipaddr'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> Check to block listed IP addresses.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"blksrcip\" $fraud_config_hash{'blksrcip'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> Check to include source IP in check.  Applicable for Remote API merchants only.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2>";

  print "<table border=1 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <td align=\"center\">IP Address: <input type=\"text\" name=\"ip_block\" size=16 maxlength=16>\n";
  print "<p><input type=\"button\" value=\"Add IP Address\" onClick=\"submitForm('add ip')\"></td>\n";
  print "    <td align=\"center\">Current Blocked:\n";
  print "<br><select name=\"ip_block_list\" size=4 multiple>\n";
  foreach my $entry (@blocked_ip_array) {
    print "<option value=\"$entry\">$entry</option>\n";
  }
  print "</select>\n";
  print "<br><input type=\"button\" value=\"Remove IP Address\" onClick=\"submitForm('remove ip')\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</td>\n";
  print "  </tr>\n";
}

sub block_ip_cntry {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\" rowspan=8><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=ipblock\&section=fraudtrack\',300,200)\"><nobr>Block Src IP Country:</nobr></a></td>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"blkipcntry\" $fraud_config_hash{'blkipcntry'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> Check to restrict which countries originating IP's are allowed from. All settings below will be ignored unless checked.  When checked default is to block all except those noted below.  <p>To block individual countries you need to check <b>allow ALL</b> first, then select which individual countries you wish to block.</td>\n";
  print "  </tr>\n";
  #print "  <tr>\n";
  #print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"blksrccntry\" $fraud_config_hash{'blksrccntry'}></td>\n";
  #print "    <td class=\"menurightside2\" colspan=2> Check to include source IP in check.  Applicable for Remote API merchants only.</td>\n";
  #print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"allow_src_all\" $fraud_config_hash{'allow_src_all'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> Check to allow ALL except blocked IP's.</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"allow_src_us\" $fraud_config_hash{'allow_src_us'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> Check to allow US based IP's.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"allow_src_ca\" $fraud_config_hash{'allow_src_ca'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> Check to allow Canadian based IP's.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"allow_src_mx\" $fraud_config_hash{'allow_src_mx'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> Check to allow Mexico based IP's.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"allow_src_eu\" $fraud_config_hash{'allow_src_eu'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> Check to allow European Union based IP's.</td>\n";
  print "  </tr>\n";

  #print "  <tr>\n";
  #print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"allow_src_lac\" $fraud_config_hash{'allow_src_lac'}></td>\n";
  #print "    <td class=\"menurightside2\" colspan=2> Check to allow Latin America and Caribbean based IP's.</td>\n";
  #print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"blk_src_eastern\" $fraud_config_hash{'blk_src_eastern'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> Check to block Eastern Europe based IP's. (Serbia, Russia, Ukraine, Poland, Hungry)</td>\n";
  print "  </tr>\n";


  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2>";

  print "<table border=1 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <td align=\"center\"> Available Countries\n";
  print "<br><select name=\"ipcountry_block_list1\" size=10 multiple>\n";
  foreach my $brief (sort keys %ipcountries) {
    print "<option value=\"$brief\">" . substr($ipcountries{"$brief"},0,20) . "</option>\n";
  }
  print "</select></td>\n";
  print "    <td align=\"center\"><input type=\"button\" value=\"<-\" onClick=\"if (document.images) copySelected(fraudtrack.ipcountry_block_list2,fraudtrack.ipcountry_block_list1)\">\n";
  print " <input type=\"button\" value=\"->\" onClick=\"if (document.images) copySelected(fraudtrack.ipcountry_block_list1,fraudtrack.ipcountry_block_list2)\">\n";
  print "<br><input type=\"button\" value=\"Select All\" onClick=\"setAll(fraudtrack.ipcountry_block_list2,fraudtrack.ipcountry_block_list1,true)\">\n";
  print "<br><input type=\"button\" value=\"Select None\" onClick=\"setAll(fraudtrack.ipcountry_block_list2,fraudtrack.ipcountry_block_list1,false)\">\n";
  print "<p><input type=\"button\" value=\"Update Countries\" onClick=\"selectAllSubmit(fraudtrack.ipcountry_block_list2,'Update IPCountries')\"></td>\n";
  print "    <td align=\"center\">Current Blocked\n";
  print "<br><select name=\"ipcountry_block_list2\" size=10 multiple>\n";
  print "<option value=\" \">&nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp;</option>\n";
  foreach my $brief (keys %blocked_ipcountry_hash) {
    print "<option value=\"$brief\" selected>" . substr($blocked_ipcountry_hash{"$brief"},0,20) . "</option>\n";
  }
  print "</select></td>\n";
  print "  </tr>\n";

  print "</table>\n";

  print "</td>\n";
  print "  </tr>\n";
}


sub block_emailaddr {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\" rowspan=2><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=ipblock\&section=fraudtrack\',300,200)\"><nobr>Block Email Addr:</nobr></a></td>\n";
  print "    <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"blkemailaddr\" $fraud_config_hash{'blkemailaddr'}></td>\n";
  print "    <td class=\"menurightside\" colspan=2> Check to block listed Email addresses.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2>";

  print "<table border=1 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <td><input type=\"text\" name=emailaddr_block size=40 maxlength=74> <input type=\"button\" value=\"Add Email Address\" onClick=\"submitForm('add emailaddr')\"></td>\n";
  print "    <td align=\"center\"> <select name=\"emailaddr_block_list\" size=4 multiple>\n";
  foreach my $entry (@blocked_emailaddr_array) {
    print "<option value=\"$entry\">$entry</option>\n";
  }
  print "</select>\n";
  print "<br> <input type=\"button\" value=\"Remove Email Address\" onClick=\"submitForm('remove emailaddr')\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</td>\n";
  print "  </tr>\n";
}

sub block_bin {
  my (%selected);
  if ($fraud_config_hash{'blkbin'} eq "checked") {
    $selected{'blkbin'} = " checked";
  }
  elsif ($fraud_config_hash{'allowbin'} eq "checked") {
    $selected{'allowbin'} = " checked";
  }
  else {
    $selected{'noaction'} = " checked";
  }

  print "  <tr>\n";
  print "    <td class=\"menuleftside\" rowspan=2><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=binblock\&section=fraudtrack\',300,200)\"><nobr>Block Bank Bins:</nobr></a></td>\n";
  print "    <td class=\"menurightside2\">&nbsp;</td>\n";
  print "    <td class=\"menurightside2\" colspan=2><input type=\"radio\" name=\"bankbin\" value=\"\" $selected{'noaction'}> No Action\n";
  print " <input type=\"radio\" name=\"bankbin\" value=\"block\" $selected{'blkbin'}> Block listed bank bins.\n";
  print " <input type=\"radio\" name=\"bankbin\" value=\"allow\" $selected{'allowbin'}> Only allow listed bank bins.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2>";

  print "<table border=1 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <td align=\"center\">Bank Bin: <input type=\"text\" name=\"bin_block\" size=6 maxlength=6>\n";
  print "<p><input type=\"button\" value=\"Add Bank Bin\" onClick=\"submitForm('add bin')\"></td>\n";
  print "    <td align=\"center\">Current Blocked:\n";
  print "<br><select name=\"bin_block_list\" size=4 multiple>\n";
  foreach my $entry (@blocked_bin_array) {
    print "<option value=\"$entry\">$entry</option>\n";
  }
  print "</select>\n";
  print "<br> <input type=\"button\" value=\"Remove Bank Bin\" onClick=\"submitForm('remove bin')\"></td>\n";
  print "    <td align=\"center\"><input type=\"button\" value=\"Export Bank Bin Table\" onClick=\"submitForm('Export Bin Fraud')\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</td>\n";
  print "  </tr>\n";
}


sub block_bin_region {
  my (%selected);
  if ($fraud_config_hash{'bankbin_reg_action'} eq "block") {
    $selected{'blockbinreg'} = " checked";
  }
  elsif ($fraud_config_hash{'bankbin_reg_action'} eq "allow") {
    $selected{'allowbinreg'} = " checked";
  }
  else {
    $selected{'noaction'} = " checked";
  }

  print "  <tr>\n";
  print "    <td class=\"menuleftside\" rowspan=3><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=binblock\&section=fraudtrack\',300,200)\"><nobr>Block Bank Bin Regions:</nobr></a></td>\n";
  print "    <td class=\"menurightside2\"><input type=\"checkbox\" name=\"bankbin_reg\" $fraud_config_hash{'bankbin_reg'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> Check to act on Bank Bin Region.</td>\n";
  print "  </tr>\n";
  print "   <tr>\n";
  print "    <td class=\"menurightside2\" colspan=3>\n";
  print " <input type=\"radio\" name=\"bankbin_reg_action\" value=\"block\" $selected{'blockbinreg'}> Block checked regions.\n";
  print " <input type=\"radio\" name=\"bankbin_reg_action\" value=\"allow\" $selected{'allowbinreg'}> Only allow checked regions.</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2>";

  print "<table border=1 cellspacing=0 cellpadding=2 width=\"100%\">\n";

  print "  <tr>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"bin_reg_us\" $fraud_config_hash{'bin_reg_us'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> US (United States) Region.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"bin_reg_ca\" $fraud_config_hash{'bin_reg_ca'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> CAN (Canadian) Region</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"bin_reg_eu\" $fraud_config_hash{'bin_reg_eu'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> EU (European Union) Region.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"bin_reg_ap\" $fraud_config_hash{'bin_reg_ap'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> AP (Asia Pacific) Region.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"bin_reg_lac\" $fraud_config_hash{'bin_reg_lac'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> LAC (Latin America/Caribbean) Region.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"bin_reg_samea\" $fraud_config_hash{'bin_reg_samea'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> SAMEA (South Asia, Middle East, Africa) Region.</td>\n";
  print "  </tr>\n";

  print "</table>\n";

  print "</td>\n";
  print "  </tr>\n";


}



sub block_phone {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\" rowspan=2><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=phoneblock\&section=fraudtrack\',300,200)\"><nobr>Block Phone Numbers:</nobr></a></td>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"blkphone\" $fraud_config_hash{'blkphone'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> Check to block listed phone numbers.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2>\n";

  print "<table border=1 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <td align=\"center\">Phone Number: <input type=\"text\" name=\"phone_block\" size=10 maxlength=15>\n";
  print "<p><input type=\"button\" value=\"Add Phone Number\" onClick=\"submitForm('add phone')\"></td>\n";
  print "    <td align=\"center\"> Current Blocked:\n";
  print "<br><select name=\"phone_block_list\" size=4 multiple>\n";
  foreach my $entry (@blocked_phone_array) {
    print "<option value=\"$entry\">$entry</option>\n";
  }
  print "</select>\n";
  print "<br> <input type=\"button\" value=\"Remove Phone Number\" onClick=\"submitForm('remove phone')\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</td>\n";
  print "  </tr>\n";
}


sub block_proxy {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=proxyblock\&section=fraudtrack\',300,200)\"><nobr>Block Proxy:</nobr></a></td>\n";
  print "      <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"blkproxy\" $fraud_config_hash{'blkproxy'}></td>\n";
  print "      <td class=\"menurightside\" colspan=2> Check to block anonmynizer proxies.</td>\n";
  print "  </tr>\n";
}

sub block_email_domain {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\" rowspan=2><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=emailblock\&section=fraudtrack\',300,200)\"><nobr>Block Email Domain:</nobr></a></td>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"blkemails\" $fraud_config_hash{'blkemails'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> Check to block listed email domains.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2>\n";

  print "<table border=1 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <td width=\"33%\" align=\"center\">Available Domains:\n";
  print "<br><select name=\"email_block_list1\" size=4 multiple>\n";
  foreach my $entry (@default_blocked_email_array) {
    print "<option value=\"$entry\">$entry</option>\n";
  }
  print "</select>\n";
  print "<br>[or add additional domains below]</td>\n";
  print "    <td width=\"34%\" align=\"center\"><input type=\"button\" value=\"<-\" onClick=\"if (document.images) copySelected(fraudtrack.email_block_list2,fraudtrack.email_block_list1)\">\n";
  print " <input type=\"button\" value=\"->\" onClick=\"if (document.images) copySelected(fraudtrack.email_block_list1,fraudtrack.email_block_list2)\">\n";
  print "<br><input type=\"button\" value=\"Select All\" onClick=\"setAll(fraudtrack.email_block_list2,fraudtrack.email_block_list1,true)\">\n";
  print "<br><input type=\"button\" value=\"Select None\" onClick=\"setAll(fraudtrack.email_block_list2,fraudtrack.email_block_list1,false)\"></td>\n";
  print "    <td width=\"33%\" align=\"center\">Current Blocked:\n";
  print "<br><select name=\"email_block_list2\" size=4 multiple>\n";
  foreach my $entry (@blocked_email_array) {
    print "<option value=\"$entry\">$entry</option>\n";
  }
  print "</select></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td colspan=3 align=\"center\"><input type=\"text\" name=\"email_block\" size=15 maxlength=30>\n";
  print " <input type=\"button\" value=\"Add Domain\" onClick=\"addOption(fraudtrack.email_block_list2,fraudtrack.email_block.value,fraudtrack.email_block.value)\">\n";
  print " <input type=\"button\" value=\"Update List\" onClick=\"selectAllSubmit(fraudtrack.email_block_list2,'update domain')\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</td>\n";
  print "  </tr>\n";
}

sub bounced_emails {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\" rowspan=3><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=bouncedemails\&section=fraudtrack\',300,200)\"><nobr>Bounced Emails:</nobr></a></td>\n";
  my %bounce_hash = ();
  $bounce_hash{$fraud_config_hash{'bounced'}} = "selected";
  print "    <td class=\"menurightside\" align=\"left\" colspan=\"1\">&nbsp;</td>\n";
  print "    <td  class=\"menurightside\" colspan=\"2\"> <select name=\"bounced\">\n";
  print "<option value=\"0\" " . $bounce_hash{"0"} . "> Off </option>\n";
  print "<option value=\"1\" " . $bounce_hash{"1"} . "> Notify and Return </option>\n";
  print "<option value=\"2\" " . $bounce_hash{"2"} . "> Notify </option>\n";
  print "</select></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=\"2\"> <input type=\"text\" name=\"bounced_email\" value=\"$fraud_config_hash{'bounced_email'}\" size=30 maxlength=60> Notification Email.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td colspan=\"2\"> <input type=\"text\" name=\"bounced_url\" value=\"$fraud_config_hash{'bounced_url'}\" size=30 maxlength=60> Notification URL</td>\n";
  print "  </tr>\n";
}

sub acct_list_rules {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\" rowspan=4><a href=\"javascript:help_win(\'/admin/help/help.cgi?topic=acctlistrules\&section=fraudtrack\',300,200)\"><nobr>Acct List Rules:</nobr></a></td>\n";
  print "    <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"chkaccts\" $fraud_config_hash{'chkaccts'}></td>\n";
  print "    <td class=\"menurightside\" colspan=2> Check to enable checking for account list rules.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2><input type=\"text\" name=\"volimit\" value=\"$fraud_config_hash{'volimit'}\" size=8 maxlength=8> Daily Limit</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2><input type=\"text\" name=\"allowedage\" value=\"$fraud_config_hash{'allowedage'}\" size=8 maxlength=8> Minimum card age</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2><input type=\"text\" name=\"acctlist\" value=\"$fraud_config_hash{'acctlist'}\" size=30 maxlength=60> Accounts</td>\n";
  print "  </tr>\n";
}

#sub customer_service {
#  print "  <tr>\n";
#  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/help/help.cgi?topic=customerservice\&section=fraudtrack\',300,200)\"><nobr>Customer Service:</nobr></a></td>\n";
#  print "    <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"custserv\" $fraud_config_hash{'custserv'}></td>\n";
#  print "    <td class=\"menurightside\" colspan=2> Check to enable customer self-service transaction void/return capability.</td>\n";
#  print "  </tr>\n";
#}

sub match_country {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=matchcountry\&section=fraudtrack\',300,200)\"><nobr>Match Country:</nobr></a></td>\n";
  print "    <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"matchcntry\" $fraud_config_hash{'matchcntry'}></td>\n";
  print "    <td class=\"menurightside\" colspan=2> Check to require Billing Address Country to match Card Issuing Country.</td>\n";
  print "  </tr>\n";
}

sub match_ardef {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=matchardef\&section=fraudtrack\',300,200)\"><nobr>Match Card Currency:</nobr></a></td>\n";
  print "    <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"matchardef\" $fraud_config_hash{'matchardef'}></td>\n";
  print "    <td class=\"menurightside\" colspan=2> Check to require Billing Address Country to match currency of issued card.</td>\n";
  print "  </tr>\n";
}

sub match_geolocation {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=matchgeolocation\&section=fraudtrack\',300,200)\"><nobr>Match IP to Card Country:</nobr></a></td>\n";
  print "    <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"matchgeoip\" $fraud_config_hash{'matchgeoip'}></td>\n";
  print "    <td class=\"menurightside\" colspan=2> Check to require Billing Address Country to match country of IP address.\n";
  print "<br> NOTE: Matching IP address to country of origin is not an exact science.\n";
  print "<br> Data is provided by <a href=\"http://www.digitalenvoy.net/technology/netacuity.shtml/\" target=\"_blank\"><font color=\"#0000ff\">Digital Envoy's NetAcuity</font></a>.  Accuracy is estimated to be 99%.</td>\n";
  print "  </tr>\n";
}

sub iovation {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=matchgeolocation\&section=fraudtrack\',300,200)\"><nobr>ioVation Fraud Screen:</nobr></a></td>\n";
  print "    <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"iovation\" $fraud_config_hash{'iovation'}></td>\n";
  print "    <td class=\"menurightside\" colspan=2> Check to screen transaction with ioVations Fraudscreening system. Requires separate account with ioVation.</td>\n";
  print "  </tr>\n";
}

sub eye4fraud {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=eye4fraud\&section=fraudtrack\',300,200)\"><nobr>Eye4Fraud Fraud Screen:</nobr></a></td>\n";
  print "    <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"eye4fraud\" $fraud_config_hash{'eye4fraud'}></td>\n";
  print "    <td class=\"menurightside\" colspan=2> Check to screen transaction with eye4fraud Fraudscreening system. Requires separate account with eye4fraud.</td>\n";
  print "  </tr>\n";
}

sub chk_cardname {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=chkname\&section=fraudtrack\',300,200)\"><nobr>Check Card Name:</nobr></a></td>\n";
  print "    <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"chkname\" $fraud_config_hash{'chkname'}></td>\n";
  print "    <td class=\"menurightside\" colspan=2> Check to have Billing Name checked for format.</td>\n";
  print "  </tr>\n";
}

sub chk_netwrk {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/help/help.cgi?topic=netwrk\&section=fraudtrack\',300,200)\"><nobr>Network Merchant:</nobr></a></td>\n";
  print "    <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"netwrk\" $fraud_config_hash{'netwrk'}></td>\n";
  print "    <td class=\"menurightside\" colspan=2><!--<input type=\"text\" size=35 maxsize=35 name=\"netwrk\" value=\"$fraud_config_hash{'netwrk'}\">-->\n";
  print " Check to enable the Network Merchant fraud screen. <a href=\"javascript:NetwrkMngmt()\"><font color=\"#000000\">Click Here to Configure.</font></a></td>\n";
  print "  </tr>\n";
}

sub chk_iTransact {
  my($iTransUN,$iTransPW,$iTransLevel,$iTransRule) = split(/\:/,$fraud_config_hash{'iTransConfig'});
  my(%selected);
  $selected{$iTransLevel} = "checked";
  $selected{$iTransRule} = "checked";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\" rowspan=5><a href=\"javascript:help_win(\'/admin/help/help.cgi?topic=iTransact\&section=fraudtrack\',300,200)\"><nobr>iTransact:</nobr></a></td>\n";
  print "    <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"iTransact\" $fraud_config_hash{'iTransact'}></td>\n";
  print "    <td class=\"menurightside\" colspan=2> Check to enable the iTransact fraud screen.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2><input type=\"text\" name=\"iTransactUN\" size=15 value=\"$iTransUN\"> iTransact Username.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2><input type=\"text\" name=\"iTransactPW\" size=15 value=\"$iTransPW\"> iTransact Online Password.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2> <input type=\"radio\" name=\"iTransactLevel\" value=\"tier1\" $selected{'tier1'}> Tier 1\n";
  print " <input type=\"radio\" name=\"iTransactLevel\" value=\"tier2\" $selected{'tier2'}> Tier 2\n";
  print " <input type=\"radio\" name=\"iTransactLevel\" value=\"auto\" $selected{'auto'}> Auto &nbsp;\n";
  print " iTransact Fraud Screening Level.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"iTransactRule\" $selected{'1'}></td>\n";
  print "    <td class=\"menurightside\" colspan=2> Check box to fail transaction when an error occurs communicating to iTransact or if no questions are returned during a Tier 2 check.</td>\n";
  print "  </tr>\n";
}

sub chk_precharge {
  my ($precharge,$merch_id,$sec1,$sec2,$misc_field_1,$misc_field_2,$misc_field_3,$misc_field_4,$misc_field_5) = split('\|',$fraud_config_hash{'precharge'});
  my(%selected);
  $selected{$precharge} = "checked";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\" rowspan=9><a href=\"javascript:help_win(\'/admin/help/help.cgi?topic=precharge\&section=fraudtrack\',300,200)\"><nobr>preCharge:</nobr></a></td>\n";
  print "    <td class=\"menurightside\" valign=\"top\"><$fraud_config_hash{'precharge'}><input type=\"checkbox\" name=\"precharge\" value=\"on\" $selected{'on'}></td>\n";
  print "    <td class=\"menurightside\" colspan=2> Check to enable the preCharge fraud screen.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2><input type=\"text\" name=\"merch_id\" size=15 value=\"$merch_id\"> preCharge Merchant ID</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2><input type=\"text\" name=\"sec1\" size=15 value=\"$sec1\"> Security Key 1.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2><input type=\"text\" name=\"sec2\" size=15 value=\"$sec2\"> Security Key 1.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2><input type=\"text\" name=\"misc_field_1\" size=15 value=\"$misc_field_1\"> Misc. Data Field 1 Map</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2><input type=\"text\" name=\"misc_field_2\" size=15 value=\"$misc_field_2\"> Misc. Data Field 2 Map</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2><input type=\"text\" name=\"misc_field_3\" size=15 value=\"$misc_field_3\"> Misc. Data Field 3 Map</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2><input type=\"text\" name=\"misc_field_4\" size=15 value=\"$misc_field_4\"> Misc. Data Field 4 Map</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2><input type=\"text\" name=\"misc_field_5\" size=15 value=\"$misc_field_5\"> Misc. Data Field 5 Map</td>\n";
  print "  </tr>\n";
}

sub match_zip {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=matchzip\&section=fraudtrack\',300,200)\"><nobr>Match Zip Code:</nobr></a></td>\n";
  print "    <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"matchzip\" $fraud_config_hash{'matchzip'}></td>\n";
  print "    <td class=\"menurightside\" colspan=2> Check to require Billing Address Zip Code to match Billing Address State.</td>\n";
  print "  </tr>\n";
}

sub block_country {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\" rowspan=2><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=countryblock\&section=fraudtrack\',300,200)\"><nobr>Block Country:</nobr></a></td>\n";
  print "    <td class=\"menurightside2\" valign=\"top\"><input type=\"checkbox\" name=\"blkcntrys\" $fraud_config_hash{'blkcntrys'}></td>\n";
  print "    <td class=\"menurightside2\" colspan=2> Check to block listed countries.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2>";

  print "<table border=1 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <td align=\"center\"> Available Countries\n";
  print "<br><select name=\"country_block_list1\" size=10 multiple>\n";
  foreach my $brief (sort keys %countries) {
    print "<option value=\"$brief\">" . substr($ipcountries{"$brief"},0,20) . "</option>\n";
  }
  print "</select></td>\n";
  print "    <td align=\"center\"><input type=\"button\" value=\"<-\" onClick=\"if (document.images) copySelected(fraudtrack.country_block_list2,fraudtrack.country_block_list1)\">\n";
  print " <input type=\"button\" value=\"->\" onClick=\"if (document.images) copySelected(fraudtrack.country_block_list1,fraudtrack.country_block_list2)\">\n";
  print "<br><input type=\"button\" value=\"Select All\" onClick=\"setAll(fraudtrack.country_block_list2,fraudtrack.country_block_list1,true)\">\n";
  print "<br><input type=\"button\" value=\"Select None\" onClick=\"setAll(fraudtrack.country_block_list2,fraudtrack.country_block_list1,false)\">\n";
  print "<p><input type=\"button\" value=\"Update Countries\" onClick=\"selectAllSubmit(fraudtrack.country_block_list2,'Update Countries')\"></td>\n";
  print "    <td align=\"center\">Current Blocked\n";
  print "<br><select name=country_block_list2 size=10 multiple>\n";
  print "<option value=\" \">&nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp;</option>\n";
  foreach my $brief (keys %blocked_country_hash) {
    print "<option value=\"$brief\" selected>" . substr($blocked_country_hash{"$brief"},0,20) . "</option>\n";
  }
  print "</select></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</td>\n";
  print "</tr>\n";

  print "  <tr>\n";
  print "    <td colspan=4 align=\"center\">&nbsp;<br><input type=\"button\" value=\"Update Fraud Screen Configuration\" onClick=\"updateConfigCheck()\"><br>&nbsp;</td>\n";
  print "  </tr>\n";
}

sub customer_service {
  print "  <tr class=\"menusection_title\">\n";
  print "    <th colspan=4>&nbsp;</th>\n";
  print "  </tr>\n";

  print "  <tr class=\"menusection_title\">\n";
  print "    <th colspan=4>Customer Service Profile</th>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"/admin/custserv.cgi\" target=\"results\" onClick=\"results()\"><nobr>Customer Service<br>Profile</nobr></a></td>\n";
  print "    <td class=\"menurightside\" colspan=3><a href=\"/admin/custserv.cgi\" target=\"results\" onClick=\"results()\">Customer Service Profile</a></td>\n";
  print "  </tr>\n";
}

sub select_negative_level {
  my ($check_all);
  my (%selected);
  if ($fraud_config_hash{'negative'} eq "") {
    $check_all = "checked";
  }
  else {
    $selected{$fraud_config_hash{'negative'}} = " checked";
  }

  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=negative\&section=fraudtrack\',300,200)\"><nobr>Negative Database:</nobr></a></td>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\" colspan=2> Use all: <input type=\"radio\" name=\"negative\" value=\"\" $check_all> &nbsp;\n";
  print " Use only my submitted numbers: <input type=\"radio\" name=\"negative\" value=\"self\" $selected{'self'}> &nbsp;\n";
  print " Skip check:<input type=\"radio\" name=\"negative\" value=\"skip\" $selected{'skip'}></td>\n";
  print "  </tr>\n";
}

sub chk_price {
  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=chkprice\&section=fraudtrack\',300,200)\"><nobr>Price Validation:</nobr></a></td>\n";
  print "    <td class=\"menurightside\" valign=\"top\"><input type=\"checkbox\" name=\"chkprice\" $fraud_config_hash{'chkprice'}></td>\n";
  print "    <td class=\"menurightside\" colspan=2> Check to have submitted items costs validated again <a href=\"price_mgt.cgi\"><font color=\"#0000ff\">Price Validation Database</font></a>.</td>\n";
  print "  </tr>\n";
}

sub the_rest {
  print "  <tr class=\"menusection_title\">\n";
  print "    <th colspan=4>Negative Database</th>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=negativedatabase\&section=fraudtrack\',300,200)\"><nobr>Negative Database:</nobr></a></td>\n";
  print "  <td class=\"menurightside\" colspan=3>";

  print "<table border=1 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <td colspan=2>Enter Order ID or Card Number:</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"leftside\">Order ID:</td>\n";
  print "    <td class=\"rightside\"><input type=\"text\" name=\"orderID\" size=20 maxlength=20></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"leftside\">Card Number:</td>\n";
  print "    <td class=\"rightside\"><input type=\"text\" name=\"cardnumber\" size=16 autocomplete=\"off\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"leftside\">Select Reason:</td>\n";
  print "    <td class=\"rightside\"><select name=\"reason\">\n";
  print "<option value=\"Card Reported as Stolen\">Card Reported as Stolen</option>\n";
  print "<option value=\"Chargeback\">Chargeback</option>\n";
  print "</select></td>\n";
  print "  </tr>\n";
  #print "  <tr>\n";
  #print "    <td class=\"leftside\">Give Your Own Reason:</td>\n";
  #print "    <td class=\"rightside\"><input type=\"text\" name=\"other\" size=40 maxlength=64></td>\n";
  #print "</tr>\n";
  print "  <tr>\n";
  print "    <td colspan=2><input type=\"button\" value=\"Add Card to Fraud Database\" onClick=\"submitForm('Add Card to Fraud Database')\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</td>\n";
  print "  </tr>\n";

  #if ($fraudtrack ne "") {
    print "  <tr class=\"menusection_title\">\n";
    print "    <th colspan=4>Positive Database</th>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=positivedatabase\&section=fraudtrack\',300,200)\"><nobr>Positive Database:</a> $positive_cnt</nobr></td>\n";
    print "    <td class=\"menurightside\" colspan=3>\n";

    print "<table border=1 cellspacing=0 cellpadding=2 width=\"100%\">\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">Card Number:</td>\n";
    print "    <td class=\"rightside\"><input type=\"text\" name=\"poscardnumber\" size=16 autocomplete=\"off\"></td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td colspan=2><input type=\"button\" value=\"Add Card to Positive Database\" onClick=\"submitForm('Add Card to Positive Database')\">\n";
    print "<input type=\"button\" value=\"Remove Card from Positive Database\" onClick=\"submitForm('Remove Card from Positive Database')\"></td>\n";
    print "  </tr>\n";
    print "  </table>\n";

    print "</td>\n";
    print "  </tr>\n";

    #print "  <tr>\n";
    #print "    <td class=\"menuleftside\" align=\"right\" colspan=4><b>$company</b></td>\n";
    #print "  </tr>\n";
    print "</table>\n";

    print "</form>\n";
  #}

  my @now = gmtime(time);
  my $copy_year = $now[5]+1900;

  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table width=\"760\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\" id=\"footer\">\n";
  print "  <tr>\n";
  print "    <td align=\"left\"><p><a href=\"/admin/logout.cgi\" title=\"Click to log out\">Log Out</a> | <a href=\"javascript:change_helpwin('/admin/helpdesk.cgi',600,500,'ahelpdesk')\">Help Desk</a> | <a id=\"close\" href=\"javascript:closewin();\" title=\"Click to close this window\">Close Window</a></p></td>\n";
  print "    <td align=\"right\"><p>\&copy; $copy_year, ";
  if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
    print "Plug and Pay Technologies, Inc.";
  }
  else {
    print "$ENV{'SERVER_NAME'}";
  }
  print "</p></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</body>\n";
  print "</html>\n";

  return;
}

sub add_to_cc_fraud {
  my @now = gmtime(time);
  my $today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

  my $orderID = &CGI::escapeHTML($query->param('orderID'));
  $orderID =~ s/[^0-9]//g;

  my $cardnumber = &CGI::escapeHTML($query->param('cardnumber'));
  $cardnumber =~ s/[^0-9]//g;

  my $reason = &CGI::escapeHTML($query->param('reason'));
  $reason =~ s/[^a-zA-Z0-9\_\-\ ]//g;

  my $other = &CGI::escapeHTML($query->param('other'));
  $other =~ s/[^a-zA-Z0-9\_\-\ ]//g;

  if ($other ne "") {
    $reason = $other;
  }

  $reason = substr($reason,0,64);

  if ($orderID ne "") {
    # query encrypted card number for given orderID
    my $dbh = &miscutils::dbhconnect("pnpdata","","$username");
    my $sth = $dbh->prepare(qq{
        select orderid
        from trans_log
        where username=? and orderid=?
      }) or die "Can't do: $DBI::errstr";
    $sth->execute("$username", "$orderID") or die "Can't execute: $DBI::errstr";
    my ($db_orderid) = $sth->fetchrow;
    $sth->finish;
    $dbh->disconnect;

    if ($db_orderid ne "$orderID") {
      my $message = "<h3>Invalid Order ID Number</h3>\n";
      &response_page("$message");
      exit;
    }

    my $db_enccardnumber = &smpsutils::getcardnumber($username,$orderID,'fraud_database','',{suppressAlert => 1});

    # decrypt encrypted card number
    $cardnumber = &rsautils::rsa_decrypt_file($db_enccardnumber,$db_length,"print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");
    $cardnumber =~ s/[^0-9]//g;
  }

  # do luhn10 error check
  $luhntest = &miscutils::luhn10($cardnumber);

  if ($luhntest eq "failure") {
    my $message = "<h3>Invalid Credit Card Number</h3>\n";
    &response_page("$message");
    exit;
  }

  $md5 = new MD5;
  $md5->add("$cardnumber");
  $enccardnumber = $md5->hexdigest();

  $cardnumber = substr($cardnumber,0,4) . '**' . substr($cardnumber,length($cardnumber)-2,2);

  $dbh = &miscutils::dbhconnect("pnpmisc");

  $sth = $dbh->prepare(qq{
        select enccardnumber from fraud
        where enccardnumber=?
        }) or die "Can't do: $DBI::errstr";
  $sth->execute("$enccardnumber") or die "Can't execute: $DBI::errstr";
  ($enccardnumber2) = $sth->fetchrow;
  $sth->finish;

  if ($enccardnumber ne $enccardnumber2) {
    $sth = $dbh->prepare(qq{
        insert into fraud
        (enccardnumber,card_number,username,trans_date,descr)
        values (?,?,?,?,?)
        }) or die "Can't do: $DBI::errstr";
    $sth->execute("$enccardnumber","$cardnumber","$username","$today","$reason") or die "Can't execute: $DBI::errstr";
    $sth->finish;

    my $message = "<h3>Credit Card Number successfully added to fraud database</h3>\n";
    &response_page("$message");
  }
  else {
    my $message = "<h3>Credit Card Number is already in fraud database</h3>\n";
    &response_page("$message");
  }
  $dbh->disconnect;
}

sub add_to_positive {

  my $cardnumber = &CGI::escapeHTML($query->param('poscardnumber'));

  # strip out all non-numeric characters - 07/26/05 - James
  $cardnumber =~ s/[^0-9]//g;

  $luhntest = &miscutils::luhn10($cardnumber);

  if ($luhntest eq "failure") {
    my $message = "<h3>Invalid Credit Card Number</h3>\n";
    &response_page("$message");
    exit;
  }

  my ($dummy1,$trans_date,$dummy) = &miscutils::gendatetime();
  my $ipaddress = $ENV{'REMOTE_ADDR'};

  my $sha1 = new SHA;
  $sha1->reset;
  $sha1->add("$cardnumber");
  $shacardnumber = $sha1->hexdigest();

  #$dbh = &miscutils::msqlconnect("fraudtrack");
  $dbh=&miscutils::dbhconnect("fraudtrack");

  $sth = $dbh->prepare(qq{
        select shacardnumber from fraud_exempt
        where shacardnumber=?
        and username=?
        }) or die "Can't do: $DBI::errstr";
  $sth->execute($shacardnumber,$username) or die "Can't execute: $DBI::errstr";
  ($test) = $sth->fetchrow;
  $sth->finish;

  if ($test eq "") {
    $sth = $dbh->prepare(qq{
        insert into fraud_exempt
        (shacardnumber,username,trans_date,ipaddress)
        values (?,?,?,?)
        }) or die "Can't do: $DBI::errstr";
    $sth->execute("$shacardnumber","$username","$trans_date","$ipaddress") or die "Can't execute: $DBI::errstr";
    $sth->finish;

    my $message = "<h3>Credit Card Number successfully added to Positive database</h3>\n";
    &response_page("$message");
  }
  else {
    my $message = "<h3>Credit Card Number is already in Positive database</h3>\n";
    &response_page("$message");
  }
  $dbh->disconnect;
}

sub remove_from_positive {

  my $cardnumber = &CGI::escapeHTML($query->param('poscardnumber'));

  # strip out all non-numeric characters - 07/26/05 - James
  $cardnumber =~ s/[^0-9]//g;

  $luhntest = &miscutils::luhn10($cardnumber);

  if ($luhntest eq "failure") {
    my $message = "<h3>Invalid Credit Card Number</h3>\n";
    &response_page("$message");
    exit;
  }

  my ($dummy1,$trans_date,$dummy) = &miscutils::gendatetime();
  my $ipaddress = $ENV{'REMOTE_ADDR'};

  my $sha1 = new SHA;
  $sha1->reset;
  $sha1->add("$cardnumber");
  $shacardnumber = $sha1->hexdigest();

  #$dbh = &miscutils::msqlconnect("fraudtrack");
  $dbh=&miscutils::dbhconnect("fraudtrack");

  $sth = $dbh->prepare(qq{
        select shacardnumber from fraud_exempt
        where shacardnumber=?
        and username=?
        }) or die "Can't do: $DBI::errstr";
  $sth->execute($shacardnumber,$username) or die "Can't execute: $DBI::errstr";
  ($test) = $sth->fetchrow;
  $sth->finish;

  if ($test eq "$shacardnumber") {
    $sth = $dbh->prepare(qq{
        delete from fraud_exempt
        where shacardnumber=?
        and username=?
        }) or die "Can't do: $DBI::errstr";
    $sth->execute($shacardnumber,$username) or die "Can't execute: $DBI::errstr";
    $sth->finish;

    my $message = "<h3>Credit Card Number successfully removed from the Positive database</h3>\n";
    &response_page("$message");
  }
  else {
    my $message = "<h3>Credit Card Number is not in the Positive database</h3>\n";
    &response_page("$message");
  }
  $dbh->disconnect;
}

sub print_company {
  print "<tr><td align=\"right\" colspan=2><b>$company</b></td></tr>";
}

sub overview {
  my($reseller,$merchant) = @_;
  my ($db_merchant,$db_company,$db_status,$db_features);

  my $gatewayAccount = new PlugNPay::GatewayAccount($merchant);

  if (($gatewayAccount->getReseller() eq $reseller) && ($gatewayAccount->getGatewayAccountName() eq $merchant)) {
    $db_merchant = $gatewayAccount->getGatewayAccountName();
    $db_company = $gatewayAccount->getCompanyName();
    $db_status = $gatewayAccount->getStatus();
    $db_features = $gatewayAccount->getRawFeatures();
  }

  return $db_merchant,$db_company,$db_status,$db_features;
}

sub response_page {
  my ($message) = @_;

  #print "Content-Type: text/html\n\n";

  print "<html>\n";
  print "<head>\n";
  print "<title>FraudTrak2 Administration </title>\n";
  print "<link href=\"/css/style_fraudtrak2.css\" type=\"text/css\" rel=\"stylesheet\">\n";

  print "<script Language=\"Javascript\">\n";
  print "//<!-- Start Script\n";

  print "function change_helpwin(helpurl,swidth,sheight,windowname) {\n";
  print "  SmallWin = window.open(helpurl, windowname,'scrollbars=yes,resizable=yes,status=yes,toolbar=yes,menubar=yes,height='+sheight+',width='+swidth);\n";
  print "}\n";

  print "function closewin() {\n";
  print "  self.close();\n";
  print "}\n";

  print "//-->\n";
  print "</script>\n";

  print "</head>\n";

  print "<body bgcolor=\"#ffffff\">\n";

  print "<table width=\"760\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\" id=\"header\">\n";
  print "  <tr>\n";
  print "    <td colspan=\"3\" align=\"left\">";
  if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
    print "<img src=\"/images/global_header_gfx.gif\" width=\"760\" alt=\"Plug 'n Pay Technologies - we make selling simple.\" height=\"44\" border=\"0\">";
  }
  else {
    print "<img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Logo\">";
  }
  print "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"3\" align=\"left\"><img src=\"/css/header_bottom_bar_gfx.gif\" width=\"760\" height=\"14\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table border=\"0\" cellspacing=\"0\" cellpadding=\"5\" width=\"760\">\n";
  print "  <tr>\n";
  print "    <td colspan=\"2\"><h1><a href=\"$ENV{'SCRIPT_NAME'}\">FraudTrak2 Administration</a> - $company</h1>\n";

  print "<div align=center>\n";
  print "<font size=\"+1\">$message</font>\n";
  print "</div>\n";

  my @now = gmtime(time);
  my $copy_year = $now[5]+1900;

  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table width=\"760\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\" id=\"footer\">\n";
  print "  <tr>\n";
  print "    <td align=\"left\"><p><a href=\"/admin/logout.cgi\" title=\"Click to log out\">Log Out</a> | <a href=\"javascript:change_helpwin('/admin/helpdesk.cgi',600,500,'ahelpdesk')\">Help Desk</a> | <a id=\"close\" href=\"javascript:closewin();\" title=\"Click to close this window\">Close Window</a></p></td>\n";
  print "    <td align=\"right\"><p>\&copy; $copy_year, ";
  if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
    print "Plug and Pay Technologies, Inc.";
  }
  else {
    print "$ENV{'SERVER_NAME'}";
  }
  print "</p></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</body>\n";
  print "</html>\n";

  return;
}

1;
