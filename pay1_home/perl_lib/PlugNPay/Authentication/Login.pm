package PlugNPay::Authentication::Login;

use strict;
use PlugNPay::Authentication;
use PlugNPay::Email;
use PlugNPay::Reseller;
use PlugNPay::Util::Array qw(inArray);
use PlugNPay::Util::Status;
use PlugNPay::Util::RandomString;
use PlugNPay::Die;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $args = shift;
  if (ref($args) eq 'HASH' && defined $args->{'login'}) {
    $self->setLogin($args->{'login'});
  }

  return $self;
}

sub getBaseUrl {
  my $domain = PlugNPay::Authentication::getDomain();
  return sprintf("%s/v1", $domain);
}

sub setLogin {
  my $self = shift;
  my $login = shift;
  $login = lc($login);
  if ($login =~ /[^a-z0-9_]/) {
    die('invalid characters in login');
  }

  $self->{'login'} = $login;
}

sub getLogin {
  my $self = shift;
  my $login = $self->{'login'};

  if (!defined $login) {
    die('login not set');
  }
  return $login;
}

sub setRealm {
  my $self = shift;
  my $realm = shift;
  $realm = lc($realm);
  if ($realm =~ /[^a-z0-9]/) {
    die(sprintf('invalid realm: %s',$realm));
  }

  $self->{'realm'} = $realm;
}

sub getRealm {
  my $self = shift;
  my $realm = $self->{'realm'};
  if (!defined $realm) {
    die('realm not set');
  }
  return uc $realm;
}

sub setPassword {
  my $self = shift;
  my $input = shift;

  my $password = $input->{'password'} || '';
  my $currentPassword = $input->{'currentPassword'} || '';
  my $tempFlag = $input->{'passwordIsTemporary'};

  my $rStatus = new PlugNPay::Util::Status(0);

  my $url = sprintf('%s/%s/login/%s/password', getBaseUrl(), $self->getRealm(), $self->getLogin());
  my $data = {
    password => $password,
    currentPassword => $currentPassword
  };

  if (defined $tempFlag) {
    if ($tempFlag) {
      $data->{'passwordIsTemporary'} = \1;
    } else {
      $data->{'passwordIsTemporary'} = \0;
    }
  }

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($url);
  $ms->setContent($data);
  $ms->setContentType('application/json');
  $ms->setMethod('POST');
  my $status = $ms->doRequest();
  if ($status) {
    $rStatus->setTrue()
  } else {
    my $response = $ms->getDecodedResponse();
    $rStatus->setError($response->{'message'});
  }

  return $rStatus;
}

sub clearPasswordHistory {
  my $self = shift;
  my $input = shift;

  my $rStatus = new PlugNPay::Util::Status(0);

  my $url = sprintf('%s/%s/login/%s/password/history', getBaseUrl(), $self->getRealm(), $self->getLogin());

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($url);
  $ms->setContentType('application/json');
  $ms->setMethod('DELETE');
  my $status = $ms->doRequest();
  if ($status) {
    $rStatus->setTrue()
  } else {
    my $response = $ms->getDecodedResponse();
    $rStatus->setError($response->{'message'});
  }

  return $rStatus;
}

sub setDirectories {
  my $self = shift;
  my $input = shift;

  my $directories = $input->{'directories'};

  if (ref($directories) ne 'ARRAY') {
    die('directories is not an array');
  }

  my $rStatus = new PlugNPay::Util::Status(0);

  my $url = sprintf('%s/%s/login/%s/acl', getBaseUrl(), $self->getRealm(), $self->getLogin());
  my $data = {
    acl => $directories
  };

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($url);
  $ms->setContent($data);
  $ms->setContentType('application/json');
  $ms->setMethod('POST');
  my $status = $ms->doRequest();

  if ($status) {
    $rStatus->setTrue()
  } else {
    my $response = $ms->getDecodedResponse();
    $rStatus->setError($response->{'message'});
  }

  return $rStatus;
}

sub addDirectories {
  my $self = shift;
  my $input = shift;

  my $directories = $input->{'directories'};

  if (ref($directories) ne 'ARRAY') {
    die('directories is not an array');
  }

  my $rStatus = new PlugNPay::Util::Status(0);

  my $url = sprintf('%s/%s/login/%s/acl', getBaseUrl(), $self->getRealm(), $self->getLogin());
  my $data = {
    acl => $directories
  };

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($url);
  $ms->setContent($data);
  $ms->setContentType('application/json');
  $ms->setMethod('PUT'); # PUT to add directories
  my $status = $ms->doRequest();
  if ($status) {
    $rStatus->setTrue()
  } else {
    my $response = $ms->getDecodedResponse();
    $rStatus->setError($response->{'message'});
  }

  return $rStatus;
}

