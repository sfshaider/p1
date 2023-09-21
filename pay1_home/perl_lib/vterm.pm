package vterm;

local $|=0;

use miscutils;
use CGI;
use SHA;
use smpsutils;
use strict;
use constants qw(%countries %USstates %USterritories %CNprovinces %USCNprov %timezones);
use PlugNPay::CardData;
use PlugNPay::Logging::DataLog;
use PlugNPay::Features;
use PlugNPay::Processor::Account;
use PlugNPay::GatewayAccount;

sub new {
  my $type = shift;

  $vterm::query = new CGI;

  $vterm::username = "";
  $vterm::function = "";
  $vterm::format = "";
  $vterm::merchant = "";
  $vterm::debug_string = "";

  $vterm::merchantid  = "";
  $vterm::processor = "";
  $vterm::proc_type = "";
  $vterm::company = "";
  $vterm::currency = "";
  $vterm::reseller = "";
  $vterm::chkprocessor = "";
  $vterm::allow_overview = "";
  $vterm::walletprocessor = "";
  $vterm::seccodes = "";

  %vterm::cookie = ();
  %vterm::cookie_out = ();

  my $feature_string = "";
  %vterm::feature = ();

  $vterm::lasttrantime = "";

  $vterm::achstatus = "";

  @vterm::months = ("01","02","03","04","05","06","07","08","09","10","11","12");
  @vterm::allowed_sec_codes = ('CCD','PPD','TEL','WEB');

  $vterm::path_cgi = "smps.cgi";
  $vterm::path_vtcgi = "smps.cgi";
  $vterm::path_testcgi = "https://pay1.plugnpay.com/payment/inputtest.cgi";
  $vterm::vt_cgi = "virtualterm.cgi";


  $vterm::username = $ENV{'REMOTE_USER'};

  if (($ENV{'SEC_LEVEL'} eq "") && ($ENV{'REDIRECT_SEC_LEVEL'} ne "")) {
    $ENV{'SEC_LEVEL'} = $ENV{'REDIRECT_SEC_LEVEL'};
  }

  if (($ENV{'LOGIN'} eq "") && ($ENV{'REDIRECT_LOGIN'} ne "")) {
    $ENV{'LOGIN'} = $ENV{'REDIRECT_LOGIN'};
  }

  if (($ENV{'HTTP_COOKIE'} ne "")){
    my (@cookies) = split('\;',$ENV{'HTTP_COOKIE'});
    foreach my $var (@cookies) {
      my ($name,$value) = split('=',$var);
      $name =~ s/ //g;
      $vterm::cookie{$name} = $value;
    }
  }
  if (exists $vterm::cookie{'cardinput_settings'}) {
    $vterm::cookie{'cardinput_settings'} =~ s/\%7C/\|/gi;
  }
  $vterm::function = &CGI::escapeHTML($vterm::query->param('function'));
  $vterm::function =~ s/[^0-9a-zA-Z\_\ ]//g;

  $vterm::accttype = &CGI::escapeHTML($vterm::query->param('accttype'));
  $vterm::accttype =~ s/[^0-9a-zA-Z\-\_]//g;
  if ($vterm::accttype eq "") {
    $vterm::accttype = "credit";
  }

  #$vterm::acct_code = &CGI::escapeHTML($vterm::query->param('acct_code'));

  $vterm::merchant = &CGI::escapeHTML($vterm::query->param('merchant'));
  $vterm::merchant =~ s/[^0-9a-zA-Z]//g;


  if (($vterm::merchant ne "") && ($ENV{'SCRIPT_NAME'} =~ /payment/)) {
    $vterm::username = $vterm::merchant;
    $vterm::path_cgi = "/payment/auth.cgi";
    $vterm::path_vtcgi = "/payment/auth.cgi";
  }

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time);
  my $filemon = sprintf("%02d",$mon+1);
  my ($weekno);
  if ($mday < 8) {
    $weekno = "01";
  }
  elsif (($mday >= 8) && ($mday < 15)) {
    $weekno = "02";
  }
  elsif (($mday >= 15) && ($mday < 22)) {
    $weekno = "03";
  }
  else {
    $weekno = "04";
  }

  $vterm::current_year = $year + 1900;
  $vterm::current_month = "$filemon";
  $vterm::path_remotedebug = "/home/p/pay1/database/remotepm_debug$weekno$filemon\.txt";

  %vterm::altaccts = ('icommerceg',["icommerceg","icgoceanba","icgcrossco"]);

  my $dbh = &miscutils::dbhconnect("pnpmisc");

  if (($vterm::merchant ne "") && ($ENV{'SCRIPT_NAME'} =~ /overview/)) {
    my $sth = $dbh->prepare(qq{
        select overview
        from salesforce
        where username=?
      }) or die "Can't do: $DBI::errstr";
    $sth->execute("$ENV{'REMOTE_USER'}") or die "Can't execute: $DBI::errstr";
    ($vterm::allow_overview) = $sth->fetchrow;
    $sth->finish;
  }

  if (($ENV{'REMOTE_USER'} =~ /^(northame|stkittsn|cableand|officetr|smart2pa|planetpa|cccc)$/) || ($vterm::allow_overview == 1)) {
    if ($vterm::merchant eq "ALL") {
      my @merchlist = &merchlist($ENV{'REMOTE_USER'});
      %vterm::altaccts = ($ENV{'REMOTE_USER'},[@merchlist]);
    }
    else {
      $vterm::username = &overview($ENV{'REMOTE_USER'},$vterm::merchant);
      $ENV{'REMOTE_USER'} = $vterm::username;
      $ENV{'SEC_LEVEL'} = 10;
      if ($vterm::merchant =~ /icommerceg/) {
        $vterm::subacct = &CGI::escapeHTML($vterm::query->param('subacct'));
        if (($ENV{'SUBACCT'} eq "") && ($vterm::subacct ne "")) {
          $ENV{'SUBACCT'} = $vterm::subacct;
        }
      }
    }
  }
  elsif (($vterm::merchant =~ /^(motisllc|motisllc2|motisllc3|motisllc4|motisllc5|motisminit|motismini2|motisredwo|motisteenh|motiswoodf|motishumb|motiscards|motisdrkin|motisdrkin1|pctis)/) && ($ENV{'REMOTE_USER'} =~ /^motis$/)) {
    $vterm::username = $vterm::merchant;
    $ENV{'REMOTE_USER'} = $vterm::merchant
  }
  elsif (($vterm::merchant =~ /^(concierges)/) && ($ENV{'REMOTE_USER'} eq "concierges")) {
    $vterm::username = $vterm::merchant;
    $ENV{'REMOTE_USER'} = $vterm::merchant;
  }
  elsif (($vterm::merchant =~ /^(golinte1|golinte2|golinte3|golinte4|golinte5|golinte6|pocketbr|homeclip|igormaniai|igormaniai1)$/) && ($ENV{'REMOTE_USER'} =~ /^golinte1$/)) {
    $vterm::username = $vterm::merchant;
    $ENV{'REMOTE_USER'} = $vterm::merchant
  }

  if ($ENV{'REMOTE_USER'} =~ /^(ipayfideli|ipacsuppor)$/) {
    $vterm::allowed_functions =~ s/cardinput\|//g;
  }

  %vterm::cardarray = ('vs','Visa','mc','MasterCard','ax','American Express','ds','Discover','vsmc','VISA/MC Combined','jc','JCB','kc','KeyCard','ach','ACH','sw','Solo','ma','Maestro');
  %vterm::transtype = ('auth','Authorization','ret','Return','return','Return');

  # DWW added to make javascript alerts more useful
  %vterm::fieldnames = ("card_name","Name","card_address1","Address","card_address2","Address2","card_city","City","card_state","State","card_zip","Zip","card_prov",
                        "International Province","card_country","Country","email","Email","card_number","Credit Card Number","card_cvv","CVV","card_amount",
                        "Amount","orderID","Order ID","acct_code","Acct Code");

  $vterm::time = gmtime(time);

  my $ga = new PlugNPay::GatewayAccount($vterm::username);

  # get processor info
  my $cardProcessor = $ga->getCardProcessor();
  $vterm::processor = $cardProcessor;
  eval {
    my $cardProcessorAccount = new PlugNPay::Processor::Account({ gatewayAccount => $ga, processorName => $cardProcessor });
    $vterm::merchantid = $cardProcessorAccount->getSettingValue('mid');
    $vterm::proc_type = $cardProcessorAccount->getSettingValue('authType');
    $vterm::currency = $cardProcessorAccount->getSettingValue('currency');
    $vterm::retailflag = $cardProcessorAccount->getIndustry();
  };

  if ($@) {
    new PlugNPay::Logging::DataLog({'collection' => 'virtualterminal'})->log({
      'message'       => 'Failed to load card processor account settings',
      'username'      => $vterm::username,
      'cardProcessor' => $cardProcessor,
      'error'         => $@
    });
  }

  $vterm::company = $ga->getMainContact()->getCompany();
  $vterm::reseller = $ga->getReseller();
  $vterm::dccusername = $ga->getDCCAccount();
  $vterm::merchstrt = $ga->getStartDate();
  $vterm::status = $ga->getStatus();
  $vterm::walletprocessor = $ga->getWalletProcessor();
  $vterm::cancredit = $ga->canProcessCredits();
  $vterm::chkprocessor = $ga->getCheckProcessor();

  $vterm::timetest{'0a_postcustinfo'} = time();
  $vterm::dccusername =~ s/[^0-9a-zA-Z]//g;
  %vterm::feature = %{$ga->getFeatures()->getFeatures()};

  if ( ($vterm::merchant ne "") && ($ENV{'SCRIPT_NAME'} !~ /overview/) && ($vterm::feature{'linked_accts'} ne "") ) {
    &check_linked_acct($vterm::username,$vterm::merchant,$vterm::feature{'linked_accts'});
  }

  my $sthsetup = $dbh->prepare(qq{
      select autobatch
      from pnpsetups
      where username=?
    }) or die "Can't do: $DBI::errstr";
  $sthsetup->execute("$vterm::username") or die "Can't execute: $DBI::errstr";
  ($vterm::autobatch) = $sthsetup->fetchrow;
  $sthsetup->finish;


  if ($vterm::currency eq "") {
    $vterm::currency = "usd";
  }

  if ($vterm::chkprocessor eq "") {
    $vterm::chkprocessor = "ach";
  }

 if ($vterm::chkprocessor eq "testprocessor" || $vterm::chkprocessor eq "testprocessorach" ) {
    $vterm::achstatus = "enabled";
  } else {
    eval {
      my $achProcAcct = new PlugNPay::Processor::Account({
        'gatewayAccount' => $vterm::username,
        'processorName'  => $vterm::chkprocessor
      });

      $vterm::achstatus = $achProcAcct->getSettingValue('status');

      if ($vterm::chkprocessor =~ /^(paymentdata|globaletel)$/) {
        my $seccodes = $achProcAcct->getSettingValue('seccodes');
        if ($vterm::chkprocessor eq "paymentdata") {
          @vterm::allowed_sec_codes = split(/\,/,$seccodes);
        } elsif ($vterm::chkprocessor eq "globaletel") {
          my %seccodes = split(/\,/,$seccodes);
          @vterm::allowed_sec_codes = (keys %seccodes);
        }
      }
    };

    if ($@) {
      new PlugNPay::Logging::DataLog({'collection' => 'virtualterminal'})->log({
        'message'      => 'Failed to load ach processor account settings',
        'username'     => $vterm::username,
        'achProcessor' => $vterm::chkprocessor,
        'error'        => $@
      });
    }
  }

  ## DCP - 20050908 per request of RB/JNCB
  if (($vterm::processor eq 'ncb') && ($vterm::allow_overview != 1)) {
    if ($vterm::username =~ /^(oceanicdig)/) {
      $vterm::allowed_functions = "cardquery|cardinput|assemblebatch|querybatch";
    }
    else {
      $vterm::allowed_functions = "cardquery|cardinput";
    }
  }

  $dbh->disconnect;

  if (($vterm::feature{'adminipcheck'} == 1) && ($ENV{'REMOTE_USER'} ne $ENV{'LOGIN'})) {
    my %security = &security_check($vterm::username,$ENV{'REMOTE_ADDR'});
    if ($security{'flag'} != 1) {
      &response_page($security{'MErrMsg'});
    }
  }

  if ($vterm::processor =~ /^(nova|paytechtampa|paytechtampaemv|paytechtampaiso|fdms|fdmsemv|fdmsintl|fdmsnorth|fdmsomaha|fdmsrc|visanet|visanetemv|global|globalc|globalctf|buypass|maverick|testprocessor)$/) {
    $vterm::purchasecardsdiv = 1;
  }
  else {
    $vterm::purchasecardsdiv = 0;
  }

  if ($vterm::achstatus eq "enabled") {
    $vterm::checkdiv = 1;
  }
  else {
    $vterm::checkdiv = 0;
  }

  if ($vterm::walletprocessor =~ /feed/) {
    $vterm::feeddiv = 1;
  }
  else {
    $vterm::feeddiv = 0;
  }

  if (-e "/home/p/pay1/web/payment/recurring/$vterm::username") {
    $vterm::billmemdiv = 1;
  }
  else {
    $vterm::billmemdiv = 0;
  }

  return [], $type;
}

