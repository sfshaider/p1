package security;

# ***** VERY IMPORTANT NOTE *****
# Do not validate the master user's security level by "==" or "!=" statements
#
# Using statements of:  if ($seclevel == 0)  {...}     [WRONG]
# Are not the same as:  if ($seclevel eq '0') {...}    [CORRECT]
#
# Only when the security level is the '0' character, does it mean the user is a master login
# When the security level is blank/null, it means the user was never correctly stored to the acl_login database
# If you cannot validate their security level, please default the security level to '12' for security reasons.
use strict;
use POSIX qw/strftime/;

use pnp_environment;
use miscutils;
use SHA;
use CGI;
use constants qw(%countries %USstates %USstates %USterritories %CNprovinces);
use sysutils;
use NetAddr::IP;
use PlugNPay::Kiosk;
use PlugNPay::UserDevices;
use PlugNPay::Util::Captcha::ReCaptcha;
use PlugNPay::Username;
use PlugNPay::Password;
use PlugNPay::Logging::MessageLog;
use PlugNPay::API::Key;
use PlugNPay::ResponseLink;
use PlugNPay::RemoteClient;
use PlugNPay::MobileClient;
use PlugNPay::GatewayAccount;
use PlugNPay::GatewayAccount::Services;
use PlugNPay::Features;
use PlugNPay::Email;
use PlugNPay::Reseller;
use PlugNPay::Authentication::Login;
use PlugNPay::Logging::DataLog;


sub new {
  my $type = shift;

  ## allow Proxy Server to modify ENV variable 'REMOTE_ADDR'
  if ( $ENV{'HTTP_X_FORWARDED_FOR'} ne '' ) {
    $ENV{'REMOTE_ADDR'} = $ENV{'HTTP_X_FORWARDED_FOR'};
  }

  if ( ( $ENV{'REDIRECT_LOGIN'} ne '' ) && ( $ENV{'LOGIN'} eq '' ) ) {
    $ENV{'LOGIN'} = $ENV{'REDIRECT_LOGIN'};
  }
  if ( ( $ENV{'REDIRECT_TEMPFLAG'} ne '' ) && ( $ENV{'TEMPFLAG'} eq '' ) ) {
    $ENV{'TEMPFLAG'} = $ENV{'REDIRECT_TEMPFLAG'};
  }

  if ( $ENV{'SEC_LEVEL'} > 4 ) {
    my $message = 'Invalid Security Level';
    &response_page($message);
  }

  @security::source = @_;
  $security::source = $security::source[0];

  if ( $security::source eq 'reseller' ) {
    $security::path_cgi = "$ENV{'SCRIPT_NAME'}";
  } else {
    $security::path_cgi = "/admin/security.cgi";
  }

  my $data = new CGI;

  %security::query         = ();
  %security::login_feature = ();    # holds sub-login specific feature settings

  @security::new_areas = ();

  @security::hashvariables     = ( 'publisher-name', 'orderID', 'card-amount', 'currency', 'FinalStatus' );
  @security::authhashvariables = ( 'publisher-name', 'orderID', 'card-amount', 'acct_code' );
  %security::areas_hash        = ();
  %security::areas             = ();

  @security::encpayload = ( 'publisher-name', 'ipaddress', 'orderID' );

  $security::reseller = '';

  $security::unpw_maxlength     = 20;
  $security::unpw_minlength     = 10;
  $security::remotepw_minlength = 9;
  $security::error              = 0;
  $security::reloginflag        = 0;

  @security::deletelist = ();

  if ( $ENV{'LOGIN'} =~ / (\w*)$/ ) {
    $ENV{'LOGIN'} = $1;
  }

  if ( $ENV{'LOGIN'} ne '' ) {
    $security::login = $ENV{'LOGIN'};
  } else {
    $security::login = $ENV{'REMOTE_USER'};
  }

  $security::remote_pwd_prefixes = "rc_|mobi_|ez_|aff_";                               # list of remote password type prefixes

  $security::error        = '';
  $security::error_string = '';

  $security::acl_dirarray = {};                                                        # HoA ref, used in conjuction with 'list_acl' sub-function
  $security::acl_db_login = {};                                                        # HoH ref, used in conjuction with 'list_acl' sub-function

  my $gatewayAccount = new PlugNPay::GatewayAccount( $ENV{'REMOTE_USER'} );
  $security::reseller = $gatewayAccount->getReseller();
  $security::status   = $gatewayAccount->getStatus();
  $security::company  = $gatewayAccount->getCompanyName();

  my $accountfeatures = new PlugNPay::Features( $ENV{'REMOTE_USER'}, 'general' );
  $security::features = $accountfeatures;

  my @ip_deletelist      = ();
  my @sitekey_deletelist = ();
  my @apikey_deletelist  = ();

  my @params = $data->param;
  @security::new_areas = $data->param('new_areas');
  $security::function  = $data->param('function');
  foreach my $param (@params) {
    if ( $param =~ /^delete_/ ) {
      my $di = substr( $param, 7 );
      if ( $security::function eq 'delete_user' ) {
        $di =~ s/[^a-zA-Z0-9\@\+\.\_]//g;
        push( @security::deletelist, $di );
      } elsif ( $security::function eq 'delete_ip' ) {
        $di =~ s/[^0-9\.]//g;
        push( @ip_deletelist, $di );
      } elsif ( $security::function eq 'delete_sitekey' ) {
        push( @sitekey_deletelist, $di );
      } elsif ( $security::function eq 'delete_multi_apikey' ) {
        push( @apikey_deletelist, $di );
      }
    } else {
      $security::query{$param} = $data->param($param);
    }
    if ( ( $param eq 'func' ) && ( $security::query{$param} ) ) {
      $security::function = $data->param($param);
      $security::query{'function'} = $security::query{$param};
    }
  }

  ## Filters

  # filter function
  $security::query{'function'} =~ s/[^a-zA-Z0-9_]//g;
  $security::function =~ s/[^a-zA-Z0-9_]//g;
  $security::query{'func'} =~ s/[^a-zA-Z0-9_]//g;

  if ( exists $security::query{'login'} ) {
    $security::query{'login'} =~ s/[^a-zA-Z0-9]//g;
  }
  if ( exists $security::query{'temp'} ) {
    $security::query{'temp'} =~ s/[^0-9]//g;
  }
  if ( exists $security::query{'seclevel'} ) {
    $security::query{'seclevel'} =~ s/[^0-9]//g;
  }
  if ( exists $security::query{'email'} ) {
    $security::query{'email'} =~ s/[^a-zA-Z0-9\_\-\@\.]//g;
  }
  if ( exists $security::query{'ipaddress'} ) {
    $security::query{'ipaddress'} =~ s/[^0-9.]//g;
  }
  if ( exists $security::query{'g-recaptcha-response'} ) {
    $security::query{'g-recaptcha-response'} =~ s/[^a-zA-Z0-9\_\-]//g;
  }
  if ( exists $security::query{'merchant'} ) {
    $security::query{'merchant'} =~ s/[^a-zA-Z0-9]//g;
  }
  if ( exists $security::query{'newpw'} ) {
    $security::query{'newpw'} =~ s/[^a-zA-Z0-9\@\+]//g;
  }
  if ( exists $security::query{'remotepwd_random'} ) {
    $security::query{'remotepwd_random'} =~ s/[^1]//g;
  }
  if ( exists $security::query{'hashkey'} ) {
    $security::query{'hashkey'} =~ s/[^a-zA-Z0-9\-\_\|\ ]//g;
  }

  my ( $security_test, $security_test_reason ) = &security_test();

  my $messageLog = new PlugNPay::Logging::MessageLog();

  my $datetime = gmtime(time);
  my $debugInformation =
    "DATE:$datetime, LOGIN:$security::login, FUNC:$security::function, RU:$ENV{'REMOTE_USER'}, IP:$ENV{'REMOTE_ADDR'}, SCRIPT:$ENV{'SCRIPT_NAME'},  PID:$$, HOST:$ENV{'SERVER_NAME'}, UA:$ENV{'HTTP_USER_AGENT'}, SL:$ENV{'SEC_LEVEL'}, REASON:$security_test_reason, ";
  foreach my $param (@params) {
    my $s = $data->param($param);
    if ( $param =~ /passwrd/ ) {
      $s = 'X' x length($s);
    }
    if ( $param =~ /^passwrd1$/ ) {
      next;
    }
    $debugInformation .= "$param:$s, ";
  }
  $debugInformation .= "\n";

  $messageLog->log($debugInformation);

  ### DCP - 20120712
  if ( $security_test ne '' ) {
    ## Exit with Error
    my $message = 'Invalid Request';
    &response_page($message);
  }

  $security::function = $security::query{'function'};

  if ( $security::query{'card-country'} eq '' ) {
    $security::query{'card-country'} = 'US';
  }

  my $loginInfo = getLoginInfo($security::login);

  $security::login    = $loginInfo->{'login'};
  $security::username = $loginInfo->{'account'};
  $security::seclevel = $loginInfo->{'securityLevel'};

  $ENV{'LOGIN'} = $security::login;

  if ( $security::username eq '' ) {
    $security::username = $security::login;
  }

  if ( defined $security::query{'login'} ) {
    my $loginInfo = {};
    eval {
      $loginInfo = getLoginInfo($security::query{'login'});
    };
    my $testusername = $loginInfo->{'account'};
    my $testseclevel = $loginInfo->{'securityLevel'};

    if ( $security::function ne 'add_user' ) {
      if ( $testusername eq '' ) {
        ## Exit with Error Message
        my $message = 'Invalid Value for Login Parameter';
        &response_page($message);
      }
    }
  }

  if ( $security::source ne 'reseller' ) {
    if ( ( $security::reseller =~ /(electro|webassis)/ ) && ( $security::username !~ /performanc3/ ) ) {
      %security::areas      = ( '/admin', 'ADMIN' );
      %security::areas_hash = ( 'ADMIN',  '/admin' );
    } elsif ( $security::reseller =~ /(arcourt|arutil|okcourt|okutilit)/ ) {
      %security::areas      = ( '/admin', 'ADMIN',  '/admin/courtpay', 'COURTPAY' );
      %security::areas_hash = ( 'ADMIN',  '/admin', 'COURTPAY',        '/admin/courtpay' );
    } else {
      %security::areas      = ( '/admin', 'ADMIN' );
      %security::areas_hash = ( 'ADMIN',  '/admin' );
    }

    if ( $ENV{'SEC_LEVEL'} eq '0' ) {
      @security::seclevels = ( '0', '4', '7', '8', '9', '11', '12', '13', '14' );
      %security::seclevels =
        ( '0', 'Master/Admin', '4', 'Full Access', '7', 'Hide Credit Card', '8', 'No credits', '9', 'Reports Only', '11', 'Developer', '12', 'Docs Only', '13', 'Virtual Term', '14', 'Order Entry Only' );
    } else {
      @security::seclevels = ( '0', '4', '7', '8', '9', '11', '12', '13' );
      %security::seclevels = ( '0', 'Master/Admin', '4', 'Full Access', '7', 'Hide Credit Card', '8', 'No credits', '9', 'Reports Only', '11', 'Developer', '12', 'Docs Only', '13', 'Virtual Term' );
    }
    %security::temp_hash = ( '1', 'SET' );
    &auth( $security::username, $security::subacct );
  } else {
    %security::areas      = ( '/reseller', 'RESELLER' );
    %security::areas_hash = ( 'RESELLER',  '/reseller' );
    @security::seclevels  = ( '4',         '7' );
    %security::seclevels  = ( '0',         'Master', '4', 'Full Access', '7', 'Risk Setting Only' );
    %security::temp_hash  = ( '1',         'SET' );
    &auth( $security::username, $security::subacct );
  }

  if ( scalar @ip_deletelist > 0 ) {
    &delete_ip(@ip_deletelist);
  }

  if ( scalar @sitekey_deletelist > 0 ) {
    &delete_sitekey(@sitekey_deletelist);
  }

  if ( scalar @apikey_deletelist > 0 ) {
    &delete_multi_apikey(@apikey_deletelist);
  }

  return [], $type;
}

sub details {
  my $loginInfo = getLoginInfo($security::login);
  $security::username = $loginInfo->{'account'};
  $security::seclevel = $loginInfo->{'securityLevel'};
}

# usernames will not be deleted, but access will be removed
sub delete_acl {
  # check to se if there is something to do.
  if ( @security::deletelist <= 0 ) {
    return;
  }

  foreach my $var (@security::deletelist) {
    if ( $var eq $security::username ) {
      next;
    }

    my $loginInfo = getLoginInfo($var);
    if ( $loginInfo->{'account'} eq $security::username ) {
      my $loginClient = new PlugNPay::Authentication::Login({
        login => $var
      });
      $loginClient->setRealm('PNPADMINID');
      $loginClient->setDirectories({
        directories => []
      });
    }
  }
}

sub delete_ip {
  my (@ip_deletelist) = @_;
  my ($username);
  if ( $ENV{'LOGIN'} ne '' ) {
    $username = $ENV{'LOGIN'};
  } else {
    $username = $security::username;
  }

  my $remoteClient = new PlugNPay::RemoteClient($username);
  foreach my $var (@ip_deletelist) {
    $var =~ s/[^0-9\.]//g;
    if ( $var =~ /^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$/ ) {
      $remoteClient->removePermittedNetworkAddress($var);
    }
  }
  $remoteClient->save();
}

sub list_acl {
  my $i = 0;

  # clear sublogin data
  %security::login = ();
  $security::acl_dirarray = {};
  $security::acl_db_login = {};

  if ( $security::seclevel eq '0' ) {
    # user is master sec level, so do all logins that belong to gateway account
    my $loginClient = new PlugNPay::Authentication::Login();
    $loginClient->setRealm('PNPADMINID');
    my $result = $loginClient->getLoginsForAccount({
      account => $security::username
    });

    if (!$result) {
      die('failed to load logins for account from authentication service');
    }

    my $logins = $result->get('logins');

    foreach my $login (@{$logins}) {
      # suppress alternate remote client and mobile passwords
      next if $login =~ /\d_/;
      my $loginUsername = $login->{'login'};
      $security::login{$loginUsername}                      = 1;
      $security::acl_dirarray->{$loginUsername . 'area'}    = $login->{'acl'};
      $security::acl_db_login{$loginUsername}->{'login'}    = $login->{'login'};
      $security::acl_db_login{$loginUsername}->{'seclevel'} = $login->{'securityLevel'};
      $security::acl_db_login{$loginUsername}->{'temp'}     = $login->{'passwordIsTemporary'};
    }
  } else {
    my $login = getLoginInfo($security::login);

    # clear list of sublogins
    %security::login = ();

    my $loginUsername = $login->{'login'};
    $security::login{$loginUsername}                      = 1;
    $security::acl_dirarray->{$loginUsername . 'area'}    = $login->{'acl'};
    $security::acl_db_login{$loginUsername}->{'login'}    = $login->{'login'};
    $security::acl_db_login{$loginUsername}->{'seclevel'} = $login->{'securityLevel'};
    $security::acl_db_login{$loginUsername}->{'temp'}     = $login->{'passwordIsTemporary'};
  }
}