sub removeDirectories {
  my $self = shift;
  my $input = shift;

  my $directories = $input->{'directories'};

  if (ref($directories) ne 'ARRAY') {
    die('directories is not an array');
  }

  my $rStatus = new PlugNPay::Util::Status(0);

  my $url = sprintf('%s/%s/login/%s/acl', getBaseUrl(), $self->getRealm(), $self->getLogin());
  my $data = {
    acl => $directories
  };

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($url);
  $ms->setContent($data);
  $ms->setContentType('application/json');
  $ms->setMethod('DELETE'); # DELETE to remove directories
  my $status = $ms->doRequest();
  if ($status) {
    $rStatus->setTrue()
  } else {
    my $response = $ms->getDecodedResponse();
    $rStatus->setError($response->{'message'});
  }

  return $rStatus;
}

sub setTemporaryPasswordMarker {
  my $self = shift;

  return $self->_updateTemporaryPasswordMarker({
    passwordIsTemporary => 1
  });
}

sub clearTemporaryPasswordMarker {
  my $self = shift;

  return $self->_updateTemporaryPasswordMarker({
    passwordIsTemporary => 0
  });
}

sub _updateTemporaryPasswordMarker {
  my $self = shift;
  my $input = shift;

  my $value = $input->{'passwordIsTemporary'};

  if (!defined $value || !inArray($value,[0,1])) {
    die('invalid value for passwordIsTemporary');
  }

  my $rStatus = new PlugNPay::Util::Status(0);

  my $url = sprintf('%s/%s/login/%s/password/temporary', getBaseUrl(), $self->getRealm(), $self->getLogin());
  my $data = {
    passwordIsTemporary => \$value
  };

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($url);
  $ms->setContent($data);
  $ms->setContentType('application/json');
  $ms->setMethod('PUT');
  my $status = $ms->doRequest();
  if ($status) {
    $rStatus->setTrue()
  } else {
    my $response = $ms->getDecodedResponse();
    $rStatus->setError($response->{'message'});
  }

  return $rStatus;
}

sub setSecurityLevel {
  my $self = shift;
  my $input = shift;

  my $value = $input->{'securityLevel'};

  if (!defined $value || $value =~ /\D/) {
    die('invalid value for securityLevel');
  }

  my $rStatus = new PlugNPay::Util::Status(0);

  my $url = sprintf('%s/%s/login/%s/securitylevel', getBaseUrl(), $self->getRealm(), $self->getLogin());
  my $data = {
    securityLevel => ($value + 0) # force to integer
  };

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($url);
  $ms->setContent($data);
  $ms->setContentType('application/json');
  $ms->setMethod('PUT');
  my $status = $ms->doRequest();
  if ($status) {
    $rStatus->setTrue()
  } else {
    my $response = $ms->getDecodedResponse();
    $rStatus->setError($response->{'message'});
  }

  return $rStatus;
}

sub setEmailAddress {
  my $self = shift;
  my $input = shift;

  my $value = $input->{'emailAddress'};

  if (!defined $value) {
    die('invalid value for emailAddress');
  }

  my $rStatus = new PlugNPay::Util::Status(0);

  my $url = sprintf('%s/%s/login/%s/emailaddress', getBaseUrl(), $self->getRealm(), $self->getLogin());
  my $data = {
    emailAddress => $value
  };

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($url);
  $ms->setContent($data);
  $ms->setContentType('application/json');
  $ms->setMethod('PUT');
  my $status = $ms->doRequest();
  if ($status) {
    $rStatus->setTrue()
  } else {
    my $response = $ms->getDecodedResponse();
    $rStatus->setError($response->{'message'});
  }

  return $rStatus;
}

sub setFeatures {
  my $self = shift;
  my $input = shift;

  my $value = $input->{'features'};

  if (!defined $value || ref($value) ne 'HASH') {
    die('invalid value for features, must be a hashref');
  }

  my $rStatus = new PlugNPay::Util::Status(0);

  my $url = sprintf('%s/%s/login/%s/features', getBaseUrl(), $self->getRealm(), $self->getLogin());
  my $data = {
    features => $value
  };

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($url);
  $ms->setContent($data);
  $ms->setContentType('application/json');
  $ms->setMethod('PUT');
  my $status = $ms->doRequest();
  if ($status) {
    $rStatus->setTrue()
  } else {
    my $response = $ms->getDecodedResponse();
    $rStatus->setError($response->{'message'});
  }

  return $rStatus;
}