sub cardinput {
  my ($date,$dummy2) = &miscutils::gendatetime_only();
  my $current_month = substr($date,4,2);
  my $current_year = substr($date,0,4);
  if ($payutils::query{'month-exp'} eq "") {
    $payutils::query{'month-exp'} = $current_month;
  }

  #begin header

  if ($vterm::accttype eq "credit") {
    print "<div id=\"creditswipe\" style=\"display:block\">\n";
    print "  <table class=\"frame\">\n";
    print "  <tr>\n";
    print "         <td><h1>Virtual Terminal - $vterm::company</h1></td>\n";
    if ($vterm::feature{'keyswipe'} ne "secure") {
      print "      <td align=\"right\"><input type=\"button\" value=\"Swipe Credit Card\" onclick=\"creditswipewindow();\"></td>\n";
    }
    print "  </tr>\n";
    print "  </table>\n";
    print "</div>\n";
    print "\n";
  }
  elsif ($vterm::accttype eq "check") {
    print "<div id=\"checkswipe\" style=\"display:block\">\n";
    print "<table class=\"frame\">\n";
    print "  <tr>\n";
    print "    <td><h1>Virtual Terminal - $vterm::company</h1></td>\n";
    if ($vterm::feature{'keyswipe'} ne "secure") {
      print "    <td align=\"right\"><input type=\"button\" value=\"Swipe Credit Card\" disabled></td>\n";
    }
    print "  </tr>\n";
    print "</table>\n";
    print "</div>\n";
  }
  elsif ($vterm::accttype eq "purchase") {
    print "<div id=\"purchaseswipe\" style=\"display:block\">\n";
    print "<table class=\"frame\">\n";
    print "  <tr>\n";
    print "    <td><h1>Virtual Terminal - $vterm::company</h1></td>\n";
    if ($vterm::feature{'keyswipe'} ne "secure") {
      print "    <td align=\"right\"><input type=\"button\" value=\"Swipe Credit Card\" onclick=\"purchaseswipewindow();\"></td>\n";
    }
    print "  </tr>\n";
    print "</table>\n";
    print "</div>\n";
  }
  elsif ($vterm::accttype eq "feed") {
    print "<div id=\"feedswipe\" style=\"display:block\">\n";
    print "<table class=\"frame\">\n";
    print "  <tr>\n";
    print "    <td><h1>Virtual Terminal - $vterm::company</h1></td>\n";
    if ($vterm::feature{'keyswipe'} ne "secure") {
      print "    <td align=\"right\"><input type=\"button\" value=\"Swipe Credit Card\" disabled></td>\n";
    }
    print "  </tr>\n";
    print "</table>\n";
    print "</div>\n";
  }
  elsif ($vterm::accttype eq "billmem") {
    print "<div id=\"billmemswipe\" style=\"display:block\">\n";
    print "<table class=\"frame\">\n";
    print "  <tr>\n";
    print "    <td><h1>Virtual Terminal - $vterm::company</h1></td>\n";
    if ($vterm::feature{'keyswipe'} ne "secure") {
      print "    <td align=\"right\"><input type=\"button\" value=\"Swipe Credit Card\" onclick=\"billmemswipewindow();\"></td>\n";
    }
    print "  </tr>\n";
    print "</table>\n";
    print "</div>\n";
  }

  print "<hr id=\"under\">\n";
  print "\n";

  #end header
  #begin radio options for payment types

  print "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
  print "<input type=\"hidden\" name=\"merchant\" value=\"$vterm::merchant\">\n";

  my %selected;
  $selected{"$vterm::accttype"} = "checked";

  print "<div class=\"form\">\n";
  print "<table class=\"form\" style=\"margin-left:0px\">\n";
  print "  <tr>\n";
  print "    <th class=\"label\">Select Payment Type:</th>\n";
  print "    <td><input type=\"radio\" name=\"accttype\" id=\"r1\" value=\"credit\" $selected{'credit'} onclick=\"is_loading('true');this.form.submit();\">Charge</td>\n";
  if ($vterm::checkdiv == 1) {
    print "    <td><input type=\"radio\" name=\"accttype\" id=\"r2\" value=\"check\" $selected{'check'} onclick=\"is_loading('true');this.form.submit();\">Check</td>\n";
  }
  if ($vterm::purchasecardsdiv == 1) {
    print "    <td><input type=\"radio\" name=\"accttype\" id=\"r3\" value=\"purchase\" $selected{'purchase'} onclick=\"is_loading('true');this.form.submit();\">Purchase Cards</td>\n";
  }
  if ($vterm::feeddiv == 1) {
    print "    <td><input type=\"radio\" name=\"accttype\" id=\"r4\" value=\"feed\" $selected{'feed'} onclick=\"is_loading('true');this.form.submit();\">Mocapay</td>\n";
  }
  if ($vterm::billmemdiv == 1) {
    print "    <td><input type=\"radio\" name=\"accttype\" id=\"r5\" value=\"billmem\" $selected{'billmem'} onclick=\"is_loading('true');this.form.submit();\">Bill/Credit Member</td>\n";
  }
  print "  </tr>\n";
  print "</table>\n";
  print "</div>\n";

  print "<div id=\"loadingStatement\" style=\"margin-left:125px;visibility:hidden\"><font color=\"#ff0000\" size=\"-1\"><b>Loading Form For Payment Type Selected, Please Wait</b></font></div>\n";

  print "</form>\n";
  #end radio

  #begin charge form
  if ($vterm::accttype eq "credit") {
    print "<div id=\"chargediv\" class=\"form\" style=\"display:block\">\n";

    print "<form method=\"post\" action=\"$vterm::path_vtcgi\" name=\"pay\" onSubmit=\"return valForm(this) && isCreditCard(document.pay.card_number.value) && disableForm(this) && checkMagstripe(event) \">\n";
    #print "<form method=\"post\" action=\"$vterm::path_testcgi\" name=\"pay\" onsubmit=\"return disableForm(this);\">\n";

    print "<input type=\"hidden\" name=\"accttype\" value=\"credit\">\n";
    &hiddenfields();

    &address_info('credit');

    print "<!-- begin payment info table -->\n";
    print "<table border=1>\n";
    print "  <tr>\n";
    print "    <th class=\"label\">Payment Information:</th>\n";
    print "  </tr>\n";

    &creditcard_info();

    if ($vterm::processor =~ /^(pago|barclays)$/) {
      print "  <tr>\n";
      print "    <th>Card Issue #:</th>\n";
      print "    <td><input type=\"text\" name=\"cardissuenum\" value=\"\" size=16 max=20 autocomplete=\"off\"> (Switch/Solo Cards Only)</td>\n";
      print "  </tr>\n";
      print "  <tr>\n";
      print "    <th>Card Start Date:</th>\n";
      print "    <td><input type=\"text\" name=\"cardstartdate\" value=\"\" size=16 max=20 autocomplete=\"off\"> (Switch/Solo Cards Only)</td>\n";
      print "  </tr>\n";
    }
    if (($vterm::processor eq "mercury") && ($vterm::feature{'acceptgift'} == 1)) {
      print "  <tr>\n";
      print "    <th>Gift Card #:</th>\n";
      print "    <td><input type=\"text\" name=\"mpgiftcard\" value=\"\" size=20 max=20 autocomplete=\"off\">  Sec. Code: <input type=\"text\" name=\"mpcvv\" value=\"\" size=4 max=4 autocomplete=\"off\"></td>\n";
      print "  </tr>\n";
    }

    &amount_info();

    print "  <tr>\n";
    print "    <th>Type:</th>\n";
    print "    <td><select name=\"mode\" class=\"formfields\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\">\n";

    if ($vterm::proc_type ne "returnonly") {
      print "<option value=\"auth\"> Authorize</option>\n";
    }

    if ($ENV{'SEC_LEVEL'} < 8) {
      if (($vterm::cancredit) && ($ENV{'SCRIPT_NAME'} !~ /payment/)) {
        print "<option value=\"newreturn\"> Return</option>\n";
      }
    }

    if (($vterm::processor =~ /^(nova|paytechtampa|fdms|visanet|global|buypass|maverick|fdmsomaha|fifththird|fdmsnorth)$/) && ($vterm::proc_type ne "returnonly")) {
      print "<option value=\"forceauth\"> Force Auth</option>\n";
    }

    print "</select></td>\n";
    print "  </tr>\n";

    if (($vterm::processor =~ /^(nova|paytechtampa|fdms|visanet|global|buypass|maverick)$/) && ($vterm::proc_type ne "returnonly") && ($ENV{'SCRIPT_NAME'} !~ /payment/)) {
      print "  <tr>\n";
      print "    <th>Authorization Code:</th>\n";
      print "    <td><input name=\"auth-code\" type=\"text\" class=\"thin\" value=\"\" maxlength=\"10\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\"> *force auths</td>\n";
      print "  </tr>\n";
    }

    &misc_stuff();
    &settings_label();

    if ($vterm::retailflag eq 'retail') {
      my (%selected);
      if ($vterm::reseller =~ /^(dodsonin)$/) {
        $selected{'retailflag'} = "";
      }
      else {
        $selected{'retailflag'} = "checked";
      }
      print "  <tr>\n";
      print "    <th>Retail Flag:</th>\n";
      print "    <td><input type=\"checkbox\" name=\"retailflag\" value=\"yes\" $selected{'retailflag'}> Check to mark transaction as keyed retail.</td>\n";
      print "  </tr>\n";
    }

    if ($vterm::proc_type !~ /authcapture/) {
      print "  <tr>\n";
      print "    <th>Auth Type:</th>\n";
      print "    <td><input type=\"checkbox\" name=\"authtype\" value=\"authpostauth\"> Check to mark transaction for settlement.</td>\n";
      print "  </tr>\n";
    }

    if (($vterm::reseller !~ /^(cynergy|electro)$/) && ($vterm::feature{'hidefrdbuypass'} != 1) && ($ENV{'SCRIPT_NAME'} !~ /payment/)) {
      print "  <tr>\n";
      print "    <th>CVV/CVC Bypass:</th>\n";
      print "    <td><input type=\"checkbox\" name=\"cvv_ign\" value=\"yes\"> Check to ignore CVV/CVC response.</td>\n";
      print "  </tr>\n";
    }

    if (($vterm::reseller !~ /^(cynergy|electro)$/) && ($vterm::feature{'hidefrdbuypass'} != 1) && ($ENV{'SCRIPT_NAME'} !~ /payment/)) {
      print "  <tr>\n";
      print "    <th>Fraud Bypass:</th>\n";
      print "    <td colspan=\"3\"><input type=\"checkbox\" name=\"fraudbuypass\" value=\"yes\" checked> Check to bypass AVS/fraud screening</td>\n";
      print "  </tr>\n";
    }

    if ($vterm::dccusername ne "") {
      print "  <tr>\n";
      print "    <th>DCC:</th>\n";
      print "    <td><input type=\"checkbox\" name=\"client\" value=\"planetpay\"> Check to settle in cardholder's native currency if applicable.</td>\n";
      print "  </tr>\n";
    }

    if ($vterm::processor eq "pago") {
      print "  <tr>\n";
      print "    <th>Payment Request Flag:</th>\n";
      print "    <td><input type=\"checkbox\" name=\"creditrequestflag\" value=\"1\"> Check to flag transaction as Payment Transfer. Only available for VISA cards.</td>\n";
      print "  </tr>\n";
    }

    if ($vterm::processor eq "cayman") {
      print "  <tr>\n";
      print "    <th>AVS Only Flag:</th>\n";
      print "    <td><input type=\"checkbox\" name=\"transflags\" value=\"avsonl\"> Check to flag transaction as AVS Only</td>\n";
      print "  </tr>\n";
    }
    elsif (($vterm::processor =~ /^(visanet|visanetemv)$/) && ($vterm::feature{'display_debt_indicator'} == 1)) {
      print "  <tr>\n";
      print "    <th>Visa Debt Indicator:</th>\n";
      print "    <td><input type=\"checkbox\" name=\"transflags\" value=\"debt\" checked> Check to set Visa Debt Indicator</td>\n";
      print "  </tr>\n";
    }

    &misc_stuff2();
    &submitform();

    print "</table>\n";
    print "</form>\n";
    print "</div>\n";
  }
  #end charge form

  #begin check form
  if ($vterm::accttype eq "check") {
    if ($vterm::checkdiv == 1) {
      print "<div id=\"checkdiv\" style=\"display:block\" class=\"form\">\n";
      print "<form method=\"post\" action=\"$vterm::path_vtcgi\" name=\"check\" onsubmit=\"return valForm(this);\">\n";
      #print "<form method=\"post\" action=\"$vterm::path_testcgi\" name=\"pay\" onsubmit=\"return disableForm(this);\">\n";

      &hiddenfields();
      &address_info('ach');

      print "<table>\n";
      print "  <tr>\n";
      print "    <th class=\"label\">Payment Information:</th>\n";
      print "  </tr>\n";
      print "  <tr>\n";
      print "    <th>Routing Number:</th>\n";
      print "    <td><input name=\"routingnum\" type=\"text\" class=\"thin\" value=\"\" maxlength=\"50\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\" id=\"routingnum\" onKeyPress=\"return noautosubmit(event);\" autocomplete=\"off\"></td>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <th>Account Number:</th>\n";
      print "    <td><input name=\"accountnum\" type=\"text\" class=\"thin\" value=\"\" maxlength=\"20\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\" autocomplete=\"off\"></td>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <th>Account Type:</th>\n";
      print "    <td><input type=\"radio\" name=\"accttype\" value=\"checking\" checked> Checking &nbsp; <input type=\"radio\" name=\"accttype\" value=\"savings\"> Savings </td>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <th>Check Number:</th>\n";
      print "    <td><input name=\"checknum\" type=\"text\" class=\"thin\" value=\"\" maxlength=\"20\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\" autocomplete=\"off\"></td>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <th>Type:</th>\n";
      print "    <td><select name=\"mode\" class=\"formfields\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\">\n";
      if ($vterm::proc_type ne "returnonly") {
        print "<option value=\"auth\"> Authorize</option>\n";
      }

      if ($ENV{'SEC_LEVEL'} < 8) {
        if ($vterm::cancredit) {
          print "<option value=\"newreturn\"> Return</option>\n";
        }
      }

      print "</select></td>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <th>Sec. Code:</th>\n";
      print "    <td><select name=\"checktype\" class=\"formfields\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\">\n";

      foreach my $var (@vterm::allowed_sec_codes) {
        print "<option value=\"$var\"> $var</option>\n";
      }

      print "</select></td>\n";
      print "  </tr>\n";

      if ($vterm::chkprocessor =~ /^(alliancesp|echo|paymentdata|testprocessor|testprocessorach|globaletel|gms)$/) {
        print "  <tr>\n";
        print "    <th>Phone:</th>\n";
        print "    <td><input type=text size=\"20\" name=\"phone\" class=\"thin\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\"> (required for WEB checks)</td>\n";
        print "  </tr>\n";
      }
      print "</table>\n";

      print "<table>\n";

      &amount_info();
      &misc_stuff();
      &settings_label();
      &misc_stuff2();
      &submitform();

      print "</table>\n";
      print "</form>\n";
      print "</div>\n";
    }
    else  {
      print "<div id=\"checkdiv\" style=\"display:block\"></div>\n";
    }
  }
  #end check form

  #begin purchase card form
  if ($vterm::accttype eq "purchase") {
    if ($vterm::purchasecardsdiv == 1) {
      print "<div id=\"purchasecardsdiv\" class=\"form\" style=\"display:block\">\n";
      print "<form method=\"post\" action=\"$vterm::path_vtcgi\" name=\"purch\" onsubmit=\"return disableForm(this);\">\n";
      #print "<form method=\"post\" action=\"$vterm::path_testcgi\" name=\"pay\" onsubmit=\"return disableForm(this);\">\n";
      print "<input type=\"hidden\" name=\"accttype\" value=\"credit\">\n";

      &hiddenfields();
      &address_info('credit');

      print "<table>\n";
      print "  <tr>\n";
      print "    <th class=\"label\">Payment Information:</th>\n";
      print "  </tr>\n";

      &creditcard_info();

      print "  <tr>\n";
      print "    <th><input type=\"hidden\" name=\"commcardtype\" value=\"purchase\">Invoice No:</th>\n";
      print "    <td><input type=\"text\" name=\"ponumber\" class=\"thin\" value=\"\" maxlength=\"17\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\"></td>\n";
      print "  </tr>\n";
      print "  <tr>\n";
      print "    <th>Tax:</th>\n";
      print "    <td><input type=\"text\" name=\"tax\" class=\"thin\" value=\"\" maxlength=\"17\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\"></td>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <th>Ship To Zip:</th>\n";
      print "    <td><input type=\"text\" name=\"zip\" class=\"thin\" value=\"\" maxlength=\"17\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\"></td>\n";
      print "  </tr>\n";

      if ($vterm::feature{'amexlev2'} == 1) {
        print "<tr class=\"amexlev2\"><td align=\"right\" class=\"$payutils::color{'employeename'}\"><span>Employee Name\:<b>*</b></span></td>";
        print "<td align=\"left\"><input type=\"text\" name=\"employeename\" value=\"$payutils::query{'employeename'}\" size=30 maxlength=39\"></td></tr>\n";

        print "<tr class=\"amexlev2\"><td align=\"right\" class=\"$payutils::color{'costcenternum'}\"><span>Cost Center Number\:<b>*</b></span></td>";
        print "<td align=\"left\"><input type=\"text\" name=\"costcenternum\" value=\"$payutils::query{'costcenternum'}\" size=20 maxlength=20\"></td></tr>\n";
      }

      #if (($vterm::reseller !~ /^(cynergy|electro)$/) && ($vterm::feature{'hidefrdbuypass'} != 1)) {
      #  print "  <tr>\n";
      #  print "    <th>CVV/CVC Bypass:</th>\n";
      #  print "    <td><input type=\"checkbox\" name=\"cvv_ign\" value=\"yes\"> Check to ignore CVV/CVC response.</td>\n";
      #  print "  </tr>\n";
      #}
      print "  <tr>\n";
      print "    <th>Type:</th>\n";
      print "    <td><select name=\"mode\" class=\"formfields\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\">\n";
      if ($vterm::proc_type ne "returnonly") {
        print "<option value=\"auth\"> Authorize</option>\n";
      }

      if ($ENV{'SEC_LEVEL'} < 8) {
        if ($vterm::cancredit) {
          print "<option value=\"newreturn\"> Return</option>\n";
        }
      }

      if (($vterm::processor =~ /^(nova|paytechtampa|fdms|visanet|global|buypass|maverick)$/) && ($vterm::proc_type ne "returnonly")) {
        print "<option value=\"forceauth\"> Force Auth</option>\n";
      }
      print "</select></td>\n";
      print "  </tr>\n";
      print "</table>\n";

      print "<table>\n";

      &amount_info();
      &misc_stuff();
      &settings_label();

      if ($vterm::proc_type !~ /authcapture/) {
        print "  <tr>\n";
        print "    <th>Auth Type:</th>\n";
        print "    <td><input type=\"checkbox\" name=\"authtype\" value=\"authpostauth\"> Check to mark transaction for settlement.</td>\n";
        print "  </tr>\n";
      }

      if (($vterm::reseller !~ /^(cynergy|electro)$/) && ($vterm::feature{'hidefrdbuypass'} != 1)) {
        print "  <tr>\n";
        print "    <th>CVV/CVC Bypass:</th>\n";
        print "    <td><input type=\"checkbox\" name=\"cvv_ign\" value=\"yes\"> Check to ignore CVV/CVC response.</td>\n";
        print "  </tr>\n";
      }

      &misc_stuff2();
      &submitform();

      print "</table>\n";
      print "</form>\n";
      print "</div>\n";
    }
    else {
      print "<div id=\"purchasecardsdiv\" style=\"display:block\"></div>\n";
    }
  }
  #end purchase card form

  #begin feed form
  if ($vterm::accttype eq "feed") {
    if ($vterm::feeddiv == 1) {
      print "<div id=\"feeddiv\" class=\"form\" style=\"display:block\">\n";
      print "<form method=\"post\" action=\"$vterm::path_vtcgi\" name=\"feed\" onsubmit=\"return disableForm(this);\">\n";
      #print "<form method=\"post\" action=\"$vterm::path_testcgi\" name=\"pay\" onsubmit=\"return disableForm(this);\">\n";

      &hiddenfields();
      &address_info('credit');

      print "<table>\n";
      print "  <tr>\n";
      print "    <th class=\"label\">Payment Information:</th>\n";
      print "  </tr>\n";
      print "  <tr>\n";
      print "    <th>Credit Card Number:</th>\n";
      print "    <td><input name=\"card_number\" type=\"text\" class=\"thin\" value=\"\" maxlength=\"20\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\" autocomplete=\"off\">\n";
      print "<input type=\"hidden\" name=\"fraudbuypass\" value=\"yes\" checked>\n";
      print "<input type=\"hidden\" name=\"mode\" value=\"auth\"></td>\n";
      print "  </tr>\n";
      print "</table>\n";

      print "<table>\n";

      &amount_info();
      &misc_stuff();
      &settings_label();
      &misc_stuff2();
      &submitform();

      print "</table>\n";
      print "</form>\n";
      print "</div>\n";
    }
    else {
      print "<div id=\"feeddiv\" style=\"display:block\"></div>\n";
    }
  }
  #end feed form

  #begin bill form
  if ($vterm::accttype eq "billmem") {
    if ($vterm::billmemdiv == 1) {
      print "<div id=\"billmemdiv\" class=\"form\" style=\"display:block\">\n";
      print "<form method=\"post\" action=\"$vterm::path_vtcgi\" name=\"bill\" onsubmit=\"return disableForm(this);\">\n";
      #print "<form method=\"post\" action=\"$vterm::path_testcgi\" name=\"pay\" onsubmit=\"return disableForm(this);\">\n";

      &hiddenfields();

      print "<table style=\"margin-top:20px\">\n";
      print "  <tr>\n";
      print "    <th>Username: </th>\n";
      print "    <td><select name=\"username\" class=\"thin\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\" onchange=\"displayCC();\">\n";
      print "<option value=\"\">Select Customer</option>\n";

      my (%cardnumber);
      if (my $droplist eq "activeonly") {
        foreach my $key (sort keys my %name) {
          if ($vterm::feature{'vterm_display_username'} == 1) {
            print "<option value=\"$key\">$key - $name{$key}</option>\n";
          }
          else {
            print "<option value=\"$key\">$name{$key}</option>\n";
          }
        }
      }
      else {

        my $qstr = "select username,name,status,cardnumber,exp,accttype,enccardnumber,length,phone";
        $qstr .= " from customer";
        if ($vterm::feature{'vterm_display_usernames'} == 1) {
          $qstr .= " order by username";
        }
        else {
          $qstr .= " order by name,username";
        }

        my ($username,$name,$status,$cardnumber,$exp,$accttype,$enccardnumber,$length,$routingnum,$accountnum,$phone);

        my $dbh = &miscutils::dbhconnect("$vterm::username");
        my $sth = $dbh->prepare(qq{ $qstr }) or die "Can't do: $DBI::errstr";
          $sth->execute() or die "Can't execute: $DBI::errstr";
          $sth->bind_columns(undef,\($username,$name,$status,$cardnumber,$exp,$accttype,$enccardnumber,$length,$phone));
          while($sth->fetch) {
            my $cd = new PlugNPay::CardData();
            my $ecrypted_card_data = '';
            eval {
              $ecrypted_card_data = $cd->getRecurringCardData({customer => "$username", username => "$vterm::username", suppressAlert => 1});
            };
            if (!$@) {
              $enccardnumber = $ecrypted_card_data;
            }

            if ($vterm::chkprocessor ne "") {
              if ($enccardnumber ne "")  {
                my $cc = &rsautils::rsa_decrypt_file($enccardnumber,$length,"print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");
                if ($cc =~ /^(\d{9}) (\d+)/) {
                  $accttype = "checking";
                  $routingnum = $1;
                  $accountnum = $2;
                  my $mod10 = &miscutils::mod10($routingnum);
                  if ($mod10 ne "success") {
                    $accountnum = "";
                    $routingnum = "";
                    $accttype = "";
                  }
                  $routingnum = substr($routingnum,0,4) . "**" . substr($routingnum,-2);
                  $accountnum = substr($accountnum,0,4) . "**" . substr($accountnum,-2);
                  $cardnumber = "$routingnum:$accountnum:$phone";
                }
                else {
                  my $luhntest = &miscutils::luhn10($cc);
                  if ($luhntest ne "success") {
                    $cardnumber = "INVALID CC\# ON FILE";
                  }
                }
              }
              else {
                $cardnumber = "NO CARD ON FILE";
              }
            }
            $exp =~ s/\//\|/;
            if ($name eq "") {
              print "<option value=\"$username\">[username: $username]</option>\n";
            }
            else {
              if ($vterm::feature{'vterm_display_username'} == 1) {
                print "<option value=\"$username\">$username - $name</option>\n";
              }
              else {
                print "<option value=\"$username\">$name</option>\n";
              }
            }
            $cardnumber{"$username"} = "$cardnumber|$exp|$accttype";
          }
        $sth->finish;
        $dbh->disconnect;
      }
      print "</select></td>\n";
      print "  </tr>\n";

      my @array = %cardnumber;
      &displaycc(@array);

      print "  <tr>\n";
      print "    <th>Type:</th>\n";
      print "    <td><select name=\"mode\" class=\"formfields\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\">\n";
      if ($vterm::proc_type ne "returnonly") {
        print "<option value=\"bill_member\"> Bill Member</option>\n";
      }

      if (($ENV{'SEC_LEVEL'} < 8) && ($vterm::processor ne "village")) {
        if ($vterm::cancredit) {
          print "<option value=\"credit_member\"> Credit Member</option>\n";
        }
      }

      #if (($vterm::processor =~ /^(nova|paytechtampa|fdms|visanet|global|buypass|maverick)$/) && ($vterm::proc_type ne "returnonly")) {
      #  print "<option value=\"forceauth\"> Force Auth</option>\n";
      #}
      print "</select></td>\n";
      print "  </tr>\n";

      #print "<tr><td colspan=\"2\" align=\"center\"><em>Leave Credit Card fields below blank to use Credit Card number on record.</em></td></tr>\n";

      #&creditcard_info();
      #if ($vterm::chkprocessor ne "") {
      if ($vterm::achstatus eq "enabled") {
        print "  <tr>\n";
        print "    <th>Payment Method:</th>\n";
        print "    <td><input type=\"radio\" name=\"paymethod\" id=\"paymethodcredit\" value=\"credit\" checked onclick=\"javascript:bmcreditActive();\"> Charge \n";
        print "<input type=\"radio\" name=\"paymethod\" id=\"paymethodchecking\" value=\"checking\" onclick=\"javascript:bmcheckActive();\"> ACH</td>\n";
        print "   </tr>\n";
      }
      print "</table>\n";

      print "<div id=\"billmemccdiv\" style=\"display:block\" >\n";
      print "<table>\n";
      print "  <tr>\n";
      print "    <th class=\"label\">Payment Information:</th>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <th>Credit Card Number:</th>\n";
      print "    <td><input name=\"card_number\" id=\"card_number\" type=\"text\" class=\"thin\" value=\"\" maxlength=\"20\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\" autocomplete=\"off\">&nbsp;\n";
      if ($vterm::retailflag eq 'ecommerce') {
        print "CVV: <input name=\"card_cvv\" type=\"text\" style=\"width:40px\" value=\"\" maxlength=\"4\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\" autocomplete=\"off\">";
      }

      print "</td>\n";
      print "  </tr>\n";
      print "  <tr>\n";
      print "    <th>Expiration Date:</th>\n";
      print "    <td><select name=\"month_exp\" style=\"width:60px\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\" onchange=\"return Mod10(document.bill.card_number.value)\">\n";
      if ($vterm::query{'month-exp'} eq "") {
        $vterm::query{'month-exp'} = $vterm::current_month;
      }
      foreach my $var (@vterm::months) {
        if ($var eq $vterm::query{'month-exp'}) {
          print "<option value=\"$var\" selected>$var</option>\n";
        }
        else {
          print "<option value=\"$var\">$var</option>\n";
        }
      }
      print "</select>\n";
      print " <select name=\"year_exp\" style=\"width:60px\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\" onchange=\"return Mod10(document.bill.card_number.value)\">\n";
      if ($vterm::query{'year-exp'} eq ""){
        $vterm::query{'year-exp'} = $vterm::current_year;
      }
      for (my $i; $i<=12; $i++) {
        my $var = $vterm::current_year + $i;
        my $val = substr($var,2,2);
        if ($val eq $vterm::query{'year-exp'}) {
          print "<option value=\"$val\" selected>$var</option>\n";
        }
        else {
          print "<option value=\"$val\">$var</option>\n";
        }
      }
      print "</select><!-- * expiration date on file will be used by default--></td>\n";
      print "  </tr>\n";
      print "</table>\n";
      print "</div>\n";

      #if ($vterm::chkprocessor ne "") {
      if ($vterm::achstatus eq "enabled") {
        print "<div id=\"billmemachdiv\" style=\"display:none\" >\n";
        print "<table>\n";

        print "  <tr>\n";
        print "    <th class=\"label\">Payment Information:</th>\n";
        print "  </tr>\n";
        print "  <tr>\n";
        print "    <th>Routing Number:</th>\n";
        print "    <td><input name=\"routingnum\" type=\"text\" class=\"thin\" value=\"\" maxlength=\"20\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\" autocomplete=\"off\"></td>\n";
        print "  </tr>\n";

        print "  <tr>\n";
        print "    <th>Account Number:</th>\n";
        print "    <td><input name=\"accountnum\" type=\"text\" class=\"thin\" value=\"\" maxlength=\"20\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\" autocomplete=\"off\"></td>\n";
        print "  </tr>\n";

        print "  <tr>\n";
        print "    <th>Account Type:</th>\n";
        print "    <td><input type=\"radio\" name=\"accttype\" value=\"checking\" checked> Checking &nbsp; <input type=\"radio\" name=\"accttype\" value=\"savings\"> Savings</td>\n";
        print "  </tr>\n";

        print "  <tr>\n";
        print "    <th>Check Number:</th>\n";
        print "    <td><input name=\"checknum\" type=\"text\" class=\"thin\" value=\"\" maxlength=\"20\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\" autocomplete=\"off\"></td>\n";
        print "  </tr>\n";

        print "  <tr>\n";
        print "    <th>Type:</th>\n";
        print "    <td><select name=\"mode\" class=\"formfields\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\">\n";
        if ($vterm::proc_type ne "returnonly") {
          print "<option value=\"auth\"> Authorize</option>\n";
        }

        if ($ENV{'SEC_LEVEL'} < 8) {
          if ($vterm::cancredit) {
            print "<option value=\"newreturn\"> Return</option>\n";
          }
        }

        print "</select></td>\n";
        print "  </tr>\n";

        print "  <tr>\n";
        print "    <th>Sec. Code:</th>\n";
        print "    <td><select name=\"checktype\" class=\"formfields\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\">\n";
        print "<option value=\"CCD\"> CCD</option>\n";
        print "<option value=\"PPD\"> PPD</option>\n";
        print "<option value=\"TEL\"> TEL</option>\n";
        print "<option value=\"WEB\"> WEB</option>\n";
        print "</select></td>\n";
        print "  </tr>\n";

        if ($vterm::chkprocessor =~ /^(alliancesp|echo|paymentdata|testprocessor|testprocessorach|gms)$/) {
          print "  <tr>\n";
          print "    <th>Phone:</th>\n";
          print "    <td><input type=text size=\"20\" name=\"phone\" class=\"thin\"onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\"> (required for WEB checks)</td>\n";
          print "  </tr>\n";
        }
        #}

        print "</table>\n";
        print "</div>\n";
      }

      print "<table>\n";

      &amount_info();

      #if ($vterm::username =~ /^(omallentow|omrichmond|omsf|omatlanta|omaugusta|omcharlott|omcincinna|omdetroit|omftlauder|omgreensbu|omindy|omkc|omknoxvill|omlosangel|omminneapo|omno|omomaha|omportland|omraleigh|omstlouis|omtest|omwaunakee|omsaltlake)$/) {
      if (($vterm::processor eq "global") && ($vterm::username =~ /^om/)) {
        print "  <tr>\n";
        print "    <th>Invoice #:</th>\n";
        print "    <td><input name=\"partialponumber\" type=\"text\" class=\"thin\" value=\"\" maxlength=\"17\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.  backgroundColor='#ffffff'\"> *required</td>\n";
        print "  </tr>\n";
      }
      else {
        &misc_stuff();
        &settings_label();

        my ($client,$receipt_type,$print_receipt,$summarizeflg,$settings);
        if (exists $vterm::cookie{'cardinput_settings'}) {
          ($client,$receipt_type,$print_receipt,$summarizeflg,$settings) = split('\|',$vterm::cookie{'cardinput_settings'});
        }

        my %selected;
        $selected{$summarizeflg} = "checked";

        if ($ENV{'REMOTE_USER'} eq "pnpdemo2") {
          print "  <tr>\n";
          print "    <th>Summarize:</th>\n";
          print "    <td><input type=\"checkbox\" name=\"summarizeflg\" value=\"1\" $selected{'1'}> Check to review billing information prior to submission.</td>\n";
          print "  </tr>\n";
        }

        %selected = ();
        $selected{$client} = "checked";

        print "  <tr>\n";
        print "    <th>Update:</th>\n";
        print "    <td><input type=\"checkbox\" name=\"updatembr\" value=\"yes\"> Check to update recurring profile with new data.</td>\n";
        print "  </tr>\n";

        if ($vterm::dccusername ne "") {
          print "  <tr>\n";
          print "    <th>DCC:</th>\n";
          print "    <td><input type=\"checkbox\" name=\"client\" value=\"planetpay\" $selected{'planetpay'}> Check to settle in cardholder's native currency if applicable.</td>\n";
          print "  </tr>\n";
        }

        print "  <tr>\n";
        print "    <th>Email:</th>\n";
        print "    <td><input type=\"checkbox\" name=\"sndemailflg\" value=\"1\"> Check to have email confirmations sent.</td>\n";
        print "  </tr>\n";

        if ($vterm::processor eq "pago") {
          print "  <tr>\n";
          print "    <th>Payment Request Flag:</th>\n";
          print "    <td><input type=\"checkbox\" name=\"creditrequestflag\" value=\"1\"> Check to flag transaction as Payment Transfer. Only available for VISA cards.</td>\n";
          print "  </tr>\n";
        }
        &misc_stuff2();
      }

      #&misc_stuff();
      &submitform();

      print "</table>\n";
      print "</form>\n";
      print "</div>\n";
    }
    else {
      print "<div id=\"billmemdiv\" style=\"display:block\"></div>\n";
    }
  }
  #end bill form

  #begin footer
  my @now = gmtime(time);
  my $cpyear = sprintf("%4d", $now[5]+1900);

  print "<hr id=\"over\">\n";
  print "<table class=\"frame\">\n";
  print "  <tr>\n";
  print "    <td align=\"left\"><a href=\"/admin/logout.cgi\" title=\"Click to log out\">Log Out</a> | <a href=\"javascript:change_win('/admin/helpdesk.cgi',600,500,'ahelpdesk')\">Help Desk</a> | <a id=\"close\" href=\"javascript:closewin();\" title=\"Click to close this window\">Close Window</a></td>\n";
  print "    <td class=\"right\">&copy; $cpyear, ";
  if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
    print "Plug and Pay Technologies, Inc.";
  }
  else {
    print "$ENV{'SERVER_NAME'}";
  }
  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";
}
#end footer

