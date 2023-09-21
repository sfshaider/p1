package remote;

use strict;
use DBI;
use rsautils;
use miscutils;
use mckutils_strict;
use MD5;
use SHA;
use sysutils;
use constants qw(%convert_countries);
use CGI qw/:standard/;
use NetAddr::IP;
use smpsutils;
use PlugNPay::GatewayAccount;
use PlugNPay::CreditCard;
use PlugNPay::OnlineCheck;
use PlugNPay::Email;
use Apache2::RequestUtil;
use PlugNPay::Transaction::Loader;
use PlugNPay::Transaction::MapLegacy;
use PlugNPay::Logging::DataLog;
use PlugNPay::GatewayAccount::InternalID;
use PlugNPay::Order::Loader;
use PlugNPay::Processor;
use PlugNPay::Processor::Account;
use PlugNPay::Transaction::Loader::History;
use PlugNPay::Transaction::Logging::Adjustment;
use PlugNPay::CardData;
use PlugNPay::ConvenienceFee;
use PlugNPay::COA;
use PlugNPay::Token;
use PlugNPay::Sys::Time;
use PlugNPay::Environment;
use PlugNPay::Transaction::Receipt;
use PlugNPay::API;
use PlugNPay::Transaction;
use PlugNPay::Transaction::MapAPI;
use PlugNPay::Transaction::Response;
use PlugNPay::Features;
use PlugNPay::Util::StackTrace;
use PlugNPay::Util::Hash;
use PlugNPay::Util::Array qw(inArray);
use PlugNPay::Transaction::TransactionProcessor;
use PlugNPay::Transaction::TransactionRouting;
use PlugNPay::Processor::Route::LegacyChecks;
use PlugNPay::GatewayAccount::LinkedAccounts;
use PlugNPay::GatewayAccount::Services;
use PlugNPay::Debug;


##  Error Code Table
#   P00
#
#
#   P98
#   P99

#print "Content-Type: text/html\n\n";
sub testRemoteStrict {
  return 1;
}