sub getLoginInfo {
  my $self = shift;
  my $input = shift;

  my $login = $input->{'login'} || $self->getLogin();

  if (!defined $login || $login eq '' || $login =~ /[^a-z0-9]/) {
    die('invalid value for login: "' . $login . '"');
  }

  my $rStatus = new PlugNPay::Util::Status(0);

  my $url = sprintf('%s/%s/login/%s', getBaseUrl(), $self->getRealm(), $login);

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($url);
  $ms->setContentType('application/json');
  $ms->setMethod('GET');
  my $status = $ms->doRequest();

  if ($status) {
    $rStatus->setTrue();
    my $data = $ms->getDecodedResponse();
    # for consistency, copy 'acl' key to 'directories' key
    $data->{'directories'} = $data->{'acl'};
    $rStatus->set('loginInfo',$data);
  } else {
    my $response = $ms->getDecodedResponse();
    $rStatus->setError($response->{'message'});
  }

  return $rStatus;
}

sub getLoginsForAccount {
  my $self = shift;
  my $input = shift;

  my $account = $input->{'account'};

  if (!defined $account || $account eq '' || $account =~ /[^a-z0-9]/) {
    die('invalid value for account');
  }

  my $rStatus = new PlugNPay::Util::Status(0);

  my $url = sprintf('%s/%s/account/%s/logins', getBaseUrl(), $self->getRealm(), $account);

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($url);
  $ms->setContentType('application/json');
  $ms->setMethod('GET');
  my $status = $ms->doRequest();
  if ($status) {
    $rStatus->setTrue();
    my $data = $ms->getDecodedResponse();
    $rStatus->set('logins',$data->{'logins'});
  } else {
    my $response = $ms->getDecodedResponse();
    $rStatus->setError($response->{'message'});
  }

  return $rStatus;
}

sub updateLogin {
  my $self = shift;
  my $input = shift;

  my $data = {};

  $data->{'account'}       = $input->{'account'}           if defined $input->{'account'};
  $data->{'securityLevel'} = $input->{'securityLevel'} + 0 if defined $input->{'securityLevel'};
  $data->{'acl'}           = $input->{'directories'}       if defined $input->{'directories'};
  $data->{'password'}      = $input->{'password'}          if defined $input->{'password'};
  $data->{'features'}            = featuresToFeaturesMap($input->{'features'}) if defined $input->{'features'};
  $data->{'passwordIsTemporary'} = ($input->{'passwordIsTemporary'} ? \1 : \0) if defined $input->{'passwordIsTemporary'};

  my $rStatus = new PlugNPay::Util::Status(0);

  my $url = sprintf('%s/%s/login/%s', getBaseUrl(), $self->getRealm(), $self->getLogin());

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($url);
  $ms->setContent($data);
  $ms->setContentType('application/json');
  $ms->setMethod('POST');
  my $status = $ms->doRequest();
  if ($status) {
    $rStatus->setTrue();
  } else {
    my $response = $ms->getDecodedResponse();
    $rStatus->setError($response->{'message'});
  }

  return $rStatus;
}

sub createLogin {
  my $self = shift;
  my $input = shift;

  my $data = {
    account => $input->{'account'},
    securityLevel => $input->{'securityLevel'} + 0,
    passwordIsTemporary => $input->{'passwordIsTemporary'} ? \1 : \0,
    password => $input->{'password'},
    emailAddress => $input->{'emailAddress'},
    features => featuresToFeaturesMap($input->{'features'}),
    acl => $input->{'directories'} || []
  };

  my $rStatus = new PlugNPay::Util::Status(0);

  my $url = sprintf('%s/%s/login/%s', getBaseUrl(), $self->getRealm(), $self->getLogin());

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($url);
  $ms->setContent($data);
  $ms->setContentType('application/json');
  $ms->setMethod('POST');
  my $status = $ms->doRequest();
  if ($status) {
    $rStatus->setTrue();
  } else {
    my $response = $ms->getDecodedResponse();
    $rStatus->setError($response->{'message'});
  }

  return $rStatus;
}