sub address_info {
  my ($accttype) = @_;

  print "<table>\n";
  print "  <tr>\n";
  print "    <th class=\"label\">Address Information:</th>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th>Name:</th>\n";
  print "    <td><input name=\"card_name\" type=\"text\" value=\"\" class=\"wide\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th>Address:</th>\n";
  print "    <td><input name=\"card_address1\" type=\"text\" value=\"\" class=\"wide\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th>Address 2:</th>\n";
  print "    <td><input name=\"card_address2\" type=\"text\" value=\"\" class=\"wide\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th>City:</th>\n";
  print "    <td><input name=\"card_city\" type=\"text\" value=\"\" class=\"thin\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th>State:</th>\n";
  print "    <td><select name=\"card_state\" class=\"thin\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\">\n";
  print "<option value=\"\">State/Province</option>\n";
  foreach my $key (&sort_hash(\%constants::USstates)) {
    if ($constants::USstates{$key} =~ /^Select Your/) {
      next;
    }
    print "<option value=\"$key\">$constants::USstates{$key}</option>\n";
  }
  foreach my $key (sort keys %constants::USterritories) {
    print "<option value=\"$key\">$constants::USterritories{$key}</option>\n";
  }
  foreach my $key (sort keys %constants::CNprovinces) {
    if ($constants::CNprovinces{$key} =~ /Country other than/) {
      next;
    }
    print "<option value=\"$key\">$constants::CNprovinces{$key}</option>\n";
  }
  print "<option value=\"ZZ\">Other than USA/CANADA</option>\n";
  print "</select> ";
  print " &nbsp;Zip: <input name=\"card_zip\" type=\"text\" style=\"width:62px\" value=\"\" size=\"10\" maxlength=\"10\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th>International Province:</th>\n";
  print "    <td><input name=\"card_prov\" type=\"text\" class=\"thin\" value=\"\" maxlength=\"19\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th>Country:</th>\n";
  print "    <td><select name=\"card_country\" class=\"thin\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\">\n";
  print "<option value=\"\"> Select Your Country</option>\n";
  my %selected = ();
  $selected{'US'} = " selected";
  foreach my $key (sort_hash(\%constants::countries)) {
    print "<option value=\"$key\"$selected{$key}>$constants::countries{$key}</option>\n";
  }
  print "</select></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th>Receipt Email:</th>\n";
  print "    <td><input name=\"email\" type=\"text\" class=\"thin\" value=\"\" maxlength=\"49\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\"></td>\n";
  print "  </tr>\n";

  if ($accttype eq "credit") {
    print "  <tr>\n";
    print "    <th>Phone:</th>\n";
    print "    <td><input type=text size=\"20\" name=\"phone\" class=\"thin\"onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\"></td>\n";
    print "  </tr>\n";
  }
  print "</table>\n";
  print "<!-- end address info table -->\n";
}


