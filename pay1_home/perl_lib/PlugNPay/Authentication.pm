package PlugNPay::Authentication;

use strict;
use URI::Escape;
use PlugNPay::DBConnection;
use PlugNPay::ResponseLink::Microservice;
use Types::Serialiser;
use PlugNPay::AWS::ParameterStore;

# authentication server, only read once from env or AWS Parameter Store
our $cachedServer;

our $lastLoginRealm = "";
our $lastLoginRealmInfo = {};

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $logger = new PlugNPay::Logging::DataLog({'collection' => 'authentication'});
  $self->{'logger'} = $logger;

  return $self;
}

sub getDomain {
  my $self = shift;

  if (!$cachedServer) {
    my $env = $ENV{'PNP_AUTH_SERVER'};
    $cachedServer = $env || PlugNPay::AWS::ParameterStore::getParameter('/AUTH/SERVER',1);
    # remove trailing slash if it's there (and multiple because why not)
    $cachedServer =~ s/\/+$//;
  }

  return $cachedServer;
}

sub getBaseUrl {
  my $domain = getDomain();
  return sprintf("%s/v1", $domain);
}

sub validateLogin {
  my $self = shift;
  my $info = shift;
  my $options = shift || {};

  # set up default options
  if (!defined $options->{'generateCookie'}) {
    $options->{'generateCookie'} = 1;
  }

  if (!defined $options->{'rehash'}) {
    $options->{'rehash'} = 0;
  }

  my $password = $info->{'password'};
  my $loginName = $info->{'login'};
  my $realm = $info->{'realm'};
  my $override = $info->{'override'};
  my $version = $info->{'version'};

  # convert isApiLogin to boolean value for JSON
  my $isApiLogin = ($info->{'isApiLogin'} ? Types::Serialiser::true : Types::Serialiser::false);

  my $generateCookie = ($options->{'generateCookie'} ? Types::Serialiser::true : Types::Serialiser::false);
  my $rehash = ($options->{'rehash'} ? Types::Serialiser::true : Types::Serialiser::false);

  my $baseUrl = $self->getBaseUrl();

  $loginName = $self->filterLogin($loginName);
  $realm =~ s/[^a-zA-Z0-9]//g;

  my $link = new PlugNPay::ResponseLink::Microservice();
  $link->setURL(sprintf('%s/%s/login/%s/authenticate', $baseUrl, $realm, $loginName));
  $link->setMethod('POST');
  my $data = {
    'merchant'       => $info->{'merchant'},
    'account'        => $info->{'merchant'},
    'password'       => $password,
    'isApiLogin'     => $isApiLogin,
    'generateCookie' => $generateCookie,
    'rehash'         => $rehash,
    'version'        => $version
  };

  # add override only if it exists
  if ($override) {
    $data->{'override'} = $override;
  }

  $link->setContentType('application/json');
  $link->setContent($data);

  my $wasSuccess = $link->doRequest();
  if (!$wasSuccess) {
    my @errors = $link->getErrors();
    $self->{'logger'}->log({'errors' => \@errors, 'login' => $loginName, 'method' => 'validateLogin'});
  } else {
    $self->{'response'} = $link->getDecodedResponse();
  }

  return $wasSuccess;
}

sub canOverride {
  my $self = shift;
  my $canOverride = $self->{'response'}{'canOverride'} || 0;
  return $canOverride;
}

sub getOverrideType {
  my $self = shift;
  my $overrideType = $self->{'response'}{'overrideType'} || '';
  return $overrideType;
}

sub getCookieValue {
  my $self = shift;
  my $cookieValue = $self->{'response'}{'cookie'};
  return $cookieValue;
}