sub list_ip {
  @security::ipaddress = ();
  my $username = $security::username;

  my $gatewayAccount = new PlugNPay::GatewayAccount($username);
  $security::bypassipcheck = $gatewayAccount->canBypassIpCheck();
  $security::noreturns     = $gatewayAccount->canProcessCredits();

  my $remoteClient = new PlugNPay::RemoteClient($username);

  foreach my $db_ipaddress ( keys %{ $remoteClient->getPermittedNetworkAddresses() } ) {
    my $db_netmask = $remoteClient->getPermittedNetworkAddresses()->{"$db_ipaddress"};

    if ( $db_netmask eq '' ) {
      $db_netmask = '32';
    }
    $db_ipaddress =~ /^(\d{1,3})\./;
    if ( $1 eq '555' ) {
      $security::rempasswd = $db_ipaddress;
      next;
    }

    if ( $db_ipaddress =~ /\// ) {

      # use the limit fool
      ($db_ipaddress) = split( /\//, $db_ipaddress, 1 );
    }

    push( @security::ipaddress, $db_ipaddress );
    $security::netmasks{$db_ipaddress} = $db_netmask;
  }
}

# returns 1 if login was loaded, 0 otherwise
sub details_acl {
  # if TEMPFLAG is 1, override $query{'login'} with $security::login.
  # otherwise, prefer $query{'login'} over $security::login
  if ( $ENV{'TEMPFLAG'} == 1 ) {
    $security::query{'login'} = $security::login;
  } else {
    $security::query{'login'} = defined($security::query{'login'}) ? $security::query{'login'} : $security::login;
  }
  $security::query{'login'} =~ s/[^a-zA-Z0-9]//g;
  my $loginInfo = getLoginInfo($security::query{'login'});

  $security::query{'seclevel'} = $loginInfo->{'securityLevel'};
  $security::query{'temp'}     = $loginInfo->{'passwordIsTemporary'} ? 1 : 0;

  # set a security level of 12, when seclevel was not specified
  if ( $security::query{'seclevel'} eq '' ) {
    $security::query{'seclevel'} = 12;
  }

  # get login's email address
  my $usernameObj = new PlugNPay::Username( $security::query{'login'} );
  $security::query{'email'} = $usernameObj->getSubEmail;

  # set login's specific feature settings
  %security::login_feature = %{ $loginInfo->{'features'} };

  $security::query{'curbun'} = $security::login_feature{'curbun'};

  my $dirarray = $security::query{'login'} . 'area';
  $security::acl_dirarray->{$dirarray} = ();

  my $acl = $loginInfo->{'acl'};

  foreach my $directory ( @{ $acl } ) {
    push( @security::new_areas, "$directory" );
    if ( $directory =~ /mservices/ ) {
      $security::areas{$directory} = 'MSERVICES';
      $security::areas_hash{'MSERVICES'} = "$directory";
    }
  }

  if (defined $loginInfo->{'login'}) {
    return 1;
  }
  return 0;
}

sub update_distclient {
  my ($username);
  if ( $ENV{'LOGIN'} ne '' ) {
    $username = $ENV{'LOGIN'};
  } else {
    $username = $security::username;
  }

  $security::query{'distclient'} =~ s/[^a-z]//g;
  if ( $security::query{'distclient'} eq 'yes' ) {
    my $dbh = &miscutils::dbhconnect('pnpmisc');
    my $sth = $dbh->prepare(
      q{
        UPDATE customers
        SET bypassipcheck=?
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute( $security::query{'distclient'}, $security::username ) or die "Can't execute: $DBI::errstr";
    $sth->finish;
    $dbh->disconnect;

    $security::bypassipcheck = 'yes';
  }
}

sub update_noreturns {
  my ($username);
  if ( $ENV{'LOGIN'} ne '' ) {
    $username = $ENV{'LOGIN'};
  } else {
    $username = $security::username;
  }

  my $dbh = &miscutils::dbhconnect('pnpmisc');

  my $sth = $dbh->prepare(
    q{
      UPDATE customers
      SET noreturns='yes'
      WHERE username=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth->execute($security::username) or die "Can't execute: $DBI::errstr";
  $sth->finish;

  $dbh->disconnect;
}

# limit reseller sourced requests to only their reseller username
sub aclLimitResellerChanges {
  if ( $security::source eq 'reseller' && $security::query{'merchant'} ne $ENV{'REMOTE_USER'} ) {
    $security::query{'merchant'} = $ENV{'REMOTE_USER'};
    $security::query{'login'}    = $ENV{'REMOTE_USER'};
  }
}

sub aclCheckForExistingLogin {
  my $loginToCheck = shift;    # $security::query{'login'}
  my $loggedInAccount = shift; # $ENV{'REMOTE_USER'}

  my $status = new PlugNPay::Util::Status(1);

  my $loginInfo = {};
  eval {
    $loginInfo = getLoginInfo($loginToCheck);
  };

  if ( defined $loginInfo->{'login'} && $loginInfo->{'account'} ne $loggedInAccount ) {
    ##  Bounce as Login Already Exists under different Username
    $status->setFalse();
    $status->setError("Login is already in use");
  }

  return ($loginInfo, $status);
}

sub aclCreateDirectoriesList {
  my (%new_areas);
  foreach my $var (@security::new_areas) {
    $var =~ s/[^a-zA-Z0-9\/]//g;
    $new_areas{$var} = 1;
  }
  if ( $security::query{'seclevel'} eq '0' ) {
    if ( $security::source eq 'reseller' ) {
      $new_areas{'/reseller'} = 1;
    } elsif ( $security::status eq 'reseller' ) {
      $new_areas{'/reseller'} = 1;
    } else {
      $new_areas{'/admin'} = 1;
    }
  }

  my @fresh_areas;
  foreach my $var ( keys %new_areas ) {
    if ( ( $security::areas_hash{$var} =~ /\w/ ) && ( $security::query{'seclevel'} < 14 ) ) {
      push @fresh_areas, $security::areas_hash{$var};
    }
  }

  return \@fresh_areas
}

sub add_acl {
  aclLimitResellerChanges();

  my (undef, $loginCheckResult) = aclCheckForExistingLogin($security::query{'login'},$ENV{'REMOTE_USER'});
  if (!$loginCheckResult) {
    response_page($loginCheckResult->getError());
    return
  }

  my $loginClient = new PlugNPay::Authentication::Login({
    login => $security::query{'login'}
  });
  $loginClient->setRealm('PNPADMINID');

  my $directories = aclCreateDirectoriesList();

  my $result = $loginClient->createLogin({
      login => $security::query{'login'},
      account => $ENV{'REMOTE_USER'},
      securityLevel => $security::query{'seclevel'},
      password => $security::query{'passwrd1'},
      emailAddress => $security::query{'email'},
      passwordIsTemporary => $security::query{'temp'},
      directories => $directories
  });

  if (!$result) {
    response_page($result->getError());
    return
  }
}

sub update_acl {
  aclLimitResellerChanges();

  my ($loginInfo, $loginCheckResult) = aclCheckForExistingLogin($security::query{'login'},$ENV{'REMOTE_USER'});
  if (!$loginCheckResult) {
    response_page($loginCheckResult->getError());
    return
  }

  if ( $ENV{'TEMPFLAG'} == 1 ) {
    $security::query{'newpw'} = 'yes';
  }

  if ( $security::query{'newpw'} eq 'yes' ) {
    ## force tempflag, when master user resets password of sub-login
    if ( ( $ENV{'SEC_LEVEL'} eq '0' ) && ( $security::username ne $security::query{'login'} ) ) {
      $security::query{'temp'} = 1;
    }
  }

  if ($loginInfo->{'login'} eq $ENV{'LOGIN'} ) {
    # ensure current password is not empty
    if (!defined $security::query{'oldpasswrd'} || $security::query{'oldpasswrd'} eq '') {
      response_page('Current password is required for this action');
      return;
    }
  }

  if ( $security::query{'login'} ne $security::username && $security::query{'seclevel'} eq '0' ) {
    ##  Bounce as need to be logged in as Master to use Sec LEvel 0.
    my $message = 'Invalid Security Level';
    response_page($message);
    return;
  }

  if ( $security::seclevel > $loginInfo->{'securityLevel'} ) {
    return;
  }
  
  # force tempflag to remain set, should merchant attempt to disable it for one of their sub-logins.
  if ( ( $ENV{'TEMPFLAG'} != 1 ) && ( $loginInfo->{'passwordIsTemporary'} == 1 ) && ( $security::query{'newpw'} ne 'yes' ) && ( $security::username ne $security::query{'login'} ) ) {
    $security::query{'temp'} = 1;
  }

  if ( $loginInfo->{'securityLevel'} eq '0' ) {
    # retain seclevel '0', if already specified within given login's record
    $security::query{'seclevel'} = 0;
  } elsif ( $loginInfo->{'securityLevel'} ne '' && $security::query{'seclevel'} eq '' ) {
    # assume currently set seclevel, when one is not given
    $security::query{'seclevel'} = $loginInfo->{'securityLevel'};
  } elsif ( $security::query{'seclevel'} eq '' && $loginInfo->{'securityLevel'} eq '' ) {
    # assume a security level of 12, when user's seclevel cannot be determined
    $security::query{'seclevel'} = 12;
  }

  # force email field to null value for master login, to prevent routing of lost password requests to alternative email addresses
  if ( ( $security::query{'seclevel'} eq '0' ) && ( $security::username eq $security::query{'login'} ) ) {
    $security::query{'email'} = '';
  }

  my $loginClient = new PlugNPay::Authentication::Login({
    login => $security::query{'login'}
  });
  $loginClient->setRealm('PNPADMINID');

  if ( $security::login !~ /^(pnpdemo|demouser)$/ ) {
    if ( $security::seclevel ne '0' ) {
      my $passwordSetResult = $loginClient->setPassword({
        password => $security::query{'passwrd1'},
        passwordIsTemporary => $security::query{'temp'}
      });

      if (!$passwordSetResult) {
        response_page($passwordSetResult->getError());
        return;
      }

      if ( $security::query{'newpw'} eq 'yes' ) {
        if ( $security::login eq $ENV{'LOGIN'} ) {
          $security::reloginflag = 1;
        }
        delete $ENV{'TEMPFLAG'};
      } else {
        if ( $security::username ne $security::query{'login'} ) {
          # update sub-login's email address
          &update_sub_email( $security::query{'login'}, $security::query{'email'} );
        }

        if ( ( $security::query{'seclevel'} > 0 ) && ( $security::username ne $security::query{'login'} ) ) {
          my $loginFeatures = $loginInfo->{'features'};

          # update sub-login's features settings
          my $updatedFeatures = update_sub_features($loginFeatures, \%security::query);

          $loginClient->setFeatures({
            features => $updatedFeatures
          });
        }
      }
    } else {
      if ( $security::query{'newpw'} eq 'yes' && $security::query{'passwrd1'} ne '' ) {
        my $passwordUpdateResult = $loginClient->setPassword({
          password => $security::query{'passwrd1'},
          currentPassword => $security::query{'oldpasswrd'},
          passwordIsTemporary => 0
        });
        if ( !$passwordUpdateResult ) {
          response_page($passwordUpdateResult->getError());
          return;
        }

        if ( $security::query{'login'} eq $ENV{'LOGIN'} ) {
          $security::reloginflag = 1;
        }

        # update sublogin's email address
        &update_sub_email( $security::query{'login'}, $security::query{'email'} );

        delete $ENV{'TEMPFLAG'};
      } else {
        # set/clear temp flag
        my $val = $security::query{'temp'};

        if ($security::query{'temp'}) {
          $loginClient->setTemporaryPasswordMarker();
        }

        $loginClient->setSecurityLevel({
          securityLevel => $security::query{'seclevel'}
        });

        # update login's email address
        &update_sub_email( $security::query{'login'}, $security::query{'email'} );

        if ( ( $security::query{'seclevel'} > 0 ) && ( $security::username ne $security::query{'login'} ) ) {
          my $loginFeatures = $loginInfo->{'features'};

          # update sub-login's features settings
          my $updatedFeatures = update_sub_features($loginFeatures, \%security::query);

          $loginClient->setFeatures({
            features => $updatedFeatures
          });
        }
      }
    }

    if ( ( $security::query{'newpw'} eq 'yes' ) && ( $security::query{'passwrd1'} ne '' ) ) {
      ## email merchant to confirm password change

      # get merchant's email address
      my $gatewayAccount  = new PlugNPay::GatewayAccount($security::username);
      my $merchantContact = $gatewayAccount->getMainContact();
      my $merch_email     = $merchantContact->getEmailAddress();

      # get the domains for the email...
      my %domains = &getdomains($security::username);

      # create password update confirm email
      my $emailmessage = "Dear Merchant,\n\n";
      $emailmessage .= "\n";
      $emailmessage .= "Our records indicate the password associated to your login username \'$security::query{'login'}\' has recently been changed.\n";
      $emailmessage .= "This email is to confirm this change has taken place.\n";
      $emailmessage .= "\n";
      $emailmessage .= "If you have not performed this password change yourself or authorized your staff to change your login password on your behalf, please contact us immediately for assistance.\n";
      $emailmessage .= "\n";
      $emailmessage .= "Thank you,\n";
      $emailmessage .= "Support Staff\n";

      # send customer the notification email
      my $emailer = new PlugNPay::Email();
      $emailer->setVersion('legacy');
      $emailer->setGatewayAccount($security::username);
      $emailer->setFormat('text');
      $emailer->setTo($merch_email);
      $emailer->setFrom("support\@$domains{'emaildomain'}");
      $emailer->setSubject('Password Change Confirmation');
      $emailer->setContent($emailmessage);
      $emailer->send();
    }
  }

  if ( $security::seclevel eq '0' ) {
    if ( $security::query{'function'} ne 'update_passwrd' ) {
      if ($security::query{'function'} ne 'update_user') {
        my $passwordSetResult = $loginClient->setPassword({
          password            => $security::query{'passwrd1'},
          passwordIsTemporary => 0
        });

        if (!$passwordSetResult) {
          response_page($passwordSetResult->getError());
          return;
        }
      }

      my $directories = aclCreateDirectoriesList();

      $loginClient->setDirectories({
        directories => $directories
      });
    }
  }
}

sub update_ip {
  my ($username);
  $username = $security::username;    ### DCP 20100720  Commented out code so IP is always stored under master account.
  my $ip = NetAddr::IP->new("$security::query{'ipaddress'}/$security::query{'netmask'}");
  my ( $firstip, $m );
  if ( defined $ip ) {
    ( $firstip, $m ) = split( /\//, $ip->first() );
  } else {
    $firstip = $security::query{'ipaddress'};

    #$netmask = '32';
  }

  my $dbh = &miscutils::dbhconnect('pnpmisc');
  my $sth = $dbh->prepare(
    q{
      SELECT ipaddress
      FROM ipaddress
      WHERE username=?
      AND ipaddress=?
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth->execute( $username, $firstip ) or die "Can't execute: $DBI::errstr";
  my ($test) = $sth->fetchrow;
  $sth->finish;

  if ( $test eq '' ) {
    ## Insert
    my $sth = $dbh->prepare(
      q{
        INSERT INTO ipaddress
        (username,ipaddress,netmask)
        VALUES (?,?,?)
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute( $username, $firstip, $security::query{'netmask'} ) or die "Can't prepare: $DBI::errstr";
    $sth->finish;
  } else {
    ## Update
    my $sth = $dbh->prepare(
      q{
        UPDATE ipaddress
        SET netmask=?
        WHERE username=?
        AND ipaddress=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute( $security::query{'netmask'}, $username, $firstip ) or die "Can't execute: $DBI::errstr";
    $sth->finish;

  }

  $dbh->disconnect;

  #my $message = "IP Address Information has been entered into security database.";
  #&response_page($message,'yes');
}

sub response_page {
  my ( $message, $close ) = @_;

  print "Content-Type: text/html\n";
  print "X-Content-Type-Options: nosniff\n";
  print "X-Frame-Options: SAMEORIGIN\n\n";

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta http-equiv=\"Pragma\" content=\"no-cache\">\n";
  print "<meta http-equiv=\"Cache-Control\" content=\"no-cache\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<link href=\"/css/style_security.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  print "<title>Response Page</title>\n";

  my $autoclose;
  if ( $close eq 'auto' ) {
    $autoclose = "onLoad=\"update_parent();\"\n";
  } elsif ( $close eq 'relogin' ) {
    $autoclose = "onLoad=\"update_parent1();\"\n";
  }

  print "<script type=\"text/javascript\">\n";
  print "<\!-- Start Script\n";

  print "function closeresults() {\n";
  print "  resultsWindow = window.close('results');\n";
  print "}\n\n";

  print "function update_parent() {\n";
  print "  window.opener.location = '$security::path_cgi';\n";
  print "  self.close();\n";
  print "}\n";

  print "function update_parent1() {\n";
  print "  window.opener.location = '/adminlogin.html';\n";
  print "  self.close();\n";
  print "}\n";

  print "function closewin() {\n";
  print "  self.close();\n";
  print "}\n";

  print "// end script-->\n";
  print "</script>\n";

  print "</head>\n";

  print "<body bgcolor=\"#ffffff\" $autoclose>\n";

  print "<table width=760 border=0 cellpadding=0 cellspacing=0 id=\"header\">\n";
  print "  <tr>\n";
  print "    <td colspan=2 align=left>";
  if ( $ENV{'SERVER_NAME'} eq 'pay1.plugnpay.com' ) {
    print "<img src=\"/css/global_header_gfx.gif\" width=760 alt=\"Plug 'n Pay Technologies - we make selling simple.\"  height=44 border=0>";
  } else {
    print "<img src=\"/images/global_header_gfx.gif\" alt=\"Corporate Logo\">";
  }
  print "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=2 align=left><img src=\"/css/header_bottom_bar_gfx.gif\" width=760 height=14></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table border=0 cellspacing=0 cellpadding=5 width=760>\n";
  print "  <tr>\n";
  print "    <td colspan=2><h1><a href=\"$ENV{'SCRIPT_NAME'}\">Security Administration</a> / $security::company</h1></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td>";

  print "<p>$message\n";

  if ( $close eq 'yes' ) {
    print "<p><div align=center><a href=\"javascript:update_parent();\">Close Window</a></div>\n";
  }

  my @now       = gmtime(time);
  my $copy_year = $now[5] + 1900;

  #print "</td>\n";
  #print "  </tr>\n";
  print "</table>\n";
  print "<table width=760 border=0 cellpadding=0 cellspacing=0 id=\"footer\">\n";
  print "  <tr>\n";
  print "    <td align=left><a href=\"mailto:support\@plugnpay.com\">support\@plugnpay.com</a></td>\n";
  print "    <td align=right>&copy; $copy_year, Plug and Pay Technologies, Inc.</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</body>\n";
  print "</html>\n";
  exit;
}

sub response_page_blank {
  my ( $message, $close ) = @_;

  print "Content-Type: text/html\n";
  print "X-Content-Type-Options: nosniff\n";
  print "X-Frame-Options: SAMEORIGIN\n\n";

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta http-equiv=\"Pragma\" content=\"no-cache\">\n";
  print "<meta http-equiv=\"Cache-Control\" content=\"no-cache\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<link href=\"/css/style_security.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  print "<title>Response Page</title>\n";

  my $autoclose;
  if ( $close eq 'auto' ) {
    $autoclose = "onLoad=\"update_parent();\"\n";
  } elsif ( $close eq 'relogin' ) {
    $autoclose = "onLoad=\"update_parent1();\"\n";
  }

  print "<script type=\"text/javascript\" src=\"/css/vt.js\"></script>\n";

  print "<script type=\"text/javascript\">\n";
  print "<\!-- Start Script\n";

  print "function update_parent() {\n";
  print "  window.opener.location = '$security::path_cgi';\n";
  print "  self.close();\n";
  print "}\n";

  print "function update_parent1() {\n";
  print "  window.opener.location = '/login/';\n";
  print "  self.close();\n";
  print "}\n";

  print "// end script-->\n";
  print "</script>\n";

  print "</head>\n";

  print "<body bgcolor=\"#ffffff\" $autoclose>\n";
  print "<table border=0 cellspacing=0 cellpadding=1 width=500>\n";
  print "<tr><td colspan=4>Working . . . . . . . . . . . . . . . . . </td></tr>\n";
  print "</table>\n";

  print "</body>\n";
  print "</html>\n";
  exit;
}

sub auth {
  my ( $username, $subacct ) = @_;

  my $gatewayAccountServices = new PlugNPay::GatewayAccount::Services($username);
  my $fraudtrack             = $gatewayAccountServices->getFraudTrack;
  my $membership             = $gatewayAccountServices->getMembership;
  my $refresh                = $gatewayAccountServices->getRefresh;
  my $easycart               = $gatewayAccountServices->getEasyCart;
  my $affiliate              = $gatewayAccountServices->getAffiliate;
  my $coupon                 = $gatewayAccountServices->getCoupon;
  my $fulfillment            = $gatewayAccountServices->getFulfillment;
  my $billpay                = $gatewayAccountServices->getBillPay;

  $security::subscription = 0;

  if ( $fulfillment == 1 ) {
    $security::areas{'/fulfillment'}     = 'FULFILLMENT';
    $security::areas_hash{'FULFILLMENT'} = '/fulfillment';
  }

  if ( ( $fraudtrack == 1 ) || ( $security::reseller =~ /(tri8inc)/ ) ) {
    $security::areas{'/admin/fraudtrack'} = 'FRAUDTRACK';
    $security::areas_hash{'FRAUDTRACK'}   = '/admin/fraudtrack';
  }

  if ( $billpay ne '' ) {
    $security::areas{'/admin/billpay'} = 'BILLPAY';
    $security::areas_hash{'BILLPAY'}   = '/admin/billpay';
  }

  if ( $coupon ne '' ) {
    $security::areas{'/admin/coupon'} = 'COUPON';
    $security::areas_hash{'COUPON'}   = '/admin/coupon';
  }

  if ( ( $membership ne '' ) || ( $refresh ne '' ) ) {
    my $tmp = "/payment/recurring/$username/admin";
    $security::areas{"$tmp"}              = 'SUBSCRIPTION';
    $security::areas_hash{'SUBSCRIPTION'} = "$tmp";
    $security::subscription               = 1;
  }

  if ( $easycart ne '' ) {
    $security::areas{'/easycart'}     = 'EASYCART';
    $security::areas_hash{'EASYCART'} = '/easycart';
  }

  if ( $affiliate ne '' ) {
    $security::areas{'/affiliate'}     = 'AFFILIATE';
    $security::areas_hash{'AFFILIATE'} = '/affiliate';
  }

  my $cnt = 1;

  if ( $ENV{'SEC_LEVEL'} eq '0' ) {
    my $loginInfo = getLoginInfo($security::username);
    my $acl = $loginInfo->{'acl'};

    foreach my $directory ( @{ $acl } ) {
      if ( $directory =~ /mservices/ ) {
        $security::areas{$directory} = 'MSERVICES';
        %security::areas_hash = ( %security::areas_hash, 'MSERVICES', "$directory" );
      }
    }

    # limit retention of custom directory paths to that given login (not from master username)
    my $cnt        = 1;
    if ($security::query{'login'} ne '') {
      my $loginInfo = undef;
      eval {
        $loginInfo = getLoginInfo($security::query{'login'});
      };

      if (!defined($loginInfo)) {
        my $acl = $loginInfo->{'acl'};

        foreach my $directory ( @{ $acl } ) {
          if ( ( $security::areas{"$directory"} !~ /\w/ ) && ( $security::function eq 'add_user' ) ) {    # if its not a known path, add to their custom list
                                                                                                          # create custom areas to preserve custom directory paths
            $security::areas{"$directory"}      = "CUSTOM$cnt";
            $security::areas_hash{"CUSTOM$cnt"} = "$directory";

            # add to selected areas, to preserve the entry
            push( @security::new_areas, "CUSTOM$cnt" );
            $cnt++;
          }
        }
      }
    }
  }

  ### Test to see if all areas in new_areas are 'allowed'
  my (%temphash);
  foreach my $area (@security::new_areas) {
    $temphash{$area} = 1;
  }
  ### Erase @security::new_areas
  @security::new_areas = ();
  ### Remove those selected areas that are not allowed.
  foreach my $area ( sort keys %temphash ) {
    if ( !exists $security::areas_hash{$area} ) {
      ## Area does not exist in allowd list delete.
      delete $temphash{$area};
    }
  }
  ### Repopulate @security::new_areas
  @security::new_areas = keys %temphash;
}

sub head {
  print "Content-Type: text/html\n";
  print "X-Content-Type-Options: nosniff\n";
  print "X-Frame-Options: SAMEORIGIN\n\n";

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta http-equiv=\"Pragma\" content=\"no-cache\">\n";
  print "<meta http-equiv=\"Cache-Control\" content=\"no-cache\">\n";
  print "<meta http-equiv=\"X-UA-Compatible\" content=\"IE=edge\" />\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<link href=\"/css/style_security.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  print "<title>Edit Items</title>\n";

  # js logout prompt
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/_js/jquery-1.10.2.min.js\"></script>\n";
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/_js/jquery_ui/jquery-ui.js\"></script>\n";
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/_js/admin/autologout.js\"></script>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"/javascript/jquery_ui/jquery-ui.css\">\n";

  print "<script type=\"text/javascript\">\n";
  print "/** Run with defaults **/\n";
  print "\$(document).ready(function(){\n";
  print "  \$(document).idleTimeout();\n";
  print "});\n";
  print "</script>\n";

  # end logout js

  print "<script type=\"text/javascript\" src=\"/css/vt.js\"></script>\n";
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/javascript/passwordStrengthCheck.js\"></script>\n";
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/javascript/securityAdmin.js\"></script>\n";

  if ( $security::function =~ /^(edit_passwrd|update_passwrd|add_new_user)$/ ) {
    print "<script type=\"text/javascript\">\n";
    print "jQuery(document).ready(function() { \n";
    print "  passwordStrengthCheck(); //call password check function\n";
    print "  jQuery('#passwordSubmitButton').attr('disabled','disabled'); //disable submit button\n";
    print "  jQuery('#passwordSubmitButton').css('opacity','0.3');\n";
    print "});\n";
    print "</script>\n";
  }

  my $captcha = new PlugNPay::Util::Captcha::ReCaptcha();
  print $captcha->headHTML();

  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";

  print "<table width=760 border=0 cellpadding=0 cellspacing=0 id=\"header\">\n";
  print "  <tr>\n";
  print "    <td colspan=2 align=left>";
  if ( $ENV{'SERVER_NAME'} =~ /plugnpay\.com/i ) {
    print "<img src=\"/images/global_header_gfx.gif\" width=760 alt=\"Plug 'n Pay Technologies - we make selling simple.\" height=44 border=0>";
  } else {
    print "<img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Logo\">\n";
  }
  print "</td>\n";
  print "  </tr>\n";

  if ( $security::reseller !~ /(webassis)/ ) {
    print "  <tr>\n";
    print "    <td align=left nowrap><a href=\"$ENV{'SCRIPT_NAME'}\">Home</a></td>\n";
    print "    <td align=right nowrap><!--<a href=\"/admin/logout.cgi\">Logout</a> &nbsp;\|&nbsp; --><a href=\"#\" onClick=\"popminifaq();\">Mini-FAQ</a></td>\n";
    print "  </tr>\n";
  }

  print "  <tr>\n";
  print "    <td colspan=2 align=left><img src=\"/css/header_bottom_bar_gfx.gif\" width=760 height=14></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table border=0 cellspacing=0 cellpadding=5 width=760>\n";
  print "  <tr>\n";
  print "    <td colspan=2><h1><a href=\"$ENV{'SCRIPT_NAME'}\">Security Administration</a> / $security::company</h1>\n";
}

sub tail {
  my @now       = gmtime(time);
  my $copy_year = $now[5] + 1900;

  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table width=760 border=0 cellpadding=0 cellspacing=0 id=\"footer\">\n";
  print "  <tr>\n";
  print
    "    <td align=left><a href=\"/admin/logout.cgi\" title=\"Click to log out\">Log Out</a> | <a href=\"javascript:change_win('/admin/helpdesk.cgi',600,500,'ahelpdesk')\">Help Desk</a> | <a id=\"close\" href=\"javascript:closewin();\" title=\"Click to close this window\">Close Window</a></td>\n";
  print "    <td align=right>\&copy; $copy_year, ";
  if ( $ENV{'SERVER_NAME'} =~ /plugnpay\.com/i ) {
    print "Plug and Pay Technologies, Inc.";
  } else {
    print "$ENV{'SERVER_NAME'}";
  }
  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</body>\n";
  print "</html>\n";
}

sub main {
  print <<EOF;
<table width="100%" border=0 cellspacing=0 cellpadding=3>
  <tr>
    <td align=center valign=top>
      <table width=80 height=50 border=1 cellpadding=0 cellspacing=0 bgcolor="#CCCCCC">
        <tr>
          <td><a href="$ENV{'SCRIPT_NAME'}\?function=show_unpw_menu"><img src="/images/admin_login_8050px.jpg" border="0" alt="Username/Password Configuration"></a></td>
        </tr>
      </table></td>
    <td valign=top><p><b><a href="$ENV{'SCRIPT_NAME'}\?function=show_unpw_menu">Username/Password Configuration</a></b><br>
      Manage administrative login information.<br>
      <a href="$ENV{'SCRIPT_NAME'}\?function=show_unpw_menu">Click here to begin</a></p></td>
  </tr>
EOF
  if ( $security::source ne 'reseller' ) {
    print <<EOF;
  <tr>
    <td align=center valign=top>
      <table width=80 height=50 border=1 cellpadding=0 cellspacing=0 bgcolor="#CCCCCC">
        <tr>
          <td><a href="$ENV{'SCRIPT_NAME'}\?function=show_transsec_menu"><img src="/images/acct_admin_8050px.jpg" border="0" alt="Transaction Security Configuration"></a></td>
        </tr>
      </table></td>
    <td valign=top><p><b><a href="$ENV{'SCRIPT_NAME'}\?function=show_transsec_menu">Transaction Security Configuration</a></b><br>
      Manage remote transaction security & access requirements.<br>
      <a href="$ENV{'SCRIPT_NAME'}\?function=show_transsec_menu">Click here to begin</a></p></td>
  </tr>
EOF

    if ( ( $security::reseller eq 'dydacom1' ) || ( $security::username eq 'videoageen' ) || ( $security::features->get('sec_rempasswd') == 1 ) ) {
      print <<EOF;
  <tr>
    <td align=center valign=top>
      <table width=80 height=50 border=1 cellpadding=0 cellspacing=0 bgcolor="#CCCCCC">
        <tr>
          <td><a href="$ENV{'SCRIPT_NAME'}\?function=show_transkey_menu"><img src="/images/config_8050px.jpg" border="0" alt="Transaction Key Configuration"></a></td>
        </tr>
      </table></td>
    <td valign=top><p><b><a href="$ENV{'SCRIPT_NAME'}\?function=show_transkey_menu">Transaction Key Configuration</a></b><br>
      Administrate your transaction key configuration.<br>
      <a href="$ENV{'SCRIPT_NAME'}\?function=show_transkey_menu">Click here to begin</a></p></td>
  </tr>
EOF
    }

    print <<EOF;
  <tr>
    <td align=center valign=top>
      <table width=80 height=50 border=1 cellpadding=0 cellspacing=0 bgcolor="#CCCCCC">
        <tr>
          <td><a href="$ENV{'SCRIPT_NAME'}\?function=show_verifyhash_menu"><img src="/images/reports_8050px.jpg" border="0" alt="Verification Hash"></a></td>
        </tr>
      </table></td>
    <td valign=top><p><b><a href="$ENV{'SCRIPT_NAME'}\?function=show_verifyhash_menu">Verification Hash</a></b><br>
      Administrate your verification hash configuration.<br>
      <a href="$ENV{'SCRIPT_NAME'}\?function=show_verifyhash_menu">Click here to begin</a></p></td>
  </tr>
EOF

    if ( $security::features->get('sec_kiosk') == 1 ) {
      print <<EOF;
  <tr>
    <td align=center valign=top>
      <table width=80 height=50 border=1 cellpadding=0 cellspacing=0 bgcolor="#CCCCCC">
        <tr>
          <td><a href="$ENV{'SCRIPT_NAME'}\?function=show_kiosk_menu"><img src="/images/news_8050px.jpg" border="0" alt="Kiosk Management"></a></td>
        </tr>
      </table></td>
    <td valign=top><p><b><a href="$ENV{'SCRIPT_NAME'}\?function=show_kiosk_menu">Kiosk Management</a></b><br>
      Administrate your kiosk IDs & other kiosk related settings.<br>
      <a href="$ENV{'SCRIPT_NAME'}\?function=show_kiosk_menu">Click here to begin</a></p></td>
  </tr>
EOF
    }

    print <<EOF;
  <tr>
    <td align=center valign=top>
      <table width=80 height=50 border=1 cellpadding=0 cellspacing=0 bgcolor="#CCCCCC">
        <tr>
          <td><a href="$ENV{'SCRIPT_NAME'}\?function=show_apikey_menu"><img src="/images/floatkey_8050px.jpg" border="0" alt="API Key Management"></a></td>
        </tr>
      </table></td>
    <td valign=top><p><b><a href="$ENV{'SCRIPT_NAME'}\?function=show_apikey_menu">API Key Management</a></b><br>
      Administrate your API Keys & other API related settings.<br>
      <a href="$ENV{'SCRIPT_NAME'}\?function=show_apikey_menu">Click here to begin</a></p></td>
  </tr>
EOF

    if ( $security::features->get('sec_device') == 1 ) {
      print <<EOF;
  <tr>
    <td align=center valign=top>
      <table width=80 height=50 border=1 cellpadding=0 cellspacing=0 bgcolor="#CCCCCC">
        <tr>
          <td><a href="$ENV{'SCRIPT_NAME'}\?function=show_device_menu"><img src="/images/news_8050px.jpg" border="0" alt="Device Management"></a></td>
        </tr>
      </table></td>
    <td valign=top><p><b><a href="$ENV{'SCRIPT_NAME'}\?function=show_device_menu">Device Management</a></b><br>
      Administrate your devices & other device related settings.<br>
      <a href="$ENV{'SCRIPT_NAME'}\?function=show_device_menu">Click here to begin</a></p></td>
  </tr>
EOF
    }
  }

  print "</table>\n";
  return;
}

sub unpw_menu {
  &list_acl();
  print "<table width=\"100%\" border=0 cellpadding=0 cellspacing=0>\n";
  &username_config_head();
  if ( $security::source ne 'reseller' || $security::login =~ /^(cynergy|plugnpay|worldwi1)$/ ) {
    &username_config_add_button();
  }
  &username_config_edit();
  if ( $security::source ne 'reseller' || $security::login =~ /^(cynergy|plugnpay|worldwi1)$/ ) {
    &username_config_delete();
  }
  if ( $security::source ne 'reseller' ) {
    &remoteclient_config_button();
    &mobileterm_config_button();
    &apikey_config();
  }
  print "</table>\n";
}

sub remoteclient_menu {
  if ( $security::source ne 'reseller' ) {
    print "<table width=\"100%\" border=0 cellpadding=0 cellspacing=0>\n";
    &remoteclient_config_head();
    &remoteclient_config();
    print "</table>\n";
  }
}

sub mobileterm_menu {
  if ( $security::source ne 'reseller' ) {
    print "<table width=\"100%\" border=0 cellpadding=0 cellspacing=0>\n";
    &mobileterm_config_head();
    &mobileterm_config();
    print "</table>\n";
  }
}

sub transsec_menu {
  &list_ip();
  if ( $security::source ne 'reseller' ) {
    print "<table width=\"100%\" border=0 cellpadding=0 cellspacing=0>\n";
    &ipaddress_config();
    &noreturns_config();
    &encpayload_config();
    &sitekey_config();
    &payscreens_cookie_config();
    print "</table>\n";
  }
}

sub transkey_menu {
  &list_ip();
  if ( ( $security::reseller eq 'dydacom1' ) || ( $security::username eq 'videoageen' ) || ( $security::features->get('sec_rempasswd') == 1 ) ) {
    print "<table width=\"100%\" border=0 cellpadding=0 cellspacing=0>\n";
    &rempasswd_config();
    print "</table>\n";
  }
}

sub verifyhash_menu {
  if ( $security::seclevel eq '0' ) {
    print "<table width=\"100%\" border=0 cellpadding=0 cellspacing=0>\n";
    &hashkey_config();
    &authhashkey_config();
    print "</table>\n";
  }
}

sub client_menu {
  if ( ( $security::login =~ /cprice|pnpdemo|plugandp|merchmov|testomaha1|ourgenerat/ ) || ( $security::features->get('sec_clientconf') == 1 ) ) {
    print "<table width=\"100%\" border=0 cellpadding=0 cellspacing=0>\n";
    &distclient_config();
    print "</table>\n";
  }
  if ( ( $security::login =~ /cprice|pnpdemo|plugandp|merchmov|testomaha1|ourgenerat/ ) || ( $security::features->get('sec_certconf') == 1 ) ) {
    print "<table width=\"100%\" border=0 cellpadding=0 cellspacing=0>\n";
    &certificate_config();
    print "</table>\n";
  }
}

sub apikey_menu {
  if ( $security::seclevel eq '0' ) {
    print "<table style=\"border-collapse: collapse; width:100%;\">\n";
    &apikey_add_key();
    &apikey_list_keys();
  }
}

sub kiosk_menu {
  if ( $security::features->get('sec_kiosk') == 1 ) {
    if ( $security::seclevel eq '0' ) {
      print "<table width=\"100%\" border=0 cellpadding=0 cellspacing=0>\n";
      &kiosk_default_url();
      &kiosk_add_id();
      &kiosk_list_ids();
      print "</table>\n";
    }
  }
}

sub device_menu {
  if ( $security::features->get('sec_device') == 1 ) {
    if ( $security::seclevel eq '0' ) {
      print "<table width=\"100%\" border=0 cellpadding=0 cellspacing=0>\n";
      &device_add_id();
      &device_list_ids();
      print "</table>\n";
    }
  }
}

sub username_config_head {
  print "<tr><th align=center colspan=2>Username/Password Configuration</th></tr>\n";
  print "<tr><td align=center colspan=2><a href=\"/admin/doc_replace.cgi?doc=Getting_Started_Guide.htm#section10\">Gateway Security Policy</a></td></tr>\n";
}

sub username_config_delete {
  print "<tr><td class=\"menuleftside\">Delete Users</td>\n";
  print "<td class=\"menurightside\">\n";

  print "<form method=post action=\"$security::path_cgi\">\n";
  print "<input type=hidden name=\"function\" value=\"delete_user\">\n";
  print "<table border=1 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  print "  <tr class=\"sectiontitle\">\n";
  print "    <th>Login Name</th>\n";
  print "    <th>Area</th>\n";
  print "    <th>Sec. Level</th>\n";
  print "    <th>Temp. Flag</th>\n";

  if ( $security::seclevel eq '0' ) {
    print "    <th>SubAcct</th>\n";
  }
  print "    <th>Action</th>\n";
  print "  </tr>\n";

  my $odd = 1;
  foreach my $key ( sort keys %security::login ) {
    my $dirarray = $key . "area";
    if ( $security::acl_db_login{$key}->{'type'} eq 'cert' ) {
      $security::acl_db_login{$key}->{'login'} = 'Digital Cert';
    }
    if ( length( $security::acl_db_login{$key}->{'login'} ) > 1020 ) {
      $security::acl_db_login{$key}->{'login'} = substr( $security::acl_db_login{$key}->{'login'}, 0, 1020 );
    }
    my $rowStyle = $odd ? '' : 'background-color: #EEE !important; vertical-align: top';
    print "  <tr style='$rowStyle'>\n";
    my $areaCount = 0;

    # suppress alternate remote client and mobile passwords
    next if $key =~ /\d_/;

    if ( $key =~ /^rc_/ ) {
      print "    <td>Remote Client</td>\n";
      print "    <td>NA</td>\n";
    } elsif ( $key =~ /^mobi_/ ) {
      print "    <td>Mobile Terminal</td>\n";
      print "    <td>NA</td>\n";
    } elsif ( $security::acl_db_login{$key}->{'seclevel'} == 14 ) {
      print "    <td>$key</td>\n";
      print "    <td>NA</td>\n";
    } else {
      print "    <td>$key</td>\n";
      print "    <td>\n";
      foreach my $var ( @{ $security::acl_dirarray->{$dirarray} } ) {
        $areaCount++;
        if ( ( $security::areas{$var} ne '' ) && ( $security::areas{$var} !~ /^(CUSTOM\d)/ ) ) {
          print "$security::areas{$var}<br>\n";
        }
      }
      if ($areaCount == 0) {
        print "[disabled]<br>\n";
      }
      print "</td>\n";
    }
    print "    <td align=center>$security::acl_db_login{$key}->{'seclevel'}</td>\n";

    if ( $security::temp_hash{"$security::acl_db_login{$key}->{'temp'}"} ne '' ) {
      printf( "    <td>%s</td>\n", $security::temp_hash{"$security::acl_db_login{$key}->{'temp'}"} );
    } else {
      print "    <td>&nbsp;</td>\n";
    }

    if ( $security::seclevel eq '0' ) {
      if ( $security::acl_db_login{$key}->{'subacct'} ne '' ) {
        print "    <td>$security::acl_db_login{$key}->{'subacct'}</td>\n";
      } else {
        print "    <td>&nbsp;</td>\n";
      }
    }

    if (  $security::acl_db_login{$key}->{'seclevel'} ne '0'
      &&  $security::acl_db_login{$key}->{'login'} !~ /^ez_$security::username/
      &&  $security::acl_db_login{$key}->{'login'} !~ /^aff_$security::username/
      &&  $areaCount > 0 ) {
      printf( "    <td><input type=checkbox name=\"delete\_%s\" value=\"1\"> Disable</td>\n", $security::acl_db_login{$key}->{'login'} );
    } else {
      print "    <td>&nbsp;</td>\n";
    }
    print "  </tr>\n";
    $odd = ($odd * -1) + 1;
  }

  my $captcha = new PlugNPay::Util::Captcha::ReCaptcha();
  print "  <tr>\n";
  print "    <td colspan=6>" . $captcha->formHTML() . "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=6><input type=submit class=\"button\" name=\"submit\" value=\" Disable Users \"></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</form></td>\n";
  print "  </tr>\n";
}

sub username_config_edit {
  print "<tr><td class=\"menuleftside\">Edit Admin Users/Password</td>\n";
  print "<td class=\"menurightside\">\n";

  print "<form name=\"edituser\" method=post action=\"$security::path_cgi\" target=\"_self\">\n";
  print "<input type=hidden name=\"func\" value=\"edit_user\">\n";
  print "<table border=1 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <td class=\"leftside\">Login Name</td>\n";
  print "    <td class=\"rightside\"><select name=\"login\">\n";
  foreach my $key ( sort keys %security::login ) {
    if ( $security::acl_db_login{$key}->{'login'} =~ /^($security::remote_pwd_prefixes)/ ) {
      next;
    }
    if ( $security::acl_db_login{$key}->{'type'} eq 'cert' ) {
      $security::acl_db_login{$key}->{'login'} = 'Digital Cert';
    }
    my $sub_email = &get_sub_email( $security::acl_db_login{$key}->{'login'} );
    my $selected = $ENV{'LOGIN'} eq $security::acl_db_login{$key}->{'login'} ? 'selected' : '';
    printf( "<option value=\"%s\" $selected>%s - %s</option>\n", $security::acl_db_login{$key}->{'login'}, $security::acl_db_login{$key}->{'login'}, $sub_email );
  }
  print "</select></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=2>\n";

  # resellers can't do this yet
  if ( $security::source ne 'reseller' ) {
    print "      <input type=submit class=\"button\" name=\"submit\" value=\" Edit Login Details \" onClick=\"document.edituser.func.value='edit_user'\">\n";
  }
  print " &nbsp; <input type=submit class=\"button\" name=\"submit\" value=\" Edit Password \" onClick=\"document.edituser.func.value='edit_passwrd'\">\n";
  print "    </td>\n";
  print "  </tr>\n";

  print "</table>\n";
  print "</form></td>\n";
  print "  </tr>\n";
}

sub username_config_edit_passwrd {
  print "<tr><td class=\"menuleftside\">Edit Password</th>\n";
  print "<td class=\"menurightside\">\n";

  print "<form method=post action=\"$security::path_cgi\" target=\"_self\">\n";
  print "<input type=hidden name=\"function\" value=\"edit_passwrd\">\n";
  print "<table border=1 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <td class=\"leftside\">Login Name</td>\n";
  print "    <td class=\"rightside\"><select name=\"login\">\n";
  foreach my $key ( sort keys %security::login ) {
    if ( $security::acl_db_login{$key}->{'login'} =~ /^($security::remote_pwd_prefixes)/ ) {
      next;
    }
    if ( $security::acl_db_login{$key}->{'type'} eq 'cert' ) {
      $security::acl_db_login{$key}->{'login'} = 'Digital Cert';
    }
    printf( "<option value=\"%s\">%s - %s</option>\n", $security::acl_db_login{$key}->{'login'}, $security::acl_db_login{$key}->{'login'}, $security::areas{"$security::acl_db_login{$key}->{'dir'}"} );

  }
  print "</select></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<br><input type=submit class=\"button\" name=\"submit\" value=\" Edit Login Password \" >\n";
  print "</td></form>\n";
  print "  </tr>\n";
}

sub username_config_add_button {
  print "<tr><td class=\"menuleftside\">Add New User</td>\n";
  print "<td class=\"menurightside\">\n";

  print "<form method=post action=\"$security::path_cgi\" target=\"_self\">\n";
  print "<input type=hidden name=\"function\" value=\"add_new_user\">\n";

  print "<table border=1 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <td colspan=2 class=\"rightside\"><input type=submit class=\"button\" name=\"submit\" value=\" Add New Login User \" >\n";
  print "<br>&nbsp;</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</form></td>\n";
  print "  </tr>\n";
}

sub username_config_add {
  head();
  if ( $security::seclevel eq '0' ) {
    if ( $security::function =~ /^(add_new_user|add_user)$/ ) {
      print "<table width=\"100%\" border=0 cellpadding=0 cellspacing=0>\n";
    }
    print "  <tr><td class=\"menuleftside\">Add New User</td>\n";
    print "  <td class=\"menurightside\">\n";

    print "<form method=post action=\"$security::path_cgi\" target=\"_self\">\n";
    print "<input type=hidden name=\"function\" value=\"add_user\">\n";
    print "<input type=hidden name=\"newpw\" value=\"yes\">\n";

    print "<table border=1 cellspacing=0 cellpadding=2 width=\"100%\">\n";
    if ( $security::error > 0 ) {
      print "<tr><th align=left colspan=2 class=\"badcolor\">$security::error_string</th></tr>";
    }

    print "<tr><td align=left colspan=2 bgcolor=\"#eeeeee\">";
    print passwordFormatListText() . "\n";
    print "<td></tr>";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Login:</td>\n";
    print "    <td class=\"rightside\"><input type=text name=\"login\" value=\"$security::query{'login'}\" size=40 maxlength=1024>\n";
    print "      <br>A Minimum COMBINATION of 8 Letters and Numbers Required.<br><b>Letters and numbers only.  NO Spaces allowed.</b></td>\n";
    print "  </tr>\n";

    my $emailRequired = $security::function eq 'add_new_user' ? 'required' : '';
    print "  <tr>\n";
    print "    <td class=\"leftside\">Email:</td><td><input type=email name=\"email\" value=\"$security::query{'email'}\" size=40 maxlength=80 $emailRequired>\n";
    print "<br>Lost password requests for this login will be validated against \& sent there.\n";
    print "<br>When left blank, the login cannot use our lost password feature.</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Password:</td>\n";
    print "    <td class=\"rightside\"><input type=password name=\"passwrd1\" value=\"\" size=40 maxlength=1024 class=\"passwordCheck\">\n";
    print "  </tr>\n";
    print "  <tr><td colspan=2><div id=\"passStrength\"></div></td></tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Password:<br>(confirm)</td>\n";
    print "    <td class=\"rightside\"><input type=password name=\"passwrd2\" value=\"\" size=40 maxlength=1024 class=\"passwordCheck\"></td>\n";
    print "  </tr>\n";
    print "  <tr><td colspan=2><div id=\"passMatch\"></div><div id=\"emptyField\"></div></td></tr>\n";

    # force all new sub-login passwords temporary
    print "  <tr>\n";
    print "    <td class=\"leftside\">&nbsp;</td>\n";
    print "    <td class=\"rightside\"><input type=hidden name=\"temp\" value=\"1\"> <b><i>Password will be automatically marked as temporary.</i></b></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Security Level:</td>\n";
    print "    <td class=\"rightside\"><select name=\"seclevel\">\n";
    my %selected_level = ();
    $selected_level{ $security::query{'seclevel'} } = 'selected';
    foreach my $var (sort { int($a) <=> int($b) } keys %security::seclevels) {
      if ( $var == 0 ) {
        next;
      }
      if ( $var >= $security::seclevel ) {
        print "<option value=\"$var\" $selected_level{$var}>$var - $security::seclevels{$var}</option>\n";
      }
    }
    print "</select>&nbsp; &nbsp; <a href=\"javascript:help_win('/admin/help.cgi\?subject=securityadmin\&anchor=#unpwconfig',600,565)\">Online Help</a></td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td class=\"leftside\">Area:</td>\n";
    print "    <td class=\"rightside\"><select name=\"new_areas\" size=10 multiple>\n";
    my %s_area = ();
    foreach my $var (@security::new_areas) {
      $s_area{$var} = ' selected';
    }
    foreach my $key1 ( sort keys %security::areas ) {
      if ( $security::areas{$key1} !~ /^(CUSTOM\d)/ ) {
        print "<option value=\"$security::areas{$key1}\"$s_area{$key1}>$security::areas{$key1}</option>\n";
      }
    }
    print "</select>&nbsp; &nbsp; <a href=\"javascript:help_win('/admin/help.cgi\?subject=securityadmin\&anchor=#unpwareas',600,565)\">Online Help</a>\n";
    print "<br>Hold down the Ctrl key when selecting multiple areas.</td>\n";
    print "  </tr>\n";

    if ( $security::features->get('linked_accts') =~ /\w/ ) {
      print "  <tr>\n";
      print "    <td class=\"leftside\">Curb Access:</td>\n";
      print "    <td class=\"rightside\"><input type=radio name=\"curbun\" value=\"1\"> Yes <input type=radio name=\"curbun\" value=\"0\" checked> NO\n";
      print "<br>When selected, limits user to only this account. (Disables access to linked accounts)</td>\n";
      print "  </tr>\n";
    }

    my $captcha = new PlugNPay::Util::Captcha::ReCaptcha();
    print "  <tr>\n";
    print "    <td class=\"leftside\"> &nbsp; </td>\n";
    print "    <td class=\"rightside\">" . $captcha->formHTML() . "</td>\n";
    print "  </tr>\n";
    print "</table>\n";

    print "<br><input type=button class=\"button\" value=\" Update Login Information \" id=\"passwordSubmitButton\" >\n";

    print "</form></td>\n";
    print "  </tr>\n";
  }

  if ( $security::function =~ /^(add_new_user|add_user)$/ ) {
    print "</table>\n";
  }

}

sub remoteclient_config_head {
  print "<tr><th align=center colspan=2>Remote Client Configuration</th></tr>\n";
}

sub remoteclient_config_button {
  print "<tr><td class=\"menuleftside\">Remote Client</td>\n";
  print "<td class=\"menurightside\">";

  print "<form method=post action=\"$security::path_cgi\" target=\"_self\">\n";
  print "<input type=hidden name=\"function\" value=\"show_remoteclient_menu\">\n";

  print "<table border=1 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <td colspan=2 class=\"rightside\"><input type=submit class=\"button\" name=\"submit\" value=\" Manage Remote Client Password \" >\n";
  print "<br>&nbsp;</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</form></td>\n";
  print "  </tr>\n";
}

sub remoteclient_config {
  ## Remote Client Password Form
  my ($remotepwd);

  print "<tr><td class=\"menuleftside\">Remote Client Password</td>\n";
  print "<td class=\"menurightside\">\n";

  print "<form method=post action=\"$security::path_cgi\">\n";
  print "<input type=hidden name=\"function\" value=\"add_remotepwd\">\n";
  print "<table border=1 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  print "  <tr>\n";
  print
    "    <td class=\"rightside\" colspan=2>If entering your own password, only Letters, Numbers, \@ and + characters are allowed. The password must be at least $security::remotepw_minlength characters long and contain at least 1 number. Or you can have the system generate a random password for you by checking the box below.  After you submit the form the new password will be displayed in the text box below.  Please confirm the password before adding it to your software.\n";
  if ( $security::function eq 'add_remotepwd' ) {
    $remotepwd = $security::query{'remotepwd'};
    if ( $security::error_string ne '' ) {
      print "<p><font class=\"badcolor\" style=\"font-weight:bold;\">$security::error_string </font>\n";
    }
  } else {
    $security::color{'remotepwd'} = 'goodcolor';
  }
  print "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"leftside $security::color{'remotepwd'}\">Remote Client Password</td>\n";
  print "    <td class=\"rightside\"><input type=text name=\"remotepwd\" value=\"$remotepwd\" size=20 maxlength=20 autocomplete=\"off\">\n";
  print "      <br><input type=checkbox name=\"remotepwd_random\" value=\"1\"> Generate Random Password</td>\n";
  print "  </tr>\n";

  my $captcha = new PlugNPay::Util::Captcha::ReCaptcha();
  print "  <tr>\n";
  print "    <td class=\"leftside\"> &nbsp; </td>\n";
  print "    <td class=\"rightside\">" . $captcha->formHTML() . "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print
    "    <td colspan=2><input type=submit class=\"button\" name=\"submit\" value=\" Add/Edit Remote Password \">&nbsp; &nbsp; <a href=\"javascript:help_win('/admin/help.cgi?subject=securityadmin&anchor=\#remotepw',600,500)\">Online Help</a></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</form></td>\n";
  print "  </tr>\n";

  return;
}

sub mobileterm_config_head {
  print "<tr><th align=center colspan=2>Mobile Terminal Configuration</th></tr>\n";
}

sub mobileterm_config_button {
  print "<tr><td class=\"menuleftside\">Mobile Terminal</td>\n";
  print "<td class=\"menurightside\">";

  print "<form method=post action=\"$security::path_cgi\" target=\"_self\">\n";
  print "<input type=hidden name=\"function\" value=\"show_mobileterm_menu\">\n";

  print "<table border=1 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <td colspan=2 class=\"rightside\"><input type=submit class=\"button\" name=\"submit\" value=\" Manage Mobile Terminal Password \" >\n";
  print "<br>&nbsp;</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</form></td>\n";
  print "  </tr>\n";
}

sub mobileterm_config {
  ## Mobile Terminal Password Form
  my ($remotepwd);

  print "<tr><td class=\"menuleftside\">Mobile Terminal Password</td>\n";
  print "<td class=\"menurightside\">\n";

  print "<form method=post action=\"$security::path_cgi\">\n";
  print "<input type=hidden name=\"function\" value=\"add_mobilepwd\">\n";
  print "<table border=1 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  print "  <tr>\n";
  print
    "    <td class=\"rightside\" colspan=2>If entering your own password, only Letters, Numbers, \@ and + characters are allowed. The password must be at least $security::remotepw_minlength characters long and contain at least 1 number. Or you can have the system generate a random password for you by checking the box below.  After you submit the form the new password will be displayed in the text box below.  Please confirm the password before adding it to your software.\n";
  if ( $security::function eq 'add_mobilepwd' ) {
    $remotepwd = $security::query{'remotepwd'};
    if ( $security::error_string ne '' ) {
      print "<p><font class=\"badcolor\" style=\"font-weight:bold;\">$security::error_string </font>\n";
    }
  } else {
    $security::color{'remotepwd'} = 'goodcolor';
  }
  print "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"leftside $security::color{'remotepwd'}\">Mobile Terminal Password</td>\n";
  print "    <td class=\"rightside\"><input type=text name=\"remotepwd\" value=\"$remotepwd\" size=20 maxlength=20 autocomplete=\"off\">\n";
  print "      <br><input type=checkbox name=\"remotepwd_random\" value=\"1\"> Generate Random Password</td>\n";
  print "  </tr>\n";

  my $captcha = new PlugNPay::Util::Captcha::ReCaptcha();
  print "  <tr>\n";
  print "    <td class=\"leftside\"> &nbsp; </td>\n";
  print "    <td class=\"rightside\">" . $captcha->formHTML() . "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print
    "    <td colspan=2><input type=submit class=\"button\" name=\"submit\" value=\" Add/Edit Mobile Terminal Password \">&nbsp; &nbsp; <a href=\"javascript:help_win('/admin/help.cgi?subject=securityadmin&anchor=\#remotepw',600,500)\">Online Help</a></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</form></td>\n";
  print "  </tr>\n";

  return;
}

sub distclient_config {
  my ($selected);
  if ( $security::bypassipcheck eq 'yes' ) {
    $selected = 'checked';
  }

  print "<tr><th align=center bgcolor=\"#dddddd\" colspan=2>Distributed Client Configuration</th></tr>\n";

  print "<tr><td class=\"menuleftside\">Enable Distributed Client</td>\n";
  print "<td class=\"menurightside\">\n";

  print "<form method=post action=\"$security::path_cgi\">\n";
  print "<input type=hidden name=\"function\" value=\"enable_distclient\">\n";
  print "<input type=checkbox name=\"distclient\" value=\"yes\" $selected> Check to enable distributed client functionality.\n";
  print "<br><input type=submit class=\"button\" name=\"submit\" value=\" Enable \">\n";
  print "</form></td>\n";
  print "  </tr>\n";
}

sub noreturns_config {
  my ($selected);
  if ( $security::noreturns eq 'yes' ) {
    $selected = 'checked';
  }
  print "<tr><th align=center bgcolor=\"#dddddd\" colspan=2>Disable Credits Configuration</th></tr>\n";

  print "<tr><td class=\"menuleftside\">Disable Credits</td>\n";
  print "<td class=\"menurightside\">\n";

  print "<form method=post action=\"$security::path_cgi\">\n";
  print "<input type=hidden name=\"function\" value=\"enable_noreturns\">\n";

  print "<table border=1 cellspacing=0 cellpadding=4 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <td colspan=2><input type=checkbox name=\"noreturns\" value=\"yes\" $selected> Check to disable credits.\n";
  print
    "<br><input type=submit class=\"button\" name=\"submit\" value=\" Disable Credits \">&nbsp; &nbsp; <a href=\"javascript:help_win('/admin/help.cgi?subject=securityadmin&anchor=\#disablecredits',600,500)\">Online Help</a>\n";
  print "<p>Once credits are disabled, only returns against previous orders will be permitted.\n";
  print "<br>To re-enable the ability to issue credits will require you to contact tech support.</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</form></td>\n";
  print "  </tr>\n";
}

sub ipaddress_config {
  print "<tr><th align=center bgcolor=\"#dddddd\" colspan=2>Transaction Security Configuration</th></tr>\n";

  my (%selected);

  if ( $ENV{'SECLEVEL'} == 0 ) {
    my $foundHash = 0;
    if ( $security::features->get('auth_sec_req') ne '' ) {
      my @authsec = split( '\|', $security::features->get('auth_sec_req') );
      foreach my $var (@authsec) {
        if ($var =~ /^hash/) {
          $foundHash = 1;
          $selected{$var} = 'selected';
        } else {
          $selected{$var} = 'checked';
        }
      }
    }
    if ($foundHash != 1) {
      $selected{'hash:none'} = 'selected';
    }

    print "<tr><td class=\"menuleftside\">Security Requirements</td>\n";
    print "<td class=\"menurightside\">\n";
    print "<form method=post action=\"$security::path_cgi\">\n";
    print "<input type=hidden name=\"function\" value=\"set_req\">\n";

    print "<table border=1 cellspacing=0 cellpadding=4 width=\"100%\">\n";
    print "  <tr><th colspan=3 align=left>Authorizations</th></tr>\n";
    print "  <tr>\n";
    print "    <td rowspan=2> &nbsp; &nbsp; </td><td class=\"leftside\">Require Match</td>\n";
    print "    <td class=\"rightside\">\n";
    print "      <font style=\"bold\">Check to enable matching of selected parameter(s).</font><br>\n";
    print "      <input type=checkbox name=\"auth_sec_req_ip\" value=\"ip\" $selected{'ip'}> IP Address (All Payment Methods)<br>\n";
    print "      <input type=checkbox name=\"auth_sec_req_rmt_ip\" value=\"rmt_ip\" $selected{'rmt_ip'}> IP Address (API/XML only)<br>\n";

    print qq|
    Auth Hash: <select name="auth_sec_req_hash">
      <option value="hash:none" $selected{'hash:none'}>Disabled</option>
      <option value="hash:auth.cgi" $selected{'hash:auth.cgi'}>Hosted Payment Page (payscreens)</option>
      <option value="hash:pnpremote.cgi" $selected{'hash:pnpremote.cgi'}>Remote API</option>
      <option value="hash" $selected{'hash'}>All</option>
    </select><br>
    |;

    print "<hr>";

    if ($selected{'pwd'} eq 'checked') {
      print "      <em>Passwords are required for all remote api requests</em><br>";
    } else {
      my $message = '';
      $message .= 'Passwords will be required for all remote api requests beginning September 1st, 2023.  ';
      $message .= 'Check the box below to begin requiring a password now.  ';
      $message .= 'This is a one-way change, it can not be changed back.';
      print "      <em>$message</em><br>";
      print "      <input type=checkbox name=\"auth_sec_req_pwd\" value=\"pwd\"> Require Password<br>\n";
    }

    print "<br>\n";
    print "  </tr>\n";

    my (%selected);
    if ( $security::features->get('auth_sec_dis') ne '' ) {
      my @authdis = split( '\|', $security::features->get('auth_sec_dis') );
      foreach my $var (@authdis) {
        $selected{$var} = ' checked';
      }
    }
    print "  <tr>\n";
    print "    <td class=\"leftside\">Disable Payment Interfaces</td>\n";
    print "    <td class=\"rightside\">\n";
    print "<table border=1>\n";
    print "  <tr>\n";
    print "    <td><input type=checkbox name=\"auth_sec_dis_rmt\" value=\"rmt\" $selected{'rmt'}> Remote Client</td> \n";
    print "    <td><input type=checkbox name=\"auth_sec_dis_pos\" value=\"pos\" $selected{'pos'}> POS Terminal</td>\n";
    print "    <td><input type=checkbox name=\"auth_sec_dis_dir\" value=\"dir\" $selected{'dir'}> Direct Method [All]</td></tr>\n";
    print "  <tr>\n";
    print "    <td><input type=checkbox name=\"auth_sec_dis_vrt\" value=\"vrt\" $selected{'vrt'}> Virtual Terminal</td>\n";
    print "    <td><input type=checkbox name=\"auth_sec_dis_upl\" value=\"upl\" $selected{'upl'}> Batch Files</td>\n";
    print "    <td><input type=checkbox name=\"auth_sec_dis_dm\" value=\"dm\" $selected{'dm'}> Direct Method [Only]</td></tr>\n";
    print "  <tr>\n";
    print "    <td><input type=checkbox name=\"auth_sec_dis_ss1\" value=\"ss1\" $selected{'ss1'}> Smart Screens v1</td>\n";
    print "    <td><input type=checkbox name=\"auth_sec_dis_ss2\" value=\"ss2\" $selected{'ss2'}> Smart Screens v2</td></tr>\n";
    print "  <tr><td colspan=3>Check to DISABLE processing through the selected interface(s).</td></tr>\n";
    print "</table>\n";

    print "</td>\n";
    print "  </tr>\n";

    %selected = ();
    if ( $security::features->get('admn_sec_req') ne '' ) {
      my @admnsec = split( '\|', $security::features->get('admn_sec_req') );
      foreach my $var (@admnsec) {
        $selected{$var} = ' checked';
      }
    }

    print "  <tr>\n";
    print "    <td rowspan=3> &nbsp; &nbsp; </td><td class=\"leftside\">Administrative Functions</td>\n";
    print "    <td class=\"rightside\">\n";
    print "      <input type=checkbox name=\"admn_sec_req_ip\" value=\"ip\" $selected{'ip'}> Require IP Address Match<br>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "  </tr>\n";
    print "</table><br>\n";
    print "<input type=submit class=\"button\" name=\"submit\" value=\" Set Security Requirements \">&nbsp; &nbsp; <a href=\"javascript:help_win('/admin/help.cgi?subject=securityadmin&anchor=\#secreq',600,500)\">Online Help</a>";

    print "</form></td>\n";
    print "  </tr>\n";

    print "<tr>\n";
    print "<td class=\"menuleftside\"> &nbsp; </td>\n";
    print "<td class=\"menurightside\"> &nbsp; </td>\n";
    print "</tr>\n";

    print "<tr><td class=\"menuleftside\">Remote Client Password</td>\n";
    print "<td class=\"menurightside\">This feature was moved to the '<a href=\"$security::path_cgi\?function=show_unpw_menu\">Username/Password Configuration</a>' section of Security Administration.\n";
    print "<br><a href=\"$security::path_cgi\?function=show_unpw_menu\">Click Here To Manage Your Accounts Login Information</a>\n";
    print "<br>&nbsp; </td>\n";
    print "</tr>\n";
  }

  if ( @security::ipaddress > 0 ) {
    print "<tr><td class=\"menuleftside\">Delete IP Addresses</td>\n";
    print "<td class=\"menurightside\">\n";

    print "<form method=post action=\"$security::path_cgi\">\n";
    print "<input type=hidden name=\"function\" value=\"delete_ip\">\n";

    if ( $security::function eq 'delete_ip' ) {
      print "<p><font class=\"badcolor\" style=\"font-weight:bold;\">$security::error_string </font>\n";
    }

    print "<table border=1 cellspacing=0 cellpadding=4 width=\"100%\">\n";
    print "  <tr class=\"sectiontitle\">\n";
    print "    <th>IP Address</th>\n";
    print "    <th>Action</th>\n";
    print "  </tr>\n";
    foreach my $key ( sort @security::ipaddress ) {
      my $ip = NetAddr::IP->new("$key/$security::netmasks{$key}");
      my ( $firstip, $lastip, $m );
      if ( defined $ip ) {
        ( $firstip, $m ) = split( /\//, $ip->first() );
        ( $lastip,  $m ) = split( /\//, $ip->last() );
      }

      if ( $ENV{'REMOTE_USER'} eq 'pnpdemo' ) {
        if ( $key ne $ENV{'REMOTE_ADDR'} ) {
          next;
        }
      }
      print "  <tr>\n";
      print "    <td>$key <b>/</b> $security::netmasks{$key}  &nbsp; <b>$firstip - $lastip</b></td>\n";
      print "    <td><input type=checkbox name=\"delete_$key\" value=\"1\"> Delete</td>\n";
      print "  </tr>\n";
    }

    print "  <tr>\n";
    print "    <td colspan=2><input type=submit class=\"button\" name=\"submit\" value=\" Delete IP Address \"></td>\n";
    print "  </tr>\n";
    print "</table>\n";

    print "</form></td>\n";
    print "  </tr>\n";
  }

  my @netmasks = ( '32', '30', '29', '28', '27', '26', '25', '24' );
  my %netmasks = ( '32', 'Single IP', '30', '2 hosts', '29', '6 hosts', '28', '14 hosts', '27', '30 hosts', '26', '62 hosts', '25', '126 hosts', '24', '254 hosts' );
  %selected = ( '32', ' selected' );
  print "<tr><td class=\"menuleftside\">Add IP Addresses</td>\n";
  print "<td class=\"menurightside\">\n";

  print "<form method=post action=\"$security::path_cgi\">\n";
  print "<input type=hidden name=\"function\" value=\"add_ip\">\n";

  if ( $security::function eq 'add_ip' ) {
    print "<p><font class=\"badcolor\" style=\"font-weight:bold;\">$security::error_string </font>\n";
  }

  print "<table border=1 cellspacing=0 cellpadding=4 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <th>IP Address</th>\n";
  print "    <th>Action</th>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"$security::color{'ipaddress'}\">IP Address</td>\n";
  print "    <td class=\"$security::color{'ipaddress'}\"><input type=text name=\"ipaddress\" value=\"$security::query{'ipaddress'}\" size=15 maxlength=15> &nbsp; &nbsp; <b>XXX.XXX.XXX.XXX</b> ";
  print " <select name=\"netmask\">";
  foreach my $mask (@netmasks) {
    print "<option value=\"$mask\" $selected{$mask}>/$mask - $netmasks{$mask}</option>\n";
  }
  print "</select>";
  print "</td>\n";
  print "  </tr>\n";

  my $captcha = new PlugNPay::Util::Captcha::ReCaptcha();
  print "  <tr>\n";
  print "    <td class=\"leftside\"> &nbsp; </td>\n";
  print "    <td class=\"rightside\">" . $captcha->formHTML() . "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print
    "    <td colspan=2><input type=submit class=\"button\" name=\"submit\" value=\" Add IP Address \">&nbsp; &nbsp; <a href=\"javascript:help_win('/admin/help.cgi?subject=securityadmin&anchor=\#addips',600,500)\">Online Help</a></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</form></td>\n";
  print "  </tr>\n";
}

sub encpayload_config {
  print "<tr><th align=center bgcolor=\"#dddddd\" colspan=2>Encrypted Payload Configuration</th></tr>\n";

  print "<tr><td class=\"menuleftside\">Encrypted Payload</td>\n";
  print "<td class=\"menurightside\">\n";

  print "<form method=post action=\"$security::path_cgi\">\n";
  print "<input type=hidden name=\"function\" value=\"update_encpayload\">\n";

  my @timewindow = ( 5, 10, 15, 30, 60, 120, 180, 240 );
  print "Time Window: <select name=\"timewindow\">\n";
  for ( my $i = 0 ; $i <= $#timewindow ; $i++ ) {
    print "<option value=\"$timewindow[$i]\"";
    if ( $security::features->get('timewindow') eq $timewindow[$i] ) {
      print " selected";
    }
    print ">$timewindow[$i]</option>\n";
  }
  print "</select><p>\n";

  my %encpayload = ();
  foreach my $var (@security::encpayload) {
    $encpayload{"$var"} = 0;
  }

  my @temp = split( /\|/, $security::features->get('encrequired') );
  for ( my $i = 0 ; $i <= $#temp ; $i++ ) {
    if ( $temp[$i] =~ /\w/ ) {
      $encpayload{"$temp[$i]"} = 1;
    }
  }

  print "<table border=1 cellspacing=0 cellpadding=4 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <th>Option</th>\n";
  print "    <th>Action</th>\n";
  print "  </tr>\n";

  foreach my $key ( sort keys %encpayload ) {
    print "  <tr>\n";
    print "    <td>$key</td>\n";
    print "    <td><table border=1 cellspacing=0 cellpadding=0 width=300>\n";
    print "  <tr>\n";
    print "    <td width=100><input type=radio name=\"payload_$key\" value=\"ignore\" checked> Ignore </td>\n";
    if ( $encpayload{"$key"} == 0 ) {
      print "    <td width=100><input type=radio name=\"payload_$key\" value=\"add\"> Add </td>\n";
      print "    <td width=100>&nbsp;</td>\n";
    } else {    # $encpayload{"$key"} == 1
      print "    <td width=100>&nbsp;</td>\n";
      print "    <td width=100><input type=radio name=\"payload_$key\" value=\"delete\"> Delete </td>\n";
    }
    print "  </tr>\n";
    print "</table></td>\n";
    print "  </tr>\n";
  }

  print "</table>\n";

  print "<br><input type=submit class=\"button\" name=\"submit\" value=\" Update Encrypted Payload \">\n";
  print "</form></td>\n";
  print "  </tr>\n";

  print "<tr><td class=\"menuleftside\"><b>Add Payload Option</b></td>\n";
  print "<td class=\"menurightside\">\n";

  print "<form method=post action=\"$security::path_cgi\">\n";
  print "<input type=hidden name=\"function\" value=\"add_encpayload\">\n";
  print "Field Name: <input type=text name=\"payload_option\" value=\"\" size=20 maxlength=20>\n";
  print "<input type=submit class=\"button\" name=\"submit\" value=\" Add Payload Option \"></form>\n";

  print "</td>\n";
  print "  </tr>\n";
}

sub sitekey_config {
  print "<tr><th align=center bgcolor=\"#dddddd\" colspan=2>Site Key Configuration</th></tr>\n";

  print "<tr><td class=\"menuleftside\"><b>Add Site Key</b></td>\n";
  print "<td class=\"menurightside\">";

  print "<form method=post action=\"$security::path_cgi\">\n";
  print "<input type=hidden name=\"function\" value=\"add_sitekey\">\n";

  if ( $security::function eq 'add_sitekey' ) {
    print "<p><font class=\"badcolor\" style=\"font-weight:bold;\">$security::error_string </font>\n";
  }

  print "<font class=\"$security::color{'domain'}\">Domain:</font> <select name=\"domaintype\"><option value=\"https\">https://</option><option value=\"http\">http://</option></select> ";
  print "<input type=text name=\"domain\" value=\"\" size=20 maxlength=255> &nbsp;\n";
  print "<input type=submit class=\"button\" name=\"submit\" value=\" Add Site Key \">\n";
  print "&nbsp; &nbsp; <a href=\"javascript:help_win('/admin/help.cgi?subject=\#sitekey',600,500)\">Online Help</a>";
  print "<br>&nbsp;\n";

  print "</form></td>\n";
  print "  </tr>\n";

  print "<tr><td class=\"menuleftside\">Delete Site Keys</td>\n";
  print "<td class=\"menurightside\">\n";

  print "<form method=post action=\"$security::path_cgi\">\n";
  print "<input type=hidden name=\"function\" value=\"delete_sitekey\">\n";

  if ( $security::function eq 'delete_sitekey' ) {
    print "<p><font class=\"badcolor\" style=\"font-weight:bold;\">$security::error_string </font>\n";
  }

  print "<table border=1 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  print "  <tr class=\"sectiontitle\">\n";
  print "    <th>Domain</th>\n";
  print "    <th>Site Key</th>\n";
  print "    <th>Action</th>\n";
  print "  </tr>\n";

  my %sitekeys = &list_sitekey("$security::username");
  my $count    = keys %sitekeys;
  if ( $count < 1 ) {
    print "  <tr>\n";
    print "    <td colspan=3 align=center>No Site Keys Registered.</td>\n";
    print "  </tr>\n";
  } else {
    foreach my $key ( sort keys %sitekeys ) {
      print "  <tr>\n";
      print "    <td>$sitekeys{$key}</td>\n";
      print "    <td>$key</td>\n";
      print "    <td><input type=checkbox name=\"delete\_$key\" value=\"1\"> Delete</td>\n";
      print "  </tr>\n";
    }

    print "  <tr>\n";
    print "    <td colspan=3><input type=submit class=\"button\" name=\"submit\" value=\" Delete Site Keys \"></td>\n";
    print "  </tr>\n";
  }
  print "</table>\n";

  print "</form></td>\n";
  print "  </tr>\n";
}

sub apikey_config {
  print "<tr><th align=\"center\" bgcolor=\"#dddddd\" colspan=2>API Key Configuration</th></tr>\n";

  print "<tr><td class=\"menuleftside\" id=\"sec_add_apikey\"><b>API Keys</b></td>\n";
  print "<td class=\"menurightside\">This feature was moved to the '<a href=\"$security::path_cgi\?function=show_apikey_menu\">API Key Management</a>' section of Security Administration.\n";
  print "<br><a href=\"$security::path_cgi\?function=show_apikey_menu\">Click Here To Manage Your API Key Information</a>\n";
  print "<br>&nbsp; </td>\n";
  print "  </tr>\n";
}

sub apikey_add_key {
  print "<tr><th align=\"center\" bgcolor=\"#dddddd\" colspan=2>API Key Creation</th></tr>\n";

  print "<tr><td class=\"menuleftside\" id=\"sec_add_apikey\"><b>Add API Key</b></td>\n";
  print "<td class=\"menurightside\">";

  print "<form method=post action=\"$security::path_cgi\#sec_add_apikey\" onSubmit=\"return ValidateApiKeyAddForm();\">\n";
  print "<input type=hidden name=\"function\" value=\"add_apikey\">\n";

  if ( $security::function eq "add_apikey" ) {
    print "<p class=\"badcolor\" style=\"font-weight:bold;\">$security::error_string </p>\n";
  }

  print "<div>\n";
  print
    "  <div><font class=\"$security::color{'keyName'}\">Key Name:</font> <input type=text id=\"apikey_keyName\" name=\"keyName\" value=\"\" size=20 maxlength=32 placeholder=\"Enter API Key Name\"></div>";

  my $captcha = new PlugNPay::Util::Captcha::ReCaptcha();
  print "  <div>" . $captcha->formHTML() . "</div>\n";

  print
    "  <div style=\"float:left; margin-top: 5px\"><input style=\"margin: 0 10px\" type=submit class=\"button\" name=\"submit\" value=\" Generate New API Key \"><a href=\"javascript:help_win('/admin/help.cgi\?subject=\#apikey',600,500);\">Online Help</a></div>\n";
  print "</div>";
  print "</form></td>\n";
  print "  </tr>\n";
}

sub apikey_list_keys {
  print "<tr><th align=\"center\" bgcolor=\"#dddddd\" colspan=2>API Key Management</th></tr>\n";

  print "<tr><td class=\"menuleftside\" id=\"sec_manage_apikey\">Manage API Keys</td>\n";
  print "<td class=\"menurightside\">\n";

  print
    "<form method=post action=\"$security::path_cgi\#sec_manage_apikey\" onSubmit=\"return confirm('This will delete the API key selected and related revisions. Do you wish to continue?');\">\n";
  print "<input type=hidden name=\"function\" value=\"delete_single_apikey\">\n";

  if ( $security::function =~ /^(delete_multi_apikey|delete_single_apikey)$/ ) {
    print "<p class=\"badcolor\" style=\"font-weight:bold;\">$security::error_string </p>\n";
  }

  print "<i> * View key details, to reactivate, modify, rotate &/or expire the API key's revisions.</i>\n";
  print "<table class=\"tbl_delete_apikey\">\n";
  print "  <tr class=\"sectiontitle\">\n";

  print "    <th>&nbsp;</th>\n";
  print "    <th>Key Name</th>\n";
  print "    <th>Revisions</th>\n";
  print "    <th>Status</th>\n";
  print "    <th>&nbsp;</th>\n";
  print "  </tr>\n";

  my $apikeys_AoH = &list_apikey("$security::username");

  my $stats;          # HoH_ref - track unique API keynames, count revisions & how many active/inactive
  my $popup_layer;    # Hash_ref - for building pop-up layer HTML code

  if ( scalar @{$apikeys_AoH} < 1 ) {
    print "  <tr>\n";
    print "    <td colspan=5 style=\"text-align:center;\">No API Keys Registered.</td>\n";
    print "  </tr>\n";
  } else {

    # generate list of unique API keynames, # of revisions & pop-up layer HTML
    for my $row ( @{$apikeys_AoH} ) {

      # update stats
      my $id = $row->{'key_name'};
      $stats->{$id}->{'revisions'}++;
      if ( $row->{'expires'} eq '' ) {
        $stats->{$id}{'active'}++;
      } else {
        $stats->{$id}{'inactive'}++;
      }

      # generate pop-up layer entry
      my $tmp = "  <tr>\n";
      $tmp .= sprintf( "    <td>%s</td>\n", $row->{'key_name'} );
      $tmp .= sprintf( "    <td>%d</td>\n", $row->{'revision'} );
      if ( $row->{'expires'} eq '' ) {
        $tmp .= "  <td class=\"apikey_active\" style=\"font-size:25px;\"> &#x221e; </td>\n";
        $tmp .= "  <td><a class=\"button\" href=\"#popup0\" onclick=\"apikey_confirm('expire_apikey','$row->{'key_name'}','$row->{'revision'}')\"> Expire </a>\n";
      } else {
        $tmp .= sprintf( "  <td class=\"apikey_inactive\">%s</td>\n", $row->{'expires'} );
        $tmp .= "  <td><a class=\"button\" href=\"#popup0\" onclick=\"apikey_confirm('reactivate_apikey','$row->{'key_name'}','$row->{'revision'}')\"> Reactivate </a>\n";
      }
      $tmp .= "  </tr>\n";

      $popup_layer->{"$id"} .= $tmp;
    }

    my $r = 0;    # keep track of row
    foreach my $key ( sort keys %{$stats} ) {
      $r++;
      print "<tr>\n";
      printf( "    <td><input type=\"radio\" name=\"keyName\" value=\"%s\"></td>\n", $key );
      printf( "    <td>%s</td>\n",                                                    $key );
      printf( "    <td>%d</td>\n",                                                    $stats->{$key}{'revisions'} );
      if ( $stats->{$key}{'active'} > 0 ) {
        printf( "    <td class=\"apikey_active\">ACTIVE (%d)</td>\n", $stats->{$key}{'active'} );
      } else {
        print "    <td class=\"apikey_inactive\">INACTIVE</td>\n";
      }
      print "    <td><a class=\"button\" href=\"#popup$r\">Details</a></td>\n";
      print "  </tr>\n";
    }

    my $captcha = new PlugNPay::Util::Captcha::ReCaptcha();
    print "  <tr>\n";
    print "    <td colspan=\"5\"><div>" . $captcha->formHTML() . "</div></td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td colspan=5><input type=submit class=\"button\" name=submit value=\" Delete API Key \"></td>\n";
    print "  </tr>\n";
  }
  print "</table>\n";
  print "</form></td>\n";
  print "  </tr>\n";

  print "</table>\n";

  if ( scalar keys %{$stats} ) {
    my $r = 0;    # pop-up counter
                  # complete pop-up layer generation
    foreach my $key ( sort keys %{$stats} ) {
      $r++;
      print "<div id=\"popup$r\" class=\"overlay\">\n";
      print "  <div class=\"popup\">\n";
      printf( "    <h2>API Key: %s</h2>\n", $key );
      print "    <a class=\"close\" href=\"#\">&times;</a>\n";
      print "    <div class=\"content\">\n";
      print "<!-- start form here -->\n";
      print "<table class=\"tbl_apikey\">\n";
      print "  <tr class=\"sectiontitle\">\n";
      print "    <th>Key Name</th>\n";
      print "    <th>Revision</th>\n";
      print "    <th>Expires</th>\n";
      print "    <th>&nbsp;</th>\n";
      print "  </tr>\n";
      print $popup_layer->{$key};
      print "  <tr>\n";
      print "    <td colspan=1><a class=\"button\" href=\"#popup0\" onclick=\"apikey_confirm('delete_single_apikey','$key','')\"> Delete API Key w/Revisions </a></td>\n";
      print "    <td colspan=1><a class=\"button\" href=\"#popup0\" onclick=\"apikey_confirm('add_apikey','$key','')\"> Rotate </a></td>\n";
      print "    <td colspan=2> &nbsp; </td>";
      print "  </tr>\n";
      print "</table>\n";
      print "<!-- end form here -->\n";
      print "    </div>\n";
      print "  </div>\n";
      print "</div>\n";
    }

    # confirmation screen w/captcha for pop-up page's buttons
    print "<div id=\"popup0\" class=\"overlay\">\n";
    print "  <div class=\"popup\">\n";
    print "    <h2>API Key: Confirm Request</h2>\n";
    print "    <a class=\"close\" href=\"#\">&times;</a>\n";
    print "    <div class=\"content\">\n";
    print "      <h4 id=\"confirm_msg\"></h4>\n";
    print "<!-- start form here -->\n";

    print "<form method=post id=\"apikey_confirm_form\" action=\"$security::path_cgi\#sec_manage_apikey\" onSubmit=\"return apikey_confirm_submit();\">\n";
    print "<input type=hidden id=\"apikey_confirm_function\" name=\"function\" value=\"\">\n";
    print "<input type=hidden id=\"apikey_confirm_keyName\" name=\"keyName\" value=\"\">\n";
    print "<input type=hidden id=\"apikey_confirm_revision\" name=\"revision\" value=\"\">\n";
    my $captcha = new PlugNPay::Util::Captcha::ReCaptcha();
    print "  <div>" . $captcha->formHTML() . "</div>\n";
    print "<br><input type=submit class=\"button\" name=submit value=\" Confirm Request \">\n";
    print "</form>\n";
    print "<!-- end form here -->\n";
    print "    </div>\n";
    print "  </div>\n";
    print "</div>\n";
  }
}

sub rempasswd_config {
  print "<tr><th align=center bgcolor=\"#dddddd\" colspan=2>Transaction Key Configuration</th></tr>\n";

  print "<tr><td class=\"menuleftside\">Delete Current Key</td>\n";
  print "<td class=\"menurightside\">\n";

  print "<form method=post action=\"$security::path_cgi\">\n";
  print "<input type=hidden name=\"function\" value=\"delete_rempasswd\">\n";
  print "<input type=hidden name=\"rempasswd\" value=\"$security::rempasswd\">\n";

  print "<table border=1 cellspacing=0 cellpadding=4 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <th>IP Address</th>\n";
  print "    <th>Action</th>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td>$security::rempasswd</td>\n";
  print "    <td><input type=checkbox name=\"delete_rempasswd\" value=\"1\"> Delete</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<br><input type=submit class=\"button\" name=\"submit\" value=\" Delete Transaction Key \">\n";
  print "</form></td>\n";
  print "  </tr>\n";

  print "<tr><td class=\"menuleftside\">Create Transaction Key</td>\n";
  print "<td class=\"menurightside\">\n";

  print "<form method=post action=\"$security::path_cgi\">\n";
  print "<input type=hidden name=\"function\" value=\"add_rempasswd\">\n";
  print
    "<input type=submit class=\"button\" name=\"submit\" value=\" Create Transaction Key \">&nbsp; &nbsp; <a href=\"javascript:help_win('/admin/help.cgi?subject=\#rempasswd',600,500)\">Online Help</a>\n";
  print "</form></td>\n";
  print "  </tr>\n";
}

sub hashkey_config {
  ## response verification hashkey
  print "  <tr><th align=center bgcolor=\"#dddddd\" colspan=2>Outbound Verification Hash</th></tr>\n";

  my (@array) = split( '\|', $security::features->get('hashkey') );
  my $key = shift(@array);
  print "<tr><td class=\"menuleftside\">Response Verification Hash</td>\n";
  print "<td class=\"menurightside\">\n";

  print "<form method=post action=\"$security::path_cgi\">\n";
  print "<input type=hidden name=\"hashkey\" value=\"$key\">\n";

  print "<table border=1 cellspacing=0 cellpadding=4 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <th>Verification Key</th>\n";
  print "    <th>Action</th>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td>$key</td>\n";
  print "    <td>";

  if ( $key =~ /\w/ ) {
    print "<input type=radio name=\"hashkeyaction\" value=\"delete\"> Delete \n";
  }
  print "<input type=radio name=\"hashkeyaction\" value=\"create\"> Create <input type=radio name=\"hashkeyaction\" value=\"\" checked> No Action </td>\n";
  print "  </tr>\n";
  print "</table>\n";

  my ( $none_selected, $hash_order );
  ## figure out which custom fields are missing from security::hashvariables array.
  if ( $security::features->get('hashkey') ne '' ) {
    my %fields = ();

    # add fields from hashkey list
    my (@array) = split( '\|', $security::features->get('hashkey') );
    $hash_order    = shift(@array);    ## Remove Key
    $none_selected = @array;           ## Chk to see if there are any variables selected.
    for ( my $i = 0 ; $i <= $#array ; $i++ ) {
      $array[$i] =~ s/[^a-zA-Z0-9\_\-]//g;
      if ( $array[$i] ne '' ) {
        $fields{"$array[$i]"} = 1;
        $hash_order .= "{" . $array[$i] . "}";
      }
    }

    # remove fields offered by default
    foreach my $key (@security::hashvariables) {
      delete $fields{$key};
    }

    # append what's left (which are the missing fields) to security::hashvariables array
    foreach my $key ( sort keys %fields ) {
      push( @security::hashvariables, $key );
    }
  }

  print "<p>Please choose the variables that will be used along with the security hash to generate the verification key response:<br>\n";
  my ( %selected, $ckcnt );
  if ( $none_selected == 0 ) {
    %selected = ( 'publisher-name', ' checked', 'orderID', ' checked', 'card-amount', ' checked' );
  }
  foreach my $var (@security::hashvariables) {
    if ( $security::features->get('hashkey') =~ /$var/ ) {
      $selected{$var} = ' checked';
    }
    print "<input type=checkbox name=\"chk_$var\" value=\"1\" $selected{$var}> $var <br>\n";
  }
  if ( $hash_order ne '' ) {
    print "<br>\n";
    print "Based on this configuration the string that you will need to hash will be:<p>\n";
    print "<b>$hash_order</b><p>\n";
    print "Where {xxxxxxxx} = the value of the variable being returned. <br>The braces, { and }, are for clarity purposes only and should not be included.<br>\n";

  }

  print "<input type=hidden name=\"function\" value=\"hashkey\">\n";

  #foreach my $var (@security::hashvariables) {
  #  print "<input type=hidden name=\"chk_$var\" value=\"1\">\n";
  #}

  print
    "<br><input type=submit class=\"button\" name=\"submit\" value=\" Create/Change/Delete Verification Hash \">&nbsp; &nbsp; <a href=\"javascript:help_win('/admin/help.cgi?subject=securityadmin&anchor=\#vhash',600,500)\">Online Help</a>\n";
  print "<br>&nbsp;\n";
  print "</form></td>\n";
  print "  </tr>\n";
}

sub authhashkey_config {
  ## authorization verification hash
  print "<tr><th align=center bgcolor=\"#dddddd\" colspan=2>Inbound Verification Hash</th></tr>\n";

  my (@array) = split( '\|', $security::features->get('authhashkey') );
  my $allowed_delay = shift(@array);
  my $key           = shift(@array);

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Authorization Verification Hash</td>\n";
  print "    <td class=\"menurightside\">";

  print "<form method=post action=\"$security::path_cgi\">\n";
  print "<input type=hidden name=\"function\" value=\"authhashkey\">\n";
  print "<input type=hidden name=\"hashkey\" value=\"$key\">\n";

  print "<table border=1 cellspacing=0 cellpadding=4 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <th>Verification Key</th>\n";
  print "    <th>Action</th>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td>$key</td>\n";
  print "    <td>";

  if ( $key =~ /\w/ ) {
    print "<input type=radio name=\"hashkeyaction\" value=\"delete\"> Delete \n";
  }
  print "<input type=radio name=\"hashkeyaction\" value=\"create\"> Create <input type=radio name=\"hashkeyaction\" value=\"\" checked> No Action </td>\n";
  print "  </tr>\n";
  print "</table><p>\n";

  my ( $none_selected, $hash_order, $custom_fields );

  ## figure out which custom fields are missing from security::authhashvariables array.
  if ( $security::features->get('authhashkey') ne '' ) {
    my %fields = ();

    # add fields from authhashkey list
    my (@array) = split( '\|', $security::features->get('authhashkey') );

    shift(@array);    ## Remove Time Window
    $hash_order = shift(@array);    ## Remove Key
    $hash_order .= "{timestamp}";

    @array = sort @array;
    foreach my $var (@array) {
      $var =~ s/[^a-zA-Z0-9\_\-]//g;
      if ( $var ne '' ) {
        $fields{"$var"} = 1;
        $hash_order .= "{" . $var . "}";
      }
    }

    # remove fields offered by default
    foreach my $key (@security::authhashvariables) {
      delete $fields{$key};
    }

    # append what's left (which are the missing fields) to security::authhashvariables array
    foreach my $key ( sort keys %fields ) {
      push( @security::authhashvariables, $key );
    }
    foreach my $key ( sort keys %fields ) {
      $custom_fields .= "$key,";
    }
  }
  my %select = ();
  $select{$allowed_delay} = 'selected';
  print "<select name=\"timewindow\">\n";
  print "<option value=\"10\" $select{'10'}>10</option>\n";
  print "<option value=\"20\" $select{'20'}>20</option>\n";
  print "<option value=\"30\" $select{'30'}>30</option>\n";
  print "<option value=\"40\" $select{'40'}>40</option>\n";
  print "<option value=\"50\" $select{'50'}>50</option>\n";
  print "<option value=\"60\" $select{'60'}>60</option>\n";
  print "</select> Please choose the time (in minutes) that the submitted Transaction Time Stamp will be valid for.\n";

  print "<p>Please choose the variables that will be used along with the security hash to generate the verification key response:<br>\n";
  my (%selected);
  foreach my $var (@security::authhashvariables) {
    if ( $security::features->get('authhashkey') =~ /$var/ ) {
      $selected{$var} = ' checked';
    }
    print "<input type=checkbox name=\"chk_$var\" value=\"1\" $selected{$var}> $var <br>\n";
  }
  print "<br><b>Custom Fields:</b> <input type=text name=\"custom_fields\" value=\"$custom_fields\" size=40 maxlength=255>\n";
  print "<br><sub>* NOTE: Use a comma delimiter, when specifying multiple custom field names. [i.e. \"field1,field2,field3\"]</sub>\n";

  if ( $hash_order ne '' ) {
    print "<p>\n";
    print "Based on this configuration the string that you will need to hash will be:<p>\n";
    print "<b>$hash_order</b><p>\n";
    print "Where {xxxxxxxx} = the value of the variable(s) being submitted. <br>The braces, { and }, are for clarity purposes only and should not be included.<br>\n";

  }

  print
    "<p><input type=submit class=\"button\" name=\"submit\" value=\" Create/Change/Delete Verification Hash \">&nbsp; &nbsp; <a href=\"javascript:help_win('/admin/help.cgi?subject=securityadmin&anchor=\#vhash',600,500)\">Online Help</a>\n";
  print "</form></td>\n";
  print "  </tr>\n";
}

sub payscreens_cookie_config {
  my $accountFeatures        = new PlugNPay::Features( $security::username, 'general' );
  my $ignorePayscreensCookie = $accountFeatures->get('ignorePayscreensCookie');
  my $clientSkipCookie       = $accountFeatures->get('clientSkipCookie');

  my $checked = $ignorePayscreensCookie eq '1' ? 'checked' : '';

  print "<tr>\n";
  print "  <th align=center bgcolor=\"#dddddd\" colspan=2>\n";
  print "    Payscreens Cookie Configuration\n";
  print "  </th>\n";
  print "</tr>\n";

  print "<form method=post action=\"$security::path_cgi\">\n";
  print "  <input type=hidden name=\"function\" value=\"update_payscreens_cookie_settings\">\n";
  print "  <tr>\n";
  print "    <td class=\"menuleftside\">\n";
  print "      <b>Ignore Cookie</b>\n";
  print "    </td>\n";
  print "    <td class=\"menurightside\">";
  print "      <input type=checkbox name=\"ignorePayscreensCookie\" value=\"yes\" size=20 maxlength=255 $checked> Check to ignore Payscreens Cookie for ALL transactions.\n";
  print "    </td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\"></td>\n";
  print "    <td>&nbsp;</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">\n";
  print "      <b>Ignore Cookie By Client</b>\n";
  print "    </td>\n";
  print "    <td class=\"menurightside\">";
  print "      <input type=text name=\"clientSkipCookie\" value=\"$clientSkipCookie\" size=20 maxlength=255> Enter one or more clients to ignore cookie.\n";
  print "      <br />\n";
  print "      Example: client1|client2|client3\n";
  print "    </td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\"></td>\n";
  print "    <td>&nbsp;</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">\n";
  print "    </td>\n";
  print "    <td class=\"menurightside\">\n";
  print "      <input type=submit class=\"button\" name=\"submit\" value=\" Set Cookie Configuration \">\n";
  print "      <br />\n";
  print "    </td>\n";
  print "  </tr>\n";
  print "</form>\n";
}

sub add_rempasswd {
  my $datetime = gmtime(time);
  my $str      = $datetime . $ENV{'SSL_SESSION_ID'} . $datetime;
  my $sha1     = new SHA;
  $sha1->reset;
  $sha1->add($str);
  my $encstr = $sha1->hexdigest();
  $encstr =~ s/[^a-zA-Z]//g;
  my $rempasswd = '555' . "." . substr( $encstr, 0, 3 ) . "." . substr( $encstr, 3, 3 ) . "." . substr( $encstr, 6, 3 );

  # James - 12/07/2011 - prevent guests from changing login password
  if ( ( $security::username =~ /^(pnpdemo|billpaydem|demouser)$/ ) ) {
    return;
  }

  my $dbh = &miscutils::dbhconnect('pnpmisc');
  my $sth = $dbh->prepare(
    qq{
      DELETE FROM ipaddress
      WHERE username=?
      AND ipaddress LIKE '555%'
    }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr" );
  $sth->execute($security::username) or die "Can't execute: $DBI::errstr";
  $sth->finish;

  my $sth2 = $dbh->prepare(
    q{
      INSERT INTO ipaddress
      (username,ipaddress)
      VALUES (?,?)
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth2->execute( $security::username, $rempasswd );
  $sth2->finish;

  $dbh->disconnect;

  my $message = "<b>Your transaction key is below.  Please paste this into your software where indicated.<p>\n <font size=\"+1\">$rempasswd</font>\n</b><p>";
  &response_page($message);
}

sub delete_rempasswd {
  if ( $security::query{'delete_rempasswd'} eq '1' ) {
    my $dbh = &miscutils::dbhconnect('pnpmisc');

    my $sth = $dbh->prepare(
      q{
        DELETE FROM ipaddress
        WHERE username=?
        AND ipaddress=?
      }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr" );
    $sth->execute( $security::username, $security::query{'rempasswd'} ) or die "Can't execute: $DBI::errstr";
    $sth->finish;

    $dbh->disconnect;

    my $message = "<b>Your transaction key has been deleted.</b>";
    &response_page($message);
  }
}

sub add_hashkey {
  ## add verification hashkey
  if ( $security::seclevel ne '0' ) {
    my $message = "<b>Your security level prevents access to this function.<p>";
    &response_page($message);
  }

  # James - 12/07/2011 - prevent guests from changing hash key
  if ( ( $security::username =~ /^(pnpdemo|billpaydem|demouser)$/ ) ) {
    return;
  }

  # custom fields from input
  my @customFields = split( ',', $security::query{'custom_fields'} );

  # enabled standard fiels config from input
  my %enabledStandardFieldsConfig = map { $_ => 1 } grep { $_ =~ /^chk_/ && $security::query{$_} == 1 } keys %security::query;

  # get list of standard fields based on input config
  my $enabledStandardFields = createVerificationHashEnabledStandardFields(
    { fields        => \@security::hashvariables,
      fieldsEnabled => \%enabledStandardFieldsConfig
    }
  );

  my $createVerificationHashInput = {
    standardFields => $enabledStandardFields,
    customFields   => \@customFields,
    action         => $security::query{'hashkeyaction'},
    secret         => $security::query{'hashkey'}
  };

  my $value = createVerificationHash($createVerificationHashInput);
  $security::features->set( 'hashkey', $value );
  $security::features->saveContext();
}

sub delete_hashkey {
  ## delete response verification hashkey
  if ( $security::seclevel ne '0' ) {
    my $message = "<b>Your security level prevents access to this function.<p>";
    &response_page($message);
  }
  if ( $security::query{'hashkeyaction'} eq 'delete' ) {
    $security::features->remove('hashkey');
    $security::features->saveContext();

  }
}

sub add_authhashkey {
  ## add authorization verification hashkey
  if ( $security::seclevel ne '0' ) {
    my $message = "<b>Your security level prevents access to this function.<p>";
    &response_page($message);
  }

  # James - 12/07/2011 - prevent guests from changing hash key
  if ( ( $security::username =~ /^(pnpdemo|billpaydem|demouser)$/ ) ) {
    return;
  }

  # custom fields from input
  my @customFields = split( ',', $security::query{'custom_fields'} );

  # enabled standard fiels config from input
  my %enabledStandardFieldsConfig = map { $_ => 1 } grep { $_ =~ /^chk_/ && $security::query{$_} == 1 } keys %security::query;

  # get list of standard fields based on input config
  my $enabledStandardFields = createVerificationHashEnabledStandardFields(
    { fields        => \@security::authhashvariables,
      fieldsEnabled => \%enabledStandardFieldsConfig
    }
  );

  my $createVerificationHashInput = {
    standardFields => $enabledStandardFields,
    customFields   => \@customFields,
    action         => $security::query{'hashkeyaction'},
    secret         => $security::query{'hashkey'},
    window         => $security::query{'timewindow'}
  };

  my $value = createVerificationHash($createVerificationHashInput);
  $security::features->set( 'authhashkey', $value );
  $security::features->saveContext();
}

sub createVerificationHashEnabledStandardFields {
  my $input   = shift;
  my $fields  = $input->{'fields'};
  my $enabled = $input->{'fieldsEnabled'};
  my @outputFields;

  foreach my $field ( @{$fields} ) {
    if ( $enabled->{ 'chk_' . $field } == 1 ) {
      push @outputFields, $field;
    }
  }
  return \@outputFields;
}

sub createVerificationHash {
  my $input = shift;

  my $standardFields = $input->{'standardFields'};
  my $customFields   = $input->{'customFields'};
  my $action         = $input->{'action'};
  my $inputSecret    = $input->{'secret'};
  my $window         = $input->{'window'};

  # give inputSecret a value of empty string if action is create
  $inputSecret = $action eq 'create' ? '' : $inputSecret;

  # give up if action is *not* create, but the input hash key is empty
  if ( $inputSecret eq '' && $action ne 'create' ) {

    # currently no way to handle this error case?
    return;
  }

  # shared secret is hashkey, or if hashkey is blank, generate one
  my $sharedSecret = $inputSecret || generateSharedSecret();

  my %fieldsForHash;
  foreach my $field ( @{$customFields}, @{$standardFields} ) {
    $field =~ s/[^a-zA-Z0-9\_\-]//g;
    if ( $field =~ /\w/ ) {
      $fieldsForHash{$field} = 1;
    }
  }

  $window =~ s/[^0-9]//g;
  my $fields = join( '|', sort keys %fieldsForHash );

  my $featureValue;
  if ( defined $window && $window ne '' ) {
    $featureValue = sprintf( '%s|%s|%s', $window, $sharedSecret, $fields );
  } else {
    $featureValue = sprintf( '%s|%s', $sharedSecret, $fields );
  }

  return $featureValue;
}

sub generateSharedSecret {
  my $length = shift || 25;    # default old length
  my @chars = ( 'a' ... 'z', 'A' ... 'Z', '0' ... '9' );
  my @secret;
  for ( my $i = 0 ; $i < $length ; $i++ ) {
    push @secret, $chars[ int( rand(@chars) ) ];
  }
  return join( '', @secret );
}

sub delete_authhashkey {
  ## delete authorization verification hashkey
  if ( $security::seclevel ne '0' ) {
    my $message = "<b>Your security level prevents access to this function.<p>";
    &response_page($message);
  }

  $security::features->remove('authhashkey');
  $security::features->saveContext();
}

sub getCurrentAccountUsername {
  return $security::username;
}

sub getRemotePasswordFromQuery {
  return $security::query{'remotepwd'};
}

sub setRemotePasswordInQuery {
  my $self = shift;
  my $password = shift;
  $security::query{'remotepwd'} = $password;
}

sub getMobilePasswordFromQuery {
  # not a bug, uses the same field as RemotePassword
  return $security::query{'remotepwd'};
}

sub setMobilePasswordInQuery {
  my $self = shift;
  my $password = shift;
  # not a bug, uses the same field as RemotePassword
  $security::query{'remotepwd'} = $password;
}

sub shouldGenerateRandomPassword {
  return $security::query{'remotepwd_random'} == 1;
}

sub add_remotepwd {
  my $self = shift;
  my $input = shift || $self; # because security.pm is used like an object in security.cgi (:
  $input->{'realm'} = 'REMOTECLIENT';
  addClientPassword($input);
}

sub add_mobilepwd {
  my $self = shift;
  my $input = shift || $self; # because security.pm is used like an object in security.cgi (:
  $input->{'realm'} = 'MOBILECLIENT'; 
  addClientPassword($input);
}

sub addClientPassword {
  my $input = shift;

  my $realm = $input->{'realm'};
  my $login = $input->{'login'};
  my $password = $input->{'password'};

  if ( $security::seclevel ne '0' ) {
    my $message = "<b>Your security level prevents access to this function.<p>";
    &response_page($message);
  }

  my $loginClient = new PlugNPay::Authentication::Login({
    login => $login
  });
  $loginClient->setRealm($realm);

  my $result = $loginClient->getLoginInfo();

  if ($result) {
    $result = $loginClient->setPassword({
      password => $password
    });
  } else {
    my $env = new PlugNPay::Environment();
    my $account = $env->get('PNP_ACCOUNT');
    $result = $loginClient->createLogin({
      login => $login,
      account => $account,
      securityLevel => 14,
      password => $password
    });
  }
}

sub set_req {
  if ( $security::seclevel ne '0' ) {
    my $message = "<b>Your security level prevents access to this function.<p>";
    &response_page($message);
  }

  # Prevent guests from changing login features of certain accounts
  if ( ( $security::username =~ /^(pnpdemo|billpaydem|demouser)$/ ) ) {
    return;
  }

  # Load current feature settings
  my $accountFeatures = new PlugNPay::Features( $security::username, 'general' );

  my $admn_sec_req = '';
  my $auth_sec_req = '';
  my $auth_sec_dis = '';

  $admn_sec_req = join('|', map { defined $security::query{"admn_sec_req_$_"} ? "$security::query{\"admn_sec_req_$_\"}" : '' } ( 'ip', 'pwd', 'encrypt', 'rmt_ip' ));

  my %new_auth_sec_req;

  # set requirements based on allowed inputs
  foreach my $asrType ('ip','hash','encrypt','rmt_ip') {
    if (defined $security::query{"auth_sec_req_$asrType"}) {
      my $val = $asrType;
      if ($asrType eq 'hash') {
        $val = $security::query{"auth_sec_req_$asrType"};
      }
      $new_auth_sec_req{$val} = 1;
    }
  }

  my %old_auth_sec_req = map { $_ => 1 }  @{$accountFeatures->getFeatureValues('auth_sec_req')};

  # set password requirement based on current value or if pwd is set
  if ($old_auth_sec_req{'pwd'} || defined $security::query{'auth_sec_req_pwd'}) {
    $new_auth_sec_req{'pwd'} = 1;
  }

  $auth_sec_req = join('|',keys %new_auth_sec_req);

  $accountFeatures->set( 'admn_sec_req', $admn_sec_req );
  $accountFeatures->set( 'auth_sec_req', $auth_sec_req );

  $auth_sec_dis .= join('', map { defined $security::query{"auth_sec_dis_$_"} ? "$security::query{\"auth_sec_dis_$_\"}|" : '' } ( 'rmt', 'pos', 'vrt', 'dir', 'upl', 'ss1', 'ss2', 'dm' ));
  $accountFeatures->set( 'auth_sec_dis', $auth_sec_dis );

  # Save new feature settings
  $accountFeatures->saveContext();

  # Set to new feature Settings
  $security::features = $accountFeatures;
}

sub certificate_config {
  print "<tr><th align=center bgcolor=\"#dddddd\" colspan=2>Digital Client Certificates</th></tr>\n";

  print "<tr><td class=\"menuleftside\">Client Certificate</td>\n";
  print "<td class=\"menurightside\">\n";

  print "<form method=post action=\"$security::path_cgi\" target=\"results\">\n";
  print "<input type=hidden name=\"function\" value=\"gen_cert\">\n";
  print "<br><input type=submit class=\"button\" name=\"submit\" value=\" Request Certificate \" >\n";
  print "</form></td>\n";
  print "  </tr>\n";
}

sub edit_user {
  # redirect user to password change screen, when login password is temporary.
  if ( $ENV{'TEMPFLAG'} == 1 && $ENV{'TECH'} eq '' ) {
    edit_passwrd();
    return;
  }

  if ( $security::query{'login'} eq $ENV{'REMOTE_USER'} ) {
    response_page("Master login is not editable");
    return;
  }

  # get details of login username specified
  my $existingUser = &security::details_acl();
  head();

  if ( $security::function eq 'edit_user' ) {
    print "<table width=\"100%\" border=0 cellpadding=0 cellspacing=0>\n";
  }

  if ($existingUser) {
    print "<tr><th class=\"menuleftside\">Update User</th>\n";
  } else {
    print "<tr><th class=\"menuleftside\">Add User</th>\n";
  }
  print "<td class=\"menurightside\">\n";

  print "<form method=post name=\"editUser\" action=\"$security::path_cgi\" target=\"_self\">\n";
  if (!$existingUser) {
    print "<input type=hidden name=\"function\" value=\"add_user\">\n";
  } else {
    print "<input type=hidden name=\"function\" value=\"update_user\">\n";
  }
  if ( $security::query{'newpw'} eq 'yes' ) {
    print "<input type=hidden name=\"newpw\" value=\"yes\">\n";
  }

  print "<table border=1 cellspacing=0 cellpadding=4 width=\"100%\">\n";

  if ( $security::error > 0 ) {
    print "<tr><th align=left colspan=2 class=\"badcolor\">$security::error_string</th></tr>";
  } elsif ( $ENV{'TEMPFLAG'} == 1 ) {
    print "<tr><th align=left colspan=2 class=\"badcolor\">The login information previously assigned to you was either TEMPORARY or has EXPIRED.";
    print "<p>New security requirments mandated by Visa require login credentials be changed every 90 days as a minimum.";
    print "<p>As a security precaution you will be required to change it.";
    print "<p>Before proceeding with any other activity, this form MUST be submitted to process your change request. <p>Please make note of your new password before submitting the form.</th></tr>";
  }

  if ( $security::acl_db_login{"$security::query{'login'}"}->{'type'} eq 'cert' ) {
    $security::query{'login'} = 'Digital Cert';
  }

  print "<tr><td class=\"leftside $security::color{'login'}\">Login Name</td><td>$security::query{'login'}<input type=hidden name=\"login\" value=\"$security::query{'login'}\">";
  if ( $ENV{'SSL_CLIENT_I_DN'} ne '' ) {
    print " <input type=checkbox name=\"use_cert\" value=\"1\"> Use Cert. ID";
  }
  print "</td></tr>\n";

  if ( $security::username ne $security::query{'login'} ) {
    print "<tr><td class=\"leftside\">Email</td><td><input type=email name=\"email\" value=\"$security::query{'email'}\" size=40 maxlength=80>\n";
    print "<br>Lost password requests for this login will be validated against \& sent there.\n";
    print "<br>When left blank, the login cannot use our lost password feature.</td>\n";
    print "  </tr>\n";

    my %checked = ();
    $checked{'1'} = ' checked';
    if ( $ENV{'TEMPFLAG'} != 1 ) {
      my $disabled = $security::query{'temp'} ? 'disabled' : '';
      print "<tr><td class=\"leftside\">Force Password Change</td><td><input type=checkbox name=\"temp\" value=\"1\" $checked{$security::query{'temp'}} $disabled>\n";
      print "User must change their password. <em>This cannot be undone.</em>\n";
      print "</td></tr>\n";
    }
  }

  if ( $security::seclevel eq '0' ) {
    print "<tr><td class=\"leftside\">Security Level</td><td><select name=\"seclevel\">\n";
    my %s_level = ();
    $s_level{ $security::query{'seclevel'} } = ' selected';
    foreach my $var (sort { $a+0 <=> $b+0 } keys %security::seclevels) {
      if ( $var == 0 ) {
        next;
      }
      if ( $var >= $security::seclevel ) {
        print "<option value=\"$var\"$s_level{$var}>$var - $security::seclevels{$var}</option>\n";
      }
    }
    print "</select>&nbsp; &nbsp; <a href=\"javascript:help_win('/admin/help.cgi\?subject=securityadmin\&anchor=#unpwconfig',600,565)\">Online Help</a></td></tr>\n";

    print "<tr><td class=\"leftside $security::color{'new_areas'}\">Area:</td>";
    print "<td><br>Hold down the Ctrl key (Windows/Linux) or Command key (MacOS) to select multiple areas.</td></tr>\n";

    print "<tr><td></td><td><select name=\"new_areas\" size=10 multiple>";
    my %s_area = ();
    foreach my $var (@security::new_areas) {
      $s_area{$var} = ' selected';
    }

    foreach my $key1 ( sort keys %security::areas ) {
      if ( $security::areas{$key1} !~ /^(CUSTOM\d)/ ) {
        print "<option value=\"$security::areas{$key1}\"$s_area{$key1}>$security::areas{$key1}</option>\n";
      }
    }

    print "</select>&nbsp; &nbsp; <a href=\"javascript:help_win('/admin/help.cgi\?subject=securityadmin\&anchor=#unpwareas',600,565)\">Online Help</a>\n";

    if ( ( $security::seclevel eq '0' ) && ( $security::features->get('linked_accts') =~ /\w/ ) && ( $security::query{'seclevel'} ne '0' ) ) {
      print "  <tr>\n";
      print "    <td class=\"leftside\">Curb Access</td>\n";

      my %checked = ();
      if ( $security::query{'curbun'} == 1 ) {
        $checked{'1'} = ' checked';
      } else {
        $checked{'0'} = ' checked';
      }
      print "    <td class=\"rightside\"><input type=radio name=\"curbun\" value=\"1\"$checked{'1'}> Yes <input type=radio name=\"curbun\" value=\"0\"$checked{'0'}> No\n";
      print "<br>When selected, limits user to only this account. (Disables access to linked accounts)</td>\n";
      print "  </tr>\n";
    }
  }

  my $captcha = new PlugNPay::Util::Captcha::ReCaptcha();
  print "  <tr>\n";
  print "    <td class=\"leftside\"> &nbsp; </td>\n";
  print "    <td class=\"rightside\">" . $captcha->formHTML() . "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<br><input type=button class=\"button\" value=\" Update Login Information \" onClick=\"ValidateArea(this.form);close_me();\">\n";
  print "</form></td>\n";
  print "  </tr>\n";

  print "  <tr><th class=\"menuleftside\"> &nbsp;</th>\n";
  print "<td class=\"menurightside\">\n";
  print "<form method=post action=\"$security::path_cgi\" target=\"_self\">\n";
  print "<input type=hidden name=\"function\" value=\"edit_passwrd\">\n";
  print "<input type=hidden name=\"login\" value=\"$security::query{'login'}\">\n";
  print "<input type=submit class=\"button\" name=\"submit\" value=\" Edit Login Password \" >\n";
  print "</form></td>\n";
  print "  </tr>\n";

  if ( $security::function eq 'edit_user' ) {
    print "</table>\n";
  }
}

sub edit_passwrd {

  # get details of login username specified
  details_acl();
  head();

  if ( $security::function =~ /^(edit_passwrd|update_passwrd)$/ ) {
    print "<table width=\"100%\" border=0 cellpadding=0 cellspacing=0>\n";
  }

  print "<tr><th class=\"menuleftside\"> Update Password</th>\n";
  print "<td class=\"menurightside\">\n";

  print "<form method=post name=\"editUser\" action=\"$security::path_cgi\" target=\"_self\">\n";
  print "<input type=hidden name=\"function\" value=\"update_passwrd\">\n";
  if ( $security::query{'newpw'} eq 'yes' ) {
    print "<input type=hidden name=\"newpw\" value=\"yes\">\n";
  }

  print "<table border=1 cellspacing=0 cellpadding=4 width=\"100%\">\n";

  if ( $security::error > 0 ) {
    print "<tr><th align=left colspan=2 class=\"badcolor\">$security::error_string</th></tr>";
  } elsif ( $ENV{'TEMPFLAG'} == 1 ) {
    print "<tr><th align=left colspan=2 class=\"badcolor\">The login information previously assigned to you was either TEMPORARY or has EXPIRED.";
    print "<p class=\"badcolor\">Login credentials must be changed every 90 days.</p>";
    print "<p>As a security precaution you will be required to change it.</p>";
    print "<p>Before proceeding with any other activity, this form MUST be submitted to process your change request.</p>\n";
    print "<p>Please make note of your new password before submitting the form.</p></th></tr>";
  }

  print "<tr><td align=left colspan=2 bgcolor=\"#eeeeee\">";
  print passwordFormatListText() . "\n";
  print "</td></tr>";

  print "</p></td></tr>\n";

  if ( $security::acl_db_login{"$security::query{'login'}"}->{'type'} eq 'cert' ) {
    $security::query{'login'} = 'Digital Cert';
  }

  print "<tr><td class=\"leftside $security::color{'login'}\">Login Name</td><td>$security::query{'login'}<input type=hidden name=\"login\" value=\"$security::query{'login'}\">";
  if ( $ENV{'SSL_CLIENT_I_DN'} ne '' ) {
    print " <input type=checkbox name=\"use_cert\" value=\"1\"> Use Cert. ID";
  }
  print "</td></tr>\n";

  print "<tr><td class=\"leftside $security::color{'oldpasswrd'}\">";
  if ( lc($ENV{'LOGIN'}) eq lc($security::query{'login'}) ) {
    print "Current Password:";
    print "</td><td><input type=password name=\"oldpasswrd\" size=40 maxlength=1024 value=\"\"></td></tr> \n";
  }

  print "<tr><td class=\"leftside $security::color{'passwrd1'}\">";
  if ( ( $ENV{'SEC_LEVEL'} eq '0' ) && ( $security::username ne $security::query{'login'} ) ) {
    print "New Sub-Login Password:";
  } else {
    print "New Password:";
  }
  print "</td><td><input type=password name=\"passwrd1\" size=40 maxlength=20 value=\"\" class=\"passwordCheck\">\n";
  print "<tr><td colspan=3><div id=\"passStrength\"></div></td></tr>\n";

  print "<tr><td class=\"leftside $security::color{'passwrd2'}\">";
  if ( ( $ENV{'SEC_LEVEL'} eq '0' ) && ( $security::query{'login'} ne $security::username ) ) {
    print "New Sub-Login Password:(confirm)";
  } else {
    print "New Password:(confirm)";
  }
  print "</td><td><input type=password name=\"passwrd2\" size=40 maxlength=20 value=\"\" class=\"passwordCheck\"></td></tr> \n";

  #print "</td><td><input type=password name=\"passwrd2\" size=40 maxlength=1024 value=\"$security::query{'passwrd2'}\"></td></tr> \n"   ## DCP 20110504
  print "<tr><td colspan=3><div id=\"passMatch\"></div><div id=\"emptyField\"></div></td></tr>\n";

  my $captcha = new PlugNPay::Util::Captcha::ReCaptcha();
  print "  <tr>\n";
  print "    <td class=\"leftside\"> &nbsp; </td>\n";
  print "    <td class=\"rightside\">" . $captcha->formHTML() . "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<input type=hidden name=\"newpw\" value=\"yes\">\n";

  if ( $ENV{'TEMPFLAG'} == 1 ) {
    print
      "<br><div align=left><b>* <u>Note</u>:</b> If your new password is accepted, you will be immediately logged out.<br>You would then login with your username \& new password to access your account.</div>\n";
  }

  print "<br><input type=button class=\"button\" id=\"passwordSubmitButton\" value=\" Update Login Password \"></form></td></tr>\n";

  if ( $security::function =~ /^(edit_passwrd|update_passwrd)$/ ) {
    print "</table>\n";
  }
}

sub passwordFormatListText {
  my @passwordFormatList;
  push @passwordFormatList, "<p><b>Password Format:</b><br>";
  push @passwordFormatList, "&bull; Passwords may not be reused.<br>";
  push @passwordFormatList, "&bull; Passwords are required to be a minimum of 12 characters<br>";
  push @passwordFormatList, "&bull; Must contain uppercase letters, lowercase letters, and numbers<br>";
  push @passwordFormatList, "&bull; Cannot contain your login name (username) or email address<br>";
  push @passwordFormatList, "&bull; Cannot contain more than 3 consecutive characters that are in your current password<br>";
  push @passwordFormatList, "";
  return join("\n",@passwordFormatList);
}

sub input_check {
  my $logstr = '';

  foreach my $key ( keys %security::query ) {
    $security::color{$key} = 'goodcolor';
  }

  my @check = ();

  if ( $security::query{'function'} eq 'create_cert' ) {
    push( @check, 'card-name', 'card-city', 'email', 'company', 'card-state', 'passwrd1', 'passwrd2' );
  } elsif ( $security::function eq 'add_user' || $security::function eq 'update_user' ) {
    if ( $security::seclevel eq '0' ) {
      push( @check, 'login', 'new_areas' );
    } else {
      push( @check, 'login' );
    }
    ##  IF Loop was commented out for some reason so passwrd check was always required.  Un-commented DCP 20080213
    if ( $security::query{'newpw'} eq 'yes' ) {
      push( @check, 'passwrd1', 'passwrd2' );
    }
  } elsif ( $security::function eq 'update_passwrd' ) {
    push( @check, 'login', 'passwrd1', 'passwrd2' );
  } elsif ( $security::query{'function'} =~ /(add_remotepwd|add_mobilepwd)/ ) {
    if ( $security::query{'remotepwd_random'} != 1 ) {
      push( @check, 'remotepwd' );
    }
  } else {
    push( @check, 'ipaddress' );
  }

  my $test_str = '';
  foreach my $var (@check) {
    $test_str .= "$var|";
  }

  my $error;

  foreach my $var (@check) {
    my $val = $security::query{$var};
    $val =~ s/[^a-zA-Z0-9]//g;
    if ( length($val) < 1 ) {
      $security::error_string .= "Missing Value for $var.<br>";
      $error = 1;
      $security::color{$var} = 'badcolor';
      $security::errvar .= "$var\|";
    }
  }

  if ( $test_str =~ /email/ ) {
    my $position = index( $security::query{'email'}, "\@" );
    my $position1 = rindex( $security::query{'email'}, "\." );
    my $elength   = length( $security::query{'email'} );
    my $pos1      = $elength - $position1;

    if ( ( $position < 1 )
      || ( $position1 < $position )
      || ( $position1 >= $elength - 2 )
      || ( $elength < 5 )
      || ( $position > $elength - 5 ) ) {
      $security::error_string .= "Invalid Email Address Format.<br>";
      $error = 2;
      $security::color{'email'} = 'badcolor';
      $security::errvar .= "email:$position:$pos1:$position1:$elength\|";
    }
  }

  if ( $test_str =~ /login/ ) {
    my $length = length( $security::query{'login'} );
    if ( $length < 3 ) {
      $security::error_string .= "Login contain less than 3 characters.<br>";
      $error = 6;
      $security::color{'login'} = 'badcolor';
      $security::errvar .= "loginLT8\|";
    }
    if ( $security::query{'login'} =~ /[^0-9A-Za-z]/ ) {
      $security::error_string .= "Invalid characters in Login. Letters and numbers only.  No spaces.<br>";
      $error = 7;
      $security::color{'login'} = 'badcolor';
      $security::errvar .= "loginIVC\|";
    }
  }

  if ( $test_str =~ /ipaddress/ ) {
    $security::query{'ipaddress'} =~ s/^0//g;
    if ( $security::query{'ipaddress'} !~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/ ) {
      $security::error_string .= "IP Address Incorrect Format.<br>";
      $error = 8;
      $security::color{'ipaddress'} = 'badcolor';
      $security::errvar .= "ipaddress\|";
    } else {
      ###   DCP  20080530  Strip out leading zeros in each ip quad
      ###   DCP  20081202  Modified to allow zero as only digit in octet
      $security::query{'ipaddress'} =~ s/\.0(\d{1,2})/\.$1/g;

      # check for invalid octets in IPv4 addresses
      my @temp = split( /\./, $security::query{'ipaddress'} );
      for ( my $i = 0 ; $i <= $#temp ; $i++ ) {
        if ( ( $temp[$i] < 0 ) || ( $temp[$i] > 255 ) ) {
          $security::error_string .= "IP Address Incorrect Format.<br>";
          $error = 8;
          $security::color{'ipaddress'} = 'badcolor';
          $security::errvar .= "ipaddress\|";
          last;
        }
      }

    }

    if ( $ENV{'SECLEVEL'} > 0 ) {
      $security::error_string .= "Access to this function is limited to master login only.<br>";
      $error = 9;
      $security::errvar .= "securitylevel\|";
    }
  }

  if ( $security::error_string ne '' ) {
    $security::error_string .= "Please Re-enter.";
  }

  $security::error = $error;
  return $error;
}

sub sort_hash {
  my $x     = shift;
  my %array = %$x;
  sort { $array{$a} cmp $array{$b}; } keys %array;
}

sub update_encpayload {
  if ( $security::seclevel ne '0' ) {
    my $message = "<b>Your security level prevents access to this function.<p>";
    &response_page($message);
  }

  # setup basic payload fields
  my %encrequired = ();
  foreach my $var (@security::encpayload) {
    $encrequired{"$var"} = 0;
  }

  # get currently defined payload fields
  my @temp = split( /\|/, $security::features->get('encrequired') );
  for ( my $i = 0 ; $i <= $#temp ; $i++ ) {
    if ( $temp[$i] =~ /\w/ ) {
      $encrequired{ $temp[$i] } = 1;
    }
  }

  # now update payload fields, using form data
  foreach my $key ( sort keys %security::query ) {
    if ( $key =~ /^(payload\_)/ ) {
      $security::query{"payload\_$key"} =~ s/[^a-zA-Z0-9\_\-]//g;

      #$security::query{"payload\_$key") = substr($security::query{"payload_$key"},0,25);

      my ( $junk, $field ) = split( /\_/, $key, 2 );
      if ( $security::query{"$key"} eq 'add' ) {
        $encrequired{"$field"} = 1;
      } elsif ( $security::query{"$key"} eq 'delete' ) {
        $encrequired{"$field"} = 0;
      }
    }
  }

  my $timeWindow = $security::query{'timewindow'};
  $timeWindow =~ s/[^0-9]//g;
  if ( $timeWindow > 0 ) {
    $security::features->set( 'timewindow', $timeWindow );
  }

  # create new encrequired features entry
  my @encRequiredKeys = grep { $encrequired{$_} == 1 } keys %encrequired;
  my $encRequiredFeatureValue = join( '|', sort @encRequiredKeys );

  $security::features->set( 'encrequired', $encRequiredFeatureValue );
  $security::features->saveContext();
}

sub add_encpayload {
  if ( $security::seclevel ne '0' ) {
    my $message = "<b>Your security level prevents access to this function.<p>";
    &response_page($message);
  }

  # James - 12/07/2011 - prevent guests from changing encpayload settings
  if ( ( $security::username =~ /^(pnpdemo|billpaydem|demouser)$/ ) ) {
    return;
  }

  # filter supplied data
  $security::query{'payload_option'} =~ s/[^a-zA-Z0-9\_\-]//g;
  $security::query{'payload_option'} = substr( $security::query{'payload_option'}, 0, 25 );

  my $encRequiredFeatureValue = $security::features->get('encrequired') || '';

  # do existince check
  my @encrequired = split( /\|/, $encRequiredFeatureValue );
  foreach my $enc (@encrequired) {
    if ( $enc eq $security::query{'payload_option'} ) {
      return;
    }
  }

  # add to list if it doesn't already exist
  push @encrequired, $security::query{"payload_option"};
  $encRequiredFeatureValue = join( '|', @encrequired );

  $security::features->set( 'encrequired', $encRequiredFeatureValue );
  $security::features->saveContext();
}

sub getdomains {
  my ($username) = @_;

  $username =~ s/[^a-zA-Z0-9]//g;
  $username =~ tr/A-Z/a-z/;

  my $gatewayAccount  = new PlugNPay::GatewayAccount($username);
  my $resellerAccount = new PlugNPay::Reseller( $gatewayAccount->getReseller() );

  my $admindomain = $resellerAccount->getAdminDomain() || 'pay1.plugnpay.com';
  my $emaildomain = $resellerAccount->getEmailDomain() || 'plugnpay.com';

  return ( emaildomain => $emaildomain, admindomain => $admindomain );
}

sub minimumCharactersDifferent {
  my ( $number, $stringA, $stringB ) = @_;

  $stringA = lc $stringA;
  $stringB = lc $stringB;

  my $newCharacterCount = 0;

  foreach my $char ( keys %{ { map { $_ => 1 } split( //, $stringB ) } } ) {
    if ( index( $stringA, $char ) < 0 ) {
      if ( ++$newCharacterCount >= $number ) {
        return 1;
      }
    }
  }
  return 0;
}

sub get_sub_email {
  ## gets sub-login user's email address from 'sub_email' table
  my ($login) = @_;

  $login =~ s/[^a-zA-Z0-9]//g;

  my $usernameObj = new PlugNPay::Username( $login );
  my $db_email    = $usernameObj->getSubEmail();

  return ($db_email);
}

sub update_sub_email {
  ## inserts/updates sub-login user's email address in 'sub_email' table
  my ( $login, $email ) = @_;

  # do nothing if email is not defined
  if (defined $email) {
    my $usernameObj = new PlugNPay::Username( $login );
    $usernameObj->setSubEmail( $email );
  }

  return;
}

sub update_sub_features {
  my $features = shift;
  my $query = shift;

  if (ref($query) ne 'HASH') {
    die('something needs fixing still');
  }

  my %copyOfFeatures = %{$features};
  my $updatedFeatures = \%copyOfFeatures;


  ## update sub-login's feature settings [e.g. only those keys in %query, that are in the %data_fields list]

  # skip updating, when login is unavailable
  $query->{'login'} =~ s/[^a-zA-Z0-9]//g;
  if ( $query->{'login'} !~ /\w/ ) {
    return;
  }

  # set the user's feature fields the merchant can modify
  # Format: "field_name" => ["default_value", "exclude_regex"]
  my %data_fields = (
    'curbun'         => [ '', "01" ],
    'sec_rempasswd'  => [ '', "01" ],
    'sec_verifyhash' => [ '', "01" ],
    'sec_clientconf' => [ '', "01" ],
    'sec_certconf'   => [ '', "01" ],
    'sec_encpayload' => [ '', "01" ]
  );

  # update features that merchants wes permitted to manipulate & provided (fields not provided are left as is)
  foreach my $key ( sort keys %data_fields ) {
    if ( $query->{"$key"} eq '' ) {
      next;
    }

    my $default = $data_fields{$key}[0];
    my $exclude = $data_fields{$key}[1];

    # remove all characters not listed within given field's exclude regex
    if ( $exclude ne '' ) {
      if ( $query->{"$key"} ne '' ) {

        # clean query field value
        $query->{"$key"} =~ s/[^$exclude]//g;
      }
      if ( $updatedFeatures->{"$key"} ne '' ) {

        # clean feature field value
        $updatedFeatures->{"$key"} =~ s/[^$exclude]//g;
      }
    }

    if ( ( exists $query->{"$key"} ) && ( defined $query->{"$key"} ) ) {
      $updatedFeatures->{"$key"} = $query->{"$key"};
    } else {
      $updatedFeatures->{"$key"} = $default;
    }
  }

  return $updatedFeatures;
}

sub add_sitekey {
  ## add new sitekey for given merchant's domain

  my ( $merchant, $domaintype, $domain, $url, $dummy );

  require sitekey;
  my $sk = new sitekey;

  $merchant = $security::username;

  my $domain_type = $security::query{'domaintype'};
  if ( $domain_type !~ /^(http|https)$/ ) {
    $domain_type = "https";
  }

  $domain = lc("$security::query{'domain'}");
  if ( $domain =~ /\// ) {
    ( $domain, $dummy ) = split( /\//, $domain, 2 );
  }
  $domain =~ s/[^a-zA-Z0-9\_\-\.\:\*]//g;

  $url = $domain_type . "\:\/\/" . $domain;
  $url =~ /^(https?\:\/\/[a-z0-9\-\.]+)\/(.*)/i;

  if ( $url !~ /\w\.\w/ ) {
    $security::error_string .= "Invalid Domain.<br>";
    $security::error = 1;
    $security::color{'domain'} = 'badcolor';
    $security::errvar .= "domain\|";
    return;
  }

  my $sitekey = $sk->addDomainForMerchant( "$url", "$merchant" );

  if ( $sitekey !~ /\w/ ) {
    $security::error_string .= "Cannot Generate Site Key. Please try again.<br>";
    $security::error = 1;
    $security::color{'domain'} = 'badcolor';
    $security::errvar .= "domain\|";
    return;
  } else {
    $security::error_string .= "Added Site Key \'$sitekey\' for \'$url\'.<br>";
    $security::error = 1;
    return;
  }

  return;
}

sub delete_sitekey {
  my (@sitekey_deletelist) = @_;

  require sitekey;
  my $sk = new sitekey;

  my $merchant = $security::username;

  foreach my $var (@sitekey_deletelist) {
    $var =~ s/[^a-zA-Z0-9]//g;
    if ( $var =~ /\w/ ) {
      $sk->removeSiteKey( "$var", "$merchant" );
    }
  }

  return;
}

sub update_payscreens_cookie_settings {
  my $accountFeatures = new PlugNPay::Features( $security::username, 'general' );

  my $ignoreCookie = $security::query{'ignorePayscreensCookie'} eq 'yes' ? 1 : 0;

  $accountFeatures->set( 'ignorePayscreensCookie', $ignoreCookie );
  $accountFeatures->set( 'clientSkipCookie',       $security::query{'clientSkipCookie'} );
  $accountFeatures->saveContext();

  return;
}

sub list_sitekey {
  ## list sitekey for given merchant's domain

  require sitekey;
  my $sk = new sitekey;

  my $merchant = $security::username;

  my %sitekeys = $sk->siteKeysForMerchant($merchant);

  return %sitekeys;
}

sub add_apikey {
  ## add new API key for given merchant

  my $keyName = $security::query{'keyName'};
  $keyName =~ s/[^a-zA-Z0-9\_\ ]//g;

  if ( ( $keyName !~ /\w/ ) && ( !$security::query{'apikey_random'} ) ) {
    $security::error_string .= "Invalid Key Name.<br>";
    $security::error = 1;
    $security::color{'keyName'} = 'badcolor';
    $security::errvar .= "keyName\|";
    return;
  }

  if ( $security::query{'g-recaptcha-response'} eq '' ) {
    $security::error_string .= "Invalid CAPTCHA.<br>";
    $security::error = 1;
    $security::color{'g-recaptcha-response'} = 'badcolor';
    $security::errvar .= "g-recaptcha-response\|";
    return;
  }

  my $apiKey = new PlugNPay::API::Key();
  $apiKey->setGatewayAccount($security::username);
  $apiKey->setKeyName($keyName);

  if ( $security::query{'apikey_random'} ) {
    $apiKey->genRandKey($keyName);
    $keyName = $apiKey->getKeyName();
  } else {
    $apiKey->setKeyName($keyName);
  }

  my $key = $apiKey->generate();

  if ( $key !~ /\w/ ) {
    $security::error_string .= "Cannot Generate API Key. Please try again.<br>";
    $security::error = 1;
    $security::color{'keyName'} = 'badcolor';
    $security::errvar .= "keyName\|";
  } else {
    my $rev = $apiKey->getRevision;
    $security::error_string .= "Added New API Key/Revision:<br>Record this information for your records.<br>It will not be presented again.<ul>";
    $security::error_string .= sprintf( "<li><b>Key Name:</b> %s</li>", $keyName );
    $security::error_string .= sprintf( "<li><b>Revision:</b> %d</li>", $rev );
    $security::error_string .= sprintf( "<li><b>Value:</b> %s", $key );
    $security::error_string .= "\&nbsp; <a href=\"#\" onClick=\"document.getElementById('hexLi').style.display='block';copyFieldValue(event,'hexVal');return false;\">Show In Hex</a></li>\n";
    $security::error_string .= sprintf( "<li id=\"hexLi\" style=\"display:none;\"><b>In Hex:</b> <input type=text id=\"hexVal\" value=\"%s\" size=40></li></ul>", unpack( 'H*', "$key" ) );
    $security::error = 1;
  }

  return;
}

sub reactivate_apikey {
  ## reactivate API key for given merchant

  my $keyName = $security::query{'keyName'};
  $keyName =~ s/[^a-zA-Z0-9\_\ ]//g;

  if ( $keyName !~ /\w/ ) {
    $security::error_string .= "Invalid Key Name.<br>";
    $security::error = 1;
    $security::color{'keyName'} = 'badcolor';
    $security::errvar .= "keyName\|";
    return;
  }

  my $revision = $security::query{'revision'};
  $revision =~ s/[^0-9]//g;
  if ( $revision !~ /\d/ ) {
    $security::error_string .= "Invalid Revision Number.<br>";
    $security::error = 1;
    $security::color{'revision'} = 'badcolor';
    $security::errvar .= "revision\|";
    return;
  }

  if ( $security::query{'g-recaptcha-response'} eq '' ) {
    $security::error_string .= "Invalid CAPTCHA.<br>";
    $security::error = 1;
    $security::color{'g-recaptcha-response'} = 'badcolor';
    $security::errvar .= "g-recaptcha-response\|";
    return;
  }

  my $apiKey = new PlugNPay::API::Key();
  $apiKey->setGatewayAccount($security::username);
  $apiKey->setKeyName($keyName);
  $apiKey->setRevision($revision);
  $apiKey->setKeyExpiration( $apiKey->getKeyName, $apiKey->getRevision );

  return;
}

sub expire_apikey {
  ## expire API key for given merchant

  my $keyName = $security::query{'keyName'};
  $keyName =~ s/[^a-zA-Z0-9\_\ ]//g;

  if ( $keyName !~ /\w/ ) {
    $security::error_string .= "Invalid Key Name.<br>";
    $security::error = 1;
    $security::color{'keyName'} = 'badcolor';
    $security::errvar .= "keyName\|";
    return;
  }

  my $revision = $security::query{'revision'};
  $revision =~ s/[^0-9]//g;
  if ( $revision !~ /\d/ ) {
    $security::error_string .= "Invalid Revision Number.<br>";
    $security::error = 1;
    $security::color{'revision'} = 'badcolor';
    $security::errvar .= "revision\|";
    return;
  }

  if ( $security::query{'g-recaptcha-response'} eq '' ) {
    $security::error_string .= "Invalid CAPTCHA.<br>";
    $security::error = 1;
    $security::color{'g-recaptcha-response'} = 'badcolor';
    $security::errvar .= "g-recaptcha-response\|";
    return;
  }

  my $apiKey = new PlugNPay::API::Key();
  $apiKey->setGatewayAccount($security::username);
  $apiKey->setKeyName($keyName);
  $apiKey->setRevision($revision);
  $apiKey->expireKey( $apiKey->getKeyName, $apiKey->getRevision );

  if ( $apiKey->getKey !~ /\w/ ) {
    $security::error_string .= "Cannot Activate API Key. Please try again.";
    $security::error = 1;
    $security::color{'keyName'} = 'badcolor';
    $security::errvar .= "keyName\|";
  } else {
    $security::error_string .= sprintf( "Reactived API Key<br>- Name: %s\n<br>- Value: %s", $keyName, $apiKey->getKey );
    $security::error = 1;
  }

  return;
}

sub delete_multi_apikey {
  ## delete multiple API keys with their revisions
  my (@apikey_deletelist) = @_;

  my $apiKey = new PlugNPay::API::Key();
  $apiKey->setGatewayAccount($security::username);

  foreach my $var (@apikey_deletelist) {
    $var =~ s/[^a-zA-Z0-9\_\ ]//g;
    if ( $var =~ /\w/ ) {
      $apiKey->deleteKey("$var");

      $security::error_string = "The selected API Key(s) were deleted.";
      $security::error        = 1;
    }
  }

  return;
}

sub delete_single_apikey {
  ## delete single API key with all revisions
  my $keyName = $security::query{'keyName'};
  $keyName =~ s/[^a-zA-Z0-9\_\ ]//g;

  if ( $keyName !~ /\w/ ) {
    $security::error_string .= "Invalid Key Name.<br>";
    $security::error = 1;
    $security::color{'keyName'} = 'badcolor';
    $security::errvar .= "keyName\|";
    return;
  }

  if ( $security::query{'g-recaptcha-response'} eq '' ) {
    $security::error_string .= "Invalid CAPTCHA.<br>";
    $security::error = 1;
    $security::color{'g-recaptcha-response'} = 'badcolor';
    $security::errvar .= "g-recaptcha-response\|";
    return;
  }

  eval {
    my $apiKey = new PlugNPay::API::Key();
    $apiKey->setGatewayAccount($security::username);
    $apiKey->deleteKey("$keyName");

    $security::error_string = "The selected API Key was deleted.";
    $security::error = 1;
  };

  return;
}

sub list_apikey {
  ## list API keys for given merchant
  my $apiKey = new PlugNPay::API::Key();
  $apiKey->setGatewayAccount($security::username);
  my $apikeys_AoH = $apiKey->listApiKeys();    # sorted array of hashes reference
  return $apikeys_AoH;
}

sub security_test {
  my ( $status, $reason );

  # this is the username we use to test with not crap from some form data or anything else!!!
  my $username = $ENV{'REMOTE_USER'};

  if ( ( exists $security::query{'login'} ) && ( $security::query{'login'} ne $ENV{'REMOTE_USER'} ) ) {
    ### Test if value is associated with merchant/reseller.
    if ( $security::source eq 'reseller' ) {

      # restrict reseller access to top level reseller username only.
      # NOTE: does not allow for reseller sub-logins
      if ( $security::reseller ne $username ) {
        $status = "Fail";
        $reason = "Not Reseller";
      }
    } else {
      if ( $ENV{'SCRIPT_NAME'} =~ /(\/overview\/)/ ) {

        # restrict reseller overview access to merchants (and their sub-logins) that belonging to reseller
        if ( $security::reseller ne $username ) {

          # merchant does not belong to reseller
          $status = "Fail";
          $reason = "Merchant Does Not Belong To Reseller";
        }
      }

      if ( $username ne $security::query{'login'} ) {
        my $loginInfo;
        eval {
          $loginInfo = getLoginInfo($security::query{'login'});
        };

        if ( $security::function eq 'add_user' && !defined $loginInfo ) {
          ## does not belong to anyone, can be used for creation of new sub-login
          $status = '';
          $reason = "Sub-Login Not Used";
        } elsif ( $loginInfo->{'account'} ne $username ) {
          $status = "Fail";
          $reason = "Sub-Login Not Merchants";
        }
      }
    }
  }

  # $status should return 'Failed' (if failed) or blank/null (if passed)
  # $reason would return the reason why it failed the security test.
  return ( $status, $reason );
}

sub kiosk_default_url {

  # form for adding kiosk default url
  my $pk  = new PlugNPay::Kiosk;
  my $url = $pk->defaultURLForUsername($security::username);

  print "  <tr>\n";
  print "    <th align=center bgcolor=\"#dddddd\" colspan=2>Kiosk Management</th>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Default Kiosk URL</td>\n";
  print "    <td class=\"menurightside\">\n";
  print "<form method=post action=\"$security::path_cgi\" target=\"_self\">\n";
  print "<input type=hidden name=\"function\" value=\"kiosk_update_default_url\">\n";

  print "<table border=1 cellspacing=0 cellpadding=4 width=\"100%\">\n";
  if ( $url ne '' ) {
    print "  <tr>\n";
    print "    <td class=\"leftside\">Currently Set:</td>\n";
    print "    <td class=\"rightside\">$url\n";
    print " &nbsp; <a href=\"$security::path_cgi\?function=kiosk_delete_default_url\" class=\"button\">Delete</a></td>\n";
    print "  </tr>\n";
  }
  print "  <tr>\n";
  print "    <td class=\"leftside\">New Default URL:</td>\n";
  print "    <td class=\"rightside\"><input type=text name=\"url\" value=\"http://\" size=40 maxlength=1024></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=2><input type=submit class=\"button\" name=\"submit\" value=\" Update Default Kiosk URL \" ></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</form>\n";
  print "<br>&nbsp;</td>\n";
  print "  </tr>\n";
}

sub kiosk_update_default_url {

  # update the kiosk default url
  if ( $security::query{'url'} ne '' ) {
    my $pk = new PlugNPay::Kiosk;
    $pk->setDefaultURLForUsername( $security::query{'url'}, $security::username );
  }
}

sub kiosk_delete_default_url {

  # deleted the kiosk default url
  my $pk  = new PlugNPay::Kiosk;
  my $url = $pk->deleteDefaultURLForUsername($security::username);
}

sub kiosk_add_id {

  # form for adding a single kiosk ID
  if ( $security::function eq 'kiosk_add_id' ) {
    print "<table width=\"100%\" border=0 cellpadding=0 cellspacing=0>\n";
  }
  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Add New Kiosk ID</td>\n";
  print "    <td class=\"menurightside\">\n";

  print "<form method=post action=\"$security::path_cgi\" target=\"_self\">\n";
  print "<input type=hidden name=\"function\" value=\"kiosk_edit_id\">\n";
  print "<input type=submit class=\"button\" name=\"submit\" value=\" Add New Kiosk ID \" ></form>\n";
  print "<br>&nbsp;</td>\n";
  print "  </tr>\n";
  if ( $security::function eq 'kiosk_add_id' ) {
    print "</table>\n";
  }
}

sub kiosk_edit_id {

  # form for editing a single kiosk ID
  my $pk = new PlugNPay::Kiosk;
  if ( $security::query{'kiosk_id'} ne '' ) {
    $security::query{'url'} = $pk->urlForKioskIDForUsername( $security::query{'kiosk_id'}, $security::username );
  }

  if ( $security::function eq 'kiosk_edit_id' ) {
    print "<table width=\"100%\" border=0 cellpadding=0 cellspacing=0>\n";
  }
  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Add/Edit Kiosk IDs</td>\n";
  print "    <td class=\"menurightside\">\n";

  print "<form method=post action=\"$security::path_cgi\">\n";
  print "<input type=hidden name=\"function\" value=\"kiosk_update_id\">\n";

  print "<table border=1 cellspacing=0 cellpadding=4 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <td class=\"leftside\">Kiosk ID:</td>\n";
  print "    <td class=\"rightside\"><input type=text name=\"kiosk_id\" value=\"$security::query{'kiosk_id'}\" size=40 maxlength=1024></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"leftside\">URL:</td>\n";
  print "    <td class=\"rightside\"><input type=text name=\"url\" value=\"$security::query{'url'}\" size=40 maxlength=1024>\n";
  print "<br><sub>* NOTE: Leave URL blank to use the kiosk default URL.</sub></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print
    "<br><input type=submit class=\"button\" name=\"submit\" value=\" Submit \">&nbsp; &nbsp; <a href=\"javascript:help_win('/admin/help.cgi\?subject=securityadmin\&anchor=#kiosk',600,500)\">Online Help</a>\n";
  print "</form>\n";

  print "</td>\n";
  print "  </tr>\n";
  if ( $security::function eq 'kiosk_edit_id' ) {
    print "</table>\n";
  }
}

sub kiosk_update_id {

  # insert or update a single kiosk ID
  my %kiosk_info = ();
  if ( $security::query{'kiosk_id'} ne '' ) {
    my $pk = new PlugNPay::Kiosk;
    $pk->setURLForKioskIDForUsername( $security::query{'url'}, $security::query{'kiosk_id'}, $security::username );
  }
}

sub kiosk_delete_id {

  # delete a single kiosk ID
  if ( $security::query{'kiosk_id'} ne '' ) {
    my $pk = new PlugNPay::Kiosk;
    $pk->deleteKioskIDForUsername( $security::query{'kiosk_id'}, $security::username );
  }
}

sub kiosk_list_ids {

  # show all kiosk IDs registered, with edit/delete buttons
  my $pk        = new PlugNPay::Kiosk;
  my %kiosk_ids = $pk->kioskIDListForUsername($security::username);

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Registered Kiosk IDs</td>\n";
  print "    <td class=\"menurightside\">\n";

  print "<form method=post action=\"$security::path_cgi\">\n";

  print "<table border=1 cellspacing=0 cellpadding=4 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <th>Kiosk ID</th>\n";
  print "    <th>URL</th>\n";
  print "    <th>Action</th>\n";
  print "  </tr>\n";

  my $count = 0;
  foreach my $key ( sort keys %kiosk_ids ) {
    $count++;
    print "  <tr>\n";
    print "    <td><input type=checkbox name=\"kiosk_id$count\" value=\"$key\"> $key</td>\n";
    print "    <td>";
    if ( $kiosk_ids{$key} ne '' ) {
      print "$kiosk_ids{$key}";
    } else {
      print "[Uses Default URL]";
    }
    print "</td>\n";
    print "    <td><a href=\"$security::path_cgi\?function=kiosk_edit_id\&kiosk_id=$key\" class=\"button\">Edit</a> &nbsp;&nbsp; \n";
    print "<a href=\"$security::path_cgi\?function=kiosk_delete_id\&kiosk_id=$key\" class=\"button\">Delete</a></td>\n";
    print "  </tr>\n";
  }

  if ( $count == 0 ) {
    print "  <tr>\n";
    print "    <td colspan=3 align=center><font class=\"error_text\">No Kiosk Device IDs Are Currently Registered</font></td>\n";
    print "  </tr>\n";
  }

  print "</table>\n";

  print "<br><b>Bulk Operation:</b> <select name=\"function\">\n";
  print "<option value=\"show_kiosk_menu\"></option>\n";
  print "<option value=\"revoke_kiosk_urls\">Revoke Kiosk URLs</option>\n";
  print "<option value=\"delete_kiosk_ids\">Delete Kiosk IDs</option>\n";
  print "</select>\n";

  print
    " &nbsp; <input type=submit class=\"button\" name=\"submit\" value=\" Submit \">&nbsp; &nbsp; <a href=\"javascript:help_win('/admin/help.cgi\?subject=securityadmin\&anchor=#kiosk',600,500)\">Online Help</a>\n";
  print "<br><sub><i>* NOTE: Bulk Operation applies to all of those devices you have selected above.</i></sub>\n";
  print "</form>\n";

  print "</td>\n";
  print "  </tr>\n";

  return;
}

sub revoke_kiosk_urls {

  # bulk revokes url from a group of kiosk IDs
  my $pk        = new PlugNPay::Kiosk;
  my %kiosk_ids = $pk->kioskIDListForUsername($security::username);
  my $max       = scalar keys %kiosk_ids;

  for ( my $i = 1 ; $i <= $max ; $i++ ) {
    if ( $security::query{"kiosk_id$i"} ne '' ) {
      $pk->setURLForKioskIDForUsername( '', $security::query{"kiosk_id$i"}, $security::username );
    }
  }
}

sub delete_kiosk_ids {

  # build deletes a group of kiosk IDs
  my $pk        = new PlugNPay::Kiosk;
  my %kiosk_ids = $pk->kioskIDListForUsername($security::username);
  my $max       = scalar keys %kiosk_ids;

  for ( my $i = 1 ; $i <= $max ; $i++ ) {
    if ( $security::query{"kiosk_id$i"} ne '' ) {
      $pk->deleteKioskIDForUsername( $security::query{"kiosk_id$i"}, $security::username );
    }
  }
}

sub device_add_id {

  # form for adding a single device ID
  print "  <tr>\n";
  print "    <th align=center bgcolor=\"#dddddd\" colspan=2>Device Management</th>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Add New Device</td>\n";
  print "    <td class=\"menurightside\">\n";

  print "<form method=post action=\"$security::path_cgi\" target=\"_self\">\n";
  print "<input type=hidden name=\"function\" value=\"device_edit_id\">\n";
  print "<input type=submit class=\"button\" name=\"submit\" value=\" Add New Device \" ></form>\n";
  print "<br>&nbsp;</td>\n";
  print "  </tr>\n";
}

sub device_edit_id {

  # form for editing a single device ID
  my %device_info = ();
  if ( $security::query{'device_id'} ne '' ) {
    my $ud = new PlugNPay::UserDevices;
    my $device_info = $ud->deviceInfoForUsername( $security::query{'device_id'}, $security::username, "1" );

    foreach my $key ( sort keys %$device_info ) {
      $device_info{$key} = $device_info->{$key};
    }

    if ( $device_info{'id_exists'} == 1 ) {
      $security::query{'approved'} = 1;
    } else {
      delete $security::query{'device_id'};
      delete $security::query{'approved'};
    }
  }

  if ( $security::function =~ /^(device_add_id|device_edit_id)$/ ) {
    print "<table width=\"100%\" border=0 cellpadding=0 cellspacing=0>\n";
  }
  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Add/Edit Device ID</td>\n";
  print "    <td class=\"menurightside\">\n";

  print "<form method=post action=\"$security::path_cgi\" target=\"_self\">\n";
  print "<input type=hidden name=\"function\" value=\"device_update_id\">\n";

  print "<table border=1 cellspacing=0 cellpadding=4 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <td class=\"leftside\">Device ID:</td>\n";
  print "    <td class=\"rightside\"><input type=text name=\"device_id\" value=\"$security::query{'device_id'}\" size=40 maxlength=1024>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"leftside\">Status:</td>\n";
  print "    <td class=\"rightside\"><input type=radio name=\"approved\" value=\"1\"";
  if ( $security::query{'approved'} == 1 ) { print " checked"; }
  print "> Approved\n";
  print "&nbsp; <input type=radio name=\"approved\" value=\"0\"";
  if ( $security::query{'approved'} == 0 ) { print " checked"; }
  print "> Revoked</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<br><input type=submit class=\"button\" name=\"submit\" value=\" Submit \" ></form>\n";
  print "<br>&nbsp;</td>\n";
  print "  </tr>\n";
  if ( $security::function =~ /^(device_add_id|device_edit_id)$/ ) {
    print "</table>\n";
  }
}

sub device_update_id {

  # insert or update the a single device ID
  my %device_info = ();
  if ( $security::query{'device_id'} ne '' ) {
    my $ud = new PlugNPay::UserDevices;
    my $device_info = $ud->deviceInfoForUsername( $security::query{'device_id'}, $security::username, "1" );

    foreach my $key ( sort keys %$device_info ) {
      $device_info{$key} = $device_info->{$key};
    }

    if ( $device_info{'id_exists'} == 0 ) {
      $ud->addDeviceForUsername( $security::query{'device_id'}, $security::username );
      if ( $security::query{'approved'} == 1 ) {
        $ud->setApprovalForDeviceForUsername( 1, $security::query{'device_id'}, $security::username );
      } else {
        $ud->setApprovalForDeviceForUsername( 0, $security::query{'device_id'}, $security::username );
      }
    } else {
      if ( $security::query{'approved'} == 1 ) {
        $ud->setApprovalForDeviceForUsername( 1, $security::query{'device_id'}, $security::username );
      } else {
        $ud->setApprovalForDeviceForUsername( 0, $security::query{'device_id'}, $security::username );
      }
    }
  }
}

sub device_delete_id {

  # delete a single device ID
  if ( $security::query{'device_id'} ne '' ) {
    my $ud = new PlugNPay::UserDevices;
    $ud->deleteDeviceForUsername( $security::query{'device_id'}, $security::username );
  }
}

sub device_approve_id {

  # grant approval to a single device ID
  if ( $security::query{'device_id'} ne '' ) {
    my $ud = new PlugNPay::UserDevices;
    $ud->setApprovalForDeviceForUsername( 1, $security::query{'device_id'}, $security::username );
  }
}

sub device_revoke_id {

  # revoke approval from a single device ID
  if ( $security::query{'device_id'} ne '' ) {
    my $ud = new PlugNPay::UserDevices;
    $ud->setApprovalForDeviceForUsername( 0, $security::query{'device_id'}, $security::username );
  }
}

sub device_list_ids {

  # show all device IDs registered, with edit/delete buttons
  my $ud         = new PlugNPay::UserDevices;
  my %device_ids = $ud->deviceIDListForUsername($security::username);

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Registered Devices</td>\n";
  print "    <td class=\"menurightside\">\n";

  print "<form method=post action=\"$security::path_cgi\">\n";

  print "<table border=1 cellspacing=0 cellpadding=4 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <th>Device ID</th>\n";
  print "    <th>Status</th>\n";
  print "    <th>Action</th>\n";
  print "  </tr>\n";

  my $count = 0;
  foreach my $key ( sort keys %device_ids ) {
    $count++;
    print "  <tr>\n";
    print "    <td><input type=checkbox name=\"device_id$count\" value=\"$key\">$key</td>\n";
    print "    <td>";
    if ( $device_ids{$key} == 1 ) {
      print "Approved";
    } else {
      print "<font class=\"error_text\">Revoked</font>";
    }
    print "</td>\n";
    print "    <td><a href=\"$security::path_cgi\?function=device_edit_id\&device_id=$key\" class=\"button\">Edit</a> &nbsp;&nbsp; \n";
    print "<a href=\"$security::path_cgi\?function=device_delete_id\&device_id=$key\" class=\"button\">Delete</a> &nbsp;&nbsp; \n";
    if ( $device_ids{$key} == 1 ) {
      print "<a href=\"$security::path_cgi\?function=device_revoke_id\&device_id=$key\" class=\"button\">Revoke</a> &nbsp;&nbsp; \n";
    } else {
      print "<a href=\"$security::path_cgi\?function=device_approve_id\&device_id=$key\" class=\"button\">Approve</a> &nbsp;&nbsp; \n";
    }
    print "</td>\n";
    print "  </tr>\n";
  }

  if ( $count == 0 ) {
    print "  <tr>\n";
    print "    <td colspan=3 align=center><font class=\"error_text\">No Devices Are Currently Registered</font></td>\n";
    print "  </tr>\n";
  }

  print "</table>\n";

  print "<br><b>Bulk Operation:</b> <select name=\"function\">\n";
  print "<option value=\"show_device_menu\"></option>\n";
  print "<option value=\"approve_devices\">Approve Device(s)</option>\n";
  print "<option value=\"revoke_devices\">Revoke Device(s)</option>\n";
  print "<option value=\"delete_devices\">Delete Device(s)</option>\n";
  print "</select>\n";

  print
    " &nbsp; <input type=submit class=\"button\" name=\"submit\" value=\" Submit \">&nbsp; &nbsp; <a href=\"javascript:help_win('/admin/help.cgi\?subject=securityadmin\&anchor=#device',600,500)\">Online Help</a>\n";
  print "<br><sub><i>* NOTE: Bulk Operation applies to all of those devices you have selected above.</i></sub>\n";
  print "</form>\n";

  print "</td>\n";
  print "  </tr>\n";

  return;
}

sub approve_devices {

  # bulk grant approval to a group of device IDs
  my $ud         = new PlugNPay::UserDevices;
  my %device_ids = $ud->deviceIDListForUsername($security::username);
  my $max        = scalar keys %device_ids;

  for ( my $i = 1 ; $i <= $max ; $i++ ) {
    if ( $security::query{"device_id$i"} ne '' ) {
      $ud->setApprovalForDeviceForUsername( 1, $security::query{"device_id$i"}, $security::username );
    }
  }
}

sub revoke_devices {

  # bulk revokes approval from a group of device IDs
  my $ud         = new PlugNPay::UserDevices;
  my %device_ids = $ud->deviceIDListForUsername($security::username);
  my $max        = scalar keys %device_ids;

  for ( my $i = 1 ; $i <= $max ; $i++ ) {
    if ( $security::query{"device_id$i"} ne '' ) {
      $ud->setApprovalForDeviceForUsername( 0, $security::query{"device_id$i"}, $security::username );
    }
  }
}

sub delete_devices {

  # bulk deletes a group of device IDs
  my $ud         = new PlugNPay::UserDevices;
  my %device_ids = $ud->deviceIDListForUsername($security::username);
  my $max        = scalar keys %device_ids;

  for ( my $i = 1 ; $i <= $max ; $i++ ) {
    if ( $security::query{"device_id$i"} ne '' ) {
      $ud->deleteDeviceForUsername( $security::query{"device_id$i"}, $security::username );
    }
  }
}

sub captchaCheck {
  my ( $self, $message ) = @_;

  # array of field names to pass through
  my @fields = ();
  if ( $security::function eq 'add_user' ) {
    @fields = ( 'newpw', 'login', 'email', 'passwrd1', 'passwrd2', 'temp', 'seclevel', 'new_areas', 'pwtype', 'oldpassword', 'curbun' );
  } elsif ( $security::function =~ /^(update_passwrd|edit_passwrd)$/ ) {
    @fields = ( 'pwtype', 'login', 'passwrd1', 'passwrd2', 'newpw' );
  } elsif ( $security::function eq 'delete_user' ) {
    foreach my $user (@security::deletelist) {
      push( @fields, "delete_" . $user );
    }
  } elsif ( $security::function =~ /^(add_remotepwd|add_mobilepwd)$/ ) {
    @fields = ( 'remotepwd', 'remotepwd_random' );
  }

  print "To complete your request, please fulfill the CAPTCHA request below \& then submit the form.\n";

  if ( $message ne '' ) {
    print "<p><b class=\"error_text\">$message</b>\n";
  }

  print "<p><form method=post action=\"$security::path_cgi\">\n";

  my $captcha = new PlugNPay::Util::Captcha::ReCaptcha();
  print $captcha->formHTML();

  print "<input type=hidden name=\"function\" value=\"$security::function\">\n";
  foreach my $field (@fields) {
    if ( $field eq 'new_areas' ) {
      foreach my $value (@security::new_areas) {
        print "<input type=hidden name=\"$field\" value=\"$value\">\n";
      }
    } elsif ( $security::query{$field} ne '' ) {
      print "<input type=hidden name=\"$field\" value=\"" . $security::query{$field} . "\">\n";
    }
  }
  print "<br><input type=submit value=\"Submit\">\n";
  print "</form>\n";

  print "<p>&nbsp;\n";
}

sub getLoginInfo {
  my $login = shift;
  my $loginClient = new PlugNPay::Authentication::Login({
    login => $login
  });

  $loginClient->setRealm('PNPADMINID');
  my $result = $loginClient->getLoginInfo();

  if (!$result) {
    use PlugNPay::Die;
    die('failed to load login from authentication service');
  }

  return $result->get('loginInfo');
}

1;