sub misc_stuff {
  print "  <tr>\n";
  print "  <th>Order ID:</th>\n";
  print "    <td><input name=\"orderID\" type=\"text\" class=\"thin\" value=\"\" maxlength=\"17\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\"> *optional</td>\n";
  print "  </tr>\n";

  print "   <tr>\n";
  print "     <th>Acct Code:</th>\n";
  print "     <td><input name=\"acct_code\" type=\"text\" class=\"thin\" maxlength=\"25\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\"> *optional</td>\n";
  print "   </tr>\n";
  print "   <tr>\n";
  print "     <th>Acct Code 2:</th>\n";
  print "     <td><input name=\"acct_code2\" type=\"text\" class=\"thin\" maxlength=\"25\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\"> *optional</td>\n";
  print "   </tr>\n";
  if ($vterm::processor eq "fdmsnorth") {
    print "   <tr>\n";
    print "     <th>Free Form Data:</th>\n";
    print "     <td><input name=\"freeform\" type=\"text\" class=\"thin\" maxlength=\"25\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\"> *optional</td>\n";
    print "   </tr>\n";
  }

}

sub settings_label {
  print "</table>\n";
  print "<table>\n";
  print "  <tr>\n";
  print "    <th class=\"label\">Settings:</th>\n";
  print "  </tr>\n";
}

