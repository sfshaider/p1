package PlugNPay::Environment;

use strict;
use PlugNPay::CGI;
use PlugNPay::InputValidator;
use PlugNPay::API;
use PlugNPay::Features;
use PlugNPay::GatewayAccount;
use PlugNPay::Username;
use PlugNPay::Util::Memcached;

my $singleton = undef;



sub new {
  my $class = shift;
  my $exists;

  if (defined $singleton) {
    $exists = 1;
  }


  my $username = shift;

  # get settings argument
  # if settings is undefined and username is a reference, username is actually the settings.
  # if username is undefined, set settings to an empty hash reference
  my $settings = shift || (ref($username) ? $username : {}); # hash reference, if key 'local' exists and it's value is true, we return an instance of environment without overriding $singleton

  # if username is a reference, it's actually the settings, so we set username to undefined.
  if (ref($username)) {
    $username = undef;
  }

  # if username is undefined, singleton is defined and settings local is false
  # then return the already defined singleton
  if (!defined $username && defined $singleton && !$settings->{'local'}) {
    return $singleton;
  }

  my $localEnvironment;

  $localEnvironment = {};
  bless $localEnvironment, $class;

  # load already set PNP_* environment variables
  foreach my $key (grep { /^PNP_/ } keys %ENV) {
    $localEnvironment->{'settings'}{$key} = $ENV{$key};
  }

  if (exists $ENV{'HTTP_X_FORWARDED_HOST'}) {
    $localEnvironment->{'settings'}{'PNP_SERVER_NAME'} = (reverse(split(',',$ENV{'HTTP_X_FORWARDED_HOST'})))[0];
  } else {
    $localEnvironment->{'settings'}{'PNP_SERVER_NAME'} = $ENV{'HTTP_HOST'};
  }

  $localEnvironment->{'settings'}{'PNP_CLIENT_IP'} = getClientIP();

  my $cgi = new CGI();

  my %headers = map { $_ => $cgi->http($_) } $cgi->http();
  $localEnvironment->{'headers'} = \%headers;

  my %query = $cgi->Vars;

  # let's start being consistent...from now on everything is underscores!  find hyphen parameter names and replace them with underscore versions
  foreach my $hyphenName (grep {/\-/} keys %query) {
    my $underscoreName = $hyphenName;
    $underscoreName =~ s/\-/_/g; 
    $query{$underscoreName} = $query{$hyphenName};
    delete $query{$hyphenName};
  }
  
  $localEnvironment->{'query'} = \%query;

  my $localEnvironmentSet;
    
  # load username data only if any of the following conditions are true
  # 1) the local setting is set to a true value
  # 2) the singleton is not defined
  # 3) the singleton is defined and username is not defined
  # 3) username is passed to the constructor and it is not the same as the logged in user
  #
  if (($settings->{'local'}) ||
      (!defined $singleton) || 
      (defined $singleton && defined $username && $singleton->get('PNP_ACCOUNT') ne $username)) {
    $localEnvironmentSet = 1;

    my $queryUsername = $query{'pt_gateway_account'} || $query{'publisher-name'} || $query{'publisher_name'} || '';
  
    # filter username from query
    $queryUsername =~ s/[^A-Za-z0-9]//g;
  
    $username = $username || $ENV{'REMOTE_USER'} || $queryUsername;
  
    if ($username ne '') { # && (!exists $localEnvironment->{'accountInformationLoaded'} && $localEnvironment->{'accountInformationLoaded'} ne $username)) {
      my $accountInfo = $localEnvironment->loadAccountInformation($username);
      $localEnvironment->{'settings'}{'PNP_SECURITY_LEVEL'} = $accountInfo->{'securityLevel'};
      $localEnvironment->{'settings'}{'PNP_RESELLER'} = $accountInfo->{'reseller'};
      $localEnvironment->{'settings'}{'PNP_COBRAND'} = $accountInfo->{'cobrand'};
      $localEnvironment->{'settings'}{'PNP_ACCOUNT'} = $accountInfo->{'gatewayAccount'};
      $localEnvironment->{'settings'}{'PNP_USER'} = $username;
  
      $localEnvironment->{'accountInformationLoaded'} = $username;
    }
  }

  if ($localEnvironmentSet && !$settings->{'local'}) {
    $singleton = $localEnvironment;
    # we have to clear the singleton for every request in mod_perl
    if (ref($singleton) && !exists $singleton->{'handlerSet'} && exists $ENV{'MOD_PERL'}) {
      require Apache2::RequestUtil;
      my $r;
  
      eval {
        $r = Apache2::RequestUtil->request;
      };
  
      if ($r) {
        if (defined $r->connection()->keepalive) {
          $r->connection()->keepalive($Apache2::Const::CONN_CLOSE);
        }
        $r->push_handlers(PerlCleanupHandler => sub {&cleanup()});
        $localEnvironment->{'handlerSet'} = 1;
      }
    }
  } 

  if ($settings->{'local'}) {
    return $localEnvironment;
  }
  return $singleton;
}  

