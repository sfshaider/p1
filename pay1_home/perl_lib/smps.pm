package smps;

local $| = 0;    ### DCP 20100719

use strict;
use pnp_environment;
use miscutils;
use CGI qw/:standard/;
use SHA;
use smpsutils;
use constants qw(%countries %USstates %USterritories %CNprovinces %USCNprov %timezones);
use sysutils;
use PlugNPay::Environment;
use PlugNPay::Logging::MessageLog;
use PlugNPay::Transaction::Logging::Adjustment;
use PlugNPay::COA;
use PlugNPay::CreditCard;
use PlugNPay::ConvenienceFee;
use PlugNPay::Features;
use PlugNPay::GatewayAccount;
use PlugNPay::GatewayAccount::Private;
use PlugNPay::GatewayAccount::LinkedAccounts;
use PlugNPay::Transaction::Adjustment::Settings;
use PlugNPay::Security::CSRFToken;
use PlugNPay::Processor;
use PlugNPay::Processor::Account;
use PlugNPay::Logging::DataLog;
use PlugNPay::Email;
use PlugNPay::Transaction::TransactionProcessor;
use PlugNPay::Transaction::Loader;
use PlugNPay::GatewayAccount::LinkedAccounts::File;
use PlugNPay::Currency;
use PlugNPay::Util::Array qw(inArray);
use PlugNPay::Legacy::Transflags;
use PlugNPay::Authentication::Login;
use PlugNPay::Debug;

sub new {
  my $type = shift;

  $smps::query = new CGI;

  $smps::timetest{'0_newstart'} = time();

  $smps::mcprocessors = "wirecard";

  $smps::earliest_date = "20140101";
  if ( ( -e "/home/pay1/outagefiles/mediumvolume.txt" ) || ( -e "/home/pay1/outagefiles/highvolume.txt" ) ) {
    my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 2 ) );
    $smps::earliest_date = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
  }

  $smps::username     = "";
  $smps::function     = "";
  $smps::format       = "";
  $smps::merchant     = "";
  $smps::debug_string = "";
  $smps::trancount    = "";

  $smps::autobatch       = "";
  $smps::merchantid      = "";
  $smps::processor       = "";
  $smps::proc_type       = "";
  $smps::company         = "";
  $smps::currency        = "";
  $smps::reseller        = "";
  $smps::chkprocessor    = "";
  $smps::allow_overview  = "";
  $smps::walletprocessor = "";
  $smps::noreturns       = "";
  $smps::industrycode    = "";
  $smps::login_country   = "";
  $smps::header_printed  = "";
  $smps::linked_accts    = "";
  $smps::fuzzyun         = "";
  $smps::switchtime      = "";

  %smps::cookie     = ();
  %smps::cookie_out = ();

  my $feature_string = "";
  %smps::feature          = ();
  %smps::fconfig          = ();
  %smps::reseller_feature = ();

  $smps::lasttrantime = "";

  $smps::achstatus   = "";
  $smps::admindomain = "";

  @smps::thawlist     = ();
  @smps::linked_accts = ();

  $smps::path_cgi      = "smps.cgi";
  $smps::path_vt       = "virtualterm.cgi";
  $smps::path_assemble = "assemblebatch.cgi";

  @smps::log_env_array = (
    'AUTH_TYPE',   'CONTENT_LENGTH',  'CONTENT_TYPE', 'HTTP_COOKIE', 'HTTP_REFERER', 'HTTP_USER_AGENT', 'LOGIN',       'REMOTE_ADDR', 'REMOTE_USER', 'REQUEST_METHOD',
    'REQUEST_URI', 'SCRIPT_FILENAME', 'SCRIPT_NAME',  'SEC_LEVEL',   'SERVER_ADDR',  'SERVER_ADMIN',    'SERVER_NAME', 'SERVER_PORT', 'SUBACCT',     'TEMPFLAG'
  );

  $smps::username = $ENV{'REMOTE_USER'};
  $smps::username =~ s/[^0-9a-zA-Z]//g;
  $smps::login = $ENV{'LOGIN'};
  $smps::login =~ s/[^0-9a-zA-Z]//g;

  if ( ( $ENV{'SEC_LEVEL'} eq "" ) && ( $ENV{'REDIRECT_SEC_LEVEL'} ne "" ) ) {
    $ENV{'SEC_LEVEL'} = $ENV{'REDIRECT_SEC_LEVEL'};
  }

  if ( ( $ENV{'LOGIN'} eq "" ) && ( $ENV{'REDIRECT_LOGIN'} ne "" ) ) {
    $ENV{'LOGIN'} = $ENV{'REDIRECT_LOGIN'};
  }

  if ( ( $ENV{'HTTP_COOKIE'} ne "" ) ) {
    my (@cookies) = split( '\;', $ENV{'HTTP_COOKIE'} );
    foreach my $var (@cookies) {
      my ( $name, $value ) = split( '=', $var );
      $name =~ s/ //g;
      $smps::cookie{$name} = $value;
    }
  }
  if ( ( $smps::cookie{'pnpadmin_auth'} eq "tsttst" ) && ( $ENV{'REMOTE_USER'} !~ /interpreta|klarktrade/i ) ) {
    ## Sound Alarm
    my $msg = "Hacker Cookie Detected\n\n";
    foreach my $key (@smps::log_env_array) {
      $msg .= "$key:$ENV{$key}\n";
    }
    $msg .= "\n\n";
    my $sub = "SMPS Possible Hacker";
    &sendemail( "$msg", "$ENV{'SERVER_NAME'}", "$sub" );
  }

  if ( ( $ENV{'REMOTE_USER'} !~ /^(onlinetran|fractalpub|smart2demo|interpreta|klarktrade)$/i ) && ( $ENV{'HTTP_USER_AGENT'} =~ / ru\;/ ) ) {
    ## Sound Alarm
    my $msg = "Possible Hacker Detected\n\n";
    foreach my $key (@smps::log_env_array) {
      $msg .= "$key:$ENV{$key}\n";
    }
    $msg .= "\n\n";
    my $sub = "SMPS Possible Hacker";
    &sendemail( "$msg", "$ENV{'SERVER_NAME'}", "$sub" );
  }

  $smps::allowed_functions = "cardquery|cardinput|assemblebatch|querybatch|reviewchargeback|importchargeback|querychargeback|uploadbatch";

  if ( $smps::query->param('displayonly') ne "" ) {
    $smps::allowed_functions = $smps::query->param('displayonly');
  }

  $smps::function = $smps::query->param('function');
  $smps::function =~ s/[^0-9a-zA-Z\_\ ]//g;

  $smps::format = $smps::query->param('format');
  $smps::format =~ s/[^0-9a-zA-Z\_\ ]//g;

  if ( $smps::query->param('client') eq "iphone" ) {
    $smps::format = "iphone";
  }

  $smps::merchant = $smps::query->param('merchant');

  $smps::accttype = $smps::query->param('accttype');
  $smps::accttype =~ s/[^a-zA-Z]//g;

  if ( $smps::function eq "batchquery" ) {
    my $batchid = $smps::query->param('batchid');
    if ( $batchid =~ /\|/ ) {
      ( $smps::merchant, $batchid ) = split( /\|/, $batchid );
      $batchid =~ s/[^0-9]//g;
      $smps::query->param( -name => 'batchid', -value => "$batchid" );
    }
  }

  $smps::merchant =~ s/[^0-9a-zA-Z]//g;

  $smps::settletimezone = $smps::query->param('settletimezone');
  $smps::settletimezone =~ s/[^0-9a-zA-Z\-\ \_]//g;

  if ( $smps::function eq "query" ) {
    my $remember = $smps::query->param('remember');
    $remember =~ s/[^a-z]//g;

    if ( $remember eq "yes" ) {
      my $a = $smps::query->param('settletimezone');
      my $b = $smps::query->param('remember');
      $smps::cookie_out{'query_settings'} = "$a|$b";
    } else {
      delete $smps::cookie_out{'query_settings'};
    }
  } elsif ( $smps::function eq "inputnew" ) {
    my $settings = $smps::query->param('settings');
    $settings =~ s/[^a-z]//g;
    if ( $settings eq "yes" ) {
      my @settings = ( 'client', 'receipt_type', 'print_receipt', 'summarizeflg', 'settings' );
      foreach my $var (@settings) {
        my $a = $smps::query->param("$var");
        if ( $a eq "" ) {
          $a = "null";
        }
        $smps::cookie_out{'cardinput_settings'} .= "$a|";
      }
      chop $smps::cookie_out{'cardinput_settings'};
    } else {
      delete $smps::cookie_out{'cardinput_settings'};
    }
  }

  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);
  my $filemon = sprintf( "%02d", $mon + 1 );
  my ($weekno);
  if ( $mday < 8 ) {
    $weekno = "01";
  } elsif ( ( $mday >= 8 ) && ( $mday < 15 ) ) {
    $weekno = "02";
  } elsif ( ( $mday >= 15 ) && ( $mday < 22 ) ) {
    $weekno = "03";
  } else {
    $weekno = "04";
  }
  $smps::path_remotedebug = "/home/pay1/database/remotepm_debug$weekno$filemon\.txt";

  %smps::altaccts = ( 'icommerceg', [ "icommerceg", "icgoceanba", "icgcrossco" ] );

  my $dbh = &miscutils::dbhconnect("pnpmisc");

  if ( ( $smps::merchant ne "" ) && ( $ENV{'SCRIPT_NAME'} =~ /overview/ ) ) {
    my $sth = $dbh->prepare(
      qq{
        select overview
        from salesforce
        where username=?
        and status <> 'cancelled'
        }
      )
      or die "Can't do: $DBI::errstr";
    $sth->execute("$ENV{'REMOTE_USER'}") or die "Can't execute: $DBI::errstr";
    my ($overview) = $sth->fetchrow;
    $sth->finish;
    if ( $overview =~ /smps/i ) {
      $smps::allow_overview = 1;
    }
  }

  if ( $smps::allow_overview == 1 ) {
    if ( $smps::merchant eq "ALL" ) {
      my @merchlist = &merchlist( $ENV{'REMOTE_USER'} );
      %smps::altaccts = ( $ENV{'REMOTE_USER'}, [@merchlist] );
    } else {
      my $orig_reseller = $ENV{'REMOTE_USER'};
      $smps::username = &overview( $ENV{'REMOTE_USER'}, $smps::merchant );
      $ENV{'REMOTE_USER'} = $smps::username;
      if ( $smps::reseller_feature{'overview_seclevel'} > 1 ) {
        $ENV{'SEC_LEVEL'} = $smps::reseller_feature{'overview_seclevel'};
      } else {
        $ENV{'SEC_LEVEL'} = 10;
      }
      if ( $smps::merchant =~ /icommerceg/ ) {
        $smps::subacct = $smps::query->param('subacct');
        if ( ( $ENV{'SUBACCT'} eq "" ) && ( $smps::subacct ne "" ) ) {
          $ENV{'SUBACCT'} = $smps::subacct;
        }
      }
    }
  }

  if ( $smps::function eq "inputnew" ) {
    if ( ( $ENV{'REMOTE_USER'} =~ /^(jhew00000|jhewitt01)/ ) || ( $smps::merchant =~ /^(jhew00000|jhewitt01)/ ) ) {
      my $micr = $smps::query->param('micr');
      my $act  = $smps::query->param('accttype');
      if ( ( $micr eq "" ) && ( $act =~ /checking|savings/ ) ) {
        $smps::merchant = "jhtestach";
        $smps::username = "jhtestach";
      }
    } elsif ( ( $ENV{'REMOTE_USER'} =~ /^(jhew\d{5})/ ) || ( $smps::merchant =~ /^(jhew\d{5})/ ) ) {
      my $micr = $smps::query->param('micr');
      my $act  = $smps::query->param('accttype');
      if ( ( $micr eq "" ) && ( $act =~ /checking|savings/ ) ) {
        $smps::merchant = "jhewica";
        $smps::username = "jhewica";
      }
    } elsif ( ( $ENV{'REMOTE_USER'} =~ /^(jhtn|jhcn|jhpc|jhsu|jgok|jhlb|jgtx|jgtn|jhmk|jhmg|jhpm|jhrs|jhbc|jhat|jhhm|jhnw|jhpl|jhex|jhgy)/ )
      || ( $smps::merchant =~ /^(jhtn|jhcn|jhpc|jhsu|jgok|jhlb|jgtx|jgtn|jhmk|jhmg|jhpm|jhrs|jhbc|jhat|jhhm|jhnw|jhpl|jhex|jhgy)/ ) ) {
      my $temp = $1;
      my $micr = $smps::query->param('micr');
      my $act  = $smps::query->param('accttype');
      if ( ( $micr eq "" ) && ( $act =~ /checking|savings/ ) ) {
        $smps::merchant = $temp . "ica";
        $smps::username = $smps::merchant;
      }
    }
  }

  if ( ( $ENV{'REMOTE_USER'} =~ /^(ipayfideli|ipacsuppor)$/ ) ) {
    $smps::allowed_functions =~ s/cardinput\|//g;
  }

  my @params   = $smps::query->param;
  my $datetime = gmtime(time);
  $smps::strttime = time();

  if ( ( $ENV{'REQUEST_METHOD'} eq "GET" ) && ( $smps::function ne "" ) && ( $smps::function !~ /details|query/ ) ) {
    my %data = ();
    foreach my $param (@params) {
      $data{$param} = $smps::query->param($param);
    }
    my %logdata = &log_filter( \%data );

    my $datalogData = {
      'originalLogFile' => '/home/pay1/database/debug/hacksmps.txt',
      'username'        => $smps::username,
      'login'           => $ENV{'LOGIN'},
      'remoteUser'      => $ENV{'REMOTE_USER'},
      'function'        => $smps::function,
      'ipAddress'       => $ENV{'REMOTE_ADDR'},
      'scriptName'      => $ENV{'SCRIPT_NAME'}
    };

    foreach my $key ( keys %logdata ) {
      $datalogData->{$key} = $logdata{$key};
    }

    &logToDataLog($datalogData);
  }

  %smps::cardarray = (
    'vs', 'Visa', 'mc', 'MasterCard', 'ax', 'American Express',
    'ds', 'Discover', 'vsmc', 'VISA/MC Combined',
    'jc', 'JCB', 'kc', 'KeyCard', 'ach', 'ACH', 'sw', 'Solo', 'ma', 'Maestro', 'cb', 'Carte Blanche',
    'dc', 'Diners Club', 'zcombined', 'Combined'
  );
  %smps::transtype = ( 'auth', 'Authorization', 'ret', 'Return', 'return', 'Return', 'reauth', 'Reauth', 'returnprev', 'Credit' );

  $smps::time = gmtime(time);

  $smps::gatewayAccount = new PlugNPay::GatewayAccount($smps::username);
  $smps::accountFeatures = new PlugNPay::Features( $smps::username, 'general' );

  $smps::processor = $smps::gatewayAccount->getCardProcessor();
  $smps::chkprocessor = $smps::gatewayAccount->getCheckProcessor();

  if ($smps::processor) {
    my $cardProcessorAccount = new PlugNPay::Processor::Account( { gatewayAccount => $smps::username, processorName => $smps::processor } );
    $smps::merchantid = $cardProcessorAccount->getSettingValue('mid');
    $smps::proc_type  = $cardProcessorAccount->getSettingValue('authType');
    $smps::currency   = $cardProcessorAccount->getSettingValue('currency');
  }

  $smps::reseller        = $smps::gatewayAccount->getReseller();
  $smps::dccusername     = $smps::gatewayAccount->getDCCAccount();
  $smps::merchstrt       = $smps::gatewayAccount->getStartDate();
  $smps::status          = $smps::gatewayAccount->getStatus();
  $smps::walletprocessor = $smps::gatewayAccount->getWalletProcessor();
  $smps::switchtime      = $smps::gatewayAccount->getSwitchTime();

  if ( $smps::gatewayAccount->canProcessCredits() ) {
    $smps::noreturns = 'no';
  } else {
    $smps::noreturns = 'yes';
  }

  my $fraud_config = $smps::gatewayAccount->getFraudConfig();

  my $mainContact = $smps::gatewayAccount->getMainContact();
  $smps::addr1   = $mainContact->getAddress1();
  $smps::addr2   = $mainContact->getAddress2();
  $smps::city    = $mainContact->getCity();
  $smps::state   = $mainContact->getState();
  $smps::zip     = $mainContact->getPostalCode();
  $smps::country = $mainContact->getCountry();
  $smps::tel     = $mainContact->getPhone();
  $smps::company = $mainContact->getCompany();

  $feature_string = $smps::accountFeatures->getFeatureString();

  $smps::timetest{'0a_postcustinfo'} = time();
  $smps::dccusername =~ s/[^0-9a-zA-Z]//g;

  $smps::processorObj = new PlugNPay::Processor( { 'shortName' => $smps::processor } );
  if ( $smps::processor =~ /^(tampa|nova|visanet|global|mercury|fdms|fdmsnorth|paytechtampa|fifththird)$/ ) {
    my $processorAccount = new PlugNPay::Processor::Account( { 'gatewayAccount' => $smps::username, 'processorName' => $smps::processor } );
    $smps::industrycode = $processorAccount->getIndustry();
  }

  if ( $feature_string ne "" ) {
    my @array = split( /\,/, $feature_string );
    foreach my $entry (@array) {
      my ( $name, $value ) = split( /\=/, $entry );
      $smps::feature{$name} = $value;
    }
  }

  $smps::feature{'cobrand'} =~ s/[^a-zA-Z0-9\_\-]//g;

  if ( ( $smps::feature{'cobrand'} =~ /\w/ ) && ( $smps::username ne "$ENV{'LOGIN'}" ) ) {
    ## get sub-login feature settings
    my $loginClient = new PlugNPay::Authentication::Login({
      login => $ENV{'LOGIN'}
    });
    $loginClient->setRealm('PNPADMINID');

    my $result = $loginClient->getLoginInfo();
    if (!$result) {
      die('failed to load login features');
    }

    my $loginInfo = $result->get('loginInfo');
    my $loginFeaturesMap = $loginInfo->{'features'};
    my $login_features = $loginClient->featuresMapToString($loginFeaturesMap);
    
    ## apply sub-login's feature settings
    if ( $login_features ne "" ) {
      my @array = split( /\,/, $login_features );
      foreach my $entry (@array) {
        my ( $name, $value ) = split( /\=/, $entry );
        if ( $name !~ /^(sec_)/ ) {

          # idea is for sub-login feature keys to only overwrite security specific feature settings [e.g. "sec_XXXXXX"] (i.e. "sec_verifyhash" & "sec_encpayload")
          # when sub-login feature key does not match existing security feature key, it creates a new security feature key (i.e. "curbun" becomes "sec_curbun")
          # this ensures all security level features are grouped/updated together, and ensures sub-login feature settings do not overwrite sensitive keys; as such "decrypt"
          $name = "sec_" . $name;
        }
        $smps::feature{"$name"} = "$value";
      }
    }

    # perform some special sub-login feature stuff here...
    if ( $smps::feature{'sec_linked_list'} eq "yes" ) {
      $smps::feature{'linked_list'} = "yes";
    }
  }

  my $path_web = &pnp_environment::get('PNP_WEB');

  # Load external linked accounts list, if necessary
  # - merges select merchant usernames into existing 'linked_accts' features list
  # - Then sets the new 'linked_acts' features setting as a MASTER list.
  my $linkedAccounts = new PlugNPay::GatewayAccount::LinkedAccounts( $smps::username, $smps::login );
  my $linkedAccountsList = $linkedAccounts->getLinkedAccounts();
  if ( $linkedAccounts->isMaster() ) {
    unshift( @{$linkedAccountsList}, 'MASTER' );
  }
  $smps::feature{'linked_accts'} = join( '|', @{$linkedAccountsList} );

  if ( $fraud_config ne "" ) {
    my @array = split( /\,/, $fraud_config );
    foreach my $entry (@array) {
      my ( $name, $value ) = split( /\=/, $entry );
      $smps::fconfig{$name} = $value;
    }
  }

  if ( ( $smps::merchant ne "" ) && ( $ENV{'SCRIPT_NAME'} !~ /overview/ ) && ( $smps::feature{'linked_accts'} ne "" ) && ( $smps::merchant ne "ALL" ) ) {
    &check_linked_acct( $smps::username, $smps::merchant, $smps::feature{'linked_accts'} );
  }

  if ( ( $smps::username =~ /^(jhew\d{5})/ ) && ( $smps::function =~ /^(query|details|batchquery)$/ ) ) {
    $smps::query->param( -name => 'acct_code', -value => "$smps::username" );
    $smps::merchant = "ALL";
  } elsif ( ( $smps::username =~ /^(jhtn|jhcn|jhpc|jhsu|jgok|jhlb|jgtx|jgtn|jhmk|jhmg|jhpm|jhrs|jhbc|jhat|jhhm|jhnw|jhpl|jhex|jhgy)\d{5}/ ) && ( $smps::function =~ /^(query|details|batchquery)$/ ) ) {
    $smps::query->param( -name => 'acct_code', -value => "$smps::username" );
    $smps::merchant = "ALL";
  }

  if ( ( $smps::feature{'linked_accts'} ne "" ) && ( $smps::merchant eq "ALL" ) ) {
    @smps::linked_accts = split( '\|', ( $smps::feature{'linked_accts'} ) );
    if ( $smps::linked_accts[0] eq "MASTER" ) {
      shift @smps::linked_accts;
    }
    foreach my $var (@smps::linked_accts) {
      $smps::linked_accts .= "$var\'\,\'";
    }
    chop $smps::linked_accts;
    chop $smps::linked_accts;    #double chop?  not sure why this code is here but afraid to remove it.
    $smps::linked_accts = "\'$smps::linked_accts";
  }

  if ( ( $smps::merchant eq "ALL" ) && ( $ENV{'LOGIN'} =~ /^(jhcorp|cashrecon)$/ ) ) {
    $smps::fuzzyun      = "jhew";
    $smps::linked_accts = "";
  } elsif ( ( $smps::merchant eq "ALL" ) && ( $smps::username eq "aarcorp" ) ) {
    $smps::fuzzyun = "aar";
    if ( $smps::username eq $ENV{'LOGIN'} ) {
      $smps::linked_accts = "";
    }
  }

  my $sthsetup = $dbh->prepare(
    qq{
        select autobatch
        from pnpsetups
        where username=?
        }
    )
    or die "Can't do: $DBI::errstr";
  $sthsetup->execute("$smps::username") or die "Can't execute: $DBI::errstr";
  ($smps::autobatch) = $sthsetup->fetchrow;
  $sthsetup->finish;

  if ( $smps::currency eq "" ) {
    $smps::currency = "usd";
  }

  $smps::achstatus = getAchStatus({
    gatewayAccount => $smps::username,
    achProcessor => $smps::chkprocessor
  });

  ## DCP - 20050908 per request of RB/JNCB
  if ( ( $smps::processor eq 'ncb' ) && ( $smps::allow_overview != 1 ) ) {
    if ( $smps::username =~ /^(oceanicdig|paymaster|casamanolo)/i ) {
      $smps::allowed_functions = "cardquery|cardinput|assemblebatch|querybatch";
    } else {
      $smps::allowed_functions = "cardquery|cardinput";
    }
  }
  if ( $smps::feature{'dailyreport'} == 1 ) {
    $smps::allowed_functions .= "|dailyreport";
  }
  $smps::timetest{'0b_postachinfo'} = time();

  if ( $smps::query->param('hide_previous') eq "yes" ) {
    my $sth_merchants = $dbh->prepare(
      qq{
        select value
        from admin_config
        where username=?
        and fieldname=?
        }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_merchants->execute( "$smps::username", 'lasttrantime' ) or die "Can't execute: $DBI::errstr";
    ($smps::lasttrantime) = $sth_merchants->fetchrow;
    $sth_merchants->finish;
  }

  $dbh->disconnect;

  if ( ( $smps::feature{'adminipcheck'} == 1 ) && ( $ENV{'REMOTE_USER'} ne $ENV{'LOGIN'} ) ) {
    my %security = &security_check( $smps::username, $ENV{'REMOTE_ADDR'} );
    if ( $security{'flag'} != 1 ) {
      &response_page( $security{'MErrMsg'} );
    }
  }

  $smps::timetest{'0c_postresellinfo'} = time();

  if ( ( $smps::admindomain eq "" ) || ( $smps::admindomain =~ /actmerchant/ ) || ( $smps::admindomain =~ /frontline/ ) ) {
    $smps::admindomain = "pay1.plugnpay.com";
  }

  ###  DCP - Remove Functionality of an AdminDomain.  The AdminDomain that merchant logs in with is where they stay.
  $smps::admindomain = $ENV{'SERVER_NAME'};

  $smps::login_country = &check_geolocation("$ENV{'REMOTE_ADDR'}");

  if ( $smps::function ne "" ) {
    &debug_log($smps::query);
  }

  return [], $type;
}

=pod

getAchStatus()

Takes a gatewayAccount and ach processor handle and returns wether or not ach is enabled for that account.

=cut

sub getAchStatus {
  my $input = shift;

  my $gatewayAccount = $input->{'gatewayAccount'};
  if (!defined $gatewayAccount) {
    die('gatewayAccount is required');
  }

  my $achProcessor = $input->{'achProcessor'};

  my $status = "disabled";

  if ( $achProcessor eq "testprocessor" || $achProcessor eq "testprocessorach" ) {
    $status = "enabled";
  } elsif ( defined $achProcessor && $achProcessor ne '' ) {
    eval {
      my $achProcAccount = new PlugNPay::Processor::Account(
        { 'gatewayAccount' => $gatewayAccount,
          'processorName'  => $achProcessor
        }
      );
      if ($achProcAccount->hasSetting('status')) {
        $status = $achProcAccount->getSettingValue('status');
      }
    };
  }

  return $status;
}

# used for a numeric sort
sub numerically { $a <=> $b }

sub main {
  my ( $sec, $min, $hour, $mday, $mon, $yyear, $wday, $yday, $isdst ) = gmtime( time() - 86400 );
  my $startdate = sprintf( "%02d/%02d/%04d", $mon + 1, $mday, $yyear + 1900 );

  my $chkstartdate = sprintf( "%04d%02d%02d", $yyear + 1900, $mon + 1, $mday );
  if ( $chkstartdate < $smps::earliest_date ) {
    $startdate = substr( $smps::earliest_date, 4, 2 ) . "/" . substr( $smps::earliest_date, 6, 2 ) . "/" . substr( $smps::earliest_date, 0, 4 );
  }

  ( $sec, $min, $hour, $mday, $mon, $yyear, $wday, $yday, $isdst ) = gmtime( time() + 86400 );
  my $enddate = sprintf( "%02d/%02d/%04d", $mon + 1, $mday, $yyear + 1900 );

  print "<table border=0 cellspacing=0 cellpadding=4>\n";

  if ( $smps::reseller !~ /^(vermont|vermont2|vermont3)$/ ) {
    if ( $smps::autobatch ne "" ) {
      print "<tr><td align=\"left\" colspan=\"2\"><b><font color=\"#ff0000\">NOTE:</font> Your account has been setup to automatically batch your credit card transactions daily.<br></br></td>\n";
    } elsif ( ( $smps::proc_type ne "authcapture" ) && ( $smps::processor ne "psl" ) ) {
      print "<tr><td align=\"left\" colspan=\"2\"><b><font color=\"#ff0000\">IMPORTANT:</font> You must batch out your transactions in order for";
      print " funds to be posted to your account.<br>&nbsp;</b></td>\n";
    }
  }

  print "<td align=\"right\" colspan=\"2\"><form method=\"post\" action=\"/admin/wizards/faq_board.cgi\" target=\"minifaq\">\n";
  print "<input type=\"hidden\" name=\"mode\" value=\"mini_faq_list\">\n";
  print "<input type=\"hidden\" name=\"category\" value=\"all\">\n";
  print "<input type=\"hidden\" name=\"search_keys\" value=\"QA20011210183553,QA20011210183746,QA20011210183820,QA20011210183847,QA20011210184040,QA20011210183637,QA20011210183518\">\n";
  print "<input type=\"submit\" value=\"Mini-FAQ\" onClick=\"popminifaq();\"></form></td>\n";
  print "</tr>\n";

  if ( $smps::allowed_functions =~ /cardquery/ ) {
    if ( ( $ENV{'SEC_LEVEL'} < 11 ) || ( $ENV{'SEC_LEVEL'} == 15 ) ) {
      &cardquery( $startdate, $enddate );
    }
  }
  if ( $smps::allowed_functions =~ /dailyreport/ ) {
    if ( ( $ENV{'SEC_LEVEL'} < 11 ) || ( $ENV{'SEC_LEVEL'} == 15 ) ) {
      &daily_report( $startdate, $enddate );
    }
  }
  if ( $ENV{'SEC_LEVEL'} < 9 ) {
    if ( $smps::allowed_functions =~ /cardinput/ ) {
      if ( ( $smps::processor =~ /^planetpay$/ ) && ( $smps::feature{'multicurrency'} != 1 ) ) {
        print "<td><hr width=400></td></tr>\n";
        print "<tr>\n";
        print "<td class=\"menuleftside\">Manual Authorizations &amp; Returns</td>\n";
        print "<td class=\"menurightside\">\n";

        print "Manually entered transaction are not permitted through a DCC account.<p>\n";
        print "Please use your primary account to enter these types of transactions.<p>\n";
        print "Credits against previously sales should be performed by searching on the original transaction first.<p>\n";
        print "<hr width=400></td></tr>\n";
      } else {
        if ( $smps::feature{'vtversion'} == 1 ) {
          &cardinput();
        } else {
          &cardinput_new();
        }
      }
    }
    if ( ( $smps::allowed_functions =~ /assemblebatch/ ) && ( $smps::proc_type ne "authcapture" ) ) {
      &assemblebatch( $startdate, $enddate );
    }
  }

  if ( $ENV{'SEC_LEVEL'} < 11 ) {
    if ( ( $smps::allowed_functions =~ /querybatch/ ) && ( $smps::proc_type ne "authcapture" ) ) {
      &querybatch( $startdate, $enddate );
    }
  }

  if ( $ENV{'SEC_LEVEL'} < 9 ) {
    if ( ( $smps::allowed_functions =~ /uploadbatch/ ) && ( $smps::proccessor !~ /volpay/ ) ) {
      &batchuploadform();
    }
  }

  print "</table>\n";
  &tail();
  return;

}

sub details {

  my $mark_flag     = 0;
  my $void_flag     = 0;
  my $hold_flag     = 0;
  my $locked_flag   = 0;
  my $mark_ret_flag = 0;
  my $settled_flag  = 0;
  my $auth_flag     = 0;
  my $reauth_flag   = 1;
  my $pending_flag  = 0;
  my $setlret_flag  = 0;

  my ( $cardnumber, $card_exp, $auth_code, $avs_code, $cvvresp, $first_flag );

  my $orderid = $smps::query->param('orderid');
  $orderid =~ s/[^0-9]//g;

  my $startdate = $smps::query->param('start-time');
  my $enddate   = $smps::query->param('end-time');
  my $accttype  = $smps::query->param('accttype');
  my $decrypt   = $smps::query->param('decrypt');
  my $rep1      = $smps::query->param('rep1');
  my $rep2      = $smps::query->param('rep2');

  ### DCP 20120109
  $startdate =~ s/[^0-9]//g;
  $enddate =~ s/[^0-9]//g;
  $accttype =~ s/[^a-z]//g;
  $decrypt =~ s/[^a-z]//g;
  $rep1 =~ s/[^0-9]//g;
  $rep2 =~ s/[^0-9]//g;

  if ( ( $smps::allow_overview == 1 ) && ( $ENV{'LOGIN'} =~ /^(jncb)$/ ) ) {
    $smps::feature{'decryptflag'}    = 1;
    $smps::feature{'decryptallflag'} = 1;
  }

  if ( $smps::feature{'decryptflag'} != 1 || $smps::feature{'decryptallflag'} != 1 ) {
    $decrypt = "";    #DCP  20091225
  }

  my $isDemoUser            = $smps::username =~ /^(pnpdemo|pnpdemo2|billpaydem|willtest|reneeclark|seventwent|onestepdem|avrdev)/i;
  my $isRemoteAddrException = $ENV{'REMOTE_ADDR'} =~ /(83\.149\.113\.151|217\.118\.66\.232|67\.165\.246\.136)/;
  my $isTech                = $ENV{'TECH'} ne '';
  if ( $ENV{'REMOTE_ADDR'} !~ /(96\.56\.10\.12)/ && ( $isDemoUser || $isTech || $isRemoteAddrException ) ) {
    $decrypt = "";
  }

  if ( $ENV{'LOGIN'} =~ /^(premier2)$/ ) {    ####  Added 20100129  at the request of Jim Schafle.
    $decrypt = "";
    $decrypt = "yes";
  }
  my ( $maxidx, %result, $txntypevoid, $txntyperetry );

  if ( ( $smps::username eq "icommerceg" ) && ( $ENV{'SUBACCT'} ne "" ) ) {
    my ($i);
    if ( exists $smps::altaccts{$smps::username} ) {
      foreach my $var ( @{ $smps::altaccts{$smps::username} } ) {
        my %res_icg = &miscutils::sendmserver( "$var", 'query', 'accttype', "$accttype", 'order-id', "$orderid", 'start-time', "$startdate", 'end-time', "$enddate" );
        foreach my $key ( keys %res_icg ) {
          $i++;
          $result{"a$i"} = $res_icg{$key};
        }
      }
    }
  } else {
    %result =
      &miscutils::sendmserver( "$smps::username", 'query', 'accttype', "$accttype", 'order-id', "$orderid", 'start-time', "$startdate", 'end-time', "$enddate", 'linked_accts', "$smps::linked_accts" );
  }

  my $color = 1;

  my (
    %res2,   %amt,        %times,       $price,   $amount, $txntype,    $shortcard, $acct_code, $acct_code2,  $acct_code3, $acct_code4, $descr,
    $status, $transflags, $chkaccttype, $batchid, $oldflg, $returndate, $refnumber, $authdate,  $entrymethod, $checktype,  $reauthAmount
  );
  my @values = values %result;
  foreach my $var ( sort @values ) {
    %res2 = ();
    my @nameval = split( /&/, $var );
    foreach my $temp (@nameval) {
      my ( $name, $value ) = split( /=/, $temp );
      $res2{$name} = $value;
    }

    if ( $res2{'time'} ne "" ) {
      my $time     = $res2{"time"};
      my $timetemp = $time;
      if ( ( $smps::settletimezone ne "" ) && ( $smps::settletimezone != 0 ) ) {
        $time = &miscutils::strtotime($time);
        $time += ( $smps::settletimezone * 60 * 60 );
        $time = &miscutils::timetostr($time);
      }

      if ( ( length( $result{'auth-code'} ) <= 160 ) && ( $smps::processor eq "planetpay" ) ) {
        $oldflg = 1;
      }

      my $timestr = substr( $time, 4, 2 ) . "/" . substr( $time, 6, 2 ) . "/" . substr( $time, 0, 4 ) . " ";
      $timestr = $timestr . substr( $time, 8, 2 ) . ":" . substr( $time, 10, 2 ) . ":" . substr( $time, 12, 2 );

      my $operation = $res2{"operation"};
      $txntype = $res2{"txn-type"};

      if ( $txntype eq "auth" ) {
        $authdate = substr( $res2{'time'}, 0, 8 );
        $refnumber = $res2{'merch-txn'};
      }

      my $status = $res2{"txn-status"};
      $amount = $res2{"amount"};

      if ( $txntype eq 'reauth' ) {
        $reauthAmount = $amount;
      }

      my ( $stuff, $pr ) = split( / /, $amount );
      $amt{"$txntype"} += $pr;

      $times{$txntype} = $time;

      if ( $txntype eq "return" ) {
        $returndate = $time;
      }

      my $merchtxn = $res2{"merch-txn"};
      $status = $res2{"txn-status"};
      $descr  = $res2{"descr"};

      $acct_code   = $res2{'acct_code'};
      $acct_code2  = $res2{'acct_code2'};
      $acct_code3  = $res2{'acct_code3'};
      $acct_code4  = $res2{'acct_code4'};
      $transflags  = $res2{'transflags'};
      $chkaccttype = $accttype;
      $checktype   = substr( $res2{'auth-code'}, 6, 3 );

      if ( ( $txntype eq "auth" ) && ( $smps::industrycode =~ /^(retail|restuarant|petroleum)$/ ) ) {
        $entrymethod = &entrymethod( $res2{'auth-code'}, $res2{'cardextra'} );
      }

      if ( $txntype =~ /^(postauth|return)$/ ) {
        $batchid = $res2{'batch-id'};
      }

      if ( ( $txntype eq "settled" ) || ( $txntype eq "auth" ) || ( $txntype eq "capture" ) || ( $txntype eq "postauth" ) ) {
        $price = $res2{"amount"};
      }
      if ( $status eq "locked" ) {
        $locked_flag = 1;
      }
      if ( ( $txntype eq "auth" ) && ( $status eq "hold" ) ) {
        $hold_flag = 1;
      }
      if ( ( $txntype eq "void" ) && ( $status eq "success" ) ) {
        $void_flag = 1;
      }
      if ( ( $txntype =~ /^(auth|forceauth)$/ ) && ( $status eq "success" ) ) {
        $mark_flag = 1;
      }
      if ( ( $txntype =~ /^(auth)$/ ) && ( $status eq "pending" ) && ( $accttype eq "checking" ) && ( $smps::chkprocessor =~ /^(alliance|alliancesp)$/ ) ) {
        $mark_flag = 1;
      }
      if ( ( $txntype eq "postauth" ) && ( $status eq "locked" ) ) {
        $mark_flag = 0;
      } elsif ( ( $txntype eq "postauth" ) && ( $status eq "pending" ) ) {
        $mark_flag = 1;
      }
      if ( ( $txntype eq "return" ) && ( $status eq "pending" ) ) {
        $mark_ret_flag = 1;
        $mark_flag     = 1;
      }
      if ( ( $txntype eq "postauth" ) && ( $status eq "success" ) ) {
        $settled_flag = 1;
      }
      if ( ( $txntype eq "return" ) && ( $status =~ /^(badcard|success)$/ ) ) {
        $setlret_flag = 1;
      }
      if ( ( $txntype eq "postauth" ) || ( ( $txntype eq "reauth" ) && ( $status eq "success" ) ) ) {
        $reauth_flag = 0;
      }
      ###  DCP 20060626 Added code to exclude authcaputre trans after switching to authonly.
      my $checkSettlementStatusArguments = {
        'transType' => $txntype,
        'status' => $status,
        'industryCode' => $smps::industrycode,
        'accountType' => $accttype,
        'achProcessor' => $smps::chkprocessor,
        'cardProcessor' => $smps::processor,
        'transFlags' => $transflags,
        'authType' => $smps::proc_type
      };

      if (&checkTransCountsAsSettled($checkSettlementStatusArguments)) {
        $settled_flag = 1;
      }

      if ( $first_flag ne "1" ) {
        if ( $result{'card-number'} ne "" ) {
          $cardnumber = $result{'card-number'};
          $card_exp   = $result{'card-exp'};
        } else {
          $cardnumber = $res2{'card-number'};
          $card_exp   = $res2{'card-exp'};
        }
        if ( $ENV{'LOGIN'} =~ /^(premier2)$/ ) {    ####  Added 20110418
          $cardnumber = substr( $cardnumber, 0, 6 ) . "**" . substr( $cardnumber, -2 );
        }

        if ( $result{'auth-code'} ne "" ) {
          $auth_code = substr( $result{'auth-code'}, 0, 6 );
          $avs_code  = $result{'avs-code'};
          $cvvresp   = $result{'cvvresp'};
        } else {
          $auth_code = substr( $res2{'auth-code'}, 0, 6 );
          $avs_code  = $res2{'avs-code'};
          $cvvresp   = $res2{'cvvresp'};
        }

        # Get CC Token for call to adjustment calculator #
        if ( &enabledInAdjustmentTable() ) {

          # first decrypt card
          my $transactionDate = substr( $timetemp, 0, 8 );
          my $decryptedCardNumber = &getcn( "$orderid", "$transactionDate", "$transactionDate" );

          # then get token
          my $creditCard = new PlugNPay::CreditCard($decryptedCardNumber);
          my $cardToken  = $creditCard->getToken();

          # print the token in the html
          print "<span id=\"cardToken\" style=\"display:none;\">$cardToken</span>\n";
        }

        print "<h3>Order ID: $orderid</h3>\n";
        if ( $transflags =~ /balance/i ) {
          print "BALANCE INQUIRY<p>\n";
        } elsif ( $transflags =~ /avsonly/i ) {
          print "AVS INQUIRY<p>\n";
        }

        if ( ( $transflags !~ /balance|avsonly/i ) && ( $txntype !~ /return/ ) ) {
          print "<b>Authorization Code:</b> $auth_code<br>\n";
          if ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) {
            print "<b>Address Verification Code:</b> $avs_code<br>\n";
            print "<b>CVV2 Response Code:</b> $cvvresp<br>\n";
            print "<b>Card Type:</b> $res2{'card-type'}<br>\n";
          } else {
            print "<b>Account Type:</b> <span id=\"detailsAccountType\">$chkaccttype</span><br>\n";
          }
        }

        if ( $res2{'card-name'} ne "" ) {
          print "<b>Card Name:</b> $res2{'card-name'}<br>\n";
        }
        if ( $res2{'card-addr'} ne "" ) {
          print "<b>Address:</b> $res2{'card-addr'}<br>\n";
          print "<b>City, State Zip:</b> $res2{'card-city'}, <span id='detailsBillingState'>$res2{'card-state'}</span>  $res2{'card-zip'}<br>\n";
          if ( $res2{'card-country'} ne "" ) {
            print "<b>Country:</b> $res2{'card-country'}<br>\n";
          }

        }

        my $card_number = $cardnumber;
        my $cclength    = length($card_number);
        my $last4       = substr( $card_number, -4, 4 );
        $shortcard = substr( $card_number, 0, $cclength - 4 ) . $last4;
        $card_number =~ s/./X/g;

        if ( $smps::query->param('decrypt') eq "yes" ) {
          print "<script type='text/javascript'>\n";
          print "       \$(document).ready(function(){\n";
          print "           decryptCard(\$(\"#orderid\").val());\n";
          print "        });\n";
          print "</script>\n";
          print "<input type=\"hidden\" id=\"orderid\" value=\"$orderid\">\n";
        }
        if ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) {
          print "<b>Card Number:</b> <span id=\"order_id_$orderid\">$shortcard</span><br>\n";
          print "<b>Card Expiration:</b> $card_exp<br>\n";
        } else {
          print "<b>Routing/Acccount:</b>  <span id=\"order_id_$orderid\">$shortcard</span><br>\n";
        }
        if ( ( $descr ne "" ) && ( $status =~ /^(badcard|problem|fraud)$/ ) ) {
          print "<b>Bank Response:</b> $descr<br>\n";
        }
        if ( $acct_code ne "" ) {
          print "<b>Acct. Code:</b> $acct_code<br>\n";
        }
        if ( $acct_code2 ne "" ) {
          print "<b>Acct. Code2:</b> $acct_code2<br>\n";
        }
        if ( $acct_code3 ne "" ) {
          print "<b>Acct. Code3:</b> $acct_code3<br>\n";
        }
        if ( $entrymethod ne "" ) {
          print "<b>Entry Method:</b> $entrymethod<br>\n";
        }

        if ( ( $smps::feature{'amexlev2'} == 1 ) && ( $res2{'card-type'} eq "ax" ) ) {
          my $startdate = substr( $timetemp, 0, 8 );
          my $dbh = &miscutils::dbhconnect( "pnpdata", "", "$smps::username" );    ## OrdersSummary
          my $sth = $dbh->prepare(
            qq{
                select shipname,shipaddr1
                from ordersummary
                where orderid=?
                and trans_date>=?
                and username=?
          }
          );
          $sth->execute( "$orderid", "$startdate", "$smps::username" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr" );
          my ( $shipname, $address1 ) = $sth->fetchrow;
          $sth->finish;
          $dbh->disconnect;
          print "<b>Employee Name:</b> $shipname<br>\n";
          print "<b>Cost Center #:</b> $address1<br>\n";
        }
        print "<br>\n";
        if ( $acct_code3 eq "pnp_sign_data" ) {
          print "<img src=\"signature_image.cgi\?orderID=$orderid\" height=\"50\" width=\"200\">\n";
          print "<br>\n";
        }
        $first_flag = 1;

        print "<table border=1 cellspacing=0 cellpadding=2>\n";
        print "<tr>\n";
        print "  <th align=left>Type</th>";
        print "  <th align=left>Status</th>";
        print "  <th align=left>Amount</th>";
        print "  <th align=left>Merchant Trans ID</th>";
        print "  <th>Transaction Time <font size=-2>(GMT $smps::settletimezone)<br>MM/DD/YYYY HH:MM:SS</font></th>";
        print "  <th align=left>Log Time (UTC)</th>";

        if ( $accttype =~ /^(checking|savings)$/ ) {
          print "  <th align=left>Result</th>\n";
        }
        print "  <th align=left>Batch ID</th>\n";
        print "\n";
      }

      if ( $color == 1 ) {
        print "  <tr class=\"listrow_color1\">\n";
      } else {
        print "  <tr class=\"listrow_color0\">\n";
      }
      print "  <td><nobr>$txntype";
      if ( $transflags =~ /fund/i ) {
        print " - CFT";
      }
      print "</nobr></td>\n";
      print "  <td><nobr>$status</nobr></td>\n";
      print "  <td><nobr>$amount</nobr></td>\n";
      print "  <td><nobr>$merchtxn</nobr></td>\n";
      print "  <td align=center><nobr>$timestr</nobr></td>\n";
      print "  <td align=center><nobr>$timetemp</nobr></td>\n";
      if ( ( $accttype =~ /^(checking|savings)$/ ) && ( $status =~ /^(badcard|problem|fraud)$/ ) ) {
        print "  <td align=left><nobr>$descr</nobr></td>\n";
      }
      if ( $txntype =~ /^(postauth|return)$/ ) {
        print "  <td align=left><nobr><b>$batchid</b></nobr></td>\n";
      }
      print "\n";

      $color = ( $color + 1 ) % 2;
    }
  }

  print "</table>\n";

  ### Representments
  if ( ( $accttype eq "checking" ) && ( $rep1 ne "" ) ) {
    my ( %result1, %result2 );
    my $color = 1;
    $first_flag = 0;

    %result1 = &miscutils::sendmserver( "$smps::username", 'query', 'accttype', "$accttype", 'start-time', "$startdate", 'order-id', "$rep1" );

    if ( $rep2 ne "" ) {
      %result2 = &miscutils::sendmserver( "$smps::username", 'query', 'accttype', "$accttype", 'start-time', "$startdate", 'order-id', "$rep2" );
      foreach my $key ( sort keys %result2 ) {
        my $newkey = "a" . $key;
        $result1{$newkey} = $result2{$key};
      }
    }

    my (
      %res2,  %amount, $price,      $amount,      $txntype, $shortcard, $acct_code,  $acct_code2, $acct_code3, $acct_code4,
      $descr, $status, $transflags, $chkaccttype, $batchid, $oldflg,    $returndate, $orderid,    $merchant,   $checktype
    );
    my @values = values %result1;
    foreach my $var ( sort @values ) {
      %res2 = ();
      my @nameval = split( /&/, $var );
      foreach my $temp (@nameval) {
        my ( $name, $value ) = split( /=/, $temp );
        $res2{$name} = $value;
      }

      if ( $res2{'time'} ne "" ) {
        my $time     = $res2{"time"};
        my $timetemp = $time;
        if ( ( $smps::settletimezone ne "" ) && ( $smps::settletimezone != 0 ) ) {
          $time = &miscutils::strtotime($time);
          $time += ( $smps::settletimezone * 60 * 60 );
          $time = &miscutils::timetostr($time);
        }

        my $timestr = substr( $time, 4, 2 ) . "/" . substr( $time, 6, 2 ) . "/" . substr( $time, 0, 4 ) . " ";
        $timestr = $timestr . substr( $time, 8, 2 ) . ":" . substr( $time, 10, 2 ) . ":" . substr( $time, 12, 2 );

        my $operation = $res2{"operation"};
        $txntype = $res2{"txn-type"};

        my $status = $res2{"txn-status"};
        $amount = $res2{"amount"};

        my ( $stuff, $pr ) = split( / /, $amount );
        $amt{"$txntype"} += $pr;

        my $merchtxn = $res2{"merch-txn"};
        $status = $res2{"txn-status"};
        $descr  = $res2{"descr"};

        $acct_code   = $res2{'acct_code'};
        $acct_code2  = $res2{'acct_code2'};
        $acct_code3  = $res2{'acct_code3'};
        $acct_code4  = $res2{'acct_code4'};
        $transflags  = $res2{'transflags'};
        $chkaccttype = $accttype;
        $checktype   = substr( $res2{'auth-code'}, 6, 3 );
        $orderid     = $res2{"order-id"};
        $merchant    = $res2{'username'};

        if ( $first_flag ne "1" ) {

          print "<h3>Representments</h3>\n";
          print "<table border=1 cellspacing=0 cellpadding=2>\n";
          print "<tr>\n";
          print "  <th align=left>Type</th>";
          print "  <th align=left>Status</th>";
          print "  <th align=left>Amount</th>";
          print "  <th align=left>Merchant Trans ID</th>";
          print "  <th>Transaction Time <font size=-2>(GMT $smps::settletimezone)<br>MM/DD/YYYY HH:MM:SS</font></th>";
          print "  <th align=left>Log Time (UTC)</th>";
          print "  <th align=left>Result</th>\n";
          print "  <th align=left>OrderID</th>\n";
          print "\n";

          $first_flag = 1;
        }
        if ( $color == 1 ) {
          print "  <tr class=\"listrow_color1\">\n";
        } else {
          print "  <tr class=\"listrow_color0\">\n";
        }
        my $strtstrg;
        if ( $smps::merchant ne "ALL" ) {
          $strtstrg .= "\&merchant=$smps::merchant";
        } else {
          $strtstrg .= "\&merchant=$merchant";
        }

        $strtstrg .= "\&settletimezone=$smps::settletimezone";
        if ( ( $ENV{'SEC_LEVEL'} < 7 ) && ( $smps::query->param('decrypt') eq "yes" ) && ( ( $smps::feature{'decryptflag'} == 1 ) || ( $smps::feature{'decryptallflag'} == 1 ) ) ) {
          $strtstrg .= "\&decrypt=yes";
        }

        print "  <td><nobr>$txntype</nobr></td>\n";
        print "  <td><nobr>$status</nobr></td>\n";
        print "  <td><nobr>$amount</nobr></td>\n";
        print "  <td><nobr>$merchtxn</nobr></td>\n";
        print "  <td align=center><nobr>$timestr</nobr></td>\n";
        print "  <td align=center><nobr>$timetemp</nobr></td>\n";
        print "  <td align=left><nobr>$descr</nobr></td>\n";
        print "  <td align=left><nobr><a href=\"$smps::path_cgi\?accttype=$accttype\&acct_code=$acct_code\&function=details&orderid=$orderid$strtstrg\"><b>$orderid</b></a></nobr></td>\n";
        $color = ( $color + 1 ) % 2;

      }
    }
    print "</table>\n";
  }

  if ( $smps::feature{'allow_multret'} eq "1" ) {
    ###  If total amount of return is less then auth.
    ###   20120118 - Modified to reduce amount of returns by amount of voids.
    if ( ( $amt{'postauth'} > 0 ) && ( $amt{'return'} > 0 ) && ( $amt{'postauth'} > ( $amt{'return'} - $amt{'void'} ) ) ) {
      my $startdate = substr( 0, 8, $returndate );
      $startdate  = $returndate;
      $first_flag = 0;

      ### Need to query for additional returns.
      %result = &miscutils::sendmserver( "$smps::username", 'query', 'accttype', "$accttype", 'start-time', "$startdate", 'partial', '1', 'acct_code4', "lnk$orderid", 'operation', 'return' );
      my (
        %res2,  %amount, $price,      $amount,      $txntype, $shortcard, $acct_code,  $acct_code2, $acct_code3, $acct_code4,
        $descr, $status, $transflags, $chkaccttype, $batchid, $oldflg,    $returndate, $orderid,    $merchant,   $checktype
      );
      my @values = values %result;
      foreach my $var ( sort @values ) {
        %res2 = ();
        my @nameval = split( /&/, $var );
        foreach my $temp (@nameval) {
          my ( $name, $value ) = split( /=/, $temp );
          $res2{$name} = $value;
        }

        if ( $res2{'time'} ne "" ) {
          my $time     = $res2{"time"};
          my $timetemp = $time;
          if ( ( $smps::settletimezone ne "" ) && ( $smps::settletimezone != 0 ) ) {
            $time = &miscutils::strtotime($time);
            $time += ( $smps::settletimezone * 60 * 60 );
            $time = &miscutils::timetostr($time);
          }

          my $timestr = substr( $time, 4, 2 ) . "/" . substr( $time, 6, 2 ) . "/" . substr( $time, 0, 4 ) . " ";
          $timestr = $timestr . substr( $time, 8, 2 ) . ":" . substr( $time, 10, 2 ) . ":" . substr( $time, 12, 2 );

          my $operation = $res2{"operation"};
          $txntype = $res2{"txn-type"};

          my $status = $res2{"txn-status"};
          $amount = $res2{"amount"};

          my ( $stuff, $pr ) = split( / /, $amount );
          $amt{"$txntype"} += $pr;

          my $merchtxn = $res2{"merch-txn"};
          $status = $res2{"txn-status"};
          $descr  = $res2{"descr"};

          $acct_code   = $res2{'acct_code'};
          $acct_code2  = $res2{'acct_code2'};
          $acct_code3  = $res2{'acct_code3'};
          $acct_code4  = $res2{'acct_code4'};
          $transflags  = $res2{'transflags'};
          $chkaccttype = $res2{'accttype'};
          $checktype   = substr( $res2{'auth-code'}, 6, 3 );
          $orderid     = $res2{"order-id"};
          $merchant    = $res2{'username'};

          if ( $first_flag ne "1" ) {
            print "<h3>Linked Credits</h3>\n";
            print "<table border=1 cellspacing=0 cellpadding=2>\n";
            print "<tr>\n";
            print "  <th align=left>Type</th>";
            print "  <th align=left>Status</th>";
            print "  <th align=left>Amount</th>";
            print "  <th align=left>Merchant Trans ID</th>";
            print "  <th>Transaction Time <font size=-2>(GMT $smps::settletimezone)<br>MM/DD/YYYY HH:MM:SS</font></th>";
            print "  <th align=left>Log Time (UTC)</th>";

            if ( $accttype =~ /^(checking|savings)$/ ) {
              print "  <th align=left>Result</th>\n";
            }
            print "  <th align=left>OrderID</th>\n";
            print "\n";

            $first_flag = 1;
          }
          if ( $color == 1 ) {
            print "  <tr class=\"listrow_color1\">\n";
          } else {
            print "  <tr class=\"listrow_color0\">\n";
          }
          my $strtstrg;
          if ( $smps::merchant ne "ALL" ) {
            $strtstrg .= "\&merchant=$smps::merchant";
          } else {
            $strtstrg .= "\&merchant=$merchant";
          }

          $strtstrg .= "\&settletimezone=$smps::settletimezone";
          if ( ( $ENV{'SEC_LEVEL'} < 7 ) && ( $smps::query->param('decrypt') eq "yes" ) && ( ( $smps::feature{'decryptflag'} == 1 ) || ( $smps::feature{'decryptallflag'} == 1 ) ) ) {
            $strtstrg .= "\&decrypt=yes";
          }

          print "  <td><nobr>$txntype</nobr></td>\n";
          print "  <td><nobr>$status</nobr></td>\n";
          print "  <td><nobr>$amount</nobr></td>\n";
          print "  <td><nobr>$merchtxn</nobr></td>\n";
          print "  <td align=center><nobr>$timestr</nobr></td>\n";
          print "  <td align=center><nobr>$timetemp</nobr></td>\n";
          if ( ( $accttype =~ /^(checking|savings)$/ ) && ( $status =~ /^(badcard|problem|fraud)$/ ) ) {
            print "  <td align=left><nobr>$descr</nobr></td>\n";
          }
          print "\n";
          print "  <td align=left><nobr><a href=\"$smps::path_cgi\?accttype=$accttype\&acct_code=$acct_code\&function=details&orderid=$orderid$strtstrg\"><b>$orderid</b></a></nobr></td>\n";
          print "\n";
          $color = ( $color + 1 ) % 2;
        }
      }
      print "</table>\n";
    }
  }    ####   END New Code to support multiple credits.

  if ( ( $void_flag != 1 ) && ( $locked_flag != 1 ) ) {
    if ( $pending_flag == 1 ) {
      print "<p>\n";
      print "<h4>Retry Transaction</h4>\n";
      print "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
      print "<input type=\"hidden\" name=\"accttype\" value=\"$accttype\">";
      print "<input type=\"hidden\" name=\"acct_code\" value=\"$acct_code\">";
      print "<input type=\"hidden\" name=\"function\" value=\"retry\">\n";
      print "<input type=\"hidden\" name=\"orderid\" value=\"$orderid\">\n";
      print "<input type=\"hidden\" name=\"txntype\" value=\"$txntyperetry\">\n";
      print "<input type=\"hidden\" name=\"merchant\" value=\"$smps::username\">";

      if ( $smps::feature{'show_vt_receipt'} == 1 ) {
        print "<input type=\"hidden\" name=\"receipt_type\" value=\"simple\">\n";
      }
      print "<input type=\"submit\" name=\"submit\" value=\"Retry\">\n";
      print "</form>\n";
      print "</p>\n";
    } elsif ( ( $settled_flag == 1 ) && ( $mark_ret_flag == 0 ) && ( $setlret_flag == 0 ) && ( $ENV{'SEC_LEVEL'} =~ /^(0|1|2|3|4|5|6|7|15)$/ ) ) {
      if ( $smps::username =~
        /^(sksupport|mplifka|jwyluda|garyrock|studiostre|plynch|jeffreyibr|sword123|teamwork1|willworkin|legends|sksupport|4productio|accessdst|aqua123|acropolis|bascomturn|emerceg|vkaminski|cyd0520260|bpowell110|waterworx|dynamic1|editex|elephant1|fairfieldr|highprofil|hkcpa|alleng|in4med|infantmed|srobertson|we6ather|mbiassocia|metrocandy|millennium4|needhamped|sasan|wcaputo|pdrucker1|hshepherd|fivestarco|mklayman)$/
        ) {
        print "<p>\n";
        print "<h4>Issue credit using billing data on file.</h4>\n";
        print "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
        print "<input type=\"hidden\" name=\"username\" value=\"$smps::username\">\n";
        print "<input type=\"hidden\" name=\"accttype\" value=\"$accttype\">\n";
        print "<input type=\"hidden\" name=\"acct_code\" value=\"$acct_code\">\n";
        print "<input type=\"hidden\" name=\"acct_code4\" value=\"lnk$orderid\">\n";
        print "<input type=\"hidden\" name=\"function\" value=\"inputnew\">\n";
        print "<input type=\"hidden\" name=\"mode\" value=\"returnprev\">\n";
        print "<input type=\"hidden\" name=\"prevorderid\" value=\"$orderid\">\n";
        print "<input type=\"hidden\" name=\"merchant\" value=\"$smps::username\">";
        my (%selected);
        my $currency = substr( $price, 0, 3 );
        my $price = substr( $price, 4 );
        $selected{$currency} = " selected";

        if ( ( $smps::feature{'curr_allowed'} ne "" ) && ( $smps::processor eq "ncb" ) && ( $smps::feature{'procmulticurr'} == 1 ) ) {
          print "         Amount: <select name=\"currency\">\n";
          my @array = split( /\|/, $smps::feature{'curr_allowed'} );
          foreach my $entry (@array) {
            $entry =~ tr/A-Z/a-z/;
            $entry =~ s/[^a-z]//g;
            print "<option value=\"$entry\" $selected{$entry}>$entry</option>\n";
          }
          print "</select> ";
        } elsif ( ( $smps::feature{'curr_allowed'} ne "" ) && ( $smps::processor =~ /^(pago|atlantic|planetpay|testprocessor|fifththird|wirecard)$/ ) ) {
          print "         Amount: <select name=\"currency\">\n";
          my @array = split( /\|/, $smps::feature{'curr_allowed'} );
          foreach my $entry (@array) {
            $entry =~ tr/A-Z/a-z/;
            $entry =~ s/[^a-z]//g;
            print "<option value=\"$entry\" $selected{$entry}>$entry</option>\n";
          }
          print "</select> ";
        } else {
          print "<input type=hidden name=\"currency\" value=\"$smps::currency\">         Amount: $smps::currency ";
        }

        print "<INPUT TYPE=\"text\" NAME=\"card-amount\" SIZE=10 MAXLENGTH=10 value=\"$price\"> (eg. 1200.99)\n";
        if ( $smps::feature{'show_vt_receipt'} == 1 ) {
          print "<input type=\"hidden\" name=\"receipt_type\" value=\"simple\">\n";
        }
        print "<input type=\"submit\" name=\"submit\" value=\"Credit Customer\">\n";
        print "</form>\n";
        print "</p>\n";
      } else {
        my ( $stuff1, $stuff2, $now ) = &miscutils::gendatetime();
        if ( ( $smps::feature{'processor_switch'} eq "yes" ) && ( $times{'auth'} < $smps::switchtime ) ) {
          print "<p>\n";
          print "<h4>Issue credit using billing data on file.</h4>\n";
          print "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
          print "<input type=\"hidden\" name=\"username\" value=\"$smps::username\">\n";
          print "<input type=\"hidden\" name=\"accttype\" value=\"$accttype\">\n";
          print "<input type=\"hidden\" name=\"acct_code\" value=\"$acct_code\">\n";
          print "<input type=\"hidden\" name=\"acct_code4\" value=\"lnk$orderid\">\n";
          print "<input type=\"hidden\" name=\"function\" value=\"inputnew\">\n";
          print "<input type=\"hidden\" name=\"mode\" value=\"returnprev\">\n";
          print "<input type=\"hidden\" name=\"prevorderid\" value=\"$orderid\">\n";
          print "<input type=\"hidden\" name=\"merchant\" value=\"$smps::username\">";
          my (%selected);
          my $currency = substr( $price, 0, 3 );
          my $price = substr( $price, 4 );
          $selected{$currency} = " selected";

          if ( ( $smps::feature{'curr_allowed'} ne "" ) && ( $smps::processor eq "ncb" ) && ( $smps::feature{'procmulticurr'} == 1 ) ) {
            print "         Amount: <select name=\"currency\">\n";
            my @array = split( /\|/, $smps::feature{'curr_allowed'} );
            foreach my $entry (@array) {
              $entry =~ tr/A-Z/a-z/;
              $entry =~ s/[^a-z]//g;
              print "<option value=\"$entry\" $selected{$entry}>$entry</option>\n";
            }
            print "</select> ";
          } elsif ( ( $smps::feature{'curr_allowed'} ne "" ) && ( $smps::processor =~ /^(pago|atlantic|planetpay|testprocessor|fifththird|wirecard)$/ ) ) {
            print "         Amount: <select name=\"currency\">\n";
            my @array = split( /\|/, $smps::feature{'curr_allowed'} );
            foreach my $entry (@array) {
              $entry =~ tr/A-Z/a-z/;
              $entry =~ s/[^a-z]//g;
              print "<option value=\"$entry\" $selected{$entry}>$entry</option>\n";
            }
            print "</select> ";
          } else {
            print "<input type=hidden name=\"currency\" value=\"$smps::currency\">         Amount: $smps::currency ";
          }
          print "<INPUT TYPE=\"text\" NAME=\"card-amount\" SIZE=10 MAXLENGTH=10 value=\"$price\"> (eg. 1200.99)\n";
          if ( $smps::feature{'show_vt_receipt'} == 1 ) {
            print "<input type=\"hidden\" name=\"receipt_type\" value=\"simple\">\n";
          }
          print "<input type=\"submit\" name=\"submit\" value=\"Credit Customer\">\n";
          print "</form>\n";
          print "</p>\n";

        } else {
          my ( $currency, $amt ) = split( / /, $price );
          print "<p>\n";
          print "<h4>Mark Transaction as Return</h4>\n";
          print "<form method=\"post\" name=\"return\" action=\"$ENV{'SCRIPT_NAME'}\" id=\"doReturn\" onsubmit=\"return validateReturn('$price')\">\n";
          print "<input type=\"hidden\" name=\"accttype\" value=\"$accttype\">";
          if ( $smps::username =~ /^(restaurant|restaurant2)$/ ) {
            print "<b>Acct Code:</b> <input type=\"text\" size=\"12\" maxlength=\"25\" name=\"acct_code2\" value=\"$acct_code2\"><br>";
          }
          print "<input type=\"hidden\" name=\"originalTransactionAmount\" value=\"$amt\">";
          print "<input type=\"hidden\" name=\"acct_code\" value=\"$acct_code\">\n";
          print "<input type=\"hidden\" name=\"function\" value=\"return\">\n";
          print "<input type=\"hidden\" name=\"orderid\" value=\"$orderid\">\n";
          print "<input type=\"hidden\" name=\"currency\" value=\"$currency\">\n";
          my $shortcard2 = substr( $shortcard, 0, 4 ) . "**" . substr( $shortcard, -2, 2 );
          print "<input type=\"hidden\" name=\"shortcard\" value=\"$shortcard2\">\n";
          print "<input type=\"hidden\" name=\"merchant\" value=\"$smps::username\">";

          if ( $smps::processor eq "kwikpay" ) {
            print "<input type=\"hidden\" name=\"amount\" value=\"$price\">\n";
          } else {
            print "<b>Amount:</b> <input type=\"text\" class=\"adjustmentDialogAmount modifyFieldAmount\" name=\"amount\" value=\"$price\" size=10>\n";
            my ( $adjustmentFlag, $surchargeFlag, $feeFlag ) = getAdjustmentFlags();
            if ( &enabledInAdjustmentTable() && !$feeFlag ) {
              my $checked = ( $smps::feature{'returnAdjustmentCheckboxChecked'} ? 'checked' : '' );
              print "<span class=\"adjustmentCheckboxWrapper\"><input type=\"checkbox\" class=\"adjustmentCheckbox\" $checked \\> Check to add applicable fee</span>\n";
            }
          }
          if ( ( $smps::feature{'show_return_receipt'} == 1 ) || ( $smps::feature{'show_vt_receipt'} == 1 ) ) {
            print "<input type=\"hidden\" name=\"receipt_type\" value=\"simple\">\n";
          } elsif ( $smps::feature{'show_pos_return_receipt'} == 1 ) {
            print "<input type=\"hidden\" name=\"receipt_type\" value=\"pos_simple\">\n";
          }
          print "<input type=\"submit\" name=\"doReturnButton\" id=\"doReturnButton\" value=\"Do Return\">\n";
          if ( $smps::feature{'storeresults'} ne "" ) {
            print " <input type=\"checkbox\" name=\"returnresults\" value=\"yes\"> Enable Results Download\n";
          }
          print "</form>\n";
          print "</p>\n";
        }
      }
    } elsif ( ( ( ( $mark_flag == 1 ) && ( $settled_flag == 0 ) ) || ( ( $mark_ret_flag == 1 ) && ( $setlret_flag == 0 ) ) || ( $hold_flag == 1 ) )
      && ( $ENV{'SEC_LEVEL'} < 9 )
      && ( $transflags !~ /balance/i ) ) {
      print "<p>\n";
      print "<h4>Void Transaction (unmark)</h4>\n";
      print "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
      print "<input type=\"hidden\" name=\"accttype\" value=\"$accttype\">";
      print "<input type=\"hidden\" name=\"acct_code\" value=\"$acct_code\">";
      print "<input type=\"hidden\" name=\"function\" value=\"unmark\">\n";
      print "<input type=\"hidden\" name=\"txntype\" value=\"$txntypevoid\">\n";
      print "<input type=\"hidden\" name=\"orderid\" value=\"$orderid\">\n";
      print "<input type=\"hidden\" name=\"amount\" value=\"$price\">\n";
      print "<input type=\"hidden\" name=\"merchant\" value=\"$smps::username\">";

      if ( ( $smps::feature{'show_void_receipt'} == 1 ) || ( $smps::feature{'show_vt_receipt'} == 1 ) ) {
        print "<input type=\"hidden\" name=\"receipt_type\" value=\"simple\">\n";
      } elsif ( $smps::feature{'show_pos_void_receipt'} == 1 ) {
        print "<input type=\"hidden\" name=\"receipt_type\" value=\"pos_simple\">\n";
      }
      print "<input type=\"submit\" name=\"submit\" value=\"Void Transaction\">\n";
      print "</form>\n";
      print "</p>\n";

      if ( ( $transflags !~ /gift/ ) && ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) && ( $mark_flag == 1 ) && ( $settled_flag == 0 ) ) {
        $price = $txntype eq 'reauth' ? $reauthAmount : $price;
        print "<p>\n";
        print "<h4>Mark Transaction for Settlement</h4>\n";
        print "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
        print "<input type=\"hidden\" name=\"accttype\" value=\"$accttype\">";
        print "<input type=\"hidden\" name=\"acct_code\" value=\"$acct_code\">";
        print "<input type=\"hidden\" name=\"function\" value=\"mark\">\n";
        print "<input type=\"hidden\" name=\"orderid\" value=\"$orderid\">\n";
        print "<input type=\"hidden\" name=\"amount\" value=\"$price\">\n";
        print "<input type=\"hidden\" name=\"merchant\" value=\"$smps::username\">";
        print "<input type=\"submit\" name=\"submit\" value=\"Mark Transaction\">\n";
        print "</form>\n";
        print "</p>\n";
      }
    }
    if ( $smps::reseller !~ /^(paynisc|payntel|siipnisc|siiptel|teretail|elretail)$/ ) {
      my ( $adjustmentFlag, $surchargeFlag ) = getAdjustmentFlags();
      my $adjustmentCheckboxHTML = '';
      if ( &enabledInAdjustmentTable() && $surchargeFlag ) {
        my $checked = ( $smps::feature{'reauthAdjustmentCheckboxChecked'} ? 'checked' : '' );
        $adjustmentCheckboxHTML = sprintf("<span class=\"adjustmentCheckboxWrapper\"><input type=\"checkbox\" class=\"adjustmentCheckbox\" $checked \\> Check to add applicable fee</span>\n");
      }
      if ( ( $smps::processorObj->getReauthAllowed() )
        && ( ( $accttype eq "" ) || ( $accttype eq "credit" ) )
        && ( $mark_flag == 1 )
        && ( $settled_flag == 0 )
        && ( $reauth_flag == 1 )
        && ( $transflags !~ /balance/i ) ) {
        print "<p>\n";
        print "<h4>Reauthorize Transaction</h4>\n";
        print "<form method=\"post\" id=\"reauthorizeTransaction\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
        print "<input type=\"hidden\" name=\"username\" value=\"$smps::username\">";
        print "<input type=\"hidden\" name=\"accttype\" value=\"$accttype\">";
        print "<input type=\"hidden\" name=\"acct_code\" value=\"$acct_code\">";
        print "<input type=\"hidden\" name=\"function\" value=\"input\">\n";
        print "<input type=\"hidden\" name=\"type\" value=\"reauth\">\n";
        print "<input type=\"hidden\" name=\"orderid\" value=\"$orderid\">\n";
        print "<input type=\"hidden\" name=\"original_amount\" value=\"$price\">\n";
        print "<input type=\"hidden\" name=\"merchant\" value=\"$smps::username\">\n";
        print "<b>Amount:</b> <input type=\"text\" class=\"adjustmentDialogAmount modifyFieldAmount\" name=\"amount\" value=\"$price\" size=10>\n";
        print $adjustmentCheckboxHTML;
        print "<input type=\"submit\" id=\"reauthorizeTransactionButton\" value=\"Reauthorize Transaction\">\n";
        print "<br /><input type=\"checkbox\" name=\"markReauth\" value=\"yes\" checked> Check to mark reauthorization for settlement.\n";
        print "</form>\n";
        print "</p>\n";
      } elsif ( ( $smps::chkprocessor =~ /^(telecheckftf|telecheck)$/ )
        && ( $accttype =~ /checking|savings/ )
        && ( $mark_flag == 1 )
        && ( $settled_flag == 0 )
        && ( $reauth_flag == 1 )
        && ( $transflags !~ /balance/i ) ) {
        print "<p>\n";
        print "<h4>Reauthorize Transaction</h4>\n";
        print "<form method=\"post\" id=\"reauthorizeTransaction\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
        print "<input type=\"hidden\" name=\"username\" value=\"$smps::username\">";
        print "<input type=\"hidden\" name=\"accttype\" value=\"$accttype\">";
        print "<input type=\"hidden\" name=\"acct_code\" value=\"$acct_code\">";
        print "<input type=\"hidden\" name=\"function\" value=\"inputnew\">\n";
        print "<input type=\"hidden\" name=\"mode\" value=\"reauth\">\n";
        print "<input type=\"hidden\" name=\"orderID\" value=\"$orderid\">\n";
        print "<input type=\"hidden\" name=\"original_amount\" value=\"$price\">\n";
        print "<input type=\"hidden\" name=\"merchant\" value=\"$smps::username\">\n";
        print "<input type=\"hidden\" name=\"receipt_type\" value=\"simple\">\n";
        print "<b>Amount:</b> <input type=\"text\" class=\"adjustmentDialogAmount modifyFieldAmount\" name=\"card-amount\" value=\"$price\" size=10>\n";
        print $adjustmentCheckboxHTML;
        print "<input type=\"submit\" id=\"reauthorizeTransactionButton\" name=submit value=\"Reauthorize Transaction\">\n";
        print "<br /><input type=\"checkbox\" name=\"markReauth\" value=\"yes\" checked> Check to mark reauthorization for settlement.\n";
        print "</form>\n";
        print "</p>\n";
      }
    }
  }

  if ( ( $smps::feature{'ach_repre_limit'} ne "" ) && ( $accttype =~ /^(checking|savings)/ ) ) {
    if ( $refnumber eq "norepresent" ) {
      print "<h4>Enable Representment</h4>\n";
      print "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
      print "<input type=\"hidden\" name=\"function\" value=\"represent_disable\">\n";
      print "<input type=\"hidden\" name=\"accttype\" value=\"$accttype\">\n";
      print "<input type=\"hidden\" name=\"transdate\" value=\"$authdate\">\n";
      print "<input type=\"hidden\" name=\"settletimezone\" value=\"$smps::settletimezone\">\n";
      if ( $rep1 ne "" ) {
        print "<input type=\"hidden\" name=\"rep1\" value=\"$rep1\">\n";
      }
      if ( $rep2 ne "" ) {
        print "<input type=\"hidden\" name=\"rep2\" value=\"$rep2\">\n";
      }
      print "<input type=\"hidden\" name=\"orderid\" value=\"$orderid\">\n";
      print "<input type=\"hidden\" name=\"merchant\" value=\"$smps::username\">";
      print "<input type=\"submit\" name=\"submit\" value=\"Enable Representment\">\n";
      print "</form>\n";
      print "</p>\n";
    } else {
      print "<h4>Disable Representment</h4>\n";
      print "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
      print "<input type=\"hidden\" name=\"function\" value=\"represent_disable\">\n";
      print "<input type=\"hidden\" name=\"accttype\" value=\"$accttype\">\n";
      print "<input type=\"hidden\" name=\"transdate\" value=\"$authdate\">\n";
      print "<input type=\"hidden\" name=\"settletimezone\" value=\"$smps::settletimezone\">\n";
      if ( $rep1 ne "" ) {
        print "<input type=\"hidden\" name=\"rep1\" value=\"$rep1\">\n";
      }
      if ( $rep2 ne "" ) {
        print "<input type=\"hidden\" name=\"rep2\" value=\"$rep2\">\n";
      }
      print "<input type=\"hidden\" name=\"orderid\" value=\"$orderid\">\n";
      print "<input type=\"hidden\" name=\"merchant\" value=\"$smps::username\">";
      print "<input type=\"submit\" name=\"submit\" value=\"Disable Representment\">\n";
      print "</form>\n";
      print "</p>\n";
    }
  }

  if ( $smps::chkprocessor !~ /^(telecheck|telecheckftf)$/ ) {
    if ( ( $ENV{'SEC_LEVEL'} < 9 ) && ( $smps::feature{'rechargeflg'} ne "no" ) ) {
      print "<p>\n";
      print "<h4>Charge Customer using billing data on file.</h4>\n";
      print "<form method=\"post\" id=\"rechargeCustomer\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
      print "<input type=\"hidden\" name=\"username\" value=\"$smps::username\">\n";
      print "<input type=\"hidden\" name=\"accttype\" value=\"$accttype\">\n";
      print "<input type=\"hidden\" name=\"function\" value=\"inputnew\">\n";
      print "<input type=\"hidden\" name=\"mode\" value=\"authprev\">\n";
      print "<input type=\"hidden\" name=\"prevorderid\" value=\"$orderid\">\n";
      print "<input type=\"hidden\" name=\"merchant\" value=\"$smps::username\">\n";
      print "<input type=\"hidden\" name=\"cvv_ign\" value=\"yes\">\n";
      print "<input type=\"hidden\" name=\"fraudbuypass\" value=\"yes\">\n";
      my (%selected);
      my $currency = substr( $price, 0, 3 );
      my $price = substr( $price, 4 );
      $selected{$currency} = " selected";

      if ( ( $smps::feature{'curr_allowed'} ne "" ) && ( $smps::processor eq "ncb" ) && ( $smps::feature{'procmulticurr'} == 1 ) ) {
        print "         <b>Amount:</b> <select name=\"currency\">\n";
        my @array = split( /\|/, $smps::feature{'curr_allowed'} );
        foreach my $entry (@array) {
          $entry =~ tr/A-Z/a-z/;
          $entry =~ s/[^a-z]//g;
          print "<option value=\"$entry\" $selected{$entry}>$entry</option>\n";
        }
        print "</select> ";
      } elsif ( ( $smps::feature{'curr_allowed'} ne "" ) && ( $smps::processor =~ /^(pago|atlantic|planetpay|testprocessor|fifththird|wirecard)$/ ) ) {
        print "         <b>Amount:</b> <select name=\"currency\">\n";
        my @array = split( /\|/, $smps::feature{'curr_allowed'} );
        foreach my $entry (@array) {
          $entry =~ tr/A-Z/a-z/;
          $entry =~ s/[^a-z]//g;
          print "<option value=\"$entry\" $selected{$entry}>$entry</option>\n";
        }
        print "</select> ";
      } else {
        print "<input type=hidden name=\"currency\" value=\"$smps::currency\">\n";
        print "         <b>Amount:</b> $smps::currency ";
      }

      print "<INPUT TYPE=\"text\" NAME=\"card-amount\" id=\"rechargeCustomerAmount\" class=\"adjustmentDialogAmount\" SIZE=10 MAXLENGTH=10 value=\"$price\"> (eg. 1200.99)\n";

      if ( $accttype =~ /^(checking|savings)$/ ) {
        my %selected = ();
        $selected{$checktype} = " selected";
        print "<br><b>Check Type:</b> <select name=\"checktype\">\n";
        my @seccodes = $smps::gatewayAccount->getSECCodes();
        if ( @seccodes == 0 ) {
          @seccodes = ( 'CCD', 'PPD', 'WEB' );
        }
        foreach my $seccode (@seccodes) {
          print "<option value=\"$seccode\" $selected{$seccode}>$seccode</option>\n";
        }
        print "</select>\n";
      }

      if ( $smps::feature{'specify_ac'} == 1 ) {
        print "<br><b>Acct Code 1:</b> <input type=\"text\" name=\"acct_code\" value=\"$acct_code\" size=\"12\" maxlength=\"25\">\n";
        print "<br><b>Acct Code 2:</b> <input type=\"text\" name=\"acct_code2\" value=\"$acct_code2\" size=\"12\" maxlength=\"25\">\n";
      } else {
        print "<input type=\"hidden\" name=\"acct_code\" value=\"$acct_code\">\n";
        print "<input type=\"hidden\" name=\"acct_code2\" value=\"$acct_code2\">\n";
      }
      print "<br />\n";
      print "Receipt Type: <select name=\"receipt_type\">\n";
      print "  <option value=\"\">None</option>\n";
      print "  <option value=\"simple\">Standard Printer</option>\n";
      print "  <option value=\"pos_simple\">Receipt Printer</option>\n";
      print "</select>\n";

      # Get email address
      my $loader            = new PlugNPay::Transaction::Loader();
      my $loadedTransaction = $loader->load( { gatewayAccount => $smps::username, orderID => $orderid } );
      my $emailAddress      = ${$loadedTransaction}{$smps::username}{$orderid}{'transactionData'}{'billingContactInformation'}{'info'}{'emailAddresses'}{'main'};
      print "<br /><input type='checkbox' id='rechargeCustomerEmailCheckbox'> Check to email receipt to customer.\n";
      print "<br /><span id='rechargeCustomerEmailField'>Customer Email: <input type='text' name='email' value='$emailAddress'></span>\n";
      print "<br />\n";

      print
        "<input type=\"submit\" name=\"rechargeCustomerButton\" id=\"rechargeCustomerButton\" value=\"Recharge Customer\"> <input type=\"checkbox\" name=\"authtype\" value=\"authpostauth\" checked> Check to mark transaction for settlement.\n";
      print "</form>\n";
      print "</p>\n";
    }
  }
  if ( ( $amt{'postauth'} > 0 ) && ( $amt{'return'} > 0 ) && ( $amt{'postauth'} > ( $amt{'return'} - $amt{'void'} ) ) && ( $smps::feature{'allow_multret'} eq "1" ) ) {
    $acct_code4 .= ":lnk$orderid";
    print "<p>\n";
    print "<h4>Issue additional linked credits using billing data on file.</h4>\n";
    print "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
    print "<input type=\"hidden\" name=\"orderID\" value=\"$orderid\">\n";
    print "<input type=\"hidden\" name=\"username\" value=\"$smps::username\">\n";
    print "<input type=\"hidden\" name=\"accttype\" value=\"$accttype\">\n";
    print "<input type=\"hidden\" name=\"checktype\" value=\"$checktype\">\n";
    print "<input type=\"hidden\" name=\"acct_code\" value=\"$acct_code\">\n";
    print "<input type=\"hidden\" name=\"function\" value=\"inputnew\">\n";
    print "<input type=\"hidden\" name=\"mode\" value=\"return\">\n";    ### DCP 20120125  Changed from returnprev to return
    print "<input type=\"hidden\" name=\"merchant\" value=\"$smps::username\">\n";
    print "<input type=\"hidden\" name=\"lnkreturn\" value=\"$orderid\">\n";
    print "<input type=\"hidden\" name=\"acct_code4\" value=\"lnk$orderid\">\n";

    if ( $smps::feature{'multicurrency'} eq "1" ) {
      print "<input type=\"hidden\" name=\"transflags\" value=\"multicurrency\">\n";
    }

    my (%selected);
    my $currency = substr( $price, 0, 3 );
    my $price = sprintf( "%0.2f", $amt{'auth'} - $amt{'return'} );
    $selected{$currency} = " selected";
    if ( ( $smps::feature{'curr_allowed'} ne "" ) && ( $smps::processor eq "ncb" ) && ( $smps::feature{'procmulticurr'} == 1 ) ) {
      print "         Amount: <select name=\"currency\">\n";
      my @array = split( /\|/, $smps::feature{'curr_allowed'} );
      foreach my $entry (@array) {
        $entry =~ tr/A-Z/a-z/;
        $entry =~ s/[^a-z]//g;
        print "<option value=\"$entry\" $selected{$entry}>$entry</option>\n";
      }
      print "</select> ";
    } elsif ( ( $smps::feature{'curr_allowed'} ne "" ) && ( $smps::processor =~ /^(pago|atlantic|planetpay|testprocessor|fifththird|wirecard)$/ ) ) {
      print "         <b>Amount:</b> <select name=\"currency\">\n";
      my @array = split( /\|/, $smps::feature{'curr_allowed'} );
      foreach my $entry (@array) {
        $entry =~ tr/A-Z/a-z/;
        $entry =~ s/[^a-z]//g;
        print "<option value=\"$entry\" $selected{$entry}>$entry</option>\n";
      }
      print "</select> ";
    } else {
      print "<input type=hidden name=\"currency\" value=\"$smps::currency\">         Amount: $smps::currency ";
    }

    print "<INPUT TYPE=\"text\" NAME=\"card-amount\" SIZE=10 MAXLENGTH=10 value=\"\"> (eg. 1200.99)\n";

    print "<input type=\"submit\" name=\"submit\" value=\"Credit Customer\">\n";
    print "</form>\n";
    print "</p>\n";
  } elsif ( ( $smps::feature{'allow_returnprev'} eq "1" ) && ( $smps::noreturns ne "yes" ) ) {
    print "<p>\n";
    print "<h4>Issue credit using billing data on file.</h4>\n";
    print "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
    print "<input type=\"hidden\" name=\"username\" value=\"$smps::username\">\n";
    print "<input type=\"hidden\" name=\"accttype\" value=\"$accttype\">\n";
    print "<input type=\"hidden\" name=\"checktype\" value=\"$checktype\">\n";
    print "<input type=\"hidden\" name=\"acct_code\" value=\"$acct_code\">\n";
    print "<input type=\"hidden\" name=\"acct_code4\" value=\"lnk$orderid\">\n";
    print "<input type=\"hidden\" name=\"function\" value=\"inputnew\">\n";
    print "<input type=\"hidden\" name=\"mode\" value=\"returnprev\">\n";
    print "<input type=\"hidden\" name=\"prevorderid\" value=\"$orderid\">\n";
    print "<input type=\"hidden\" name=\"merchant\" value=\"$smps::username\">";
    my (%selected);
    my $currency = substr( $price, 0, 3 );
    my $price = substr( $price, 4 );
    $selected{$currency} = " selected";

    if ( ( $smps::feature{'curr_allowed'} ne "" ) && ( $smps::processor eq "ncb" ) && ( $smps::feature{'procmulticurr'} == 1 ) ) {
      print "         Amount: <select name=\"currency\">\n";
      my @array = split( /\|/, $smps::feature{'curr_allowed'} );
      foreach my $entry (@array) {
        $entry =~ tr/A-Z/a-z/;
        $entry =~ s/[^a-z]//g;
        print "<option value=\"$entry\" $selected{$entry}>$entry</option>\n";
      }
      print "</select> ";
    } elsif ( ( $smps::feature{'curr_allowed'} ne "" ) && ( $smps::processor =~ /^(pago|atlantic|planetpay|testprocessor|fifththird|wirecard)$/ ) ) {
      print "         Amount: <select name=\"currency\">\n";
      my @array = split( /\|/, $smps::feature{'curr_allowed'} );
      foreach my $entry (@array) {
        $entry =~ tr/A-Z/a-z/;
        $entry =~ s/[^a-z]//g;
        print "<option value=\"$entry\" $selected{$entry}>$entry</option>\n";
      }
      print "</select> ";
    } else {
      print "<input type=hidden name=\"currency\" value=\"$smps::currency\">         Amount: $smps::currency ";
    }

    print "<INPUT TYPE=\"text\" NAME=\"card-amount\" SIZE=10 MAXLENGTH=10 value=\"$price\"> (eg. 1200.99)\n";
    if ( $smps::feature{'show_vt_receipt'} == 1 ) {
      print "<input type=\"hidden\" name=\"receipt_type\" value=\"simple\">\n";
    }
    print "<input type=\"submit\" name=\"submit\" value=\"Credit Customer\">\n";
    print "</form>\n";
    print "</p>\n";
  }
}

sub checkTransCountsAsSettled {
  my $arguments = shift || {};
  my $validACHProcs = ['alliance','alliancesp','globaletel','securenetach','tpayments','gms'];
  my $validCardProcs = ['globalc','pago','newtek','wirecard','payvision'];
  if ($arguments->{'transType'} ne 'auth') {
    return 0;
  }

  if ($arguments->{'status'} ne 'success') {
    return 0;
  }

  if ($arguments->{'industryCode'} eq 'petroleum') {
    return 0;
  }

  my $achPass = inArray($arguments->{'achProcessor'},$validACHProcs) && $arguments->{'accountType'} eq 'checking' && $arguments->{'transFlags'} !~ /authonly/;
  my $cardPass = inArray($arguments->{'cardProcessor'},$validCardProcs) && $arguments->{'transFlags'} =~ /capture/;
  my $capturePass = $arguments->{'authType'} eq 'authcapture' && $arguments->{'accountType'} ne 'checking';

  return $capturePass || $cardPass || $achPass;
}

sub unmark {
  my $amount     = $smps::query->param('amount');
  my $orderid    = $smps::query->param('orderid');
  my $txntype    = $smps::query->param('txntype');
  my $accttype   = $smps::query->param('accttype');
  my $acct_code4 = "Virtual Terminal";
  my $transflags = $smps::query->param('transflags');

  my %query  = ();
  my @params = $smps::query->param;
  foreach my $param (@params) {
    $query{$param} = $smps::query->param($param);
  }

  my ( $currency, $amt, @garbage ) = split( '\ +', $amount );
  $currency =~ s/[^a-zA-Z]//g;
  $currency = substr( $currency, 0, 3 );
  $amt =~ s/[^0-9\.]//g;
  $amount = "$currency $amt";

  my %result = &miscutils::sendmserver( "$smps::username", 'void', 'accttype', "$accttype", 'txn-type', "$txntype", 'amount', "$amount", 'acct_code4', $acct_code4, 'order-id', "$orderid",
    'transflags', "$transflags" );

  if ( $result{'FinalStatus'} =~ /success/ ) {
    if ( ( $smps::accountFeatures->get('convfee') ) || ( $smps::accountFeatures->get('cardcharge') ) ) {
      my %resultCF = &convfee_admin( 'void', $orderid, $accttype, $amount, $currency, $acct_code4 );
      if ( $resultCF{'FinalStatus'} =~ /^success|problem$/ ) {
        $result{'FinalStatusCF'} = $resultCF{'FinalStatus'};
        $result{'MErrMsgCF'}     = $resultCF{'MErrMsg'};
      }
    }
  }

  # receipt_type is only set in trans admin for the following feature settings/values:
  #   show_pos_void_receipt=1
  #   show_vt_receipt=1
  #   show_void_receipt=1
  if ( ( $result{'FinalStatus'} =~ /success|pending/ )
    && ( ( $query{'receipt_type'} =~ /simple|itemized|pos_simple|pos_itemized/i ) || ( $query{'receipt-type'} =~ /simple|itemized|pos_simple|pos_itemized/i ) ) ) {
    require mckutils_strict;

    $query{'receipt-company'}  = $smps::company;
    $query{'receipt-address1'} = $smps::addr1;
    $query{'receipt-address2'} = $smps::addr2;
    $query{'receipt-city'}     = $smps::city;
    $query{'receipt-state'}    = $smps::state;
    $query{'receipt-zip'}      = $smps::zip;
    $query{'receipt-country'}  = $smps::country;
    $query{'receipt-phone'}    = $smps::tel;

    $query{'orderID'} = $orderid;

    if ( $amount =~ /^([a-zA-Z]{3} \d+)/ ) {
      ( $query{'currency'}, $query{'card-amount'} ) = split( " ", $amount, 2 );
    } else {
      $query{'card-amount'} = $amount;
    }

    if ( $smps::feature{'pubemail'} =~ /\w/ ) {
      $query{'publisher-email'} = $smps::feature{'pubemail'};
    }

    my $dbh = &miscutils::dbhconnect( "pnpdata", "", "$smps::username" );    ## Trans_Log
    my $sth = $dbh->prepare(
      qq{
        select card_name,card_addr,card_city,card_state,card_zip,card_country,card_number,card_exp
        from trans_log
        where orderid=? and username=?
      }
      )
      or die "Can't do: $DBI::errstr";
    $sth->execute( "$orderid", "$smps::username" ) or die "Can't execute: $DBI::errstr";
    ( $query{'card-name'}, $query{'card-address1'}, $query{'card-city'}, $query{'card-state'}, $query{'card-zip'}, $query{'card-country'}, $query{'card-number'}, $query{'card-exp'} ) = $sth->fetchrow;
    $sth->finish;
    $dbh->disconnect;

    foreach my $key ( sort keys %query ) {
      if ( ( $query{$key} ne "" ) && ( $result{$key} eq "" ) ) {
        $result{$key} = $query{$key};
      }
    }

    my $template_data  = '';                                         # clear and initialize value for holding void template data
    my $template_table = &void_table_template(%result);    # create product table data & amount voided

    # Load, Fill-In & Display Return Template
    my @todays_date = gmtime(time);
    $result{'order-date'} = sprintf( "%02d/%02d/%04d", $todays_date[4] + 1, $todays_date[3], $todays_date[5] + 1900 );

    if ( $result{'card-number'} =~ /^(\d+\*\*\d+)$/ ) {
      $result{'filteredCC'} = $result{'card-number'};
    } else {
      $result{'card-number'} =~ s/[^0-9]//g;
      $result{'card-number'} = substr( $result{'card-number'}, 0, 20 );
      my ($cardnumber) = $result{'card-number'};
      my $cclength = length($cardnumber);
      my $last4 = substr( $cardnumber, -4, 4 );
      $cardnumber =~ s/./X/g;
      $result{'filteredCC'}  = substr( $cardnumber, 0, $cclength - 4 ) . $last4;
      $result{'card-number'} = substr( $cardnumber, 0, $cclength - 4 ) . $last4;
    }

    # load/display template for receipt
    my @array   = %query;
    my $payment = mckutils->new(@array);
    %mckutils::feature = %smps::feature;
    %mckutils::result  = %result;
    %mckutils::query   = %query;

    $mckutils::query{'publisher-name'} = $smps::username;
    $mckutils::query{'mode'}           = "void";

    # the only part of final relevant for a void
    my $receipt = mckutils::receipt({
      ruleIds => ['7.1'] # virtualterm/thankyou/<username>_<mode>.htm template
    });
    if ($receipt) {
      mckutils::displayHtml($receipt);
      return;
    } elsif ( $smps::query{'receipt_type'} =~ /^pos_/i || $smps::query{'receipt-type'} =~ /^pos_/i ) {
      $template_data = &pos_void_template(%result);
    } else {
      $template_data = &void_template(%result);
    }
    $template_data =~ s/\[pnp_([a-zA-Z0-9\-\_]*)\]/$result{$1}/g;
    $template_data =~ s/\[TABLE\]/$template_table/g;
    &mckutils::genhtml( undef, $template_data );
    return;
  } else {
    if ( $result{'FinalStatus'} eq "success" ) {
      print "<h3>$orderid has been successfully voided</h3>\n";
      if ( exists $result{'FinalStatusCF'} ) {
        if ( $result{'FinalStatusCF'} =~ /pending|success/ ) {
          print "<h4>Your Void of the Fee Portion of this transaction was successful.</h4>\n";
        } else {
          print "<h4>Your Void of the Fee Portion of this transaction failed:</h4>\n";
          print "Reason: $result{'MErrMsgCF'}<br>\n";
        }
      }
    } else {
      print %result;
      print "<br>\n";
    }
  }
}

sub void_template {
  my (%query) = @_;

  my $template_data = "";

  $template_data .= "\n";
  $template_data .= "<div align=left><table border=0 width=590>\n";
  $template_data .= "  <tr>\n";
  $template_data .= "    <td align=left>\n";
  $template_data .= "      <table border=0 width=100%>\n";
  $template_data .= "        <tr>\n";
  $template_data .= "          <td align=center valign=top colspan=2>\n";
  $template_data .= "            <font size=+1><b>Void Receipt</b></font>\n";
  $template_data .= "            <br>Please print or save this as your receipt.\n";
  $template_data .= "            <br>&nbsp;</td>\n";
  $template_data .= "        </tr>\n";
  $template_data .= "        <tr>\n";
  $template_data .= "          <td align=left valign=top colspan=2>\n";
  $template_data .=
    "            <blockquote>If you have a problem with this void, please email us at <a href=\"mailto:[pnp_publisher-email]\">[pnp_publisher-email]</a>. Please give your full name, order ID number, and the exact nature of the problem.</blockquote>\n";
  $template_data .= "\n";
  $template_data .= "            <p><b>Order Date: [pnp_order-date]</b>\n";
  $template_data .= "            <br><b>Order ID: [pnp_orderID]</b>\n";

  if ( $query{'order-id'} ne "" ) {
    $template_data .= "            <br><b>Merchant ID: [pnp_order-id]</b>\n";
  }
  $template_data .= "          </td>\n";
  $template_data .= "        </tr>\n";
  $template_data .= "        <tr>\n";
  $template_data .= "         <td colspan=2><hr>\n";
  if ( $query{'paymethod'} eq "onlinecheck" ) {
    $template_data .= "            <p><b>Routing #:</b> [pnp_filteredRN]\n";
    $template_data .= "            <br><b>Account #:</b> [pnp_filteredAN]\n";
  } else {
    $template_data .= "            <p><b>Card #:</b> [pnp_filteredCC]\n";
    $template_data .= "            <br><b>Card Exp:</b> [pnp_card-exp]\n";
  }
  $template_data .= "            <br><table border=0 cellpadding=0 cellspacing=0 width=100%>\n";
  $template_data .= "              <tr align=right>\n";
  $template_data .= "                <td align=left colspan=2>[TABLE]</td>\n";
  $template_data .= "              </tr>\n";
  $template_data .= "              </table><hr>\n";
  $template_data .= "              <table border=0 width=100% cellpadding=0 cellspacing=0>\n";
  $template_data .= "                <tr>\n";
  $template_data .= "                  <td valign=top colspan=2>\n";
  $template_data .= "                    <table border=0 cellpadding=1 cellspacing=0 width=100%>\n";
  $template_data .= "                      <tr>\n";
  $template_data .= "                        <td colspan=2><b><u>Card Holder Information:</u></b><br>\n";
  $template_data .= "                        <td align=left>\n";
  $template_data .= "                      </tr>\n";
  $template_data .= "                      <tr>\n";
  $template_data .= "                        <td align=right>Name: </td>\n";
  $template_data .= "                        <td align=left> [pnp_card-name] </td>\n";
  $template_data .= "                      </tr>\n";

  if ( $query{'card-company'} ne "" ) {
    $template_data .= "                      <tr>\n";
    $template_data .= "                        <td align=right valign=top>Company: </td>\n";
    $template_data .= "                        <td align=left> [pnp_card-company] </td>\n";
    $template_data .= "                      </tr>\n";
  }
  $template_data .= "                      <tr>\n";
  $template_data .= "                        <td align=right valign=top>Address: </td>\n";
  $template_data .= "                        <td align=left> [pnp_card-address1] </td>\n";
  $template_data .= "                      </tr>\n";
  if ( $query{'address2'} ne "" ) {
    $template_data .= "                      <tr>\n";
    $template_data .= "                        <td align=left></td>\n";
    $template_data .= "                        <td align=left> [pnp_card-address2] </td>\n";
    $template_data .= "                      </tr>\n";
  }
  $template_data .= "                      <tr>\n";
  $template_data .= "                        <td align=left></td>\n";
  $template_data .= "                        <td align=left><nobr> [pnp_card-city], [pnp_card-prov] </nobr></td>\n";
  $template_data .= "                      </tr>\n";
  $template_data .= "                      <tr>\n";
  $template_data .= "                        <td align=left></td>\n";
  $template_data .= "                        <td align=left><nobr> [pnp_card-state] [pnp_card-zip] [pnp_card-country] </nobr></td>\n";
  $template_data .= "                      </tr>\n";

  if ( $query{'phone'} ne "" ) {
    $template_data .= "                      <tr>\n";
    $template_data .= "                        <td align=right>Phone: </td>\n";
    $template_data .= "                        <td align=left> [pnp_phone] </td>\n";
    $template_data .= "                      </tr>\n";
  }
  if ( $query{'fax'} ne "" ) {
    $template_data .= "                      <tr>\n";
    $template_data .= "                        <td align=right>Fax: </td>\n";
    $template_data .= "                        <td align=left> [pnp_fax] </td>\n";
    $template_data .= "                      </tr>\n";
  }
  if ( $query{'email'} ne "" ) {
    $template_data .= "                      <tr>\n";
    $template_data .= "                        <td align=right>Email: </td>\n";
    $template_data .= "                        <td align=left> [pnp_email] </a></td>\n";
    $template_data .= "                      </tr>\n";
  }
  $template_data .= "                    </table>\n";
  $template_data .= "                  </td>\n";
  $template_data .= "                </tr>\n";
  $template_data .= "              </table>\n";
  $template_data .= "              </td>\n";
  $template_data .= "            </tr>\n";
  $template_data .= "          </table>\n";
  $template_data .= "          </td>\n";
  $template_data .= "        </tr>\n";

  if ( $query{'acct_code'} ne "" ) {
    $template_data .= "        <tr>\n";
    $template_data .= "          <td colspan=\"2\">Acct Code: &nbsp; [pnp_acct_code]</td>\n";
    $template_data .= "        </tr>\n";
  }
  if ( $query{'acct_code2'} ne "" ) {
    $template_data .= "        <tr>\n";
    $template_data .= "          <td colspan=\"2\">Acct Code2: &nbsp; [pnp_acct_code2]</td>\n";
    $template_data .= "        </tr>\n";
  }
  if ( $query{'acct_code3'} ne "" ) {
    $template_data .= "        <tr>\n";
    $template_data .= "          <td colspan=\"2\">Acct Code3: &nbsp; [pnp_acct_code3]</td>\n";
    $template_data .= "        </tr>\n";
  }
  if ( $query{'acct_code4'} ne "" ) {
    $template_data .= "        <tr>\n";
    $template_data .= "          <td colspan=\"2\">Acct Code4: &nbsp; [pnp_acct_code4]</td>\n";
    $template_data .= "        </tr>\n";
  }

  $template_data .= "      </table>\n";
  $template_data .= "      </div>\n";
  $template_data .= "    </td>\n";
  $template_data .= "  </tr>\n";
  $template_data .= "</table>\n";

  $template_data .= "<p><form><input type=\"button\" name=\"print_button\" value=\"Print Page\" onclick=\"window.print();\"></form>\n";

  if ( $query{'receipt_link'} ne "" ) {
    $template_data .= "<p>To continue shopping, <a href=\"$query{'receipt_link'}\">CLICK HERE</a>.\n";
  } elsif ( $query{'receipt-link'} ne "" ) {
    $template_data .= "<p>To continue shopping, <a href=\"$query{'receipt-link'}\">CLICK HERE</a>.\n";
  }
  $template_data .= "</div>\n";

  return $template_data;
}

sub pos_void_template {
  my (%query) = @_;

  my $template_data = "";

  $template_data .= "<font size=+1><b>Void Receipt</b></font>\n";

  if ( $query{'receipt-company'} ne "" ) {
    $template_data .= "<p><font size=+1><b>[pnp_receipt-company]</b></font>\n";
  }
  if ( $query{'receipt-address1'} ne "" ) {
    $template_data .= "<br><font size=+1>[pnp_receipt-address1]</font>\n";
  }
  if ( $query{'receipt-address2'} ne "" ) {
    $template_data .= "<br><font size=+1>[pnp_receipt-address2]</font>\n";
  }
  if ( $query{'receipt-city'} ne "" ) {
    $template_data .= "<br><font size=+1>[pnp_receipt-city], [pnp_receipt-state] [pnp_receipt-zip] [pnp_receipt-country]</font>\n";
  }
  $template_data .= "<br>&nbsp;\n";
  if ( $query{'receipt-phone'} ne "" ) {
    $template_data .= "<br><font size=-1>Phone: [pnp_receipt-phone]</font>\n";
  }
  if ( $query{'receipt-fax'} ne "" ) {
    $template_data .= "<br><font size=-1>Fax: [pnp_receipt-fax]</font>\n";
  }
  if ( $query{'receipt-email'} ne "" ) {
    $template_data .= "<br><font size=-1>Email: [pnp_receipt-email]</font>\n";
  }
  if ( $query{'receipt-url'} ne "" ) {
    $template_data .= "<br><font size=-1>[pnp_receipt-url]</font>\n";
  }
  $template_data .= "</div>\n";

  $template_data .= "<p><b>Order Date:</b> [pnp_order-date]\n";
  $template_data .= "<br><b>Order ID:</b> [pnp_orderID]\n";
  if ( $query{'order-id'} ne "" ) {
    $template_data .= "<br><b>Merchant ID:</b> [pnp_order-id]\n";
  }

  $template_data .= "<p><hr>\n";

  if ( $query{'paymethod'} eq "onlinecheck" ) {
    $template_data .= "<p><b>Routing #:</b> [pnp_filteredRN]\n";
    $template_data .= "<br><b>Account #:</b> [pnp_filteredAN]\n";
  } else {
    $template_data .= "<p><b>Card #:</b> [pnp_card-number]\n";
    $template_data .= "<br><b>Card Exp:</b> [pnp_card-exp]\n";
  }
  $template_data .= "<br>[TABLE]\n";

  $template_data .= "<p><hr>\n";
  $template_data .= "<br><b><u>Card Holder Information:</u></b>\n";
  $template_data .= "<br>[pnp_card-name]\n";
  $template_data .= "<br>[pnp_card-address1]\n";
  if ( $query{'card-address2'} ne "" ) {
    $template_data .= "<br>[pnp_card-address2]\n";
  }
  $template_data .= "<br>[pnp_card-city],\n";
  $template_data .= "<br>[pnp_card-state] [pnp_card-zip] [pnp_card-country]\n";

  if ( $query{'phone'} ne "" ) {
    $template_data .= "<p>Phone: [pnp_phone]\n";
  }
  if ( $query{'fax'} ne "" ) {
    $template_data .= "<br>Fax: [pnp_fax]\n";
  }
  if ( $query{'email'} ne "" ) {
    $template_data .= "<br>Email: [pnp_email]\n";
  }

  $template_data .= "<br>&nbsp;\n";

  # add print button
  $template_data .= "<script language=\"JavaScript\"><!--\n";
  $template_data .= "if (document.layers && (self.innerHeight == 0 && self.innerWidth == 0)) {\n";
  $template_data .= "     // printing\n";
  $template_data .= "}\n";
  $template_data .= "else {\n";
  $template_data .= "    document.write('<form><input type=\"button\" value=\"Print Receipt\" onClick=\"window.print();\"><\/form>');\n";
  $template_data .= "}\n";
  $template_data .= "//--></script>\n";

  if ( $query{'receipt_link'} ne "" ) {
    $template_data .= "<p>To return to site, <a href=\"$query{'receipt_link'}\">CLICK HERE</a>.\n";
  } elsif ( $query{'receipt-link'} ne "" ) {
    $template_data .= "<p>To return to site, <a href=\"$query{'receipt-link'}\">CLICK HERE</a>.\n";
  }
  $template_data .= "</div>\n";

  return $template_data;
}

sub void_table_template {
  my (%query) = @_;
  my $template_table = "";

  $query{'card-amount'} = sprintf( "%.2f", $query{'card-amount'} );
  $template_table .= "<br><b>Void Total:</b> $query{'currency_symbol'}$query{'card-amount'}\n";

  return $template_table;
}

sub return {
  my $orderid    = $smps::query->param('orderid');
  my $amount     = $smps::query->param('amount');
  my $shortcard  = $smps::query->param('shortcard');
  my $accttype   = $smps::query->param('accttype');
  my $acct_code2 = $smps::query->param('acct_code2');
  my $acct_code4 = "Virtual Terminal";
  my $currency   = $smps::query->param('currency');

  my ($amt);
  if ( $currency !~ /[a-zA-Z]{3}/ ) {
    my @garbage = ();
    ( $currency, @garbage ) = split( '\ +', $amount );
    $currency =~ s/[^a-zA-Z]//g;
    $currency = substr( $currency, 0, 3 );
  }

  if ( $ENV{'SEC_LEVEL'} >= 8 ) {
    my $message = "Your current security level is not cleared for this operation. <p>Please contact Technical Support if you believe this to be in error. ";
    &response_page($message);
  }

  my %query  = ();
  my @params = $smps::query->param;
  foreach my $param (@params) {
    $query{$param} = $smps::query->param($param);
  }

  $amount =~ s/[^0-9\.]//g;
  $amt = $amount;

  $currency =~ s/[^a-zA-Z]//g;
  $currency = substr( $currency, 0, 3 );

  ## Normalize Decimal Place based on currency
  my $currencyObj = new PlugNPay::Currency($currency);
  $amt = $currencyObj->format( $amt, { digitSeparator => '' } );

  $amount = "$currency $amt";

  if ( $amount !~ /[a-zA-Z]{3} [0-9\.]/ ) {
    my $message = "<h3>Your Return for -\$$amount failed</h3><br>\n";
    $message .= "Reason: Currency of transaction is missing.  Please contact tech support.<br>\n";
    &response_page($message);
    return;
  }

  my %result = ();
  %result = &miscutils::sendmserver( "$smps::username", 'return', 'accttype', "$accttype", 'amount', "$amount", 'order-id', "$orderid", 'acct_code4', $acct_code4, 'acct_code2', "$acct_code2" );

  ###  Conv. Fee Return
  if ( $result{'FinalStatus'} =~ /success|pending/ ) {
    if ( ( $smps::accountFeatures->get('returnfee') ) && ( ( $smps::accountFeatures->get('convfee') ) || ( $smps::accountFeatures->get('cardcharge') ) ) ) {
      my %resultCF = &convfee_admin( 'return', $orderid, $accttype, $amount, $currency, $acct_code4 );
      if ( $resultCF{'FinalStatus'} =~ /^success|problem$/ ) {
        $result{'FinalStatusCF'} = $resultCF{'FinalStatus'};
        $result{'MErrMsgCF'}     = $resultCF{'MErrMsg'};
      }
    }
  }

  my ($onload);
  if ( ( $smps::feature{'storeresults'} ne "" ) && ( $smps::query->param('returnresults') eq "yes" ) ) {
    $onload = &storeresults( 'return', %result );
  }

  # receipt_type is only set in trans admin for the following feature settings/values:
  #   show_vt_receipt=1
  #   show_return_receipt=1
  #   show_pos_return_receipt=1
  if ( ( $result{'FinalStatus'} =~ /success|pending/ )
    && ( ( $query{'receipt_type'} =~ /simple|itemized|pos_simple|pos_itemized/i ) || ( $query{'receipt-type'} =~ /simple|itemized|pos_simple|pos_itemized/i ) ) ) {
    require mckutils_strict;

    $query{'receipt-company'}  = $smps::company;
    $query{'receipt-address1'} = $smps::addr1;
    $query{'receipt-address2'} = $smps::addr2;
    $query{'receipt-city'}     = $smps::city;
    $query{'receipt-state'}    = $smps::state;
    $query{'receipt-zip'}      = $smps::zip;
    $query{'receipt-country'}  = $smps::country;
    $query{'receipt-phone'}    = $smps::tel;

    $query{'orderID'} = $result{'orderid'};

    if ( $amount =~ /^([a-zA-Z]{3} \d+)/ ) {
      ( $query{'currency'}, $query{'card-amount'} ) = split( " ", $amount, 2 );
    } else {
      $query{'card-amount'} = $amount;
    }

    if ( $smps::feature{'pubemail'} =~ /\w/ ) {
      $query{'publisher-email'} = $smps::feature{'pubemail'};
    }

    my $dbh = &miscutils::dbhconnect( "pnpdata", "", "$smps::username" );    ## Trans_Log
    my $sth = $dbh->prepare(
      qq{
        select card_name,card_addr,card_city,card_state,card_zip,card_country,card_number,card_exp
        from trans_log
        where orderid=? and username=?
      }
      )
      or die "Can't do: $DBI::errstr";
    $sth->execute( "$orderid", "$smps::username" ) or die "Can't execute: $DBI::errstr";
    ( $query{'card-name'}, $query{'card-address1'}, $query{'card-city'}, $query{'card-state'}, $query{'card-zip'}, $query{'card-country'}, $query{'card-number'}, $query{'card-exp'} ) = $sth->fetchrow;
    $sth->finish;
    $dbh->disconnect;

    foreach my $key ( sort keys %query ) {
      if ( ( $query{$key} ne "" ) && ( $result{$key} eq "" ) ) {
        $result{$key} = $query{$key};
      }
    }

    my $template_data  = "";                                           # clear and initialize value for holding return template data
    my $template_table = &return_table_template(%result);    # create product table data & amount returned

    # Load, Fill-In & Display Return Template
    my @todays_date = gmtime(time);
    $result{'order-date'} = sprintf( "%02d/%02d/%04d", $todays_date[4] + 1, $todays_date[3], $todays_date[5] + 1900 );

    if ( $result{'card-number'} =~ /^(\d+\*\*\d+)$/ ) {
      $result{'filteredCC'} = $result{'card-number'};
    } else {
      $result{'card-number'} =~ s/[^0-9]//g;
      $result{'card-number'} = substr( $result{'card-number'}, 0, 20 );
      my ($cardnumber) = $result{'card-number'};
      my $cclength = length($cardnumber);
      my $last4 = substr( $cardnumber, -4, 4 );
      $cardnumber =~ s/./X/g;
      $result{'filteredCC'}  = substr( $cardnumber, 0, $cclength - 4 ) . $last4;
      $result{'card-number'} = substr( $cardnumber, 0, $cclength - 4 ) . $last4;
    }

    # load/display template for receipt
    my @array   = %query;
    my $payment = mckutils->new(@array);
    %mckutils::feature = %smps::feature;
    %mckutils::result  = %result;
    %mckutils::query   = %query;

    $mckutils::query{'publisher-name'} = $smps::username;
    $mckutils::query{'mode'}           = "return";

    # the only part of final relevant for a return
    my $receipt = mckutils::receipt({
      ruleIds => ['7.1'] # virtualterm/thankyou/<username>_<mode>.htm template
    });
    if ($receipt) {
      mckutils::displayHtml($receipt);
      return;
    } elsif ( $smps::query{'receipt_type'} =~ /^pos_/i || $smps::query{'receipt-type'} =~ /^pos_/i ) {
      $template_data = &pos_return_template(%result);
    } else {
      $template_data = &return_template(%result);
    }
    $template_data =~ s/\[pnp_([a-zA-Z0-9\-\_]*)\]/$result{$1}/g;
    $template_data =~ s/\[TABLE\]/$template_table/g;
    &mckutils::genhtml( undef, $template_data );
    return;
  } else {
    &head( 'Transaction Results', "$onload" );

    if ( $result{'FinalStatus'} eq "success" ) {
      print "<h3>Your Return for -\$$amount was successful.</h3><br>\n";
      print "<h3>Credit Card #: $shortcard</h3><br>\n";
    } elsif ( $result{'FinalStatus'} eq "pending" ) {
      print "<h4>Your Return for -\$$amount has been inserted into the batch database.</h4><br>\n";
      print "<h4>The order ID is: $orderid</h4>\n";
      print "<h4>Credit Card # is: $shortcard</h4>\n";
    } else {
      print "<h4>Your Return for -\$$amount failed</h4><br>\n";
      print "<h4>The order ID is: $orderid</h4>\n";
      print "<h4>Credit Card # is: $shortcard</h4>\n";
      print "Reason: $result{'MErrLoc'} $result{'MErrMsg'} $result{'aux-msg'}";
      print "<br>\n";
    }
    if ( exists $result{'FinalStatusCF'} ) {
      if ( $result{'FinalStatusCF'} =~ /pending|success/ ) {
        print "<h4>Your Return of the Fee Portion of this transaction was successful.</h4>\n";
      } else {
        print "<h4>Your Return of the Fee Portion of this transaction failed:</h4>\n";
        print "Reason: $result{'MErrMsgCF'}<br>\n";
      }
    }

    print "</div>\n";
    print "</body>\n";
    print "</html>\n";
  }
}

sub return_table_template {
  my (%query) = @_;
  my $template_table = "";

  $query{'card-amount'} = sprintf( "%.2f", $query{'card-amount'} );
  $template_table .= "<br><b>Return Total:</b> $query{'currency_symbol'}$query{'card-amount'}\n";

  return $template_table;
}

sub return_template {
  my (%query) = @_;

  my $template_data = "";

  $template_data .= "\n";
  $template_data .= "<div align=left><table border=0 width=590>\n";
  $template_data .= "  <tr>\n";
  $template_data .= "    <td align=left>\n";
  $template_data .= "      <table border=0 width=100%>\n";
  $template_data .= "        <tr>\n";
  $template_data .= "          <td align=center valign=top colspan=2>\n";
  $template_data .= "            <font size=+1><b>Return Receipt</b></font>\n";
  $template_data .= "            <br>Please print or save this as your receipt.\n";
  $template_data .= "            <br>&nbsp;</td>\n";
  $template_data .= "        </tr>\n";
  $template_data .= "        <tr>\n";
  $template_data .= "          <td align=left valign=top colspan=2>\n";
  $template_data .=
    "            <blockquote>If you have a problem with this return, please email us at <a href=\"mailto:[pnp_publisher-email]\">[pnp_publisher-email]</a>. Please give your full name, order ID number, and the exact nature of the problem.</blockquote>\n";
  $template_data .= "\n";
  $template_data .= "            <p><b>Order Date: [pnp_order-date]</b>\n";
  $template_data .= "            <br><b>Order ID: [pnp_orderID]</b>\n";

  if ( $query{'order-id'} ne "" ) {
    $template_data .= "            <br><b>Merchant ID: [pnp_order-id]</b>\n";
  }
  $template_data .= "          </td>\n";
  $template_data .= "        </tr>\n";
  $template_data .= "        <tr>\n";
  $template_data .= "         <td colspan=2><hr>\n";
  if ( $query{'paymethod'} eq "onlinecheck" ) {
    $template_data .= "            <p><b>Routing #:</b> [pnp_filteredRN]\n";
    $template_data .= "            <br><b>Account #:</b> [pnp_filteredAN]\n";
  } else {
    $template_data .= "            <p><b>Card #:</b> [pnp_filteredCC]\n";
    $template_data .= "            <br><b>Card Exp:</b> [pnp_card-exp]\n";
  }
  $template_data .= "            <br><table border=0 cellpadding=0 cellspacing=0 width=100%>\n";
  $template_data .= "              <tr align=right>\n";
  $template_data .= "                <td align=left colspan=2>[TABLE]</td>\n";
  $template_data .= "              </tr>\n";
  $template_data .= "              </table><hr>\n";
  $template_data .= "              <table border=0 width=100% cellpadding=0 cellspacing=0>\n";
  $template_data .= "                <tr>\n";
  $template_data .= "                  <td valign=top colspan=2>\n";
  $template_data .= "                    <table border=0 cellpadding=1 cellspacing=0 width=100%>\n";
  $template_data .= "                      <tr>\n";
  $template_data .= "                        <td colspan=2><b><u>Card Holder Information:</u></b><br>\n";
  $template_data .= "                        <td align=left>\n";
  $template_data .= "                      </tr>\n";
  $template_data .= "                      <tr>\n";
  $template_data .= "                        <td align=right>Name: </td>\n";
  $template_data .= "                        <td align=left> [pnp_card-name] </td>\n";
  $template_data .= "                      </tr>\n";

  if ( $query{'card-company'} ne "" ) {
    $template_data .= "                      <tr>\n";
    $template_data .= "                        <td align=right valign=top>Company: </td>\n";
    $template_data .= "                        <td align=left> [pnp_card-company] </td>\n";
    $template_data .= "                      </tr>\n";
  }
  $template_data .= "                      <tr>\n";
  $template_data .= "                        <td align=right valign=top>Address: </td>\n";
  $template_data .= "                        <td align=left> [pnp_card-address1] </td>\n";
  $template_data .= "                      </tr>\n";
  if ( $query{'address2'} ne "" ) {
    $template_data .= "                      <tr>\n";
    $template_data .= "                        <td align=left></td>\n";
    $template_data .= "                        <td align=left> [pnp_card-address2] </td>\n";
    $template_data .= "                      </tr>\n";
  }
  $template_data .= "                      <tr>\n";
  $template_data .= "                        <td align=left></td>\n";
  $template_data .= "                        <td align=left><nobr> [pnp_card-city], [pnp_card-prov] </nobr></td>\n";
  $template_data .= "                      </tr>\n";
  $template_data .= "                      <tr>\n";
  $template_data .= "                        <td align=left></td>\n";
  $template_data .= "                        <td align=left><nobr> [pnp_card-state] [pnp_card-zip] [pnp_card-country] </nobr></td>\n";
  $template_data .= "                      </tr>\n";

  if ( $query{'phone'} ne "" ) {
    $template_data .= "                      <tr>\n";
    $template_data .= "                        <td align=right>Phone: </td>\n";
    $template_data .= "                        <td align=left> [pnp_phone] </td>\n";
    $template_data .= "                      </tr>\n";
  }
  if ( $query{'fax'} ne "" ) {
    $template_data .= "                      <tr>\n";
    $template_data .= "                        <td align=right>Fax: </td>\n";
    $template_data .= "                        <td align=left> [pnp_fax] </td>\n";
    $template_data .= "                      </tr>\n";
  }
  if ( $query{'email'} ne "" ) {
    $template_data .= "                      <tr>\n";
    $template_data .= "                        <td align=right>Email: </td>\n";
    $template_data .= "                        <td align=left> [pnp_email] </a></td>\n";
    $template_data .= "                      </tr>\n";
  }
  $template_data .= "                    </table>\n";
  $template_data .= "                  </td>\n";
  $template_data .= "                </tr>\n";
  $template_data .= "              </table>\n";
  $template_data .= "              </td>\n";
  $template_data .= "            </tr>\n";
  $template_data .= "          </table>\n";
  $template_data .= "          </td>\n";
  $template_data .= "        </tr>\n";

  if ( $query{'acct_code'} ne "" ) {
    $template_data .= "        <tr>\n";
    $template_data .= "          <td colspan=\"2\">Acct Code: &nbsp; [pnp_acct_code]</td>\n";
    $template_data .= "        </tr>\n";
  }
  if ( $query{'acct_code2'} ne "" ) {
    $template_data .= "        <tr>\n";
    $template_data .= "          <td colspan=\"2\">Acct Code2: &nbsp; [pnp_acct_code2]</td>\n";
    $template_data .= "        </tr>\n";
  }
  if ( $query{'acct_code3'} ne "" ) {
    $template_data .= "        <tr>\n";
    $template_data .= "          <td colspan=\"2\">Acct Code3: &nbsp; [pnp_acct_code3]</td>\n";
    $template_data .= "        </tr>\n";
  }
  if ( $query{'acct_code4'} ne "" ) {
    $template_data .= "        <tr>\n";
    $template_data .= "          <td colspan=\"2\">Acct Code4: &nbsp; [pnp_acct_code4]</td>\n";
    $template_data .= "        </tr>\n";
  }

  $template_data .= "      </table>\n";
  $template_data .= "      </div>\n";
  $template_data .= "    </td>\n";
  $template_data .= "  </tr>\n";
  $template_data .= "</table>\n";

  $template_data .= "<p><form><input type=\"button\" name=\"print_button\" value=\"Print Page\" onclick=\"window.print();\"></form>\n";

  if ( $query{'receipt_link'} ne "" ) {
    $template_data .= "<p>To continue shopping, <a href=\"$query{'receipt_link'}\">CLICK HERE</a>.\n";
  } elsif ( $query{'receipt-link'} ne "" ) {
    $template_data .= "<p>To continue shopping, <a href=\"$query{'receipt-link'}\">CLICK HERE</a>.\n";
  }
  $template_data .= "</div>\n";

  return $template_data;
}

sub pos_return_template {
  my (%query) = @_;

  my $template_data = "";

  $template_data .= "<font size=+1><b>Return Receipt</b></font>\n";

  if ( $query{'receipt-company'} ne "" ) {
    $template_data .= "<p><font size=+1><b>[pnp_receipt-company]</b></font>\n";
  }
  if ( $query{'receipt-address1'} ne "" ) {
    $template_data .= "<br><font size=+1>[pnp_receipt-address1]</font>\n";
  }
  if ( $query{'receipt-address2'} ne "" ) {
    $template_data .= "<br><font size=+1>[pnp_receipt-address2]</font>\n";
  }
  if ( $query{'receipt-city'} ne "" ) {
    $template_data .= "<br><font size=+1>[pnp_receipt-city], [pnp_receipt-state] [pnp_receipt-zip] [pnp_receipt-country]</font>\n";
  }
  $template_data .= "<br>&nbsp;\n";
  if ( $query{'receipt-phone'} ne "" ) {
    $template_data .= "<br><font size=-1>Phone: [pnp_receipt-phone]</font>\n";
  }
  if ( $query{'receipt-fax'} ne "" ) {
    $template_data .= "<br><font size=-1>Fax: [pnp_receipt-fax]</font>\n";
  }
  if ( $query{'receipt-email'} ne "" ) {
    $template_data .= "<br><font size=-1>Email: [pnp_receipt-email]</font>\n";
  }
  if ( $query{'receipt-url'} ne "" ) {
    $template_data .= "<br><font size=-1>[pnp_receipt-url]</font>\n";
  }
  $template_data .= "</div>\n";

  $template_data .= "<p><b>Order Date:</b> [pnp_order-date]\n";
  $template_data .= "<br><b>Order ID:</b> [pnp_orderID]\n";
  if ( $query{'order-id'} ne "" ) {
    $template_data .= "<br><b>Merchant ID:</b> [pnp_order-id]\n";
  }

  $template_data .= "<p><hr>\n";

  if ( $query{'paymethod'} eq "onlinecheck" ) {
    $template_data .= "<p><b>Routing #:</b> [pnp_filteredRN]\n";
    $template_data .= "<br><b>Account #:</b> [pnp_filteredAN]\n";
  } else {
    $template_data .= "<p><b>Card #:</b> [pnp_card-number]\n";
    $template_data .= "<br><b>Card Exp:</b> [pnp_card-exp]\n";
  }
  $template_data .= "<br>[TABLE]\n";

  $template_data .= "<p><hr>\n";
  $template_data .= "<br><b><u>Card Holder Information:</u></b>\n";
  $template_data .= "<br>[pnp_card-name]\n";
  $template_data .= "<br>[pnp_card-address1]\n";
  if ( $query{'card-address2'} ne "" ) {
    $template_data .= "<br>[pnp_card-address2]\n";
  }
  $template_data .= "<br>[pnp_card-city],\n";
  $template_data .= "<br>[pnp_card-state] [pnp_card-zip] [pnp_card-country]\n";

  if ( $query{'phone'} ne "" ) {
    $template_data .= "<p>Phone: [pnp_phone]\n";
  }
  if ( $query{'fax'} ne "" ) {
    $template_data .= "<br>Fax: [pnp_fax]\n";
  }
  if ( $query{'email'} ne "" ) {
    $template_data .= "<br>Email: [pnp_email]\n";
  }

  $template_data .= "<br>&nbsp;\n";

  # add print button
  $template_data .= "<script language=\"JavaScript\"><!--\n";
  $template_data .= "if (document.layers && (self.innerHeight == 0 && self.innerWidth == 0)) {\n";
  $template_data .= "     // printing\n";
  $template_data .= "}\n";
  $template_data .= "else {\n";
  $template_data .= "    document.write('<form><input type=\"button\" value=\"Print Receipt\" onClick=\"window.print();\"><\/form>');\n";
  $template_data .= "}\n";
  $template_data .= "//--></script>\n";

  if ( $query{'receipt_link'} ne "" ) {
    $template_data .= "<p>To return to site, <a href=\"$query{'receipt_link'}\">CLICK HERE</a>.\n";
  } elsif ( $query{'receipt-link'} ne "" ) {
    $template_data .= "<p>To return to site, <a href=\"$query{'receipt-link'}\">CLICK HERE</a>.\n";
  }
  $template_data .= "</div>\n";

  return $template_data;
}

sub convfee_admin {

  # Handle returns and voids for IR and ConvFee
  my ( $mode, $orderid, $accttype, $amount, $currency, $acct_code4 ) = @_;
  my %result = ();

  my $skipVoidReturn_flag = 0;
  my $feeacct             = "";
  if ( $smps::accountFeatures->get('convfee') ) {
    my $cf = new PlugNPay::ConvenienceFee($smps::username);
    $feeacct = $cf->getChargeAccount();
    if ( $cf->isSurcharge() ) {
      $skipVoidReturn_flag = 1;
    }
  } elsif ( $smps::accountFeatures->get('cardcharge') ) {
    my $coa = new PlugNPay::COA($smps::username);
    $feeacct = $coa->getChargeAccount();
    if ( $coa->isSurcharge() || $coa->isOptional() ) {
      $skipVoidReturn_flag = 1;
    }
  }
  if ( $skipVoidReturn_flag != 1 ) {
    ###  Merchant is configured for either COA or Conv Fee.
    ### Locate Adjustment Fee Tran.

    my $adjustmentLog = new PlugNPay::Transaction::Logging::Adjustment();
    $adjustmentLog->setGatewayAccount($smps::username);
    $adjustmentLog->setOrderID($orderid);
    $adjustmentLog->load();
    my $baseAmount        = $adjustmentLog->getBaseAmount();
    my $adjustmentOrderID = $adjustmentLog->getAdjustmentOrderID();
    my $adjustmentAmount  = $adjustmentLog->getAdjustmentTotalAmount();

    my $percentReturned = 0;
    my $filteredAmount  = $amount;
    $filteredAmount =~ s/[^0-9\.]//g;
    if ( $baseAmount > 0 ) {
      $percentReturned = $filteredAmount / $baseAmount;
    } else {
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'}     = "Fee transaction not found or amount equals 0.";
      return %result;
    }

    if ( $adjustmentOrderID > 0 ) {
      my %data = ();
      $data{'orderID'}        = $adjustmentOrderID;
      $data{'publisher-name'} = $feeacct;
      $data{'accttype'}       = $accttype;
      $data{'mode'}           = "return";

      my @array = %data;
      my %trans = &miscutils::check_trans(@array);

      my $price = sprintf( "%3s %.2f", $currency, $adjustmentAmount * $percentReturned + 0.0001 );

      if ( ( $mode eq "return" ) && ( $trans{'allow_return'} == 1 ) ) {
        %result = &miscutils::sendmserver( "$feeacct", 'return', 'accttype', $data{'accttype'}, 'amount', $price, 'order-id', $data{'orderID'}, 'acct_code4', $acct_code4 );
        if ( $result{'FinalStatus'} !~ /success|pending/ ) {
          $result{'MErrMsg'} = "Return of fee transaction failed.";
        }
      } elsif ( ( $mode eq "void" ) && ( $trans{'allow_void'} == 1 ) ) {
        %result = &miscutils::sendmserver( "$feeacct", 'void', 'accttype', $data{'accttype'}, 'amount', $price, 'order-id', $data{'orderID'}, 'acct_code4', $acct_code4 );
        if ( $result{'FinalStatus'} !~ /success|pending/ ) {
          $result{'MErrMsg'} = "Void of fee transaction failed.";
        }
      } else {
        $result{'FinalStatus'} = "problem";
        $result{'MErrMsg'}     = "Fee $mode not allowed.";
      }
    } else {
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'}     = "Fee transaction not found.";
    }
  }
  return %result;
}

sub mark {
  my $orderid    = $smps::query->param('orderid');
  my $amount     = $smps::query->param('amount');
  my $accttype   = $smps::query->param('accttype');
  my $acct_code4 = "Virtual Terminal";

  my ( $currency, $amt, @garbage ) = split( '\ +', $amount );
  $currency =~ s/[^a-zA-Z]//g;
  $currency = substr( $currency, 0, 3 );
  $amt =~ s/[^0-9\.]//g;

  ## Normalize Decimal Place based on currency
  $amt = new PlugNPay::Currency($currency)->format( $amt, { digitSeparator => '' } );

  $amount = "$currency $amt";

  my %result = &miscutils::sendmserver( "$smps::username", 'postauth', 'accttype', "$accttype", 'amount', "$amount", 'acct_code4', $acct_code4, 'order-id', "$orderid" );

  if ( $result{'FinalStatus'} =~ /^(success|pending)$/ ) {
    print "<h3>Order: $orderid has been marked for batching</h3>";
  } else {
    print "<h3>Order: $orderid could not be marked for batching</h3><br>";
    print "Reason: $result{'MErrMsg'}";
  }
}

sub retry {

  my $orderid  = $smps::query->param('orderid');
  my $txntype  = $smps::query->param('txntype');
  my $accttype = $smps::query->param('accttype');

  # Contact the credit server
  my %result = &miscutils::sendmserver( "$smps::username", "retry", 'accttype', "$accttype", 'order-id', $orderid, 'txn-type', $txntype );

  print "<html>\n";
  print "<body bgcolor=\"#ffffff\">\n";
  print "<div align=center>\n";

  if ( $result{'FinalStatus'} eq "success" ) {
    print "<h3>Your transaction for $result{'paid-amount'} was successful</h3><br>\n";
    print "<h3>The order ID is: $orderid</h3>\n";
    print "<h3>The AVS Code is: $result{'avs-code'}</h3>\n";
    if ( $result{'cvvresp'} ne "" ) {
      print "<h3>The CVV Code is: $result{'cvvresp'}</h3>\n";
    }
    my $auth_code = substr( $result{'auth-code'}, 0, 6 );
    print "<h3>The Auth Code is: $auth_code</h3>\n";
  } else {
    print "<h3>Your transaction for $result{'paid-amount'} failed</h3><br>\n";
    print "Reason: ";
    print %result;
    print "<br>\n";
  }

  print "</div>\n";
  print "</body>\n";
  print "</html>\n";

}

sub input {

  if ( $ENV{'SEC_LEVEL'} >= 9 ) {
    my $message = "Your current security level is not cleared for this operation. <p>Please contact Technical Support if you believe this to be in error. ";
    &response_page($message);
  }

  $smps::timetest{'1_inputstart'} = time();

  my $form_orderid = $smps::query->param('orderid');
  $form_orderid =~ s/[^0-9]//g;

  my $name            = $smps::query->param('name');
  my $addr1           = $smps::query->param('addr1');
  my $addr2           = $smps::query->param('addr2');
  my $city            = $smps::query->param('city');
  my $type            = $smps::query->param('type');
  my $state           = $smps::query->param('state');
  my $zip             = $smps::query->param('zip');
  my $country         = $smps::query->param('country');
  my $province        = $smps::query->param('prov');
  my $auth_code       = $smps::query->param('auth-code');
  my $original_amount = $smps::query->param('original_amount');
  my $amount          = $smps::query->param('amount');
  my $exp_month       = $smps::query->param('exp_month');
  my $exp_year        = $smps::query->param('exp_year');
  my $acct_code       = $smps::query->param('acct_code');
  my $acct_code4      = "Virtual Terminal";

  $name =~ s/[^a-zA-Z0-9_\.\/\-\ \#\'\,]/ /g;
  $addr1 =~ s/[\r\n]//;
  $addr1 =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;
  $addr2 =~ s/[\r\n]//;
  $addr2 =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;
  $city =~ s/[^a-zA-Z0-9\.\-\' ]/ /g;
  $state =~ s/[^a-zA-Z0-9\.\-\' ]/ /g;
  $zip =~ s/[^a-zA-Z\'0-9 ]/ /g;
  $country =~ s/[^a-zA-Z\' ]/ /g;
  $province =~ s/[^a-zA-Z\' ]/ /g;
  $auth_code =~ s/[^a-zA-Z0-9\ ]/ /g;
  $original_amount =~ s/[^0-9\. \ a-zA-Z]/ /g;
  $amount =~ s/[^0-9\. \ a-zA-Z]/ /g;
  $exp_month =~ s/[^0-9]//g;
  $exp_year =~ s/[^0-9]//g;
  $acct_code =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;

  my $transflags = $smps::query->param('transflags');
  if ( $transflags ne "" ) {
    $transflags .= ",moto";
  } else {
    $transflags = "moto";
  }

  my $cardnumber = $smps::query->param('cardnumber');
  $cardnumber =~ s/[^0-9]//g;

  my $routingnum = $smps::query->param('routingnum');
  $routingnum =~ s/[^0-9]//g;
  $routingnum = substr( $routingnum, 0, 9 );

  my $accountnum = $smps::query->param('accountnum');
  my $accttype   = $smps::query->param('accttype');

  my ( $cardtype, $orderID );

  if ( $cardnumber ne "" ) {
    my $luhntest = &miscutils::luhn10($cardnumber);
    if ( $luhntest eq "failure" ) {
      print "<html><body bgcolor=\"#ffffff\"><div align=\"center\"><h3>Invalid Credit Card Number.  Please check and re-submit.</h3></div></body></html>\n";
      return;
    }
  }

  if ( ( $accountnum ne "" ) && ( $routingnum ne "" ) ) {
    my $luhntest = &miscutils::mod10($routingnum);
    if ( ( length($routingnum) != 9 ) || ( $luhntest eq "failure" ) ) {
      print "<html><body bgcolor=\"#ffffff\"><div align=\"center\"><h3>Invalid Bank Routing Number.  Please check and re-submit.</h3></div></body></html>\n";
      return;
    }
    $cardnumber = "$routingnum $accountnum";
  }

  if ( ( $cardnumber eq "" ) && ( $form_orderid eq "" ) ) {
    print "<html><body bgcolor=\"#ffffff\"><div align=\"center\"><h3>Missing Credit Card Number or OrderID.  Please check and re-submit.</h3></div></body></html>\n";
    return;
  }

  $smps::timetest{'2_luhntest'} = time();

  my %month_array  = ( 1,     "Jan", 2,     "Feb", 3,     "Mar", 4,     "Apr", 5,     "May", 6,     "Jun", 7,     "Jul", 8,     "Aug", 9,     "Sep", 10,    "Oct", 11,    "Nov", 12,    "Dec" );
  my %month_array2 = ( "Jan", "01",  "Feb", "02",  "Mar", "03",  "Apr", "04",  "May", "05",  "Jun", "06",  "Jul", "07",  "Aug", "08",  "Sep", "09",  "Oct", "10",  "Nov", "11",  "Dec", "12" );

  my ( $sec, $min, $hour, $mday, $mon, $yyear, $wday, $yday, $isdst ) = gmtime(time);

  my $price;
  if ( $amount !~ /[a-zA-Z]{3} / ) {
    $price = "$smps::currency $amount";
  } else {
    $price = $amount;
  }

  my ($orig_curr);
  if ( $type eq "reauth" ) {
    my ( $junk1, $orig_tst_amt ) = split( /\s/, $original_amount, 2 );
    my ( $junk2, $tst_amt )      = split( /\s/, $amount,          2 );
    $orig_curr = $junk1;
    $orig_tst_amt =~ s/[^0-9\.]//g;
    $tst_amt =~ s/[^0-9\.]//g;

    if ( ( $tst_amt >= $orig_tst_amt ) && ( $smps::processor ne "fifththird" ) ) {
      print "<html><body bgcolor=\"#ffffff\"><div align=\"center\"><h3>Amount for reauthorization must be less than original amount.  Please check and re-submit.</h3></div></body></html>\n";
      return;
    }

  }

  my $amtresult = &smpsutils::checkamt($price);
  $smps::timetest{'3_postchkamt'} = time();

  if ( $amtresult ne "" ) {
    print "<h3>Your transaction for $smps::currency $amount failed</h3><br>\n";
    print "Reason: ";
    print $amtresult;
    print "<br>\n";
  } else {
    $amount =~ s/[^0-9\.]//g;
    if ( $type eq "reauth" ) {
      $price = sprintf( "%s %.2f", $orig_curr, $amount );
    } else {
      $price = sprintf( "%s %.2f", $smps::currency, $amount );
    }
    my $addr = $addr1 . " " . $addr2;
    $addr =~ s/ $//g;
    my $exp = $exp_month . '/' . $exp_year;

    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);
    if ( $form_orderid eq "" ) {
      $orderID = sprintf( "%04d%02d%02d%02d%02d%02d%05d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec, $$ );
    } else {
      $orderID = $form_orderid;
      $orderID =~ s/[^0-9]//g;
    }

    my $shortcard = substr( $cardnumber, 0, 4 ) . "**" . substr( $cardnumber, -2, 2 );

    my $dbh = &miscutils::dbhconnect( "pnpdata", "", "$smps::username" );    ## Trans_Log

    my $sth = $dbh->prepare(
      qq{
        select orderid
        from trans_log
        where orderid=?
        and trans_date>=?
        and card_number=?
        and username=?
        }
      )
      or die "Can't do: $DBI::errstr";
    $sth->execute( "$orderID", "$smps::earliest_date", "$shortcard", "$smps::username" ) or die "Can't execute: $DBI::errstr";
    my ($chkorderid) = $sth->fetchrow;
    $sth->finish;

    $dbh->disconnect;

    $smps::timetest{'4_oidtest'} = time();

    if ( $chkorderid ne "" ) {
      print "<html><body bgcolor=\"#ffffff\"><h3>This order id has already been used</h3></body></html>\n";
      return;
    }

    if ( $type eq "ret" ) {
      $type = 'return';
    }

    my @extrafields;
    if ( ( $smps::processor eq "fdms" ) && ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) ) {
      my $tax = $smps::query->param('tax');
      $tax =~ s/[^0-9\.]//g;
      my $ship_zip = $smps::query->param('ship_zip');
      $ship_zip =~ s/[^a-zA-Z\'0-9 ]/ /g;
      my $ponumber = $smps::query->param('ponumber');
      $ponumber =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;
      my $commcardtype = $smps::query->param('commcardtype');
      $commcardtype =~ s/[^a-zA-Z0-9]//g;
      my $commtaxexempt = $smps::query->param('commtaxexempt');
      $commtaxexempt =~ s/[^a-zA-Z]//g;
      my $duty = $smps::query->param('duty');
      $duty =~ s/[^0-9\.]//g;
      my $freight = $smps::query->param('freight');
      $freight =~ s/[^0-9\.]//g;
      @extrafields = ( 'tax', $tax, 'ship_zip', $ship_zip, 'ponumber', $ponumber, 'commcardtype', $commcardtype, 'commtaxexempt', $commtaxexempt, 'duty', $duty, 'freight', $freight );
    }

    if ( ( $smps::processor eq "visanet" ) && ( ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) ) ) {
      my $email = $smps::query->param('email');
      $email =~ s/\;/\,/g;
      $email =~ s/[^_0-9a-zA-Z\-\@\.\,\+\#\&\*]//g;
      $email =~ tr/A-Z/a-z/;
      my $phone = $smps::query->param('phone');
      $phone =~ s/[^0-9\-]//g;
      my $commcardtype = $smps::query->param('commcardtype');
      $commcardtype =~ s/[^a-zA-Z0-9]//g;

      @extrafields = ( 'email', $email, 'phone', $phone, 'commcardtype', $commcardtype );
    }

    if ( $smps::chkprocessor =~ /^(telecheck|firstamer|selectcheck|delaware|paymentdata|citynat)$/ ) {
      my $micr     = $smps::query->param('micr');
      my $checknum = $smps::query->param('checknum');
      my $phone    = $smps::query->param('phone');
      $phone =~ s/[^0-9\-]//g;
      my $socsecnum = $smps::query->param('socsecnum');
      $socsecnum =~ s/[^0-9\-\ ]//g;
      my $licensestate = $smps::query->param('licensestate');
      $licensestate =~ s/[^a-zA-Z]//g;
      my $licensenum = $smps::query->param('licensenum');
      $licensenum =~ s/[^_0-9a-zA-Z\-\.\ ]//g;
      my $dateofbirth = $smps::query->param('dateofbirth');
      $dateofbirth =~ s/[^_0-9a-zA-Z\-\.\ \/]//g;
      my $email = $smps::query->param('email');
      $email =~ s/\;/\,/g;
      $email =~ s/[^_0-9a-zA-Z\-\@\.\,\+\#\&\*]//g;
      $email =~ tr/A-Z/a-z/;
      my $checktype = $smps::query->param('checktype');
      $checktype =~ s/[^A-Za-z]//g;

      @extrafields = (
        'micr',       $micr,       'checknum',    $checknum,    'phone', $phone, 'socsecnum', $socsecnum, 'licensestate', $licensestate,
        'licensenum', $licensenum, 'dateofbirth', $dateofbirth, 'email', $email, 'checktype', $checktype
      );
    }

    if ( ( $smps::username =~ /ncbjamaica/ ) && ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) ) {
      my $testhost = $smps::query->param('testhost');
      $testhost =~ s/[^a-zA-Z0-9]//g;
      my $testposentry = $smps::query->param('testposentry');
      $testposentry =~ s/[^a-zA-Z0-9]//g;
      @extrafields = ( 'testhost', $testhost, 'testposentry', $testposentry );
    }

    my $cvv = $smps::query->param('card-cvv');
    $cvv =~ s/[^0-9]//g;

    $smps::timetest{'4a_prepurch'} = time();

    # Contact the credit server
    my %result = &miscutils::sendmserver(
      "$smps::username", "$type",     'accttype',  "$accttype",     'order-id',     $orderID,    'amount',    $price, 'auth-code',  $auth_code,
      'card-number',     $cardnumber, 'card-name', $name,           'card-address', $addr,       'card-city', $city,  'card-state', $state,
      'card-zip',        $zip,        'card-cvv',  $cvv,            'card-country', $country,    'card-exp',  $exp,   'acct_code',  $acct_code,
      'acct_code4',      $acct_code4, 'subacct',   $ENV{'SUBACCT'}, 'transflags',   $transflags, @extrafields
    );

    $smps::timetest{'5_purch'} = time();

    if ( $type eq "reauth" && $result{'FinalStatus'} eq 'success' && $smps::query->param('markReauth') eq 'yes' ) {
      my %postauthResult = &miscutils::sendmserver( $smps::username, "postauth", 'amount', $price, 'order-id', $orderID, 'accttype', $accttype, 'acct_code', $acct_code, 'acct_code4', $acct_code4 );
      $result{'postauthstatus'} = $postauthResult{'FinalStatus'};
    }

    if ( $smps::transtype{$type} eq "" ) {
      $smps::transtype{$type} = "transaction";
    }

    $shortcard = substr( $cardnumber, 0, 4 ) . "**" . substr( $cardnumber, -2, 2 );

    print "<div align=center>\n";

    if ( $result{'FinalStatus'} eq "success" ) {
      print "<h3>Your $smps::transtype{$type} for $smps::currency $amount was successful</h3><br>\n";
      print "<h3>The order ID is: $orderID</h3><br>\n";
      if ( $type ne "reauth" ) {
        print "<h3>The name is: $name</h3>\n";
        if ( $type ne "ret" ) {
          print "<h3>The AVS Code is: $result{'avs-code'}</h3><br>\n";
          $auth_code = substr( $result{'auth-code'}, 0, 6 );
          print "<h3>The CVV Code is: $result{'cvvresp'}</h3>\n";
          print "<h3>The Auth Code is: $auth_code</h3>\n";
        }
        print "<h3>Credit Card # is: $shortcard</h3>\n";
      }
    } elsif ( $result{'FinalStatus'} eq "pending" ) {
      print "<h3>Your $smps::transtype{$type} for $smps::currency $amount has been inserted into the batch database</h3><br>\n";
      print "<h3>The order ID is: $orderID</h3>\n";
      print "<h3>The name is: $name</h3>\n";
      print "<h3>Credit Card # is: $shortcard</h3>\n";
    } else {
      print "<h3>Your $smps::transtype{$type} for $smps::currency $amount failed</h3><br>\n";
      print "Reason: ";
      print "$result{'MErrLoc'} $result{'MErrMsg'} $result{'aux-msg'}";
      print "<br>\n";
    }
  }
  $smps::timetest{'6_end'} = time();
}

sub dccoptout {
  require remote_strict;

  my ( %query, %result );
  my @params = $smps::query->param;
  foreach my $param (@params) {
    $query{$param} = $smps::query->param($param);
  }
  $query{'publisher-name'} = $ENV{'REMOTE_USER'};

  my @array = %query;

  my $pnpremote = remote->new(@array);

  %result = $pnpremote->dccoptout();

}

sub input_new {
  ## Comment out by DCP, 20061101
  my %transtype = ( 'auth', 'Authorization', 'credit', 'Return', 'newreturn', 'Return', 'bill_member', 'Authorization', 'credit_member', 'Return', 'returnprev', 'Credit' );

  if ( ( $ENV{'SEC_LEVEL'} >= 9 ) && ( $ENV{'SEC_LEVEL'} != 13 ) ) {
    my $message = "Your current security level is not cleared for this operation. <p>Please contact Technical Support if you believe this to be in error. ";
    &response_message($message);
  }

  my ( %query, %result );
  my @params = $smps::query->param;
  foreach my $param (@params) {
    $query{$param} = $smps::query->param($param);
  }
  $query{'publisher-name'} = $ENV{'REMOTE_USER'};

  if ( ( $smps::feature{'multicurrency'} eq "1" ) && ( $query{'transflags'} !~ /multicurrency/ ) ) {
    if ( exists $query{'transflags'} ) {
      $query{'transflags'} .= ",multicurrency";
    } else {
      $query{'transflags'} = "multicurrency";
    }
  }

  if ( ( $smps::processor eq "wirecard" ) && ( $query{'mode'} eq "payment" ) ) {
    $query{'mode'}       = 'newreturn';
    $query{'transflags'} = 'payment';
  }

  if ( ( $smps::proc_type eq "returnonly" ) && ( $query{'mode'} !~ /^(credit|newreturn|return)$/ ) ) {
    my $message = "Your current account status allows for issuing returns and/or credits only. <p>Please contact Technical Support if you believe this to be in error.";
    &response_message($message);
  }

  # DWW added to properly convert underscores for all fields
  if ( $query{'convert'} =~ /underscores/i ) {
    my @underscorearray = %query;
    %query = &miscutils::underscore_to_hyphen(@underscorearray);
  }

  if ( $query{'card-cvv'} ne "" ) {
    $query{'card-cvv'} =~ s/[^0-9]//g;
    $query{'card-cvv'} = substr( $query{'card-cvv'}, 0, 4 );
  }

  ##  DCP - Added support for split name
  if ( ( $query{'card-name'} eq "" ) && ( $query{'card-fname'} ne "" ) && ( $query{'card-lname'} ne "" ) ) {
    $query{'card-name'} = "$query{'card-fname'} $query{'card-lname'}";
  }

  ###  DCP - Make CVV required for VT if cvv_vt fraud config setting is set.
  if ( ( $smps::fconfig{'cvv_vt'} == 1 ) && ( $query{'mode'} eq "auth" ) && ( $query{'card-cvv'} eq "" ) && ( $query{'retailflag'} ne "yes" ) ) {
    my $message = "CVV/CVC data is required for manually entered transactions.";
    &response_message($message);
  }

  ### DCP 20101210 - Request from Janelle - Affiniscape
  if ( ( $smps::reseller =~ /^(cynergy|affinisc|lawpay)/ ) && ( $smps::username =~ /^(cyd|ap|ams|lp|law)/ ) && ( $query{'acct_code'} eq "" ) ) {
    $smps::feature{'mapacctcode'} = "LOGIN";
  }

  if ( $smps::feature{'mapacctcode'} ne "" ) {
    $smps::feature{'mapacctcode'} =~ tr/a-z/A-Z/;
    my $tmp = $ENV{"$smps::feature{'mapacctcode'}"};
    $tmp =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\']/ /g;
    $tmp = substr( $tmp, 0, 25 );
    $query{'acct_code'} = $tmp;
  }

  if ( ( $ENV{'REMOTE_USER'} =~ /^(jhew)/ ) || ( $smps::merchant =~ /^(jhew)/ ) ) {
    if ( $smps::merchant =~ /^(jhew)/ ) {
      $query{'acct_code'} = $query{'merchant'};
    } else {
      $query{'acct_code'} = $ENV{'REMOTE_USER'};
    }
    $query{'acct_code'} =~ /jhew(\d*)/;
    $query{'storenum'} = $1;

    if ( ( $query{'micr'} eq "" ) && ( $query{'accttype'} =~ /(checking|savings)/ ) ) {
      my $gatewayAccount = new PlugNPay::GatewayAccount( $query{'merchant'} );
      my $mainContact    = $gatewayAccount->getMainContact();
      $smps::addr1   = $mainContact->getAddress1();
      $smps::addr2   = $mainContact->getAddress2();
      $smps::city    = $mainContact->getCity();
      $smps::state   = $mainContact->getState();
      $smps::zip     = $mainContact->getPostalCode();
      $smps::country = $mainContact->getCountry();
      $smps::tel     = $mainContact->getPhone();
      $smps::company = $mainContact->getCompany();

      $query{'acct_code'}      = $query{'merchant'};
      $query{'publisher-name'} = "jhewica";
      $query{'merchant'}       = "jhewica";
      $ENV{'REMOTE_USER'} =~ /jhew(\d*)/;
      $query{'storenum'} = $1;
    }
  } elsif ( ( $ENV{'REMOTE_USER'} =~ /^(jhtn|jhcn|jhpc|jhsu|jgok|jhlb|jgtx|jgtn|jhmk|jhmg|jhpm|jhrs|jhbc|jhat|jhhm|jhnw|jhpl|jhex|jhgy)/ )
    || ( $smps::merchant =~ /^(jhtn|jhcn|jhpc|jhsu|jgok|jhlb|jgtx|jgtn|jhmk|jhmg|jhpm|jhrs|jhbc|jhat|jhhm|jhnw|jhpl|jhex|jhgy)/ ) ) {
    my $temp = $1;

    if ( $smps::merchant =~ /^jhtn|jhcn|jhpc|jhsu|jgok|jhlb|jgtx|jgtn|jhmk|jhmg|jhpm|jhrs|jhbc|jhat|jhhm|jhnw|jhpl|jhex|jhgy/ ) {
      $query{'acct_code'} = $query{'merchant'};
    } else {
      $query{'acct_code'} = $ENV{'REMOTE_USER'};
    }
    $query{'acct_code'} =~ /$temp(\d*)/;
    $query{'storenum'} = $1;

    if ( ( $query{'micr'} eq "" ) && ( $query{'accttype'} =~ /(checking|savings)/ ) ) {
      my $gatewayAccount = new PlugNPay::GatewayAccount( $query{'merchant'} );
      my $mainContact    = $gatewayAccount->getMainContact();
      $smps::addr1   = $mainContact->getAddress1();
      $smps::addr2   = $mainContact->getAddress2();
      $smps::city    = $mainContact->getCity();
      $smps::state   = $mainContact->getState();
      $smps::zip     = $mainContact->getPostalCode();
      $smps::country = $mainContact->getCountry();
      $smps::tel     = $mainContact->getPhone();
      $smps::company = $mainContact->getCompany();

      $query{'acct_code'}      = $query{'merchant'};
      $query{'publisher-name'} = $temp . "ica";
      $query{'merchant'}       = $query{'publisher-name'};
      $ENV{'REMOTE_USER'} =~ /$temp(\d*)/;
      $query{'storenum'} = $1;
    }
  }

  if ( ( $query{'receipt_type'} =~ /simple|itemized|pos_simple|pos_itemized/i ) || ( $query{'receipt-type'} =~ /simple|itemized|pos_simple|pos_itemized/i ) ) {
    $query{'receipt-company'}  = $smps::company;
    $query{'receipt-address1'} = $smps::addr1;
    $query{'receipt-address2'} = $smps::addr2;
    $query{'receipt-city'}     = $smps::city;
    $query{'receipt-state'}    = $smps::state;
    $query{'receipt-zip'}      = $smps::zip;
    $query{'receipt-country'}  = $smps::country;
    $query{'receipt-phone'}    = $smps::tel;
  }

  my @array = %query;

  require remote_strict;
  require mckutils_strict;

  my $pnpremote = remote->new(@array);

  if ( $query{'mode'} =~ /^(authprev)$/ ) {
    my $payment = mckutils->new(@array);
    $remote::query{'acct_code4'} = "Virtual Terminal";
    %result = $pnpremote->authprev();
  }

  %query = %remote::query;

  if ( $query{'summarizeflg'} == 1 ) {
    $remote::summarizeflg = "1";
  }

  @array = %query;

  if ( $query{'mode'} =~ /^(return|reauth)$/ ) {
    $remote::query{'acct_code4'} = "Virtual Terminal";
    %result = $pnpremote->trans_admin();
  } elsif ( $query{'mode'} =~ /^(credit|newreturn|payment)$/ ) {
    if ( ( $smps::processor eq "mercury" ) && ( $query{'issue'} eq "yes" ) && ( $query{'mpgiftcard'} ne "" ) && ( $query{'transflags'} !~ /issue/ ) ) {
      if ( $query{'transflags'} ne "" ) {
        $query{'transflags'} .= ",issue";
      } else {
        $query{'transflags'} = "issue";
      }
    }

    my $payment = mckutils->new(@array);

    if ( $smps::achstatus eq "enabled" ) {
      if ( ( $mckutils::query{'card-number'} eq "" ) && ( $mckutils::query{'accttype'} eq "credit" ) ) {
        my $message = "Missing Credit Card Number.  Please check and re-enter.";
        &response_message($message);
      }
    } else {
      if ( $mckutils::query{'card-number'} eq "" ) {
        my $message = "Missing Credit Card Number.  Please check and re-enter.";
        &response_message($message);
      }
    }

    $remote::query{'acct_code4'} = "Virtual Terminal";
    %result = $pnpremote->newreturn();

    $query{'currency'}    = $result{'currency'};
    $query{'card-amount'} = $result{'card-amount'};

    if ( ( $result{'FinalStatus'} =~ /success|pending/ )
      && ( ( $query{'receipt_type'} =~ /simple|itemized|pos_simple|pos_itemized/i ) || ( $query{'receipt-type'} =~ /simple|itemized|pos_simple|pos_itemized/i ) ) ) {
      my $template_data  = "";                                           # clear and initialize value for holding return template data
      my $template_table = &return_table_template(%result);    # create product table data & amount returned

      # Load, Fill-In & Display Return Template
      my @todays_date = gmtime(time);
      $result{'order-date'} = sprintf( "%02d/%02d/%04d", $todays_date[4] + 1, $todays_date[3], $todays_date[5] + 1900 );

      $result{'card-number'} =~ s/[^0-9]//g;
      $result{'card-number'} = substr( $result{'card-number'}, 0, 20 );
      my ($cardnumber) = $result{'card-number'};
      my $cclength = length($cardnumber);
      my $last4 = substr( $cardnumber, -4, 4 );
      $cardnumber =~ s/./X/g;
      $result{'card-number'} = substr( $cardnumber, 0, $cclength - 4 ) . $last4;

      if ( ( $query{'receipt_type'} =~ /^pos_/i ) || ( $query{'receipt-type'} =~ /^pos_/i ) ) {
        $template_data = &pos_return_template(%result);
      } else {
        $template_data = &return_template(%result);
      }
      $template_data =~ s/\[pnp_([a-zA-Z0-9\-\_]*)\]/$result{$1}/g;
      $template_data =~ s/\[TABLE\]/$template_table/g;
      &mckutils::genhtml( "", "$template_data" );
      return;
    }
  } elsif ( $query{'mode'} =~ /^(forceauth)$/ ) {
    $remote::query{'acct_code4'} = "Virtual Terminal";
    %result = $pnpremote->forceauth();
  }
  ## THIS RETURNPREV CODE IS NOT YET READY FOR USAGE - 01/09/10 James
  ## RETURNPREV CODE DOES NOT WORK CURRNENTLY
  elsif ( $query{'mode'} =~ /^(returnprev)$/ ) {
    if ( $remote::query{'lnkreturn'} ne "" ) {
      $remote::query{'acct_code4'} = "VT:lnk$remote::query{'prevorderid'}";
    } else {
      $remote::query{'acct_code4'} = "Virtual Terminal";
    }
    %result = $pnpremote->returnprev();
    %query  = %remote::query;
  } elsif ( $query{'mode'} =~ /^(bill_member|credit_member)$/ ) {
    $remote::query{'acct_code4'} = "Virtual Terminal";

    if ( $query{'retailflag'} ne "yes" ) {
      if ( exists $remote::query{'transflags'} ) {
        $remote::query{'transflags'} .= ",moto";
      } else {
        $remote::query{'transflags'} = "moto";
      }
    }

    %result = $pnpremote->bill_member();
    if ( $result{'FinalStatus'} eq "problem" ) {
      %query = %remote::query;
    } else {
      %query = %mckutils::query;
    }
    if ( $query{'summarizeflg'} == 1 ) {
      &summarize();
    }

    if (
      ( $result{'FinalStatus'} =~ /success|pending/ )
      && ( ( $mckutils::query{'receipt_type'} =~ /simple|itemized|pos_simple|pos_itemized/i )
        || ( $mckutils::query{'receipt-type'} =~ /simple|itemized|pos_simple|pos_itemized/i ) )
      ) {
      my @array          = ( %query, %result );
      my $template_table = "";
      my $template_data  = "";                    # clear and initialize value for holding return template data

      my @todays_date = gmtime(time);
      $query{'order-date'} = sprintf( "%02d/%02d/%04d", $todays_date[4] + 1, $todays_date[3], $todays_date[5] + 1900 );

      ## Filter CC#
      $query{'card-number'} =~ s/[^0-9]//g;
      $query{'card-number'} = substr( $result{'card-number'}, 0, 20 );
      my ($cardnumber) = $query{'card-number'};
      my $cclength = length($cardnumber);
      my $last4 = substr( $cardnumber, -4, 4 );
      $cardnumber =~ s/./X/g;
      $query{'card-number'} = substr( $cardnumber, 0, $cclength - 4 ) . $last4;

      @array = (%query);

      if ( $query{'mode'} =~ /bill_member/ ) {
        $template_table = &mckutils::create_table_for_template(@array);    # create product table data & amount returned
        if ( ( $query{'receipt_type'} =~ /^pos_/i ) || ( $query{'receipt-type'} =~ /^pos_/i ) ) {
          $template_data = &mckutils::pos_template(@array);
        } else {
          $template_data = &mckutils::thankyou_template(@array);
        }
      } else {
        $template_table = &return_table_template(@array);    # create product table data & amount returned
        if ( ( $query{'receipt_type'} =~ /^pos_/i ) || ( $query{'receipt-type'} =~ /^pos_/i ) ) {
          $template_data = &pos_return_template(@array);
        } else {
          $template_data = &return_template(@array);
        }
      }
      $template_data =~ s/\[pnp_([a-zA-Z0-9\-\_]*)\]/$query{$1}/g;
      $template_data =~ s/\[TABLE\]/$template_table/g;
      &mckutils::genhtml( "", "$template_data" );
      return;
    }
  } elsif ( $query{'mode'} =~ /auth/ ) {
    my $payment = mckutils->new(@array);

    if ( $smps::achstatus eq "enabled" ) {
      if ( $mckutils::query{'accttype'} =~ /^(checking|savings)$/ ) {
        if ( ( ( $mckutils::query{'routingnum'} eq "" ) || ( $mckutils::query{'accountnum'} eq "" ) ) && ( $mckutils::query{'micr'} eq "" ) ) {
          my $message = "Missing Account Number \&/or Routing Number.  Please check and re-enter.";
          &response_message($message);
        }
      } elsif ( $smps::processor eq "mercury" ) {
        if ( ( $mckutils::query{'mpgiftcard'} eq "" ) && ( $mckutils::query{'card-number'} eq "" ) ) {
          my $message = "Missing Credit Card Number \&/or Gift Card Number.  Please check and re-enter.";
          &response_message($message);
        }
      } elsif ( ( $mckutils::query{'card-number'} eq "" ) && ( $mckutils::query{'accttype'} eq "credit" ) ) {
        my $message = "Missing Credit Card Number.  Please check and re-enter.";
        &response_message($message);
      }
    } else {
      if ( $smps::processor eq "mercury" ) {
        if ( ( $mckutils::query{'mpgiftcard'} eq "" ) && ( $mckutils::query{'card-number'} eq "" ) ) {
          my $message = "Missing Credit Card Number \&/or Gift Card Number.  Please check and re-enter.";
          &response_message($message);
        }
      } elsif ( $mckutils::query{'card-number'} eq "" ) {
        my $message = "Missing Credit Card Number.  Please check and re-enter.";
        &response_message($message);
      }
    }

    $mckutils::source = "virtterm";

    if ( $query{'retailflag'} ne "yes" ) {
      if ( exists $mckutils::query{'transflags'} ) {
        $mckutils::query{'transflags'} .= ",moto";
      } else {
        $mckutils::query{'transflags'} = "moto";
      }
    }

    if ( ( $mckutils::query{'reload'} eq "yes" ) && ( $smps::processor eq "mercury" ) ) {
      if ( exists $mckutils::query{'transflags'} ) {
        $mckutils::query{'transflags'} .= ",reload";
      } else {
        $mckutils::query{'transflags'} = "reload";
      }
    }

    if ( $query{'fraudbuypass'} eq "yes" ) {
      $mckutils::buypassfraud = "yes";
    }
    $mckutils::query{'acct_code4'} = "Virtual Terminal";

    if ( ( $mckutils::query{'mpgiftcard'} ne "" )
      && ( $mckutils::query{'card-number'} ne "" )
      && ( $mckutils::query{'transflags'} !~ /reload/i ) ) {
      my $tempCC  = $mckutils::query{'card-number'};
      my $tempCVV = $mckutils::query{'card-cvv'};
      my $tempAMT = $mckutils::query{'card-amount'};
      if ( $mckutils::query{'mpgiftamount'} > 0 ) {
        $mckutils::query{'mpgiftamount'} =~ s/[^0-9\.]//g;
        $mckutils::query{'mpgiftamount'} = sprintf( "%.2f", $mckutils::query{'mpgiftamount'} );
        $mckutils::query{'card-amount'} = $mckutils::query{'mpgiftamount'};
      }
      $mckutils::query{'card-number'} = $mckutils::query{'mpgiftcard'};
      $mckutils::query{'card-cvv'}    = $mckutils::query{'mpcvv'};
      if ( $mckutils::query{'transflags'} !~ /nonsf/ ) {
        if ( $mckutils::query{'transflags'} ne "" ) {
          $mckutils::query{'transflags'} .= ",nonsf";
        } else {
          $mckutils::query{'transflags'} = "nonsf";
        }
      }
      my ( %result1, %resultGC, %resultCC, $voidstatus );
      %resultGC = $payment->purchase("auth");
      my $tempOID = $mckutils::query{'orderID'};
      if ( $mckutils::query{'mpgiftamount'} > 0 ) {
        $mckutils::query{'card-amount'} = $tempAMT;
      }
      if ( ( ( $resultGC{'FinalStatus'} eq "success" ) || ( ( $resultGC{'FinalStatus'} eq "badcard" ) && ( $resultGC{'balance'} == 0 ) ) )
        && ( $resultGC{'amount'} < $mckutils::query{'card-amount'} ) ) {
        $payment->database();
        $mckutils::query{'card-number'} = $tempCC;
        $mckutils::query{'card-cvv'}    = $tempCVV;
        $mckutils::query{'card-amount'} -= $resultGC{'amount'};
        ## INC OrderID
        $mckutils::query{'orderID'} = &miscutils::incorderid( $mckutils::query{'orderID'} );
        $mckutils::orderID = $mckutils::query{'orderID'};
        $mckutils::query{'transflags'} =~ s/nonsf//g;
        $mckutils::query{'transflags'} =~ s/\,$//g;
        %resultCC = $payment->purchase("auth");
        if ( $resultCC{'FinalStatus'} ne "success" ) {
          my $price = sprintf( "%3s %.2f", "$mckutils::query{'currency'}", $resultGC{'amount'} );
          ## Void  GC transaction
          for ( my $i = 1 ; $i <= 3 ; $i++ ) {
            %result1 = &miscutils::sendmserver(
              $mckutils::query{'publisher-name'},
              "void", 'acct_code', $mckutils::query{'acct_code'},
              'acct_code4', "$mckutils::query{'acct_code4'}",
              'txn-type', 'marked', 'amount', "$price", 'order-id', "$tempOID"
            );
            last if ( $result1{'FinalStatus'} eq "success" );
          }
          if ( $result1{'FinalStatus'} eq "success" ) {
            $main::result{'aux-msg'}     = $result1{'aux-msg'};
            $main::result{'MStatus'}     = "failure";
            $main::result{'FinalStatus'} = "badcard";
            $mckutils::success           = "no";
            $voidstatus                  = "success";
          } else {
            $main::result{'aux-msg'}     = $result1{'aux-msg'};
            $main::result{'MStatus'}     = "failure";
            $main::result{'FinalStatus'} = "badcard";
            $mckutils::success           = "no";
            $voidstatus                  = "problem";
          }
          %result = %resultCC;
        } else {
          %result = %resultGC;
          $result{'auth-codeGC'} = substr( $resultGC{'auth-code'}, 0, 6 );
          $result{'auth-codeCC'} = substr( $resultCC{'auth-code'}, 0, 6 );
          $result{'amountGC'}    = $resultGC{'amount'};
          $result{'amountCC'}    = $resultGC{'card-amount'};
        }
      } else {
        %result = %resultGC;
      }
    } else {
      %result = $payment->purchase("auth");
    }

    $result{'auth-code'} = substr( $result{'auth-code'}, 0, 6 );

    if ( $result{'FinalStatus'} eq "success" ) {
      if ( $mckutils::feature{'convfee'} ne "" ) {
        my %result = &mckutils::convfee();
        if ( $result{'feeamt'} > 0 ) {
          $mckutils::query{'conv_fee_amt'}      = $result{'feeamt'};
          $mckutils::query{'conv_fee_acct'}     = $result{'feeacct'};
          $mckutils::query{'conv_fee_failrule'} = $result{'failrule'};
        }
      } elsif ( $mckutils::feature{'conv_fee'} ne "" ) {
        my ( $feeamt, $feeacct, $failrule ) = &mckutils::conv_fee();
        if ( $feeamt > 0 ) {
          $mckutils::query{'conv_fee_amt'}      = $feeamt;
          $mckutils::query{'conv_fee_acct'}     = $feeacct;
          $mckutils::query{'conv_fee_failrule'} = $failrule;
        }
      }
    }

    $payment->database();

    if ( ( $result{'FinalStatus'} eq "success" ) && ( $mckutils::query{'conv_fee_amt'} > 0 ) ) {
      my $origamt      = $mckutils::query{'card-amount'};
      my $origacct     = $mckutils::query{'publisher-name'};
      my $origemail    = $mckutils::query{'publisher-email'};
      my %orgifeatures = %mckutils::feature;

      $mckutils::query{'card-amount'}    = $mckutils::query{'conv_fee_amt'};
      $mckutils::query{'publisher-name'} = $mckutils::query{'conv_fee_acct'};
      my $tempOID = $mckutils::query{'orderID'};

      $mckutils::query{'orderID'} = PlugNPay::Transaction::TransactionProcessor::generateOrderID();

      $mckutils::orderID = $mckutils::query{'orderID'};
      $mckutils::query{'acct_code3'} = "CFC:$tempOID:$origacct";

      my %resultCF = $payment->purchase("auth");

      $payment->database();

      $result{'auth-codeCF'}   = substr( $resultCF{'auth-code'}, 0, 6 );
      $result{'FinalStatusCF'} = $resultCF{'FinalStatus'};
      $result{'MErrMsgCF'}     = $resultCF{'MErrMsg'};
      $result{'orderIDCF'}     = $mckutils::query{'orderID'};
      $result{'convfeeamt'}    = $mckutils::query{'conv_fee_amt'};

      my ( %result1, $voidstatus );

      if ( ( $resultCF{'FinalStatus'} ne "success" ) && ( $mckutils::query{'conv_fee_failrule'} eq "VOID" ) ) {
        my $price = sprintf( "%3s %.2f", "$mckutils::query{'currency'}", $resultCF{'amount'} );
        ## Void Main transaction
        for ( my $i = 1 ; $i <= 3 ; $i++ ) {
          %result1 = &miscutils::sendmserver(
            $origacct, "void", 'acct_code', $mckutils::query{'acct_code'},
            'acct_code4', "$mckutils::query{'acct_code4'}",
            'txn-type', 'auth', 'amount', "$price", 'order-id', "$tempOID"
          );
          last if ( $result1{'FinalStatus'} eq "success" );
        }
        $result{'voidstatus'}  = $result1{'FinalStatus'};
        $result{'FinalStatus'} = $resultCF{'FinalStatus'};
        $result{'MErrMsg'}     = $resultCF{'MErrMsg'};
      }
      if ( $resultCF{'FinalStatus'} eq "success" ) {
        $mckutils::query{'totalchrg'} = sprintf( "%.2f", $origamt + $mckutils::query{'conv_fee_amt'} );
      }
      %mckutils::result = ( %mckutils::result, %result );
      $mckutils::query{'card-amount'}     = $origamt;
      $mckutils::query{'publisher-name'}  = $origacct;
      $mckutils::query{'publisher-email'} = $origemail;
      %mckutils::feature                  = %orgifeatures;
      $mckutils::query{'orderID'}         = $tempOID;
      $mckutils::query{'convfeeamt'}      = $result{'convfeeamt'};

      delete $mckutils::query{'conv_fee_amt'};
      delete $mckutils::query{'conv_fee_acct'};
      delete $mckutils::query{'conv_fee_failrule'};

    }

    if ( $result{'FinalStatus'} eq "success" ) {
      eval {
        $payment->logFeesIfApplicable(\%mckutils::query, \%mckutils::result, $mckutils::adjustmentFlag, $mckutils::conv_fee_acct, $mckutils::conv_fee_oid);
      };
    }

    if ( $result{'dcctype'} ne 'twopass' || $query{'dccoptout'} ne '' ) {
      $payment->email();
    }

    %query = %mckutils::query;

    if ( ( $result{'FinalStatus'} eq "success" )
      && ( ( $mckutils::query{'receipt_type'} =~ /simple|itemized|pos_simple|pos_itemized/i ) || ( $mckutils::query{'receipt-type'} =~ /simple|itemized|pos_simple|pos_itemized/i ) ) ) {
      $payment->final();
      return;
    }
  }

  if ( $query{'mode'} !~ /^(auth|inputnew)$/ ) {
    my %logdata = &log_filter( \%result );
    my ( $d1, $now, $time ) = &miscutils::gendatetime();

    $smps::path_remotedebug =~ s/[^a-zA-Z0-9\_\-\.\/]//g;

    my $datalogData = {
      'originalLogFile' => $smps::path_remotedebug,
      'ipAddress'       => $ENV{'REMOTE_ADDR'},
      'scriptName'      => $ENV{'SCRIPT_NAME'},
      'securityLevel'   => $ENV{'SEC_LEVEL'},
      'host'            => $ENV{'SERVER_NAME'},
      'port'            => $ENV{'SERVER_PORT'},
      'browser'         => $ENV{'HTTP_USER_AGENT'},
      'requestMethod'   => $ENV{'REQUEST_METHOD'}
    };

    foreach my $key ( sort keys %logdata ) {
      $datalogData->{$key} = $logdata{$key};
    }

    &logToDataLog($datalogData);
  }

  # These are not determined by anything such as merchant username, etc,
  # so they have been moved to web/admin/templates/iphone to webtxt/templates/legacy/smps/iphone
  if ( $mckutils::query{'client'} eq "iphone" ) {
    my $file;
    my $path = '/home/pay1/webtxt/templates/legacy/smps/iphone/';
    if ( -e $path . "$query{'mode'}\_$result{'FinalStatus'}\_iphone.htm" ) {
      $file = $query{'mode'} . '_' . $result{'FinalStatus'} . '_iphone.htm';
    } elsif ( -e $path . "$result{'FinalStatus'}\_iphone.htm" ) {
      $file = $result{'FinalStatus'} . '_iphone.htm';
    } elsif ( -e $path . "$query{'mode'}\_iphone.htm" ) {
      $file = $query{'mode'} . '_iphone.htm';
    } else {
      $file = 'iphone.htm';
    }

    my @array = ( %query, %result );
    return &parse_template( $path, $file, @array );
  }

  ## redirect certain types of smps responses to mckutils final sub-function for custom receipt output.
  if ( ( ( $result{'FinalStatus'} =~ /^(success|pending)$/ ) && ( ( $query{'receipt_type'} ne "" ) || ( $query{'receipt-type'} ne "" ) ) )
    && ( ( $smps::chkprocessor eq "telecheckftf" ) && ( $query{'mode'} =~ /^(reauth)$/ ) && ( $query{'accttype'} =~ /^(checking|savings)$/ ) ) ) {
    my @array   = %query;
    my $payment = mckutils->new(@array);
    %mckutils::feature = %smps::feature;
    %mckutils::result  = %result;
    %mckutils::query   = %query;
    $payment->final();
    return;
  } elsif ( ( $result{'FinalStatus'} =~ /^(badcard|problem)$/ )
    && ( $smps::chkprocessor =~ /^(telecheck|telecheckftf)$/ )
    && ( $query{'mode'} =~ /^(auth)$/ )
    && ( $query{'accttype'} =~ /^(checking|savings)$/ )
    && ( ( $query{'receipt_type'} ne "" ) || ( $query{'receipt-type'} ne "" ) ) ) {
    my @array   = %query;
    my $payment = mckutils->new(@array);
    %mckutils::feature = %smps::feature;
    %mckutils::result  = %result;
    %mckutils::query   = %query;
    $payment->final();
    return;
  } elsif (
    ( $result{'FinalStatus'} =~ /^(badcard|problem)$/ ) && ( $smps::username =~ /^(jhew|jhrh|jhrr|jhdr|jhce|jhjd|jhst|jhtt|jhcn|jhgy)/ ) && ( $query{'mode'} =~ /^(auth)$/ )    ###  DCP 20121229
    && ( ( $query{'receipt_type'} ne "" ) || ( $query{'receipt-type'} ne "" ) )
    ) {
    my @array   = %query;
    my $payment = mckutils->new(@array);
    %mckutils::feature = %smps::feature;
    %mckutils::result  = %result;
    %mckutils::query   = %query;
    $payment->final();
    return;
  } elsif ( ( ( $result{'FinalStatus'} =~ /^(success|pending)$/ ) && ( ( $query{'receipt_type'} ne "" ) || ( $query{'receipt-type'} ne "" ) ) )
    && ( ( $smps::username =~ /^(nabixxxxcentra3|pnpdemo2|jamestu2)$/ ) && ( $query{'mode'} =~ /^(reauth|void|return)$/ ) ) ) {
    my @array   = %query;
    my $payment = mckutils->new(@array);
    %mckutils::feature = %smps::feature;
    %mckutils::result  = %result;
    %mckutils::query   = %query;
    $payment->final();
    return;
  }

  # 03/18/10 - fixed bug where we expect the head from the receipt_type, but transaction was not successful, so we need a display a different head
  if ( ( $smps::format !~ /^(text|download)$/ ) && ( ( $query{'receipt_type'} ne "" ) || ( $query{'receipt-type'} ne "" ) ) && ( $result{'FinalStatus'} ne "success" ) ) {
    print header( -type => 'text/html' );    ### DCP 20100719
    &head("Transaction");
  }

  # 09/08/05 - added this line to make the response show correctly, without causing an internal server error.

  my $shortcard = substr( $query{'card-number'}, 0, 4 ) . '**' . substr( $query{'card-number'}, -2, 2 );

  print "<div align=center>\n";
  print "<table>\n";
  if ( $result{'FinalStatus'} eq "success" ) {
    if ( ( $result{'dcctype'} eq "twopass" ) && ( $query{'dccoptout'} eq "" ) ) {
      print "<tr><td colspan=\"2\">\n";
      print "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
      print "<input type=\"hidden\" name=\"function\" value=\"inputnew\">\n";
      print "This credit card qualifies for DCC.  As a convenience to our international customers, \n";
      print "this purchase can be made in the home currency.  Today\'s exchange rate from $result{'currency'} is $result{'conv_rate'}.<p>\n";
      print "Please select below the amount you wish to charge the customer. Please note that your choice will be final.<p>\n";
      print "<input type=\"radio\" name=\"dccoptout\" value=\"Y\"> $result{'merch_sym'} $query{'card-amount'}<br>\n";
      print "<input type=\"radio\" name=\"dccoptout\" value=\"N\" checked> $result{'native_sym'} $result{'native_amt'}<br>\n";

      print "<b>PLEASE NOTE: The customer will not be charged until a choice has been submitted.</b><br>\n";
      print "<input type=\"submit\" value=\"Submit Payment\">\n";
      print "<input type=\"hidden\" name=\"dccinfo\" value=\"$result{'dccinfo'}\">\n";
      foreach my $key ( sort keys %query ) {
        if ( $key =~ /^(publisher-name|origacct)$/ ) {
          next;
        }
        print "<input type=\"hidden\" name=\"$key\" value=\"$query{$key}\">\n";
      }
      print "</form>\n";
      print "</td></tr>\n";
    } else {
      print "<tr><th colspan=2 align=\"left\">Your $transtype{$query{'mode'}} for $query{'currency'} $query{'card-amount'} was successful</th></tr>\n";
      print "<tr><td colspan=2 align=\"left\">\n";
      print "<table>\n";
      print "<tr><th align=\"right\">The order ID is:</th><td>$query{'orderID'}</td></tr>\n";
      print "<tr><th align=\"right\">The name is:</th><td>$query{'card-name'}</td></tr>\n";
      if ( $query{'mode'} ne "return" ) {
        print "<tr><th align=\"right\">The AVS Code is:</th><td>$result{'avs-code'}</td></tr>\n";
        my $auth_code = substr( $result{'auth-code'}, 0, 6 );
        print "<tr><th align=\"right\">The CVV Code is:</th><td>$result{'cvvresp'}</td></tr>\n";
        if ( $result{'auth-code'} ne "      " ) {
          print "<tr><th align=\"right\">The Auth Code is:</th><td>$auth_code</td></tr>\n";
        }
      }
      print "<tr><th align=\"right\">Credit Card # is:</th><td>$shortcard</td></tr>\n";
      if ( ( $query{'client'} =~ /(planetpay)/ ) && ( $result{'dccmsg'} ne "" ) ) {
        print "<tr><td colspan=\"2\">\n";
        print "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\" target=\"results\">\n";
        print "<input type=\"hidden\" name=\"function\" value=\"dccoptout\">\n";
        print "This credit card qualifies for DCC.  If the customers DOES NOT wish this transaction to settle to their credit card in the converted amount ";
        print "shown below please click on the button below.<br>\n";
        print "The conversion rate used was: $result{'conv_rate'}<br>\n";
        print "The converted amount is: $result{'native_sym'} $result{'native_amt'}<br>\n";
        print "<input type=\"hidden\" name=\"dccoptout\" value=\"Y\">\n";
        print "<input type=\"hidden\" name=\"publisher-name\" value=\"$mckutils::query{'publisher-name'}\"> \n";
        print "<input type=\"hidden\" name=\"mode\" value=\"dccoptout\"> \n";
        print "<input type=\"hidden\" name=\"orderID\" value=\"$mckutils::query{'orderID'}\"> \n";
        print "<input type=\"submit\" value=\"Please Settle this Transaction in US Dollars\" onClick=\"results();\">\n";
        print "</form>\n";
        print "</td></tr>\n";
      }
    }
    if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $result{'conv_rate'} != 0 ) ) {
      print "<tr><td colspan=\"2\" align=\"left\"><table>\n";
      print "<tr><th align=\"right\">Native Amount:</th><td>$result{'native_isocur'} $result{'native_amt'}</td></tr>\n";
      print "<tr><th align=\"right\">Conversion Rate:</th><td>$result{'conv_rate'}</td></tr>\n";
      print "</table></td></tr>\n";
    }
    print "</table>\n";
    print "</td></tr>\n";
  } elsif ( ( $result{'FinalStatus'} eq "pending" ) ) {
    ## DCP 20060420  replace smps::currency with result{'currency'}
    print "<tr><th align=\"left\" colspan=\"2\">Your $transtype{$query{'mode'}} for $query{'currency'} $query{'card-amount'} has been inserted into the batch database</th></tr>\n";
    print "<tr><td colspan=2 align=\"left\">\n";
    print "<table>\n";
    print "<tr><th align=\"right\">The order ID is:</th><td>$query{'orderID'}</td></tr>\n";
    if ( $query{'accttype'} =~ /^(checking|savings)$/ ) {

    } else {
      print "<tr><th align=\"right\">The name is:</th><td>$query{'card-name'}</td></tr>\n";
      print "<tr><th align=\"right\">Credit Card # is:</th><td>$shortcard</td></tr>\n";
    }
    print "</table>\n";
    print "</td></tr>\n";
  } else {
    print "<tr><th colspan=2 align=\"left\">Your $transtype{$query{'mode'}} for $query{'currency'} $query{'card-amount'} failed.</th></tr>\n";
    print "<tr><td colspan=2 align=\"left\">\n";
    print "<table>\n";
    print "<tr><th align=\"right\">Reason:</th><td> ";
    print "$result{'MErrLoc'} $result{'MErrMsg'} $result{'aux-msg'}";
    print "</td></tr>\n";
    print "</table>\n";
    print "</td></tr>\n";
  }
  print "</table>\n";

  if ( $ENV{'SERVER_NAME'} !~ /eci\-pay/i ) {
    my ($vt_url);
    if ( exists $query{'vt_url'} ) {
      $vt_url = $query{'vt_url'};
    } elsif ( exists $query{'vt-url'} ) {
      $vt_url = $query{'vt-url'};
    } else {
      $vt_url = $ENV{'SCRIPT_NAME'};
    }

    # 06/30/11 - added code to remove query strings from vt_url
    if ( $vt_url =~ /\?/ ) {
      my @temp = split( /\?/, $vt_url, 2 );
      $vt_url = $temp[0];
    }

    print "<table cellspacing=\"10\">\n";
    print "<tr>\n";
    print "<td> <a href=\"javascript:window.close();\">Close Window</a> </td>\n";

    # 06/30/11 - added code to limit where vt_url can redirect to
    if ( $vt_url =~ /(smps|virtualterm)\.cgi$/i ) {
      print "<td> <a href=\"$vt_url\">Enter another transaction.</a> </td>\n";
    } else {
      print "<td> <a href=\"#\" onClick=\"history.go(-1);\">Enter another transaction.</a> </td>\n";
    }
    print
      "<td> <a href=\"helpdesk.cgi\" target=\"ahelpdesk\" onClick=\"window.open('','ahelpdesk','width=550,height=520,toolbar=no,location=no,directories=no,status=no,menubar=no,scrollbars=yes,resizable=yes');\"> Help Desk</font></td>\n";
    print "</tr>\n";
    print "</table>\n";
  }

  print "</body>\n";
  print "</html>\n";

}


=pod

calculateReturnAdjustmentAmount()

Calculats the adjustment amount for a completed return using the rate
derived from the base amount and adjustment amount from the original auth

=cut

sub calculateReturnAdjustmentAmount {
  my $input = shift;

  my $returnTotalAmount  = $input->{'returnTotalAmount'};
  if (!defined $returnTotalAmount) {
    die("returnTotalAmount not defined");
  }

  my $authorizationBaseAmount = $input->{'authorizationBaseAmount'};
  if (!defined $authorizationBaseAmount) {
    die("authorizationBaseAmount not defined");
  }

  my $authorizationAdjustmentAmount = $input->{'authorizationAdjustmentAmount'};
  if (!defined $authorizationAdjustmentAmount) {
    die("authorizationAdjustmentAmount not defined");
  }
  my $adjustmentRate = $authorizationAdjustmentAmount / $authorizationBaseAmount;
  my $returnBaseAmount = $returnTotalAmount / (1.0 + $adjustmentRate);
  my $returnAdjustmentAmount = $returnTotalAmount - $returnBaseAmount;

  # significant digits (and rounding)
  $returnAdjustmentAmount = sprintf('%.2f',$returnAdjustmentAmount + .0001) + 0;
  return $returnAdjustmentAmount;
}

=pod

amountFromDatabaseAmountString()

Takes a string and attempts to pull the amount out of it

=cut

sub amountFromDatabaseAmountString {
  my $amountString = shift;
  my ($beginning,$end) =split(/ +/,$amountString);
  my $amount = $end || $beginning;
  $amount =~ s/[^\d\.]//g;

  if ($amount eq '') {
    die('Invalid amount string: ' . $amountString);
  }

  my @dots = grep { /\./ } split(//,$amount);
  if (@dots >=2) {
    die('Invalid amount, more than one period present: ' . $amountString);
  }

  return $amount;
}

=pod

currencyFromDatabaseAmountString()

Takes a string and attempts to pull the currency out of it

=cut

sub currencyFromDatabaseAmountString {
  my $currencyString = shift;
  my ($beginning,$end) =split(/ /,$currencyString);
  my $currency = lc substr($beginning,0,3);
  $currency =~ s/[^a-z]//g;

  if (length($currency) != 3) {
    die('Invalid currency string: ' . $currencyString);
  }

  return $currency;
}

=pod

calculateDisplayedBaseAmountAndAdjustment()

Calculates the base amount and adjustment to display for a transaction given
the adjustment log and the transaction type

=cut

sub calculateDisplayedBaseAmountAndAdjustment {
  my $input = shift;

  my $amount = $input->{'amount'};
  if (!defined $amount) {
    die("amount is not defined");
  }

  my $transactionType = $input->{'transactionType'};
  if (!defined $transactionType) {
    die("transationType is not defined");
  }

  my $adjustmentInfo = $input->{'adjustmentInfo'};

  my $baseAmount = $amount;
  my $adjustmentAmount = 0;

  if ( defined $adjustmentInfo ) {
    $baseAmount = $adjustmentInfo->getBaseAmount();
    if ( $transactionType eq "return" ) {
      $adjustmentAmount = calculateReturnAdjustmentAmount({
        returnTotalAmount => $amount,
        authorizationBaseAmount => $adjustmentInfo->getBaseAmount(),
        authorizationAdjustmentAmount => $adjustmentInfo->getAdjustmentAmount()
      });
      $baseAmount = $amount - $adjustmentAmount;
    } else {
      $adjustmentAmount = $adjustmentInfo->getAdjustmentAmount();
    }
  }

  $baseAmount = sprintf( "%0.2f", ( $baseAmount + 0.0001 ));
  $adjustmentAmount = sprintf( "%0.2f", ( $adjustmentAmount + 0.0001 ));

  return ($baseAmount,$adjustmentAmount);
}

=pod

calculateDisplayedBaseAmountAndAdjustmentForOperation()

Calculates the base amount and adjustment to display for a transaction given
the operation, adjustment log and the transaction type

=cut

sub calculateDisplayedBaseAmountAndAdjustmentForOperation {
  my $input = shift;

  my $operation = $input->{'operation'};
  if (!defined $operation) {
    die("operation is not defined");
  }

  # all these checked further down the call stack (or is it further up? hmm...)
  my $transactionType = $input->{'transactionType'};
  my $amount = $input->{'amount'};
  my $adjustmentInfo = $input->{'adjustmentInfo'};

  # data to return
  my $baseAmount = '0.00';
  my $adjustment = '0.00';

  if ($operation ne 'void' && $operation ne 'inquiry' && $operation ne 'settle') {
    # my $adjustmentInfo = $adjustmentHashRef->{$orderid};
    my $amt = amountFromDatabaseAmountString($amount);

    if ( defined $adjustmentInfo) {
      ($baseAmount, $adjustment) = calculateDisplayedBaseAmountAndAdjustment({
        amount => $amt,
        transactionType => $transactionType,
        adjustmentInfo => $adjustmentInfo
      });
    } else {
      $baseAmount = $amt;
    }
  }

  return {
    baseAmount => $baseAmount,
    adjustment => $adjustment
  };
}

sub query {
  my ( $adjustmentFlag, $surchargeFlag ) = getAdjustmentFlags();

  if ( -e "/home/pay1/outagefiles/highvolume.txt" ) {
    print "Sorry, this program is not available at this time.<p>\n";
    print "Please try back in a little while.<p>\n";
    return;
  }

  my ( $firstflag, %accounts, $batchtime, $org_decrypt, $rejectrpt );
  my $cardtype     = $smps::query->param('cardtype');
  my $form_txntype = $smps::query->param('txntype');
  my $txnstatus    = $smps::query->param('txnstatus');
  my $startdate    = $smps::query->param('startdate');
  my $enddate      = $smps::query->param('enddate');
  my $starthour    = $smps::query->param('starthour');
  my $endhour      = $smps::query->param('endhour');
  my $lowamount    = $smps::query->param('lowamount');
  $lowamount =~ s/[^0-9\.]//g;
  my $highamount = $smps::query->param('highamount');
  $highamount =~ s/[^0-9\.]//g;
  my $orderid = $smps::query->param('orderid');
  $orderid =~ s/[^a-zA_Z0-9\-]//g;
  my $acct_code = $smps::query->param('acct_code');
  $acct_code =~ s/[^a-zA-Z0-9\-\ \:\.]//g;
  my $acct_code2 = $smps::query->param('acct_code2');
  $acct_code2 =~ s/[^a-zA-Z0-9\-\ \:\.]//g;
  my $acct_code3 = $smps::query->param('acct_code3');
  $acct_code3 =~ s/[^a-zA-Z0-9\-\ \:\.]//g;
  my $acct_code4 = $smps::query->param('acct_code4');
  $acct_code4 =~ s/[^a-zA-Z0-9\-\ \:\.]//g;
  my $query_currency        = $smps::query->param('currency');
  my $splitacctcode         = $smps::query->param('splitacctcode');
  my $splitbtime            = $smps::query->param('splitbtime');
  my $omitfooter            = $smps::query->param('omitfooter');
  my $batchtimeflg          = $smps::query->param('batchtimeflg');
  my $exclude_representment = $smps::query->param('exclude_representment');
  my $cardname              = $smps::query->param('card-name');

  my $decrypt = $smps::query->param('decrypt');

  my $display_acct = $smps::query->param('display_acct');
  my $accttype     = $smps::query->param('accttype');

  my $startyear  = $smps::query->param('startyear');
  my $startmonth = $smps::query->param('startmonth');
  my $startday   = $smps::query->param('startday');

  $startyear =~ s/[^0-9]//g;
  $startmonth =~ s/[^0-9]//g;
  $startday =~ s/[^0-9]//g;

  my $hideprevious = $smps::query->param('hide_previous');
  my $refnumber    = $smps::query->param('refnumber');
  $refnumber =~ tr/a-z/A-Z/;
  if ( ( $smps::processor eq "catalunya" ) && ( $refnumber ne "" ) ) {
    $refnumber = substr( "0" x 12 . $refnumber, -12, 12 );
  }

  my $summaryonly = $smps::query->param('summaryonly');
  $summaryonly =~ s/[^a-zA-Z]//g;

  my $oidcn = $smps::query->param('oidcn');
  $oidcn =~ s/[^a-z]//g;
  if ( $oidcn ne "yes" ) {
    $oidcn = "";
  }

  my $partial = $smps::query->param('partial');

  my $display_errmsg = $smps::query->param('display_errmsg');

  if ( $form_txntype eq "chargeback" ) {
    $txnstatus = "";
    $accttype  = "checking";
  } elsif ( $form_txntype eq "representment" ) {
    $partial               = 1;
    $acct_code4            = "Representment";
    $accttype              = "checking";
    $form_txntype          = "";
    $exclude_representment = "";
  } elsif ( $form_txntype eq "rejectrpt" ) {
    $txnstatus             = "";
    $accttype              = "checking";
    $form_txntype          = "settled";
    $exclude_representment = "";
    $rejectrpt             = 1;
  }

  if ( ( $smps::username =~ /^(pnpdemo|pnpdemo2|billpaydem|willtest|reneeclark|seventwent|ipayfriendf|friendfind|onestepdem|avrdev)/ )
    || ( $ENV{'TECH'} ne "" )
    || ( $ENV{'REMOTE_ADDR'} =~ /(83\.149\.113\.151|217\.118\.66\.232|67\.165\.246\.136)/ ) ) {
    $decrypt = "";
  }

  if ( ( $smps::allow_overview == 1 ) && ( $ENV{'LOGIN'} =~ /^(jncb|premier2)$/ ) ) {
    $smps::feature{'decryptflag'}    = 1;
    $smps::feature{'decryptallflag'} = 1;
  }

  if ( $ENV{'TECH'} =~ /^(barbara|unplugged)$/ ) {
    $decrypt = $smps::query->param('decrypt');
  }

  if ( $ENV{'SEC_LEVEL'} > 7 || $smps::query->param('decrypt') ne 'yes' || $smps::feature{'decryptflag'} != 1 || $smps::feature{'decryptallflag'} != 1 ) {
    $decrypt = "";    #DCP  20091225
  }

  if ( ( $smps::feature{'bindetails'} == 1 ) && ( $summaryonly ne "yes" ) ) {
    $org_decrypt                     = $decrypt;
    $decrypt                         = 'yes';
    $smps::feature{'decryptallflag'} = 1;
    $smps::query->param( 'decrypt', 'yes' );
  } elsif ( ( $smps::feature{'display_cclast4'} == 1 ) && ( $summaryonly ne "yes" ) ) {
    $org_decrypt                     = $decrypt;
    $decrypt                         = 'yes';
    $smps::feature{'decryptallflag'} = 1;
    $smps::query->param( 'decrypt', 'yes' );
  }

  if ( ( $startyear >= 1999 ) && ( $startmonth >= 1 ) && ( $startmonth < 13 ) && ( $startday >= 1 ) && ( $startday < 32 ) ) {
    $startdate = sprintf( "%02d/%02d/%04d", $startmonth, $startday, $startyear );
  }

  my $tmpstartdate = substr( $startdate, 6, 4 ) . substr( $startdate, 0, 2 ) . substr( $startdate, 3, 2 );
  if ( $tmpstartdate < $smps::earliest_date ) {
    $startdate = substr( $smps::earliest_date, 4, 2 ) . "/" . substr( $smps::earliest_date, 6, 2 ) . "/" . substr( $smps::earliest_date, 0, 4 );
  }

  my ( $m, $d, $y ) = split( /\//, $startdate );
  my $startdatestr = sprintf( "%04d%02d%02d", $y, $m, $d );

  my $endyear  = $smps::query->param('endyear');
  my $endmonth = $smps::query->param('endmonth');
  my $endday   = $smps::query->param('endday');

  $endyear =~ s/[^0-9]//g;
  $endmonth =~ s/[^0-9]//g;
  $endday =~ s/[^0-9]//g;

  if ( ( $endyear >= 1999 ) && ( $endmonth >= 1 ) && ( $endmonth < 13 ) && ( $endday >= 1 ) && ( $endday < 32 ) ) {
    $enddate = sprintf( "%02d/%02d/%04d", $endmonth, $endday, $endyear );
  }

  ( $m, $d, $y ) = split( /\//, $enddate );
  my $enddatestr = sprintf( "%04d%02d%02d", $y, $m, $d );

  if ( $enddatestr < 19980000 ) {
    my $junk = "";
    ( $junk, $enddatestr ) = &miscutils::gendatetime( 24 * 60 * 60 );
  }

  my $starttimea = &miscutils::strtotime($startdatestr);
  my $endtimea   = &miscutils::strtotime($enddatestr);
  my $elapse     = $endtimea - $starttimea;

  if ( ( $form_txntype eq 'anm' ) && ( $elapse > ( 33 * 24 * 3600 ) ) ) {
    my $message = "Sorry, but for the \"Auth But Not Settled Query\" no more than 1 months may be queried at one time.  Please use the back button and change your selected date range.";
    print "$message\n";
    return;
  } elsif ( $elapse > ( 93 * 24 * 3600 ) ) {
    my $message = "Sorry, but no more than 3 months may be queried at one time.  Please use the back button and change your selected date range.";
    print "$message\n";
    return;
  } elsif ( ( $smps::query->param('cardnumber') eq "" ) && ( $smps::query->param('orderid') eq "" ) && ( $smps::username =~ /^(friendfind)/ ) && ( $elapse > ( 3 * 24 * 3600 ) ) ) {
    my $message =
      "Sorry, but no more than 3 days may be queried at one time unless searching for a specific orderid or credit card number.  Please use the back button and change your selected date range.";
    print "$message\n";
    return;
  }

  if ( ( $smps::username eq "knowled2" ) && ( $form_txntype eq "markret" ) ) {
    $form_txntype = "return";
  }

  my $cardnumber = $smps::query->param('cardnumber');
  my $routingnum = $smps::query->param('routingnum');
  my $accountnum = $smps::query->param('accountnum');

  if ( ( $routingnum ne "" ) && ( $accountnum ne "" ) && ( $cardnumber eq "" ) ) {
    $routingnum =~ s/[^0-9]//g;
    $accountnum =~ s/[^0-9]//g;
    $cardnumber = "$routingnum $accountnum";
    $accttype   = 'checking';
  } else {
    $cardnumber =~ s/[^0-9\*]//g;
  }

  if ( ( $oidcn eq "yes" ) && ( $orderid ne "" ) && ( $cardnumber eq "" ) ) {
    $cardnumber = &getcn( "$orderid", "$startdatestr", "$enddatestr" );
  }

  my ( $first4, $last4, $last2, $partialstr );
  if ( $cardnumber =~ /(\d+)\*+(\d+)/ ) {
    $first4 = $1;
    $first4 = substr( $first4, 0, 4 );
    $last4  = $2;
    $last2  = substr( $last4, -2, 2 );
    if ( length($last4) >= 4 ) {
      $last4 = substr( $last4, 0, 4 );
    } else {
      $last4 = "";
    }
    $partialstr = "$first4" . "%" . "$last2";
  }

  my $shortcard = substr( $cardnumber, 0, 4 ) . "**" . substr( $cardnumber, -2, 2 );

  my ( $rejectrpttype, @orderidarray, %chargebackhash, %returnTime, $DisplayStartDate );

  $DisplayStartDate = $startdate;

  @orderidarray = ($orderid);

  if ( $cardnumber ne "" ) {
    my ( $checkusername, $trans_date, $orderid, $chkshacardnumber, $shaflag );
    my $cc         = new PlugNPay::CreditCard($cardnumber);
    my @cardHashes = $cc->getCardHashArray();

    my ( $m, $d, $y ) = split( /\//, $startdate );
    my $startdatestr = sprintf( "%04d%02d%02d", $y, $m, $d );

    if ( $startdatestr < $smps::earliest_date ) {
      $startdatestr = $smps::earliest_date;
    }

    if ( $startdatestr < "19990101" ) {
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 30 * 2 ) );
      my $twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
      $startdatestr = $twomonthsago;
    }

    @orderidarray = ();

    my $dbh = &miscutils::dbhconnect( "pnpdata", "", "$smps::username" );    ## Op_Log
    my @queryArray = ();

    my $qstr = "select orderid,shacardnumber from operation_log ";
    push( @queryArray, $startdatestr, $enddatestr );

    if ( $partialstr ne "" ) {
      $qstr .= " FORCE INDEX(oplog_tdateuname_idx) where trans_date>=? and trans_date<=? ";
      if ( exists $smps::altaccts{$smps::username} ) {
        my ($qmarks);
        foreach my $var ( @{ $smps::altaccts{$smps::username} } ) {
          $qmarks .= '?,';
          $accounts{$var} = 1;
        }
        chop $qmarks;
        $qstr .= " and username IN ($qmarks) ";
        push( @queryArray, values %accounts );
      } elsif ( $smps::fuzzyun ne "" ) {
        $qstr .= " and username LIKE ? ";
        push( @queryArray, "$smps::fuzzyun%" );
      } elsif ( $smps::linked_accts ne "" ) {
        my ($qmarks);
        my $linkAccts = $smps::linked_accts;
        $linkAccts =~ s/[^a-z0-9\,]//g;
        my @tempArray = split($linkAccts);
        foreach my $var (@tempArray) {
          $qmarks .= '?,';
        }
        chop $qmarks;
        $qstr .= " and username IN ($qmarks) ";
        push( @queryArray, @tempArray );
      } else {
        $qstr .= " and username=? ";
        push( @queryArray, $smps::username );
      }
      $qstr .= " and card_number LIKE ? ";
      push( @queryArray, $partialstr );
    } else {
      $qstr .= " FORCE INDEX(oplog_tdatesha_idx) where trans_date>=? and trans_date<=? ";
      my $qmarks = '?' . ',?' x ($#cardHashes);
      $qstr .= " and shacardnumber in ($qmarks)";
      push( @queryArray, @cardHashes );

      if ( exists $smps::altaccts{$smps::username} ) {
        my ( $temp, $qmarks );
        foreach my $var ( @{ $smps::altaccts{$smps::username} } ) {
          $qmarks .= '?,';
          $accounts{$var} = 1;
        }
        chop $qmarks;
        $qstr .= " and username IN ($qmarks) ";
        push( @queryArray, values %accounts );
      } elsif ( $smps::fuzzyun ne "" ) {
        $qstr .= " and username LIKE ? ";
        push( @queryArray, "$smps::fuzzyun%" );
      } elsif ( $smps::linked_accts ne "" ) {
        my ($qmarks);
        my $linkAccts = $smps::linked_accts;
        $linkAccts =~ s/[^a-z0-9\,]//g;
        my @tempArray = split($linkAccts);
        foreach my $var (@tempArray) {
          $qmarks .= '?,';
        }
        chop $qmarks;
        $qstr .= " and username IN ($qmarks) ";
        push( @queryArray, @tempArray );
      } else {
        $qstr .= " and username=? ";
        push( @queryArray, $smps::username );
      }
    }

    my $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
    $sth->execute(@queryArray) or die "Can't execute: $DBI::errstr";
    my $rv = $sth->bind_columns( undef, \( $orderid, $chkshacardnumber ) );

    while ( $sth->fetch ) {
      if ( $cc->compareHash($chkshacardnumber) ) {
        if ( $shaflag != 1 ) {
          @orderidarray = ($orderid);
        } else {
          $orderidarray[ ++$#orderidarray ] = "$orderid";
        }
        $shaflag = 1;
        $decrypt = "yes";
      } elsif ( $shaflag != 1 ) {
        $orderidarray[ ++$#orderidarray ] = "$orderid";
      }
    }
    $sth->finish;
    $dbh->disconnect;

    if ( $shaflag == 1 ) {
      print "<b>The following were exact matches of the credit card number entered.</b><br>\n";
    } else {
      print "<b>An exact card match could not be found.</b><br>\n";
    }
  } elsif ( ( $rejectrpt == 1 ) && ( $batchtimeflg eq "yes" ) ) {
    my $i = 0;
    my $j = 0;
    my $k = 0;
    my ( $transdate, $transtime, $acct_code, $acct_code2, $acct_code3, $acct_code4, $tmp_oid, $descr );
    my $dbh = &miscutils::dbhconnect( "pnpdata", "", "$smps::username" );    ## Op_Log
    ### Query for any chargebacks in date range.
    my $qstr =
      "select orderid,trans_date,trans_time,descr,acct_code,acct_code2,acct_code3,acct_code4 from trans_log FORCE INDEX(tlog_tdateuname_idx) where trans_date>=? and trans_date<? and username=?  and operation='chargeback' and accttype='checking' and (duplicate is null or duplicate='') order by trans_time ";
    my $sth = $dbh->prepare(qq{$qstr}) or die "dead prep $orderid $smps::username\n";
    $sth->execute( "$startdatestr", "$enddatestr", "$smps::username" ) or die "dead exe $orderid $smps::username\n";
    $sth->bind_columns( undef, \( $orderid, $transdate, $transtime, $descr, $acct_code, $acct_code2, $acct_code3, $acct_code4 ) );
    while ( $sth->fetch ) {
      $i++;
      if ( ( $smps::settletimezone ne "" ) && ( $smps::settletimezone != 0 ) ) {
        $transtime = &miscutils::strtotime($transtime);
        $transtime += ( $smps::settletimezone * 60 * 60 );
        $transtime = &miscutils::timetostr($transtime);
      }
      if ( $acct_code4 =~ /Representment\:([0-2F]+)/ ) {
        $returnTime{$acct_code3} = $transtime;
        $tmp_oid = $acct_code3;
        $j++;
      } else {
        $returnTime{$orderid} = $transtime;
        $tmp_oid = $orderid;
        if ( $descr =~ /^R01/ ) {
          $k++;
        }
      }
      $chargebackhash{$orderid} = $transtime;
    }
    $sth->finish();
    $dbh->disconnect;

    my $starttime = $startdatestr . "000000";
    $starttime = &miscutils::strtotime($starttime);
    $starttime -= ( 20 * 24 * 3600 );
    $starttime = &miscutils::timetostr($starttime);
    $startdate = substr( $starttime, 0, 8 );
    $startdate = substr( $startdate, 4, 2 ) . "/" . substr( $startdate, 6, 2 ) . "/" . substr( $startdate, 0, 4 );

    $batchtimeflg  = "";
    $rejectrpttype = 'submitted';

  }

  my $invoicenum = $smps::query->param('invoicenum');
  $invoicenum =~ s/[^0-9\-]//g;

  if ( ( $invoicenum ne "" ) && ( $smps::username =~ /^om/ ) && ( $smps::processor eq "global" ) ) {
    my ( $trans_date, $orderid );
    my ( $m, $d, $y ) = split( /\//, $startdate );
    my $startdatestr = sprintf( "%04d%02d%02d", $y, $m, $d );
    if ( $startdatestr < $smps::earliest_date ) {
      $startdatestr = $smps::earliest_date;
    }

    if ( $startdatestr < "19990101" ) {
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 30 * 2 ) );
      my $twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
      $startdatestr = $twomonthsago;
    }

    @orderidarray = ();

    my $dbh = &miscutils::dbhconnect( "pnpdata", "", "$smps::username" );
    my $qstr = "select orderid from trans_log FORCE INDEX(tlog_tdateuname_idx) ";
    $qstr .= " where trans_date>='$startdatestr' and trans_date<='$enddatestr' ";
    if ( exists $smps::altaccts{$smps::username} ) {
      my ($temp);
      foreach my $var ( @{ $smps::altaccts{$smps::username} } ) {
        $temp .= "'$var',";
        $accounts{$var} = 1;
      }
      chop $temp;
      $qstr .= " and username IN ($temp) ";
    } else {
      $qstr .= " and username='$smps::username' ";
    }
    $qstr .= " and operation='auth' ";
    $qstr .= " and auth_code LIKE '%$invoicenum%' ";

    my $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
    $sth->execute or die "Can't execute: $DBI::errstr";
    my $rv = $sth->bind_columns( undef, \($orderid) );
    while ( $sth->fetch ) {
      $orderidarray[ ++$#orderidarray ] = "$orderid";
    }
    $sth->finish;
    $dbh->disconnect;
  }

  if ( $summaryonly ne "yes" ) {
    if ( $smps::format !~ /^(text|download)$/ ) {
      if ( $firstflag == 0 ) {
        print "<table border=1 cellspacing=0 cellpadding=2>\n";
        print "<tr><th align=left>Start Date</th><td align=left>$DisplayStartDate</td></tr>\n";
        print "<tr><th align=left>End Date</th><td align=left>$enddate</td></tr>\n";
        print "<tr><th align=left>Account Type</th><td align=left>$smps::accttype</td></tr>\n";
        print "</table>\n";

        print "<br><table class=\"tablesorter\ {sortlist: [[3,0]]}\" id=\"sortabletable\" border=1 cellspacing=0 cellpadding=2>\n";
        print "<thead>\n";
        print "<tr>\n";
        print "<th id=\"zebrasort\" align=left>Type</th>";
        if ( $smps::merchant eq "ALL" ) {
          print "<th align=left>Acct Name</th>";
        }
        print "<th align=left>Name</th>";
        print "<th align=left>Status</th>";
        print "<th class=\"{sorter: 'text'}\" id=\"nozebra\" align=left>Order ID</th>";
        if ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) {
          print "<th>Transaction Time<font size=-2><br>(GMT $smps::settletimezone)<br>MM/DD/YYYY HH:MM:SS</font></th>";
          print "<th>Time Received<font size=-2><br>(GMT $smps::settletimezone)<br>MM/DD/YYYY HH:MM:SS</font></th>";
          print "<th align=left>Card Number</th>";
          print "<th align=left>Exp</th>";
          print "<th class=\"{sorter: 'digit'}\" align=left>Amount</th>\n";
          if ( $adjustmentFlag == 1 ) {
            print "<th align=\"left\">Base Amount</th>\n";
            if ( $surchargeFlag == 1 ) {
              print "<th align=\"left\">Credit Card Fee</th>\n";
            } else {
              print "<th align=\"left\">Service Fee</th>\n";
            }
          }

          if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
            print "<th align=\"left\">Converted Amount</th>\n";
            print "<th align=\"left\">Conversion Rate</th>\n";
          }
          print "<th class=\"{sorter: false}\" id=\"nozebra\" align=left>Auth<br>Code</th>\n";
          if ( $smps::processor =~ /^(wirecard|banistmo|epx|catalunya)$/ ) {
            print "<th align=left>Reference #</th>\n";
          }
          if ( $smps::industrycode =~ /^(retail|restuarant|petroleum)$/ ) {
            print "<th align=left>Entry Method</th>\n";
          }
        } else {
          print "<th align=center>Auth Time <font size=-2>(GMT $smps::settletimezone)<br>MM/DD/YYYY HH:MM:SS</font></th>";
          if ( ( $rejectrpt == 1 ) && ( $rejectrpttype eq "submitted" ) ) {
            print "<th>Return Time <font size=-2>(GMT $smps::settletimezone)<br>MM/DD/YYYY HH:MM:SS</font></th>";
          } else {
            print "<th>Transaction Time <font size=-2>(GMT $smps::settletimezone)<br>MM/DD/YYYY HH:MM:SS</font></th>";
          }
          print "<th align=left>Routing/Acct Number</th>";
          print "<th align=left>Amount</th>\n";
          if ( $adjustmentFlag == 1 ) {
            print "<th align=\"left\">Base Amount</th>\n";
            if ( $surchargeFlag == 1 ) {
              print "<th align=\"left\">Credit Card Fee</th>\n";
            } else {
              print "<th align=\"left\">Service Fee</th>\n";
            }
          }
        }
        if ( $accttype =~ /checking|savings/ ) {
          print "<th>SEC Code</th>\n";
        }
        if ( $display_acct eq "yes" ) {
          print "<th align=left>Acct Code1</th>";
          print "<th align=left>Acct Code2</th>\n";
          print "<th align=left>Acct Code3</th>\n";
          print "<th align=left>Acct Code4</th>\n";
        }
        if ( $smps::processor eq "fdmsnorth" ) {
          print "<th align=left>Free Form Data</th>\n";
        }
        print "<th align=left>Bank Response</th>\n";
        if ( $rejectrpt == 1 ) {
          print "<th align=left>ACH Status</th>\n";
        }
        if ( $form_txntype eq "batch" ) {
          print "<th align=left>Batch ID</th>\n";
        }
        if ( $smps::feature{'bindetails'} == 1 ) {
          print "<th>Region</th>\n";
          print "<th>Country</th>\n";
          print "<th>Debit</th>\n";
          print "<th>Prod. Type</th>\n";
        }
        $firstflag = 1;
      }
      print "</thead>\n";
      print "<tbody>\n";
    } else {
      if ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) {
        if ( $smps::merchant eq "ALL" ) {
          print "Acct Name\t";
        }
        print "Type\tName\tStatus\tOrderID\tTime\tCardNumber\tExpDate\t";
        if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
          print "Currency\t";
        }
        print "Amount\t";
        if ( $adjustmentFlag == 1 ) {
          print "BaseAmount\t";
          if ( $surchargeFlag == 1 ) {
            print "CreditCardFee\t";
          } else {
            print "ServiceFee\t";
          }
        }
        print "AuthCode\tAcctCode\tAcctCode2\tAcctCode3";
        if ( ( $smps::username =~ /restaurant|emslanalyt|hvinvestm|americanch3/ ) || ( $smps::reseller =~ /^(affinisc|lawpay)$/ ) || ( $smps::merchstrt > 20070101 ) || ( $smps::feature{'display_ac4'} == 1 ) )
        {
          print "\tAcctCode4";
        }
        if ( $smps::processor =~ /^(wirecard|banistmo|epx|catalunya)$/ ) {
          print "\tReferenceNo";
        }
        if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
          print "\tConvertedCurrency\tConvertedAmount\tConversionRate";
        }
        print "\tBatchTime";
        if ( $display_errmsg eq "yes" ) {
          print "\tErrMsg";
        }
        if ( $smps::reseller =~ /^premier2/ ) {
          print "\tCountry\tAVSCode\tCVVRESP";
        }
        if ( $form_txntype eq "batch" ) {
          print "\tBatchID";
        }
        if ( $smps::feature{'bindetails'} == 1 ) {
          print "\tREGION\tCOUNTRY\tDEBIT\tPRODTYPE";
        }
        print "\tIPaddress";
        print "\tCurrency";
        print "\r\n";
      } else {
        if ( $smps::merchant eq "ALL" ) {
          print "Acct Name\t";
        }
        print "Type\tName\tStatus\tOrderID\tTime\tCardNumber\tExpDate\tAmount\t";
        if ( $adjustmentFlag == 1 ) {
          print "BaseAmount\t";
          if ( $surchargeFlag == 1 ) {
            print "CreditCardFee\t";
          } else {
            print "ServiceFee\t";
          }
        }
        print "AuthCode\tAcctCode\tAcctCode2\tAcctCode3";
        if ( ( $smps::username =~ /restaurant|emslanalyt|hvinvestm|americanch3/ ) || ( $smps::reseller =~ /^(affinisc|lawpay)$/ ) || ( $smps::merchstrt > 20070101 ) || ( $smps::feature{'display_ac4'} == 1 ) )
        {
          print "\tAcctCode4";
        }
        print "\tAuthTime";
        if ( $smps::processor =~ /^(wirecard|banistmo|epx|catalunya)$/ ) {
          print "\tReferenceNo";
        }
        if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
          print "\tConvertedCurrency\tConvertedAmount\tConversionRate";
        }
        if ( $display_errmsg eq "yes" ) {
          print "\tErrMsg";
        }
        if ( $form_txntype eq "batch" ) {
          print "\tBatchID";
        }
        print "\tIPaddress";
        print "\tCurrency";
        print "\r\n";
      }
    }
  }

  if ( $lowamount ne "" ) {
    $lowamount = sprintf( "%.2f", $lowamount );
  }
  if ( $highamount > 0 ) {
    $highamount = sprintf( "%.2f", $highamount );
  }

  my ( $starttime, $endtime, $orderidold, $maxtime );

  if ( $startdate ne "" ) {
    my ( $m, $d, $y ) = split( /\//, $startdate );
    if ( $starthour eq "" ) {
      $starttime = sprintf( "%04d%02d%02d000000", $y, $m, $d );
    } else {
      $starttime = sprintf( "%04d%02d%02d%02d0000", $y, $m, $d, $starthour );
    }
    if ( $smps::settletimezone ne "" ) {
      $starttime = &miscutils::strtotime($starttime);
      $starttime -= ( $smps::settletimezone * 60 * 60 );
      $starttime = &miscutils::timetostr($starttime);
    }
    if ( $starttime < '19990101000000' ) {
      $starttime = "";
      $startdate = "";
    }
  }
  if ( $enddate ne "" ) {
    my ( $m, $d, $y ) = split( /\//, $enddate );
    if ( $endhour eq "" ) {
      $endtime = sprintf( "%04d%02d%02d000000", $y, $m, $d );
    } else {
      $endtime = sprintf( "%04d%02d%02d%02d0000", $y, $m, $d, $endhour );
    }
    if ( $smps::settletimezone ne "" ) {
      $endtime = &miscutils::strtotime($endtime);
      $endtime -= ( $smps::settletimezone * 60 * 60 );
      $endtime = &miscutils::timetostr($endtime);
    }
  }
  my ( $ct, $cb_sum, $cb_cnt, $rt_sum, $rt_cnt, $cbt_sum, $cbt_cnt, $rtt_sum, $rtt_cnt );
  if ( $smps::processor eq "catalunya" ) {
    ( $ct, $cb_sum, $cb_cnt, $cbt_sum, $cbt_cnt ) = &query_chargeback( $starttime, $endtime );
  }

  my $i = 0;
  my ( %result, %total, %cardtotals, %failtotal, %failcardtotals, %bindata );
  my ( %ntotal, %ncardtotals, %nfailtotal, %nfailcardtotals, %tcardtotals, %txntype, %customercnt );
  my %currency_types = ();
  my $query_endtime  = "";

  if ( $batchtimeflg eq "yes" ) {
    $batchtime     = $starttime;
    $query_endtime = &miscutils::strtotime($endtime);
    $query_endtime += ( 7 * 24 * 60 * 60 );
    $query_endtime = &miscutils::timetostr($query_endtime);
  } else {
    $query_endtime = $endtime;
  }

  foreach my $vorderid ( sort @orderidarray ) {
    if ( ( $vorderid eq $orderidold ) && ( $vorderid ne "" ) ) {
      next;
    }
    if ( exists $smps::altaccts{$smps::username} ) {
      if ( ( $smps::query->param('decrypt') ne "yes" ) || ( $smps::feature{'decryptallflag'} != 1 ) ) {
        $decrypt = "";
      }
      my ($i);
      foreach my $var ( @{ $smps::altaccts{$smps::username} } ) {
        my %res_icg = &miscutils::sendmserver(
          "$var",       'query',       'accttype',   "$accttype",  'order-id', "$vorderid",     'start-time', "$starttime", 'batch-time', "$batchtime",  'end-time',   "$query_endtime",
          'card-type',  "$cardtype",   'txn-status', "$txnstatus", 'txn-type', "$form_txntype", 'acct_code',  "$acct_code", 'acct_code2', "$acct_code2", 'acct_code3', "$acct_code3",
          'acct_code4', "$acct_code4", 'card-name',  "$cardname",  'decrypt',  "$decrypt",      'refnumber',  "$refnumber", 'partial',    "$partial"
        );
        foreach my $key ( keys %res_icg ) {
          $i++;
          $result{"a$i"} = $res_icg{$key} . "\&username=$var";
        }
      }
    } else {
      if ( ( $smps::query->param('decrypt') ne "yes" ) || ( $smps::feature{'decryptallflag'} != 1 ) ) {
        $decrypt = "";
      }
      %result = &miscutils::sendmserver(
        "$smps::username", 'query',               'accttype',  "$accttype",      'order-id',   "$vorderid",   'start-time', "$starttime",
        'batch-time',      "$batchtime",          'end-time',  "$query_endtime", 'card-type',  "$cardtype",   'txn-status', "$txnstatus",
        'txn-type',        "$form_txntype",       'acct_code', "$acct_code",     'acct_code2', "$acct_code2", 'acct_code3', "$acct_code3",
        'acct_code4',      "$acct_code4",         'card-name', "$cardname",      'decrypt',    "$decrypt",    'refnumber',  "$refnumber",
        'linked_accts',    "$smps::linked_accts", 'fuzzyun',   "$smps::fuzzyun", 'partial',    "$partial",    'low-amount', "$lowamount",
        'high-amount',     "$highamount"
      );
    }

    my ( %cardtype, %lasttran, %dupcheck );

    my @values = values %result;

    ## Added DCP 20040824
    %result = ();

    my $old_orderid;
    my $color      = 0;
    my @queryorder = ();
    my (%queryresults);
    my ( %operations, %orderOperations, %orderFinalStatus, %orderAge, %representment1, %representment2, %representmentF, %ac3hash );

    foreach my $var ( sort @values ) {
      my %res2 = ();
      my @nameval = split( /&/, $var );
      foreach my $temp (@nameval) {
        my ( $name, $value ) = split( /=/, $temp );
        $res2{$name} = $value;
      }
      if ( $res2{'time'} eq "" ) {
        next;
      }

      my $testamt = substr( $res2{'amount'}, 4 );
      if ( ( $lowamount >= 0 ) && ( $highamount > $lowamount ) ) {
        if ( ( $testamt < $lowamount ) || ( $testamt > $highamount ) ) {
          next;
        }
      } elsif ( ( ( $lowamount > 0 ) && ( $highamount eq "" ) ) && ( $testamt != $lowamount ) ) {
        next;
      }

      my $oid = $res2{'order-id'};
      my $op  = $res2{'txn-type'};
      my $fs  = $res2{'txn-status'};
      my $ac3 = $res2{'acct_code3'};
      $ac3 =~ s/%(..)/pack('c',hex($1))/eg;

      my $tt = $res2{'time'};
      $tt = &miscutils::strtotime($tt);
      my $agedays = ( time() - $tt ) / ( 24 * 3600 );

      $orderOperations{$oid}{$op} = $var;
      $orderFinalStatus{$oid}     = $fs;
      $orderAge{$oid}             = $agedays;
      $ac3hash{$oid}              = $ac3;

      if ( $rejectrpt == 1 ) {
        if ( $res2{'acct_code4'} =~ /Representment\:([0-2F]+)/ ) {
          if ( $1 =~ /^1/ ) {
            $representment1{ $res2{'acct_code3'} } = $res2{'order-id'};
          } elsif ( $1 =~ /^2/ ) {
            $representment2{ $ac3hash{ $res2{'acct_code3'} } } = $res2{'order-id'};
          }
          next;
        }
        if ( $res2{'txn-status'} ne "badcard" ) {
          next;
        }
        if ( ( $rejectrpttype eq 'submitted' ) && ( !exists $returnTime{$oid} ) ) {
          next;
        }
      }

      if ( !exists $operations{ $res2{'order-id'} } ) {
        push( @queryorder, $res2{'order-id'} );
      }
      $operations{ $res2{'order-id'} } = $res2{'txn-type'};
    }

    my $adjustmentHashRef = {};
    if ( $adjustmentFlag == 1 ) {
      if (@queryorder) {
        $adjustmentHashRef = loadMultipleAdjustments( \@queryorder );
      }
    }

    my $i = 0;
    my $j = 0;
    foreach my $oid (@queryorder) {
      foreach my $op ( sort keys %{ $orderOperations{$oid} } ) {
        my $var     = $orderOperations{$oid}{$op};
        my %res2    = ();
        my @nameval = split( /&/, $var );
        foreach my $temp (@nameval) {
          my ( $name, $value ) = split( /=/, $temp );
          $value =~ s/%(..)/pack('c',hex($1))/eg;
          $res2{$name} = $value;
        }
        if ( $res2{'time'} eq "" ) {
          next;
        }
        $smps::trancount++;
        my $time = $res2{"time"};
        if ( ( $smps::settletimezone ne "" ) && ( $smps::settletimezone != 0 ) ) {
          $time = &miscutils::strtotime($time);
          $time += ( $smps::settletimezone * 60 * 60 );
          $time = &miscutils::timetostr($time);
        }

        if ( $time > $maxtime ) {
          $maxtime = $time;
        }
        if ( ( $hideprevious eq "yes" ) && ( $smps::lasttrantime ne "" ) ) {
          if ( $time <= $smps::lasttrantime ) {
            next;
          }
        }

        my $timestr = substr( $time, 4, 2 ) . "/" . substr( $time, 6, 2 ) . "/" . substr( $time, 0, 4 ) . " ";
        $timestr = $timestr . substr( $time, 8, 2 ) . ":" . substr( $time, 10, 2 ) . ":" . substr( $time, 12, 2 );

        my $sortabletime = substr( $time, 0, 14 );    # allows date and time to be sorted properly

        my $txntype    = $res2{"txn-type"};
        my $origin     = $res2{"origin"};
        my $status     = $res2{"txn-status"};
        my $orderid    = $res2{"order-id"};
        my $cardnumber = $res2{"card-number"};
        my $exp        = $res2{"card-exp"};
        my $amount     = $res2{"amount"};
        my $authcode   = substr( $res2{"auth-code"}, 0, 6 );
        my $cardname   = $res2{'card-name'};
        my $acctcode   = $res2{'acct_code'};
        my $acctcode2  = $res2{'acct_code2'};
        my $acctcode3  = $res2{'acct_code3'};
        my $acctcode4  = $res2{'acct_code4'};
        my $cardtype   = $res2{'card-type'};
        my $batch_time = $res2{'batch_time'};
        my $refnumber  = $res2{'merch-txn'};
        my $descr      = $res2{'descr'};
        my $merchant   = $res2{'username'};
        my $checktype  = substr( $res2{"auth-code"}, 6, 3 );
        my $country    = $res2{'card-country'};
        my $avscode    = $res2{'avs-code'};
        my $cvvresp    = $res2{'cvvresp'};
        my $batchid    = $res2{'batch-id'};
        my $transflags = $res2{'transflags'};
        my $ipaddress  = $res2{'ipaddress'};

        my $entrymethod = "";

        my $calculatedBaseAmountAndAdjustment = calculateDisplayedBaseAmountAndAdjustmentForOperation({
          adjustmentInfo => $adjustmentHashRef->{$orderid},
          amount => $amount,
          transactionType => $txntype,
          operation => $op
        });

        my $baseAmount = $calculatedBaseAmountAndAdjustment->{'baseAmount'};
        my $adjustment = $calculatedBaseAmountAndAdjustment->{'adjustment'};

        if ( $smps::industrycode =~ /^(retail|restuarant|petroleum)$/ ) {
          if ( $txntype eq "auth" ) {
            $entrymethod = &entrymethod( $res2{'auth-code'}, $res2{'cardextra'} );
          } else {
            $entrymethod = "&nbsp;";
          }
        }
        if ( ( $smps::username =~ /^(jhcorp)$/ )
          && ( $smps::merchant eq "ALL" )
          && ( $ENV{'LOGIN'} =~ /^cc\d{4}/ )
          && ( $accttype =~ /^(checking|savings)$/ )
          && ( $acctcode !~ /$smps::feature{'linked_accts'}/ ) ) {
          next;
        }

        if ( ( $exclude_representment == 1 ) && ( $acctcode4 =~ /Representment/i ) ) {
          next;
        }
        ###  Address Info added 20110713
        my $card_address = $res2{'card-addr'};
        my $card_city    = $res2{'card-city'};
        my $card_state   = $res2{'card-state'};
        my $card_zip     = $res2{'card-zip'};
        my $card_country = $res2{'card-country'};

        my $representment_status = "";
        my $tran_status          = "";

        if ( ( $rejectrpt == 1 ) && ( $rejectrpttype eq 'submitted' ) ) {
          if ( ( $descr !~ /^R01:/ ) && ( exists $chargebackhash{$orderid} ) ) {
            $representment_status = "Final Rejection - Not subject to represent.";
            $tran_status          = "$status";
          } elsif ( ( exists $representment2{$orderid} ) && ( exists $chargebackhash{ $representment2{$orderid} } ) ) {    #2 Representments
            $representment_status = "2nd & Final Representment Status - $orderFinalStatus{$representment2{$orderid}}";
            $tran_status          = "$orderFinalStatus{$representment2{$orderid}}";
            if ( $tran_status =~ /success|pending/ ) {
              next;
            }
          } elsif ( ( exists $representment1{$orderid} ) && ( exists $chargebackhash{ $representment1{$orderid} } ) ) {
            if ( $smps::feature{'ach_repre_limit'} == 2 ) {
              $representment_status = "1st Representment Status - $orderFinalStatus{$representment1{$orderid}}";
              $tran_status          = "pending";
            } else {
              $representment_status = "1st & Last Representment Status - $orderFinalStatus{$representment1{$orderid}}";
              $tran_status          = "$orderFinalStatus{$representment1{$orderid}}";
            }
            if ( $tran_status =~ /success|pending/ ) {
              next;
            }
          } elsif ( exists $chargebackhash{$orderid} ) {
            next;
          }

          if ( $tran_status eq "" ) {
            next;
          }
        } elsif ( $rejectrpt == 1 ) {
          if ( $descr !~ /^R01:/ ) {
            $representment_status = "Final Rejection - Not subject to represent.";
            $tran_status          = "$status";
          } elsif ( exists $representment2{$orderid} ) {    #2 Representments
            $representment_status = "2nd & Final Representment Status - $orderFinalStatus{$representment2{$orderid}}";
            $tran_status          = "$orderFinalStatus{$representment2{$orderid}}";
          } elsif ( exists $representment1{$orderid} ) {    #1 Representments
            if ( $smps::feature{'ach_repre_limit'} == 2 ) {
              $representment_status = "1st Representment Status - $orderFinalStatus{$representment1{$orderid}}";
              $tran_status          = "pending";
            } else {
              $representment_status = "1st & Last Representment Status - $orderFinalStatus{$representment1{$orderid}}";
              $tran_status          = "$orderFinalStatus{$representment1{$orderid}}";
            }
          } elsif ( $orderAge{$orderid} > 20 ) {            #If transaction is too old
            $representment_status = "Final Rejection - Expired";
            $tran_status          = "$status";
          } else {
            $representment_status = "Waiting Representment";
            $tran_status          = "pending";
          }
        } else {
          $tran_status = "$status";
        }

        $i++;
        if ( ( $transflags =~ /redo$/ ) && ( $ENV{'LOGIN'} !~ /(processa)/ ) ) {
          next;
        }

        my $freeform = substr( $res2{"auth-code"}, 255, 12 );

        my $sortableexp = "20" . substr( $exp, 3, 2 ) . substr( $exp, 0, 2 );    # allows exp to be sorted properly

        my $sortableamt = $amount;
        $sortableamt =~ s/[^0-9\.\-]//g;                                         # allows amount to be sorted properly

        my ( $currency, $price ) = split( / /, $amount );

        if ( ( $query_currency ne "" ) && ( $query_currency ne $currency ) ) {
          next;
        }

        if ( ( $smps::feature{'bindetails'} == 1 ) && ( $cardnumber =~ /^(3|4|5|6|7)\d{12,15}/ ) ) {
          %bindata = &miscutils::check_bankbin($cardnumber);

          #region country  debit  prodtype
        }

        if ( ( $oidcn eq "yes" ) && ( $cardnumber =~ /(3|4|5|6|7)\d{12,15}/ ) ) {
          my $first4 = substr( $cardnumber, 0,  4 );
          my $last2  = substr( $cardnumber, -2, 2 );
          $cardnumber = "$first4" . "**" . "$last2";
        }

        if ( ( $smps::feature{'bindetails'} == 1 ) && ( $org_decrypt ne "yes" ) ) {
          $decrypt = 'no';
          $smps::query->param( 'decrypt', 'no' );
          ## DCP 20110419
          my $first6 = substr( $cardnumber, 0,  6 );
          my $last2  = substr( $cardnumber, -2, 2 );
          $cardnumber = "$first6" . "**" . "$last2";
        } elsif ( ( $smps::feature{'display_cclast4'} == 1 ) && ( $org_decrypt ne "yes" ) ) {
          $decrypt = 'no';
          $smps::query->param( 'decrypt', 'no' );
          ## DCP 20120124
          my $first2 = substr( $cardnumber, 0, 2 );
          my $first4 = substr( $cardnumber, 0, 4 );
          my $last4  = substr( $cardnumber, -4 );
          $cardnumber = "$first2" . "**" . "$last4";
        }

        if ( $partialstr ne "" ) {
          if ( ( $decrypt eq "yes" ) && ( $last4 ne "" ) && ( substr( $cardnumber, -4, 4 ) ne $last4 ) ) {
            next;
          }
        }

        if ( $smps::username =~ /^(brookline)$/ ) {    ###  DCP  20081111  Duplicate Transaction Filter
          if ( $dupcheck{$smps::username}{$orderid}{$txntype}{$status} == 1 ) {
            next;
          } else {
            $dupcheck{$smps::username}{$orderid}{$txntype}{$status} = 1;
          }
        }

        my ( $native_sym, $merch_sym, $native_amt, $native_isocur, $conv_rate );
        if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
          my %currencyUSDSYM = ( 'AUD', 'A$', 'CAD', 'C$', 'EUR', '&#8364;', 'GBP', '&#163;', 'JPY', '&#165;', 'USD', '$' );
          my %currency840SYM = ( '036', 'A$', '124', 'C$', '978', '&#8364;', '826', '&#163;', '392', '&#165;', '997', '$' );

          $native_sym = $currency840SYM{$currency};
          $merch_sym  = $currencyUSDSYM{$smps::currency};

          my $processor = $res2{'processor'} || $smps::processor;

          $conv_rate = smpsutils::conversionRateFromAuthCodeColumnData({
            processor => $processor,
            authCodeColumnData => $res2{'auth-code'}
          });

          $native_amt = smpsutils::calculateNativeAmountFromAuthCodeColumnData({
            processor => $processor,
            authCodeColumnData => $res2{'auth-code'},
            nativeCurrency => $currency,
            convertedAmount => $price
          });

          $native_isocur = $smps::currency;
          $native_isocur =~ tr/A-Z/a-z/;
        }

        if ( $native_amt == 0 ) {
          $native_amt = $price;
        }



        if ( ( $smps::settletimezone ne "" ) && ( $smps::settletimezone != 0 ) ) {
          $batch_time = &miscutils::strtotime($batch_time);
          $batch_time += ( $smps::settletimezone * 60 * 60 );
          $batch_time = &miscutils::timetostr($batch_time);
        }

        if ( ( $batchtimeflg eq "yes" ) && ( $batch_time > $endtime ) ) {
          next;
        }

        my $btimestr = substr( $batch_time, 4, 2 ) . "/" . substr( $batch_time, 6, 2 ) . "/" . substr( $batch_time, 0, 4 ) . " ";
        $btimestr .= substr( $batch_time, 8, 2 ) . ":" . substr( $batch_time, 10, 2 ) . ":" . substr( $batch_time, 12, 2 );

        my $sortablebtime = substr( $batch_time, 0, 14 );    # allows date and time to be sorted properly

        ## Added DCP 20040824
        %res2 = ();

        if ( $accttype eq "checking" ) {
          $cardtype = "ach";
        }
        if ( $cardtype ne "" ) {
          $cardtype{$orderid} = $cardtype;
        }

        if ( $txntype eq "void" ) {
          $txntype = $lasttran{$orderid} . "void";
        }
        $lasttran{$orderid}        = $txntype;
        $txntype{$txntype}         = 1;
        $currency_types{$currency} = 1;

        if ( $cardtype eq "" ) {
          $cardtype = $cardtype{$orderid};
        }

        my $transdate = substr( $time, 0, 8 );
        if ( $txntype !~ /^ret/ ) {
          if ( $status =~ /^(badcard|problem)$/ ) {
            $cardtotals{$transdate}{$txntype}{$cardtype}{'problem'}{'total'}{$currency} += $price;
            $cardtotals{$transdate}{$txntype}{$cardtype}{'problem'}{'trxs'}{$currency}  += 1;

            $ncardtotals{$transdate}{$txntype}{$cardtype}{'problem'}{'total'}{$smps::currency}           += $native_amt;
            $ncardtotals{$transdate}{$txntype}{$cardtype}{'problem'}{'baseAmountTotal'}{$smps::currency} += $baseAmount;
            $ncardtotals{$transdate}{$txntype}{$cardtype}{'problem'}{'adjustmentTotal'}{$smps::currency} += $adjustment;
            $ncardtotals{$transdate}{$txntype}{$cardtype}{'problem'}{'trxs'}{$smps::currency}            += 1;

            $tcardtotals{$txntype}{$cardtype}{'problem'}{'total'}{$currency} += $price;
            $tcardtotals{$txntype}{$cardtype}{'problem'}{'trxs'}{$currency}  += 1;
          } else {
            $cardtotals{$transdate}{$txntype}{$cardtype}{'success'}{'total'}{$currency} += $price;
            $cardtotals{$transdate}{$txntype}{$cardtype}{'success'}{'trxs'}{$currency}  += 1;

            $ncardtotals{$transdate}{$txntype}{$cardtype}{'success'}{'total'}{$smps::currency}           += $native_amt;
            $ncardtotals{$transdate}{$txntype}{$cardtype}{'success'}{'baseAmountTotal'}{$smps::currency} += $baseAmount;
            $ncardtotals{$transdate}{$txntype}{$cardtype}{'success'}{'adjustmentTotal'}{$smps::currency} += $adjustment;
            $ncardtotals{$transdate}{$txntype}{$cardtype}{'success'}{'trxs'}{$smps::currency}            += 1;

            $tcardtotals{$txntype}{$cardtype}{'success'}{'total'}{$currency} += $price;
            $tcardtotals{$txntype}{$cardtype}{'success'}{'trxs'}{$currency}  += 1;
          }
        } else {
          if ( $status =~ /^(badcard|problem)$/ ) {
            $cardtotals{$transdate}{$txntype}{$cardtype}{'problem'}{'total'}{$currency} -= $price;

            $ncardtotals{$transdate}{$txntype}{$cardtype}{'problem'}{'total'}{$smps::currency}           -= $native_amt;
            $ncardtotals{$transdate}{$txntype}{$cardtype}{'problem'}{'baseAmountTotal'}{$smps::currency} -= $baseAmount;
            $ncardtotals{$transdate}{$txntype}{$cardtype}{'problem'}{'adjustmentTotal'}{$smps::currency} -= $adjustment;

            $tcardtotals{$txntype}{$cardtype}{'problem'}{'total'}{$currency} -= $price;
          } else {
            $cardtotals{$transdate}{$txntype}{$cardtype}{'success'}{'total'}{$currency} -= $price;

            $ncardtotals{$transdate}{$txntype}{$cardtype}{'success'}{'total'}{$smps::currency}           -= $native_amt;
            $ncardtotals{$transdate}{$txntype}{$cardtype}{'success'}{'baseAmountTotal'}{$smps::currency} -= $baseAmount;
            $ncardtotals{$transdate}{$txntype}{$cardtype}{'success'}{'adjustmentTotal'}{$smps::currency} -= $adjustment;

            $tcardtotals{$txntype}{$cardtype}{'success'}{'total'}{$currency} -= $price;
          }
        }

        if ( $txntype =~ /void/ ) {
          $txntype = "void";
          ++$total{"voidtrx$currency"};
          ++$ntotal{"voidtrx$smps::currency"};
        }

        if ( ( $txntype eq "auth" ) && ( $status eq "badcard" ) ) {
          $total{"authbadcard$currency"} += $price;
          ++$total{"authbadcardtrx$currency"};

          $ntotal{"authbadcard$smps::currency"} += $native_amt;
          ++$ntotal{"authbadcardtrx$smps::currency"};
        }

        if ( ( $txntype eq "auth" ) && ( $status =~ /^(badcard|problem)$/ ) ) {
          $customercnt{$cardname}++;
        }

        if ( $status eq "success" ) {
          $total{"$txntype$currency"}        += $price;
          $ntotal{"$txntype$smps::currency"} += $native_amt;
          if ( $txntype eq "auth" ) {
            ++$total{"authtrx$currency"};
            ++$ntotal{"authtrx$smps::currency"};
          } elsif ( $txntype eq "postauth" ) {
            ++$total{"postauthtrx$currency"};
            ++$ntotal{"postauthtrx$smps::currency"};
          } elsif ( $txntype eq "batch" ) {
            ++$total{"batchtrx$currency"};
            ++$ntotal{"batchtrx$smps::currency"};
          }
          ## Added DCP 20051208
          elsif ( $txntype eq "return" ) {
            ++$total{"returnedtrx$currency"};
            ++$ntotal{"returnedtrx$smps::currency"};
          }
        } elsif ( ( $txntype eq "postauth" ) && ( $status =~ /^(pending|locked)$/ ) ) {
          $total{"marked$currency"} += $price;
          ++$total{"markedtrx$currency"};
          $ntotal{"marked$smps::currency"} += $native_amt;
          ++$ntotal{"markedtrx$smps::currency"};
        } elsif ( ( $txntype eq "return" ) && ( $status =~ /^(pending|locked)$/ ) ) {
          $total{"marked$currency"} -= $price;
          ++$total{"returnedtrx$currency"};

          $ntotal{"marked$smps::currency"} -= $native_amt;
          ++$ntotal{"returnedtrx$smps::currency"};
        } elsif ( ( $txntype eq "auth" ) && ( $accttype eq "checking" ) && ( $status =~ /^(pending)$/ ) ) {
          $total{"authpend$currency"} += $price;
          ++$total{"authpendtrx$currency"};

          $ntotal{"authpend$smps::currency"} += $native_amt;
          ++$ntotal{"authpendtrx$smps::currency"};

        } elsif ( ( $txntype eq "auth" ) && ( $accttype eq "checking" ) && ( $status =~ /^(badcard|problem)$/ ) ) {
          $total{"authfail$currency"} += $price;
          ++$total{"authfailtrx$currency"};

          $ntotal{"authfail$smps::currency"} += $native_amt;
          ++$ntotal{"authfailtrx$smps::currency"};
        } elsif ( ( $txntype eq "auth" ) && ( $status !~ /^(success)$/ ) ) {
          $failtotal{"$txntype$currency"} += $price;
          ++$failtotal{"authtrx$currency"};

          $nfailtotal{"$txntype$smps::currency"} += $native_amt;
          ++$nfailtotal{"authtrx$smps::currency"};

        } elsif ( ( $txntype eq "postauth" ) && ( $status !~ /^(success|pending)$/ ) ) {
          $failtotal{"$txntype$currency"} += $price;
          ++$failtotal{"$txntype\trx$currency"};

          $nfailtotal{"$txntype$smps::currency"} += $native_amt;
          ++$nfailtotal{"$txntype\trx$smps::currency"};
        }

        $cardnumber = substr( $cardnumber, 0, 27 );

        if ( $old_orderid ne $orderid ) {
          $color       = ( $color + 1 ) % 2;
          $old_orderid = $orderid;
        }
        if ( $summaryonly ne "yes" ) {
          if ( $smps::format !~ /^(text|download)$/ ) {
            my $strtstrg;
            if ( $smps::merchant ne "ALL" ) {
              $strtstrg .= "\&merchant=$smps::merchant";
            } else {
              $strtstrg .= "\&merchant=$merchant";
            }

            $strtstrg .= "\&settletimezone=$smps::settletimezone";

            if ( exists $representment1{$orderid} ) {
              $strtstrg .= "\&rep1=$representment1{$orderid}";
            }
            if ( exists $representment2{$orderid} ) {
              $strtstrg .= "\&rep2=$representment2{$orderid}";
            }

            if ( ( $ENV{'SEC_LEVEL'} < 7 ) && ( $smps::query->param('decrypt') eq "yes" ) && ( ( $smps::feature{'decryptflag'} == 1 ) || ( $smps::feature{'decryptallflag'} == 1 ) ) ) {

              #if ($decrypt eq "yes") {
              $strtstrg .= "\&decrypt=yes";
            }

            if ( $color == 1 ) {
              print "  <tr class=\"listrow_color1\">\n";
            } else {
              print "  <tr class=\"listrow_color0\">\n";
            }
            print "<td><nobr>$txntype";
            if ( $transflags =~ /fund/i ) {
              print " - CFT";
            }
            print "</nobr></td>\n";
            if ( $smps::merchant eq "ALL" ) {
              print "<td><nobr>$merchant</nobr></td>\n";
            }
            print "<td><nobr>$cardname</nobr></td>\n";
            print "<td><nobr>$tran_status</nobr></td>\n";
            print "<td><nobr><a href=\"$smps::path_cgi\?accttype=$accttype\&acct_code=$acct_code\&function=details&orderid=$orderid$strtstrg\">$orderid</a></nobr></td>\n";
            if ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) {
              print "<td align=center sortvalue=\"$sortabletime\"><nobr>$timestr</nobr></td>\n";
              print "<td align=center sortvalue=\"$sortablebtime\"><nobr>$btimestr</nobr></td>\n";
              print "<td><nobr>$cardnumber</nobr></td>\n";
              print "<td sortvalue=\"$sortableexp\"><nobr>$exp</nobr></td>\n";
              if ( $txntype !~ /ret/ ) {
                print "<td sortvalue=\"$sortableamt\"><nobr>$amount</nobr></td>\n";
              } else {
                print "<td sortvalue=\"-$sortableamt\"><nobr><font color=\"#ff0000\">($amount)</font></nobr></td>\n";
              }
              ## DCP
              if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
                if ( $txntype eq "void" ) {
                  print "<td align=\"left\"><nobr>&nbsp;</nobr></td>\n";
                  print "<td align=\"right\"><nobr>&nbsp;</nobr></td>\n";
                } else {
                  print "<td align=\"left\"><nobr>$native_isocur $native_amt</nobr></td>\n";
                  print "<td align=\"right\"><nobr>$conv_rate</nobr></td>\n";
                }
              }
              if ( $adjustmentFlag == 1 ) {
                print "<td align=\"right\"><nobr>$baseAmount</nobr></td>\n";
                print "<td align=\"right\"><nobr>$adjustment</nobr></td>\n";
              }
              print "<td>$authcode</td>\n";
              if ( $smps::processor =~ /^(wirecard|banistmo|epx|catalunya)$/ ) {
                print "<td align=left><nobr>$refnumber</nobr></td>\n";
              }
              if ( $entrymethod ne "" ) {
                print "<td>$entrymethod</td>";
              }
            } else {
              print "<td align=center sortvalue=\"$sortablebtime\"><nobr>$btimestr</nobr></td>\n";

              if ( ( $rejectrpt == 1 ) && ( $rejectrpttype eq "submitted" ) ) {
                $j++;
                my $transtime = $returnTime{$orderid};
                my $transtimestr = substr( $transtime, 4, 2 ) . "/" . substr( $transtime, 6, 2 ) . "/" . substr( $transtime, 0, 4 ) . " ";
                $transtimestr .= substr( $transtime, 8, 2 ) . ":" . substr( $transtime, 10, 2 ) . ":" . substr( $transtime, 12, 2 );
                print "<td align=center sortvalue=\"$transtime\"><nobr>$j $transtimestr</nobr></td>\n";
              } else {
                print "<td align=center sortvalue=\"$sortabletime\"><nobr>$timestr</nobr></td>\n";
              }
              print "<td>$cardnumber</td>\n";
              if ( $txntype !~ /ret/ ) {
                print "<td><nobr>$amount</nobr></td>\n";
              } else {
                print "<td><nobr><font color=\"#ff0000\">($amount)</font></nobr></td>\n";
              }
              if ( $adjustmentFlag == 1 ) {
                print "<td align=\"right\"><nobr>$baseAmount</nobr></td>\n";
                print "<td align=\"right\"><nobr>$adjustment</nobr></td>\n";
              }
            }
            if ( $accttype =~ /checking|savings/ ) {
              print "<td><nobr>$checktype</nobr></td>\n";
            }
            if ( $display_acct eq "yes" ) {
              print "<td><nobr>$acctcode\&nbsp;</nobr></td>\n";
              print "<td><nobr>$acctcode2\&nbsp;</nobr></td>\n";
              print "<td><nobr>$acctcode3\&nbsp;</nobr></td>\n";
              print "<td><nobr>$acctcode4\&nbsp;</nobr></td>\n";
            }
            if ( $smps::processor eq "fdmsnorth" ) {
              print "<td>$freeform</td>\n";
            }
            if ( ( $status =~ /^(badcard|problem|fraud)$/ ) && ( $txntype =~ /auth/ ) ) {
              print "<td><nobr>$descr\&nbsp;</nobr></td>\n";
            } elsif ( $transflags =~ /balance/i ) {
              print "<td><nobr>Balance Inquiry</nobr></td>\n";
            } elsif ( $transflags =~ /avsonly/i ) {
              print "<td><nobr>AVS Inquiry</nobr></td>\n";
            } else {
              print "<td><nobr>&nbsp;</nobr></td>\n";
            }
            if ( $rejectrpt == 1 ) {
              print "<td>$representment_status</td>\n";
            }
            if ( $form_txntype eq "batch" ) {
              print "<td><nobr>$batchid\&nbsp;</nobr></td>\n";
            }
            if ( $smps::feature{'bindetails'} == 1 ) {
              print "<td><nobr>$bindata{'bbin_region'}</nobr></td>\n";
              print "<td><nobr>$bindata{'bbin_country'}</nobr></td>\n";
              print "<td><nobr>$bindata{'bbin_debit'}</nobr></td>\n";
              print "<td><nobr>$bindata{'bbin_prodtype'}</nobr></td>\n";
            }

            print "</tr>\n";
          } else {
            $amount =~ s/[^0-9\.]//g;
            if ( $smps::merchant eq "ALL" ) {
              print "$merchant\t";
            }

            print "$txntype\t$cardname\t$status\t$orderid\t$timestr\t$cardnumber\t$exp\t";
            if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
              print "$currency\t";
            }
            if ( $txntype !~ /ret/ ) {
              print "$amount\t";
            } else {
              print "-$amount\t";
            }
            if ( $adjustmentFlag == 1 ) {
              print "$baseAmount\t";
              print "$adjustment\t";
            }

            print "$authcode\t";
            if ( $splitacctcode eq "yes" ) {
              $acctcode =~ s/\|/\t/g;
              $acctcode2 =~ s/\|/\t/g;
              $acctcode3 =~ s/\|/\t/g;
            }
            print "$acctcode\t$acctcode2\t$acctcode3";
            if ( ( $smps::username =~ /restaurant|emslanalyt|hvinvestm|americanch3/ ) || ( $smps::reseller =~ /^(affinisc|lawpay)$/ ) || ( $smps::merchstrt > 20070101 ) || ( $smps::feature{'display_ac4'} == 1 ) )
            {
              print "\t$acctcode4";
            }
            if ( $smps::processor =~ /^(wirecard|banistmo|epx|catalunya)$/ ) {
              print "\t$refnumber";
            }
            if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
              print "\t$native_isocur\t$native_amt\t$conv_rate";
            }
            if ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) {
              if ( $splitbtime eq "yes" ) {
                $btimestr =~ s/\ /\t/g;
              }
              print "\t$btimestr";
            }
            if ( $display_errmsg eq "yes" ) {
              print "\t$descr";
            }
            if ( $smps::reseller =~ /^premier2/ ) {
              print "\t$country\t$avscode\t$cvvresp";
            }
            if ( $form_txntype eq "batch" ) {
              print "\t$batchid";
            }
            if ( $smps::feature{'bindetails'} == 1 ) {
              print "\t$bindata{'bbin_region'}\t$bindata{'bbin_country'}\t$bindata{'bbin_debit'}\t$bindata{'bbin_prodtype'}";
            }
            print "\t$ipaddress";
            print "\t$currency";
            print "\r\n";
          }
        }
      }
    }
    ## Added DCP  20040823
    @values = ();

    $orderidold = $vorderid;
    if ( $hideprevious eq "yes" ) {
      my $lasttrantime = $maxtime;

      my $dbh = &miscutils::dbhconnect("pnpmisc");

      my $sth_merchants = $dbh->prepare(
        qq{
        delete from admin_config
        where username=?
        and fieldname=?
        }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_merchants->execute( "$smps::username", 'lasttrantime' ) or die "Can't execute: $DBI::errstr";
      $sth_merchants->finish;

      # Insert
      $sth_merchants = $dbh->prepare(
        qq{
         insert into admin_config
         (username,fieldname,value)
         values (?,?,?)
        }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_merchants->execute( "$smps::username", 'lasttrantime', "$lasttrantime" ) or die "Can't execute: $DBI::errstr";
      $sth_merchants->finish;

      $dbh->disconnect;

    }

  }
  my (@currency_types);
  foreach my $curr ( sort keys %currency_types ) {
    if ( $curr eq "" ) {
      next;
    }
    $currency_types[ ++$#currency_types ] = $curr;
  }
  if ( ( @currency_types == 1 ) && ( $currency_types[0] eq $smps::currency ) ) {
    @currency_types = ();
  }
  if ( $smps::format !~ /^(text|download)$/ ) {
    print "</table>\n";
    print "<br>\n";
    print "<table border=1 cellspacing=0 cellpadding=2>\n";
    print "<tr><th>Action</th><th>TOTAL<br>Amount - $smps::currency</th><th>TOTAL<br>Count - $smps::currency</th>\n";

    foreach my $curr (@currency_types) {
      print "<th>Amount - $curr</th><th>Count - $curr</th>";
    }
    print "</tr>\n";

    printf( "<tr><td>Authorized Success</td><td align=right>%.2f</td><td align=right>\%d</td>\n", $ntotal{"auth$smps::currency"}, $ntotal{"authtrx$smps::currency"} );
    foreach my $curr (@currency_types) {
      printf( "<td align=right>%.2f</td><td align=right>\%d</td>\n", $total{"auth$curr"}, $total{"authtrx$curr"} );
    }
    print "</tr>\n";

    if ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) {
      printf( "<tr><td>Authorized Pending</td><td align=right>%.2f</td><td align=right>\%d</td>\n", $ntotal{"authpend$smps::currency"}, $ntotal{"authpendtrx$smps::currency"} );
      foreach my $curr (@currency_types) {
        printf( "<td align=right>%.2f</td><td align=right>\%d</td>\n", $total{"authpend$curr"}, $total{"authpendtrx$curr"} );
      }
      print "</tr>\n";

      printf( "<tr><td>Authorized Failure</td><td align=right>%.2f</td><td align=right>\%d</td>\n", $ntotal{"authfail$smps::currency"}, $ntotal{"authfailtrx$smps::currency"} );
      foreach my $curr (@currency_types) {
        printf( "<td align=right>%.2f</td><td align=right>\%d</td>\n", $total{"authfail$curr"}, $total{"authfailtrx$curr"} );
      }
      print "</tr>\n";
    } else {
      printf( "<tr><td>Authorized Failure</td><td align=right>%.2f</td><td align=right>\%d</td>\n", $nfailtotal{"auth$smps::currency"}, $nfailtotal{"authtrx$smps::currency"} );
      foreach my $curr (@currency_types) {
        printf( "<td align=right>%.2f</td><td align=right>\%d</td>\n", $failtotal{"auth$curr"}, $failtotal{"authtrx$curr"} );
      }
      print "</tr>\n";
    }

    printf( "<tr><td>Authorized Badcard</td><td align=right>%.2f</td><td align=right>\%d</td>\n", $ntotal{"authbadcard$smps::currency"}, $ntotal{"authbadcardtrx$smps::currency"} );
    foreach my $curr (@currency_types) {
      printf( "<td align=right>%.2f</td><td align=right>\%d</td>\n", $total{"authbadcard$curr"}, $total{"authbadcardtrx$curr"} );
    }
    print "</tr>\n";

    printf( "<tr><td>Voided</td><td align=right>%.2f</td><td align=right>\%d</td>\n", $ntotal{"void$smps::currency"}, $ntotal{"voidtrx$smps::currency"} );
    foreach my $curr (@currency_types) {
      printf( "<td align=right>%.2f</td><td align=right>\%d</td>\n", $total{"void$curr"}, $total{"voidtrx$curr"} );
    }
    print "</tr>\n";

    printf( "<tr><td>Marked for Batching</td><td align=right>%.2f</td><td align=right>\%d</td>\n", $ntotal{"marked$smps::currency"}, $ntotal{"markedtrx$smps::currency"} );
    foreach my $curr (@currency_types) {
      printf( "<td align=right>%.2f</td><td align=right>\%d</td>\n", $total{"marked$curr"}, $total{"markedtrx$curr"} );
    }
    print "</tr>\n";

    printf(
      "<tr><td>Settled Success</td><td align=right>%.2f</td><td align=right>\%d</td>\n",
      $ntotal{"settled$smps::currency"} + $ntotal{"postauth$smps::currency"} + $ntotal{"capture$smps::currency"},
      $ntotal{"postauthtrx$smps::currency"}
    );
    foreach my $curr (@currency_types) {
      printf( "<td align=right>%.2f</td><td align=right>\%d</td>\n", $total{"settled$curr"} + $total{"postauth$curr"} + $total{"capture$curr"}, $total{"postauthtrx$curr"} );
    }
    print "</tr>\n";

    printf( "<tr><td>Settled Failure</td><td align=right>%.2f</td><td align=right>\%d</td>\n", $nfailtotal{"settled$smps::currency"}, $nfailtotal{"settledtr$smps::currency"} );
    foreach my $curr (@currency_types) {
      printf( "<td align=right>%.2f</td><td align=right>\%d</td>\n", $failtotal{"settled$curr"} + $failtotal{"postauth$curr"} + $failtotal{"capture$curr"}, $failtotal{"postauthtrx$curr"} );
    }
    print "</tr>\n";

    printf( "<tr><td>Returned</td><td align=right>%.2f</td><td align=right>\%d</td>\n", $ntotal{"markret$smps::currency"} + $ntotal{"return$smps::currency"}, $ntotal{"returnedtrx$smps::currency"} );
    foreach my $curr (@currency_types) {
      printf( "<td align=right>%.2f</td><td align=right>\%d</td>\n", $total{"markret$curr"} + $total{"return$curr"}, $total{"returnedtrx$curr"} );
    }
    print "</tr>\n";

    printf( "<tr><td>Submitted in Batches</td><td align=right>%.2f</td><td align=right>\%d</td>\n", $ntotal{"batch$smps::currency"}, $ntotal{"batchtrx$smps::currency"} );
    foreach my $curr (@currency_types) {
      printf( "<td align=right>%.2f</td><td align=right>\%d</td>\n", $total{"batch$curr"}, $total{"batchtrx$curr"} );
    }
    print "</tr>\n";

    print "</table>\n";

    print "<h3>Summary:</h3>\n";
    print "<table border=1 cellspacing=0 cellpadding=2>\n";
    print "<tr><th>Date</th><th>Tran. Type</th><th>Card Type</th><th>Count</th><th>Amt</th><th>Amt. Net Voids</th><th>Failed Count</th><th>Failed Amt</th>\n";
    print "<th>Total Count</th>\n";
    if ( $adjustmentFlag == 1 && $surchargeFlag == 1 ) {
      print "<th>Total Base Amount</th>\n";    # only display this for surcharge for now
      print "<th>Total Credit Card Fees</th>\n";
    }
    print "<th>Total Amount</th>\n";
    print "</tr>\n";
    foreach my $curr (@currency_types) {
      print "<tr>\n";
      print "  <th>$curr</th>\n";
      print "</tr>\n";

      foreach my $transdate ( sort keys %cardtotals ) {
        foreach my $txntype ( sort keys %{ $cardtotals{$transdate} } ) {
          if ( $txntype =~ /^batch/ ) {
            next;
          }
          foreach my $cardtype ( sort keys %{ $cardtotals{$transdate}{$txntype} } ) {

            my $transdatestr = substr( $transdate, 4, 2 ) . "/" . substr( $transdate, 6, 2 ) . "/" . substr( $transdate, 0, 4 ) . " ";
            my $total = $cardtotals{$transdate}{$txntype}{$cardtype}{'success'}{'total'}{$curr};
            $total = sprintf( "%.2f", $total );
            my $failtotal = $cardtotals{$transdate}{$txntype}{$cardtype}{'problem'}{'total'}{$curr};
            $failtotal = sprintf( "%.2f", $failtotal );
            my $trxs     = $cardtotals{$transdate}{$txntype}{$cardtype}{'success'}{'trxs'}{$curr};
            my $failtrxs = $cardtotals{$transdate}{$txntype}{$cardtype}{'problem'}{'trxs'}{$curr};

            my $alltotal = sprintf( "%.2f", $total + $failtotal );
            my $alltrxs = $trxs + $failtrxs;

            if ( ( $total != 0 ) || ( $failtotal > 0 ) ) {
              print "<tr>\n";
              print "  <th align=\"left\">$transdatestr</th>\n";
              print "  <td>$txntype</td>\n";
              print "  <td>$smps::cardarray{$cardtype} \&lt;$cardtype\&gt;</td>\n";
              printf( "  <td align=\"right\">%0d</td>\n", $trxs );
              printf( "  <td align=\"right\">%.2f</td>",  $total );

              my $voidamt = $cardtotals{$transdate}{ $txntype . "void" }{$cardtype}{'success'}{'total'}{$curr};
              my $nettotal = sprintf( "%.2f", $total - $voidamt );

              print "  <td align=\"right\">$nettotal</td>\n";
              print "  <td align=\"right\">&nbsp;$failtrxs</td>\n";
              print "  <td align=\"right\">&nbsp;$failtotal</td>\n";
              print "  <td align=\"right\">&nbsp;$alltrxs</td>\n";
              print "  <td align=\"right\">&nbsp;$alltotal</td>\n";
              print "</tr>\n";
            }
          }
        }
      }
    }

    my $colspan = 10;
    if ( $adjustmentFlag == 1 ) {
      if ( $surchargeFlag == 1 ) {
        $colspan = 12;
      }
    }

    print "<tr>\n";
    print "  <th colspan=\"$colspan\">DAILY TOTALS $smps::currency</th>\n";
    print "</tr>\n";

    my $old_transdatestr;
    my $color = 0;

    foreach my $transdate ( sort keys %ncardtotals ) {
      foreach my $txntype ( sort keys %{ $ncardtotals{$transdate} } ) {
        if ( $txntype =~ /^batch/ ) {
          next;
        }
        foreach my $cardtype ( sort keys %{ $ncardtotals{$transdate}{$txntype} } ) {
          my $transdatestr = substr( $transdate, 4, 2 ) . "/" . substr( $transdate, 6, 2 ) . "/" . substr( $transdate, 0, 4 ) . " ";
          if ( $transdatestr ne "$old_transdatestr" ) {
            $color            = ( $color + 1 ) % 2;
            $old_transdatestr = $transdatestr;
          }
          my $total     = $ncardtotals{$transdate}{$txntype}{$cardtype}{'success'}{'total'}{$smps::currency};
          my $failtotal = $ncardtotals{$transdate}{$txntype}{$cardtype}{'problem'}{'total'}{$smps::currency};
          $failtotal = sprintf( "%.2f", $failtotal );
          my $trxs     = $ncardtotals{$transdate}{$txntype}{$cardtype}{'success'}{'trxs'}{$smps::currency};
          my $failtrxs = $ncardtotals{$transdate}{$txntype}{$cardtype}{'problem'}{'trxs'}{$smps::currency};

          my $baseAmountTotal = $ncardtotals{$transdate}{$txntype}{$cardtype}{'success'}{'baseAmountTotal'}{$smps::currency};
          my $adjustmentTotal = $ncardtotals{$transdate}{$txntype}{$cardtype}{'success'}{'adjustmentTotal'}{$smps::currency};

          my $alltotal = sprintf( "%.2f", $total + $failtotal );
          my $alltrxs = $trxs + $failtrxs;

          if ( ( $total != 0 ) || ( $failtotal > 0 ) ) {
            if ( $color == 1 ) {
              print "  <tr class=\"listrow_color1\">\n";
            } else {
              print "  <tr class=\"listrow_color0\">\n";
            }
            print "  <td align=\"left\"><b>$transdatestr</b></td>\n";
            print "  <td>$txntype</td>\n";
            print "  <td>$smps::cardarray{$cardtype}";
            if ( $cardtype ne "" ) {
              print " \&lt;$cardtype\&gt;";
            }
            print "</td>\n";
            printf( "  <td align=\"right\">%0d</td>\n",  $trxs );
            printf( "  <td align=\"right\">%.2f</td>\n", $total );

            my $voidamt = $ncardtotals{$transdate}{ $txntype . "void" }{$cardtype}{'success'}{'total'}{$smps::currency};
            my $nettotal = sprintf( "%.2f", $total - $voidamt );

            print "  <td align=\"right\">$nettotal</td>\n";
            print "  <td align=\"right\">&nbsp;$failtrxs</td>\n";
            print "  <td align=\"right\">&nbsp;$failtotal</td>\n";
            print "  <td>&nbsp;$alltrxs</td>\n";
            if ( $adjustmentFlag == 1 ) {
              if ( $surchargeFlag == 1 ) {
                printf( "  <td align=\"right\">%.2f</td>\n", $baseAmountTotal );    # only display this for surcharge for now
                printf( "  <td align=\"right\">%.2f</td>\n", $adjustmentTotal );
              }
            }
            printf( "  <td align=\"right\">%.2f</td>\n", $alltotal );
            print "</tr>\n";
          }
        }
      }
    }
    my @cbtype = ( 'chargeback', 'retrieval' );
    my %cb_ct_hash = ( 'VISA', 'vs', 'MSTR', 'mc' );
    foreach my $type (@cbtype) {
      $txntype{$type} = 1;
      foreach my $ct ( keys %$ct ) {
        my $ct1 = $cb_ct_hash{$ct};
        $tcardtotals{$type}{$ct1}{'success'}{'total'}{$smps::currency} = $$cb_sum{$type}{$ct};
        $tcardtotals{$type}{$ct1}{'success'}{'trxs'}{$smps::currency}  = $$cb_cnt{$type}{$ct};
      }
    }
    foreach my $txntype ( sort keys %txntype ) {
      if ( $txntype =~ /^batch/ ) {
        next;
      }
      foreach my $cardtype ( sort keys %{ $tcardtotals{$txntype} } ) {
        my $total     = $tcardtotals{$txntype}{$cardtype}{'success'}{'total'}{$smps::currency};
        my $failtotal = $tcardtotals{$txntype}{$cardtype}{'problem'}{'total'}{$smps::currency};
        $failtotal = sprintf( "%.2f", $failtotal );
        my $trxs     = $tcardtotals{$txntype}{$cardtype}{'success'}{'trxs'}{$smps::currency};
        my $failtrxs = $tcardtotals{$txntype}{$cardtype}{'problem'}{'trxs'}{$smps::currency};
        if ( ( $total != 0 ) || ( $failtotal > 0 ) ) {
          print "<tr>\n";
          print "  <th align=\"left\">TOTAL</th>\n";
          print "  <td>$txntype</td>\n";
          print "  <td>$smps::cardarray{$cardtype}";
          if ( $cardtype ne "" ) {
            print " \&lt;$cardtype\&gt;\n";
          }
          print "</td>\n";
          printf( "  <td align=\"right\">%0d</td>\n",  $trxs );
          printf( "  <td align=\"right\">%.2f</td>\n", $total );

          my $voidamt = $tcardtotals{ $txntype . "void" }{$cardtype}{'success'}{'total'}{$smps::currency};
          my $nettotal = sprintf( "%.2f", $total - $voidamt );

          print "  <td align=\"right\">$nettotal</td>\n";
          print "  <td align=\"right\">&nbsp;$failtrxs</td>\n";
          print "  <td align=\"right\">&nbsp;$failtotal</td>\n";
          print "</tr>\n";
        }
      }
    }

    print "</table>\n";

    if ( $smps::username =~ /ipayfriendf|friendfind/ ) {
      print "<table>\n";
      my $declinecnt = "";
      my $dupcnt     = "";
      foreach my $key ( keys %customercnt ) {
        $declinecnt++;
        if ( $customercnt{$key} > 1 ) {
          $dupcnt += ( $customercnt{$key} - 1 );
        }
      }
      print "<tr><th>Number of Unique Customers with Declined Cards:</th><td>$declinecnt</td></tr>\n";
      print "<tr><th>Number of Duplicate Declines:</th><td>$dupcnt</td></tr>\n";
      print "</table>\n";
    }

  } elsif ( $omitfooter ne "yes" ) {
    foreach my $curr (@currency_types) {
      printf( "Authorized - $curr\t%.2f\t%0d\n",           $total{"auth$curr"},                                                       $total{"authtrx$curr"} );
      printf( "Marked for Batching - $curr\t%.2f\t%0d\n",  $total{"marked$curr"},                                                     $total{"markedtrx$curr"} );
      printf( "Settled - $curr\t%.2f\t%0d\n",              $total{"settled$curr"} + $total{"postauth$curr"} + $total{"capture$curr"}, $total{"postauthtrx$curr"} );
      printf( "Returned - $curr\t%.2f\t%0d\n",             $total{"markret$curr"} + $total{"return$curr"},                            $total{"returnedtrx$curr"} );
      printf( "Submitted in Batches - $curr\t%.2f\t%0d\n", $total{"batch$curr"},                                                      $total{"batchtrx$curr"} );
      print "Summary - $curr\n";
      print "Date\tTran. Type\tCard Type\tAmt\tCount\tAmt. Net Voids\n";
      foreach my $transdate ( sort keys %cardtotals ) {

        foreach my $txntype ( sort keys %{ $cardtotals{$transdate} } ) {
          if ( $txntype =~ /^batch/ ) {
            next;
          }
          foreach my $cardtype ( sort keys %{ $cardtotals{$transdate}{$txntype} } ) {
            my $transdatestr = substr( $transdate, 4, 2 ) . "/" . substr( $transdate, 6, 2 ) . "/" . substr( $transdate, 0, 4 ) . " ";
            my $total        = $cardtotals{$transdate}{$txntype}{$cardtype}{'success'}{'total'}{$curr};
            my $trxs         = $cardtotals{$transdate}{$txntype}{$cardtype}{'success'}{'trxs'}{$curr};
            if ( $total > 0 ) {
              printf( "$transdatestr\t$txntype\t$smps::cardarray{$cardtype}\t%.2f\t%0d\t", $total, $trxs );
              my $voidamt = $cardtotals{$transdate}{ $txntype . "void" }{$cardtype}{'success'}{'total'}{$curr};
              my $nettotal = sprintf( "%.2f", $total - $voidamt );
              print "$nettotal\n";
            }
          }
        }
      }
    }
    printf( "Total Authorized - $smps::currency\t%.2f\t%0d\n",          $ntotal{"auth$smps::currency"},   $ntotal{"authtrx$smps::currency"} );
    printf( "Total Marked for Batching - $smps::currency\t%.2f\t%0d\n", $ntotal{"marked$smps::currency"}, $ntotal{"markedtrx$smps::currency"} );
    printf(
      "Total Settled - $smps::currency\t%.2f\t%0d\n",
      $ntotal{"settled$smps::currency"} + $ntotal{"postauth$smps::currency"} + $ntotal{"capture$smps::currency"},
      $ntotal{"postauthtrx$smps::currency"}
    );
    printf( "Total Returned - $smps::currency\t%.2f\t%0d\n", $ntotal{"markret$smps::currency"} + $ntotal{"return$smps::currency"}, $ntotal{"returnedtrx$smps::currency"} );
    printf( "Total Submitted in Batches - $smps::currency\t%.2f\t%0d\n", $ntotal{"batch$smps::currency"}, $ntotal{"batchtrx$smps::currency"} );
    print "Total Summary - $smps::currency\n";
    print "Date\tTran. Type\tCard Type\tAmt\tCount\tAmt. Net Voids\n";

    foreach my $transdate ( sort keys %ncardtotals ) {
      foreach my $txntype ( sort keys %{ $ncardtotals{$transdate} } ) {
        if ( $txntype =~ /^batch/ ) {
          next;
        }
        foreach my $cardtype ( sort keys %{ $cardtotals{$transdate}{$txntype} } ) {
          my $transdatestr = substr( $transdate, 4, 2 ) . "/" . substr( $transdate, 6, 2 ) . "/" . substr( $transdate, 0, 4 ) . " ";
          my $total        = $ncardtotals{$transdate}{$txntype}{$cardtype}{'success'}{'total'}{$smps::currency};
          my $trxs         = $ncardtotals{$transdate}{$txntype}{$cardtype}{'success'}{'trxs'}{$smps::currency};
          if ( $total > 0 ) {
            printf( "$transdatestr\t$txntype\t$smps::cardarray{$cardtype}\t%.2f\t%0d\t", $total, $trxs );
            my $voidamt = $ncardtotals{$transdate}{ $txntype . "void" }{$cardtype}{'success'}{'total'}{$smps::currency};
            my $nettotal = sprintf( "%.2f", $total - $voidamt );
            print "$nettotal\n";
          }
        }
      }
    }
    if ( $smps::username =~ /ipayfriendf|friendfind/ ) {
      my $declinecnt = "";
      my $dupcnt     = "";
      foreach my $key ( keys %customercnt ) {
        $declinecnt++;
        if ( $customercnt{$key} > 1 ) {
          $dupcnt += ( $customercnt{$key} - 1 );
        }
      }
      print "Number of Unique Customers with Declined Cards:$declinecnt\n";
      print "Number of Duplicate Declines:$dupcnt\n";
    }
  }

  &logToDataLog(
    { 'originalLogFile' => '/home/pay1/database/debug/smps.txt',
      'function'        => $smps::function,
      'elapsedTime'     => $elapse,
      'username'        => $smps::username,
      'login'           => $ENV{'LOGIN'},
      'remoteUser'      => $ENV{'REMOTE_USER'}
    }
  );

  if ( $elapse > 30 ) {
    &logToDataLog(
      { 'originalLogFile'  => '/home/pay1/database/debug/smps_longqueries.txt',
        'transactionCount' => $smps::trancount,
        'function'         => $smps::function,
        'elapsedTime'      => $elapse,
        'username'         => $smps::username,
        'login'            => $ENV{'LOGIN'},
        'remoteUser'       => $ENV{'REMOTE_USER'},
        'logReason'        => 'smps query exceeds "long" threshold'
      }
    );
  }
}

sub daily_report_query {
  my (
    $subacct,     $orderid,   $refnumber, $cardname,   $amount,     $trans_date, $trans_time,   $trans_type, $auth_code, $result, $descr,
    $finalstatus, $operation, $acct_code, $acct_code2, $acct_code3, $acct_code4, $card_country, $username,   $accttype,  $merchantid
  );
  my ( $debit_credit, $storenum, %status, %trans );
  my ( $fname, $lname );

  my @now = gmtime(time);
  my $today = sprintf( "%02d%02d%02d", $now[5] + 1900, $now[4] + 1, $now[3] );

  my $startyear      = $smps::query->param('startyear');
  my $startmonth     = $smps::query->param('startmonth');
  my $startday       = $smps::query->param('startday');
  my $endyear        = $smps::query->param('endyear');
  my $endmonth       = $smps::query->param('endmonth');
  my $endday         = $smps::query->param('endday');
  my $settletimezone = $smps::query->param('settletimezone');

  $startyear =~ s/[^0-9]//g;
  $startmonth =~ s/[^0-9]//g;
  $startday =~ s/[^0-9]//g;

  $endyear =~ s/[^0-9]//g;
  $endmonth =~ s/[^0-9]//g;
  $endday =~ s/[^0-9]//g;

  my $startdate = sprintf( "%04d%02d%02d", $startyear, $startmonth, $startday );
  my $starttime = $startdate . "000000";
  my $enddate   = sprintf( "%04d%02d%02d", $endyear, $endmonth, $endday );
  my $endtime   = $enddate . "000000";

  if ( $settletimezone ne "" ) {
    $starttime = &miscutils::strtotime($starttime);
    $starttime -= ( $settletimezone * 60 * 60 );
    $starttime = &miscutils::timetostr($starttime);

    $endtime = &miscutils::strtotime($endtime);
    $endtime -= ( $settletimezone * 60 * 60 );
    $endtime = &miscutils::timetostr($endtime);
  }

  if ( $smps::format =~ /^(text|download)$/ ) {
    print
      "Store No.\tCreated Date\tPayment Method\tDebit or Credit\tReceipt\#\tCardholder Name\tBill to Lname\tBill to Fname\tTransaction Type\tAmount\tAuthorization Code\tStatus\tMerchant ID\tResponse Code\tResponse Description\tUsername\tTransactionID\n";
  } else {
    print "<table border=1 cellspacing=0 cellpadding=2>\n";
    print "  <tr>\n";
    print "    <th>Store #</th>\n";
    print "    <th>Created Date</th>\n";
    print "    <th>Payment Method</th>\n";
    print "    <th>Debit or Credit</th>\n";
    print "    <th>Receipt\#</th>\n";
    print "    <th>Cardholder Name</th>\n";
    print "    <th>Bill to Lname</th>\n";
    print "    <th>Bill to Fname</th>\n";
    print "    <th>Transaction Type</th>\n";
    print "    <th>Amount</th>\n";
    print "    <th>Authorization Code</th>\n";
    print "    <th>Status</th>\n";
    print "    <th>Merchant ID</th>\n";
    print "    <th>Response Code</th>\n";
    print "    <th>Response Description</th>\n";
    print "    <th>Username</th>\n";
    print "    <th>TransactionID</th>\n";
    print "  </tr>\n";
  }
  my $temptimestr = $today . "000000";
  $today = substr( $starttime, 0, 8 );
  my $st = &miscutils::strtotime($starttime);
  $st -= ( 4 * 24 * 60 * 60 );
  $st = &miscutils::timetostr($st);
  my $sd = substr( $st, 0, 8 );

  my $dbh = &miscutils::dbhconnect("pnpdata");
  my $qstr =
    "select orderid,refnumber,card_name,amount,trans_date,trans_time,trans_type,auth_code,result,descr,finalstatus,operation,acct_code,acct_code2,acct_code3,acct_code4,card_country,username,accttype,merchant_id";
  $qstr .= " from trans_log FORCE INDEX(tlog_tdateuname_idx) ";
  $qstr .= " where trans_date>='$sd'  ";

  $qstr .= "and trans_time>='$starttime' ";
  $qstr .= "and trans_time<'$endtime' ";

  if ( exists $smps::altaccts{$smps::username} ) {
    my ($temp);
    foreach my $var ( @{ $smps::altaccts{$smps::username} } ) {
      $temp .= "'$var',";
    }
    chop $temp;
    $qstr .= " and username IN ($temp) ";
  } elsif ( ( $smps::linked_accts ne "" ) && ( $smps::feature{'linked_list'} = "yes" ) && ( $smps::username ne $ENV{'LOGIN'} ) ) {
    $qstr .= " and username IN ($smps::linked_accts) ";
  } elsif ( $smps::fuzzyun ne "" ) {
    $qstr .= " and username LIKE '$smps::fuzzyun%' ";
  } elsif ( $smps::linked_accts ne "" ) {
    $qstr .= " and username IN ($smps::linked_accts) ";
  } else {
    $qstr .= " and username='$smps::username' ";
  }

  $qstr .= " and username NOT IN ('jhewitt01','jhewitt02','jhewcorp','jhewitt','jhew00000')";
  $qstr .= " and operation IN ('auth','forceauth','return','postauth','void','reauth')";
  $qstr .= " and (duplicate IS NULL or duplicate='')";
  $qstr .= " ORDER BY orderid, trans_time";

  my $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
  $sth->execute or die "Can't execute: $DBI::errstr";
  my $rv = $sth->bind_columns(
    undef,
    \($orderid,     $refnumber, $cardname,  $amount,     $trans_date, $trans_time, $trans_type,   $auth_code, $result,   $descr,
      $finalstatus, $operation, $acct_code, $acct_code2, $acct_code3, $acct_code4, $card_country, $username,  $accttype, $merchantid
     )
  );

  while ( $sth->fetch ) {
    my $time = $trans_time;
    if ( ( $settletimezone ne "" ) && ( $settletimezone != 0 ) ) {
      $time = &miscutils::strtotime($time);
      $time += ( $smps::settletimezone * 60 * 60 );
      $time = &miscutils::timetostr($time);
    }

    my $timestr = substr( $time, 4, 2 ) . "/" . substr( $time, 6, 2 ) . "/" . substr( $time, 0, 4 ) . " ";
    $timestr = $timestr . substr( $time, 8, 2 ) . ":" . substr( $time, 10, 2 ) . ":" . substr( $time, 12, 2 );

    if ( $operation =~ /return/ ) {
      $debit_credit = "D";
    } else {
      $debit_credit = "C";
    }
    my $receiptnum = $acct_code2;

    my $tempname = $cardname;
    $tempname =~ s/[^a-zA-Z\ ]//g;
    my ( $name1, $name2, $name3 ) = split( / /, $tempname, 3 );

    if ( $name3 eq "" ) {
      $fname = $name1;
      $lname = $name2;
    } elsif ( ( $name3 ne "" ) && ( length($name2) == 1 ) ) {
      $fname = $name1 . " " . $name2;
      $lname = $name3;
    } elsif ( $name3 ne "" ) {
      $fname = $name1;
      $lname = $name2 . " " . $name3;
    }

    my $authcode = substr( $auth_code, 0, 6 );
    my $status = "";
    my ( $respcode, $respdesc ) = split( /\:/, $descr );
    if ( $finalstatus =~ /success/ ) {
      $respdesc = "Approved";
    }
    if ( $acct_code ne "" ) {
      $storenum = "$acct_code";
    } else {
      $storenum = "$username";
    }

    $status{"$orderid\|$operation"} = $finalstatus;
    $trans{"$storenum\|$orderid\|$operation"} =
      "$timestr\t$debit_credit\t$receiptnum\t$cardname\t$lname\t$fname\t$trans_type\t$amount\t$authcode\t$merchantid\t$respcode\t$respdesc\t$username\t$accttype\t$acct_code\t$acct_code2\t$acct_code3\t$trans_date";
  }
  $sth->finish;
  $dbh->disconnect;

  foreach my $key ( sort keys %trans ) {
    my ( $storenum, $oid, $operation ) = split( /\|/, $key );
    my ($status);
    if ( $operation eq 'auth' ) {
      if ( ( exists $status{"$oid\|void"} ) ) {
        $status = "voided";
      } elsif ( ( $status{"$oid\|postauth"} =~ /pending|success/ ) ) {
        $status = "settled";
      } elsif ( $status{"$oid\|auth"} eq "success" ) {
        $status = "waiting settlement";
      } else {
        $status = "declined";
      }
    } elsif ( $operation eq 'return' ) {
      if ( ( $status{"$oid\|return"} eq "pending" ) && ( exists $status{"$oid\|void"} ) ) {
        $status = "voided";
      } elsif ( ( $status{"$oid\|return"} eq "pending|success" ) ) {
        $status = "settled";
      }
    }
    my (
      $timestr,    $debit_credit, $receiptnum, $cardname, $fname,    $lname,     $trans_type, $amount,     $authcode,
      $merchantid, $respcode,     $respdesc,   $username, $accttype, $acct_code, $acct_code2, $acct_code3, $trans_date
      )
      = split( /\t/, $trans{$key} );
    if ( $operation =~ /^(auth|return)$/ ) {
      if ( $accttype eq "" ) {
        $accttype = "credit";
      }
      my $storenum = substr( $storenum, 4, 6 );

      if ( ( $smps::query->param('result') eq "" )
        || ( ( $smps::query->param('result') eq "approved" ) && ( $status ne "declined" ) )
        || ( ( $smps::query->param('result') eq "declined" ) && ( $status eq "declined" ) ) ) {

        if ( ( $smps::query->param('merchant') eq "ALL" ) && ( $smps::feature{'linked_list'} eq "yes" ) && ( $username !~ /^($smps::feature{'linked_accts'})$/ ) ) {

          # skip this entry, as it does not exist in sub-login's custom linked account list
          next;
        } elsif ( ( $smps::query->param('merchant') ne "$username" ) && ( $smps::query->param('merchant') ne "ALL" ) ) {

          # skip this entry, as it does not belong to merchant specified
          next;
        }

        if ( $smps::format =~ /^(text|download)$/ ) {
          print "$storenum\t$timestr\t$accttype\t$debit_credit\t$receiptnum\t$cardname\t$lname\t$fname\t$trans_type\t$amount\t$authcode\t$status\t$merchantid\t$respcode\t$respdesc\t$username\t$oid\n";
        } else {
          print "  <tr>\n";
          print "    <td><nobr>$storenum</nobr></td>\n";
          print "    <td><nobr>$timestr</nobr></td>\n";
          print "    <td><nobr>$accttype</nobr></td>\n";
          print "    <td><nobr>$debit_credit</nobr></td>\n";
          print "    <td><nobr>$receiptnum</nobr></td>\n";
          print "    <td><nobr>$cardname</nobr></td>\n";
          print "    <td><nobr>$fname</nobr></td>\n";
          print "    <td><nobr>$lname</nobr></td>\n";
          print "    <td><nobr>$trans_type</nobr></td>\n";
          print "    <td><nobr>$amount</nobr></td>\n";
          print "    <td><nobr>$authcode</nobr></td>\n";
          print "    <td><nobr>$status</nobr></td>\n";
          print "    <td><nobr>$merchantid</nobr></td>\n";
          print "    <td><nobr>$respcode</nobr></td>\n";
          print "    <td><nobr>$respdesc</nobr></td>\n";
          print "    <td><nobr>$username</nobr></td>\n";
          print "    <td><nobr>$oid</nobr></td>\n";
          print "  </tr>\n";
        }
      }
    }
  }

  if ( $smps::format !~ /^(text|download)$/ ) {
    print "</table>\n";
  }

}

sub batchretry {
  my $batchid  = $smps::query->param('batchid');
  my $accttype = $smps::query->param('accttype');

  my %batch_result = &miscutils::sendmserver( "$smps::username", 'batch-retry', 'accttype', "$accttype", 'batch-id', "$batchid" );

  print %batch_result;
  print "<br>\n";

  print "<b>Batch ID:</b> " . $batch_result{"batch-id"} . "<br>\n";
  print "<b>Gateway Batch ID:</b> " . $batch_result{"gw-batch-id"} . "<br>\n";
  print "<b>Status:</b> " . $batch_result{"FinalStatus"} . "<br>\n";
  print "<b>Batch Status:</b> " . $batch_result{"batch-status"} . "<br>\n";
  print "<b>Batch Message:</b> " . $batch_result{"MErrMsg"} . "<br>\n";
  print "<b>Batch Amount:</b> " . $batch_result{"total-amount"} . "<br><br>\n";

  print "<div align=center><table border=1 cellspacing=0 cellpadding=2>\n";
  print "<th align=left>Order ID</th>\n";
  print "<th align=left>Result</th>\n";
  print "<th align=left>Exception</th>\n";
  for ( my $i = 1 ; $i <= 500 ; $i++ ) {
    if ( $batch_result{"order-id-$i"} eq "" ) {
      last;
    }
    print "<tr>\n";
    print "<td>" . $batch_result{"order-id-$i"} . "</td>\n";
    print "<td>" . $batch_result{"response-code-$i"} . "</td>\n";
    print "<td>" . $batch_result{"exception-message-$i"} . "</td>\n";
  }
  print "</table></div><br>\n";

  print "<hr width=400><br>\n";

}

sub batchquery {
  if ( -e "/home/pay1/outagefiles/highvolume.txt" ) {
    print "Sorry, this program is not available at this time.<p>\n";
    print "Please try back in a little while.<p>\n";
    return;
  }

  my %badcardarray = ();
  my ( $batchfile, $dateold, $batchidold, $usernameold );
  my $accttype      = $smps::query->param('accttype');
  my $cardtype      = $smps::query->param('cardtype');
  my $txnstatus     = $smps::query->param('txnstatus');
  my $batchstatusin = $smps::query->param('batchstatus');
  my $startdate     = $smps::query->param('startdate');
  my $enddate       = $smps::query->param('enddate');
  my $currency      = $smps::query->param('currency');
  my $lowamount     = $smps::query->param('lowamount');
  my $highamount    = $smps::query->param('highamount');
  my $orderid       = $smps::query->param('orderid');
  my $batchid       = $smps::query->param('batchid');
  my $showdetails   = $smps::query->param('showdetails');
  my $display_acct  = $smps::query->param('display_acct');
  my $display_ext   = $smps::query->param('display_ext');
  ## DCP 20080204
  my $display_rept = $smps::query->param('display_rept');
  my $acct_code    = $smps::query->param('acct_code');

  my ( $starttime, $endtime, $transtype, $reportdata );

  my ( $adjustmentFlag, $surchargeFlag ) = getAdjustmentFlags();

  if ( $lowamount > 0 ) {
    $lowamount = "$smps::currency $lowamount";
  }
  if ( $highamount > 0 ) {
    $highamount = "$smps::currency $highamount";
  }

  my $startyear  = $smps::query->param('startyear');
  my $startmonth = $smps::query->param('startmonth');
  my $startday   = $smps::query->param('startday');
  $startyear =~ s/[^0-9]//g;
  $startmonth =~ s/[^0-9]//g;
  $startday =~ s/[^0-9]//g;

  if ( ( $startyear >= 1999 ) && ( $startmonth >= 1 ) && ( $startmonth < 13 ) && ( $startday >= 1 ) && ( $startday < 32 ) ) {
    $startdate = sprintf( "%02d/%02d/%04d", $startmonth, $startday, $startyear );
  }

  my $tmpstartdate = substr( $startdate, 6, 4 ) . substr( $startdate, 0, 2 ) . substr( $startdate, 3, 2 );
  if ( $tmpstartdate < $smps::earliest_date ) {
    $startdate = substr( $smps::earliest_date, 4, 2 ) . "/" . substr( $smps::earliest_date, 6, 2 ) . "/" . substr( $smps::earliest_date, 0, 4 );
  }

  my $endyear  = $smps::query->param('endyear');
  my $endmonth = $smps::query->param('endmonth');
  my $endday   = $smps::query->param('endday');
  $endyear =~ s/[^0-9]//g;
  $endmonth =~ s/[^0-9]//g;
  $endday =~ s/[^0-9]//g;

  if ( ( $endyear >= 1999 ) && ( $endmonth >= 1 ) && ( $endmonth < 13 ) && ( $endday >= 1 ) && ( $endday < 32 ) ) {
    $enddate = sprintf( "%02d/%02d/%04d", $endmonth, $endday, $endyear );
  }

  if ( $startdate ne "" ) {
    my ( $m, $d, $y ) = split( /\//, $startdate );
    $starttime = sprintf( "%04d%02d%02d000000", $y, $m, $d );

    my $chkstartdate = substr( $starttime, 0, 8 );
    if ( $smps::earliest_date > $chkstartdate ) {
      $starttime = $smps::earliest_date . "000000";
    }

    if ( $smps::settletimezone ne "" ) {
      $starttime = &miscutils::strtotime($starttime);
      $starttime -= ( $smps::settletimezone * 60 * 60 );
      $starttime = &miscutils::timetostr($starttime);
    }

    if ( $starttime < '19990101000000' ) {
      $starttime = "";
      $startdate = "";
    }
  }
  if ( $enddate ne "" ) {
    my ( $m, $d, $y ) = split( /\//, $enddate );
    $endtime = sprintf( "%04d%02d%02d000000", $y, $m, $d );
    if ( $smps::settletimezone ne "" ) {
      $endtime = &miscutils::strtotime($endtime);
      $endtime -= ( $smps::settletimezone * 60 * 60 );
      $endtime = &miscutils::timetostr($endtime);
    }
  }

  #### START 3 Month Limit Check
  my ( $m, $d, $y );

  ( $m, $d, $y ) = split( /\//, $startdate );
  my $startdatestr = sprintf( "%04d%02d%02d", $y, $m, $d );

  ( $m, $d, $y ) = split( /\//, $enddate );
  my $enddatestr = sprintf( "%04d%02d%02d", $y, $m, $d );

  if ( $enddatestr < 20010000 ) {
    my $junk = "";
    ( $junk, $enddatestr ) = &miscutils::gendatetime( 24 * 60 * 60 );
  }

  my $starttimea = &miscutils::strtotime($startdatestr);
  my $endtimea   = &miscutils::strtotime($enddatestr);
  my $elapse     = $endtimea - $starttimea;

  if ( $elapse > ( 93 * 24 * 3600 ) ) {
    my $message = "Sorry, but no more than 3 months may be queried at one time.  Please use the back button and change your selected date range.";
    print "$message\n";
    return;
  } elsif ( ( $smps::username =~ /^(friendfinde)$/ ) && ( $elapse > ( 8 * 24 * 3600 ) ) ) {
    my $message = "Sorry, but no more than 7 days may be queried at one time when performing a Review Batch.";
    print "$message\n";
    return;
  }

  if ( ( $smps::format eq "" ) || ( $smps::format eq "table" ) ) {
    print "<table border=1 cellspacing=0 cellpadding=2>\n";
    print "<tr>\n";
    if ( ( $smps::fuzzyun ne "" ) || ( $smps::linked_accts ne "" ) ) {
      print "<th align=left>Username</th>";
    }
    if ( ( $showdetails ne "" ) || ( ( $accttype eq "checking" ) && ( $smps::chkprocessor !~ /^(alliance|alliancesp|echo|delaware|paymentdata|telecheck|telecheckftf|citynat|securenetach|mtbankach)$/ ) ) )
    {
      print "<th align=left>Type</th>";
      print "<th align=left>Status</th>";
      print "<th align=left>Name</th>";
      if ( $accttype eq "checking" ) {
        print "<th align=left>Batch ID</th>";
        print "<th align=left>Gateway<br>Batch ID</th>";
      } else {
        print "<th align=left>Order ID</th>";
        print "<th align=left>Batch ID</th>";
      }
      print "<th>Transaction Time <font size=-2>(GMT $smps::settletimezone)<br>MM/DD/YYYY HH:MM:SS</font></th>";
      print "<th align=left>Batch<br>Status</th>";
      print "<th>Card Type</th>";
      if ( ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) && ( $smps::feature{'display_cclast4'} == 1 ) ) {
        print "<th>Card Masked</th>";
      } elsif ( ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) && ( $smps::feature{'display_cc'} == 1 ) ) {
        print "<th>Card Number</th>";
      }
      if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
        print "<th colspan=2>Amount</th>\n";
      } else {
        print "<th align=left>Amount</th>\n";
      }
      if ( $adjustmentFlag == 1 ) {
        print "<th align=\"left\">Base Amount</th>\n";
        if ( $surchargeFlag == 1 ) {
          print "<th align=\"left\">Credit Card Fee</th>\n";
        } else {
          print "<th align=\"left\">Service Fee</th>\n";
        }
      }

      if ( $display_acct eq "yes" ) {
        print "<th>Acct Code1</th>\n";
        print "<th>Acct Code2</th>\n";
        print "<th>Acct Code3</th>\n";
        if ( $smps::feature{'display_ac4'} == 1 ) {
          print "<th>Acct Code4</th>\n";
        }
        print "<th>Company</th>\n";
      }
      if ( $smps::feature{'display_authcode'} == 1 ) {
        print "<th>Auth Code</th>\n";
      }
      ## DCP 20080204
      if ( $display_rept eq "yes" ) {
        print "<th align=left>Report Data</th>";
      }
    }
  } elsif ( $smps::format =~ /^(text|download)$/ ) {
    if ( ( $smps::fuzzyun ne "" ) || ( $smps::linked_accts ne "" ) ) {
      print "Username\t";
    }
    if ( ( $showdetails ne "" ) || ( ( $accttype eq "checking" ) && ( $smps::chkprocessor !~ /^(alliance|alliancesp|echo|delaware|paymentdata|telecheck|telecheckftf|citynat|securenetach|mtbankach)$/ ) ) )
    {
      print "Type\t";
      print "Status\t";
      print "Name\t";
      if ( $accttype eq "checking" ) {
        print "Batch ID\t";
        print "Gateway Batch ID\t";
      } else {
        print "Order ID\t";
        print "Batch ID\t";
      }
      print "Transaction Time (GMT)\t";
      print "Batch Status\t";
      print "Card Type\t";
      if ( ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) && ( $smps::feature{'display_cclast4'} == 1 ) ) {
        print "Card Masked\t";
      } elsif ( ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) && ( $smps::feature{'display_cc'} == 1 ) ) {
        print "Card Number\t";
      }
      if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
        print "Conv. Amount\tNative Amount\t";
      } else {
        print "Amount\t";
      }
      if ( $adjustmentFlag == 1 ) {
        print "Base Amount\t";
        if ( $surchargeFlag == 1 ) {
          print "CreditCardFee\t";
        } else {
          print "ServiceFee\t";
        }
      }

      if ( $display_acct eq "yes" ) {
        print "Acct Code1\t";
        print "Acct Code2\t";
        print "Acct Code3\t";
        if ( $smps::feature{'display_ac4'} == 1 ) {
          print "Acct Code4\t";
        }
      }
      if ( $smps::feature{'display_authcode'} == 1 ) {
        print "Auth Code\t";
      }
      ## DCP  20080204
      if ( $display_rept eq "yes" ) {
        print "Report Data\t";
      }
      if ( ( $display_ext eq "yes" ) || ( $smps::feature{'display_ext'} == 1 ) ) {
        print "Order Description\t";
      }
      print "\n";
    }
  }

  $transtype = "batchquery";

  my (%result);
  if ( ( $smps::username eq "icommerceg" ) && ( $ENV{'SUBACCT'} ne "" ) ) {
    my ( $maxidx, $i );
    if ( exists $smps::altaccts{$smps::username} ) {
      foreach my $var ( @{ $smps::altaccts{$smps::username} } ) {
        my %res_icg = &miscutils::sendmserver(
          "$var",       "$transtype", 'accttype',   "$accttype",  'low-amount', "$lowamount", 'high-amount', "$highamount", 'batch-id', "$batchid",
          'txn-status', "$txnstatus", 'start-time', "$starttime", 'end-time',   "$endtime",   'txn-type',    "batch"
        );

        foreach my $key ( keys %res_icg ) {
          $i++;
          $result{"a$i"} = $res_icg{$key};
        }
      }
    }
  } else {
    %result = &miscutils::sendmserver(
      "$smps::username", "$transtype",          'accttype',   "$accttype",      'low-amount', "$lowamount", 'high-amount', "$highamount",
      'batch-id',        "$batchid",            'txn-status', "$txnstatus",     'start-time', "$starttime", 'end-time',    "$endtime",
      'linked_accts',    "$smps::linked_accts", 'fuzzyun',    "$smps::fuzzyun", 'txn-type',   "batch"
    );
  }
  my (
    %cntarray, %cntarray1, %cntarray2, %cntarray3, %datearray, %amtarray, %amtarray1,       %amtarray2, %amtarray3,
    $total,    %cnttotal,  %amttotal,  %cnttotal3, %amttotal3, %unhash,   %baseAmountArray, %adjustmentArray
  );
  my ( %acarray,          %ac2array,         %ac3array );
  my ( %cardtypecnttotal, %cardtypeamttotal, %currency_types, %cardtypecnttotal3, %cardtypeamttotal3, %total, %cardtotals, %cardtotals2, %cardtotals3, %tran_hash, %total_native );
  my ( $txntype,          $status,           $gateid, $batchstatus, $amount, $cardnumber, $cardname, $acct_code2, $acct_code3, $acct_code4, $auth_code, $timestr, $datestr, $card_company, $username );

  my ($dbhod);
  if ( ( $display_ext eq "yes" ) || ( $smps::feature{'display_ext'} == 1 ) ) {
    $dbhod = &miscutils::dbhconnect("pnpdata");
  }

  ### Get adjustment fees ###
  my ( $adjustmentHashRef, $baseAmount, $adjustment );
  if ( $adjustmentFlag == 1 ) {

    # first get order IDs
    my @orderIDArray = ();
    my @values       = values %result;
    foreach my $var ( sort @values ) {
      my (%resultHash);
      my @nameval = split( /&/, $var );
      foreach my $temp (@nameval) {
        my ( $name, $value ) = split( /=/, $temp );
        $resultHash{$name} = $value;
      }
      push( @orderIDArray, $resultHash{"order-id"} );
    }

    # then create adjustment hash
    if (@orderIDArray) {
      $adjustmentHashRef = loadMultipleAdjustments( \@orderIDArray );
    }
  }

  my $color  = 1;
  my @values = values %result;
  foreach my $var ( sort @values ) {
    my (%res2);
    my @nameval = split( /&/, $var );
    foreach my $temp (@nameval) {
      my ( $name, $value ) = split( /=/, $temp );
      $res2{$name} = $value;
    }

    if ( ( $res2{'time'} ne "" ) && ( ( $batchstatusin eq "" ) || ( $res2{'batch-status'} eq $batchstatusin ) ) ) {

      my $time = $res2{"time"};
      if ( ( $smps::settletimezone ne "" ) && ( $smps::settletimezone != 0 ) ) {
        $time = &miscutils::strtotime($time);
        $time += ( $smps::settletimezone * 60 * 60 );
        $time = &miscutils::timetostr($time);
      }

      $datestr = substr( $time, 4, 2 ) . "/" . substr( $time, 6, 2 ) . "/" . substr( $time, 0, 4 ) . " ";
      $timestr = $datestr . substr( $time, 8, 2 ) . ":" . substr( $time, 10, 2 ) . ":" . substr( $time, 12, 2 );

      $txntype      = $res2{"txn-type"};
      $status       = $res2{"txn-status"};
      $batchid      = $res2{"batch-id"};
      $orderid      = $res2{"order-id"};
      $gateid       = $res2{"gw-batch-id"};
      $batchstatus  = $res2{"batch-status"};
      $amount       = $res2{"amount"};
      $cardnumber   = $res2{"card-number"};
      $cardname     = $res2{'card-name'};
      $card_company = $res2{'card-company'};

      # get base fees and adjustment fees for each order id
      if ( $adjustmentFlag == 1 ) {
        if ( $adjustmentHashRef->{$orderid} ) {
          $baseAmount = $adjustmentHashRef->{$orderid}->getBaseAmount();
          $adjustment = $adjustmentHashRef->{$orderid}->getAdjustmentTotalAmount();
        }
      }

      my $transflags = $res2{'transflags'};
      if ( ( $transflags =~ /redo$/ ) && ( $ENV{'LOGIN'} !~ /(processa)/ ) ) {
        next;
      }

      if ( $txntype eq "chargeback" ) {
        my $descr = $res2{"descr"};
        my $date = substr( $time, 0, 8 );
        $badcardarray{"$date $orderid $batchid $amount $cardname"} = $descr;
        next;
      }

      if ( $accttype eq "checking" ) {
        $cardtype = $status;
      } else {
        $cardtype = $res2{'card-type'};
      }

      $acct_code  = $res2{'acct_code'};
      $acct_code2 = $res2{'acct_code2'};
      $acct_code3 = $res2{'acct_code3'};
      $acct_code4 = $res2{'acct_code4'};

      $acarray{$orderid}  = $acct_code;
      $ac2array{$orderid} = $acct_code2;
      $ac3array{$orderid} = $acct_code3;

      $auth_code = substr( $res2{'auth-code'}, 0, 6 );

      $username = $res2{'username'};

      my $time1 = substr( $time, 0, 8 );

      if ( $txntype eq "postauth" ) {
        if ( exists $tran_hash{"$orderid$txntype$status"} ) {
          next;
        } else {
          $tran_hash{"$orderid$txntype$status"} = 1;
        }
      }

      my ( $currency, $price ) = split( / /, $amount );
      $currency_types{$currency} = 1;
      $cntarray{"$username $batchid $cardtype"}++;
      $cntarray1{"$time1 $cardtype"}++;
      $cntarray2{"$batchid $cardtype $currency"}++;
      $cntarray3{"$time1 $cardtype $currency"}++;

      # Adjustment totals
      if ( $adjustmentFlag == 1 ) {

        # calculate base amount and adjustment totals for each card type
        if ( $txntype eq "return" ) {
          $baseAmountArray{"$time1 $cardtype"} -= $baseAmount;
          $adjustmentArray{"$time1 $cardtype"} -= $adjustment;
        } else {
          $baseAmountArray{"$time1 $cardtype"} += $baseAmount;
          $adjustmentArray{"$time1 $cardtype"} += $adjustment;
        }
      }

      $datearray{"$batchid"} = $datestr;
      $unhash{"$batchid"}    = $username;

      if ( $accttype eq "checking" ) {
        $cntarray{"$username $batchid TOTAL"}++;
      }

      my ( $native_sym, $merch_sym, $native_amt, $native_isocur, $conv_rate );
      ##  DCP  Modify line below MC == 1
      if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
        my %currencyUSDSYM = ( 'AUD', 'A$', 'CAD', 'C$', 'EUR', '&#8364;', 'GBP', '&#163;', 'JPY', '&#165;', 'USD', '$' );
        my %currency840SYM = ( '036', 'A$', '124', 'C$', '978', '&#8364;', '826', '&#163;', '392', '&#165;', '997', '$' );

        $conv_rate = smpsutils::conversionRateFromAuthCodeColumnData({
          processor => $smps::processor,
          authCodeColumnData => $res2{'auth-code'}
        });

        $native_amt = smpsutils::calculateNativeAmountFromAuthCodeColumnData({
          processor => $smps::processor,
          authCodeColumnData => $res2{'auth-code'},
          nativeCurrency => $currency,
          convertedAmount => $price
        });

        $native_sym = $currency840SYM{$currency};
        $merch_sym  = $currencyUSDSYM{$smps::currency};

        $native_isocur = $smps::currency;
        $native_isocur =~ tr/A-Z/a-z/;

        if ( $txntype eq "return" ) {
          $amtarray{"$username $batchid $cardtype"}  -= $native_amt;
          $amtarray1{"$time1 $cardtype"}             -= $native_amt;
          $amtarray2{"$batchid $cardtype $currency"} -= $price;
          $amtarray3{"$time1 $cardtype $currency"}   -= $price;
          $total{$currency}                          -= $price;
          $total_native{$smps::currency}             -= $native_amt;
        } else {
          $amtarray{"$username $batchid $cardtype"}  += $native_amt;
          $amtarray1{"$time1 $cardtype"}             += $native_amt;
          $amtarray2{"$batchid $cardtype $currency"} += $price;
          $amtarray3{"$time1 $cardtype $currency"}   += $price;
          $total{$currency}                          += $price;
          $total_native{$smps::currency}             += $native_amt;
        }

        if ( $cardtype =~ /^(vs|mc)$/ ) {
          my $cardtypeC = "vsmc";
          $cntarray{"$username $batchid $cardtypeC"}++;
          $cntarray1{"$time1 $cardtypeC"}++;
          $cntarray2{"$batchid $cardtypeC $currency"}++;
          $cntarray3{"$time1 $cardtypeC $currency"}++;

          if ( $txntype eq "return" ) {
            $amtarray{"$username $batchid $cardtypeC"}  -= $native_amt;
            $amtarray1{"$time1 $cardtypeC"}             -= $native_amt;
            $amtarray2{"$batchid $cardtypeC $currency"} -= $price;
            $amtarray3{"$time1 $cardtypeC $currency"}   -= $price;
          } else {
            $amtarray{"$username $batchid $cardtypeC"}  += $native_amt;
            $amtarray1{"$time1 $cardtypeC"}             += $native_amt;
            $amtarray2{"$batchid $cardtypeC $currency"} += $price;
            $amtarray3{"$time1 $cardtypeC $currency"}   += $price;
          }
        }
      } elsif ( $smps::processor =~ /^($smps::mcprocessors)$/ ) {
        $native_amt = $price;
        if ( $txntype eq "return" ) {
          $amtarray{"$username $batchid $cardtype"}  -= $native_amt;
          $amtarray1{"$time1 $cardtype"}             -= $native_amt;
          $amtarray2{"$batchid $cardtype $currency"} -= $price;
          $amtarray3{"$time1 $cardtype $currency"}   -= $price;
          $total{$currency}                          -= $price;
          $total_native{$smps::currency}             -= $native_amt;
        } else {
          $amtarray{"$username $batchid $cardtype"}  += $native_amt;
          $amtarray1{"$time1 $cardtype"}             += $native_amt;
          $amtarray2{"$batchid $cardtype $currency"} += $price;
          $amtarray3{"$time1 $cardtype $currency"}   += $price;
          $total{$currency}                          += $price;
          $total_native{$smps::currency}             += $native_amt;
        }

        if ( $cardtype =~ /^(vs|mc)$/ ) {
          my $cardtypeC = "vsmc";
          $cntarray{"$username $batchid $cardtypeC"}++;
          $cntarray1{"$time1 $cardtypeC"}++;
          $cntarray2{"$batchid $cardtypeC $currency"}++;
          $cntarray3{"$time1 $cardtypeC $currency"}++;

          if ( $txntype eq "return" ) {
            $amtarray{"$username $batchid $cardtypeC"}  -= $native_amt;
            $amtarray1{"$time1 $cardtypeC"}             -= $native_amt;
            $amtarray2{"$batchid $cardtypeC $currency"} -= $price;
            $amtarray3{"$time1 $cardtypeC $currency"}   -= $price;
          } else {
            $amtarray{"$username $batchid $cardtypeC"}  += $native_amt;
            $amtarray1{"$time1 $cardtypeC"}             += $native_amt;
            $amtarray2{"$batchid $cardtypeC $currency"} += $price;
            $amtarray3{"$time1 $cardtypeC $currency"}   += $price;
          }
        }
      } else {
        if ( $txntype eq "return" ) {
          $amtarray{"$username $batchid $cardtype"} -= $price;
          $amtarray1{"$time1 $cardtype"}            -= $price;
        } else {
          $amtarray{"$username $batchid $cardtype"} += $price;
          $amtarray1{"$time1 $cardtype"}            += $price;
        }

        if ( $cardtype =~ /^(vs|mc)$/ ) {
          my $cardtypeC = "vsmc";
          $cntarray{"$username $batchid $cardtypeC"}++;
          $cntarray1{"$time1 $cardtypeC"}++;

          if ( $txntype eq "return" ) {
            $amtarray{"$username $batchid $cardtypeC"} -= $price;
            $amtarray1{"$time1 $cardtypeC"}            -= $price;
          } else {
            $amtarray{"$username $batchid $cardtypeC"} += $price;
            $amtarray1{"$time1 $cardtypeC"}            += $price;
          }
        }

        #show 'combined' row for all cardtypes
        if ( $cardtype ne '' ) {
          my $cardtypeC = "zcombined";
          if ( $status ne 'problem' ) {
            $cntarray{"$username $batchid $cardtypeC"}++;
            $cntarray1{"$time1 $cardtypeC"}++;

            if ( $txntype eq "return" ) {
              $amtarray{"$username $batchid $cardtypeC"} -= $price;
              $amtarray1{"$time1 $cardtypeC"}            -= $price;
            } else {
              $amtarray{"$username $batchid $cardtypeC"} += $price;
              $amtarray1{"$time1 $cardtypeC"}            += $price;
            }
          }
        }

        if ( $accttype eq "checking" ) {
          if ( $txntype eq "return" ) {
            $amtarray{"$username $batchid TOTAL"} -= $price;
            $amtarray1{"$time1 TOTAL"}            -= $price;
          } else {
            $amtarray{"$username $batchid TOTAL"} += $price;
            $amtarray1{"$time1 TOTAL"}            += $price;
          }
        }

      }
      if ( ( $showdetails eq "" )
        && ( ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) || ( $smps::chkprocessor !~ /^(alliance|alliancesp|echo|delaware|paymentdata|telecheck|telecheckftf|citynat|securenetach|mtbankach)$/ ) ) ) {
        if ( $txntype !~ /ret/ ) {
          $total += $price;
        } else {
          $total -= $price;
        }
      } else {
        if ( $smps::processor eq "global" ) {
          $reportdata = substr( $res2{'auth-code'}, 166, 25 );
        }
        if ( $smps::format =~ /^(text|download)$/ ) {
          if ( ( $smps::fuzzyun ne "" ) || ( $smps::linked_accts ne "" ) ) {
            print "$username\t";
          }
          print "$txntype\t";
          print "$status\t";
          print "$cardname\t";

          if ( ( $accttype eq "checking" ) && ( $smps::chkprocessor !~ /^(firstamer|selectcheck|alliance|alliancesp|echo|delaware|paymentdata|telecheck|citynat|securenetach|mtbankach)$/ ) ) {
            print "$orderid\t";
            print "$gateid\t";
          } else {
            print "$orderid\t";
            if ( $smps::processor =~ /^(buypass|fdms|fdmsomaha|global|paytechtampa|paytechsalem|visanet)$/ ) {
              print "$batchid\t";
            } else {
              print "\t";
            }

          }

          print "$timestr\t";
          print "$batchstatus\t";
          print "$cardtype\t";
          if ( ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) && ( $smps::feature{'display_cclast4'} == 1 ) ) {
            my $ccnum = &getcn( "$orderid", "$startdatestr", "$enddatestr" );
            my $last4 = substr( $ccnum, length($ccnum) - 4, 4 );
            print "$last4\t";
          } elsif ( ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) && ( $smps::feature{'display_cc'} == 1 ) ) {
            print "$cardnumber\t";
          }
          if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
            if ( $txntype !~ /ret/ ) {
              print "$smps::currency $native_amt\t";
              print "$amount\t";
            } else {
              print "($smps::currency $native_amt)\t";
              print "($amount)\t";
            }
          } elsif ( $smps::processor =~ /^($smps::mcprocessors)$/ ) {
            if ( $txntype !~ /ret/ ) {
              print "$smps::currency $native_amt\t";
              print "$amount\t";
            } else {
              print "($smps::currency $native_amt)\t";
              print "($amount)\t";
            }
          } else {
            if ( $txntype !~ /ret/ ) {
              print "$amount\t";
            } else {
              print "($amount)\t";
            }
          }
          if ( $adjustmentFlag == 1 ) {
            my ( $baseAmount, $adjustment );
            if ( $adjustmentHashRef->{$orderid} ) {
              $baseAmount = $adjustmentHashRef->{$orderid}->getBaseAmount();
              $adjustment = $adjustmentHashRef->{$orderid}->getAdjustmentTotalAmount();
            }
            print "$baseAmount\t";
            print "$adjustment\t";
          }

          #print "$cardtype\t";
          if ( $display_acct eq "yes" ) {
            print "$acct_code\t";
            print "$acct_code2\t";
            print "$acct_code3\t";
            if ( $smps::feature{'display_ac4'} == 1 ) {
              print "$acct_code4\t";
            }
          }
          if ( $smps::feature{'display_authcode'} == 1 ) {
            print "$auth_code\t";
          }
          ## DCP  20080204
          if ( $display_rept eq "yes" ) {
            print "$reportdata\t";
          }

          if ( ( $display_ext eq "yes" ) || ( $smps::feature{'display_ext'} == 1 ) ) {
            my $sth = $dbhod->prepare(
              qq{
                  select description
                  from orderdetails
                  where orderid=?
                  and username=?
                  }
              )
              or die "Can't do: $DBI::errstr";
            $sth->execute( "$orderid", "$ENV{'REMOTE_USER'}" ) or die "Can't execute: $DBI::errstr";
            my ($description) = $sth->fetchrow;
            $sth->finish();
            print "$description\t";
          }
          print "\n";
          ###  Below IF Loop added DCP 20070824
          if ( $status =~ /success/ ) {
            my ( $dummy, $price ) = split( / /, $amount );
            if ( $txntype !~ /ret/ ) {
              $total = $total + $price;
            } else {
              $total = $total - $price;
            }

            my $transdate = substr( $time, 0, 8 );
            my ($cardtype2);

            if ( $cardtype =~ /^(vs|mc)$/ ) {
              $cardtype2 = 'VisaMastercard';
            } else {
              $cardtype2 = '';
            }
            if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
              if ( $txntype !~ /ret/ ) {
                $cardtotals{"$transdate $cardtype"}            += $native_amt;
                $cardtotals3{"$transdate $cardtype $currency"} += $price;
              } else {
                $cardtotals{"$transdate $cardtype"}            -= $native_amt;
                $cardtotals3{"$transdate $cardtype $currency"} -= $price;
              }
            } elsif ( $smps::processor =~ /^($smps::mcprocessors)$/ ) {
              if ( $txntype !~ /ret/ ) {
                $cardtotals{"$transdate $cardtype"}            += $native_amt;
                $cardtotals3{"$transdate $cardtype $currency"} += $price;
              } else {
                $cardtotals{"$transdate $cardtype"}            -= $native_amt;
                $cardtotals3{"$transdate $cardtype $currency"} -= $price;
              }
            } else {
              if ( $txntype !~ /ret/ ) {
                $cardtotals{"$transdate $cardtype"}   += $price;
                $cardtotals2{"$transdate $cardtype2"} += $price;
              } else {
                $cardtotals{"$transdate $cardtype"}   -= $price;
                $cardtotals2{"$transdate $cardtype2"} -= $price;
              }
            }
          }
        } elsif ( ( $showdetails eq "" ) && ( $accttype eq "checking" ) ) {    # xxxx new 07/09/2009
          if ( $status =~ /success/ ) {
            my ( $dummy, $price ) = split( / /, $amount );
            if ( $txntype !~ /ret/ ) {
              $total = $total + $price;
            } else {
              $total = $total - $price;
            }
          }
        } else {
          if ( $color == 1 ) {
            print "  <tr class=\"listrow_color1\">\n";
          } else {
            print "  <tr class=\"listrow_color0\">\n";
          }
          if ( ( $smps::fuzzyun ne "" ) || ( $smps::linked_accts ne "" ) ) {
            print "<td>$username</td>";
          }
          print "<td>$txntype</td>\n";
          print "<td>$status</td>\n";
          print "<td><nobr>$cardname</nobr></td>\n";

          if ( ( $accttype eq "checking" ) && ( $smps::chkprocessor !~ /^(firstamer|selectcheck|alliance|alliancesp|echo|delaware|paymentdata|telecheck|citynat|securenetach)$/ ) ) {
            print "<td><a href=\"$smps::path_cgi\?accttype=$accttype\&function=batchdetails\&orderid\=$orderid\&merchant=$username\" target=\"newwin\">$orderid</a></td>\n";
            print "<td>$gateid</td>\n";
          } else {
            my $linkURL = "$smps::path_cgi\?accttype=$accttype\&function=details\&orderid\=$orderid\&merchant=$username";
            print "<td><a href=\"$linkURL\" target=\"newwin\">$orderid</a></td>\n";
            if ( $smps::processor =~ /^(universal|buypass|fdms|fdmsomaha|global|paytechtampa|paytechsalem|visanet)$/ ) {
              print "<td>$batchid</td>\n";
            } else {
              print "<td></td>\n";
            }
          }

          print "<td align=center><nobr>$timestr</nobr></td>\n";
          print "<td><nobr>$batchstatus</nobr></td>\n";
          print "<td><nobr>$cardtype</nobr></td>\n";
          if ( ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) && ( $smps::feature{'display_cclast4'} == 1 ) ) {
            my $ccnum = &getcn( "$orderid", "$startdatestr", "$enddatestr" );
            my $last4 = substr( $ccnum, length($ccnum) - 4, 4 );
            print "<td><nobr>$last4</nobr></td>\n";
          } elsif ( ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) && ( $smps::feature{'display_cc'} == 1 ) ) {
            print "<td><nobr>$cardnumber</nobr></td>\n";
          }
          if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
            if ( $txntype !~ /ret/ ) {
              print "<td><nobr>$smps::currency $native_amt</nobr></td>";
              print "<td><nobr>$amount</nobr></td>\n";
            } else {
              print "<td><nobr><font color=\"#ff0000\">($smps::currency $native_amt)</font></nobr></td>";
              print "<td><nobr><font color=\"#ff0000\">($amount)</font><nobr></td>\n";
            }
          } elsif ( $smps::processor =~ /^($smps::mcprocessors)$/ ) {
            if ( $txntype !~ /ret/ ) {
              print "<td><nobr>$amount</nobr></td>\n";
            } else {
              print "<td><nobr><font color=\"#ff0000\">($amount)</font></nobr></td>\n";
            }
          } else {
            if ( $txntype !~ /ret/ ) {
              print "<td><nobr>$amount</nobr></td>\n";
            } else {
              print "<td><nobr><font color=\"#ff0000\">($amount)</font></nobr></td>\n";
            }
          }

          if ( $adjustmentFlag == 1 ) {
            my ( $baseAmount, $adjustment );
            if ( $adjustmentHashRef->{$orderid} ) {
              $baseAmount = $adjustmentHashRef->{$orderid}->getBaseAmount();
              $adjustment = $adjustmentHashRef->{$orderid}->getAdjustmentTotalAmount();
            }
            print "<td><nobr>$baseAmount</nobr></td>\n";
            print "<td><nobr>$adjustment</nobr></td>\n";
          }

          if ( $display_acct eq "yes" ) {
            print "<td><nobr>$acct_code</nobr></td>\n";
            print "<td><nobr>$acct_code2</nobr></td>\n";
            print "<td><nobr>$acct_code3</nobr></td>\n";
            if ( $smps::feature{'display_ac4'} == 1 ) {
              print "<td><nobr>$acct_code4</nobr></td>\n";
            }
            print "<td><nobr>$card_company</nobr></td>\n";
          }
          if ( $smps::feature{'display_authcode'} == 1 ) {
            print "<td><nobr>$auth_code</nobr></td>\n";
          }
          ## DCP  20080204
          if ( $display_rept eq "yes" ) {
            print "<td><nobr>$reportdata</nobr></td>\n";
          }
          print "</tr>\n";

          $color = ( $color + 1 ) % 2;

          if ( $status =~ /success/ ) {
            my ( $dummy, $price ) = split( / /, $amount );
            if ( $txntype !~ /ret/ ) {
              $total = $total + $price;
            } else {
              $total = $total - $price;
            }

            my $transdate = substr( $time, 0, 8 );
            my ($cardtype2);

            if ( $cardtype =~ /^(vs|mc)$/ ) {
              $cardtype2 = 'VisaMastercard';
            } else {
              $cardtype2 = '';
            }
            if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
              if ( $txntype !~ /ret/ ) {
                $cardtotals{"$transdate $cardtype"}            += $native_amt;
                $cardtotals3{"$transdate $cardtype $currency"} += $price;
              } else {
                $cardtotals{"$transdate $cardtype"}            -= $native_amt;
                $cardtotals3{"$transdate $cardtype $currency"} -= $price;
              }
            } elsif ( $smps::processor =~ /^($smps::mcprocessors)$/ ) {
              if ( $txntype !~ /ret/ ) {
                $cardtotals{"$transdate $cardtype"}            += $native_amt;
                $cardtotals3{"$transdate $cardtype $currency"} += $price;
              } else {
                $cardtotals{"$transdate $cardtype"}            -= $native_amt;
                $cardtotals3{"$transdate $cardtype $currency"} -= $price;
              }
            } else {
              if ( $txntype !~ /ret/ ) {
                $cardtotals{"$transdate $cardtype"}   += $price;
                $cardtotals2{"$transdate $cardtype2"} += $price;
              } else {
                $cardtotals{"$transdate $cardtype"}   -= $price;
                $cardtotals2{"$transdate $cardtype2"} -= $price;
              }
            }
          }
        }
      }
    }
  }
  if ( ( $display_ext eq "yes" ) || ( $smps::feature{'display_ext'} == 1 ) ) {
    $dbhod->disconnect;
  }

  if ( ( $smps::format eq "" ) || ( $smps::format eq "table" ) ) {
    print "</table>\n";
    print "<br>\n";
  }

  if ( ( $showdetails eq "" )
    && ( ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) || ( $smps::chkprocessor =~ /^(alliance|alliancesp|echo|delaware|paymentdata|telecheck|telecheckftf|citynat|securenetach|mtbankach)$/ ) ) ) {
    if ( ( $smps::format eq "" ) || ( $smps::format eq "table" ) ) {
      print "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\" target=\"newwin\">\n";
      print "<input type=\"hidden\" name=\"accttype\" value=\"$accttype\">\n";
      print "<input type=\"hidden\" name=\"function\" value=\"batchquery\">\n";
      print "<input type=\"hidden\" name=\"showdetails\" value=\"yes\">\n";
      print "<input type=\"hidden\" name=\"username\" value=\"$smps::username\">\n";
      print "<input type=\"hidden\" name=\"startyear\" value=\"$startyear\">\n";
      print "<input type=\"hidden\" name=\"startmonth\" value=\"$startmonth\">\n";
      print "<input type=\"hidden\" name=\"startday\" value=\"$startday\">\n";
      print "<input type=\"hidden\" name=\"endyear\" value=\"$endyear\">\n";
      print "<input type=\"hidden\" name=\"endmonth\" value=\"$endmonth\">\n";
      print "<input type=\"hidden\" name=\"endday\" value=\"$endday\">\n";
      print "<input type=\"hidden\" name=\"merchant\" value=\"$smps::merchant\">\n";
      print "<input type=\"hidden\" name=\"settletimezone\" value=\"$smps::settletimezone\">\n";

      if ( $smps::processor =~ /^($smps::mcprocessors)$/ ) {
        print "<table border=1 cellspacing=0 cellpadding=2>\n";
        if ( $accttype eq "checking" ) {
          print "<tr><th colspan=\"2\">Batch ID</th><th>Date</th><th>Status</th>\n";
        } else {
          print "<tr><th colspan=\"2\">Batch ID</th><th>Date</th><th>Card Type</th>\n";
        }
        foreach my $curr ( sort keys %currency_types ) {
          print "<th>Count $curr</th><th>Amount $curr</th>";
        }
        print "</tr>\n";
        my $i = 0;
        my (%selected);
        foreach my $key ( sort keys %cntarray ) {
          ( $username, $batchid, $cardtype ) = split( / /, $key );
          if ( $i == 0 ) {
            $i++;
          }
          if ( ( $batchid ne $batchidold ) || ( $username ne $usernameold ) ) {
            print "<tr>\n";
            print "<td><input type=\"radio\" name=\"batchid\" value=\"$username\|$batchid\" $selected{$batchid}></td>\n";
            print "<td align=\"left\"><b>$batchid</b></td>\n";
            print "<td>$datearray{$batchid}</td>\n";
          } else {
            print "<tr><td colspan=\"3\"></td>\n";
          }
          if ( ( $accttype eq "checking" ) && ( $smps::chkprocessor =~ /^(alliance|alliancesp|echo|delaware|paymentdata|telecheck|telecheckftf|citynat|securenetach|mtbankach)$/ ) ) {
            print "<td>$cardtype</td>\n";
          } else {
            print "<td>$smps::cardarray{$cardtype}</td>\n";
          }
          my $idx = "";
          foreach my $curr ( sort keys %currency_types ) {
            $idx = "$batchid $cardtype $curr";
            print "<td align=\"right\">$cntarray2{$idx}</td>\n";
            printf( "<td align=\"right\">%.2f</td>\n", $amtarray2{$idx} );
          }
          print "</tr>\n";
          $batchidold  = $batchid;
          $usernameold = $username;
        }
      } else {
        print "<div id=\"cardTypesCheckboxDiv\"></div>\n";
        print "<table border=1 cellspacing=0 cellpadding=2>\n";
        print "<tr>";
        if ( ( $smps::fuzzyun ne "" ) || ( $smps::linked_accts ne "" ) ) {
          print "<th>Username</th>";
        }
        if ( $accttype eq "checking" ) {
          print "<th colspan=\"2\">Batch ID</th><th>Date</th><th>Status</th><th>Count</th><th>Amount $smps::currency</th>\n";
        } else {
          print "<th colspan=\"2\">Batch ID</th><th>Date</th><th>Card Type</th><th>Count</th><th>Amount $smps::currency</th>\n";
        }
        print "</tr>";
        my $i = 0;
        my (%selected);
        my $color = 0;
        foreach my $key ( sort keys %cntarray ) {
          ( $username, $batchid, $cardtype ) = split( / /, $key );

          my $batchidClass = $batchid;
          $batchidClass =~ (s/\D//g);

          my $cardtypeClass = $smps::cardarray{$cardtype};
          $cardtypeClass =~ (s/\s//g);

          if ( $i == 0 ) {
            $i++;
          }
          if ( ( $batchid ne $batchidold ) || ( $username ne $usernameold ) ) {
            $color = ( $color + 1 ) % 2;

            if ( $color == 1 ) {
              print "  <tr class=\"listrow_color1\">\n";
            } else {
              print "  <tr class=\"listrow_color0\">\n";
            }
            if ( ( $smps::fuzzyun ne "" ) || ( $smps::linked_accts ne "" ) ) {
              print "<td>$username</td>\n";
            }
            print "<td><input type=\"radio\" name=\"batchid\" value=\"$username\|$batchid\" $selected{$batchid}></td>\n";
            print "<td style=\"display:none\"><input type=\"hidden\" class=\"batchidHiddenField\" value=\"$batchid\"></td>\n";
            print "<td align=\"left\"><b>$batchid</b></td>\n";
            print "<td>$datearray{$batchid}</td>\n";
            print "<td colspan=\"3\"></td></tr>\n";
            if ( $color == 1 ) {
              print "  <tr class=\"listrow_color1 $batchidClass $cardtypeClass\">\n";
            } else {
              print "  <tr class=\"listrow_color0 $batchidClass $cardtypeClass\">\n";
            }
            if ( ( $smps::fuzzyun ne "" ) || ( $smps::linked_accts ne "" ) ) {
              print "<td colspan=\"4\"></td>\n";
            } else {
              print "<td colspan=\"3\"></td>\n";
            }
          } else {
            if ( $color == 1 ) {
              print "  </tr><tr class=\"listrow_color1 $batchidClass $cardtypeClass\">\n";
            } else {
              print "  </tr><tr class=\"listrow_color0 $batchidClass $cardtypeClass\">\n";
            }
            if ( ( $smps::fuzzyun ne "" ) || ( $smps::linked_accts ne "" ) ) {
              print "<td colspan=\"4\"></td>\n";
            } else {
              print "<td colspan=\"3\"></td>\n";
            }
          }
          if ( ( $accttype eq "checking" ) && ( $smps::chkprocessor =~ /^(alliance|alliancesp|echo|delaware|paymentdata|telecheck|telecheckftf|citynat|securenetach|mtbankach)$/ ) ) {
            print "<td>$cardtype</td>\n";
          } else {
            print "<td class=\"cardTypes\">$smps::cardarray{$cardtype}</td>\n";
          }
          print "<td align=\"right\" class=\"cardCounts\">$cntarray{$key}</td>\n";
          printf( "<td align=\"right\" class=\"cardAmounts\">%.2f</td>\n", $amtarray{$key} );
          $batchidold  = $batchid;
          $usernameold = $username;
        }
      }
      print "</table>\n";

      print "<p><table border=\"0\">\n";
      print "<tr>\n";
      print "<td align=\"right\"><b>Acct. Code(s):</b> </td>\n";
      my ($checked);
      if ( ( $smps::reseller =~ /^(cynergy|affinisc|lawpay)/ ) && ( $smps::username =~ /^(cyd|ap|ams|lp|law)/ ) ) {
        $checked = "checked";
      }
      print "<td><input type=\"checkbox\" name=\"display_acct\" value=\"yes\" $checked> Check to Display Acct. Code Info.</td>\n";
      print "</tr>\n";
      if ( ( $smps::processor eq "global" ) && ( $smps::username =~ /^om/ ) ) {
        print "<tr>\n";
        print "<td align=\"right\"><b>Report Data:</b> </td>\n";
        print "<td><input type=\"checkbox\" name=\"display_rept\" value=\"yes\"> Check to Report Data</td>\n";
        print "</tr>\n";
      }
      print "<tr>\n";
      print "<td align=\"right\"><b>Error Msg:</b> </td>\n";
      print "<td><input type=\"checkbox\" name=\"display_errmsg\" value=\"yes\"> Check to include Error Message in Text/Download Format</td>\n";
      print "</tr>\n";
      print "<tr>\n";
      print "<td align=\"right\"><b>Extended:</b> </td>\n";
      print "<td><input type=\"checkbox\" name=\"display_ext\" value=\"yes\"> Check to include Extended Description in Text/Download Format</td>\n";
      print "</tr>\n";
      print "<tr>\n";
      print "<td align=\"right\"><b>Format:</b> </td>\n";
      print
        "<td><input type=\"radio\" name=\"format\" value=\"table\" checked> Table <input type=\"radio\" name=\"format\" value=\"text\"> Text <input type=\"radio\" name=\"format\" value=\"download\"> Download</td>\n";
      print "</tr>\n";

      print "</table>\n";
      print "<p><input type=\"submit\" value=\"Review Batch Details\">\n";
      print "</form>\n";

      print "<br>\n";
      print "<h3>Summary:</h3>\n";

      print "<table border=1 cellspacing=0 cellpadding=2>\n";
      print "<tr>";
      if ( $accttype eq "checking" ) {
        print "<th>Date</th><th>Status</th>";
      } else {
        print "<th>Date</th><th>Card Type</th>";
      }

      if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
        print "<th>To Bank<br>Count $smps::currency</th><th>To Bank<br>Amount $smps::currency</th>\n";
        foreach my $curr ( sort keys %currency_types ) {
          print "<th>Charged<br>Count $curr</th><th>Charged<br>Amount $curr</th>";
        }
      } elsif ( $smps::processor =~ /^($smps::mcprocessors)$/ ) {
        foreach my $curr ( sort keys %currency_types ) {
          print "<th>Charged<br>Count $curr</th><th>Charged<br>Amount $curr</th>";
        }
      } else {
        print "<th>Count $smps::currency</th><th>Amount $smps::currency</th>\n";
      }

      # Add adjustment header
      if ( $adjustmentFlag == 1 ) {
        if ( $surchargeFlag == 1 ) {
          print "<th>Base Amount</th>\n";    # only display this for surcharge for now
          print "<th>Credit Card Fee Amount</th>\n";
        }
      }

      print "</tr>\n";

      my $color = 1;
      foreach my $key ( sort keys %cntarray1 ) {
        my ( $date, $cardtype ) = split( / /, $key );
        $cardtypecnttotal{$cardtype} += $cntarray1{$key};
        $cardtypeamttotal{$cardtype} += $amtarray1{$key};

        my $batchidClass = $date;
        $batchidClass =~ (s/\D//g);
        $batchidClass = "$batchidClass" . "summary";

        my $cardtypeClass = $smps::cardarray{$cardtype};
        $cardtypeClass =~ (s/\s//g);

        if ( ( $cardtype ne "vsmc" ) && ( $cardtype ne "zcombined" ) ) {
          $cnttotal{$date} += $cntarray1{$key};
          $amttotal{$date} += $amtarray1{$key};
        }
        if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
          foreach my $curr ( sort keys %currency_types ) {
            $cardtypecnttotal3{"$cardtype $curr"} += $cntarray3{"$key $curr"};
            $cardtypeamttotal3{"$cardtype $curr"} += $amtarray3{"$key $curr"};
            if ( $cardtype ne "vsmc" ) {
              $cnttotal3{"$date $curr"} += $cntarray3{"$key $curr"};
              $amttotal3{"$date $curr"} += $amtarray3{"$key $curr"};
            }
          }
        } elsif ( $smps::processor =~ /^($smps::mcprocessors)$/ ) {
          foreach my $curr ( sort keys %currency_types ) {
            $cardtypecnttotal3{"$cardtype $curr"} += $cntarray3{"$key $curr"};
            $cardtypeamttotal3{"$cardtype $curr"} += $amtarray3{"$key $curr"};
            if ( $cardtype ne "vsmc" ) {
              $cnttotal3{"$date $curr"} += $cntarray3{"$key $curr"};
              $amttotal3{"$date $curr"} += $amtarray3{"$key $curr"};
            }
          }
        }
        if ( $date ne $dateold ) {
          if ( $dateold ne "" ) {
            if ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) {
              if ( $color == 1 ) {
                print "  <tr class=\"listrow_color1 $batchidClass $cardtypeClass\">\n";
              } else {
                print "  <tr class=\"listrow_color0 $batchidClass $cardtypeClass\">\n";
              }
              print "<td> &nbsp; </td><td><b>DAILY TOTAL</b></td>";
              if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
                print "<td align=\"right\">$cnttotal{$dateold}</td><td align=\"right\">";
                printf( "%.2f</td>\n", $amttotal{$dateold} );
                foreach my $curr ( sort keys %currency_types ) {
                  print "<td align=\"right\">$cnttotal3{\"$dateold $curr\"}</td>\n";
                  printf( "<td align=right>%.2f</td>", $amttotal3{"$dateold $curr"} );
                }
              } elsif ( $smps::processor =~ /^($smps::mcprocessors)$/ ) {
                foreach my $curr ( sort keys %currency_types ) {
                  print "<td align=\"right\">$cnttotal3{\"$dateold $curr\"}</td>\n";
                  printf( "<td align=right>%.2f</td>", $amttotal3{"$dateold $curr"} );
                }
              } else {
                print "<td align=\"right\"><b>$cnttotal{$dateold}</b></td>";
                printf( "<td align=\"right\"><b>%.2f</b></td>\n", $amttotal{$dateold} );
              }
              print "</tr>\n";
            }
            $color = ( $color + 1 ) % 2;
          }
          my $datestr = substr( $date, 4, 2 ) . "/" . substr( $date, 6, 2 ) . "/" . substr( $date, 0, 4 );
          if ( $color == 1 ) {
            print "  <tr class=\"listrow_color1 $batchidClass $cardtypeClass\">\n";
          } else {
            print "  <tr class=\"listrow_color0 $batchidClass $cardtypeClass\">\n";
          }
          print "<td><b>$datestr</b></td>\n";
          print "<td style=\"display:none\"><input type=\"hidden\" class=\"batchidHiddenField\" value=\"$batchidClass\"></td>\n";
        } else {
          if ( $color == 1 ) {
            print "  <tr class=\"listrow_color1 $batchidClass $cardtypeClass\">\n";
          } else {
            print "  <tr class=\"listrow_color0 $batchidClass $cardtypeClass\">\n";
          }
          print "<td> &nbsp; </td>\n";
        }
        if ( $accttype eq "checking" ) {
          print "<td>$cardtype</td>\n";
        } else {
          print "<td class=\"cardTypes\">$smps::cardarray{$cardtype}</td>\n";
        }

        ## DCP Loop Through Currency Types of MC and Add data here.
        if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
          print "<td align=\"right\">$cntarray1{$key}</td>\n";
          printf( "<td align=\"right\">%.2f</td>\n", $amtarray1{$key} );
          foreach my $curr ( sort keys %currency_types ) {
            print "<td align=\"right\">$cntarray3{\"$key $curr\"}</td>\n";
            printf( "<td align=right>%.2f</td>", $amtarray3{"$key $curr"} );
          }
        } elsif ( $smps::processor =~ /^($smps::mcprocessors)$/ ) {
          foreach my $curr ( sort keys %currency_types ) {
            print "<td align=\"right\">$cntarray3{\"$key $curr\"}</td>\n";
            printf( "<td align=right>%.2f</td>", $amtarray3{"$key $curr"} );
          }
        } else {
          print "<td align=\"right\" class=\"cardCounts\">$cntarray1{$key}</td>\n";
          printf( "<td align=\"right\" class=\"cardAmounts\">%.2f</td>\n", $amtarray1{$key} );
        }

        # Display base amount and adjustment totals
        if ( $adjustmentFlag == 1 ) {
          if ( $surchargeFlag == 1 ) {
            printf( "<td align=\"right\" class=\"adjustmentBaseAmounts\">%.2f</td>\n", $baseAmountArray{$key} );    # only display this for surcharge for now
            printf( "<td align=\"right\" class=\"adjustmentFeeAmounts\">%.2f</td>\n",  $adjustmentArray{$key} );
          }
        }

        $dateold = $date;
        print "</tr>\n";
      }
      if ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) {
        if ( $color == 1 ) {
          print "  <tr class=\"listrow_color1\">\n";
        } else {
          print "  <tr class=\"listrow_color0\">\n";
        }
        print "<td> &nbsp; </td><td><b>DAILY TOTAL</b></td>";
        if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
          print "<td align=\"right\">$cnttotal{$dateold}</td><td align=\"right\">";
          printf( "%.2f</td>\n", $amttotal{$dateold} );
          foreach my $curr ( sort keys %currency_types ) {
            print "<td align=\"right\">$cnttotal3{\"$dateold $curr\"}</td>\n";
            printf( "<td align=right>%.2f</td>", $amttotal3{"$dateold $curr"} );
          }
        } elsif ( $smps::processor =~ /^($smps::mcprocessors)$/ ) {
          foreach my $curr ( sort keys %currency_types ) {
            print "<td align=\"right\">$cnttotal3{\"$dateold $curr\"}</td>\n";
            printf( "<td align=right>%.2f</td>", $amttotal3{"$dateold $curr"} );
          }
        } else {
          print "<td align=\"right\"><b>$cnttotal{$dateold}</b></td>";
          printf( "<td align=\"right\"><b>%.2f</b></td>\n", $amttotal{$dateold} );
        }
        print "</tr>\n";
        $color = ( $color + 1 ) % 2;
      }

      my @cols = keys %cardtypecnttotal;
      my $cols = @cols;
      my ($cnt);
      foreach my $key ( sort keys %cardtypecnttotal ) {
        $cnt++;

        my $cardtypeClass = $smps::cardarray{$key};
        $cardtypeClass =~ (s/\s//g);

        my $batchidClass = "summaryTotals";

        if ( $cnt == 1 ) {
          print "<tr class=\"$batchidClass $cardtypeClass\"><th rowspan=\"$cols\">Totals</th>\n";
          print "<td style=\"display:none\"><input type=\"hidden\" class=\"batchidHiddenField\" value=\"$batchidClass\"></td>\n";
          if ( $accttype eq "checking" ) {
            print "<td>$key</td>\n";
          } else {
            print "<td class=\"cardTypes\">$smps::cardarray{$key}</td>\n";
          }
          if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
            print "<td align=\"right\">$cardtypecnttotal{$key}</td>\n";
            printf( "<td align=\"right\">%.2f</td>\n", $cardtypeamttotal{$key} );
            foreach my $curr ( sort keys %currency_types ) {
              print '<td align="right">' . $cardtypecnttotal3{"$key $curr"} . "</td>\n";
              printf( "<td align=\"right\">%.2f</td>\n", $cardtypeamttotal3{"$key $curr"} );
            }
          } elsif ( $smps::processor =~ /^($smps::mcprocessors)$/ ) {
            foreach my $curr ( sort keys %currency_types ) {
              print '<td align="right">' . $cardtypecnttotal3{"$key $curr"} . "</td>\n";
              printf( "<td align=\"right\">%.2f</td>\n", $cardtypeamttotal3{"$key $curr"} );
            }
          } else {
            print "<td align=\"right\" class=\"cardCounts\">$cardtypecnttotal{$key}</td>\n";
            printf( "<td align=\"right\" class=\"cardAmounts\">%.2f</td>\n", $cardtypeamttotal{$key} );
          }
          print "</tr>\n";
        } else {
          print "<tr class=\"$batchidClass $cardtypeClass\">\n";
          if ( $accttype eq "checking" ) {
            print "<td>$key</td>\n";
          } else {
            print "<td class=\"cardTypes\">$smps::cardarray{$key}</td>\n";
          }

          if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
            print "<td align=\"right\">$cardtypecnttotal{$key}</td>\n";
            printf( "<td align=\"right\">%.2f</td>\n", $cardtypeamttotal{$key} );
            foreach my $curr ( sort keys %currency_types ) {
              print '<td align="right">' . $cardtypecnttotal3{"$key $curr"} . "</td>\n";
              printf( "<td align=\"right\">%.2f</td>\n", $cardtypeamttotal3{"$key $curr"} );
            }
          } elsif ( $smps::processor =~ /^($smps::mcprocessors)$/ ) {
            foreach my $curr ( sort keys %currency_types ) {
              print '<td align="right">' . $cardtypecnttotal3{"$key $curr"} . "</td>\n";
              printf( "<td align=\"right\">%.2f</td>\n", $cardtypeamttotal3{"$key $curr"} );
            }
          } else {
            print "<td align=\"right\" class=\"cardCounts\">$cardtypecnttotal{$key}</td>\n";
            printf( "<td align=\"right\" class=\"cardAmounts\">%.2f</td>\n", $cardtypeamttotal{$key} );
          }
          print "</tr>\n";
        }
      }

      if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
        printf( "<tr><th  colspan=2 align=\"left\">Total Successful Batches</th><th colspan=2 align=\"right\">$smps::currency %.2f</th>", $total_native{$smps::currency} );
        foreach my $curr ( sort keys %currency_types ) {
          printf( "<th colspan=2 align=\"right\"> %.2f</th>", $total{$curr} );
        }
        print "</tr>\n";
        print "</table>\n";
      } elsif ( $smps::processor =~ /^($smps::mcprocessors)$/ ) {
        print "<tr><th  colspan=2 align=\"left\">Total Successful Batches</th>";
        foreach my $curr ( sort keys %currency_types ) {
          printf( "<th colspan=2 align=\"right\"> %.2f</th>", $total{$curr} );
        }
        print "</tr>\n";
        print "</table>\n";
      } else {
        printf( "<br><b>Total Successful Batches: \$%.2f</b><br>\n", $total );
        print "</table>\n";
      }
    } else {
      print "batchid\tdate\ttype\tcount\tamount\n";
      foreach my $key ( sort keys %cntarray ) {
        my ( $username, $batchid, $cardtype ) = split( / /, $key );
        print "$batchid\t";
        print "$datearray{$batchid}\t";
        print "$smps::cardarray{$cardtype}\t";
        print "$cntarray{$key}\t";
        printf( "%.2f", $amtarray{$key} );
        print "\n";
      }
    }
  } elsif ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) {
    if ( $smps::format =~ /^(text|download)$/ ) {
      print "\n\n";
      print "Summary\n";
      foreach my $key ( sort keys %cardtotals ) {
        my ( $transdate, $cardtype ) = split( / /, $key );
        my $transdatestr = substr( $transdate, 4, 2 ) . "/" . substr( $transdate, 6, 2 ) . "/" . substr( $transdate, 0, 4 ) . " ";
        if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
          printf( "$transdatestr\t$smps::cardarray{$cardtype}\t$smps::currency %.2f\t\n", $cardtotals{$key} );
          foreach my $curr ( sort keys %currency_types ) {
            printf( "\t$curr %.2f", $cardtotals3{"$key $curr"} );
          }
        } elsif ( $smps::processor =~ /^($smps::mcprocessors)$/ ) {
          printf( "$transdatestr\t$smps::cardarray{$cardtype}\t$smps::currency %.2f\t\n", $cardtotals{$key} );
          foreach my $curr ( sort keys %currency_types ) {
            printf( "\t$curr %.2f", $cardtotals3{"$key $curr"} );
          }
        } else {
          printf( "$transdatestr\t$smps::cardarray{$cardtype}\t%.2f\n", $cardtotals{$key} );
        }
      }
      print "\n";
      if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
        printf( "\nTotal Successful Batches: $smps::currency %.2f</b>\n", $total{$smps::currency} );
        foreach my $curr ( sort keys %currency_types ) {
          printf( "\nTotal Successful Batches: $curr %.2f\n", $total{$curr} );
        }
      } elsif ( $smps::processor =~ /^($smps::mcprocessors)$/ ) {
        printf( "\nTotal Successful Batches: $smps::currency %.2f</b>\n", $total{$smps::currency} );
        foreach my $curr ( sort keys %currency_types ) {
          printf( "\nTotal Successful Batches: $curr %.2f\n", $total{$curr} );
        }
      } else {
        printf( "\nTotal Successful Batches: \$%.2f\n", $total );
      }
    } else {
      print "<br>\n";
      print "<h3>Summary :</h3>\n";
      print "<table border=1 cellspacing=0 cellpadding=2>\n";
      foreach my $key ( sort keys %cardtotals ) {
        my ( $transdate, $cardtype ) = split( / /, $key );
        my $transdatestr = substr( $transdate, 4, 2 ) . "/" . substr( $transdate, 6, 2 ) . "/" . substr( $transdate, 0, 4 ) . " ";
        if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
          print "<tr><th align=\"left\">$transdatestr</th><td>$smps::cardarray{$cardtype}</td>";
          printf( "<td align=\"right\">$smps::currency %.2f</td>", $amtarray1{$key} );
          foreach my $curr ( sort keys %currency_types ) {
            printf( "<td>$curr %.2f</td>\n", $cardtotals3{"$key $curr"} );
          }
        } elsif ( $smps::processor =~ /^($smps::mcprocessors)$/ ) {
          print "<tr><th align=\"left\">$transdatestr</th><td>$smps::cardarray{$cardtype}</td>";
          foreach my $curr ( sort keys %currency_types ) {
            printf( "<td>$curr %.2f</td>\n", $cardtotals3{"$key $curr"} );
          }
        } else {
          printf( "<tr><th align=\"left\">$transdatestr</th><td>$smps::cardarray{$cardtype}</td><td>%.2f</td>\n", $cardtotals{$key} );
        }
      }
      if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
        printf( "<tr><th aligh=\"left\" colspan=2>Total Successful Batches</th><th align=\"right\">$smps::currency %.2f</th>", $total_native{$smps::currency} );
        foreach my $curr ( sort keys %currency_types ) {
          printf( "<th align=\"right\">$curr %.2f</th>", $total{$curr} );
        }
        print "</tr>\n";
        print "</table>\n";
      } elsif ( $smps::processor =~ /^($smps::mcprocessors)$/ ) {
        print "<tr><th aligh=\"left\" colspan=2>Total Successful Batches</th>";
        foreach my $curr ( sort keys %currency_types ) {
          printf( "<th align=\"right\">$curr %.2f</th>", $total{$curr} );
        }
        print "</tr>\n";
        print "</table>\n";
      } else {
        print "</table>\n";
        printf( "<br><b>Total Successful Batches: \$%.2f</b><br>\n", $total );
      }
    }
  }
  if ( ( $accttype eq "checking" ) && ( $smps::chkprocessor =~ /^(alliance|alliancesp)$/ ) ) {
    my $dbh = &miscutils::dbhconnect("pnpmisc");
    my ( @cb_dates, @dates, %chargeback, %fees, $trans_date, $debcrefees, $discount, $returnfees, $chargebackfees, $nocfees, $feetst, $chargeback );
    my $startdate = substr( $starttime, 0, 8 );
    my $enddate   = substr( $endtime,   0, 8 );

    my $sth = $dbh->prepare(
      qq{
        select trans_date,debcredfees,discount,returnfees,chargebackfees,nocfees,chargebacks
        from alliancefees
        where username=?
        and trans_date>=?
        and trans_date<?
        order by trans_date
        }
      )
      or die "Can't do: $DBI::errstr";
    $sth->execute( "$ENV{'REMOTE_USER'}", "$startdate", "$enddate" ) or die "Can't execute: $DBI::errstr";
    my $rv = $sth->bind_columns( undef, \( $trans_date, $debcrefees, $discount, $returnfees, $chargebackfees, $nocfees, $chargeback ) );
    while ( $sth->fetch ) {
      $debcrefees     = sprintf( "%.2f", $debcrefees );
      $discount       = sprintf( "%.2f", $discount );
      $returnfees     = sprintf( "%.2f", $returnfees );
      $chargebackfees = sprintf( "%.2f", $chargebackfees );
      $nocfees        = sprintf( "%.2f", $nocfees );
      $chargeback     = sprintf( "%.2f", $chargeback );

      if ( $chargeback != 0 ) {
        push( @cb_dates, $trans_date );
        $chargeback{"$trans_date"} = "$chargeback";
      }
      $feetst = $trans_date + $debcrefees + $discount + $returnfees + $chargebackfees + $nocfees;
      if ( $feetst > 0.01 ) {
        push( @dates, $trans_date );
        $fees{"$trans_date"} = "$debcrefees,$discount,$returnfees,$chargebackfees,$nocfees";
      }
    }
    $sth->finish;
    $dbh->disconnect;

    print "<h3>Alliance Chargebacks:</h3>\n";
    print "<table border=1 cellspacing=0 cellpadding=2>\n";
    print "<tr><th>Date</th><th>Chargeback</th></th></tr>\n";
    foreach my $trans_date (@cb_dates) {
      $chargeback = $chargeback{"$trans_date"};
      print "<tr><td>$trans_date</td><td>$chargeback</td></tr>\n";
    }
    print "</table><p>\n";

    print "<h3>Alliance ACH Fees:</h3>\n";
    print "<table border=1 cellspacing=0 cellpadding=2>\n";
    print "<tr><th>Date</th><th>Transaction</th><th>Discount</th><th>Return</th><th>Chargeback</th><th>NOC</th></tr>\n";
    foreach my $trans_date (@dates) {
      ( $debcrefees, $discount, $returnfees, $chargebackfees, $nocfees ) = split( '\,', $fees{"$trans_date"} );
      print "<tr><td>$trans_date</td><td>$debcrefees</td><td>$discount</td><td>$returnfees</td><td>$chargebackfees</td><td>$nocfees</td></tr>\n";
    }
    print "</table><p>\n";
  } elsif ( ( $accttype eq "checking" ) && ( $smps::chkprocessor =~ /^(paymentdata|delaware|citynat)$/ ) ) {

    my $transdatestr    = "";
    my $transdatestrold = "";
    my $chtotal         = 0;
    my $chcount         = 0;
    my $chgrandtotal    = 0;
    my $chgrandcount    = 0;
    if ( $smps::format =~ /^(text|download)$/ ) {
      print "Chargebacks:\n";
      print "Date\tOrderID\tBatch ID\tCard Name\t";
      if ( $display_acct eq "yes" ) {
        print "Acct. Code\tAcct. Code 2\tAcct. Code 3\t";
      }
      print "Amount\n";
      foreach my $key ( sort keys %badcardarray ) {
        my ( $date, $orderid, $batchid, $currency, $price, $card_name ) = split( / /, $key, 6 );
        $transdatestr = substr( $date, 4, 2 ) . "/" . substr( $date, 6, 2 ) . "/" . substr( $date, 0, 4 ) . " ";
        if ( $transdatestr ne $transdatestrold ) {
          if ( $chcount > 0 ) {
            printf( "\nTotal\t$chcount\t$currency %.2f\n", $chtotal );
            $chtotal = 0;
            $chcount = 0;
          }
          print "$transdatestr\t";
        } else {
          print "\n";
          print "$transdatestr\t";
        }
        print "$orderid\t$batchid\t$card_name\t";
        if ( $display_acct eq "yes" ) {
          print "$acarray{$orderid}\t$ac2array{$orderid}\t$ac3array{$orderid}\t";
        }

        print "$currency $price";
        $chcount++;
        $chgrandcount++;
        $chtotal         = $chtotal + $price;
        $chgrandtotal    = $chgrandtotal + $price;
        $transdatestrold = $transdatestr;
      }
      if ( $chcount > 0 ) {
        printf( "\nTotal\t$chcount\t$currency %.2f\n", $chtotal );
      }
      if ( $chgrandcount > 0 ) {
        printf( "Grand Total\t$chgrandcount\t$currency %.2f\n", $chgrandtotal );
      }
    } else {
      print "<br>\n";
      print "<h3>Chargebacks:</h3>\n";
      print "<table border=1 cellspacing=0 cellpadding=2>\n";
      print "<tr><th align=\"left\">Date</th><th align=\"left\">OrderID</th><th align=\"left\">Batch ID</th><th align=\"left\">Card Name</th>";
      if ( $display_acct eq "yes" ) {
        print "<th align=\"left\">Acct. Code</th><th align=\"left\">Acct. Code 2</th><th align=\"left\">Acct. Code 3</th>";
      }
      print "<th align=\"left\">Amount</th>\n";
      foreach my $key ( sort keys %badcardarray ) {
        my ( $date, $orderid, $batchid, $currency, $price, $card_name ) = split( / /, $key, 6 );
        $transdatestr = substr( $date, 4, 2 ) . "/" . substr( $date, 6, 2 ) . "/" . substr( $date, 0, 4 ) . " ";
        print "<tr>\n";
        if ( $transdatestr ne $transdatestrold ) {
          if ( $chcount > 0 ) {
            printf( "<th align=\"left\">Total</th><td></td><td></td><td>$chcount</td><td align=\"right\">$currency %.2f</td>\n<tr>", $chtotal );
            $chtotal = 0;
            $chcount = 0;
          }
          print "<th align=\"left\">$transdatestr</th>\n";
        } else {
          print "<th align=\"left\"></th>\n";
        }
        print "<td>$orderid</td>\n";
        print "<td>$batchid</td>\n";
        print "<td>$card_name</td>\n";
        if ( $display_acct eq "yes" ) {
          print "<td>$acarray{$orderid}</td>\n";
          print "<td>$ac2array{$orderid}</td>\n";
          print "<td>$ac3array{$orderid}</td>\n";
        }

        print "<td align=\"right\">$currency $price</td>\n";
        $chcount++;
        $chgrandcount++;
        $chtotal         = $chtotal + $price;
        $chgrandtotal    = $chgrandtotal + $price;
        $transdatestrold = $transdatestr;
      }
      if ( $chcount > 0 ) {
        printf( "<tr><th align=\"left\">Total</th><td></td><td></td><td>$chcount</td><td align=\"right\">$currency %.2f</td>\n", $chtotal );
      }
      if ( $chgrandcount > 0 ) {
        printf( "<tr><th align=\"left\">Grand Total</th><td></td><td></td><td>$chgrandcount</td><td align=\"right\">$currency %.2f</td>\n", $chgrandtotal );
      }
      print "</table><br>\n";
    }
  }

  my $datetime = gmtime(time);
  $smps::endtime = time();
  $elapse        = $smps::endtime - $smps::strttime;

  if ( $elapse > 30 ) {
    &logToDataLog(
      { 'originalLogFile' => '/home/pay1/database/debug/smps_longqueries.txt',
        'function'        => $smps::function,
        'elapsedTime'     => $elapse,
        'username'        => $smps::username,
        'login'           => $ENV{'LOGIN'},
        'remoteUser'      => $ENV{'REMOTE_USER'},
        'logReason'       => 'smps query exceeds "long" threshold'
      }
    );
  }
}

sub batchdetails {

  my $mark_flag     = 0;
  my $void_flag     = 0;
  my $mark_ret_flag = 0;
  my $settled_flag  = 0;
  my $auth_flag     = 0;

  my $orderid  = $smps::query->param('orderid');
  my $accttype = $smps::query->param('accttype');

  my %result = &miscutils::sendmserver( "$smps::username", "batchdetails", 'accttype', "$accttype", 'order-id', "$orderid" );

  print "<h3>Batch ID: $orderid</h3>\n";
  print "<b>Status:</b> $result{'batch-status'}<br><br>\n";
  print "<table border=1 cellspacing=0 cellpadding=2>\n";
  print "<tr>\n";
  print "<th align=left valign=\"bottom\">OrderID</th>";
  print "<th align=left valign=\"bottom\">Name</th>";
  print "<th align=left valign=\"bottom\">Type</th>";
  print "<th align=left valign=\"bottom\">Transaction Amount</th>";
  print "<th align=left valign=\"bottom\">Settled Amount</th>";
  print "<th align=left valign=\"bottom\">Status</th>";
  print "<th align=left valign=\"bottom\">Description</th>";

  my $color = 1;
  my $i     = 0;
  my ( $settletotal, $total );
  my @values = values %result;
  foreach my $var ( sort @values ) {

    my (%res2);
    my @nameval = split( /&/, $var );
    foreach my $temp (@nameval) {
      my ( $name, $value ) = split( /=/, $temp );
      $res2{$name} = $value;
    }

    if ( $res2{'time'} ne "" ) {
      my $time = $res2{"time"};

      my $timestr = substr( $time, 4, 2 ) . "/" . substr( $time, 6, 2 ) . "/" . substr( $time, 0, 4 ) . " ";
      $timestr = $timestr . substr( $time, 8, 2 ) . ":" . substr( $time, 10, 2 ) . ":" . substr( $time, 12, 2 );

      my $operation = $res2{"operation"};
      my $txntype   = $res2{"txn-type"};
      my $txnstatus = $res2{"txn-status"};
      my $orderid   = $res2{"order-id"};
      my $amount    = $res2{"amount"};
      my $txnsettle = $res2{"txn-settle"};
      my $descr     = $res2{"descr"};
      my $cardname  = $res2{"card-name"};
      my $acct_code = $res2{'acct_code'};

      if ( $color == 1 ) {
        print "  <tr class=\"listrow_color1\">\n";
      } else {
        print "  <tr class=\"listrow_color0\">\n";
      }
      print "<td><a href=\"$smps::path_cgi\?accttype=$accttype\&acct_code=$acct_code\&username=$smps::username\&function=details\&orderid=$orderid\">$orderid</a></td>\n";
      print "<td>$cardname</td>\n";
      print "<td>$txntype</td>\n";
      print "<td align=\"right\">$amount</td>\n";
      if ( $txnstatus =~ /^(success|problem)$/ ) {
        print "<td align=\"right\">$txnsettle</td>\n";
      } else {
        print "<td> &nbsp; </td>\n";
      }
      print "<td>$txnstatus</td>\n";
      print "<td>$descr</td>\n";
      print "\n";

      $settletotal += $txnsettle;

      if ( ( $txntype eq "return" ) && ( ( $accttype eq "" ) || ( $accttype eq "credit" ) ) ) {
        $total -= $amount;
      } else {
        $total += $amount;
      }
      $color = ( $color + 1 ) % 2;
    }
  }

  print "<tr>";
  print "<th align=\"left\">TOTAL</td>\n";
  print "<td></td>\n";
  printf( "<th align=\"right\">%.2f</th>\n", $total );
  printf( "<th align=\"right\">%.2f</th>\n", $settletotal );
  print "<td></td>\n";

  print "</table>\n";

}

sub assemble {

  if ( $ENV{'SEC_LEVEL'} >= 9 ) {
    my $message = "Your current security level is not cleared for this operation. <p>Please contact Technical Support if you believe this to be in error. ";
    &response_page($message);
  }

  my $cardtype = $smps::query->param('cardtype');
  $cardtype =~ s/[^a-z]//g;
  my $txntype = $smps::query->param('txntype');
  $txntype =~ s/[^a-z]//g;
  my $startdate = $smps::query->param('startdate');
  $startdate =~ s/[^0-9\/ ]//g;
  my $enddate = $smps::query->param('enddate');
  $enddate =~ s/[^0-9\/ ]//g;
  my $maxcount = $smps::query->param('maxcount');
  $maxcount =~ s/[^0-9]//g;
  my $lowamount = $smps::query->param('lowamount');
  $lowamount =~ s/[^0-9]//g;
  my $highamount = $smps::query->param('highamount');
  $highamount =~ s/[^0-9]//g;
  my $acct_code = $smps::query->param('acct_code');
  $acct_code =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;
  my $accttype = $smps::query->param('accttype');
  $accttype =~ s/[^a-zA-Z]//g;
  my $sortorder = $smps::query->param('sortorder');

  if ( $smps::username eq "creativepu" ) {
    $sortorder = "orderid";
  }
  $sortorder =~ s/[^a-zA-Z]//g;

  my ( $starttime, $endtime, $charges, $credits, %cardtotal, %charges, %credits, $acct_code4 );

  if ( -e "/home/pay1/outagefiles/highvolume.txt" ) {
    print "Sorry, this program is not available at this time.<p>\n";
    print "Please try back in a little while.<p>\n";
    return;
  }

  my $startyear  = $smps::query->param('startyear');
  my $startmonth = $smps::query->param('startmonth');
  my $startday   = $smps::query->param('startday');
  $startyear =~ s/[^0-9]//g;
  $startmonth =~ s/[^0-9]//g;
  $startday =~ s/[^0-9]//g;

  if ( ( $startyear >= 1999 ) && ( $startmonth >= 1 ) && ( $startmonth < 13 ) && ( $startday >= 1 ) && ( $startday < 32 ) ) {
    $startdate = sprintf( "%02d/%02d/%04d", $startmonth, $startday, $startyear );
  }

  #DCP - 20040420 - Restrict assemble batch to 3 months back.
  my ( $sec, $min, $hour, $mday, $mon, $yyear, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 93 ) );
  my $three_months_ago = sprintf( "%04d%02d%02d", $yyear + 1900, $mon + 1, $mday );
  my $tmpstartdate = substr( $startdate, 6, 4 ) . substr( $startdate, 0, 2 ) . substr( $startdate, 3, 2 );
  if ( $tmpstartdate < $three_months_ago ) {
    $startdate = substr( $three_months_ago, 4, 2 ) . "/" . substr( $three_months_ago, 6, 2 ) . "/" . substr( $three_months_ago, 0, 4 );
  }

  $tmpstartdate = substr( $startdate, 6, 4 ) . substr( $startdate, 0, 2 ) . substr( $startdate, 3, 2 );
  if ( $tmpstartdate < $smps::earliest_date ) {
    $startdate = substr( $smps::earliest_date, 4, 2 ) . "/" . substr( $smps::earliest_date, 6, 2 ) . "/" . substr( $smps::earliest_date, 0, 4 );
  }

  my $endyear  = $smps::query->param('endyear');
  my $endmonth = $smps::query->param('endmonth');
  my $endday   = $smps::query->param('endday');
  $endyear =~ s/[^0-9]//g;
  $endmonth =~ s/[^0-9]//g;
  $endday =~ s/[^0-9]//g;
  if ( ( $endyear >= 1999 ) && ( $endmonth >= 1 ) && ( $endmonth < 13 ) && ( $endday >= 1 ) && ( $endday < 32 ) ) {
    $enddate = sprintf( "%02d/%02d/%04d", $endmonth, $endday, $endyear );
  }

  if ( $lowamount > 0 ) {
    $lowamount = "$smps::currency $lowamount";
  }
  if ( $highamount > 0 ) {
    $highamount = "$smps::currency $highamount";
  }

  if ( $startdate ne "" ) {
    my ( $m, $d, $y ) = split( /\//, $startdate );
    $starttime = sprintf( "%04d%02d%02d000000", $y, $m, $d );

    if ( $smps::settletimezone ne "" ) {
      $starttime = &miscutils::strtotime($starttime);
      $starttime -= ( $smps::settletimezone * 60 * 60 );
      $starttime = &miscutils::timetostr($starttime);
    }

    if ( $starttime < '19990101000000' ) {
      $starttime = "";
      $startdate = "";
    }
  }
  if ( $enddate ne "" ) {
    my ( $m, $d, $y ) = split( /\//, $enddate );
    $endtime = sprintf( "%04d%02d%02d000000", $y, $m, $d );
  }

  $starttime =~ s/[^0-9]//g;
  $endtime =~ s/[^0-9]//g;

  print "<form name=\"assemble\" method=\"post\" action=\"$smps::path_assemble\">\n";
  print "<input type=hidden name=accttype value=\"$accttype\">";
  print "<input type=hidden name=acct_code value=\"$acct_code\">";
  print "<input type=hidden name=function value=submit>\n";
  print "<table border=1 cellspacing=0 cellpadding=2>\n";
  print "<th colspan=2></th>";
  print "<th align=left>Type</th>";
  print "<th align=left>Name</th>";
  print "<th align=left>Order ID</th>";
  print "<th>Transaction Time <font size=-2>(GMT $smps::settletimezone)<br>MM/DD/YYYY HH:MM:SS</font></th>";
  print "<th align=left>Card<br>Type</th>";

  if ( $smps::industrycode eq "restaurant" ) {
    print "<th align=left>Total Amount<br>pre gratuity</th>\n";
    print "<th align=left>Gratuity</th>\n";
  } else {
    print "<th align=left>Amount</th>\n";
  }
  print "<th align=left>Acct Code</th>\n";

  my $i = 0;
  my (%result);
  if ( ( $smps::username eq "icommerceg" ) && ( $ENV{'SUBACCT'} ne "" ) ) {
    my ( %res_icg, $maxidx );
    if ( exists $smps::altaccts{$smps::username} ) {
      foreach my $var ( @{ $smps::altaccts{$smps::username} } ) {
        my %res_icg = &miscutils::sendmserver(
          "$var",     'batch-prep', 'accttype',   "$accttype",  'card-type', "$cardtype", 'low-amount', "$lowamount", 'high-amount', "$highamount",
          'maxcount', "$maxcount",  'start-time', "$starttime", 'end-time',  "$endtime",  'txn-type',   "$txntype"
        );

        foreach my $key ( keys %res_icg ) {
          $i++;
          $result{"a$i"} = $res_icg{$key} . "\&username=$var";
        }
      }
    }
  } else {
    %result = &miscutils::sendmserver(
      "$smps::username", 'batch-prep', 'accttype',   "$accttype",  'card-type', "$cardtype", 'low-amount', "$lowamount", 'high-amount', "$highamount",
      'maxcount',        "$maxcount",  'start-time', "$starttime", 'end-time',  "$endtime",  'txn-type',   "$txntype",   'acct_code',   "$acct_code"
    );
  }

  if ( $sortorder eq "orderid" ) {
    foreach my $key ( keys %result ) {
      $result{$key} =~ s/(time=\d+)\&(order-id=\d+)/$2\&$1/;
    }
  }

  my $color          = 1;
  my %currency_types = ();
  $i = 1;
  my @values = values %result;
  foreach my $var ( sort @values ) {
    my %res2 = ();
    my @nameval = split( /&/, $var );
    foreach my $temp (@nameval) {
      my ( $name, $value ) = split( /=/, $temp );
      $res2{$name} = $value;
    }

    if ( $res2{'time'} ne "" ) {
      my $time = $res2{"time"};

      if ( $time < $starttime ) {
        next;
      }

      if ( $smps::settletimezone ne "" ) {
        $time = &miscutils::strtotime($time);
        $time += ( $smps::settletimezone * 60 * 60 );
        $time = &miscutils::timetostr($time);
      }

      my $timestr = substr( $time, 4, 2 ) . "/" . substr( $time, 6, 2 ) . "/" . substr( $time, 0, 4 ) . " ";
      $timestr = $timestr . substr( $time, 8, 2 ) . ":" . substr( $time, 10, 2 ) . ":" . substr( $time, 12, 2 );

      my $orderid    = $res2{"order-id"};
      my $txntype    = $res2{"txn-type"};
      my $amount     = $res2{"amount"};
      my $status     = $res2{"status"};
      my $cardtype   = $res2{"card-type"};
      my $cardname   = $res2{'card-name'};
      my $acct_code  = $res2{'acct_code'};
      my $auth_code  = $res2{'auth-code'};
      my $acct_code4 = $res2{'acct_code4'};

      my ( $currency, $price ) = split( / /, "$amount" );
      $currency_types{$currency} = 1;

      my ( $native_sym, $merch_sym, $native_amt, $native_isocur );
      if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
        my %currencyUSDSYM = ( 'AUD', 'A$', 'CAD', 'C$', 'EUR', '&#8364;', 'GBP', '&#163;', 'JPY', '&#165;', 'USD', '$' );
        my %currency840SYM = ( '036', 'A$', '124', 'C$', '978', '&#8364;', '826', '&#163;', '392', '&#165;', '997', '$' );

        my $dccinfo = "";
        my ( $exponent, $conv_rate );
        if ( $smps::processor eq "planetpay" ) {
          $dccinfo = substr( $auth_code, 116, 51 );
        } elsif ( $smps::processor eq "fifththird" ) {
          $dccinfo = substr( $auth_code, 186, 27 );
        } elsif ( $smps::processor eq "testprocessor" ) {
          $dccinfo = substr( $auth_code, 116, 37 );
        }
        if ( $dccinfo =~ /\,/ ) {
          my ($dummy);
          ( $dummy, $dummy, $dummy, $conv_rate, $exponent, $dummy, $dummy ) = split( /\,/, $dccinfo );
        } else {
          $conv_rate = substr( $dccinfo, 15, 10 ) + 0;
          $exponent  = substr( $dccinfo, 25, 1 );
        }
        $conv_rate = ( $conv_rate / ( 10**$exponent ) );

        $native_sym = $currency840SYM{$currency};
        $merch_sym  = $currencyUSDSYM{$smps::currency};

        my $currencyObj = new PlugNPay::Currency($currency);
        $native_amt = $currencyObj->format( ( $amount * $conv_rate + .00001 ), { digitSeparator => '' } );
        $native_isocur = $currencyObj->getCurrencyCode();
      }

      if ( $color == 1 ) {
        print "  <tr class=\"listrow_color1\">\n";
      } else {
        print "  <tr class=\"listrow_color0\">\n";
      }
      print "<th>$i</th>\n";
      print "<td><nobr><input type=checkbox name=listval value=$i></nobr></td>\n";
      print "<input type=hidden name=\"order-id-$i\" value=\"$orderid\">\n";
      print "<input type=hidden name=\"txn-type-$i\" value=\"$txntype\">\n";
      print "<input type=hidden name=\"username-$i\" value=\"$res2{'username'}\">\n";
      if ( $smps::industrycode ne "restaurant" ) {
        print "<input type=hidden name=\"amount-$i\" value=\"$amount\">\n";
      }
      if ( $smps::feature{'display_ac4'} == 1 ) {
        print "<input type=hidden name=\"acct_code4-$i\" value=\"$acct_code4\">\n";
      }
      print "<td><nobr>$txntype</nobr></td>\n";
      print "<td><nobr>$cardname</nobr></td>\n";
      print "<td><nobr>$orderid</nobr></td>\n";
      print "<td align=center><nobr>$timestr</nobr></td>\n";
      if ( $accttype eq "checking" ) {
        print "<td align=center><nobr>Check</nobr></td>\n";
      } else {
        print "<td align=center><nobr>$cardtype</nobr></td>\n";
      }
      if ( $smps::industrycode eq "restaurant" ) {
        print "<td><nobr><input type=\"hidden\" name=\"amount-$i\" value=\"$amount\">$amount</nobr></td>\n";
        print "<td><nobr><input type=\"text\" name=\"gratuity-$i\" value=\"\"></nobr></td>\n";
      } else {
        print "<td><nobr>$amount</nobr></td>\n";
      }
      print "<td><nobr>$acct_code &nbsp;</nobr></td>\n";
      print "\n";
      $i++;

      $color = ( $color + 1 ) % 2;

      if ( ( $txntype =~ /auth/ ) ) {
        $cardtotal{"$cardtype $currency"} += $price;
        $charges{$currency} += $price;
      } else {
        $cardtotal{"$cardtype $currency"} -= $price;
        $credits{$currency} += $price;
      }
    }
  }

  if ( $i == 1 ) {
    print "<tr><td align=center colspan=8><nobr><b>No Unmarked Transations Available</b></nobr></td></tr>\n";
  }

  print "</table>\n";

  print "<br>\n";

  if ( $i > 1 ) {
    print "<table border=1 cellspacing=0 cellpadding=2>\n";
    print "<tr><th align=left>Card Totals</th><th colspan=2>Amount</th>\n";
    foreach my $curr ( sort keys %currency_types ) {
      foreach my $var ( sort keys %cardtotal ) {
        my ( $ctype, $dummy ) = split( / /, $var );
        printf( "<tr><td>%s</td><td>$curr<td align=right>%.2f</td>\n", $smps::cardarray{$ctype}, $cardtotal{"$var"} );
      }
      printf( "<tr><th align=left>Total Charges</th><td>$curr</td><td align=right>%.2f</td>",  $charges{$curr} );
      printf( "<tr><th align=left>Total Returns</th><td>$curr</td><td align=right>%.2f</td>",  $credits{$curr} );
      printf( "<tr><th align=left>Total in Batch</th><td>$curr</td><td align=right>%.2f</td>", $charges{$curr} - $credits{$curr} );
    }
    print "</table>\n";

    print
      "<br><input type=submit name=submit value=\"Commit Batch\"> <input type=button value=\"Un-Check All\" onClick=\"uncheck($i)\;\"> <input type=button value=\"Check All\" onClick=\"check($i)\;\">\n";
    print "<input type=\"hidden\" name=\"merchant\" value=\"$smps::merchant\">\n";
    print "</form>";
  }

  my $datetime = gmtime(time);
  $smps::endtime = time();
  my $elapse = $smps::endtime - $smps::strttime;

  if ( $elapse > 30 ) {
    &logToDataLog(
      { 'originalLogFile' => '/home/pay1/database/debug/smps_longqueries.txt',
        'function'        => $smps::function,
        'elapsedTime'     => $elapse,
        'username'        => $smps::username,
        'login'           => $ENV{'LOGIN'},
        'remoteUser'      => $ENV{'REMOTE_USER'},
        'logReason'       => 'smps query exceeds "long" threshold'
      }
    );
  }
}

sub submit {
  if ( $smps::processor =~ /^(testprocessor|nova)$/ ) {
    &submit_as_postauths();
    return;
  }

  my $flag           = 0;
  my $batch_count    = 0;
  my $batch_subtotal = 0;
  my %batch          = ();

  my @listval = $smps::query->param('listval');
  foreach my $var ( sort @listval ) {
    my $price = $smps::query->param("amount-$var");
    $price =~ s/[^0-9A-Za-z\ \.]//g;

    my ( $currency, $amount ) = split( / /, $price );

    $batch_count += 1;

    my $gratuity = $smps::query->param("gratuity-$var");
    $gratuity =~ s/[^0-9\.]//g;
    my $tran_total = sprintf( "%.2f", $amount + $gratuity );
    $amount = "$currency " . "$tran_total";

    my $oid = $smps::query->param("order-id-$var");
    $oid =~ s/[^0-9]//g;
    $batch{"order\-id\-$batch_count"} = $oid;
    my $txntype = $smps::query->param("txn-type-$var");
    $txntype =~ s/[^a-zA-Z]//g;
    $batch{"txn\-type\-$batch_count"} = $txntype;

    $batch{"amount\-$batch_count"}   = $amount;
    $batch{"gratuity\-$batch_count"} = $gratuity;

    my $ac4 = $smps::query->param("acct_code4-$var");
    $ac4 =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;
    $batch{"acct_code4\-$batch_count"} = $ac4;

    $batch_subtotal += $amount;

    if ( $batch_count == 50 ) {
      my @pairs = %batch;
      &process_batch( $batch_count, @pairs );
      $batch_count    = 0;
      $batch_subtotal = 0;
      %batch          = ();
    }
  }

  if ( $batch_count > 0 ) {
    my @pairs = %batch;
    &process_batch( $batch_count, @pairs );
    $batch_count    = 0;
    $batch_subtotal = 0;
    %batch          = ();
  }

  my $datetime = gmtime(time);
  $smps::endtime = time();
  my $elapse = $smps::endtime - $smps::strttime;

  if ( $elapse > 30 ) {
    &logToDataLog(
      { 'originalLogFile'  => '/home/pay1/database/debug/smps_longqueries.txt',
        'transactionCount' => $smps::trancount,
        'function'         => $smps::function,
        'elapsedTime'      => $elapse,
        'username'         => $smps::username,
        'login'            => $ENV{'LOGIN'},
        'remoteUser'       => $ENV{'REMOTE_USER'},
        'logReason'        => 'smps query exceeds "long" threshold'
      }
    );
  }
}

sub submit_as_postauths {
  my %batch = ();
  my $color = 1;

  my @listval  = $smps::query->param('listval');
  my $accttype = $smps::query->param('accttype');

  my $date_time = gmtime(time);
  print "<div align=center><table border=1 cellspacing=0 cellpadding=2>\n";
  print "  <tr class=\"listsection_title\">\n";
  print "    <td align=left>DATE</td>\n";
  print "    <td colspan=2>$date_time <b>GMT</b></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th align=left>Order ID</th>\n";
  print "    <th align=left>Result</th>\n";
  print "    <th align=left>Exception</th>\n";
  print "  </tr>\n";

  foreach my $var ( sort @listval ) {
    $var =~ s/[^0-9]//g;

    my $price = $smps::query->param("amount-$var");
    my ( $currency, $amount ) = split( / /, $price );

    my $gratuity = $smps::query->param("gratuity-$var");
    $gratuity =~ s/[^0-9\.]//g;
    my $tran_total = sprintf( "%.2f", $amount + $gratuity );
    $amount = "$currency " . "$tran_total";

    $batch{'order-id'}   = $smps::query->param("order-id-$var");
    $batch{'txn-type'}   = $smps::query->param("txn-type-$var");
    $batch{'amount'}     = $amount;
    $batch{'gratuity'}   = $gratuity;
    $batch{'acct_code4'} = $smps::query->param("acct_code4-$var");

    $batch{'order-id'} =~ s/[^0-9]//g;
    $batch{'txn-type'} =~ s/[^0-9a-zA-Z]//g;
    $batch{'amount'} =~ s/[^0-9a-zA-Z\ \.]//g;
    $batch{'gratuity'} =~ s/[^0-9a-zA-Z\ \.]//g;
    $batch{'acct_code4'} =~ s/[^A-Za-z0-9:,\-\. _\#]//g;

    my @pairs = %batch;

    my %batch_result = &miscutils::sendmserver( "$smps::username", 'postauth', 'accttype', "$accttype", @pairs );

    if ( $color == 1 ) {
      print "  <tr class=\"listrow_color1\">\n";
    } else {
      print "  <tr class=\"listrow_color0\">\n";
    }
    print "    <td>$batch{'order-id'}</td>\n";
    print "    <td>$batch_result{'FinalStatus'}</td>\n";
    print "    <td>$batch_result{'MErrMSg'}</td>\n";
    print "  </tr>\n";

    $color = ( $color + 1 ) % 2;
    %batch = ();
  }

  print "</table></div><br>\n";
  print "<hr width=400><br>\n";

  my $datetime = gmtime(time);
  $smps::endtime = time();
  my $elapse = $smps::endtime - $smps::strttime;

  if ( $elapse >= 0 ) {

    #Even a moment is an eternity
    &logToDataLog(
      { 'originalLogFile' => '/home/pay1/database/debug/smps_longqueries.txt',
        'function'        => $smps::function,
        'elapsedTime'     => $elapse,
        'username'        => $smps::username,
        'login'           => $ENV{'LOGIN'},
        'remoteUser'      => $ENV{'REMOTE_USER'},
        'logReason'       => 'smps query exceeds "long" threshold'
      }
    );
  }
}

sub process_result {
  my ( $orderID, $txntype, $price, $batch_count, $batch_subtotal, $gratuity, @pairs ) = @_;

  ( $batch_count, $batch_subtotal, @pairs ) = &add_to_batch( $orderID, $txntype, $price, $batch_count, $batch_subtotal, $gratuity, @pairs );

  if ( $batch_count == 50 ) {
    &process_batch( $batch_count, @pairs );
    ( $batch_count, $batch_subtotal, @pairs ) = &initialize_batch();
  }
  return ( $batch_count, $batch_subtotal, @pairs );
}

sub initialize_batch {
  my ( $batch_count, $batch_subtotal, @pairs );
  return ( $batch_count, $batch_subtotal, @pairs );
}

sub add_to_batch {
  my ( $orderID, $txntype, $price, $batch_count, $batch_subtotal, $gratuity, @pairs ) = @_;
  my ( $dummy, $amount ) = split( / /, $price );
  $batch_count += 1;

  $pairs[ ++$#pairs ] = "order\-id\-$batch_count";
  $pairs[ ++$#pairs ] = "$orderID";
  $pairs[ ++$#pairs ] = "txn\-type\-$batch_count";
  $pairs[ ++$#pairs ] = "$txntype";
  $pairs[ ++$#pairs ] = "amount\-$batch_count";
  $pairs[ ++$#pairs ] = "$price";
  $pairs[ ++$#pairs ] = "gratuity\-$batch_count";
  $pairs[ ++$#pairs ] = "$gratuity";

  $batch_subtotal += $amount;
  return ( $batch_count, $batch_subtotal, @pairs );
}

sub process_batch {

  my ( $batch_count, @pairs ) = @_;

  my $a = @pairs;

  my $accttype = $smps::query->param('accttype');
  @pairs = ( "num\-txns", "$batch_count", @pairs );
  my %batch_result = &miscutils::sendmserver( "$smps::username", 'batch-commit', 'accttype', "$accttype", @pairs );

  if ( $batch_result{"batch-id"} ne "" ) {
    print "<b>Batch ID:</b> " . $batch_result{"batch-id"} . "<br>\n";
    print "<b>Gateway Batch ID:</b> " . $batch_result{"gw-batch-id"} . "<br>\n";
    print "<b>Status:</b> " . $batch_result{"FinalStatus"} . "<br>\n";
    print "<b>Batch Status:</b> " . $batch_result{"batch-status"} . "<br>\n";
    print "<b>Batch Message:</b> " . $batch_result{"MErrMsg"} . "<br>\n";
    print "<b>Batch Amount:</b> " . $batch_result{"total-amount"} . "<br><br>\n";
  }

  my $date_time = gmtime(time);
  print "<div align=center><table border=1 cellspacing=0 cellpadding=2>\n";
  print "  <tr class=\"listsection_title\">\n";
  print "    <td align=left>DATE</td>\n";
  print "    <td colspan=2>$date_time <b>GMT</b></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th align=left>Order ID</th>\n";
  print "    <th align=left>Result</th>\n";
  print "    <th align=left>Exception</th>\n";
  print "  </tr>\n";

  my $color = 1;
  for ( my $i = 1 ; $i <= $batch_count ; $i++ ) {
    if ( $color == 1 ) {
      print "  <tr class=\"listrow_color1\">\n";
    } else {
      print "  <tr class=\"listrow_color0\">\n";
    }
    print "    <td>" . $batch_result{"order-id-$i"} . "</td>\n";
    print "    <td>" . $batch_result{"response-code-$i"} . "</td>\n";
    print "    <td>" . $batch_result{"exception-message-$i"} . "</td>\n";
    print "  </tr>\n";
    $color = ( $color + 1 ) % 2;
  }
  print "</table></div><br>\n";

  print "<hr width=400><br>\n";
}

sub head {
  my ( $title, $onload ) = @_;

  if ( $title eq "" ) {
    $title = "Transaction Administration";
  }

  print "<html>\n";
  print "<head>\n";
  print "<title>Transaction Administration Area</title>\n";
  print "<link href=\"/_css/admin/smps.css\" type=\"text/css\" rel=\"stylesheet\">\n";

  # css for tablesorter
  print " <style type=\"text/css\">\n";
  print "       th.header { \n";
  print "             background-image: url(../images/bg.gif);\n";
  print "             cursor: pointer;\n";
  print "             font-weight: bold;\n";
  print "             background-repeat: no-repeat;\n";
  print "             background-position: center left;\n";
  print "             padding-left: 20px;\n";
  print "             border-right: 1px solid #dad9c7;\n";
  print "             margin-left: -1px;\n";
  print "       }\n";
  print "	th.headerSortUp { \n";
  print "             background-image: url(../images/asc.gif);\n";
  print "             background-color: #D0D0D0;\n";
  print "       }\n";
  print "       th.headerSortDown { \n";
  print "             background-image: url(../images/desc.gif);\n";
  print "             background-color: #eeeeee;\n";
  print "       }\n";
  print "       table.tablesorter tbody tr.odd td { \n";
  print "		background-color:#FFFFFF; \n";
  print "       }\n";
  print "       table.tablesorter tbody tr.even td { \n";
  print "               background-color:#e0e0e0; \n";
  print "       }\n";
  print " </style>\n";

  # js logout prompt
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/_js/jquery-1.10.2.min.js\"></script>\n";
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/_js/jquery-ui-1.10.3.custom.min.js\"></script>\n";
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/javascript/jquery_cookie.js\"></script>\n";
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/_js/admin/autologout.js\"></script>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"/_css/plugnpay-theme/jquery-ui-1.10.3.custom.min.css\">\n";

  print "<script type='text/javascript'>\n";
  print "       /** Run with defaults **/\n";
  print "       \$(document).ready(function(){\n";
  print "         \$(document).idleTimeout();\n";
  print "        });\n";
  print "</script>\n";

  # end logout js

  print "<script type=\"text/javascript\" src=\"/javascript/decryptcard.js\"></script>\n";

  print "<script type=\"text/javascript\" src=\"/javascript/cardTypeOptions.js\"></script>\n";

  print "<script type=\"text/javascript\" src=\"/javascript/tablesorter/jquery.metadata.js\"></script>\n";
  print "<script type=\"text/javascript\" src=\"/javascript/tablesorter/jquery.tablesorter.js\"></script>\n";

  print "<script type=\"text/javascript\" Language=\"Javascript\">\n";
  print "<!-- Start Script\n";

  print " // tablesorter // \n";
  print " \$(document).ready(function() { \n";
  print "   \$(\"#sortabletable\").tablesorter({\n";
  print "        widgets: ['zebra'],\n";
  print "        textExtraction: function(node) {\n";
  print "            return node.getAttribute('sortvalue') || node.innerHTML;\n";
  print "        }\n";
  print "    });\n";
  print "  });\n";
  print " // end tablesorter // \n";

  print "function results() \{\n";
  print "   resultsWindow \= window.open(\"/payment/recurring/blank.html\",\"results\",\"menubar=no,status=no,scrollbars=yes,resizable=yes,width=400,height=300\")\;\n";
  print "}\n";

  print "function change_win(helpurl,swidth,sheight,windowname) {\n";
  print "  SmallWin = window.open(helpurl, windowname,'scrollbars=yes,resizable=yes,status=yes,toolbar=yes,menubar=yes,height='+sheight+',width='+swidth);\n";
  print "}\n";

  print "function uncheck(max) {\n";
  print "  for (k = 0\; k < max - 1\; k++) {\n";
  print "    document.assemble.listval[k].checked = false\;\n";
  print "  }\n";
  print "}\n";

  print "function check(max) {\n";
  print "  for (k = 0\; k < max - 1\; k++) {\n";
  print "    document.assemble.listval[k].checked = true\;\n";
  print "  }\n";
  print "}\n";

  print "function disableForm(theform) { \n";
  print "  if (document.all || document.getElementById) { \n";
  print "    for (i = 0; i < theform.length; i++) { \n";
  print "      var tempobj = theform.elements[i]; \n";
  print "      if (tempobj.type.toLowerCase() == \"submit\" || tempobj.type.toLowerCase() == \"reset\") \n";
  print "        tempobj.disabled = true; \n";
  print "      if (tempobj.type.toLowerCase() == \"button\") \n";
  print "        tempobj.disabled = false; \n";
  print "    } \n";
  print "    return true; \n";
  print "  } \n";
  print "  else { \n";
  print "    return true; \n";
  print "  } \n";
  print "} \n";

  print "function enableForm(theform) { \n";
  print "  if (document.all || document.getElementById) { \n";
  print "    for (i = 0; i < theform.length; i++) { \n";
  print "      var tempobj = theform.elements[i]; \n";
  print "      if (tempobj.type.toLowerCase() == \"submit\" || tempobj.type.toLowerCase() == \"reset\") \n";
  print "        tempobj.disabled = false; \n";
  print "      if (tempobj.type.toLowerCase() == \"button\") \n";
  print "        tempobj.disabled = true; \n";
  print "    } \n";
  print "    return true; \n";
  print "  } \n";
  print "  else { \n";
  print "    return true; \n";
  print "  } \n";
  print "} \n";

  print "function closewin() {\n";
  print "  self.close();\n";
  print "}\n";

  my $adjustmentEnabled = &enabledInAdjustmentTable();
  print "function validateReturn(originalAmount){\n";
  print "  var error = false;\n";
  print "  var adjustmentEnabled = $adjustmentEnabled;\n";
  print "  originalAmount = parseFloat(originalAmount.replace(/[^0-9.]/g,''), 10);\n";
  print "  var retamount=document.forms[\"return\"][\"amount\"].value;\n";
  print "  retamount = parseFloat(retamount.replace(/\[^0-9.]/g,''), 10);\n";
  print "  if (isNaN(retamount) || retamount < 0.01) {\n";
  print "    alert('Amount must be greater than 0.00.');\n";
  print "    error = true;\n";
  print "  } else if (isNaN(originalAmount) || retamount > originalAmount) {\n";
  print "    alert('Amount cannot be greater than the amount of the transaction.');\n";
  print "    error = true;\n";
  print "  }\n";
  print "  if (error) {\n";
  print "    if (adjustmentEnabled && typeof AdjustmentDialogBox.resetTransactionAmount() === 'function') {\n";
  print "      AdjustmentDialogBox.resetTransactionAmount();\n";
  print "    }\n";
  print "    return false;\n";
  print "  }\n";
  print "}\n";

  print "// end script-->\n";
  print "</script>\n";

  print "<SCRIPT LANGUAGE=\"JavaScript\" TYPE=\"text/javascript\">\n";
  print "<!--\n";
  print "  function popminifaq() {\n";
  print "    minifaq=window.open('','minifaq','width=600,height=400,toolbar=no,location=no,directories=no,status=yes,menubar=yes,scrollbars=yes,resizable=yes');\n";
  print "    if (window.focus) { minifaq.focus(); }\n";
  print "    return false;\n";
  print "  }\n";
  print "// -->\n";
  print "</SCRIPT>\n";
  print "<script type=\"text/javascript\" src=\"/_js/Tools.js\"></script>\n";

  # Load adjustment dialog box javascript
  if ( $smps::function eq 'details' ) {
    if ( &enabledInAdjustmentTable() ) {
      my ( $adjustmentFlag, $surchargeFlag, $feeFlag ) = getAdjustmentFlags();

      # set adjustment model fields
      my $adjustmentModelName = '';
      my $isSurcharge         = 0;
      my $isFee               = 0;
      if ( $adjustmentFlag == 1 ) {
        if ( $surchargeFlag == 1 ) {
          $adjustmentModelName = "Credit Card Fee";
          $isSurcharge         = 1;
        } else {
          $adjustmentModelName = "Service Fee";
        }
        $isFee = $feeFlag ? 1 : 0;
      }

      # find out if merchant checks if customer's state allows surcaharge
      my $coa                = new PlugNPay::COA($smps::username);
      my $checkCustomerState = $coa->getCheckCustomerState();

      # get CSRF Token
      my $csrfToken = new PlugNPay::Security::CSRFToken()->getToken();

      # create javascript
      print "<!-- Adjustment Dialog Box -->\n";
      print "<meta name=\"request-token\" content=\"$csrfToken\">\n";
      print "<script type=\"text/javascript\" src=\"/_js/adjustmentDialogBox.js\"></script>\n";
      print "<script type=\"text/javascript\">\n";
      print qq`
        jQuery(document).ready(function() {
          var isSurcharge = $isSurcharge;
          var isFee = $isFee;
          AdjustmentDialogBox.setGatewayAccount('$smps::username');
          AdjustmentDialogBox.setAdjustmentModelName('$adjustmentModelName');
          AdjustmentDialogBox.setIsSurcharge(isSurcharge);
          AdjustmentDialogBox.setToken(jQuery('#cardToken').text());
          AdjustmentDialogBox.setBillingState(jQuery('#detailsBillingState').text());
          AdjustmentDialogBox.setCheckCustomerState($checkCustomerState);
          AdjustmentDialogBox.setAccountType(jQuery('#detailsAccountType').text());
          AdjustmentDialogBox.setTransactionCurrency('$smps::currency');
          if (jQuery('#doReturn').length) {
            AdjustmentDialogBox.setOriginalTransactionAmount(jQuery('#doReturn input[name=originalTransactionAmount]').val());
          } else if (jQuery('#reauthorizeTransaction').length) {
            AdjustmentDialogBox.setOriginalTransactionAmount(jQuery('#reauthorizeTransaction input[name=original_amount]').val());
          }
          AdjustmentDialogBox.setResponderPrefix('/admin');
          buttonSelectorArray = ['#rechargeCustomerButton'];
          formSelectorArray = [];
          if (isSurcharge) {
            buttonSelectorArray.push('#reauthorizeTransactionButton');
            formSelectorArray.push('#reauthorizeTransaction')
          }
          if (!isFee) {
            buttonSelectorArray.push('#doReturnButton');
            formSelectorArray.push('#doReturn');
          }
          AdjustmentDialogBox.init(buttonSelectorArray);
          AdjustmentDialogBox.hideAdjustmentCheckbox(formSelectorArray);
        });
      `;
      print "</script>\n";
    }

    print "<!-- Recharge customer email receipt -->\n";
    print "<script>\n";
    print "  jQuery(document).ready(function() { \n";
    print "    var emailAddress = jQuery('#rechargeCustomerEmailField input').val();\n";
    print "    jQuery('#rechargeCustomerEmailField').hide();\n";
    print "    jQuery('#rechargeCustomerEmailField input').val('');\n";
    print "    jQuery('#rechargeCustomerEmailCheckbox').click(function() {\n";
    print "      if (jQuery('#rechargeCustomerEmailCheckbox').prop('checked')) {\n";
    print "        jQuery('#rechargeCustomerEmailField').show();\n";
    print "        jQuery('#rechargeCustomerEmailField input').val(emailAddress);\n";
    print "      } else {\n";
    print "        jQuery('#rechargeCustomerEmailField').hide();\n";
    print "        jQuery('#rechargeCustomerEmailField input').val('');\n";
    print "      }\n";
    print "    });\n";
    print "    jQuery('#rechargeCustomer').submit(function() {\n";
    print "      if (jQuery('#rechargeCustomerEmailCheckbox').prop('checked') && jQuery('#rechargeCustomerEmailField input').val() == '') {\n";
    print "        alert('Customer Email is Required');\n";
    print "        jQuery('#rechargeCustomerEmailField input').css('border-color','#f00').focus();\n";
    print "        return false;\n";
    print "      }\n";
    print "    });\n";
    print "  });\n";
    print "</script>\n";
  }
  print "</head>\n";

  print "<body bgcolor=\"#ffffff\" $onload>\n";

  print "<table width=\"760\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\" id=\"header\">\n";
  print "  <tr>\n";
  print "    <td colspan=\"3\" align=\"left\">";
  if ( $ENV{'SERVER_NAME'} =~ /plugnpay\.com/i ) {
    print "<img src=\"/images/global_header_gfx.gif\" width=\"760\" alt=\"Plug 'n Pay Technologies - we make selling simple.\" height=\"44\" border=\"0\">";
  } else {
    print "<img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Logo\">\n";
  }
  print "</td>\n";
  print "  </tr>\n";

  if ( $smps::reseller !~ /(webassis)/ ) {
    print "  <tr>\n";
    print "    <td align=\"left\" nowrap><a href=\"$ENV{'SCRIPT_NAME'}\">Home</a></td>\n";
    print "    <td align=\"right\" nowrap><a href=\"/admin/logout.cgi\">Logout</a> </td>\n";
    print "  </tr>\n";
  }

  print "  <tr>\n";
  print "    <td colspan=\"3\" align=\"left\"><img src=\"/css/header_bottom_bar_gfx.gif\" width=\"760\" height=\"14\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table border=\"0\" cellspacing=\"0\" cellpadding=\"5\" width=\"760\">\n";
  print "  <tr>\n";
  print "    <td colspan=\"3\" valign=\"top\" align=\"left\">\n";
  print "  <tr>\n";
  print "    <td colspan=\"2\"><h1><a href=\"$ENV{'SCRIPT_NAME'}\">Transaction Administration Area</a> - $smps::company</h1>\n";

  if ( $smps::username =~ /^(icommerceg)$/ ) {
    print "<b>Troy, MI USA 1-800-226-2273 or (248) 269-6000</b><br>\n";
  }
}

sub usernameSelect {
  my $info       = shift;
  my $username   = $info->{'username'};
  my $login      = $info->{'login'};
  my $fieldName  = $info->{'fieldName'};
  my $selectName = $info->{'selectName'};
  my $selectHTML = '';

  my $linkedAccounts = new PlugNPay::GatewayAccount::LinkedAccounts( $username, $login );
  my $accts = $linkedAccounts->getLinkedAccounts();

  $selectHTML .= 'Merchant: <select name="' . $fieldName . '" id="' . $selectName . '">';

  foreach my $key ( sort @{$accts} ) {
    $selectHTML .= '<option value="' . $key . '" ' . ( $key eq $username ? 'selected' : '' ) . '>' . $key . '</option>';
  }

  $selectHTML .= '</select>';

  return $selectHTML;
}

sub cardquery {
  my %cardtype_hash = %smps::cardarray;
  delete $cardtype_hash{'ach'};
  delete $cardtype_hash{'vsmc'};
  if ( $smps::processor ne "ncb" ) {
    delete $cardtype_hash{'kc'};
  } elsif ( $smps::processor !~ /^(pago|barclays)$/ ) {
    delete $cardtype_hash{'sw'};
    delete $cardtype_hash{'ma'};
  }

  my (%selected);
  if ( exists $smps::cookie{'query_settings'} ) {
    my ( $tz, $rembr ) = split( '\|', $smps::cookie{'query_settings'} );
    if ( $rembr eq "yes" ) {
      $selected{'remember'} = "checked";
    }
    if ( ( $smps::feature{'settletimezone'} eq "" ) && ( $tz ne "" ) ) {
      $smps::feature{'settletimezone'} = $tz;
    }
  }
  my ( $startdate, $enddate ) = @_;
  print "<tr>\n";
  print "<td class=\"menuleftside\">Card Queries Void Return</td>\n";
  print "<td class=\"menurightside\">\n";
  if ( -e "/home/pay1/outagefiles/highvolume.txt" ) {
    print "Sorry, this program is not available at this time.<p>\n";
    print "Please try back in a little while.<p>\n";
    return;
  }
  print "<form action=\"$smps::path_cgi\" method=post onSubmit=\"return disableForm(this);\">";
  print "<pre><b>\n";
  print "<input type=hidden name=function value=query>\n";

  # pre tags need spaces before :(
  print '       '
    . usernameSelect(
    { username   => $smps::username,
      login      => $smps::login,
      fieldName  => 'merchant',
      selectName => 'cardquery_merchant'
    }
    )
    . "\n";

  print "           Card: <select name=cardtype>\n";
  print "<option value=\"\">All Cards</option>\n";

  foreach my $key ( sort keys %cardtype_hash ) {
    print "<option value=\"$key\">$cardtype_hash{$key}</option>\n";
  }

  print "</select>                   <a href=\"help.html#query\" target=help>Help</a>\n";
  print "    Transaction: <select name=\"txntype\">\n";
  print "<option value=\"\">All Transactions</option>\n";
  print "<option value=\"invoice\">Invoiced</option>\n";
  print "<option value=\"auth\">Authorized</option>\n";
  print "<option value=\"anm\">Authorized but never marked</option>\n";
  print "<option value=\"marked\">Marked for batching</option>\n";
  print "<option value=\"settled\">Settled Auths</option>\n";
  print "<option value=\"forceauth\">Forced Auth</option>\n";
  print "<option value=\"markret\">Returns</option>\n";
  print "<option value=\"setlret\">Settled Returns</option>\n";
  print "<option value=\"voidmark\">Voided Marks</option>\n";
  print "<option value=\"voidreturn\">Voided Returns</option>\n";
  print "<option value=\"batch\">Batches</option>\n";

  if ( $smps::chkprocessor ne "" ) {
    print "<option value=\"chargeback\">ACH Rejections</option>\n";
    if ( $smps::feature{'ach_repre_limit'} ne "" ) {
      print "<option value=\"representment\">ACH Representments</option>\n";
      print "<option value=\"rejectrpt\">ACH Rejection Report</option>\n";
    }
  }
  print "</select>\n";
  print "         Status: <select name=\"txnstatus\">\n";
  print "<option value=\"success\">success</option>\n";
  print "<option value=\"pending\">pending</option>\n";
  print "<option value=\"sap\">success and pending</option>\n";
  print "<option value=\"failure\">failure</option>\n";
  print "<option value=\"badcard\">badcard</option>\n";
  print "<option value=\"problem\">problem</option>\n";
  print "<option value=\"\">any status</option>\n";
  print "</select>\n";
  my ( $select_mo, $select_dy, $select_yr ) = split( '/', $startdate );
  my $html = &miscutils::start_date( $select_yr, $select_mo, $select_dy );
  print "      First Day: $html ";
  print "  Time: <select name=\"starthour\">\n";

  for ( my $i = 0 ; $i <= 23 ; $i++ ) {
    my $time = sprintf( "%02d", $i );
    print "<option value=\"$i\">$time</option>\n";
  }

  print "    </select>\n";

  ( $select_mo, $select_dy, $select_yr ) = split( '/', $enddate );
  $html = &miscutils::end_date( $select_yr, $select_mo, $select_dy );
  print "       Last Day: $html ";
  print "  Time: <select name=\"endhour\">\n";
  for ( my $i = 0 ; $i <= 23 ; $i++ ) {
    my $time = sprintf( "%02d", $i );
    print "<option value=\"$i\">$time</option>\n";
  }
  print "    </select>\n";

  my %timezonehash = ();
  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( time() );
  if ( $isdst == 1 ) {
    %timezonehash = %constants::daylighttimezones;
  } else {
    %timezonehash = %constants::timezones;
  }

  print "      Time Zone: <select name=\"settletimezone\">\n";
  print "      <option value=\"\"> Select Time Zone </option>\n";
  foreach my $timeshift ( sort numerically keys %timezonehash ) {
    print "      <option value=\"$timeshift\" ";
    if ( $timeshift == $smps::feature{'settletimezone'} ) {
      print "selected";
    }
    print "> $timezonehash{$timeshift} </option>\n";
  }
  print "    </select> <input type=\"checkbox\" name=\"remember\" value=\"yes\" $selected{'remember'}> Remember Setting\n";

  print "       Order ID: <input type=text size=\"32\" name=\"orderid\"> (optional)\n";
  print "                 <input type=\"checkbox\" name=\"oidcn\" value=\"yes\"> Check to display all orders using the same CC# as OrderID entered.\n";

  # 06/01/05 - comment out by David request - does not work due to alpha-numeric values in numeric only search (format 'USD xxx.xx')
  print " Amount between: <input type=text size=\"8\" name=\"lowamount\"> and: <input type=text size=\"8\" name=\"highamount\"> (optional)\n";

  print "    Card Number: <input type=text size=\"20\" name=\"cardnumber\" autocomplete=\"off\"> (optional)\n";
  print " Routing Number: <input type=text size=\"20\" name=\"routingnum\" autocomplete=\"off\"> (optional - for checks only)\n";
  print " Account Number: <input type=text size=\"20\" name=\"accountnum\" autocomplete=\"off\"> (optional - for checks only)\n";

  if ( ( $smps::walletprocessor =~ /^(feed|seqr)$/ ) || ( $smps::achstatus eq "enabled" ) ) {
    print "      Acct Type: <select name=\"accttype\">\n";
    print "<option value=\"credit\"> Credit</option>\n";
    if ( $smps::achstatus eq "enabled" ) {
      print "<option value=\"checking\"> Checking</option>\n";
    }
    if ( $smps::walletprocessor =~ /^feed$/ ) {
      print "<option value=\"feed\"> Feed Tribe</option>\n";
    } elsif ( $smps::walletprocessor =~ /^seqr$/ ) {
      print "<option value=\"seqr\"> SEQR</option>\n";
    }

    print "</select>\n";
  }

  print "      Acct Code: <input type=text size=\"12\" maxlength=\"25\" name=\"acct_code\"> \n";
  print "     Acct Code2: <input type=text size=\"12\" maxlength=\"25\" name=\"acct_code2\"> \n";
  print "     Acct Code3: <input type=text size=\"12\" maxlength=\"25\" name=\"acct_code3\"> \n";

  if ( ( $smps::feature{'curr_allowed'} ne "" ) && ( $smps::processor =~ /^(pago|atlantic|planetpay|testprocessor|fifththird|wirecard)$/ ) ) {
    print "       Currency: <select name=\"currency\">\n";
    print "<option value=\"\" selected>Any</option>\n";
    my @array = split( /\|/, $smps::feature{'curr_allowed'} );
    foreach my $entry (@array) {
      $entry =~ tr/A-Z/a-z/;
      $entry =~ s/[^a-z]//g;
      print "<option value=\"$entry\">$entry</option>\n";
    }
    print "</select> (optional)\n";
  }

  if ( $smps::processor =~ /^(wirecard|banistmo|epx|catalunya|sabadell)$/ ) {
    print "    Reference #: <input type=text size=\"24\" maxlength=\"24\" name=\"refnumber\"> \n";
  }
  if ( ( $smps::username =~ /^om/ ) && ( $smps::processor eq "global" ) ) {
    print "      Invoice #: <input type=text size=\"24\" maxlength=\"24\" name=\"invoicenum\"> \n";
  }
  if ( $smps::reseller =~ /^(paynisc|payntel|siipnisc|siiptel|teretail|elretail)$/ ) {
    print " Partial Match : <input type=\"checkbox\" name=\"partial\" value=\"1\" checked> Check to Display Partial Matches on Acct Code Queries.\n";
    print "     Acct Code4: <input type=radio name=\"acct_code4\" value=\"\" checked> Any &nbsp;";
    print " <input type=radio name=\"acct_code4\" value=\"Collect Batch\"> Collect Batch &nbsp;";
    print " <input type=radio name=\"acct_code4\" value=\"CR\"> CR &nbsp;";
    print " <input type=radio name=\"acct_code4\" value=\"Virtual Terminal\"> Virt. Term. &nbsp;";
    print " <input type=radio name=\"acct_code4\" value=\"IVR\"> IVR &nbsp;\n";
    print " <input type=radio name=\"acct_code4\" value=\"KIO\"> KIO &nbsp;\n";
    print " <input type=radio name=\"acct_code4\" value=\"EBI\"> EBI &nbsp;\n";
  } else {
    print "  Partial Match: <input type=\"checkbox\" name=\"partial\" value=\"1\"> Check to Display Partial Matches on Acct Code Queries.\n";
    print " Virt. Terminal: <input type=\"checkbox\" name=\"acct_code4\" value=\"Virtual Terminal\"> Check to Display Virtual Terminal Entered Transaction Only.\n";
    print "                 (For transactions entered after Nov. 09, 2004)\n";
  }
  if ( $smps::chkprocessor ne "" ) {
    print " ACH Represent.: <input type=\"checkbox\" name=\"exclude_representment\" value=\"1\" checked> Check to Exclude Representment Transactions.\n";
  }
  if ( ( $smps::feature{'decryptflag'} == 1 ) || ( ( $smps::feature{'decryptallflag'} == 1 ) ) ) {
    print "    Decrypt CC#: <input type=\"checkbox\" id=\"decrypt\" name=\"decrypt\" value=\"yes\"> Check to Display Full CC#\n";
  }
  if ( $smps::reseller =~ /^(paynisc|payntel|siipnisc|siiptel|teretail|elretail)$/ ) {
    print "<input type=\"hidden\" name=\"display_acct\" value=\"yes\">\n";
  } else {
    my ($checked);
    if ( ( $smps::reseller =~ /^(cynergy|affinisc|lawpay)/ ) && ( $smps::username =~ /^(cyd|ap|ams|lp|law)/ ) ) {
      $checked = "checked";
    }
    print "  Acct. Code(s): <input type=\"checkbox\" name=\"display_acct\" value=\"yes\" $checked> Check to Display Acct. Code Info.\n";
    if ( $smps::username eq "disposal" ) {
      print "Split Acct Codes: <input type=\"checkbox\" name=\"splitacctcode\" value=\"yes\" checked> Check to split delimited Acct. Code Info. (Warning: Header Columns will no long line up.\n";
      print "Split Batch Date/Time: <input type=\"checkbox\" name=\"splitbtime\" value=\"yes\" checked> Check to split batch date/time.\n";
      print "Omit Footer: <input type=\"checkbox\" name=\"omitfooter\" value=\"yes\" checked> Check to omit footer on text output.\n";
    }
  }
  print "  Bank Response: <input type=\"checkbox\" name=\"display_errmsg\" value=\"yes\" > Check to include Bank Response.\n";
  print
    "         Format: <input type=\"radio\" name=\"format\" value=\"table\" checked> Table <input type=radio name=\"format\" value=\"text\"> Text <input type=\"radio\" name=\"format\" value=\"download\"> Download\n";
  print "   Summary Only: <input type=\"checkbox\" name=\"summaryonly\" value=\"yes\"> Check to Display Report Summary Only\n";

  if ( $ENV{'REMOTE_USER'} =~ /^(homeworkst1|homeworkst|powernetin|ruraltvofm)$/ ) {
    print "  Hide Previous: <input type=\"checkbox\" name=\"hide_previous\" value=\"yes\" checked> Check to hide previously viewed transactions.\n";
  }
  print
    " Submitted Date: <input type=\"checkbox\" name=\"batchtimeflg\" value=\"yes\"> Check to Query against date trans was sumbitted.  Default is Query against date tran was processed. Applicable for POSTAUTH and RETURNS Only.\n";
  print "\n";
  print "<input type=submit name=submit value=\"Submit Query\"> <input type=\"button\" value=\"Unlock\" disabled=\"disabled\" onClick=\"enableForm(this.form);\">\n";
  if ( $ENV{'SUBACCT'} ne "" ) {
    print "<input type=\"hidden\" name=\"subacct\" value=\"$ENV{'SUBACCT'}\">\n";
  }
  print "</b></pre>\n";
  print "</form>\n";

}

sub daily_report {
  my %cardtype_hash = %smps::cardarray;
  delete $cardtype_hash{'ach'};
  delete $cardtype_hash{'vsmc'};
  if ( $smps::processor ne "ncb" ) {
    delete $cardtype_hash{'kc'};
  } elsif ( $smps::processor !~ /^(pago|barclays)$/ ) {
    delete $cardtype_hash{'sw'};
    delete $cardtype_hash{'ma'};
  }

  my (%selected);
  if ( exists $smps::cookie{'query_settings'} ) {
    my ( $tz, $rembr ) = split( '\|', $smps::cookie{'query_settings'} );
    if ( $rembr eq "yes" ) {
      $selected{'remember'} = "checked";
    }
    if ( ( $smps::feature{'settletimezone'} eq "" ) && ( $tz ne "" ) ) {
      $smps::feature{'settletimezone'} = $tz;
    }
  }
  my ( $startdate, $enddate ) = @_;

  print "<tr>\n";
  print "  <td class=\"menuleftside\">&nbsp;</td>\n";
  print "  <td class=\"menurightside\"><hr width=400></td>\n";
  print "</tr>\n";

  print "<tr>\n";
  print "<td class=\"menuleftside\">Days End Reporting</td>\n";
  print "<td class=\"menurightside\">\n";
  if ( -e "/home/pay1/outagefiles/highvolume.txt" ) {
    print "Sorry, this program is not available at this time.<p>\n";
    print "Please try back in a little while.<p>\n";
    return;
  }
  print "<form action=\"$smps::path_cgi\" method=post onSubmit=\"return disableForm(this);\">";
  print "<input type=\"hidden\" name=\"settletimezone\" value=\"-5\">\n";
  print "<input type=hidden name=\"function\" value=\"dailyreport\">\n";
  print "<input type=hidden name=\"txntype\" value=\"auth\">\n";

  print "<pre><b>";

  print '    '
    . usernameSelect(
    { username   => $smps::username,
      login      => $smps::login,
      fieldName  => 'merchant',
      selectName => 'dailyreport_merchant'
    }
    )
    . "\n";

  my ( $select_mo, $select_dy, $select_yr ) = split( '/', $startdate );
  my $html = &miscutils::start_date( $select_yr, $select_mo, $select_dy );
  print "   First Day: $html ";
  print "<input type=\"hidden\" name=\"starthour\" value=\"00\"> ";
  print "\n";

  ( $select_mo, $select_dy, $select_yr ) = split( '/', $enddate );
  $html = &miscutils::end_date( $select_yr, $select_mo, $select_dy );
  print "    Last Day: $html ";

  my %timezonehash = ();
  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( time() );
  %timezonehash = %constants::timezones;

  print "\n";

  print
    "      Result: <input type=\"radio\" name=\"result\" value=\"\" checked> All <input type=\"radio\" name=\"result\" value=\"approved\"> Approved <input type=\"radio\" name=\"result\" value=\"declined\"> Declined\n";
  print
    "      Format: <input type=\"radio\" name=\"format\" value=\"table\" checked> Table <input type=\"radio\" name=\"format\" value=\"text\"> Text <input type=\"radio\" name=\"format\" value=\"download\"> Download\n";

  ####  Need to query both credit and checking

  print "<input type=\"hidden\" name=\"display_errmsg\" value=\"yes\">";
  print "<input type=\"hidden\" name=\"format\" value=\"aaatext\">";

  print "</b></pre>\n";
  print "<input type=submit name=submit value=\"Submit Query\"> <input type=\"button\" value=\"Unlock\" disabled=\"disabled\" onClick=\"enableForm(this.form);\">\n";
  if ( $ENV{'SUBACCT'} ne "" ) {
    print "<input type=\"hidden\" name=\"subacct\" value=\"$ENV{'SUBACCT'}\">\n";
  }
  print "</form>\n";
}

sub cardinput {
  &cardinput_new();
}

sub cardinput_new {
  print "<tr>\n";
  print "  <td class=\"menuleftside\">&nbsp;</td>\n";
  print "  <td class=\"menurightside\"><hr width=400></td>\n";
  print "</tr>\n";
  print "<tr>\n";
  print "  <td class=\"menuleftside\">Manual Authorizations &amp; Returns</td>\n";
  print "  <td class=\"menurightside\" style=\"font-weight: bold; font-size: .70em; padding: 15px;\">This feature was moved to the 'Virtual Terminal' section of your Merchant Administration Area.\n";
  print "</tr>\n";
  print "<tr>\n";
  print "  <td class=\"menuleftside\">&nbsp;</td>\n";
  print "  <td class=\"menurightside\"><hr width=400></td>\n";
  print "</tr>\n";
}

sub assemblebatch {

  my ( $sec, $min, $hour, $mday, $mon, $yyear, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 180 ) );
  my $earliest_yr = sprintf( "%04d", $yyear + 1900 );

  ( $sec, $min, $hour, $mday, $mon, $yyear, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 4 ) );
  my $startdate = sprintf( "%02d/%02d/%04d", $mon + 1, $mday, $yyear + 1900 );

  print "<tr>\n";
  print "<td class=\"menuleftside\">Assemble Batch</td>\n";
  print "<td class=\"menurightside\">\n";
  print "<form method=post action=\"$smps::path_assemble\" onSubmit=\"return disableForm(this);\">\n";
  print "<pre>";

  if ( -e "/home/pay1/outagefiles/highvolume.txt" ) {
    print "Sorry, this program is not available at this time.<p>\n";
    print "Please try back in a little while.<p>\n";
    print "<hr width=400>\n";
    return;
  }

  print "Note: To speed up the assemble batch process, please enter a recent start date.\n";
  print "<b>\n";
  print "<input type=hidden name=function value=assemble>\n";

  print "       "
    . usernameSelect(
    { username   => $smps::username,
      login      => $smps::login,
      fieldName  => 'merchant',
      selectName => 'merchant'
    }
    )
    . "\n";

  print "           Card: <select name=\"cardtype\">\n";
  print "<option value=\"\">All Cards\n";
  print "<option value=\"ax\">American Express\n";
  print "<option value=\"cb\">Carte Blanche\n";
  print "<option value=\"dc\">Diners Club\n";
  print "<option value=\"ds\">Discover\n";
  print "<option value=\"jcb\">Japanese Credit Bureau\n";
  if ( $smps::processor eq "ncb" ) {
    print "<option value=\"kc\">KeyCard</option>\n";
  }
  if ( $smps::processor =~ /^(pago|barclays)$/ ) {
    print "<option value=\"ma\">Maestro</option>\n";
  }
  print "<option value=\"mc\">MasterCard\n";
  print "<option value=\"vs\">Visa\n";
  if ( $smps::processor =~ /^(pago|barclays)$/ ) {
    print "<option value=\"sw\">Solo</option>\n";
  }
  print "<option value=\"ot\">Other</select>                <a href=\"help.html#assemble\" target=help>Help</a>\n";

  if ( $smps::achstatus eq "enabled" ) {
    print "      Acct Type: <select name=\"accttype\">\n";
    print "<option value=\"credit\"> Credit</option>\n";
    print "<option value=\"checking\"> Checking</option>\n";
    print "</select>\n";
  }

  my ( $select_mo, $select_dy, $select_yr, $html );
  ( $select_mo, $select_dy, $select_yr ) = split( '/', $startdate );
  $html = &miscutils::start_date( $select_yr, $select_mo, $select_dy, $earliest_yr );
  print "      First Day: $html\n";

  my %timezonehash = ();
  ( $sec, $min, $hour, $mday, $mon, $yyear, $wday, $yday, $isdst ) = localtime( time() );
  if ( $isdst == 1 ) {
    %timezonehash = %constants::daylighttimezones;
  } else {
    %timezonehash = %constants::timezones;
  }

  print "      Time Zone: <select name=\"settletimezone\">\n";
  print "      <option value=\"\"> Select Time Zone </option>\n";
  foreach my $timeshift ( sort numerically keys %timezonehash ) {
    print "      <option value=\"$timeshift\" ";
    if ( $timeshift == $smps::feature{'settletimezone'} ) {
      print "selected";
    }
    print "> $timezonehash{$timeshift} </option>\n";
  }
  print "    </select>\n";

  print "      Acct Code: <input type=text size=\"12\" maxlength=\"25\" name=\"acct_code\"> (optional<font size=\"-1\">-for recording only</font>)\n";
  print "Maximum transactions to display: <input type=text size=\"5\" name=\"maxcount\" value=\"100\"><br>\n";
  print "<input type=submit value=\"Begin Search\"> <input type=\"button\" value=\"Unlock\" disabled=\"disabled\" onClick=\"enableForm(this.form);\">\n";
  print "\n";
  print "</b></pre>\n";
  if ( $ENV{'SUBACCT'} ne "" ) {
    print "<input type=\"hidden\" name=\"subacct\" value=\"$ENV{'SUBACCT'}\">\n";
  }
  print "</form>\n";

  print "<hr width=400>\n";
}

sub querybatch {
  my ( $startdate, $enddate ) = @_;
  my ( $sec, $min, $hour, $mday, $mon, $yyear, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 4 ) );
  $startdate = sprintf( "%02d/%02d/%04d", $mon + 1, $mday, $yyear + 1900 );

  print "<tr>\n";
  print "<td class=\"menuleftside\">Review Batches</td>\n";
  print "<td class=\"menurightside\">\n";
  if ( -e "/home/pay1/outagefiles/highvolume.txt" ) {
    print "Sorry, this program is not available at this time.<p>\n";
    print "Please try back in a little while.<p>\n";
    return;
  }
  print "<form method=post action=\"$smps::path_cgi\" onSubmit=\"return disableForm(this);\">";
  print "<pre><b>\n";
  print "<input type=hidden name=function value=batchquery>\n";

  print "           "
    . usernameSelect(
    { username   => $smps::username,
      login      => $smps::login,
      fieldName  => 'merchant',
      selectName => 'querybatch_merchant'
    }
    )
    . "\n";

  my ( $select_mo, $select_dy, $select_yr, $html );
  ( $select_mo, $select_dy, $select_yr ) = split( '/', $startdate );
  $html = &miscutils::start_date( $select_yr, $select_mo, $select_dy );
  print "          First Day: $html \n";
  ( $select_mo, $select_dy, $select_yr ) = split( '/', $enddate );
  $html = &miscutils::end_date( $select_yr, $select_mo, $select_dy );
  print "           Last Day: $html \n";
  my %timezonehash = ();
  ( $sec, $min, $hour, $mday, $mon, $yyear, $wday, $yday, $isdst ) = localtime( time() );

  if ( $isdst == 1 ) {
    %timezonehash = %constants::daylighttimezones;
  } else {
    %timezonehash = %constants::timezones;
  }

  print "          Time Zone: <select name=\"settletimezone\">\n";
  print "      <option value=\"\"> Select Time Zone </option>\n";

  foreach my $timeshift ( sort numerically keys %timezonehash ) {
    print "      <option value=\"$timeshift\" ";
    if ( $timeshift == $smps::feature{'settletimezone'} ) {
      print "selected";
    }
    print "> $timezonehash{$timeshift} </option>\n";
  }
  print "    </select>\n";
  print
    "             Format: <input type=radio name=\"format\" value=\"table\" checked> Table <input type=radio name=\"format\" value=\"text\"> Text <input type=\"radio\" name=\"format\" value=\"download\"> Download\n";

  if ( $smps::achstatus eq "enabled" ) {
    print "          Acct Type: <select name=\"accttype\">\n";
    print "<option value=\"credit\"> Credit</option>\n";
    print "<option value=\"checking\"> Checking</option>\n";
    print "</select>\n";
  }
  print "\n";
  print "</b></pre>\n";
  print "<input type=submit value=\"Begin Search\"> <input type=\"button\" value=\"Unlock\" disabled=\"disabled\" onClick=\"enableForm(this.form);\">\n";
  if ( $ENV{'SUBACCT'} ne "" ) {
    print "<input type=\"hidden\" name=\"subacct\" value=\"$ENV{'SUBACCT'}\">\n";
  }
  print "</form>\n";

  print "<br>\n";
  print "<hr width=400>\n";
  print "</td>\n";
}

sub details_tail {
  if ( $ENV{'SERVER_NAME'} !~ /eci\-pay|connectnpay/i ) {
    print "<form method=post action=\"/admin/helpdesk.cgi\" target=ahelpdesk>\n";
    print
      "<input type=submit name=submit value=\"Help Desk\" onClick=\"window.open('','ahelpdesk','width=550,height=520,toolbar=no,location=no,directories=no,status=no,menubar=no,scrollbars=yes,resizable=yes'); return(true);\">\n";
    print "</form>\n";
  }

  print "</body>\n";
  print "</html>\n";
}

sub tail {
  my @now       = gmtime(time);
  my $copy_year = $now[5] + 1900;

  print "</td>\n";
  print "  </tr>\n";
  print "  </tbody>\n";
  print "</table>\n";

  print "<table width=\"760\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\" id=\"footer\">\n";
  print "  <tr>\n";
  print "    <td align=\"left\"><p><a href=\"/admin/logout.cgi\" title=\"Click to log out\">Log Out</a>";
  if ( $ENV{'SERVER_NAME'} !~ /(eci\-pay|connectnpay)/i ) {
    print " | <a href=\"javascript:change_win('/admin/helpdesk.cgi',600,500,'ahelpdesk')\">Help Desk</a>";
  }
  print " | <a id=\"close\" href=\"javascript:closewin();\" title=\"Click to close this window\">Close Window</a></p></td>\n";
  print "    <td align=\"right\"><p>\&copy; $copy_year, ";
  if ( $ENV{'SERVER_NAME'} =~ /plugnpay\.com/i ) {
    print "Plug and Pay Technologies, Inc.";
  } else {
    print "$ENV{'SERVER_NAME'}";
  }
  print "</p></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</body>\n";
  print "</html>\n";
}

sub batchuploadform {
  print "<tr>\n";
  print "<td class=\"menuleftside\">Upload Batch Files of Transactions</td>\n";
  print "<td class=\"menurightside\">This section is for the uploading of files containing multiple transactions and should not be confused with \"Batching Out\", which is a settlement process.<p>\n";

  print "<form method=post action=\"/admin/uploadbatch.cgi\" enctype=\"multipart/form-data\" onSubmit=\"return disableForm(this);\">\n";
  print "    <input type=hidden name=function value=batchupload>\n";
  print "<pre><b>";

  print "          "
    . usernameSelect(
    { username   => $smps::username,
      login      => $smps::login,
      fieldName  => 'merchant',
      selectName => 'batchuploadform_merchant'
    }
    )
    . "\n";

  print "              File: <input type=\"file\" name=\"data\">\n";
  print "     Email Address: <input type=\"text\" name=\"emailresults\" size=\"29\" maxlength=\"49\"> for batch results.\n";
  print "          Batch ID: <input type=\"text\" name=\"batchid\" size=\"29\" maxlength=\"29\"> No spaces please.\n";
  print "     Email Confirm: <select name=\"sndmail\">\n";
  print "      <option value=\"yes\">Yes for auths</option>\n";
  print "      <option value=\"no\" selected>No</option>\n";
  print "    </select> Choose yes to receive an email confirmation.\n";
  print "Result File Format: <select name=\"header_format\">\n";
  print "      <option value=\"\">no header</option>\n";
  print "      <option value=\"yes\" selected>incl. header</option>\n";
  print "      <option value=\"icverify\">IC Verify</option>\n";
  print "    </select>\n";
  print "\n";
  print "</b></pre>\n";
  print "<input type=submit value=\"Upload Batch File\"> <input type=\"button\" value=\"Unlock\" disabled=\"disabled\" onClick=\"enableForm(this.form);\">\n";
  print "<p>&bull; <a href=\"/new_docs/Upload_Batch_Instructions.htm\"><b>Documentation</b></a>\n";
  print "<br>&bull; <a href=\"/admin/uploadbatch.cgi\?function=listbatches\&merchant=$smps::merchant\"><b>Batch Results</b></a>\n";
  print "</form>\n";
  print "<br>\n";
  print "<hr width=400>\n";
  print "</td>\n";
}

sub storebatchfile {
  my $base_path = "/home/pay1/merchantbatch/";
  my $lock_file = $base_path . "lock";
  if ( -e $lock_file ) {
    print "Batches are currently being collected please wait 15 minutes then retry your batch upload.<br>\n";
    return;
  }
  my $id = PlugNPay::Transaction::TransactionProcessor::generateOrderID();
  $smps::username =~ s/[^0-9a-zA-Z]//g;
  my $filename     = $base_path . $smps::username . "." . $id . ".batch";
  my $data         = $smps::query->param('data');
  my @linearray    = ();
  my $initial_line = $smps::query->param('emailresults') . "|" . $smps::query->param('sndmail') . "|" . $smps::query->param('header_format') . "\n";
  push @linearray, $initial_line;

  while (<$data>) {
    push @linearray, $_;
  }
  $filename =~ s/[^a-zA-Z0-9\_\-\.\/]//g;
  &sysutils::filelog( "append", ">>$filename" );
  open( OUTFILE, ">>$filename" );
  foreach my $line (@linearray) {
    print OUTFILE $line;
  }
  close OUTFILE;

  if ( ( -e $filename ) && ( -s $filename ) && ( -T $filename ) ) {
    print "Batch uploaded successfully.<br>\n";
  } else {
    print "There was a problem uploading your batch please contact support.<br>\n";
    if ( !-T $filename ) {
      print "File is not a text file.<br>\n";
    }

    unlink $filename;
  }
}

sub chargeback {
  if ( -e "/home/pay1/outagefiles/highvolume.txt" ) {
    print "Sorry, this program is not available at this time.<p>\n";
    print "Please try back in a little while.<p>\n";
    return;
  }

  my ( $orderidold, %result );
  my (@orderidarray);

  my $form_txntype = "settled";
  my $txnstatus    = "success";

  my $cardtype   = $smps::query->param('cardtype');
  my $startdate  = $smps::query->param('startdate');
  my $enddate    = $smps::query->param('enddate');
  my $startyear  = $smps::query->param('startyear');
  my $startmonth = $smps::query->param('startmonth');
  my $startday   = $smps::query->param('startday');
  $startyear =~ s/[^0-9]//g;
  $startmonth =~ s/[^0-9]//g;
  $startday =~ s/[^0-9]//g;

  if ( ( $startyear >= 1999 ) && ( $startmonth >= 1 ) && ( $startmonth < 13 ) && ( $startday >= 1 ) && ( $startday < 32 ) ) {
    $startdate = sprintf( "%02d/%02d/%04d", $startmonth, $startday, $startyear );
  }

  my ( $m, $d, $y ) = split( /\//, $startdate );
  my $startdatestr = sprintf( "%04d%02d%02d", $y, $m, $d );

  if ( $startdatestr < $smps::earliest_date ) {
    $startdatestr = $smps::earliest_date;
  }

  if ( $startdatestr < "19990101" ) {
    my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 30 * 2 ) );
    my $twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
    $startdatestr = $twomonthsago;
  }

  my $endyear  = $smps::query->param('endyear');
  my $endmonth = $smps::query->param('endmonth');
  my $endday   = $smps::query->param('endday');
  $endyear =~ s/[^0-9]//g;
  $endmonth =~ s/[^0-9]//g;
  $endday =~ s/[^0-9]//g;
  if ( ( $endyear >= 1999 ) && ( $endmonth >= 1 ) && ( $endmonth < 13 ) && ( $endday >= 1 ) && ( $endday < 32 ) ) {
    $enddate = sprintf( "%02d/%02d/%04d", $endmonth, $endday, $endyear );
  }

  my $cardnumber = $smps::query->param('cardnumber');
  $cardnumber =~ s/[^0-9]//g;

  my $luhntest = &miscutils::luhn10($cardnumber);
  if ( $luhntest ne "success" ) {
    print "Invalid Credit Card Number<p>\n";
    return;
  }

  ( $m, $d, $y ) = split( /\//, $enddate );
  my $enddatestr = sprintf( "%04d%02d%02d", $y, $m, $d );

  if ( $enddatestr < 19980000 ) {
    $enddatestr = "20341231";
  }

  my $shortcard = substr( $cardnumber, 0, 4 ) . "**" . substr( $cardnumber, -2, 2 );

  my ( $shacardnumber, $firstflag );

  if ( $cardnumber ne "" ) {
    my ( %accounts, $shaflag );

    my $cc              = new PlugNPay::CreditCard($cardnumber);
    my @cardHashes      = $cc->getCardHashArray();
    my $cardHashSrchStr = "'" . join( "\'\,\'", @cardHashes ) . "'";

    my $dbh = &miscutils::dbhconnect( "pnpdata", "", "$smps::username" );    ## Trans_Log

    my $qstr = "select username,trans_date,orderid,shacardnumber ";
    $qstr .= "from trans_log FORCE INDEX(tlog_tdatesha_idx) where trans_date>='$startdatestr' and trans_date<='$enddatestr'";

    if ( ( exists $smps::altaccts{$smps::username} ) && ( $ENV{'SUBACCT'} ne "" ) ) {
      my ($temp);
      foreach my $var ( @{ $smps::altaccts{$smps::username} } ) {
        $temp .= "'$var',";
        $accounts{$var} = 1;
      }
      chop $temp;
      $qstr .= " and username IN ($temp) ";
    } else {
      $qstr .= " and username='$smps::username' ";
    }
    $qstr .= "and shacardnumber IN ($cardHashSrchStr) order by trans_date,orderid";

    my ( $checkusername, $trans_date, $orderid, $chkshacardnumber );
    my $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
    $sth->execute or die "Can't execute: $DBI::errstr";
    my $rv = $sth->bind_columns( undef, \( $checkusername, $trans_date, $orderid, $chkshacardnumber ) );

    while ( $sth->fetch ) {
      if ( ( $checkusername eq $smps::username ) || ( exists $accounts{$checkusername} ) ) {
        if ( $cc->compareHash($chkshacardnumber) ) {
          if ( $shaflag != 1 ) {
            @orderidarray = ($orderid);
          } else {
            $orderidarray[ ++$#orderidarray ] = "$orderid";
          }
          $shaflag = 1;
        } elsif ( $shaflag != 1 ) {
          $orderidarray[ ++$#orderidarray ] = "$orderid";
        }
      }
    }
    $sth->finish;
    $dbh->disconnect;

    if ( $shaflag == 1 ) {
      print "<b>The following were exact matches of the credit card number entered.</b><br>\n";
    } else {
      print "<b>An exact card match could not be found.</b><br>\n";
    }

  }

  if ( $firstflag == 0 ) {
    print "<table border=1 cellspacing=0 cellpadding=2>\n";
    print "<tr>\n";
    print "<th align=left>Type</th>";
    print "<th align=left>Name</th>";
    print "<th align=left>Status</th>";
    print "<th align=left>Order ID</th>";
    print "<th>Transaction Time <font size=-2>(GMT)<br>MM/DD/YYYY HH:MM:SS</font></th>";
    print "<th align=left>Card<br>Number</th>";
    print "<th align=left>Exp</th>";
    print "<th align=left>Amount</th>\n";
    print "<th align=left>Auth<br>Code</th>\n";

    $firstflag = 1;
  }

  my $starttime = $startdatestr . "000000";
  my $endtime   = $enddatestr . "000000";
  my $i         = 0;
  foreach my $vorderid ( sort @orderidarray ) {
    if ( ( $vorderid eq $orderidold ) && ( $vorderid ne "" ) ) {
      next;
    }
    if ( ( $smps::username eq "icommerceg" ) && ( $ENV{'SUBACCT'} ne "" ) ) {
      my ( $maxidx, $i );
      if ( exists $smps::altaccts{$smps::username} ) {
        foreach my $var ( @{ $smps::altaccts{$smps::username} } ) {
          my %res_icg = &miscutils::sendmserver( "$var", 'query', 'order-id', "$vorderid", 'start-time', "$starttime", 'txn-type', "$form_txntype", 'txn-status', "$txnstatus", 'end-time', "$endtime" );

          foreach my $key ( keys %res_icg ) {
            $i++;
            $result{"a$i"} = $res_icg{$key};
          }
        }
      }
    } else {
      %result = &miscutils::sendmserver( "$smps::username", 'query', 'order-id', "$vorderid", 'start-time', "$starttime", 'txn-type', "$form_txntype", 'txn-status', "$txnstatus", 'end-time', "$endtime" );
    }
    my @values = values %result;
    foreach my $var ( sort @values ) {

      my %res2 = ();
      my @nameval = split( /&/, $var );
      foreach my $temp (@nameval) {
        my ( $name, $value ) = split( /=/, $temp );
        $res2{$name} = $value;
      }

      if ( $res2{'time'} ne "" ) {
        my $time = $res2{"time"};

        my $timestr = substr( $time, 4, 2 ) . "/" . substr( $time, 6, 2 ) . "/" . substr( $time, 0, 4 ) . " ";
        $timestr = $timestr . substr( $time, 8, 2 ) . ":" . substr( $time, 10, 2 ) . ":" . substr( $time, 12, 2 );

        my $txntype = $res2{"txn-type"};
        my $origin  = $res2{"origin"};
        my $status  = $res2{"txn-status"};
        my $orderid = $res2{"order-id"};
        $time = $res2{"time"};
        my $cardnumber = $res2{"card-number"};
        my $exp        = $res2{"card-exp"};
        my $amount     = $res2{"amount"};
        my $authcode   = substr( $res2{"auth-code"}, 0, 6 );
        my $cardname   = $res2{'card-name'};
        my $acctcode   = $res2{'acct_code'};
        my $acctcode2  = $res2{'acct_code2'};
        my $acctcode3  = $res2{'acct_code3'};
        my $acctcode4  = $res2{'acct_code4'};
        my $trans_date = substr( $time, 0, 8 );

        my ( $dummy, $price ) = split( / /, $amount );
        $cardnumber = substr( $cardnumber, 0, 27 );
        my ($strtstrg);
        if ( $smps::merchant ne "" ) {
          $strtstrg = "\&merchant=$smps::merchant";
        }
        print "<tr>";
        print "<td>$txntype</td>\n";
        print "<td>$cardname</td>\n";
        print "<td>$status</td>\n";
        print "<td><a href=\"$smps::path_cgi\?function=chrgbckdetails&orderid=$orderid\&trans_date=$trans_date$strtstrg\">$orderid</a></td>\n";
        print "<td align=center>$timestr</td>\n";
        print "<td>$cardnumber</td>\n";
        print "<td>$exp</td>\n";

        if ( $txntype !~ /ret/ ) {
          print "<td>$amount</td>\n";
        } else {
          print "<td><font color=\"#ff0000\">($amount)</font></td>\n";
        }
        print "<td>$authcode</td>\n";
        print "\n";
      }
    }
    $orderidold = $vorderid;
  }
  print "</table>\n";
  print "<br>\n";

  print "</table>\n";
  &tail();
  return;
}

sub chrgbckdetails {
  my ( %result,    $chkusername, %trans_date, $report_line );
  my ( $txntype,   $origin,      $status,     $cardnumber, $card_exp, $amount, $auth_code );
  my ( $card_name, $card_addr,   $card_city,  $card_state, $card_zip, $card_country, $avs_code, $cvvresp );
  my ( $phone,     $fax,         $email,      $ipaddress );
  my ( $acct_code, $acct_code2, $acct_code3, $acct_code4, $timestr );
  my ( $dummy,     $dummy2,     $trans_date, $trans_time, $endtime );

  $trans_date = $smps::query->param('trans_date');
  my $form_txntype = $smps::query->param('txntype');
  my $txnstatus    = $smps::query->param('txnstatus');

  my $orderid = $smps::query->param('orderid');

  my $time = &miscutils::gendatetime( -$trans_date );
  ( $dummy, $trans_date, $trans_time ) = &miscutils::gendatetime( $time - ( 60 * 24 * 3600 ) );
  my $starttime = $trans_time;
  ( undef, $endtime ) = &miscutils::gendatetime_only();

  my $i = 0;
  if ( ( $smps::username eq "icommerceg" ) && ( exists $smps::altaccts{$smps::username} ) ) {
    my ( $maxidx, $i );
    foreach my $var ( @{ $smps::altaccts{$smps::username} } ) {
      my %res_icg = &miscutils::sendmserver( "$var", 'query', 'order-id', "$orderid", 'start-time', "$starttime", 'txn-type', "$form_txntype", 'txn-status', "$txnstatus" );

      foreach my $key ( keys %res_icg ) {
        $i++;
        $result{"a$i"} = $res_icg{$key};
      }
      if ( $i > 1 ) {
        $chkusername = $var;
        last;
      }
    }
  } else {
    %result = &miscutils::sendmserver( "$smps::username", 'query', 'order-id', "$orderid", 'start-time', "$starttime", 'txn-type', "$form_txntype", 'txn-status', "$txnstatus", 'end-time', "$endtime" );
    $chkusername = $smps::username;
  }
  my @values = values %result;
  foreach my $var ( sort @values ) {
    my %res2 = ();
    my @nameval = split( /&/, $var );
    foreach my $temp (@nameval) {
      my ( $name, $value ) = split( /=/, $temp );
      $res2{$name} = $value;
    }

    if ( $res2{'time'} ne "" ) {
      my $time = $res2{"time"};

      my $timestr = substr( $time, 4, 2 ) . "/" . substr( $time, 6, 2 ) . "/" . substr( $time, 0, 4 ) . " ";
      $timestr = $timestr . substr( $time, 8, 2 ) . ":" . substr( $time, 10, 2 ) . ":" . substr( $time, 12, 2 );

      $txntype      = $res2{"txn-type"};
      $origin       = $res2{"origin"};
      $status       = $res2{"txn-status"};
      $orderid      = $res2{"order-id"};
      $cardnumber   = $res2{"card-number"};
      $cardnumber   = substr( $cardnumber, 0, 27 );
      $card_exp     = $res2{'card-exp'};
      $amount       = $res2{"amount"};
      $auth_code    = substr( $res2{"auth-code"}, 0, 6 );
      $card_name    = $res2{'card-name'};
      $card_addr    = $res2{'card-adress1'};
      $card_city    = $res2{'card-city'};
      $card_state   = $res2{'card-state'};
      $card_zip     = $res2{'card-zip'};
      $card_country = $res2{'card-country'};
      $avs_code     = $res2{'avs-code'};
      $cvvresp      = $res2{'cvvresp'};

      $acct_code  = $res2{'acct_code'};
      $acct_code2 = $res2{'acct_code2'};
      $acct_code3 = $res2{'acct_code3'};
      $acct_code4 = $res2{'acct_code4'};
      $trans_date{$txntype} = substr( $time, 0, 8 );
      my ( $dummy, $price ) = split( / /, $amount );
      if ( $txntype =~ /return/ ) {
        my $txnlabel = "<font color=\"red\">Credit Issued</font>";
      }
      $report_line .= "<tr><td>$txntype</td><td>$status</td><td>$amount</td><td align=center>$timestr GMT</td><tr>\n";
    }
  }

  my $qstr = "select authtime,postauthtime,returntime,username,acct_code2,amount,enccardnumber,length,subacct,card_name,";
  $qstr .= "card_exp,auth_code,avs,cvvresp,card_addr,card_city,card_state,card_zip,card_country ";
  $qstr .= "from operation_log where (substr(postauthtime,0,8)='$trans_date' or substr(authtime,0,8)='$trans_date') ";
  $qstr .= "and orderid='$orderid' ";
  $qstr .= "and username='$smps::username' ";

  my $dbh = &miscutils::dbhconnect( "pnpdata", "", "$chkusername" );    ## OrdersSummary

  my $sth = $dbh->prepare(
    qq{
        select phone,fax,email,ipaddress,card_addr,card_city,card_state,card_zip,card_country
        from ordersummary
        where orderid=?
        and trans_date=?
        and username=?
  }
  );
  $sth->execute( "$orderid", "$trans_date{'auth'}", "$chkusername" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr" );
  ( $phone, $fax, $email, $ipaddress, $card_addr, $card_city, $card_state, $card_zip, $card_country ) = $sth->fetchrow;
  $sth->finish;

  $dbh->disconnect;

  my $dbh_merch = &miscutils::dbhconnect("merch_info");
  my $sth_info  = $dbh_merch->prepare(
    qq{
      select sitename
      from profile
      where username=? and site=?
      }
    )
    or &miscutils::errmaildie( __LINE__, __FILE__, "Can't prepare: $DBI::errstr" );
  $sth_info->execute( "$smps::username", "$acct_code2" ) or die "Can't execute: $DBI::errstr";
  my ($sitename) = $sth_info->fetchrow;
  $sth_info->finish;
  $dbh_merch->disconnect;

  $auth_code = substr( $auth_code, 0, 6 );

  print "<div align=\"center\">\n";
  print "<table border=1 cellspacing=0 cellpadding=2>\n";
  print "<tr><th colspan=2>Retrieval Request Form</th></tr>\n";
  print "<tr><th align=left>Date & Time:</th><td>$timestr GMT</td></tr>\n";
  print "<tr><th align=left>Transaction ID:</th><td>$orderid</td></tr>\n";
  print "<tr><th align=left>Amount:</th><td>$amount</td></tr>\n";
  print "<tr><th align=left>Card Name:</th><td>$card_name</td></tr>\n";
  print "<tr><th align=left>Card Number:</th><td>$cardnumber</td></tr>\n";
  print "<tr><th align=left>Exp. Date:</th><td>$card_exp</td></tr>\n";

  print "<tr><th align=left>Auth. Code:</th><td>$auth_code</td></tr>\n";
  print "<tr><th align=left>AVS Code:</th><td>$avs_code</td></tr>\n";
  print "<tr><th align=left>CCV2 Response:</th><td>$cvvresp</td></tr>\n";

  if ( $sitename ne "" ) {
    print "<tr><th align=left>Site Name:</th><td colspan=1>$sitename</td></tr>\n";
  }

  print "<tr><th align=left>\n";
  print "Address:</th><td colspan=1>$card_addr<br>$card_city, $card_state  $card_zip<br>$card_country</td></tr>\n";
  if ( $phone ne "" ) {
    print "<tr><th align=left>Phone:</th><td colspan=1>$phone</td></tr>\n";
  }
  print "<tr><th align=left>Email:</th><td colspan=1>$email</td></tr>\n";
  print "<tr><th align=left>IP Address:</th><td colspan=1>$ipaddress</td></tr>\n";
  print "</table>\n";
  print "<p><table border=1 cellspacing=0 cellpadding=2>\n";
  print "<tr><th colspan=4>TRANSACTION HISTORY</th></tr>\n";
  print "<tr><th>Txn Type</th><th>Status</th><th>Amount</th><th>Date & Time</th></tr>\n";
  print "$report_line\n";
  print "</table>\n";
  print "</div>\n";
}

sub sort_hash {
  my $x     = shift;
  my %array = %$x;
  sort { $array{$a} cmp $array{$b}; } keys %array;
}

sub chargeback_import {
  require MD5;
  my ( %merchdata, %data_error );
  my ( $today,     $time ) = &miscutils::gendatetime_only();
  my ( $sec,       $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( time() );
  $today = sprintf( "%04d%02d%02d", $year + 1900, $mon + 1, $mday );
  $time = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec );

  $smps::username = $ENV{'REMOTE_USER'};
  $smps::username =~ s/[^0-9a-zA-Z]//g;
  $smps::login = $ENV{'LOGIN'};
  $smps::login =~ s/[^0-9a-zA-Z]//g;

  $smps::dbh1 = &miscutils::dbhconnect("fraudtrack");
  $smps::dbh  = &miscutils::dbhconnect("pnpmisc");

  my $gatewayAccount = new PlugNPay::GatewayAccount($smps::username);
  $smps::processor = $gatewayAccount->getCardProcessor();

  my $filename = $smps::query->param('data');

  my ( @fields, %data, $parseflag );
  while (<$filename>) {
    if ( substr( $_, -1 ) eq "\n" ) {
      chop;
    }
    my $linetest = $_;
    $linetest =~ s/^W//g;
    if ( length($linetest) < 1 ) {
      next;
    }

    my @data = split('\t');

    if ( substr( $data[0], 0, 1 ) eq "\!" ) {
      $parseflag = 1;
      (@fields) = (@data);
      $fields[0] = substr( $data[0], 1 );
      next;
    }

    if ( $parseflag == 1 ) {
      %merchdata = ();
      my $i = 0;
      foreach my $var (@fields) {
        $var =~ tr/A-Z/a-z/;
        $var =~ s/\W//g;
        $merchdata{$var} = $data[$i];
        $merchdata{$var} =~ s/[^a-zA-Z0-9_\.\/\@:\-\ ]//g;
        $i++;
      }

      # Data Filters

      # Cardnumber filter
      $merchdata{'cardnumber'} =~ s/[^0-9]//g;
      $merchdata{'cardnumber'} =~ /([1-9].*)/;
      $merchdata{'cardnumber'} = $1;

      # Transaction Date Filter
      if ( $merchdata{'trans_date'} =~ /\// ) {
        my ( $mo, $dy, $yr ) = split( '/', $merchdata{'trans_date'} );
        $mo = sprintf( "%02d", $mo );
        $dy = sprintf( "%02d", $dy );
        $yr = substr( $yr, -2 );
        $yr = sprintf( "%04d", 2000 + $yr );
        $merchdata{'trans_date'} = $yr . $mo . $dy;
      }

      # post_date Filter
      if ( $merchdata{'post_date'} =~ /\// ) {
        my ( $mo, $dy, $yr ) = split( '/', $merchdata{'post_date'} );
        $mo = sprintf( "%02d", $mo );
        $dy = sprintf( "%02d", $dy );
        $yr = substr( $yr, -2 );
        $yr = sprintf( "%04d", 2000 + $yr );
        $merchdata{'post_date'} = $yr . $mo . $dy;
      }

      # Amount Filter
      $merchdata{'amount'} =~ s/[^0-9\.]//g;
      $merchdata{'amount'} = sprintf( "%.2f", $merchdata{'amount'} );

      if ( exists $merchdata{'orderid'} ) {
        $merchdata{'orderid'} =~ s/[^0-9]//g;
      }

      $merchdata{'username'} = $ENV{'REMOTE_USER'};

      my ( $error, $errvar ) = &cb_input_check( \%merchdata );

      my $cardtype = &miscutils::cardtype("$merchdata{'cardnumber'}");

      $merchdata{'cardtype'} = $cardtype;

      my @shaArray = ();
      if ( $merchdata{'cardnumber'} ne "" ) {
        my $cc              = new PlugNPay::CreditCard( $merchdata{'cardnumber'} );
        my @cardHashes      = $cc->getCardHashArray();
        my $cardHashSrchStr = "'" . join( "\'\,\'", @cardHashes ) . "'";
        $merchdata{'cardHashSrchStr'} = $cardHashSrchStr;
      }

      if ( $error > 0 ) {
        $data_error{ $merchdata{'cardnumber'} } = $errvar;
        next;
      }

      if ( $fields[0] =~ /chargeback/i ) {
        &query_chargeback_old( \%merchdata );
      }
    }
  }
  $smps::dbh1->disconnect;
  $smps::dbh->disconnect;

  if ( $parseflag == 1 ) {
    my $message = "File Has Been Uploaded and Imported into Database";
    my $i       = 1;
    foreach my $key ( keys %data_error ) {
      if ( $i == 1 ) {
        $message .= "<br>There was a problem with the following record(s).\n";
        $message .= "They were missing the following mandatory information.<br>\n";
      }
      $message .= "$i: $key: $data_error{$key}<br>\n";
      $i++;
    }
    $message = "<p align=left>$message</p>";
    print "$message";
  } else {
    my $message = "Sorry Improper File Format";
    $message = "<p align=left>$message</p>";
    print "$message";
  }
}

sub query_chargeback_old {
  my ($data) = @_;
  my $found = 0;
  my ( %found, %merchdata );
  if ( ( $$data{'orderid'} ne "" ) && ( $$data{'shacardnumber'} eq "" ) ) {
    my $timeadjust = ( 90 * 24 * 3600 );
    my ( $dummy1, $startdate, $timestr ) = &miscutils::gendatetime("-$timeadjust");

    if ( $startdate < $smps::earliest_date ) {
      $startdate = $smps::earliest_date;
    }

    my $qstr = "select subacct,substr(amount,5),orderid,trans_date,card_country,card_number ";
    $qstr .= "from trans_log ";
    $qstr .= "where trans_date>='$startdate' ";
    $qstr .= "and username='$$data{'username'}' ";
    $qstr .= "and orderid='$$data{'orderid'}' ";
    if ( $$data{'subacct'} ne "" ) {
      $qstr .= "and subacct='$$data{'subacct'}' ";
    }
    $qstr .= "and operation IN ('auth','forceauth') ";
    $qstr .= "and finalstatus='success' ";

    my ( $subacct, $amount, $orderid, $trans_date, $card_country, $card_number );
    my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime( time() );
    my $date = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

    my $sth_billing = $smps::dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
    $sth_billing->execute() or die "Can't execute: $DBI::errstr";
    my $rv = $sth_billing->bind_columns( undef, \( $subacct, $amount, $orderid, $trans_date, $card_country, $card_number ) );

    while ( $sth_billing->fetch ) {
      if ( !exists $found{$orderid} ) {
        $merchdata{'cardtype'} = &miscutils::cardtype("$card_number");
        &insert_chargeback( $$data{'username'}, $subacct, $orderid, $trans_date, $$data{'post_date'}, $amount, $card_country, $merchdata{'cardtype'}, $$data{'returnflag'} );
        $found = 1;
        $found{$orderid} = 1;
        last;
      }
    }
    $sth_billing->finish;

    if ( $found != 1 ) {
      print "TRAN NOT FOUND: ORDERID:$$data{'orderid'}, DATE:$$data{'trans_date'}, AMT:$amount<br>\n";
    }

    return;
  }

  my $trans_time = &miscutils::strtotime( $$data{'trans_date'} );
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $trans_time - ( 240 * 3600 ) );
  my $startdate = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
  ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $trans_time + ( 48 * 3600 ) );
  my $enddate = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

  my $date = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

  if ( $startdate < $smps::earliest_date ) {
    $startdate = $smps::earliest_date;
  }

  my ( $subacct, $amount, $orderid, $trans_date, $card_country );
  my ($sth_billing);

  $smps::processor = "FDFDFDF";    ###  Remove when op_log has index on shacardnumber

  if ( $smps::processor =~ /^(fdms|visanet|paytechtampa)$/ ) {
    my $now = localtime( time() );
    $sth_billing = $smps::dbh->prepare(
      qq{
        select subacct,substr(amount,5),orderid,trans_date,card_country
        from operation_log
        where trans_date>='$startdate'
        and trans_date<='$enddate'
        and username='$$data{'username'}'
        and shacardnumber IN ($$data{'cardHashSrchStr'})
        and substr(amount,5)='$$data{'amount'}'
        and postauthstatus='success'
        }
      )
      or die "Can't do: $DBI::errstr";
    $sth_billing->execute() or die "Can't execute: $DBI::errstr";
  } else {
    $sth_billing = $smps::dbh->prepare(
      qq{
        select subacct,substr(amount,5),orderid,trans_date,card_country
        from trans_log
        where shacardnumbee IN ($$data{'cardHashSrchStr'})
        and trans_date>='$startdate'
        and trans_date<='$enddate'
        and username='$$data{'username'}'
        and operation IN ('auth','forceauth')
        and substr(amount,5)='$$data{'amount'}'
        and finalstatus='success'
        }
      )
      or die "Can't do: $DBI::errstr";
    $sth_billing->execute() or die "Can't execute: $DBI::errstr";
  }
  my $rv = $sth_billing->bind_columns( undef, \( $subacct, $amount, $orderid, $trans_date, $card_country ) );
  while ( $sth_billing->fetch ) {
    if ( !exists $found{$orderid} ) {
      &insert_chargeback( $$data{'username'}, $subacct, $orderid, $trans_date, $$data{'post_date'}, $amount, $card_country, $merchdata{'cardtype'} );
      &insert_fraud( $$data{'username'}, $$data{'cardnumber'} );
      $found = 1;
      $found{$orderid} = 1;
      last;
    }
  }
  $sth_billing->finish;

  my $now = localtime( time() );
  if ( $found != 1 ) {
    my ( $subacct, $amount, $orderid, $trans_date, $card_country );
    if ( $smps::processor eq "fdms" ) {
      my $now = localtime( time() );
      print "START OPLOG QUERY 2: $now<br>\n";
      $sth_billing = $smps::dbh->prepare(
        qq{
          select subacct,substr(amount,5),orderid,trans_date,card_country
          from operation_log
          where trans_date between '$startdate' and '$enddate'
          and username='$$data{'username'}'
          and shacardnumber IN ($$data{'cardHashSrchStr'})
          and postauthstatus='success'
          }
        )
        or die "Can't do: $DBI::errstr";
      $sth_billing->execute() or die "Can't execute: $DBI::errstr";
    } else {
      print "START TRANLOG QUERY 2: $now<br>\n";
      $sth_billing = $smps::dbh->prepare(
        qq{
          select subacct,substr(amount,5),orderid,trans_date,card_country
          from trans_log
          where shacardnumbee IN ($$data{'cardHashSrchStr'})
          and trans_date>='$startdate'
          and trans_date<='$enddate'
          and username='$$data{'username'}'
          and operation IN ('auth','forceauth')
          and finalstatus='success'
          }
        )
        or die "Can't do: $DBI::errstr";
      $sth_billing->execute() or die "Can't execute: $DBI::errstr";
    }
    my $rv = $sth_billing->bind_columns( undef, \( $subacct, $amount, $orderid, $trans_date, $card_country ) );
    while ( $sth_billing->fetch ) {
      if ( !exists $found{$orderid} ) {
        &insert_chargeback( $$data{'username'}, $subacct, $orderid, $trans_date, $$data{'post_date'}, $amount, $card_country, $merchdata{'cardtype'} );
        &insert_fraud( $$data{'username'}, $$data{'cardnumber'} );
        $found = 1;
        $found{$orderid} = 1;
        last;
      }
    }
    $sth_billing->finish;
    my $now = localtime( time() );
  }

  if ( $found != 1 ) {
    print "TRAN NOT FOUND: CARD:$$data{'cardnumber'}, DATE:$$data{'trans_date'}, AMT:$amount<br>\n";
  }
}

sub insert_chargeback {
  my ( $username, $subacct, $orderid, $trans_date, $post_date, $amount, $card_country, $cardtype, $returnflag ) = @_;
  my ( $date, $time ) = &miscutils::gendatetime_only();

  $card_country =~ tr/a-z/A-Z/;

  print "INCB UN:$username:$subacct:, OID:$orderid, CO:$card_country, CT:$cardtype<br>\n";

  my $sth = $smps::dbh1->prepare(
    qq{
        select username
        from chargeback
        where username='$username' and orderid='$orderid' and subacct='$subacct'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr" );
  $sth->execute or die "Can't execute: $DBI::errstr";
  my ($test) = $sth->fetchrow;
  $sth->finish;

  if ( $test ne "" ) {
    print " Transaction already in Chargeback database. <br>\n";
  } else {
    my $sth = $smps::dbh1->prepare(
      qq{
        insert into chargeback
        (username,orderid,trans_date,subacct,post_date,entered_date,amount,cardtype,country,returnflag)
        values (?,?,?,?,?,?,?,?,?,?)
        }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr" );
    $sth->execute( "$username", "$orderid", "$trans_date", "$subacct", "$post_date", "$date", "$amount", "$cardtype", "$card_country", "$returnflag" ) or die "Can't execute: $DBI::errstr";
    $sth->finish;
  }

}

sub insert_fraud {

  my ( $username, $cardnumber ) = @_;

  my $reason = "Chargeback";

  my ( $now, $trans_time ) = &miscutils::gendatetime_only();

  my $md5 = new MD5;
  $md5->add($cardnumber);
  my $cardnumber_md5 = $md5->hexdigest();
  $cardnumber = substr( $cardnumber, 0, 4 ) . '**' . substr( $cardnumber, length($cardnumber) - 2, 2 );

  my $sth = $smps::dbh->prepare(
    qq{
    select enccardnumber,trans_date,card_number
    from fraud
    where enccardnumber='$cardnumber_md5'
  }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %$smps::query );
  $sth->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %$smps::query );
  my ( $test, $orgdate, $cardnumber1 ) = $sth->fetchrow;
  $sth->finish;

  if ( $test ne "" ) {
    print " Transaction already in Fraud database. <br>\n";
  } else {
    my $sth_insert = $smps::dbh->prepare(
      qq{
      insert into fraud
      (enccardnumber,username,trans_date,descr,card_number)
      values (?,?,?,?,?)
    }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %$smps::query );
    $sth_insert->execute( "$cardnumber_md5", "$username", "$now", "$reason", "$cardnumber" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %$smps::query );
    $sth_insert->finish;
    print "INSERTING FRAUD UN:$smps::username, CC:$cardnumber<br>\n";
  }
}

sub cb_input_check {
  my ($query) = @_;
  my ( $error, $errvar );

  my @check = ( 'amount', 'post_date' );

  if ( $$query{'orderid'} eq "" ) {
    @check = ( @check, 'cardnumber', 'trans_date' );
  }

  my $errhdr = "MissingValues,";

  foreach my $var (@check) {
    my $val = $$query{$var};
    $val =~ s/[^a-zA-Z0-9]//g;
    my $tst = length($val);
    if ( $tst < 1 ) {
      $error = 1;
      $errvar .= "$var,";
    }
  }

  if ( $errvar ne "" ) {
    $errvar = $errhdr . $errvar;
  }

  if ( ( $$query{'cardnumber'} !~ /\*\*/ ) && ( $$query{'cardnumber'} ne "" ) ) {
    my $CCtest = $$query{'cardnumber'};
    $CCtest =~ s/[^0-9]//g;
    my $luhntest = &miscutils::luhn10($CCtest);
    if ( $luhntest eq "failure" ) {
      $error = 1;
      $errvar .= ":InvalidCardnumber,$CCtest";
    }
  }
  return $error, $errvar;
}

sub response_page {
  print header( -type => 'text/html' );    ### DCP 20100719

  my ( $message, $close ) = @_;

  my ($autoclose);

  print "<html>\n";
  print "<Head>\n";
  print "<title>Response Page</title>\n";
  print "<link href=\"/_css/admin/smps.css\" type=\"text/css\" rel=\"stylesheet\">\n";

  print "<script Language=\"Javascript\">\n";
  print "<\!-- Start Script\n";
  print "function closeresults() {\n";
  print "  resultsWindow = window.close(\"results\");\n";
  print "}\n\n";
  print "// end script-->\n";
  print "</script>\n";

  print "</head>\n";

  if ( $close eq "auto" ) {
    $autoclose = "onLoad=\"update_parent();\"\n";
  } elsif ( $close eq "relogin" ) {
    $autoclose = "onLoad=\"update_parent1();\"\n";
  }

  print "<body bgcolor=\"#ffffff\" $autoclose>\n";
  print "<table border=\"0\" cellspacing=\"0\" cellpadding=\"1\" width=\"500\">\n";
  print "<tr><td align=\"center\" colspan=\"4\"><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corporate Logo\"></td></tr>\n";
  print "<tr><td align=\"center\" colspan=\"4\" class=\"larger\" bgcolor=\"#000000\"><font color=\"#ffffff\">Reseller Administration Area</font></td></tr>\n";
  print "<tr><td align=\"center\" colspan=\"4\"><img src=\"/images/icons.gif\" alt=\"The PowertoSell\"></td></tr>\n";
  print "<tr><td>&nbsp;</td><td>&nbsp;</td><td colspan=2>&nbsp;</td></tr>\n";
  print "<tr><td colspan=\"4\">$message</td></tr>\n";
  print "</table>\n";

  if ( $close eq "yes" ) {
    print "<p><div align=\"center\"><a href=\"javascript:update_parent();\">Close Window</a></div>\n";
  }

  print "</body>\n";
  print "</html>\n";
  return;
}

sub response_message {
  my ( $message, $close ) = @_;
  my ($autoclose);

  if ( $smps::header_printed ne "yes" ) {    ## DCP 20110112
    print header( -type => 'text/html' );
  }

  if ( $close eq "auto" ) {
    $autoclose = "onLoad=\"update_parent();\"\n";
  } elsif ( $close eq "relogin" ) {
    $autoclose = "onLoad=\"update_parent1();\"\n";
  }

  print "<script Language=\"Javascript\">\n";
  print "<\!-- Start Script\n";

  print "function closeresults() {\n";
  print "  resultsWindow = window.close(\"results\");\n";
  print "}\n\n";

  print "// end script-->\n";
  print "</script>\n";
  print "<div align=\"center\">\n";
  print "<table border=\"0\" cellspacing=\"0\" cellpadding=\"1\" width=\"500\">\n";
  print "<tr><td colspan=\"4\">$message</td></tr>\n";
  print "</table>\n";
  print "</div>\n";

  if ( $close eq "yes" ) {
    print "<p><div align=\"center\"><a href=\"javascript:update_parent();\">Close Window</a></div>\n";
  }

  print "</body>\n";
  print "</html>\n";
  return;
}

sub overview {
  my ( $reseller, $merchant ) = @_;

  my $env      = new PlugNPay::Environment($reseller);
  my $features = $env->getFeatures();

  if ( $features->get('overview_seclevel') ) {
    $smps::reseller_feature{'overview_seclevel'} = $features->get('overview_seclevel');
  }

  my $linked_overview_accts = $features->get('linked_overview_accts');
  my @linked_accts = split( /\|/, $linked_overview_accts );
  push( @linked_accts, $reseller );

  my $private  = new PlugNPay::GatewayAccount::Private();
  my $accounts = $private->queryAllAccounts(
    { 'reseller' => {
        'operator' => 'IN',
        'values'   => \@linked_accts
      },
      'username' => $merchant,
      'status'   => {
        'operator' => '<>',
        'value'    => 'cancelled'
      }
    },
    {}
  );

  my $db_merchant;
  if ( @{$accounts} > 0 ) {
    $db_merchant = $accounts->[0]->getGatewayAccountName();
  }

  return $db_merchant;
}

sub merchlist {
  my ($reseller) = @_;
  my ( $db_merchant, @merchlist );

  my $private = new PlugNPay::GatewayAccount::Private();
  if ( $reseller eq "cableand" ) {
    my $accounts = $private->queryAllAccounts(
      { 'reseller' => {
          'operator' => 'IN',
          'values'   => [ 'cableand', 'cccc', 'jncb', 'bdagov' ]
        }
      },
      {}
    );

    foreach my $ga ( @{$accounts} ) {
      my $db_merchant = $ga->getGatewayAccountName();
      $merchlist[ ++$#merchlist ] = "$db_merchant";
    }
  } elsif ( $reseller eq "stkittsn" ) {
    my $accounts = $private->queryAllAccounts(
      { 'reseller' => {
          'operator' => 'IN',
          'values'   => [ 'skittsn', 'stkitts2' ]
        }
      },
      {}
    );

    foreach my $ga ( @{$accounts} ) {
      my $db_merchant = $ga->getGatewayAccountName();
      $merchlist[ ++$#merchlist ] = "$db_merchant";
    }
  } elsif ( $reseller eq "cccc" ) {
    my $accounts = $private->queryAllAccounts(
      { 'processor' => 'cccc',
        'status'    => {
          'operator' => '<>',
          'value'    => 'cancelled'
        }
      },
      {}
    );

    foreach my $ga ( @{$accounts} ) {
      my $db_merchant = $ga->getGatewayAccountName();
      $merchlist[ ++$#merchlist ] = "$db_merchant";
    }
  } else {
    my $accounts = $private->queryAllAccounts( { 'reseller' => $reseller }, {} );

    foreach my $ga ( @{$accounts} ) {
      my $db_merchant = $ga->getGatewayAccountName();
      $merchlist[ ++$#merchlist ] = "$db_merchant";
    }
  }

  return @merchlist;
}

sub virtterm {

  &head('Virtual Terminal');
  print "<table border=0 cellspacing=0 cellpadding=4>\n";

  if ( ( $ENV{'SEC_LEVEL'} < 9 ) || ( $ENV{'SEC_LEVEL'} == 13 ) ) {
    if ( $smps::allowed_functions =~ /cardinput/ ) {
      if ( ( $smps::processor eq "planetpay" ) && ( $smps::feature{'multicurrency'} != 1 ) ) {
        print "<hr width=400></td></tr>\n";
        print "<tr>\n";
        print "<td class=\"menuleftside\">Manual Authorizations &amp; Returns</td>\n";
        print "<td class=\"menurightside\">\n";

        print "Manually entered transaction are not permitted through a DCC account.<p>\n";
        print "Please use your primary account to enter these types of transactions.<p>\n";
        print "Credits against previously sales should be performed by searching on the original transaction first.<p>\n";
        print "<hr width=400></td></tr>\n";
      } elsif ( $smps::processor eq "volpay" ) {
        print "<hr width=400></td></tr>\n";
        print "<tr>\n";
        print "<td class=\"menuleftside\">Manual Authorizations &amp; Returns</td>\n";
        print "<td class=\"menurightside\">\n";

        print "Manually entered transaction are not permitted through a Volpay account.<p>\n";
        print "<hr width=400></td></tr>\n";
      } elsif ( $smps::processor eq "ncb" ) {
        if ( $ENV{'SEC_LEVEL'} < 7 ) {
          &cardinput_new();
        }
      } else {
        &cardinput_new();
      }
    }
  }

  print "</table>\n";
  &tail();
  return;
}

sub security_check {
  my ( $username, $remoteaddr ) = @_;
  my ( $ipaddr, %result, $login, $test );
  $username =~ s/[^a-zA-Z0-9]//g;

  my $dbh = &miscutils::dbhconnect('pnpmisc');
  
  my $sth = $dbh->prepare(q/
    SELECT ipaddress
    FROM ipaddress
    WHERE username=?
      AND ipaddress=?
  /) or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr" );
  $sth->execute( "$username", "$remoteaddr" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr" );
  ($ipaddr) = $sth->fetchrow;
  $sth->finish;
  
  $dbh->disconnect;

  if ( $ipaddr ne "" ) {
    $result{'flag'} = 1;
  } else {
    $result{'MErrMsg'} = "Your Source IP address has not been registered. Access to this area is denied.";
    $result{'flag'}    = 0;
  }

  return %result;
}

sub orders {
  my (%query);
  my @postauthlist = ();
  my @voidlist     = ();
  my @returnlist   = ();
  my @releaselist  = ();
  my ($message);

  my @params = $smps::query->param;
  foreach my $param (@params) {
    $query{$param} = $smps::query->param($param);
    $query{$param} =~ s/[^0-9a-zA-Z\_\ \.\@]//g;
    if ( $param =~ /^func_(\d*)$/ ) {
      if ( $query{$param} eq "postauth" ) {
        $postauthlist[ ++$#postauthlist ] = "$1";
      } elsif ( $query{$param} eq "void" ) {
        $voidlist[ ++$#voidlist ] = "$1";
      } elsif ( $query{$param} eq "return" ) {
        $returnlist[ ++$#returnlist ] = "$1";
      } elsif ( $query{$param} eq "release" ) {
        $releaselist[ ++$#releaselist ] = "$1";
      }
    }
  }

  if ( @releaselist > 1 ) {
    $message .= &release_auth(@releaselist);
  }

  print "<div align=center>\n";
  print "<table>\n";
  print "<tr><td colspan=\"2\">\n";
  print "$message\n";
  print "</td></tr>\n";

  print "</table>\n";
  &tail();
  return;
}

sub release_auth {
  my (@releaselist) = @_;
  my (%query);
  my @params = $smps::query->param;
  foreach my $param (@params) {
    $query{$param} = $smps::query->param($param);
    $query{$param} =~ s/[^0-9a-zA-Z\_\ \.\@]//g;
  }

  my ($message);

  my $dbh      = &miscutils::dbhconnect("pnpmisc");
  my $username = $ENV{'REMOTE_USER'};
  $username =~ s/[^a-z0-9]//g;
  my $dbhpnp = &miscutils::dbhconnect( "pnpdata", "", "$username" );

  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);

  ##  Should we allow multiple transactions to be thawed at one time ?
  foreach my $oid (@releaselist) {
    my $description = "Transction $oid thawed";
    my $transtime = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec );

    my $transdate = $query{"transdate_$oid"};
    $transdate =~ s/[^0-9]//g;

    my $ipaddress = $ENV{'REMOTE_ADDR'};

    my $orderid = $oid;
    $orderid =~ s/[^0-9]//g;

    my $action    = "tran. thawed";
    my $operation = 'auth';

    if ( $transdate < $smps::earliest_date ) {
      return;
    }

    my ($updateflag);

    my $sth = $dbhpnp->prepare(
      qq{
          select finalstatus
          from trans_log FORCE INDEX(tlog_tdateuname_idx)
          where trans_date=?
          and orderid=? and username=? and operation=?
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %query, 'username', $username );
    $sth->execute( "$transdate", "$orderid", "$username", "$operation" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %query, 'username', $username );
    my ($finalstatus) = $sth->fetchrow;
    $sth->finish;

    if ( $finalstatus ne "hold" ) {
      $message .= "$orderid previously released.<br>\n";
      next;
    }
    my $sth2 = $dbhpnp->prepare(
      qq{
          update trans_log
          set finalstatus='success'
          where orderid='$orderid' and username='$username' and operation='auth' and finalstatus='hold'
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %query, 'username', $username );
    $sth2->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %query, 'username', $username );
    $sth2->finish;

    my $sth3 = $dbhpnp->prepare(
      qq{
          update operation_log
          set lastopstatus='success'
          where orderid='$orderid' and username='$username' and lastopstatus='hold'
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %query, 'username', $username );
    $sth3->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %query, 'username', $username );
    $sth3->finish;

    my $sth4 = $dbhpnp->prepare(
      qq{
          update ordersummary
          set result='success'
          where trans_date='$transdate'
          and orderid='$orderid'
          and username='$username'
          and result='hold'
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %query, 'username', $username );
    $sth4->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %query, 'username', $username );
    $sth4->finish;

    my $sth5 = $dbh->prepare(
      qq{
        insert into risk_log
        (username,orderid,trans_time,ipaddress,action,description)
        values (?,?,?,?,?,?)
        }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %query, 'username', $username );
    $sth5->execute( "$username", "$orderid", "$transtime", "$ipaddress", "$action", "$description" )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %query, 'username', $username );
    $sth5->finish;

    $message .= "$orderid successfully released.<br>\n";

  }

  $dbhpnp->disconnect;
  $dbh->disconnect;

  return $message;
}

sub toggle_represent {
  my (@releaselist) = @_;
  my (%query);
  my @params = $smps::query->param;

  my $username  = $smps::query->param('merchant');
  my $orderid   = $smps::query->param('orderid');
  my $function  = $smps::query->param('function');
  my $transdate = $smps::query->param('transdate');

  my ($message);

  my $dbh = &miscutils::dbhconnect("pnpmisc");
  $username = $ENV{'REMOTE_USER'};
  $username =~ s/[^a-z0-9]//g;
  my $dbhpnp = &miscutils::dbhconnect( "pnpdata", "", "$username" );

  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);

  my $sth = $dbhpnp->prepare(
    qq{
        select transflags
        from trans_log FORCE INDEX(tlog_tdateuname_idx)
        where trans_date=?
        and orderid=? and username=? and operation='auth'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %query, 'username', $username );
  $sth->execute( "$transdate", "$orderid", "$username" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %query, 'username', $username );
  my ($transflagString) = $sth->fetchrow;
  $sth->finish;

  # create transflags object in case they are stored as a hex bitmap string
  my $transflags = new PlugNPay::Legacy::Transflags();
  $transflags->fromString($transflagString);

  if ( $transflags =~ /norepresent/ ) {
    $transflags =~ s/norepresent//;
  } elsif ( $transflags !~ /norepresent/ ) {
    if ( $transflags eq "" ) {
      $transflags = "norepresent";
    } else {
      $transflags .= ",norepresent";
    }
  } else {
    ## Error
    $dbh->disconnect;
    return;
  }
  $transflags =~ s/\,\,/,/g;

  my $sth2 = $dbhpnp->prepare(
    qq{
        update trans_log
        set transflags=?
        where trans_date=?
        and orderid=?
        and username=?
        and operation='auth'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %query, 'username', $username );
  $sth2->execute( "$transflags", "$transdate", "$orderid", "$username" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %query, 'username', $username );
  $sth2->finish;

  $dbh->disconnect;

  return;
}

sub summarize {
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"/css/vt.css\" >\n";
  print "<div align=\"center\"><table>\n";
  print "<tr><td colspan=2>\n";
  print "Please Check The Following Information Carefully.<br>\n";
  print "Use the \"Back Button\" on your Browser to make any necessary corrections.</td></tr>\n";

  print "<tr><th align=\"left\">Amount to be Charged:</th><td>$mckutils::query{'currency'} $mckutils::query{'card-amount'}</td></tr>\n";
  if ( $mckutils::query{'shipinfo'} ne "" ) {
    print "<tr><td width=\"50%\" valign=\"top\">\n";
  } else {
    print "<tr>><td colspan=\"2\">\n";
  }
  print "<b>Billing Information</b><br>\n";
  print "$mckutils::query{'card-name'}<br>\n";
  if ( $mckutils::query{'card-company'} ne "" ) {
    print "$mckutils::query{'card-company'} <br>\n";
  }
  print "$mckutils::query{'card-address1'}<br>\n";
  if ( $mckutils::query{'card-address2'} ne "" ) {
    print "$mckutils::query{'card-address2'}<br>\n";
  }
  print "$mckutils::query{'card-city'}, $mckutils::query{'card-state'}  $mckutils::query{'card-zip'}<br>\n";
  if ( $mckutils::query{'card-prov'} ne "" ) {
    print "$mckutils::query{'card-prov'}<br>\n";
  }
  print $mckutils::countries{"$mckutils::query{'card-country'}"} . "<br>\n";
  if ( ( $mckutils::query{'paymethod'} ne "check" ) && ( $mckutils::query{'accountnum'} eq "" ) ) {
    my $cardnumber = $mckutils::query{'card-number'};
    if ( $mckutils::query{'card-number'} ne "" ) {
      my $nice_number = substr( $mckutils::query{'card-number'}, 0, 4 ) . '**' . substr( $mckutils::query{'card-number'}, -2, 2 );
      print "$nice_number  Exp. Date: $mckutils::query{'month-exp'}/$mckutils::query{'year-exp'} <br>\n";
    }
  } elsif ( $mckutils::query{'accountnum'} ne "" ) {
    print "<br>Account#: $mckutils::query{'accountnum'}<br>\n";
    print "Routing#: $mckutils::query{'routingnum'}<br>\n";
    print "Check #: $mckutils::query{'checknum'}<br><br>\n";
  }
  print "$mckutils::query{'email'}<br>\n";
  if ( $mckutils::query{'phone'} ne "" ) {
    print "Tel: $mckutils::query{'phone'}<br>\n";
  }
  if ( $mckutils::query{'fax'} ne "" ) {
    print "Night Phone/Fax: $mckutils::query{'fax'}<br>\n";
  }
  print "</td>\n";
  if ( $mckutils::query{'shipinfo'} eq "1" ) {
    print "<td  width=\"50%\" valign=\"top\">\n";
    if ( $mckutils::query{'shipinfo-label'} ne "" ) {
      print "<b>$mckutils::query{'shipinfo-label'}</b><br>\n";
    } else {
      print "<b>Shipping Information</b><br>\n";
    }
    print "$mckutils::query{'shipname'}<br>\n";
    if ( $mckutils::query{'shipcompany'} ne "" ) {
      print "$mckutils::query{'shipcompany'}<br>";
    }
    print "$mckutils::query{'address1'}<br>\n";
    if ( $mckutils::query{'address2'} ne "" ) {
      print "$mckutils::query{'address2'}<br>\n";
    }
    print "$mckutils::query{'city'}, $mckutils::query{'state'} $mckutils::query{'zip'}<br>\n";
    if ( $mckutils::query{'province'} ne "" ) {
      print "$mckutils::query{'province'}<br>\n";
    }
    print $mckutils::countries{"$mckutils::query{'country'}"} . "<br>\n";
    if ( $mckutils::query{'shipemail'} ne "" ) {
      print "$mckutils::query{'shipemail'}<br>\n";
    }
    if ( $mckutils::query{'shipphone'} ne "" ) {
      print "Tel: $mckutils::query{'shipphone'}<br>\n";
    }
    if ( $mckutils::query{'shipfax'} ne "" ) {
      print "Night Phone/Fax: $mckutils::query{'shipfax'}<br>\n";
    }

    print "<br>\n\n";
    print "</td></tr>\n";
  } else {
    print "</tr>\n";
  }
  print "<tr><td>";

  print "<form method=\"post\" action=\"$smps::path_cgi\" name=\"bill\">\n";
  print "<input type=\"hidden\" name=\"convert\" value=\"$mckutils::query{'convert'}\">\n";
  print "<input type=\"hidden\" name=\"merchant\" value=\"$mckutils::query{'merchant'}\">\n";
  print "<input type=\"hidden\" name=\"vt_url\" value=\"$mckutils::query{'vt_url'}\">\n";
  print "<input type=\"hidden\" name=\"receipt_company\" value=\"$mckutils::query{'receipt_company'}\">\n";
  print "<input type=\"hidden\" name=\"username\" value=\"$mckutils::query{'username'}\">\n";
  print "<input type=\"hidden\" name=\"mode\" value=\"$mckutils::query{'mode'}\">\n";
  print "<input type=\"hidden\" name=\"function\" value=\"inputnew\">\n";
  print "<input type=\"hidden\" name=\"card-amount\" value=\"$mckutils::query{'card-amount'}\">\n";
  print "<input type=\"hidden\" name=\"orderID\" value=\"$mckutils::query{'orderID'}\">\n";
  print "<input type=\"hidden\" name=\"acct_code\" value=\"$mckutils::query{'acct_code'}\">\n";
  print "<input type=\"hidden\" name=\"currency\" value=\"$mckutils::query{'currency'}\">\n";
  print "<input type=\"hidden\" name=\"card_number\" value=\"$mckutils::query{'card_number'}\">\n";
  print "<input type=\"hidden\" name=\"month_exp\" value=\"$mckutils::query{'month_exp'}\">\n";
  print "<input type=\"hidden\" name=\"year_exp\" value=\"$mckutils::query{'year_exp'}\">\n";
  print "<input type=\"hidden\" name=\"card-cvv\" value=\"$mckutils::query{'card-cvv'}\">\n";

  print "<input type=\"hidden\" name=\"client\" value=\"$mckutils::query{'client'}\">\n";
  print "<input type=\"hidden\" name=\"receipt_type\" value=\"$mckutils::query{'receipt_type'}\">\n";
  print "<input type=\"hidden\" name=\"print_receipt\" value=\"$mckutils::query{'print_receipt'}\">\n";

  print "<input type=\"submit\" value=\"Submit Payment\">\n";
  print "</form></td>\n";
  print "<td><form method=\"get\" action=\"$smps::path_vt\">\n";
  print "<input type=\"submit\" value=\"Start Over\">\n";
  print "</form></td>\n";
  print "</tr>\n";
  print "</table>\n";

  print "</body>\n";
  print "</html>\n";
  return;

}

sub check_linked_acct {
  my ( $username, $merchant, $la_feature ) = @_;
  my ( $feature_string, $fraud_config );
  my (%linked_accts);

  if ( $la_feature ne "" ) {
    my ( %la_feature, %la_linked_accts );
    my @linked_accts = split( '\|', $la_feature );
    foreach my $var (@linked_accts) {
      $var =~ s/[^0-9a-z]//g;
      $linked_accts{$var} = 1;
    }

    if ( exists $linked_accts{$merchant} ) {
      my $gatewayAccount = new PlugNPay::GatewayAccount($merchant);
      my $username       = $gatewayAccount->getGatewayAccountName();
      my $processor      = $gatewayAccount->getCardProcessor();

      my $merchantid;
      my $proc_type;
      my $currency;
      if ( $processor && $username ) {
        my $cardProcessorAccountObj = new PlugNPay::Processor::Account(
          { 'gatewayAccount' => $username,
            'processorName'  => $processor
          }
        );

        $merchantid = $cardProcessorAccountObj->getSettingValue('mid');
        $proc_type  = $cardProcessorAccountObj->getSettingValue('authType');
        $currency   = $cardProcessorAccountObj->getSettingValue('currency');
      }

      my $company      = $gatewayAccount->getMainContact()->getCompany();
      my $reseller     = $gatewayAccount->getReseller();
      my $chkprocessor = $gatewayAccount->getCheckProcessor();
      my $dccusername  = $gatewayAccount->getDCCAccount();
      my $merchstrt    = $gatewayAccount->getStartDate();

      my $status          = $gatewayAccount->getStatus();
      my $walletprocessor = $gatewayAccount->getWalletProcessor();
      my $feature_string  = $gatewayAccount->getFeatures()->getFeatureString();
      my $fraud_config    = $gatewayAccount->getFraudConfig();

      ## Linked Account request is verified.
      $smps::status          = $status;
      $smps::company         = $company;
      $smps::currency        = $currency;
      $smps::reseller        = $reseller;
      $smps::processor       = $processor;
      $smps::proc_type       = $proc_type;
      $smps::merchstrt       = $merchstrt;
      $smps::merchantid      = $merchantid;
      $smps::dccusername     = $dccusername;
      $smps::chkprocessor    = $chkprocessor;
      $smps::walletprocessor = $walletprocessor;

      if ( $smps::chkprocessor eq "" ) {
        $smps::chkprocessor = "ach";
      }

      $ENV{'REMOTE_USER'} = $username;
      $smps::username = $username;

      if ( $feature_string ne "" ) {
        my @array = split( /\,/, $feature_string );
        foreach my $entry (@array) {
          my ( $name, $value ) = split( /\=/, $entry );
          $smps::feature{$name} = $value;
        }
      }

      if ( $fraud_config ne "" ) {
        my @array = split( /\,/, $fraud_config );
        foreach my $entry (@array) {
          my ( $name, $value ) = split( /\=/, $entry );
          $smps::fconfig{$name} = $value;
        }
      }
    }
  }
}

sub query_chargeback {
  my ( $startdate, $enddate ) = @_;

  $startdate = substr( $startdate, 0, 8 );
  $enddate   = substr( $enddate,   0, 8 );

  my ( %ct, %cb_sum, %cb_cnt, %rt_sum, %rt_cnt, %cbt_sum, %cbt_cnt, %rtt_sum, %rtt_cnt );
  my ( $origamt, $cardtype, $type, $post_date );
  my $dbh = &miscutils::dbhconnect("fraudtrack");

  my $qstr = "select post_date,origamt,cardtype,type ";
  $qstr .= "from chargeback where post_date >= '$startdate' and post_date <'$enddate' ";
  $qstr .= "and username='$smps::username' ORDER BY post_date";

  my $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
  $sth->execute or die "Can't execute: $DBI::errstr";
  $sth->bind_columns( undef, \( $post_date, $origamt, $cardtype, $type ) );

  while ( $sth->fetch ) {
    $cb_cnt{$type}{$cardtype}++;
    $cb_sum{$type}{$cardtype} += $origamt;
    $cbt_cnt{$post_date}{$type}{$cardtype}++;
    $cbt_sum{$post_date}{$type}{$cardtype} += $origamt;
    $ct{$cardtype} = 1;
  }
  $sth->finish;

  $dbh->disconnect;

  return ( \%ct, \%cb_sum, \%cb_cnt, \%cbt_sum, \%cbt_cnt );
}

sub getcn {
  my ( $orderid, $startdate, $enddate ) = @_;
  my $starttime = &miscutils::strtotime($startdate);
  $startdate = substr( &miscutils::timetostr( &miscutils::strtotime($startdate) - 30 * 24 * 3600 ), 0, 8 );
  my ($cardnumber);
  my @query_array = ( $startdate, $enddate, $orderid );
  my $qstr = "select enccardnumber,length,username ";
  $qstr .= "from trans_log ";
  $qstr .= "where trans_date>=? and trans_date<=? ";
  $qstr .= "and orderid=? ";
  if ( exists $smps::altaccts{$smps::username} ) {
    my ($temp);
    foreach my $var ( @{ $smps::altaccts{$smps::username} } ) {
      $temp .= "'$var',";
    }
    chop $temp;
    $qstr .= " and username IN ($temp) ";
  } else {
    $qstr .= "and username=? ";
    push( @query_array, $smps::username );
  }
  $qstr .= "and operation in ('auth','forceauth','return','storedata','postauth') ";
  $qstr .= "and (duplicate IS NULL or duplicate='') ";
  my $dbh = &miscutils::dbhconnect( "pnpdata", "", "$smps::username" );    ## Trans_Log
  my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr" );
  $sth->execute(@query_array) or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr" );
  my ( $enccardnumber, $length, $uname ) = $sth->fetchrow;
  $sth->finish;
  $dbh->disconnect;
  $enccardnumber = &smpsutils::getcardnumber( $uname, $orderid, 'smps_getcn', $enccardnumber );

  if ( $enccardnumber ne "" ) {
    $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );
  }
  return $cardnumber;
}

sub parse_template {
  my ( $path, $file, %result ) = @_;
  my $template_file  = $path . $file;
  my $template_data  = "";                                    # clear and initialize value for holding thank you template data
  my $template_table = &mckutils::create_table_for_template(%result);    # create product table data

  # Load, Fill-In & Display Return Template
  my @todays_date = gmtime(time);
  $result{'order-date'} = sprintf( "%02d/%02d/%04d", $todays_date[4] + 1, $todays_date[3], $todays_date[5] + 1900 );

  $result{'card-number'} =~ s/[^0-9]//g;
  $result{'card-number'} = substr( $result{'card-number'}, 0, 20 );
  my ($cardnumber) = $result{'card-number'};
  my $cclength = length($cardnumber);
  my $last4 = substr( $cardnumber, -4, 4 );
  $cardnumber =~ s/./X/g;
  $result{'card-number'} = substr( $cardnumber, 0, $cclength - 4 ) . $last4;

  if ( $template_file ne "" ) {

    # open template file for reading
    my $fileReader = new PlugNPay::WebDataFile();
    my $results    = $fileReader->readFile(
      { fileName  => $file,
        localPath => $path
      }
    );

    my @lines = split( "\n", $results );

    # read template contents into memory
    foreach my $line (@lines) {
      $_ =~ s/\[pnp_([a-zA-Z0-9\-\_]*)\]/$result{$1}/g;
      $_ =~ s/\[TABLE\]/$template_table/g;
      $template_data .= $line;
    }

    # display filled in template to user
    &mckutils::genhtml2( "", "$template_data" );
    return 1;
  }
  return 0;
}

sub check_geolocation {
  my ($ipaddress) = @_;
  my ( %error, $w, $x, $y, $z, $elapse, $stime, $etime, $country, $mmcountry, $ipnum_from, $ipnum_to, $ipnum, $isp, $org );
  my ( %percent, %cnt, $db_count, $days, $count, $db_country, $totalcnt, $db_org, $db_isp, $db_date, %dates );
  my ($threshold);

  if ( exists $smps::feature{'geo_chk_threshold'} ) {
    $smps::feature{'geo_chk_threshold'} =~ s/[^0-9]//g;
    $threshold = $smps::feature{'geo_chk_threshold'};
  } else {
    $threshold = 10;    ## %percent below at which a login violation warning is triggered.  The higher the number the more warnings will be sent.
  }

  if ( $ipaddress !~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/ ) {
    return;
  }

  if ( $smps::username =~ /^(smart2demo|initaly|pnpdemo)$/ ) {
    return;
  }

  my $dbh = &miscutils::dbhconnect("fraudtrack");

  $w = $1;
  $x = $2;
  $y = $3;
  $z = $4;

  if ( -e "/home/pay1/outagefiles/stop_geolocation.txt" ) {
    return;
  }

  $ipnum = int( 16777216 * $w + 65536 * $x + 256 * $y + $z );

  if ( length($ipnum) > 11 ) {
    return;
  }

  $stime = time();

  my $sth = $dbh->prepare(
    qq{
        select ipnum_from, ipnum_to, country_code
        from ip_country
        where ipnum_to >= $ipnum
        ORDER BY ipnum_to ASC LIMIT 1
  }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr" );
  $sth->execute() or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr" );
  ( $ipnum_from, $ipnum_to, $mmcountry ) = $sth->fetchrow;
  $sth->finish;

  if ( ( $ipnum < $ipnum_from ) || ( $ipnum > $ipnum_to ) ) {
    $mmcountry = "";
  }

  if ( $mmcountry =~ /^(UK|GB)$/ ) {
    $mmcountry = "GB";
  }

  $country = $mmcountry;

  if ( $country eq "" ) {
    $country = "NA";
    return $country;
  }

  return $country;

  my ($data);
  my $sth2 = $dbh->prepare(
    qq{
        select ipnum_from, ipnum_to, geodata
        from ip_isp
        where ipnum_to >= $ipnum
        ORDER BY ipnum_to ASC LIMIT 1
  }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr" );
  $sth2->execute() or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr" );
  ( $ipnum_from, $ipnum_to, $data ) = $sth2->fetchrow;
  $sth2->finish;

  if ( ( $ipnum < $ipnum_from ) || ( $ipnum > $ipnum_to ) ) {
    $data = "";
  }

  if ( $data eq "" ) {
    $data = "ISP Not Found";
  }

  $isp = $data;

  my $sth3 = $dbh->prepare(
    qq{
        select ipnum_from, ipnum_to, geodata
        from ip_org
        where ipnum_to >= $ipnum
        ORDER BY ipnum_to ASC LIMIT 1
  }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr" );
  $sth3->execute() or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr" );
  ( $ipnum_from, $ipnum_to, $data ) = $sth3->fetchrow;
  $sth3->finish;

  if ( ( $ipnum < $ipnum_from ) || ( $ipnum > $ipnum_to ) ) {
    $data = "";
  }

  if ( $data eq "" ) {
    $data = "ORG Not Found";
  }

  $org = $data;

  my $username = $smps::username;
  my $login    = $ENV{'LOGIN'};
  my ( $dummy, $trans_date, $trans_time ) = &miscutils::gendatetime();

  my $sth4 = $dbh->prepare(
    qq{
        select count
        from login_stats
        where username=?
        and login=?
        and trans_date=?
        and country=?
        and isp=?
        and org=?
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", 'username', $username );
  $sth4->execute( "$username", "$login", "$trans_date", "$country", "$isp", "$org" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", 'username', $username );
  ($count) = $sth4->fetchrow;
  $sth4->finish;

  if ( $count eq "" ) {
    my $sth = $dbh->prepare(
      qq{
        insert into login_stats
        (username,login,trans_date,country,count,isp,org)
        values (?,?,?,?,?,?,?)
        }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", 'username', $username );
    $sth->execute( "$username", "$login", "$trans_date", "$country", '1', "$isp", "$org" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", 'username', $username );
    $sth->finish;
  } else {
    $count++;
    my $sth = $dbh->prepare(
      qq{
        update login_stats
        set count=?
        where username=?
        and login=?
        and trans_date=?
        and country=?
        and isp=?
        and org=?
        }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", 'username', $username );
    $sth->execute( "$count", "$username", "$login", "$trans_date", "$country", "$isp", "$org" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", 'username', $username );
    $sth->finish;
  }

  if ( !-e "/home/pay1/logfiles/stop_smpsgeo.txt" ) {

    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 90 * 24 * 3600 ) );
    my $startdate = sprintf( "%04d%02d%02d", $year + 1900, $mon + 1, $mday );

    my $sth2 = $dbh->prepare(
      qq{
        select count,country,isp,org,trans_date
        from login_stats
        where username=?
        and login=?
        and trans_date>=?
        }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", 'username', $username, %ENV );
    $sth2->execute( "$username", "$login", "$startdate" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", 'username', $username, %ENV );
    my $rv = $sth2->bind_columns( undef, \( $db_count, $db_country, $db_isp, $db_org, $db_date ) );
    while ( $sth2->fetch ) {

      if ( $db_isp eq "" ) {
        next;
      }

      if ( $db_country =~ /^GB\|/ ) {
        $db_country = "GB";
      }
      $dates{$db_date} = 1;
      $totalcnt += $db_count;
      $cnt{"$db_country/$db_isp/$db_org"} += $db_count;
    }
    $sth2->finish;

    $dbh->disconnect;

    my @days = keys %dates;
    $days = @days;

    &logToDataLog(
      { 'originalLogFile' => '/home/pay1/database/debug/geodata_debug.txt',
        'username'        => $username,
        'login'           => $login,
        'ipAddress'       => $ipaddress,
        'country'         => $country,
        'ISP'             => $isp,
        'ORG'             => $org
      }
    );

    if ( ( $days >= 5 ) && ( $totalcnt > 0 ) ) {
      foreach my $key ( keys %cnt ) {
        $percent{$key} = sprintf( "%.1f", ( $cnt{$key} / $totalcnt ) * 100 );
      }

      if ( $percent{"$country/$isp/$org"} < $threshold ) {
        ## Current Country of Login < Threshold send warning.
        my $msg = "Foreign Country Detected\n\n";
        $msg .= "current warning threshold:$threshold\%\n\n";
        $msg .= "username:$username\n";
        $msg .= "login:$login\n\n";
        $msg .= "current login country:$country\n";
        $msg .= "current isp:$isp\n";
        $msg .= "current org:$org\n";
        $msg .= "login history\n";
        $msg .= "total count:$totalcnt\n";
        foreach my $key ( keys %percent ) {
          $msg .= "country:$key, cnt:$cnt{$key}, percent:$percent{$key}\n";
        }
        $msg .= "\n\nENV VARS\n";
        foreach my $key (@smps::log_env_array) {
          $msg .= "$key:$ENV{$key}\n";
        }
        $msg .= "\n\n";
        my $sub = "pnp - foreign country login Warning";
        if ( $username !~ /^(pnpdemo|demo|anonymi)/ ) {
          &sendemail( "$msg", "$ENV{'SERVER_NAME'}", "$sub" );
        }
      }

    }

  }

  return $country;
}

sub sendemail {
  my ( $msg, $hostname, $sub ) = @_;

  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( time() );
  my $time = sprintf( "%02d/%02d %02d:%02d", $mon + 1, $mday, $hour, $min );

  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setFormat('text');
  $emailObj->setTo('dprice@plugnpay.com');
  $emailObj->setCC('chris@plugnpay.com');
  $emailObj->setFrom('checklog@plugnpay.com');
  $emailObj->setSubject($sub);
  if ( $sub =~ /Hacker/ ) {
    $emailObj->setBCC('6318061932@txt.att.net');
  }

  my $message = '';
  $message .= "$time\n\n";
  $message .= "$msg\n";

  $emailObj->setContent($message);
  $emailObj->send();
}

sub debug_log {
  my ($query) = @_;

  my %logdata = ();
  $logdata{'UN'}      = $smps::username;
  $logdata{'LOGIN'}   = $ENV{'LOGIN'};
  $logdata{'SL'}      = $ENV{'SEC_LEVEL'};
  $logdata{'TECH'}    = $ENV{'TECH'};
  $logdata{'RU'}      = $ENV{'REMOTE_USER'};
  $logdata{'HOST'}    = $ENV{'SERVER_NAME'};
  $logdata{'IP'}      = $ENV{'REMOTE_ADDR'};
  $logdata{'SCRIPT'}  = $ENV{'SCRIPT_NAME'};
  $logdata{'UA'}      = $ENV{'HTTP_USER_AGENT'};
  $logdata{'LOGINCO'} = $smps::login_country;

  my @params = $query->param;
  foreach my $param (@params) {
    my $value = $query->param($param);
    if ( $param =~ /listval/ ) {
      my @listval = $query->param('listval');
      my $listcnt = 0;
      foreach my $var (@listval) {
        $listcnt++;
        $logdata{'listval'} .= $var . "|";
      }
      $logdata{'listvalcnt'} = $listcnt;
    } else {
      $logdata{$param} = $value;
    }
  }
  foreach my $key ( sort keys %smps::cookie ) {
    $logdata{ 'CK_' . $key } = $smps::cookie{$key};
  }

  %logdata = &log_filter( \%logdata );

  my $logger = new PlugNPay::Logging::MessageLog();
  $logger->logMessage( \%logdata );
}

sub log_filter {
  my ($hash) = @_;
  my %logdata = ();
  foreach my $key ( keys %$hash ) {
    if ( $key =~ /card.*num|accountnum|acct_num|ccno/i ) {
      $logdata{$key} = substr( $$hash{$key}, 0, 6 ) . ( 'X' x ( length( $$hash{$key} ) - 8 ) ) . substr( $$hash{$key}, -2 );    # Format: first6, X's, last2
    } elsif ( ( $key =~ /^(TrakData|magstripe)$/i ) && ( $$hash{$key} ne "" ) ) {
      $logdata{$key} = "Data Present:" . substr( $$hash{$key}, 0, 6 ) . "****" . "0000";
    } elsif ( ( $key =~ /^(data)$/i ) && ( $$hash{$key} ne "" ) ) {
      $logdata{$key} = "Batch File Present";
    } elsif ( $key =~ /(cvv|pass.*w.*d|x_tran_key|card.code)/i ) {
      $logdata{$key} = $$hash{$key};
      $logdata{$key} =~ s/./X/g;
    } elsif ( ( $key =~ /^(ssnum|ssnum4)$/i ) || ( $key =~ /^($smps::feature{'mask_merchant_variables'})$/ ) ) {
      $logdata{$key} = ( 'X' x ( length( $$hash{$key} ) - 4 ) ) . substr( $$hash{$key}, -4, 4 );
    } else {
      my ( $key1, $val ) = &logfilter_in( $key, $$hash{$key} );
      $logdata{$key1} = $val;
    }
  }
  return %logdata;
}

sub storeresults {
  my ( $operation, %result ) = @_;
  my ( $filename, $pairs, $message, %input );
  %input = ();
  $pairs = "";

  my $path_base = "/home/pay1/private/tranresults/";
  my $path_cgi  = "/results.cgi";

  my ( $ct_ext, $ct_format ) = split( '\:', $smps::feature{'storeresults'} );

  if ( $operation =~ /^(return)$/ ) {
    if ( $result{'FinalStatus'} ne "pending" ) {
      $input{'MErrMsg'} = $result{'MErrMsg'};
    }
    $input{'FinalStatus'} = $result{'FinalStatus'};
    $input{'amount'}      = $result{'amount'};
    $input{'mode'}        = 'return';
  }

  my @params = $smps::query->param;
  foreach my $param (@params) {
    $input{$param} = $smps::query->param($param);
  }
  $input{'orderID'}        = $input{'orderid'};
  $input{'publisher-name'} = $input{'merchant'};

  %input = ( %input, %result );
  ( $input{'currency'}, $input{'card-amount'} ) = split( / /, $input{'amount'} );

  ## Add Masked CN
  my ($cardnumber);
  $cardnumber = $input{'card-number'};
  my $first4 = substr( $cardnumber, 0, 4 );
  my $last4  = substr( $cardnumber, -4 );
  my $CClen  = length($cardnumber);
  $cardnumber =~ s/./\*/g;
  $cardnumber = $first4 . substr( $cardnumber, 4, $CClen - 8 ) . $last4;
  $input{'card-number'} = $cardnumber;

  if ( exists $input{'auth-code'} ) {
    $input{'auth-code'} = substr( $input{'auth-code'}, 0, 6 );
  }
  my $errmsg = $result{'MErrMsg'};

  if ( $ct_format =~ /^xml$/i ) {
    ### Need to Generate XML response here
    require xmlparse2;
    my @array = (%input);
    $xmlparse2::version = 2;
    $message .= &xmlparse2::output_xml( '1', @array );
    $message = &xmlparse2::xml_wrapper( $message, $input{'publisher-name'} );
  } else {
    foreach my $key ( keys %input ) {
      if ( ( $key !~ /^card.number/i )
        && ( $key !~ /.link$/i )
        && ( $key !~ /merch.txn/i )
        && ( $key !~ /cust.txn|User.Agent|card.allowed|receipt.type|confemailtemplate/i )
        && ( $key !~ /month.exp/i )
        && ( $key !~ /year.exp/i )
        && ( $key !~ /card.cvv/i )
        && ( $key !~ /publisher\-password/i )
        && ( $key !~ /magstripe/i )
        && ( $key !~ /^MErrMsg$/i )
        && ( $key !~ /path.*cgi/i )
        && ( $key !~ /image.placement/i )
        && ( $key ne "" ) ) {
        $_ = $input{$key};
        s/(\W)/'%' . unpack("H2",$1)/ge;
        if ( $pairs ne "" ) {
          $pairs = "$pairs\&$key=$_";
        } else {
          $pairs = "$key=$_";
        }
      }
    }
    $errmsg =~ s/(\W)/'%' . unpack("H2",$1)/ge;
    if ( $errmsg ne "" ) {
      if ( $mckutils::query{'client'} =~ /^(coldfusion|miva)/i ) {
        $pairs .= "\&MERRMSG=$errmsg";
      } else {
        $pairs .= "\&MErrMsg=$errmsg";
      }
    }
    $message = $pairs;
  }

  ### Generate Random File Name
  my $size = 40;
  my @alphanumeric = ( 'a' .. 'z', 'A' .. 'Z', 0 .. 9 );
  $filename = join '', map $alphanumeric[ rand @alphanumeric ], 0 .. $size;

  my $fileData = 'Content-Disposition: inline; filename="results.' . $ct_ext . "\"\n";
  $ct_ext =~ s/[^a-zA-Z0-9\-_\.\+]//g;
  my $contentType = sprintf( 'application/%s', $ct_ext );
  $fileData = $message . "\n";

  ### Write Data to file
  my $fileWriter = new PlugNPay::WebDataFile();
  $fileWriter->writeFile(
    { fileName    => $filename . '.txt',
      contentType => $contentType,
      content     => $fileData,
      storageKey  => 'transactionResults'
    }
  );

  my $onload = 'onLoad="window.location.href=\'' . $path_cgi . '/results.' . $ct_ext . '?' . $filename . '\';return true;" ';

  return $onload;
}

sub entrymethod {
  my ( $authcode, $cardextra ) = @_;

  my ( $entry, $entrymethod );
  my %entrymap = ( '0', 'Bad Swipe', '1', 'Swiped', '2', 'Swiped' );
  my %location = (
    'evertec',   '8',   'fdms',    '32', 'fdmsemvcan',   '25', 'fdmsintl',  '285', 'fdmsnorth', '25', 'fdmsomaha', '22', 'fifththird', '54', 'global', '56',
    'globalctf', '108', 'mercury', '56', 'paytechtampa', '87', 'planetpay', '186', 'rbc',       '38', 'nova',      '15', 'elavon',     '15'
  );

  if ( $location{$smps::processor} ne "" ) {
    $entry = substr( $authcode, $location{$smps::processor}, 1 );
  } elsif ( $smps::processor =~ /^(paytechsalem|visanet)$/ ) {
    $entry = $cardextra;
  }
  if ( exists $entrymap{$entry} ) {
    $entrymethod = $entrymap{$entry};
  } else {
    $entrymethod = "Keyed";
  }

  return $entrymethod;
}

sub logfilter_in {
  my ( $key, $val ) = @_;

  if ( $key =~ /^(orderid|refnumber|certitaxid)$/i ) {
    return ( $key, $val );
  }

  if ( $key =~ /([3-7]\d{13,19})/ ) {
    $key =~ s/([3-7]\d{13,19})/&logfilter_sub($1)/ge;
  }

  if ( $val =~ /([3-7]\d{12,19})/ ) {
    $val =~ s/([3-7]\d{13,19})/&logfilter_sub($1)/ge;
  }

  return ( $key, $val );
}

sub logfilter_sub {
  my ($stuff) = @_;

  my $luhntest = &miscutils::luhn10($stuff);
  if ( $luhntest eq "success" ) {
    $stuff =~ s/./X/g;
  }

  return $stuff;
}

sub getAdjustmentFlags {
  my $adjustmentFlag = 0;
  my $surchargeFlag  = 0;
  my $feeFlag        = 0;
  my $coa            = new PlugNPay::COA($smps::username);

  if ( $coa->getEnabled() ) {
    $adjustmentFlag = 1;
    if ( $coa->isSurcharge() ) {
      $surchargeFlag = 1;
    }
    if ( $coa->isFee() ) {
      $feeFlag = 1;
    }
  }
  return ( $adjustmentFlag, $surchargeFlag, $feeFlag );
}

sub loadMultipleAdjustments {
  my $orderIDs = shift;

  my $adjustmentLog = new PlugNPay::Transaction::Logging::Adjustment();
  $adjustmentLog->setGatewayAccount($smps::username);
  my $adjustments = $adjustmentLog->loadMultiple($orderIDs);

  return $adjustments;
}

sub enabledInAdjustmentTable {
  my $adjustmentSettings = new PlugNPay::Transaction::Adjustment::Settings($smps::username);
  if ( $adjustmentSettings->isSetup() ) {
    if ( $adjustmentSettings->getEnabled() ) {
      return 1;
    }
  }
  return 0;
}

sub logToDataLog {
  my $logData = shift;
  my $logger = new PlugNPay::Logging::DataLog( { collection => 'smps' } );
  $logger->log($logData);
}

1;