sub misc_stuff2 {
  my ($client,$receipt_type,$print_receipt,$summarizeflg,$settings);
  if (exists $vterm::cookie{'cardinput_settings'}) {
    ($client,$receipt_type,$print_receipt,$summarizeflg,$settings) = split('\|',$vterm::cookie{'cardinput_settings'});
  }

  my %selected;
  $selected{$receipt_type} = "checked";
  print "  <tr>\n";
  print "    <th>Receipt Type:</th>\n";
  print "    <td><input type=\"radio\" name=\"receipt_type\" value=\"\" checked> None &nbsp; <input type=\"radio\" name=\"receipt_type\" value=\"simple\" $selected{'simple'}> Std. Printer &nbsp; <input type=\"radio\" name=\"receipt_type\" value=\"pos_simple\" $selected{'pos_simple'}> Receipt Printer</td>\n";
  print "  </tr>\n";

  %selected = ();
  $selected{$print_receipt} = "checked";
  print "  <tr>\n";
  print "    <th>Auto Receipt:</th>\n";
  print "    <td><input type=\"checkbox\" name=\"print_receipt\" value=\"yes\" $selected{'yes'}> Check to Have Receipt Printed Automatically on Load.</td>\n";
  print "  </tr>\n";

  if ($vterm::feature{'marketdataflg'} == 1) {
    print "  <tr>\n";
    print "    <th>Market Data:</th>\n";
    print "    <td><input type=\"text\" size=\"15\" maxlength=\"25\" name=\"marketdata\" value=\"\"></td>\n";
    print "  </tr>\n";
  }

  #if ($ENV{'REMOTE_ADDR'} eq "96.56.10.12") {
  ## 02/26/11 James - commented out this setting, as there is an issue with getting SMPS to set cookies proeprly with the Apache2/mod_perl version used
  ##                - this has been an known/ongoing issue that was realized back when we migrated server platforms back in July 2010.
  %selected = ();
  $selected{$settings} = "checked";
  print "  <tr>\n";
  print "    <th>Remember Settings:</th>\n";
  print "    <td><input type=\"checkbox\" name=\"settings\" value=\"yes\" $selected{'yes'}> Check to remember settings for next time.</td>\n";
  print "  </tr>\n";
  #}
}