sub validateCookie {
  my $self = shift;
  my $info = shift;
  my $valid = 0;

  my $cookie = uri_unescape($info->{'cookie'});
  my $realm = $info->{'realm'};
  my $update = $info->{'update'};

  if (!defined $update) {
    $update = Types::Serialiser::true; # maps to true with JSON::XS
  }

  my $data = {'cookie' => $cookie, 'update' => $update};

  my $baseUrl = $self->getBaseUrl();
  my $link = new PlugNPay::ResponseLink::Microservice();

  $link->setURL($baseUrl . '/' . $realm . '/cookie/validate');
  $link->setMethod('POST');
  $link->setContentType('application/json');
  $link->setContent($data);

  my $wasSuccess = $link->doRequest();
  if (!$wasSuccess) {
    my @errors = $link->getErrors();
    $self->{'logger'}->log({'errors' => \@errors, 'method' => 'validateCookie'});
  } else {
    $self->{'response'} = $link->getDecodedResponse();
    if ($self->{'response'}{'isValid'}) {
      my $effectiveLogin = $self->{'response'}{'override'} || $self->{'response'}{'login'};
      $lastLoginRealm = $self->createLastLoginRealmKey($effectiveLogin,$realm);
      $lastLoginRealmInfo = $self->{'response'};
      $valid = 1;
    }
  }

  return $valid;
}

sub getCookie {
  my $self = shift;
  my $cookie = $self->{'response'}{'cookie'};
  return $cookie;
}

sub getLogin {
  my $self = shift;
  my $login = $self->{'response'}{'login'};
  return $login;
}

sub getOverrideLogin {
  my $self = shift;
  my $overrideLogin = $self->{'response'}{'override'};
  return $overrideLogin;
}

sub getAccount {
  my $self = shift;
  my $account = $self->{'response'}{'account'};
  return $account;
}

sub getSubAccount {
  my $self = shift;
  my $subaccount = $self->{'response'}{'subAccount'};
  return $subaccount;
}

sub getSecurityLevel {
  my $self = shift;
  my $securityLevel = $self->{'response'}{'securityLevel'};
  return $securityLevel;
}

sub getMustChangePassword {
  my $self = shift;
  my $mustChangePassword = $self->{'response'}{'mustChangePassword'};
  return $mustChangePassword;
}

sub getReason {
  my $self = shift;
  my $reason = $self->{'response'}{'reason'};
  return $reason;
}

sub canAccess {
  my $self = shift;
  my $info = shift;

  my $access = $info->{'group'};
  my $login = $info->{'login'};
  my $realm = $info->{'realm'};

  my @checklist;
  my $hasAccess = 0;

  # if we have the data from the validation response, check it.
  if ($lastLoginRealm eq $self->createLastLoginRealmKey($login,$realm) &&
      $lastLoginRealmInfo->{'acl'} && ref($lastLoginRealmInfo->{'acl'}) eq 'ARRAY') {
    @checklist = @{$lastLoginRealmInfo->{'acl'}};
  } else { # otherwise call the login access endpoint
    my $loginClient = new PlugNPay::Authentication::Login({
      login => $login
    });
    $loginClient->setRealm($realm);
    my $result = $loginClient->getLoginInfo();
    if ($result) {
      my $loginInfo = $result->get('loginInfo');
      @checklist = @{$loginInfo->{'acl'}};
    }
  }

  foreach my $entry (@checklist) {
    if (lc($entry) eq lc($access)) {
      $hasAccess = 1;
      last;
    }
  }

  return $hasAccess;
}

sub expireSession {
  my $self = shift;
  my $info = shift;
  my $login = $info->{'login'};
  my $realm = $info->{'realm'};
  my $cookie = uri_unescape($info->{'cookie'});

  my $baseUrl = $self->getBaseUrl();
  my $link = new PlugNPay::ResponseLink::Microservice();
  my $url = sprintf('%s/%s/cookie', $baseUrl, $realm);
  $link->setURL($url);
  $link->setMethod('DELETE');
  $link->setContentType('application/json');
  $link->setContent({'cookie' => $cookie});
  my $status = $link->doRequest();

  return $status;
}

sub getTimeRemaining {
  my $self = shift;
  my $info = shift; # realm and cookie keys required

  $info->{'update'} = Types::Serialiser::false; # maps to false in JSON::XS

  $self->validateCookie($info);

  return $self->{'response'}{'expiresInSeconds'};
}

sub createLastLoginRealmKey {
  my $self = shift;
  my $login = shift;
  my $realm = shift;
  my $key = sprintf('%s:%s',$login,$realm);
  return $key;
}

# REGEX Functions #
sub filterLogin {
  my $self = shift;
  my $login = lc(shift);
  $login =~ s/[^a-zA-Z0-9\@\.\-\_]//g;

  return $login;
}

1;
