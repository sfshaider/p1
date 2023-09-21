package payutils;

use strict;
use pnp_environment;
use CGI;
use DBI;
use SHA;
use rsautils;
use scrubdata;
use miscutils;
use XML::DOM;
use XML::Simple;
use XML::Writer;
use constants qw(%countries %USstates %USterritories %CNprovinces %USCNprov %timezones);
use language qw(%lang_titles);
use sysutils;
use PlugNPay::InputValidator;
use PlugNPay::ResponseLink;
use PlugNPay::Environment;
use PlugNPay::Security::CSRFToken;
use PlugNPay::API::REST::Session;
use PlugNPay::COA;
use PlugNPay::Email;
use PlugNPay::Features;
use PlugNPay::Transaction::TransactionProcessor;
use PlugNPay::Util::Captcha::ReCaptcha;
use PlugNPay::Util::RandomString;
use PlugNPay::Legacy::PayUtils::PayTemplate;
use PlugNPay::Logging::DataLog;
use HTML::Entities;
use PlugNPay::PayScreens::Assets;

sub new {
  my $type = shift;

  %payutils::query = @_;

  $payutils::path_web = &pnp_environment::get('PNP_WEB');

  # added by drew to scrub bad html out of data and log it
  my $scrubber = new scrubdata;
  foreach my $key (keys %payutils::query) {
    if ($key =~ /^(description|item|cost|quantity)/i) {
      my $original = $payutils::query{$key};
      $payutils::query{$key} = $scrubber->untainttext($payutils::query{$key});
      if ($original ne $payutils::query{$key}) {
        open(SCRUBDEBUG,'>>',"/home/p/pay1/database/debug/scrub_debug.txt");
        print SCRUBDEBUG "$payutils::query{'publisher-name'}\t$payutils::query{'orderID'}\t$key\t$payutils::query{$key}\t$original\n";
        close SCRUBDEBUG;
      }
    }
  }

  %payutils::feature=();
  %payutils::pl_feature = ();
  %payutils::color=();
  %payutils::cookie=();
  %payutils::error=();
  %payutils::requiredstar = ();
  %payutils::readonly = ();
  %payutils::displayonly = ();
  %payutils::template = ();
  %payutils::tableprop = ();
  %payutils::lang_titles = ();
  %payutils::autocomplete = ();

  @payutils::item=();
  @payutils::description = ();
  @payutils::quantity = ();
  @payutils::cost = ();
  @payutils::weight = ();
  @payutils::ext = ();
  @payutils::taxable = ();
  @payutils::nohidden = ();
  @payutils::encrypt_nohidden = ();
  @payutils::nocheck = ();
  @payutils::privacy_statement = ();
  @payutils::giftstatement = ();
  @payutils::unknownParameters = ();
  @payutils::customfields = ();

  $payutils::subtotal = "";
  $payutils::max = "";
  $payutils::taxsubtotal = "";
  $payutils::totalcnt = "";
  $payutils::totalwgt = "";

  $payutils::domain="";
  $payutils::company="";
  $payutils::reseller="";
  $payutils::chkprocessor = "";
  $payutils::walletprocessor = "";
  $payutils::feature = "";
  $payutils::pl_features = "";
  $payutils::unpw_minlength = "";
  $payutils::unpw_maxlength = "";
  $payutils::pwcheckplus = "";
  $payutils::usonly = "";
  $payutils::uscanonly = "";
  $payutils::usterrflag = "";
  $payutils::itemrow = "";
  $payutils::nophone = "";
  $payutils::couponflag = "";
  $payutils::pnpdevelopment = "";

  $payutils::ewallet = "";
  $payutils::upsell_url = "";
  $payutils::upsell = "";
  $payutils::bname = "";
  $payutils::username = "";
  $payutils::password = "";
  $payutils::skip_express = "";
  $payutils::allow_cookie = "";

  $payutils::error_string ="";
  $payutils::error = "";
  $payutils::errvar = "";
  $payutils::orderID = "";

  $payutils::online_checks = "";
  $payutils::path_wallet = "";
  $payutils::path_wallet2 = "";
  $payutils::match = "";
  $payutils::unpwcheck = "";
  $payutils::path_zipcode = "";

  $payutils::digprodflg = "";
  $payutils::hrdprodflg = "";
  $payutils::digonlyflg = "";

  $payutils::goodcolor = "";
  $payutils::backcolor = "";
  $payutils::badcolor = "";
  $payutils::badcolortxt = "";
  $payutils::linkcolor = "";
  $payutils::textcolor = "";
  $payutils::alinkcolor = "";
  $payutils::vlinkcolor = "";
  $payutils::fontface = "";
  $payutils::itemrow = "";
  $payutils::privacy_statement = "";
  $payutils::upsellflag = "";
  $payutils::merch_state = "";
  $payutils::backimage = "";
  $payutils::autoload = "";
  $payutils::lang = 0;
  $payutils::newswipecode = 0;
  $payutils::startdate = "";

  $payutils::certitaxhost = "certitax";

  $payutils::currency = "";

  %payutils::coupon_info = ();
  %payutils::coupon_promo_info = ();
  %payutils::fraud_config = ();

  $payutils::gift_coupon = 0; # assume no gift certificate coupon was used

  $payutils::mpgiftcard_balance = 0;

  # List of available 'card-allowed' card type values
  @payutils::card_list = ("Visa", "Mastercard", "Amex", "Discover", "Diners", "JCB", "EasyLink", "Bermuda", "IslandCard", "Butterfield", "KeyCard", "MilStar", "Solo", "Switch");

  # Hash of available 'card-allowed' values with their assocated short cardtype, title & logo URL details
  # Format: "CARD-TYPE" => ["RADIO_VALUE", "RADIO_TEXT", "IMAGE_PATH"]
  %payutils::card_hash = (
    "Visa"        => ["VISA",        "Visa",             "/images/small-visa.gif"],
    "Mastercard"  => ["MSTR",        "Mastercard",       "/images/small-mastercard.gif"],
    "Amex"        => ["AMEX",        "Amex",             "/images/small-amex.gif"],
    "Discover"    => ["DSCR",        "Discover",         "/images/small-discover.gif"],
    "Diners"      => ["DNRS",        "Diners Club",      "/images/small-diners.gif"],
    "JCB"         => ["JCB",         "JCB",              "/images/small-jcb.gif"],
    "EasyLink"    => ["EasyLink",    "EasyLink",         "/images/small-easylink.gif"],
    "Bermuda"     => ["Bermuda",     "Bermuda Card",     ""],
    "IslandCard"  => ["IslandCard",  "Island Card",      ""],
    "Butterfield" => ["Butterfield", "Butterfield Card", "/images/small-bermuda.gif"],
    "KeyCard"     => ["KeyCard",     "Key Card",         "/images/small-keycard.gif"],
    "MilStar"     => ["MilStar",     "Military Star",    "/images/small-milstar.gif"],
    "Solo"        => ["SOLO",        "Solo",             "/images/small-solo.gif"],
    "Switch"      => ["SWTCH",       "Switch",           "/images/small-switch.gif"]
  );


  my ($testun,$custstatus,$custreason,$fconfig,%fraud_config);

  my $env = new PlugNPay::Environment();
  my $remoteIP = $env->get('PNP_CLIENT_IP');

  if ($payutils::query{'fix_ie7'} eq "yes") {
    $payutils::query{'nostatelist'} = "yes";
    $payutils::query{'nocountrylist'} = "yes";
    $payutils::query{'nocardexplist'} = "yes";
    $payutils::query{'defaultcountry'} = "US";
  }

  if ($payutils::query{'convert'} =~ /underscores/i) {
    my @array = %payutils::query;
    %payutils::query = &miscutils::underscore_to_hyphen(@array);
  }

  $payutils::query{'publisher-name'} =~ s/[^0-9a-zA-Z]//g;
  $payutils::query{'publisher-name'} = substr($payutils::query{'publisher-name'},0,12);

  my %authNetTestHash = ( map { lc($_) => $payutils::query{$_} } keys %payutils::query );

  if ( ($payutils::query{'client'} =~ /^authnet$/i)
          || ( (exists $authNetTestHash{'x_login'}) && (exists $authNetTestHash{'x_version'}) )
          || ( (exists $authNetTestHash{'x_login'}) && (exists $authNetTestHash{'x_adc_relay_response'}) )
          || ( (exists $authNetTestHash{'x_login'}) && (exists $authNetTestHash{'x_relay_response'}) )) {

    my @array = %payutils::query;
    %payutils::query = &input_authnet(@array);
  }

  # create an inputvalidator instance
  my $iv = new PlugNPay::InputValidator;
  $iv->changeContext('payscreens');
  $iv->setDebug();
  $iv->setRemoteUser($payutils::query{'publisher-name'});

  # filter input using inputvalidator plan is a special problem this fixes it
  @payutils::unknownParameters = grep {!/^plan$/} $iv->unknownParameters(%payutils::query);
  ###  Comment

  my $dbh = &miscutils::dbhconnect("pnpmisc");
  my $sth = $dbh->prepare(q{
      SELECT username,status,reason,fraud_config,reseller,chkprocessor,processor,state,currency,walletprocessor,startdate
      FROM customers
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$payutils::query{'publisher-name'}") or die "Can't execute: $DBI::errstr";
  ($testun,$custstatus,$custreason,$fconfig,$payutils::reseller,$payutils::chkprocessor,$payutils::processor,$payutils::merch_state,$payutils::currency,$payutils::walletprocessor,$payutils::startdate) = $sth->fetchrow;
  $sth->finish;

  my $accountFeatures = new PlugNPay::Features("$payutils::query{'publisher-name'}",'general');
  $payutils::feature = $accountFeatures->getFeatureString();

  if (($custstatus eq "cancelled") || ($custstatus eq "hold")) {
    $dbh->disconnect;
    my $message = "The transaction cannot be processed for the following reason:\n";
    $message .= "C: " . substr($custreason,0,4);

    print "Content-Type: text/html\n\n";
    print response_page("$message");
    exit;
  }

  $payutils::reseller =~ s/[^0-9a-zA-Z]//g;

  my $sth2 = $dbh->prepare(q{
      SELECT company,features
      FROM privatelabel
      WHERE username=?
    });
  $sth2->execute("$payutils::reseller");
  ($payutils::company,$payutils::pl_features) = $sth2->fetchrow;
  $sth2->finish;

  if (($payutils::processor eq "psl") && ($payutils::query{'client'} eq "psl") && ($payutils::query{'pslstatus'} eq "badcard")) {
    my $sth = $dbh->prepare(q{
        SELECT qrydata
        FROM psldata
        WHERE username=?
        AND orderid=?
      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%payutils::query);
    $sth->execute("$payutils::query{'publisher-name'}", "$payutils::query{'orderID'}") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%payutils::query);
    my ($qrydata) = $sth->fetchrow;
    $sth->finish;
    foreach my $pair (split(/\&/,$qrydata)) {
      if ($pair =~ /(.*)=(.*)/) { #found key=value;#
        my ($key,$value) = ($1,$2);  #get key, value
        $value =~ s/%(..)/pack('c',hex($1))/eg;
        $value =~ s/\+/ /g;  #substitue spaces for + sign
        $key =~ s/%(..)/pack('c',hex($1))/eg;
        $key =~ s/\+/ /g;  #substitue spaces for + sign

        $payutils::query{$key} = $value; #Create Associative Array
      }
    }
    delete $payutils::query{'orderID'};
    $payutils::query{'FinalStatus'} = "badcard";
    $payutils::query{'MErrMsg'} = "Card Declined";
  }

  if (($payutils::reseller eq "webassis") && ($payutils::query{'image-link'} eq "")) {
    $payutils::query{'image-link'} = "https://$ENV{'SERVER_NAME'}/logos/webassist/wa_checkout.gif";
  }
  if ($payutils::reseller eq "intuit") {
    $payutils::query{'client'} = "intuit";
  }

  if (($payutils::query{'paymethod'} =~ /^(onlinecheck|check)$/i)) {  ## DCP 20090319
    if ($payutils::chkprocessor =~ /^(paymentdata|alliancesp|echo|testprocessor|testprocessorach|telecheck)$/) {
      if ($payutils::query{'required'} ne "") {
        if ($payutils::query{'required'} !~ /phone/) {
          $payutils::query{'required'} .= "|phone";
        }
      }
      else {
        $payutils::query{'required'} = "phone";
      }
      if ($payutils::query{'required'} !~ /acctclass/) {
        $payutils::query{'required'} .= "|acctclass";
      }

    }
  }

  if (($payutils::query{'shipsame'} ne "yes") && ($payutils::query{'shipinfo'} == 1) && ($payutils::query{'shipmethod'} =~ /UPS|USPS|pnp_amount/i)) {
    if ($payutils::query{'required'} ne "") {
      $payutils::query{'required'} .= "|shipname|address1|city|state|zip|country";
    }
    else {
      $payutils::query{'required'} .= "shipname|address1|city|state|zip|country";
    }
  }

  if ($payutils::feature =~ /(.*)=(.*)/) {
    my @array = split(/\,/,$payutils::feature);
    foreach my $entry (@array) {
      my($name,$value) = split(/\=/,$entry);
      $payutils::feature{$name} = $value;
    }
  }

  if ($payutils::pl_features =~ /(.*)=(.*)/) {
    my @array = split(/\,/,$payutils::pl_features);
    foreach my $entry (@array) {
      my($name,$value) = split(/\=/,$entry);
      $payutils::pl_feature{$name} = $value;
    }
  }

  if ($payutils::query{'acct_code3'} eq "billpay") {
    # Never allow a coupon management coupon code to be entered, when paying a billing presentment invoiced transaction
    # Explicitly turn off coupon code collection ability
    $payutils::couponflag = "";
    $payutils::feature{'couponflag'} = 0;
  }

  if ($payutils::query{'client'} eq "quikstor") {
    $payutils::feature{'noemail'} = 1;
  }

  if (($payutils::query{'publisher-email'} eq "") && ($payutils::feature{'pubemail'} ne "")) {
    $payutils::query{'publisher-email'} = $payutils::feature{'pubemail'};
  }

  if ($payutils::feature{'keyswipe'} =~ /^(secure)$/) {
    $payutils::newswipecode = 1;
  }

  if (($payutils::feature{'card-allowed'} ne "") && ($payutils::query{'card-allowed'} eq "")) {
    $payutils::query{'card-allowed'} = $payutils::feature{'card-allowed'};
    $payutils::query{'card-allowed'} =~ s/\|/\,/g;
  }

  if ($payutils::feature{'nohidden'} ne "") {
    @payutils::nohidden = split(/\|/,$payutils::feature{'nohidden'});
  }

  if ($payutils::query{'client'} =~ /mobile/) {
    $payutils::query{'convert'} = "underscores";
    push (@payutils::nohidden,'magensacc');
    push (@payutils::nohidden,'Track1');
    push (@payutils::nohidden,'EncTrack1');
    push (@payutils::nohidden,'EncTrack2');
    push (@payutils::nohidden,'EncTrack3');
    push (@payutils::nohidden,'EncMP');
    push (@payutils::nohidden,'KSN');
    push (@payutils::nohidden,'devicesn');
    push (@payutils::nohidden,'MPStatus');
    push (@payutils::nohidden,'MagnePrintStatus');
  }

  if ($payutils::query{'client'} eq "mobileapp") {
    $payutils::query{'receipt_type'} = "simple";
  }

  ### DCP 20110812 - To Support MonkeyMedia Customer.
  if ($payutils::query{'amexlev2'} == 1) {
    $payutils::feature{'amexlev2'} = 1;
  }
  if ($payutils::query{'amexlev2'} == 1) {
    push (@payutils::nohidden,'employeename');
    push (@payutils::nohidden, 'costcenternum');
  }

  if ($payutils::feature{'customfields'} == 1) {
    my ($fieldname,$size,$maxlen,$required,$class,$conditionkey,$conditionval);
    my $sth = $dbh->prepare(q{
        SELECT fieldname,size,maxlen,required,class,conditionkey,conditionval
        FROM customfields
        WHERE username=?
      }) or die "Can't do: $DBI::errstr";
    $sth->execute("$payutils::query{'publisher-name'}") or die "Can't execute: $DBI::errstr";
    while (my ($fieldname,$size,$maxlen,$required,$class,$conditionkey,$conditionval) = $sth->fetchrow) {
      if ($payutils::query{"$conditionkey"} ne $conditionval) {
        next;
      }
      ##  set required
      if ($payutils::query{'required'} ne "") {
        if ($payutils::query{'required'} !~ /$fieldname/) {
          $payutils::query{'required'} .= "|$fieldname";
        }
      }
      else {
        $payutils::query{'required'} = "$fieldname";
      }
      push (@payutils::nohidden,$fieldname);
      my $tmp = "$fieldname,$size,$maxlen,$class";
      push (@payutils::customfields, "$tmp");
    }
    $sth->finish;
  }

  $dbh->disconnect;

  #if ($payutils::feature{'usonly'} eq "yes") {
  if ($payutils::feature{'usonly'} =~ /^(yes|1)$/i) {
    $payutils::usonly = "yes";
  }
  #elsif ($payutils::feature{'uscanonly'} eq "yes") {
  elsif ($payutils::feature{'uscanonly'} =~ /^(yes|1)$/i) {
    $payutils::uscanonly = "yes";
  }
  #if ($payutils::feature{'usterrflag'} eq "no") {
  if ($payutils::feature{'usterrflag'} =~ /^(no|0)$/i) {
    $payutils::usterrflag = "no";
  }

  # 10/28/10 - force phone to show for ACH/eCheck payments.
  if (($payutils::query{'paymethod'} =~ /^(onlinecheck|check)$/i) && ($payutils::chkprocessor =~ /^(paymentdata|alliancesp|echo|testprocessor|testprocessorach)$/)) {
    $payutils::feature{'nophone'} = 0;
    $payutils::nophone = "";
  }

  ####  DCP 20090508
  #### JT 20110604 - corrected 'merchantdb' regex filter to permit alphanumeric characters (was alpha only)
  if (( exists $payutils::query{'merchantdb'} ) && ($ENV{'SCRIPT_NAME'} =~ /\/pay\.cgi$/)){
    $payutils::query{'merchantdb'} =~ tr/A-Z/a-z/;
    $payutils::query{'merchantdb'} =~ s/[^a-z0-9]//g;
    if ($payutils::feature{'altmerchantdb'} =~ /$payutils::query{'merchantdb'}/) {

    }
    else {
      delete $payutils::query{'merchantdb'};
    }
  }

  if ($payutils::feature{'pwcheckplus'} =~ /^(yes|1)$/i) {
    $payutils::pwcheckplus = "yes";
  }

  if (exists $payutils::feature{'autocomplete'}) {
    my @array = split('\|',$payutils::feature{'autocomplete'});
    foreach my $var (@array) {
      $payutils::autocomplete{$var} = " autocomplete=\"off\" ";
    }
    if (exists $payutils::autocomplete{'form'}) {
      %payutils::autocomplete = ('form'," autocomplete=\"off\" ");
    }
  }

  if (exists $payutils::feature{'readonly'}) {
    my @array = split('\|',$payutils::feature{'readonly'});
    foreach my $var (@array) {
      $payutils::readonly{$var} = " readonly=\"readonly\" ";
    }
  }
  if (exists $payutils::feature{'displayonly'}) {
    my @array = split('\|',$payutils::feature{'displayonly'});
    foreach my $var (@array) {
      $payutils::displayonly{$var} = "1";
    }
  }

  if ($payutils::query{'client'} =~ /^(affiniscape)$/) {
    push (@payutils::nocheck, 'email', 'card-city', 'card-state');
    $payutils::feature{'optionalpay'} .= "|email";
  }
  elsif ($payutils::reseller =~ /^(aaronsin|homesmrt)$/) {
    push (@payutils::nocheck, 'email');
    $payutils::feature{'optionalpay'} .= "|email";
    $payutils::feature{'nocheckpay'} .= "|email";
  }

  my @array = split(/\,/,$fconfig);
  foreach my $entry (@array) {
    my($name,$value) = split(/\=/,$entry);
    $fraud_config{$name} = $value;
  }
  %payutils::fraud_config = %fraud_config;
  $payutils::feature{'cvv'} = $fraud_config{'cvv'};

  if ($payutils::query{'publisher-name'} =~ /^(pnpdev)$/) {
    #$payutils::feature{'exp'} = 1;
  }
  if ($payutils::query{'publisher-name'} =~ /^(instituteo)$/) {
    $payutils::feature{'splitname'} = 1;
  }

  if ($payutils::processor =~ /^(ncb|psl)$/) {
    $payutils::feature{'cvv'} = 1;
  }

  if ($payutils::feature{'onload'} eq "clear") {
    $payutils::autoload = "onLoad=\"document.forms['pay'].reset()\;\";";
  }
  if ($payutils::query{'paymethod'} eq "swipe") {
    if ($payutils::newswipecode == 1) {
      $payutils::autoload = "onLoad=\"document.pay.card_number.focus();\"";
    }
    else {
      $payutils::autoload = "onLoad=\"document.keyswipe1.in1.focus();\"";
    }
  }
  elsif (($payutils::query{'keyswipe'} eq "secure") || ($payutils::feature{'keyswipe'} eq "secure")) {
    $payutils::autoload = "onLoad=\"document.pay.card_number.focus();\"";
  }

  if ($ENV{'SERVER_NAME'} =~ /pay\-gate/) {
    $payutils::domain = "pay\-gate.com";
    $payutils::company = "World Wide Merchant Services";
  }
  elsif ($ENV{'SERVER_NAME'} =~ /pdsadmin/) {
    $payutils::domain = "www.pdsadmin.com";
    $payutils::company = "Payment Data Systems";
  }
  elsif ($ENV{'SERVER_NAME'} =~ /webassist/) {
    $payutils::domain = "webassist.com";
    $payutils::company = "WebAssist";
  }
  elsif ($ENV{'SERVER_NAME'} =~ /singularbillpay/) {
    $payutils::domain = "singularbillpay.com";
    $payutils::company = "Singular Bill Pay";
  }
  elsif ($payutils::company eq "") {
    $payutils::domain = "plugnpay.com";
    $payutils::company = "Plug \& Pay Technologies, Inc.";
  }

#  if ($payutils::query{'pass'} != 1) {
#    $payutils::query{'attempts'}++;
#  }
  if ($ENV{'HTTP_REFERER'} !~ /plugnpay\.com/) {
    $payutils::query{'referrer'} = $ENV{'HTTP_REFERER'};
  }

  #  $path_wallet = "https://$payutils::query{'Ecom_Subscriber_Username'}:$payutils::query{'Ecom_Subscriber_Password'}\@pay1.plugnpay.com/ewallet/wallet.cgi";
  $payutils::path_wallet = "https://pay1.plugnpay.com/ewallet/wallet.cgi";
  $payutils::path_wallet2 = "https://pay1.plugnpay.com/ewallet/wallet_table.cgi";

  #if ($payutils::query{'client'} =~ /courtpay/i) {
  #  $payutils::query{'acct_code4'} = "$payutils::query{'x_defendantfirstname'} $payutils::query{'x_defendantlastname'}";
  #}

  if (($payutils::query{'client'} =~ /coldfusion/i) || ($payutils::query{'CLIENT'} =~ /coldfusion/i)) {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
    my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
    open (DEBUG,'>>',"/home/p/pay1/database/debug/payutils_coldfusion.txt");
    print DEBUG "DATE:$now, UN:$payutils::query{'publisher-name'}, SN:$ENV{'SCRIPT_NAME'}, IP:$remoteIP\n";
    close(DEBUG);

    %payutils::query = &miscutils::input_cold_fusion(%payutils::query);
  }

  if (($payutils::query{'publisher-name'} ne "$testun") || ($payutils::query{'publisher-name'} eq "")) {
    my $message = "The transaction cannot be processed for the following reason:\n";
    $message .= "Invalid Account\n";
    print "Content-Type: text/html\n\n";
    print response_page("$message");
    exit;
  }

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
  if ($payutils::query{'orderID'} eq "") {
    $payutils::orderID = sprintf("%04d%02d%02d%02d%02d%02d%05d",$year+1900,$mon+1,$mday,$hour,$min,$sec,$$);
  }
  else {
    $payutils::orderID = $payutils::query{'orderID'};
  }


  $payutils::query{'ipaddress'} = $remoteIP;

  if ($payutils::query{'card-allowed'} =~ /checks/i) {
    #    $online_checks = "yes";
  }

  if ((length($payutils::query{'defaultcountry'}) == 2) && (length($payutils::query{'card-country'}) < 2)) {
    if ($payutils::query{'defaultcountry'} ne "  ") {
      $payutils::query{'card-country'} = $payutils::query{'defaultcountry'};
    }
  }
  elsif (length($payutils::query{'card-country'}) < 2) {
    $payutils::query{'card-country'} = "US";
  }

  if ((length($payutils::query{'defaultcountry'}) == 2) && (length($payutils::query{'country'}) < 2)) {
    if ($payutils::query{'defaultcountry'} ne "  ") {
      $payutils::query{'country'} = $payutils::query{'defaultcountry'};
    }
  }
  elsif (length($payutils::query{'country'}) < 2) {
    $payutils::query{'country'} = "US";
  }

  if (length($payutils::query{'company'}) > 2) {
    $payutils::query{'card-company'} = $payutils::query{'company'};
  }

  if ($payutils::feature{'unpw_maxlength'} ne "") {
    $payutils::feature{'unpw_maxlength'} =~ s/[^0-9]//g;
    $payutils::unpw_maxlength = $payutils::feature{'unpw_maxlength'};
  }
  if ($payutils::feature{'unpw_minlength'} ne "") {
    $payutils::feature{'unpw_minlength'} =~ s/[^0-9]//g;
    $payutils::unpw_minlength = $payutils::feature{'unpw_minlength'};
  }

  if ($payutils::unpw_minlength < 4) {
    $payutils::unpw_minlength = 4;
  }

  if ($payutils::unpw_maxlength eq "") {
    $payutils::unpw_maxlength = 8;
  }

  if ($payutils::query{'card-allowed'} eq "") {
    $payutils::query{'card-allowed'} = "Visa,Mastercard";
  }

  # 03/19/11 - turn off 'splitname' when 'keyswipe' option is used, to prevent name fill-in requirement errors
  if (($payutils::query{'keyswipe'} =~ /(yes|secure)/) || ($payutils::feature{'keyswipe'} =~ /(yes|secure)/)) {
    $payutils::feature{'splitname'} = 0;
  }

  # 01/26/12 - turn off 'keyswipe' when 'nocardexplist' option is used, to prevent data fill-in errors with swiped cards
  if ($payutils::query{'nocardexplist'} eq "yes") {
    $payutils::query{'keyswipe'} = "";
    $payutils::feature{'keyswipe'} = "";
  }

  if ($payutils::feature{'splitname'} == 1) {
    $payutils::query{'card-name'} = $payutils::query{'card-fname'} . " " . $payutils::query{'card-lname'};
  }

#  # set 'shipsame' to 'yes'; when no shipping address is given
#  if (($payutils::query{'shipsame'} ne "yes") && (($payutils::query{'shipname'} eq "") || ($payutils::query{'address1'} eq "") || ($payutils::query{'city'} eq "") || ($payutils::query{'state'} eq "") || ($payutils::query{'zip'} eq "") || ($payutils::query{'country'} eq ""))) {
#    $payutils::query{'shipsame'} = "yes";
#  }

  if ($payutils::query{'shipsame'} eq "yes") {
    $payutils::query{'shipname'} = $payutils::query{'card-name'};
    $payutils::query{'shipcompany'} = $payutils::query{'card-company'};
    $payutils::query{'address1'} = $payutils::query{'card-address1'};
    $payutils::query{'address2'} = $payutils::query{'card-address2'};
    $payutils::query{'city'} = $payutils::query{'card-city'};
    $payutils::query{'state'} = $payutils::query{'card-state'};
    $payutils::query{'province'} = $payutils::query{'card-prov'};
    $payutils::query{'zip'} = $payutils::query{'card-zip'};
    $payutils::query{'country'} = $payutils::query{'card-country'};
    $payutils::query{'shipemail'} = $payutils::query{'email'};
    $payutils::query{'shipphone'} = $payutils::query{'phone'};
    $payutils::query{'shipfax'} = $payutils::query{'fax'};
  }

  $payutils::query{'publisher-name'} =~ s/[^0-9a-zA-Z]//g;

  $payutils::query{'uname'} =~  s/[^0-9a-zA-Z]//g;
  $payutils::query{'passwrd1'} =~  s/[^0-9a-zA-Z]//g;
  $payutils::query{'passwrd2'} =~  s/[^0-9a-zA-Z]//g;

  $payutils::path_zipcode = "$payutils::path_web/payment/zipdb";

  # Email Address Filter
  $payutils::query{'email'} =~ s/\;/\,/g;
  $payutils::query{'email'} =~ s/[^_0-9a-zA-Z\-\@\.\,]//g;
  $payutils::query{'email'} =~ s/,(com|org|net|mil|gov|tv|cc|ws|info|biz|bz|edu)$/\.$1/;

  # Check Filters
  $payutils::query{'routingnum'} =~ s/[^0-9]//g;
  $payutils::query{'accountnum'} =~ s/[^0-9]//g;
  $payutils::query{'checknum'} =~ s/[^0-9]//g;

  # Card Number Filter
  ## 11/24/2008 - exclude peterluger card- type from card-number numeric filtering - Copied over from peterlugerpay.cgi
  if ($payutils::query{'card-type'} ne "peterluger") {
    $payutils::query{'card-number'} =~ s/[^0-9]//g;
  }
  #$payutils::query{'card-number'} =~ s/[^0-9]//g;

  # MP Gift Card Filter
  if (exists $payutils::query{'mpgiftcard'}) {
    my $stuff = "";
    $payutils::query{'mpgiftcard'} =~ s/[^0-9\-]//g;
    ($payutils::query{'mpgiftcard'},$stuff) = split('\-',$payutils::query{'mpgiftcard'});
  }

  # Card Amount Filters
  $payutils::query{'card-amount'} =~ s/[^0-9\.]//g;

  if (exists $payutils::query{'currency'}) {
    $payutils::query{'currency'} =~ tr/A-Z/a-z/;
    $payutils::query{'currency'} =~ s/[^a-z]//g;
    $payutils::query{'currency'} = substr($payutils::query{'currency'},0,3);
  }

  # Card Exp Date Filter
  if (($payutils::query{'card-exp'} ne "") && ($payutils::query{'month-exp'} eq "") && ($payutils::query{'year-exp'} eq "")) {
    $payutils::query{'month-exp'} = substr($payutils::query{'card-exp'},0,2);
    $payutils::query{'year-exp'} = substr($payutils::query{'card-exp'},-2,2);
  }

  # CVV Filter
  $payutils::query{'card-cvv'} =~ s/[^0-9]//g;
  $payutils::query{'card-cvv'} = substr($payutils::query{'card-cvv'},0,4);

  # Misc. Filters
  $payutils::query{'card-address1'} = substr($payutils::query{'card-address1'},0,39);
  $payutils::query{'card-address2'} = substr($payutils::query{'card-address2'},0,39);
  $payutils::query{'card-zip'} =~ s/[^0-9A-Za-z\ \-]//g;

  if (exists $payutils::query{'phone'}) {
    $payutils::query{'phone'} =~ s/[^0-9]//g;
    if (substr($payutils::query{'phone'},0,1) == 1) {
      $payutils::query{'phone'} = substr($payutils::query{'phone'},1);
    }
  }

  if ($payutils::query{'paymethod'} =~ /^(telecheck|onlinecheck|check)$/) {
    $payutils::usonly = "yes";

    if ($payutils::chkprocessor =~ /^(paymentdata|alliancesp|echo|testprocessor|testprocessorach)$/) {
      # force split ame for ACH/eCheck processing, when using select ACH processors
      $payutils::feature{'splitname'} = 1;

      # 07/06/11 - Force keyswipe option off, if enabled.
      #          - To prevent verification problems, due to splitname/keyswipe conflict
      $payutils::query{'keyswipe'} = "";
      $payutils::feature{'keyswipe'} = "";
    }
  }

  if (($payutils::query{'mpgiftcard'} ne "") && ($payutils::query{'card-number'} eq "")) {
     $payutils::query{'paymethod'} = "mpgiftcard";
  }


  $payutils::goodcolor = "#2020a0";
  $payutils::backcolor = "#ffffff";
  $payutils::badcolor = "#ff0000";
  $payutils::badcolortxt = "RED";
  $payutils::linkcolor = $payutils::goodcolor;
  $payutils::textcolor = $payutils::goodcolor;
  $payutils::alinkcolor = "#187f0a";
  $payutils::vlinkcolor = "#0b1f48";
  $payutils::fontface = "Arial,Helvetica,Univers,Zurich BT";
  $payutils::itemrow = "#d0d0d0";
  $payutils::titlecolor = $payutils::backcolor;
  $payutils::titlebackcolor = $payutils::goodcolor;

  foreach my $entry (keys %payutils::feature) {
    if ($entry =~ /^goodcolor$/) {
      $payutils::goodcolor = $payutils::feature{$entry};
    }
    elsif ($entry =~ /^backcolor$/) {
      $payutils::backcolor = $payutils::feature{$entry};
    }
    elsif ($entry =~ /^badcolor$/) {
      $payutils::badcolor = $payutils::feature{$entry};
    }
    elsif ($entry =~ /^badcolortxt$/) {
      $payutils::badcolortxt = $payutils::feature{$entry};
    }
    elsif ($entry =~ /^linkcolor$/) {
      $payutils::linkcolor = $payutils::feature{$entry};
    }
    elsif ($entry =~ /^textcolor$/) {
      $payutils::textcolor = $payutils::feature{$entry};
    }
    elsif ($entry =~ /^alinkcolor$/) {
      $payutils::alinkcolor = $payutils::feature{$entry};
    }
    elsif ($entry =~ /^vlinkcolor$/) {
      $payutils::vlinkcolor = $payutils::feature{$entry};
    }
    elsif ($entry =~ /^titlecolor$/) {
      $payutils::titlecolor = $payutils::feature{$entry};
    }
    elsif ($entry =~ /^titlebackcolor$/) {
      $payutils::titlebackcolor = $payutils::feature{$entry};
    }
    elsif ($entry =~ /^fontface$/) {
      $payutils::fontface = $payutils::feature{$entry};
    }
    elsif ($entry =~ /^itemrow$/) {
      $payutils::itemrow = $payutils::feature{$entry};
    }
    elsif ($entry =~ /^backimage$/) {
      $payutils::backimage = $payutils::feature{$entry};
    }
    elsif ($entry =~ /^image-link$/) {
      $payutils::query{'image-link'} = $payutils::feature{$entry};
    }
    elsif ($entry =~ /^image-placement$/) {
      $payutils::query{'image-placement'} = $payutils::feature{$entry};
    }
  }

  @payutils::standardfields = ('card-name','card-address1','card-address2','card-city','card-state','card-zip','card-country',
                     'card-number','card-exp','card-type','card-cvv','phone','fax','email','uname','passwrd1','passwrd2',
                     'shipname','address1','address2','city','state','zip','country','card-prov','province',
                     'cookie_pw','ssnum','card-company','title','pinnumber','web900-pin'
                    );

  ### Added back in to support custom scripts  DCP 20081121
  %payutils::countries = %constants::countries;
  %payutils::USstates = %constants::USstates;
  %payutils::USterritories = %constants::USterritories;
  %payutils::CNprovinces = %constants::CNprovinces;
  %payutils::USCNprov = %constants::USCNprov;

  %payutils::UPSmethods = ("ALL","All Servies","DOM","All Domestic Services","CAN","All Canadian Services","INT","All International Services",
                 "1DM","Next Day Air Early AM","1DMRS","Next Day Air Early AM Residential","1DA","Next Day Air",
                 "1DARS","Next Day Air Residential","1DP","Next Day Air Saver","1DPRS","Next Day Air Saver Residential",
                 "2DM","2nd Day Air A.M.","2DMRS","2nd Day Air A.M. Residential","2DA","2nd Day Air",
                 "2DARS","2nd Day Air Residential","3DS","3 Day Select","3DSRS","3 Day Select Residential",
                 "GND","Ground","GNDRES","Ground Residential","STD","Canada Standard",
                 "CXR","Worldwide Express to Canada","CXP","Worldwide Express Plus to Canada","CXD","Worldwide Expedited to Canada",
                 "XPR","Worldwide Express","XDM","Worldwide Express Plus","XPD","Worldwide Expedited");

  %payutils::Ship_Methods = ("ALL","UPS All Servies","DOM","UPS All Domestic Services","CAN","UPS All Canadian Services","INT","UPS All International Services",
                   "1DM","UPS Next Day Air Early AM","1DMRS","UPS Next Day Air Early AM Residential","1DA","UPS Next Day Air",
                   "1DARS","UPS Next Day Air Residential","1DP","UPS Next Day Air Saver","1DPRS","UPS Next Day Air Saver Residential",
                   "2DM","UPS 2nd Day Air A.M.","2DMRS","UPS 2nd Day Air A.M. Residential","2DA","UPS 2nd Day Air",
                   "2DARS","UPS 2nd Day Air Residential","3DS","UPS 3 Day Select","3DSRS","UPS 3 Day Select Residential",
                   "GND","UPS Ground","GNDRES","UPS Ground Residential","STD","UPS Canada Standard",
                   "CXR","UPS Worldwide Express to Canada","CXP","UPS Worldwide Express Plus to Canada","CXD","UPS Worldwide Expedited to Canada",
                   "XPR","UPS Worldwide Express","XDM","UPS Worldwide Express Plus","XPD","UPS Worldwide Expedited",
                   "Express","U.S. Postal Service Express","Priority","U.S. Postal Service Priority","Parcel","U.S. Postal Service Parcel",
                   "Priority Courier","Canada Post Priority Courier","Expedited","Canada Post Expedited","Regular","Canada Post Regular",
                   "Purolator International","Canada Post Purolator International","Xpresspost USA","Canada Post Xpresspost USA",
                   "Expedited US Commercial","Canada Post Expedited US Commercial","Xpresspost International","Canada Post Xpresspost International",
                   "Small Packets Air","Canada Post Small Packets Air","Parcel Surface","Canada Post Parcel Surface",
                   "Small Packets Surface","Canada Post Parcel Surface","14","UPS Next Day Air Early AM",
                   "01","UPS Next Day Air","13","UPS Next Day Air Saver","59","UPS 2nd Day Air AM","02",
                   "UPS 2nd Day Air","12","UPS 3 Day Select","03","UPS Ground","11","UPS Standard","07",
                   "UPS Worldwide Express","54","UPS Worldwide Express Plus","08","UPS Worldwide Expedited",
                   "65","UPS Saver");


  #%payutils::lang_titles = %language::lang_titles;

  # Languange Setting: # '0' = English # '1' = Spanish # '2' = French # '3' = Dutch
  %payutils::lang_hash = ('en','0','sp','1','fr','2','es','1','nl','3');

  # check and enforce languange setting
  $payutils::query{'lang'} =~ tr/A-Z/a-z/;
  $payutils::query{'lang'} =~ s/[^a-z]//;
  $payutils::lang = $payutils::lang_hash{$payutils::query{'lang'}};
  if ($payutils::lang <= 0) {
    $payutils::lang = 0; # assume English by default
  }
  ## Look into changing from 2D hash to 1D as 2D is no longer needed.
  foreach my $key (keys %language::lang_titles) {
    $payutils::lang_titles{$key}[$payutils::lang] = $language::lang_titles{$key}[$payutils::lang];
  }
  ###
  if ($payutils::query{'card-allowed'} =~ /Discover/i) {
    $payutils::lang_titles{'required'}[$payutils::lang] .= "\/Discover";
  }
  if ($payutils::query{'card-allowed'} =~ /Amex/i) {
    $payutils::lang_titles{'required'}[$payutils::lang] .= "\/Amex";
  }
  if ($payutils::processor eq "ncb") {
    $payutils::lang_titles{'required'}[$payutils::lang] .= "\/and some KeyCards";
  }
  $payutils::lang_titles{'required'}[$payutils::lang] .= "\.";

  my $templateContent = PlugNPay::Legacy::PayUtils::PayTemplate::loadTemplate({
    gatewayAccount => $payutils::query{'merchant'} || $payutils::query{'publisher-name'} || $payutils::query{'publisher_name'},
    reseller => $payutils::reseller,
    cobrand => $payutils::feature{'cobrand'},
    language => $payutils::query{'lang'} || '',
    client => $payutils::query{'client'},
    requestedTemplate => $payutils::query{'paytemplate'}
  });

  if ($templateContent ne "") {
    my (%tempflag,$tempflag);
    foreach my $line (split("\n",$templateContent)) {
      if ($line =~ /<(doctype|language|head|top|tail|head_mobile|top_mobile|tail_mobile|table|submtpg1|submtpg2|inputcheck|shipping|displayamt|body_[a-z0-9]+)>/i) {
        if ($tempflag eq "") {
          $tempflag = $1;
          $tempflag =~ tr/A-Z/a-z/;
          next;
        }
      }
      if ($line =~ /<\/$tempflag>/i) {
        $tempflag = "";
        next;
      }
      if ($tempflag eq "language") {
        my ($key,$value) = split('\t');
        $payutils::lang_titles{$key}[$payutils::lang] = $value;
      }
      elsif ($tempflag eq "table") {
        my ($key,$value) = split('\t');
        $payutils::tableprop{$key} = $value;
      }
      elsif ($tempflag =~ /^(doctype|head|top|tail|head_mobile|top_mobile|tail_mobile|submtpg1|submtpg2|inputcheck|shipping|displayamt|body_[a-z0-9]+)$/) {
        $payutils::template{$tempflag} .= &parse_template($line) . "\n";
      }
    }
  }

  $payutils::lang_titles{'privacy'}[$payutils::lang] =~ s/\[pnp_company\]/$payutils::company/g;
  $payutils::lang_titles{'re_enter2'}[$payutils::lang] =~ s/\[pnp_badcolor\]/$payutils::badcolor/g;
  $payutils::lang_titles{'re_enter2'}[$payutils::lang] =~ s/\[pnp_badcolortxt\]/$payutils::badcolortxt/g;
  $payutils::lang_titles{'reqinfo'}[$payutils::lang] =~ s/\[pnp_badcolor\]/$payutils::badcolor/g;
  $payutils::lang_titles{'reqinfo'}[$payutils::lang] =~ s/\[pnp_badcolortxt\]/$payutils::badcolortxt/g;
  $payutils::lang_titles{'passwrderr1'}[$payutils::lang] =~ s/\[pnp_unpw_minlength\]/$payutils::unpw_minlength/g;

  if (($ENV{'HTTP_COOKIE'} ne "")) {
    my (@cookies) = split('\;',$ENV{'HTTP_COOKIE'});
    foreach my $var (@cookies) {
      my ($name,$value) = split('=',$var);
      $name =~ s/ //g;
      $payutils::cookie{$name} = $value;
      if (($name =~ /^pnpaff_$payutils::query{'publisher-name'}$/) && ($payutils::query{'acct_code'} eq "")) {
        $payutils::query{'acct_code'} = $value;
      }
      if ($name =~ /pnpaffiliate/) {
      }
    }
  }

  if (($payutils::query{'acct_code'} eq "") && ($payutils::cookie{'pnpaffiliate'} ne "")) {
    $payutils::query{'acct_code'} = "$payutils::cookie{'pnpaffiliate'}";
  }

  if (($payutils::query{'client'} eq "softcart") && ($payutils::query{'pass'} != 1)) {
    &softcart_remote;
  }
  elsif ($payutils::query{'client'} eq "cart32") {
    &cart32();
  }
  elsif (($payutils::query{'client'} =~ /update/i) || ($payutils::query{'wfunction'} =~ /update/i)) {
    &update_record();
    exit;
  }
  elsif ($payutils::query{'client'} eq "Change") {
    &update_express_record();
    exit;
  }
  if ($payutils::query{'wfunction'} eq "passremind") {
    print forgot_password();
    exit
  }

  if (($payutils::query{'pass'} == 1) && ($payutils::query{'bcommonname'} eq "")) {
    $payutils::skip_express = "yes";
  }

  if (($payutils::cookie{'pnpid'} ne "") && ($payutils::query{'wfunction'} ne "bypass")) {
    &customer_record();
  }

  if ($payutils::query{'exclude-state'} ne "") {
    if ($payutils::query{'exclude-state'} =~ /\,/) {
      my @excludearray = split(/\,/,$payutils::query{'exclude-state'});
      foreach my $excludevalue (@excludearray) {
        if (exists $constants::USstates{$excludevalue}) {
          delete $constants::USstates{$excludevalue};
        }
      }
    }
    else {
      if (exists $constants::USstates{$payutils::query{'exclude-state'}}) {
        delete $constants::USstates{$payutils::query{'exclude-state'}};
      }
    }
  }

  if ($payutils::upsellflag == 1) {  #Begin Upsell Routine
    my ($j,@searchterm,$itemstring,%match,@scores);
    for (my $i=1; $i<=999; $i++) {
      if ($payutils::query{"quantity$i"} > 0) {
        $searchterm[$j] = $payutils::query{"item$i"};
        $itemstring .= $searchterm[$j];
        $j++;
      }
    }
    my $dbh_upsell = &miscutils::dbhconnect('merchantdata');
    foreach my $searchitem (@searchterm) {
      my ($sku,$upsku,$template,$upsellid);
      my $sth = $dbh_upsell->prepare(q{
          SELECT sku,upsku,template,upsellid
          FROM upsell
          WHERE LOWER(username) LIKE LOWER(?)
        }) or die "Can't prepare: $DBI::errstr";
      $sth->execute($payutils::query{'publisher-name'}) or die "Can't execute: $DBI::errstr";
      while (my ($sku,$upsku,$template,$upsellid) = $sth->fetchrow) {
        my $score = $sku;
        $score =~ s/[\W]//g;
        $score = length($score);
        my $dbterm = $sku;
        $dbterm =~ /(.*?)\*(.*?)/g;
        my ($trm1,$trm2) = ($1,$2);
        $dbterm =~ s/\*//g;

        if (((($trm1) && ($searchitem =~ /$trm1[^\W]*$trm2/)) || ($searchitem =~ /$dbterm/)) && ($itemstring !~ /$upsku/)) {
          push (@scores,$score);
          $match{$score} = "$sku\t$upsku\t$template\t$upsellid";
        }
      }
      $sth->finish;
    }
    $dbh_upsell->disconnect;
    my @sorted_scores = sort { $a <=> $b } @scores;
    my $key = pop (@sorted_scores);
    if ($match{$key} ne "") {
      my ($sku,$upsku,$template,$upsellid) = split('\t',$match{$key});
      $payutils::upsell_path = "$payutils::path_web/admin/upsell/deployed/$payutils::query{'publisher-name'}\_$template";

      if (($payutils::cookie{"$payutils::query{'publisher-name'}$upsku$sku"} ne "1")
           && (-e $payutils::upsell_path) && ($payutils::cookie{"$payutils::query{'publisher-name'}upsell"} ne "1")) {
        $upsku =~ s/(\W)/'%' . unpack("H2",$1)/ge;
        my $pairs = "publisher-name=$payutils::query{'publisher-name'}\&upsku=$upsku\&sku=$sku\&orderID=$payutils::orderID\&upsellid=$upsellid";
        if ($payutils::query{'debugupsell'} eq "yes") {
          $pairs .= "\&debugupsell=yes";
        }
        $payutils::upsell_url = "https://pay1.plugnpay.com/upsell/upsell.cgi?$pairs";
        $payutils::upsell = "onLoad=\"upsell();\"";
        #last;
      }
    }
  }  ### End Upsell Routine


  my %currencyUSDSYM = ('aud','A$','ang','&#402;','awg','&#402;','cad','C$','eur','&#8364;','gbp','&#163;','jpy','&#165;','usd','$','frf','&#8355;','chf','CHF','jmd','JMD');

  if ($payutils::processor eq "ncb") {
    $currencyUSDSYM{'usd'} = "USD \$";
  }

  # safeguard transactions for allowed currency types only
  if ($payutils::currency eq "") {
    $payutils::currency = "usd";
  }

  if ($payutils::query{'currency'} eq "") {
    $payutils::query{'currency'} = $payutils::currency;
  }

  # enforce allowed currency types only
  if (($payutils::processor !~ /^(pago|atlantic|planetpay|globalc|globalctf|surefire|ncb|testprocessor|wirecard)$/)
    && ($payutils::currency !~ /$payutils::query{'currency'}/i) && ($payutils::feature{'convertcurrency'} !~ /$payutils::query{'currency'}/i)) {
    # error if transaction is not an allowed currency type & is not from from a processer with allows multi-currency transactions
    $payutils::error = 1;
    $payutils::error{'dataentry'} .= "$payutils::lang_titles{'currencyerr1'}[$payutils::lang] $payutils::currency:$payutils::query{'currency'}:";
    $payutils::errvar .= "currency\|";
  }

  # if it's safe to proceed, look up correct currency symbol for currency type selected
  $payutils::query{'currency_symbol'} = $currencyUSDSYM{"$payutils::query{'currency'}"};

  if ($payutils::query{'currency_symbol'} eq "") {
    $payutils::query{'currency_symbol'} = "\$";
  }

  if ($payutils::query{'show_currency'} eq "yes") {
    $payutils::query{'currency_symbol'} = $payutils::query{'currency'};
  }

  return [], $type;
}

sub customer_record {
  my ($sfname,$slname,$enccardnumber,$length,$username,$password);

  my $dbh_init = &miscutils::dbhconnect('wallet');

  my $sth = $dbh_init->prepare(q{
      SELECT b.name,s.email,s.username,s.password
      FROM subscriber s, billing b
      WHERE s.walletid=?
      AND b.walletid=?
    }) or die "Can't prepare: $DBI::errstr";
  $sth->execute("$payutils::cookie{'pnpid'}", "$payutils::cookie{'pnpid'}") or die "Can't execute: $DBI::errstr";
  ($payutils::bname,$payutils::query{'semail'},$username,$password) = $sth->fetchrow;
  $sth->finish;

  if (($payutils::query{'cookie_pw'} ne "") && ($payutils::query{'cookie_pw'} eq $password)) {
    my $sth = $dbh_init->prepare(q{
        SELECT name,addr1,addr2,addr3,city,state,zip,country,cardtype,cardnumber,enccardnumber,length,cardexp
        FROM billing
        WHERE walletid=?
      }) or die "Can't prepare: $DBI::errstr";
    $sth->execute("$payutils::cookie{'pnpid'}") or die "Can't execute: $DBI::errstr";
    ($payutils::query{'card-name'},$payutils::query{'card-address1'},$payutils::query{'card-address2'},$payutils::query{'card-address3'},$payutils::query{'card-city'},$payutils::query{'card-state'},$payutils::query{'card-zip'},
        $payutils::query{'card-country'},$payutils::query{'card-type'},$payutils::query{'card-number'},$enccardnumber,$length,$payutils::query{'card-exp'}) = $sth->fetchrow;
    $sth->finish;


    my $sth2 = $dbh_init->prepare(q{
        SELECT sfname,slname,shipaddr1,shipaddr2,shipaddr3,shipcity,shipstate,shipzip,shipcountry,shipphone,shipemail
        FROM shipping
        WHERE walletid=?
      }) or die "Can't prepare: $DBI::errstr";
    $sth2->execute("$payutils::cookie{'pnpid'}") or die "Can't execute: $DBI::errstr";
    ($sfname,$slname,$payutils::query{'address1'},$payutils::query{'address2'},$payutils::query{'address3'},$payutils::query{'city'},
        $payutils::query{'state'},$payutils::query{'zip'},$payutils::query{'country'},$payutils::query{'phone'},$payutils::query{'email'}) = $sth2->fetchrow;
    $sth2->finish;


    $payutils::query{'shipname'} = "$sfname $slname";

    if (($payutils::query{'client'} !~ /update/i) && ($payutils::query{'wfunction'} !~ /update/i)) {
      $payutils::query{'card-number'} = &rsautils::rsa_decrypt_file($enccardnumber,$length,"print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");
    }

    $payutils::query{'year-exp'} = substr($payutils::query{'card-exp'},3,2);
    $payutils::query{'month-exp'} = substr($payutils::query{'card-exp'},0,2);
  }

  $dbh_init->disconnect;
}


sub sort_hash {
  my $x = shift;
  my %array=%$x;
  sort { $array{$a} cmp $array{$b}; } keys %array;
}


sub shopcart {
  my ($roptionflag);
  foreach my $key (keys %payutils::query) {
    if ($key =~ /roption\d?/) {
      $roptionflag += $payutils::query{$key};
    }
  }

  if (($payutils::query{'roption'} ne "") && ($payutils::query{'pass'} ne "1" )) {
    my $ii = $payutils::query{'roption'};
    if ($payutils::query{'rquantity'} ne "") {
      $payutils::query{"quantity$ii"} = $payutils::query{'rquantity'};
    }
    else {
      $payutils::query{"quantity$ii"} = 1;
    }
  }
  elsif (($roptionflag > 0) && ($payutils::query{'pass'} ne "1")) {
    for (my $i=1; $i<=25; $i++) {
      if ($payutils::query{"roption$i"} > 0) {
        my $ii = $payutils::query{"roption$i"};
        if ($payutils::query{'rquantity'} ne "") {
          $payutils::query{"quantity$ii"} = $payutils::query{'rquantity'};
        }
        else {
          $payutils::query{"quantity$ii"} = 1;
        }
      }
    }
  }

  my $j = 1;
  my $subtotal = 0;
  my $taxsubtotal = 0;
  my $totalcnt = 0;
  my $totalwgt = 0;

  my ($dbh);
  if ($payutils::fraud_config{'chkprice'} == 1) {
    $dbh = &miscutils::dbhconnect("fraudtrack");
    open (FRAUD,'>>',"/home/p/pay1/database/debug/fraud_debug_chkprice.txt");
  }

  for (my $i=1; $i<=2000; $i++) {
    if ($payutils::query{"quantity$i"} > 0) {

      if ($payutils::fraud_config{'chkprice'} == 1) {
        print FRAUD "PAYUTILS  UN:$payutils::query{'publisher-name'}, OID:$payutils::query{'orderID'}, EC:$payutils::query{'easycart'}, ";
        my $item = $payutils::query{"item$i"};
        my $sth = $dbh->prepare(q{
            SELECT cost
            FROM costdata
            WHERE entry=?
            AND username=?
          }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%payutils::query);
        $sth->execute("$item", "$payutils::query{'publisher-name'}") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%payutils::query);
        my ($price) = $sth->fetchrow;
        $sth->finish;
        $price =~ s/[^0-9\.]//g;
        print FRAUD "$item:$price:$payutils::query{\"cost$i\"}, ";
        if ($price > $payutils::query{"cost$i"}) {
          $payutils::query{"cost$i"} = $price;
        }
      }

      $payutils::item[$j] = $payutils::query{"item$i"};
      $payutils::description[$j] = $payutils::query{"description$i"};
      $payutils::quantity[$j] = $payutils::query{"quantity$i"};
      $payutils::quantity[$j] =~ s/[^0-9\.]//g;
      $payutils::cost[$j] = $payutils::query{"cost$i"};
      $payutils::cost[$j] =~ s/[^0-9\.\-]//g;
      $payutils::weight[$j] = $payutils::query{"weight$i"};
      $payutils::max = $j;
      $payutils::ext[$j] = ($payutils::cost[$j] * $payutils::quantity[$j]);
      $payutils::subtotal += ($payutils::quantity[$j] * $payutils::cost[$j]);
      $payutils::query{"subtotal"} = &Round($payutils::subtotal);

      # put taxable field into array for later use
      $payutils::taxable[$j] = $payutils::query{"taxable$i"};

      if ($payutils::query{"taxable$i"} !~ /N/i) {
        $payutils::taxsubtotal += ($payutils::quantity[$j] * $payutils::cost[$j]);
      }

      if ($payutils::query{"fulfillmap$i"} ne "") {
        $payutils::query{"fulfillflg"} = "Y";
      }

      if (($payutils::feature{'digdwnld'} =~ /^http/i) && ($payutils::item[$j] =~ /\.(zip|hqx|bin|sea|pdf|doc|mp3|xls|ppt|txt|exe|htm|html|gif)$/i)) {
        $payutils::query{'success-link'} = "$payutils::feature{'digdwnld'}";
      }

      $payutils::totalcnt += $payutils::quantity[$j];
      $payutils::totalwgt += ($payutils::quantity[$j] * $payutils::weight[$j]);
      $payutils::query{'test_wgt'} = $payutils::totalwgt;

      if (($payutils::query{'roption'} eq "$i") && ($payutils::query{'pass'} ne "1" )) {
        $payutils::query{'plan'} = $payutils::query{"plan$i"};
        $payutils::query{'billcycle'} = $payutils::query{"billcycle$i"};
        $payutils::query{'recurring-fee'} = $payutils::query{"recurring-fee$i"};

        $payutils::query{'recurringfee'} = $payutils::query{"recurringfee$i"};
        $payutils::query{'balance'} = $payutils::query{"balance$i"};
      }
      $j++;
    }
  }

  if ($payutils::fraud_config{'chkprice'} == 1) {
    $dbh->disconnect;
    print FRAUD "\n";
    close (FRAUD);
  }

  if (($payutils::digprodflg == 1) && ($payutils::hrdprodflg != 1)) {
    $payutils::digonlyflg = 1;
  }
}


###### Start Page 1 Table Pay Page
#  pay_screen1_head
#  pay_screen1_table
#  pay_screen1_badcard
#  pay_screen1_body
#  pay_screen1_pairs
#  pay_screen1_tail
#  un_pw
#  input_check
#


sub pay_screen1_head {
  my $output = '';

  if ($payutils::template{'doctype'} ne "") {
    $output .= "$payutils::template{'doctype'}\n";
  }
  else {
    $output .= "<!DOCTYPE html>\n";
  }
  if (($payutils::query{'client'} eq "rectrac") && ($payutils::query{'publisher-name'} =~ /^(pnpdemo2|scotttest|demoacct|demoacct2)$/)) {
    $output .= "<!-- saved from url=(0040)http://pay1.plugnpay.com/payment/pay.cgi -->\n";
  }

  if (($payutils::query{'amexlev2'} == 1) && ($payutils::query{'card-type'} eq "AMEX")) {
    if ($payutils::autoload ne "") {
      chop $payutils::autoload;
      $payutils::autoload .= " \$('.amexlev2').css('visibility','visible');\$('.amexlev2').css('display','table-row');\"";
    }
    else {
      $payutils::autoload = "onLoad=\"\$('.amexlev2').css('visibility','visible');\$('.amexlev2').css('display','table-row');\"";
    }
  }

  $output .= "<html>\n";
  $output .= "<head>\n";
  $output .= "<title>Payment Screen</title> \n";

  $output .= "<style type=\"text/css\">\n";
  $output .= "<!--\n";
  $output .= "th { font-family: $payutils::fontface; font-size: 10pt; color: $payutils::goodcolor }\n";
  $output .= "td { font-family: $payutils::fontface; font-size: 9pt; color: $payutils::goodcolor }\n";
  $output .= ".badcolor { color: $payutils::badcolor }\n";
  $output .= ".goodcolor { color: $payutils::goodcolor }\n";
  $output .= ".larger { font-size: 12pt }\n";
  $output .= ".smaller { font-size: 9pt }\n";
  $output .= ".short { font-size: 8% }\n";
  $output .= ".itemscolor { background-color: $payutils::titlebackcolor; color: $payutils::titlecolor }\n";
  $output .= ".itemrows { background-color: $payutils::itemrow }\n";
  $output .= ".info { position: static }\n";
  $output .= "#tail { position: static }\n";
  $output .= "-->\n";
  $output .= "</style>\n";

  # Generate CSRF Token
  my $csrfToken = new PlugNPay::Security::CSRFToken()->getToken();
  $output .= "<meta name=\"request-token\" content=\"$csrfToken\">\n";

  # Genearte API REST Session ID
  my $apiRestSession = new PlugNPay::API::REST::Session();
  my $domain = 'https://' . $ENV{'HTTP_HOST'};
  $apiRestSession->setValidDomains([$domain]);
  $apiRestSession->setMultiUse();
  my $apiRestSessionId = $apiRestSession->generateSessionID($payutils::query{'publisher-name'});
  $output .= "<meta name=\"api-rest-session\" content=\"$apiRestSessionId\">\n";

  # Get currency
  my $currency = $payutils::query{'currency_symbol'};
  $output .= "<meta name=\"currency\" content=\"$currency\">\n";

  # COA Settings
  my $coa = new PlugNPay::COA($payutils::query{'publisher-name'});
  if ($coa->getEnabled()) {
    my $isSurcharge = $coa->isSurcharge();
    my $checkCustomerState = $coa->getCheckCustomerState();

    $output .= "<meta name=\"isSurcharge\" content=\"$isSurcharge\">\n";
    $output .= "<meta name=\"checkCustomerState\" content=\"$checkCustomerState\">\n";
  }

  $output .= "\n\n<!--  START OF CUSTOMIZEABLE HEAD SECTION --> \n\n";
  if ($payutils::template{'head'} ne "") {
    $output .= "$payutils::template{'head'}\n";
  }
  $output .= "\n\n<!--  END OF CUSTOMIZEABLE HEAD SECTION --> \n\n";
  if ($payutils::query{'lang'} ne "") {
    $output .= "<meta content=\"text/html; charset=UTF-8\" http-equiv=\"content-type\"/>\n";
  }

  if ($payutils::newswipecode == 1) {
    # new card swipe javascript
    $output .= "<script type=\"text/javascript\" charset=\"utf-8\" src=\"https://$ENV{'SERVER_NAME'}/javascript/jquery.min.js\"></script>\n";
    $output .= "<script type=\"text/javascript\" src=\"https://$ENV{'SERVER_NAME'}/javascript/swipe.js\"></script>\n";
    $output .= "<script type=\"text/javascript\"> \n";
    $output .= "   \$('document').ready( function() { \n";
    $output .= "   pnp_BindKr('#card_number,#routingnum'); \n";
    $output .= "   }); \n";
    $output .= "</script> \n";
  }
  $output .= "<script Language=\"Javascript\">\n";
  $output .= "<\!-- Start Script\n";

  $output .= "function results() {\n";
  $output .= "  resultsWindow = window.open('/payment/recurring/blank.html','results','menubar=no,status=no,scrollbars=yes,resizable=yes,width=400,height=300');\n";
  $output .= "}\n";

  $output .= "function online_help(ht,wd) {\n";
  $output .= "  helpWindow = window.open('/payment/recurring/blank.html','help','menubar=no,status=no,scrollbars=yes,resizable=yes,width='+wd+',height='+ht);\n";
  $output .= "}\n";

  $output .= "function update(pay) {\n";
  $output .= "  if(document.pay.cookie_pw.value == '') {\n";
  $output .= "    alert('A valid password is required to use this option. Please click here now to close this window and return to the order form.');\n";
  $output .= "  }\n";
  $output .= "  else {\n";
  $output .= "    resultsWindow = window.open('/payment/recurring/blank.html','results','menubar=no,status=no,scrollbars=yes,resizable=yes,width=400,height=300');\n";
  $output .= "    document.pay.target = 'results';\n";
  $output .= "    document.pay.wfunction.value = 'update';\n";
  $output .= "    document.pay.submit();\n";
  $output .= "  }\n";
  $output .= "}\n\n";

  $output .= "function pass_remind(pay) {\n";
  $output .= "    resultsWindow = window.open('/payment/recurring/blank.html','results','menubar=no,status=no,scrollbars=yes,resizable=yes,width=400,height=300');\n";
  $output .= "    pay.target = 'results';\n";
  $output .= "    document.pay.wfunction.value = 'passremind';\n";
  $output .= "    pay.submit();\n";
  $output .= "}\n\n";

  $output .= "function check_un() {\n";
  $output .= "  if(document.pay.cookie_pw.value == '') {\n";
  $output .= "    alert('A valid password is required to use this option. Please click here now to close this window and return to the order form.');\n";
  $output .= "  }\n";
  $output .= "  else {\n";
  $output .= "    document.pay.wfunction.value='';\n";
  $output .= "    document.pay.submit();\n";
  $output .= "  }\n";
  $output .= "}\n";

  $output .= "function upsell() {\n";
  $output .= "  upsellWindow = window.open('$payutils::upsell_url','upsell','menubar=no,status=no,scrollbars=no,resizable=no,width=350,height=350');\n";
  $output .= "}\n";

  if ($payutils::ewallet eq "yes") {
    $output .= "function wallet(thisForm) {\n";
    $output .= "  thisForm.submit();\n";
    $output .= "}\n";
  }

  $output .= "function popUp(url) {\n";
  $output .= "  sealWin=window.open(url,'win','toolbar=0,location=0,directories=0,status=1,menubar=1,scrollbars=1,resizable=1,width=500,height=450');\n";
  $output .= "  self.name = 'mainWin';\n";
  $output .= "}\n";

  if (($payutils::query{'keyswipe'} eq "yes") || ($payutils::feature{'keyswipe'} eq "yes")) {
    # for legacy keyswipe ability
    $output .= "function keyswipewindow () {\n";
    $output .= "  window.name = 'mainWin;\n";
    $output .= "  var keyswipe = window.open('../keyswipe.htm','keyswipe','toolbar=0,location=0,directories=0,status=0,menubar=0,scrollbars=0,resizable=0,width=350,height=200');\n";
    $output .= "}\n";
  }
  elsif (($payutils::query{'keyswipe'} eq "secure") || ($payutils::feature{'keyswipe'} eq "secure")) {
    # for secure keyswipe ability
    &javascript_luhn10();
  }

  $output .= "pressed_flag = 0;\n";
  $output .= "function mybutton(form) {\n";
  $output .= "  if (pressed_flag == 0) {\n";
  $output .= "    pressed_flag = 1;\n";
  $output .= "    return true;\n";
  $output .= "  }\n";
  $output .= "  else {\n";
  $output .= "    return false;\n";
  $output .= "  }\n";
  $output .= "}\n";

  $output .= "function disableForm(theform) {\n";
  if (($payutils::query{'keyswipe'} eq "secure") || ($payutils::feature{'keyswipe'} eq "secure")) {
    $output .= "  if ((isCreditCard() == false) && (document.pay.paymethod.value == 'swipe')) {\n";
    $output .= "    alert('Invalid Credit Card Number.  Please Try Again.');\n";
    $output .= "    return false;\n";
    $output .= "  }\n";
  }
  $output .= "  if (document.all || document.getElementById) {\n";
  $output .= "    for (i = 0; i < theform.length; i++) {\n";
  $output .= "      var tempobj = theform.elements[i];\n";
  $output .= "      if (tempobj.type.toLowerCase() == \"submit\" || tempobj.type.toLowerCase() == \"reset\")\n";
  $output .= "        tempobj.disabled = true;\n";
  $output .= "    }\n";
  $output .= "    return true;\n";
  $output .= "  }\n";
  $output .= "  else {\n";
  $output .= "    return true;\n";
  $output .= "  }\n";
  $output .= "}\n";

  $output .= "function numbersonly(myfield, e, dec) {\n";
  $output .= "  var key;\n";
  $output .= "  var keychar;\n";
  $output .= "  if (window.event) {\n";
  $output .= "    key = window.event.keyCode;\n";
  $output .= "  }\n";
  $output .= "  else if (e) {\n";
  $output .= "    key = e.which;\n";
  $output .= "  }\n";
  $output .= "  else {\n";
  $output .= "     return true;\n";
  $output .= "  }\n";
  $output .= "  keychar = String.fromCharCode(key);\n";
  $output .= "  // control keys\n";
  $output .= "  if ((key==null) || (key==0) || (key==8) || (key==9) || (key==13) || (key==27) ) {\n";
  $output .= "    return true;\n";
  $output .= "  }\n";
  $output .= "  // numbers\n";
  $output .= "  else if (((\"0123456789\").indexOf(keychar) > -1)) {\n";
  $output .= "    return true;\n";
  $output .= "  }\n";
  $output .= "  // decimal point jump\n";
  $output .= "  else if (dec && (keychar == \".\")) {\n";
  $output .= "    myfield.form.elements[dec].focus();\n";
  $output .= "    return false;\n";
  $output .= "  }\n";
  $output .= "  else {\n";
  $output .= "    return false;\n";
  $output .= "  }\n";
  $output .= "}\n";

  if ($payutils::query{'comments'} ne "") {
    $output .= "function filtercomments() {\n";
    $output .= "  if (document.pay.comments) {\n";
    $output .= "   document.pay.comments.value = document.pay.comments.value.replace(/[^a-zA-Z0-9.?@\$\" ]/gm,'');\n";
    $output .= "  }\n";
    $output .= "}\n";
  }

  $output .= qq`
    // Wait before allowing submit
    window.onload = function() {
      var allowSubmit = false;

      setTimeout(function() {
        allowSubmit = true;
      }, 10000);

      document.getElementsByName("pay")[0].addEventListener("submit", function(event) {
        // Make sure submit is allowed before submitting
        event.preventDefault();
        var checkAllowSubmit = setInterval(submit, 500);
        function submit() {
          if (allowSubmit) {
            clearInterval(checkAllowSubmit);
            event.target.submit();
          }
        }
      });
    };
  `;

  $output .= "// end script-->\n";
  $output .= "</script>\n\n";

  if ($payutils::query{'amexlev2'} == 1) {
    $output .= "<script type=\"text/javascript\" src=\"/javascript/jquery.min.js\"></script>\n";
    $output .= "<style id=\"amexlev2css\" type=\"text/css\">\n";
    $output .= "<!--\n";
    $output .= ".amexlev2 { width: 100%; display: none; visibility: hidden; }\n";
    $output .= "-->\n";
    $output .= "</style>\n";
  }

  if ($payutils::feature{'css-link'} ne "") {
    $output .= "<link href=\"$payutils::feature{'css-link'}\" type=\"text/css\" rel= \"stylesheet\">\n";
  }

  $output .= "</head>\n";

  if ($payutils::backimage eq "") {
    $output .= "<body bgcolor=\"$payutils::backcolor\" link=\"$payutils::linkcolor\" text=\"$payutils::goodcolor\" alink=\"$payutils::alinkcolor\" vlink=\"$payutils::vlinkcolor\" $payutils::upsell $payutils::autoload>\n";
  }
  else {
    $output .= "<body bgcolor=\"$payutils::backcolor\" link=\"$payutils::linkcolor\" text=\"$payutils::goodcolor\" alink=\"$payutils::alinkcolor\" vlink=\"$payutils::vlinkcolor\" background=\"$payutils::backimage\" $payutils::upsell $payutils::autoload>\n";
  }

  if ($payutils::query{'image-placement'} eq "") {
    $payutils::query{'image-placement'} = "center";
  }

  my $imagehtml = "";
  if ($payutils::query{'image-anchor'} =~ /^http/i) {
    $imagehtml = "<a href=\"$payutils::query{'image-anchor'}\"><img src=\"$payutils::query{'image-link'}\" border=\"0\"></a>\n";
  }
  else {
    $imagehtml ="<img src=\"$payutils::query{'image-link'}\">";
  }

  $output .= "\n\n<!--  START OF CUSTOMIZEABLE TOP SECTION --> \n\n";

  if ($payutils::template{'top'} ne "") {
    $output .= "$payutils::template{'top'}\n";
  }
  elsif (($payutils::query{'image-link'} ne "") && ($payutils::query{'image-placement'} ne "left") && ($payutils::query{'image-placement'} ne "topleft") && ($payutils::query{'image-placement'} ne "table")) {
    $output .= "<div align=\"$payutils::query{'image-placement'}\">\n";
    $output .= "$imagehtml\n";
    $output .= "</div>\n\n";
  }
  elsif (($payutils::query{'image-link'} ne "") && ($payutils::query{'image-placement'} eq "topleft")) {
    $output .= "<div align=\"left\">\n";
    $output .= "$imagehtml\n";
    $output .= "</div>\n\n";
  }

  $output .= "\n\n<!--  END OF CUSTOMIZEABLE TOP SECTION --> \n\n";

  my ($overall,$leftborder,$labels,$fields,$cellspacing,$cellpadding);
  if ($payutils::tableprop{'overall_width'} > 400) {
    $overall = $payutils::tableprop{'overall_width'};
  }
  else {
    $overall = '600';
  }
  if ($payutils::tableprop{'lborder_width'} > 10) {
    $leftborder = $payutils::tableprop{'lborder_width'};
  }
  else {
    $leftborder = '50';
  }
  if ($payutils::tableprop{'label_width'} > 75) {
    $labels = $payutils::tableprop{'label_width'};
  }
  else {
    $labels = '525';
  }
  if ($payutils::tableprop{'field_width'} > 75) {
    $fields = $payutils::tableprop{'field_width'};
  }
  else {
    $fields = '425';
  }
  if (($payutils::tableprop{'cellspacing'} > 0) && ($payutils::tableprop{'cellspacing'} < 10)) {
    $cellspacing = $payutils::tableprop{'cellspacing'};
  }
  else {
    $cellspacing = '0';
  }
  if (($payutils::tableprop{'cellpadding'} > 0) && ($payutils::tableprop{'cellpadding'} < 10)) {
    $cellpadding = $payutils::tableprop{'cellpadding'};
  }
  else {
    $cellpadding = '1';
  }

  $output .= "<div class=\"info\" align=\"center\">\n";

  if (($payutils::query{'keyswipe'} eq "secure") || ($payutils::feature{'keyswipe'} eq "secure")) {
    # for secure keyswipe ability
    $output .= "<form method=\"post\" name=\"pay\" action=\"$payutils::query{'path_invoice_cgi'}\" onSubmit=\"return disableForm(this) && checkMagstripe(event)\" $payutils::autocomplete{'form'}>\n";

  }
  elsif (($payutils::feature{'skipsummaryflg'} == 1) && ($payutils::feature{'use_captcha'} != 1)) {
    $output .= "<form method=\"post\" name=\"pay\" action=\"$payutils::query{'path_invoice_cgi'}\" onSubmit=\"return disableForm(this);\" $payutils::autocomplete{'form'}>\n";
  }
  else {
    $output .= "<form method=\"post\" name=\"pay\" action=\"$payutils::query{'path_cgi'}\" accept-charset=\"UTF-8\" $payutils::autocomplete{'form'}>\n";
  }

  $output .= "<table cellspacing=\"$cellspacing\" cellpadding=\"$cellpadding\" border=\"0\" width=\"$overall\">\n";
  $output .= "<tr valign=\"top\">\n";
  if (($payutils::query{'image-link'} ne "") && ($payutils::query{'image-placement'} eq "left")) {
    $output .= "  <td rowspan=\"50\">$imagehtml</td>\n";
  }
  else {
    $output .= "  <td width=\"$leftborder\" rowspan=\"50\"> &nbsp; </td>\n";
  }
  $output .= "  <td width=\"$labels\" class=\"short\"> &nbsp; </td>\n";
  $output .= "  <td width=\"$fields\" class=\"short\"> &nbsp; </td>\n";
  $output .= "</tr>\n";

  if (($payutils::query{'image-link'} ne "") && ($payutils::query{'image-placement'} eq "table")) {
    $output .= "<tr>\n";
    $output .= "  <td colspan=\"2\"><div align=\"center\">$imagehtml</div></td>\n";
    $output .= "</tr>\n\n";
  }

  $output .= "\n";

  return $output;
}


sub pay_screen1_table {
  my ($discount, $discount_type);

  my $output = '';

  if ($payutils::query{'easycart'} == 1) {
    $output .= "<tr><td colspan=\"2\">\n";
    $output .= "<div id=\"paytable\">\n";

    $output .= "<!-- start itemization table -->\n";
    $output .= "<table cellspacing=\"0\" cellpadding=\"1\" border=\"0\" width=\"550\">\n";
    $output .= "  <tr>";
    my ($columns);
    if ($payutils::query{'showskus'} eq "yes") {
      $columns = 4;
      $output .= "    <th align=\"left\" class=\"itemscolor\">$payutils::lang_titles{'modelnum'}[$payutils::lang]</th>\n";
    }
    else {
      $columns = 3;
    }
    $output .= "    <th align=\"left\" class=\"itemscolor\">$payutils::lang_titles{'description'}[$payutils::lang]</th>\n";
    $output .= "    <th class=\"itemscolor\" align=\"right\">$payutils::lang_titles{'price'}[$payutils::lang]</th>\n";
    $output .= "    <th class=\"itemscolor\" align=\"right\">$payutils::lang_titles{'qty'}[$payutils::lang]</th>\n";
    $output .= "    <th class=\"itemscolor\" align=\"right\">$payutils::lang_titles{'amount'}[$payutils::lang]</th>\n";
    $output .= "  </tr>\n";

    for (my $j=1; $j<=$payutils::max; $j++) {
      $output .= "  <tr class=\"itemrows\">";
      if ($payutils::query{'showskus'} eq "yes") {
        $output .= "    <td align=\"left\" class=\"itemrows\">$payutils::item[$j]</td>\n";
      }
      $output .= "    <td align=\"left\" class=\"itemrows\">$payutils::description[$j]</td>\n";
      $output .= sprintf("    <td align=\"right\" class=\"itemrows\">$payutils::query{'currency_symbol'}%.2f</td>\n", $payutils::cost[$j]);
      $output .= "    <td align=\"right\" class=\"itemrows\">$payutils::quantity[$j]</td>\n";
      $output .= sprintf("    <td align=\"right\" class=\"itemrows\">$payutils::query{'currency_symbol'}%.2f</td>\n",$payutils::ext[$j]);
      $output .= "  </tr>";
    }
    if (($payutils::couponflag == 1) || ($payutils::feature{'couponflag'} == 1)) {
      ($discount) = &calculate_discnt();
      if (($discount > 0) && ($payutils::gift_coupon != 1)) {
        $output .= "  <tr>\n";
        $output .= "    <th align=\"left\" colspan=\"$columns\">$payutils::lang_titles{'discount'}[$payutils::lang]</th>\n";
        $output .= sprintf("    <td align=\"right\">$payutils::query{'currency_symbol'}%.2f</td>\n", $discount);
        $output .= "  </tr>\n";
      }
    }

    $payutils::subtotal = &Round($payutils::subtotal);
    $output .= "  <tr>\n";
    $output .= "    <th align=\"left\" colspan=\"$columns\">$payutils::lang_titles{'subtotal'}[$payutils::lang]</th>\n";
    $output .= sprintf("    <td align=\"right\">$payutils::query{'currency_symbol'}%.2f</td>\n", $payutils::subtotal);
    $output .= "  </tr>\n";

    if ($payutils::query{'shipping'} > 0) {
      $payutils::query{'shipping'} = &Round($payutils::query{'shipping'});
      if ($payutils::query{'shipmethod'} eq "") {
        if ($payutils::query{'shiplabel'} eq "") {
          $output .= "  <tr>\n";
          $output .= "    <th align=\"left\" colspan=\"$columns\">$payutils::lang_titles{'shipping'}[$payutils::lang]</th>\n";
          $output .= sprintf("    <td align=\"right\">$payutils::query{'currency_symbol'}%.2f</td>\n", $payutils::query{'shipping'});
          $output .= "  </tr>\n";
        }
        else {
          $output .= "  <tr>\n";
          $output .= "    <th align=\"left\" colspan=\"$columns\">$payutils::query{'shiplabel'}</th>\n";
          $output .= sprintf("    <td align=\"right\">$payutils::query{'currency_symbol'}%.2f</td>\n", $payutils::query{'shipping'});
          $output .= "  </tr>\n";
        }
      }
    }

    if ($payutils::query{'handling'} > 0) {
      $payutils::query{'handling'} = &Round($payutils::query{'handling'});
      $output .= "  <tr>\n";
      $output .= "    <th align=\"left\" colspan=\"$columns\">$payutils::lang_titles{'handling'}[$payutils::lang]</th>\n";
      $output .= sprintf("    <td align=\"right\">$payutils::query{'currency_symbol'}%.2f</td>\n", $payutils::query{'handling'});
      $output .= "  </tr>\n";
    }
    if ($payutils::query{'publisher-name'} !~ /^(constructio|scanaloginc)$/) {
      &certitaxcalc();
    }
    &taxcalc();

    if ($payutils::query{'shipmethod'} ne "") {
      $payutils::query{'card-amount'} = $payutils::subtotal + $payutils::query{'tax'} + $payutils::query{'handling'};
    }
    else {
      $payutils::query{'card-amount'} = $payutils::subtotal + $payutils::query{'shipping'} + $payutils::query{'tax'} + $payutils::query{'handling'};
    }

    if ($payutils::query{'tax'} > 0) {
      $output .= "  <tr>\n";
      $output .= "    <th align=\"left\" colspan=\"$columns\">$payutils::lang_titles{'tax'}[$payutils::lang]</th>\n";
      $output .= sprintf("    <td align=\"right\">$payutils::query{'currency_symbol'}%.2f</td>\n", $payutils::query{'tax'});
      $output .= "  </tr>\n";
    }

    if ((($payutils::couponflag == 1) || ($payutils::feature{'couponflag'} == 1)) && ($payutils::gift_coupon == 1)) {
      my $prediscount_total = $payutils::query{'card-amount'};
      ($discount) = &calculate_gift_cert_discnt();
      $output .= "<tr><th align=\"left\" colspan=\"$columns\">$payutils::lang_titles{'giftcert'}[$payutils::lang]</th>\n";
      $output .= sprintf("<td align=\"right\">$payutils::query{'currency_symbol'}%.2f</td></tr>\n", $discount);
      if (($discount >= $prediscount_total) && ($payutils::query{'card-amount'} <= 0)) {
        $payutils::query{'card-amount'} = 0.00;
        $payutils::query{'paymethod'} = "invoice";
      }
      elsif ($discount == $prediscount_total) {
        $payutils::query{'card-amount'} -= $discount;
        $payutils::query{'paymethod'} = "invoice";
      }
    }

    if ($payutils::query{'acct_code3'} eq "billpay") {
      ($discount) = &calculate_discnt();
      $discount = &Round($discount);
      if (($discount > 0) && ($payutils::query{'acct_code3'} eq "billpay")) {
        $output .= "  <tr>\n";
        $output .= "    <th align=\"left\" colspan=\"$columns\">$payutils::lang_titles{'discount'}[$payutils::lang]</th>\n";
        $output .= sprintf("    <td align=\"right\">$payutils::query{'currency_symbol'}%.2f</td>\n", $discount);
        $output .= "  </tr>\n";

        $payutils::query{'card-amount'} -= $discount;
        if ($payutils::query{'card-amount'} <= 0) {
          $payutils::query{'card-amount'} = 0.00;
          $payutils::query{'paymethod'} = "invoice";
        }
      }
    }

    my $display_total = $payutils::query{'card-amount'};
    if (($payutils::feature{'conv_fee'} ne "") && ($payutils::query{'override_adjustment'} != 1)) {
      my ($feeamt, $fee_acct, $failrule) = &conv_fee();
      if ($feeamt > 0) {
        $display_total += $feeamt;
        $output .= "  <tr>\n";
        $output .= "    <th align=\"left\" colspan=\"$columns\">$payutils::lang_titles{'convfee'}[$payutils::lang]</th>\n";
        $output .= sprintf("  <td align=\"right\">$payutils::query{'currency_symbol'}%.2f</td>\n", $feeamt);
        $output .= "  </tr>\n";
      }
    }

    my $TotalPrefix="";
    if ($payutils::feature{'cardcharge'} ne "") {
      $TotalPrefix = "INITIAL";
    }
    $output .= "  <tr>\n";
    $output .= "    <th align=\"left\" colspan=\"$columns\">$TotalPrefix $payutils::lang_titles{'total'}[$payutils::lang]</th>\n";
    $output .= sprintf("    <td align=\"right\">$payutils::query{'currency_symbol'}%.2f</td>\n", $display_total);
    $output .= "  </tr>\n";
    $output .= "</table>\n";
    $output .= "</div>\n";

    if ($payutils::query{'shipmethod'} ne "") {
      $output .= "<div align=\"center\"><i>Tax and shipping will be calculated upon checkout, if applicable. </i></div>\n";
    }
  }
  elsif ($payutils::template{'displayamt'} ne "") {
    my $display_total = $payutils::query{'card-amount'};
    if (($payutils::feature{'conv_fee'} ne "") && ($payutils::query{'override_adjustment'} != 1)) {
      my ($feeamt, $fee_acct, $failrule) = &conv_fee();
      if ($feeamt > 0) {
        $display_total += $feeamt;
      }
    }
    $display_total =  sprintf("%.2f",$display_total);
    $payutils::template{'displayamt'} =~ s/\[displayamt\]/$display_total/;
    $output .= "<tr>\n";
    $output .= "  <td colspan=\"2\" class=\"larger\">$payutils::template{'displayamt'}</td>\n";
    $output .= "</tr>\n";
  }
  elsif ($payutils::query{'card-amount'} > 0) {
    my $display_total = $payutils::query{'card-amount'};
    if (($payutils::feature{'conv_fee'} ne "") && ($payutils::query{'override_adjustment'} != 1)) {
      my ($feeamt, $fee_acct, $failrule) = &conv_fee();
      if ($feeamt > 0) {
        $display_total += $feeamt;
      }
    }
    $payutils::query{'card-amount'} = sprintf("%.2f",$payutils::query{'card-amount'});
    $display_total =  sprintf("%.2f",$display_total);
    $output .= "<tr>\n";
    $output .= "  <td colspan=\"2\" class=\"larger\"><span>$payutils::lang_titles{'amttocharge'}[$payutils::lang]\: <b>$payutils::query{'currency_symbol'}$display_total</b></span></td>\n";
    $output .= "</tr>\n";
  }
  else {
    $output .= "<tr>\n";
    $output .= "  <td colspan=\"2\"> &nbsp; </td>\n";
    $output .= "</tr>\n";
  }

  return $output;
}


sub pay_screen1_badcard {
  my $output = '';

  if (($payutils::query{'MErrMsg'} ne "") || ($payutils::error{'dataentry'} ne "")) {
    $output .= "<tr><td colspan=\"2\" class=\"larger\">\n";
    if (($payutils::error{'dataentry'} =~ /minimum purchase of/i) && ($payutils::feature{'minpurchase'} ne "")) {
      $output .= "<br><b>$payutils::error{'dataentry'}</b></br>\n";
      return;
    }
    $output .= "<br>$payutils::lang_titles{'infoproblem'}[$payutils::lang]\n";
    $output .= "<p>\n";
    if (($payutils::query{'MErrMsg'} =~ /fails LUHN-10 check/) || ($payutils::query{'MErrMsg'} =~ /bad card/)) {
      $output .= "$payutils::lang_titles{'validcc'}[$payutils::lang] ";
      $payutils::color{'card-number'} = $payutils::badcolor;
    }
    elsif ($payutils::query{'MErrMsg'} =~ /did not respond in a timely manner/) {
      $output .= "$payutils::lang_titles{'sorry2'}[$payutils::lang] \n";
    }
    elsif ($payutils::query{'MErrMsg'} =~ /or are not configured to accept the card type used/) {
      $output .= "$payutils::lang_titles{'sorry1'}[$payutils::lang]\n";
      $payutils::color{'card-number'} = $payutils::badcolor;
      $payutils::color{'card-type'} = $payutils::badcolor;
    }
    elsif (($payutils::query{'MErrMsg'} =~ /Application agent not found/) && ($payutils::processor eq "intuit")) {
      $output .= "Application not registered in production environment at Intuit - contact your software provider.\n";
    }
    elsif (($payutils::chkprocessor eq "telecheck") && ($payutils::query{'accttype'} =~ /^(checking|savings)$/)) {
      if ($payutils::query{'resp-code'} =~ /^(08|88|73)$/) {
        $output .= "We are sorry that we cannot process additional electronic payments on your order. Our decision is based, in whole or in part, on information provided to us by TeleCheck. We encourage you to call TeleCheck at 1.877.678.5898 or write TeleCheck Customer Care at P.O. Box 4513, Houston, TX 77210-4513. Please provide TeleCheck your driver's license number and the state where it was issued, and the complete banking numbers printed on the bottom of your check. Under the Fair Credit Reporting Act, you have the right to a free copy of your information held in TeleCheck's files within 60 days from today. You may also dispute the accuracy or completeness of any information in TeleCheck's consumer report. TeleCheck did not make the adverse decision to not accept your payment item and is unable to explain why this decision was made.";
      }
      elsif ($payutils::query{'resp-code'} =~ /^(25|82)$/) {
        $output .= "We are unable to process this transaction with the payment information provided. Please use a different form of payment at this time.";
      }
      else {
        $output .= "We are unable to verify your checking account or identity information. Please review the information you entered to ensure that all information is correct.";
      }
    }
    else {
      if ($payutils::error{'dataentry'} ne "") {
        $output .= "<b>$payutils::error{'dataentry'}</b>\n";
        $output .= "<tr><td align=\"left\" colspan=\"3\">\n";
        $output .= "$payutils::lang_titles{'re_enter2'}[$payutils::lang]";
        $output .= "</td></TR>\n";
      }
      else {
        if ($payutils::query{'paymethod'} eq "teleservice") {
          $output .= "<b>$payutils::query{'MErrMsg'}</b>\n";
        }
        else {
          my (@error_response) = split(/\|/,$payutils::query{'MErrMsg'});
          $output .= "$payutils::lang_titles{'declined'}[$payutils::lang]\n";
          foreach my $var (@error_response) {
            $output .= "<b>$var</b><br>\n";
          }
          $output .= "<br>\n";
          $output .= "$payutils::lang_titles{'incorrect'}[$payutils::lang]\n";
          $output .= "<br>\n";
          $output .= "$payutils::lang_titles{'inerror'}[$payutils::lang]\n";
          $output .= "<br></td></tr>\n";
        }
      }
    }
  }
  else {
    if (($payutils::error >= 1) && ($payutils::query{'pass'} == 1)) {
      $output .= "<tr><td colspan=\"2\">\n";
      $output .= "<br>$payutils::lang_titles{'reqinfo'}[$payutils::lang]\n";
      $output .= "</td></tr>\n";
    }
  }
# mercury gift card error
  if (($payutils::processor eq "mercury") && ($payutils::feature{'acceptgift'} == 1)) {
    if ($payutils::query{'MErrMsg'} =~ /Gift Card/) {
      $output .= "<tr><td colspan=\"2\" class=\"larger\">\n";
      $output .= "<font color=\"#FF0000\">\n";
      $output .= "$payutils::lang_titles{'mpgifterror'}[$payutils::lang]\n";
      $output .= "</font>\n";
      $payutils::error = 1;
      $payutils::color{'card-number'} = 'badcolor';
      $payutils::color{'card-exp'} = 'badcolor';
      $payutils::color{'mpgiftcard'} = 'badcolor';
      $payutils::color{'mpcvv'} = 'badcolor';
      $payutils::errvar .= "mpgiftcard\|mpcvv\"";
      $output .= "</td></tr>\n";
    }
  }

  return $output;
}


sub pay_screen1_body {
  my $output = '';
  $output .= pay_screen1_billing();
  $output .= pay_screen1_shipping();
  return $output;
}


sub pay_screen1_wallet {
  my $output = '';
  $output .= "<tr><td> &nbsp; </td><td align=\"left\" colspan=\"2\">\n";
  $output .= "<input type=\"submit\" name=\"client\" value=\"Click to Use Your PnP eWallet\" onClick=\"wallet(this.form);\"></td></tr>\n";
  $output .= "<input type=\"hidden\" name=\"wfunction\" value=\"login\">\n";
  $output .= "</td></tr>\n";
  return $output;
}


sub pay_screen1_billing {
  my $output = '';

  if (($payutils::query{'keyswipe'} eq "yes") || ($payutils::feature{'keyswipe'} eq "yes")) {
    # for legacy keyswipe ability
    $output .= "<input type=\"hidden\" name=\"magstripe\" value=\"$payutils::query{'magstripe'}\">\n";
    if ($payutils::query{'convert'} ne "underscores") {
      $output .= "<input type=\"hidden\" name=\"convert\" value=\"underscores\">\n";
    }
    $output .= "<tr><td colspan=\"2\" class=\"larger\"><br>To Swipe Credit Card:</td></tr>\n";
    $output .= "<tr><td colspan=\"2\"><ol>\n";
    $output .= "<li>Click 'Swipe Credit Card' button.\n";
    $output .= "<li>Swipe the credit card through your card reader.\n";
    $output .= "<li>Click the 'OK' button. The name, card # \& exp date will be filled in.</ol>\n";
    $output .= "<input type=\"button\" value=\"Swipe Credit Card\" onClick=\"keyswipewindow();\">\n";
    $output .= "</td></tr>\n";
  }
  elsif (($payutils::query{'keyswipe'} eq "secure") || ($payutils::feature{'keyswipe'} eq "secure")) {
    $output .= "<input type=\"hidden\" name=\"magstripe\" value=\"$payutils::query{'magstripe'}\">\n";
    if ($payutils::query{'convert'} ne "underscores") {
      $output .= "<input type=\"hidden\" name=\"convert\" value=\"underscores\">\n";
    }
  }

  if ($payutils::template{'body_prebilling'} ne "") {
    $output .= "$payutils::template{'body_prebilling'}\n";
  }

  if ($payutils::query{'paymethod'} ne "check") {
    if (($payutils::bname ne "") && ($payutils::query{'client'} !~ /update/i) && ($payutils::query{'wfunction'} !~ /update/i)) {
      $output .= "<tr><td colspan=\"2\" class=\"larger\"><br>Welcome Back $payutils::bname,</td></tr>\n";
      $output .= "<tr><td colspan=\"2\">To use the billing information previously registered with us, ";
      $output .= "please enter your password in the space provided below.</td></tr>\n";
      $output .= "<tr><td align=\"right\">PnPExpress Password: </td>";
      $output .= "<td align=\"left\"><input type=\"password\" name=\"cookie_pw\" size=\"10\" maxlength=\"10\"></td></tr>\n";
      $output .= "<tr><td> &nbsp; </td><td colspan=\"2\" class=\"smaller\"><input type=\"button\" value=\"Checkout with PnPExpress\" onClick=\"check_un();\"></td>\n";
      $output .= "<tr><td> &nbsp; </td><td colspan=\"2\" class=\"smaller\"><input type=\"button\" name=\"client\" value=\"Update PnPExpress\" onClick=\"update(this.form);\"><input type=\"hidden\" name=\"wfunction\" value=\"\">";
      $output .= "<input type=\"button\" name=\"client\" value=\"Forgot your Password?\" onClick=\"pass_remind(this.form);\"></td></tr>\n";
    }

    if (($payutils::allow_cookie eq "yes") && ($payutils::query{'client'} !~ /update/i) && ($payutils::bname eq "")) {
      $output .= "<tr><td align=\"left\" colspan=\"2\">To subscribe to PnPExpress and have us remember your billing and";
      $output .= " shipping information for your next purchase, enter a password in the spaces provided below.  <b>4 ";
      $output .= "characters as a minimum and no special characters.</b></td></tr>\n";
      $output .= "<tr><td align=\"right\" style=\"color: $payutils::color{'cookie_pw'}\">Enter Password:</td>";
      $output .= "<td><input type=\"text\" name=\"cookie_pw1\" value=\"$payutils::query{'cookie_pw1'}\" size=\"10\" maxlength=\"10\" autocomplete=\"off\"></td></tr>\n";
      $output .= "<tr><td align=\"right\" style=\"color: $payutils::color{'cookie_pw'}\">Confirm Password:</td>";
      $output .= "<td><input type=\"text\" name=\"cookie_pw2\" value=\"$payutils::query{'cookie_pw2'}\" size=\"10\" maxlength=\"10\" autocomplete=\"off\"></td></tr>\n";
      $output .= "<tr><td colspan=\"2\"></td></tr>";
    }

    if (($payutils::query{'app-level'} > 1) && ($payutils::query{'noavsnotice'} ne "yes")) {
      $output .= "<tr><td class=\"larger\" colspan=\"2\"><b>NOTICE:</b> Address Verification is being enforced. ";
      $output .= "Please enter your address exactly as it appears on your credit card statement or your purchase will be declined.";
      $output .= "</td></tr>\n";
    }

    if ($payutils::query{'showbillinginfo'} ne "no") {
      $output .= "<tr><td align=\"left\" colspan=\"2\" class=\"larger\"><br>";
      $output .= "$payutils::lang_titles{'billing'}[$payutils::lang]<br>";
      $output .= "</td></tr>\n";

      $output .= "<tr><td align=\"left\" colspan=\"2\">";
      $output .= "$payutils::lang_titles{'billing1'}[$payutils::lang]\n";
      $output .= "</td></tr>\n";
    }
  }
  else {
    $output .= "<tr><td align=\"left\" colspan=\"2\" class=\"larger\"><br>";
    $output .= "$payutils::lang_titles{'subscription'}[$payutils::lang]\:";
    $output .= "</td></tr>\n";
    $output .= "<tr><td align=\"left\" colspan=\"2\"><br>";
    $output .= "$payutils::lang_titles{'billing1'}[$payutils::lang]\n";
    $output .= "</td></tr>\n";
  }

  if (($payutils::query{'privacy'} ne "omitstatement") && ($payutils::feature{'omitstatement'} != 1) && ($payutils::pl_feature{'omitstatement'} != 1)) {
    $output .= "<tr><td align=\"left\" colspan=\"2\" class=\"smaller\">";
    if ($payutils::query{'privacy'} ne "") {
      $output .= "<span style=\"width: 500\">$payutils::query{'privacy_statement'}</span><br>&nbsp;\n";
    }
    else {
      $output .= "<span style=\"width: 500\">$payutils::lang_titles{'privacy'}[$payutils::lang]</span><br>&nbsp;\n";
    }
    $output .= "</td></tr>\n";
  }

  ### DCP Loyalty Program - Ask to subscribe.
  if (($payutils::feature{'loyaltyprog'} == 1) && (! exists $payutils::cookie{"loyalty_$payutils::query{'publisher-name'}"} )) {
    $output .= "<tr><td align=\"left\" colspan=\"2\"><input type=\"checkbox\" name=\"loyaltysubscribe\" value=\"1\">";
    $output .= "CHECK HERE if you would like to participate in the Customer Connect loyalty program and earn points for your purchases. ";
    $output .= " <a href=\"$payutils::feature{'loyaltyprog_url'}\" target=\"small_win\">CLICK HERE</a> to learn more.<br>&nbsp;</td></tr>\n";
  }
  if ($payutils::template{'body_askamt'} ne "") {
    $output .= "$payutils::template{'body_askamt'}\n";
  }
  if ($payutils::query{'askamtflg'} == 1) {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-amount'}\"><span>$payutils::lang_titles{'amt_to_pay'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"card-amount\" size=\"10\" value=\"$payutils::query{'card-amount'}\" maxlength=\"10\"></td></tr>\n";
  }
  if ($payutils::template{'body_cardinfo'} ne "") {
    $output .= "$payutils::template{'body_cardinfo'}\n";
  }
  if (($payutils::query{'keyswipe'} =~ /(yes|secure)/) || ($payutils::feature{'keyswipe'} =~ /(yes|secure)/)) {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-name'}\"><span>$payutils::lang_titles{'name'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"card_name\" size=\"30\" value=\"$payutils::query{'card-name'}\" maxlength=\"39\"></td></tr>\n";
  }
  elsif ($payutils::feature{'splitname'} == 1) {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-name'}\"><span>$payutils::lang_titles{'fname'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"card-fname\" size=\"30\" value=\"$payutils::query{'card-fname'}\" maxlength=\"39\">";
    if (($payutils::query{'paymethod'} eq "onlinecheck") && ($payutils::chkprocessor =~ /^(paymentdata|alliancesp|echo|testprocessor|testprocessorach)$/)) {
      $output .= "<br> <i>No first name prefix (Dr, Mr, Mrs, Miss), middle name or initials permitted.  e.g. \'John\'</i>";
    }
    $output .= "</td></tr>\n";
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-name'}\"><span>$payutils::lang_titles{'lname'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"card-lname\" size=\"30\" value=\"$payutils::query{'card-lname'}\" maxlength=\"39\">";
    if (($payutils::query{'paymethod'} eq "onlinecheck") && ($payutils::chkprocessor =~ /^(paymentdata|alliancesp|echo|testprocessor|testprocessorach)$/)) {
      $output .= "<br> <i>No last name suffix (Jr, Sr, PhD, JD, MD), or numbers permitted.  e.g. \'Smith\'</i>";
    }
    $output .= "</td></tr>\n";
  }
  else {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-name'}\"><span>$payutils::lang_titles{'name'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"card-name\" size=\"30\" value=\"$payutils::query{'card-name'}\" maxlength=\"39\"></td></tr>\n";
  }
  if ($payutils::query{'showssnum'} eq "yes") {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'ssnum'}\"><span>$payutils::lang_titles{'ssnum'}[$payutils::lang]\:$payutils::requiredstar{'ssnum'}</span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"ssnum\" value=\"$payutils::query{'ssnum'}\" size=\"15\" maxlength=\"15\" autocomplete=\"off\"></td></tr>\n";
  }
  elsif ($payutils::query{'showssnum4'} eq "yes") {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'ssnum4'}\"><span>$payutils::lang_titles{'last4'}[$payutils::lang]\:$payutils::requiredstar{'ssnum4'}</span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"ssnum4\" value=\"$payutils::query{'ssnum4'}\" size=\"4\" maxlength=\"4\" autocomplete=\"off\"></td></tr>\n";
  }

  if ($payutils::query{'showcompany'} eq "yes") {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-company'}\"><span>$payutils::lang_titles{'company'}[$payutils::lang]\:$payutils::requiredstar{'card-company'}</span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"card-company\" size=\"30\" value=\"$payutils::query{'card-company'}\" maxlength=\"39\"></td></tr>\n";
  }

  if ($payutils::query{'showtitle'} eq "yes") {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'title'}\"><span>$payutils::lang_titles{'title'}[$payutils::lang]\:$payutils::requiredstar{'title'}</span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"title\" size=\"30\" value=\"$payutils::query{'title'}\" maxlength=\"39\"></td></tr>\n";
  }

  if ($payutils::feature{'suppresspay'} !~ /card-address1/) {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-address1'}\"><span>$payutils::lang_titles{'card_address1'}[$payutils::lang]\:$payutils::requiredstar{'card-address1'}</span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"card-address1\" size=\"30\" value=\"$payutils::query{'card-address1'}\" maxlength=\"39\"></td></tr>\n";
  }

  if ($payutils::feature{'suppresspay'} !~ /card-address2/) {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-address2'}\"><span>$payutils::lang_titles{'card_address2'}[$payutils::lang]\:$payutils::requiredstar{'card-address2'}</span></td>\n";
    $output .= "<td align=left><input type=\"text\" name=\"card-address2\" size=\"30\" value=\"$payutils::query{'card-address2'}\" maxlength=\"39\"></td></tr>\n";
  }
  if ($payutils::feature{'suppresspay'} !~ /card-city/) {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-city'}\"><span>$payutils::lang_titles{'city'}[$payutils::lang]\:$payutils::requiredstar{'card-city'}</span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"card-city\" size=\"20\" value=\"$payutils::query{'card-city'}\" maxlength=\"30\"></td></tr>\n";
  }
  if ($payutils::feature{'suppresspay'} !~ /card-state/) {
    if ($payutils::query{'nostatelist'} ne "yes") {
      $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-state'}\"><span>$payutils::lang_titles{'state'}[$payutils::lang]\:$payutils::requiredstar{'card-state'}</span></td>";
      $output .= "<td align=\"left\"><select name=\"card-state\">\n";

      my %selected = ();
      $selected{$payutils::query{'card-state'}} = " selected";
      $output .= "<option value=\"\">$payutils::lang_titles{'selectstate'}[$payutils::lang]</option>\n";
      foreach my $key (&sort_hash(\%constants::USstates)) {
        $output .= "<option value=\"$key\"$selected{$key}>$constants::USstates{$key}</option>\n";
      }
      if ($payutils::usterrflag ne "no") {
        foreach my $key (sort keys %constants::USterritories) {
          $output .= "<option value=\"$key\"$selected{$key}>$constants::USterritories{$key}</option>\n";
        }
      }
      if (($payutils::usonly ne "yes") && ($payutils::uscanonly ne "yes"))  {
        foreach my $key (sort keys %constants::CNprovinces) {
          $output .= "<option value=\"$key\"$selected{$key}>$constants::CNprovinces{$key}</option>\n";
        }
      }
      if ($payutils::uscanonly eq "yes")  {
        foreach my $key (sort keys %constants::USCNprov) {
          $output .= "<option value=\"$key\"$selected{$key}>$constants::USCNprov{$key}</option>\n";
        }
      }
      $output .= "</select></td></tr>\n";
    }
    else {
      $output .= "<tr><td ALIGN=\"right\" class=\"$payutils::color{'card-state'}\"><span>$payutils::lang_titles{'state'}[$payutils::lang]\:$payutils::requiredstar{'card-state'}</span></td>";
      $output .= "<td align=\"left\"><input type=\"text\" name=\"card-state\" size=\"20\" value=\"$payutils::query{'card-state'}\" maxlength=\"19\"></td></tr>\n";
    }
  }
  if ($payutils::feature{'suppresspay'} !~ /card-prov/) {
    if (($payutils::usonly ne "yes") && ($payutils::uscanonly ne "yes"))  {
      $output .= "<tr><td ALIGN=\"right\" class=\"$payutils::color{'card-prov'}\"><span>$payutils::lang_titles{'province'}[$payutils::lang]\:$payutils::requiredstar{'card-prov'}</span></td>";
      $output .= "<td align=\"left\"><input type=\"text\" name=\"card-prov\" size=\"20\" value=\"$payutils::query{'card-prov'}\" maxlength=\"19\"></td></tr>\n";
    }
  }
  if ($payutils::feature{'suppresspay'} !~ /card-zip/) {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-zip'}\"><span>$payutils::lang_titles{'zip'}[$payutils::lang]\:$payutils::requiredstar{'card-zip'}</span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"card-zip\" size=\"10\" value=\"$payutils::query{'card-zip'}\" maxlength=\"10\"></td></tr>\n";
  }
  if ($payutils::feature{'suppresspay'} !~ /card-country/) {
    if ($payutils::query{'nocountrylist'} ne "yes") {
      $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-country'}\"><span>$payutils::lang_titles{'country'}[$payutils::lang]\:$payutils::requiredstar{'card-country'}</span></td>";
      $output .= "<td align=left><select name=\"card-country\">\n";

      my %selected = ();
      $selected{$payutils::query{'card-country'}} = " selected";
      if ($payutils::usonly eq "yes") {
        $output .= "<option value=\"US\" selected>$constants::countries{'US'}</option>\n";
      }
      elsif ($payutils::uscanonly eq "yes") {
        $output .= "<option value=\"US\"$selected{'US'}}>$constants::countries{'US'}</option>\n";
        $output .= "<option value=\"CA\"$selected{'CA'}>$constants::countries{'CA'}</option>\n";
      }
      else {
        foreach my $key (&sort_hash(\%constants::countries)) {
          $output .= "<option value=\"$key\"$selected{$key}>$constants::countries{$key}</option>\n";
        }
      }
      $output .= "</select></td></tr>\n";
    }
    else {
      $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-country'}\"><span>$payutils::lang_titles{'country'}[$payutils::lang]\:$payutils::requiredstar{'card-country'}</span></td>";
      $output .= "<td align=\"left\"><input type=\"text\" name=\"card-country\" size=\"15\" value=\"$payutils::query{'card-country'}\" maxlength=\"20\"></td></tr>\n";
    }
  }

  if ($payutils::template{'body_prepayment'} ne "") {
    $output .= "$payutils::template{'body_prepayment'}\n";
  }

  if (($payutils::couponflag == 1) || ($payutils::feature{'couponflag'} == 1)) {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'promoid'}\"><span>$payutils::lang_titles{'coupon'}[$payutils::lang]\:$payutils::requiredstar{'promoid'}</span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"promoid\" size=\"30\" value=\"$payutils::query{'promoid'}\" maxlength=\"250\"></td></tr>\n";
  }

  if ($payutils::query{'paymethod'} =~ /^(onlinecheck|check)$/) {
    my %selected = ();
    $selected{$payutils::query{'accttype'}} = " selected";
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'accttype'}\"><span>$payutils::lang_titles{'accttype'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><select name=\"accttype\">\n";
    $output .= "<option value=\"checking\" $selected{'checking'}>Checking</option>\n";
    $output .= "<option value=\"savings\" $selected{'savings'}>Savings</option>\n";
    $output .= "</select>\n";
    $output .= "</td></tr>\n";

    if ($payutils::chkprocessor =~ /^(paymentdata|alliancesp|echo|testprocessor|testprocessorach)$/) {
      $selected{$payutils::query{'acctclass'}} = " selected";
      $output .= "<tr><td align=\"right\" class=\"$payutils::color{'acctclass'}\"><span>$payutils::lang_titles{'acctclass'}[$payutils::lang]\:<b>*</b></span></td>";
      $output .= "<td align=\"left\"><select name=\"acctclass\">\n";
      $output .= "<option value=\"personal\" $selected{'personal'}>Personal</option>\n";
      $output .= "<option value=\"business\" $selected{'business'}>Business</option>\n";
      $output .= "</select>\n";
      $output .= "</td></tr>\n";
    }
    elsif ($payutils::chkprocessor =~ /^(telecheck|paymentdata)$/) {
      $selected{$payutils::query{'acctclass'}} = " selected";
      $output .= "<tr><td align=\"right\" class=\"$payutils::color{'acctclass'}\"><span>$payutils::lang_titles{'checktype'}[$payutils::lang]\:<b>*</b></span></td>";
      $output .= "<td align=\"left\"><select name=\"acctclass\">\n";
      $output .= "<option value=\"personal\" $selected{'personal'}>Personal</option>\n";
      $output .= "<option value=\"business\" $selected{'business'}>Business</option>\n";
      $output .= "</select>\n";
      $output .= "</td></tr>\n";
    }

    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'checknum'}\"><span>$payutils::lang_titles{'checknum'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"checknum\" value=\"$payutils::query{'checknum'}\" size=\"20\" maxlength=\"20\" autocomplete=\"off\"> <a href=\"help.cgi?subject=checknum&lang=$payutils::query{'lang'}\" target=\"help\" onClick=\"online_help(300,625)\;\"><font size=\"-2\" color=\"$payutils::goodcolor\"><b>$payutils::lang_titles{'help'}[$payutils::lang]</b></font></a></td></tr>\n";

    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'routingnum'}\"><span>$payutils::lang_titles{'routingnum'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"routingnum\" value=\"$payutils::query{'routingnum'}\" size=\"20\" maxlength=\"20\" autocomplete=\"off\"> <a href=\"help.cgi?subject=routingnum&lang=$payutils::query{'lang'}\" target=\"help\" onClick=\"online_help(300,625)\;\"><font size=\"-2\" color=\"$payutils::goodcolor\"><b>$payutils::lang_titles{'help'}[$payutils::lang]</b></font></a></td></tr>\n";
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'accountnum'}\"><span>$payutils::lang_titles{'accountnum'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"accountnum\" value=\"$payutils::query{'accountnum'}\" size=\"20\" maxlength=\"20\" autocomplete=\"off\"> <a href=\"help.cgi?subject=accountnum&lang=$payutils::query{'lang'}\" target=\"help\" onClick=\"online_help(300,625)\;\"><font size=\"-2\" color=\"$payutils::goodcolor\"><b>$payutils::lang_titles{'help'}[$payutils::lang]</b></font></a></td></tr>\n";
  }
  elsif ($payutils::query{'paymethod'} eq "telecheck") {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'licensestate'}\"><span>$payutils::lang_titles{'licensestate'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><select name=\"licensestate\">\n";
    my %selected = ();
    $selected{$payutils::query{'licensestate'}} = " selected";
    $output .= "<option value=\"\">Select Your State/Province/Territory</option>\n";
    foreach my $key (&sort_hash(\%constants::USstates)) {
      $output .= "<option value=\"$key\"$selected{$key}>$constants::USstates{$key}</option>\n";
    }
    if ($payutils::usterrflag ne "no") {
      foreach my $key (sort keys %constants::USterritories) {
        $output .= "<option value=\"$key\"$selected{$key}>$constants::USterritories{$key}</option>\n";
      }
    }
    $output .= "</select></td></tr>\n";

    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'licensenum'}\"><span>$payutils::lang_titles{'licensenum'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"licensenum\" value=\"$payutils::query{'licensenum'}\" size=\"30\" maxlength=\"30\" autocomplete=\"off\"></td></tr>\n";

    %selected = ();
    $selected{$payutils::query{'accttype'}} = " selected";
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'accttype'}\"><span>$payutils::lang_titles{'accttype'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><select name=\"accttype\">\n";
    $output .= "<option value=\"checking\" $selected{'checking'}>Checking</option>\n";
    $output .= "<option value=\"savings\" $selected{'savings'}>Savings</option>\n";
    $output .= "</select>\n";
    $output .= "</td></tr>\n";

    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'checknum'}\"><span>$payutils::lang_titles{'checknum'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"checknum\" value=\"$payutils::query{'checknum'}\" size=\"20\" maxlength=\"20\" autocomplete=\"off\"> <a href=\"help.cgi?subject=checknum&lang=$payutils::query{'lang'}\" target=\"help\" onClick=\"online_help(300,500)\;\"><font size=\"-2\" color=\"$payutils::goodcolor\"><b>$payutils::lang_titles{'help'}[$payutils::lang]</b></font></a></td></tr>\n";

    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'micr'}\"><span>$payutils::lang_titles{'micr'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"micr\" value=\"$payutils::query{'micr'}\" size=\"30\" maxlength=\"30\" autocomplete=\"off\"> <a href=\"help.cgi?subject=micr&lang=$payutils::query{'lang'}\" target=\"help\" onClick=\"online_help(300,500)\;\"><font size=\"-2\" color=\"$payutils::goodcolor\"><b>$payutils::lang_titles{'help'}[$payutils::lang]</b></font></a></td></tr>\n";

  }
  elsif ($payutils::query{'paymethod'} eq "teleservice") {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'pinnumber'}\"><span>PIN \#:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"pinnumber\" value=\"$payutils::query{'pinnumber'}\" size=\"16\" maxlength=\"20\" autocomplete=\"off\"></td></tr>\n";
  }
  elsif ($payutils::query{'paymethod'} =~ /Invoice/i) {
  }
  elsif (($payutils::query{'paymethod'} eq "web900") || ($payutils::query{'paymethod'} eq "prepaid")) {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'web900-pin'}\"><span>Pin No:<b>*</b></span></td>";
    $output .= "<td align=\"left\"> <input type=\"text\" name=\"web900-pin\" autocomplete=\"off\"></td></tr>\n";
  }
  elsif (($payutils::query{'paymethod'} eq "mocapay") && ($payutils::walletprocessor =~ /feed/)) {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-number'}\"><span>$payutils::lang_titles{'tran_code'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"card-number\" value=\"$payutils::query{'card-number'}\" size=\"16\" maxlength=\"20\" onKeyPress=\"return numbersonly(this, event)\" autocomplete=\"off\"></td></tr>\n";
  }
  elsif (($payutils::query{'transflags'} !~ /load/i) && ($payutils::processor eq "psl")) {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'walletid'}\"><span>$payutils::lang_titles{'walletid'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"walletid\" value=\"$payutils::query{'walletid'}\" size=\"30\" maxlength=\"49\" autocomplete=\"off\"></td></tr>\n";
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'passcode'}\"><span>$payutils::lang_titles{'passcode'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"> <input type=\"text\" name=\"passcode\" value=\"$payutils::query{'passcode'}\" size=\"30\" maxlength=\"49\" autocomplete=\"off\"></td></tr>\n";
  }
  else {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-type'}\"><span>$payutils::lang_titles{'card_type'}[$payutils::lang]\: </span></td>";
    $output .= "<td align=\"left\">";

    $output .= "<table border=\"0\" cellspacing=\"0\" cellpadding=\"2\">\n";
    $output .= "  <tr>\n";

    my $colcnt = 0;
    for (my $i = 0; $i <= $#payutils::card_list; $i++) {
      my $key = $payutils::card_list[$i];

      if ($payutils::query{'card-allowed'} =~ /$key/i) {
        if (($payutils::feature{'dispcardmodulo'} > 0) && ($colcnt % $payutils::feature{'dispcardmodulo'} == 0)) {
          $output .= "  </tr>\n";
          $output .= "  <tr>\n";
        }
        elsif ($colcnt % 4 == 0) {
          $output .= "  </tr>\n";
          $output .= "  <tr>\n";
        }

        my $checked = "";
        if ($payutils::query{'card-type'} =~ /$payutils::card_hash{$key}[0]/i) { $checked = " checked"; }

        $output .= "    <td><nobr><input type=\"radio\" name=\"card-type\" value=\"$payutils::card_hash{$key}[0]\"";
        if ($payutils::query{'amexlev2'} == 1) {
          if ($key =~ /^(amex)$/i) {
            $output .= " onClick=\"\$('.amexlev2').css('visibility','visible');\$('.amexlev2').css('display','table-row');\"";
          }
          else {
            $output .= " onClick=\"\$('.amexlev2').css('visibility','hidden');\$('.amexlev2').css('display','none');\"";
          }
        }
        $output .= "$checked> <span style=\"color: $payutils::goodcolor\">";
        if ($payutils::feature{'dispcardlogo'} == 1) {
          if ($payutils::card_hash{$key}[2] ne "") {
            $output .= "<img src=\"$payutils::card_hash{$key}[2]\" title=\"$payutils::card_hash{$key}[1]\" alt=\"$payutils::card_hash{$key}[1]\">";
          }
          else {
            $output .= "$payutils::card_hash{$key}[1]";
          }
        }
        else {
          $output .= "$payutils::card_hash{$key}[1]";
        }
        $output .= "</span></nobr></td>\n";

        $colcnt = $colcnt + 1;
      }
    }

    $output .= "  </tr>\n";
    $output .= "</table>\n";

    $output .= "</td></tr>\n";

    if ($payutils::query{'amexlev2'} == 1) {
      $output .= "<tr class=\"amexlev2\"><td align=\"right\" class=\"$payutils::color{'employeename'}\"><span>Employee Name\:<b>*</b></span></td>";
      $output .= "<td align=\"left\"><input type=\"text\" name=\"employeename\" value=\"$payutils::query{'employeename'}\" size=\"30\" maxlength=\"39\"></td></tr>\n";

      $output .= "<tr class=\"amexlev2\"><td align=\"right\" class=\"$payutils::color{'costcenternum'}\"><span>Cost Center Number\:<b>*</b></span></td>";
      $output .= "<td align=\"left\"><input type=\"text\" name=\"costcenternum\" value=\"$payutils::query{'costcenternum'}\" size=\"20\" maxlength=\"20\"></td></tr>\n";
    }

    if (@payutils::customfields >= 1) {
      foreach my $var (@payutils::customfields) {
        my ($fieldname,$size,$maxlen,$class) = split(/\,/,$var);
        $output .= "<tr class=\"$class\"><td align=\"right\" class=\"$payutils::color{$fieldname}\"><span>$payutils::lang_titles{$fieldname}[$payutils::lang]\:$payutils::requiredstar{$fieldname}</span></td>";
        $output .= "<td align=\"left\"><input type=\"text\" name=\"$fieldname\" value=\"$payutils::query{$fieldname}\" size=$size maxlength=\"$maxlen\"></td></tr>\n";
      }
    }

    my $cardnumfieldtype = "";
    if ($payutils::feature{'cardnumfield'} eq "masked") {
      $cardnumfieldtype = "password";
    }
    else {
      $cardnumfieldtype = "text";
    }
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-number'}\"><span>$payutils::lang_titles{'card_number'}[$payutils::lang]\:<b>*</b></span></td>";
    if (($payutils::query{'keyswipe'} eq "yes") || ($payutils::feature{'keyswipe'} eq "yes")) {
      # for legacy keyswipe ability
      $output .= "<td align=\"left\"><input type=\"$cardnumfieldtype\" name=\"card_number\" value=\"$payutils::query{'card-number'}\" size=\"16\" maxlength=\"20\" onKeyPress=\"return numbersonly(this, event);\" autocomplete=\"off\"></td></tr>\n";
    }
    elsif (($payutils::query{'keyswipe'} eq "secure") || ($payutils::feature{'keyswipe'} eq "secure")) {
      # for secure keyswipe ability
      $output .= "<td align=\"left\"><input type=\"$cardnumfieldtype\" name=\"card_number\" id=\"card_number\" value=\"$payutils::query{'card-number'}\" onKeyPress=\"return noautosubmit(event);\" size=\"16\" autocomplete=\"off\"></td></tr>\n";
      $output .= "<input type=\"hidden\" name=\"magensacc\" id=\"magensacc\" value=\"\">\n";
      $output .= "<input type=\"hidden\" name=\"EncTrack1\" id=\"EncTrack1\" value=\"\">\n";
      $output .= "<input type=\"hidden\" name=\"EncTrack2\" id=\"EncTrack2\" value=\"\">\n";
      $output .= "<input type=\"hidden\" name=\"EncTrack3\" id=\"EncTrack3\" value=\"\">\n";
      $output .= "<input type=\"hidden\" name=\"EncMP\" id=\"EncMP\" value=\"\">\n";
      $output .= "<input type=\"hidden\" name=\"KSN\" id=\"KSN\" value=\"\">\n";
      $output .= "<input type=\"hidden\" name=\"devicesn\" id=\"devicesn\" value=\"\">\n";
      $output .= "<input type=\"hidden\" name=\"MPStatus\" id=\"MPStatus\" value=\"\">\n";
      $output .= "<input type=\"hidden\" name=\"MagnePrintStatus\" id=\"MagnePrintStatus\" value=\"\">\n";
    }
    else {
      $output .= "<td align=\"left\"><input type=\"$cardnumfieldtype\" name=\"card-number\" value=\"$payutils::query{'card-number'}\" size=\"16\" maxlength=\"20\" onKeyPress=\"return numbersonly(this, event);\" autocomplete=\"off\"";
      if ($payutils::query{'amexlev2'} == 1) {
        ## 20110812  JT - show amex level2 fields, when card number entered starts with '3', per David's direction
        $output .= " onBlur=\"if(this.value.charAt(0) == '3') {\$('.amexlev2').css('visibility','visible');\$('.amexlev2').css('display','table-row');} else{\$('.amexlev2').css('visibility','hidden');\$('.amexlev2').css('display','none');}\"";
      }
      $output .= "></td></tr>\n";
    }

    if (($payutils::feature{'cvv'} == 1) || ($payutils::query{'cvv-flag'} eq "yes")) {
      my $cvvfieldtype = "";
      if ($payutils::feature{'cvvfield'} eq "masked") {
        $cvvfieldtype = "password";
      }
      else {
        $cvvfieldtype = "text";
      }
      $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-cvv'}\"><span>$payutils::lang_titles{'card_cvv'}[$payutils::lang]\:$payutils::requiredstar{'card-cvv'}</span></td>";
      $output .= "<td align=\"left\"><input type=\"$cvvfieldtype\" name=\"card-cvv\" value=\"$payutils::query{'card-cvv'}\" size=\"4\" maxlength=\"4\" autocomplete=\"off\"> $payutils::lang_titles{'required'}[$payutils::lang]";

      $output .= " <a href=\"help.cgi?subject=cvv&lang=$payutils::query{'lang'}\" target=\"help\" onClick=\"online_help(300,500)\;\"><font size=\"-2\" color=\"$payutils::goodcolor\"><b>$payutils::lang_titles{'help'}[$payutils::lang]</b></font></a> </td></tr>\n";
    }

    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-exp'}\"><span>$payutils::lang_titles{'card_exp'}[$payutils::lang]\:<b>*</b></span></td> ";
    $output .= "<td align=\"left\">\n";
    if (($payutils::query{'keyswipe'} =~ /(yes|secure)/) || ($payutils::feature{'keyswipe'} =~ /(yes|secure)/)) {
      $output .= "<select name=\"month_exp\">\n";
      my @months = ("01","02","03","04","05","06","07","08","09","10","11","12");
      my ($date) = &miscutils::gendatetime_only();
      my $current_month = substr($date,4,2);
      my $current_year = substr($date,0,4);
      if ($payutils::query{'month_exp'} eq "") {
        $payutils::query{'month_exp'} = $current_month;
      }
      foreach my $var (@months) {
        if ($var eq $payutils::query{'month_exp'}) {
          $output .= "<option value=\"$var\" selected>$var</option>\n";
        }
        else {
          $output .= "<option value=\"$var\">$var</option>\n";
        }
      }
      $output .= "</select> ";

      $output .= "<select name=\"year_exp\">\n";

      if ($payutils::query{'year_exp'} eq ""){
        $payutils::query{'year_exp'} = $current_year;
      }
      for (my $i; $i<=12; $i++) {
        my $var = $current_year + $i;
        my $val = substr($var,2,2);
        if ($val eq $payutils::query{'year_exp'}) {
          $output .= "<option value=\"$val\" selected>$var</option>\n";
        }
        else {
          $output .= "<option value=\"$val\">$var</option>\n";
        }
      }
      $output .= "</select>\n";
    }
    else {
      if ($payutils::query{'nocardexplist'} ne "yes") {
        $output .= "<select name=\"month-exp\">\n";
        my @months = ("01","02","03","04","05","06","07","08","09","10","11","12");
        my ($date) = &miscutils::gendatetime_only();
        my $current_month = substr($date,4,2);
        my $current_year = substr($date,0,4);
        if ($payutils::query{'month-exp'} eq "") {
          $output .= "<option value=\"\" selected>$payutils::lang_titles{'month'}[$payutils::lang]</option>\n";
        }
        foreach my $var (@months) {
          if ($var eq $payutils::query{'month-exp'}) {
            $output .= "<option value=\"$var\" selected>$var</option>\n";
          }
          else {
            $output .= "<option value=\"$var\">$var</option>\n";
          }
        }
        $output .= "</select> ";

        $output .= "<select name=\"year-exp\">\n";

        if ($payutils::query{'year-exp'} eq ""){
          $output .= "<option value=\"\" selected>$payutils::lang_titles{'year'}[$payutils::lang]</option>\n";
        }
        for (my $i; $i<=12; $i++) {
          my $var = $current_year + $i;
          my $val = substr($var,2,2);
          if ($val eq $payutils::query{'year-exp'}) {
            $output .= "<option value=\"$val\" selected>$var</option>\n";
          }
          else {
            $output .= "<option value=\"$val\">$var</option>\n";
          }
        }
        $output .= "</select>\n";
      }
      else {
        $output .= "<input type=\"text\" name=\"month-exp\" value=\"$payutils::query{'month-exp'}\" size=\"2\" maxlength=\"2\" autocomplete=\"off\"> / <input type=\"text\" name=\"year-exp\" value=\"$payutils::query{'year-exp'}\" size=\"2\" maxlength=\"2\" autocomplete=\"off\"> MM/YY\n";
      }
    }
    $output .= "</td></tr>\n";

    if (($payutils::processor =~ /^(pago|barclays)$/) && ($payutils::query{'card-allowed'} =~ /Solo|Switch/i)) {
      $output .= "<tr><td align=\"right\" class=\"$payutils::color{'cardissuenum'}\"><span>$payutils::lang_titles{'cardissuenum'}[$payutils::lang]\:<b>*</b></span></td>";
      $output .= "<td align=\"left\"><input type=\"text\" name=\"cardissuenum\" value=\"$payutils::query{'cardissuenum'}\" size=\"3\" maxlength=\"2\" autocomplete=\"off\"> (Switch/Solo Cards Only)</td></tr>\n";

      $output .= "<tr><td align=\"right\" class=\"$payutils::color{'cardstartdate'}\"><span>$payutils::lang_titles{'cardstartdate'}[$payutils::lang]\:<b>*</b></span></td>";
      $output .= "<td align=\"left\"><input type=\"text\" name=\"cardstartdate\" value=\"$payutils::query{'cardstartdate'}\" size=\"30\" maxlength=\"30\" autocomplete=\"off\"> (Switch/Solo Cards Only)</td></tr>\n";
    }
  }

  if (($payutils::processor eq "psl") && ($payutils::query{'transflags'} =~ /load/i)) {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'walletid'}\"><span>$payutils::lang_titles{'walletid'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"walletid\" value=\"$payutils::query{'walletid'}\" size=\"30\" maxlength=\"49\" autocomplete=\"off\"></td></tr>\n";
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'passcode'}\"><span>$payutils::lang_titles{'passcode'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"> <input type=\"text\" name=\"passcode\" value=\"$payutils::query{'passcode'}\" size=\"30\" maxlength=\"49\" autocomplete=\"off\"></td></tr>\n";
  }
  elsif (($payutils::processor eq "psl") && ($payutils::query{'transflags'} =~ /issue/i)) {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'dateofbirth'}\"><span>$payutils::lang_titles{'dateofbirth'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"> <input type=\"text\" name=\"dateofbirth\" value=\"$payutils::query{'dateofbirth'}\" size=\"10\" maxlength=\"10\" autocomplete=\"off\">MM/DD/YYYY</td></tr>\n";
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'challenge'}\"><span>$payutils::lang_titles{'challenge'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"> <input type=\"text\" name=\"challenge\" value=\"$payutils::query{'challenge'}\" size=\"30\" maxlength=\"49\" autocomplete=\"off\"></td></tr>\n";
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'response'}\"><span>$payutils::lang_titles{'response'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"> <input type=\"text\" name=\"response\" value=\"$payutils::query{'response'}\" size=\"30\" maxlength=\"49\" autocomplete=\"off\"></td></tr>\n";
  }
  elsif (($payutils::processor =~ /^(mercury|testprocessor)$/) && ($payutils::feature{'acceptgift'} == 1)) {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'mpgiftcard'}\"><span>$payutils::lang_titles{'mpgiftcard'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"mpgiftcard\" value=\"$payutils::query{'mpgiftcard'}\" size=\"20\" maxlength=\"30\" autocomplete=\"off\"></td></tr>\n";
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'mpcvv'}\"><span>$payutils::lang_titles{'mpcvv'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"mpcvv\" value=\"$payutils::query{'mpcvv'}\" size=\"4\" maxlength=\"4\" autocomplete=\"off\"></td></tr>\n";
    $output .= "<tr><td>&nbsp;</td><td>$payutils::lang_titles{'giftstatement'}[$payutils::lang]</td></tr>\n";
  }

  if ($payutils::query{'commcardtype'} eq "business") {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'ponumber'}\"><span>$payutils::lang_titles{'ponumber'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"ponumber\" value=\"$payutils::query{'ponumber'}\" size=\"20\" maxlength=\"20\"></td></tr>\n";
  }

  if ($payutils::feature{'noemail'} != 1) {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'email'}\"><span>$payutils::lang_titles{'email'}[$payutils::lang]\:$payutils::requiredstar{'email'}</span></td>";
    if ($payutils::displayonly{'email'} == 1) {
      $output .= "<td align=\"left\"><input type=\"hidden\" name=\"email\" value=\"$payutils::query{'email'}\">$payutils::query{'email'}</td></tr>\n";
    }
    else {
      $output .= "<td align=\"left\"><input type=\"text\" name=\"email\" value=\"$payutils::query{'email'}\" size=\"30\" maxlength=\"49\"></td></tr>\n";
    }
  }

  # 02/16/06 - added ability to use 'nophone' from features
  if (($payutils::feature{'nophone'} != 1) && ($payutils::nophone ne "yes")) {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'phone'}\"><span>$payutils::lang_titles{'phone'}[$payutils::lang]\:$payutils::requiredstar{'phone'}</span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"phone\" value=\"$payutils::query{'phone'}\" size=\"15\" maxlength=\"15\"></td></tr>\n";

    if (($payutils::processor eq "psl") && ($payutils::query{'transflags'} =~ /issue/i)) {
      my (%checked);
      $checked{$payutils::query{'phonetype'}} = ' checked';

      $output .= "<tr><td align=\"right\" class=\"$payutils::color{'phonetype'}\"><span>$payutils::lang_titles{'phonetype'}[$payutils::lang]\:<b>*</b></span></td>";
      $output .= "<td align=\"left\"><input type=\"radio\" name=\"phonetype\" value=\"Home\" $checked{'Home'}> Home\n";
      $output .= "<input type=\"radio\" name=\"phonetype\" value=\"Mobile\" $checked{'Mobile'}> Mobile\n";
      $output .= "<input type=\"radio\" name=\"phonetype\" value=\"Business\" $checked{'Business'}> Business\n";
      $output .= "</td></tr>\n";
    }

    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'fax'}\"><span>$payutils::lang_titles{'fax'}[$payutils::lang]\:$payutils::requiredstar{'fax'}</span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"fax\" value=\"$payutils::query{'fax'}\" size=\"15\" maxlength=\"15\"></td></tr>\n";
  }

  return $output;
}


sub pay_screen1_shipping {
  my $output = '';

  my %selected = ();
  if (($payutils::query{'shipmethod'} eq "UPS") && ($payutils::query{'ups_method_allow'} ne "")) {
    my (%selected);
    my @ups_ship_methods_merchant = split(/\,/,$payutils::query{'ups_method_allow'});
    $output .= "<tr><td align=right class=\"$payutils::color{'shipping'}\"><span>$payutils::lang_titles{'shipmeth'}[$payutils::lang]\:$payutils::requiredstar{'shipping'}</span></td>";
    $output .= "<td align=\"left\">\n";
    $selected{$payutils::query{'serviceLevelCode'}} = " selected";
    $output .= "<select name=\"serviceLevelCode\" size=\"1\">\n";
    $output .= "  <option value=\"NONE\"> $payutils::lang_titles{'servlevcode'}[$payutils::lang] </option>\n";
    foreach my $shippingtype (@ups_ship_methods_merchant) {
      if ($shippingtype ne "") {
        $output .= "  <option value=\"$shippingtype\" $selected{$shippingtype}> $payutils::UPSmethods{$shippingtype} </option>\n";
      }
    }
    $output .= "</select>\n";
    $output .= "</td></tr>\n";
    $payutils::query{'shipinfo'} = 1;
  }
  elsif ($payutils::query{'shipmethod'} eq "eparcel") {
    my ($cnt,%eparcel) = &eParcel('html');
    $output .= "<tr><td align=right class=\"$payutils::color{'shipping'}\"><span>$payutils::lang_titles{'shipmeth'}[$payutils::lang]\:$payutils::requiredstar{'shipping'}</span></td>";
    $output .= "<td align=\"left\">\n";
    $output .= "<table border=0>\n";
    $output .= "<tr><th> &nbsp; </th><th align=\"left\">Service</th><th>$payutils::lang_titles{'deliverydate'}[$payutils::lang]</th><th>Rate</th></tr>\n";
    if ($payutils::query{'serviceLevelCode'} eq "") {
      $payutils::query{'serviceLevelCode'} = "1";
    }
    $selected{$payutils::query{'serviceLevelCode'}} = " checked";
    if ($cnt > 0) {
      for (my $i=1; $i<=$cnt; $i++) {
        $output .= "<tr><td align=\"center\"><input type=\"radio\" name=\"serviceLevelCode\" value=\"$i\" $selected{$i}></td>\n";
        $output .= "<td>$eparcel{\"NAME_$i\"}</td><td align=\"center\">$eparcel{\"DELIVERY_DATE_$i\"}</td><td align=\"right\">$eparcel{\"SHIPPING_RATE_$i\"}</td></tr>\n";
      }
    }
    else {
      $output .= "<tr><th colspan=\"4\">$payutils::lang_titles{'novalid'}[$payutils::lang]</th></tr>\n";
    }
    $output .= "</table>\n";
    foreach my $key (keys %eparcel) {
      $output .= "<input type=\"hidden\" name=\"$key\" value=\"$eparcel{$key}\">\n";
    }
    $output .= "</td></tr>\n";
    $payutils::query{'shipinfo'} = 1;
  }
  #elsif ($payutils::query{'shipmethod'} =~ /^pnp_/i) {
  #}
  elsif ($payutils::query{'shipmethod'} ne "") {
    my @ship_methods_merchant = split(/\,/,$payutils::query{'method-allow'});
    if (@ship_methods_merchant > 0) {
      $output .= "<tr><td align=right class=\"$payutils::color{'shipping'}\"><span>$payutils::lang_titles{'shipping'}[$payutils::lang]\:$payutils::requiredstar{'shipping'}</span></td>";
      $output .= "<td align=\"left\">\n";
      $output .= "<select name=\"serviceLevelCode\" size=\"1\">\n";
      $output .= "  <option value=\"NONE\"> $payutils::lang_titles{'servlevcode'}[$payutils::lang] </option>\n";
      foreach my $shippingtype (@ship_methods_merchant) {
        if ($shippingtype ne "") {
          if ($shippingtype eq $payutils::query{'serviceLevelCode'}) {
            $output .= "  <option value=\"$shippingtype\" selected> $payutils::Ship_Methods{$shippingtype} </option>\n";
          }
          else {
            $output .= "  <option value=\"$shippingtype\"> $payutils::Ship_Methods{$shippingtype} </option>\n";
          }
        }
      }
      $output .= "</select>\n";

      # currently only valid for UPS XML
      if ($payutils::query{'shipmethod'} =~ /UPSX/i) {
        $output .= "<br>\n";
        $output .= "<input type=\"checkbox\" name=\"ship-insurance\" value=\"true\"> <a href=\"help.cgi?subject=shippinginsurance\" target=\"_blank\"> <font size=\"-2\" color=\"$payutils::goodcolor\"> $payutils::lang_titles{'ship-insurance'}[$payutils::lang] (UPS) </font> </a>\n";
      }

      $output .= "</td></tr>\n";
    }
    $payutils::query{'shipinfo'} = 1;
  }

  if (($payutils::digonlyflg == 1) && ($payutils::query{'noshipdigital'} eq "yes")){
    $payutils::query{'shipinfo'} = 0;
  }

  if (($payutils::query{'shipinfo'} == 1) && ($payutils::query{'suppress_shipinfo'} == 1)) {
    $output .= "<input type=\"hidden\" name=\"shipname\" value=\"$payutils::query{'shipname'}\">\n";
    $output .= "<input type=\"hidden\" name=\"shipcompany\" value=\"$payutils::query{'shipcompany'}\">\n";
    $output .= "<input type=\"hidden\" name=\"address1\" value=\"$payutils::query{'address1'}\">\n";
    $output .= "<input type=\"hidden\" name=\"address2\" value=\"$payutils::query{'address2'}\">\n";
    $output .= "<input type=\"hidden\" name=\"city\" value=\"$payutils::query{'city'} \">\n";
    $output .= "<input type=\"hidden\" name=\"state\" value=\"$payutils::query{'state'}\">\n";
    $output .= "<input type=\"hidden\" name=\"province\" value=\"$payutils::query{'province'}\">\n";
    $output .= "<input type=\"hidden\" name=\"zip\" value=\"$payutils::query{'zip'}\">\n";
    $output .= "<input type=\"hidden\" name=\"country\" value=\"$payutils::query{'country'}\">\n";
    $output .= "<input type=\"hidden\" name=\"shipemail\" value=\"$payutils::query{'shipemail'}\">\n";
    $output .= "<input type=\"hidden\" name=\"shipphone\" value=\"$payutils::query{'shipphone'}\">\n";
    $output .= "<input type=\"hidden\" name=\"shipfax\" value=\"$payutils::query{'shipfax'}\">\n";
  }
  elsif ($payutils::query{'shipinfo'} == 1) {
    $output .= "<tr><td align=\"left\" colspan=\"2\" class=\"larger\"><br>";
    if ($payutils::query{'shipinfo-label'} ne "") {
      $output .= "$payutils::query{'shipinfo-label'}</td>\n";
    }
    else {
      $output .= "$payutils::lang_titles{'shipinfo'}[$payutils::lang]\:</td>\n";
    }
    $output .= "\n";

    my %checked = ();
    $checked{$payutils::query{'shipsame'}} = " checked";
    $output .= "<tr><td align=\"left\" colspan=\"2\"><input type=\"checkbox\" name=\"shipsame\" value=\"yes\"$checked{'yes'}>";
    $output .= "$payutils::lang_titles{'shipsame'}[$payutils::lang]</td></tr>\n";

    $output .= "<tr><td align=right class=\"$payutils::color{'shipname'}\"><span>$payutils::lang_titles{'name'}[$payutils::lang]\:$payutils::requiredstar{'shipname'}</span></td>";
    $output .= "<td align=left><input type=\"text\" name=\"shipname\" size=\"30\" value=\"$payutils::query{'shipname'}\" maxlength=\"39\"></td></tr>\n";

    if ($payutils::query{'showshipcompany'} eq "yes") {
      $output .= "<tr><td align=\"right\" class=\"$payutils::color{'shipcompany'}\"><span>$payutils::lang_titles{'company'}[$payutils::lang]\:$payutils::requiredstar{'shipcompany'}</span></td>";
      $output .= "<td align=\"left\"><input type=\"text\" name=\"shipcompany\" size=\"30\" value=\"$payutils::query{'shipcompany'}\" maxlength=\"39\"></td></tr>\n";
    }

    $output .= "<tr><td align=right class=\"$payutils::color{'address1'}\"><span>$payutils::lang_titles{'address1'}[$payutils::lang]\:$payutils::requiredstar{'address1'}</span></td>";
    $output .= "<td align=left><input type=\"text\" name=\"address1\" size=\"30\" value=\"$payutils::query{'address1'}\" maxlength=\"39\"></td></tr>\n";

    $output .= "<tr><td align=right class=\"$payutils::color{'address2'}\"><span>$payutils::lang_titles{'address2'}[$payutils::lang]\:$payutils::requiredstar{'address2'}</span></td>";
    $output .= "<td align=left><input type=\"text\" name=\"address2\" size=\"30\" value=\"$payutils::query{'address2'}\" maxlength=\"39\"></td></tr>\n";

    $output .= "<tr><td align=right class=\"$payutils::color{'city'}\"><span>$payutils::lang_titles{'city'}[$payutils::lang]\:$payutils::requiredstar{'city'}</span></td>";
    $output .= "<td align=left><input type=\"text\" name=\"city\" size=\"20\" value=\"$payutils::query{'city'}\" maxlength=\"30\"></td></tr>";

    if ($payutils::query{'nostatelist'} ne "yes") {
      $output .= "<tr><td ALIGN=\"right\" class=\"$payutils::color{'state'}\"><span>$payutils::lang_titles{'state'}[$payutils::lang]\:$payutils::requiredstar{'state'}</span></td>";
      $output .= "<td align=\"left\"><select name=\"state\">\n";

      my %selected = ();
      $selected{$payutils::query{'state'}} = " selected";
      $output .= "<option value=\"\">$payutils::lang_titles{'selectstate'}[$payutils::lang]</option>\n";
      foreach my $key (&sort_hash(\%constants::USstates)) {
        $output .= "<option value=\"$key\"$selected{$key}>$constants::USstates{$key}</option>\n";
      }
      if ($payutils::usterrflag ne "no") {
        foreach my $key (sort keys %constants::USterritories) {
          $output .= "<option value=\"$key\"$selected{$key}>$constants::USterritories{$key}</option>\n";
        }
      }
      if (($payutils::usonly ne "yes") && ($payutils::uscanonly ne "yes")) {
        foreach my $key (sort keys %constants::CNprovinces) {
          $output .= "<option value=\"$key\"$selected{$key}>$constants::CNprovinces{$key}</option>\n";
        }
      }
      if ($payutils::uscanonly eq "yes") {
        foreach my $key (sort keys %constants::USCNprov) {
          $output .= "<option value=\"$key\"$selected{$key}>$constants::USCNprov{$key}</option>\n";
        }
      }
      $output .= "</select></td></tr>\n";
    }
    else {
      $output .= "<tr><td ALIGN=\"right\" class=\"$payutils::color{'state'}\"><span>$payutils::lang_titles{'state'}[$payutils::lang]\:<b>*</b></span></td>";
      $output .= "<td align=\"left\"><input type=\"text\" name=\"state\" size=\"20\" value=\"$payutils::query{'state'}\" maxlength=\"19\"></td></tr>\n";
    }

    if (($payutils::usonly ne "yes") && ($payutils::uscanonly ne "yes")) {
      $output .= "<tr><td ALIGN=\"right\" class=\"$payutils::color{'province'}\"><span>International Province:$payutils::requiredstar{'province'}</span></td>";
      $output .= "<td align=\"left\"><input type=\"text\" name=\"province\" size=\"20\" value=\"$payutils::query{'province'}\" maxlength=\"19\"></td></tr>\n";
    }

    $output .= "<tr><td align=right class=\"$payutils::color{'zip'}\"><span>$payutils::lang_titles{'zip'}[$payutils::lang]\:$payutils::requiredstar{'zip'}</span></td>";
    $output .= "<td align=left><input type=\"text\" name=\"zip\" size=\"10\" value=\"$payutils::query{'zip'}\" maxlength=\"10\"></td></tr>\n";

    if ($payutils::query{'nocountrylist'} ne "yes") {
      $output .= "<tr><td align=right class=\"$payutils::color{'country'}\"><span>$payutils::lang_titles{'country'}[$payutils::lang]\:$payutils::requiredstar{'country'}</span></td>";
      $output .= "<td align=left><select name=\"country\">\n";

      my %selected = ();
      $selected{$payutils::query{'country'}} = " selected";
      if ($payutils::usonly eq "yes") {
        $output .= "<option value=\"US\" selected>$constants::countries{'US'}</option>\n";
      }
      elsif ($payutils::uscanonly eq "yes") {
        $output .= "<option value=\"US\"$selected{'US'}>$constants::countries{'US'}</option>\n";
        $output .= "<option value=\"CA\"$selected{'CA'}>$constants::countries{'CA'}</option>\n";
      }
      else {
        foreach my $key (&sort_hash(\%constants::countries)) {
          $output .= "<option value=\"$key\"$selected{$key}>$constants::countries{$key}</option>\n";
        }
      }
      $output .= "</select></td></tr>\n";
    }
    else {
      $output .= "<tr><td align=\"right\" class=\"$payutils::color{'country'}\"><span>$payutils::lang_titles{'country'}[$payutils::lang]\:$payutils::requiredstar{'country'}</span></td>";
      $output .= "<td align=\"left\"><input type=\"text\" name=\"country\" size=\"15\" value=\"$payutils::query{'country'}\" maxlength=\"20\"></td></tr>\n";
    }
  }

  if ($payutils::query{'showshipemail'} eq "yes") {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'shipemail'}\"><span>$payutils::lang_titles{'email'}[$payutils::lang]\:$payutils::requiredstar{'shipemail'}</span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"shipemail\" value=\"$payutils::query{'shipemail'}\" size=\"30\" maxlength=\"49\"></td></tr>\n";
  }

  if ($payutils::query{'showshipphone'} eq "yes") {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'shipphone'}\"><span>$payutils::lang_titles{'phone'}[$payutils::lang]\:$payutils::requiredstar{'shipphone'}</span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"shipphone\" value=\"$payutils::query{'shipphone'}\" size=\"15\" maxlength=\"15\"></td></tr>\n";
  }

  if ($payutils::query{'showshipfax'} eq "yes") {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'shipfax'}\"><span>$payutils::lang_titles{'fax'}[$payutils::lang]\:$payutils::requiredstar{'shipfax'}</span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"shipfax\" value=\"$payutils::query{'shipfax'}\" size=\"15\" maxlength=\"15\"></td></tr>\n";
  }

  if ($payutils::query{'comments'} ne "") {
    if ($payutils::query{'comm-title'} ne "") {
      my $commTitle = encode_entities($payutils::query{'comm-title'});
      $output .= "<tr><td align=\"right\" valign=\"top\" class=\"goodcolor\">$commTitle:</td>\n";
    }
    else {
       $output .= "<tr><td align=\"right\"><span>$payutils::lang_titles{'comments'}[$payutils::lang]\:</span></td>\n";
    }
    $output .= "<td align=\"left\"><TEXTAREA name=\"comments\" ROWS=6 COLS=40 onBlur=\"filtercomments();\">$payutils::query{'comments'}</TEXTAREA></td></tr>\n";
  }
  return $output;
}

sub pay_screen1_pairs {
  my $output = '';

  if ($payutils::template{'body_prepairs'} ne "") {
    $output .= "$payutils::template{'body_prepairs'}\n";
  }

  my (%unknownParameters,$rowref);

  if ($ENV{'SCRIPT_NAME'} =~ /payment\/pay\.cgi/) {
    foreach my $var (@payutils::unknownParameters) {
      $unknownParameters{$var} = 1;
    }
    $rowref = &store_pairs(@payutils::unknownParameters);
  }

  $output .= "<tr><td>\n";

  my @doNotPrintAsHiddenInputField = ('company', 'phone', 'fax', 'email', 'shipsame', 'shipname', 'shipcompany', 'address1', 'address2', 'city', 'state', 'province', 'zip', 'country', 'month-exp', 'month_exp', 'year-exp', 'year_exp', 'mpgiftcard', 'mpcvv', 'routingnum', 'accountnum', 'checknum', 'accttype', 'acctclass', 'serviceLevelCode', 'roption', 'uname', 'passwrd1', 'passwrd2', 'pass', 'max', 'tax', 'ssnum', 'ssnum4', 'dateofbirth', 'comments', 'submit', 'response', 'MErrMsg', 'pinnumber', 'web900-pin', 'challenge', 'passphrase', 'promoid', 'walletid', 'passcode', 'cookie_pw', 'wfunction', 'g_recaptcha_response');
  # Note: do not remove the 'month_exp' and 'year_exp' from above list.  They must be here to prevent keyswipe problems.
  my @omitHiddenPairsList = (@payutils::nohidden, @payutils::encrypt_nohidden, @doNotPrintAsHiddenInputField);
  my %omitHiddenPairsHash = map { $payutils::query{$_} ne '' ? ($_ => 1) : () } @omitHiddenPairsList;

  foreach my $key (sort keys %payutils::query) {
    if ((exists $unknownParameters{$key}) || (exists $omitHiddenPairsHash{$key}) || ($key =~ /^card\-/)) {
      # skip everything flagged unknown/omitted or is a card-... field
      next;
    }
    elsif (($payutils::query{$key} ne '') && ($key !~ /^(item|description|cost|quantity|weight|taxable)[0-9]/)) {
      # only list those populated & not related to product itemization
      $output .= "<input type=\"hidden\" name=\"$key\" value=\"$payutils::query{$key}\">\n";
    }
  }

  ### Required to flag the payment as being Smart Screens v1 based
  $output .= "<input type=\"hidden\" name=\"customname99999999\" value=\"payscreensVersion\">\n";
  $output .= "<input type=\"hidden\" name=\"customvalue99999999\" value=\"1\">\n";

  if ($rowref ne "") {
    $output .= "<input type=\"hidden\" name=\"pairsref\" value=\"$rowref\">\n";
  }

  if ($payutils::query{'paymethod'} eq "swipe") {
    if ($payutils::feature{'swipe_address'} == 1) {
      ### Do Nothing
    }
    elsif ($payutils::feature{'swipe_zip'} == 1) {
      ### need all but zip as hidden
      $output .= "<input type=\"hidden\" name=\"card-address1\" value=\"$payutils::query{'card-address1'}\">\n";
      $output .= "<input type=\"hidden\" name=\"card-address2\" value=\"$payutils::query{'card-address2'}\">\n";
      $output .= "<input type=\"hidden\" name=\"card-city\" value=\"$payutils::query{'card-city'}\">\n";
      $output .= "<input type=\"hidden\" name=\"card-state\" value=\"$payutils::query{'card-state'}\">\n";
      $output .= "<input type=\"hidden\" name=\"card-prov\" value=\"$payutils::query{'card-prov'}\">\n";
      $output .= "<input type=\"hidden\" name=\"card-country\" value=\"$payutils::query{'card-country'}\">\n";
    }
    else {
      ### need all hidden
      $output .= "<input type=\"hidden\" name=\"card-address1\" value=\"$payutils::query{'card-address1'}\">\n";
      $output .= "<input type=\"hidden\" name=\"card-address2\" value=\"$payutils::query{'card-address2'}\">\n";
      $output .= "<input type=\"hidden\" name=\"card-city\" value=\"$payutils::query{'card-city'}\">\n";
      $output .= "<input type=\"hidden\" name=\"card-state\" value=\"$payutils::query{'card-state'}\">\n";
      $output .= "<input type=\"hidden\" name=\"card-prov\" value=\"$payutils::query{'card-prov'}\">\n";
      $output .= "<input type=\"hidden\" name=\"card-country\" value=\"$payutils::query{'card-country'}\">\n";
      $output .= "<input type=\"hidden\" name=\"card-zip\" value=\"$payutils::query{'card-zip'}\">\n";
    }
  }

  ## 01/05/11 James - commented out, because its causing duplicate text to appear at bottom of billing page
  if ($payutils::query{'askamtflg'} != 1) {
    $output .= "<input type=\"hidden\" name=\"card-amount\" value=\"$payutils::query{'card-amount'}\">\n";
  }
  $output .= "<input type=\"hidden\" name=\"card-allowed\" value=\"$payutils::query{'card-allowed'}\">\n";
  $output .= "<input type=\"hidden\" name=\"pass\" value=\"1\">\n";

  &taxcalc();

  $output .= sprintf("<input type=\"hidden\" name=\"tax\" value=\"%.2f\">\n", $payutils::query{'tax'});

  if ($payutils::query{'easycart'} == 1) {
    for (my $j=1; $j<=$payutils::max; $j++) {
      $output .= "<input type=\"hidden\" name=\"item$j\" value=\"$payutils::item[$j]\">\n";
      $output .= "<input type=\"hidden\" name=\"quantity$j\" value=\"$payutils::quantity[$j]\">\n";
      $output .= "<input type=\"hidden\" name=\"cost$j\" value=\"$payutils::cost[$j]\">\n";
      $output .= "<input type=\"hidden\" name=\"description$j\" value=\"$payutils::description[$j]\">\n";
      if ($payutils::taxable[$j] ne "") {
        $output .= "<input type=\"hidden\" name=\"taxable$j\" value=\"$payutils::taxable[$j]\">\n";
      }
      if ($payutils::weight[$j] ne "") {
        $output .= "<input type=\"hidden\" name=\"weight$j\" value=\"$payutils::weight[$j]\">\n";
      }
    }
    $output .= "<input type=\"hidden\"\n name=\"max\" value=\"$payutils::max\">\n";
    if ($payutils::upsellflag == 1) {
      $output .= "<input type=\"hidden\" name=\"plan1000\" value=\"\">\n";
      $output .= "<input type=\"hidden\" name=\"item1000\" value=\"\">\n";
      $output .= "<input type=\"hidden\" name=\"quantity1000\" value=\"\">\n";
      $output .= "<input type=\"hidden\" name=\"cost1000\" value=\"\">\n";
      $output .= "<input type=\"hidden\" name=\"description1000\" value=\"\">\n";
      $output .= "<input type=\"hidden\" name=\"upsell\" value=\"\">\n";
    }
  }
  $output .= "</td>\n";

  if ($payutils::template{'body_postpairs'} ne "") {
    $output .= "$payutils::template{'body_postpairs'}\n";
  }

  return $output;
}


sub pay_screen1_tail {
  my $output = '';

  $output .= "\n";
  $output .= "\n";
  my $submit_label = "";
  if ($payutils::feature{'submit_pg1'} ne "") {
    $submit_label = "$payutils::feature{'submit_pg1'}";
  }
  elsif ($payutils::feature{'skipsummaryflg'} == 1) {
    $submit_label = "$payutils::lang_titles{'submitpay'}[$payutils::lang]\" onClick=\"return(mybutton(this.form));";
  }
  else {
    $submit_label = "$payutils::lang_titles{'summorder'}[$payutils::lang]";
  }
  $output .= "<tr><td></td><td align=\"left\">";

  $output .= "<input type=\"submit\" value=\"$submit_label\"> ";

  if ($payutils::feature{'skipresetflg'} != 1) {
    if (($payutils::query{'keyswipe'} eq "secure") || ($payutils::feature{'keyswipe'} eq "secure")) {
      $output .= " <input type=\"reset\" value=\"$payutils::lang_titles{'reset'}[$payutils::lang]\" onClick=\"document.pay.reset();document.pay.card_number.focus();\"></td></tr>\n";
    }
    else {
      $output .= "<input type=\"reset\" value=\"$payutils::lang_titles{'reset'}[$payutils::lang]\">";
    }
  }
  $output .= "</td></tr>\n";

  if (($payutils::feature{'hide_security_policy'} != 1) && ($payutils::pl_feature{'hide_security_policy'} != 1)) {
    if ($payutils::query{'privacy_url'} ne "") {
      $output .= "<tr><td align=\"left\" colspan=\"2\"><a href=\"$payutils::query{'privacy_url'}\" target=\"newWin\"><font size=\"1\">$payutils::lang_titles{'privpol'}[$payutils::lang]</font></a> &nbsp; </td></tr>\n";
    }
    else {
      $output .= "<tr><td align=\"left\" colspan=\"2\"><a href=\"PrivacyPolicy.html\" target=\"newWin\"><font size=\"1\">$payutils::lang_titles{'privpol'}[$payutils::lang]</font></a> &nbsp; </td></tr>\n";
    }
  }
  if ($payutils::query{'return_url'} ne "") {
    $output .= "<tr><td colspan=\"2\"><a href=\"$payutils::query{'return_url'}\" target=\"newWin\"><font size=\"1\">$payutils::lang_titles{'creditpol'}[$payutils::lang]</font></a> &nbsp; </td></tr>\n";
  }
  if ($payutils::query{'shipping_url'} ne "") {
    $output .= "<tr><td colspan=\"2\"><a href=\"$payutils::query{'shipping_url'}\" target=\"newWin\"><font size=\"1\">$payutils::lang_titles{'ship_pol'}[$payutils::lang]</font></a> &nbsp; </td></tr>\n";
  }

  if (($payutils::feature{'securecode'} == 1) || ($payutils::feature{'seal'} == 1)) {
    $output .= "<tr><td align=\"left\" colspan=\"2\"><br><br>\n";
    if ($payutils::feature{'seal'} == 1) {
      if ($ENV{'SERVER_NAME'} =~ /pay1\.plugnpay\.com/i) {
        $output .= "<script src=\"https://seal.verisign.com/getseal\?host_name=pay1.plugnpay.com\&size=S\&use_flash=NO\&use_transparent=NO\"></script>\n";
      }
      elsif ($ENV{'SERVER_NAME'} =~ /payments\.lawpay\.com/i) {
        $output .= "<span id=\"siteseal\"><script type=\"text/javascript\" src=\"https://seal.godaddy.com/getSeal\?sealID=m6kNHoaqAADYf4bSIRazgNdZroQQbTRRI3PptroIQQd5M2AZmfZ2w7\"></script></span>\n";
      }
    }
    if ($payutils::feature{'securecode'} == 1) {
      $output .= " &nbsp;<img src=\"/logos/securecode/sclogo_80x44.gif\"> &nbsp; ";
    }
    $output .= "</td></tr>\n";
  }

  if ($payutils::feature{'vbvlogos'} == 1) {
      $output .= "<tr><td align=\"left\" valign=\"middle\" colspan=\"2\"><br><br>\n";
      $output .= "<a href=\"http://www.mastercardsecurecode.com\" target=\"vbvwin\">";
      $output .= "<img src=\"/logos/securecode/sclogolearn_80x44.gif\" border=\"0\">";
      $output .= "</a> &nbsp;\n";
      $output .= "<a href=\"https://verified.visa.com\" target=\"vbvwin\">";
      $output .= "<img src=\"/logos/securecode/vbv_learn_more.gif\" border=\"0\">";
      $output .= "</a>\n";
      $output .= "<br>\n";
      $output .= "<br>\n";
      $output .= "Your card may be eligible or enrolled in Verified by Visa, MasterCard SecureCode or\n";
      $output .= "JCB J/Secure payer authentication programs. After clicking the \'Submit Order\' button,\n";
      $output .= "your Card Issuer may prompt you for your payer authentication password to complete\n";
      $output .= "your purchase\n";
      $output .= "</td></tr>\n";
  }
  $output .= "</table>\n";
  $output .= "</form>\n";
  $output .= "</div>\n\n";

  $output .= "<div id=\"tail\">\n";

  $output .= "</div>\n";

  $output .= "\n\n<!--  START OF CUSTOMIZEABLE TAIL SECTION --> \n\n";
  if ($payutils::template{'tail'} ne "") {
    $output .= "$payutils::template{'tail'}\n";
  }
  $output .= "\n\n<!--  END OF CUSTOMIZEABLE TAIL SECTION --> \n\n";

  $output .= "</body>\n";
  $output .= "</html>";

  return $output;
}


sub pay_screen2_head {
  my $output = '';
  
  $payutils::query{'attempts'}++;

  if ($payutils::template{'doctype'} ne "") {
    $output .= "$payutils::template{'doctype'}\n";
  }
  else {
    $output .= "<!DOCTYPE html>\n";
  }

  $output .= "<html>\n";
  $output .= "<head>\n";
  $output .= "<title>Order Confirmation Screen</title> \n";

  ###  DCP  Moved above inserting custom template to allow default stylesheet to be overwritten
  $output .= "<style type=\"text/css\">\n";
  $output .= "<!--\n";
  $output .= "th { font-family: $payutils::fontface; font-size: 10pt; color: $payutils::goodcolor }\n";
  $output .= "td { font-family: $payutils::fontface; font-size: 9pt; color: $payutils::goodcolor }\n";
  $output .= ".badcolor { color: $payutils::badcolor }\n";
  $output .= ".goodcolor { color: $payutils::goodcolor }\n";
  $output .= ".larger { font-size: 100% }\n";
  $output .= ".smaller { font-size: 60% }\n";
  $output .= ".short { font-size: 8% }\n";
  $output .= ".itemscolor { background-color: $payutils::titlebackcolor; color: $payutils::titlecolor }\n";
  $output .= ".itemrows { background-color: $payutils::itemrow }\n";
  $output .= ".items { position: static }\n";
  $output .= "#badcard { position: static; color: red; border: solid red }\n";
  $output .= ".info { position: static }\n";
  $output .= "#tail { position: static }\n";
  $output .= "-->\n";
  $output .= "</style>\n";

  if ($payutils::query{'lang'} ne "") {
    $output .= "<meta content=\"text/html; charset=UTF-8\" http-equiv=\"content-type\"/>\n";
  }
  $output .= "\n\n<!--  START OF CUSTOMIZEABLE HEAD SECTION --> \n\n";
  if ($payutils::template{'head'} ne "") {
    $output .= "$payutils::template{'head'}\n";
  }
  $output .= "\n\n<!--  END OF CUSTOMIZEABLE HEAD SECTION --> \n\n";

  $output .= "<SCRIPT LANGUAGE=\"JavaScript\">\n";

  $output .= " // beginning of script checking\n";
  $output .= "pressed_flag = 0;\n";
  $output .= "function mybutton(form) {\n";
  $output .= "  if (pressed_flag == 0) {\n";
  $output .= "    pressed_flag = 1;\n";
  $output .= "    return true;\n";
  $output .= "  }\n";
  $output .= "  else {\n";
  $output .= "    return false;\n";
  $output .= "  }\n";
  $output .= "}\n";

  $output .= "function goback(form) {\n";
  $output .= "  document.pay.action = \"" . $payutils::query{'path_cgi'} . "\";\n";
  $output .= "  document.pay.pass.value = \"0\";\n";
  $output .= "  document.pay.submit();\n";
  $output .= "}\n";

  if ($payutils::feature{'indicate_processing'} ne "") {
    $output .= "function is_processing(recon) {\n";
    $output .= "  if (recon == 'true') {\n";
    $output .= "    document.getElementById('processingStatement').style.visibility = \"visible\";\n";
    $output .= "  }\n";
    $output .= "  else {\n";
    $output .= "    document.getElementById('processingStatement').style.visibility = \"hidden\";\n";
    $output .= "  }\n";
    $output .= "}\n";
  }

  $output .= "</SCRIPT>\n";

  if ($payutils::feature{'use_captcha'} == 1) {
    my $recaptcha = new PlugNPay::Util::Captcha::ReCaptcha();
    $output .= $recaptcha->headHTML({ version => 2 });
  }

  $output .= "</head>\n";

  if ($payutils::feature{'css-link'} ne "") {
    $output .= "<link href=\"$payutils::feature{'css-link'}\" type=\"text/css\" rel= \"stylesheet\">\n";
  }

  if ($payutils::backimage eq "") {
    $output .= "<body bgcolor=\"$payutils::backcolor\" link=\"$payutils::linkcolor\" text=\"$payutils::goodcolor\" alink=\"$payutils::alinkcolor\" vlink=\"$payutils::vlinkcolor\">\n";
  }
  else {
    $output .= "<body bgcolor=\"$payutils::backcolor\" link=\"$payutils::linkcolor\" text=\"$payutils::goodcolor\" alink=\"$payutils::alinkcolor\" vlink=\"$payutils::vlinkcolor\" background=\"$payutils::backimage\">\n";
  }

  if ($payutils::query{'image-placement'} eq "") {
    $payutils::query{'image-placement'} = "center";
  }

  my $imagehtml = "";
  if ($payutils::query{'image-anchor'} =~ /^http/i) {
    $imagehtml = "<a href=\"$payutils::query{'image-anchor'}\"><img src=\"$payutils::query{'image-link'}\" border=\"0\"></a>\n";
  }
  else {
    $imagehtml ="<img src=\"$payutils::query{'image-link'}\">";
  }

  $output .= "\n\n<!--  START OF CUSTOMIZEABLE TOP SECTION --> \n\n";

  if ($payutils::template{'top'} ne "") {
    $output .= "$payutils::template{'top'}\n";
  }
  elsif (($payutils::query{'image-link'} ne "") && ($payutils::query{'image-placement'} ne "left")) {
    $output .= "<div align=\"$payutils::query{'image-placement'}\">\n";
    $output .= "$imagehtml\n";
    $output .= "</div>\n";
  }

  $output .= "\n\n<!--  END OF CUSTOMIZEABLE TOP SECTION --> \n\n";

  return $output;
}


sub pay_screen2_table {
  my $output = '';

  my ($discount, $discount_type);

  my $imagehtml = "";
  if ($payutils::query{'image-anchor'} =~ /^http/i) {
    $imagehtml = "<a href=\"$payutils::query{'image-anchor'}\"><img src=\"$payutils::query{'image-link'}\"></a>\n";
  }
  else {
    $imagehtml ="<img src=\"$payutils::query{'image-link'}\">";
  }

  $output .= "<div align=\"center\" class=\"info\">\n";
  $output .= "<table border=\"0\" cellspacing=\"0\" cellpadding=\"4\" width=\"600\">\n";
  $output .= "<tr valign=\"top\">\n";
  if (($payutils::query{'image-placement'} eq "left") && ($payutils::query{'image-link'} ne "")) {
     $output .= "<td height=\"1\" rowspan=\"2\" align=\"right\" valign=\"top\">$imagehtml</td>\n";
  }
  else {
    $output .= "<td width=\"50\" height=\"1\" rowspan=\"2\"> &nbsp; </td>\n";
  }
  $output .= "<td width=\"440\" height=\"1\" rowspan=\"1\" colspan=\"2\"> &nbsp; </td></tr>\n";

  if ($payutils::query{'easycart'} == 1) {
    $output .= "<tr><td valign=\"bottom\" colspan=\"2\">\n\n";

    $output .= "<div id=\"paytable\">\n";
    $output .= "<table cellspacing=\"0\" cellpadding=\"1\" border=\"0\" width=\"550\">\n";
    $output .= "<tr>\n";
    my ($columns);
    if ($payutils::query{'showskus'} eq "yes") {
      $columns = 4;
      $output .= "<th align=\"left\" class=\"itemscolor\">$payutils::lang_titles{'modelnum'}[$payutils::lang]</th>\n";
    }
    else {
      $columns = 3;
    }
    $output .= "<th align=\"left\" class=\"itemscolor\">$payutils::lang_titles{'description'}[$payutils::lang]</th>\n";
    $output .= "<th class=\"itemscolor\" align=\"right\">$payutils::lang_titles{'price'}[$payutils::lang]</th>\n";
    $output .= "<th class=\"itemscolor\" align=\"right\">$payutils::lang_titles{'qty'}[$payutils::lang]</th>\n";
    $output .= "<th class=\"itemscolor\" align=\"right\">$payutils::lang_titles{'amount'}[$payutils::lang]</th>\n";
    $output .= "</tr>\n";

    for (my $j=1; $j<=$payutils::max; $j++) {
      $output .= "<tr class=\"itemrows\">";
      if ($payutils::query{'showskus'} eq "yes") {
        $output .= "<td align=\"left\" class=\"itemrows\">$payutils::item[$j]</td>\n";
      }
      $output .= "<td align=\"left\" class=\"itemrows\">$payutils::description[$j]</td>\n";
      $output .= sprintf("<td align=\"right\" class=\"itemrows\">$payutils::query{'currency_symbol'}%.2f</td>\n", $payutils::cost[$j]);
      $output .= "<td align=\"right\" class=\"itemrows\">$payutils::quantity[$j]</td>\n";
      $output .= sprintf("<td align=\"right\" class=\"itemrows\">$payutils::query{'currency_symbol'}%.2f</td>\n",$payutils::ext[$j]);
      $output .= "</tr>";
    }

    if (($payutils::couponflag == 1) || ($payutils::feature{'couponflag'} == 1)) {
      ($discount) = &calculate_discnt();
      if (($discount > 0) && ($payutils::gift_coupon != 1)) {
        $output .= "<tr><th align=\"left\" colspan=\"$columns\">$payutils::lang_titles{'discount'}[$payutils::lang]</th>\n";
        $output .= sprintf("<td align=\"right\">$payutils::query{'currency_symbol'}%.2f</td></tr>\n", $discount);
      }
    }

    $payutils::subtotal = &Round($payutils::subtotal);
    $output .= "<tr><th align=\"left\" colspan=\"$columns\">$payutils::lang_titles{'subtotal'}[$payutils::lang]</th>\n";
    $output .= sprintf("<td align=\"right\">$payutils::query{'currency_symbol'}%.2f</td></tr>\n", $payutils::subtotal);

    if ($payutils::query{'shipping'} > 0) {
      $payutils::query{'shipping'} = &Round($payutils::query{'shipping'});
      if ($payutils::query{'shiplabel'} eq "") {
        $output .= "<tr><th align=\"left\" colspan=\"$columns\">$payutils::lang_titles{'shipping'}[$payutils::lang]</th>\n";
        $output .= sprintf("<td align=\"right\">$payutils::query{'currency_symbol'}%.2f</td></tr>\n", $payutils::query{'shipping'});
      }
      else {
        $output .= "<tr><th align=\"left\" colspan=\"$columns\">$payutils::query{'shiplabel'}</th>\n";
        $output .= sprintf("<td align=\"right\">$payutils::query{'currency_symbol'}%.2f</td></tr>\n", $payutils::query{'shipping'});
      }
    }

    if ($payutils::query{'handling'} > 0) {
      $payutils::query{'handling'} = &Round($payutils::query{'handling'});
      $output .= "<tr><th align=\"left\" colspan=\"$columns\">$payutils::lang_titles{'handling'}[$payutils::lang]</th>\n";
      $output .= sprintf("<td align=\"right\">$payutils::query{'currency_symbol'}%.2f</td></tr>\n", $payutils::query{'handling'});
    }

    if ($payutils::query{'publisher-name'} !~ /^(constructio|scanaloginc)$/) {
      &certitaxcalc();
    }
    &taxcalc();
    $payutils::query{'card-amount'} = $payutils::subtotal + $payutils::query{'shipping'} + $payutils::query{'tax'} + $payutils::query{'handling'};

    if ($payutils::query{'tax'} > 0) {
      $output .= "<tr><th align=\"left\" colspan=\"$columns\">$payutils::lang_titles{'tax'}[$payutils::lang]</th>\n";
      $output .= sprintf("<td align=\"right\">$payutils::query{'currency_symbol'}%.2f</td></tr>\n", $payutils::query{'tax'});
    }

    if ((($payutils::couponflag == 1) || ($payutils::feature{'couponflag'} == 1)) && ($payutils::gift_coupon == 1)) {
      my $prediscount_total = $payutils::query{'card-amount'};
      ($discount) = &calculate_gift_cert_discnt();
      $output .= "<tr><th align=\"left\" colspan=\"$columns\">$payutils::lang_titles{'giftcert'}[$payutils::lang]</th>\n";
      $output .= sprintf("<td align=\"right\">$payutils::query{'currency_symbol'}%.2f</td></tr>\n", $discount);
      if (($discount >= $prediscount_total) && ($payutils::query{'card-amount'} <= 0)) {
        $payutils::query{'card-amount'} = 0.00;
        $payutils::query{'paymethod'} = "invoice";
      }
      elsif ($discount == $prediscount_total) {
        $payutils::query{'card-amount'} -= $discount;
        $payutils::query{'paymethod'} = "invoice";
      }
    }

    if ($payutils::query{'acct_code3'} eq "billpay") {
      ($discount) = &calculate_discnt();
      $discount = &Round($discount);
      if (($discount > 0) && ($payutils::query{'acct_code3'} eq "billpay")) {
        $output .= "<tr><th align=\"left\" colspan=\"$columns\">$payutils::lang_titles{'discount'}[$payutils::lang]</th>\n";
        $output .= sprintf("<td align=\"right\">$payutils::query{'currency_symbol'}%.2f</td></tr>\n", $discount);

        $payutils::query{'card-amount'} -= $discount;
        if ($payutils::query{'card-amount'} <= 0) {
          $payutils::query{'card-amount'} = 0.00;
          $payutils::query{'paymethod'} = "invoice";
        }
      }
    }

    my $display_total = $payutils::query{'card-amount'};
    if (($payutils::feature{'conv_fee'} ne "") && ($payutils::query{'override_adjustment'} != 1)) {
      my ($feeamt, $fee_acct, $failrule) = &conv_fee();
      if ($feeamt > 0) {
        $display_total += $feeamt;
        $output .= "<tr><th align=\"left\" colspan=\"$columns\">$payutils::lang_titles{'convfee'}[$payutils::lang]</th>\n";
        $output .= sprintf("<TD align=\"right\">$payutils::query{'currency_symbol'}%.2f</td></tr>\n", $feeamt);
      }
    }

    if ($payutils::feature{'cardcharge'} ne "") {
      my $adjustment = &cardcharge();
      if ($adjustment > 0) {
        $output .= "<tr><th align=\"left\" colspan=\"$columns\">Card Fee</th>\n";
        $output .= sprintf("<td align=\"right\">$payutils::query{'currency_symbol'}%.2f</td></tr>\n", $adjustment);
      }
      elsif ($adjustment < 0) {
        $output .= "<tr><th align=\"left\" colspan=\"$columns\">Card Discount</th>\n";
        $output .= sprintf("<td align=\"right\">$payutils::query{'currency_symbol'}%.2f</td></tr>\n", $adjustment);
      }
      $display_total += $adjustment;
      $payutils::query{'cardcharge_adjustment'} = $adjustment;
    }

    $output .= "<tr><th align=\"left\" colspan=\"$columns\">$payutils::lang_titles{'total'}[$payutils::lang]</th>\n";
    $output .= sprintf("<TD align=\"right\">$payutils::query{'currency_symbol'}%.2f</td></tr>\n", $display_total);

    $output .= "</table>\n";
    $output .= "</div>\n";
  }
  elsif ($payutils::query{'card-amount'} > 0) {

    my $displayTotal = $payutils::query{'card-amount'};
    if ($payutils::feature{'cardcharge'} ne "") {
      my $adjustment = &cardcharge();
      $displayTotal += $adjustment;
      $payutils::query{'cardcharge_adjustment'} = $adjustment;
    }
    $displayTotal =  sprintf("%.2f",$displayTotal);

    $output .= "<tr><td class=\"larger\">$payutils::lang_titles{'amttocharge'}[$payutils::lang]\: <b>$payutils::query{'currency_symbol'}$displayTotal</b></td></tr>\n";
  }
  else {
    $output .= "<tr><td colspan=\"2\"> &nbsp; </td></tr>\n";
  }
# print mercury gift card and cc total after total is calculated
    if (($payutils::processor eq "mercury") && ($payutils::feature{'acceptgift'} == 1)) {
      if ($payutils::query{'mpgiftcard'} ne "") {
        my ($gc_amount,$cc_amount) = 0;
        if ($payutils::query{'card-amount'} <= $payutils::mpgiftcard_balance) {
           $gc_amount = $payutils::query{'card-amount'};
        }
        else {
           $gc_amount = $payutils::mpgiftcard_balance;
           $cc_amount = $payutils::query{'card-amount'} - $payutils::mpgiftcard_balance;
        }
        $output .= "<tr><td width=\"50\" height=\"1\" rowspan=\"3\"> &nbsp; </td>\n";
        $output .= "<td width=\"440\" height=\"1\" rowspan=\"1\" colspan=\"2\"> &nbsp; </td></tr>\n";
        $payutils::lang_titles{'mpgiftcardsummary'}[$payutils::lang] =~ s/\[pnp_balance\]/$payutils::query{'currency_symbol'}$payutils::mpgiftcard_balance/;
        $output .= "<tr><td align=\"left\" colspan=\"2\">$payutils::lang_titles{'mpgiftcardsummary'}[$payutils::lang]</td></tr>\n";
        $output .= "<tr><td align=\"left\" colspan=\"2\">$payutils::lang_titles{'mpgiftcardamount'}[$payutils::lang]: ";
        $output .= sprintf("<b>$payutils::query{'currency_symbol'}%.2f</b></td></tr>\n", $gc_amount);

        if (($payutils::query{'card-number'} ne "") || ($payutils::query{'card_number'} ne "")) {
          $output .= "<tr><td width=\"50\" height=\"1\" rowspan=\"2\"> &nbsp; </td></tr>\n";
          $output .= "<tr><td align=\"left\" colspan=\"2\">$payutils::lang_titles{'creditcardamount'}[$payutils::lang]: ";
          $output .= sprintf("<b>$payutils::query{'currency_symbol'}%.2f</b></td></tr>\n", $cc_amount);
        }
	      $output .= "<tr><td>&nbsp;</td></tr>\n";
      }
    }

    return $output;
}


sub pay_screen2_body {
  my $output = '';

  my $env = new PlugNPay::Environment();
  my $remoteIP = $env->get('PNP_CLIENT_IP');
  my ($url);
  if (exists $payutils::query{'path_invoice_cgi'}) {
    $url = "$payutils::query{'path_invoice_cgi'}";
  }
  else {
    $url = "https://" . $ENV{'SERVER_NAME'} . "/payment/$payutils::query{'publisher-name'}.cgi";
  }

  $output .= "<SCRIPT LANGUAGE=\"JavaScript\"> \n";
  $output .= "<\!-- Begin \n";
  $output .= "function disableForm(theform) { \n";
  $output .= "  if (document.all || document.getElementById) { \n";
  $output .= "    for (i = 0; i < theform.length; i++) { \n";
  $output .= "      var tempobj = theform.elements[i]; \n";
  $output .= "      if (tempobj.type.toLowerCase() == \"submit\" || tempobj.type.toLowerCase() == \"reset\") \n";
  $output .= "        tempobj.disabled = true; \n";
  $output .= "    } \n";
  $output .= "    return true; \n";
  $output .= "  } \n";
  $output .= "  else { \n";
  $output .= "    return true; \n";
  $output .= "  } \n";
  $output .= "} \n";
  $output .= "//  End --> \n";
  $output .= "</script> \n";

  $output .= "<tr><td>&nbsp; <form method=\"post\" name=\"pay\" action=\"$url\" onSubmit=\"return disableForm(this);\">\n";
  $output .= "</td>\n";


  $output .= "<td colspan=\"2\" align=\"left\">\n";
  if ($payutils::error_string ne "") {
    $output .= "$payutils::error_string<br>\n";
  }

  $output .= "$payutils::lang_titles{'carefully'}[$payutils::lang]</td></tr>\n";

  if ($payutils::query{'shipinfo'} ne "") {
    $output .= "<tr><td> &nbsp; </td><td width=\"50%\" valign=\"top\">\n";
  }
  else {
    $output .= "<tr><td> &nbsp; </td><td colspan=\"2\">\n";
  }
  $output .= "$payutils::lang_titles{'billinginfo'}[$payutils::lang]<br>\n";
  $output .= "$payutils::query{'card-name'}<br>\n";
  if ($payutils::query{'card-company'} ne "") {
    $output .= "$payutils::query{'card-company'} <br>\n";
  }
  $output .= "$payutils::query{'card-address1'}<br>\n";
  if ($payutils::query{'card-address2'} ne "") {
    $output .= "$payutils::query{'card-address2'}<br>\n";
  }
  $output .= "$payutils::query{'card-city'}, $payutils::query{'card-state'}  $payutils::query{'card-zip'}<br>\n";
  if ($payutils::query{'card-prov'} ne "") {
    $output .= "$payutils::query{'card-prov'}<br>\n";
  }
  $output .= $constants::countries{"$payutils::query{'card-country'}"} . "<br>\n";
  if (($payutils::query{'paymethod'} ne "check") && ($payutils::query{'accountnum'} eq "")){
    my $cardnumber = $payutils::query{'card-number'};
    if ($payutils::query{'card-number'} ne "") {
      my $last4 = substr($payutils::query{'card-number'},-4);
      my $nice_number = $payutils::query{'card-number'};
      $nice_number =~ s/[0-9]/X/g;
      $nice_number = substr($nice_number,0,length($nice_number)-4) . $last4;
      my $cardexp = "$payutils::query{'month-exp'}/$payutils::query{'year-exp'}";
      if ($payutils::feature{'maskexp'} == 1) {
        $cardexp =~ s/\d/X/g;
      }
      $output .= "$nice_number  Exp. Date: $cardexp <br>\n";
    }
  }
  elsif ($payutils::query{'accountnum'} ne "") {
    $output .= "<br>$payutils::lang_titles{'routingnum'}[$payutils::lang]\: $payutils::query{'routingnum'}<br>\n";
    $output .= "$payutils::lang_titles{'accountnum'}[$payutils::lang]\: $payutils::query{'accountnum'}<br>\n";
    $output .= "$payutils::lang_titles{'checknum'}[$payutils::lang]\: $payutils::query{'checknum'}<br>\n";

    if ($payutils::query{'accttype'} ne "") {
      $output .= "$payutils::lang_titles{'accttype'}[$payutils::lang]: $payutils::query{'accttype'}<br>\n";
    }
    if ($payutils::chkprocessor =~ /^(telecheck|paymentdata)$/) {
      $output .= "$payutils::lang_titles{'checktype'}[$payutils::lang]: $payutils::query{'acctclass'}<br>\n";
    }
    elsif ($payutils::query{'acctclass'} ne "") {
      $output .= "$payutils::lang_titles{'acctclass'}[$payutils::lang]: $payutils::query{'acctclass'}<br>\n";
    }
    $output .= "<br>\n";
  }
  $output .= "$payutils::query{'email'}<br>\n";
  if ($payutils::query{'phone'} ne "") {
    $output .= "$payutils::lang_titles{'phone'}[$payutils::lang]: $payutils::query{'phone'}<br>\n";
  }
  if ($payutils::query{'fax'} ne "") {
    $output .= "$payutils::lang_titles{'fax'}[$payutils::lang]\: $payutils::query{'fax'}<br>\n";
  }
  $output .= "</td>\n";
  if ($payutils::query{'shipinfo'} eq "1") {
    $output .= "<td  width=\"50%\" valign=\"top\">\n";
    if ($payutils::query{'shipinfo-label'} ne "") {
      $output .= "<b>$payutils::query{'shipinfo-label'}</b><br>\n";
    }
    else {
      $output .= "$payutils::lang_titles{'shippinginfo'}[$payutils::lang]<br>\n";
    }
    $output .= "$payutils::query{'shipname'}<br>\n";
    if ($payutils::query{'shipcompany'} ne "") {
      $output .= "$payutils::query{'shipcompany'}<br>";
    }
    $output .= "$payutils::query{'address1'}<br>\n";
    if ($payutils::query{'address2'} ne "") {
      $output .= "$payutils::query{'address2'}<br>\n";
    }
    $output .= "$payutils::query{'city'}, $payutils::query{'state'} $payutils::query{'zip'}<br>\n";
    if ($payutils::query{'province'} ne "") {
      $output .= "$payutils::query{'province'}<br>\n";
    }
    $output .= "$constants::countries{\"$payutils::query{'country'}\"}<br><br>\n";
    if ($payutils::query{'shipemail'} ne "") {
      $output .= "$payutils::query{'shipemail'}<br>\n";
    }
    if ($payutils::query{'shipphone'} ne "") {
      $output .= "$payutils::lang_titles{'phone'}[$payutils::lang]\: $payutils::query{'shipphone'}<br>\n";
    }
    if ($payutils::query{'shipfax'} ne "") {
      $output .= "$payutils::lang_titles{'fax'}[$payutils::lang]\: $payutils::query{'shipfax'}<br>\n";
    }

    $output .= "<br>\n\n";
    $output .= "</td></tr>\n";
  }
  else {
    $output .= "</tr>\n";
  }

  $output .= "<tr><td> &nbsp; </td><td colspan=\"2\">";

  if (($payutils::allow_cookie eq "yes") && ($payutils::query{'cookie_pw1'} ne "")) {
    $output .= "<b>PnPExpress Password</b><br>\n";
    $output .= "$payutils::query{'cookie_pw1'}<br>\n";
  }

  if (($payutils::query{'passwrd1'} ne "") && ($payutils::query{'uname'} ne "") && (($payutils::query{'suppress_unpw'} ne "yes") && ($payutils::query{'suppress-unpw'} ne "yes"))) {
    $output .= "<b class=\"badcolor larger\">$payutils::lang_titles{'notice'}[$payutils::lang]</b><br>\n";
    $output .= "$payutils::lang_titles{'pleasecopy'}[$payutils::lang]\n";
    $output .= "<b>$payutils::lang_titles{'username'}[$payutils::lang]\: $payutils::query{'uname'}<br>\n";
    $output .= "$payutils::lang_titles{'password'}[$payutils::lang]\: $payutils::query{'passwrd1'}</b><br>\n";
    $output .= "$payutils::lang_titles{'unpasswrd5'}[$payutils::lang]\n";
  }
  $output .= "</td></tr>\n";

  if ($payutils::feature{'use_captcha'} == 1) {
    my $recaptcha = new PlugNPay::Util::Captcha::ReCaptcha();
    $output .= "<tr><td colspan=\"3\" align=\"center\">\n";
    $output .= $recaptcha->formHTML({ version => 2 });
    $output .= "</td></tr>\n";
  }

  return $output;
}


sub pay_screen2_pairs {
  my $output = '';

  my(%nohidden);
  $output .= "<tr><td colspan=\"3\">\n";
  if (exists $payutils::query{'comments'}) {
    $payutils::query{'comments'} =~ s/\"/\&quot\;/g;
  }
  foreach my $var (@payutils::encrypt_nohidden) {
    $nohidden{$var} = 1;
  }
  foreach my $key (sort keys %payutils::query) {
    if (($key eq "orderID") || (exists $nohidden{$key})) {
       next;
    }
    $output .= "<input type=\"hidden\"\n name=\"$key\" value=\"$payutils::query{$key}\">";
  }
  $output .= "<input type=\"hidden\"\n name=\"orderID\" value=\"$payutils::orderID\">";
  $output .= "</td></tr>\n";
}


sub pay_screen2_tail {
  my $output = '';

  $output .= "<tr><td colspan=\"3\" align=\"center\">\n";
  $output .= "<div align=\"left\">\n";
  if ($payutils::query{'screen2-above-submit-message'} ne "") {
    $output .= "<br>\n";
    $output .= "$payutils::query{'screen2-above-submit-message'}\n";
    $output .= "<br>\n";
  }
  if ($payutils::template{'submtpg2'} ne "") {
    $output .= "$payutils::template{'submtpg2'}\n";
  }
  else {
    $output .= "<div align=\"center\">";
    if (($payutils::query{'accttype'} eq "checking") && ($payutils::chkprocessor eq "telecheck")) {
      $output .= "By entering my account number above and clicking $payutils::lang_titles{'submitorder'}[$payutils::lang], I authorize my payment to be processed as an electronic funds transfer \n";
      $output .= "or draft drawn from my account. If the payment is returned unpaid, I authorize you or your service provider to collect the payment and my state\'s return item \n";
      $output .= "fee by electronic funds transfer(s) or draft(s) drawn from my account. <a href=\"http://www.firstdata.com/support/telecheck_returned_check/returned_check_fees.htm\" target=\"_blank\"><b>Click here</b></a> \n";
      $output .= "to view your state's returned item fee. If this payment is from a corporate account, I make these authorizations as an authorized corporate representative and agree that the entity will be bound by the NACHA operating rules.\n";
      $output .= "<p>\n";
    }

    if ($payutils::feature{'indicate_processing'} ne "") {
      $output .= "<div id=\"processingStatement\" style=\"visibility:hidden\" align=\"center\"><font class=\"badcolor larger\"><b>Processing Payment, Please be Patient</b></font></div>\n";
      $output .= "<input type=\"submit\" value=\"$payutils::lang_titles{'submitorder'}[$payutils::lang]\" onClick=\"is_processing('true');return(mybutton(this.form));\">";
    }
    else {
      $output .= "<input type=\"submit\" value=\"$payutils::lang_titles{'submitorder'}[$payutils::lang]\" onClick=\"return(mybutton(this.form));\">";
    }
    $output .= " &nbsp; <input type=\"button\" value=\"Edit Information\" onClick=\"goback();\">\n";
    $output .= "</div><br>\n";
  }
  $output .= "</form>\n";

  if ($payutils::query{'pg2_statement'} ne "") {
    $output .= "$payutils::query{'pg2_statement'} \n";
  }
  elsif ($payutils::query{'pg2-statement'} ne "") {
    $output .= "$payutils::query{'pg2-statement'} \n";
  }
  elsif ($payutils::lang_titles{'patience3'}[$payutils::lang] ne "") {
    $output .= "$payutils::lang_titles{'patience3'}[$payutils::lang] \n";
  }
  else {
    $output .= "$payutils::lang_titles{'patience1'}[$payutils::lang]\n";
    $output .= " <a href=\"mailto:\n";
    if ($payutils::query{'from-email'} ne "") {
      $output .= "$payutils::query{'from-email'}\">$payutils::query{'from-email'}</a>.\n";
    }
    else {
      $output .= "$payutils::query{'publisher-email'}\">$payutils::query{'publisher-email'}</a>.\n";
    }
    $output .= "$payutils::lang_titles{'patience2'}[$payutils::lang] ";
  }
  $output .= "</div></td></tr></table>\n";
  $output .= "</div>\n";
  $output .= "\n\n<!--  START OF CUSTOMIZEABLE TAIL SECTION --> \n\n";
  if ($payutils::template{'tail'} ne "") {
    $output .= "$payutils::template{'tail'}\n";
  }
  $output .= "\n\n<!--  END OF CUSTOMIZEABLE TAIL SECTION --> \n\n";
  $output .= "</body>\n";
  $output .= "</html>\n";

  return $output;
}


sub colors {
  my (@required) = split('\|',$payutils::query{'required'});
  foreach my $var (@required) {
    $payutils::requiredstar{$var} = "*";
  }

  ### DCP 20090803
  my @check = ('card-name','card-address1','card-city','email');
  if ($payutils::query{'requirecompany'} eq "yes") {
    @check = (@check,'card-company');
  }
  if (($payutils::query{'card-country'} eq "US") || ($payutils::query{'card-country'} eq "")) {
    @check = (@check,'card-state','card-zip');
  }
  if ($payutils::feature{'cvv'} == 1) {
    @check = (@check,'card-cvv');
  }

  my(%optional);
  if ($payutils::feature{'optionalpay'} ne "") {
    my @optional = split(/\|/,$payutils::feature{'optionalpay'});
    foreach my $var (@optional) {
      $optional{"$var"} = 1;
    }
  }
  foreach my $var (@check) {
    if (exists $optional{$var} ) {
      next;
    }
    $payutils::requiredstar{$var} = "<b>*</b>";
  }
  ###  END DCP 20090803

  foreach my $var (@payutils::standardfields) {
    $payutils::color{$var} = 'goodcolor';
  }
}


sub input_check {

  if ($payutils::query{'card-name'} =~ /^(visa|mastercard|amex|american express|discover)$/i) {
    $payutils::error = 1;
    $payutils::color{'card-name'} = 'badcolor';
    $payutils::error{'dataentry'} .= "$payutils::lang_titles{'namecheck'}[$payutils::lang]";
    $payutils::errvar .= "card-name\|";
    $payutils::query{'card-name'} = "";
  }

  if ($payutils::feature{'splitname'} == 1) {
    $payutils::query{'card-name'} = $payutils::query{'card-fname'} . " " . $payutils::query{'card-lname'};
    if ($payutils::query{'shipsame'} eq "yes") {
      $payutils::query{'shipname'} = $payutils::query{'card-name'};
    }
  }

  foreach my $key (keys %payutils::query) {
    $payutils::color{$key} = 'goodcolor';
  }

  my ($cardtype);
  if (($payutils::query{'card-type'} =~ /MilStar/i) && ($payutils::query{'card-number'} =~ /^(60194|60191)/)) {
    $cardtype = "MilStar";
    if (($payutils::query{'transflags'} !~ /milstar/)) {
      if (exists $payutils::query{'transflags'} ) {
        $payutils::query{'transflags'} .= ",milstar";
      }
      else {
        $payutils::query{'transflags'} = "milstar";
      }
    }
  }
  else {
    $cardtype = &miscutils::cardtype($payutils::query{'card-number'});
  }

  $payutils::query{'card-type'} = $cardtype;

  # check to be sure only an allowed card type was entered
  if ($payutils::feature{'enforce_cardallowed'} == 1) {
    my $cardtype_match = 0;
    my @allowed_list = split(/\,/, $payutils::query{'card-allowed'});
    for (my $i=0; $i <= $#allowed_list; $i++) {
      if ($payutils::card_hash{"$allowed_list[$i]"}[0] eq $payutils::query{'card-type'}) {
        $cardtype_match = 1;
        last;
      }
    }
    if ($cardtype_match != 1) {
      $payutils::error = 1;
      $payutils::color{'card-type'} = 'badcolor';
      $payutils::color{'card-number'} = 'badcolor';
      $payutils::error{'dataentry'} .= "Card Type Not Accepted."; # "$payutils::lang_titles{'cardtypecheck'}[$payutils::lang]";
      $payutils::errvar .= "card-type\|card-number\"";
      $payutils::query{'card-type'} = "";
      $payutils::query{'card-number'} = "";
      return;
    }
  }

  my (@required_fields) = split('\|',$payutils::query{'required'});

  if ($payutils::query{'client'} =~ /mobile/) {
    for (@required_fields) {
	s/\_/\-/;
    }
  }

  if ($payutils::feature{'alloweval'} == 1) {
    if (exists $payutils::template{'inputcheck'}) {
      eval $payutils::template{'inputcheck'}; die "eval: $@" if $@;
    }
  }

  if ($payutils::query{'paymethod'} eq "web900") {
    if ($payutils::query{'web900-pin'} eq "") {
      $payutils::error = 1;
      $payutils::color{'web900-pin'} = 'badcolor';
      $payutils::error{'dataentry'} .= "No web 900 pin number entered.";
      $payutils::errvar .= "web900pin\|";
    }
  }
  elsif ($payutils::query{'paymethod'} eq "teleservice") {
    my (%pin,$pin,$amt,$status);
    $payutils::query{'pinnumber'} =~ s/[^0-9a-zA_Z]//g;
    my $publishername = $payutils::query{'publisher-name'};
    $publishername =~ s/[^0-9a-zA-Z]//g;
    &sysutils::filelog("read","$payutils::path_web/payment/recurring/$publishername/admin/web900.txt");
    open(PIN,'<',"$payutils::path_web/payment/recurring/$publishername/admin/web900.txt");
    while(<PIN>) {
      chop;
      ($pin,$amt,$status) = split('\t');
      $pin{$_} = $status;
    }
    close(PIN);

    if ((length($payutils::query{'pinnumber'}) < 5) || ($pin{$payutils::query{'pinnumber'}} ne "") || ($payutils::query{'card-amount'} ne $amt)) {
      $payutils::error = 1;
      $payutils::color{'pinnumber'} = 'badcolor';
      $payutils::error{'dataentry'} .= "Sorry, the PIN number entered is invalid.";
      $payutils::errvar .= "pinnumber\|";
    }
  }
  elsif ($payutils::query{'paymethod'} eq "mocopay") {
    if ($payutils::query{'card-number'} eq "") {
      $payutils::error = 1;
      $payutils::color{'card-number'} = 'badcolor';
      $payutils::error{'dataentry'} .= "No account number entered.";
      $payutils::errvar .= "card-number\|";
    }
  }
  # Mercury gift cards
  elsif (($payutils::feature{'acceptgift'} == 1) && ($payutils::query{'mpgiftcard'} ne ""))  {
    if ((length $payutils::query{'mpgiftcard'} < 10) || ($payutils::query{'mpcvv'} eq "")) {
      #No Gift Card password entered or invlaid length.
      $payutils::error = 1;
      $payutils::color{'mpgiftcard'} = 'badcolor';
      $payutils::color{'mpcvv'} = 'badcolor';
      $payutils::error{'dataentry'} .= "$payutils::lang_titles{'mpgiftinvalid'}[$payutils::lang]";
      $payutils::errvar .= "mpgiftcard\|mpcvv\"";
    }
    # Balance inquiry
    elsif (length $payutils::query{'mpgiftcard'} >= 10) {
      (my $result,$payutils::mpgiftcard_balance) = &balance_check();
      if ($payutils::mpgiftcard_balance == 0) {
	$result = "problem"; 		   # this is so that error occurs here instead of after transaction is submitted
      }
      if ($result ne "success") {
        if ($result eq "badcard") {
            if ($payutils::query{'card-number'} eq "") {
              $payutils::error = 1;
              $payutils::color{'card-number'} = 'badcolor';
              $payutils::color{'card-exp'} = 'badcolor';
              $payutils::error{'dataentry'} .= "$payutils::lang_titles{'lowbalance'}[$payutils::lang]";
              $payutils::error{'dataentry'} =~ s/\[pnp_balance\]/$payutils::query{'currency_symbol'}$payutils::mpgiftcard_balance/;
              $payutils::errvar .= "mpgiftcard\|";
            }
        }
        else { # problem status
	      $payutils::error = 1;
              $payutils::error{'dataentry'} .= "$payutils::lang_titles{'mpgifterror'}[$payutils::lang]\n";
              $payutils::color{'card-number'} = 'badcolor';
              $payutils::color{'card-exp'} = 'badcolor';
              $payutils::color{'mpgiftcard'} = 'badcolor';
              $payutils::color{'mpcvv'} = 'badcolor';
              $payutils::errvar .= "mpgiftcard\|mpcvv\"";
        }
      }
    }
  }
  elsif (($payutils::processor eq "psl")  && ($payutils::query{'transflags'} =~ /issue/i)) {
    my $test_DOB = $payutils::query{'dateofbirth'};
    $test_DOB =~ s/[^0-9]//g;
    if (length($test_DOB) < 8) {
      ## Sorry, the Date of Birth entered is invalid. Proper Format is: MM/DD/YYYY
      $payutils::error = 1;
      $payutils::color{'dateofbirth'} = 'badcolor';
      $payutils::error{'dateofbirth'} = "$payutils::lang_titles{'psldob'}[$payutils::lang]";
      $payutils::errvar .= "dateofbirth\|";
    }
    if ($payutils::query{'phonetype'} !~ /(Business|Home|Mobile)/i) {
      ## Sorry, invalid phone type.
      $payutils::error = 1;
      $payutils::color{'phonetype'} = 'badcolor';
      $payutils::error{'phonetype'} = "$payutils::lang_titles{'pslphone'}[$payutils::lang]";
      $payutils::errvar .= "phonetype\|";
    }
    if ($payutils::query{'walletid'} ne $payutils::query{'email'}) {
      ## Sorry, the WalletID and Email address must match.
      $payutils::error = 1;
      $payutils::color{'walletid'} = 'badcolor';
      $payutils::error{'walletid'} = "$payutils::lang_titles{'pslwalletid'}[$payutils::lang]";
      $payutils::errvar .= "walletid\|";
    }

    @required_fields = (@required_fields,'phone','phonetype','challenge','response','dateofbirth');
    @payutils::nohidden = (@payutils::nohidden,'phone','phonetype','challenge','response','dateofbirth');
  }
  elsif (($payutils::processor eq "psl")  && ($payutils::query{'transflags'} !~ /issue|load/i)) {
    # do nothing...
  }
  elsif (($payutils::online_checks ne "yes") && ($payutils::query{'paymethod'} !~ /^(onlinecheck|check|invoice|billpay_invoice)$/i)) {  ## DCP 20090319
  #elsif (($payutils::online_checks ne "yes") && ($payutils::query{'paymethod'} ne "onlinecheck")) {
    #if (($payutils::query{'paymethod'} ne "check") && ($payutils::query{'paymethod'} ne "onlinecheck") && ($payutils::query{'paymethod'} !~ /invoice/i)){
      my $CCtest = $payutils::query{'card-number'};
      $CCtest =~ s/[^0-9]//g;
      my $luhntest = &miscutils::luhn10($CCtest);
      if ($luhntest eq "failure") {
        $payutils::error = 1;
        $payutils::color{'card-number'} = 'badcolor';
        $payutils::errvar = "card-number length\|$luhntest\|";
        $payutils::error{'dataentry'} .= "$payutils::lang_titles{'validcc'}[$payutils::lang]";
      }
      if ((($payutils::feature{'cvv'} == 1) || ($payutils::query{'cvv-flag'} eq "yes")) && ($cardtype =~ /^(VISA|MSTR|DSCR|AMEX)/) && ($payutils::feature{'suppresspay'} !~ /(card-cvv)/)) {
        if ($payutils::feature{'nocheckpay'} !~ /(card-cvv)/) {
          if ((length($payutils::query{'card-cvv'}) != 3) && (length($payutils::query{'card-cvv'}) != 4)) {
            $payutils::error = 1;
            $payutils::color{'card-cvv'} = 'badcolor';
            $payutils::errvar = "card-cvv\|";
          }
        }
      }
      elsif ( ($cardtype =~ /(KC)/) && ($payutils::feature{'cvv'} == 1) ) {
        my $expmo = $payutils::query{'month-exp'};
        my $expyr = $payutils::query{'year-exp'};
        my $datetest = "20" . $expyr . $expmo;
        my $testbin = substr($payutils::query{'card-number'},0,9);
        if (    ( ($testbin >= 777000000) && ($testbin < 777580000) && ($datetest >= 200810) )
             || ( ($testbin >= 777581000) && ($testbin < 777773000) && ($datetest >= 200810) )
             || ( ($testbin >= 777740000) && ($testbin < 777777055) && ($datetest >= 200810) )
             || ( ($testbin >= 777777055) && ($testbin < 777777056) && ($datetest >= 201411) )
             || ( ($testbin >= 777777056) && ($testbin < 777777800) && ($datetest >= 200810) )
           ) {
          if ((length($payutils::query{'card-cvv'}) != 3) && (length($payutils::query{'card-cvv'}) != 4)) {
            $payutils::error = 1;
            $payutils::color{'card-cvv'} = 'badcolor';
            $payutils::errvar = "card-cvv\|";
          }
        }
      }
      if ( ($cardtype =~ /MilStar/i) && (($payutils::query{'transflags'} =~ /milstar/) || ($payutils::feature{'defaultmilstar'} == 1)) ) {
        ## Cardtype = Milstar, EXP DATE Chk is ignored
      }
      else {
        my ($date) = &miscutils::gendatetime_only();
        my $exptst1 =  $payutils::query{'year-exp'} + 2000;
        $exptst1 .= $payutils::query{'month-exp'};
        my $exptst2 =  substr($date,0,6);
        if ($exptst1 < $exptst2) {
          $payutils::error = 1;
          $payutils::color{'card-exp'} = 'badcolor';
          $payutils::errvar = "card-exp\|";
        }
      }
    #}
  }
  elsif (($payutils::online_checks eq "yes") || ($payutils::query{'paymethod'} =~ /^(onlinecheck|check)$/i)) {  ## DCP 20090319
    if ($payutils::chkprocessor =~ /^(paymentdata|alliancesp|echo|testprocessor|testprocessorach)$/) {
      ## enforce ACH billing name requirements
      if (($payutils::query{'card-fname'} =~ /[^0-9a-zA-Z\-]/) || ($payutils::query{'card-fname'} eq "") || (length($payutils::query{'card-fname'}) < 2)) {
        ## error when first name contains non-allowed characters, is not defined, or is too short
        $payutils::error = 1;
        $payutils::color{'card-fname'} = 'badcolor';
        $payutils::error{'dataentry'} .= "Enter first name only. (No first name prefix, middle name or initials permitted.)<br>";
        $payutils::errvar .= "card-fname\|";
      }

      if (($payutils::query{'card-lname'} =~ /[^0-9a-zA-Z\-]/) || ($payutils::query{'card-lname'} eq "") || (length($payutils::query{'card-lname'}) < 2)) {
        ## error when last name contains non-allowed characters, is not defined, or is too short.
        $payutils::error = 1;
        $payutils::color{'card-lname'} = 'badcolor';
        $payutils::error{'dataentry'} .= "Enter last name only. (No last name suffix or numbers permitted.)<br>";
        $payutils::errvar .= "card-lname\|";
      }
    }

    if (length($payutils::query{'accountnum'}) < 5) {
      ## Account Number has too few characters.
      $payutils::error = 1;
      $payutils::color{'accountnum'} = 'badcolor';
      $payutils::errvar .= "account\|";
      $payutils::error{'dataentry'} .= "$payutils::lang_titles{'acctnumerr'}[$payutils::lang]";
    }
    my $ABAtest = $payutils::query{'routingnum'};
    $ABAtest =~ s/[^0-9]//g;
    my $luhntest = &modulus10($ABAtest);
    if ((length($payutils::query{'routingnum'}) != 9) || ($luhntest eq "FAIL")){
      ## Invalid Routing Number.  Please check and re-enter.
      $payutils::error = 1;
      $payutils::color{'routingnum'} = 'badcolor';
      $payutils::errvar .= "aba\|";
      $payutils::error{'dataentry'} .= "$payutils::lang_titles{'routnumerr'}[$payutils::lang]";
    }
    if ((length($payutils::query{'checknum'}) < 1) && ($payutils::feature{'skip_checknum_inputcheck'} != 1)) {
      ## Check Number has to few digits.
      $payutils::error = 1;
      $payutils::color{'checknum'} = 'badcolor';
      $payutils::errvar .= "seq\|";
      $payutils::error{'dataentry'} .= "$payutils::lang_titles{'checknumerr'}[$payutils::lang]";
    }
  }
  elsif ($payutils::query{'paymethod'} eq "telecheck") {
    my $chklen = length($payutils::query{'checknum'});
    if (length($payutils::query{'checknum'}) < 1) {
      $payutils::error = 1;
      $payutils::color{'checknum'} = 'badcolor';
      $payutils::errvar .= "seq\|";
    }
    if (length($payutils::query{'micr'}) < ($chklen + 9 + 3)) {
      $payutils::error = 1;
      $payutils::color{'micr'} = 'badcolor';
      $payutils::errvar .= "micr\|";
    }
    @required_fields = (@required_fields,'phone','card-state','licensenum','licensestate');
    @payutils::nohidden = (@payutils::nohidden,'licensenum','licensestate','micr');
  }
  if ($payutils::processor eq "psl") {
    #if ($payutils::query{'transflags'} =~ /load/i) {
    #
    #}
    @required_fields = (@required_fields,'walletid','passcode');
    @payutils::nohidden = (@payutils::nohidden,'walletid','passcode');
  }


  my @check = @required_fields;
  @check = (@check,'card-name','card-address1','card-city','email');
  if ($payutils::query{'requirecompany'} eq "yes") {
    @check = (@check,'card-company');
  }
  if (($payutils::query{'card-country'} eq "US") || ($payutils::query{'card-country'} eq "")) {
    @check = (@check,'card-state','card-zip');
  }

  if ($payutils::feature{'noemail'} == 1) {
    push (@payutils::nocheck,'email');
  }
  if ($payutils::feature{'nocheckpay'} ne "") {
    my @nocheckpay = split(/\|/,$payutils::feature{'nocheckpay'});
    foreach my $var (@nocheckpay) {
      push (@payutils::nocheck, "$var");
    }
  }
  if ($payutils::feature{'suppresspay'} ne "") {
    my @suppress = split(/\|/,$payutils::feature{'suppresspay'});
    foreach my $var (@suppress) {
      push (@payutils::nocheck, "$var");
    }
  }
  if ($payutils::feature{'suppressswipepay'} ne "") {
    my @suppress = split(/\|/,$payutils::feature{'suppressswipepay'});
    foreach my $var (@suppress) {
      push (@payutils::nocheck, "$var");
    }
  }
  if ($payutils::feature{'suppressmobilepay'} ne "") {
    my @suppress = split(/\|/,$payutils::feature{'suppressmobilepay'});
    foreach my $var (@suppress) {
      $var =~ s/\_/\-/;
      push (@payutils::nocheck, "$var");
    }
  }
  if (($payutils::query{'amexlev2'} == 1) && ($cardtype =~ /amex/i)) {
    push (@check,'costcenternum');
    push (@check,'employeename');
    $payutils::query{'card-type'} = 'AMEX';
  }

  my (%nocheck);
  foreach my $var (@payutils::nocheck) {
    $nocheck{$var} = 1;
  }

  foreach my $var (@check) {
    #if (exists $nocheck{$var}) {
    if ((exists $nocheck{$var}) || ($var eq "")) {
      next;
    }
    my $val = $payutils::query{$var};
    $val =~ s/[^a-zA-Z0-9]//g;
    if (length($val) < 1) {
      $payutils::error = 1;
      $payutils::color{$var} = 'badcolor';
      $payutils::errvar .= "$var\|";
    }
    if ($var eq "phone") {
      if (length($val) < 10) {
        $payutils::error = 1;
        $payutils::color{$var} = 'badcolor';
        $payutils::errvar .= "$var\|";
      }
    }
  }

  if (length($payutils::query{'card-address1'}) > 39) {
    $payutils::error = 1;
    $payutils::color{'card-address1'} = 'badcolor';
    $payutils::errvar .= "card-address1\|";
  }

  if (($payutils::query{'publisher-name'} =~ /^(pnpdemo|alluinc|tdminc2)$/) || ($payutils::fraud_config{'matchzip'} == 1)) {
  #if ($payutils::feature{'checkzip'} == 1) {
    my (%zipcode);
    if (($payutils::query{'card-country'} eq "US") && ($payutils::query{'card-zip'} ne "")) {
      $payutils::query{'card-zip'} =~ s/[^0-9]//g;
      my $zipkey = substr($payutils::query{'card-zip'},0,5);
      #my ($state,$county) = split(/\:/,$zipcode{$zipkey});

      my $dbh = &miscutils::dbhconnect("fraudtrack");
      my $sth = $dbh->prepare(q{
          SELECT state,city,county
          FROM zipcodes
          WHERE zipcode=?
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%payutils::query);
      $sth->execute("$zipkey") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%payutils::query);
      my ($state,$zipcity,$county) = $sth->fetchrow;
      $sth->finish;
      $dbh->disconnect;

      if (($state ne "AP") && ($state !~ /$payutils::query{'card-state'}/i)) {
        ## The Zip Code and State for your billing address do not match.
        $payutils::error = 1;
        $payutils::color{'card-zip'} = 'badcolor';
        $payutils::errvar .= "zipandstatenotmatch\|";
        $payutils::error{'dataentry'} .= "$payutils::lang_titles{'billaddrerr'}[$payutils::lang]";
      }
      $payutils::query{'shipcounty'} = $county;
    }
    if (($payutils::query{'shipinfo'} eq "1") && ($payutils::query{'zip'} ne "") && ($payutils::query{'country'} eq "US")) {
      $payutils::query{'zip'} =~ s/[^0-9]//g;
      my $zipkey = substr($payutils::query{'zip'},0,5);
      #my ($state,$county) = split(/\:/,$zipcode{$zipkey});

      my $dbh = &miscutils::dbhconnect("fraudtrack");
      my $sth = $dbh->prepare(q{
          SELECT state,city,county
          FROM zipcodes
          WHERE zipcode=?
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%payutils::query);
      $sth->execute("$zipkey") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%payutils::query);
      my ($state,$zipcity,$county) = $sth->fetchrow;
      $sth->finish;
      $dbh->disconnect;

      if (($state ne "AP") && ($state !~ /$payutils::query{'state'}/i)) {
        ## The Zip Code and State for your shipping address do not match.
        $payutils::error = 1;
        $payutils::color{'zip'} = 'badcolor';
        $payutils::errvar .= "zipandshipstatenotmatch\|";
        $payutils::error{'dataentry'} .= "$payutils::lang_titles{'shipadderr'}[$payutils::lang]";
      }
      $payutils::query{'shipcounty'} = $county;
    }
  }

  if ($nocheck{'email'} != 1) {
    my $position = index($payutils::query{'email'},"\@");
    my $position1 = rindex($payutils::query{'email'},"\.");
    my $elength  = length($payutils::query{'email'});
    my $pos1 = $elength - $position1;

    if (($position < 1)
       || ($position1 < $position)
       || ($position1 >= $elength - 2)
       || ($elength < 5)
       || ($position > $elength - 5)
    ) {
      $payutils::error = 1;
      $payutils::color{'email'} = 'badcolor';
      $payutils::errvar .= "email:$position:$pos1:$position1:$elength\|";
    }
  }

  if (($payutils::query{'shipmethod'} eq "UPS")) {
    my ($country);
    $country = $payutils::query{'country'};
    if (($payutils::query{'serviceLevelCode'} =~ /^(XPR)$/) && ($country =~ /^(US|CA)$/ )) {
      ## Choosen shipping method  not allowed for destination country.
      $payutils::error = 1;
      $payutils::color{'shipping'} = 'badcolor';
      $payutils::error{'dataentry'} .= "$payutils::lang_titles{'destnotallowed'}[$payutils::lang]";
      $payutils::errvar .= "shipmethod:Inappropriate Method\|";
    }
    elsif (($payutils::query{'serviceLevelCode'} =~ /^(STD)$/) && ($country !~ /^(CA)$/)) {
      ## Choosen shipping method  not allowed for destination country.
      $payutils::error = 1;
      $payutils::color{'shipping'} = 'badcolor';
      $payutils::error{'dataentry'} .= "$payutils::lang_titles{'destnotallowed'}[$payutils::lang]";
      $payutils::errvar .= "shipmethod:Inappropriate Method\|";
    }
    elsif (($payutils::query{'serviceLevelCode'} =~ /^(1DA|2DA|3DS|GND)$/) && ($country !~ /^(US)$/)) {
      ## Choosen shipping method  not allowed for destination country.
      $payutils::error = 1;
      $payutils::color{'shipping'} = 'badcolor';
      $payutils::error{'dataentry'} .= "$payutils::lang_titles{'destnotallowed'}[$payutils::lang]";
      $payutils::errvar .= "shipmethod:Inappropriate Method\|";
    }
  }

  if (($payutils::allow_cookie eq "yes") && ($payutils::query{'cookie_pw1'} ne "")) {
    ## Passwords Can Not Contain Less Than $payutils::unpw_minlength Characters - Please Re-enter.
    my $length = length($payutils::query{'cookie_pw1'});
    my $length2 = length($payutils::query{'cookie_pw2'});
    if (($length < 4) || ($length2 < 4)) {
      $payutils::error_string = "$payutils::lang_titles{'passwrderr1'}[$payutils::lang]";
      $payutils::error = 1;
      $payutils::color{'cookie_pw'} = 'badcolor';
      $payutils::errvar .= "cookie_pwLT4\|";
    }

    if ($payutils::query{'cookie_pw1'} ne $payutils::query{'cookie_pw2'}) {
      ## Passwords Do Not Match - Please Re-enter.
      $payutils::error_string = "$payutils::lang_titles{'passwrderr3'}[$payutils::lang]";
      $payutils::error = 1;
      $payutils::color{'cookie_pw'} = 'badcolor';
      $payutils::errvar .= "cookie_pwDNM1\|";
    }
  }

  if (($payutils::query{'plan'} ne "") && ($payutils::query{'unpwcheck'} ne "no") && ($payutils::unpwcheck ne "no")) {
    my ($database);
    my $uname = $payutils::query{'uname'};
    my $pass1 = $payutils::query{'passwrd1'};
    my $pass2 = $payutils::query{'passwrd2'};
    $payutils::error_string = "";

    #checking for duplicate username
    if ($payutils::query{'merchantdb'} ne "") {
      $database = $payutils::query{'merchantdb'};
    }
    else {
     $database = $payutils::query{'publisher-name'};
    }

    my ($username);
    if ($payutils::feature{'merchantdbs'} ne "") {
      my @merchantdbs = split('\|',$payutils::feature{'merchantdbs'});
      foreach my $db (@merchantdbs) {
        $db =~ s/[^a-zA-Z0-9]//g;
        my $dbh = &miscutils::dbhconnect("$db");
        my $sth = $dbh->prepare(q{
            SELECT username
            FROM customer
            WHERE LOWER(username) = LOWER(?)
          }) or die "Can't prepare: $DBI::errstr";
        $sth->execute("$uname") or die "Can't execute: $DBI::errstr";
        ($username) = $sth->fetchrow;
        $sth->finish;
        $dbh->disconnect;
        if ($username ne "") {
          last;
        }
      }
    }
    else {
      my $dbh = &miscutils::dbhconnect("$database");
      my $sth = $dbh->prepare(q{
          SELECT username
          FROM customer
          WHERE LOWER(username) = LOWER(?)
        }) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$uname") or die "Can't execute: $DBI::errstr";
      ($username) = $sth->fetchrow;
      $sth->finish;
      $dbh->disconnect;
    }

    #if ($username !~ /\w/) {  ## Modified DCP 20080422
    if ($username ne "") {
      # if duplicate is found, either generate a new username or provide error to the end user
      if (($payutils::query{'suppress_unpw'} eq "yes") || ($payutils::query{'suppress-unpw'} eq "yes")) {
        # loop max of 10 times, in effort to find a unique username/password # LOOP UP TO 10 TIMES ------+
        #   when username exists and the suppress_unpw option is used                                    |
        for (my $i = 1; $i <= 50; $i++) {         #    <---------------------- NO WAIT 50 TIMES! --------+
          # get next sequential orderID number
          my $uname = new PlugNPay::Util::RandomString()->randomAlphaNumeric(40);

          # enforce username requirements
          if ($payutils::pwcheckplus eq "yes") {
            # ensure 1st character in username is a letter # why is this a requirement?
            if (substr($uname, 0, 1) !~ /[a-zA-Z]/) {
              substr($uname, 0, 1) = "a";
            }
            # ensure 2nd character in username is a letter # 1st seems remotely reasonable, but this is stupid, and what if the third character is a number?  changing substring replace to replace with letters for both
            if (substr($uname, 1, 1) !~ /a-zA-Z/) {
              substr($uname, 1, 1) = "z";
            }

            # now setup password check plus requirements (uppercase, lowercase & numberic characters) # wtf is this, this isn't even the password.  this is garbage.   :dumpsterfire:
            substr($uname, 0, 1) = uc(substr($uname, 0, 1));
            substr($uname, 1, 1) = lc(substr($uname, 1, 1));
            substr($uname, 2, 1) = int(rand(10));
          } else {
            $uname = lc($uname);
          }

          # limit username length, if necessary # wait...
          if (length($uname) > $payutils::unpw_maxlength) {
            $uname = substr($uname, 0, $payutils::unpw_maxlength);
          }

          # now check for new username's existance
          my ($db_username);
          if ($payutils::feature{'merchantdbs'} ne "") {
            my @merchantdbs = split('\|',$payutils::feature{'merchantdbs'});
            foreach my $db (@merchantdbs) {
              $db =~ s/[^a-zA-Z0-9]//g;
              my $dbh = &miscutils::dbhconnect("$db");
              my $sth = $dbh->prepare(q{
                  SELECT username
                  FROM customer
                  WHERE LOWER(username) = LOWER(?)
                }) or die "Can't prepare: $DBI::errstr";
              $sth->execute("$uname") or die "Can't execute: $DBI::errstr";
              ($db_username) = $sth->fetchrow;
              $sth->finish;
              $dbh->disconnect;
              if ($db_username ne "") {
                last;
              }
            }
          }
          else {
            my $dbh = &miscutils::dbhconnect("$database");
            my $sth = $dbh->prepare(q{
                SELECT username
                FROM customer
                WHERE LOWER(username) = LOWER(?)
              }) or die "Can't prepare: $DBI::errstr";
            $sth->execute("$uname") or die "Can't execute: $DBI::errstr";
            ($db_username) = $sth->fetchrow;
            $sth->finish;
            $dbh->disconnect;
          }

          # if new username is found to be unique, exit this loop early
          if ($db_username eq "") {
            $payutils::query{'uname'} = $uname;
            last;
          }
        }
      }
      else {
        $payutils::error_string .= "Username \"$uname\" Already in Use.<br>";
        $payutils::error = 1;
        $payutils::color{'uname'} = 'badcolor';
        $payutils::errvar .= "unameAIU\|";
      }
    }

    my $length = length($pass1);
    my $length2 = length($uname);
    if (($length < $payutils::unpw_minlength) || ($length2 < $payutils::unpw_minlength)) {
      $payutils::error_string .= "Password and/or Username Contain Less Than $payutils::unpw_minlength Characters.<br>";
      $payutils::error = 1;
      $payutils::color{'uname'} = 'badcolor';
      $payutils::errvar .= "unameLT$payutils::unpw_minlength\|";
    }

    if ($pass1 ne $pass2) {
      $payutils::error_string .= "Passwords Do Not Match. <br>";
      $payutils::error = 1;
      $payutils::color{'passwrd1'} = 'badcolor';
      $payutils::color{'passwrd2'} = 'badcolor';
      $payutils::errvar .= "unameDNM1\|";
    }

    if ($uname eq $pass1) {
      ## Usernames and Passwords are not allowed to match.
      $payutils::error_string .= "Usernames and Passwords are not allowed to match.<br>";
      $payutils::error = 1;
      $payutils::color{'passwrd1'} = 'badcolor';
      $payutils::color{'passwrd2'} = 'badcolor';
      $payutils::errvar .= "unameDNM2\|";
    }
    if ($payutils::pwcheckplus eq "yes") { # this looks like it's not even used, looked at a database for someone with it on and more usernames than not violate the requirements below
      # check username for letter & number existance
      if (($uname !~ /[0-9]/) || ($uname !~ /[a-zA-Z]/)) {
        $payutils::error_string .= "Username must contain both Characters and Numbers.<br>"; # wtf?
        $payutils::error = 1;
        $payutils::color{'uname'} = 'badcolor';
        $payutils::color{'passwrd1'} = 'badcolor';
        $payutils::color{'passwrd2'} = 'badcolor';
        $payutils::errvar .= "unameNUM\|";
      }
      # check username for letter upper & lower case existance
      if (($uname !~ /[a-z]/) || ($uname !~ /[A-Z]/)) {
        $payutils::error_string .= "Username must contain both \'UPPER\' \& \'lower\' case Characters.<br>"; # who does this?  seriously?
        $payutils::error = 1;
        $payutils::color{'uname'} = 'badcolor';
        $payutils::color{'passwrd1'} = 'badcolor';
        $payutils::color{'passwrd2'} = 'badcolor';
        $payutils::errvar .= "unameCASE\|";
      }
      # check password for letter & number existance
      if (($pass1 !~ /[0-9]/) || ($pass1 !~ /[a-zA-Z]/)) {
        $payutils::error_string .= "Password must contain both Characters and Numbers.<br>";
        $payutils::error = 1;
        $payutils::color{'uname'} = 'badcolor';
        $payutils::color{'passwrd1'} = 'badcolor';
        $payutils::color{'passwrd2'} = 'badcolor';
        $payutils::errvar .= "passwordNUM\|";
      }
      # check password for letter upper & lower case existance
      if (($pass1 !~ /[a-z]/) || ($pass1 !~ /[A-Z]/)) {
        $payutils::error_string .= "Password must contain both \'UPPER\' \& \'lower\' case Characters.<br>";
        $payutils::error = 1;
        $payutils::color{'uname'} = 'badcolor';
        $payutils::color{'passwrd1'} = 'badcolor';
        $payutils::color{'passwrd2'} = 'badcolor';
        $payutils::errvar .= "passwordCASE\|";
      }

    }
    if ($payutils::error_string ne "") {
      $payutils::error_string .= "<br>Please Re-enter.";
    }
  }

  if ((($payutils::couponflag == 1) || ($payutils::feature{'couponflag'} == 1)) && ($payutils::query{'promoid'} ne "")) {
    # grab coupon & promotion params, then validate.

    my ($errmsg);

    my ($dummy,$datestr,$timestr) = &miscutils::gendatetime();

    # validate coupon codes provided by customer
    my @placeholder = ();
    my $qstr = "SELECT promoid,promocode,use_limit,use_count,expires,status FROM promo_coupon";
    $qstr .= " WHERE username=?";
    push(@placeholder, $payutils::query{'publisher-name'});

    $payutils::query{'promoid'} =~ s/[^0-9a-zA-Z ]//g;
    $qstr .= " AND promoid=?";
    push(@placeholder, $payutils::query{'promoid'});

    if ($payutils::query{'subacct'} ne "") {
      $qstr .= " AND subacct=?";
      push(@placeholder, $payutils::query{'subacct'});
    }

    my $dbh = &miscutils::dbhconnect('merch_info');

    my $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
    $sth->execute(@placeholder) or die "Can't do: $DBI::errstr";
    ($payutils::coupon_info{'promoid'},$payutils::coupon_info{'promocode'},$payutils::coupon_info{'limit'},$payutils::coupon_info{'count'},$payutils::coupon_info{'expires'},$payutils::coupon_info{'status'}) = $sth->fetchrow;

    $sth->finish;

    if ($payutils::coupon_info{'promoid'} ne "") {
      if ($payutils::coupon_info{'expires'} < $datestr) {
        $errmsg .= "Coupon Code:$payutils::query{'promoid'}, Coupon expired.";
      }
      elsif ($payutils::coupon_info{'status'} =~ /cancel/) {
        $errmsg .= "Coupon Code:$payutils::query{'promoid'}, Coupon canceled.";
      }
      elsif (($payutils::coupon_info{'limit'} <= 0.00) && ($payutils::coupon_info{'limit'} =~ /\.\d{2}$/)) {
        $errmsg .= "Coupon Code:$payutils::query{'promoid'}, No balance left on gift certificate.";
      }
      elsif (($payutils::coupon_info{'count'} > $payutils::coupon_info{'limit'}) && ($payutils::coupon_info{'limit'} ne "")) {
        $errmsg .= "Coupon Code:$payutils::query{'promoid'}, Use count exceeded.";
      }
    }
    else {
      $errmsg = "Coupon Code not found.";
    }

    if ($errmsg ne "") {
      $payutils::error = 1;
      $payutils::color{'promoid'} = 'badcolor';
      $payutils::errvar .= "promoid\|";
      $payutils::error{'dataentry'} .= "$errmsg";

      $dbh->disconnect();
    }
    else {
      # verify promotion for each good coupon code & apply to discount total.
      my @placeholder = ();
      my $qstr = "SELECT promocode,discount,disctype,usetype,status,minpurchase,sku,expires FROM promo_offers ";
      $qstr .= " WHERE username=?";
      push(@placeholder, $payutils::query{'publisher-name'});

      $qstr .= " AND promocode=?";
      push(@placeholder, $payutils::coupon_info{'promocode'});

      if ($payutils::query{'subacct'} ne "") {
        $qstr .= " AND subacct=?";
        push(@placeholder, $payutils::query{'subacct'});
      }

      my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",'QSTR',$qstr,%payutils::query);
      $sth->execute(@placeholder) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",'QSTR',$qstr,%payutils::query);
      ($payutils::coupon_promo_info{'promocode'},$payutils::coupon_promo_info{'discount'},$payutils::coupon_promo_info{'disctype'},$payutils::coupon_promo_info{'usetype'},$payutils::coupon_promo_info{'status'},$payutils::coupon_promo_info{'minpurchase'},$payutils::coupon_promo_info{'sku'},$payutils::coupon_promo_info{'expires'}) = $sth->fetchrow;

      $sth->finish;

      if ($payutils::coupon_promo_info{'promocode'} eq $payutils::coupon_info{'promocode'}) {
        $payutils::coupon_promo_info{'sku'} =~ s/[^a-zA-Z0-9\-\_\ \*\.\|]//g;
        $payutils::coupon_promo_info{'sku'} =~ s/\*/\./g;

        if ($payutils::coupon_promo_info{'expires'} < $datestr) {
          $errmsg .= "Coupon Code:$payutils::coupon_info{'promoid'}, Offer expired.";
        }
        elsif (($payutils::coupon_promo_info{'minpurchase'} ne "") && ($payutils::coupon_promo_info{'minpurchase'} > $payutils::query{'card-amount'})) {
          $errmsg .= "Coupon Code:$payutils::coupon_info{'promoid'}, Minimum purchase of $payutils::coupon_promo_info{'minpurchase'} required.";
        }

        if ($payutils::coupon_promo_info{'disctype'} eq "gift") {
          $payutils::gift_coupon = 1;
        }
      }
      else {
        $errmsg .= "Coupon Code:$payutils::coupon_info{'promoid'}, Offer cancelled.";
      }

      if ($errmsg ne "") {
        $payutils::error = 1;
        $payutils::color{'promoid'} = 'badcolor';
        $payutils::errvar .= "promoid\|";
        $payutils::error{'dataentry'} .= "$errmsg";
      }

      $dbh->disconnect();
    }
  }

  # 02/06/06 - added code for minimum purchase amount per order
  if (($payutils::feature{'minpurchase'} ne "") && ($payutils::query{'card-amount'} < $payutils::feature{'minpurchase'})) {
    $payutils::error = 1;
    $payutils::color{'card-amount'} = 'badcolor';
    $payutils::errvar .= "card-amount\|";
    $payutils::error{'dataentry'} .= "Sorry, we cannot process your order at this time.<br><font style=\"color: $payutils::badcolor\">Minimum purchase of $payutils::feature{'minpurchase'} is required.</font> Thank You.";
  }

  # 02/09/06 - added code for maximum purchase amount per order
  if (($payutils::feature{'maxpurchase'} ne "") && ($payutils::query{'card-amount'} > $payutils::feature{'maxpurchase'})) {
    $payutils::error = 1;
    $payutils::color{'card-amount'} = 'badcolor';
    $payutils::errvar .= "card-amount\|";
    $payutils::error{'dataentry'} .= "Sorry, we cannot process your order at this time.<br><font style=\"color: $payutils::badcolor\">Purchases exceeding $payutils::feature{'maxpurchase'} not permitted.</font> Thank You.";
  }

}


sub un_pw {
  my $output = '';

  if (($payutils::query{'suppress_unpw'} eq "yes") || ($payutils::query{'suppress-unpw'} eq "yes")) {
    # SHA the orderID number to get a unique username
    my $sha = new SHA;
    $sha->add($payutils::orderID);
    my $uname = $sha->hexdigest();

    #my $uname = crypt(($payutils::orderID * int(rand(255))), $payutils::query{'publisher-name'});
    #my $uname = $payutils::orderID;

    # clean up the new username
    $uname =~ s/ //g;
    $uname =~ s/\W//g;

    # get 2 letters for use with generated usernames/passwords
    my $temp1 = $uname;
    $temp1 =~ s/[^a-zA-Z]//g;

    # enforce username requirements
    if ($payutils::pwcheckplus ne "yes") {
      $uname = lc($uname);
    }
    else {
      # now setup password check plus requirements (uppercase, lowercase & numberic characters)
      substr($uname, 0, 1) = uc(substr($temp1, 0, 1));
      substr($uname, 1, 1) = lc(substr($temp1, 1, 1));
      substr($uname, 2, 1) = int(rand(10));
    }

    # limit username length, if necessary
    if (length($uname) > $payutils::unpw_maxlength) {
      $uname = substr($uname, 0, $payutils::unpw_maxlength);
    }

    # create unique password
    my $passwrd = crypt($uname, $uname);

    # clean up the new password
    $passwrd =~ s/\W//g;

    # enforce password requirements # what pwcheckplus is would be nice to know
    if ($payutils::pwcheckplus ne "yes") {
      $passwrd = lc($passwrd);
    }
    else {
      substr($passwrd, 0, 1) = uc(substr($temp1, 0, 1));
      substr($passwrd, 1, 1) = lc(substr($temp1, 1, 1));
      substr($passwrd, 2, 1) = int(rand(10));
    }

    # limit password length, if necessary
    if (length($passwrd) > $payutils::unpw_maxlength) {
      $passwrd = substr($passwrd, 0, $payutils::unpw_maxlength);
    }

    $output .= "<input type=\"hidden\" name=\"uname\" value=\"$uname\">\n";
    $output .= "<input type=\"hidden\" name=\"passwrd1\" value=\"$passwrd\">\n";
    $output .= "<input type=\"hidden\" name=\"passwrd2\" value=\"$passwrd\">\n";
  }
  elsif ($payutils::query{'hideunpw'} eq "yes") {
    $output .= "<input type=\"hidden\" name=\"uname\" value=\"$payutils::query{'uname'}\">\n";
    $output .= "<input type=\"hidden\" name=\"passwrd1\" value=\"$payutils::query{'passwrd1'}\">\n";
    $output .= "<input type=\"hidden\" name=\"passwrd2\" value=\"$payutils::query{'passwrd2'}\">\n";
  }
  else {
    $output .= "<tr><td align=\"left\" colspan=\"2\" class=\"goodcolor larger\">";
    ## Please Enter Your Desired Username &amp; Password Below:
    $output .= "$payutils::lang_titles{'pleaseenter'}[$payutils::lang]</td></tr>\n";

    $output .= "<tr><td colspan=\"2\" align=\"left\">\n";
    if ($payutils::error_string ne "") {
      $output .= "<b class=\"badcolor\">$payutils::error_string</b>\n";
    }
    ## Usernames and Passwords CAN NOT be the same, are restricted to a maximum of
    $payutils::lang_titles{'unpasswrd1'}[$payutils::lang] =~ s/\[pnp_unpw_maxlength\]/$payutils::unpw_maxlength/g;
    $output .= "$payutils::lang_titles{'unpasswrd1'}[$payutils::lang]";
    if ($payutils::pwcheckplus eq "yes") {
      ## usernames MUST contain both UPPER \/ lower case letters and numbers.
      $output .= "$payutils::lang_titles{'unpasswrd2'}[$payutils::lang]\n";
    }
    else {
      ## can contain only <b class=\"badcolor\">letters and\/or numbers.
      $output .= " $payutils::lang_titles{'unpasswrd3'}[$payutils::lang]\n";
    }
    #Any blank spaces or special characters (\*,\!,\#,\? etc... ) </b>will be removed. Please enter your choices accordingly.  You will receive an email with your Username and Password for your records.\n";
    $output .= "$payutils::lang_titles{'unpasswrd4'}[$payutils::lang]</td></tr>\n";

    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'uname'}\">Desired Username:</td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"uname\" size=\"$payutils::unpw_maxlength\" maxlength=\"$payutils::unpw_maxlength\" value=\"$payutils::query{'uname'}\" autocomplete=\"off\"> A Minimum of $payutils::unpw_minlength Characters Required</td>\n";
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'passwrd1'}\">Password:</td>";
    $output .= "<td align=\"left\"><input type=\"password\" name=\"passwrd1\" size=\"$payutils::unpw_maxlength\" maxlength=\"$payutils::unpw_maxlength\" value=\"$payutils::query{'passwrd1'}\" autocomplete=\"off\"> A Minimum of $payutils::unpw_minlength Characters Required</td>\n";
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'passwrd2'}\">Password:</td>";
    $output .= "<td align=\"left\"><input type=\"password\" name=\"passwrd2\" size=\"$payutils::unpw_maxlength\" maxlength=\"$payutils::unpw_maxlength\" value=\"$payutils::query{'passwrd2'}\" autocomplete=\"off\"> Please enter your password a second time to verify it.</td>\n";
    $output .= "\n";
  }

  return $output;
}

sub pay_screen1_badcard1 {
  my $output = '';

  if ($payutils::query{'MErrMsg'} ne "") {
    $output .= "<div style=\"text-align: center: width: 75%\">\n";
    $output .= "<span calss=\"larger\">There seems to be a problem with the information you entered.\n";
    $output .= "<br>\n";
    if ($payutils::query{'MErrMsg'} =~ /fails LUHN-10 check/) {
      $output .= "The number you entered is NOT a valid credit card number.  Please re-enter your credit ";
      $output .= "card number and check it closely before resubmitting your order.\n";
    }
    elsif ($payutils::query{'MErrMsg'} =~ /or are not configured to accept the card type used/) {
      $output .= "Sorry - We are currently not authorized to accept that credit card type.  Please choose another card. Thank You.\n";
    }
    else {
      $output .= "The Credit Card Processor has returned the following error message: <br><b>$payutils::query{'MErrMsg'}</b>\n";
    }
    $output .= "<br>\n";
    $output .= "$payutils::lang_titles{'incorrect'}[$payutils::lang]\n";
    $output .= "$payutils::lang_titles{'inerror'}[$payutils::lang]\n";
    $output .= "</div>\n";
  }

  if (($payutils::error > 0) && ($payutils::query{'pass'} == 1)) {
    $output .= "<div class=\"larger\">\n";
    $output .= "<dl><dt><dd><dl><dt><dd>\n";
    $output .= "Some <b>Required Information</b> ";
    $output .= "has not been filled in correctly.  <br>Please re-enter \n";
    $output .= "the information in the <b class=\"badcolor\">fields marked in RED</b>.<br>\n";
    if ($payutils::error_string ne "") {
      $output .= "$payutils::error_string\n";
    }
  }
  $output .= "</dl></dl>\n";
  $output .= "</div>\n";

  return $output;
}


sub taxcalc {
  #  James - 04/19/2000 @ 4:05 pm - Do not change the ($payutils::query{'tax'} < 0.001) calculation
  #  This to work with items that are to have a $0.00 dollar amount.
  #  * Note: the item price must be set $0.001 in order to work correctly.

  my ($taxable_state);
  if (($payutils::query{'notax'} != 1) && ($payutils::query{'tax'} < 0.001)) {
    my @taxstate = split(/\||\,/,$payutils::query{'taxstate'});
    my @taxrate = split(/\||\,/,$payutils::query{'taxrate'});

    if ($payutils::query{'taxbilling'} eq "yes") {
      $taxable_state = $payutils::query{'card-state'};
    }
    else {
      if ($payutils::query{'state'} ne "") {
        $taxable_state = $payutils::query{'state'};
      }
      else {
        $taxable_state = $payutils::query{'card-state'};
      }
    }

    my $k = 0;
    if ($payutils::query{'taxstate'} eq "all") {
      if ($payutils::query{'taxship'} eq "no") {
        $payutils::query{'tax'} = ($payutils::taxsubtotal) * $taxrate[$k];
      }
      else {
        $payutils::query{'tax'} = ($payutils::taxsubtotal + $payutils::query{'shipping'}) * $taxrate[$k];
      }
    }
    else {
      foreach my $var (@taxstate) {
        if (($taxrate[$k] > 0) && ($taxable_state =~ /$var/i)) {
          if ($payutils::query{'taxship'} eq "no") {
            $payutils::query{'tax'} = ($payutils::taxsubtotal) * $taxrate[$k];
          }
          else {
            $payutils::query{'tax'} = ($payutils::taxsubtotal + $payutils::query{'shipping'}) * $taxrate[$k];
          }
        }
        $k++;
      }
    }
    $payutils::query{'tax'} = &Round($payutils::query{'tax'});
  }
}

sub eParcel {

  my ($destinationPostalCode,$TotalXmlRequest,$statusMessage);

  if ($payutils::query{'zip'} ne "") {
     $destinationPostalCode = "$payutils::query{'zip'}";
  }
  else {
    $destinationPostalCode = $payutils::query{'card-zip'};
  }

  my $xmlRequestHeader = "<?xml version=\"1.0\" ?><eparcel><ratesAndServicesRequest><merchantCPCID>$payutils::query{'CPCID'}</merchantCPCID><lineItems>";

  $TotalXmlRequest = $xmlRequestHeader;

# 3. For each item you sould generate a string that contains the data as follows
# usually, the next two lines of code would be included within for loop for example.
# The tags are fairly explanatory:
#  <quantity> is the number of articles of THIS type. For example, a client could order 2 pens and 5 erasers.
#              this is the number that would be put here.
#  <weight>,<length>,<width> and <height> are the characteristics for ONE article of this type.
#              this value is usually kept in some database on the merchant server.
#  <description> is a textual description of the product

  for (my $j=1; $j<=$payutils::max; $j++) {
    my($xmlBody) = "<item><quantity>$payutils::quantity[$j]</quantity><weight>$payutils::weight[$j]</weight><length>$payutils::query{\"L$j\"}</length><width>$payutils::query{\"W$j\"}</width><height>$payutils::query{\"H$j\"}</height><description>$payutils::description[$j]</description></item>";
    $TotalXmlRequest .= $xmlBody;
  }

# 4. The data will now contain the postal code provided
# i.e. $destinationPostalCode is replaced by the shipping destination postal code.
  my($xmlTrailer) = "</lineItems><city>Toronto</city><provOrState>Ontario</provOrState><country>CANADA</country><postalCode> $destinationPostalCode</postalCode></ratesAndServicesRequest></eparcel>";

  $TotalXmlRequest .= $xmlTrailer;

  # 5. Open a socket to our server in a way similar to the following
  # IP = 206.191.4.228, port = 30000
  my $remote = "206.191.4.228";
  my $port = "30000";
  my $sock = new IO::Socket::INET (  PeerAddr	=>	$remote,
				PeerPort	=>	$port,
				Proto 		=>	'tcp' ) ;


  print $sock "$TotalXmlRequest\n" ;
  $sock->flush();
  # ... unless it could not connect
  unless ($sock) {
     $statusMessage = "Could not connect to server.";
  }

  my($line) ;
  my($response) = "";

  while ($line = <$sock>) {
     $response .= $line;
     if ($line =~ /<\/eparcel>/) {
        last;
     }
  }
  return $response;

}

sub uspscalc {  ##  US Postal Service Rate Calculator
  # USPS Site submits data as query string.  Returns Table that needs to be parsed.
  my $host = "http://postcalc.usps.gov/speed.asp";
  my %shipstring = ();
  $shipstring{'OZ'} = ""; # Originationg Zip Code
  $shipstring{'DZ'} = $payutils::query{'zip'};  # Destination Zip Code
  $shipstring{'P'} = ""; # Weight in pounds
  $shipstring{'O'} = ""; # Weight in ounces
  $shipstring{'LP'} = "package"; # Appears to be optional
  $shipstring{'Char'} = "0"; # Package Charateristics Options are 0-12, 0=Standard
  $shipstring{'zipok'} = "Continue"; # Appears to be submit button.  Probably can ignore
  $shipstring{'BL'} = "off"; # off/on Appears to be a flag for large items.
                             # BL=on  for large items i.e. The length of its longest side plus the distance around
                             # its thickest part is more than 84" and less than or equal to 108
  $shipstring{'OV'} = "off"; # off/on  Appears to be a flag for Oversized items.
                             # The length of its longest side plus the distance around its thickest part is more than
                             # 108" and less than or equal to 130
  $shipstring{'Dir'} = "forward"; # ?
  $shipstring{'retspec'} = "no";  # ?

  my ($pairs);
  foreach my $key (keys %shipstring) {
    $pairs .= "\&$key=$shipstring{$key}";
  }

}

sub softcart_remote {
  my $pairs = "orderid=$payutils::query{'orderid'}";
  my $data =  &miscutils::formpost_raw($payutils::query{'path-remote'},$pairs);
  my @lines = split("\n",$data);
  foreach my $var (@lines) {
    if ($var ne "") {
      my ($name,$value) = split('\|',$var);
      $payutils::query{"$name"} = $value;
    }
  }
  return %payutils::query;
}

sub cart32 {
  for (my $k=1; $k<=$payutils::query{'NumberOfItems'}; $k++) {
    $payutils::query{"item$k"} = substr($payutils::query{"Item$k"},0,4) . $k;
    $payutils::query{"cost$k"} = $payutils::query{"Price$k"};
    $payutils::query{"quantity$k"} = $payutils::query{"Qty$k"};
    $payutils::query{"description$k"} = $payutils::query{"Item$k"};
    $payutils::query{"option$k"} = $payutils::query{"Option$k"};
  }
}

sub wallet {
  my ($pairs,$url);
  foreach my $key (keys %payutils::query) {
    $payutils::query{$key} =~ s/(\W)/'%' . unpack("H2",$1)/ge;
    if($pairs ne "") {
      $pairs = "$pairs\&$key=$payutils::query{$key}" ;
    }
    else{
      $pairs = "$key=$payutils::query{$key}" ;
    }
  }
  if ($payutils::query{'ewalletversion'} eq "2") {
    $url = "$payutils::path_wallet2";
  }
  else {
    $url = "$payutils::path_wallet";
  }

  my $page = &miscutils::formpost_raw($url,$pairs);
  print $page;
  exit;
}


# programs in web/payment/*.cgi use this subroutine
sub luhn10{
  my($CCtest) = @_;
  my $len = length($CCtest);
  my @digits = split('',$CCtest);
  my ($a,$b,$c,$temp,$j,$sum,$check,$luhntest);
  for (my $k=0; $k<$len; $k++) {
    $j = $len - 1 - $k;
    if (($j - 1) >= 0) {
      $a = $digits[$j-1] * 2;
    } else {
      $a = 0;
    }
    if (length($a) > 1) {
      ($b,$c) = split('',$a);
      $temp = $b + $c;
    } else {
      $temp = $a;
    }
    $sum = $sum + $digits[$j] + $temp;
    $k++;
  }
  $check = substr($sum,length($sum)-1);
  if ($check eq "0") {
    $luhntest = "PASS";
  } else {
    $luhntest = "FAIL";
  }
  return($luhntest);
}

sub modulus10{ # used to test check routing numbers
  my($ABAtest) = @_;
  my @digits = split('',$ABAtest);
  my ($modtest);
  my $sum = $digits[0] * 3 + $digits[1] * 7 + $digits[2] * 1 + $digits[3] * 3 + $digits[4] * 7 + $digits[5] * 1 + $digits[6] * 3 + $digits[7] * 7;
  my $check = 10 - ($sum % 10);
  $check = substr($check,-1);
  my $checkdig = substr($ABAtest,-1);
  if ($check eq $checkdig) {
    $modtest = "PASS";
  } else {
    $modtest = "FAIL";
  }
  return($modtest);
}

sub referrer_check {
  my ($domain_check) = @_;
  my $referrer_domain = $ENV{'HTTP_REFERER'};
  if (($referrer_domain !~ /plugnpay.com/) && ($referrer_domain !~ /$domain_check/i)) {
    my $response_message = "Access to this page was from an un-authorized source.<br>  Please use the back button and resubmit the form again.";
    print response_page("$response_message");
    exit;
  }
}

sub response_page2 {
  my $output = '';

  my ($message,$autoclose) = @_;
  if ($autoclose eq "yes") {
    $autoclose = " onLoad=\"closeself()\;\"";
  }
  $output .= "<!DOCTYPE html>\n";
  $output .= "<html>\n";
  $output .= "<head>\n";
  $output .= "<title>Credit Card Fraud Prevention Screen</title> \n";

  my $client = $payutils::query{'client'};
  $client =~ s/[^a-zA-Z0-9]//g;

  if ($payutils::query{'client'} =~ /mobile/) {
    $output .= "  <meta name=\"viewport\" content=\"width=320; initial-scale=1.0; maximum-scale=1.0; user-scalable=0;\"/>\n";
    $output .= "  <link rel=\"apple-touch-icon\" href=\"/javascript/iui/pnpicon.png\" />\n";
    $output .= "  <meta name=\"apple-touch-fullscreen\" content=\"YES\" />\n";
    $output .= "  <style type=\"text/css\" media=\"screen\">\@import \"/css/$client/iui.css\";</style>\n";
  }

  $output .= "<script Language=\"Javascript\">\n";
  $output .= "<\!-- Start Script\n";
  $output .= "function closeself() {\n";
  $output .= "  resultsWindow = window.close('results');\n";
  $output .= "}\n";
  $output .= "// end script-->\n";
  $output .= "</script>\n";

  $output .= "<style type=\"text/css\">\n";
  $output .= "<!--\n";
  $output .= "th { font-family: $payutils::fontface; font-size: 10pt; color: $payutils::goodcolor }\n";
  $output .= "td { font-family: $payutils::fontface; font-size: 9pt; color: $payutils::goodcolor }\n";
  $output .= ".larger { font-size: 12pt }\n";
  $output .= "-->\n";
  $output .= "</style>\n";

  $output .= "</head>\n";
  $output .= "<body bgcolor=\"#FFFFFF\"$autoclose>\n";
  $output .= "<div align=center style=\"90%\"><br>\n";
  $output .= "<table><tr><th class=\"larger\">$message</th></tr></table><br>\n";
  $output .= "<br>\n";
  $output .= "<form><input type=button value=\"Close\" onClick=\"closeself();\"></form>\n";
  $output .= "</div>\n";
  $output .= "</body>\n";
  $output .= "</html>\n";

  return $output;
}


sub response_page {
  my $output = '';

  my ($message) = @_;
  $output .= "<!DOCTYPE html>\n";
  $output .= "<html>\n";
  $output .= "<head>\n";
  $output .= "<title>Un-Authorized Access</title>\n";

  my $client = $payutils::query{'client'};
  $client =~ s/[^a-zA-Z0-9]//g;

  if ($payutils::query{'client'} =~ /mobile/) {
    $output .= "  <meta name=\"viewport\" content=\"width=320; initial-scale=1.0; maximum-scale=1.0; user-scalable=0;\"/>\n";
    $output .= "  <link rel=\"apple-touch-icon\" href=\"/javascript/iui/pnpicon.png\" />\n";
    $output .= "  <meta name=\"apple-touch-fullscreen\" content=\"YES\" />\n";
    $output .= "  <style type=\"text/css\" media=\"screen\">\@import \"/css/$client/iui.css\";</style>\n";
  }

  $output .= "<style type=\"text/css\">\n";
  $output .= "<!--\n";
  $output .= "th { font-family: $payutils::fontface; font-size: 10pt; color: $payutils::goodcolor }\n";
  $output .= "td { font-family: $payutils::fontface; font-size: 9pt; color: $payutils::goodcolor }\n";
  $output .= ".larger { font-size: 12pt }\n";
  $output .= "-->\n";
  $output .= "</style>\n";

  $output .= "</head>\n";
  $output .= "<body bgcolor=\"#ffffff\">\n";
  $output .= "<br>\n";
  $output .= "<div align=center style=\"90%\">\n";
  $output .= "<table><tr><th class=\"larger\">$message</th></tr></table><br>\n";
  $output .= "</div>\n";
  $output .= "</body>\n";
  $output .= "</html>\n";

  return $output;
}


sub underscore_to_hyphen {
  foreach my $key (keys %payutils::query) {
    if(($key ne "acct_code") && ($key =~ /\_/)) {
      $_ = $payutils::query{$key};
      $payutils::query{$key} = "";
      $key =~ tr/\_/\-/;
      $payutils::query{$key} = $_;
    }
  }
}

sub adobefdf {
  my (@deviceexpr,@devicetype,@deviceid);

  $payutils::query{'adobetitle'} = "A Book";
  $payutils::query{'adobecompany'} = "A Company";
  $payutils::query{'adobedocurl'} = "http://www.genesysweb.com/adobe/doc.pdf";
  $payutils::query{'adobesellerurl'} = "http://www.genesysweb.com/adobe/mybook.fdf";


  my $docurl = 'http://www.adobe.com/acrobat/mybook.pdf';
  my $sellername = $payutils::query{'adobecompany'};
  my $wsbfile = "/home/p/pay1/adobe/wsb/$payutils::query{'sellerID'}.wsb";
  my $doctitle = $payutils::query{'adobetitle'};
  my $sellerid = $payutils::query{'sellerID'};
  my $sellerurl = 'https://pay1.plugnpay.com/payment/testadobepay.cgi';
  my $docid = $payutils::query{'docID'};

  my $perms = 'FFFFFFE3';          # permissions to be applied to the file
  my $webbroker = '/home/p/pay1/adobe/webbroker';

  # get current UTC time (must be GMT relative)
  my @t = gmtime;
  my $utc_now = sprintf( "%04d%02d%02d%02d%02d%02d",
        $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0] );
  @t = gmtime( time() - (24*3600) );
  my $utc_yesterday = sprintf( "%04d%02d%02d%02d%02d%02d",
        $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0] );

  # push time as a device
  push @deviceexpr, 'ge';
  push @devicetype, 'utc';
  push @deviceid, "UTC-$utc_yesterday";

  # get title key
  if ( $sellerid eq '' || $sellername eq '' ) {
    print STDERR "Error: one of sellerid or sellername is not specified\n";
    exit 1;
  }

  if( !open( WBFILE, "| $webbroker -3 -w \"$wsbfile\"" ) ) {
    print STDERR "Could not pipe to webbroker.cgi\n";
    exit 1;
  }

  print WBFILE "<seller name=\"$sellername\" id=\"$sellerid\"\n";
  print WBFILE "url=\"$sellerurl\"/>\n";
  print WBFILE "<document-set url=\"$docurl\" title=\"$doctitle\">\n";
  print WBFILE "<document id=\"$docid\"/>\n";
  print WBFILE "</document-set>\n";
  print WBFILE "<transaction id=\"123456789\" utc=\"$utc_now\"/>\n";
  print WBFILE "<request name=\"prefs\"/>\n";
  print WBFILE "<request version=\"00040005\"/>\n";
  close WBFILE;
}


sub update_record {
  my $output = '';

  $output .= "<!DOCTYPE html>\n";
  $output .= "<html>\n";
  $output .= "<head>\n";

  $output .= "<style type=\"text/css\">\n";
  $output .= "<!--\n";
  $output .= "th { font-family: $payutils::fontface; font-size: 10pt; color: $payutils::goodcolor }\n";
  $output .= "td { font-family: $payutils::fontface; font-size: 9pt; color: $payutils::goodcolor }\n";
  $output .= ".badcolor { color: $payutils::badcolor }\n";
  $output .= ".goodcolor { color: $payutils::goodcolor }\n";
  $output .= ".larger { font-size: 12pt }\n";
  $output .= ".smaller { font-size: 9pt }\n";
  $output .= ".short { font-size: 8% }\n";
  $output .= ".itemscolor { background-color: $payutils::titlebackcolor; color: $payutils::titlecolor }\n";
  $output .= ".itemrows { background-color: $payutils::itemrow }\n";
  $output .= ".info { position: static }\n";
  $output .= "-->\n";
  $output .= "</style>\n";

  $output .= "<script Language=\"Javascript\">\n";
  $output .= "<\!-- Start Script\n";
  $output .= "function adjust_win() {\n";
  $output .= "  self.resizeTo(450,550);\n";
  $output .= "}\n";
  $output .= "// end script-->\n";
  $output .= "</script>\n\n";

  $output .= "</head>\n";
  $output .= "<body bgcolor=\"#ffffff\" onLoad=\"adjust_win();\">\n";

  my $dbh_init = &miscutils::dbhconnect('wallet');

  my $sth = $dbh_init->prepare(q{
      SELECT name,email,username,password
      FROM subscriber
      WHERE walletid=?
    }) or die "Can't prepare: $DBI::errstr";
  $sth->execute("$payutils::cookie{'pnpid'}") or die "Can't execute: $DBI::errstr";
  my ($name,$email,$username,$password) = $sth->fetchrow;
  $sth->finish;
  $dbh_init->disconnect;
  if ($password ne $payutils::query{'cookie_pw'}) {
    $output .= "Sorry wrong password\n";
  }
  else {
    customer_record();
    $output .= "<table border=0>\n";
    $output .= "<form name=\"blah\" method=\"post\">\n";
    $output .= exp_billing();
    $output .= pay_screen1_shipping();
    $output .= "<tr><td>&nbsp;</td><td><input type=\"submit\" name=\"client\" value=\"Change\"> <input type=\"button\" value=\"Close Window\" onClick=\"self.close();\"></td></tr>\n";
    $output .= "</form>\n";
    $output .= "</table>\n";
  }
  $output .= "</body>\n";
  $output .= "</html>\n";

  return $output;
}


sub update_express_record {
  my $cardnumber = $payutils::query{'card-number'};
  my($q);
  if (index($cardnumber,'*') > 0) {
    $q=1;
  }
  else {
    $q=0;
  }

  my ($enccardnumber,$length) = &rsautils::rsa_encrypt_card($cardnumber,'/home/p/pay1/pwfiles/keys/key');
  substr($cardnumber,4,length($payutils::query{'card-number'})-6) = "****";
  $payutils::query{'month-exp'} = substr($payutils::query{'month-exp'},0,2);
  $payutils::query{'year-exp'} = substr($payutils::query{'year-exp'},0,2);
  $payutils::query{'card-exp'} = $payutils::query{'month-exp'} . "/" . $payutils::query{'year-exp'};

  my $dbh = &miscutils::dbhconnect('wallet');

  if ($q == 0) {
    my $sth = $dbh->prepare(q{
        UPDATE billing
        SET name=?,addr1=?,addr2=?,addr3=?,city=?,state=?,zip=?,country=?,cardtype=?,cardnumber=?,enccardnumber=?,length=?,cardexp=?
        WHERE walletid=?
        AND commonname='express'
      }) or die "Can't prepare: $DBI::errstr";
    $sth->execute($payutils::query{'card-name'},$payutils::query{'card-address1'},$payutils::query{'card-address2'},$payutils::query{'card-address3'},$payutils::query{'card-city'},
                     $payutils::query{'card-state'},$payutils::query{'card-zip'},$payutils::query{'card-country'},
                     $payutils::query{'card-type'},$cardnumber,$enccardnumber,$length,$payutils::query{'card-exp'}, "$payutils::cookie{'pnpid'}") or die "Can't execute: $DBI::errstr";
    $sth->finish;
  }
  elsif ($q == 1) {
    my $sth = $dbh->prepare(q{
        UPDATE billing
        SET name=?,addr1=?,addr2=?,addr3=?,city=?,state=?,zip=?,country=?,cardtype=?,cardexp=?
        WHERE walletid=?
        AND commonname='express'
      }) or die "Can't prepare: $DBI::errstr";
    $sth->execute($payutils::query{'card-name'},$payutils::query{'card-address1'},$payutils::query{'card-address2'},$payutils::query{'card-address3'},$payutils::query{'card-city'},
                     $payutils::query{'card-state'},$payutils::query{'card-zip'},$payutils::query{'card-country'},
                     $payutils::query{'card-type'},$payutils::query{'card-exp'}, "$payutils::cookie{'pnpid'}") or die "Can't execute: $DBI::errstr";
    $sth->finish;
  }

  my $sth = $dbh->prepare(q{
      UPDATE shipping
      SET sfname=?,slname=?,shipaddr1=?,shipaddr2=?,shipaddr3=?,shipcity=?,shipstate=?,shipzip=?,shipcountry=?,shipphone=?,shipemail=?
      WHERE walletid=?
      AND commonname='express'
    }) or die "Can't prepare: $DBI::errstr";
  $sth->execute($payutils::query{'shipname'},"",$payutils::query{'address1'},$payutils::query{'address2'},$payutils::query{'address3'},$payutils::query{'city'},$payutils::query{'state'},
                   $payutils::query{'zip'},$payutils::query{'country'},$payutils::query{'phone'},$payutils::query{'email'}, "$payutils::cookie{'pnpid'}") or die "Can't execute: $DBI::errstr";
  $sth->finish;

  $dbh->disconnect;

  my $message = "Account Information has been updated successfully";
  print response_page2($message,"no");
  exit;
}


sub forgot_password {
  my $dbh_init = &miscutils::dbhconnect('wallet');

  my $sth = $dbh_init->prepare(q{
      SELECT email,password,name
      FROM subscriber
      WHERE walletid=?
    }) or die "Can't prepare: $DBI::errstr";
  $sth->execute("$payutils::cookie{'pnpid'}") or die "Can't execute: $DBI::errstr";
  my ($email,$password,$name) = $sth->fetchrow;
  $sth->finish;

  $dbh_init->disconnect;

  $email = substr($email,0,50);
  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setFormat('text');
  $emailObj->setTo($email);
  $emailObj->setFrom('passwd@plugnpay.com');
  $emailObj->setSubject("$name, Here is your PnP Express Password !"); # there's that super important space before the ! again
  my $message = '';
  $message .= "Hello $name:\n";
  $message .= "Per your request, here is your PnP Express Password: $password\n";
  $message .= "Please write it down somewhere safe for future reference!\n\n";
  $message .= "Support Staff\n";
  $message .= "\n\n";
  $emailObj->setContent($message);
  $emailObj->send();

  $message = "Your password has been sent to the email address we have on file for you.  Please click here now to close this window and return to the order form.";
  my $output = response_page2($message);
  return $output;
}


#   added 01/17/2000
sub Round {
   my $item  = shift(@_);

   my $temp1 = (int($item *100)*10);
   my $temp2 = int($item *1000);
   my $temp3 = $temp2 - $temp1;  #get tenths of a pennie

   my $trunc = 0;    #round down
   if ( $temp3 >= 5 ) {
      $trunc = 10;   #round up
   }
   my $value = ($temp1 + $trunc)/1000;
   my $retval = sprintf("%.2f", $value);

   return ( $retval );
}


sub calculate_discnt {

  if (($payutils::query{'acct_code3'} eq "billpay") && ($payutils::query{'discnt'} > 0)) {
    $payutils::query{'discnt'} = &Round($payutils::query{'discnt'});
    return "$payutils::query{'discnt'}";
  }

  if ($payutils::query{'promoid'} eq "") {
    return;
  }

  my $discounttotal = 0;
  my $taxdiscounttotal = 0;

  if ($payutils::coupon_promo_info{'sku'} ne "") {
    for (my $i=1; $i<=$payutils::max; $i++) {
      if (($payutils::item[$i] =~ /$payutils::coupon_promo_info{'sku'}/) && ($payutils::subtotal >= $payutils::coupon_promo_info{'minpurchase'}) && ($payutils::coupon_promo_info{'status'} !~ /cancel/)) {
        if ($payutils::coupon_promo_info{'disctype'} eq "cert") {
          if ($payutils::coupon_promo_info{'discount'} =~ /\w/) {
            # when 'discount' is set, see if customer has matching prerequisite product SKU in the order
            my $prerequisite = 0;
            for (my $i=1; $i<=$payutils::max; $i++) {
              if ($payutils::item[$i] =~ /$payutils::coupon_promo_info{'discount'}/) {
                $prerequisite = 1;
                last;
              }
            }
            if ($prerequisite == 1) {
              # apply discount, because prerequisite was fulfilled
              $discounttotal += $payutils::cost[$i] * $payutils::quantity[$i];
              if ($payutils::taxable[$i] !~ /N/i) {
                #$taxdiscounttotal += $payutils::cost[$i] * $payutils::quantity[$i];
                $taxdiscounttotal += $discounttotal;
              }
            }
          }
          else {
            # assume no SKU prerequisite for item certificate discount, apply discount normally
            $discounttotal += $payutils::cost[$i] * $payutils::quantity[$i];
            if ($payutils::taxable[$i] !~ /N/i) {
              #$taxdiscounttotal += $payutils::cost[$i] * $payutils::quantity[$i];
              $taxdiscounttotal += $discounttotal;
            }
          }
        }
        elsif ($payutils::coupon_promo_info{'disctype'} eq "amt") {
          $discounttotal += $payutils::coupon_promo_info{'discount'} * $payutils::quantity[$i];
          if ($payutils::taxable[$i] !~ /N/i) {
            #$taxdiscounttotal += $payutils::cost[$i] * $payutils::quantity[$i];
            $taxdiscounttotal += $discounttotal;
          }
        }
        elsif ($payutils::coupon_promo_info{'disctype'} eq "pct") {
          $discounttotal += ($payutils::cost[$i] * $payutils::coupon_promo_info{'discount'}) * $payutils::quantity[$i];
          if ($payutils::taxable[$i] !~ /N/i) {
            #$taxdiscounttotal += $payutils::cost[$i] * $payutils::quantity[$i];
            $taxdiscounttotal += $discounttotal;
          }
        }
        elsif ($payutils::coupon_promo_info{'disctype'} eq "gift") {
          $payutils::gift_coupon = 1;
        }

      }
    }
  }
  else {
   if (($payutils::subtotal >= $payutils::coupon_promo_info{'minpurchase'}) && ($payutils::coupon_promo_info{'status'} !~ /cancel/)) {
      if ($payutils::coupon_promo_info{'disctype'} eq "amt") {
        $discounttotal += $payutils::coupon_promo_info{'discount'};
      }
      elsif ($payutils::coupon_promo_info{'disctype'} eq "pct") {
        $discounttotal += ($payutils::subtotal * $payutils::coupon_promo_info{'discount'});
      }
      elsif ($payutils::coupon_promo_info{'disctype'} eq "gift") {
        $payutils::gift_coupon = 1;
      }
    }
  }

  $discounttotal = sprintf("%0.02f", $discounttotal);
  $taxdiscounttotal = sprintf("%0.02f", $taxdiscounttotal);

  if ($discounttotal > $payutils::subtotal) {
    $discounttotal = $payutils::subtotal;
    $payutils::subtotal = 0.00;
    $payutils::taxsubtotal = 0.00;
  }
  else {
    $payutils::subtotal -= $discounttotal;
    $payutils::taxsubtotal -= $taxdiscounttotal;
  }
  if ($discounttotal > 0.00) {
    $payutils::query{'discnt'} = $discounttotal;
  }

  $discounttotal = sprintf("%0.02f", $discounttotal);
  return ($discounttotal);
}


sub calculate_gift_cert_discnt {

  if ($payutils::query{'promoid'} eq "") {
    return;
  }

  # initialize variables
  my ($discounttotal);

  if ($payutils::coupon_promo_info{'sku'} ne "") {
    my $apt_amt = 0; # holds subtotal of just those items which match promo sku requirement

    for (my $i=1; $i<=$payutils::max; $i++) {
      if (($payutils::item[$i] =~ /$payutils::coupon_promo_info{'sku'}/) && ($payutils::subtotal > $payutils::coupon_promo_info{'minpurchase'}) && ($payutils::coupon_promo_info{'status'} !~ /cancel/)) {
        if ($payutils::coupon_promo_info{'disctype'} eq "cert") {
          # do nothing
          next;
        }
        elsif ($payutils::coupon_promo_info{'disctype'} eq "amt") {
          # do nothing
          next;
        }
        elsif ($payutils::coupon_promo_info{'disctype'} eq "pct") {
          # do nothing
          next;
        }
        elsif ($payutils::coupon_promo_info{'disctype'} eq "gift") {
          $apt_amt += $payutils::cost[$i] * $payutils::quantity[$i];
        }
      }
    }

    if ($apt_amt > $payutils::coupon_info{'limit'}) {
      $discounttotal += $payutils::coupon_info{'limit'};
    }
    else {
      $discounttotal += $apt_amt;
    }

  }
  else {
    if (($payutils::subtotal > $payutils::coupon_promo_info{'minpurchase'}) && ($payutils::coupon_promo_info{'status'} !~ /cancel/)) {
      if ($payutils::coupon_promo_info{'disctype'} eq "amt") {
        # do nothing
      }
      elsif ($payutils::coupon_promo_info{'disctype'} eq "pct") {
        # do nothing
      }
      elsif ($payutils::coupon_promo_info{'disctype'} eq "gift") {
        $discounttotal += $payutils::coupon_info{'limit'};
      }
    }
  }

  $discounttotal = sprintf("%0.02f", $discounttotal);

  # deduct gift cert from order total
  if ($discounttotal > $payutils::query{'card-amount'}) {
    $discounttotal = $payutils::query{'card-amount'};
  }
  else {
    $payutils::query{'card-amount'} -= $discounttotal;
  }

  if ($discounttotal > 0) {
    $payutils::query{'discnt'} = $discounttotal;
  }

  $discounttotal = sprintf("%0.02f", $discounttotal);
  return ($discounttotal);
}


sub recurring_record {
  if (($payutils::query{'username'} ne "") && ($payutils::query{'password'} ne "")) {
    my $database = $payutils::query{'publisher-name'};
    if ($payutils::query{'merchantdb'} ne "") {
      $database = $payutils::query{'merchantdb'};
    }

    my $dbh_cust = &miscutils::dbhconnect("$database");

    # get customer profile info for username
    my $sth = $dbh_cust->prepare(q{
        SELECT username,password,name,addr1,addr2,city,state,zip,country,email
        FROM customer
        WHERE LOWER(username) LIKE LOWER(?)
      }) or die "Can't prepare: $DBI::errstr";
    $sth->execute($payutils::query{'username'}) or die "Can't execute: $DBI::errstr";
    my ($username,$password,$name,$addr1,$addr2,$city,$state,$zip,$country,$email) = $sth->fetchrow;
    $sth->finish;

    if (($payutils::feature{'allow_un_fuzzy'} == 1) && ($payutils::query{'username'} =~ /^($username)$/i)) {
      # correct username case, by overwriting with database version
      $payutils::query{'username'} = $username;
    }

    if (($payutils::query{'username'} eq $username) && ($username ne "")) {
      # assuming we found a matching customer profile, do validation
      if (($payutils::feature{'allow_pw_update'} == 1) && ($payutils::query{'allow_pw_update'} == 1) && ($password ne $payutils::query{'password'})) {
        # update customer profile password on file, if needed
        my $sth = $dbh_cust->prepare(q{
            UPDATE customer
            SET password=?
            WHERE username=?
          }) or die "Can't prepare: $DBI::errstr";
        $sth->execute($payutils::query{'password'},$username) or die "Can't execute: $DBI::errstr";
        $sth->finish;
        $password = $payutils::query{'password'};
      }

      if (($payutils::query{'password'} eq $password) && ($password ne "")) {
        # username/password match, update query data with that from customer profile
        $payutils::query{'card-name'} = $name;
        $payutils::query{'card-address1'} = $addr1;
        $payutils::query{'card-address2'} = $addr2;
        $payutils::query{'card-city'} = $city;
        $payutils::query{'card-state'} = $state;
        $payutils::query{'card-zip'} = $zip;
        $payutils::query{'card-country'} = $country;
        $payutils::query{'email'} = $email;

        $payutils::match = 1;
        $payutils::unpwcheck = "no";
        $payutils::query{'unpwcheck'} = "no";
      }
    }

    $dbh_cust->disconnect;
  }

  if ($payutils::match != 1) {
    $payutils::error_string = "The Username and Password you entered do not match a user on file and can not be used to renew an existing account.";

    if ($payutils::query{'hideunpw'} eq "yes") {
      my %result = (
        'FinalStatus', "problem",
        'MStatus', "failure",
        'MErrMsg', $payutils::error_string,
        'resp-code', "PXX"
      );
      my %data = (%payutils::query,%result);
      foreach my $key (sort keys %data) {
        if (($key =~ /(card.number|card.exp|card.cvv|merch.txn|cust.txn|month.exp|year.exp|magstripe|mpgiftcard|mpcvv)/i) || ($key =~ /(.link)$/i)) {
          delete $data{$key};
        }
      }
      my $data_ref = \%data;

      my $rl = new PlugNPay::ResponseLink($payutils::query{'publisher-name'},$payutils::query{'problem-link'},$data_ref,uc($payutils::feature{'transitiontype'}),"none");
      $rl->doRequest();
      print $rl->getResponseContent;
      exit;
    }
    else {
      $payutils::error_string .= " Please go back and check the Username and Password you entered or pick a new username and password in the space below.<p>";
      $payutils::error = 1;
    }
  }
}


sub generate_ups_request {
  my %shipstring = ();
  $shipstring{'appVersion'} = "1.0";
  $shipstring{'acceptUPSLicenseAgreement'} = "Yes";
  $shipstring{'responseType'} = "application/x-ups-rss";
  $shipstring{'actionCode'} = "3";
  $shipstring{'shipperPostalCode'} = $payutils::query{'merchant-zip'};
  $shipstring{'consigneePostalCode'} = $payutils::query{'zip'};
  $shipstring{'consigneeCountry'} = $payutils::query{'country'};
  $shipstring{'packageActualWeight'} = $payutils::totalwgt;
  $shipstring{'residentialInd'} = "1";
  $shipstring{'packagingType'} = "00";
  $shipstring{'serviceLevelCode'} = $payutils::query{'serviceLevelCode'};
  if ($payutils::query{'rate-chart'} ne "") {
    $shipstring{'rateChart'} = $payutils::query{'rate-chart'};
  }
  else {
    $shipstring{'rateChart'} = $payutils::query{'ups-rate-chart'};
  }
  if ($shipstring{'packageActualWeight'} < 1.0) {
    $shipstring{'packageActualWeight'} = 1.0;
  }
  my $tempint = int($shipstring{'packageActualWeight'});
  my $tempdec = $shipstring{'packageActualWeight'} - $tempint;
  if ($tempdec > 0) {
    $shipstring{'packageActualWeight'} = $tempint + 1;
  }
  else {
    $shipstring{'packageActualWeight'} = $tempint;
  }
  my $poststring = "";
  foreach my $key (keys %shipstring) {
    $poststring .= $key . "\=" .$shipstring{$key} . "\&";
  }
  chop($poststring);
  return $poststring;
}

sub generate_upsx_request {
  # features that need to be set
  # ups-shipnumber

  # these are created in the ups.com website
  my $pnp_accesslicense = "BC30509FB348FB38";
  my $pnp_upsuserid = "drewmtb";
  my $pnp_upspassword = "abcd1234";

  # validate important data for UPS here
  if (($payutils::query{'serviceLevelCode'} =~ /^(14|01|13|59|02|12|03)$/) && ($payutils::query{'country'} ne "US")) {
    # these service levels are only valid for US
    $payutils::error = 1;
    $payutils::color{'shipping'} = 'badcolor';
    $payutils::color{'country'} = 'badcolor';
    $payutils::error{'dataentry'} .= "Sorry, the shipping method selected is only valid for deliveries to the US.";
    $payutils::errvar .= "serviceLevelCode\|";
  }
  elsif (($payutils::query{'serviceLevelCode'} =~ /^(11|07|54|08|65)$/) && ($payutils::query{'country'} eq "US")) {
    # these service levels are only valid for international shipping
    $payutils::error = 1;
    $payutils::color{'shipping'} = 'badcolor';
    $payutils::color{'country'} = 'badcolor';
    $payutils::error{'dataentry'} .= "Sorry, the shipping method selected is not valid for deliveries to the US.";
    $payutils::errvar .= "serviceLevelCode\|";
  }

  if ($payutils::error == 1) {
    return;
  }

  my $result = "";

  my $xml_request = XML::Writer->new(OUTPUT => \$result, NEWLINES => 0);

  # start xml request
  $xml_request->xmlDecl();
  $xml_request->startTag("AccessRequest",
                         "xml:lang" => "en-US");
    $xml_request->startTag("AccessLicenseNumber");
    # this is pnps XML license number userid and password
    $xml_request->characters($pnp_accesslicense);
    $xml_request->endTag("AccessLicenseNumber");
    $xml_request->startTag("UserId");
    $xml_request->characters($pnp_upsuserid);
    $xml_request->endTag("UserId");
    $xml_request->startTag("Password");
    $xml_request->characters($pnp_upspassword);
    $xml_request->endTag("Password");
  $xml_request->endTag("AccessRequest");
  # close xml request
  $xml_request->end;

  $xml_request = XML::Writer->new(OUTPUT => \$result, NEWLINES => 0);
  # start xml request
  $xml_request->xmlDecl();
  $xml_request->startTag("RatingServiceSelectionRequest",
                         "xml:lang" => "en-US");

  $xml_request->startTag("Request");
    $xml_request->startTag("TransactionReference");
    $xml_request->endTag("TransactionReference");
    $xml_request->startTag("RequestAction");
    $xml_request->characters("Rate");
    $xml_request->endTag("RequestAction");
  $xml_request->endTag("Request");

  # ups-pickuptype can be invalid it will default to daily pickup
  # pickup is not required by UPS but does help rate calculation
  if ($payutils::query{'ups-pickuptype'} ne "") {
  $xml_request->startTag("Pickup");
    $xml_request->startTag("Code");
    $xml_request->characters($payutils::query{'ups-pickuptype'});
    $xml_request->endTag("Code");
#    $xml_request->startTag("Description");
#    $xml_request->characters("Rate");
#    $xml_request->endTag("Description");
  $xml_request->endTag("Pickup");
  }

  $xml_request->startTag("Shipment");
    $xml_request->startTag("Description");
    $xml_request->characters("Rate Description");
    $xml_request->endTag("Description");

  # ship from
    $xml_request->startTag("Shipper");
      if ($payutils::feature{'ups-shipnumber'} ne "") {
      # ship number is required to receive negotiated rates
      # DWW i doubt any of our merchants need this but it's here
      $xml_request->startTag("ShipperNumber");
      $xml_request->characters($payutils::feature{'ups-shipnumber'});  # ups account
      $xml_request->endTag("ShipperNumber");
      }
      $xml_request->startTag("Address");
        # merchant-city is required if country does not utilize postal codes
        # if merchant-city set do not send postal code
        if ($payutils::query{'merchant-city'} ne "") {
          $xml_request->startTag("City");
          $xml_request->characters($payutils::query{'merchant-city'});
          $xml_request->endTag("City");
        }
        else {
          $xml_request->startTag("PostalCode");
          $xml_request->characters($payutils::query{'merchant-zip'});
          $xml_request->endTag("PostalCode");
        }
        $xml_request->startTag("CountryCode");
        # country defaults to US if it's not sent
        if ($payutils::query{'merchant-country'} ne "") {
          $xml_request->characters($payutils::query{'merchant-country'});
        }
        else {
          $xml_request->characters("US");
        }
        $xml_request->endTag("CountryCode");
      $xml_request->endTag("Address");
    $xml_request->endTag("Shipper");

  # ship to
    $xml_request->startTag("ShipTo");
      $xml_request->startTag("Address");
        # city is required if country does not utilize postal codes
        $xml_request->startTag("City");
        $xml_request->characters($payutils::query{'city'});
        $xml_request->endTag("City");
        $xml_request->startTag("PostalCode");
        $xml_request->characters($payutils::query{'zip'});
        $xml_request->endTag("PostalCode");
        $xml_request->startTag("CountryCode");
        $xml_request->characters($payutils::query{'country'});
        $xml_request->endTag("CountryCode");
        if ($payutils::query{'ups-residential'} eq "true") {
        $xml_request->startTag("ResidentialAddressIndicator");
        $xml_request->characters("");
        $xml_request->endTag("ResidentialAddressIndicator");
        }
      $xml_request->endTag("Address");
    $xml_request->endTag("ShipTo");

    $xml_request->startTag("Service");
      $xml_request->startTag("Code");
      $xml_request->characters($payutils::query{'serviceLevelCode'});
      $xml_request->endTag("Code");
    $xml_request->endTag("Service");

    $xml_request->startTag("Package");
    $xml_request->startTag("PackagingType");
      $xml_request->startTag("Code");
      $xml_request->characters($payutils::query{'ups-container'});
      $xml_request->endTag("Code");
    $xml_request->endTag("PackagingType");

    $xml_request->startTag("PackageWeight");
      $xml_request->startTag("UnitOfMeasurement");
        $xml_request->startTag("Code");
          # default weight measurement is LBS merchant can set this
          # valid values LBS KGS
          if ($payutils::query{'ups-weightmeasurement'} eq "") {
            $xml_request->characters("LBS");
          }
          else {
            $xml_request->characters($payutils::query{'ups-weightmeasurement'});
          }
        $xml_request->endTag("Code");
      $xml_request->endTag("UnitOfMeasurement");
      $xml_request->startTag("Weight");
      # weight must be 6.1 format
      $xml_request->characters(sprintf("%.1f",$payutils::totalwgt));
      $xml_request->endTag("Weight");
    $xml_request->endTag("PackageWeight");
    $xml_request->endTag("Package");
    # if customer has checked insurance box we add it to the request
    if ($payutils::query{'ship-insurance'} eq "true") {
    $xml_request->startTag("InsuredValue");
      $xml_request->startTag("CurrencyCode");
        # use currency hash default to USD for US CAD for Canada
        if (($payutils::query{'currency'} eq "") && ($payutils::query{'merchant-country'} eq "CA")) {
          $xml_request->characters("CAD");
        }
        elsif ($payutils::query{'currency'} eq "") {
          $xml_request->characters("USD");
        }
        else {
          $xml_request->characters($payutils::query{'currency'});
        }
      $xml_request->endTag("CurrencyCode");
      $xml_request->startTag("MonetaryValue");
        $xml_request->characters($payutils::query{'total'});
      $xml_request->endTag("MonetaryValue");
    $xml_request->endTag("InsuredValue");
    } # end insured shipping if

  $xml_request->endTag("Shipment");
  $xml_request->endTag("RatingServiceSelectionRequest");
  # close xml request
  $xml_request->end;

  return $result;
}

sub generate_caps_request {
  my $output = "";

  # do some error checking first
  if (($payutils::query{'serviceLevelCode'} =~ /^(Priority Worldwide USA|Xpresspost USA|Expedited US Commercial|Expedited US Business)$/) && ($payutils::query{'country'} ne "US")) {
    # these service levels are only valid for US
    $payutils::error = 1;
    $payutils::color{'shipping'} = 'badcolor';
    $payutils::color{'country'} = 'badcolor';
    $payutils::error{'dataentry'} .= "Sorry, the shipping method selected is only valid for deliveries to the US.";
    $payutils::errvar .= "serviceLevelCode\|";
  }
  elsif (($payutils::query{'serviceLevelCode'} =~ /^(Priority International|Air Parcel|Xpresspost International|Parcel Surface)$/) && (($payutils::query{'country'} eq "CA") || ($payutils::query{'country'} eq "US"))) {
    # these service levels are not valid for CA or US
    $payutils::error = 1;
    $payutils::color{'shipping'} = 'badcolor';
    $payutils::color{'country'} = 'badcolor';
    $payutils::error{'dataentry'} .= "Sorry, the shipping method selected is not valid for Canada or the US.";
    $payutils::errvar .= "serviceLevelCode\|";
  }
  elsif (($payutils::query{'serviceLevelCode'} =~ /^(Parcel Courier|Xpresspost|Expedited|Regular)$/) && ($payutils::query{'country'} ne "CA")) {
    # these service levels are only valid for CA
    $payutils::error = 1;
    $payutils::color{'shipping'} = 'badcolor';
    $payutils::color{'country'} = 'badcolor';
    $payutils::error{'dataentry'} .= "Sorry, the shipping method selected only delivers to Canada.";
    $payutils::errvar .= "serviceLevelCode\|";
  }

  if ($payutils::error == 1) {
    return;
  }

  my $xml_request = XML::Writer->new(OUTPUT => \$output, NEWLINES => 0);

  $xml_request->xmlDecl();
  $xml_request->startTag('eparcel');

    $xml_request->startTag('language');
    $xml_request->characters($payutils::query{'capslanguage'});
    $xml_request->endTag('language');
    $xml_request->startTag('ratesAndServicesRequest');

      $xml_request->startTag('merchantCPCID');
      $xml_request->characters($payutils::query{'capsid'});  # username for merchant with caps
      $xml_request->endTag('merchantCPCID');

      $xml_request->startTag('fromPostalCode');
      $xml_request->characters($payutils::query{'merchant-zip'});  # merchant zip code
      $xml_request->endTag('fromPostalCode');

      if ($payutils::query{'capsinsurance'} eq "yes") {
      $xml_request->startTag('itemsPrice');
      $xml_request->characters($payutils::query{'subtotal'});  # value of item for insurance
      $xml_request->endTag('itemsPrice');
      }

      $xml_request->startTag('lineItems');
      # items go here
      for (my $pos=1;$pos<=$payutils::max;$pos++) {
        if ($payutils::query{"weight$pos"} > 0) {
        $xml_request->startTag('item');  # metric units please
          $xml_request->startTag('quantity');
          $xml_request->characters($payutils::query{"quantity$pos"});
          $xml_request->endTag('quantity');
          $xml_request->startTag('weight');
          $xml_request->characters($payutils::query{"weight$pos"});
          $xml_request->endTag('weight');
          $xml_request->startTag('length');
          $xml_request->characters($payutils::query{"length$pos"});
          $xml_request->endTag('length');
          $xml_request->startTag('width');
          $xml_request->characters($payutils::query{"width$pos"});
          $xml_request->endTag('width');
          $xml_request->startTag('height');
          $xml_request->characters($payutils::query{"height$pos"});
          $xml_request->endTag('height');
          $xml_request->startTag('description');
          $xml_request->characters($payutils::query{"description$pos"});
          $xml_request->endTag('description');

        # ready to ship flag if being shipped one item at time
        if ($payutils::query{"readyToShip$pos"} eq "yes") {
        $xml_request->startTag('readyToShip');
        $xml_request->endTag('readyToShip');
        }

        $xml_request->endTag('item');
        } # end weight if
      }
      $xml_request->endTag('lineItems');

      $xml_request->startTag('city');
      $xml_request->characters($payutils::query{'card-city'});  # city where parcel will be shipped to
      $xml_request->endTag('city');

      $xml_request->startTag('provOrState');
      if ($payutils::query{'card-prov'} ne "") {
        $xml_request->characters($payutils::query{'card-prov'});  # province or state
      }
      else {
        $xml_request->characters($payutils::query{'card-state'});  # province or state
      }
      $xml_request->endTag('provOrState');

      $xml_request->startTag('country');
      $xml_request->characters($payutils::query{'card-country'});  # country where parcel will be shipped to
      $xml_request->endTag('country');

      $xml_request->startTag('postalCode');
      $xml_request->characters($payutils::query{'card-zip'});  # postal code where parcel will be shipped to
      $xml_request->endTag('postalCode');

    $xml_request->endTag('ratesAndServicesRequest');
  $xml_request->endTag('eparcel');
  $xml_request->end;

  return $output;
}

sub generate_usps_request {
  require POSIX;
  # string ref for xml doc
  my $result = "";
  # final return string
  my $poststring = "";

  # our username and password to use USPS calculator DO NOT GIVE OUT
  my $usps_username = "301PLUGN3455";
  my $usps_password = "040UC33OC467";

  $payutils::query{'pounds'} = int($payutils::totalwgt);
  # always round ounces up this way we overcharge slightly :)
  $payutils::query{'ounces'} = &POSIX::ceil(16 * ($payutils::totalwgt - $payutils::query{'pounds'}));

  my $xml_request = XML::Writer->new(OUTPUT => \$result, NEWLINES => 0);

  # start xml request
  $xml_request->xmlDecl();
  if ($payutils::query{'country'} eq "US") {
    $xml_request->startTag("RateV4Request",
                           "USERID" => $usps_username,
                           "PASSWORD" => $usps_password);
  } else {
    $xml_request->startTag("IntlRateV2Request",
                           "USERID" => $usps_username,
                           "PASSWORD" => $usps_password);
  }

  $xml_request->startTag("Revision");
  $xml_request->characters("2");
  $xml_request->endTag("Revision");


  # start of package
  $xml_request->startTag("Package", "ID"=>"1");

  if ($payutils::query{'country'} eq "US") {
    # valid service settings
    # FIRST CLASS, FIRST CLASS COMMERCIAL, FIRST CLASS HFP COMMERCIAL, PRIORITY, PRIORITY COMMERCIAL
    # PRIORITY HFP COMMERCIAL, EXPRESS, EXPRESS COMMERCIAL, EXPRESS SH, EXPRESS SH COMMERCIAL
    # EXPRESS HFP, EXPRESS HFP COMMERCIAL, PARCEL, MEDIA, LIBRARY, ALL, ONLINE
    $xml_request->startTag("Service");
    $xml_request->characters($payutils::query{'serviceLevelCode'});
    $xml_request->endTag("Service");
    # zip codes must be 5 digits and valid
    my $tempzip = $payutils::query{'merchant-zip'};
    $tempzip =~ s/[^0-9]//g;
    $tempzip = substr($tempzip,0,5);
    $xml_request->startTag("ZipOrigination");
    $xml_request->characters($tempzip);
    $xml_request->endTag("ZipOrigination");
    $tempzip = $payutils::query{'zip'};
    $tempzip =~ s/[^0-9]//g;
    $tempzip = substr($tempzip,0,5);
    $xml_request->startTag("ZipDestination");
    $xml_request->characters($tempzip);
    $xml_request->endTag("ZipDestination");
  }

  # pounds 0 min 70 max
  $xml_request->startTag("Pounds");
  $xml_request->characters($payutils::query{'pounds'});
  $xml_request->endTag("Pounds");
  # ounces min 0.0 max 1120.0 max length 10 digits
  $xml_request->startTag("Ounces");
  $xml_request->characters($payutils::query{'ounces'});
  $xml_request->endTag("Ounces");

  if ($payutils::query{'country'} eq "US") {
    # valid containers
    # VARIABLE, FLAT RATE ENVELOPE, PADDED FLAT RATE ENVELOPE, LEGAL FLAT RATE ENVELOPE
    # SM FLAT RATE ENVELOPE, WINDOW FLAT RATE ENVELOPE, GIFT CARD FLAT RATE ENVELOPE
    # FLAT RATE BOX, SM FLAT RATE BOX, MD FLAT RATE BOX, LG FLAT RATE BOX
    # REGIONALRATEBOXA, REGIONALRATEBOXB, REGIONALRATEBOXC, RECTANGULAR, NONRECTANGULAR
    # Note: RECTANGULAR or NONRECTANGULAR must be indicated when <Size>LARGE</Size>.
    $xml_request->startTag("Container");
    if ($payutils::query{'usps-container'} eq "NONE") {
      $xml_request->characters("VARIABLE");
    }
    else {
      $xml_request->characters($payutils::query{'usps-container'});
    }
    $xml_request->endTag("Container");
    # valid sizes
    # LARGE, REGULAR
    # required
    $xml_request->startTag("Size");
    $xml_request->characters($payutils::query{'usps-size'});
    $xml_request->endTag("Size");
  }

  # valid values true, false, collapse
  # required
  # default to false
  $xml_request->startTag("Machinable");
  if ($payutils::query{'machinable'} ne "") {
    $xml_request->characters($payutils::query{'machinable'});
  }
  else {
    $xml_request->characters("false");
  }
  $xml_request->endTag("Machinable");

  if ($payutils::query{'country'} ne "US") {
    # valid values All, Package, Postcards or aerogrammes, Envelope, LargeEnvelope, FlatRate
    # required
    $xml_request->startTag("MailType");
    if ($payutils::query{'mailtype'} =~ /^All|Package|Envelope|LargeEnvelope|FlatRate$/) {
      $xml_request->characters($payutils::query{'mailtype'});
    }
    else {
      $xml_request->characters("Package");
    }
    $xml_request->endTag("MailType");

    # required but not used
    # only in dollars
    $xml_request->startTag("ValueOfContents");
    $xml_request->characters($payutils::query{'total'});
    $xml_request->endTag("ValueOfContents");

    $xml_request->startTag("Country");
    my $countrytext = "";
    if ($payutils::query{'country'} =~ /^GB$/) {
      # this is a fix for USPS stupidity
      $countrytext = "Great Britain and Northern Ireland";
    }
    else {
      $countrytext = $constants::countries{$payutils::query{'country'}};
    }
    $xml_request->characters($countrytext);
    $xml_request->endTag("Country");

    # valid settings RECTANGULAR NONRECTANGULAR
    # doesn't make much of a difference just default it
    # required
    $xml_request->startTag("Container");
    $xml_request->characters("RECTANGULAR");
    $xml_request->endTag("Container");

    # valid values REGULAR LARGE
    # default to REGULAR
    # required
    $xml_request->startTag("Size");
    if (($payutils::query{'usps-size'} eq "REGULAR") || ($payutils::query{'usps-size'} eq "LARGE")) {
      $xml_request->characters($payutils::query{'usps-size'});
    }
    else {
      $xml_request->characters("REGULAR");
    }
    $xml_request->endTag("Size");

    # dimension fields are required we just default them
    $xml_request->startTag("Width");
    $xml_request->characters("0");
    $xml_request->endTag("Width");

    $xml_request->startTag("Length");
    $xml_request->characters("0");
    $xml_request->endTag("Length");

    $xml_request->startTag("Height");
    $xml_request->characters("0");
    $xml_request->endTag("Height");

    $xml_request->startTag("Girth");
    $xml_request->characters("0");
    $xml_request->endTag("Girth");
  }

  $xml_request->endTag("Package");
  # end of package

  if ($payutils::query{'country'} eq "US") {
    $xml_request->endTag("RateV4Request");
  } else {
    $xml_request->endTag("IntlRateV2Request");
  }

  $xml_request->end;
  if ($payutils::query{'country'} eq "US") {
    $poststring = "API=RateV4\&XML=" . $result;
  } else {
    $poststring = "API=IntlRateV2\&XML=" . $result;
  }

  return $poststring;
}

sub exp_billing {
  my $output = '';

  $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-name'}\">Name:<b>*</b></td>";
  $output .= "<td align=\"left\"><input type=\"text\" name=\"card-name\" size=\"30\" value=\"$payutils::query{'card-name'}\" maxlength=\"39\"></td></tr>\n";

  if ($payutils::query{'showcompany'} eq "yes") {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-company'}\">Company:$payutils::requiredstar{'card-company'}</td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"card-company\" size=\"30\" value=\"$payutils::query{'card-company'}\" maxlength=\"39\"></td></tr>\n";
  }

  $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-address1'}\">Billing Address:<b>*</b></td>";
  $output .= "<td align=\"left\"><input type=\"text\" name=\"card-address1\" size=\"30\" value=\"$payutils::query{'card-address1'}\" maxlength=\"39\"></td></tr>\n";

  $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-address2'}\">Line 2: </td>\n";
  $output .= "<td align=left><input type=\"text\" name=\"card-address2\" size=\"30\" value=\"$payutils::query{'card-address2'}\" maxlength=\"39\"></td></tr>\n";

  $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-city'}\">City:<b>*</b></td>";
  $output .= "<td align=\"left\"><input type=\"text\" name=\"card-city\" size=\"20\" value=\"$payutils::query{'card-city'}\" maxlength=\"30\"></td></tr>\n";

  if ($payutils::query{'nostatelist'} ne "yes") {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-state'}\">State/Province:<b>*</b></td>";
    $output .= "<td align=\"left\"><select name=\"card-state\">\n";

    my %selected = ();
    $selected{$payutils::query{'card-state'}} = " selected";
    $output .= "<option value=\"\">Select Your State/Province/Territory</option>\n";
    foreach my $key (&sort_hash(\%constants::USstates)) {
      $output .= "<option value=\"$key\"$selected{$key}>$constants::USstates{$key}</option>\n";
    }
    if ($payutils::usterrflag ne "no") {
      foreach my $key (sort keys %constants::USterritories) {
        $output .= "<option value=\"$key\"$selected{$key}>$constants::USterritories{$key}</option>\n";
      }
    }
    if (($payutils::usonly ne "yes") && ($payutils::uscanonly ne "yes")) {
      foreach my $key (sort keys %constants::CNprovinces) {
        $output .= "<option value=\"$key\"$selected{$key}>$constants::CNprovinces{$key}</option>\n";
      }
    }
    if ($payutils::uscanonly eq "yes") {
      foreach my $key (sort keys %constants::USCNprov) {
        $output .= "<option value=\"$key\"$selected{$key}>$constants::USCNprov{$key}</option>\n";
      }
    }
    $output .= "</select></td></tr>\n";
  }
  else {
    $output .= "<tr><td ALIGN=\"right\" class=\"$payutils::color{'card-state'}\">State/Province:$payutils::requiredstar{'card-state'}</td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"card-state\" size=\"20\" value=\"$payutils::query{'card-state'}\" maxlength=\"19\"></td></tr>\n";
  }
  if (($payutils::usonly ne "yes") && ($payutils::uscanonly ne "yes"))  {
    $output .= "<tr><td ALIGN=\"right\" class=\"$payutils::color{'card-prov'}\">International Province: </td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"card-prov\" size=\"20\" value=\"$payutils::query{'card-prov'}\" maxlength=\"19\"></td></tr>\n";
  }

  $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-zip'}\">Zip/Postal Code:$payutils::requiredstar{'card-zip'}</td>";
  $output .= "<td align=\"left\"><input type=\"text\" name=\"card-zip\" size=\"10\" value=\"$payutils::query{'card-zip'}\" maxlength=\"10\"></td></tr>\n";

  if ($payutils::query{'nocountrylist'} ne "yes") {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-country'}\">Country\:$payutils::requiredstar{'card-country'}</td>";
    $output .= "<td align=left><select name=\"card-country\">\n";

    my %selected = ();
    $selected{$payutils::query{'card-country'}} = " selected";
    if ($payutils::usonly eq "yes") {
      $output .= "<option value=\"US\" selected>$constants::countries{'US'}</option>\n";
    }
    elsif ($payutils::uscanonly eq "yes") {
      $output .= "<option value=\"US\"$selected{'US'}>$constants::countries{'US'}</option>\n";
      $output .= "<option value=\"CA\"$selected{'CA'}>$constants::countries{'CA'}</option>\n";
    }
    else {
      my %selected = ();
      $selected{$payutils::query{'card-country'}} = " selected";
      foreach my $key (&sort_hash(\%constants::countries)) {
        $output .= "<option value=\"$key\"$selected{$key}>$constants::countries{$key}</option>\n";
      }
    }
    $output .= "</select></td></tr>\n";
  }
  else {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-country'}\">Country\:$payutils::requiredstar{'card-country'}</td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"card-country\" size=\"15\" value=\"$payutils::query{'card-country'}\" maxlength=\"20\"></td></tr>\n";
  }

  $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-type'}\">Card Type:<b>*</b></td>";
  $output .= "<td align=\"left\">";

  $output .= "<table border=\"0\" cellspacing=\"0\" cellpadding=\"2\">\n";
  $output .= "  <tr>\n";

  my $colcnt = 0;
  for (my $i = 0; $i <= $#payutils::card_list; $i++) {
    my $key = $payutils::card_list[$i];

    if ($payutils::query{'card-allowed'} =~ /$key/i) {
      if (($payutils::feature{'dispcardmodulo'} > 0) && ($colcnt % $payutils::feature{'dispcardmodulo'} == 0)) {
        $output .= "  </tr>\n";
        $output .= "  <tr>\n";
      }
      elsif ( (($colcnt % 3 == 0) && ($payutils::feature{'dispcardlogo'} == 1)) ||
           (($colcnt % 4 == 0) && ($payutils::feature{'dispcardlogo'} != 1)) ) {
        $output .= "  </tr>\n";
        $output .= "  <tr>\n";
      }

      my $checked = "";
      if ($payutils::color{'card-type'} =~ /$payutils::card_hash{$key}[0]/i) { $checked = " checked"; }

      $output .= "    <td><nobr><input type=\"radio\" name=\"card-type\" value=\"$payutils::card_hash{$key}[0]\"$checked> <span style=\"color: $payutils::goodcolor\">";
      if ($payutils::feature{'dispcardlogo'} == 1) {
        if ($payutils::card_hash{$key}[2] ne "") {
          $output .= "<img src=\"$payutils::card_hash{$key}[2]\" title=\"$payutils::card_hash{$key}[1]\" alt=\"$payutils::card_hash{$key}[1]\">";
        }
        else {
          $output .= "$payutils::card_hash{$key}[1]";
        }
      }
      else {
        $output .= "$payutils::card_hash{$key}[1]";
      }
      $output .= "</span></nobr></td>\n";

      $colcnt = $colcnt + 1;
    }
  }

  $output .= "  </tr>\n";
  $output .= "</table>\n";

  $output .= "</td></tr>\n";

  $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-number'}\">Credit Card \#:<b>*</b></td>";
  $output .= "<td align=\"left\"><input type=\"text\" name=\"card-number\" value=\"$payutils::query{'card-number'}\" size=\"16\" maxlength=\"20\" autocomplete=\"off\"></td></tr>\n";
  if (($payutils::feature{'cvv'} == 1) || ($payutils::query{'cvv-flag'} eq "yes")) {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-cvv'}\">Credit Card CVV/CVC:<b>*</b></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"card-cvv\" value=\"$payutils::query{'card-cvv'}\" size=\"4\" maxlength=\"4\" autocomplete=\"off\"> Required for Visa/Mastercard. <a href=\"help.cgi?subject=cvv\" target=\"help\" onClick=\"online_help(300,500)\;\"><font size=\"-2\" color=\"$payutils::goodcolor\"><b>Click Here For Help</b></font></a> </td></tr>\n";
  }

  $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-exp'}\">Exp. Date:<b>*</b></td> ";
  $output .= "<td align=\"left\">\n";
if ($payutils::query{'nocardexplist'} ne "yes") {
  $output .= "<select name=\"month-exp\">\n";
  my @months = ("01","02","03","04","05","06","07","08","09","10","11","12");
  my ($date) = &miscutils::gendatetime_only();
  my $current_month = substr($date,4,2);
  my $current_year = substr($date,0,4);
  if ($payutils::query{'month-exp'} eq "") {
    $payutils::query{'month-exp'} = $current_month;
  }
  foreach my $var (@months) {
    if ($var eq $payutils::query{'month-exp'}) {
      $output .= "<option value=\"$var\" selected>$var</option>\n";
    }
    else {
      $output .= "<option value=\"$var\">$var</option>\n";
    }
  }
  $output .= "</select> ";

  $output .= "<select name=\"year-exp\">\n";

  #my @years = ("2002","2003","2004","2005","2006","2007","2008","2009","2010","2011","2012","2013");
  if ($payutils::query{'year-exp'} eq ""){
    $payutils::query{'year-exp'} = "03";
  }
  for (my $i; $i<=12; $i++) {
    my $var = $current_year + $i;
  #foreach my $var (@years) {
    my $val = substr($var,2,2);
    if ($val eq $payutils::query{'year-exp'}) {
      $output .= "<option value=\"$val\" selected>$var</option>\n";
    }
    else {
      $output .= "<option value=\"$val\">$var</option>\n";
    }
  }
  $output .= "</select>\n";
}
else {
  $output .= "<input type=\"text\" name=\"month-exp\" value=\"$payutils::query{'month-exp'}\" size=\"2\" maxlength=\"2\" autocomplete=\"off\"> / <input type=\"text\" name=\"year-exp\" value=\"$payutils::query{'year-exp'}\" size=\"2\" maxlength=\"2\" autocomplete=\"off\"> MM/YY\n";
}
  $output .= "</td></tr>\n";

  $output .= "<tr><td align=\"right\" class=\"$payutils::color{'email'}\">Email Address:<b>*</b></td>";
  $output .= "<td align=\"left\"><input type=\"text\" name=\"email\" value=\"$payutils::query{'email'}\" size=\"30\" maxlength=\"49\"></td></tr>\n";

  # 02/16/06 - added ability to use 'nophone' from features
  if (($payutils::feature{'nophone'} != 1) && ($payutils::nophone ne "yes")) {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'phone'}\">Day Phone \#:$payutils::requiredstar{'phone'}</td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"phone\" value=\"$payutils::query{'phone'}\" size=\"15\" maxlength=\"15\"></td></tr>\n";

    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'fax'}\">Night Phone/FAX \#:$payutils::requiredstar{'fax'}</td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"fax\" value=\"$payutils::query{'fax'}\" size=\"15\" maxlength=\"15\"></td></tr>\n";
  }

  return $output;
}


sub shipping_calc {
  my ($pagecontent);

  # URLS FOR UPS
  my $ups_url = "http://www.ups.com/using/services/rave/qcost_dss.cgi";
  my $ups_host = "www.ups.com";
  my $ups_path = "/using/services/rave/qcost_dss.cgi";

  # URLS for UPSX UPS XML
  # https://wwwcie.ups.com/ups.app/xml/Rate is the testing url
  #my $upsx_url = "https://wwwcie.ups.com/ups.app/xml/Rate";
  my $upsx_url = "https://www.ups.com/ups.app/xml/Rate";
  # https://www.ups.com/ups.app/xml/Rate is the production url
  # my $upsx_url = "https://www.ups.com/ups.app/xml/Rate";

  # These are the USPS testing URLS they only work with canned tests
  #  my $usps_url = "http://testing.shippingapis.com/ShippingAPITest.dll";
  #  my $usps_host = "testing.shippingapis.com";
  #  my $usps_path = "/ShippingAPITest.dll";
  # URLS FOR USPS
  my $usps_url = "http://Production.ShippingAPIs.com/ShippingAPI.dll";
  my $usps_host = "Production.ShippingAPIs.com";
  my $usps_path = "/ShippingAPI.dll";

  # vars URLS for Canada Post
  my $caps_url = "http://sellonline.canadapost.ca:30000";

  # init a bunch of vars to make sure we don't get stomped on
  my $ship_type_flag = "";
  my $ship_post_string = "";
  my $host = "";
  my $path = "";
  my $url = "";

  if (($payutils::query{'shipmethod'} eq "") || ($payutils::error > 0)) {
    return;
  }
  elsif ($payutils::query{'shipmethod'} =~ /^pnp_/i) {
    $payutils::query{'shipping'} = &pnp_ship_calc();
    return;
  }

  if ($payutils::totalwgt <= 0) {
    # if weight is 0, return without calculating
    $payutils::query{'SHIPCALC_WARNING'} = "\n\n\n\n******SHIPPING WAS NOT CALCULATED FOR THIS ORDER******* \n\n Total Weight Not Specified.\n\n\n\n";
    return;
  }

  if ($payutils::query{'serviceLevelCode'} =~ /ALL|DOM|CAN|INT|1DM|1DMRS|1DA|1DARS|1DP|1DPRS|2DM|2DMRS|2DA|2DARS|3DS|3DSRS|GND|GNDRES|STD|CXR|CXP|CXD|XPR|XDM|XPD/) {
    $ship_type_flag = "UPS";
    $url = $ups_url;
    $ship_post_string = &generate_ups_request();
    $host = $ups_host;
    $path = $ups_path;
  }
  elsif ($payutils::query{'serviceLevelCode'} =~ /^(14|01|13|59|02|12|03|11|07|54|08|65)$/) {
    if ($payutils::totalwgt <= 0) {
      # if weight is 0 return without calculating
      return;
    }
    $ship_type_flag = "UPSX";
    $url = $upsx_url;
    $ship_post_string = &generate_upsx_request();
  }
  elsif ($payutils::query{'serviceLevelCode'} =~ /Priority Courier|Xpresspost|Expedited|Regular|Priority International|Air Parcel|Xpresspost USA|Expedited US Commercial|Xpresspost International|Parcel Surface|Small Packets Surface/) {
    if ($payutils::totalwgt <= 0) {
      # if weight is 0 return without calculating
      return;
    }
    $ship_type_flag = "CAPS";
    $url = $caps_url;
    $ship_post_string = &generate_caps_request();
    if ($payutils::error == 1) {
      return;
    }
  }
  elsif ($payutils::query{'serviceLevelCode'} =~ /Express|Priority|Parcel/) {
    $ship_type_flag = "USPS";
    $url = $usps_url;
    $ship_post_string = &generate_usps_request();
    $host = $usps_host;
    $path = $usps_path;
  }
  elsif (($payutils::query{'serviceLevelCode'} eq "NONE") && ($payutils::totalwgt > 0)) {
    $payutils::error = 1;
    $payutils::color{'shipping'} = 'badcolor';
    $payutils::errvar .= "servicelevelcode";
    $payutils::error{'dataentry'} .= "Please select a Shipping Method.";
  }


  if ($ship_type_flag eq "UPS") {
    $pagecontent = &miscutils::formpostUPS($url,$ship_post_string,$host,$path);
  }
  elsif ($ship_type_flag eq "USPS") {
    $pagecontent = &miscutils::formpostUSPS($url,$ship_post_string,$host,$path);
  }
  elsif (($ship_type_flag eq "CAPS") || ($ship_type_flag eq "UPSX")) {
    $pagecontent = &miscutils::formpostUPS($url,$ship_post_string);
  }

  if ($ship_type_flag eq "UPS") {
    my @contentlines = split(/\n+/,$pagecontent);
    foreach my $shipvalue (@contentlines) {
      if ($shipvalue =~ /UPSOnLine/) {
        chop $shipvalue;
        my @shiparray = split(/\%/,$shipvalue);
        if ($shiparray[3] =~ /Success/) {
          $payutils::query{'ship-type'} = $shiparray[5];
          $payutils::query{'shipping'} = $shiparray[12];
        }
        elsif ($shiparray[3] =~ /Invalid ShipperPostalCode/) {
          $payutils::error = 1;
          $payutils::color{'shipping'} = 'badcolor';
          $payutils::errvar .= "upsshipping\|";
          $payutils::error_string = $payutils::error_string . "Merchant needs to fix shipper postal code.";
          $payutils::error{'dataentry'} .= "Merchant needs to fix shipper postal code.";
          $payutils::query{'MErrMsg'} = "Merchant needs to fix shipper postal code.";
        }
        elsif ($shiparray[3] =~ /Invalid ConsigneePostalCode/) {
          $payutils::error = 1;
          $payutils::color{'shipping'} = 'badcolor';
          $payutils::color{'zip'} = 'badcolor';
          $payutils::errvar .= "upsshipping\|";
          $payutils::error_string = $payutils::error_string . "Zip code is not valid";
          $payutils::error{'dataentry'} .= "Zip code is not valid";
          $payutils::query{'MErrMsg'} = "Zip code is not valid";
        }
        elsif ($shiparray[3] =~ /unknown country/) {
          $payutils::error = 1;
          $payutils::color{'shipping'} = 'badcolor';
          $payutils::color{'country'} = 'badcolor';
          $payutils::errvar .= "upsshipping\|";
          $payutils::error_string = $payutils::error_string . "Country not supported for UPS delivery";
          $payutils::error{'dataentry'} .= "Country not supported for UPS delivery";
          $payutils::query{'MErrMsg'} = "Country not supported for UPS delivery";
        }
        elsif ($shiparray[3] =~ /Packages must weigh more than zero pounds/) {
          $payutils::error = 1;
          $payutils::color{'shipping'} = 'badcolor';
          $payutils::errvar .= "upsshipping\|";
          $payutils::error_string = $payutils::error_string . "Package has zero weight";
          $payutils::error{'dataentry'} .= "Package has zero weight";
          $payutils::query{'MErrMsg'} = "Package has zero weight";
        }
        elsif ($shiparray[3] =~ /The selected service is invalid for the US48 Origin site/) {
          $payutils::error = 1;
          $payutils::color{'shipping'} = 'badcolor';
          $payutils::errvar .= "upsshipping\|";
          $payutils::error_string = $payutils::error_string . "Invalid service selected";
          $payutils::error{'dataentry'} .= "A Shipping Method must be selected.";
          $payutils::query{'MErrMsg'} = "You must select a Shipping Method.";
        }
        elsif ($shiparray[3] =~ /Input RateChart field is invalid/) {
          $payutils::error = 1;
          $payutils::color{'shipping'} = 'badcolor';
          $payutils::errvar .= "upsshipping\|";
          $payutils::error_string = $payutils::error_string . "Invalid rate chart selected";
          $payutils::error{'dataentry'} .= "Invalid rate chart selected";
          $payutils::query{'MErrMsg'} = "Invalid rate chart selected";
        }
        elsif ($shiparray[3] =~/Ground Residential service is unavailable from/) {
          $payutils::error = 1;
          $payutils::color{'shipping'} = 'badcolor';
          $payutils::color{'zip'} = 'badcolor';
          $payutils::errvar .= "upsshipping\|";
          $payutils::error_string = $payutils::error_string . "UPS does not ship to this Zip Code";
          $payutils::error{'dataentry'} .= "UPS does not ship to this Zip Code";
          $payutils::query{'MErrMsg'} = "UPS does not ship to this Zip Code";
        }
      }
    }
  }
  elsif ($ship_type_flag eq "UPSX") {
    my $parser = XML::Simple->new();
    my $doc = $parser->XMLin($pagecontent,  forcearray => 0, keyattr => []);

    # response is succesful process it
    if ($doc->{Response}->{ResponseStatusCode} == 1) {
      $payutils::query{'shipping'} = $doc->{RatedShipment}->{TotalCharges}->{MonetaryValue};
    }
    else {
      # handle problem responses here
      $payutils::query{'UPS_ErrorSeverity'} = $doc->{Response}->{Error}->{ErrorSeverity};
      $payutils::query{'UPS_ErrorCode'} = $doc->{Response}->{Error}->{ErrorCode};
      $payutils::query{'UPS_ErrorDescription'} = $doc->{Response}->{Error}->{ErrorDescription};
      $payutils::query{'UPS_ResponseStatusCode'} = $doc->{Response}->{ResponseStatusCode};
      $payutils::query{'UPS_WARNING'} = "\n\n*****SHIPPING WAS NOT CALCULATED FOR THIS ORDER*****\n\n " . $doc->{Response}->{Error}->{ErrorDescription} . "\n\n";
    }
  }
  elsif ($ship_type_flag eq "USPS") {
    my $parser = XML::Simple->new();
    my $doc = $parser->XMLin($pagecontent,  forcearray => 0, keyattr => []);

    # response is succesful process it
    if (!defined $doc->{Error}) {
        if ($payutils::query{'country'} eq "US") {
          # get US response
          $payutils::query{'shipping'} = $doc->{Package}->{Postage}->{Rate};
        }
        else {
          # get Intl response
          # because USPS is stupid we have to do a loop through this junk
          my $services = $doc->{Package}->{Service};
          foreach my $service (@{$services}) {
            # filter out the stuff that makes selecting shipping a pain
            # $service->{SvcDescription} =~ s/\&lt\;sup\&gt\;\&amp\;reg\;\&lt\;\/sup\&gt\;//g;
            $service->{SvcDescription} =~ s/\&lt;sup\&gt;\&#8482;\&lt;\/sup\&gt;//g;
            $service->{SvcDescription} =~ s/\&lt;sup\&gt;\&#174;\&lt;\/sup\&gt;//g;
            $service->{SvcDescription} =~ s/\*//g;
            if ($service->{SvcDescription} eq $payutils::query{'usps_international_rate_type'}) {
              $payutils::query{'shipping'} = $service->{Postage};
              $payutils::query{'USPS_Service'} = $service->{SvcDescription};
            }
          }
          # if shipping wasn't picked properly just pick the lowest one
          #if ($payutils::query{'shipping'} eq "") {
          if (($payutils::query{'shipping'} eq "") || ($payutils::query{'shipping'} == 0)) {
            foreach my $service (@{$services}) {
              #if ($payutils::query{'shipping'} eq "") {
              if (($payutils::query{'shipping'} eq "") || ($payutils::query{'shipping'} == 0)) {
                $payutils::query{'shipping'} = $service->{Postage};
                $payutils::query{'USPS_Service'} = $service->{SvcDescription};
              }
              if ($payutils::query{'shipping'} > $service->{Postage}) {
                $payutils::query{'shipping'} = $service->{Postage};
                $payutils::query{'USPS_Service'} = $service->{SvcDescription};
              }
            }
          }
        }
    }
    else {
      # handle problem responses here
      $payutils::query{'USPS_ErrorNumber'} = $doc->{Error}->{Number};
      $payutils::query{'USPS_ErrorDescription'} = $doc->{Error}->{Description};
      $payutils::query{'USPS_WARNING'} = "\n\n*****SHIPPING WAS NOT CALCULATED FOR THIS ORDER*****\n\n " . $doc->{Error}->{Description} . "\n\n";
    }
  }
  elsif ($ship_type_flag eq "CAPS") {
    my $parser = XML::Simple->new();
    my $xmldoc = $parser->XMLin($pagecontent,  forcearray => 0, keyattr => []);

    # good response of 1 or 2
    if ($xmldoc->{ratesAndServicesResponse}->{statusCode} > 0) {
      $payutils::query{'CAPS_statusCode'} = $xmldoc->{'ratesAndServicesResponse'}->{'statusCode'};
      $payutils::query{'CAPS_requestID'} = $xmldoc->{'ratesAndServicesResponse'}->{'requestID'};
      $payutils::query{'CAPS_handling'} = $xmldoc->{'ratesAndServicesResponse'}->{'handling'};
      $payutils::query{'CAPS_statusMessage'} = $xmldoc->{ratesAndServicesResponse}->{'statusMessage'};

      if (defined $xmldoc->{'ratesAndServicesResponse'}->{'product'}) {
        foreach my $key (keys %{$xmldoc->{'ratesAndServicesResponse'}->{'product'}}) {
          # pick out the rate and add it to shipping
          if ($key eq $payutils::query{'serviceLevelCode'}) {
            $payutils::query{'shipping'} = $xmldoc->{'ratesAndServicesResponse'}->{'product'}->{$key}->{'rate'};
          }
          foreach my $field (keys %{$xmldoc->{'ratesAndServicesResponse'}->{'product'}->{$key}}) {
            $payutils::query{"CAPS_$key"} .= "'" . $field . "','". $xmldoc->{'ratesAndServicesResponse'}->{'product'}->{$key}->{$field} . "',";
          }
          chop $payutils::query{"CAPS_$key"};
        }
      } # end defined product if

     if (defined $xmldoc->{'ratesAndServicesResponse'}->{'packing'}->{'box'}) {
        my $box_id = $xmldoc->{'ratesAndServicesResponse'}->{'packing'}->{'packingID'};
        foreach my $key (keys %{$xmldoc->{'ratesAndServicesResponse'}->{'packing'}->{'box'}}) {
          if (! scalar keys %{$xmldoc->{'ratesAndServicesResponse'}->{'packing'}->{'box'}->{$key}}) {
            $payutils::query{"CAPS_package_$box_id"} .= "'" . $key . "','" . $xmldoc->{'ratesAndServicesResponse'}->{'packing'}->{'box'}->{$key} . "',";
          }
          else {
            foreach my $field (keys %{$xmldoc->{'ratesAndServicesResponse'}->{'packing'}->{'box'}->{$key}}) {
              $payutils::query{"CAPS_package_$box_id"} .= "'" . $field . "','" . $xmldoc->{'ratesAndServicesResponse'}->{'packing'}->{'box'}->{$key}->{$field} . "',";
            }
          }
        }
        chop $payutils::query{"CAPS_package_$box_id"};
      }
    }
    else {
      # handle bad response
      $payutils::query{'CAPS_statusCode'} = $xmldoc->{'error'}->{'statusCode'};
      $payutils::query{'CAPS_requestID'} = $xmldoc->{'error'}->{'requestID'};
      $payutils::query{'CAPS_statusMessage'} = $xmldoc->{'error'}->{'statusMessage'};
      $payutils::query{'CAPS_WARNING'} = "\n\n*****SHIPPING WAS NOT CALCULATED FOR THIS ORDER*****\n\n";
    }
  } # end of parsing canada post response page

  # set query ship-service
  # set this to return more readable shipping service info.
  $payutils::query{'ship-service'} = $payutils::Ship_Methods{$payutils::query{'serviceLevelCode'}};
}

sub pnp_ship_calc {

  my ($cntry_list,$shipping,$ruletype,$where,$cntry,$state,$shiprules,$display,$details,$origshipamt,@rules);

  my $all_state_list = "AL|AK|AZ|AR|AA|AE|AP|CA|CO|CT|DE|DC|FL|GA|HI|ID|IL|IN|IA|KS|KY|LA|ME|MD|MA|MI|MN|MS|MO|MT|NE|NV|NH|NJ|NM|NY|NC|ND|OH|OK|OR|PA|PR|RI|SC|SD|TN|TX|UT|VT|VI|VA|WA|WV|WI|WY";
  my $cont_only_state_list = "AL|AZ|AR|CA|CO|CT|DE|DC|FL|GA|ID|IL|IN|IA|KS|KY|LA|ME|MD|MA|MI|MN|MS|MO|MT|NE|NV|NH|NJ|NM|NY|NC|ND|OH|OK|OR|PA|PR|RI|SC|SD|TN|TX|UT|VT|VI|VA|WA|WV|WI|WY";

  foreach my $key (keys %constants::countries) {
    if ($key ne "") {
      $cntry_list .= "$key|";
    }
  }
  chop $cntry_list;

  my (%shiprules,@shiprules);
  $shiprules{'ihashacomm'} = "amount,all:all,9.99|5.85|29.99|7.85|49.99|9.85|69.99|11.85|149.99|13.85|or|0.00";
  $shiprules{'thumbprint'} = "amount,all:all,48.00|4.95|75.00|6.95|120.00|7.95|160.00|9.95|200.00|12.95|300.00|14.95|or|16.95";
  $shiprules{'outwestmer'} = "amount,all:all,199.00|10.95|399.00|19.95|or|24.95";
  $shiprules{'pnpdemo'} = "amount,all:all,48.00|4.95|75.00|6.95|120.00|7.95|160.00|9.95|200.00|12.95|300.00|14.95|or|16.95";

  if ($payutils::query{'shipcalced'} != 1) {
    $origshipamt = $payutils::query{'shipping'};
  }
  my $dbh = &miscutils::dbhconnect("pnpmisc");
  my $sth = $dbh->prepare(q{
      SELECT shiprules,display,details
      FROM shipping
      WHERE username=?
      ORDER BY shiprules DESC
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$payutils::query{'publisher-name'}") or die "Can't execute: $DBI::errstr";
  while (my ($shiprules,$display,$details) = $sth->fetchrow) {
    my ($id,$label) = split('\|',$details);
    #  If rule has an ID and id is not being sent then skip rule
    if ( ($id ne "") && (($payutils::query{'serviceLevelCode'} eq "") || ($payutils::query{'serviceLevelCode'} eq "NONE")) ) {
      $shiprules = "";
      $display = "";
      $details = "";
      next;
    }
    #  If rule ID is being sent and rule contains an ID, then if ID's do not match skip rule
    if (($payutils::query{'serviceLevelCode'} ne "") && ($payutils::query{'serviceLevelCode'} ne "NONE") && ($id ne "")) {
      if ($payutils::query{'serviceLevelCode'} !~ /$id/i) {
        $shiprules = "";
        $display = "";
        $details = "";
        next;
      }
    }
    $shiprules =~ s/[^a-zA-Z0-9\.\,\|\:\/\ \-]//g;
    @rules = split(',',$shiprules);
    $ruletype = shift(@rules);
    $ruletype =~ s/[^a-zA-Z0-9]//g;
    $where = shift(@rules);
    $where =~ s/[^a-zA-Z0-9\:\|]//g;
    ($cntry,$state) = split('\:',$where);
    if ($state eq "all") {
      $state = $all_state_list;
    }
    elsif ($state eq "cont_only") {
      $state = $cont_only_state_list;
    }

    if ($cntry eq "all") {
      $cntry = "[A-Z]";
    }
    elsif ($cntry eq "intl") {
      $cntry_list =~ s/US\|//g;
      $cntry_list =~ s/CA\|//g;
      $cntry = $cntry_list;
    }
    elsif ($cntry eq "intlCA") {
      $cntry_list =~ s/US\|//g;
      $cntry = $cntry_list;
    }

    if (($payutils::query{'country'} =~ /^US$/i) && ($payutils::query{'state'} =~ /^($state)$/i)) {
      @shiprules = (@shiprules,$shiprules);
    }
    elsif (($payutils::query{'country'} =~ /$cntry/) && ($state =~ /^na$/i)) {
      @shiprules = (@shiprules,$shiprules);
    }
    ##  Commented Out  DCP 20060104
    #if (($payutils::query{'country'} =~ /$cntry/) && ($payutils::query{'state'} =~ /^($state)$/)) {
    #  @shiprules = (@shiprules,$shiprules);
    #  #last;
    #}
  }
  $sth->finish;
  $dbh->disconnect;


  # Hard Coded for testing.
  # Ship Rule MAP  Rule Name,CountryList:STateList,SubtotalThreshold|ShippingCost......
  if (exists $shiprules{$payutils::query{'publisher-name'}}) {
    #$shiprules = $shiprules{"$payutils::query{'publisher-name'}"};
    @shiprules = ($shiprules{"$payutils::query{'publisher-name'}"});
  }

  my $shipsubtot = $payutils::subtotal;
  my $shiptot = 0;
  foreach my $shiprules (@shiprules) {
    $shipping = 0;

### Commented Out 20100714 - jamest
#$payutils::query{'shiprules'} .= "$shiprules";

    #  These can be removed after hardcoded values for merchants above are removed.
    @rules = split(',',$shiprules);
    $ruletype = shift(@rules);
    $ruletype =~ s/[^a-zA-Z0-9]//g;
    $where = shift(@rules);
    $where =~ s/[^a-zA-Z0-9\:\|]//g;

$payutils::query{'shiprules_ruletype'} .= $ruletype;
$payutils::query{'shiprules_ruletype'} =~ s/\|/\,/g;

$payutils::query{'shiprules_where'} .= $where;
$payutils::query{'shiprules_where'} =~ s/\|/\,/g;

    if ($ruletype =~ /^item/) {
      my $amts = shift(@rules);
      $amts =~ s/[^a-zA-Z0-9\|\.\ \/ \-]//g;
$payutils::query{'shiprules_amts'} .= $amts;
$payutils::query{'shiprules_amts'} =~ s/\|/\,/g;
      my %rate = split('\|',$amts);
      my $idx = 0;
      my $itemorderflg = 0;
      for (my $j=1; $j<=$payutils::max; $j++) {
        my $item = $payutils::query{"item$j"};
        foreach my $key (keys %rate) {
          if ($item =~ /^$key/) {
            #if ($ruletype =~ /^itemper/) {
            if (($ruletype =~ /^itemper/) && ($item =~ /^$key$/)) {   ### DCP 20100420
              $shipping += ($rate{$key} * $payutils::query{"quantity$j"});
            }
            elsif ($ruletype =~ /^itemflat/) {
              $shipping += $rate{$key};
            }
            elsif ($ruletype =~ /^itemorder/) {
              $shipping += $rate{$key};
              $itemorderflg = 1;
              last;
            }
            $shipsubtot -= ($payutils::query{"quantity$j"} * $payutils::query{"cost$j"});
          }
        }
        if ($itemorderflg == 1) {
          last;
        }
      }
    }
    elsif ($ruletype =~ /^amount/) {
      if ($shipsubtot <= 0) {
        next;
      }
      my $amts = shift(@rules);
      $amts =~ s/[^a-zA-Z0-9\|\.]//g;
$payutils::query{'shiprules_amts'} .= $amts;
$payutils::query{'shiprules_amts'} =~ s/\|/\,/g;
      my @buckets = split('\|',$amts);
      my $lowlimit = 0;
      my $idx = 0;
      for ($idx=0;$idx<=@buckets;$idx++) {
        if (($shipsubtot > $lowlimit) && ($shipsubtot <= $buckets[$idx]) && ($buckets[$idx] ne "or")) {
          $shipping = $buckets[$idx+1];
          last;
        }
        elsif ($buckets[$idx] eq "or") {
          $shipping = $buckets[$idx+1];
          last;
        }
        else {
          $lowlimit = $buckets[$idx];
          $idx++;
        }
      }
    }
    elsif ($ruletype =~ /^percentage/) {
      if ($shipsubtot <= 0) {
        next;
      }
      my $amts = shift(@rules);
      $amts =~ s/[^a-zA-Z0-9\|\.]//g;
$payutils::query{'shiprules_amts'} .= $amts;
$payutils::query{'shiprules_amts'} =~ s/\|/\,/g;
      my @buckets = split('\|',$amts);
      my $lowlimit = 0;
      my $idx = 0;
      for ($idx=0;$idx<=@buckets;$idx++) {
        if (($shipsubtot > $lowlimit) && ($shipsubtot <= $buckets[$idx]) && ($buckets[$idx] ne "or")) {
          $shipping = ($buckets[$idx+1] * 0.01 * $payutils::subtotal);
          last;
        }
        elsif ($buckets[$idx] eq "or") {
          $shipping = ($buckets[$idx+1] * 0.01 * $payutils::subtotal);
          last;
        }
        else {
          $lowlimit = $buckets[$idx];
          $idx++;
        }
      }
    }
    elsif ($ruletype =~ /^flatper/) {
      if ($shipsubtot <= 0) {
        next;
      }
      my $amts = shift(@rules);
      $amts =~ s/[^a-zA-Z0-9\|\.]//g;
$payutils::query{'shiprules_amts'} .= $amts;
$payutils::query{'shiprules_amts'} =~ s/\|/\,/g;
      my @buckets = split('\|',$amts);
      my $lowlimit = 0;
      my $idx = 0;
      for ($idx=0;$idx<=@buckets;$idx++) {
         if ($buckets[$idx] eq "or") {
           $shipping = $buckets[$idx+1] * $payutils::totalcnt;
           last;
         }
      }
    }
    elsif ($ruletype =~ /^flatrate/) {
      if ($shipsubtot <= 0) {
        next;
      }
      my $amts = shift(@rules);
      $amts =~ s/[^a-zA-Z0-9\|\.]//g;
$payutils::query{'shiprules_amts'} .= $amts;
$payutils::query{'shiprules_amts'} =~ s/\|/\,/g;
      my @buckets = split('\|',$amts);
      my $lowlimit = 0;
      my $idx = 0;
      for ($idx=0;$idx<=@buckets;$idx++) {
         if ($buckets[$idx] eq "or") {
           $shipping = $buckets[$idx+1];
           last;
         }
      }
    }
    elsif ($ruletype =~ /^quantity/) {
      my $shipquan = $payutils::totalcnt;
      if ($shipquan <= 0) {
        next;
      }
      my $amts = shift(@rules);
      $amts =~ s/[^a-zA-Z0-9\|\.]//g;
$payutils::query{'shiprules_amts'} .= $amts;
$payutils::query{'shiprules_amts'} =~ s/\|/\,/g;
      my @buckets = split('\|',$amts);
      my $lowlimit = 0;
      my $idx = 0;
      for ($idx=0;$idx<=@buckets;$idx++) {
        if (($shipquan > $lowlimit) && ($shipquan <= $buckets[$idx]) && ($buckets[$idx] ne "or")) {
          $shipping = $buckets[$idx+1];
          last;
        }
        elsif ($buckets[$idx] eq "or") {
          $shipping = $buckets[$idx+1];
          last;
        }
        else {
          $lowlimit = $buckets[$idx];
          $idx++;
        }
      }
    }
    elsif ($ruletype =~ /^weight/) {
      my $shipwgt = $payutils::totalwgt;
      if ($shipwgt <= 0) {
        next;
      }
      my $amts = shift(@rules);
      $amts =~ s/[^a-zA-Z0-9\|\.]//g;
$payutils::query{'shiprules_amts'} .= $amts;
$payutils::query{'shiprules_amts'} =~ s/\|/\,/g;
      my @buckets = split('\|',$amts);
      my $lowlimit = 0;
      my $idx = 0;
      for ($idx=0;$idx<=@buckets;$idx++) {
        if (($shipwgt > $lowlimit) && ($shipwgt <= $buckets[$idx]) && ($buckets[$idx] ne "or")) {
          $shipping = $buckets[$idx+1];
          last;
        }
        elsif ($buckets[$idx] eq "or") {
          $shipping = $buckets[$idx+1];
          last;
        }
        else {
          $lowlimit = $buckets[$idx];
          $idx++;
        }
      }
    }

    $shiptot += $shipping;
  }

  $shipping = sprintf("%.2f",$shiptot);
  if ($ruletype =~ /plus/) {
    $shipping += $origshipamt;
  }
  $shipping = sprintf("%.2f",$shipping);
  $payutils::query{'shipcalced'} = 1;
  return $shipping;
}

sub certitaxcalc {
  my $env = new PlugNPay::Environment();
  my $remoteIP = $env->get('PNP_CLIENT_IP');
  my (%certitax);

  if ($payutils::feature{'certitax'} eq "") {
    return;
  }
  if (($payutils::query{'tax'} > 0) || ($payutils::query{'skiptaxcalc'} == 1))  {
    return;
  }

  ## Comment out later  DCP  200812101
  $payutils::query{'CertiTaxDebug'} = 1;

  $certitax{'ReferredId'} = "$payutils::query{'referredid'}";
  $certitax{'Location'} = "$payutils::query{'locationid'}";
  if ($payutils::query{'calculatetax'} =~ /^(true|false)$/i) {
    $certitax{'CalculateTax'} = $payutils::query{'calculatetax'};
  }
  else {
    $certitax{'CalculateTax'} = "True";
  }
  if ($payutils::query{'ConfirmAddress'} =~ /^(true|false)$/i) {
    $certitax{'ConfirmAddress'} = $payutils::query{'ConfirmAddress'};
  }
  else {
    $certitax{'ConfirmAddress'} = "false";
  }
  if ($payutils::query{'defaultproductcode'} =~ /[0-9]/) {
    $certitax{'DefaultProductCode'} =  $payutils::query{'defaultproductcode'};
  }
  else {
    $certitax{'DefaultProductCode'} = "0";
  }

  $certitax{'TaxExemptCertificate'} = "$payutils::query{'TaxExemptCertificate'}";
  $certitax{'TaxExemptIssuer'} = "$payutils::query{'TaxExemptIssuer'}";
  $certitax{'TaxExemptReason'} = "$payutils::query{'TaxExemptReason'}";

  my $url = "https://webservices.esalestax.net/CertiTAX.NET/CertiCalc.asmx/Calculate";

  my ($company,$taxable_addr1,$taxable_addr2,$taxable_city,$taxable_county,$taxable_state,$taxable_zip,$taxable_country,$taxable_name);
  my ($totalAmount,$lineItem);

  my ($serialNumber,$merchantID,$service_level,$nexus) = split('\|',$payutils::feature{'certitax'});

  $certitax{'SerialNumber'} = $serialNumber;

  if ($nexus !~ /^(POD|POB|POS|POSH)$/) {
    $certitax{'Nexus'} = "POD";
  }
  else {
    $certitax{'Nexus'} = $nexus;
  }

  $certitax{'MerchantTransactionId'} = "$payutils::query{'orderID'}";

  $service_level = "";
  if ($payutils::query{'taxbilling'} eq "yes") {
    $taxable_name = $payutils::query{'card-name'};
    $taxable_addr1 = $payutils::query{'card-address1'};
    $taxable_addr2 = $payutils::query{'card-address2'};
    $taxable_city = $payutils::query{'card-city'};
    $taxable_county = "";
    $taxable_state = $payutils::query{'card-state'};
    $taxable_zip = $payutils::query{'card-zip'};
  }
  else {
    if (($payutils::query{'state'} ne "") && ($payutils::query{'zip'} ne "")) {
      $taxable_name = $payutils::query{'shipname'};
      $taxable_addr1 = $payutils::query{'address1'};
      $taxable_addr2 = $payutils::query{'address2'};
      $taxable_city = $payutils::query{'city'};
      $taxable_county = "";
      $taxable_state = $payutils::query{'state'};
      $taxable_zip = $payutils::query{'zip'};
    }
    else {
      $taxable_name = $payutils::query{'card-name'};
      $taxable_addr1 = $payutils::query{'card-address1'};
      $taxable_addr2 = $payutils::query{'card-address2'};
      $taxable_city = $payutils::query{'card-city'};
      $taxable_county = "";
      $taxable_state = $payutils::query{'card-state'};
      $taxable_zip = $payutils::query{'card-zip'};
    }
  }
  $certitax{'Name'} = "$taxable_name";
  $certitax{'Street1'} = substr($taxable_addr1,0,35);
  $certitax{'Street2'} = substr($taxable_addr2,0,35);
  $certitax{'City'} = "$taxable_city";
  $certitax{'County'} = "$taxable_county";
  $certitax{'State'} = "$taxable_state";
  $certitax{'PostalCode'} = "$taxable_zip";
  $certitax{'Nation'} = "$taxable_country";


  if ($taxable_zip eq "") {
    return;
  }

  if ($service_level eq "lineitem") {
    my ($j);
    if ($payutils::query{'easycart'} == 1) {
      for ($j=1; $j<=$payutils::max; $j++) {
        my $cost = sprintf("%.2f",$payutils::quantity[$j] * $payutils::cost[$j]);
        $cost =~ s/[^0-9]//g;
        $lineItem .= "{$j,$payutils::item[$j],$payutils::quantity[$j],$cost}";
      }
      if ($payutils::query{'taxship'} ne "no") {
        $j++;
        my $shipping = $payutils::query{'shipping'};
        $shipping =~ s/[^0-9]//g;
        $lineItem .= "{$j,SHIP,1,$shipping}";
      }
    }
    else {
      if ($payutils::query{'taxship'} eq "no") {
        $totalAmount = $payutils::taxsubtotal;
      }
      else {
        $totalAmount = $payutils::taxsubtotal + $payutils::query{'shipping'};
      }
      $totalAmount = sprintf("%.2f",$totalAmount);
      $totalAmount =~ s/[^0-9]//g;
      $lineItem = "{1,TOTAL,1,$totalAmount}";
    }
  }
  else {
    my ($subtotal);
    if ($payutils::query{'easycart'} == 1) {
      $subtotal = $payutils::taxsubtotal;
    }
    else {
      $subtotal = $payutils::query{'subtotal'};
    }
    if ($payutils::query{'taxship'} eq "no") {
      $totalAmount = $subtotal;
    }
    else {
      $totalAmount = $subtotal + $payutils::query{'shipping'};
    }
    $totalAmount = sprintf("%.2f",$totalAmount);
    $totalAmount =~ s/[^0-9\.]//g;
  }
  $certitax{'ShippingCharge'} = "$payutils::query{'shipping'}";
  $certitax{'HandlingCharge'} = "$payutils::query{'handling'}";
  if ($certitax{'ShippingCharge'} == 0) {
    $certitax{'ShippingCharge'} = "0";
  }
  if ($certitax{'HandlingCharge'} == 0) {
    $certitax{'HandlingCharge'} = 0;
  }

  $certitax{'Total'} = "$totalAmount";
  ### Perform Web Services Request
  my $pairs = "";
  foreach my $key (keys %certitax) {
    $_ = $certitax{$key};
    s/(\W)/'%' . unpack("H2",$1)/ge;
    if($pairs ne "") {
      $pairs = "$pairs\&$key=$_" ;
    }
    else{
      $pairs = "$key=$_" ;
    }
  }

  my $starttime = time();
  my $resp = &miscutils::formpost_raw($url,$pairs);

  if ($resp =~ /xml version/i) {
    require XML::Simple;

    my @taxdetails = ('CityTaxAuthority','CountyTaxAuthority','LocalTaxAuthority','NationalTaxAuthority','OtherTaxAuthority','StateTaxAuthority','CityTax','CountyTax','LocalTax','NationalTax','OtherTax','StateTax');

    my $parser = XML::Simple->new();
    my $xmldoc = $parser->XMLin($resp, SuppressEmpty => 1);
    $payutils::query{'CertiTaxID'} = $xmldoc->{CertiTAXTransactionId};
    $payutils::query{'tax'} = $xmldoc->{TotalTax};

    if ($payutils::query{'certitaxdetail'} == 1) {
      foreach my $element (@taxdetails) {
        if (defined $xmldoc->{$element}) {
          $payutils::query{"$element"} = $xmldoc->{"$element"};
        }
        else {
          $payutils::query{"$element"} = "";
        }
      }
    }
  }
  else {
    $payutils::query{'taxcalcerror'} = "$resp";
  }

  if ($payutils::query{'CertiTaxDebug'} == 1) {
    my $endtime = time();
    my $etime = $endtime - $starttime;
    my $time = gmtime(time());
    open (DEBUG,'>>',"/home/p/pay1/database/debug/CertTax_debug.txt");
    print DEBUG "TIME:$time, ETIME:$etime, RA:$remoteIP, MERCH:$mckutils::query{'publisher-name'}, SCRIPT:$ENV{'SCRIPT_NAME'}, ";
    print DEBUG "HOST:$ENV{'SERVER_NAME'}, URL:$url INPUT VAR: ";
    print DEBUG "SEND:$pairs\n";
    print DEBUG "RETURN:$resp\n\n";
    close (DEBUG);
  }
}

sub input_authnet {
  my (%query) = @_;

  my %authnetHash = ();
  foreach my $key (keys %query) {
    if ($key =~ /^x_/i) {
      $authnetHash{lc $key} = $query{$key};
    }
  }

  if (exists $query{'ccNum'}) {
    $query{'card-number'} = $query{'ccNum'};
  }
  if (exists $query{'ZIP'}) {
    $query{'card-zip'} = $query{'ZIP'};
  }
  if (exists $query{'amount'}) {
    $query{'card-amount'} = $query{'amount'};
  }
  if (exists $authnetHash{'x_exp_date'}) {
    my ($mo,$yr) = split('/',$authnetHash{'x_exp_date'});
    if (length($mo) == 1) {
      $query{'card-exp'} = "0$mo" . "/" . substr($authnetHash{'x_exp_date'},-2);
    }
    else {
      $query{'card-exp'} = "$mo" . "/" . substr($authnetHash{'x_exp_date'},-2);
    }
  }

  my %authnet_map = ('publisher-name','x_Login','card-address1','x_Address','card-number','x_Card_Num','card-city','x_City','card-state','x_State','card-zip','x_Zip','card-country','x_Country','orderID','x_InvoiceNum','card-amount','x_Amount','address1','x_Ship_To_Address','city','x_Ship_To_City','state','x_Ship_To_State','zip','x_Ship_To_Zip','country','x_Ship_To_Country','phone','x_Phone','email','x_Email','success-link','x_Receipt_Link_URL');

  foreach my $key (keys %authnet_map) {
    if (exists $authnetHash{lc $authnet_map{$key}} ) {
      $query{$key} = $authnetHash{lc $authnet_map{$key}};
    }
  }
  if (exists $authnetHash{'x_first_name'}) {
    $query{'card-name'} = $authnetHash{'x_first_name'} . " " . $authnetHash{'x_last_name'};
  }

  if (exists $authnetHash{'x_Ship_to_First_Name'}) {
    $query{'shipname'} = "$authnetHash{'x_ship_to_first_name'} $authnetHash{'x_ship_to_last_name'}";
  }
  if ($query{'client'} eq "") {
    $query{'client'} = "authnet";
  }
  if (($authnetHash{'x_adc_url'} =~ /^https?:\/\//i) && ($authnetHash{'x_adc_relay_response'} =~ /^true$/i)) {
    $query{'success-link'} = $authnetHash{'x_adc_url'};
  }
  elsif (($authnetHash{'x_relay_url'} =~ /^https?:\/\//i) && ($authnetHash{'x_relay_response'} =~ /^true$/i)) {
    $query{'success-link'} = $authnetHash{'x_relay_url'};
  }

  return %query;
}

sub javascript_cardswipe {
  my $output = '';

  $output .= "var cardname = '';\n";
  $output .= "var firstname = '';\n";
  $output .= "var lastname = '';\n";
  $output .= "var cardnumber = '';\n";
  $output .= "var carddata = '';\n";
  $output .= "var exp_mo = '';\n";
  $output .= "var exp_yr = '';\n";

  $output .= "var clickedButton = false;\n";

  $output .= "function parsedata() {\n";
  $output .= "  if (document.keyswipe1.in1.value == '') {\n";
  $output .= "    //close window, when field is blank.\n";
  $output .= "    self.close();\n";
  $output .= "  }\n";
  $output .= "\n";
  $output .= "  if (((document.keyswipe1.in1.value.charAt(0) == 'B') || (document.keyswipe1.in1.value.charAt(0) == 'b')) && (document.keyswipe1.in1.value.charAt(document.keyswipe1.in1.value.length -1) != '?')){\n";
  $output .= "    carddata = '%' + document.keyswipe1.in1.value + '?';\n";
  $output .= "  }\n";
  $output .= "  else {\n";
  $output .= "    carddata = document.keyswipe1.in1.value;\n";
  $output .= "  }\n";
  $output .= "\n";
  $output .= "  if ((carddata.charAt(0) == '%') && ((carddata.charAt(1) == 'B') || (carddata.charAt(1) == 'b')) && (carddata.charAt(carddata.length -1) == '?')) {\n";
  $output .= "    cardnumber = carddata.slice(2,carddata.search(/\\^/));\n";
  $output .= "    cardnumber = cardnumber.replace(/ /g,'');\n";
  $output .= "    cardname = carddata.slice((carddata.search(/\\^/) + 1),(carddata.length - 1));\n";
  $output .= "    cardexp = cardname.slice((cardname.search(/\\^/) + 1),(cardname.search(/\\^/) + 5));\n";
  $output .= "    exp_mo = cardexp.slice(2,4);\n";
  $output .= "    exp_yr = cardexp.slice(0,2);  \n";
  $output .= "    cardexp = cardexp.slice(2,4) + \"/\" + cardexp.slice(0,2);\n";
  $output .= "    cardname = cardname.slice(0,cardname.search(/\\^/));\n";
  $output .= "    lastname = cardname.slice(0,cardname.search(/\\//));\n";
  $output .= "    firstname = cardname.slice((cardname.search(/\\//) + 1),(cardname.length));\n\n";
  $output .= "    while (firstname.charAt(firstname.length - 1) == ' ') {\n";
  $output .= "      firstname = firstname.slice(0,(firstname.length - 1));\n";
  $output .= "    }\n\n";
  $output .= "    for (var i = 0; i < document.pay.month_exp.length; i++) {\n";
  $output .= "      if (document.pay.month_exp.options[i].value == exp_mo) {\n";
  $output .= "        document.pay.month_exp.selectedIndex = i;\n";
  $output .= "      }\n";
  $output .= "    }\n\n";
  $output .= "    for (var i = 0; i < document.pay.year_exp.length; i++) {\n";
  $output .= "      var AA = document.pay.year_exp.options[i].value;\n";
  $output .= "      if (document.pay.year_exp.options[i].value == exp_yr) {\n";
  $output .= "        document.pay.year_exp.selectedIndex = i;\n";
  $output .= "      }\n";
  $output .= "    }\n\n";
  $output .= "    document.pay.card_name.value = firstname + \" \" + lastname;\n";
  $output .= "    document.pay.card_number.value = cardnumber;\n";
  $output .= "    document.pay.magstripe.value = carddata;\n\n";
  $output .= "    document.keyswipe1.in1.value = '';\n";
  $output .= "  }\n";
  $output .= "  else {\n";
  $output .= "    if (carddata.charAt(carddata.length -1) == '?') {\n";
  $output .= "      alert('Bad card data please swipe again.');\n";
  $output .= "      document.keyswipe1.in1.value = '';\n";
  $output .= "      document.keyswipe1.in1.focus();\n";
  $output .= "    }\n";
  $output .= "  }\n";
  $output .= "}\n";
  $output .= "\n";

  return $output;
}

sub javascript_luhn10 {
  my $output = '';

  $output .= "function isCreditCard() {\n";
  $output .= "// perform luhn10 check on credit card number\n";
  $output .= "\n";
  $output .= "  var CC = document.pay.card_number.value;\n";
  $output .= "\n";

  $output .= "  if (CC == \"ENCRYPTED\") {\n";
  $output .= "    return true;\n";
  $output .= "  }\n";
  $output .= " \n";

  $output .= "  var cardtest = CC.slice(0,6);\n";
  $output .= "  if ((cardtest == '604626') || (cardtest == '605011') || (cardtest == '603028') || (cardtest == '603628')) {\n";
  $output .= "    return true;\n";
  $output .= "  }\n\n";

  if (($payutils::processor eq "mercury") && ($payutils::feature{'acceptgift'} == 1)) {
    $output .= "  if ((document.pay.mpgiftcard) && (document.pay.mpgiftcard.value.length > 12) && (CC.length == 0)) {\n";
    $output .= "    return true;\n";
    $output .= "  }\n\n";
  }

  $output .= "  if ((CC.length > 20) || (CC.length < 12)) {\n";
  $output .= "    return false;\n";
  $output .= "  }\n";
  $output .= " \n";
  $output .= "  sum = 0; mul = 1; l = CC.length;\n";
  $output .= "\n";
  $output .= "  for (i = 0; i < l; i++) {\n";
  $output .= "    digit = CC.substring(l-i-1,l-i);\n";
  $output .= "    tproduct = parseInt(digit ,10)*mul;\n";
  $output .= "    if (tproduct >= 10) {\n";
  $output .= "      sum += (tproduct % 10) + 1;\n";
  $output .= "    }\n";
  $output .= "    else {\n";
  $output .= "      sum += tproduct;\n";
  $output .= "    }\n";
  $output .= "    if (mul == 1) {\n";
  $output .= "      mul++;\n";
  $output .= "    }\n";
  $output .= "    else {\n";
  $output .= "      mul--;\n";
  $output .= "    }\n";
  $output .= "  }\n";
  $output .= "\n";
  $output .= "  if ((sum % 10) == 0){\n";
  $output .= "  // card passed luhn10 check\n";
  $output .= "    return true;\n";
  $output .= "  }\n";
  $output .= "  else {\n";
  $output .= "  // card failed luhn10 check\n";
  $output .= "    return false;\n";
  $output .= "  }\n";
  $output .= "}\n";

  return $output;
}

sub pay_swipe_billing {
  my $output = '';

  if (($payutils::feature{'hidepayswipe'} ne "yes") && ($payutils::newswipecode != 1)) {
    $output .= "<tr><td colspan=\"2\" class=\"larger\">\n";
    $output .= "<FORM name=\"keyswipe1\" onSubmit=\"return clickedButton\" onKeyPress=\"if(event.keyCode==13 || event.keycode==10) return false;\" $payutils::autocomplete{'form'}>\n";
    $output .= "Swipe Credit Card: <input type=\"password\" name=\"in1\" size=\"20\" onChange=\"parsedata();\"> <input type=\"button\" value=\"OK\" onChange=\"parsedata();\">\n";
    $output .= "</FORM>\n";
    $output .= "</td></tr>\n";

    $output .= "<tr><td colspan=\"3\" class=\"larger\">OR</td></tr>\n";
  }

  if ($payutils::newswipecode == 1) {
    $output .= "<form method=\"post\" name=\"pay\" action=\"$payutils::query{'path_invoice_cgi'}\" onSubmit=\"return disableForm(this) && checkMagstripe(event)\" $payutils::autocomplete{'form'}>\n";

  }
  else {
    $output .= "<form method=\"post\" name=\"pay\" action=\"$payutils::query{'path_invoice_cgi'}\" onSubmit=\"return disableForm(this);\" $payutils::autocomplete{'form'}>\n";
  }

  if ($payutils::query{'paymethod'} !~ /^(onlinecheck|check)$/) {
    $output .= "<input type=\"hidden\" name=\"magstripe\" value=\"$payutils::query{'magstripe'}\">\n";
    $output .= "<input type=\"hidden\" name=\"convert\" value=\"underscores\">\n";
  }

  if (($payutils::query{'app-level'} > 1) && ($payutils::query{'noavsnotice'} ne "yes")) {
    $output .= "<tr><td class=\"larger\" colspan=\"2\"><b>NOTICE:</b> Address Verification is being enforced. ";
    $output .= "Please enter your address exactly as it appears on your credit card statement or your purchase will be declined.";
    $output .= "</td></tr>\n";
  }

  if ($payutils::query{'showbillinginfo'} ne "no") {
    $output .= "<tr><td align=\"left\" colspan=\"2\" class=\"larger\"><br>";
    $output .= "$payutils::lang_titles{'billing'}[$payutils::lang]<br>";
    $output .= "</td></tr>\n";

    $output .= "<tr><td align=\"left\" colspan=\"2\">";
    $output .= "$payutils::lang_titles{'billing1'}[$payutils::lang]\n";
    $output .= "</td></tr>\n";
  }

  if ($payutils::query{'askamtflg'} == 1) {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-amount'}\"><span>$payutils::lang_titles{'amt_to_pay'}[$payutils::lang]\:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"card-amount\" size=\"10\" value=\"$payutils::query{'card-amount'}\" maxlength=\"10\"></td></tr>\n";
  }
  if ($payutils::template{'body_cardinfo'} ne "") {
    $output .= "$payutils::template{'body_cardinfo'}\n";
  }

  $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-name'}\"><span>Name:<b>*</b></span></td>";
  $output .= "<td align=\"left\"><input type=\"text\" name=\"card_name\" size=\"30\" value=\"$payutils::query{'card-name'}\" maxlength=\"39\"></td></tr>\n";

  if ($payutils::query{'card-allowed'} ne "") {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-type'}\"><span>Card Types Accepted:</span></td>";
    $output .= "<td align=\"left\"><span style=\"color: $payutils::goodcolor\">";
    if ($payutils::query{'card-allowed'} =~ /Visa/i)        { $output .= "Visa "; }
    if ($payutils::query{'card-allowed'} =~ /Mastercard/i)  { $output .= "Mastercard "; }
    if ($payutils::query{'card-allowed'} =~ /Amex/i)        { $output .= "Amex "; }
    if ($payutils::query{'card-allowed'} =~ /Discover/i)    { $output .= "Discover "; }
    if ($payutils::query{'card-allowed'} =~ /Diners/i)      { $output .= "Diners Club "; }
    if ($payutils::query{'card-allowed'} =~ /JCB/i)         { $output .= "JCB "; }

    if ($payutils::query{'card-allowed'} =~ /EasyLink|Bermuda|IslandCard|Butterfield|KeyCard/i) { $output .= "\n<br>"; }
    if ($payutils::query{'card-allowed'} =~ /EasyLink/i)    { $output .= "EasyLink "; }
    if ($payutils::query{'card-allowed'} =~ /Bermuda/i)     { $output .= "Bermuda Card "; }
    if ($payutils::query{'card-allowed'} =~ /IslandCard/i)  { $output .= "Island Card "; }
    if ($payutils::query{'card-allowed'} =~ /Butterfield/i) { $output .= "Butterfield Card "; }
    if ($payutils::query{'card-allowed'} =~ /KeyCard/i)     { $output .= "Key Card "; }

    if ($payutils::processor =~ /^(pago|barclays)$/) {
      if ($payutils::query{'card-allowed'} =~ /Solo/i)       { $output .= "Solo "; }
      if ($payutils::query{'card-allowed'} =~ /Switch/i)     { $output .= "Switch "; }
    }
    $output .= "</span></td></tr>\n";
  }

  my $cardnumfieldtype = "";
  if ($payutils::feature{'cardnumfield'} eq "masked") {
    $cardnumfieldtype = "password";
  }
  else {
    $cardnumfieldtype = "text";
  }
  $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-number'}\"><span>Credit Card \#:<b>*</b></span></td>";

  if ($payutils::newswipecode == 1) {
    $output .= "<td align=\"left\"><input type=\"$cardnumfieldtype\" name=\"card_number\" id=\"card_number\" value=\"$payutils::query{'card-number'}\" onKeyPress=\"return noautosubmit(event);\" size=\"16\" autocomplete=\"off\"></td></tr>\n";
    $output .= "<input type=\"hidden\" name=\"magensacc\" id=\"magensacc\" value=\"\">\n";
    $output .= "<input type=\"hidden\" name=\"EncTrack1\" id=\"EncTrack1\" value=\"\">\n";
    $output .= "<input type=\"hidden\" name=\"EncTrack2\" id=\"EncTrack2\" value=\"\">\n";
    $output .= "<input type=\"hidden\" name=\"EncTrack3\" id=\"EncTrack3\" value=\"\">\n";
    $output .= "<input type=\"hidden\" name=\"EncMP\" id=\"EncMP\" value=\"\">\n";
    $output .= "<input type=\"hidden\" name=\"KSN\" id=\"KSN\" value=\"\">\n";
    $output .= "<input type=\"hidden\" name=\"devicesn\" id=\"devicesn\" value=\"\">\n";
    $output .= "<input type=\"hidden\" name=\"MPStatus\" id=\"MPStatus\" value=\"\">\n";
    $output .= "<input type=\"hidden\" name=\"MagnePrintStatus\" id=\"MagnePrintStatus\" value=\"\">\n";

  }
  else {
    $output .= "<td align=\"left\"><input type=\"$cardnumfieldtype\" name=\"card_number\" value=\"$payutils::query{'card-number'}\" size=\"16\" maxlength=\"20\" autocomplete=\"off\"></td></tr>\n";
  }

  if (($payutils::feature{'cvv'} == 1) || ($payutils::query{'cvv-flag'} eq "yes")) {
    my $cvvfieldtype = "";
    if ($payutils::feature{'cvvfield'} eq "masked") {
      $cvvfieldtype = "password";
    }
    else {
      $cvvfieldtype = "text";
    }
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-cvv'}\"><span>Credit Card CVV/CVC:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"$cvvfieldtype\" name=\"card-cvv\" value=\"$payutils::query{'card-cvv'}\" size=\"4\" maxlength=\"4\" autocomplete=\"off\"> Required for Visa/Mastercard";
    if ($payutils::query{'card-allowed'} =~ /Discover/i) {
      $output .= "/Discover";
    }
    if ($payutils::query{'card-allowed'} =~ /Amex/i) {
      $output .= "/Amex";
    }

    if ($payutils::processor eq "ncb") {
      $output .= "/and some KeyCards";
    }

    $output .= ". <a href=\"help.cgi?subject=cvv\" target=\"help\" onClick=\"online_help(300,500)\;\"><font size=\"-2\" color=\"$payutils::goodcolor\"><b>Click Here For Help</b></font></a> </td></tr>\n";
  }


  $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-exp'}\"><span>Exp. Date:<b>*</b></span></td> ";
  $output .= "<td align=\"left\"><select name=\"month_exp\">\n";
  my @months = ("01","02","03","04","05","06","07","08","09","10","11","12");
  my ($date) = &miscutils::gendatetime_only();
  my $current_month = substr($date,4,2);
  my $current_year = substr($date,0,4);
  if ($payutils::query{'month_exp'} eq "") {
    $output .= "<option value=\"\" selected>Month</option>\n";  ## DCP 20081111
  }
  foreach my $var (@months) {
    if ($var eq $payutils::query{'month_exp'}) {
      $output .= "<option value=\"$var\" selected>$var</option>\n";
    }
    else {
      $output .= "<option value=\"$var\">$var</option>\n";
    }
  }
  $output .= "</select> ";

  $output .= "<select name=\"year_exp\">\n";
  if ($payutils::query{'year_exp'} eq ""){
    $output .= "<option value=\"\" selected>Year</option>\n";  ## DCP 20081111
  }
  for (my $i; $i<=12; $i++) {
    my $var = $current_year + $i;
    my $val = substr($var,2,2);
    if ($val eq $payutils::query{'year_exp'}) {
      $output .= "<option value=\"$val\" selected>$var</option>\n";
     }
    else {
      $output .= "<option value=\"$val\">$var</option>\n";
    }
  }
  $output .= "</select></td></tr>\n";

  if (($payutils::processor =~ /^(pago|barclays)$/) && ($payutils::query{'card-allowed'} =~ /Solo|Switch/i)) {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'cardissuenum'}\"><span>Card Issue #:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"cardissuenum\" value=\"$payutils::query{'cardissuenum'}\" size=\"3\" maxlength=\"2\" autocomplete=\"off\"> (Switch/Solo Cards Only)</td></tr>\n";

    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'cardstartdate'}\"><span>Card Start Date:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"cardstartdate\" value=\"$payutils::query{'cardstartdate'}\" size=\"30\" maxlength=\"30\" autocomplete=\"off\"> (Switch/Solo Cards Only)</td></tr>\n";
  }


  if (($payutils::processor =~ /^(mercury|testprocessor)$/) && ($payutils::feature{'acceptgift'} == 1)) {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'mpgiftcard'}\"><span>Gift Card Number:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"mpgiftcard\" value=\"$payutils::query{'mpgiftcard'}\" size=\"20\" maxlength=\"30\" autocomplete=\"off\"></td></tr>\n";
    $output .= "<tr><td>&nbsp;</td><td>If you have a Gift Card you may enter it here instead of a credit card. If your Gift Card balance is insufficient for the entire purchase amount you may enter your Credit Card details as well.  Any amount still outstanding after your gift card has been charged will be applied against your credit card.</td></tr>\n";
  }

  if ($payutils::query{'commcardtype'} eq "business") {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'ponumber'}\"><span>PO Number:<b>*</b></span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"ponumber\" value=\"$payutils::query{'ponumber'}\" size=\"20\" maxlength=\"20\"></td></tr>\n";
  }
  if ($payutils::feature{'swipe_address'} == 1) {
    if ($payutils::feature{'suppressswipepay'} !~ /card-address1/) {
      $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-address1'}\"><span>$payutils::lang_titles{'card_address1'}[$payutils::lang]\:$payutils::requiredstar{'card-address1'}</span></td>";
      $output .= "<td align=\"left\"><input type=\"text\" name=\"card-address1\" size=\"30\" value=\"$payutils::query{'card-address1'}\" maxlength=\"39\"></td></tr>\n";
    }
    if ($payutils::feature{'suppressswipepay'} !~ /card-address2/) {
      $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-address2'}\"><span>$payutils::lang_titles{'card_address2'}[$payutils::lang]\:$payutils::requiredstar{'card-address2'}</span></td>\n";
      $output .= "<td align=left><input type=\"text\" name=\"card-address2\" size=\"30\" value=\"$payutils::query{'card-address2'}\" maxlength=\"39\"></td></tr>\n";
    }
    if ($payutils::feature{'suppressswipepay'} !~ /card-city/) {
      $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-city'}\"><span>$payutils::lang_titles{'city'}[$payutils::lang]\:$payutils::requiredstar{'card-city'}</span></td>";
      $output .= "<td align=\"left\"><input type=\"text\" name=\"card-city\" size=\"20\" value=\"$payutils::query{'card-city'}\" maxlength=\"30\"></td></tr>\n";
    }
    if ($payutils::feature{'suppressswipepay'} !~ /card-state/) {
      if ($payutils::query{'nostatelist'} ne "yes") {
        $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-state'}\"><span>$payutils::lang_titles{'state'}[$payutils::lang]\:$payutils::requiredstar{'card-state'}</span></td>";
        $output .= "<td align=\"left\"><select name=\"card-state\">\n";

        my %selected = ();
        $selected{$payutils::query{'card-state'}} = " selected";
        $output .= "<option value=\"\">$payutils::lang_titles{'selectstate'}[$payutils::lang]</option>\n";
        foreach my $key (&sort_hash(\%constants::USstates)) {
          $output .= "<option value=\"$key\"$selected{$key}>$constants::USstates{$key}</option>\n";
        }
        if ($payutils::usterrflag ne "no") {
          foreach my $key (sort keys %constants::USterritories) {
            $output .= "<option value=\"$key\"$selected{$key}>$constants::USterritories{$key}</option>\n";
          }
        }
        if (($payutils::usonly ne "yes") && ($payutils::uscanonly ne "yes"))  {
          foreach my $key (sort keys %constants::CNprovinces) {
            $output .= "<option value=\"$key\"$selected{$key}>$constants::CNprovinces{$key}</option>\n";
          }
        }
        if ($payutils::uscanonly eq "yes")  {
          foreach my $key (sort keys %constants::USCNprov) {
            $output .= "<option value=\"$key\"$selected{$key}>$constants::USCNprov{$key}</option>\n";
          }
        }
        $output .= "</select></td></tr>\n";
      }
      else {
        $output .= "<tr><td ALIGN=\"right\" class=\"$payutils::color{'card-state'}\"><span>$payutils::lang_titles{'state'}[$payutils::lang]\:$payutils::requiredstar{'card-state'}</span></td>";
        $output .= "<td align=\"left\"><input type=\"text\" name=\"card-state\" size=\"20\" value=\"$payutils::query{'card-state'}\" maxlength=\"19\"></td></tr>\n";
      }
     }
    if ($payutils::feature{'suppresspay'} !~ /card-prov/) {
      if (($payutils::usonly ne "yes") && ($payutils::uscanonly ne "yes"))  {
        $output .= "<tr><td ALIGN=\"right\" class=\"$payutils::color{'card-prov'}\"><span>$payutils::lang_titles{'province'}[$payutils::lang]\:$payutils::requiredstar{'card-prov'}</span></td>";
        $output .= "<td align=\"left\"><input type=\"text\" name=\"card-prov\" size=\"20\" value=\"$payutils::query{'card-prov'}\" maxlength=\"19\"></td></tr>\n";
      }
    }
     if ($payutils::feature{'suppresspay'} !~ /card-zip/) {
      $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-zip'}\"><span>$payutils::lang_titles{'zip'}[$payutils::lang]\:$payutils::requiredstar{'card-zip'}</span></td>";
      $output .= "<td align=\"left\"><input type=\"text\" name=\"card-zip\" size=\"10\" value=\"$payutils::query{'card-zip'}\" maxlength=\"10\"></td></tr>\n";
    }
    if ($payutils::feature{'suppresspay'} !~ /card-country/) {
      if ($payutils::query{'nocountrylist'} ne "yes") {
        $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-country'}\"><span>$payutils::lang_titles{'country'}[$payutils::lang]\:$payutils::requiredstar{'card-country'}</span></td>";
        $output .= "<td align=left><select name=\"card-country\">\n";

        my %selected = ();
        $selected{$payutils::query{'card-country'}} = " selected";
        if ($payutils::usonly eq "yes") {
          $output .= "<option value=\"US\" selected>$constants::countries{'US'}</option>\n";
        }
        elsif ($payutils::uscanonly eq "yes") {
          $output .= "<option value=\"US\"$selected{'US'}>$constants::countries{'US'}</option>\n";
          $output .= "<option value=\"CA\"$selected{'CA'}>$constants::countries{'CA'}</option>\n";
        }
        else {
          foreach my $key (&sort_hash(\%constants::countries)) {
            $output .= "<option value=\"$key\"$selected{$key}>$constants::countries{$key}</option>\n";
          }
        }
        $output .= "</select></td></tr>\n";
      }
      else {
        $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-country'}\"><span>$payutils::lang_titles{'country'}[$payutils::lang]\:$payutils::requiredstar{'card-country'}</span></td>";
        $output .= "<td align=\"left\"><input type=\"text\" name=\"card-country\" size=\"15\" value=\"$payutils::query{'card-country'}\" maxlength=\"20\"></td></tr>\n";
      }
    }
  }
  elsif ($payutils::feature{'swipe_zip'} == 1) {
    $output .= "<tr><td align=\"right\" class=\"$payutils::color{'card-zip'}\"><span>$payutils::lang_titles{'zip'}[$payutils::lang]\: </span></td>";
    $output .= "<td align=\"left\"><input type=\"text\" name=\"card-zip\" size=\"10\" value=\"$payutils::query{'card-zip'}\" maxlength=\"10\"></td></tr>\n";
  }

  return $output;
}

sub pay_swipe_head {
  my $output = '';

  $output .= "<!DOCTYPE html>\n";
  if (($payutils::query{'client'} eq "rectrac") && ($payutils::query{'publisher-name'} =~ /^(pnpdemo2|scotttest|demoacct|demoacct2)$/)) {
    $output .= "<!-- saved from url=(0040)http://pay1.plugnpay.com/payment/pay.cgi -->\n";
  }
  $output .= "<html>\n";
  $output .= "<head>\n";
  $output .= "<title>Payment Screen</title> \n";
  if ($payutils::query{'lang'} ne "") {
    $output .= "<meta content=\"text/html; charset=UTF-8\" http-equiv=\"content-type\"/>\n";
  }

  if ($payutils::newswipecode == 1) {
    # new card swipe javascript
    $output .= "<script type=\"text/javascript\" charset=\"utf-8\" src=\"https://$ENV{'SERVER_NAME'}/javascript/jquery.min.js\"></script>\n";
    $output .= "<script type=\"text/javascript\" src=\"https://$ENV{'SERVER_NAME'}/javascript/swipe.js\"></script>\n";
    $output .= "<script type=\"text/javascript\"> \n";
    $output .= "   \$('document').ready( function() { \n";
    $output .= "   pnp_BindKr('#card_number,#routingnum'); \n";
    $output .= "   }); \n";
    $output .= "</script> \n";
  }
  $output .= "<script Language=\"Javascript\">\n";
  $output .= "<\!-- Start Script\n";

  if ($payutils::newswipecode != 1) {
    $output .= &javascript_cardswipe();
  }

  $output .= &javascript_luhn10();

  $output .= "function results() {\n";
  $output .= "  resultsWindow = window.open('/payment/recurring/blank.html','results','menubar=no,status=no,scrollbars=yes,resizable=yes,width=400,height=300');\n";
  $output .= "}\n";

  $output .= "function online_help(ht,wd) {\n";
  $output .= "  helpWindow = window.open('/payment/recurring/blank.html','help','menubar=no,status=no,scrollbars=yes,resizable=yes,width='+wd+',height='+ht);\n";
  $output .= "}\n";

  $output .= "pressed_flag = 0;\n";
  $output .= "function mybutton(form) {\n";
  $output .= "  if (pressed_flag == 0) {\n";
  $output .= "    pressed_flag = 1;\n";
  $output .= "    return true;\n";
  $output .= "  }\n";
  $output .= "  else {\n";
  $output .= "    return false;\n";
  $output .= "  }\n";
  $output .= "}\n";

  $output .= "function disableForm(theform) {\n";
  $output .= "  // perform luhn10 check, if credit card number\n";
  $output .= "  if ((isCreditCard() == false) && (document.pay.paymethod.value == 'swipe')) {\n";
  if ($payutils::feature{'indicate_processing'} ne "") {
    $output .= "    is_processing('false');\n";
  }
  $output .= "    alert('Invalid Credit Card Number.  Please Try Again.');\n";
  $output .= "    return false;\n";
  $output .= "  }\n";
  $output .= "  if (document.all || document.getElementById) {\n";
  $output .= "    for (i = 0; i < theform.length; i++) {\n";
  $output .= "      var tempobj = theform.elements[i];\n";
  $output .= "      if (tempobj.type.toLowerCase() == 'submit' || tempobj.type.toLowerCase() == 'reset')\n";
  $output .= "        tempobj.disabled = true;\n";
  $output .= "    }\n";
  $output .= "    return true;\n";
  $output .= "  }\n";
  $output .= "  else {\n";
  $output .= "    return true;\n";
  $output .= "  }\n";
  $output .= "}\n";

  if ($payutils::feature{'indicate_processing'} ne "") {
    $output .= "function is_processing(recon) {\n";
    $output .= "  if (recon == 'true') {\n";
    $output .= "    document.getElementById('processingStatement').innerHTML = '<div align=center><b>Processing Payment, Please be Patient<b></div><br>';\n";
    $output .= "  }\n";
    $output .= "  else {\n";
    $output .= "    document.getElementById('processingStatement').innerHTML = '';\n";
    $output .= "  }\n";
    $output .= "}\n";
  }

  $output .= "// end script-->\n";
  $output .= "</script>\n\n";

  $output .= "<style type=\"text/css\">\n";
  $output .= "<!--\n";
  $output .= "th { font-family: $payutils::fontface; font-size: 10pt; color: $payutils::goodcolor }\n";
  $output .= "td { font-family: $payutils::fontface; font-size: 9pt; color: $payutils::goodcolor }\n";
  $output .= ".badcolor { color: $payutils::badcolor }\n";
  $output .= ".goodcolor { color: $payutils::goodcolor }\n";
  $output .= ".larger { font-size: 12pt }\n";
  $output .= ".smaller { font-size: 9pt }\n";
  $output .= ".short { font-size: 8% }\n";
  $output .= ".itemscolor { background-color: $payutils::titlebackcolor; color: $payutils::titlecolor }\n";
  $output .= ".itemrows { background-color: $payutils::itemrow }\n";
  $output .= ".info { position: static }\n";
  $output .= "#tail { position: static }\n";
  $output .= "-->\n";
  $output .= "</style>\n";

  if ($payutils::feature{'css-link'} ne "") {
    $output .= "<link href=\"$payutils::feature{'css-link'}\" type=\"text/css\" rel= \"stylesheet\">\n";
  }

  $output .= "</head>\n";

  if ($payutils::backimage eq "") {
    $output .= "<body bgcolor=\"$payutils::backcolor\" link=\"$payutils::linkcolor\" text=\"$payutils::goodcolor\" alink=\"$payutils::alinkcolor\" vlink=\"$payutils::vlinkcolor\" $payutils::upsell $payutils::autoload>\n";
  }
  else {
    $output .= "<body bgcolor=\"$payutils::backcolor\" link=\"$payutils::linkcolor\" text=\"$payutils::goodcolor\" alink=\"$payutils::alinkcolor\" vlink=\"$payutils::vlinkcolor\" background=\"$payutils::backimage\" $payutils::upsell $payutils::autoload>\n";
  }

  if ($payutils::query{'image-placement'} eq "") {
    $payutils::query{'image-placement'} = "center";
  }

  if (($payutils::query{'image-link'} ne "") && ($payutils::query{'image-placement'} ne "left") && ($payutils::query{'image-placement'} ne "topleft") && ($payutils::query{'image-placement'} ne "table")) {
    $output .= "<div align=\"$payutils::query{'image-placement'}\">\n";
    $output .= "<img src=\"$payutils::query{'image-link'}\">\n";
    $output .= "</div>\n\n";
  }
  elsif (($payutils::query{'image-link'} ne "") && ($payutils::query{'image-placement'} eq "topleft")) {
    $output .= "<div align=\"left\">\n";
    $output .= "<img src=\"$payutils::query{'image-link'}\">\n";
    $output .= "</div>\n\n";
  }

  $output .= "<div class=\"info\" align=\"center\">\n";
  $output .= "<table cellspacing=\"0\" cellpadding=\"1\" border=\"0\" width=\"600\">\n";

  $output .= "<tr valign=\"top\">\n";
  if (($payutils::query{'image-link'} ne "") && ($payutils::query{'image-placement'} eq "left")) {
    $output .= "<td rowspan=\"50\"><img src=\"$payutils::query{'image-link'}\"></td>\n";
  }
  else {
    $output .= "<td width=\"50\" rowspan=\"50\"> &nbsp; </td>\n";
  }
  $output .= "<td width=\"125\" class=\"short\"> &nbsp; </td>\n";
  $output .= "<td width=\"425\" class=\"short\"> &nbsp; </td>\n";
  $output .= "</tr>\n";

  if (($payutils::query{'image-link'} ne "") && ($payutils::query{'image-placement'} eq "table")) {
    $output .= "<tr><td colspan=\"2\">\n";
    $output .= "<div align=\"center\">\n";
    $output .= "<img src=\"$payutils::query{'image-link'}\">\n";
    $output .= "</div></tr>\n\n";
  }

  $output .= "\n";

  return $output;
}

sub pay_swipe_tail {
  my $output = '';

  my $submit_label = "";
  if ($payutils::feature{'submit_pg1'} ne "") {
    $submit_label = "$payutils::feature{'submit_pg1'}";
  } else {
    $submit_label = "$payutils::lang_titles{'submitpay'}[$payutils::lang]";
  }
  $output .= "<tr><td align=\"left\" colspan=2>";
  $output .= "&nbsp;<br>\n";
  $output .= "<b>We appreciate your patience while your order is processed. It should take less than 1 minute.</b><p>\n";
  $output .= "Please press the \"$submit_label\" only once to prevent any potential double billing.\n";

  if (($payutils::query{'from-email'} ne "") || ($payutils::query{'publisher-email'} ne "")) {
    $output .= "If you have a problem please email us at <a href=\"mailto:\n";
    if ($payutils::query{'from-email'} ne "") {
      $output .= "$payutils::query{'from-email'}\">$payutils::query{'from-email'}</a>.\n";
    }
    else {
      $output .= "$payutils::query{'publisher-email'}\">$payutils::query{'publisher-email'}</a>.\n";
    }
    $output .= "Please give your full name, order number (if you received a purchase confirmation), ";
    $output .= "and the exact nature of the problem.\n";
  }
  $output .= "<br>&nbsp;\n";

  $output .= "<span id=\"processingStatement\" class=\"badcolor larger\"></span>\n";
  $output .= "</td></tr>\n";

  $output .= "\n";
  $output .= "<tr><td></td><td align=\"left\">";
  if ($payutils::feature{'indicate_processing'} ne "") {
    $output .= "<input type=\"submit\" value=\"$submit_label\" onClick=\"is_processing('true');\">";
  }
  else {
    $output .= "<input type=\"submit\" value=\"$submit_label\">";
  }
  if ($payutils::newswipecode == 1) {
    $output .= " <input type=\"reset\" value=\"$payutils::lang_titles{'reset'}[$payutils::lang]\" onClick=\"document.pay.reset();document.pay.card_number.focus();\"></td></tr>\n";
  }
  else {
    $output .= " <input type=\"reset\" value=\"$payutils::lang_titles{'reset'}[$payutils::lang]\" onClick=\"document.keyswipe1.reset();document.keyswipe1.in1.focus();\"></td></tr>\n";
  }

  $output .= "</table>\n";
  $output .= "</form>\n";
  $output .= "</div>\n\n";

  $output .= "</body>\n";
  $output .= "</html>";

  return $output;
}


sub record_usps_error {
  my ($error,$tagname,%query) = @_;
  open (DEBUG,'>>',"/home/p/pay1/database/debug/usps_debug.txt");
  print DEBUG "TAGNAME:$tagname\n";
  foreach my $key (sort keys %query) {
    if ($key =~ /(cvv|number)/i) {
      next;
    }
    print DEBUG "$key:$query{$key}, ";
  }
  print DEBUG "\n$error\n";
  close (DEBUG);
  return;
}


sub mobileHead {
  my $output = '';

  $output .= "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">\n";

  $output .= "<html xmlns=\"http://www.w3.org/1999/xhtml\">\n";

  $output .= "<head>\n";
  $output .= "  <title>Plug n Pay</title>\n";
  $output .= "  <meta name=\"viewport\" content=\"width=320; initial-scale=1.0; maximum-scale=1.0; user-scalable=0;\"/>\n";
  $output .= "  <link rel=\"apple-touch-icon\" href=\"/javascript/iui/pnpicon.png\" />\n";
  $output .= "  <meta name=\"apple-touch-fullscreen\" content=\"YES\" />\n";

  my $pay_template_home = "$payutils::path_web/css/$payutils::query{'client'}/";
  my $publishername = $payutils::query{'publisher-name'};
  $publishername =~ s/[^0-9a-zA-Z]//g;
  my $css_path = "";
  if (-e "$payutils::path_web/logos/upload/css/$payutils::query{'publisher-name'}\_mobile.css") {
    $css_path = "/logos/upload/css/$payutils::query{'publisher-name'}\_mobile.css";
  }
  elsif (-e "$pay_template_home/$publishername\_mobile.css") {
    $css_path = "/css/$payutils::query{'client'}/$publishername\_mobile.css";
  }
  elsif(-e "$pay_template_home/cobrand/$payutils::feature{'cobrand'}\_mobile.css") {
    $css_path = "/css/$payutils::query{'client'}/cobrand/$payutils::feature{'cobrand'}\_mobile.css";
  }
  elsif(-e "$pay_template_home/reseller/$payutils::reseller\_mobile.css") {
    $css_path = "/css/$payutils::query{'client'}/reseller/$payutils::reseller\_mobile.css";
  }
  else {
    $css_path = "/css/$payutils::query{'client'}/iui.css";
  }
  $output .= "  <style type=\"text/css\" media=\"screen\">\@import \"$css_path\";</style>\n";


  $output .= "  <script type=\"text/javascript\" charset=\"utf-8\" src=\"/javascript/jquery.min.js\"></script>\n";
  $output .= "  <script type=\"text/javascript\" charset=\"utf-8\" src=\"/javascript/iui/mobilefunctions.js\"></script>\n";

  $output .= "\n\n<!--  START OF CUSTOMIZEABLE HEAD SECTION --> \n\n";
  if ($payutils::template{'head_mobile'} ne "") {
    $output .= "$payutils::template{'head_mobile'}\n";
  }
  $output .= "\n\n<!--  END OF CUSTOMIZEABLE HEAD SECTION --> \n\n";

  $output .= "</head>\n";

  return $output;
}

sub pay_mobile_badcard {
  my $output = '';

  if (($payutils::query{'MErrMsg'} ne "") || ($payutils::error{'dataentry'} ne "")) {
    $output .= "<fieldset>\n";
    $output .= "    <div class=\"error\">\n";

    if (($payutils::error{'dataentry'} =~ /minimum purchase of/i) && ($payutils::feature{'minpurchase'} ne "")) {
      $output .= "$payutils::error{'dataentry'}\n";
      return;
    }
    $output .= "$payutils::lang_titles{'infoproblem'}[$payutils::lang]\n";
    if (($payutils::query{'MErrMsg'} =~ /fails LUHN-10 check/) || ($payutils::query{'MErrMsg'} =~ /bad card/)) {
      $output .= "$payutils::lang_titles{'validcc'}[$payutils::lang] ";
      $payutils::color{'card-number'} = $payutils::badcolor;
    }
    elsif ($payutils::query{'MErrMsg'} =~ /did not respond in a timely manner/) {
      $output .= "$payutils::lang_titles{'sorry2'}[$payutils::lang] \n";
    }
    elsif ($payutils::query{'MErrMsg'} =~ /or are not configured to accept the card type used/) {
      $output .= "$payutils::lang_titles{'sorry1'}[$payutils::lang]\n";
      $payutils::color{'card-number'} = $payutils::badcolor;
      $payutils::color{'card-type'} = $payutils::badcolor;
    }
    elsif (($payutils::query{'MErrMsg'} =~ /Application agent not found/) && ($payutils::processor eq "intuit")) {
      $output .= "Application not registered in production environment at Intuit - contact your software provider.\n";
    }
    elsif (($payutils::chkprocessor eq "telecheck") && ($payutils::query{'accttype'} =~ /^(checking|savings)$/)) {
      if ($payutils::query{'resp-code'} =~ /^(08|88|73)$/) {
        $output .= "We are sorry that we cannot process additional electronic payments on your order. Our decision is based, in whole or in part, on information provided to us by TeleCheck. We encourage you to call TeleCheck at 1.877.678.5898 or write TeleCheck Customer Care at P.O. Box 4513, Houston, TX 77210-4513. Please provide TeleCheck your driver's license number and the state where it was issued, and the complete banking numbers printed on the bottom of your check. Under the Fair Credit Reporting Act, you have the right to a free copy of your information held in TeleCheck's files within 60 days from today. You may also dispute the accuracy or completeness of any information in TeleCheck's consumer report. TeleCheck did not make the adverse decision to not accept your payment item and is unable to explain why this decision was made.";
      }
      elsif ($payutils::query{'resp-code'} =~ /^(25)$/) {
        $output .= "We are unable to process this transaction with the payment information provided. Please use a different form of payment at this time.";
      }
      else {
        $output .= "We are unable to verify your checking account or identity information. Please review the information you entered to ensure that all information is correct.";
      }
    }
    else {
      if ($payutils::error{'dataentry'} ne "") {
        $output .= "$payutils::error{'dataentry'}\n";
        $output .= "$payutils::lang_titles{'re_enter2'}[$payutils::lang]";
      }
      else {
        if ($payutils::query{'paymethod'} eq "teleservice") {
          $output .= "$payutils::query{'MErrMsg'}\n";
        }
        else {
          my (@error_response) = split(/\|/,$payutils::query{'MErrMsg'});
          $output .= "$payutils::lang_titles{'declined'}[$payutils::lang]\n";
          foreach my $var (@error_response) {
            $output .= "$var\n";
          }
          $output .= "<br>\n";
          $output .= "$payutils::lang_titles{'incorrect'}[$payutils::lang]\n";
          $output .= "<br>\n";
          $output .= "$payutils::lang_titles{'inerror'}[$payutils::lang]\n";
          $output .= "<br>\n";
        }
      }
    }
    $output .= "</div>\n";
    $output .= "  </fieldset>\n";
  }
  else {
    if (($payutils::error >= 1) && ($payutils::query{'pass'} == 1)) {
      $output .= "<fieldset>\n";
      $output .= "  <div class=\"error\">\n";
      $output .= "    $payutils::lang_titles{'reqinfo'}[$payutils::lang]\n";
      $output .= "  </div>\n";
      $output .= "</fieldset>\n";
    }
  }

  return $output;
}


sub pay_mobile_table {
  my $output = '';

  my ($discount, $discount_type);

  my ($columns);

  #items
  $output .= "<div class=\"itemtable\">\n";
  for (my $j=1; $j<=$payutils::max; $j++) {
    $output .= "<label>$payutils::quantity[$j] $payutils::description[$j]</label>\n";
    $output .= sprintf ("<span>$payutils::query{'currency_symbol'}%.2f</span>\n",$payutils::ext[$j]);
    $output .= "<br>\n";
  }
  $output .= "</div>\n";

  #subtotal
  $payutils::subtotal = &Round($payutils::subtotal);
  $output .= "<div class=\"itemtable\">\n";
  $output .= "<label>$payutils::lang_titles{'subtotal'}[$payutils::lang]</label>\n";
  $output .= sprintf("<span>$payutils::query{'currency_symbol'}%.2f</span>\n", $payutils::subtotal);

  if ($payutils::query{'shipmethod'} ne "") {
    $payutils::query{'card-amount'} = $payutils::subtotal + $payutils::query{'tax'} + $payutils::query{'handling'};
  }
  else {
    $payutils::query{'card-amount'} = $payutils::subtotal + $payutils::query{'shipping'} + $payutils::query{'tax'} + $payutils::query{'handling'};
  }

  #tax
  if ($payutils::query{'tax'} > 0) {
    $output .= "<br>\n";
    $output .= "<label>$payutils::lang_titles{'tax'}[$payutils::lang]</label>\n";
    $output .= sprintf("<span>$payutils::query{'currency_symbol'}%.2f</span>\n", $payutils::query{'tax'});
    $output .= "<br>\n";
  }
  else {
    $output .= "<br>\n";
  }

    my $display_total = $payutils::query{'card-amount'};
    $output .= "</div>\n";

    #total
    $output .= "  <div class=\"itemtable\">\n";
    $output .= "    <label>$payutils::lang_titles{'total'}[$payutils::lang]</label>\n";
    $output .= sprintf("    <span>$payutils::query{'currency_symbol'}%.2f</span>\n", $display_total);
    $output .= "    <br>\n";
    $output .= "  </div>\n";

    return $output;
}


sub pay_mobile_billing {
  my $output = '';

  $output .= "<body>\n";

  $output .= "\n\n<!--  START OF CUSTOMIZEABLE TOP SECTION --> \n\n";

  if ($payutils::template{'top_mobile'} ne "") {
    $output .= "$payutils::template{'top_mobile'}\n";
  }
  $output .= "\n\n<!--  END OF CUSTOMIZEABLE TOP SECTION --> \n\n";

  $output .= "  <div class=\"toolbar\">\n";
  $output .= "  </div>\n";
  if ($payutils::feature{'mobilesummary'} == 1) { # use summary page
    $output .= "  <form novalidate title=\"Plug n Pay\" name=\"mobilepay\" class=\"panel\" action=\"$payutils::query{'path_cgi'}\" method=\"post\" selected=\"true\">\n";
  }
  else {
    $output .= "  <form novalidate title=\"Plug n Pay\" name=\"mobilepay\" class=\"panel\" action=\"$payutils::query{'path_invoice_cgi'}\" method=\"post\" selected=\"true\">\n";
  }
  $output .= "      <input type=\"hidden\" id=\"magensacc\" name=\"magensacc\" value=\"\" />\n";
  $output .= "      <input type=\"hidden\" name=\"EncTrack1\" id=\"EncTrack1\" value=\"\">\n";
  $output .= "      <input type=\"hidden\" name=\"EncTrack2\" id=\"EncTrack2\" value=\"\">\n";
  $output .= "      <input type=\"hidden\" name=\"EncTrack3\" id=\"EncTrack3\" value=\"\">\n";
  $output .= "      <input type=\"hidden\" name=\"EncMP\" id=\"EncMP\" value=\"\">\n";
  $output .= "      <input type=\"hidden\" name=\"KSN\" id=\"KSN\" value=\"\">\n";
  $output .= "      <input type=\"hidden\" name=\"devicesn\" id=\"devicesn\" value=\"\">\n";
  $output .= "      <input type=\"hidden\" name=\"MPStatus\" id=\"MPStatus\" value=\"\">\n";
  $output .= "      <input type=\"hidden\" name=\"MagnePrintStatus\" id=\"MagnePrintStatus\" value=\"\">\n";

  if ($payutils::query{'client'} eq "mobile") {
    &pay_mobile_badcard();
  }

  if ($payutils::query{'publisher-name'} =~ /^(demoapps|demouser)$/) {
    $output .= "<div class=\"demomessage\" id=\"demomessage\">\n";
    $output .= "<p>This app is currently using a demo account. This account is for demonstration purposes only. DO NOT enter valid credit card information. To run a test transaction, use the card number that is already entered.</p>\n";
    $output .= "<p>Please note that this message will not appear when using a non-demo account.</p>\n";
    $output .= "<span id=\"hideme\">Tap here to close this message</span>\n";
    $output .= "</div>\n";
  }

  if (($payutils::query{'askamtflg'} != 1) && ($payutils::query{'client'} eq "mobile") && ($payutils::query{'easycart'} ne "1")) { # for non-app use
    $output .= "      <h1>Amount to be charged: $payutils::query{'currency_symbol'}$payutils::query{'card-amount'}</h1><br\>\n";
  }

  $output .= "<fieldset>\n";
  if ($payutils::query{'easycart'} eq "1") {
      &pay_mobile_table(); # needs to be called here so that it's within the form
  }
  else {
    if (($payutils::query{'client'} eq "mobileapp") || ($payutils::query{'askamtflg'} == 1)) { # for non-app use
       $output .= "          <div class=\"row\">\n";
       $output .= "              <label>Amount:*</label>\n";
       $output .= "              <input type=\"tel\" pattern=\"[0-9]*\" id=\"card_amount\" name=\"card_amount\" value=\"$payutils::query{'card-amount'}\"/>\n";
       $output .= "          </div>\n";
    }
  }
  $output .= "</fieldset>\n";

  $output .= "      <h2>Payment Information:</h2>\n";
  $output .= "      <fieldset>\n";
  $output .= "          <div class=\"row\">\n";
  $output .= "              <label>Name:</label>\n";
  $output .= "              <input type=\"text\" name=\"card_name\" id=\"card_name\" value=\"$payutils::query{'card-name'}\"/>\n";
  $output .= "          </div>\n";
  $output .= "          <div class=\"row\">\n";
  $output .= "              <label>Card #:*</label>\n";
  if ($payutils::query{'publisher-name'} =~ /^(demoapps|demouser)$/) {
     $output .= "              <input type=\"tel\" pattern=\"[0-9]*\" name=\"card_number\" id=\"card_number\" value=\"4111111111111111\" autocomplete=\"off\"/>\n";
  }
  else {
     $output .= "              <input type=\"tel\" pattern=\"[0-9]*\" name=\"card_number\" id=\"card_number\" value=\"$payutils::query{'card-number'}\" autocomplete=\"off\"/>\n";
  }
  $output .= "          </div>\n";
  $output .= "          <div class=\"row\">\n";
  $output .= "              <label>Exp Date:*</label>\n";
  $output .= "              <div class=\"smallselect\">\n";
  $output .= "                <select id=\"month_exp\" name=\"month_exp\">\n";
  my @months = ("01","02","03","04","05","06","07","08","09","10","11","12");
  my ($date) = &miscutils::gendatetime_only();
  my $current_month = substr($date,4,2);
  my $current_year = substr($date,0,4);
  if ($payutils::query{'month-exp'} eq "") {
     $output .= "                            <option value=\"\" selected>$payutils::lang_titles{'month'}[$payutils::lang]</option>\n";
  }
  foreach my $var (@months) {
     if ($var eq $payutils::query{'month-exp'}) {
       $output .= "                          <option value=\"$var\" selected>$var</option>\n";
     }
     else {
       $output .= "                          <option value=\"$var\">$var</option>\n";
     }
  }
  $output .= "                </select>\n";
  $output .= "                <select id=\"year_exp\" name=\"year_exp\">\n";
  if ($payutils::query{'year_exp'} eq ""){
     $output .= "                            <option value=\"\" selected>$payutils::lang_titles{'year'}[$payutils::lang]</option>\n";
  }
  for (my $i; $i<=12; $i++) {
     my $var = $current_year + $i;
     my $val = substr($var,2,2);
     if ($val eq $payutils::query{'year-exp'}) {
        $output .= "                         <option value=\"$val\" selected>$var</option>\n";
     }
     else {
        $output .= "                         <option value=\"$val\">$var</option>\n";
     }
  }
  $output .= "                </select>\n";
  $output .= "              </div>\n";
  $output .= "          </div>\n";

  if (($payutils::feature{'cvv'} == 1) || ($payutils::query{'cvv-flag'} eq "yes")) {
      $output .= "          <div class=\"row\">\n";
      $output .= "              <label>CVV #:*</label>\n";
      $output .= "              <input type=\"tel\" pattern=\"[0-9]*\" id=\"card_cvv\" name=\"card_cvv\" value=\"$payutils::query{'card-cvv'}\" autocomplete=\"off\"/>\n";
      $output .= "          </div>\n";
  }
  if ($payutils::query{'client'} =~ /mobileapp/) {
    if ($payutils::feature{'suppressmobilepay'} !~ /acct_code/) {
      $output .= "          <div class=\"row\">\n";
      $output .= "              <label>Acct Code:</label>\n";
      $output .= "              <input type=\"text\" id=\"acct_code\" name=\"acct_code\" value=\"$payutils::query{'acct_code'}\"/>\n";
      $output .= "          </div>\n";
    }
  }

  $output .= "      </fieldset>\n";

  $output .= "      <h2>Address Information:</h2>\n";
  $output .= "      <fieldset>\n";
  if ($payutils::feature{'suppressmobilepay'} !~ /card_address1/) {
    $output .= "          <div class=\"row\">\n";
    $output .= "              <label>Address:</label>\n";
    $output .= "              <input type=\"text\" id=\"card_address1\" name=\"card_address1\" value=\"$payutils::query{'card-address1'}\"/>\n";
    $output .= "          </div>\n";
  }
  if ($payutils::feature{'suppressmobilepay'} !~ /card_address2/) {
    $output .= "          <div class=\"row\">\n";
    $output .= "              <label>Address 2:</label>\n";
    $output .= "              <input type=\"text\" id=\"card_address2\" name=\"card_address2\" value=\"$payutils::query{'card-address2'}\"/>\n";
    $output .= "          </div>\n";
  }
  if ($payutils::feature{'suppressmobilepay'} !~ /card_city/) {
    $output .= "          <div class=\"row\">\n";
    $output .= "              <label>City:</label>\n";
    $output .= "              <input type=\"text\" id=\"card_city\" name=\"card_city\" value=\"$payutils::query{'card-city'}\"/>\n";
    $output .= "          </div>\n";
  }
  if ($payutils::feature{'suppressmobilepay'} !~ /card_state/) {
    $output .= "          <div class=\"row\">\n";
    $output .= "              <label>State:</label>\n";
    $output .= "              <select id=\"card_state\" name=\"card_state\">\n";
    my %selected = ();
    $selected{$payutils::query{'card-state'}} = " selected";
    $output .= "               <option value=\"$payutils::query{'card_state'}\">State/Province</option>\n";
    foreach my $key (&sort_hash(\%constants::USstates)) {
      if ($constants::USstates{$key} =~ /^Select Your/) {
        next;
      }
      $output .= "             <option value=\"$key\"$selected{$key}>$constants::USstates{$key}</option>\n";
    }
    foreach my $key (sort keys %constants::USterritories) {
      $output .= "             <option value=\"$key\"$selected{$key}>$constants::USterritories{$key}</option>\n";
    }
    foreach my $key (sort keys %constants::CNprovinces) {
      if ($constants::CNprovinces{$key} =~ /Country other than/) {
        next;
      }
      $output .= "             <option value=\"$key\"$selected{$key}>$constants::CNprovinces{$key}</option>\n";
    }
    $output .= "               <option value=\"ZZ\">Other than USA/CANADA</option>\n";
    $output .= "              </select>\n";
    $output .= "          </div>\n";
  }
  if ($payutils::feature{'suppressmobilepay'} !~ /card_zip/) {
    $output .= "          <div class=\"row\">\n";
    $output .= "              <label>Zip:</label>\n";
    $output .= "              <input type=\"text\" id=\"card_zip\" name=\"card_zip\" value=\"$payutils::query{'card-zip'}\"/>\n";
    $output .= "          </div>\n";
  }
  if ($payutils::feature{'suppressmobilepay'} !~ /card_prov/) {
    $output .= "          <div class=\"row\">\n";
    $output .= "              <label>Int'l Prov.:</label>\n";
    $output .= "              <input type=\"text\" id=\"card_prov\" name=\"card_prov\" value=\"$payutils::query{'card-prov'}\"/>\n";
    $output .= "          </div>\n";
  }
  if ($payutils::feature{'suppressmobilepay'} !~ /card_country/) {
    $output .= "          <div class=\"row\">\n";
    $output .= "              <label>Country:</label>\n";
    $output .= "              <select id=\"card_country\" name=\"card_country\">\n";
    my %selected = ();
    $selected{$payutils::query{'card-country'}} = " selected";
    foreach my $key (sort_hash(\%constants::countries)) {
      $output .= "                     <option value=\"$key\"$selected{$key}>$constants::countries{$key}</option>\n";
    }
    $output .= "              </select>\n";
    $output .= "           </div>\n";
  }
  if ($payutils::feature{'suppressmobilepay'} !~ /email/) {
    $output .= "          <div class=\"row\">\n";
    $output .= "              <label>Email:</label>\n";
    $output .= "              <input type=\"email\" id=\"email\" name=\"email\" value=\"$payutils::query{'email'}\"/>\n";
    $output .= "          </div>\n";
  }
  if ($payutils::feature{'suppressmobilepay'} !~ /phone/) {
    $output .= "          <div class=\"row\">\n";
    $output .= "              <label>Phone:</label>\n";
    $output .= "              <input type=\"tel\" id=\"phone\" name=\"phone\" value=\"$payutils::query{'phone'}\"/>\n";
    $output .= "          </div>\n";
  }
  $output .= "      </fieldset>\n";

  return $output;
}


sub mobileTail {
  my $output = '';
  $output .= "      <div id=\"processingStatement\" class=\"processing\" style=\"display:none\">Please wait while processing...</div>\n";
  my $submitbuttonvalue;
  if ($payutils::feature{'mobilesummary'} == 1) {
     $submitbuttonvalue = "Continue";
  }
  else {
     $submitbuttonvalue = "Submit";
  }
  # DCP 20120203 REmoved Name Attribute from Submit Button.
  $output .= "      <div id=\"showbutton\" style=\"display:block\">\n";
  if ($payutils::feature{'minpurchase'} ne "") {
    $output .= "      <input type=\"submit\" class=\"whiteButton\" id=\"submit\" value=\"$submitbuttonvalue\" onClick=\"return checkform() && minAmountCheck($payutils::feature{'minpurchase'}) && isCreditCard(this.form.card_number.value) && is_processing('true')\">\n";
  }
  else {
    $output .= "      <input type=\"submit\" class=\"whiteButton\" id=\"submit\" value=\"$submitbuttonvalue\" onClick=\"return checkform() && isCreditCard(this.form.card_number.value) && is_processing('true')\">\n";
  }
  $output .= "      </div>\n";
  $output .= "  </form>\n";

  $output .= "\n\n<!--  START OF CUSTOMIZEABLE TAIL SECTION --> \n\n";
  if ($payutils::template{'tail_mobile'} ne "") {
    $output .= "$payutils::template{'tail_mobile'}\n";
  }
  $output .= "\n\n<!--  END OF CUSTOMIZEABLE TAIL SECTION --> \n\n";

  $output .= "</body>\n";
  $output .= "</html>\n";
}

sub mobileSummaryPageTail {
  my $output = '';
  $output .= "      <div id=\"processingStatement\" class=\"processing\" style=\"display:none\">Please wait while processing...</div>\n";
  $output .= "      <div id=\"showbutton\" style=\"display:block\">\n";
  $output .= "      <input type=\"submit\" class=\"whiteButton\" id=\"submit\" value=\"Submit\" onClick=\"return is_processing('true')\">\n";
  $output .= "      </div>\n";
  $output .= "  </form>\n";

  $output .= "\n\n<!--  START OF CUSTOMIZEABLE TAIL SECTION --> \n\n";
  if ($payutils::template{'tail_mobile'} ne "") {
    $output .= "$payutils::template{'tail_mobile'}\n";
  }
  $output .= "\n\n<!--  END OF CUSTOMIZEABLE TAIL SECTION --> \n\n";

  $output .= "</body>\n";
  $output .= "</html>\n";
  return $output;
}


sub pay_mobile_summary {
  my $output = '';

  $output .= "<body>\n";

  $output .= "\n\n<!--  START OF CUSTOMIZEABLE TOP SECTION --> \n\n";

  if ($payutils::template{'top_mobile'} ne "") {
    $output .= "$payutils::template{'top_mobile'}\n";
  }
  $output .= "\n\n<!--  END OF CUSTOMIZEABLE TOP SECTION --> \n\n";

  $output .= "  <div class=\"toolbar\">\n";
  $output .= "  </div>\n";
  $output .= "  <form novalidate title=\"Plug n Pay\" name=\"mobilepay\" class=\"panel\" action=\"$payutils::query{'path_invoice_cgi'}\" method=\"post\" selected=\"true\">\n";
  $output .= "      <input type=\"hidden\" id=\"magensacc\" name=\"magensacc\" value=\"\" />\n";
  $output .= "      <input type=\"hidden\" name=\"EncTrack1\" id=\"EncTrack1\" value=\"\">\n";
  $output .= "      <input type=\"hidden\" name=\"EncTrack2\" id=\"EncTrack2\" value=\"\">\n";
  $output .= "      <input type=\"hidden\" name=\"EncTrack3\" id=\"EncTrack3\" value=\"\">\n";
  $output .= "      <input type=\"hidden\" name=\"EncMP\" id=\"EncMP\" value=\"\">\n";
  $output .= "      <input type=\"hidden\" name=\"KSN\" id=\"KSN\" value=\"\">\n";
  $output .= "      <input type=\"hidden\" name=\"devicesn\" id=\"devicesn\" value=\"\">\n";
  $output .= "      <input type=\"hidden\" name=\"MPStatus\" id=\"MPStatus\" value=\"\">\n";
  $output .= "      <input type=\"hidden\" name=\"MagnePrintStatus\" id=\"MagnePrintStatus\" value=\"\">\n";

  if ($payutils::query{'client'} eq "mobile") {
    &pay_mobile_badcard();
  }

  if (($payutils::query{'card-amount'} ne "") && ($payutils::query{'client'} eq "mobile") && ($payutils::query{'easycart'} ne "1")) { # for non-app use
    $output .= "      <h1>Amount to be charged: $payutils::query{'currency_symbol'}$payutils::query{'card-amount'}</h1><br\>\n";
  }

  $output .= "<fieldset>\n";
  if ($payutils::query{'easycart'} eq "1") {
      &pay_mobile_table();
  }
  $output .= "</fieldset>\n";

  $output .= "<h2>Payment Information:</h2>\n";
  $output .= "<fieldset>\n";
  $output .= "    <div class=\"itemtable\">\n";
  $output .= "        <label><span id=\"card_name_summ\">$payutils::query{'card-name'}</span></label><br>\n";
  $output .= "        <br>\n";
  if ($payutils::query{'card-number'} ne "") {
    # copied from standard summary page
    my $last4 = substr($payutils::query{'card-number'},-4);
    my $nice_number = $payutils::query{'card-number'};
    $nice_number =~ s/[0-9]/X/g;
    $nice_number = substr($nice_number,0,length($nice_number)-4) . $last4;
    my $cardexp = "$payutils::query{'month-exp'}/$payutils::query{'year-exp'}";
    if ($payutils::feature{'maskexp'} == 1) {
        $cardexp =~ s/\d/X/g;
    }
  $output .= "        <label><span id=\"card_number_summ\">$nice_number</span></label><br>\n";
  $output .= "        <label><span id=\"card_exp_summ\">Exp. $cardexp</span></label><br>\n";
  $output .= "    </div>\n";
  }
  $output .= "</fieldset>\n";

  $output .= "<h2>Address Information:</h2>\n";
  $output .= "<fieldset>\n";
  $output .= "    <div class=\"itemtable\">\n";
  if ($payutils::feature{'suppressmobilepay'} !~ /card_address1/) {
    $output .= "        <label><span id=\"card_address1_summ\">$payutils::query{'card-address1'}</span></label>\n";
    $output .= "        <br>\n";
  }
  if (($payutils::feature{'suppressmobilepay'} !~ /card_address2/) && ($payutils::query{'card-address2'} ne "")) {
    $output .= "        <label><span id=\"card_address2_summ\">$payutils::query{'card-address2'}</span></label>\n";
    $output .= "        <br>\n";
  }
  if (($payutils::feature{'suppressmobilepay'} !~ /card_city/) || ($payutils::feature{'suppressmobilepay'} !~ /card_state/) || ($payutils::feature{'suppressmobilepay'} !~ /card_zip/)) {
    $output .= "        <label><span id=\"card_city_summ\">$payutils::query{'card-city'}</span>, <span id=\"card_state_summ\">$payutils::query{'card-state'}</span> <span id=\"card_zip_summ\">$payutils::query{'card-zip'}</span></label>\n";
    $output .= "        <br>\n";
  }
  if (($payutils::feature{'suppressmobilepay'} !~ /card_prov/) && ($payutils::query{'card-prov'} ne "")) {
    $output .= "        <label><span id=\"card_prov_summ\">$payutils::query{'card-prov'}</span></label>\n";
    $output .= "        <br>\n";
  }
  if ($payutils::feature{'suppressmobilepay'} !~ /card_country/) {
    $output .= "        <label><span id=\"card_country_summ\">$payutils::query{'card-country'}</span></label>\n";
    $output .= "        <br>\n";
  }
  if ($payutils::feature{'suppressmobilepay'} !~ /email/) {
    $output .= "        <label><span id=\"email_summ\">$payutils::query{'email'}</span></label>\n";
    $output .= "        <br>\n";
  }
  if (($payutils::feature{'suppressmobilepay'} !~ /phone/) && ($payutils::query{'phone'} ne "")) {
    $output .= "        <label><span id=\"card_phone_summ\">$payutils::query{'phone'}</span></label>\n";
    $output .= "        <br>\n";
  }

  $output .= "    </div>\n";
  $output .= "</fieldset>\n";

  return $output;
}


sub conv_fee {

  my (%feerules,@feerules,$feeamt);

  ## Rule Format FAILRULE, TYPE, FEEACCT, AMT|PERCENT|FIXED,AMT|PERCENT|FIXED,AMT|PERCENT|FIXED ....
  ## TYPE =  STEP, FULL or SUBMT   STEP  applies fee depending on amount in each fee bucket.  FULL applies fee to full amount. SUBMT, Fee is SUBMiTted with tran
  ## FAILRULE = IGN or VOID  IGN = leave primary transaction alone if Conv Fee tran fails. (default)  VOID = Void primary if Conv Fee fails.
  #$mckutils::feature{'conv_fee'} = "IGN,STEP,100.00|.025|1.00,400|.0225|1.00,800|.0215|1.00,all|.02|1.00";

  my ($feerules);

  if ($payutils::query{'paymethod'} =~ /^(onlinecheck|check)$/i) {
    $feerules = $payutils::feature{'conv_fee_ach'};
  }
  else {
    $feerules = $payutils::feature{'conv_fee'};
  }

  $feerules =~ s/[^a-zA-Z0-9\.\:\|]//g;
  @feerules = split('\:',$feerules);

  my $failrule = shift(@feerules);
  $failrule =~ s/[^a-zA-Z0-9]//g;

  my $ruletype = shift(@feerules);
  $ruletype =~ s/[^a-zA-Z0-9]//g;

  my $fee_acct = shift(@feerules);
  $fee_acct =~ s/[^a-zA-Z0-9]//g;
  $fee_acct =~ tr/A-Z/a-z/;

  ## Calculate Fee Amt
  #if ($ruletype =~ /^SUBMT$/i) {
  # $feeamt = $payutils::query{'convfeeamt'};
  #}
  if (($ruletype =~ /^SUBMT$/i) || ($payutils::query{'convfeeamt'} > 0)) {
   $feeamt = $payutils::query{'convfeeamt'};
  }
  ## RuleType = STEP
  elsif ($ruletype =~ /^STEP$/i) {
    my ($oldamt, $calcamt);
    my $tstamt = $payutils::query{'card-amount'};
    foreach my $bucket (@feerules) {
      my ($amt,$per,$fix) = split('\|',$bucket);
      if (($amt =~ /^ALL$/i) || ($amt > $payutils::query{'card-amount'})) {
        $feeamt += (($payutils::query{'card-amount'} - $oldamt) * $per) + $fix;
        $feeamt = sprintf("%.2f",$feeamt+0.0001);
        $tstamt -= $amt;
        last;
      }
      elsif ($payutils::query{'card-amount'} >= $amt) {
        $calcamt = $amt - $oldamt;
        $feeamt += (($amt - $oldamt) * $per) + $fix;
        $feeamt = sprintf("%.2f",$feeamt+0.0001);
        if ($payutils::query{'card-amount'} - $amt < .01) {
          last;
        }
      }
      $oldamt = $amt;
    }
  }
  ## RuleType = FULL
  else {
    foreach my $bucket (@feerules) {
      my ($amt,$per,$fix) = split('\|',$bucket);
      if (($amt =~ /^ALL$/i) || ($amt >= $payutils::query{'card-amount'})) {
        $feeamt = ($payutils::query{'card-amount'} * $per) + $fix;
        $feeamt = sprintf("%.2f",$feeamt+0.0001);
        last;
      }
    }
  }
  #&database();

  return $feeamt, $fee_acct, $failrule;
}


sub parse_template {
  my($line) = @_;
  if ($line !~ /\[pnp_/) {
    return $line;
  }
  $line =~ s/\r\n//g;
  my $parsecount = 0;
  while ($line =~ /\[pnp\_([0-9a-zA-Z-+_]*)\]/) {
    my $query_field = $1;
    $parsecount++;
    if ($payutils::query{$query_field} ne "") {
      if ($query_field =~ /^(card-number|card_number|card-exp|card_exp|accountnum|routingnum)$/) {
        $line =~ s/\[pnp\_([0-9a-zA-Z-+]*)\]/FILTERED/;
      }
      elsif ($query_field =~ /^(subtotal|tax|shipping|handling|discnt)$/) {
        $line =~ s/\[pnp_$query_field\]/sprintf("%.2f", $payutils::query{$query_field})/e;
      }
      else {
        $line =~ s/\[pnp\_$query_field\]/$payutils::query{$query_field}/;
      }
    }
    elsif ($query_field =~ /^(orderID)$/) {
      $line =~ s/\[pnp_$query_field\]/$payutils::orderID/e;
    }
    else {
      $line =~ s/\[pnp\_$query_field\]//;
    }
    if ($parsecount >= 10) {
      return $line;
    }
  } # end while
  return $line;
}

sub payment_plans {
  my(%query1) = @_;
  my ($stuff,$database,%payplans);
  ($query1{'plan'},$stuff) = split(':',$query1{'plan'});

  if ($query1{'merchantdb'} ne "") {
    $database = $query1{'merchantdb'};
  }
  else {
    $database = $query1{'publisher-name'};
  }
  $database =~ s/[^0-9a-zA-Z]//g;

  my $path_plans = "$payutils::path_web/payment/recurring/$database/admin/paymentplans.txt";
  my ($parseflag,$i);
  if (-e $path_plans) {
    &sysutils::filelog("read","$path_plans");
    open(PAYPLANS,'<',"$path_plans") || die "Cannot Open payment Plans\n\n";
    my (@fields);
    while(<PAYPLANS>) {
      chop;
      my @data = split('\t');
      if (substr($data[0],0,1) eq "\!") {
        $parseflag = 1;
        (@fields) = (@data);
        $fields[0] = substr($data[0],1);
        next;
      }
      if ($parseflag == 1) {
        my ($i);
        foreach my $var (@fields) {
          $var =~ tr/A-Z/a-z/;
          if ($var ne "plan") {
            $query1{$var} = $data[$i];
            $payplans{$var} = $data[$i];
          }
          $i++;
        }

        if ($query1{'rquantity'} > 1) {
          $query1{'card-amount'} = sprintf("%.2f", $query1{'card-amount'} * $query1{'rquantity'});
        }

        my ($plan,$stuff) = split(':',$query1{'planid'});
        if (($fields[0] =~ /plan/i) && ($query1{'plan'} eq $plan)) {
          $query1{'plan'} = $query1{'planid'};
          last;
        }
      }
    }
  }
  if (exists $query1{'card-amount'}) {
    $query1{'card-amount'} =~ tr/A-Z/a-z/;
    if ($query1{'card-amount'} =~ /^[a-z]{3} .+/) {
      ($query1{'currency'},$query1{'card-amount'})  = split(/ /,$query1{'card-amount'});
    }
    $query1{'card-amount'} =~ s/[^0-9\.]//g;
    $query1{'card-amount'} = sprintf("%.2f", $query1{'card-amount'});
  }
  return %query1;
}

sub balance_check {
  my @now = gmtime(time);
  my $exp = sprintf("%02d/%2d", $now[4]+1, substr(($now[5]+1900),2,2));
  my $tmpoid = PlugNPay::Transaction::TransactionProcessor::generateOrderID();

  $payutils::query{'mpgiftcard'} =~ s/\D//g;

  my @array = (
    "publisher-name","$payutils::query{'publisher-name'}",
    "mode","auth",
    "card-amount","0",
    "card-exp", "$exp",
    "transflags","balance,gift",
    "orderID", "$tmpoid",
    "mpgiftcard","$payutils::query{'mpgiftcard'}"
  );

  require mckutils_strict;
  my $payment = mckutils->new(@array);
  my %result = $payment->purchase("auth");
  $result{'auth-code'} = substr($result{'auth-code'},0,6);

  $payment->database();

  if ($result{'FinalStatus'} =~ /success/i) {
    if ($result{'balance'} >= $payutils::query{'card-amount'}) {
      return $result{'FinalStatus'}, $result{'balance'};
    }
    else {
      return 'badcard', $result{'balance'};
    }
  }
  else {
    return 'problem';
  }
}

sub store_pairs {
  my $env = new PlugNPay::Environment();
  my $remoteIP = $env->get('PNP_CLIENT_IP');
  my(@unknownParameters) = @_;

  if (@unknownParameters == 0) {
    return '';
  }

  ## Log


  {
    my $time = gmtime(time());
    open (DEBUG,'>>',"/home/p/pay1/database/debug/store_pairs_debug.txt");
    print DEBUG "TIME:$time, UN:$payutils::query{'publisher-name'}, RA:$remoteIP, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, PID:$$\n";
    close(DEBUG);
  }

  ## Generate Row Ref and Time Stamp
  my $id = PlugNPay::Transaction::TransactionProcessor::generateOrderID();
  my ($datestr,$timestr) = &miscutils::gendatetime_only();
  my $rowref = $payutils::query{'publisher-name'} . $id;

  my @insert_array1 = ();
  my @insert_array2 = ();
  my $qstr1 = "INSERT INTO paypairs (rowref,trans_time,name,value) VALUES ";
  my $qstr2 = "INSERT INTO paypairs (rowref,trans_time,name,valtxt) VALUES ";

  foreach my $var (@unknownParameters) {
    my $value = $payutils::query{$var};
    my $valtxt = "";
    $var =~ s/(\W)/'%' . unpack("H2",$1)/ge;
    $value =~ s/(\W)/'%' . unpack("H2",$1)/ge;
    if (length($value) > 254) {
      $qstr2 .= "\n(?,?,?,?),";
      push (@insert_array2,"$rowref","$timestr","$var","$valtxt");
    }
    else {
      $qstr1 .= "\n(?,?,?,?),";
      push (@insert_array1,"$rowref","$timestr","$var","$value");
    }
  }
  chop $qstr1;
  chop $qstr2;

  ### InsertData -  Do we need to erase first?
  my $dbh = &miscutils::dbhconnect("pnpmisc");

  if (@insert_array1 > 0) {
    my $sth = $dbh->prepare(qq{$qstr1}) or die "Can't prepare: $DBI::errstr";
    $sth->execute(@insert_array1) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%mckutils::query);
    $sth->finish;
  }

  if (@insert_array2 > 0) {
    my $sth = $dbh->prepare(qq{$qstr2}) or die "Can't prepare: $DBI::errstr";
    $sth->execute(@insert_array2) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%mckutils::query);
    $sth->finish;
  }

  $dbh->disconnect;

  return $rowref;
}

sub cardcharge {
  require PlugNPay::COA;
  require PlugNPay::Environment;
  require PlugNPay::Country::State;

  my $adjustment = 0;
  my $Total = $payutils::query{'card-amount'};

  my $BIN = '000000000000';
  if ($payutils::query{'paymethod'} !~ /^(onlinecheck|check)$/i) {
    $BIN = substr($payutils::query{'card-number'},0,12);
  }

  if ($payutils::query{'cardcharge_adjustment'} eq "") {
    my $env = new PlugNPay::Environment($payutils::query{'publisher-name'});
    my $coa = new PlugNPay::COA($payutils::query{'publisher-name'});

    # allow surcharge in all states by default
    my $stateCanSurcharge = 1;

    # if merchant only surcharges in states that allow it, check if state allows it
    if ($coa->isSurcharge() && $coa->getCheckCustomerState()) {
      my $stateObj = new PlugNPay::Country::State();
      my $billingState = $payutils::query{'card-state'};
      $stateObj->setState($billingState);
      $stateCanSurcharge = $stateObj->getCanSurcharge();
    }

    if ($stateCanSurcharge) {
      my $resp = $coa->get($BIN,$Total);

      if ($payutils::query{'paymethod'} =~ /^(onlinecheck|check)$/i) {
        $adjustment = $$resp{'achAdjustment'};
      } else {
        $adjustment = $$resp{'adjustment'};
      }
      my $type = $$resp{'type'};
      my $message = $$resp{'message'};
    }
  }
  else {
    $adjustment = $payutils::query{'cardcharge_adjustment'};
  }
  $adjustment = &Round($adjustment);

  return $adjustment;
}

1;