sub submitform {
  print "  <tr>\n";
  print "    <td></td>\n";
  print "    <td><div id=\"processingStatement\" style=\"visibility:hidden\"><font color=\"#ff0000\"><b>Processing Payment, Please be Patient</b></font></div>\n";
  if ($vterm::feature{'multicurrency'} eq "1") {
    print "<input type=\"hidden\" name=\"transflags\" value=\"multicurrency\">\n";
  }
  #print "<input type=\"submit\" name=\"submit\" value=\"Submit Payment\" onClick=\"return isCreditCard(this.form.card_number.value) && is_processing('true')\"> <input type=\"reset\" value=\"Clear Form\" onClick=\"is_processing('false') && hint('blurClass')\"> <input type=\"button\" value=\"Unlock\" disabled=\"disabled\" onClick=\"enableForm(this.form);\"></td>\n";
  print "<input type=\"submit\" name=\"submit\" value=\"Submit Payment\" onClick=\"is_processing('true');\"> <input type=\"reset\" value=\"Clear Form\" onClick=\"is_processing('false');\"> <input type=\"button\" value=\"Unlock\" disabled=\"disabled\" onClick=\"enableForm(this.form);\"></td>\n";
  print "  </tr>\n";
}

sub hiddenfields {
  print "<input type=\"hidden\" name=\"function\" value=\"inputnew\">\n";
  print "<input type=\"hidden\" name=\"magstripe\" value=\"\">\n";
  print "<input type=\"hidden\" name=\"convert\" value=\"underscores\">\n";
  print "<input type=\"hidden\" name=\"merchant\" value=\"$vterm::merchant\">\n";
  print "<input type=\"hidden\" name=\"vt_url\" value=\"$vterm::vt_cgi\">\n";
  if ($ENV{'SUBACCT'} ne "") {
    print "<input type=\"hidden\" name=\"subacct\" value=\"$ENV{'SUBACCT'}\">\n";
  }
  print "<input type=\"hidden\" name=\"receipt_company\" value= \"$vterm::company\">\n";
}