sub getClientIP {
  my $firstVal;
  
  if (exists $ENV{'HTTP_X_FORWARDED_FOR'}) {
    $firstVal = (split(/,/, $ENV{'HTTP_X_FORWARDED_FOR'}))[0];
    $firstVal =~ s/^\s+|\s+$//g;
  }

  return $firstVal || $ENV{'REMOTE_ADDR'};
}

sub get {
  my $self = shift;
  my $key = shift;
  if (!$key) { # called statically
    $key = $self;
  }
  if ($key =~ /^PNP_/) {
    if ($key ne $self) {
      if (!exists $self->{'settings'}{$key}) {
        $self->{'settings'}{$key} = $self->getFromDatabase($key);
      } else {
        return $self->{'settings'}{$key};
      }
    } else {
      if (exists $ENV{$key}) {
        return $ENV{$key};
      } else {
        return $self->getFromDatabase($key);
      }
    }
  }
}

sub isContainer {
  return -e '/home/pay1/etc/is_container';
}

sub getFromDatabase {
  my $self = shift;
  my $key = shift;
  $key =~ s/[^A-Za-z0-9_]//g;

  my $memcached = new PlugNPay::Util::Memcached('pnp_environment_settings');

  my $cachedValue = $memcached->get($key);

  if ($cachedValue ne '') {
    return $cachedValue;
  }

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q/
    SELECT value
    FROM pnp_environment_settings
    WHERE setting_name = ?
  /);
  $sth->execute($key);

  my $row = $sth->fetchrow_hashref;
  if (defined $row) {
    $memcached->set($key, $row->{'value'},900);
    return $row->{'value'};
  }
  return '';
}

sub getAPI {
  my $self = shift;
  my $context = shift;

  if (!defined $context) {
    return undef;
  } else {
    return new PlugNPay::API($context);
  }
}

sub getQuery {
  my $self = shift;
  my $context = shift;

  $context =~ s/[^A-Za-z0-9_]//g;

  my %query;

  if (!defined $context || $context eq '') {
    return %query;
  }

  my $iv = new PlugNPay::InputValidator();
  $iv->changeContext($context);
  return $iv->filterHash(%{$self->{'query'}});
}

sub getFeatures {
  my $self = shift;
  return $self->{'features'};
}

sub getHeaders {
  my $self = shift;
  return %{$self->{'headers'}};
}

sub loadAccountInformation {
  my $self = shift;
  my $username = lc shift;

  $username =~ s/[^a-z0-9]//g;

  my $un = new PlugNPay::Username($username);

  my $accountName  = $un->getGatewayAccount();

  my %info;

  # Set the gatewayAccount
  $info{'gatewayAccount'} = $accountName;

  # Get the corbrand, if one is set.
  my $features = new PlugNPay::Features($accountName,'general');
  $self->{'features'} = $features;
  $info{'cobrand'} = $features->get('cobrand');

  # Get the reseller from the account;
  my $account = new PlugNPay::GatewayAccount($accountName);
  $info{'reseller'} = $account->getReseller();

  # Get the security level
  $info{'securityLevel'} = $un->getSecurityLevel();

  return \%info;
}

END {
  cleanup();
}

sub cleanup {
  $singleton = undef;
}

1;