sub createPasswordResetID {
  my $self = shift;
  my $input = shift;

  my $override = defined $input->{'override'} ? $input->{'override'} : '';

  my $data = {
    emailAddress => $input->{'emailAddress'},
    override     => $override
  };

  my $rStatus = new PlugNPay::Util::Status(0);

  my $url = sprintf('%s/%s/login/%s/reset-id', getBaseUrl(), $self->getRealm(), $self->getLogin());

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($url);
  $ms->setContent($data);
  $ms->setContentType('application/json');
  $ms->setMethod('POST');
  my $status = $ms->doRequest();
  if ($status) {
    $rStatus->setTrue();
    my $data = $ms->getDecodedResponse();
    $rStatus->set('resetID',$data->{'resetID'});
  } else {
    my $response = $ms->getDecodedResponse();
    $rStatus->setError($response->{'message'});
  }

  return $rStatus;
}

sub usePasswordResetID {
  my $self = shift;
  my $input = shift;

  my $override = defined $input->{'override'} ? $input->{'override'} : '';

  my $data = {
    resetID => $input->{'resetID'},
    override     => $override
  };

  my $rStatus = new PlugNPay::Util::Status(0);

  my $url = sprintf('%s/%s/reset-id', getBaseUrl(), $self->getRealm());

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($url);
  $ms->setContent($data);
  $ms->setContentType('application/json');
  $ms->setMethod('POST');
  my $status = $ms->doRequest();
  if ($status) {
    $rStatus->setTrue();
    my $data = $ms->getDecodedResponse();
    $rStatus->set('login', $data->{'login'});
    $rStatus->set('emailAddress', $data->{'emailAddress'});
    $rStatus->set('password', $data->{'password'});
  } else {
    my $response = $ms->getDecodedResponse();
    $rStatus->setFalse();
    $rStatus->setError($response->{'message'});
  }

  return $rStatus;
}

sub featuresMapToString {
  my $self = shift;
  my $features = shift;

  if (!defined $features) {
    return '';
  }

  if (ref($features) ne 'HASH') {
    die('features is not a hash');
  }

  # without the sort, this can not be tested reliably
  return join(',',map { sprintf("%s=%s",$_,$features->{$_}) } sort keys %{$features});
}

sub featuresToFeaturesMap {
  my $self = shift;
  my $features = shift;

  # if it's already a map, return it
  if (ref($features) eq 'HASH') {
    return $features;
  }

  # convert features object to string
  if (ref($features) eq 'PlugNPay::Features') {
    $features = "$features";
  }

  if (!defined $features || $features eq '') {
    return {};
  }

  my %featuresMap;
  foreach my $pair (split(/,/,$features)) {
    my ($featureName, $featureValue) = split(/=/,$pair);
    $featuresMap{$featureName} = $featureValue;
  }

  return \%featuresMap;
}

sub autoResetPassword {
  my $self = shift;
  my $emailAddress = shift;

  my $result = $self->setRandomTemporaryPassword();
  if (!$result) {
    return $result;
  }

  return $self->emailPassword($emailAddress, $result->get('password'));
}

sub setRandomTemporaryPassword {
  my $self = shift;

  my $password = new PlugNPay::Util::RandomString()->randomAlphaNumeric(16);
  my $result = $self->setPassword({
    password => $password,
    passwordIsTemporary => 1,
  });

  $result->set('password',$password);

  return $result;
}

sub emailPassword {
  my $self = shift;
  my $emailAddress = shift;
  my $password = shift;

  my $result = $self->getLoginInfo();

  # result is a status object
  if (!$result) {
    return $result;
  }

  my $loginInfo = $result->get('loginInfo');
  my $account = $loginInfo->{'account'};

  my $ra = new PlugNPay::Reseller($account);
  my $fromAddress = $ra->getSupportEmail();

  if (!$result) {
    return $result;
  }

  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setGatewayAccount($account);
  $emailObj->setFormat('text');
  $emailObj->setTo($emailAddress);
  $emailObj->setFrom($fromAddress);
  $emailObj->setSubject('Your password has been reset.');

  my $emailmessage = '';
  $emailmessage .= "Dear Merchant,\n\n";
  $emailmessage .= "Your password has been reset.\n\n";
  $emailmessage .= "Your new password is shown below.\n\n";
  $emailmessage .= "It is a temporary password and will be required to be changed the first time you log in.\n";
  $emailmessage .= "Password:$password\n";
  $emailmessage .= "Support Staff\n";

  $emailObj->setContent($emailmessage);

  # returns as status object
  $result = $emailObj->send();
  return $result;
}

1;