sub creditcard_info {
    print "  <tr>\n";
    print "    <th>Credit Card Number:</th>\n";
    if (($vterm::username !~ /^(nabcentra2|scotttest|jhewitt01|jhewitt02|nabmunicip|nablibrary|pnpdemo2)$/) && ($vterm::feature{'keyswipe'} ne "secure")) {
      print "    <td><input name=\"card_number\" type=\"text\" class=\"thin\" value=\"\" maxlength=\"20\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\" id=\"card_number\" autocomplete=\"off\">&nbsp;\n";
    }
    else {
      print "    <td><input name=\"card_number\" type=\"text\" class=\"thin\" value=\"\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\" id=\"card_number\" onKeyPress=\"return noautosubmit(event);\" autocomplete=\"off\">&nbsp;\n";
    }
    print "      <input type=\"hidden\" name=\"magensacc\" value=\"\" />\n"; # used for encrypted card reader data

    print "CVV: <input name=\"card_cvv\" type=\"text\" style=\"width:40px\" value=\"\" maxlength=\"4\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\" autocomplete=\"off\">";

    print "</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <th>Expiration Date:</th>\n";
    print "    <td><select name=\"month_exp\" style=\"width:60px\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\">\n";
    if ($vterm::query{'month-exp'} eq "") {
      $vterm::query{'month-exp'} = $vterm::current_month;
    }
    foreach my $var (@vterm::months) {
      if ($var eq $vterm::query{'month-exp'}) {
        print "<option value=\"$var\" selected>$var</option>\n";
      }
      else {
        print "<option value=\"$var\">$var</option>\n";
      }
    }
    print "</select>\n";
    print " <select name=\"year_exp\" style=\"width:60px\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\">\n";
    if ($vterm::query{'year-exp'} eq ""){
      $vterm::query{'year-exp'} = $vterm::current_year;
    }
    for (my $i; $i<=21; $i++) {
      my $var = $vterm::current_year + $i;
      my $val = substr($var,2,2);
      if ($val eq $vterm::query{'year-exp'}) {
        print "<option value=\"$val\" selected>$var</option>\n";
      }
      else {
        print "<option value=\"$val\">$var</option>\n";
      }
    }
    print "</select></td>\n";
    print "  </tr>\n";
}

sub amount_info {
  print "  <tr>\n";
  print "    <th>Amount:</th>\n";
  print "    <td><input name=\"card_amount\" id=\"card_amount\" type=\"text\" class=\"thin\" maxlength=\"10\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\">\n";

  if ( ($vterm::feature{'curr_allowed'} ne "") && ($vterm::processor eq "ncb") && ($vterm::feature{'procmulticurr'} == 1)  ) {
    my (%selected);
    $selected{"$vterm::currency"} = "selected";
    print "<select name=\"currency\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\">\n";
    my @array = split(/\|/,$vterm::feature{'curr_allowed'});
    foreach my $entry (@array) {
      $entry =~ tr/A-Z/a-z/;
      $entry =~ s/[^a-z]//g;
      print "<option value=\"$entry\" $selected{$entry}>$entry</option>\n";
    }
    print "</select> ";
  }
  elsif (($vterm::feature{'curr_allowed'} ne "") && ($vterm::processor =~ /^(pago|atlantic|planetpay|testprocessor|fifththird|wirecard)$/)) {
    my (%selected);
    $selected{"$vterm::currency"} = "selected";
    print "<select name=\"currency\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\">\n";
    my @array = split(/\|/,$vterm::feature{'curr_allowed'});
    foreach my $entry (@array) {
      $entry =~ tr/A-Z/a-z/;
      $entry =~ s/[^a-z]//g;
      print "<option value=\"$entry\" $selected{$entry}>$entry</option>\n";
    }
    print "</select> ";
  }
  else {
    print "<input type=hidden name=\"currency\" value=\"$vterm::currency\"> ($vterm::currency) ";
  }

  print " (example: 1200.99)</td>\n";
  print "  </tr>\n";

  print "  <tr><th></th><td><span id=\"convFeeContainer\"></span></td></tr>\n";


}

sub virtterm {

  &head('Virtual Terminal');

  if (($ENV{'SEC_LEVEL'} < 9) || ($ENV{'SEC_LEVEL'} == 13)) {
    if (($vterm::processor eq "planetpay") && ($vterm::feature{'multicurrency'} != 1)) {
      print "<hr width=400></td></tr>\n";
      print "<tr>\n";
      print "<th valign=top align=left bgcolor=\"#4a7394\"><font color=\"#ffffff\"> Manual<br>Authorizations<br> &amp;<br>Returns</font></th>\n";
      print "<th align=\"left\">\n";

      print "Manually entered transaction are not permitted through a DCC account.<p>\n";
      print "Please use your primary account to enter these types of transactions.<p>\n";
      print "Credits against previously sales should be performed by searching on the original transaction first.<p>\n";
      print "<hr width=400></th></tr>\n";
    }
    else {
      &cardinput();
    }
  }

  &tail();
  return;
}

sub head {
  my ($title) = @_;

  if ($title eq "") {
    $title = "Transaction Administration";
  }

  if (1) {
    print $vterm::query->header( -type =>'text/html');
  }
  else {
    print "Content-Type: text/html\r\n\r\n";
  }
  #print "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\" \"http://www.w3.org/TR/html4/loose.dtd\">\n";
  print "<html>\n";
  print "<head>\n";
  print "<title>Virtual Terminal</title>\n";

  #print "<META HTTP-EQUIV=\"Cache-Control\" CONTENT=\"no-store, no-cache, must-revalidate\">\n";
  #print "<META HTTP-EQUIV=\"Pragma\" CONTENT=\"no-cache\">\n";
  #print "<META HTTP-EQUIV=\"Expires\" CONTENT=\"-1\">\n";

  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"/css/vt.css\">\n";

  # js logout prompt
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/_js/jquery.min.js\"></script>\n";
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

  print "<script type=\"text/javascript\" src=\"/css/vt.js\"></script>\n";

  print "<MP Version: $ENV{'MOD_PERL'}>\n";

  if ($vterm::feature{'convfee'} eq "1") {
    print "<script type=\"text/javascript\" src=\"/admin/_js/virtualterm.js\"></script>\n";
    print "<script type='text/javascript'>\n";
    print "   jQuery('document').ready( function() { \n";
    print "	   convenienceFee('$vterm::username');\n";
    print "   });\n";
    print "</script>\n";
  }

  #print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/javascript/jquery.min.js\"></script>\n";
  print "<script type=\"text/javascript\" src=\"/javascript/swipe.js\"></script>\n";
  print "<script type='text/javascript'> \n";
  print "   \$('document').ready( function() { \n";
  print "   pnp_BindKr('#card_number,#routingnum'); \n";
  print "   }); \n";
  print "</script> \n";
  if ($vterm::feature{'keyswipe'} eq "secure") {
    print "<script type=\"text/javascript\"> \n";
    print "      \$(function(){ \n";
    print "        // find all the input elements with placeholder attributes \n";
    print "               \$('input[placeholder!=\"\"]').hint(); \n";
    print "       }); \n";
    print "</script>\n";
  }

  print "<script Language=\"Javascript\" type=\"text/javascript\">\n";
  print "<!-- Start Script\n";

  print "function results() \{\n";
  print "   resultsWindow \= window.open(\"/payment/recurring/blank.html\",\"results\",\"menubar=no,status=no,scrollbars=yes,resizable=yes,width=400,height=300\")\;\n";
  print "}\n";

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

  print "function disableForm(theform) {\n";
  print "  if (document.all || document.getElementById) {\n";
  print "    for (i = 0; i < theform.length; i++) {\n";
  print "      var tempobj = theform.elements[i];\n";
  print "      if (tempobj.type.toLowerCase() == \"submit\" || tempobj.type.toLowerCase() == \"reset\") {\n";
  print "        tempobj.disabled = true;\n";
  print "      }\n";
  print "      if (tempobj.type.toLowerCase() == \"button\") { \n";
  print "        tempobj.disabled = false; \n";
  print "      }\n";
  print "    }\n";
  print "    return true;\n";
  print "  }\n";
  print "  else {\n";
  print "    return true;\n";
  print "  }\n";
  print "}\n\n";

  print "function enableForm(theform) { \n";
  print "if (document.all || document.getElementById) { \n";
  print "  for (i = 0; i < theform.length; i++) { \n";
  print "    var tempobj = theform.elements[i]; \n";
  print "    if (tempobj.type.toLowerCase() == \"submit\" || tempobj.type.toLowerCase() == \"reset\")\n";
  print "      tempobj.disabled = false; \n";
  print "    if (tempobj.type.toLowerCase() == \"button\") \n";
  print "      tempobj.disabled = true; \n";
  print "  }\n";
  print "  return true; \n";
  print "} \n";
  print "else { \n";
  print "  return true; \n";
  print "} \n";
  print "}\n";

  #luhn10 check
  print "function isCreditCard(CC) {\n";
  print "// perform luhn10 check on credit card number\n";

  print "  if (CC == \"ENCRYPTED\") {\n";
  print "       return true;\n";
  print "  }\n";

  print "  var cardtest = CC.slice(0,6);\n";
  print "  if ((cardtest == '604626') || (cardtest == '605011') || (cardtest == '603028') || (cardtest == '603628')) {\n";
  print "    return true;\n";
  print "  }\n\n";

  if (($vterm::processor eq "mercury") && ($vterm::feature{'acceptgift'} == 1)) {
    print "  if ((document.pay.mpgiftcard) && (document.pay.mpgiftcard.value.length > 12) && (document.pay.card_number.value.length == 0)) {\n";
    print "    return true;\n";
    print "  }\n\n";
  }

  print "  CC = CC.replace(/\\D/g,''); // strips non-numeric characters\n";
  print "  if ((CC.length > 20) || (CC.length < 12)) {\n";
  print "       alert('Invalid Credit Card Length.  Please Try Again.');\n";
  #print "       return false;\n";
  print "       return is_processing('false');\n";
  print "  }\n";

  print "  sum = 0; mul = 1; l = CC.length;\n";

  print "  for (i = 0; i < l; i++) {\n";
  print "       digit = CC.substring(l-i-1,l-i);\n";
  print "       tproduct = parseInt(digit ,10)*mul;\n";
  print "       if (tproduct >= 10) {\n";
  print "         sum += (tproduct % 10) + 1;\n";
  print "       }\n";
  print "       else {\n";
  print "         sum += tproduct;\n";
  print "       }\n";
  print "       if (mul == 1) {\n";
  print "         mul++;\n";
  print "       }\n";
  print "       else {\n";
  print "         mul--;\n";
  print "       }\n";
  print "  }\n";

  print "  if ((sum % 10) == 0) {\n";
  print "  // card passed luhn10 check\n";
  print "         return true;\n";
  print "  }\n";
  print "  else {\n";
  print "  // card failed luhn10 check\n";
  print "       alert('Invalid Credit Card Number.  Please Try Again.');\n";
  #print "       return false;\n";
  print "       return is_processing('false');\n";
  print "  }\n";
  print "}\n";


  # DWW added to validate form
  print "function valForm(thisForm) { \n";
  my @req_fields = split(/\|/,$vterm::feature{'vtrequired'});
  my $req_string = "";
  my $field_string = "";
  foreach my $field (@req_fields) {
    $req_string .= "\"$field\"\,";
    $field_string .= "\"$vterm::fieldnames{$field}\"\,";
  }
  chop $req_string;
  chop $field_string;
  print "  var reqs = new Array($req_string); \n";
  print "  var fields = new Array($field_string); \n";
  print "  for (pos = 0; pos < reqs.length; pos++) {\n";
  print "    if(document.pay.elements[reqs[pos]].value ==\"\") { \n";
  print "    alert(fields[pos] + \" is a required field.\") \n";
  print "    document.pay.elements[reqs[pos]].focus(); \n";
  print "    return false } \n";
  print "  }\n";
  print "  return true \n";
  print "} \n";

  print "function bmcreditActive() { \n";
  print "  billmemccdiv.style.display ='block'\n";
  print  "  billmemachdiv.style.display ='none'\n";
  print "} \n";
  print "function bmcheckActive() { \n";
  print  "  billmemachdiv.style.display ='block'\n";
  print "  billmemccdiv.style.display ='none'\n";
  print "} \n";

  print "function is_loading(recon) {\n";
  print "  if (recon == 'true') {\n";
  print "    document.getElementById('loadingStatement').style.visibility = \"visible\";\n";
  print "  }\n";
  print "  else {\n";
  print "    document.getElementById('loadingStatement').style.visibility = \"hidden\";\n";
  print "  }\n";
  print "}\n";

  print "function is_processing(recon) {\n";
  print "  if (recon == 'true') {\n";
  print "    document.getElementById('processingStatement').style.visibility = \"visible\";\n";
  print "  }\n";
  print "  else {\n";
  print "    document.getElementById('processingStatement').style.visibility = \"hidden\";\n";
  print "    return false;\n";
  print "  }\n";
  print "}\n";

  print "// end script-->\n";
  print "</script>\n";
  print "</head>\n";

  print "<body bgcolor=\"#ffffff\" onLoad=\"is_loading('false');\">\n";

  print "<div>\n";
  print "<table>\n";
  print "  <tr>\n";
  print "    <td><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Payment Gateway Logo\"></td>\n";
  print "    <td class=\"right\">&nbsp;</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td colspan=\"2\"><img src=\"/adminlogos/masthead_background.gif\" alt=\"Corp. Logo\" width=\"750\" height=\"16\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";
  print "</div>\n";
}