sub new {
  my $type = shift;
  my %query = @_;
  delete $query{'FinalStatus'};
  delete $query{'MStatus'};

  %remote::times = ();
  %remote::security = ();
  %remote::feature = ();
  %remote::masked = ();

  $remote::noreturns = "";
  $remote::processor = "";
  $remote::chkprocessor = "";

  $remote::times{time()} = "start_new";

  $remote::logall = "yes";
  $remote::member_dbasetype = "mysql";
  $remote::summarizeflg = "";
  $remote::tranqueactive = "";
  $remote::tranque = "";

  my $env = new PlugNPay::Environment();
  my $remote_ip = $env->get('PNP_CLIENT_IP');

  my $r;
  my %headers;
  eval {
    $r = Apache2::RequestUtil->request;
  };

  if ($r) {
    my $aprHeaders = $r->headers_in;
    my %headTemp = map uc, %{\%$aprHeaders};
    foreach my $key (keys %headTemp) {
      my $val = $headTemp{$key};
      $val =~ s/[^0-9A-Z\)\(\,\;\:\ \-\_]//g;
      $key =~ s/[^A-Z\-\_]//g;
      $headers{$key} = $val;
    }
  }
  $ENV{'SSL_PROTOCOL'} = $headers{'X-SSL_PROTOCOL'};
  $ENV{'SSL_CIPHER'} = $headers{'X-SSL_CIPHER'};

  if (exists $ENV{'MOD_PERL'}) {
    $remote::pid = $$;
  }
  else {
    $remote::pid = getppid();
  }

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
  $remote::now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
  my $filemon = sprintf("%02d",$mon+1);
  $remote::time = time();

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


  $remote::path_debug = "/home/p/pay1/database/remotepm_debug$weekno$filemon\.txt";

  local $remote::version = "20051017.00001";

  $remote::remoteaddr = $remote_ip;

  %remote::altaccts = ('icommerceg',["icommerceg","icgoceanba","icgcrossco"],'pnpdev',["pnpdemo"],'captivecus',["pnpdemo","intelligens","wolfcoffeec"],'dietsmar',["dietsmar","dietsmar2"],'motisllc5',["motisllc5","motiswoodf","motisredwo","motishumb","motiscards"]);

  %remote::registered_ips = ();

  #if (($ENV{'PNP_REMOTE_CLIENT'} ne "") && ($ENV{'PNP_REMOTE_MODE'} ne "")) {
  #  $query{'client'} = $ENV{'PNP_REMOTE_CLIENT'};
  #  $query{'mode'} = $ENV{'PNP_REMOTE_MODE'};
  #}

  ## CreditRequestFlag Filter
  if (exists $query{'creditrequestflag'}) {
    $query{'creditrequestflag'} =~ s/[^0-1]//g;
  }

  # Client filter
  if ($query{'client'} ne "") {
    $query{'client'} =~ s/[^0-9a-zA-Z]//g;
  }

  # Subacct Filter
  if ($query{'subacct'} ne "") {
    $query{'subacct'} =~ s/[^0-9a-zA-Z]//g;
  }
  ## App-Level Filter
  if (exists $query{'app-level'}) {
    $query{'app-level'} =~ s/[^0-9\-]//g;
  }

  ## Acct Code Filter
  if (exists $query{'acct_code'}) {
    $query{'acct_code'} =~ s/[^A-Za-z0-9:,\-\. _\$\|\#]//g;
  }
  if (exists $query{'acct_code2'}) {
    $query{'acct_code2'} =~ s/[^A-Za-z0-9:,\-\. _\$\|\#]//g;
  }
  if (exists $query{'acct_code3'}) {
    $query{'acct_code3'} =~ s/[^A-Za-z0-9:,\-\. _\$\|\#]//g;
  }
  if (exists $query{'acct_code4'}) {
    $query{'acct_code4'} =~ s/[^A-Za-z0-9:,\-\. _\$\|\#]//g;
  }

  ## Free Form Filter
  if (exists $query{'freeform'}) {
    $query{'freeeform'} =~ s/[^A-Za-z0-9:,\-\. _]//g;
  }

  my @array = %query;

  if (($query{'client'} =~ /coldfusion/i) || ($query{'CLIENT'} =~ /coldfusion/i)) {
    %query = &input_cold_fusion(@array);
  }
  elsif ($query{'client'} =~ /softcart/i) {
    $query{'easycart'} = "1";
  }
  elsif ($query{'client'} =~ /^miva/i) {
    %query = &input_miva(@array);
  }
  elsif ($query{'client'} =~ /cart32/i) {
    %query = &input_cart32(@array);
  }
  elsif ( ($query{'client'} =~ /^authnet$/i)
          || ((exists $query{'x_Login'} || exists $query{'x_login'}) && (exists $query{'x_Version'} || exists $query{'x_version'})
             && (exists $query{'x_ADC_Relay_Response'} || exists $query{'x_adc_relay_response'} || exists $query{'x_Relay_Response'} || exists $query{'x_relay_response'}))
          || ((exists $query{'x_Login'} || exists $query{'x_login'}) && (exists $query{'x_Version'} || exists $query{'x_version'})
             && (exists $query{'x_ADC_URL'} || exists $query{'x_adc_url'} || exists $query{'x_relay_url'} || exists $query{'x_Relay_URL'}))
  ) {
    %query = &input_authnet(@array);
  }
  elsif (($query{'client'} eq "authnetcp" ) || (exists $query{'x_cpversion'})) {
    %query = &input_authnet_cp(@array);
  }
  elsif ( ($query{'client'} =~ /^achdirect$/i) || ((exists $query{'pg_merchant_id'}) && (exists $query{'pg_password'}) && (exists $query{'pg_transaction_type'})) ) {
    %query = &input_achdirect(@array);
  }
  elsif ((exists $query{'magstripe'}) && (! exists $query{'card-number'})) {
    %query = &input_swipe(@array);
  }
  elsif ((exists $query{'ewallet_id'}) && ($query{'ewallet_id'} =~ /\d*\=\d*/)) {
    %query = &input_ewallet(@array);
  }
  elsif ( $query{'client'} eq "dydacomp1" ) {
    %query = &input_dydacomp(@array);
  }

  if ($query{'convert'} =~ /underscores/i) {
    %query = &underscore_to_hyphen(@array);
  }

  if ( ( ($query{'magensacc'} ne "") || (($query{'devicesn'} ne "") && ($query{'KSN'} ne "")) )  && ($query{'mode'} =~ /^(bill_member|add_member|update_member|query_member|query_member_fuzzy)$/) ) {
    my %input = ();

    $query{'magensacc'} =~ s/[^0-9A-iZa-z\|\%\^\/\?\=\;\:]//g;
    $query{'devicesn'} =~ s/[^0-9A-Za-z]//g;
    $query{'KSN'} =~ s/[^0-9A-Za-z]//g;
    $query{'Track1'} =~ s/[^0-9A-iZa-z\|\%\^\/\?\=\;\:]//g;
    $query{'EncTrack1'} =~ s/[^0-9A-Za-z]//g;
    $query{'EncTrack2'} =~ s/[^0-9A-Za-z]//g;
    $query{'EncTrack3'} =~ s/[^0-9A-Za-z]//g;
    $query{'EncMP'} =~ s/[^0-9A-Za-z]//g;
    $query{'MPStatus'} =~ s/[^0-9A-Za-z]//g;

    my @magensa_variables = ('magensacc','devicesn','KSN','Track1','EncTrack1','EncTrack1','EncTrack1','EncMP','MPStatus','card-exp','swipedevice');
    foreach my $var (@magensa_variables) {
      if ((defined $query{$var}) && ($query{$var} ne "")) {
        $input{$var} = $query{$var};
      }
    }

    require magensa;
    my %results = &magensa::decrypt("$query{'magensacc'}",\%input);
    $query{'card-number'} = $results{'PAN'};
    $query{'card-exp'} = $results{'card-exp'};
  }

  if ( ( ($query{'magensacc_2'} ne "") || (($query{'devicesn_2'} ne "") && ($query{'KSN_2'} ne "")) )  && ($query{'mode'} =~ /^(bill_member|add_member|update_member|query_member|query_member_fuzzy)$/) ) {
    my %input = ();

    $query{'magensacc_2'} =~ s/[^0-9A-iZa-z\|\%\^\/\?\=\;\:]//g;
    $query{'devicesn_2'} =~ s/[^0-9A-Za-z]//g;
    $query{'KSN_2'} =~ s/[^0-9A-Za-z]//g;
    $query{'Track1_2'} =~ s/[^0-9A-iZa-z\|\%\^\/\?\=\;\:]//g;
    $query{'EncTrack1_2'} =~ s/[^0-9A-Za-z]//g;
    $query{'EncTrack2_2'} =~ s/[^0-9A-Za-z]//g;
    $query{'EncTrack3_2'} =~ s/[^0-9A-Za-z]//g;
    $query{'EncMP_2'} =~ s/[^0-9A-Za-z]//g;
    $query{'MPStatus_2'} =~ s/[^0-9A-Za-z]//g;

    my @magensa_variables = ('magensacc','devicesn','KSN','Track1','EncTrack1','EncTrack1','EncTrack1','EncMP','MPStatus','card-exp');
    foreach my $var (@magensa_variables) {
      if ((defined $query{"$var\_2"}) && ($query{"$var\_2"} ne "")) {
        $input{$var} = $query{"$var\_2"};
      }
    }

    require magensa;
    my %results = &magensa::decrypt("$query{'magensacc_2'}",\%input);
    $query{'card-number2'} = $results{'PAN'};
    $query{'card-exp2'} = $results{'card-exp'};
  }

  if ($query{'client'} =~ /^(Omni3750|Vx610)/i) {
    $query{'posflag'} = "1";
  }
  else {
    delete $query{'posflag'};
  }

  if (($query{'merchant'} ne "") && ($query{'publisher-name'} eq "")) {
    $query{'publisher-name'} = $query{'merchant'};
  }
  else {
    $query{'merchant'} = $query{'publisher-name'};
  }

  $query{'publisher-name'} = substr($query{'publisher-name'},0,12);
  $query{'merchant'} = substr($query{'merchant'},0,12);

  $remote::gatewayAccount = new PlugNPay::GatewayAccount($query{'merchant'});
  $remote::accountFeatures = $remote::gatewayAccount->getFeatures();
  %remote::feature = %{$remote::accountFeatures->getFeatures()};


  if (($remote::accountFeatures->get('enableToken') == 1) && ($query{'paymentToken'} ne "")) {  ###  Temporary until token server fully operational 20170405
    my $cc = new PlugNPay::Token();
    my $redeemedToken = $cc->fromToken($query{'paymentToken'},'PROCESSING');
    $redeemedToken  =~ s/%(..)/pack('c',hex($1))/eg;
    $redeemedToken =~ s/\+/ /g;
    if ($redeemedToken =~ /(\d+) (\d+)/) {
      my ($routingnum,$accountnum) = split(/ /,$redeemedToken);
      my $ach = new PlugNPay::OnlineCheck();
      $ach->setABARoutingNumber($routingnum);
      $ach->setAccountNumber($accountnum);
      if ($ach->verifyABARoutingNumber()) {
        $query{'routingnum'} = $routingnum;
        $query{'accountnum'} = $accountnum;
      }
    }
    else {
      my $cc = new PlugNPay::CreditCard($redeemedToken);
      if (cardIsPotentiallyValid($cc)) {
        $query{'card-number'} = $redeemedToken;
      }
    }
  }

  ## Decrypt Flag Security Retriction  ###  DCP 20090929
  if ((exists $query{'decryptflag'}) && ($query{'publisher-name'} =~ /(pnpdemo|onestepdem|avrdev|shopkeep)/)) {
    delete $query{'decryptflag'};
  }

  # orderID filter
  if ($query{'orderID'} ne "") {
    $query{'orderID'} =~ s/[^0-9]//g;
    #$query{'orderID'} = substr($query{'orderID'},0,29);
  }

  # Card number filter
  if ($query{'card-number'} ne "") {
    $query{'card-number'} =~ s/[^0-9]//g;
    $query{'card-number'} = substr($query{'card-number'},0,20);
  }

  # ABA Routing number filter
  if ($query{'routingnum'} ne "") {
    $query{'routingnum'} =~ s/[^0-9]//g;
    $query{'routingnum'} = substr($query{'routingnum'},0,9);
  }

  # Bank Account number filter
  if ($query{'accountnum'} ne "") {
    $query{'accountnum'} =~ s/[^0-9]//g;
    $query{'accountnum'} = substr($query{'accountnum'},0,20);
  }

  # Membership Username filter
  if (($query{'username'} ne "")  && ($query{'mode'} =~ /(add_member|delete_member|cancel_member|update_member|query_member|query_billing|passwrdtest|bill_member)/)) {
    $query{'username'} =~ s/[^0-9a-zA-Z\@\.\-\_]//g;
  }

  # Currency filter
  if (exists $query{'currency'}) {
    $query{'currency'} =~ tr/A-Z/a-z/;
    $query{'currency'} =~ s/[^a-z]//g;
    $query{'currency'} = substr($query{'currency'},0,3);
  }

  ## Address filters
  #if (exists $query{'card-address1'}) {
  #  $query{'card-address1'} =~ s/[\r\n]//;
  #  $query{'card-address1'} =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\']/x/g;
  #}

  #if (exists $query{'card-address2'}) {
  #  $query{'card-address2'} =~ s/[\r\n]//;
  #  $query{'card-address2'} =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\']/x/g;
  #}

  if (exists $query{'card-city'}) {
    $query{'card-city'} =~ s/[^a-zA-Z0-9\.\-\' ]/ /g;
  }
  if (exists $query{'card-state'}) {
    $query{'card-state'} =~ s/[^a-zA-Z\' ]/ /g;
  }
  if (exists $query{'card-zip'}) {
    $query{'card-zip'} =~ s/[^a-zA-Z\'0-9 ]/ /g;
  }
  if (exists $query{'card-country'}) {
    $query{'card-country'} =~ s/[^a-zA-Z\' ]/ /g;
  }
  if (exists $query{'card-address1'}) {
    $query{'card-address1'} =~ s/[\r\n]//;
    $query{'card-address1'} =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;
  }
  if (exists $query{'card-address2'}) {
    $query{'card-address2'} =~ s/[\r\n]//;
    $query{'card-address2'} =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;
  }
  if (exists $query{'city'}) {
    $query{'city'} =~ s/[^a-zA-Z0-9\.\-\' ]/ /g;
  }
  if (exists $query{'state'}) {
    $query{'state'} =~ s/[^a-zA-Z\' ]/ /g;
  }
  if (exists $query{'zip'}) {
    $query{'zip'} =~ s/[^a-zA-Z\'0-9 ]/ /g;
  }
  if (exists $query{'country'}) {
    $query{'country'} =~ s/[^a-zA-Z\' ]/ /g;
  }
  if (exists $query{'address1'}) {
    $query{'address1'} =~ s/[\r\n]//;
    $query{'address1'} =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;
  }
  if (exists $query{'address2'}) {
    $query{'address2'} =~ s/[\r\n]//;
    $query{'address2'} =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;
  }

  # Country filter
  if (exists $query{'card-country'}) {
    $query{'card-country'} =~ tr/a-z/A-Z/;
    if (length($query{'card-country'}) > 3) {
      my $test = $query{'card-country'};
      if (exists $constants::convert_countries{$test}) {
        $query{'card-country'} = $constants::convert_countries{$test};
      }
    }
    #  Commented out to rethink requirement 01/18/2004
    #else {
    #  $query{'card-country'} = substr($query{'card-country'},0,2);
    #}
  }

  # Currency Set
  if (($query{'currency'} eq "") && (($query{'mode'} =~ /^(mark|void|credit|newreturn|auth)$/) || ($query{'mode'} eq ""))) {
    $query{'currency'} = "usd";
  }

  if (length($query{'country'}) > 3) {
    my $test = $query{'country'};
    $test =~ tr/a-z/A-Z/;
    if (exists $constants::convert_countries{$test}) {
      $query{'country'} = $constants::convert_countries{$test};
    }
  }

  # Card CVV filter
  if (exists $query{'card-cvv'}) {
    $query{'card-cvv'} =~ s/[^0-9]//g;
    #if ($query{'card-cvv'} =~ /^(3|4|5|6)/ ) {
    #  $query{'card-cvv'} = substr($query{'card-cvv'}, length($query{'card-cvv'}) - 3, 3);
    #}
    #if ((length($query{'card-cvv'}) == 4) && (substr($query{'card-cvv'},0,1) == 0)) {
    #  $query{'card-cvv'} = substr($query{'card-cvv'},1);
    #}
  }

  # Expiration Date Filter

  if (exists $query{'card-exp'}) {
    $query{'card-exp'} =~ s/[^0-9\/]//g;
    if ($query{'card-exp'} =~ /^\d+\/\d+\/\d+$/) {
      my ($mo,$dy,$yr) = split(/\/+/,$query{'card-exp'});
      $mo = sprintf("%02d",substr($mo,-2));
      $yr = sprintf("%02d",substr($yr,-2));
      $query{'card-exp'} = $mo . "/" . $yr;
    }
    elsif ($query{'card-exp'} =~ /\//) {
      #my ($mo,$yr) = split('/',$query{'card-exp'});
      my ($mo,$yr) = split(/\/+/,$query{'card-exp'});
      $mo = sprintf("%02d",substr($mo,-2));
      $yr = sprintf("%02d",substr($yr,-2));
      $query{'card-exp'} = $mo . "/" . $yr;
    }
  }
  if (exists $query{'card-exp'}) {
    my $card_exp = $query{'card-exp'};
    $card_exp =~ s/[^0-9]//g;
    my $length = length($card_exp);
    my $year = substr($card_exp,-2);
    if ($length >= 4) {
      $query{'card-exp'} = substr($card_exp,0,2) . "/" . $year;
    }
    elsif ($length == 3) {
      $query{'card-exp'} = "0" . substr($card_exp,0,1) . "/" . $year;
    }
  }

  if (exists $query{'month-exp'}) {
    $query{'month-exp'} = substr($query{'month-exp'},0,2);
  }

  if (exists $query{'year-exp'}) {
    $query{'year-exp'} = substr($query{'year-exp'},0,2);
  }

  # Card Amount Filter
  if ($query{'card-amount'} ne "") {
    $query{'card-amount'} =~ s/[^0-9\.]//g;
    $query{'card-amount'} = sprintf("%.2f", $query{'card-amount'} + 0.0001);
    if ($query{'currency'} ne "usd") {
      if (length($query{'card-amount'}) > 12 || $remote::accountFeatures->get('highflg') eq '1') {
        $query{'card-amount'} = substr($query{'card-amount'},-12);
      }
    }
    else {
      if (length($query{'card-amount'}) > 9) {
        $query{'card-amount'} = substr($query{'card-amount'},-9);
      }
    }
  }

  # Email Address Filter
  if (exists $query{'email'}) {
    $query{'email'} =~ s/\;/\,/g;
    $query{'email'} =~ s/[^_0-9a-zA-Z\-\@\.\,\+\#\&\*]//g;
    $query{'email'} =~ s/@[@.,_-]*/@/g;
    $query{'email'} =~ tr/A-Z/a-z/;
    $query{'email'} =~ s/,(com|org|net|mil|gov|tv|cc|ws|info|biz|bz)$/\.$1/;
  }

  # Rempasswd filter
  if (exists $query{'rempasswd'}) {
    $query{'rempasswd'} =~ s/[^a-zA-Z0-9\.]//g;
  }

  # ipaddress filter
  if (exists $query{'ipaddress'}) {
    $query{'ipaddress'} =~ s/[^0-9\.]//g;
    if ($query{'ipaddress'} !~ /^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$/) {
      $query{'ipaddress'} = "";
    }
  }

  if (($query{'merchant'} ne "") && ($query{'publisher-name'} eq "")) {
    $query{'publisher-name'} = $query{'merchant'};
  }
  else {
    $query{'merchant'} = $query{'publisher-name'};
  }

  if (!PlugNPay::Environment::isContainer()) {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
    my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
    open(DEBUG,">>$remote::path_debug");
    print DEBUG "DATE:$now, IP:$remote::remoteaddr, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, BROWSER:$ENV{'HTTP_USER_AGENT'}, PID:$remote::pid, RM:$ENV{'REQUEST_METHOD'}, SSLCIPHER:$ENV{'SSL_CIPHER'}, SSLPROTOCOL:$ENV{'SSL_PROTOCOL'}, ";
    foreach my $key (sort keys %query) {
      my $maskableMerchantVariables = $remote::accountFeatures->get('mask_merchant_variables');
      if ($key =~ /card.num|accountnum|acct_num|ccno/i) {
        my $tmpCC = substr($query{$key},0,6) . ('X' x (length($query{$key})-8)) . substr($query{$key},-2); # Format: first6, X's, last2
        $remote::masked{$key} = $query{$key};
        print DEBUG "$key:$tmpCC, ";
      }
      elsif (($key =~ /card/i) && ($key =~ /num/i)) {
        my $tmpCC = substr($query{$key},0,6) . ('X' x (length($query{$key})-8)) . substr($query{$key},-2); # Format: first6, X's, last2
        $remote::masked{$key} = $query{$key};
        print DEBUG "$key:$tmpCC, ";
      }
      elsif (($key =~ /^(TrakData|magstripe)$/i) && ($query{$key} ne "")) {
        $remote::masked{$key} = $query{$key};
        print DEBUG "$key:Data Present:" . substr($query{$key},0,6) . "****" . "0000" . ", ";
      }
      elsif (($key =~ /^(data)$/i) && ($query{$key} ne "")) {
        print DEBUG "$key:Batch File Present:, ";
      }
      elsif ($key =~ /(cvv|publisher.password|x_password|x_tran_key|card.code|passwd)/i) {
        my $aaaa = $query{$key};
        $aaaa =~ s/./X/g;
        $remote::masked{$key} = $query{$key};
        #if (($query{'publisher-name'} eq "lunavineya") && ($key eq "publisher-password")) {
        #  $aaaa = $query{$key};
        #}
        print DEBUG "$key:$aaaa, ";
      }
      elsif (($key =~ /^(ssnum|ssnum4)$/i) || ($key =~ /^($maskableMerchantVariables)$/)) {
        # mask all, but last 4 chars within field value
        my $val = ('X' x (length($query{$key})-4)) . substr($query{$key},-4,4);
        print DEBUG "$key:$val, ";
      }
      else {
        my ($key1,$val) = &logfilter_in($key,$query{$key});
        print DEBUG "$key1:$val, ";
      }

    }
    print DEBUG "\n\n";
    close(DEBUG);
  }

  # publisher-name/password filters
  $query{'publisher-name'} =~ s/[^0-9a-zA-Z]//g;

  if ($query{'publisher-name'} eq "") {
    my %result;
    $result{'FinalStatus'} = "problem";
    $result{'MStatus'} = "failure";
    $result{'MErrMsg'} = "Missing merchant/publisher name.";
    $result{'resp-code'} = "P98";
    my @array = ("",%result);
    if (($query{'pnp_proto'} =~ /pnpxml/i) || ($query{'client'} =~ /pnpxml/i)) {
      &output_pnpxml(@array);
      exit;
    }
    print header( -type=>'text/html');  ### DCP 20100716
    #print "Content-Type: text/html\n\n";
    &script_output(@array);
    exit;
  }


  if (-e "/home/p/pay1/outagefiles/returnproblem.txt") {  ### DCP 20170414
    my %result;
    $result{'FinalStatus'} = "problem";
    $result{'MStatus'} = "problem";
    $result{'MErrMsg'} = "System Down forMaintenance.";
    $result{'resp-code'} = "P150";
    my @array = ("",%result);
    if (($query{'pnp_proto'} =~ /pnpxml/i) || ($query{'client'} =~ /pnpxml/i)) {
      &output_pnpxml(@array);
      exit;
    }
    print header( -type=>'text/html');  ### DCP 20100716
    &script_output(@array);
    exit;

  }


  if ($query{'shipsame'} eq "yes") {
    $query{'shipname'} = $query{'card-name'};
    $query{'address1'} = $query{'card-address1'};
    $query{'address2'} = $query{'card-address2'};
    $query{'city'} = $query{'card-city'};
    $query{'state'} = $query{'card-state'};
    $query{'province'} = $query{'card-prov'};
    $query{'zip'} = $query{'card-zip'};
    $query{'country'} = $query{'card-country'};
  }

  if (($query{'card-amount'} < 0) && ($query{'taxstate'} ne "") && ($query{'taxrate'} ne "") && ($query{'subtotal'} > 0)) {
    @array = %query;
    %query = &taxcalc(@array);
  }
  %remote::query = %query;

  if (-e "/home/p/pay1/batchfiles/$query{'mode'}\_multi.txt")  {
    if (($query{'num-txns'} > 1) && ($query{'parallelproc'} eq "yes") && ($query{'mode'} =~ /^(batchauth|batchcommit)$/)) {
      require tranque;
      $remote::tranque = tranque->new(\%query);
      $remote::tranqueactive = $remote::tranque->check_tranque();
    }
  }

  $remote::times{time()} = "end_new";

  return [], $type;
}

sub cardIsPotentiallyValid {
  my $cardObject = shift;
  if (ref($cardObject) != 'PlugNPay::CreditCard') {
    die("input is not a PlugNPay::CreditCard");
  }
  return !$cardObject->requiresLuhn10() || $cardObject->verifyLuhn10();
}

sub script_output {
  my $type = shift;
  my %query = @_;

  $remote::times{time()} = "start_output";

  if ($query{'Duplicate'} eq "yes") {
    $query{'card-amount'} =~ s/[^0-9\.]//g;
  }

  if (exists $query{'auth-code'}) {
    $query{'auth-code'} = substr($query{'auth-code'},0,6);
  }

  if ($query{'FinalStatus'} =~ /^(success|pending)$/) {
    $query{'success'} = "yes";
  }
  elsif ($query{'FinalStatus'} =~ /^(badcard|failure|fraud)$/) {
    $query{'success'} = "no";
  }
  else {
    $query{'success'} = "problem";
  }

  my $errmsg = $query{'MErrMsg'};

  $query{'auth-msg'} = $query{'aux-msg'} . " " . $query{'MErrMsg'};

  foreach my $key (keys %query) {
    if (($key =~ /^customname(\d+)/) && ($query{$key} ne "") && ($query{"customvalue$1"} ne "")) {
      $query{$query{$key}} = $query{"customvalue$1"}
    }
  }

  if ($query{'mode'} eq "comtest") {
    delete $query{'auth-msg'};
    delete $query{'success'};
  }

  my  @array = %query;

  if ($query{'client'} eq "palmpilot") {
    &palmpilot(@array);
  }
  elsif ($query{'client'} =~ /coldfusion/i) {
    %query = &output_cold_fusion(@array);
  }
  elsif ($query{'client'} =~ /miva/i) {
    %query = &output_miva(@array);
  }
  elsif ($query{'client'} =~ /^(authnet|dydacomp|dallasmust)$/i) {
    %query = &output_authnet(@array);
  }
  elsif ($query{'client'} =~ /^(authnetcp)$/i) {
    %query = &output_authnet_cp(@array);
  }
  elsif ($query{'client'} =~ /^mmnextel$/i) {
    &output_mmnextel(@array);
  }
  elsif (($query{'pnp_proto'} =~ /pnpxml/i) || ($query{'client'} =~ /pnpxml/i)) {
    &output_pnpxml(@array);
  }
  elsif ($query{'client'} =~ /^angelivr$/) {
    &output_angel(@array);
  }
  elsif ($query{'client'} =~ /^achdirect$/) {
    &output_achdirect(@array);
  }

  my $shortcc = substr($query{'card-number'},0,4) . '**' . substr($query{'card-number'},length($query{'card-number'})-2,2);
  $shortcc =~ s/(\W)/'%' . unpack("H2",$1)/ge;

  if ($query{'convert'} =~ /underscores/i) {
    my @array = %query;
    %query = &hyphen_to_underscore(@array);
  }

  my $qstr = "";
  foreach my $key (sort keys %query) {
    if (($key !~ /^card.number/i)
        #&& ($key !~ /^card.exp/i)
        && ($key !~ /.link$/i)
        && ($key !~ /^pindata$/i)
        && ($key !~ /merch.txn/i)
        && ($key !~ /cust.txn/i)
        && ($key !~ /month.exp/i)
        && ($key !~ /year.exp/i)
        && ($key !~ /card.cvv/i)
        && ($key !~ /publisher.password/i)
        && ($key !~ /magstripe/i)
        && ($key !~ /^MErrMsg$/i)
        && ($key !~ /^magensacc$/i)
        && ($key ne ""))
    {
      #print "$key:$query{$key}<br>\n";
      $query{$key} =~ s/(\W)/'%' . unpack("H2",$1)/ge;
      my $k = $key;
      $k =~ s/(\W)/'%' . unpack("H2",$1)/ge;
      if ($qstr ne "") {
        $qstr .= "\&$k\=$query{$key}";
      }
      else {
        $qstr .= "$k\=$query{$key}";
      }
    }
  }
  $errmsg =~ s/(\W)/'%' . unpack("H2",$1)/ge;
  if ($errmsg ne "") {
    if ($query{'client'} =~ /^(coldfusion|miva)/i) {
      $qstr .= "\&MERRMSG=$errmsg";
    }
    else {
      $qstr .= "\&MErrMsg=$errmsg";
    }
  }
  if ($query{'acct_code4'} =~ /^(authprev|returnprev)/) {
    if ($query{'convert'} =~ /underscores/i) {
      $qstr .= "\&card_number=$shortcc";
    }
    else {
      $qstr .= "\&card-number=$shortcc";
    }
  }
  $qstr .= "\&a=b";

  #if ((($query{'testmode'} =~ /debug/i) || ($query{'mode'} =~ /debug/i) || ($remote::logall eq "yes")) && ($query{'mode'} !~ /^query/i)) {
  if ( ($query{'testmode'} =~ /debug/i) || ($query{'mode'} =~ /debug/i) || ($remote::logall eq "yes") )  {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
    my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
    my $etime = time() - $remote::time;

    if ($remote::query{'elapsedTimePurchase'} > 0) {
      my $etimeDelta = $etime - $remote::query{'elapsedTimePurchase'};
      if ($etimeDelta > 60) {
        ### Notify
        my $msg = "Elapsed Time Mismatch: UN:$remote::query{'publisher-name'}, DELTA:$etimeDelta, TIME:$now, PID:$remote::pid, IP:$remote::remoteaddr";
        &alertEmail($msg);
      }
    }

    if (!PlugNPay::Environment::isContainer()) {
      open(DEBUG,">>$remote::path_debug");
      print DEBUG "DATE:$now, TIME:$etime, IP:$remote::remoteaddr, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, BROWSER:$ENV{'HTTP_USER_AGENT'}, PID:$remote::pid, VERSION:$remote::version, MODE:$query{'mode'}, ";
      if ($query{'mode'} !~ /^query|list/i) {
        my $featuresHash = $remote::accountFeatures->getFeatures();
        foreach my $key (sort keys %{$featuresHash}) {
          print DEBUG "F:$key:" .  $remote::accountFeatures->get($key) . ", ";
        }
        if ($remote::accountFeatures->get('show_env') == 1) {
          foreach my $key (sort keys %ENV) {
            print DEBUG "E:$key:$ENV{$key}, ";
          }
        }
        if (! -e "/home/p/pay1/database/debug/newlogfilter.txt") {
          my $logstr = "a=a&" . $qstr;
          $logstr =~ s/&([^=]+)=([^&]*)/&logfilter_out($1,$2)/ge;
          print DEBUG "ReturnStrng:$logstr:";
          print DEBUG "\n\n";
          close(DEBUG);
        }
        else {
          if ($query{'mode'} !~ /^query|authprev|returnprev|bill/i) {
            my $logstr = $qstr;
            foreach my $key (keys %remote::masked) {
              my $k = $key;
              $k =~ s/(\W)/'%' . unpack("H2",$1)/ge;
              if ($logstr =~ /($k.*?)\&/) {
                $logstr =~ s/$1/DATA_MASKED=DATA_MASKED/g;
              }
            }
            print DEBUG "ReturnStrng:$logstr:";
          }
          else {
            print DEBUG "FinalStatus:$query{'FinalStatus'}, MErrMsg:$query{'MErrMsg'}, card-amount:$query{'card-amount'}, orderID:$query{'orderID'}";
          }
        }
      }
      elsif ($query{'mode'} =~ /^query|list/i) {
        print DEBUG "FinalStatus:$query{'FinalStatus'}, MErrMsg:$query{'MErrMsg'}, AuthMsg:$query{'auth-msg'}, publisher-name:$query{'publisher-name'}, card-amount:$query{'card-amount'}, orderID:$query{'orderID'}, RCP:$remote::accountFeature->get('log_rc_password'), ";

        if (($query{'mode'} =~ /^query/i) && ($query{'orderID'} ne "")) {
          my $logstr = "a=a&" . $qstr;
          $logstr =~ s/&([^=]+)=([^&]*)/&logfilter_out($1,$2)/ge;
          print DEBUG "ReturnStrng:$logstr:";
        }

      }
      print DEBUG "\n\n";
      close(DEBUG);
    }
  }

  if ($query{'posflag'} == 1) {
    my $length = length($qstr);
    ##  DCP 20100714 - Replaced CT Line with CGI.pm.   CL header commented out previously on 20100711 to address header problems
    #print "Content-Length: $length\n";
    #print "Content-Type: text/html\n\n";
    print header( -type=>'text/html',-Content_length=>"$length" );
  }
  print "$qstr\n";

  $remote::times{time()} = "end_output";

  #&record_time(\%remote::times);

}

sub palmpilot {
  #my $type = shift;
  my (%query) = @_;
  #print "Content-Type: text/html\n\n";

  my %avs = ('A','Address matches - ZIP does not.',
        'E','Ineligible transaction.',
        'N','Neither Address nor ZIP matches.',
        'R','Retry - System Unavailable.',
        'S','Card Type Not Supported.',
        'U','Address Information Unavailable.',
        'W','Nine digit ZIP match - Address does not.',
        'X','Exact Match - Address and Nine digit ZIP.',
        'Y','Address and 5 digit ZIP match.',
        'Z','Five digit ZIP matches - address does not.'
       );

  print "<html>\n";
  print "<head>\n";
  print "<title><font size=\"-1\">PnP RemoteTerm</font></title>\n";
  print "<meta name=\"palmcomputingplatform\" content=\"true\">\n";
  print "</head>\n";
  print "<body>\n";
  print "<p><font size=\"4\">Final Status: $query{'FinalStatus'}</font><p>\n";
  if ($query{'FinalStatus'} eq "success") {
    print "<font size=\"2\">Auth Code: $query{'auth-code'}</font><p>\n";
    print "<font size=\"2\">AVS Response: $avs{$query{'avs-code'}}</font>\n";
  }
  else {
    print "<font size=\"2\">$query{'auth-msg'}</font>\n";
  }
  print "</body>\n";
  print "</html>\n";
  exit;
}

sub output_pnpxml {
  require xmlparse;
  if (0) {
    my $resp =  "Content-Type: text/xml\n\n";
    $resp .= &xmlparse::output_xml(@_);
    print $resp;
  }
  else {
    my $resp .= &xmlparse::output_xml(@_);
    my $length = length($resp);
    #print header( -type=>'text/xml',-Content_length=>"$length" );
    print header( -type=>'text/xml');
    print "$resp";
  }
  exit;
}

sub output_mmnextel {
  #my $type = shift;
  my (%query) = @_;

  if ($query{'FinalStatus'} ne "success") {
    $query{'auth-code'} = "Declined";
  }

  #my $resp =  "Content-Type: text/html\n\n";
  print header( -type=>'text/html');  ### DCP 20100716
  my $resp = "$query{'orderID'};$query{'auth-code'};$query{'MErrMsg'};";

  #my $resp =  "Content-Type: text/vnd.wap.wml\n\n";
  #$resp .=  "<?xml version=\"1.0\"?>\n";
  #$resp .=  "<!DOCTYPE wml PUBLIC \"-//WAPFORUM//DTD WML 1.1//EN\" \"http://www.wapforum.org/DTD/wml_1.1.xml\">\n";
  #$resp .=  "<wml>\n";
  #$resp .=  "      <card id=\"M1\">\n";
  #$resp .=  "            <!-- Autopost results using WML Script events. -->\n";
  #$resp .=  "            <onevent type=\"onenterforward\">  \n";
  #$resp .=  "                  <go href=\"$query{'CCRURL'}\" method=\"post\">\n";
  #$resp .=  "                        <postfield name=\"TransID\" value=\"$query{'orderID'}\"        />\n";
  #$resp .=  "                        <postfield name=\"REFNO\"   value=\"CCWAP\"         />\n";
  #$resp .=  "                        <postfield name=\"Auth\"    value=\"$query{'auth-code'}\"        />\n";
  #$resp .=  "                        <postfield name=\"Notes\"   value=\"$query{'MErrMsg'}\"        />\n";
  #$resp .=  "                  </go>\n";
  #$resp .=  "            </onevent>                                                           \n";
  #$resp .=  "            <onevent type=\"onenterbackward\">  \n";
  #$resp .=  "                  <go href=\"<% = CCRURL %>\" method=\"post\">\n";
  #$resp .=  "                        <postfield name=\"TransID\" value=\"$query{'orderID'}\"        />\n";
  #$resp .=  "                        <postfield name=\"REFNO\"   value=\"CCWAP\"         />\n";
  #$resp .=  "                        <postfield name=\"Auth\"    value=\"$query{'auth-code'}\"        />\n";
  #$resp .=  "                        <postfield name=\"Notes\"   value=\"$query{'MErrMsg'}\"        />\n";
  #$resp .=  "                  </go>\n";
  #$resp .=  "            </onevent>                                                          \n";
  #$resp .=  "      </card>\n";
  #$resp .=  "</wml> \n";

  print $resp;
  exit;
}

sub output_angel {
  my (%query) = @_;
  my ($status,$message);

  if ($query{'FinalStatus'} eq "success") {
    $status = "OK";
    $message = "Thank you, your payment has been approved.\n";
  }
  else {
    $status = "NOTOK";
    $message = "Sorry your payment has been declined for the following reason, $query{'MErrMsg'}.\n"
  }
  $query{'next_page'} =~ s/[^0-9\/]//g;

  #my $resp =  "Content-Type: text/xml\n\n";   ## DCP 20100716
  my $resp = "<ANGELXML>\n";
  $resp .= "<VARIABLES>\n";
  $resp .= "<VAR name=\"confirmation_number\" value=\"$query{'orderID'}\"/>\n";

  $resp .= "<VAR name=\"status\" value=\"$status\"/>\n";
  $resp .= "<VAR name=\"MErrMsg\" value=\"$query{'MErrMsg'}\"/>\n";
  $resp .= "</VARIABLES>\n";
  $resp .= "<MESSAGE>\n";
  $resp .= "<PLAY>\n";
  $resp .= "<PROMPT type=\"text\">\n";
  $resp .= "</PROMPT>\n";
  $resp .= "</PLAY>\n";
  $resp .= "<GOTO destination=\"$query{'next_page'}\" />\n";
  $resp .= "</MESSAGE>\n";
  $resp .= "</ANGELXML>\n";

  print header( -type=>'text/html');  ### DCP 20100716
  print $resp;
  exit;
}

sub passwrdtest {
  my (%query) = %remote::query;
  my ($database);
  my (%result);

  if ($query{'merchantdb'} ne "") {
    $database = $query{'merchantdb'};
  }
  else {
    $database = $query{'publisher-name'};
  }

  # Membership Management service, check if account has this service 
  # by checking if the database exists.
  my ( $dbh, $error ) = &checkDBExists($database);
  if ($error && !defined $dbh) {
    return &handleModeNotPermitted(\%result, $error);
  }
  
  my $sth = $dbh->prepare(qq{
      select username
      from customer
      where lower(username) = lower(?)
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute($remote::query{'username'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  my ($username) = $sth->fetchrow;
  $sth->finish;
  $dbh->disconnect;

  if ($username ne "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Username \"$remote::query{'username'}\" Already in Use - Please Re-enter.";
  }
  else {
    $result{'FinalStatus'} = "success";
  }
  return %result;
}

sub newreturn {
  my (@array) = %remote::query;
  my (%result,$operation,@extrafields);

  if (($remote::accountFeatures->get('multicurrency') == 1) && ($remote::query{'transflags'} !~ /multicurrency/)) {
    if (exists $remote::query{'transflags'} ) {
      $remote::query{'transflags'} .= ",multicurrency";
    }
    else {
      $remote::query{'transflags'} = "multicurrency";
    }
    @array = %remote::query;
  }

  if (($remote::query{'mpgiftcard'} ne "") && ($remote::query{'card-number'} eq "")) {
    $remote::query{'card-number'} = $remote::query{'mpgiftcard'};
    $remote::query{'card-cvv'} = $remote::query{'mpcvv'};
    @array = %remote::query;
  }

  my $payment = mckutils->new(@array);

  #if (($mckutils::cardtype eq "PL") && ($mckutils::query{'mpcvv'} ne "") && ($mckutils::query{'card-cvv'} eq "")) {
  #  $mckutils::query{'card-cvv'} = $mckutils::query{'mpcvv'};
  #}

  if (($mckutils::query{'walletid'} ne "") && ($mckutils::query{'passcode'} ne "")) {
    @extrafields = ('walletid',"$mckutils::query{'walletid'}",'passcode',"$mckutils::query{'passcode'}",'ipaddress',"$mckutils::query{'ipaddress'}");
  }
  if ($remote::processor =~ /emv$/) {
    $mckutils::query{'terminalnum'} =~ s/[^0-9]//g;
    push (@extrafields, 'terminalnum', $mckutils::query{'terminalnum'});
  }

  my %query = %mckutils::query;
  if ($query{'currency'} eq "") {
    $query{'currency'} = "usd";
  }
  my $addr = $query{'card-address1'} . " " . $query{'card-address2'};
  $addr = substr($addr,0,50);
  my $amount = $query{'card-amount'} + 0;
  my $price = sprintf("%3s %.2f","$query{'currency'}",$amount);
  my $country = substr($query{'card-country'},0,2);
  $query{'card-zip'} = substr($query{'card-zip'},0,10);

  if (($query{'accountnum'} ne "") && ($query{'routingnum'} ne "") && ($query{'accttype'} =~ /^(checking|savings)$/) ) {
    my $luhntest = &miscutils::mod10($query{'routingnum'});
    if ((length($query{'routingnum'}) != 9) || ($luhntest eq "failure")){
      %result = (%query,%result);
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} .= "Bank routing number failed mod10 test.";
      $result{'resp-code'} = "P53";
      return %result;
    }
    $query{'card-number'} = "$query{'routingnum'} $query{'accountnum'}";
  }

  if (($query{'creditrequestflag'} eq "1") || ($query{'mode'} eq "payment")) {
    $operation = "payment";
  }
  else {
    $operation = "return";
  }

  my $username = $query{'publisher-name'};
  %result = &miscutils::sendmserver("$username","$operation",
    'accttype',"$query{'accttype'}",
    'order-id', $query{'orderID'},
    'amount', $price,
    'card-number', $query{'card-number'},
    'card-name', $query{'card-name'},
    'card-address', $addr,
    'card-city', $query{'card-city'},
    'card-state', $query{'card-state'},
    'card-zip', $query{'card-zip'},
    'card-country', $country,
    'card-exp', $query{'card-exp'},
    'subacct', $query{'subacct'},
    'transflags', $query{'transflags'},
    'acct_code', $query{'acct_code'},
    'acct_code2', $query{'acct_code2'},
    'acct_code3', $query{'acct_code3'},
    'acct_code4', $query{'acct_code4'},
    'card-cvv', $query{'card-cvv'},
    @extrafields
  );

  if (($mckutils::dcc eq "yes") && ($result{'dccinfo'} ne "")) {
    #my @array = %query;
    my @array = (%query,%result);
    %result = (%result,&mckutils::dccmsg(@array));
    $result{'card-amount'} = $result{'native_amt'};
    $result{'currency'} = $result{'native_isocur'};
    $result{'currency_symbol'} = $result{'native_sym'};
  }

  %result = (%query,%result);
  return %result;
}

sub returnprev {
  my %query = %remote::query;
  my $username = $query{'publisher-name'};
  my $gatewayAccount = new PlugNPay::GatewayAccount($username);
  my $featureVersion = $gatewayAccount->getFeatures()->get('queryTransVersion');

  if ($featureVersion == 2 || $gatewayAccount->usesUnifiedProcessing()) {
    return &_new_returnprev($gatewayAccount,\%query);
  } else {
    return &_returnprev();
  }
}

sub _new_returnprev {
  my $gatewayAccount = shift;
  my $requestData = shift;
  my %result = ();
  my $username = $gatewayAccount->getGatewayAccountName();
  my $features = $gatewayAccount->getFeatures();
  my $linkedAccounts = new PlugNPay::GatewayAccount::LinkedAccounts($username);

  if (!defined $requestData || ref($requestData) ne 'HASH') {
    $requestData = \%remote::query;
  }

  #if account can run transactions then do not even try
  if (!$gatewayAccount->canProcessReturns()) {
    $result{'FinalStatus'} = 'problem';
    $result{'MErrMsg'} = 'Not allowed to process returns';
    $result{'MStatus'} = 'problem';
    return %result;
  }

  #get processor
  my $processor = $requestData->{'processor'};
  if (!$processor) {
    if ($requestData->{'accttype'} =~ /savings|checking/i) {
      $processor = $gatewayAccount->getCheckProcessor();
    } else {
      $processor = $gatewayAccount->getCardProcessor();
    }
  }

  #enable mulitcurrency if applicable
  my @transFlags = split(',',$requestData->{'transflags'});
  if ($features->get('multicurrency') == 1 && !inArray('multicurrency',\@transFlags)) {
    push @transFlags,'multicurrency';
  }

  #validate prevorderid and, if there, check the sent username is linked to requests username
  my $previousOrderId = $requestData->{'prevorderid'};
  if ($requestData->{'prevorderid'} =~ /\:/) {
    ($previousOrderId, $username) = split('\:',$requestData->{'prevorderid'}); 
    if ($linkedAccounts->isLinkedTo($username)) {
      $username = $gatewayAccount->getGatewayAccountName();
    }
  }
  $previousOrderId =~ s/[^0-9]//g;
  $username =~ s/[^a-z0-9]//g;

  my $processorObject = new PlugNPay::Processor({'shortName' => $processor});
  
  my $exists = 0;
  my $loader = new PlugNPay::Transaction::Loader({'loadPaymentData' => 1, 'returnAsHash' => 0});
  my @extra = ();
  my $loadedTransactions = $loader->load({'transactionID' => $previousOrderId, 'gatewayAccount' => $username});
  my $loaded = $loadedTransactions->{$username}{$previousOrderId};
  if (defined $loaded && ref($loaded) =~ /^PlugNPay::Transaction/) {
    #for new procs set this stuff
    if ($processorObject->usesUnifiedProcessing()) {
      push @extra,('pnp_transaction_ref_id',$loaded->getPNPTransactionID(),'refnumber',$loaded->getProcessorReferenceID());
    }
    $exists = 1;
    my $payment = $loaded->getPayment();
    if ($loaded->getTransactionPaymentType() eq 'ach') {
      my $accountNumber = $payment->getAccountNumber();
      my $routingNumber = $payment->getRoutingNumber();
      $requestData->{'card-number'} = $routingNumber . ' ' . $accountNumber;
      if ($payment->verifyABARoutingNumber()) {
        $requestData->{'routingnum'} = $routingNumber;
        $requestData->{'accountnum'} = $accountNumber;
        $requestData->{'accttype'} = $payment->getAccountType();
      } else {
        $result{'FinalStatus'} = "problem";
        $result{'MErrMsg'} .= "Bank routing number failed mod10 test.";
        $result{'resp-code'} = "P53";
        return %result;
      }
    } else {
      if (cardIsPotentiallyValid($payment) && !$payment->isExpired()) {
        $requestData->{'card-number'} = $payment->getNumber();
        $requestData->{'card-exp'} = $payment->getExpirationMonth() . '/' . $payment->getExpirationYear()
      } else {
        $result{'FinalStatus'} = "problem";
        $result{'MErrMsg'} = "Invalid credit cardnumber on record.";
        return %result;
      }
    }
    my $billingInformation = $loaded->getBillingInformation();
    $requestData->{'card-name'} = $payment->getName() || $billingInformation->getFullName();
    $requestData->{'card-address1'} = $billingInformation->getAddress1();
    $requestData->{'card-address2'} = $billingInformation->getAddress2();
    $requestData->{'card-city'} = $billingInformation->getCity();
    $requestData->{'card-state'} = $billingInformation->getState();
    $requestData->{'card-zip'} = substr($billingInformation->getPostalCode(),0,10);
    $requestData->{'card-country'} = $billingInformation->getCountry();
  }

  if (!$exists) {
    $result{'FinalStatus'} = 'problem';
    $result{'MErrMsg'} = 'Referenced order ID does not exist, please try again with correct order ID.';
    $result{'MStatus'} = 'problem';
    return %result;
  }

  # do some shady stuff
  my $mckutils = mckutils->new(%{$requestData});
  $requestData = \%mckutils::query;

  # get default currency
  if (!$requestData->{'currency'}) {
    my $defaultCurrency = 'usd';
    #if fails use USD, previously just set USD if sent currency was blank
    eval {
      my $processorAccount = new PlugNPay::Processor::Account({
        'gatewayAccount' => $gatewayAccount->getGatewayAccountName(),
        'processorID' => $processorObject->getID()
      });
      $defaultCurrency = lc($processorAccount->getSettingValue('currency'));
    };

    $requestData->{'currency'} = $defaultCurrency;
  }

  my $fullAddress = substr($requestData->{'card-address1'} . " " . $requestData->{'card-address2'},0,50);
  my $amount = $requestData->{'card-amount'};
  my $price = sprintf("%3s %.2f",$requestData->{'currency'},$amount);
  my $country = substr($requestData->{'card-country'},0,2);

  ## Corrects card-number field for ACH payments, after the value was filterd by mckutils->new (e.g. space was removed)
  if ($requestData->{'accttype'} =~ /^(checking|savings)$/) {
    $requestData->{'card-number'} = $requestData->{'routingnum'} . ' ' . $requestData->{'accountnum'};
  }

  my %return = &miscutils::sendmserver($username,'return',
    'accttype', (defined $requestData->{'accttype'} ? $requestData->{'accttype'} : ''),
    'order-id', $requestData->{'orderID'},
    'orderID', $requestData->{'orderID'},
    'prevorderid', $requestData->{'prevorderid'},
    'amount', $price,
    'card-number', $requestData->{'card-number'},
    'card-name', $requestData->{'card-name'},
    'card-address', $fullAddress,
    'card-city', $requestData->{'card-city'},
    'card-state', $requestData->{'card-state'},
    'card-zip', substr($requestData->{'card-zip'},0,10),
    'card-country', $country,
    'card-exp', $requestData->{'card-exp'},
    'subacct', $requestData->{'subacct'},
    'transflags', $requestData->{'transflags'},
    'lnkreturn', $requestData->{'lnkreturn'},
    'acct_code', $requestData->{'acct_code'},
    'acct_code2', $requestData->{'acct_code2'},
    'acct_code3', $requestData->{'acct_code3'},
    'acct_code4', $requestData->{'acct_code4'},
    @extra
  );

  $requestData->{'transflags'} = join(',',@transFlags);
  %remote::query = %{$requestData};
  %result = (%{$requestData},%return);
  return %result;
}

sub _returnprev {
  my (%result,$prevorderid,$username,$processor);

  my @extrafields = ();

  if (($remote::accountFeatures->get('multicurrency') == 1) && ($remote::query{'transflags'} !~ /multicurrency/)) {
    if (exists $remote::query{'transflags'} ) {
      $remote::query{'transflags'} .= ",multicurrency";
    }
    else {
      $remote::query{'transflags'} = "multicurrency";
    }
  }

  if ($remote::query{'prevorderid'} eq "") {
    %result = (%remote::query,%result);
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} .= "Missing previous orderID.";
    $result{'resp-code'} = "PXX";
    return %result;
  }

  if ($remote::query{'prevorderid'} =~ /\:/) {
   ($prevorderid,$username) = split('\:',$remote::query{'prevorderid'});
    my @linked_accts = split('\|',$remote::accountFeatures->get('linked_accts'));
    my (%linked_accts);
    foreach my $var (@linked_accts) {
      $var =~ s/[^0-9a-z]//g;
      $linked_accts{$var} = 1;
    }
    if (! exists $linked_accts{$username}) {
      $username = "$remote::query{'publisher-name'}";
    }
  }
  else {
    $prevorderid = "$remote::query{'prevorderid'}";
    $username = "$remote::query{'publisher-name'}";
  }
  $prevorderid =~ s/[^0-9]//g;
  $username =~ s/[^a-z0-9]//g;

  my $qstr = "select orderid,card_name,card_addr,card_city,card_state,card_zip,card_country,card_exp,accttype,enccardnumber,length ";
  $qstr .= "from trans_log ";
  $qstr .= "where orderid=? ";
  $qstr .= "and username=? ";
  $qstr .= "and operation in ('auth','forceauth','return','storedata') ";
  $qstr .= "and (duplicate IS NULL or duplicate='')";

  my $dbh = &miscutils::dbhconnect("pnpdata","","$remote::query{'publisher-name'}"); ## Trans_Log
  my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%remote::query);
  $sth->execute("$prevorderid","$username") or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%remote::query);
  my ($loadedOrderID,$card_name,$card_addr,$card_city,$card_state,$card_zip,$card_country,$card_exp,$accttype,$enccardnumber,$length) = $sth->fetchrow;
  $sth->finish;
  $dbh->disconnect;

  if (lc($accttype) =~ /savings|checking/) {
    $processor = $remote::gatewayAccount->getCheckProcessor();
  } else {
    $processor = $remote::gatewayAccount->getCardProcessor();
  }

  if ($loadedOrderID) {
    $enccardnumber = &smpsutils::getcardnumber($username,$prevorderid,$processor,$enccardnumber);
  }

  if ($enccardnumber eq "") {
    %result = (%remote::query,%result);
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} .= "No previous billing information found.";
    $result{'resp-code'} = "PXX";
    return %result;
  }
  else {
    $remote::query{'card-number'} = &rsautils::rsa_decrypt_file($enccardnumber,$length,"print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");
  }

  if ($remote::query{'card-number'} =~ /^(\d{9}) (\d+)/) {
    $remote::query{'routingnum'} = $1;
    $remote::query{'accountnum'} = $2;
    my $modtest = &miscutils::mod10($remote::query{'routingnum'});
    if ($modtest eq "success") {
      $remote::query{'accttype'} = "$accttype";
    }
    else {
      delete $remote::query{'routingnum'};
      delete $remote::query{'accountnum'};
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} .= "Bank routing number failed mod10 test.";
      $result{'resp-code'} = "P53";
      return %result;
    }
  }
  else {
    my $cc = new PlugNPay::CreditCard($remote::query{'card-number'});
    if (!cardIsPotentiallyValid($cc)) {
        $result{'FinalStatus'} = "problem";
        $result{'MErrMsg'} = "Invalid credit cardnumber on record.";
        return %result;
    }
  }
  if ($remote::processor =~ /emv$/) {
    $remote::query{'terminalnum'} =~ s/[^0-9]//g;
    push (@extrafields, 'terminalnum', $remote::query{'terminalnum'});
  }

  $remote::query{'card-name'} = $card_name;
  $remote::query{'card-address1'} = $card_addr;
  $remote::query{'card-city'} = $card_city;
  $remote::query{'card-state'} = $card_state;
  $remote::query{'card-zip'} = $card_zip;
  $remote::query{'card-country'} = $card_country;
  $remote::query{'card-exp'} = $card_exp;

  my (@array) = %remote::query;
  my $payment = mckutils->new(@array);
  my %query = %mckutils::query;

  if ($query{'currency'} eq "") {
    $query{'currency'} = "usd";
  }
  my $addr = $query{'card-address1'} . " " . $query{'card-address2'};
  $addr = substr($addr,0,50);
  my $amount = $remote::query{'card-amount'};
  my $price = sprintf("%3s %.2f","$query{'currency'}",$amount);
  my $country = substr($query{'card-country'},0,2);
  $query{'card-zip'} = substr($query{'card-zip'},0,10);

  ## Corrects card-number field for ACH payments, after the value was filterd by mckutils->new (e.g. space was removed)
  if ($query{'accttype'} =~ /^(checking|savings)$/) {
    $query{'card-number'} = "$query{'routingnum'} $query{'accountnum'}";
  }

  $username = $query{'publisher-name'};
  %result = &miscutils::sendmserver("$username","return",
    'accttype',"$query{'accttype'}",
    'order-id', $query{'orderID'},
    'amount', $price,
    'card-number', $query{'card-number'},
    'card-name', $query{'card-name'},
    'card-address', $addr,
    'card-city', $query{'card-city'},
    'card-state', $query{'card-state'},
    'card-zip', $query{'card-zip'},
    'card-country', $country,
    'card-exp', $query{'card-exp'},
    'subacct', $query{'subacct'},
    'transflags', $query{'transflags'},
    'lnkreturn', $query{'lnkreturn'},
    'acct_code', $query{'acct_code'},
    'acct_code2', $query{'acct_code2'},
    'acct_code3', $query{'acct_code3'},
    'acct_code4', $query{'acct_code4'},
    @extrafields
  );
  %result = (%query,%result);
  return %result;
}

sub authprev {
  my %result;
  my ($username,$prevorderid);
  if ($remote::query{'prevorderid'} eq "" && !defined $remote::query{'pnpTransactionID'}) {
    %result = (%remote::query,%result);
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} .= "Missing previous orderID.";
    $result{'resp-code'} = "P85";
    return %result;
  }

  if ($remote::query{'prevorderid'} =~ /\:/) {
   ($prevorderid,$username) = split('\:',$remote::query{'prevorderid'});
    my @linked_accts = split('\|',$remote::accountFeatures->get('linked_accts'));
    my (%linked_accts);
    foreach my $var (@linked_accts) {
      $var =~ s/[^0-9a-z]//g;
      $linked_accts{$var} = 1;
    }
    if (! exists $linked_accts{$username}) {
      $username = "$remote::query{'publisher-name'}";
    }
  } else {
    $prevorderid = "$remote::query{'prevorderid'}";
    $username = "$remote::query{'publisher-name'}";
  }

  $prevorderid =~ s/[^0-9]//g;
  $username =~ s/[^a-z0-9]//g;
  my $featureVersion = $remote::gatewayAccount->getFeatures()->get('queryTransVersion');
  my $routeToNewFunction = defined $remote::query{'pnpTransactionID'};
  my $orderLoader = new PlugNPay::Order::Loader();
  my $databaseCheck = $orderLoader->checkDatabasesToLoad($username, {'orderID' => $prevorderid});

  if ($routeToNewFunction || $databaseCheck->{'new'} || $featureVersion) {
    return &_unifiedAuthPrev($databaseCheck, $username, $prevorderid);
  } else {
    return &_authprev($username, $prevorderid);
  }
}

sub _unifiedAuthPrev {
  my $dbcheck = shift;
  my $refUsername = shift;
  my $prevOrderID = shift;
  my $username = $remote::query{'publisher-name'};
  my $gatewayAccount = new PlugNPay::GatewayAccount($username);
  my $loader = new PlugNPay::Transaction::Loader({'loadPaymentData' => 1});
  my $result = {};
  my $pnpReferenceID;
  if (defined $remote::query{'pnpTransactionID'}) {
    $result = $loader->unifiedLoad({'transactionID' => $remote::query{'pnpTransactionID'}, 'username' => $refUsername})->{$refUsername}{$remote::query{'pnpTransactionID'}};
    $pnpReferenceID = $remote::query{'pnpTransactionID'};
  } else {
    $result = $loader->load({'orderID' => $prevOrderID, 'username' => $refUsername})->{$refUsername};
    my @keys = keys %{$result};
    if (@keys == 1) {
      $result = $result->{$keys[0]};
      $pnpReferenceID = $keys[0];
    } else {
      foreach my $key (@keys) {
        if ($result->{'transaction_state'} eq 'AUTH' && $result->{'merchant_order_id'} == $prevOrderID) {
          $result = $result->{$key};
          $pnpReferenceID = $key;
          last;
        }
      }
    }
  }

  eval {
    if (!$result || !$result->getPayment() || !$result->getPayment()->getMaskedNumber()) {
      my %results = %remote::query;
      $results{'FinalStatus'} = "problem";
      $results{'MErrMsg'} .= "No previous billing information found.";
      $results{'resp-code'} = "P86";
      return %results;
    }
  };

  if ($@) {
    my %results = %remote::query;
    $results{'FinalStatus'} = "problem";
    $results{'MErrMsg'} .= "No previous transaction information found.";
    $results{'resp-code'} = "P86";
    return %results;
  }

  #Now we have our trans obj
  $remote::query{'mode'} = 'auth';
  $remote::query{'acct_code4'} = 'authprev';
  $remote::query{'pnp_transaction_ref_id'} = $pnpReferenceID;
  delete $remote::query{'pnpTransactionID'};

  if ($result->{'additional_processor_details'}) {
    my $stateID = $result->{'transaction_state_id'};
    $remote::query{'refnumber'} = $result->{'additional_processor_details'}{$stateID}{'processor_reference_id'};
  }

  eval {
    $remote::query{'card-name'} = $result->{'billing_information'}{'name'};
    $remote::query{'email'} = $result->{'billing_information'}{'email'};
    $remote::query{'phone'} = $result->{'billing_information'}{'phone'};
    $remote::query{'card-address1'} = $result->{'billing_information'}{'address'};
    $remote::query{'card-city'} = $result->{'billing_information'}{'city'};
    $remote::query{'card-state'} = $result->{'billing_information'}{'state'};
    $remote::query{'card-zip'} = $result->{'billing_information'}{'postal_code'};
    $remote::query{'card-country'} = $result->{'billing_information'}{'country'};
  };

  my $paymentInfoIsValid = 0;
  eval {
    my $token = $result->{'pnp_token'};
    if (!$token) {
      my %result = %remote::query;
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} .= "No previous payment information found.";
      $result{'resp-code'} = "P86";
      return %result;
    }

    my $tokenObj = new PlugNPay::Token();
    if ($token !~ /^[a-fA-F0-9]+$/) {
      $tokenObj->fromBinary($token);
      $token = $tokenObj->inHex();
    }

    my $paymentInfo = $tokenObj->fromToken($token);
    $paymentInfoIsValid = defined $paymentInfo && $paymentInfo ne '';
    if ($result->{'transaction_vehicle'} eq 'ach') {
      $remote::query{'paymethod'} = 'ach';
      $remote::query{'processor'} = $gatewayAccount->getCheckProcessor();

      my @ach = split(' ',$paymentInfo);
      $remote::query{'routingnum'} = $ach[0];
      $remote::query{'accountnum'} = $ach[1];
      $paymentInfoIsValid &&= ($ach[0] && $ach[1]);
    } else {
      $remote::query{'paymethod'} = 'credit';
      $remote::query{'processor'} = $gatewayAccount->getCardProcessor();
      $remote::query{'card-number'} = $paymentInfo;
      $remote::query{'card-exp'} = $result->{'card_information'}{'card_expiration'};
    }
  };

  if ($@ || !$paymentInfoIsValid) {
    my %result = %remote::query;
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} .= "No previous billing information found.";
    $result{'resp-code'} = "P86";
    return %result;
  }

  return;
}

sub _authprev {
  my (%result,$prevorderid,$username,$processor);
  $username = shift;
  $prevorderid = shift;
  $prevorderid =~ s/[^0-9]//g;
  $username =~ s/[^a-z0-9]//g;

  my $qstr = "select orderid,card_name,card_addr,card_city,card_state,card_zip,card_country,card_exp,accttype,enccardnumber,length ";
  $qstr .= "from trans_log ";
  $qstr .= "where orderid=? ";
  $qstr .= "and username=? ";
  $qstr .= "and operation in ('auth','forceauth','return','storedata') ";
  $qstr .= "and (duplicate IS NULL or duplicate='')";

  my $dbh = &miscutils::dbhconnect("pnpdata","","$remote::query{'publisher-name'}"); ## Trans_Log
  my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%remote::query);
  $sth->execute("$prevorderid","$username") or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%remote::query);
  my ($loadedOrderID,$card_name,$card_addr,$card_city,$card_state,$card_zip,$card_country,$card_exp,$accttype,$enccardnumber,$length) = $sth->fetchrow;
  $sth->finish;

  if (lc($accttype) =~ /savings|checking/) {
    $processor = $remote::gatewayAccount->getCheckProcessor();
  } else {
    $processor = $remote::gatewayAccount->getCardProcessor();
  }


  if ($loadedOrderID) {
    $enccardnumber = &smpsutils::getcardnumber($username,$prevorderid,$processor,$enccardnumber);
  }

  if ($remote::processor eq "emerchantpay") {
    my $qstr = "select phone,email ";
    $qstr .= "from ordersummary ";
    $qstr .= "where orderid=? ";
    $qstr .= "and username=? ";
    $qstr .= "and (duplicate IS NULL or duplicate='')";

    my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%remote::query);
    $sth->execute("$prevorderid","$username") or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%remote::query);
    my ($phone,$email) = $sth->fetchrow;
    $sth->finish;
    $remote::query{'phone'} = $phone;
    $remote::query{'email'} = $email;
  }
  $dbh->disconnect;

  if ($enccardnumber eq "") {
    %result = (%remote::query,%result);
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} .= "No previous billing information found.";
    $result{'resp-code'} = "P86";
    return %result;
  }
  else {
    $remote::query{'card-number'} = &rsautils::rsa_decrypt_file($enccardnumber,$length,"print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");
  }

  if ($remote::query{'card-number'} =~ /^(\d{9}) (\d+)/) {
    $remote::query{'routingnum'} = $1;
    $remote::query{'accountnum'} = $2;
    my $modtest = &miscutils::mod10($remote::query{'routingnum'});
    if ($modtest eq "success") {
      $remote::query{'accttype'} = "$accttype";
    }
    else {
      delete $remote::query{'routingnum'};
      delete $remote::query{'accountnum'};
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} .= "Bank routing number failed mod10 test.";
      $result{'resp-code'} = "P53";
      return %result;
    }
  }
  else {
    my $cc = new PlugNPay::CreditCard($remote::query{'card-number'});
    if (!cardIsPotentiallyValid($cc)) {
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = "Invalid credit cardnumber on record.";
      return %result;
    }
  }
  $remote::query{'mode'} = 'auth';
  $remote::query{'acct_code4'} = 'authprev';
  $remote::query{'card-name'} = $card_name;
  $remote::query{'card-address1'} = $card_addr;
  $remote::query{'card-city'} = $card_city;
  $remote::query{'card-state'} = $card_state;
  $remote::query{'card-zip'} = $card_zip;
  $remote::query{'card-country'} = $card_country;

  if ($remote::query{'card-exp'} !~ /^\d\d\/\d\d$/) {
    $remote::query{'card-exp'} = $card_exp;
  }

  return;
}

sub forceauth {
  my (@array) = %remote::query;
  my (%result);
  my $payment = mckutils->new(@array);

  my @extrafields = ();

  &mckutils::receiptcc();

  my %query = %mckutils::query;

  if ($remote::processor eq "wirecard") {
    if (($query{'auth-code'} eq "") || ($query{'card-amount'} eq "")) {
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = "Transaction may not be forced. Refnumber, auth code and card amount required.";
      return %result;
    }
  }
  else {
    if (($query{'card-number'} eq "") || ($query{'card-exp'} eq "")
         || ($query{'auth-code'} eq "") || ($query{'card-amount'} eq "")) {
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = "Transaction may not be forced. Card number, expiration date, auth code, card amount required.";
      return %result;
    }
  }

  if (($remote::accountFeatures->get('force_onfail') ne "") && ($query{'force_onfail'} ne "")) {
    my $cardbin = substr($query{'card-number'},0,6);

    my $dbh = &miscutils::dbhconnect("fraudtrack");
    my $sth = $dbh->prepare(qq{
        select username
        from bin_fraud
        where entry=?
        and username=?
      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
    $sth->execute("$cardbin","friendfind6") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%mckutils::query);
    my ($test) = $sth->fetchrow;
    $sth->finish;
    $dbh->disconnect();

    if ($test ne "") {
      $result{'ForceFinalStatus'} = "problem";
      $result{'ForceMErrMsg'} = "Card BIN found in Negative Table:$cardbin";
      %result = (%query,%result);
      return %result;
    }
  }

  if ($remote::processor =~ /emv$/) {
    $remote::query{'terminalnum'} =~ s/[^0-9]//g;
    push (@extrafields, 'terminalnum', $remote::query{'terminalnum'});
  }

  my $addr = $query{'card-address1'} . " " . $query{'card-address2'};
  $addr = substr($addr,0,50);

  my $price = sprintf("%3s %.2f","$query{'currency'}",$query{'card-amount'});

  my $country = substr($query{'card-country'},0,2);

  $query{'card-zip'} = substr($query{'card-zip'},0,10);

  my $username = $query{'publisher-name'};

  %result = &miscutils::sendmserver("$username","forceauth",
    'order-id', $query{'orderID'},
    'amount', $price,
    'auth-code', $query{'auth-code'},
    'card-number', $query{'card-number'},
    'card-exp', $query{'card-exp'},
    'card-name', $query{'card-name'},
    'card-address', $addr,
    'card-city', $query{'card-city'},
    'card-state', $query{'card-state'},
    'card-zip', $query{'card-zip'},
    'card-country', $country,
    'subacct', $query{'subacct'},
    'acct_code', $query{'acct_code'},
    'acct_code2', $query{'acct_code2'},
    'acct_code3', $query{'acct_code3'},
    'acct_code4', $query{'acct_code4'},
    'freeform', $query{'freeform'},
    'refnumber', $query{'refnumber'},
    @extrafields
  );

  if ($result{'FinalStatus'} =~ /^success|pending$/) {
    $result{'aux-msg'} = " Transaction has been successfully forced.";
    my (%res);
    if ($query{'authtype'} eq "authpostauth") {
      %res = &miscutils::sendmserver($query{'publisher-name'},"postauth"
                ,'order-id',$query{'orderID'}
                ,'amount', $price
                ,'acct_code4',"$query{'acct_code4'}"
                );
      if ($res{'FinalStatus'} =~ /^success|pending$/) {
        $result{'aux-msg'} = " Transaction has been successfully forced and postauthed.";
      }
      else {
        $result{'FinalStatus'} = "problem";
        $result{'MErrMsg'} = "Transaction was successfully forced but was unable to be postauthed. Please contact tech. support.";
      }
    }
  }
  else {
    $result{'MErrMsg'} = "Transaction was not able to be forced. Please contact tech. support.";
  }

  #if ($result{'FinalStatus'} =~ /^success|pending$/) {
  #  $result{'aux-msg'} .= " Transaction has been successfully forced.";
  #}
  #else {
  #  $result{'MErrMsg'} = "Transaction was not able to be forced. Please contact tech. support.";
  #}

  %result = (%query,%result);
  return %result;
}

sub ecard {
  my $type = shift;
  my($operation) = @_;
  my (@array) = %remote::query;
  my (%result);
  my $payment = mckutils->new(@array);
  my %query = %mckutils::query;
  if ($query{'currency'} eq "") {
    $query{'currency'} = "usd";
  }
  my $amount = $query{'card-amount'};
  my $price = sprintf("%3s %.2f","$query{'currency'}",$amount);

  my $username = $query{'publisher-name'};
  %result = &miscutils::sendmserver("$username","$operation",
    'accttype',"$query{'accttype'}",
    'order-id', $query{'orderID'},
    'amount', $price,
    'card-number', $query{'card-number'},
    'card-exp', $query{'card-exp'},
    'card-number_sv', $query{'card-number_sv'},
    'card-exp_sv', $query{'card-exp_sv'},
    'acct_code', $query{'acct_code'},
    'acct_code2', $query{'acct_code2'},
    'acct_code3', $query{'acct_code3'},
    'acct_code4', $query{'acct_code4'},
    'magstripe', $query{'magstripe'},
    'pin', $query{'pin'}
  );
  %result = (%query,%result);
  return %result;
}

sub taxcalc {
  my (%query) = @_;
  my ($taxable_state,$k,@taxstate,@taxrate);
  if (($query{'notax'} != 1) && ($query{'tax'} < 0.001)) {
    @taxstate = split('\|',$query{'taxstate'});
    @taxrate = split('\|',$query{'taxrate'});
    if ($query{'taxbilling'} eq "yes") {
      $taxable_state = $query{'card-state'};
    }
    else {
      $taxable_state = $query{'state'};
    }
    $k = 0;
    if ($query{'taxstate'} eq "all") {
      if ($query{'taxship'} eq "no") {
        $query{'tax'} = ($query{'subtotal'}) * $taxrate[$k];
      } else {
        $query{'tax'} = ($query{'subtotal'} + $query{'shipping'}) * $taxrate[$k];
      }
    }
    else {
      foreach my $var (@taxstate) {
        if (($taxrate[$k] > 0) && ($taxable_state =~ /$var/i)) {
          if ($query{'taxship'} eq "no") {
            $query{'tax'} = ($query{'subtotal'}) * $taxrate[$k];
          } else {
            $query{'tax'} = ($query{'subtotal'} + $query{'shipping'}) * $taxrate[$k];
          }
        }
        $k++;
      }
    }
  }
  #$query{'card-amount'} = $query{'tax'} + $query{'shipping'} + $query{'subtotal'};
  return ($query{'tax'});
}

sub underscore_to_hyphen {
  my (%query) = @_;
  foreach my $key (keys %query) {
    if(($key !~ /^(acct_code|vt_url)/i) && ($key =~ /\_/)) {
      my $temp = $query{$key};
      delete $query{$key};
      $key =~ tr/\_/\-/;
      $query{$key} = $temp;
    }
    elsif(($key =~ /\_/) && ($key =~ /^acct_code(.*)/i)) {
      my $a = $1;
      my $temp = $query{$key};
      delete $query{$key};
      $a =~ tr/\_/\-/;
      $a = "acct_code$a";
      $query{$a} = $temp;
    }

  }
  return (%query);
}

sub hyphen_to_underscore {
  my (%query) = @_;
  foreach my $key (keys %query) {
    if(($key ne "acct_code") && ($key =~ /\-/)) {
      my $temp = $query{$key};
      delete $query{$key};
      $key =~ tr/\-/\_/;
      $query{$key} = $temp;
    }
  }
  return (%query);
}

sub upper_to_lowercase {
  my (%query) = @_;
  foreach my $key (keys %query) {
    if($key ne "orderID") {
      my $temp = $query{$key};
      delete $query{$key};
      $key =~ tr/A-Z/a-z/;
      $query{$key} = $temp;
    }
  }
  return (%query);
}

sub lower_to_uppercase {
  my (%query) = @_;
  foreach my $key (keys %query) {
    my $temp = $query{$key};
    delete $query{$key};
    $key =~ tr/a-z/A-Z/;
    $query{$key} = $temp;
  }
  return (%query);
}

sub input_cold_fusion {
  my (%query) = @_;
  %query = &underscore_to_hyphen(%query);
  %query = &upper_to_lowercase(%query);
  if (($query{'orderID'} eq "") && ($query{'orderid'} ne "")) {
    $query{'orderID'} = $query{'orderid'};
  }
  return (%query);
}

sub output_cold_fusion {
  my (%query) = @_;
  $query{'aux-msg'} =~ s/\:/ /g;
  $query{'auth-msg'} =~ s/\:/ /g;
  %query = &hyphen_to_underscore(%query);
  %query = &lower_to_uppercase(%query);
  return (%query);
}

sub input_palmpilot {
  my (%query) = @_;
  my %publisher_names = ('1.16338185.185126280','fdc32tes','0.-862268375.61159581','apmsafec','1.16377852.185264538','acumenfi','1.16300426.186390130','medicoolin2','1.16419439.186388335','fishworks','1.16332580.185775711','epz2300100','1.16482734.185543304','eventmarke','1.16483773.185752455','ecqabogul','1.16305321.185687367','rainbowente','1.16428445.186389320','epz4800001','1.16435782.186401172','alexbuduki','0.3543300596.587871007','wholesalef','1.16509856.185353112','ableautoto','0.3058121182.1735879371','ntcwebgroup','0.2515369020.587870901','wholesalef');
  my %publisher_email = ('1.16338185.185126280','dprice@plugnpay.com','0.-862268375.61159581','gmcneely@apmsafe.com','1.16377852.185264538','lodette@palm.net','1.16300426.186390130','orders@medicool.com','1.16419439.186388335','marlinq@ruraltel.net','1.16332580.185775711','biztrack2000@yahoo.com','1.16482734.185543304','gene@eventmarketplace.com','1.16483773.185752455','bogul@earthlink.net','1.16305321.185687367','cart@rainbowrope.com','1.16428445.186389320','donholland@earthlink.net','1.16435782.186401172','bud@bvb-enterprises.com','0.3543300596.587871007','topper727@hotmail.com','1.16509856.185353112','jamesmichael@cardsglobal.net','0.3058121182.1735879371','brian@ntcwebgroup.com','0.2515369020.587870901','topper727@hotmail.com');

  if ($query{'publisher-name'} eq "") {
    if ($publisher_names{$query{'clientID'}} eq "") {
      $publisher_names{$query{'clientID'}} = "fdc32tes";
    }
    $query{'publisher-name'} = $publisher_names{$query{'clientID'}};
  }
  if ($query{'publisher-email'} eq "") {
    if ($publisher_email{$query{'clientID'}} eq "") {
      $publisher_email{$query{'clientID'}} = "dprice\@plugnpay.com";
    }
    $query{'publisher-email'} = $publisher_email{$query{'clientID'}};
  }
  return (%query);
}

sub input_authnet {
  my (%query) = @_;
  my ($version);
  my %input = %query;

  foreach my $key (keys %input) {
    if ($key =~ /x_login/i){
      $key =~ s/[^a-zA-Z0-9\-\_]//g;
    }
    if($key =~ /^x_/i) {
      my $temp = $input{$key};
      delete $input{$key};
      $key =~ tr/A-Z/a-z/;
      $input{$key} = $temp;
    }
  }

  $query{'version'} = $input{'x_version'};

  if ($query{'version'} eq "3.1") {
    if ($input{'x_exp_date'} =~ /\/|\-/) {
      my ($mo,$yr) = split(/\/+|-+/,$input{'x_exp_date'});
      #my ($mo,$yr) = split('/|-',$input{'x_exp_date'});
      if (length($mo) == 1) {
        $query{'card-exp'} = "0$mo" . "/" . substr($input{'x_exp_date'},-2);
      }
      else {
        $query{'card-exp'} = "$mo" . "/" . substr($input{'x_exp_date'},-2);
      }
    }
    else {
      $query{'card-exp'} = $input{'x_exp_date'};
    }

    $query{'publisher-name'} = $input{'x_login'};
    if ($input{'x_password'} ne "") {
      $query{'publisher-password'} = $input{'x_password'};
    }
    else {
      $query{'publisher-password'} = $input{'x_tran_key'};
    }
    $query{'card-name'} = $input{'x_first_name'} . " " . $input{'x_last_name'};
    $query{'card-address1'} = $input{'x_address'};
    $query{'card-number'} = $input{'x_card_num'};
    $query{'card-city'} = $input{'x_city'};
    $query{'card-state'} = $input{'x_state'};
    $query{'card-zip'} = $input{'x_zip'};
    $query{'card-company'} = $input{'x_company'};
    $query{'card-cvv'} = $input{'x_card_code'};
    $query{'card-country'} = $input{'x_country'};
    $query{'order-id'} = $input{'x_invoice_num'};
    $query{'card-amount'} = $input{'x_amount'};
    $query{'shipname'} = "$input{'x_ship_to_first_name'} $input{'x_ship_to_last_name'}";
    $query{'address1'} = $input{'x_ship_to_address'};
    $query{'city'} = $input{'x_ship_to_city'};
    $query{'state'} = $input{'x_ship_to_state'};
    $query{'zip'} = $input{'x_ship_to_zip'};
    $query{'country'} = $input{'x_ship_to_country'};
    $query{'shipcompany'} = $input{'x_ship_to_company'};
    $query{'phone'} = $input{'x_phone'};
    $query{'email'} = $input{'x_email'};
    $query{'currency'} = $input{'x_currency_code'};

    if (exists $input{'x_cust_id'}) {
      $query{'x_cust_id'} = $input{'x_cust_id'};
    }
    if (exists $input{'x_bill_cycle'}) {
      $query{'x_bill_cycle'} = $input{'x_bill_cycle'};
    }
    if (exists $input{'x_duplicate_window'}) {
      $query{'dupchkwin'} = $input{'x_duplicate_window'};
    }
    if ((exists $input{'x_customer_ip'}) && ($query{'ipaddress'} eq "")) {
      $query{'ipaddress'} = $input{'x_customer_ip'};
    }
    if ((exists $input{'x_transflags'}) && ($query{'transflags'} eq "")) {
      $query{'transflags'} = $input{'x_transflags'};
    }

    if ((exists $input{'x_refnumber'}) && ($query{'refnumber'} eq "")) {
      $query{'refnumber'} = $input{'x_refnumber'};
    }

    ##  Added 20050118 DCP to support other AuthNet TransType. Need to un-comment AUTH_CAPTURE after merchants are contacted so impact is not unexpected as
    ##  Some merchants are currently sending in AUTH_CAPTURE
    ##  Tran Types
    #if ($input{'x_type'} =~ /AUTH_CAPTURE/i) {
    #  $query{'mode'} = "auth";
    #  #$query{'authtype'} = "authpostauth";
    #}
    if ($input{'x_type'} =~ /PRIOR_AUTH_CAPTURE/i) {
      $query{'mode'} = "mark";
      $query{'orderID'} = $input{'x_trans_id'};
    }
    elsif ($input{'x_type'} =~ /AUTH_CAPTURE/i) {
      $query{'mode'} = "auth";
      # Grandfather select merchants to 'authonly'.  All other merchants get 'authpostauth'.
      if ($input{'x_login'} !~ /^(1800duilaw|acacpusainc|adamstelep|alphaone|americanbu|bigjimsfen|blachlylan|california16|christmass|consumersp|crstteleph|customshir|cwsmallgro|cyd0976504|cyd1042462|cyd1478682|demonisc|easternill1|engumsacad|farmerstel1|foragesf|graftonvcc|grassroots1|informbusi|jsecompute|kleesgolfs|lakeregion2|laneelectr|lcenterpri1|mcleanelec|mexicosprin1|nabchrislu|nabmiccusc|nemonttele|nevadabrot|optimalnat|progressiv6|publicserv|pumponellc|rjmedia|rosascafet|sahadiseco|skindeepinc|skybahamas|slopeelect|southeaste2|southernai|southernpr|sportsgemp|steubencou|teatrozucc1|tewsinc|thegingerb|urbanherbs|valleytele|vangogh|vcshobbies|westkyrura|wicksgloba)$/) {
        $query{'authtype'} = "authpostauth";
      }
    }
    elsif ($input{'x_type'} =~ /AUTH_ONLY/i) {
      $query{'mode'} = "auth";
    }
    elsif ($input{'x_type'} =~ /VOID/i) {
      $query{'mode'} = "void";
      $query{'orderID'} = $input{'x_trans_id'};
    }
    elsif ($input{'x_type'} =~ /CAPTURE_ONLY/i) {
      $query{'mode'} = "forceauth";
    }
    elsif ($input{'x_type'} =~ /CREDIT/i) {
      $query{'mode'} = "return";
      $query{'orderID'} = $input{'x_trans_id'};
    }
    else {
      $query{'mode'} = "auth";
    }

    if ($input{'x_recurring_billing'} =~ /YES/i) {
      if (exists $query{'transflags'} ) {
        $query{'transflags'} .= ",recurring";
      }
      else {
        $query{'transflags'} = "recurring";
      }
    }

    if (exists $input{'x_bank_aba_code'}) {
      $query{'routingnum'} = $input{'x_bank_aba_code'};
      $query{'accountnum'} = $input{'x_bank_acct_num'};
      $query{'accttype'} = $input{'x_bank_acct_type'};
      $query{'accttype'} =~ tr/A-X/a-x/;
    }
    #$query{'bankname'} = $input{'x_bank_name'};
    #$query{'bankacctname'} = $input{'x_bank_acct_name'};

  }
  else {
    if ($query{'x_Exp_Date'} =~ /\/|\-/) {
      my ($mo,$yr) = split('/|-',$query{'x_Exp_Date'});
      if (length($mo) == 1) {
        $query{'card-exp'} = "0$mo" . "/" . substr($input{'x_exp_date'},-2);
      }
      else {
        $query{'card-exp'} = "$mo" . "/" . substr($input{'x_exp_date'},-2);
      }
    }
    else {
      $query{'card-exp'} = $query{'x_Exp_Date'};
    }

    #my ($mo,$yr) = split('/',$query{'x_Exp_Date'});
    #if (length($mo) == 1) {
    #  $query{'card-exp'} = "0$mo" . "/" . substr($query{'x_Exp_Date'},-2);
    #}
    #else {
    #  $query{'card-exp'} = "$mo" . "/" . substr($query{'x_Exp_Date'},-2);
    #}

    if (exists  $query{'x_login'}) {
      $query{'publisher-name'} = $query{'x_login'};
    }
    else {
      $query{'publisher-name'} = $query{'x_Login'};
    }
    if (exists  $query{'x_password'}) {
      $query{'publisher-password'} = $query{'x_password'};
    }
    else {
      $query{'publisher-password'} = $query{'x_Password'};
    }
    $query{'card-name'} = $query{'x_First_Name'} . " " . $query{'x_Last_Name'};
    $query{'card-address1'} = $query{'x_Address'};
    $query{'card-number'} = $query{'x_Card_Num'};
    $query{'card-city'} = $query{'x_City'};
    $query{'card-state'} = $query{'x_State'};
    $query{'card-zip'} = $query{'x_Zip'};
    $query{'card-cvv'} = $query{'x_Card_Code'};
    $query{'card-country'} = $query{'x_Country'};
    $query{'order-id'} = $query{'x_Invoice_Num'};
    $query{'card-amount'} = $query{'x_Amount'};
    $query{'shipname'} = "$query{'x_Ship_to_First_Name'} $query{'x_Ship_To_Last_Name'}";
    $query{'address1'} = $query{'x_Ship_To_Address'};
    $query{'city'} = $query{'x_Ship_To_City'};
    $query{'state'} = $query{'x_Ship_To_State'};
    $query{'zip'} = $query{'x_Ship_To_Zip'};
    $query{'country'} = $query{'x_Ship_To_Country'};
    $query{'phone'} = $query{'x_Phone'};
    $query{'email'} = $query{'x_Email'};
  }
  $query{'client'} = "authnet";
  return %query;
}

sub input_authnet_cp {
  my (%query) = @_;
  my ($version);
  my %input = %query;
  my $itemizedflg = 0;

  foreach my $key (keys %input) {
    if ($key =~ /x_login/i){
      $key =~ s/[^a-zA-Z0-9\-\_]//g;
    }
    if($key =~ /^x_/i) {
      my $temp = $input{$key};
      delete $input{$key};
      $key =~ tr/A-Z/a-z/;
      $input{$key} = $temp;
    }
    if ($key =~ /^x_line_item/) {
      $itemizedflg = 1;
    }
  }

  $query{'cpversion'} = $input{'x_cpversion'};

  if ($query{'cpversion'} eq "1.0") {
    $query{'publisher-name'} = $input{'x_login'};
    if ($input{'x_password'} ne "") {
      $query{'publisher-password'} = $input{'x_password'};
    }
    else {
      $query{'publisher-password'} = $input{'x_tran_key'};
    }
    $query{'x_market_type'} = $input{'x_market_type'};
    $query{'x_market_type'} =~ s/[^2]//g;

    $query{'x_device_type'} = $input{'x_device_type'};
    $query{'x_device_type'} =~ s/[^0-9]//g;

    $query{'x_response_format'} = $input{'x_response_format'};
    $query{'x_response_format'} =~ s/[^0-1]//g;
    if ($query{'x_response_format'} ne "1") {
      $query{'x_response_format'} = 0;
    }

    $query{'x_user_ref'} = $input{'x_user_ref'};

    if ($query{'x_response_format'} eq "1") {
      $query{'x_delim_char'} = $input{'x_delim_char'};
      $query{'x_delim_char'} = substr($query{'x_delim_char'},0,1);
      $query{'x_encap_char'} = $input{'x_encap_char'};
      $query{'x_encap_char'} = substr($query{'x_encap_char'},0,1);
      if($query{'x_delim_char'} eq "") {
        $query{'x_delim_char'} = "|";
      }
    }

    if (exists $input{'x_duplicate_window'}) {
      $query{'dupchkwin'} = $input{'x_duplicate_window'};
    }

    ## Customer Info
    $query{'card-name'} = $input{'x_first_name'} . " " . $input{'x_last_name'};
    $query{'card-address1'} = $input{'x_address'};
    $query{'card-city'} = $input{'x_city'};
    $query{'card-state'} = $input{'x_state'};
    $query{'card-zip'} = $input{'x_zip'};
    $query{'card-company'} = $input{'x_company'};
    $query{'card-country'} = $input{'x_country'};
    $query{'phone'} = $input{'x_phone'};
    $query{'fax'} = $input{'x_fax'};

    ## Invoice Information
    $query{'order-id'} = $input{'x_invoice_num'};
    $query{'x_description'} = $input{'x_description'};

    ## Order Details  --  Support to be added later
    #x_line_item=item1<|>golf balls<|><|>2<|>18.95<|>Y
    #x_line_item=item2<|>golf bag<|>Wilson golf carry bag, red<|>1<|>39.99<|>Y
    #x_line_item=item3<|>book<|>Golf for Dummies<|>1<|>21.99<|>Y

    if ($itemizedflg == 1) {
      #for (my $i=1; $i<=30; $i++) {
        if (exists $input{"x_line_item"} ) {
          my $i=1;
          ($query{"item$i"},$query{"unit$i"},$query{"description$i"},$query{"quantity$i"},$query{"cost$i"},$query{"taxable$i"}) = split (/\<\|\>/,$input{"x_line_item"});
        }
        if (($query{'publisher-name'} eq "precision") && ($query{'taxable1'} eq "Y")) {
          $query{'item2'} = '056';
          $query{'unit2'} = "U";
          $query{'description2'} = "TAX";
          $query{'quantity2'} = "1";
          $query{'taxable2'} = "N";
          $query{'tax'} = sprintf("%.2f",$input{'x_amount'} - $query{'cost1'});
          $query{'cost2'} = $query{'tax'};
        }
      #}
    }

    ## Shipping Details
    $query{'shipname'} = "$input{'x_ship_to_first_name'} $input{'x_ship_to_last_name'}";
    $query{'address1'} = $input{'x_ship_to_address'};
    $query{'city'} = $input{'x_ship_to_city'};
    $query{'state'} = $input{'x_ship_to_state'};
    $query{'zip'} = $input{'x_ship_to_zip'};
    $query{'country'} = $input{'x_ship_to_country'};
    $query{'shipcompany'} = $input{'x_ship_to_company'};
    $query{'email'} = $input{'x_email'};

    ## Transaction Data
    $query{'card-amount'} = $input{'x_amount'};
    $query{'currency'} = $input{'x_currency_code'};
    $query{'method'} = $input{'x_method'};

    ## WEX Card Info
    my @wexarray = ('x_drivernum','x_odometer','x_vehiclenum','x_jobnum','x_deptnum','x_licensenum','x_userdata','x_userid','x_devseqnum');
    foreach my $var (@wexarray) {
      if (exists $input{$var}) {
        my $qkey = substr($var,2);
        $query{$qkey} = $input{$var};
      }
    }

    if ($input{'x_recurring_billing'} =~ /YES/i) {
      if (exists $query{'transflags'} ) {
        $query{'transflags'} .= ",recurring";
      }
      else {
        $query{'transflags'} = "recurring";
      }
    }

    if (exists $input{'x_cust_id'}) {
      $query{'x_cust_id'} = $input{'x_cust_id'};
    }

    if ((exists $input{'x_customer_ip'}) && ($query{'ipaddress'} eq "")) {
      $query{'ipaddress'} = $input{'x_customer_ip'};
    }

    ## Tran Types
    if ($input{'x_type'} =~ /AUTH_CAPTURE/i) {
      $query{'mode'} = "auth";
      #$query{'authtype'} = "authpostauth";
    }
    elsif ($input{'x_type'} =~ /AUTH_ONLY/i) {
      $query{'mode'} = "auth";
    }
    elsif ($input{'x_type'} =~ /VOID/i) {
      $query{'mode'} = "void";
      $query{'orderID'} = $input{'x_ref_trans_id'};
    }
    elsif ($input{'x_type'} =~ /CAPTURE_ONLY/i) {
      $query{'mode'} = "forceauth";
      $query{'auth_code'} = $input{'x_auth_code'};
    }
    elsif ($input{'x_type'} =~ /CREDIT/i) {
      $query{'mode'} = "return";
      $query{'orderID'} = $input{'x_ref_trans_id'};
    }
    elsif ($input{'x_type'} =~ /PRIOR_AUTH_CAPTURE/i) {
      $query{'mode'} = "mark";
      $query{'orderID'} = $input{'x_ref_trans_id'};
    }
    else {
      $query{'mode'} = "auth";
    }

    $query{'card-number'} = $input{'x_card_num'};

    if ($input{'x_exp_date'} =~ /\/|\-/) {
      my ($mo,$yr) = split(/\/+|-+/,$input{'x_exp_date'});
      if (length($mo) == 1) {
        $query{'card-exp'} = "0$mo" . "/" . substr($input{'x_exp_date'},-2);
      }
      else {
        $query{'card-exp'} = "$mo" . "/" . substr($input{'x_exp_date'},-2);
      }
    }
    else {
      $query{'card-exp'} = $input{'x_exp_date'};
    }
    $query{'card-cvv'} = $input{'x_card_code'};

    if (exists $input{'x_track1'}) {
      $query{'magstripe'} = "\%" . "$input{'x_track1'}\?";
      if ($query{'card-number'} eq "") {
        my @array = %query;
        %query = &input_swipe(@array);
      }
    }
    elsif (exists $input{'x_track2'}) {
      $query{'magstripe'} = "\;$input{'x_track2'}\?";
      if ($query{'card-number'} eq "") {
        my @array = %query;
        %query = &input_swipe(@array);
      }
    }
  }
  $query{'client'} = "authnetcp";
  return %query;
}

sub input_swipe {
  my (%query) = @_;
  my ($tracklevel,$data,$track1data,$track2data,$name);

  if ($query{'magstripe'} =~ /.*\%\b(.*)?\?\;?(.*)\??/i) {
    $tracklevel = 1;
    $track1data = $1;
    $track2data = $2;
  }
  elsif ($query{'magstripe'} =~ /^\;(.*)\?$/) {
    $track2data = $1;
    $tracklevel = 2;
  }
  if ($tracklevel == 1) {
    ($query{'card-number'},$name,$data) = split(/\^/,$track1data);
    $query{'card-exp'} = substr($data,2,2) . substr($data,0,2);
    if ($query{'card-name'} eq "") {
      $query{'card-name'} = $name;
    }
  }
  elsif ($tracklevel == 2) {
    ($query{'card-number'},$data) = split(/=/,$track2data);
    $query{'card-exp'} = substr($data,2,2) . substr($data,0,2);
  }
  return %query;
}

sub input_ewallet {
  my (%query) = @_;
  my ($tracklevel,$data,$track1data,$track2data,$name);

  if ($query{'ewallet_id'} =~ /(\d*\=\d*)/i) {
    $track2data = $1;
    ($query{'ewallet_id'},$data) = split(/=/,$track2data);
    #($query{'card-number'},$data) = split(/=/,$track2data);
    #$query{'card-exp'} = substr($data,2,2) . substr($data,0,2);
  }
  return %query;
}

sub input_mmnextel {
  my (%query) = @_;

  foreach my $key (keys %query) {
    if ($key !~ /^(TK)$/) {
      $query{$key} =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \)\(\$\%]//g;
    }
  }

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
  my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
  if (!PlugNPay::Environment::isContainer()) {
    open(DEBUG,">>$remote::path_debug");
    print DEBUG "NEXTEL DATE:$now IP:$remote::remoteaddr, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, BROWSER:$ENV{'HTTP_USER_AGENT'}, PID:$remote::pid, ";
    foreach my $key (sort keys %query) {
      if ($key eq "C") {
        print DEBUG $key . ":" . substr($query{'C'},0,6) . "****" . substr($query{'C'},-2) . ", ";
      }
      elsif ($key eq "TK") {
        print DEBUG "$key:Data Present, ";
        next;
      }
      else {
        print DEBUG "$key:$query{$key}, ";
      }
    }
    print DEBUG "\n\n";
    close(DEBUG);
  }

  my %map = ('M','month-exp','Y','year-exp','U','publisher-name','P','publisher-password','N','card-name','C','card-number','A','card-amount','T','gratuity','R','acct_code','TK','magstripe');

  $query{'mode'} = "auth";
  $query{'client'} = "mmnextel";

  foreach my $key (keys %map) {
    if (exists $query{$key}) {
      $query{$map{$key}} = $query{$key};
      delete $query{$key};
    }
  }

  return %query;
}

sub input_cart32 {
  my (%query) = @_;
  for(my $k=1; $k<=$query{'NumberOfItems'}; $k++) {
    $query{"item$k"} = substr($query{"Item$k"},0,4) . $k;
    $query{"cost$k"} = $query{"Price$k"};
    $query{"quantity$k"} = $query{"Qty$k"};
    $query{"description$k"} = $query{"Item$k"};
    $query{"option$k"} = $query{"Option$k"};
  }
  $query{'card-name'} = "$query{'card-fname'} $query{'card-lname'}";
  return %query;
}

sub input_miva {
  my (%query) = @_;
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
  $query{'card-number'} = $query{'ccNum'};
  $query{'card-zip'} = $query{'ZIP'};
  $query{'card-amount'} = $query{'amount'};
  my ($mo,$yr) = split('/',$query{'x_Exp_Date'});
  if (length($mo) == 1) {
    $query{'card-exp'} = "0$mo" . "/" . substr($query{'x_Exp_Date'},-2);
  }
  else {
    $query{'card-exp'} = "$mo" . "/" . substr($query{'x_Exp_Date'},-2);
  }
  $query{'publisher-name'} = $query{'x_merchant'};
  $query{'card-name'} = "$query{'x_Card_Name'}";
  $query{'card-address1'} = $query{'x_Address'};
  $query{'card-number'} = $query{'x_Card_Num'};
  $query{'card-city'} = $query{'x_City'};
  $query{'card-state'} = $query{'x_State'};
  $query{'card-zip'} = $query{'x_Zip'};
  $query{'card-country'} = $query{'x_Country'};
  $query{'orderID'} = sprintf("%04d%02d%02d%02d%06d",$year+1900,$mon+1,$mday,$hour,$query{'x_Invoice_Num'});
  $query{'card-amount'} = $query{'x_Amount'};
  $query{'shipname'} = "$query{'x_Ship_to_First_Name'} $query{'x_Ship_To_Last_Name'}";
  $query{'address1'} = $query{'x_Ship_To_Address'};
  $query{'city'}        = $query{'x_Ship_To_City'};
  $query{'state'} = $query{'x_Ship_To_State'};
  $query{'zip'} = $query{'x_Ship_To_Zip'};
  $query{'country'} = $query{'x_Ship_To_Country'};
  $query{'phone'} = $query{'x_Phone'};
  $query{'email'} = $query{'x_Email'};
  return %query;
}

sub input_dydacomp {
  my (%query) = @_;
  $query{'rempasswd'} = $query{'tran_key'};
  return %query;
}

sub input_achdirect {
  my (%query) = @_;
  my (%input);
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
  my %datamap = ('publisher-name','pg_merchant_id','publisher-password','pg_password','x_mode','pg_transaction_type','card-amount','pg_total_amount','tax','pg_sales_tax_amount','orderID','pg_consumer_id','order-id','ecom_consumerorderid','x_walletid','ecom_walletid','card-company','pg_billto_postal_name_company','card-fname','ecom_billto_postal_name_first','card-lname','ecom_billto_postal_name_last','card-address1','ecom_billto_postal_street_line1','card-address2','ecom_billto_postal_street_line2','card-city','ecom_billto_postal_city','card-state','ecom_billto_postal_stateprov','card-zip','ecom_billto_postal_postalcode','card-Country','ecom_billto_postal_countrycode','phone','ecom_billto_telecom_phone_number','email','ecom_billto_online_email','ssn','pg_billto_ssn','licensenum','pg_billto_dl_number','licensestate','pg_billto_dl_state','dateofbirth','pg_billto_date_of_birth','acct_code','pg_entered_by','card-type','Ecom_payment_card_type','card-name','ecom_payment_card_name','card-number','ecom_payment_card_number','Month-exp','ecom_payment_card_expdate_month','Year-exp','ecom_payment_card_expdate_year','card-cvv','ecom_payment_card_verification','commcardtype','pg_procurement_card','ponumber','pg_customer_acct_code','magswipe','pg_cc_swipe_data','transflags','pg_mail_or_phone_order','routingnum','ecom_payment_check_trn','accountnum','ecom_payment_check_account','accttype','ecom_payment_check_account_type','checknum','ecom_payment_check_checkno','checktype','pg_entry_class_code');

  $query{'client'} = "achdirect";

  foreach my $key (keys %datamap) {
    $input{$key} = $query{"$datamap{$key}"};
  }
  $query{'card-exp'} = sprintf("%02d",$query{'ecom_payment_card_expdate_month'}) . "/" . sprintf("%02d",$query{'ecom_payment_card_expdate_year'});

  if ($query{'pg_transaction_type'} eq "10") {
    $input{'mode'} = 'auth';
    $input{'authtype'} = "authpostauth";
  }
  elsif ($query{'pg_transaction_type'} eq "11") {
    $input{'mode'} = 'auth';
    $input{'authtype'} = "authpostauth";
  }
  elsif ($query{'pg_transaction_type'} eq "12") {
    $input{'mode'} = 'mark';
  }
  elsif ($query{'pg_transaction_type'} eq "13") {
    $input{'mode'} = 'newreturn';
  }
  elsif ($query{'pg_transaction_type'} eq "14") {
    $input{'mode'} = 'void';
  }
  elsif ($query{'pg_transaction_type'} eq "15") {
    $input{'mode'} = 'forceauth';
  }
  elsif ($query{'pg_transaction_type'} eq "20") {  ### ACH
    $input{'mode'} = 'auth';
    $input{'authtype'} = "authpostauth";
  }
  elsif ($query{'pg_transaction_type'} eq "21") {  ### ACH
    $input{'mode'} = 'auth';
  }
  elsif ($query{'pg_transaction_type'} eq "22") {
    $input{'mode'} = 'mark';
  }
  elsif ($query{'pg_transaction_type'} eq "23") {
    $input{'mode'} = 'newreturn';
  }
  elsif ($query{'pg_transaction_type'} eq "24") {
    $input{'mode'} = 'void';
  }
  elsif ($query{'pg_transaction_type'} eq "25") {  ## Charge - No Verification
    $input{'mode'} = 'null';
  }
  elsif ($query{'pg_transaction_type'} eq "26") {  ## Verification Only
    $input{'mode'} = 'null';
  }
  else {
    $input{'mode'} = 'null';
  }
  %query = (%query,%input);
  return %query;
}

sub output_authnet {
  my (%query) = @_;

  my %input = %query;

  foreach my $key (keys %input) {
    if($key =~ /^x_/i) {
      my $temp = $input{$key};
      delete $input{$key};
      $key =~ tr/A-Z/a-z/;
      $input{$key} = $temp;
    }
  }

  my $delimeter = ",";

  if ($input{'x_adc_delim_data'} =~ /^true$/i) {
    $input{'x_delim_data'} = "true";
  }
  if ($input{'x_adc_delim_character'} ne "") {
    $input{'x_delim_char'} = $input{'x_adc_delim_character'};
  }
  if ($input{'x_adc_url'} =~ /^false$/i) {
    $input{'x_relay_response'} = "false";
  }

  if ($input{'x_delim_char'} ne "") {
    $delimeter = $input{'x_delim_char'};
  }

  if ($query{'FinalStatus'} =~ /^(success|pending)$/) {
    $query{'x_response_code'} = "1"; # authnet 'approved' response
    $query{'x_response_subcode'} = $query{'resp-code'}; # PnP response code
    $query{'x_response_reason_code'} = "1"; # authnet transaction approved reason
    $query{'x_response_reason_text'} = "This transaction has been approved.";
    $query{'x_auth_code'} = $query{'auth-code'};
  }
  elsif ($query{'FinalStatus'} =~ /^(badcard)$/) {
    $query{'x_response_code'} = "2"; # authnet 'declined' response
    $query{'x_response_subcode'} = $query{'resp-code'}; # PnP response code
    $query{'x_response_reason_code'} = "2"; # authnet transaction declined reason
    $query{'x_response_reason_text'} = $query{'MErrMsg'};
  }
  elsif ($query{'FinalStatus'} =~ /^(fraud)$/) {
    $query{'x_response_code'} = "2"; # authnet 'declined' response
    $query{'x_response_subcode'} = $query{'resp-code'}; # PnP response code
    $query{'x_response_reason_code'} = "251"; # authnet transaction fraudulent reason
    $query{'x_response_reason_text'} = $query{'MErrMsg'};
  }
  elsif ( ($query{'FinalStatus'} =~ /^(problem)$/) && ($query{'accttype'} =~ /^(checking)$/i) && ($query{'niscflg'} == 1) && (-e "/home/p/pay1/batchfiles/alliance/maintenance.txt")  ) {
    $query{'x_response_code'} = "2";
    $query{'x_response_subcode'} = $query{'resp-code'}; # PnP response code
    $query{'x_response_reason_code'} = "25"; # authnet transaction error reason, try again later
    $query{'x_response_reason_text'} = "System Down for Maintenance.";
  }
  else {
    $query{'x_response_code'} = "3"; # authnet 'error' response
    $query{'x_response_subcode'} = $query{'resp-code'}; # PnP response code
    $query{'x_response_reason_code'} = "19"; # authnet general transaction error reason
    $query{'x_response_reason_text'} = $query{'MErrMsg'};
  }

  $query{'x_amount'} = $query{'card-amount'};
  $query{'x_avs_code'} = $query{'avs-code'};
  $query{'x_trans_id'} = $query{'orderID'};
  ($query{'x_first_name'},$query{'x_last_name'}) = split(/ /,$query{'card-name'}, 2);
  ($query{'x_ship_to_first_name'},$query{'x_ship_to_last_name'}) = split(/ /,$query{'shipname'}, 2);

  my @delete_array = ('orderID','card-number','card-exp','card-amount','card-name','card-address1','card-address2','card-city','card-state','card-zip','card-country','publisher-name','shipname','address1','city','state','zip','country','phone','email','MErrMsg','auth-code','auth-msg','merchant','easycart','auth_date','publisher-password','shipinfo','currency','mode','month-exp','year-exp','publisher-email','card-cvv','referrer','User-Agent','IPaddress','x_Card_Num');

  if ( (($input{'x_delim_data'} =~ /^true$/i) && ($input{'x_relay_response'} =~ /^false$/i)) || ($query{'client'} =~ /^(dallasmust|dydacomp)$/) ) {

    my @resp1 = ('x_response_code','x_response_subcode','x_response_reason_code','x_response_reason_text','x_auth_code','x_avs_code','x_trans_id','x_invoice_num','x_description','x_amount','x_method','x_type','x_cust_id','x_first_name','x_last_name','x_company','x_address','x_city','x_state','x_zip','x_country','x_phone','x_fax','x_email','x_ship_to_first_name','x_ship_to_last_name','x_ship_to_company','x_ship_to_address','x_ship_to_city','x_ship_to_state','x_ship_to_zip','x_ship_to_country','x_tax','x_duty','x_freight','x_tax_exempt','x_po_num','x_MD5_hash','x_cvv2_resp_code');

    my %resp2 = ('x_response_code',"$query{'x_response_code'}",'x_response_subcode',"$query{'x_response_subcode'}",'x_response_reason_code',"$query{'x_response_reason_code'}",'x_response_reason_text',"$query{'x_response_reason_text'}",'x_auth_code',"$query{'x_auth_code'}",'x_avs_code',"$query{'avs-code'}",'x_trans_id',"$query{'orderID'}",'x_invoice_num',"$query{'order-id'}",'x_description',"$query{'x_description'}",'x_amount',"$query{'x_amount'}",'x_method',"$query{'x_method'}",'x_type',"$query{'x_type'}",'x_cust_id',"$query{'x_cust_id'}",'x_first_name',"$query{'x_first_name'}",'x_last_name',"$query{'x_last_name'}",'x_company',"$query{'card-company'}",'x_address',"$query{'card-address1'}",'x_city',"$query{'card-city'}",'x_state',"$query{'card-state'}",'x_zip',"$query{'card-zip'}",'x_country',"$query{'card-country'}",'x_phone',"$query{'phone'}",'x_fax',"$query{'fax'}",'x_email',"$query{'email'}",'x_ship_to_first_name',"$query{'x_ship_to_first_name'}",'x_ship_to_last_name',"$query{'x_ship_to_last_name'}",'x_ship_to_company',"$query{'shipcompany'}",'x_ship_to_address',"$query{'address1'}",'x_ship_to_city',"$query{'city'}",'x_ship_to_state',"$query{'state'}",'x_ship_to_zip',"$query{'zip'}",'x_ship_to_country',"$query{'country'}",'x_tax',"$query{'tax'}",'x_duty',"$query{'x_duty'}",'x_freight',"$query{'shipping'}",'x_tax_exempt',"$query{'x_tax_exempt'}",'x_po_num',"$query{'ponumber'}",'x_MD5_hash',"$query{'resphash'}",'x_cvv2_resp_code',"$query{'cvvresp'}");

    my ($resp);

    if ($query{'client'} =~ /^(dallasmust|dydacomp)$/) {
      $delimeter = '","';
    }

    foreach my $var (@resp1) {
      $resp .= $input{'x_encap_char'} . "$resp2{$var}" . $input{'x_encap_char'} . $delimeter;
    }

    if ($query{'client'} =~ /^(dallasmust|dydacomp)$/) {
      $resp .= $query{'mode'} . $delimeter . $query{'authtype'} ."\"";
      $resp = "\"" . $resp;
    }
    else {
      $resp .= "\n";
    }

    if ((($query{'testmode'} =~ /debug/i) || ($query{'mode'} =~ /debug/i) || ($remote::logall eq "yes"))
        && ($query{'mode'} !~ /query_trans/i)) {
      my $t = $resp;
      $t =~ s/\n//g;
      my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
      my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
      my $etime = time() - $remote::time;
      if (!PlugNPay::Environment::isContainer()) {
        open(DEBUG,">>$remote::path_debug");
        print DEBUG "AUTHNET DATE:$now, TIME:$etime, IP:$remote::remoteaddr, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, BROWSER:$ENV{'HTTP_USER_AGENT'}, PID:$remote::pid, VERSION:$remote::version, MERCHANT:$query{'publisher-name'}, ";
        my $masked = "MASKED";
        $t =~ s/([\D])([3-7]\d{13,16})([\D])/$1$masked$2/g;
        print DEBUG "ReturnStrng:$t:";
        print DEBUG "\n\n";
        close(DEBUG);
      }
    }

    my $length = length($resp);

    print header( -type=>'text/html',-Content_length=>"$length" );
    #print "Content-Length: $length\n";   ### DCP 20100713 Added CL back using CGI
    #print "Content-Type: text/html\n\n";
    print "$resp";
    #&record_time(\%remote::times);
    exit;
    #$remote::response_type = "text";
  }
}

sub output_authnet_cp {
  require authnet_emulation;

  my (%query) = @_;

  my %input = %query;

  my $authnet = authnet->new();

  foreach my $key (keys %input) {
    if($key =~ /^x_/i) {
      my $temp = $input{$key};
      delete $input{$key};
      $key =~ tr/A-Z/a-z/;
      $input{$key} = $temp;
    }
  }

  my $delimeter = "|";

  if ($input{'x_delim_char'} ne "") {
    $delimeter = $input{'x_delim_char'};
  }

  if ($query{'FinalStatus'} =~ /^(success|pending)$/) {
    $query{'x_response_code'} = "1";
    $query{'x_auth_code'} = $query{'auth-code'};
    $query{'resp-code'} = "00";
  }
  elsif ($query{'FinalStatus'} =~ /^(badcard)$/) {
    $query{'x_response_code'} = "2";
  }
  else {
    $query{'x_response_code'} = "3";
  }

  my (%map,$resp,$resptxt);
  my $respcode = $query{'resp-code'};

  #print "RC:$respcode, PROC:$mckutils::processor<br>\n";

  if ($mckutils::processor eq "testprocessor") {
    %map = %authnet::testprocessor_map;
  }
  elsif ($mckutils::processor eq "paytechtampa") {
    %map = %authnet::paytechtampa_map;
  }
  elsif ($mckutils::processor eq "moneris") {
    %map = %authnet::moneris_map;
  }

  if (exists $authnet::pnp_map{'$respcode'}) {
    $resp = $authnet::pnp_map{'$respcode'};
  }
  elsif (exists $map{$respcode}) {
    $resp = $map{$respcode};
  }
  else {
    #$resp = "9";  ####  Response map not found return "This reason code is reserved or not applicable to this API."
    $resp = $respcode;  #### DCP 20110111 - At request of Tony Kamin
    $query{'x_response_reason_text'} = $query{'MErrMsg'};   #### DCP 20110111
  }

  $query{'respcode'} = $resp;

  if ((exists $authnet::errorcodes{$resp}) && ($query{'x_response_reason_text'} eq "")) {  ### DCP 20110111
    $query{'x_response_reason_text'} = $authnet::errorcodes{$resp};
  }
  else {
    $query{'x_response_reason_text'} = $query{'MErrMsg'};
  }

  $query{'x_amount'} = $query{'card-amount'};
  $query{'x_avs_code'} = $query{'avs-code'};
  $query{'x_trans_id'} = $query{'orderID'};

  if ($input{'x_response_format'} == 1) {

    my @resp1 = ('x_cpversion','x_response_code','x_response_reason_code','x_response_reason_text','x_auth_code','x_avs_code','x_cvv2_resp_code','x_trans_id','x_MD5_hash','x_user_ref');

    my %resp2 = ('x_cpversion',"$query{'x_cpversion'}",'x_response_code',"$query{'x_response_code'}",'x_response_reason_code',"$query{'respcode'}",'x_response_reason_text',"$query{'x_response_reason_text'}",'x_auth_code',"$query{'x_auth_code'}",'x_avs_code',"$query{'avs-code'}",'x_trans_id',"$query{'orderID'}",'x_invoice_num',"$query{'order-id'}",'x_description','','x_amount',"$query{'x_amount'}",'x_MD5_hash',"$query{'resphash'}",'x_cvv2_resp_code',"$query{'cvvresp'}",'x_user_ref',"$query{'x_user_ref'}");

    my ($resp);

    foreach my $var (@resp1) {
      $resp .= $input{'x_encap_char'} . "$resp2{$var}" . $input{'x_encap_char'} . $delimeter;
    }

    $resp .= "\n";

    if ((($query{'testmode'} =~ /debug/i) || ($query{'mode'} =~ /debug/i) || ($remote::logall eq "yes"))
        && ($query{'mode'} !~ /query_trans/i)) {
      my $t = $resp;
      $t =~ s/\n//g;
      my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
      my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
      my $etime = time() - $remote::time;
      if (!PlugNPay::Environment::isContainer()) {
        open(DEBUG,">>$remote::path_debug");
        print DEBUG "AUTHNET DATE:$now, TIME:$etime, IP:$remote::remoteaddr, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, BROWSER:$ENV{'HTTP_USER_AGENT'}, PID:$remote::pid, VERSION:$remote::version, MERCHANT:$query{'publisher-name'}, ";
        my $masked = "MASKED";
        $t =~ s/([\D])([3-7]\d{13,16})([\D])/$1$masked$2/g;
        print DEBUG "ReturnStrng:$t:";
        print DEBUG "\n\n";
        close(DEBUG);
      }
    }

    my $length = length($resp);

    print header( -type=>'text/html',-Content_length=>"$length" );
    print "$resp";

    exit;

  }
  else {
    ###  XML Response Goes Here
  }
}

sub output_achdirect {
  my (%query) = @_;

  my (%input);

  my $delimeter = "\n";

  if ($query{'FinalStatus'} =~ /^(success|pending)$/) {
    $input{'pg_response_type'} = "A";
    $input{'pg_authorization_code'} = $query{'auth-code'};
    $input{'pg_avs_result'} = $query{'avsresp'};
  }
  elsif ($query{'FinalStatus'} =~ /^(badcard)$/) {
    $input{'pg_response_type'} = "D";
    $input{'pg_response_code'} = $query{'respcode'};
    $input{'pg_response_description'} = $query{'MErrMsg'};
  }
  else {
    $input{'pg_response_type'} = "E";
    $input{'pg_response_code'} = $query{'respcode'};
    $input{'pg_response_description'} = $query{'MErrMsg'};
  }

  for (my $i=1; $i<=9; $i++) {
    my $key = "pg_merchant_data_$i";
    if (exists $query{$key}) {
      $input{$key} = $query{$key};
    }
  }

  $input{'pg_merchant_id'} = $query{'publisher-name'};
  $input{'pg_transaction_type'} = $query{'pg_transaction_type'};

  my %datamap = ('publisher-name','pg_merchant_id','publisher-password','pg_password','x_mode','pg_transaction_type ','card-amount','pg_total_amount ','tax','pg_sales_tax_amount ','pg_consumer_id','pg_consumer_id','order-id','ecom_consumerorderid ','ecom_walletid','ecom_walletid ','card-company','pg_billto_postal_name_company ','card-fname','ecom_billto_postal_name_first ','card-lname','ecom_billto_postal_name_last ','card-address1','ecom_billto_postal_street_line1 ','card-address2','ecom_billto_postal_street_line2 ','card-city','ecom_billto_postal_city ','card-state','ecom_billto_postal_stateprov ','card-zip','ecom_billto_postal_postalcode ','card-Country','ecom_billto_postal_countrycode ','phone','ecom_billto_telecom_phone_number ','email','ecom_billto_online_email ','ssn','pg_billto_ssn ','licensenum','pg_billto_dl_number ','licensestate','pg_billto_dl_state ','dateofbirth','pg_billto_date_of_birth ','acct_code','pg_entered_by ','card-type','Ecom_payment_card_type ','card-name','ecom_payment_card_name ','card-number','ecom_payment_card_number ','Month-exp','ecom_payment_card_expdate_month ','Year-exp','ecom_payment_card_expdate_year ','card-cvv','ecom_payment_card_verification ','commcardtype','pg_procurement_card ','ponumber','pg_customer_acct_code ','magswipe','pg_cc_swipe_data ','transflags','pg_mail_or_phone_order','routingnum','ecom_payment_check_trn','accountnum','ecom_payment_check_account','accttype','ecom_payment_check_account_type','checknum','ecom_payment_check_checkno','checktype','pg_entry_class_code');

  my %resp = ('pg_total_amount','card-amount','pg_sales_tax_amount','tax','pg_consumer_id','pg_consumer_id','ecom_consumerorderid','ecom_consumerorderid','ecom_walletid','ecom_walletid','ecom_billto_postal_name_first','ecom_billto_postal_name_first','ecom_billto_postal_name_last','ecom_billto_postal_name_last','pg_billto_postal_name_company','card-company','ecom_billto_online_email','email');

  my %auth_resp = ('pg_avs_result','avs-resp','pg_trace_number','orderID','pg_authorization_code','auth-code','pg_preauth_result','pg_preauth_result','pg_preauth_description','pg_preauth_result');
  my %void_resp = ();
  my %return_resp = ();

  if ($query{'mode'} =~ /^(auth)$/) {
    %resp = %auth_resp;
  }
  elsif ($query{'mode'} =~ /^(void)$/) {
    %resp = %void_resp;
  }
  elsif ($query{'mode'} =~ /^(return)$/) {
    %resp = %return_resp;
  }

  foreach my $key (keys %resp) {
    $input{$key} = $query{$resp{$key}};
  }

  my ($resp);

  foreach my $key (sort keys %input) {
    $resp .= "$key" . "=" . "$input{$key}" . "\n";
  }

  my $length = length($resp);
  print header( -type=>'text/html',-Content_length=>"$length" );
  print "$resp";
  exit;
}

sub output_miva {
  my (%query) = @_;
  $query{'aux-msg'} =~ s/\:/ /g;
  $query{'auth-msg'} =~ s/\:/ /g;
  $query{'auth-msg'} = substr($query{'auth-msg'},0,124);
  %query = &hyphen_to_underscore(%query);
  %query = &lower_to_uppercase(%query);
  return (%query);
}

sub support_email {
  my ($message) = @_;

  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setFormat('text');

  if ($remote::query{'notify-email'} ne "") {
    $emailObj->setTo($remote::query{'notify-email'});
    $emailObj->setCC('dprice@plugnpay.com');
  } elsif ($remote::query{'publisher-email'} ne "") {
    $emailObj->setTo($remote::query{'publisher-email'});
    $emailObj->setCC('dprice@plugnpay.com');
  } else {
    $emailObj->setTo('dprice@plugnpay.com');
  }

  $emailObj->setFrom('pnpremote@plugnpay.com');
  $emailObj->setSubject("pnpremote $remote::query{'mode'} failure");

  $message = "publisher-name: $remote::query{'publisher-name'}\n" . $message;
  $emailObj->setContent($message);

  $emailObj->send();
}

#####  Membership Management Support  #####
###  Should add data validity check for some membership routines.
sub getRecurringCustomerTableLengths {
  my $database = shift;
  my $options = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $tableInfo = $dbs->getColumnsForTable({
    database => $database,
    table => 'customer'
  });

  my %lengthInfo = map { $_ => $tableInfo->{$_}{'length'} } keys %{$tableInfo};
  # TODO could someone add a comment as to why this even needs to exist?  Cargo Cult?
  # Dave wants to know too, this was the code this is replacing, including Dave's comment
  # ### WTF is this for ?  DCP 20131101
  # if ($db_length > 5) {
  #   $length_hash{$db_name} = $db_length-1;
  # }
  # else {
  #   $length_hash{$db_name} = $db_length;
  # }
  if ($options->{'gt5sub1'}) {
    foreach my $key (keys %lengthInfo) {
      if ($lengthInfo{$key} > 5) {
        $lengthInfo{$key} -= 1;
      } elsif (!$options->{'gt5else'}) { # TODO also why?  WHY?!!
        delete $lengthInfo{$key};
      }
    }
  }

  return \%lengthInfo;
}

# check if database exists for Membership Management service 
sub checkDBExists {
  my $database = shift;
  my ( $dbh, $error );

  eval {
    $dbh =  &miscutils::dbhconnect("$database");
  };

  if ($@) {
    $error = $@;
  }

  return $dbh, $error;
}

# log error and return error when account is not subscribed to a Membership Management service.
sub handleModeNotPermitted {
  my $resultHash = shift;
  my $error = shift;
  my $result = { %$resultHash };

  my $logger = new PlugNPay::Logging::DataLog({ collection => 'remote_strict' });
  my $stackTrace = new PlugNPay::Util::StackTrace()->string();
  $logger->log({message => 'An error occurred while attempting to load db info.', error => $error, stackTrace => $stackTrace });

  $result->{'FinalStatus'} = "problem";
  if ($error =~ /^Failed to load db info/i) {
    $result->{'resp-code'} = "P93";
    $result->{'MErrMsg'} = "Mode not permitted for this account.";
  } else {
    $result->{'MErrMsg'} = "Unknown error, please contact support.";
  }

  return %$result;
}

sub add_member {

  my $env = new PlugNPay::Environment();
  my $remote_ip = $env->get('PNP_CLIENT_IP');

  my (%query) = %remote::query;
  my $untest = "";
  my ($expire,$time,$dummy1,$dummy2,$dummy3,$sday,$smonth,$syear,$eday,$emonth,$eyear,$start,$database,$datestr,$timestr,$orderid,$monthday,$expiremonth,%result);

  $orderid = PlugNPay::Transaction::TransactionProcessor::generateOrderID();
  ($datestr,$timestr) = &miscutils::gendatetime_only();

  if ($query{'orderID'} eq "") {
    $query{'orderID'} = $orderid;
    $query{'orderID'} = "MM$query{'orderID'}";
  }

  if ($query{'expire'} ne "") {
    $expire = $query{'expire'};
  }
  elsif ($query{'enddate'} ne "") {
    $expire = $query{'enddate'};
  }
  else {
    $time = time();
    $smonth = $smonth + 1;
    $syear = $syear + 1900;

    ($dummy1,$dummy2,$dummy3,$eday,$emonth,$eyear) = gmtime($time+($query{'days'}*3600*24));
    $emonth = $emonth + $query{'months'};
    $eyear = $eyear + 1900 + (($emonth - ($emonth%12)) / 12);
    $emonth = ($emonth % 12) + 1;

    $expire = sprintf("%04d%02d%02d",$eyear,$emonth,$eday);
    $monthday = substr($expire,4,4);
    if ((($monthday > "0930") && ($monthday < "1001"))
        || (($monthday > "0430") && ($monthday < "0501"))
        || (($monthday > "0630") && ($monthday < "0701"))
        || (($monthday > "1130") && ($monthday < "1201"))
        || (($monthday > "0228") && ($monthday < "0301"))) {
      $expiremonth = substr($expire,4,2) + 1;
      if ($expiremonth > 12) {
        $expire = sprintf("%04d%02d%02d", substr($expire,0,4)+1, $expiremonth-12, 1);
      }
      else {
        $expire = sprintf("%04d%02d%02d", substr($expire,0,4), $expiremonth, 1);
      }
    }
  }

  if ($query{'start'} ne "") {
    $start = $query{'start'};
  }
  elsif ($query{'startdate'} ne "") {
    $start = $query{'startdate'};
  }
  else {
    $start = $datestr;
  }

  $query{'startdate'} = substr($start,0,8);
  $query{'enddate'} = substr($expire,0,8);

  if ($query{'merchantdb'} ne "") {
    $database = $query{'merchantdb'};
  }
  else {
   $database = $query{'publisher-name'};
  }

  # Membership Management service, check if account has this service 
  # by checking if the database exists.
  my ( $dbh, $error ) = &checkDBExists($database);
  if ($error && !defined $dbh) {
    return &handleModeNotPermitted(\%result, $error);
  }

  my $sth = $dbh->prepare(qq{
       select username
       from customer
       where username=?
     }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
   $sth->execute($query{'username'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%query);
   $sth->bind_columns(undef,\($untest));
   $sth->fetch;
   $sth->finish;

  if (($untest eq "") && ($query{'username'} ne "")) {
    if (($query{'card-number'} ne "")) {
      $query{'card-number'} =~ s/\D//g;
      my $cc = new PlugNPay::CreditCard($query{'card-number'});
      if (cardIsPotentiallyValid($cc)) {
        $query{'shacardnumber'} = $cc->getCardHash();
        ($query{'enccardnumber'},$query{'encryptedDataLen'}) = &rsautils::rsa_encrypt_card($query{'card-number'},"/home/p/pay1/pwfiles/keys/key");
      }
      else {
        $dbh->disconnect;
        $result{'aux-msg'} .= "Credit card number failed luhn test.";
        $result{'resp-code'} = "P55";
        return %result;
      }
    }
    if (($query{'accountnum'} ne "") && ($query{'routingnum'} ne "")) {
      my $modtest = &miscutils::mod10($query{'routingnum'});
      if ($modtest eq "success") {
        $query{'card-number'} = $query{'routingnum'} . " " . $query{'accountnum'};
        my $cc = new PlugNPay::OnlineCheck();
        $cc->setABARoutingNumber($query{'routingnum'});
        $cc->setAccountNumber($query{'accountnum'});
        $query{'shacardnumber'} = $cc->getCardHash();
        ($query{'enccardnumber'},$query{'encryptedDataLen'}) = &rsautils::rsa_encrypt_card($query{'card-number'},"/home/p/pay1/pwfiles/keys/key");
      }
      else {
        $dbh->disconnect;
        $result{'aux-msg'} .= "Bank routing number failed mod10 test.";
        $result{'resp-code'} = "P53";
        return %result;
      }
    }

    my $map_hash = {
      'name'        => 'card-name',
      'addr1'       => 'card-address1',
      'addr2'       => 'card-address2',
      'country'     => 'card-country',
      'city'        => 'card-city',
      'state'       => 'card-state',
      'zip'         => 'card-zip',
      'shipaddr1'   => 'address1',
      'shipaddr2'   => 'address2',
      'shipcity'    => 'city',
      'shipstate'   => 'state',
      'shipzip'     => 'zip',
      'shipcountry' => 'country',
      'monthly'     =>'recfee',
      'lastbilled'  => 'startdate',
      'exp'         => 'card-exp',
      'cardnumber'  => 'card-number',
      'orderid'     => 'orderID',
    };

    my $skip_hash = {
      'id'            => 1,
      'result'        => 1,
      'lastattempted' => 1,
      'acct_code4'    => 1,
    };

    my $length_hash = getRecurringCustomerTableLengths($database, { gt5sub1 => 1 });

    $query{'enccardnumber'} = &smpsutils::storecardnumber($database,$query{'username'},'add_member',$query{'enccardnumber'},'rec');
    if (($remote::accountFeatures->get('enableToken') == 1) && ($query{'card-number'} ne '')) {
      my $token = new PlugNPay::Token();
      $result{'token'} = $token->getToken($query{'card-number'});
    }

    if (($query{'currency'} ne "") && ($length_hash->{'monthly'} >= 11)) {
      my $amount = $query{'recfee'};
      $query{'recfee'} = sprintf("%3s %.2f","$query{'currency'}",$amount);
    }

    if ($query{'card-number'} ne "") {
      if ($length_hash->{'cardnumber'} > 12) {
        $query{'card-number'} = substr($query{'card-number'},0,6) . '**' . substr($query{'card-number'},length($query{'card-number'})-2,2);
      }
      else {
        $query{'card-number'} = substr($query{'card-number'},0,4) . '**' . substr($query{'card-number'},length($query{'card-number'})-2,2);
      }
    }

    my $sql ="insert into customer (";
    my $qmark = "";
    my @array = ();
    my %data = ();
    foreach my $testvar (keys %$length_hash) {
      if (exists $skip_hash->{$testvar}) {
        next;
      }
      my $hashkey = "";
      my $val = "";
      if (exists $map_hash->{$testvar}) {
        $hashkey = $map_hash->{$testvar};
      }
      else {
        $hashkey = $testvar;
      }
      if (length($query{$hashkey}) > $length_hash->{$testvar}) {
        $val = substr($query{$hashkey},0,$length_hash->{$testvar});
      }
      else {
        $val = $query{$hashkey};
      }
      $sql .= "$testvar,";
      $qmark .= "?,";
      push (@array,"$val");

    }
    chop $sql;
    chop $qmark;
    $sql .= ") values ($qmark)";

    my $sth = $dbh->prepare(qq{$sql}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
    $sth->execute(@array) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%query);
    $sth->finish;

    $result{'FinalStatus'} = "success";
    $result{'aux-msg'} .= " username $query{'username'} has been successfully added to the members database.";
    $result{'resp-code'} .= "P00";
  }
  else {
    $result{'FinalStatus'} = "problem";
    if ($query{'username'} ne "") {
      $result{'MErrMsg'} .= " username $query{'username'} and/or orderid aleady exists.";
      $result{'resp-code'} .= "P40";
    }
    else {
      $result{'MErrMsg'} .= " null not allowed in field: username";
      $result{'resp-code'} .= "P41";
    }
  }

  if ($result{'FinalStatus'} eq "success") {
    my $action = "Acct Added";
    my $myusername = substr($query{'username'},0,24);
    my $reason = "Remote by $remote_ip";
    $reason = substr($reason,0,255);
    my $now = time();

    my $sth_history = $dbh->prepare(q{
        insert into history
        (trans_time,username,action,descr)
        values (?,?,?,?)
      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
    $sth_history->execute($now,$myusername,$action,$reason) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
    $sth_history->finish;
  }

  $dbh->disconnect;
  return %result;
}

sub delete_member {
  my (%query) = %remote::query;
  my ($database,%result);

  if ($query{'merchantdb'} ne "") {
    $database = $query{'merchantdb'};
  }
  else {
   $database = $query{'publisher-name'};
  }

  # Membership Management service, check if account has this service 
  # by checking if the database exists.
  my ( $dbh, $error ) = &checkDBExists($database);
  if ($error && !defined $dbh) {
    return &handleModeNotPermitted(\%result, $error);
  }
  
  my $sth = $dbh->prepare(qq{
      select username
      from customer
      where username=?
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
  $sth->execute($query{'username'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%query);
  my ($untest) = $sth->fetchrow;
  $sth->finish;

  if ($untest ne "") {
    my $sth = $dbh->prepare(qq{
        delete from customer
        where username=?
      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
    $sth->execute($query{'username'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
    $sth->finish;
    $result{'FinalStatus'} = "success";
    $result{'aux-msg'} = "Username $query{'username'} has been removed from the database.";
  }
  else {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Username $query{'username'} does not exist in the database.";
  }

  my $action = "Account Deleted";
  my $reason = "Remote Request";
  &record_history($query{'username'},$action,$reason,$database,$dbh);

  $dbh->disconnect;
  return %result;
}

sub clone_member {
  # Required fields
  # merchantdb or publisher-name
  # username of member
  # newusername for cloned account
  # new password is optional
  my (%query) = %remote::query;
  my ($database,%result);

  if ($query{'merchantdb'} ne "") {
    $database = $query{'merchantdb'};
  }
  else {
    $database = $query{'publisher-name'};
  }

  if ($query{'username'} eq "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "You need to pass a username, refer to documentation for required fields.";
    return %result;
  }
  elsif ($query{'newusername'} eq "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "You need to pass a username for the cloned account, refer to documentation for required fields.";
    return %result;
  }

  # Membership Management service, check if account has this service 
  # by checking if the database exists.
  my ( $dbh, $error ) = &checkDBExists($database);
  if ($error && !defined $dbh) {
    return &handleModeNotPermitted(\%result, $error);
  }

  my $sth = $dbh->prepare(qq{
      select username
      from customer
      where username=?
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
  $sth->execute($query{'newusername'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%query);
  my ($test) = $sth->fetchrow;
  $sth->finish;

  if ($test ne "") {
    $result{'FinalStatus'} = "problem";
    $result{'aux-msg'} .= " username $query{'newusername'} already exists and can not be used.";
    $result{'resp-code'} .= "P99";
  }
  else {
    my $sth = $dbh->prepare(qq{
        select *
        from customer
        where username=?
      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
    $sth->execute($query{'username'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%query);
    my $data = $sth->fetchrow_hashref or $result{'FinalStatus'} = "problem";
    $sth->finish;

    if ($$data{'username'} eq "") {
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = "Username does not exist. No record found.";
    }
    else {
      my @array = ();
      my ($qmark);
      $$data{'username'} = "$query{'newusername'}";
      if ($query{'password'} ne "") {
        $$data{'password'} = $query{'password'};
      }

      $$data{'enccardnumber'} = &smpsutils::storecardnumber($database,$$data{'username'},'clone_member',$$data{'enccardnumber'},'rec');

      my $sql = "insert into customer ( ";
      foreach my $key (keys %$data) {
        $qmark .= "?,";
        push (@array,$$data{$key});
        $sql .= "$key,";
      }
      chop $qmark;
      chop $sql;
      $sql .= ") values (" . $qmark . ")";

      my $sth = $dbh->prepare(qq{$sql}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
      $sth->execute(@array) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%query);
      $sth->finish;

      my $sth2 = $dbh->prepare(qq{
          select username
          from customer
          where username=?
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
      $sth2->execute($query{'newusername'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%query);
      my ($test) = $sth2->fetchrow;
      $sth2->finish;

      if ($test ne "") {
        $result{'FinalStatus'} = "success";
        $result{'aux-msg'} .= " username $query{'newusername'} has been successfully added to the members database.";
        $result{'resp-code'} .= "P00";
      }
      else {
        $result{'FinalStatus'} = "problem";
        $result{'MErrMsg'} = "Record Not Created.";
      }
    }
  }

  $dbh->disconnect;
  return %result;
}

sub query_member {
# Required fields
# merchantdb or publisher-name
# username of member
  my (%query) = %remote::query;
  my ($database,%result);
  if ($query{'merchantdb'} ne "") {
    $database = $query{'merchantdb'};
  }
  else {
   $database = $query{'publisher-name'};
  }

  if ($query{'username'} eq "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "You need to pass a username, refer to documentation for required fields.";
    return %result;
  }

  my @db_array = ('username','orderid','plan','purchaseid','name','company','addr1','addr2','city','state','zip','country','shipname','shipaddr1','shipaddr2','shipcity','shipstate','shipzip','shipcountry','phone','fax','email','billcycle','startdate','enddate','monthly','cardnumber','exp','lastbilled','lastattempted','status','result','acct_code','accttype','enccardnumber','length','password','balance');

  my $db_query = "select *";
  $db_query .= " from customer";
  if ($remote::accountFeatures->get('allow_un_fuzzy') == 1) {
    $db_query .= " where lower(username) = lower(?)";
  }
  else {
    $db_query .= " where username=?";
  }

  # Membership Management service, check if account has this service 
  # by checking if the database exists.
  my ( $dbh, $error ) = &checkDBExists($database);
  if ($error && !defined $dbh) {
    return &handleModeNotPermitted(\%result, $error);
  }

  my $sth = $dbh->prepare(qq{ $db_query }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
  $sth->execute($query{'username'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%query);
  my $data = $sth->fetchrow_hashref or $result{'FinalStatus'} = "problem";
  $sth->finish;
  $dbh->disconnect;

  my $cd = new PlugNPay::CardData();
  my $encrypted_card_data = '';
  eval {
    if ($data->{'username'}) {
      $encrypted_card_data = $cd->getRecurringCardData({ customer => "$query{'username'}", username => "$database", suppressAlert => 1 });
    }
  };
  if (!$@) {
    $data->{'enccardnumber'} = $encrypted_card_data;
  }

  foreach my $var (@db_array) {
    if (exists $$data{$var}) {
      $result{$var} = $$data{$var};
    }
  }

  if ($result{'enccardnumber'} ne "") {
    my $cardnumber = &rsautils::rsa_decrypt_file($result{'enccardnumber'},$result{'length'},"print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");
    if ($cardnumber !~ /(\d+) (\d+)/) {
      my $cc = new PlugNPay::CreditCard($cardnumber);
      $result{'card-type'}  = $cc->getBrand();
    }
    else {
      $result{'card-type'} = "ACH";
    }
    $result{'cardnumber'} = substr($cardnumber,0,6) . '**' . substr($cardnumber,-4); # Format: first6, **, last4
  }
  delete $result{'enccardnumber'};
  delete $result{'length'};

  if (($remote::accountFeatures->get('api_qrymem_givepass') == 1) && ($result{'password'} ne '')) {
    my $hasher = new PlugNPay::Util::Hash();
    $hasher->add($result{'password'});
    $result{'password'} = $hasher->bcrypt();
    if ($remote::accountFeatures->get('bcrypt_php_compat')) {
      $result{'password'} =~ s/^\$2a/\$2y/;
    }
  }
  else {
    delete $result{'password'};
  }

  if ($result{'FinalStatus'} ne "problem") {
    $result{'FinalStatus'} = "success";
  }
  elsif ($result{'FinalStatus'} eq "problem") {
    $result{'aux-msg'} = "Username does not exist.";
  }

  return %result;
}

sub query_member_fuzzy {
  # Required fields
  # merchantdb or publisher-name
  # username of member
  my (%query) = %remote::query;
  my ($database,%result,@bindvalues,$idx);

  if ($query{'merchantdb'} ne "") {
    $database = $query{'merchantdb'};
  }
  else {
    $database = $query{'publisher-name'};
  }

  if ($query{'username'} eq "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "You need to pass a username, refer to documentation for required fields.";
    return %result;
  }

  my @db_array = ('username','orderid','plan','purchaseid','name','company','addr1','addr2','city','state','zip','country','shipname','shipaddr1','shipaddr2','shipcity','shipstate','shipzip','shipcountry','phone','fax','email','billcycle','startdate','enddate','monthly','cardnumber','exp','lastbilled','lastattempted','status','result','acct_code','accttype','enccardnumber','length');

  my $db_query = "select ";
  for (my $i=0; $i<=$#db_array; $i++) {
    $db_query = $db_query . $db_array[$i] . "\,";
  }
  chop $db_query;

  my ($srchun);
  if ($query{'fuzzyflg'} == 1) {
    if (length($query{'username'}) < 8) {
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = "Username is below the minimum length of 8.";
      return %result;
    }
    $db_query .= " from customer where username LIKE ?";
    $srchun = "$query{'username'}%"
  }
  else {
    $db_query .= " from customer where username=?";
    $srchun = "$query{'username'}"
  }

  # Membership Management service, check if account has this service 
  # by checking if the database exists.
  my ( $dbh, $error ) = &checkDBExists($database);
  if ($error && !defined $dbh) {
    return &handleModeNotPermitted(\%result, $error);
  }

  my $sth = $dbh->prepare(qq{$db_query}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
  $sth->execute("$srchun") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%query);
  while (my $data = $sth->fetchrow_hashref) {
    $idx = sprintf("%05d" ,$idx);

    my $cd = new PlugNPay::CardData();
    my $ecrypted_card_data = '';
    eval {
      $ecrypted_card_data = $cd->getRecurringCardData({customer => "$data->{'username'}", username => "$database"});
    };
    if (!$@) {
      $data->{'enccardnumber'} = $ecrypted_card_data;
    }

    if (($data->{'enccardnumber'} ne "") && ($data->{'cardnumber'} !~ /^(\d[6]\*\*\d[4])$/)) {
      my $cardnumber = &rsautils::rsa_decrypt_file($data->{'enccardnumber'},$data->{'length'},"print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");
      $data->{'cardnumber'} = substr($cardnumber,0,6) . '**' . substr($cardnumber,-4); # Format: first6, **, last4
      delete $data->{'enccardnumber'};
      delete $data->{'length'};
    }

    foreach my $key (keys %$data) {
      my $hashkey = $key;
      $hashkey =~ tr/A-Z/a-z/;
      if ($data->{'qm_version'} == 2) {
        $result{"a$idx"} .= "$hashkey\=$data->{$key}\&";
      }
      else {
        $result{"$hashkey"} = "$data->{$key}";
      }
    }
    if (exists $result{"a$idx"}) {
    #if (($query{'fuzzyflg'} == 1) || ($query{'qm_version'} == 2)) {
      chop $result{"a$idx"};
    }
    $idx++;
  }
  $sth->finish;
  $dbh->disconnect;

  if ($idx < 1) {
    $result{'FinalStatus'} = "problem";
    $result{'aux-msg'} = "Username does not exist.";
    if ($query{'qm_version'} != 2) {
      for (my $i=0;$i<=$#db_array;$i++) {
        $result{$db_array[$i]} = "";
      }
    }
  }
  else {
    $result{'membrcnt'} = $idx+0;
    $result{'FinalStatus'} = "success";
  }

  return %result;
}

sub list_members {
  # Purpose: obtain list of active/expired members (simular to refresh script)

  # Required Fields:
  # 'merchantdb' or 'publisher-name'

  # Optional Fields:
  # 'status' = 'active', 'expired', or 'all' [assumes 'active' when NULL]
  # 'crypt'  = 'bcrypt', 'omit' or 'blank'

  my (%query) = %remote::query;
  my ($database,%result);

  if ($query{'merchantdb'} ne "") {
    $database = $query{'merchantdb'};
  }
  else {
    $database = $query{'publisher-name'};
  }

  if (exists $query{'status'}) {
    $query{'status'} =~ tr/A-Z/a-z/;
    $query{'status'} =~ s/[^a-z]//g;
  }
  if (exists $query{'crypt'}) {
    $query{'crypt'} =~ tr/A-Z/a-z/;
    $query{'crypt'} =~ s/[^a-z]//g;
  }

  if (($query{'crypt'} ne '') && ($query{'crypt'} !~ /^(bcrypt|omit|blank)$/)) {
    $result{'FinalStatus'} = "problem";
    $result{'MStatus'} = "problem";
    $result{'MErrMsg'} = "Weak cryptographic algorithm specified. Contact technical support.";
    $result{'aux-msg'} = $result{'MErrMsg'};
    $result{'resp-code'} = 'P81';
    return %result;
  }

  # set defaults:
  if ($query{'status'} !~ /^(all|active|expired)$/) {
    $query{'status'} = "active";
  }

  # now do SQL query
  my @now = gmtime(time());
  my $today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

  my (@db_array,$ccexpflg);
  if (defined $query{'fields'}) {
    @db_array = split(/\s+/,$query{'fields'});
  } elsif ($query{'expcc'} =~ /^(1|2|3)$/) {
    $ccexpflg = 1;
    @db_array = ('username','exp');
  } else {
    @db_array = ('username','password','enddate','purchaseid');
  }

  my $idx = 0;

  ## profile all data per customer record
  my $db_query = "select ";
  if ($query{'alldata'} eq "yes") {
    $db_query .= " * ";
  } else {
    $db_query .= '`' . join('`,`',@db_array) . '`';
  }

  $db_query .= " from customer";

  if ($query{'status'} eq "active") {
    $db_query .= " where enddate >= $today";
  } elsif ($query{'status'} eq "expired") {
    $db_query .= " where enddate < $today";
  }

  # Membership Management service, check if account has this service 
  # by checking if the database exists.
  my ( $dbh, $error ) = &checkDBExists($database);
  if ($error && !defined $dbh) {
    return &handleModeNotPermitted(\%result, $error);
  }

  my $sth = $dbh->prepare(qq{$db_query}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
  my $rv = $sth->execute() or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%query);
  while (my $data = $sth->fetchrow_hashref()) {
    if ($ccexpflg == 1) {
      my $testexp = $data->{'exp'};
      my ($mo,$yr) = split('/',$testexp);
      $mo = sprintf("%02d",substr($mo,-2));
      $yr = sprintf("%02d",substr($yr,-2));
      $testexp = "20" . $yr . $mo;
      my @then = gmtime(time + $query{'expcc'}*(30*24*3600));
      my $then = sprintf("%04d%02d", $then[5]+1900, $then[4]+1);
      if ($testexp > $then) {
        next;
      }
    }

    $idx = sprintf("%05d" ,$idx);

    my $cd = new PlugNPay::CardData();
    my $ecrypted_card_data = '';

    if (exists $data->{'cardnumber'}) {
      eval {
        $ecrypted_card_data = $cd->getRecurringCardData({customer => "$data->{'username'}", username => "$database"});
      };
    }

    if (!$@) {
      $data->{'enccardnumber'} = $ecrypted_card_data;
    }

    if ($query{'crypt'} eq 'omit') {
      delete $data->{'password'};
    } elsif ($query{'crypt'} eq 'blank') {
      $data->{'password'} = '';
    }


    foreach my $key (keys %$data) {
      # encrypt passwords, as necessary
      $key =~ tr/A-Z/a-z/;
      if ($key =~ /(result|shacardnumber|enccardnumber|length)/) {
        next;
      } elsif (($key eq "cardnumber") && ($data->{'enccardnumber'} ne "") && ($data->{'cardnumber'} !~ /^(\d[6]\*\*\d[4])$/))  {
        my $cardnumber = &rsautils::rsa_decrypt_file($data->{'enccardnumber'},$data->{'length'},"print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");
        $data->{'cardnumber'} = substr($cardnumber,0,6) . '**' . substr($cardnumber,-4); # Format: first6, **, last4
        if ($remote::accountFeatures->get('enableToken') == 1) {
          my $cc = new PlugNPay::Token();
          $data->{'token'} = $cc->getToken($cardnumber);
        }
      } elsif (($key eq "password") && ($data->{$key} ne '')) {
        my $hasher = new PlugNPay::Util::Hash();
        $hasher->add($data->{$key});
        $data->{$key} = $hasher->bcrypt();
        if ($remote::accountFeatures->get('bcrypt_php_compat')) {
          $data->{$key} =~ s/^\$2a/\$2y/;
        }
      }
      # write aXXXXX result entry
      my $a = $data->{$key};
      $a =~ s/(\W)/'%' . unpack("H2",$1)/ge;
      #$result{"a$idx"} .= "$key\=$data->{$key}\&";
      $result{"a$idx"} .= "$key\=$a\&";
    }
    chop $result{"a$idx"};
    $idx++;
  }
  $sth->finish;
  $dbh->disconnect;

  $result{'TranCount'} = sprintf("%01d", $idx);

  if ($result{'TranCount'} == 0) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "No Records Found";
    $result{'aux-msg'} = $result{'MErrMsg'};
    $result{'resp-code'} = "PXX";
  }
  elsif ($result{'FinalStatus'} eq "problem") {
    $result{'MErrMsg'} = "Can not extract profile data - please contact support.";
    $result{'aux-msg'} = $result{'MErrMsg'};
    $result{'resp-code'} = "PXX";
  }
  else {
    $result{'FinalStatus'} = "success";
  }

  return %result;
}

sub bill_member {
  # Required fields
  # merchantdb or publisher-name
  # username of member
  my $self = shift;
  my ($tdsresult)= shift||$self;
  my (%query) = %remote::query;
  my $ccflag = 0;

  my ($database,%result,$bill_descr,$status_amount,$submitted_exp);

  if (exists $query{'month-exp'}) {
    $query{'month-exp'} = substr($query{'month-exp'},0,2);
    if (length($query{'year-exp'}) == 4) {
      $query{'year-exp'} = substr($query{'year-exp'},-2);
    }
    else {
      $query{'year-exp'} = substr($query{'year-exp'},0,2);
    }
    if ($query{'month-exp'} ne "") {
      $query{'card-exp'} = $query{'month-exp'} . "/" . $query{'year-exp'};
    }
  }
  my $CClength = length($query{'card-number'});
  if (($CClength > 12) && ($query{'card-exp'} ne "")) {
    my $cc = new PlugNPay::CreditCard($query{'card-number'});
    if (!cardIsPotentiallyValid($cc)) {
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = "Invalid submitted credit cardnumber.";
      return %result;
    } else {
      $ccflag = 1;
      $submitted_exp = $query{'card-exp'};
    }
  }

  if ($query{'merchantdb'} ne "") {
    $database = $query{'merchantdb'};
  }
  else {
    $database = $query{'publisher-name'};
  }

  if ($query{'acct_code4'} eq "") {
    $query{'acct_code4'} = "$query{'publisher-name'}:$query{'username'}";
    if ($query{'mode'} eq "credit_member") {
      $query{'acct_code4'} .= ":CREDIT";
    }
  }

  if ($query{'username'} eq "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "You need to pass a username, refer to documentation for required fields.";
    return %result;
  }

  my @db_array = ('purchaseid','name','company','addr1','addr2','city','state','zip','country','shipname','shipaddr1','shipaddr2','shipcity','shipstate','shipzip','shipcountry','phone','fax','email','billcycle','enccardnumber','length','exp','acct_code','accttype','password','encardnumber2','exp2','cashbalance');

  if ($database eq "boudin") {
    push (@db_array, 'commcardtype');
    push (@db_array, 'ponumber');
  }

  my %query_keys = ('name','card-name','company','card-company','addr1','card-address1','addr2','card-addres2','city','card-city','state','card-state','zip','card-zip','country','card-country','shipaddr1','address1','shipaddr2','address2','shipcity','city','shipstate','state','shipzip','zip','shipcountry','country','exp','card-exp','enccardnumber','enccardnumber','length','length','password','passcode','exp2','card-exp2','enccardnumber2','enccardnumber2','cashbalance','cashbalance');

  if (($remote::accountFeatures->get('api_billmem_chkbalance') == 1) || ($remote::accountFeatures->get('api_billmem_updtbalance') == 1)) {
    # append in balanace field to @db_array & %query_keys for later usage.
    push(@db_array, 'balance');
    $query_keys{'balance'} = "balance";
  }

  # Membership Management service, check if account has this service 
  # by checking if the database exists.
  my ( $dbh, $error ) = &checkDBExists($database);
  if ($error && !defined $dbh) {
    return &handleModeNotPermitted(\%result, $error);
  }

  my $sth = $dbh->prepare(qq{
      select *
      from customer
      where username=?
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
  $sth->execute("$query{'username'}") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%query);
  my $ref = $sth->fetchrow_hashref() or $result{'FinalStatus'} = "problem";
  $sth->finish;
  $dbh->disconnect;

  if ($ref->{'username'}) {
    $ref->{'enccardnumber'} = &smpsutils::getcardnumber($database,$query{'username'},'bill_member',$ref->{'enccardnumber'},'rec');
  }

  if ($ref->{'orderid'} =~ /^\d+$/) {
    $ref->{'origorderid'} = $ref->{'orderid'};
  }

  my %resulthash;
  foreach my $key (keys %{$ref}) {
    $resulthash{$key} = $ref->{$key};
  }

  if ($result{'FinalStatus'} eq "problem") {
    $result{'MErrMsg'} = "Username does not exist.";
    return %result;
  }

  # enforce password match, if necessary
  if (($remote::accountFeatures->get('api_billmem_chkpasswrd') == 1) && ($resulthash{'password'} ne "") && ($query{'password'} ne $resulthash{'password'})) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Password does not match.";
    return %result;
  }

  # check available balance, if necessary
  if (($remote::accountFeatures->get('api_billmem_chkbalance') == 1) && ($resulthash{'balance'} ne "") && ($query{'card-amount'} > $resulthash{'balance'})) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Insufficent balance.";
    return %result;
  }

  if (($query{'usecard'} eq "cash") && ($query{'card-amount'} > $resulthash{'cashbalance'})) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Insufficent cash balance.";
    $result{'cashbalance'} = $resulthash{'cashbalance'};
    return %result;
  }

  for (my $i=0; $i<=$#db_array; $i++) {
    if ($resulthash{"$db_array[$i]"} ne "") {
      if (exists $query_keys{$db_array[$i]}) {
        $query{$query_keys{$db_array[$i]}} = $resulthash{"$db_array[$i]"};
      }
      else {
        $query{$db_array[$i]} = $resulthash{"$db_array[$i]"};
      }
    }
  }

  if ($remote::query{'acct_code'} ne "") {
    $query{'acct_code'} = $remote::query{'acct_code'};
  }

  if ($query{'client'} eq "psl") {
    $query{'transflags'} = "load";
    $query{'walletid'} = "$query{'email'}";
    $query{'success-link'} = "http://pay1.plugnpay.com/fake_uri.html";
    $query{'badcard-link'} = "http://pay1.plugnpay.com/fake_uri.html";
  }
  else {
    delete $query{'passcode'};
  }

  if( ($query{'enccardnumber2'} ne "") && ($query{'usecard'} eq "card2")) {
    $query{'card-number'} = &rsautils::rsa_decrypt_file($query{'enccardnumber2'},$query{'length'},"print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");
    $query{'card-exp'} = $query{'card-exp2'};
  }
  elsif ($query{'usecard'} eq "cash") {
    ### Do nothing
  }
  elsif (($query{'enccardnumber'} ne "") && ($ccflag != 1)) {
    $query{'card-number'} = &rsautils::rsa_decrypt_file($query{'enccardnumber'},$query{'length'},"print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");
  }
  delete $query{'enccardnumber'};
  delete $query{'length'};
  delete $query{'enccardnumber2'};

  if ($ccflag == 1) {
    $query{'card-exp'} = "$submitted_exp";
  }
  ($query{'month-exp'},$query{'year-exp'}) = split('\/',$query{'card-exp'});

  if ($query{'card-number'} =~ /^(\d{9}) (\d+)/) {
    $query{'routingnum'} = $1;
    $query{'accountnum'} = $2;
    my $modtest = &miscutils::mod10($query{'routingnum'});
    if ($modtest eq "success") {
      $query{'accttype'} = "checking";

      # apply extra ACH processing params, when necessary
      if (($remote::chkprocessor ne "") && ($resulthash{'commcardtype'} eq "business")) {
        $query{'commcardtype'} = $resulthash{'commcardtype'};
        $query{'acctclass'} = "business";
        $query{'checktype'} = "CCD";
      }
    }
    else {
      delete $query{'routingnum'};
      delete $query{'accountnum'};
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} .= "Bank routing number failed mod10 test.";
      $result{'resp-code'} = "P53";
      return %result;
    }
  }
  elsif ($query{'usecard'} eq "cash") {
    ### Do nothing
  }
  else {
    my $cc = new PlugNPay::CreditCard($query{'card-number'});
    if (!cardIsPotentiallyValid($cc)) {
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = "Invalid credit cardnumber on record.";
      return %result;
    }
    $query{'accttype'} = "credit";
  }

  my ($altacctflag);
  if ((exists $remote::altaccts{$query{'publisher-name'}}) && (exists $query{'merchantequals'}) ) {
    my $aa = $query{$query{'merchantequals'}};
    $aa =~ s/[^a-zA-Z0-9]//g;
    foreach my $var ( @{ $remote::altaccts{$query{'publisher-name'}} } ) {
      if ($var eq $aa) {
        $query{'publisher-name'} = $aa;
        $altacctflag = 1;
        last;
      }
    }
    if ($altacctflag != 1) {
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = "Invalid or missing field:$query{$query{'merchantequals'}}.";
      return %result;
    }
  }

  my @array = %query;
  my $payment = mckutils->new(@array);
  %remote::query = %mckutils::query;

  if ($remote::summarizeflg == 1) {
    return;
  }

  $dbh = &miscutils::dbhconnect("$database");

  if ($query{'mode'} eq "credit_member") {
    my %query = %remote::query;
    if ($query{'currency'} eq "") {
      $query{'currency'} = "usd";
    }
    my $addr = $query{'card-address1'} . " " . $query{'card-address2'};
    $addr = substr($addr,0,50);
    my $amount = $query{'card-amount'};
    my $price = sprintf("%3s %.2f","$query{'currency'}",$amount);
    my $country = substr($query{'card-country'},0,2);
    $query{'card-zip'} = substr($query{'card-zip'},0,10);

    ## Corrects card-number field for ACH payments, after the value was filterd by mckutils->new (e.g. space was removed)
    if ($query{'accttype'} =~ /^(checking|savings)$/) {
      $query{'card-number'} = "$query{'routingnum'} $query{'accountnum'}";
    }

    my $username = $query{'publisher-name'};
    %result = &miscutils::sendmserver("$username","return",
      'accttype', "$query{'accttype'}",
      'acctclass', "$query{'acctclass'}",
      'commcardtype', "$query{'commcardtype'}",
      'checktype', "$query{'checktype'}",
      'order-id', "$query{'orderID'}",
      'origorderid', "$query{'origorderid'}",
      'amount', "$price",
      'card-number', "$query{'card-number'}",
      'card-name', "$query{'card-name'}",
      'card-address', "$addr",
      'card-city', "$query{'card-city'}",
      'card-state', "$query{'card-state'}",
      'card-zip', "$query{'card-zip'}",
      'card-country', "$country",
      'card-exp', "$query{'card-exp'}",
      'acct_code', "$query{'acct_code'}",
      'acct_code4', "$query{'acct_code4'}",
      'transflags', $query{'transflags'},
      'subacct', "$query{'subacct'}"
    );
    $status_amount = "-$query{'card-amount'}";
  }
  elsif ($query{'usecard'} eq "cash") {
    $result{'FinalStatus'} = "success";
    $result{'MErrMsg'} = "00";
    $status_amount = "$query{'card-amount'}";
  }
  else {
    if ($remote::query{'tdsflag'} == 1) {
      %result = $payment->tds($tdsresult);
      if (exists $result{'tdsauthreq'}) {
        my @array = (%remote::query,%result);
        &script_output('blah',@array);
        exit;
      }
      else {
        my @tdsvars = ('cavv','eci','xid');
        foreach my $var (@tdsvars) {
          if ($$tdsresult{$var} ne "") {
            $result{$var} = $$tdsresult{$var};
          }
        }
      }
    }
    else {
      %result = $payment->purchase("auth");
    }

    $payment->database();

    if ( ($result{'FinalStatus'} eq "success") && ($mckutils::query{'conv_fee_amt'} > 0 ) && (($mckutils::accountFeatures->get('convfee') || $mckutils::accountFeatures->get('cardcharge')) ) ) {
      my $origamt = $mckutils::query{'card-amount'};
      my $origacct = $mckutils::query{'publisher-name'};
      my $origemail = $mckutils::query{'publisher-email'};
      my %orgifeatures = %mckutils::feature;

      $mckutils::query{'card-amount'} = $mckutils::query{'conv_fee_amt'};
      $mckutils::query{'publisher-name'} = $mckutils::query{'conv_fee_acct'};
      my $tempOID = $mckutils::query{'orderID'};

      $mckutils::query{'orderID'} = PlugNPay::Transaction::TransactionProcessor::generateOrderID();

      $mckutils::orderID = $mckutils::query{'orderID'};
      $mckutils::query{'acct_code3'} = "CFC:$tempOID:$origacct";

      my %resultCF = $payment->purchase("auth");

      $payment->database();

      $result{'auth-codeCF'} = substr($resultCF{'auth-code'},0,6);
      $result{'FinalStatusCF'} = $resultCF{'FinalStatus'};
      $result{'MErrMsgCF'} = $resultCF{'MErrMsg'};
      $result{'orderIDCF'} = $mckutils::query{'orderID'};
      $result{'convfeeamt'} = $mckutils::query{'conv_fee_amt'};

      my (%result1,$voidstatus);

      if (($resultCF{'FinalStatus'} ne "success") && ($mckutils::query{'conv_fee_failrule'} eq "VOID")) {
        my $price = sprintf("%3s %.2f","$mckutils::query{'currency'}",$resultCF{'amount'});
        ## Void Main transaction
        for(my $i=1; $i<=3; $i++) {
          %result1 = &miscutils::sendmserver($origacct,"void"
           ,'acct_code', $mckutils::query{'acct_code'}
           ,'acct_code4', "$mckutils::query{'acct_code4'}"
           ,'txn-type','auth'
           ,'amount',"$price"
           ,'order-id',"$tempOID"
           );
          last if($result1{'FinalStatus'} eq "success");
        }
        $result{'voidstatus'} = $result1{'FinalStatus'};
        $result{'FinalStatus'} = $resultCF{'FinalStatus'};
        $result{'MErrMsg'} = $resultCF{'MErrMsg'};
      }
      if ($resultCF{'FinalStatus'} eq "success") {
        $mckutils::query{'totalchrg'} = sprintf("%.2f",$origamt+$mckutils::query{'conv_fee_amt'});
      }
      %mckutils::result = (%mckutils::result,%result);
      $mckutils::query{'card-amount'} = $origamt;
      $mckutils::query{'publisher-name'} = $origacct;
      $mckutils::query{'publisher-email'} = $origemail;
      %mckutils::feature = %orgifeatures;
      $mckutils::query{'orderID'} = $tempOID;
      $mckutils::query{'convfeeamt'} = $result{'convfeeamt'};

      delete $mckutils::query{'conv_fee_amt'};
      delete $mckutils::query{'conv_fee_acct'};
      delete $mckutils::query{'conv_fee_failrule'};

    }

    eval {
      $payment->logFeesIfApplicable(\%mckutils::query, \%mckutils::result, $mckutils::adjustmentFlag, $mckutils::conv_fee_acct, $mckutils::conv_fee_oid);
    };

    if ($@) {
      my $logger = new PlugNPay::Logging::DataLog({ collection => 'remote_strict' });
      my $stackTrace = new PlugNPay::Util::StackTrace()->string();
      $logger->log({message => 'An error occurred while attempting to log adjustment fee.', error => $@, stackTrace => $stackTrace });
    }

    $status_amount = "$query{'card-amount'}";
    if ($query{'sndemailflg'} == 1) {
      if ($remote::accountFeatures->get('sendEmailReceipt') == 1) {
        # convert data SSv1 to SSv2 field names
        my $api = new PlugNPay::API('payscreens');
        $api->setLegacyParameters(\%mckutils::query);

        my $transactionType = ($api->parameter('pt_transaction_type') eq 'credit_member' ? 'credit' : 'auth');
        my $transactionVehicle = (lc($api->parameter('pd_transaction_payment_type')) eq 'ach' ? 'ach' : 'credit');

        my $transaction = new PlugNPay::Transaction($transactionType, $transactionVehicle);

        # Create an api mapper and set the transaction values based on the api object
        my $mapper = new PlugNPay::Transaction::MapAPI();
        $mapper->setAPI($api);
        $mapper->setTransaction($transaction);
        $mapper->map();

        #Create a transaction response
        my $response = new PlugNPay::Transaction::Response($transaction);
        $response->setRawResponse(\%result);

        #Create transaction receipt email
        my $transReceipt = new PlugNPay::Transaction::Receipt();
        $transReceipt->sendEmailReceipt({ transaction => $transaction, response => $response, ccAddress => $query{'email'}});
      } else {
        $payment->email();
      }
    }

    if ( ($result{'FinalStatus'} eq "success") && ($ccflag == 1) && ($query{'updatembr'} eq "yes") ) {
      my $cardnumber = $query{'card-number'};
      my $cc = new PlugNPay::CreditCard($cardnumber);
      my $shacardnumber = $cc->getCardHash();
      my ($enccardnumber,$encryptedDataLen) = &rsautils::rsa_encrypt_card($cardnumber,"/home/p/pay1/pwfiles/keys/key");

      $enccardnumber = &smpsutils::storecardnumber($database,$query{'username'},'bill_member',$enccardnumber,'rec');

      $cardnumber = substr($cardnumber,0,4) . '**' . substr($cardnumber,length($cardnumber)-2,2);

      my $sth = $dbh->prepare(qq{
          update customer
          set length=?,cardnumber=?,shacardnumber=?,enccardnumber=?,exp=?
          where username=?
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr,%query");
      $sth->execute("$encryptedDataLen","$cardnumber","$shacardnumber","$enccardnumber","$query{'card-exp'}","$query{'username'}")
      or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr,%query");
      $sth->finish;

      my $action = "Record Updated";
      my $reason = "VT Request";
      &record_history($query{'username'},$action,$reason,$database,$dbh);
    }
  }

  if ($query{'description'} ne "") {
    $bill_descr = $query{'description'};
  }
  else {
    if ($query{'mode'} eq "credit_member") {
      $bill_descr = "Remote member credit.";
    }
    elsif ($query{'usecard'} eq "cash") {
      $bill_descr = "Remote member cash billing.";
    }
    else {
      $bill_descr = "Remote member billing.";
    }
  }

  $bill_descr = substr($bill_descr,0,39);

  my ($today) = &miscutils::gendatetime_only();

  $sth = $dbh->prepare(qq{
      insert into billingstatus
      (username,trans_date,amount,orderid,descr,result)
      values (?,?,?,?,?,?)
    }) or die "Can't prepare: $DBI::errstr";
  $sth->execute("$query{'username'}","$today","$status_amount","$remote::query{'orderID'}","$bill_descr","$result{'FinalStatus'}") or die "Can't execute: $DBI::errstr";
  $sth->finish;

  # update profile's balance, if necessary
  if (($remote::accountFeatures->get('api_billmem_updtbalance') == 1) && ($resulthash{'balance'} ne "")) {
    my $balance = $query{'balance'} - $status_amount;
    if ($balance < 0) {
      $balance = "0.00";
    }
    else {
      $balance = sprintf("%0.02f", $balance);
    }
    $result{'balance'} = $balance;

    my $sth = $dbh->prepare(qq{
        update customer
        set balance=?
        where username=?
      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr,%query");
    $sth->execute("$balance","$query{'username'}") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr,%query");
    $sth->finish;
  }
  elsif (($query{'usecard'} eq "cash") && ($resulthash{'cashbalance'} ne "")) {
    my $cashbalance = $query{'cashbalance'} - $status_amount;
    if ($cashbalance < 0) {
      $cashbalance = "0.00";
    }
    else {
      $cashbalance = sprintf("%0.02f", $cashbalance);
    }
    $result{'cashbalance'} = $cashbalance;

    my $sth = $dbh->prepare(qq{
        update customer
        set cashbalance=?
        where username=?
      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr,%query");
    $sth->execute("$cashbalance","$query{'username'}") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr,%query");
    $sth->finish;
  }

  $dbh->disconnect;

  $result{'auth-code'} = substr($result{'auth-code'},0,6);

  return %result;
}

sub cancel_member {
  my (%query) = %remote::query;
  my ($database,$status,$bc,%result);
  if ($query{'username'} eq "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "You need to pass a username, refer to documentation for required fields.";
    return;
  }
  if ($query{'merchantdb'} ne "") {
    $database = $query{'merchantdb'};
  }
  else {
   $database = $query{'publisher-name'};
  }

  # Membership Management service, check if account has this service 
  # by checking if the database exists.
  my ( $dbh, $error ) = &checkDBExists($database);
  if ($error && !defined $dbh) {
    return &handleModeNotPermitted(\%result, $error);
  }

  my $sth = $dbh->prepare(qq{
      select username
      from customer
      where username=?
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
  $sth->execute($query{'username'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%query);
  my ($untest) = $sth->fetchrow;
  $sth->finish;
  if ($untest ne "") {
    $status = "cancelled";
    $bc = "0";
    my $sth = $dbh->prepare(qq{
         update customer
         set status=?,billcycle=?
         where username=?
      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
    my $dbresult = $sth->execute("$status","$bc","$query{'username'}") or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
    $sth->finish;
    if ($dbresult == 1) {
      my $action = "Account Cancelled";
      my $reason = "Remote Request";
      &record_history($query{'username'},$action,$reason,$database,$dbh);
      $result{'FinalStatus'} = "success";
      $result{'aux-msg'} = "The account for Username $query{'username'} has been cancelled.";
    }
    else {
      $result{'FinalStatus'} = "problem";
      $result{'aux-msg'} = "DB returned $dbresult. Bad result.";
    }
  }
  else {
    $result{'FinalStatus'} = "problem";
    $result{'aux-msg'} = "Username does not exist.";
  }

  $dbh->disconnect;
  return %result;
}

sub update_member {
  my (%query) = %remote::query;
  my (@customer_data,$database,$shacardnumber,$cardnumber,$enccardnumber,$encryptedDataLen,$action,$reason,%result);

  if (exists $query{'recfee'}) {
    $query{'recfee'} = sprintf("%.2f",$query{'recfee'});
  }

  # my %length_hash = ('username','12','plan','12','name','39','addr1','39','addr2','39','balance','8','country','39','billcycle','9','startdate','9','enddate','9','city','39','state','39','zip','13','monthly','8','cardnumber','26','exp','10','orderid','22','purchaseid','39','password','15','shipname','39','shipaddr1','39','shipaddr2','39','shipcity','39','shipstate','39','shipzip','13','shipcountry','39','phone','15','fax','10','email','39','status','10','acct_code','15');

  my %map_hash = ("company","company","purchaseid","purchaseid","plan","plan","password","password","name","card-name","addr1","card-address1","addr2","card-address2","city","card-city","state","card-state","zip","card-zip","country","card-country","shipname","shipname",
    "shipaddr1","address1","shipaddr2","address2","shipcity","city","shipstate","state","shipzip","zip","shipcountry","country","phone","phone","fax","fax","email","email","startdate","startdate","enddate","enddate","monthly","recfee","exp","card-exp","exp2","card-exp2",
    "billcycle","billcycle","status","status","acct_code","acct_code","orderid","orderID","commcardtype","commcardtype");

  my %skip_hash = (
    username => 1,
    id => 1
  );

  if ($query{'merchantdb'} ne "") {
    $database = $query{'merchantdb'};
  }
  else {
    $database = $query{'publisher-name'};
  }

  # Membership Management service, check if account has this service 
  # by checking if the database exists.
  my ( $dbh, $error ) = &checkDBExists($database);
  if ($error && !defined $dbh) {
    return &handleModeNotPermitted(\%result, $error);
  }

  my ($balanceflag,$billunflag,$commcardflag);
  my $lengthHashRef = getRecurringCustomerTableLengths($database, { gt5sub1 => 1, gt5else => 1 });
  my %length_hash = %{$lengthHashRef};

  if ( ($query{'currency'} ne "") && ($length_hash{'monthly'} >= 11) && (exists $query{'recfee'}) ) {
    my $amount = $query{'recfee'};
    $query{'recfee'} = sprintf("%3s %.2f","$query{'currency'}",$amount);
  }

  my %customer_fields = ();
  foreach my $testvar (keys %length_hash) {
    if (exists $skip_hash{$testvar}) {
      next;
    }

    my $hashkey = "";
    my $val = "";
    if (exists $map_hash{$testvar}) {
      $hashkey = $map_hash{$testvar};
    }
    else {
      $hashkey = $testvar;
    }

    if (length($query{$hashkey}) > $length_hash{$testvar}) {
      $customer_fields{$hashkey} = substr($query{$hashkey},0,$length_hash{$testvar});
    }
    elsif ((defined $query{$hashkey}) && (exists $query{$hashkey})) {
      $customer_fields{$hashkey} = $query{$hashkey};
    }
  }

  foreach my $key (keys %map_hash) {
    if (exists $query{$map_hash{$key}}) {
      $customer_fields{$key} = $query{$map_hash{$key}};
    }
  }

  my $temp = "";
  foreach my $key (keys %customer_fields) {
    $temp = $customer_fields{$key};
    $temp =~ s/[^a-zA-Z0-9_\.\,\/\@:\-\~\?\&\=\ \#\'\+]//g;
    $customer_fields{$key} = $temp;
  }

  my $qstr = "update customer set ";
  my ($qstr1);
  foreach my $key (sort keys %customer_fields) {
    if (exists $length_hash{$key}) {
      if ($qstr1 ne "") {
        $qstr1 .= ",$key=?";
      }
      else {
        $qstr1 = "$key=?";
      }
      $customer_data[++$#customer_data] = "$customer_fields{$key}";
    }
  }
  $qstr .= $qstr1;

  if (@customer_data < 1) {
    $dbh->disconnect;
    $result{'FinalStatus'} = "problem";
    $result{'aux-msg'} = "No valid data fields to update.";
    return %result;
  }

  my $enccardnumber;
  if ($query{'card-number'} ne "") {
    my $cc = new PlugNPay::CreditCard($query{'card-number'});
    if (cardIsPotentiallyValid($cc)) {
      $shacardnumber = $cc->getCardHash();
      ($enccardnumber,$encryptedDataLen) = &rsautils::rsa_encrypt_card($query{'card-number'},"/home/p/pay1/pwfiles/keys/key");

      $enccardnumber = &smpsutils::storecardnumber($database,$query{'username'},'update_member',$enccardnumber,'rec');

      if ($length_hash{'cardnumber'} > 12) {
        $query{'card-number'} = substr($query{'card-number'},0,6) . '**' . substr($query{'card-number'},length($query{'card-number'})-2,2);
      }
      else {
        $query{'card-number'} = substr($query{'card-number'},0,4) . '**' . substr($query{'card-number'},length($query{'card-number'})-2,2);
      }
      $cardnumber = $query{'card-number'};
      $qstr .= ",length=?,cardnumber=?,shacardnumber=?,enccardnumber=?";
      $customer_data[++$#customer_data] = $encryptedDataLen;
      $customer_data[++$#customer_data] = $cardnumber;
      $customer_data[++$#customer_data] = $shacardnumber;
      $customer_data[++$#customer_data] = $enccardnumber;
    }
    else {
      $dbh->disconnect;
      $result{'FinalStatus'} = "problem";
      $result{'aux-msg'} = "Credit Card Number is Not Valid.";
      return %result;
    }
  }
  elsif (($query{'accountnum'} ne "") && ($query{'routingnum'} ne "")) {
    my $modtest = &miscutils::mod10($query{'routingnum'});
    if ($modtest eq "success") {
      $query{'card-number'} = $query{'routingnum'} . " " . $query{'accountnum'};
      my $cc = new PlugNPay::OnlineCheck($query{'card-number'});
      $shacardnumber = $cc->getCardHash();
      ($enccardnumber,$encryptedDataLen) = &rsautils::rsa_encrypt_card($query{'card-number'},"/home/p/pay1/pwfiles/keys/key");

      $enccardnumber = &smpsutils::storecardnumber($database,$query{'username'},'update_member',$enccardnumber,'rec');

      if ($length_hash{'cardnumber'} > 12) {
          $query{'card-number'} = substr($query{'card-number'},0,6) . '**' . substr($query{'card-number'},length($query{'card-number'})-2,2);
      }
      else {
        $query{'card-number'} = substr($query{'card-number'},0,4) . '**' . substr($query{'card-number'},length($query{'card-number'})-2,2);
      }
      $cardnumber = $query{'card-number'};
      $qstr .= ",length=?,cardnumber=?,shacardnumber=?,enccardnumber=?";
      $customer_data[++$#customer_data] = "$encryptedDataLen";
      $customer_data[++$#customer_data] = "$cardnumber";
      $customer_data[++$#customer_data] = "$shacardnumber";
      $customer_data[++$#customer_data] = $enccardnumber;
    }
    else {
      $dbh->disconnect;
      $result{'FinalStatus'} = "problem";
      $result{'aux-msg'} .= "Bank routing number failed mod10 test.";
      $result{'resp-code'} = "P53";
      return %result;
    }
  }
  if (($query{'card-number2'} ne "") && (exists $length_hash{'enccardnumber2'})){
    my $cc = new PlugNPay::CreditCard($query{'card-number2'});
    if (cardIsPotentiallyValid($cc)) {
      my $shacardnumber = $cc->getCardHash();
      my ($enccardnumber2,$encryptedDataLen2) = &rsautils::rsa_encrypt_card($query{'card-number2'},"/home/p/pay1/pwfiles/keys/key");

      $enccardnumber = &smpsutils::storecardnumber($database,$query{'username'},'update_member',$enccardnumber,'rec');

      if ($length_hash{'cardnumber2'} > 12) {
          $query{'card-number2'} = substr($query{'card-number2'},0,6) . '**' . substr($query{'card-number2'},length($query{'card-number2'})-2,2);
      }
      else {
        $query{'card-number2'} = substr($query{'card-number2'},0,4) . '**' . substr($query{'card-number2'},length($query{'card-number2'})-2,2);
      }
      $cardnumber = $query{'card-number2'};
      $qstr .= ",cardnumber2=?,shacardnumber2=?,enccardnumber2=?";
      $customer_data[++$#customer_data] = "$cardnumber";
      $customer_data[++$#customer_data] = "$shacardnumber";
      $customer_data[++$#customer_data] = $enccardnumber2;
    }
    else {
      $dbh->disconnect;
      $result{'FinalStatus'} = "problem";
      $result{'aux-msg'} = "Credit Card Number is Not Valid.";
      return %result;
    }
  }

  $customer_data[++$#customer_data] = $query{'username'};
  $qstr .= " where username=?";

  my $sth = $dbh->prepare(qq{
      select username
      from customer
      where username=?
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
  $sth->execute($query{'username'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%query);
  my ($untest) = $sth->fetchrow;
  $sth->finish;

  if ($untest ne "") {
    $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr,%query");
    $sth->execute(@customer_data) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr,%query");
    $sth->finish;

    $result{'FinalStatus'} = "success";
    $result{'aux-msg'} = $result{'aux-msg'} . "Record for $query{'username'} has been successfully updated.";
    $action = "Record Updated";
    $reason = "Remote Request";
  }
  else {
    $result{'FinalStatus'} = "problem";
    $result{'aux-msg'} .= " $query{'username'} does not exist.";
    $action = "Failed Updated";
    $reason = "Remote Request";
  }
  &record_history($query{'username'},$action,$reason,$database,$dbh);

  $dbh->disconnect;

  return %result;
}

sub query_billing {
  # Required fields publisher-name
  my (%query) = %remote::query;
  my ($database);

  if ($query{'merchantdb'} ne "") {
    $database = $query{'merchantdb'};
  }
  else {
    $database = $query{'publisher-name'};
  }

  my (%result,$startdate,$enddate,$username,$trans_date,$amount,$orderid,$descr,$result);

  my $timeadjust = (280 * 24 * 3600);
  my ($dummy,$datestr,$timestr) = &miscutils::gendatetime("-$timeadjust");
  $startdate = $query{'startdate'};
  $startdate =~ s/[^0-9]//g;
  if (($query{'startdate'} eq "") && ($query{'username'} eq "")) {
    my $timeadjust = (2 * 24 * 3600);
    my ($dummy,$datestr,$timestr) = &miscutils::gendatetime("-$timeadjust");
    $startdate = $datestr;
  }
  elsif (($query{'startdate'} < $datestr) && ($query{'username'} ne "")) {
    $startdate = $datestr;
  }
  elsif (($query{'startdate'} < $datestr) && ($query{'username'} eq "")) {
    $startdate = $datestr;
  }

  $enddate = $query{'enddate'};
  $enddate =~ s/[^0-9]//g;

  if (($query{'enddate'} eq "") && ($query{'username'} ne "")) {
    my $timeadjust = (1 * 24 * 3600);
    my ($dummy,$datestr,$timestr) = &miscutils::gendatetime("$timeadjust");
    $enddate = $datestr;
  }
  if ($enddate < $startdate) {
    $enddate = $startdate + 1;
  }

  # Membership Management service, check if account has this service 
  # by checking if the database exists.
  my ( $dbh, $error ) = &checkDBExists($database);
  if ($error && !defined $dbh) {
    return &handleModeNotPermitted(\%result, $error);
  }
  my $dbh1 = &miscutils::dbhconnect("pnpdata","","$query{'publisher-name'}"); ## Trans_Log

  my $i = 0;

  if ($query{'username'} ne "") {
    my $qstr = "select orderid,startdate ";
    $qstr .= "from customer ";
    $qstr .= "where username=?";

    my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
    $sth->execute("$query{'username'}") or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
    my ($dborderid,$dbstartdate) = $sth->fetchrow;
    my %res = &tran_detail($query{'publisher-name'},$dborderid,$dbstartdate,$enddate,$dbh1);
    foreach my $key (keys %res) {
      my $idx = sprintf("DR%06d",$i);
      $result{$idx} = "username=$query{'username'}\&descr=Initial Signup\&";
      $result{$idx} .= $res{$key};
      $i++;
    }
    $sth->finish;
    if (($dbstartdate >= 20000000) && ($dbstartdate <= 20500000)) {
      if ($startdate < $dbstartdate) {
        $startdate = $dbstartdate;
      }
    }
  }

  my @placeholder = ();
  my $qstr = "select username,trans_date,amount,orderid,descr,result ";
  $qstr .= "from billingstatus ";
  $qstr .= "where trans_date>=? and trans_date<? ";
  push(@placeholder, $startdate, $enddate);
  if ($query{'username'} ne "") {
    $qstr .= "and username=?";
    push(@placeholder, $query{'username'});
  }

  my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
  $sth->execute(@placeholder) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
  $sth->bind_columns(undef,\($username,$trans_date,$amount,$orderid,$descr,$result));
  while ($sth->fetch) {
    my %res = &tran_detail($query{'publisher-name'},$orderid,$startdate,$enddate,$dbh1,$amount);
    foreach my $key (keys %res) {
      my $idx = sprintf("DR%06d",$i);
      $result{$idx} = "username=$username\&amount=$amount\&descr=$descr\&";
      $result{$idx} .= $res{$key};
      $i++;
    }
  }
  $sth->finish;
  $dbh->disconnect;
  $dbh1->disconnect;

  if ($i > 0) {
    $result{'FinalStatus'} = "success";
  }
  else {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "No Records Found";
  }
  return %result;
}

###  Coupon Section

sub coupon {
  my ($mode) = @_;
  my (%result);
  if ($mode eq "add_coupon") {
    %result = &update_coupon();
  }
  elsif ($mode eq "delete_coupon") {
    %result = &delete_coupon();
  }
  elsif($mode eq "update_coupon") {
    %result = &update_coupon();
  }
  return %result;
}

sub delete_coupon {
  my (%query) = %remote::query;

  my (%result);

  # see if merchant is subscribed to service
  my ($service_ok, $service_type) = &mckutils::check_service("$query{'publisher-name'}", "coupon");
  if ($service_ok ne "yes") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "$service_type";
    $result{'resp-code'} = "PXX";
    return %result;
  }

  my $dbh = &miscutils::dbhconnect("merch_info");
  my $sth = $dbh->prepare(qq{
      delete from promo_coupon
      where username=?
      and promoid=?
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute("$query{'publisher-name'}", "$query{'promoid'}") or die "Can't execute: $DBI::errstr";
  $sth->finish;
  $dbh->disconnect;

  return %result;
}

sub update_coupon {
  my (%query) = %remote::query;

  my (%result);

  # see if merchant is subscribed to service
  my ($service_ok, $service_type) = &mckutils::check_service("$query{'publisher-name'}", "coupon");
  if ($service_ok ne "yes") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "$service_type";
    $result{'resp-code'} = "PXX";
    return %result;
  }

  my $dbh = &miscutils::dbhconnect("merch_info");

  ## check if offer exists
  my $sth= $dbh->prepare(qq{
      select username
      from promo_offers
      where username=? and promocode=?
      and subacct=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$query{'publisher-name'}", "$query{'promocode'}", "$query{'subacct'}") or die "Can't execute: $DBI::errstr";
  my ($test) = $sth->fetchrow;
  $sth->finish;

  if ($test ne "") {   ###  Offer exists
    my $sth= $dbh->prepare(qq{
        select username
        from promo_coupon
        where username=? and promoid=?
        and subacct=?
      }) or die "Can't do: $DBI::errstr";
    $sth->execute("$query{'publisher-name'}", "$query{'promoid'}", "$query{'subacct'}") or die "Can't execute: $DBI::errstr";
    my ($test) = $sth->fetchrow;
    $sth->finish;

    if ($test ne "") {
      if ($query{'allow_update'} == 1) {
        my $sth = $dbh->prepare(qq{
            update promo_coupon
            set promocode=?, use_limit=?, expires=?, status=?
            where username=? and promoid=?
            and subacct=?
          }) or die "Can't prepare: $DBI::errstr";
        $sth->execute("$query{'promocode'}","$query{'use_limit'}","$query{'expires'}","$query{'status'}","$query{'publisher-name'}","$query{'promoid'}","$query{'subacct'}") or die "Can't execute: $DBI::errstr";
        $sth->finish;
        $result{'FinalStatus'} = "success";
        $result{'MErrMsg'} = "Promoid updated.";
      }
      else { ### PromoID exists but allow update is set to 0
        $result{'FinalStatus'} = "problem";
        $result{'MErrMsg'} = "Promoid exists and update flag not set to 1";
      }
    }
    else {
      my $sth = $dbh->prepare(qq{
          insert into promo_coupon
          (username,promoid,promocode,use_limit,expires,status,subacct)
          values (?,?,?,?,?,?,?)
        }) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$query{'publisher-name'}","$query{'promoid'}","$query{'promocode'}","$query{'use_limit'}","$query{'expires'}","$query{'status'}","$query{'subacct'}");
      $sth->finish;
      $result{'FinalStatus'} = "success";
      $result{'MErrMsg'} = "Promoid inserted successfully.";
    }
  }
  else {  ###  Offer does not exist return error
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Invalid promocode.";
  }

  $dbh->disconnect;
  return %result;
}

sub tran_detail {
  my ($username,$orderid,$startdate,$enddate,$dbh,$testamount) = @_;
  my (%result,$trans_date,$trans_time,$operation,$finalstatus,$amount,$descr,$result,
      $card_name,$card_addr,$card_city,$card_state,$card_zip,$card_country,$card_number,$card_exp,
      $acct_code,$acct_code2,$acct_code3,$acct_code4,$auth_code,$avs,$currency,$merchant,$subacct);

  my @placeholder = ();
  my $qstr = "select trans_date,trans_time,operation,finalstatus,amount,descr,";
  $qstr .= "card_name,card_addr,card_city,card_state,card_zip,card_country,card_number,card_exp,";
  $qstr .= "acct_code,acct_code2,acct_code3,acct_code4,auth_code,avs,username,subacct ";
  $qstr .= "from trans_log ";
  $qstr .= "where trans_date >=? and trans_date<? and orderid=? ";
  push(@placeholder, $startdate, $enddate, $orderid);
  if (exists $remote::altaccts{$username}) {
    my ($temp);
    foreach my $var ( @{ $remote::altaccts{$username} } ) {
      $temp .= "?,";
      push(@placeholder, $var);
    }
    chop $temp;
    $qstr .= "and username IN ($temp) ";
  }
  else {
    $qstr .= "and username=? ";
    push(@placeholder, $username);
  }

  if ($remote::query{'level'} == 1) {
    if ($testamount < 0) {
      $qstr .= "and operation in ('return') ";
    }
    else {
      $qstr .= "and operation in ('auth') ";
    }
  }
  else {
    $qstr .= "and operation in ('auth','postauth','forceauth','return','void') ";
  }
  $qstr .= "and (duplicate IS NULL or duplicate='')";

  my $i = 0;
  my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute(@placeholder) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->bind_columns(undef,\($trans_date,$trans_time,$operation,$finalstatus,$amount,$descr,
      $card_name,$card_addr,$card_city,$card_state,$card_zip,$card_country,$card_number,$card_exp,
      $acct_code,$acct_code2,$acct_code3,$acct_code4,$auth_code,$avs,$merchant,$subacct));
  while ($sth->fetch) {
    my $idx = sprintf("%06d",$i);
    if ($amount =~ / /) {
      ($currency,$amount) = split(/ /,$amount);
      $amount =~ s/[^0-9\.]//g;
    }
    $auth_code = substr($auth_code,0,6);
    $result{$idx} = "trans_date=$trans_date\&trans_time=$trans_time\&operation=$operation\&card-amount=$amount\&";
    $result{$idx} .= "card-name=$card_name\&card-address1=$card_addr\&card-city=$card_city\&card-state=$card_state\&";
    $result{$idx} .= "card-zip=$card_zip\&card-country=$card_country\&card-number=$card_number\&card-exp=$card_exp\&";
    $result{$idx} .= "result=$finalstatus\&MErrMsg=$descr\&acct_code=$acct_code\&acct_code2=$acct_code2\&acct_code3=$acct_code3\&";
    $result{$idx} .= "acct_code4=$acct_code4\&auth-code=$auth_code\&avs-code=$avs\&currency=$currency\&orderID=$orderid\&";
    $result{$idx} .= "publisher-name=$merchant\&FinalStatus=$finalstatus";
    if ($subacct ne "") {
      $result{$idx} .= "\&subacct=$subacct";
    }
    $i++;
  }
  $sth->finish;
  return %result;
}

sub record_history {

  my $env = new PlugNPay::Environment();
  my $remote_ip = $env->get('PNP_CLIENT_IP');

  my ($myusername,$action,$reason,$database,$dbh) = @_;
  $myusername = substr($myusername,0,24);
  $action = substr($action,0,20);
  $reason = $reason . " by $remote_ip";
  $reason = substr($reason,0,255);
  my $now = time();

  my $sth_history = $dbh->prepare(q{
      insert into history
      (trans_time,username,action,descr)
      values (?,?,?,?)
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth_history->execute($now,$myusername,$action,$reason)
                        or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth_history->finish;
}

sub authenticate {
  my $username = shift;
  my $password = shift;

  my $features = new PlugNPay::Features($username,'general');
  my $masterRemoteClientUsername = $features->get('masterRemoteClientUN');

  my $authClient = new PlugNPay::Authentication();

  my $authenticated = $authClient->validateLogin({
    login => $username,
    password => $password,
    realm => 'REMOTECLIENT',
  });

  if (!$authenticated && $masterRemoteClientUsername ne $username) {
    $authenticated = $authClient->validateLogin({
      login => $masterRemoteClientUsername,
      password => $password,
      realm => 'REMOTECLIENT',
    });
  }

  return $authenticated;
}

sub security_check {
  my $env = new PlugNPay::Environment();
  my $remote_ip = $env->get('PNP_CLIENT_IP');

  my ($username,$password,$mode,$remoteaddr,$client) = @_;

  my ($ipaddr,%result,$login,$test,$test2,$netmask,$office_override,$non_rc_pwd_found,$noreturns);

  %remote::security = ();

  my $authenticated = authenticate($username, $password);

  my $submitted_IP = $remoteaddr;

  $username =~ s/[^a-zA-Z0-9]//g;
  $password =~ s/\'//g;

  $remote::gatewayAccount = new PlugNPay::GatewayAccount($remote::query{'merchant'});
  my $bypassipcheck =  $remote::gatewayAccount->canBypassIpCheck();
  my $reseller = $remote::gatewayAccount->getReseller();


  ###  DCP 20100223 Remove after VS implements new store results system.
  if ($remote::query{'client'} =~ /^rectrac$/) {
    $bypassipcheck = "yes";
  }

  if (($remote::query{'client'} =~ /^(dydacomp1)$/) && ($bypassipcheck)) {
    $remote::registered_ips{$username} = $remoteaddr;
  }
  elsif (($remote::query{'client'} eq "quikstor") && ($bypassipcheck) && ($remote::query{'rempasswd'} ne "")) {   ##Added back 2011051
    $remoteaddr = $remote::query{'rempasswd'};
  }
  elsif (($remote::query{'client'} =~ /barkresearch|shopkeep|rectrac|cciphone|intuit/i) && ($bypassipcheck)) {
    $remote::registered_ips{$username} = $remoteaddr;
  }
  elsif (($username =~ /^(escltd)$/i) && ($bypassipcheck)) {
    $remote::registered_ips{$username} = $remoteaddr;
  }
  elsif (($mode eq "XML") && ($client =~ /^(quikstor)$/i) && ($bypassipcheck)) { ### Added back 20110513
     $remote::registered_ips{$username} = $remoteaddr;
  }
  elsif ( ($mode =~ /^(XML|COLLECTBATCH)$/) && ($client =~ /^(onestep)$/i) && (($bypassipcheck) || ($reseller eq "tri8inc")) ) {
     $remote::registered_ips{$username} = $remoteaddr;
  }
  elsif ($reseller =~ /^(vermont|vermont2|vermont3)$/) {  ###  DCP 20110105 - VMS is not sending client=rectrac with transactions.
    $remote::registered_ips{$username} = $remoteaddr;
  }


  ### IP Override for testing from office.
  if ($remote_ip =~ /^(96\.56\.10\.(12|14)|10\.150\.50\.(10|20)|192\.168\.1\.240)$/) {
    $remote::registered_ips{$username} = $remoteaddr;
    if ($remote::accountFeatures->get('rmt_admin_override') ne "") {
      # the feature "rmt_admin_override specifies the time support was turned on and lasts for 12 hours.
      # do not use "support" mode if before the time set and only use it until 12 hours after the set time

      # create times for now and 12 hours ago to compare the feature to
      my ($d1,$d2,$nowminus12hrs) = &miscutils::gendatetime(-12*3600);
      my ($d3,$d4,$now) = &miscutils::gendatetime();

      if (($now >= $remote::accountFeatures->get('rmt_admin_override')) && ($nowminus12hrs < $remote::accountFeatures->get('rmt_admin_override'))) {
        # someone needs to go through and rename these variables.  "test" is not descriptive at all and the context is not clear. -chris
        $office_override ="1";
      }
    }
  }

  

  if ($remote::query{'mode'} eq "authenticate") {
    if ($authenticated) {
      $result{'FinalStatus'} = "success";
    } else {
      $result{'FinalStatus'} = "problem";
    }
  }

  if ( !exists $remote::registered_ips{$username} ) {
    if ($remote::accountFeatures->get('admn_sec_req') !~ /ip/i) {
      $ipaddr = "pass";
    } else {
      if ($authenticated) {
        my $ip = NetAddr::IP->new("$remoteaddr");
        $remoteaddr =~ /([\da-zA-Z]+)\.([\da-zA-Z]+)\.([\da-zA-Z]+)\.([\da-zA-Z]+)/;
        my $testip = "$1\.$2\.$3\.\%";
        my $dbh = new PlugNPay::DBConnection()->getHandleFor("pnpmisc");
        my $sth = $dbh->prepare(q{
            select ipaddress,netmask
            from ipaddress
            where username=?
            and ipaddress LIKE ?
          }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
        $sth->execute($username,$testip) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
        $sth->bind_columns(undef,\($ipaddr,$netmask));
        while ($sth->fetch) {
          if (($netmask < 24) || ($netmask > 32)) {
            $netmask = "32";
          }
          if ($remoteaddr eq $ipaddr) {
            last; #### Work Around for Rempasswd
          }
          else {
            my $db_ip = NetAddr::IP->new("$ipaddr/$netmask");
            if ((defined $db_ip) && (defined $ip)) {
              if ( $ip->within($db_ip) ) {
                last;  ### IP IN RANGE;
              }
            }
            else {
              $ipaddr = "";
            }
          }
        }
        $sth->finish;
      }

      if ($remote::query{'client'} eq "quikstor") {
        my $masterUsername = $username;
        if ($remote::accountFeatures->get('masterRemoteClientUN') ne "") {
          $masterUsername = $remote::accountFeatures->get('masterRemoteClientUN');
        }
        #### DCP - 20110510  - If remoteaddr is modified due to custom coding then the database is checked against the real IP to see if it will pass.
        #### Possible only applicable to Quikstor because other modifcation work by modifying the real ip to match the submitted string.
        if (($ipaddr eq "") && ($remoteaddr ne "$submitted_IP")) {
          my $dbh = new PlugNPay::DBConnection()->getHandleFor("pnpmisc");
          my $sth = $dbh->prepare(q{
              select ipaddress
              from ipaddress
              where username=?
              and ipaddress=?
              and netmask='32'
            }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
          $sth->execute($masterUsername,$submitted_IP) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
          ($ipaddr) = $sth->fetchrow;
          $sth->finish;
        }
      }
    }
  }

  if ( $authenticated && ( $ipaddr ne "" || $remote::registered_ips{$username} =~ /$remoteaddr/ ) ) {
    $result{'flag'} = 1;
  }
  elsif ( $authenticated && $remote::query{'mode'} eq "inforetrieval" && ($remote::query{'client'} =~ /^(mm|mmnextel)$/)) {
    $result{'flag'} = 1;
  }
  elsif ( $ipaddr ne '' || $remote::registered_ips{$username} =~ /$remoteaddr/
            || (($login eq "") && ($remote::query{'subacct'} ne "")) ) {
    $result{'resp-code'} = "P91";
    $result{'MErrMsg'} = "Missing/incorrect password";
    $result{'flag'} = 0;
  }
  else {
    if ($remote::query{'client'} =~ /^(mm|mmnextel)$/) {
      $result{'resp-code'} = "P92";
      $result{'MErrMsg'} = "Account not configured for mobil administration. Please Enable Distributed Client in your security admin area.";
    }
    else {
      $result{'resp-code'} = "P93";
      $result{'MErrMsg'} = "IP Not registered to username. Please register $remoteaddr in your admin area.";
    }
    $result{'flag'} = 0;
  }


  ## Failed Security Test - Return
  if ($result{'flag'} == 0) {
    %remote::security = %result;
    return %result;
  }

  if ($remote::query{'mode'} =~ /^(mark|void|credit|newreturn|query_trans)$/) {
    if (($remote::query{'tranroutingflg'} == 1) || ($remote::accountFeatures->get('tranroutingflg') == 1)) {
      my $tr = new PlugNPay::Transaction::TransactionRouting();
      $tr->setLegacyTransaction(\%remote::query);
      my $un = $tr->tranRouting();
      if (($un ne "") && ($un ne $remote::query{'publisher-name'})) {
        ## Add indicator, transaction has been rerouted and pointer to original account name.
        $remote::query{'preRoutedAccount'} = $remote::query{'publisher-name'};
        $remote::query{'publisher-name'} = $un;
        $remote::query{'merchant'} = $un;
        $username = $un;
        delete $remote::query{'tranroutingflg'};
      }
    }
  }


  $remote::gatewayAccount = new PlugNPay::GatewayAccount($username);
  $remote::accountFeatures = new PlugNPay::Features("$username",'general');
  %remote::feature = %{$remote::accountFeatures->getFeatures()};

  $remote::processor = $remote::gatewayAccount->getCreditCardProcessor();
  $remote::chkprocessor = $remote::gatewayAccount->getACHProcessor();

  if (($remote::gatewayAccount->getReseller =~ /^(vermont|vermont2|vermont3)$/) && ($remote::gatewayAccount->canProcessCredits eq "yes") && ($remote::query{'mode'} =~ /^(credit|newreturn)$/)) {
    my ($error);
    $error = "Mode:credit\nUN:$username\nIP:$remote_ip\n\nVermont Systems Account\nCredits re-enabled for this account.";
    &support_email($error);
    $noreturns = "";
  }

  if (($remote::gatewayAccount->getCreditCardProcessor() eq "mercury") && ($remote::query{'mpgiftcard'} ne "") && ($remote::query{'transflags'} =~ /issue/) && ($remote::query{'card-number'} eq "")) {
    $noreturns = "";
  }

  if ($remote::gatewayAccount->getCreditCardProcessor() =~ /emv$/) {
    $remote::query{'terminalnum'} =~ s/[^0-9]//g;
    if ($remote::query{'terminalnum'} eq "") {
      $remote::query{'terminalnum'} = '00099';
    }
  }

  if ($remote::query{'currency'} eq "") {
    $remote::query{'currency'} = $remote::gatewayAccount->getDefaultCurrency();
  }

  ###  Over ride submitted currency with setup currency if the following conditions are not met.
  if (($remote::gatewayAccount->getCreditCardProcessor() !~ /^(pago|atlantic|planetpay|fifththird|testprocessor|wirecard|cal|catalunya)$/) && ($remote::accountFeatures->get('procmulticurr') != 1)) {
    $remote::query{'currency'} = $remote::gatewayAccount->getDefaultCurrency();
  }

  if ( exists $remote::query{'merchantdb'} ) {
    $remote::query{'merchantdb'} =~ tr/A-Z/a-z/;
    $remote::query{'merchantdb'} =~ s/[^a-z0-9]//g;
    if ($remote::accountFeatures->get('altmerchantdb') =~ /$remote::query{'merchantdb'}/) {
      # do nothing...
    }
    else {
      delete $remote::query{'merchantdb'};
    }
  }

  if ($remote::accountFeatures->get('hashkey') ne "") {
    my ($amount);
    if ($remote::query{'card-amount'} eq "") {
      $amount = "0.00";
    }
    else {
      $amount = $remote::query{'card-amount'};
    }
    my (@array) = split('\|',$remote::accountFeatures->get('hashkey'));
    my $key = shift (@array);
    foreach my $var (@array) {
      if ($var eq "card-amount") {
        $key .= $amount;
      }
      else {
        $key .= $remote::query{$var};
      }
    }
    my $md5 = new MD5;
    $md5->add("$key");
    $remote::query{'resphash'} = $md5->hexdigest();
  }


  if (($remote::query{'mode'} =~ /^(newreturn|credit)$/) && (! $remote::gatewayAccount->canProcessCredits)) {
    my $davesmsg = "Mode:$mode\nUN:$username\nSA:$remote::query{'subacct'}\nIP:$remoteaddr\n\n$remote::query{'mode'} not permitted for this account. Disabled by merchant.";
    $davesmsg .= "\norderID:$remote::query{'orderID'}\nAmount:$remote::query{'card-amount'}\n";
    &support_email($davesmsg);
    $result{'MErrMsg'} = "$remote::query{'mode'} not permitted for this account.";
    $result{'resp-code'} = "P94";
    $result{'flag'} = 0;
  }

  if (($remote::gatewayAccount->getProcessingType() eq "returnonly") && ($mode =~ /^(auth|forceauth)$/)) {
    my $davesmsg = "Mode:$mode\nUN:$username\nSA:$remote::query{'subacct'}\nIP:$remoteaddr\nProcType:$remote::gatewayAccount->getProcessingType()\n\n$mode not permitted for this account. Disabled by merchant.";
    &support_email($davesmsg);
    $result{'MErrMsg'} = "$remote::query{'mode'} not permitted for this account.";
    $result{'resp-code'} = "P94";
    $result{'flag'} = 0;
  }

  %remote::security = %result;
  return %result;
}

sub security_check1 {
  return security_check(@_);
}

sub trans_admin {
  return PlugNPay::Processor::Route::LegacyChecks::trans_admin(\%remote::query);
}

sub batch_commit {
  my (%query) = %remote::query;
  my (%result,$trancount);

  if (($query{'num-txns'} eq "") || ($query{'publisher-name'} eq "")) {
    $result{'FinalStatus'} = "problem";
    $result{'MStatus'} = "problem";
    $result{'MErrMsg'} = "Missing information. $query{'mode'} transaction failed.";
    return %result;
  }

  my $trans_id = PlugNPay::Transaction::TransactionProcessor::generateOrderID();
  my $group_id = $trans_id;
  my ($tranque);

  for (my $i=1; $i<=$query{'num-txns'}; $i++) {
    my (%input);

    $input{'publisher-name'} = $query{'publisher-name'};
    $input{'mode'} = "postauth";

    $input{'orderID'} = $query{"orderID-$i"};
    $input{'card-amount'} = $query{"card-amount-$i"};

    $result{"orderID-$i"} = $query{"orderID-$i"};

    ## Added DCP 20051207
    $input{'acct_code4'} = $query{'acct_code4'};

    if ($input{'orderID'} eq "") {
      $result{"FinalStatus-$i"} = "problem";
      $result{"MStatus-$i"} = "problem";
      $result{"MErrMsg-$i"} = "Transaction number $i is missing the orderID.";
      next;
    }

    if ($input{'card-amount'} eq "") {
      $result{"FinalStatus-$i"} = "problem";
      $result{"MStatus-$i"} = "problem";
      $result{"MErrMsg-$i"} = "Transaction number $i is missing the amount.";
      next;
    }
    $trancount++;
    my @array = %input;

    if ($remote::tranqueactive eq "yes") {
      $input{'mode'} = 'mark';
      $input{'pnp_orig_mode'} = 'batchcommit';
      my %inputhash = %input;
      $trans_id = $remote::tranque->format_data($trans_id,$group_id,\%inputhash);
      next;
    }

    my %trans = &miscutils::check_trans(@array);

    if (($trans{'Duplicate'} eq "yes") || ($trans{'debug'} == 1)) {
      foreach my $key (keys %trans) {
        $result{"$key\-$i"} = $trans{$key};
      }
      next;
    }

    if ($trans{'allow_mark'} == 1) {
      if ($query{"dccoptout-$i"} eq "Y") {
        $remote::query{'dccoptout'} = "Y";
        $remote::query{'orderID'} = $input{'orderID'};
        my %result = &dccoptout();
        delete $remote::query{'dccoptout'};
        delete $remote::query{'orderID'};
      }

      ## Added DCP 20051207
      $input{'currency'} = substr($trans{'authamt'},0,3);
      $input{'currency'} =~ s/[^a-zA-Z]//g;

      my $test = substr($trans{'authamt'},4);

      if ($test eq "") {
        $test = substr($trans{'amount'},4);
      }
      if (($test > $input{'card-amount'}) && ($trans{'allow_reauth'} == 1)) {
        if ($input{'currency'} eq "") {
          $input{'currency'} = "usd";
        }
        my (%res);
        my $price = sprintf("%3s %.2f","$input{'currency'}",$input{'card-amount'}+0.0001);
        %res = &miscutils::sendmserver($input{'publisher-name'},"reauth"
              ,'order-id',$input{'orderID'}
              ,'amount', $price
              ,'acct_code4',"$input{'acct_code4'}"
              );

        if ($res{'FinalStatus'} eq "success") {
          %res = &miscutils::sendmserver($query{'publisher-name'},"postauth"
              ,'order-id',$input{'orderID'}
              ,'amount', $price
              ,'acct_code4',"$input{'acct_code4'}"
              );
        }
        if (exists $res{'FinalStatus'}) {
          $result{"FinalStatus\-$i"} = $res{'FinalStatus'};
          $result{"MStatus\-$i"} = $res{'MStatus'};
        }
        else {
          $result{"FinalStatus\-$i"} = "problem";
          $result{"MStatus\-$i"} = "problem";
        }
        if ($result{'FinalStatus'} =~ /^pending|success$/) {
          $result{"aux-msg\-$i"} = "$input{'orderID'} has been successfully reauthed.";
        }
        else {
          $result{"MErrMsg\-$i"} = "$input{'orderID'} was not reauthed successfully.";
        }
      }
      else {
        if ($input{'currency'} eq "") {
          $input{'currency'} = "usd";
        }
        my $price = sprintf("%3s %.2f","$input{'currency'}",$input{'card-amount'}+0.0001);

        my %res = &miscutils::sendmserver($input{'publisher-name'},"postauth"
               ,'order-id',$input{'orderID'}
               ,"amount","$price"
               ,"acct_code4","$input{'acct_code4'}"
               );

        if (exists $res{'FinalStatus'}) {
          $result{"FinalStatus\-$i"} = $res{'FinalStatus'};
          $result{"MStatus\-$i"} = $res{'MStatus'};
        }
        else {
          $result{"FinalStatus\-$i"} = "problem";
          $result{"MStatus\-$i"} = "problem";
        }

        if ($res{'FinalStatus'} =~ /^(pending|success)$/) {
          $result{"MErrMsg\-$i"} = "$input{'orderID'} has been successfully marked for settlement.";
        }
        else {
          $result{"MErrMsg\-$i"} = "$input{'orderID'} was not marked successfully.";
        }
      }
    }
    else {
      $result{"FinalStatus\-$i"} = "problem";
      if (($trans{'mark_flag'} == 1) || ($trans{'mark_ret_flag'} == 1)) {
        $result{"MErrMsg\-$i"} = "Transaction previously marked successfully.";
      }
      elsif ($trans{'order-id'} eq "") {
        $result{"MErrMsg\-$i"} = "Transaction orderid does not exist and may not be marked."
      }
      else {
        $result{"MErrMsg\-$i"} = "Transaction may not be marked.";
      }
    }
  }
  $result{'FinalStatus'} = "success";
  $result{'MStatus'} = "success";

  if ($remote::tranqueactive eq "yes") {
    my @results_array = &tranque::check_results($group_id,$trancount,'batchcommit');
    my $i = 0;
    foreach my $hash (@results_array) {
      $i++;
      delete $$hash{'mode'};
      my @array = %$hash;
      foreach my $key (keys %$hash) {
        $result{"$key\-$i"} = $$hash{$key};
      }
    }
  }

  return %result;
}

sub batch_auth {
  my (%query) = %remote::query;
  my (%result,$errvar,$oldorderid,$trancount);

  my @required = ('num-txns');
  foreach my $var (@required) {
    $query{$var} =~ s/[^0-9]//g;
    if ($query{$var} eq "") {
      $errvar .= "$var: ";
    }
  }

  if ($errvar ne "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "The following variables were missing or were non-numeric: $errvar";
    return %result;
  }

  my $trans_id = PlugNPay::Transaction::TransactionProcessor::generateOrderID();
  my $group_id = $trans_id;
  my ($tranque);

  my ($foundflag);
  for (my $i=1; $i<=$query{'num-txns'}; $i++) {
    my(%input);
    $input{'publisher-name'} = $query{'publisher-name'};
    if (exists $query{'client'}) {
      $input{'client'} = $query{'client'};
    }
    $input{'mode'} = "auth";
    $foundflag = 0;
    foreach my $key (keys %query) {
      my ($ikey,$idx);
      if ($key =~ /(.*)\-([0-9]*)$/) {
        $ikey = $1;
        $idx = $2;
        if ($idx == $i) {
          $foundflag = 1;
          $input{$ikey} = $query{$key};
          delete $query{$key};
        }
      }
    }
    if ($foundflag != 1) {
      next;
    }
    $trancount++;
    if ($input{'orderID'} eq "") {
      if ($input{'orderid'} ne "") {
        $input{'orderID'} = $input{'orderid'};
      }
      elsif ($input{'ORDERID'} ne "") {
        $input{'orderID'} = $input{'ORDERID'};
      }
    }

    if ($input{'orderID'} eq "") {
      my ($orderid,$dummy);
      if ($i == 1) {
        $orderid = PlugNPay::Transaction::TransactionProcessor::generateOrderID();
      }
      else {
        my $k = $i-1;
        ## DCP - Below added 20040301 to handle situation where bad data is being passwed with wrong index.
        if ($oldorderid eq "") {
          $oldorderid = PlugNPay::Transaction::TransactionProcessor::generateOrderID();
        }
        ($orderid,$dummy,$dummy) = &miscutils::incorderid($oldorderid);
      }
      $input{'orderID'} = $orderid;
    }

    my @array = %input;

    if ($remote::tranqueactive eq "yes") {
      $input{'mode'} = 'auth';
      $input{'pnp_orig_mode'} = 'batchauth';
      my %inputhash = %input;
      $trans_id = $remote::tranque->format_data($trans_id,$group_id,\%inputhash);
      $oldorderid = $input{'orderID'};
      next;
    }

    my $payment = mckutils->new(@array);

    my %res = $payment->purchase("auth");

    $payment->database();

    $res{'auth-code'} = substr($res{'auth-code'},0,6);
    foreach my $key (keys %res) {
       $result{"$key\-$i"} = $res{$key};
    }
    $result{"orderID\-$i"} = $input{'orderID'};
    $oldorderid = $input{'orderID'};
  }
  $result{'FinalStatus'} = "success";

  if ($remote::tranqueactive eq "yes") {
    my @results_array = &tranque::check_results($group_id,$trancount,'batchauth');
    my $i = 0;
    foreach my $hash (@results_array) {
      $i++;
      delete $$hash{'mode'};
      my @array = %$hash;
      foreach my $key (keys %$hash) {
        $result{"$key\-$i"} = $$hash{$key};
      }
    }
  }

  return %result;
}

sub batch_file {

  my (%result, $errvar);
  my $filelimit = 5000;
  my ($date,$time) = &miscutils::gendatetime_only();

  my @required = ('batchid','num-txns');
  foreach my $var (@required) {
    my $test = $remote::query{$var};
    $test =~ s/[^0-9]//g;
    if ($test eq "") {
      $errvar .= "$var: ";
    }
  }

  if ($errvar ne "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "The following variables were missing or were non-numeric: $errvar";
    return %result;
  }

  $remote::query{'data'} =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\r\n\t \,\!\|\+]/x/g;

  my @data = split(/\r\n|\n/,$remote::query{'data'});

  if (@data > $filelimit) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "File exceeds maximum transaction limit of $filelimit.";
    return %result;
  }

  require uploadbatch;

  my $uploadbatch = uploadbatch->new();

  if ($remote::query{'batchid'} ne "") {
    $remote::query{'batchid'} =~ s/[^a-zA-Z0-9\_\-]//g;
    $uploadbatch::batchid = $remote::query{'batchid'};
  }

  # Make sure this batchid does not exist.
  my $sth = $uploadbatch::dbh->prepare(qq{
      select batchid
      from batchfile
      where batchid=?
    }) or &miscutils::errmail("__LINE__,__FILE__,Can't prepare: $DBI::errstr");
  $sth->execute("$uploadbatch::batchid") or &miscutils::errmail("__LINE__,__FILE__,Can't prepare: $DBI::errstr");
  my ($batchid_exists) = $sth->fetchrow;
  $sth->finish;

  if ($batchid_exists ne "") {
    $uploadbatch::dbh->disconnect;
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "This Batch ID already exists.";
    return %result;
  }

  my $trn_cnt = 0;
  my $trans_id = PlugNPay::Transaction::TransactionProcessor::generateOrderID();
  my $firstorderid = $trans_id;
  my $lastorderid = "";
  my ($junk1,$junk2,$trans_time) = &miscutils::gendatetime();
  my $header = "";

  if ($remote::query{'format'} eq "yes") {
    $header = shift @data;
  }

  foreach my $line (@data) {
    if ($line ne "") {
      $trn_cnt++;
      &uploadbatch::insert_transaction($uploadbatch::batchid,$trans_id,$remote::query{'publisher-name'},$line,$trans_time,"$trn_cnt","$remote::query{'subacct'}","$header","$remote::query{'format'}");
    }
    $lastorderid = $trans_id;
    $trans_id = &miscutils::incorderid($trans_id);
  }

  delete $remote::query{'data'};

  &uploadbatch::insert_batch($uploadbatch::batchid,$firstorderid,$lastorderid,$remote::query{'publisher-name'},$header,$remote::query{'format'},$remote::query{'emailresults'},$remote::query{'sndmail'});

  &uploadbatch::finalize_batch($uploadbatch::batchid);

  if ($remote::query{'num-txns'} == $trn_cnt) {
    $result{'FinalStatus'} = "success";
    $result{'aux-msg'} =  "Batch uploaded successfully.";
    $result{'resultURL'} = "https://" . $ENV{'SERVER_NAME'} . "/admin/uploadbatch.cgi\?function=retrieveresults\&batchid=$uploadbatch::batchid";
  }
  else {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Transaction count mismatch. $trn_cnt:$remote::query{'num-txns'}";
  }
  $uploadbatch::dbh->disconnect;
  return %result;
}

sub batch_file_new {
  my (%result, $errvar);
  my $filelimit = 5000;
  my ($date,$time) = &miscutils::gendatetime_only();

  my @required = ('batchid','num-txns');
  foreach my $var (@required) {
    my $test = $remote::query{$var};
    $test =~ s/[^0-9]//g;
    if ($test eq "") {
      $errvar .= "$var: ";
    }
  }

  if ($errvar ne "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "The following variables were missing or were non-numeric: $errvar";
    return %result;
  }

  $remote::query{'data'} =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\r\n\t \,\!\|\+]/x/g;

  my @data = split(/\r\n|\n/,$remote::query{'data'});

  if (@data > $filelimit) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "File exceeds maximum transaction limit of $filelimit.";
    return %result;
  }
  elsif (($remote::query{'publisher-name'} =~ /pnpdemo2/) && (@data > 50)) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "File exceeds maximum transaction limit of 50 for test accounts.";
    return %result;
  }

  require uploadbatch;
  my $uploadbatch = uploadbatch->new();

  if ($remote::query{'batchid'} ne "") {
    $uploadbatch::batchid = $remote::query{'batchid'};
  }

  if (($remote::accountFeatures->get('upload_batch_priority') > 0) || ($remote::accountFeatures->get('upload_batch_priority') < 0 )) {
    $uploadbatch::upload_batch_priority = $remote::accountFeatures->get('upload_batch_priority');
  }
  else {
    $uploadbatch::upload_batch_priority = 0;
  }
  $uploadbatch::upload_batch_priority = substr($uploadbatch::upload_batch_priority,0,2);

  # Make sure this batchid does not exist.
  my $sth = $uploadbatch::dbh->prepare(qq{
      select batchid
      from batchfile
      where batchid=?
    }) or &miscutils::errmail("__LINE__,__FILE__,Can't prepare: $DBI::errstr");
  $sth->execute("$uploadbatch::batchid") or &miscutils::errmail("__LINE__,__FILE__,Can't prepare: $DBI::errstr");
  my ($batchid_exists) = $sth->fetchrow;
  $sth->finish;

  if ($batchid_exists ne "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "This Batch ID already exists.";
    $uploadbatch::dbh->disconnect;
    return %result;
  }

  my $trn_cnt = 0;
  my $trans_id = PlugNPay::Transaction::TransactionProcessor::generateOrderID();
  my $firstorderid = $trans_id;
  my $lastorderid = "";
  my ($junk1,$junk2,$trans_time) = &miscutils::gendatetime();
  my $header = "";
  my $insert_tran_cnt = 20;

  if ($remote::query{'format'} eq "yes") {
    $header = shift @data;
    $header =~ s/\r//g;
    $header =~ s/\n//g;
    if ($header !~ /^\!batch/i) {
      $uploadbatch::dbh->disconnect;
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = "Invalid header, check and attempt upload again.";
      return %result;
    }
  }
  my @array1 = ();
  my @array2 = ();

  foreach my $line (@data) {
    my $temp_line = $line;
    $temp_line =~ s/\t//g;
    if (($line ne "")&& ($temp_line ne "") && ($line !~ /^\!batch/i)) {
      $trn_cnt++;
      @array2 = ("$uploadbatch::batchid","$trans_id","$remote::query{'publisher-name'}","$line","$trans_time","$trn_cnt","$remote::query{'subacct'}","$header","$remote::query{'format'}");
      $array1[++$#array1] = [@array2];
      $lastorderid = $trans_id;
      $trans_id = &miscutils::incorderid($trans_id);
      if (@array1 == $insert_tran_cnt) {
        &uploadbatch::insert_transaction_multi(\@array1);
        @array1 = ();
      }
    }
  }
  ## Last
  if (@array1 > 0) {
    &uploadbatch::insert_transaction_multi(\@array1);
    @array1 = ();
  }

  delete $remote::query{'data'};

  &uploadbatch::insert_batch($uploadbatch::batchid,$firstorderid,$lastorderid,$remote::query{'publisher-name'},$header,$remote::query{'format'},$remote::query{'emailresults'},$remote::query{'sndmail'});

  &uploadbatch::finalize_batch($uploadbatch::batchid);

  if ($remote::query{'num-txns'} == $trn_cnt) {
    $result{'FinalStatus'} = "success";
    $result{'aux-msg'} =  "Batch uploaded successfully.";
    $result{'resultURL'} = "https://" . $ENV{'SERVER_NAME'} . "/admin/uploadbatch.cgi\?function=retrieveresults\&batchid=$uploadbatch::batchid";
  }
  else {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Transaction count mismatch. $trn_cnt:$remote::query{'num-txns'}";
  }

  $uploadbatch::dbh->disconnect;
  return %result;
}

sub batch_results {
  #require uploadbatch;
  #my $uploadbatch = uploadbatch->new();
  #if ($remote::query{'batchid'} ne "") {
  #  $uploadbatch::batchid = $remote::query{'batchid'};
  #}
  my (%result, $errvar, $foundflg);

  # get batch header flag
  my $headerflag = "";
  my $header = "";
  my $line = "";
  my $db_line = "";

  $remote::query{'batchid'} =~ s/[^a-zA-Z0-9\_\-]//g;
  if ($remote::query{'batchid'} eq "") {
    ## Return Error
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "BatchID missing.";
    return %result;
  }
  my $batchid = $remote::query{'batchid'};

  my $dbh = &miscutils::dbhconnect("uploadbatch");

  my $sth = $dbh->prepare(qq{
      select headerflag,header
      from batchid
      where username=?
      and batchid=?
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr $batchid");
  $sth->execute("$remote::query{'publisher-name'}","$batchid") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr $batchid");
  $sth->bind_columns(undef,\($headerflag,$header));
  $sth->fetch;
  $sth->finish;

  my (%statuscnt,$count,$status);
  $statuscnt{'success'} = 0;
  $statuscnt{'locked'} = 0;
  $statuscnt{'pending'} = 0;

  my $sth_count = $dbh->prepare(qq{
      select count(orderid),status
      from batchfile
      where username=?
      and batchid=?
      group by status
    }) or die "prepare $DBI::errstr\n";
  $sth_count->execute("$remote::query{'publisher-name'}","$batchid") or die "execute $DBI::errstr\n";
  $sth_count->bind_columns(undef,\($count,$status));
  # count of trxs left to process
  my $process_count = 0;
  while ($sth_count->fetch) {
    $foundflg = 1;
    if (($status eq "pending") || ($status eq "locked")) {
      $process_count += $count;
    }
    $statuscnt{$status} = $count;
  }
  $sth_count->finish;

  if ($headerflag eq "yes") {
    $line = "FinalStatus\tMErrMsg\tresp-code\torderID\tauth-code\tavs-code\tcvvresp\t$header\n";
  }

  my $sth2 = $dbh->prepare(qq{
      select line
      from batchresult
      where batchid=?
      and username=?
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr $batchid");
  $sth2->execute("$batchid","$remote::query{'publisher-name'}") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr $batchid");
  $sth2->bind_columns(undef,\($db_line));
  while ($sth2->fetch()) {
    $line .= "$db_line\n";
    $foundflg = 1;
  }
  $sth2->finish;

  $dbh->disconnect;

  if ($foundflg == 1) {
    $result{'FinalStatus'} = "success";
    $result{'results'} = $line;
    if ($process_count > 0) {
      $result{'batchstatus'} = "pending";
      $result{'trans_pending'} = $process_count;
      $result{'trans_success'} = $statuscnt{'success'};
    }
    else {
      $result{'batchstatus'} = "complete";
      $result{'trans_success'} = $statuscnt{'success'};
    }
  }
  else {
    ## Return Error
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "No Data Found.";
  }

  return %result;
}

sub query_trans {
  my %query = %remote::query;
  my $username = $query{'publisher-name'} || $query{'merchant'};
  my $gatewayAccount = new PlugNPay::GatewayAccount($username);
  my $featureVersion = $gatewayAccount->getFeatures()->get('queryTransVersion');

  if ($featureVersion == 2 || $gatewayAccount->usesUnifiedProcessing()) {
    my $newData = &_loadTransactions();
    return &_mapData($newData,$query{'qresp'});
  } else {
    return &_legacy_query_trans();
  }
}

sub _loadTransactions {
  my %query = %remote::query;
  my $loadParams = {};
  my $username = $query{'publisher-name'} || $query{'merchant'};
  $loadParams->{'username'} = $username;
  if ($query{'trans_date'} || $query{'transdate'}) {
    $loadParams->{'transaction_date_time'} = $query{'trans_date'} || $query{'transdate'};
  } else {
    $loadParams->{'start_date'} = $query{'startdate'} if (defined $query{'startdate'});
    $loadParams->{'end_date'} = $query{'enddate'} if (defined $query{'enddate'});
  }
  $loadParams->{'order_classification_id'} = $query{'order-id'} if (defined $query{'order-id'});
  $loadParams->{'amount'} = $query{'amount'} if (defined $query{'amount'});
  $loadParams->{'authorization_code'} = $query{'auth-code'} if (defined $query{'auth-code'});
  $loadParams->{'processor'} = $query{'processor'} if (defined $query{'processor'});
  $loadParams->{'vendor_token'} = $query{'vendor_token'} if (defined $query{'vendor_token'});
  $loadParams->{'operation'} = $query{'operation'} if ($query{'operation'});
  $loadParams->{'account_type'} = $query{'accttype'} if ($query{'accttype'});

  my $orderID = ($query{'orderID'} ? $query{'orderID'} : $query{'orderid'});
  my $loadPaymentData = 0;
  if ($orderID) {
    $loadPaymentData = 1;
    $loadParams->{'orderID'} = $orderID;
  }
  my $loader = new PlugNPay::Transaction::Loader({'loadPaymentData' => $loadPaymentData});
  my $loaded = {};
  eval {
    $loaded = $loader->load($loadParams)->{$username};
  };

  if ($@) {
    my $dataLog = new PlugNPay::Logging::DataLog({'collection' => 'query_trans'});
    $dataLog->log({'message' => $@, 'status' => 'error', 'caller' => $ENV{'REMOTE_USER'},'search_params' => $loadParams});
  }

  return $loaded;
}

sub _mapData {
  my $loaded = shift || {};
  my $responseFormat = shift || 'complex';
  my %legacyData = ();
  my $index = 0;
  my $amtHash = {'operation_total' => {},
                 'date_total' => {},
                 'batch_total' => {}
                };

  my $mapper = new PlugNPay::Transaction::MapLegacy();
  my $transactions = [];
  my $historyBuilder = new PlugNPay::Transaction::Loader::History();

  foreach my $orderID (sort keys %{$loaded}) {
    my %extraTransactions = %{$loaded->{$orderID}->getExtraTransactionData()};
    my $currentTransaction = $loaded->{$orderID};
    my $newExtra = {};
    foreach my $transState (keys %extraTransactions ) {
      if (ref($extraTransactions{$transState}) =~ /^PlugNPay::Transaction/) {
        my $responseData = $extraTransactions{$transState}->getExtraTransactionData()->{'response_data'};
        push @{$transactions}, $mapper->mapRemote($extraTransactions{$transState},$responseData);
      } else {
        $newExtra->{$transState} = $extraTransactions{$transState};
      }
    }

    my $currentResponse = $extraTransactions{'response_data'};
    $currentTransaction->setExtraTransactionData($newExtra);
    push @{$transactions}, $mapper->mapRemote($currentTransaction,$currentResponse);
    my $history = $historyBuilder->buildTransactionHistory($currentTransaction);
    my @historic = map {$mapper->mapRemote($_)} values %{$history};
    push @{$transactions},@historic;
  }

  if (@{$transactions} > 0) {
    # Hold on to ya butts....
    foreach my $legacyMapped (@{$transactions}) {
      my $idx = sprintf("%05d",$index);

      my $transDate = $legacyMapped->{'trans_time'};
      my $result = $legacyMapped->{'status'};
      my $operation = $legacyMapped->{'operation'};
      my ($currency,$amount);
      if ($legacyMapped->{'amountcharged'} =~ / /) {
        ($currency,$amount) = split(/ /,$legacyMapped->{'amountcharged'});
      } else {
        $amount = $legacyMapped->{'amountcharged'};
        $currency = $legacyMapped->{'currency'};
      }

      if ($amount) {
        $amount =~ s/[^0-9\.]//g;
        if ($operation =~ /return|credit/) {
          $amtHash->{batch_total}{$result} -= $amount;
          $amtHash->{date_total}{$transDate} -= $amount;
          $amtHash->{operation_total}{'return'} += $amount;
        } elsif ($operation =~ /postauth/) {
          $amtHash->{batch_total}{$result} += $amount;
          $amtHash->{date_total}{$transDate} += $amount;
          $amtHash->{operation_total}{'postauth'} += $amount;
        } elsif ($operation =~ /sale/) {
          $amtHash->{batch_total}{$result} += $amount;
          $amtHash->{date_total}{$transDate} += $amount;
          $amtHash->{operation_total}{'sale'} += $amount;
        } elsif ($operation =~ /void/){
          $amtHash->{operation_total}{'void'} += $amount;
        } else {
          $amtHash->{'operation_total'}{'auth'} += $amount;
        }
      }

      if ($responseFormat =~ /simple/i) {
        $legacyData{"a$idx"} = 'operation=' . $operation . '&FinalStatus=' . $result . '&orderID=' . $legacyMapped->{'orderID'} . '&trans_date=' . $legacyMapped->{'trans_date'} . '&trans_time=' . $legacyMapped->{'trans_time'};
      } else {
        $legacyData{"a$idx"} = join('&', map{ $_ . '=' . $legacyMapped->{$_} } sort keys %{$legacyMapped});
      }
      $index++;
    }

    if ($index > 0) {
      if ($remote::query{'operation'} =~ /^(batchquery)$/) {
        foreach my $key (keys %{$amtHash->{batch_total}}) {
          $legacyData{"batchtotal_$key"} = $amtHash->{batch_total}{$key};
        }
        foreach my $key (keys %{$amtHash->{'date_total'}}) {
          $legacyData{"datetotal_$key"} = $amtHash->{'date_total'}{$key};
        }
      }

      foreach my $key (keys %{$amtHash->{'operation_total'}}) {
        $legacyData{"opertotal_$key"} = $amtHash->{'operation_total'}{$key};
      }
      $legacyData{'FinalStatus'} = "success";
      $legacyData{'num-txns'} = $index;
    } else {
      $legacyData{'FinalStatus'} = "problem";
      $legacyData{'MErrMsg'} = "No Records to Parse";
    }
  } else {
    $legacyData{'FinalStatus'} = "problem";
    $legacyData{'MErrMsg'} = "No Records Found";
  }

  return %legacyData;
}

sub _legacy_query_trans {
  # Required fields publisher-name
  my (%query) = %remote::query;
  my (%result,$startdate,$enddate);
  my ($datestr,$timestr,$enccardnumber,$length,%amthash,%amt1hash,%amt2hash,$starttime,$endtime);


  my $adjustmentFlag = 0;
  my $surcharge_flag = 0;
  if ($remote::accountFeatures->get('convfee')) {
    my $cf = new PlugNPay::ConvenienceFee($query{'publisher-name'});
    if ($cf->getEnabled()) {
      $adjustmentFlag = 1;
      if ($cf->isSurcharge()) {
        $surcharge_flag = 1;
      }
    }
  }
  elsif ($remote::accountFeatures->get('cardcharge')) {
    my $coa = new PlugNPay::COA($query{'publisher-name'});
    if ($coa->getEnabled()) {
      $adjustmentFlag = 1;
      if ($coa->isSurcharge()) {
        $surcharge_flag = 1;
      }
    }
  }

  if ($query{'orderID'} ne "") {
    ## orderID is being passed
    #my $timeadjust = (365 * 24 * 3600);
    #($dummy,$datestr,$timestr) = &miscutils::gendatetime("-$timeadjust");
    $datestr = "20040101";
  }
  else {
    ### orderID is blank
    my $timeadjust = (1095 * 24 * 3600);
    ($datestr,$timestr) = &miscutils::gendatetime_only("-$timeadjust");

    ###  DCP 20101020 delete ability to decrypt cardnumber if query does not specify individual orderID
    delete $query{'decryptflag'};
  }

  if (exists $query{'startdate'}) {
    $query{'startdate'} =~ s/[^0-9]//g;
    $query{'startdate'} =~ /^(\d{8})(\d*)/;
    $query{'startdate'} = $1;
    $starttime = $2;
    if (($starttime =~ /^([0-2][0-9][0-5][0-9][0-5][0-9])/) && ($starttime < 240000)) {
      $starttime = $query{'startdate'} . $1;
    }
    else {
      $starttime = "";
    }
  }
  if (exists $query{'enddate'}) {
    $query{'enddate'} =~ s/[^0-9]//g;
    $query{'enddate'} =~ /^(\d{8})(\d*)/;
    $query{'enddate'} = $1;
    $endtime = $2;
    if (($endtime =~ /^([0-2][0-9][0-5][0-9][0-5][0-9])/) && ($endtime < 240000)) {
      $endtime = $query{'enddate'} . $1;
    }
    else {
      $endtime = "";
    }
  }

  if ($query{'startdate'} < $datestr) {
    my $timeadjust = (2 * 24 * 3600);
    my ($datestr,$timestr) = &miscutils::gendatetime_only("-$timeadjust");
    $startdate = $datestr;
  }
  else {
    $startdate = $query{'startdate'};
  }

  if ($query{'enddate'} eq "") {
    my $timeadjust = (1 * 24 * 3600);
    my ($datestr,$timestr) = &miscutils::gendatetime_only("$timeadjust");
    $enddate = $datestr;
  }
  else {
    $enddate = $query{'enddate'};
  }

  if ($enddate < $startdate) {
    $enddate = $startdate + 1;
  }

  my @cardHashes = ();
  my %cardHashRef = ();
  my ($qmarks);
  if ($query{'card-number'} ne "") {
    my $cc = new PlugNPay::CreditCard($query{'card-number'});
    @cardHashes = $cc->getCardHashArray();
    $qmarks = '?' . ',?'x($#cardHashes);
  }

  my $starttimea = &miscutils::strtotime($startdate);
  my $endtimea = &miscutils::strtotime($enddate);
  my $elapse = $endtimea-$starttimea;

  if (($elapse > (93 * 24 * 3600)) && ($query{'orderID'} eq "")) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "No more than 3 months may be queried at one time.";
    return %result;
  }

  my @values = ();
  my $qstr = "select trans_date,trans_time,operation,finalstatus,amount,descr,result,orderid,";
  $qstr .= "card_name,card_addr,card_city,card_state,card_zip,card_country,card_number,card_exp,cvvresp,";
  $qstr .= "acct_code,acct_code2,acct_code3,acct_code4,accttype,auth_code,avs,enccardnumber,length,refnumber,batch_time,processor ";

  $qstr .= "from trans_log ";

  my @dateArray=();

  my ($qmarks2,$dateArray) = &miscutils::dateIn($startdate,$enddate);

  if (-e "/home/p/pay1/database/debug/querytdate.txt") {
    $qstr .= "where trans_date>=? ";
    push(@values, $startdate);
    $qstr .= "and trans_date<? ";
    push(@values, $enddate);
    if ($query{'orderID'} ne "") {
      $qstr .= "and orderid=? ";
      push(@values, $query{'orderID'});
    }
    elsif ($query{'card-number'} ne "") {
      $qstr .= "and shacardnumber IN ($qmarks) ";
      push(@values, @cardHashes);
    }
  }
  else {
    if ($query{'orderID'} ne "") {
      $qstr .= "FORCE INDEX (PRIMARY) where orderid=? and trans_date IN ($qmarks2) ";
      push(@values, $query{'orderID'}, @$dateArray);
    } elsif ($query{'card-number'} ne "") {
      $qstr .= "FORCE INDEX(tlog_tdatesha_idx) where shacardnumber IN ($qmarks) and trans_date IN ($qmarks2) ";
      push(@values, @cardHashes, @$dateArray);
    } else {
      $qstr .= "FORCE INDEX(tlog_tdateuname_idx) where trans_date IN ($qmarks2) ";
      push(@values, @$dateArray);
    }
  }

  if (exists $remote::altaccts{$query{'publisher-name'}}) {
    my ($temp);
    foreach my $var ( @{ $remote::altaccts{$query{'publisher-name'}} } ) {
      $temp .= "?,";
      push(@values, $var);
    }
    chop $temp;
    $qstr .= "and username IN ($temp) ";
  }
  else {
    $qstr .= "and username=? ";
    push(@values, $query{'publisher-name'});
  }

  if ($query{'subacct'} ne "") {
    $qstr .= "and subacct=? ";
    push(@values, $query{'subacct'});
  }

  if ($query{'operation'} ne "") {
    $query{'operation'} =~ tr/A-Z/a-z/;
    $query{'operation'} =~ s/[^a-z\,]//g;
  }
  if ($query{'operation'} =~ /^(auth|postauth|forceauth|return|void|chargeback|storedata)$/) {
    $qstr .= "and operation=? ";
    push(@values, $query{'operation'});
  }
  elsif ($query{'operation'} =~ /^(batchquery)$/) {
    $qstr .= "and operation in ('postauth','return') ";
  }
  elsif ($query{'operation'} =~ /[a-z]+\,[a-z]+/) {
    my $qmarks = '';
    my @qOps = split(/\,/,$query{'operation'});
    foreach my $op (@qOps) {
      if ($op !~ /^(auth|postauth|forceauth|return|void|chargeback|storedata)$/) {
        next;
      }
      $qmarks .= '?,';
      push(@values, $op);
    }
    chop $qmarks;
    $qstr .= "and operation IN ($qmarks)  ";
  }
  else {
    $qstr .= "and operation in ('auth','postauth','forceauth','return','void','storedata') ";
  }

  if (($query{'batchid'} =~ /^(20)/) && ($query{'operation'} =~ /^(batchquery)$/)) {
    $query{'batchid'} =~ s/[^0-9]//g;
    $qstr .= "and result=? ";
    push(@values, $query{'batchid'});
  }

  if ($query{'auth-code'} ne "") {
    $query{'auth-code'} =~ tr/a-z/A-Z/;
    $query{'auth-code'} =~ s/[^0-9A-Z]//g;
    $query{'auth-code'} = substr($query{'auth-code'},0,6);
    $qstr .= "and UPPER(auth_code) LIKE ? ";
    push(@values, "$query{'auth-code'}%");
  }

  if ($query{'result'} =~ /^(success|pending|problem|badcard)$/) {
    $qstr .= "and finalstatus=? ";
    push(@values, $query{'result'});
  }

  if ($query{'accttype'} =~ /^(checking|savings|seqr)$/) {
    $qstr .= "and accttype=? ";
    push(@values, $query{'accttype'});
  }

  if ($query{'qacct_code'} ne "") {
    my $acctcode = "";
    my @qacct_code = split(/\,/,$query{'qacct_code'});
    foreach my $var (@qacct_code) {
      $acctcode .= "?,";
      push(@values, $var);
    }
    chop $acctcode;
    $qstr .= "and acct_code IN ($acctcode) ";
  }
  elsif ($query{'acct_code'} ne "") {
    $qstr .= "and acct_code=? ";
    push(@values, $query{'acct_code'});
  }

  if ($query{'qacct_code2'} ne "") {
    my $acctcode = "";
    my @qacct_code = split(/\,/,$query{'qacct_code2'});
    foreach my $var (@qacct_code) {
      $acctcode .= "?,";
      push(@values, $var);
    }
    chop $acctcode;
    $qstr .= "and acct_code2 IN ($acctcode) ";
  }
  elsif ($query{'acct_code2'} ne "") {
    $qstr .= "and acct_code2=? ";
    push(@values, $query{'acct_code2'});
  }

  if ($query{'qacct_code3'} ne "") {
    my $acctcode = "";
    my @qacct_code = split(/\,/,$query{'qacct_code3'});
    foreach my $var (@qacct_code) {
      $acctcode .= "?,";
      push(@values, $var);
    }
    chop $acctcode;
    $qstr .= "and acct_code3 IN ($acctcode) ";
  }
  elsif ($query{'acct_code3'} ne "") {
    $qstr .= "and acct_code3=? ";
    push(@values, $query{'acct_code3'});
  }

  if($starttime ne "") {
    $qstr .= "and trans_time>=? ";
    push(@values, $starttime);
  }
  if($endtime ne "") {
    $qstr .= "and trans_time<? ";
    push(@values, $endtime);
  }

  $qstr .= "and (duplicate IS NULL or duplicate='')";

  if (($query{'qresp'} eq "simple") || ($query{'orderID'} ne "")) {
    $qstr .= " ORDER BY orderid, trans_time ";
  }

  my $query_start_time = time();
  my @queryorder = ();
  my %amountHash = ();
  my $i = 0;
  my $dbh = &miscutils::dbhconnect("pnpdata","","$query{'publisher-name'}"); ## Trans_Log

  # column binding vars
  my ($trans_date,$trans_time,$operation,$finalstatus,$amount,$descr,$result,$shacardnumber,$token,
      $card_name,$card_addr,$card_city,$card_state,$card_zip,$card_country,$card_number,$card_exp,$refnumber,
      $acct_code,$acct_code2,$acct_code3,$acct_code4,$auth_code,$avs,$currency,$orderid,$accttype,$cvvresp,
      $respcode,$batch_time,$processor);

  my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
  $sth->execute(@values) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
  $sth->bind_columns(undef,\($trans_date,$trans_time,$operation,$finalstatus,$amount,$descr,$result,$orderid,
      $card_name,$card_addr,$card_city,$card_state,$card_zip,$card_country,$card_number,$card_exp,$cvvresp,
      $acct_code,$acct_code2,$acct_code3,$acct_code4,$accttype,$auth_code,$avs,$enccardnumber,$length,$refnumber,$batch_time,$processor));
  while ($sth->fetch) {
    push (@queryorder, $orderid);
    $amountHash{$orderid} = $amount;

    my $idx = sprintf("%05d",$i);
    if ($query{'card-name'} ne "") {
      my $testname = $card_name;
      $testname =~ s/^[\s]+|[\s]+$//g;
      if ($query{'card-name'} !~ /$testname/i) {
        next;
      }
    }

    # assume current set processor if processor was not set in trans_log
    if (!defined $processor || $processor eq '') {
      if (lc($accttype) =~ /savings|checking/) {
        $processor = $remote::gatewayAccount->getCheckProcessor();
      } else {
        $processor = $remote::gatewayAccount->getCardProcessor();
      }
    }

    if ($query{'qresp'} eq "simple") {
      if ($operation =~ /^(auth|reauth|forceauth|postauth|return)$/) {
        $result{$orderid} = "operation=$operation\&FinalStatus=$finalstatus\&orderID=$orderid\&trans_date=$trans_date\&trans_time=$trans_time";
        $i++;
      }
      elsif ($operation =~ /^(void)$/) {
        $result{$orderid} =~ s/FinalStatus=\w*\&/FinalStatus=voided\&/;
      }
    }
    else {
      if ($amount =~ / /) {
        ($currency,$amount) = split(/ /,$amount);
        $amount =~ s/[^0-9\.]//g;
      }
      $amt2hash{$operation} += $amount;
      if ($operation eq "return") {
        $amthash{"$result"} -= $amount;
        $amt1hash{"$trans_date"} -= $amount;
      }
      elsif ($operation eq "postauth") {
        $amthash{"$result"} += $amount;
        $amt1hash{"$trans_date"} += $amount;
      }

      if ($finalstatus ne "success") {
        $descr =~ /\w*?:?(\w*):[\w\.\ \-\,]*$/;
        $respcode = $1;
      }

      my $fullAuthCode = $auth_code;
      $auth_code = substr($auth_code,0,6);
      $result{"a$idx"} = "trans_date=$trans_date\&trans_time=$trans_time\&operation=$operation\&FinalStatus=$finalstatus\&card-amount=$amount\&amountcharged=$amount\&";
      $result{"a$idx"} .= "card-name=$card_name\&card-address1=$card_addr\&card-city=$card_city\&card-state=$card_state\&";
      $result{"a$idx"} .= "card-zip=$card_zip\&card-country=$card_country\&card-exp=$card_exp\&cvvresp=$cvvresp\&";
      $result{"a$idx"} .= "result=$result\&MErrMsg=$descr\&acct_code=$acct_code\&acct_code2=$acct_code2\&acct_code3=$acct_code3\&";
      $result{"a$idx"} .= "acct_code4=$acct_code4\&accttype=$accttype\&auth-code=$auth_code\&avs-code=$avs\&currency=$currency\&";
      $result{"a$idx"} .= "orderID=$orderid\&resp-code=$respcode\&refnumber=$refnumber\&batch_time=$batch_time";

      if ( ( $processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $remote::accountFeatures->get('multicurrency') == 1 ) ) {
        my $cardProcessorAccount = new PlugNPay::Processor::Account( { gatewayAccount => $query{'publisher-name'}, processorName => $processor } );
        my $nativeCurrency   = $cardProcessorAccount->getSettingValue('currency');

        my $nativePrice = smpsutils::calculateNativeAmountFromAuthCodeColumnData({
          processor => $processor,
          authCodeColumnData => $fullAuthCode,
          nativeCurrency => $currency,
          convertedAmount => $amount
        });

        if ($nativePrice == 0) {
          # no conversion, display amount as loaded from the database
          $result{"a$idx"} .= "\&converted-amount=$amount\&converted-currency=$currency";
        } else {
          $result{"a$idx"} .= "\&converted-amount=$nativePrice\&converted-currency=$nativeCurrency";
        }
      }

      
      my $receiptcc = ('X' x (length($card_number)-4)) . substr($card_number,-4,4); # Format: X's, last4
      $result{"a$idx"} .= "\&receiptcc=$receiptcc";

      if ($query{'decryptflag'} == 1) {
        $enccardnumber = &smpsutils::getcardnumber($query{'publisher-name'},$orderid,$processor,$enccardnumber);
        my $cardnumber = &rsautils::rsa_decrypt_file($enccardnumber,$length,"print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");
        $result{"a$idx"} .= "\&card-number=$cardnumber";
      } else {
        $result{"a$idx"} .= "\&card-number=$card_number";
      }

      if (($query{'ordersummary'} == 1) && ($operation =~ /^(auth|reauth|postauth)$/)) {
        # add order summary data, as necessary

        my @db_cols = ('tax','shipping','morderid','shipname','shipcompany','shipaddr1','shipaddr2','shipcity','shipstate','shipzip','shipcountry','shipphone','phone','fax','email','plan','billcycle','easycart','ipaddress','useragent','referrer','successlink','shipinfo','publisheremail');

        my $qstr .= "select ";
        for (my $z = 0; $z <= $#db_cols; $z++) {
          $qstr .= "$db_cols[$z],";
        }
        chop $qstr;
        $qstr .= " from ordersummary";
        $qstr .= " where orderid=? and username=?";
        $qstr .= " LIMIT 1";

        my $sth_summary = $dbh->prepare(qq{$qstr}) or die "Can\'t prepare: $DBI::errstr";
        $sth_summary->execute("$orderid", "$query{'publisher-name'}") or die "Can\'t execute: $DBI::errstr";
        my @db_data = $sth_summary->fetchrow_array();
        for (my $z = 0; $z <= $#db_cols; $z++) {
          $result{"a$idx"} .= sprintf("\&%s\=%s", $db_cols[$z], $db_data[$z]);
        }
        $sth_summary->finish;
      }

      if (($query{'orderdetails'} == 1) && ($operation =~ /^(auth|reauth|postauth)$/)) {
        # add order product details, as necessary
        my ($item, $quantity, $cost, $description, $customa, $customb, $customc, $customd, $custome);

        my $sth_details = $dbh->prepare(qq{
            select item, quantity, cost, description, customa, customb, customc, customd, custome
            from orderdetails
            where orderid=? and username=?
            order by item
          }) or die "Can\'t prepare: $DBI::errstr";
        $sth_details->execute("$orderid", "$query{'publisher-name'}") or die "Can\'t execute: $DBI::errstr";
        $sth_details->bind_columns(undef,\($item, $quantity, $cost, $description, $customa, $customb, $customc, $customd, $custome));

        my $z = 1;
        while ($sth_details->fetch) {
          if ($item ne "") {
            $result{"a$idx"} .= "\&item$z=$item\&quantity$z=$quantity\&cost$z=$cost\&description$z= $description";
            $result{"a$idx"} .= "\&customa$z=$customa\&customb$z=$customb\&customc$z=$customc\&customd$z=$customd\&custome$z=$custome";
            $z++;
          }
        }
        $sth_details->finish;
      }

      $i++;
    }
  }
  $sth->finish;
  $dbh->disconnect;

  my $adjustmentHashRef = "";
  if (($adjustmentFlag == 1) && (@queryorder)) {
    my $adjustmentLog = new PlugNPay::Transaction::Logging::Adjustment();
    $adjustmentLog->setGatewayAccount($query{'merchant'});
    $adjustmentHashRef = $adjustmentLog->loadMultiple(\@queryorder);

    my $i=0;
    my ($idx);
    foreach my $orderid (@queryorder) {
      my $baseAmount = 0;
      my $adjustment = 0;
      $idx = sprintf("%05d",$i);
      my $hashKey = "a$idx";

      my ($currency,$amt) = split(/ /,$amountHash{$orderid});
      if ($adjustmentHashRef->{$orderid}) {
        $adjustment = $adjustmentHashRef->{$orderid}->getAdjustmentTotalAmount();
        $baseAmount = $adjustmentHashRef->{$orderid}->getBaseAmount();
        if ($result{$hashKey} =~ /\&operation=return\&/) {
          my $baseAmount = $adjustmentHashRef->{$orderid}->getBaseAmount();
          my $totalAmount = $baseAmount+$adjustment;
          my $proRatedAdjustment = sprintf("%0.2f",($amt/$totalAmount * $adjustment)+.00001);
          $adjustment = $proRatedAdjustment;
        }
      }
      else {
        $baseAmount = $amt;
        $adjustment = 0;
      }
      $result{$hashKey} .= "\&adjustment=$adjustment\&baseAmount=$baseAmount";
      $i++;
    }
  }

  my $query_elpase_time = time() - $query_start_time;

  if (($i > 0) && ($query{'qresp'} eq "simple")) {
    my $k=0;
    my (%temphash);
    foreach my $key (sort keys %result) {
      my $idx = sprintf("%05d",$k);
      $temphash{"a$idx"} = $result{$key};
      $k++;
    }
    $i = $k;
    %result = %temphash;
  }

  if ($i > 0) {
    if ($query{'operation'} =~ /^(batchquery)$/) {
      foreach my $key (keys %amthash) {
        $result{"batchtotal_$key"} = $amthash{$key};
      }
      foreach my $key (keys %amt1hash) {
        $result{"datetotal_$key"} = $amt1hash{$key};
      }
    }
    foreach my $key (keys %amt2hash) {
      $result{"opertotal_$key"} = $amt2hash{$key};
    }
    $result{'FinalStatus'} = "success";
    $result{'num-txns'} = $i;
  }
  else {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "No Records Found";
  }

  return %result;
}


sub batch_assemble {
  my ($starttime,$endtime,%result);
  my $startdate = $remote::query{'startdate'};
  my $enddate = $remote::query{'enddate'};
  my $username = $remote::query{'publisher-name'};
  my $accttype = $remote::query{'accttype'};
  my $cardtype = $remote::query{'cardtype'};
  my $txntype = $remote::query{'txntype'};

  if ($startdate ne "") {
    $starttime = sprintf("%08d000000", $startdate);
    if ($starttime < '19990101000000') {
      $starttime = "";
      $startdate = "";
    }
  }
  if ($enddate ne "") {
    $endtime = sprintf("%08d000000", $enddate);
  }

  #print "UN:$username, AT:$accttype, CT:$cardtype, ST:$starttime, ET:$endtime, TT:$txntype\n";
  #exit;

  my %res1 = &miscutils::sendmserver("$username",'batch-prep',
            'accttype',"$accttype",
            'card-type', "$cardtype",
            'start-time', "$starttime",
            'end-time', "$endtime",
            'txn-type', "$txntype");

  my @values = values %res1;

  my (%data,%cardtotal);
  my $i = 0;
  foreach my $var (sort @values) {
    #print "VAR:$var:<br>\n";
    my %res2 = ();
    my @nameval = split(/&/,$var);
    foreach my $temp (@nameval) {
      my ($name,$value) = split(/=/,$temp);
      $res2{$name} = $value;
    }

    if ($res2{'time'} ne "") {
      my $idx = sprintf("%05d",$i);
      my %var = ('order-id','orderID','amount','card-amount','auth-code','auth-code','card-type','card-type','acct_code','acct_code','acct_code2','acct_code2','acct_code3','acct_code3','avs','avs-code');

      $res2{'trans_date'} = substr($res2{'time'},0,8);
      $res2{'currency'} = substr($res2{'amount'},0,3);
      $res2{'auth-code'} = substr($res2{'auth-code'},0,6);
      $res2{'amount'} = substr($res2{'amount'},4);
      my ($str);
      foreach my $key (sort keys %var) {
        $str .= "$var{$key}=$res2{$key}\&";
      }

      $result{"a$idx"} = $str;

      $i++;
      $cardtotal{$res2{'card-type'}} += $res2{'amount'};
    }
  }
  if ($i > 0) {
    $result{'FinalStatus'} = "success";
    foreach my $key (keys %cardtotal) {
      $result{"total-$key"} = $cardtotal{$key};
    }
  }
  else {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "No Records Found";
  }

  return %result;
}

sub query_chargeback {
  my (%query) = %remote::query;
  my (%result,%returns,$startdate,$enddate,$trans_date,$operation,$finalstatus,$amount,$descr,$result,
      $card_name,$card_addr,$card_city,$card_state,$card_zip,$card_country,$card_number,$card_exp,
      $acct_code,$acct_code2,$acct_code3,$acct_code4,$auth_code,$avs,$currency,$orderid);

  my $timeadjust = (90 * 24 * 3600);
  my ($dummy,$datestr,$timestr) = &miscutils::gendatetime("-$timeadjust");

  if (exists $query{'startdate'}) {
    $query{'startdate'} =~ s/[^0-9]//g;
  }
  if (exists $query{'enddate'}) {
    $query{'enddate'} =~ s/[^0-9]//g;
  }

  if ($query{'startdate'} < $datestr) {
    my $timeadjust = (2 * 24 * 3600);
    my ($dummy,$datestr,$timestr) = &miscutils::gendatetime("-$timeadjust");
    $startdate = $datestr;
  }
  else {
    $startdate = $query{'startdate'};
  }

  if ($query{'enddate'} eq "") {
    my $timeadjust = (1 * 24 * 3600);
    my ($dummy,$datestr,$timestr) = &miscutils::gendatetime("$timeadjust");
    $enddate = $datestr;
  }
  else {
    $enddate = $query{'enddate'};
  }

  if ($enddate < $startdate) {
    $enddate = $startdate + 1;
  }

  #print "ST:$startdate, END:$enddate, OID:$query{'orderID'}, PN:$query{'publisher-name'}\n";
  my @placeholder = ();
  my $qstr = "select entered_date,orderid ";
  $qstr .= "from chargeback ";
  $qstr .= "where entered_date>=? ";
  $qstr .= "and entered_date<? ";
  push(@placeholder, "$startdate", "$enddate");

  if ((exists $remote::altaccts{$query{'publisher-name'}}) && ($query{'subacct'} ne "")) {
    $qstr .= "and (";
    my ($temp);
    foreach my $var ( @{ $remote::altaccts{$query{'publisher-name'}} } ) {
      $temp .= "username=? or ";
      push(@placeholder, "$var");
    }
    $temp = substr($temp,0,length($temp)-4);
    $qstr .= "$temp) ";
  }
  else {
    $qstr .= "and username=? ";
    push(@placeholder, "$query{'publisher-name'}");
  }

  if ($query{'subacct'} ne "") {
    $qstr .= "and subacct=?";
    push(@placeholder, "$query{'subacct'}");
  }

  #print "QSTR:$qstr\n";

  my @temp_placeholder = ();
  my (%date,$temp);

  my $dbh = &miscutils::dbhconnect('fraudtrack');
  my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
  $sth->execute(@placeholder) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
  $sth->bind_columns(undef,\($trans_date,$orderid));
  while ($sth->fetch) {
    #print "OID:$orderid:<br>\n";
    $date{$orderid} = $trans_date;
    #$temp .= "'$orderid',";
    $temp .= "orderid=? or ";
    push(@temp_placeholder, "$orderid");
  }
  $sth->finish;
  $dbh->disconnect;

  chop $temp;
  chop $temp;
  chop $temp;
  chop $temp;

  if ($temp eq "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "No Records Found";
    $result{'aux-msg'} = $result{'MErrMsg'};
    $result{'resp-code'} = "PXX";
    return %result;
  }

  $timeadjust = (120 * 24 * 3600);
  ($dummy,$datestr,$timestr) = &miscutils::gendatetime("-$timeadjust");
  $startdate = $datestr;

  $timeadjust = (1 * 24 * 3600);
  ($dummy,$datestr,$timestr) = &miscutils::gendatetime("$timeadjust");
  $enddate = $datestr;

  my @placeholder2 = ();
  $qstr = "select trans_date,amount,orderid,";
  $qstr .= "card_name,card_addr,card_city,card_state,card_zip,card_country,card_number,card_exp,";
  $qstr .= "acct_code,acct_code2,acct_code3,acct_code4,operation ";

  $qstr .= "from trans_log ";
  $qstr .= "where ($temp) ";
  push(@placeholder2, @temp_placeholder);
  $qstr .= "and trans_date>=? ";
  $qstr .= "and trans_date<? ";
  push(@placeholder2, "$startdate", "$enddate");

  if (exists $remote::altaccts{$query{'publisher-name'}}) {
    my ($temp);
    foreach my $var ( @{ $remote::altaccts{$query{'publisher-name'}} } ) {
      $temp .= "?,";
      push(@placeholder2, "$var");
    }
    chop $temp;
    $qstr .= "and username IN ($temp) ";
  }
  else {
    $qstr .= "and username=? ";
    push(@placeholder2, "$query{'publisher-name'}");
  }

  if ($query{'subacct'} ne "") {
    $qstr .= "and subacct='$query{'subacct'}' ";
    push(@placeholder2, "$query{'subacct'}");
  }

  $qstr .= "and operation in ('auth','return') and finalstatus='success' ";
  $qstr .= "and (duplicate IS NULL or duplicate='') ";
  $qstr .= "ORDER BY operation DESC ";

  my $i = 0;

  $dbh = &miscutils::dbhconnect("pnpdata","","$query{'publisher-name'}"); ## Trans_Log
  $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
  $sth->execute(@placeholder2) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
  $sth->bind_columns(undef,\($trans_date,$amount,$orderid,
      $card_name,$card_addr,$card_city,$card_state,$card_zip,$card_country,$card_number,$card_exp,
      $acct_code,$acct_code2,$acct_code3,$acct_code4,$operation));
  while ($sth->fetch) {
    if ($operation eq "return") {
      $returns{$orderid} = 1;
      next;
    }
    if ((exists $returns{$orderid}) && ($ENV{'HTTP_USER_AGENT'} eq "NATS")) {
      next;
    }
    my $idx = sprintf("%05d",$i);
    if ($amount =~ / /) {
      ($currency,$amount) = split(/ /,$amount);
      $amount =~ s/[^0-9\.]//g;
    }
    $result{"a$idx"} = "trans_date=$trans_date\&card-amount=$amount\&chbck_date=$date{$orderid}\&";
    $result{"a$idx"} .= "card-name=$card_name\&card-address1=$card_addr\&card-city=$card_city\&card-state=$card_state\&";
    $result{"a$idx"} .= "card-zip=$card_zip\&card-country=$card_country\&card-number=$card_number\&card-exp=$card_exp\&";
    $result{"a$idx"} .= "acct_code=$acct_code\&acct_code2=$acct_code2\&acct_code3=$acct_code3\&";
    $result{"a$idx"} .= "acct_code4=$acct_code4\&currency=$currency\&orderID=$orderid";
    $i++;
  }
  $sth->finish;
  $dbh->disconnect;

  $result{'TranCount'} = sprintf("%01d", $i);

  if ($i > 0) {
    $result{'FinalStatus'} = "success";
    $result{'resp-code'} = "P00";
  }
  else {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "No Records Found";
    $result{'aux-msg'} = $result{'MErrMsg'};
    $result{'resp-code'} = "PXX";
  }

  return %result;
}

sub test_mode {
  my ($newtestmode,$testmode,%result);
  my $username = $remote::query{'publisher-name'};

  my $subacct = $remote::query{'subacct'};

  my $dbh = &miscutils::dbhconnect('pnpmisc');

  my $sth= $dbh->prepare(qq{
      select testmode
      from customers
      where username=?
    }) or die "Can't prepare: $DBI::errstr";
  $sth->execute($username) or die "Can't execute: $DBI::errstr";
  ($testmode) = $sth->fetchrow;
  $sth->finish;

  if ($testmode eq "yes") {
    $newtestmode = "no";
  }
  elsif (($testmode eq "no") || ($testmode eq "")) {
    $newtestmode = "yes";
  }

  $sth = $dbh->prepare(qq{
      update customers
      set testmode=?
      where username=?
    }) or die "Can't prepare: $DBI::errstr";
  $sth->execute($newtestmode,$username) or die "Can't execute: $DBI::errstr";
  $sth->finish;

  $dbh->disconnect;

  if ($newtestmode =~ /yes|no/) {
    $result{'FinalStatus'} = "success";
    $result{'testmode'} = $newtestmode;
  }
  else {
    $result{'FinalStatus'} = "problem";
  }

  return %result;
}

sub shopdata {
  my $j = 1;
  my ($subtotal,$taxsubtotal,$totalcnt,$totalwgt);
  my (@item,@description,@quantity,@cost,@weight,@ext,@taxable);

  for (my $i=1; $i<=2000; $i++) {
    if ($remote::query{"quantity$i"} > 0) {
      $item[$j] = $remote::query{"item$i"};
      $description[$j] = $remote::query{"description$i"};
      $quantity[$j] = $remote::query{"quantity$i"};
      $quantity[$j] =~ s/[^0-9\.]//g;
      $cost[$j] = $remote::query{"cost$i"};
      $cost[$j] =~ s/[^0-9\.\-]//g;
      $weight[$j] = $remote::query{"weight$i"};
      $remote::max = $j;
      $ext[$j] = ($cost[$j] * $quantity[$j]);
      $remote::query{'subtotal'} = ($quantity[$j] * $cost[$j]) + $subtotal;

      # put taxable field into array for later use
      $taxable[$j] = $remote::query{"taxable$i"};

      if ($remote::query{"taxable$i"} !~ /N/i) {
        $taxsubtotal = ($quantity[$j] * $cost[$j]) + $taxsubtotal;
      }

      $totalcnt = $quantity[$j] + $totalcnt;
      $totalwgt = ($quantity[$j] * $weight[$j]) + $totalwgt;
      $remote::query{'test_wgt'} = $totalwgt;
      $j++;
    }
    delete $remote::query{"item$i"};
    delete $remote::query{"quantity$i"};
    delete $remote::query{"cost$i"};
    delete $remote::query{"description$i"};
    delete $remote::query{"weight$i"};
  }

  $remote::query{'ordrcnt'} = $j;
  for (my $i=1; $i<=$j; $i++) {
    $remote::query{"item$i"} = $item[$i];
    $remote::query{"quantity$i"} = $quantity[$i];
    $remote::query{"cost$i"} = $cost[$i];
    $remote::query{"description$i"} = $description[$i];
    $remote::query{"weight$i"} = $weight[$i];
  }

  #&CertiTax();
}

sub record_time {
  #return;
  my ($times) = @_;
  my (%times) = (%$times,%mckutils::times);

  open (TIMES,">>/home/p/pay1/database/debug/tran_times_remote.txt");

  my ($oldtime);
  print TIMES "1:$remote::query{'publisher-name'}, OID:$mckutils::orderID\n";

  my ($a);
  foreach my $key (sort keys %times) {
    if ($oldtime eq "") {
      $oldtime = $times{$key};
    }
    $a = $times{$key};
    my $delta = $a - $oldtime;
    print TIMES "$key:$delta\n";
  }

  my $tottime = $a - $oldtime;
  print TIMES "TOTTIME:$tottime\n";
  print TIMES "\n\n";
  close (TIMES);
}

sub checkid {
  my $username = $remote::query{'publisher-name'};

  my (%result);
  my $dbh = &miscutils::dbhconnect('pnpmisc');
  my $sth = $dbh->prepare(qq{
      select name,company,processor,chkprocessor
      from customers
      where username=?
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute("$username") or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  my ($merchant_name,$merchant_company,$processor,$chkprocessor) = $sth->fetchrow;
  $sth->finish;
  $dbh->disconnect;

  if ($merchant_name ne "") {
    $result{'FinalStatus'} = "success";
    $result{'merchant_name'} = $merchant_name;
    $result{'merchant_company'} = $merchant_company;
    $result{'merchant_processor'} = $processor;
    $result{'merchant_chkprocessor'} = $chkprocessor;
  }
  else {
    $result{'FinalStatus'} = "problem";
  }

  return %result;
}

sub info_retrieval {
  my $username = $remote::query{'publisher-name'};
  my (%result);

  my $dbh = &miscutils::dbhconnect('pnpmisc');
  my $sth = $dbh->prepare(qq{
      select name,company,addr1,city,state,zip,email,url,tel
      from customers
      where username=?
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute($username) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  my ($merchant_name,$merchant_company,$merchant_addr1,$merchant_city,$merchant_state,$merchant_zip,$merchant_email,$merchant_url,$merchant_tel) = $sth->fetchrow;
  $sth->finish;
  $dbh->disconnect;

  $result{'FinalStatus'} = "success";
  $result{'merchant_name'} = $merchant_name;
  $result{'merchant_company'} = $merchant_company;
  $result{'merchant_addr1'} = $merchant_addr1;
  $result{'merchant_city'} = $merchant_city;
  $result{'merchant_state'} = $merchant_state;
  $result{'merchant_zip'} = $merchant_zip;
  $result{'merchant_email'} = $merchant_email;
  $result{'merchant_tel'} = $merchant_tel;

  return %result;
}

sub decrypt_card {
  my(%result);

  if ($remote::query{'magensacc'} ne "") {
    require magensa;
    my %result1 = &magensa::decrypt("$remote::query{'magensacc'}",\%remote::query);
    if ($result1{'StatusCode'} == 1000 ) {
      $result1{'PAN'} =~ s/[^0-9]//g;
      $result{'pan'} = $result1{'PAN'};
      $result{'FinalStatus'} = "success";
    }
    else {
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = "Decryption problem";
      $result{'StatusCode'} = $result1{'StatusCode'};
    }
  }
  else {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Missing magensa data.";
  }

  return %result;
}

sub dccoptout {
  my (%result,$optflagloc);

  my $dbh_misc = &miscutils::dbhconnect("pnpmisc");
  my $sth = $dbh_misc->prepare(qq{
      select processor
      from customers
      where username=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$remote::query{'publisher-name'}") or die "Can't execute: $DBI::errstr";
  my ($processor) = $sth->fetchrow;
  $sth->finish;
  $dbh_misc->disconnect;

  if ($processor eq "fifththird") {
    $optflagloc = 185;
  }
  else {
    $optflagloc = 115;
  }

  $remote::query{'dccoptout'} = substr($remote::query{'dccoptout'},0,1);
  $remote::query{'dccoptout'} =~ tr/a-z/A-Z/;

  if ($remote::query{'dccoptout'} !~ /(Y|N)/) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Invalid value for dccoptout.";
    $result{'resp-code'} = "0000";
    return %result;
  }

  if ($remote::query{'publisher-name'} =~ /^(planettest|pnpdemo)$/ ) {
    $result{'FinalStatus'} = "success";
    $result{'resp-code'} = "0000";
    return %result;
  }

  my $dbh = &miscutils::dbhconnect("pnpdata","","$remote::query{'publisher-name'}");

  my $sth2 = $dbh->prepare(qq{
      select postauthstatus,auth_code
      from operation_log
      where orderid=?
      and username=?
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%remote::query);
  $sth2->execute("$remote::query{'orderID'}","$remote::query{'publisher-name'}") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%remote::query);
  my ($postauthstatus,$auth_code) = $sth2->fetchrow;
  $sth2->finish;

  $result{'authcodeorg'} = $auth_code;
  if ($postauthstatus ne "success") {
    if (length($auth_code) < $optflagloc) {
      $dbh->disconnect;
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = "Invalid length for auth code.";
      $result{'resp-code'} = "0000";
      $dbh->disconnect;
      return %result;
    }
    if ((substr($auth_code,$optflagloc,1) ne $remote::query{'dccoptout'})) {

      substr($auth_code,$optflagloc,1) = "$remote::query{'dccoptout'}";

      $result{'authcodenew'} = $auth_code;

      my $sth = $dbh->prepare(qq{
          update operation_log
          set auth_code=?
          where orderid=?
          and username=?
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%remote::query);
      $sth->execute("$auth_code","$remote::query{'orderID'}","$remote::query{'publisher-name'}") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%remote::query);
      $sth->finish;

      $sth = $dbh->prepare(qq{
          update trans_log
          set auth_code=?
          where orderid=?
          and username=?
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%remote::query);
      $sth->execute("$auth_code","$remote::query{'orderID'}","$remote::query{'publisher-name'}") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%remote::query);
      $sth->finish;
      $result{'FinalStatus'} = "success";
      $result{'resp-code'} = "0000";
    }
    else {
      $result{'FinalStatus'} = "success";
      $result{'resp-code'} = "0000";
    }
  }
  else {
    ## Error Transaction already settled.
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Transaction already settled.  DCC may not be modified.";
    $result{'resp-code'} = "0000";
  }

  $dbh->disconnect;
  return %result;
}

sub query_noc {
  # Required fields publisher-name
  my (%query) = %remote::query;
  my (%result,$startdate,$enddate,$trans_date,$descr,$result,$card_name,$orderid,$username,$error_code);
  my ($dummy,$datestr,$timestr);

  if ($query{'orderID'} ne "") {
    $datestr = "20050101";
  }
  else {
    my $timeadjust = (90 * 24 * 3600);
    ($dummy,$datestr,$timestr) = &miscutils::gendatetime("-$timeadjust");
  }

  if (exists $query{'startdate'}) {
    $query{'startdate'} =~ s/[^0-9]//g;
  }
  if (exists $query{'enddate'}) {
    $query{'enddate'} =~ s/[^0-9]//g;
  }

  if ($query{'startdate'} < $datestr) {
    my $timeadjust = (2 * 24 * 3600);
    my ($dummy,$datestr,$timestr) = &miscutils::gendatetime("-$timeadjust");
    $startdate = $datestr;
  }
  else {
    $startdate = $query{'startdate'};
  }

  if ($query{'enddate'} eq "") {
    my $timeadjust = (1 * 24 * 3600);
    my ($dummy,$datestr,$timestr) = &miscutils::gendatetime("$timeadjust");
    $enddate = $datestr;
  }
  else {
    $enddate = $query{'enddate'};
  }

  if ($enddate < $startdate) {
    $enddate = $startdate + 1;
  }

  #print "ST:$startdate, END:$enddate, OID:$query{'orderID'}, PN:$query{'publisher-name'}\n";

  my @placeholder = ();
  my $qstr = "select username,trans_date,orderid,name,descr,error ";
  $qstr .= "from achnoc ";
  $qstr .= "where trans_date>=? ";
  push(@placeholder, $startdate);
  $qstr .= "and trans_date<? ";
  push(@placeholder, $enddate);

  if (exists $remote::altaccts{$query{'publisher-name'}}) {
    my ($temp);
    foreach my $var ( @{ $remote::altaccts{$query{'publisher-name'}} } ) {
      $temp .= "?,";
      push(@placeholder, $var);
    }
    chop $temp;
    $qstr .= "and username IN ($temp) ";
  }
  else {
    $qstr .= "and username=? ";
    push(@placeholder, $query{'publisher-name'});
  }
  if ($query{'orderID'} ne "") {
    $qstr .= "and orderid=? ";
    push(@placeholder, $query{'orderID'});
  }

  my ($routingnum,$accountnum,$resp_code);
  my $i = 0;
  my $dbh = &miscutils::dbhconnect('pnpmisc'); ## achnoc table
  my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
  $sth->execute(@placeholder) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
  $sth->bind_columns(undef,\($username,$trans_date,$orderid,$card_name,$descr,$error_code));
  while ($sth->fetch) {
    my $idx = sprintf("%05d",$i);
    $routingnum = "";
    $accountnum = "";
    $resp_code = "";
    if ($error_code =~ /^(C\d+)\:/) {
      $resp_code = $1;
    }
    if ($descr =~ /Route Number: (\d{9})/) {
      $routingnum = $1;
    }
    if ($descr =~ /Account Number: (\d+)/) {
      $accountnum = $1;
    }

    $result{"a$idx"} = "publisher-name=$username\&trans_date=$trans_date\&orderID=$orderid\&card-name=$card_name\&MErrMsg=$descr";
    $result{"a$idx"} .= "\&resp-code=$resp_code\&routingnum=$routingnum\&accountnum=$accountnum&aux-msg=$error_code";
    $i++;
  }
  $sth->finish;
  $dbh->disconnect;

  if ($i > 0) {
    $result{'FinalStatus'} = "success";
    $result{'num-txns'} = $i;
  }
  else {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "No Records Found";
  }

  return %result;
}

sub ewallet_reg {
  require ewallet;

  my @array = %remote::query;
  my $payment = ewallet->new(@array);
  my %result = $payment->register_ewallet("auth");

  return %result;
}

sub query_ecard {
  print "query_ecard Sub - Should be dormant:4409\n";
  #require ecardproc;
  #my @array = %remote::query;
  #my $payment = ecardproc->new(@array);
  #my %result = $payment->query_ecard();
  #return %result;
}

sub query_iotrans {
  my (%query) = %remote::query;

  require iovation;
  my (%result,%req,%error,$res,$pairs,$message,$resp,$header);
  my ($subscriberid,$subscriberaccount,$subscriberpasscode) = split('\|',$remote::accountFeatures->get('iovation'));
  my %res = &iovation::check_transaction(\%query,$subscriberid,$subscriberaccount,$subscriberpasscode);

  return %res;
}

sub query_pos {
  my (%query) = %remote::query;
  my (%result);

  my $cardnumber = $query{'card-number'};
  $cardnumber =~ s/[^\d]//g;
  if (length($cardnumber) < 13) {
    ## Return Error
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Invalid Cardnumber.";
  }
  else {
    ## Query Op_log for age.
    my $cc = new PlugNPay::CreditCard($query{'card-number'});
    my @cardHashes = $cc->getCardHashArray();
    my $qmarks = '?' . ',?'x($#cardHashes);


    my $timeadjust = (185 * 24 * 3600);
    my ($dummy,$datestr,$timestr) = &miscutils::gendatetime("-$timeadjust");

    my $dbh = &miscutils::dbhconnect("pnpdata","",""); ## Op_Log
    my $qstr = "select trans_date from operation_log FORCE INDEX(oplog_tdatesha_idx)";
    $qstr .= "where trans_date>=? ";
    $qstr .= "and shacardnumber IN ($qmarks)  ";
    $qstr .= "order by trans_date";

    my $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
    $sth->execute($datestr,@cardHashes) or die "Can't execute: $DBI::errstr";
    my ($trans_date) = $sth->fetchrow;
    $sth->finish;

    if ($trans_date >= $datestr) {
      my $count = 0;
      my $qstr = "select count(trans_date) from operation_log FORCE INDEX(oplog_tdatesha_idx)";
      $qstr .= " where trans_date>=? ";
      $qstr .= " and shacardnumber IN ($qmarks)  ";
      my $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
      $sth->execute($trans_date,@cardHashes) or die "Can't execute: $DBI::errstr";
      ($count) = $sth->fetchrow;
      $sth->finish;
      $result{'cardcnt'} = $count;
    }
    $dbh->disconnect;

    if ($trans_date ne "") {
      ## Calc Age.
      $datestr = &miscutils::strtotime($trans_date);
      $result{'age'} = sprintf("%3d",(time() - $datestr)/(3600*24));
      $result{'FinalStatus'} = "success";

    }
    else {
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = "Cardnumber not found";
    }

    my $dbh_fraudtrack = &miscutils::dbhconnect("fraudtrack");
    my $sth2 = $dbh_fraudtrack->prepare(qq{
        select trans_time
        from negative
        where shacardnumber IN ($qmarks)
        and trans_time>?
      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
    $sth2->execute(@cardHashes, $timestr) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query);
    my ($test) = $sth2->fetchrow;
    $sth2->finish;
    $dbh_fraudtrack->disconnect;

    if ($test ne "") {
      $result{'negative'} = "1";
    }
    else {
      $result{'negative'} = "0";
    }
  }

  return %result;
}

sub add_negative {
  my (%query) = %remote::query;
  my (%result);
  my ($dummy,$today,$dummy2) = &miscutils::gendatetime();

  my $username = $query{'publisher-name'};
  my $cardnumber = $query{'card-number'};
  $cardnumber =~ s/[^0-9]//g;
  my $reason = $query{'reason'};
  $reason =~ s/[^0-9a-zA-Z\.\ ]//g;
  $reason = substr($reason,0,64);

  my $md5 = new MD5;
  $md5->add("$cardnumber");
  my $enccardnumber = $md5->hexdigest();

  $cardnumber = substr($cardnumber,0,4) . '**' . substr($cardnumber,length($cardnumber)-2,2);

  my $dbh = &miscutils::dbhconnect("pnpmisc");

  my $sth = $dbh->prepare(qq{
      select enccardnumber
      from fraud
      where enccardnumber=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$enccardnumber") or die "Can't execute: $DBI::errstr";
  my ($enccardnumber2) = $sth->fetchrow;
  $sth->finish;

  if ($enccardnumber ne $enccardnumber2) {
    $sth = $dbh->prepare(q{
        insert into fraud
        (enccardnumber,card_number,username,trans_date,descr)
        values (?,?,?,?,?)
      }) or die "Can't do: $DBI::errstr";
    $sth->execute("$enccardnumber","$cardnumber","$username","$today","$reason") or die "Can't execute: $DBI::errstr";
    $sth->finish;

    $result{'FinalStatus'} = "success";
    #print "<h3>Credit Card Number successfully added to fraud database</h3>\n";
  }
  else {
    $result{'MErrMsg'} = "Credit Card Number is already in fraud database.";
    $result{'FinalStatus'} = "problem";
  }

  $dbh->disconnect;
  return %result;
}

sub logfilter_out {
  my ($key, $val) = @_;

  if ($key =~ /([3-7]\d{12,18})/) {
    $key =~ s/([3-7]\d{13,19})/&logfilter_sub($1)/ge;
  }

  if ($key !~ /orderid|refnumber|CertiTaxID|password/i) {
    if ($val =~ /([3-7]\d{12,18})/) {
      $val =~ s/([3-7]\d{13,19})/&logfilter_sub($1)/ge;
    }
  }

  $key =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;
  $val =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;

  return "\&$key\=$val";
}

sub logfilter_in {
  my ($key, $val) = @_;

  if ($key =~ /^(orderid|refnumber|certitaxid)$/i){
    return ($key,$val);
  }

  if ($key =~ /([3-7]\d{13,19})/) {
    $key =~ s/([3-7]\d{13,19})/&logfilter_sub($1)/ge;
  }

  if ($val =~ /([3-7]\d{12,19})/) {
    $val =~ s/([3-7]\d{13,19})/&logfilter_sub($1)/ge;
  }

  $key =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;
  $val =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;

  return ($key,$val);
}

sub logfilter_sub {
  my ($stuff) = @_;

  my $luhntest = &miscutils::luhn10($stuff);
  if ($luhntest eq "success") {
    $stuff =~ s/./X/g;
  }

  return $stuff;
}

sub retrieve_report {
  my (%query) = %remote::query;
  my (%result);

  # ventnordat_DailyTrans_20100216100247.dat
  # /home/p/pay1/private/reports/data/2010
  my $path_reports = "/home/p/pay1/private/reports/data/";
  my $year = substr($query{'date'},0,4);

  # @files = </var/www/htdocs/*>;

  my @files = <$path_reports$year\/$query{'publisher-name'}\_$query{'reportname'}\_$query{'date'}*>;
  foreach my $file (@files) {
    #print "Content-Type: text/plain\n\n";
    print header( -type=>'text/plain');  ### DCP 20100716
    &sysutils::filelog("read","$file");
    open(REPORT,"$file");
    while(<REPORT>) {
      print $_;
    }
    close(REPORT);
    exit;
  }
  $result{'FinalStatus'} = "problem";
  $result{'MErrMsg'} = "No report Found.";
  return %result;
}

## Billing Presentment specific functions (billpay)

sub count_invoices {
  # counts number of invoices in billpay database, based on conditions specified
  require remote_billpay;
  my %result = &count_invoices();
  return %result;
}

sub count_clients {
  # counts number of client contacts in billpay database
  require remote_billpay;
  my %result = &count_clients();
  return %result;
}

sub list_clients {
  # gets list of client email contacts in billpay database
  require remote_billpay;
  my %result = &list_clients();
  return %result;
}

sub update_client {
  # add/update client contact info in billpay database
  require remote_billpay;
  my %result = &update_client();
  return %result;
}

sub query_client {
  # query client contacts in billpay database
  require remote_billpay;
  my %result = &query_client();
  return %result;
}

sub delete_client {
  # remove specific client's contact info from billpay database.
  require remote_billpay;
  my %result = &delete_client();
  return %result;
}

sub upload_invoice {
  # upload invoice batch file into billpay database
  require remote_billpay;
  my %result = &upload_invoice();
  return %result;
}

sub update_invoice {
  # add/update invoice in billpay database
  my %query = @_;
  require remote_billpay;
  my ($FinalStatus, $MErrMsg) = &update_invoice(%query);
  return ("$FinalStatus", "$MErrMsg");
}

sub query_invoice {
  # search for invoices in billpay database
  require remote_billpay;
  my %result = &query_invoice();
  return %result;
}

sub delete_invoice {
  # delete specific invoice from billpay database
  require remote_billpay;
  my %result = ();
  if ($remote::accountFeatures->get('billpay_remove_invoice') == 1) {
    %result = &delete_invoice();
  }
  else {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "$remote::query{'mode'} not permitted for this account.";
    $result{'resp-code'} = "PXX";
  }
  return %result;
}

sub bill_invoice {
  # search for invoices in billpay database
  require remote_billpay;
  my %result = &bill_invoice();
  return %result;
}

sub verifyPaRes {
  my (%query) = %remote::query;
  my %result = ();
  my $tdsprocessor = $remote::gatewayAccount->getTDSProcessor();
  eval {
    my $tdsStr = "";
    foreach my $key (keys %query) {
      $tdsStr .= "$key\=$query{$key}\&";
    }
    my %tdsresult = ();
    eval 'require ' . $tdsprocessor;
    my $evalStr = '%tdsresult = &' . $tdsprocessor . '::recvpares("' . $tdsStr . '")';
    eval $evalStr;

    $result{'cavv'} = $tdsresult{'cavv'};
    $result{'xid'} = $tdsresult{'xid'};

    $result{'eci'} = $tdsresult{'eci'};
    if ($tdsresult{'xid'} ne "") {
      $result{'FinalStatus'} = 'success';
    }
    else {
      $result{'FinalStatus'} = 'problem';
      $result{'MErrMsg'} = "Unable to verify paRes.";
    }
  };

  if ($@) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "TDS Processor not enabled or operation not supported.";
  }
  return %result;
}

sub alertEmail {
  my ($msg) = @_;
  my $emailer = new PlugNPay::Email();
  $emailer->setVersion('legacy');
  $emailer->setGatewayAccount($remote::query{'publisher-name'});
  $emailer->setFormat('text');
  $emailer->setTo("dprice\@plugnpay.com");
  $emailer->setCC("chris\@plugnpay.com");
  $emailer->setFrom("noc\@plugnpay.com");
  $emailer->setSubject("Remote API Error");
  $emailer->setContent($msg);
  $emailer->send();
}



1;