sub tail {
  print "</body>\n";
  print "</html>\n";
}

sub sort_hash {
  my $x = shift;
  my %array=%$x;
  sort { $array{$a} cmp $array{$b}; } keys %array;
}

# used for a numeric sort
sub numerically {$a <=> $b}

sub displaycc {
  my (%cardnumber) = @_;

  print "<script Language=\"Javascript\" type=\"text/javascript\">\n";
  print "<!-- Start Script\n";

  print "function displayCC() {\n";
  print "  var myCCArray = new Array();\n";
  print "  var myCCInfoArray = new Array();\n";
  foreach my $key (keys %cardnumber) {
    print "  myCCArray[\'$key\'] = \'$cardnumber{$key}\'\;\n";
  }
  print "  var searchInteger, searchString\n";
  print "  testInteger=document.bill.username.selectedIndex\n";
  print "  testString=document.bill.username.options[testInteger].value\n";

  # ACH
  #if ($vterm::chkprocessor ne "") {
  if ($vterm::achstatus eq "enabled") {
  print " myCCInfoArray = myCCArray[testString].split(\"|\");\n";
  print " if (myCCInfoArray[2] === \"checking\") {\n";
  print "       document.bill.card_number.value = \"\"\;\n";
  print "       billmemachdiv.style.display ='block'\n";
  print "       billmemccdiv.style.display ='none'\n";
  print "  myCCInfoArray = myCCInfoArray[0].split(\":\");\n";
  print "       document.bill.routingnum.value = eval(\"myCCInfoArray[0]\");\n";
  print "       document.bill.accountnum.value = eval(\"myCCInfoArray[1]\");\n";
  print "  document.getElementById('paymethodchecking').checked = true;\n";
  print "       document.getElementById('paymethodcredit').checked = false;\n";
  print "       document.bill.phone.value = eval(\"myCCInfoArray[2]\");\n";
  print " }\n";

  # CC
  print " else {\n";
  print "       billmemccdiv.style.display ='block'\n";
  print "       billmemachdiv.style.display ='none'\n";
  print "       document.bill.routingnum.value = \"\"\;\n";
  print "       document.bill.accountnum.value = \"\"\;\n";
  print "       document.getElementById('paymethodchecking').checked = false;\n";
  print "       document.getElementById('paymethodcredit').checked = true;\n";
  }

  print "  if (testInteger=document.bill.username.options[0].selected) {\n";
  print "    document.bill.card_number.value = \"\"\;\n";
  print "    }\n";
  print "    else {\n";
  print "      myCCInfoArray = myCCArray[testString].split(\"|\");\n";
  print "      document.bill.card_number.value = eval(\"myCCInfoArray[0]\");\n";
  print "      for(idx = 0; idx < document.bill.month_exp.length; idx++) {\n";
  print "      if (document.bill.month_exp[idx].value == myCCInfoArray[1]) {\n";
  print "        document.bill.month_exp[idx].selected = true;\n";
  print "      }\n";
  print "    }\n";
  print "    for(idx = 0; idx < document.bill.year_exp.length; idx++) {\n";
  print "      if (document.bill.year_exp[idx].value == myCCInfoArray[2]) {\n";
  print "        document.bill.year_exp[idx].selected = true;\n";
  print "      }\n";
  print "    }\n";
  print "  }\n";
  #if ($vterm::chkprocessor ne "") {
  if ($vterm::achstatus eq "enabled") {
    print " }\n";
  }
  print "}\n"; # end of fucntion

  print "// end script-->\n";
  print "</script>\n";

}

sub check_linked_acct {
  my($username,$merchant,$la_feature) = @_;
  my(%linked_accts);

  if ($la_feature ne "") {
    my $dbh = &miscutils::dbhconnect("pnpmisc");
    my (%la_feature,%la_linked_accts);
    my @linked_accts = split('\|',$la_feature);
    foreach my $var (@linked_accts) {
      $var =~ s/[^0-9a-z]//g;
      $linked_accts{$var} = 1;
    }
    if (exists $linked_accts{$merchant} ) {
      my $ga = new PlugNPay::GatewayAccount($merchant);
      $username = "$ga";

      my $processor = $ga->getCardProcessor();

      my $cardProcessorAccount;
      my $merchantid;
      my $proc_type;
      my $currency;
      my $retailflag;

      eval {
        $cardProcessorAccount = new PlugNPay::Processor::Account({ gatewayAccount => $ga, processorName => $processor });
        $merchantid = $cardProcessorAccount->getSettingValue('mid');
        $proc_type = $cardProcessorAccount->getSettingValue('authType');
        $currency = $cardProcessorAccount->getSettingValue('currency');
        $retailflag = $cardProcessorAccount->getIndustry();
      };

      my $company = $ga->getMainContact()->getCompany();
      my $reseller = $ga->getReseller();
      my $checkprocessor = $ga->getCheckProcessor();
      my $dccusername =$ga->getDCCAccount();
      my $merchstrt = $ga->getStartDate();
      my $status = $ga->getStatus();
      my $walletprocessor = $ga->getWalletProcessor();

      ## Linked Account request is verified.
      $vterm::merchantid = $merchantid;
      $vterm::processor = $processor;
      $vterm::proc_type = $proc_type;
      $vterm::company = $company;
      $vterm::currency = $currency;
      $vterm::reseller = $reseller;
      $vterm::chkprocessor = $checkprocessor;
      $vterm::dccusername = $dccusername;
      $vterm::merchstrt = $merchstrt;
      $vterm::retailflag = $retailflag;
      $vterm::status = $status;
      $vterm::walletprocessor =$walletprocessor;
      $ENV{'REMOTE_USER'} = $username;
      $vterm::username = $username;
      %vterm::feature = %{$ga->getFeatures()->getFeatures()};
    }
    $dbh->disconnect;
  }

}


1;
