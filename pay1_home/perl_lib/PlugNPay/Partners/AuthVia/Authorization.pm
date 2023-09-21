package PlugNPay::Partners::AuthVia::Authorization;

use strict;
use PlugNPay::ResponseLink;
use PlugNPay::Sys::Time;
use PlugNPay::Logging::DataLog;
use PlugNPay::AWS::ParameterStore;
use PlugNPay::Partners::AuthVia::Merchant;
use PlugNPay::ResponseLink::Microservice;
use PlugNPay::Die qw(fail);

our $_authViaURL;
our $_serviceURL;
our $_clientSecretMap;
our $_authViaSecret;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  if (!defined $_clientSecretMap || ref($_clientSecretMap) ne 'HASH') {
    $_clientSecretMap = {};
  }

  my $partner = shift;
  if (defined $partner) {
    $self->setPartner($partner)
  }

  my $username = shift; 
  if (defined $username) { 
    $self->setGatewayAccount($username); 
  } 

  return $self;
}

sub _loadServiceURL {
  $_serviceURL = &PlugNPay::AWS::ParameterStore::getParameter('/SERVICE/AUTHVIA/URL');
}

sub getServiceURL {
  if (!defined $_serviceURL) {
    &_loadServiceURL();
  }

  return $_serviceURL;
}

sub _loadAuthViaURL {
  $_authViaURL = &PlugNPay::AWS::ParameterStore::getParameter('/PARTNER/AUTHVIA/URL');
}

sub getAuthViaURL {
  if (!defined $_authViaURL) {
    #alert 
    &_loadAuthViaURL();
  }
  return $_authViaURL;
}

sub getAuthViaSecret {
  if (!defined $_authViaSecret) {
     $_authViaSecret = &PlugNPay::AWS::ParameterStore::getParameter('/PARTNER/AUTHVIA/SECRET');
  }

  return $_authViaSecret;
}

sub setGatewayAccount {
  my $self = shift;
  my $username = shift;
  $self->{'username'} = $username;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'username'};
}

sub setPartner {
  my $self = shift;
  my $partner = shift;
  $self->{'partner'} = $partner;
}

sub getPartner {
  my $self = shift;
  return $self->{'partner'};
}

sub setSecretString {
  my $self = shift;
  my $secretString = shift;
  $self->{'secretString'} = $secretString;
}

sub getSecretString {
  my $self = shift;
  $self->loadClientIfNotLoaded();

  return $self->{'secretString'};
}

sub setClientId {
  my $self = shift;
  my $clientId = shift;
  $self->{'clientId'} = $clientId;
}

sub getClientId {
  my $self = shift;
  $self->loadClientIfNotLoaded();
  return $self->{'clientId'};
}

sub setClientUsername {
  my $self = shift;
  my $clientUsername = shift;
  $self->{'clientUsername'} = $clientUsername;
}

sub getClientUsername {
  my $self = shift;
  return $self->{'clientUsername'};
}

sub getClientRowId {
  my $self = shift;
  my $username = shift;
  my $data = $self->loadClientInfo();

  return $data->{'clientRowId'};
}

sub setReloadClientInfo {
  my $self = shift;
  $self->{'reload'} = 1;
}

sub shouldReloadClientInfo {
  my $self = shift;
  return $self->{'reload'};
}

sub loadClientIfNotLoaded {
  my $self = shift;
  if (!defined $self->{'secretString'} && !defined $self->{'clientId'}) {
    my $data = $self->loadClientInfo();
    $self->{'clientId'} = $data->{'clientId'};
    $self->{'secretString'} = $data->{'secret'};
    $self->{'clientUsername'} = $data->{'partnerName'};
  }
}

#returns client authorization info for a gateway account
sub loadClientInfo {
  my $self = shift;
  my $account = $self->getPartner() || $self->getGatewayAccount();

  if (!defined $account) {
    fail("No gateway account set");
  }

  my $data = $_clientSecretMap->{$self->getGatewayAccount()};
  if (ref($data) ne 'HASH' || !$data->{'clientId'} || !$data->{'secret'} || !$data->{'partnerName'}) {
    my $url = $self->getServiceURL() . '/partner/username/' . $account;

    my $ms = new PlugNPay::ResponseLink::Microservice();
    $ms->setMethod('GET');
    $ms->setURL($url);
    $ms->doRequest();
    
    $data = $ms->getDecodedResponse();

    $_clientSecretMap->{$account} = {
      'clientRowId' => $data->{'clientRowId'},
      'clientId'    => $data->{'clientId'},
      'partnerName' => $data->{'partnerName'},
      'secret'      => $data->{'secret'}
    };
  }

  return $data;
}

=pod
  Creating Token: 
  Generate a random string, at least 16 characters, with longer values being encouraged. We suggest 100 characters.
  Get the current time in seconds (GMT), must be within 5 seconds of current EPOCH.
  Combine these 3 values together in a string, with dots separating each value.
  HMAC 256 encoded using the shared secret.
  Base64 URL encode the encoded value, the result is your signature.
=cut

#Generates token for authorization
sub createJWTToken {
  my $self = shift;
  my $authViaSecret = $self->getAuthViaSecret();

  my $timeObj = new PlugNPay::Sys::Time();
  $timeObj->addSeconds(5); # must be within 5 seconds of current EPOCH.
  my $secretLength = length($authViaSecret);
  my $timeStamp = $timeObj->nowInFormat('unix');
  my $secretString = $authViaSecret . '.' . $secretLength . '.' . $timeStamp;

  my $hasher = new PlugNPay::Util::Hash();
  $hasher->add($secretString);
  my $digested = $hasher->hmacSHA256Base64($self->getSecretString(), 1); # the 1 adds padding

  return {
    'token'     => $digested,
    'timestamp' => $timeStamp,
    'secret'    => $authViaSecret,
    'length'    => $secretLength
  };
}

#registers token with authvia with 15 minute expire time
sub generateAuthorizationRequest {
  my $self = shift;
  my $options = shift;
  $self->loadClientIfNotLoaded();

  my $newJWT = $self->createJWTToken();
  my $hash = {
    'client_id'       => $self->getClientId(),
    'signature_value' => $newJWT->{'secret'},
    'timestamp'       => int($newJWT->{'timestamp'}),
    'signature'       => $newJWT->{'token'},
    'audience'        => 'api.authvia.com/v3',
    'expiration'      => '15m'
  };

  # for requests by the merchant
  if (ref($options) eq 'HASH') {
    $hash->{'role'} = $options->{'role'};
    if ($hash->{'role'} eq 'merchant') {
      $hash->{'merchantId'} = $options->{'merchantId'};
    }
  } else {
    $hash->{'role'} = 'partner'; 
  }

  my $scopeList = $self->getScopeList();
  if ($scopeList) {
    $hash->{'scope'} = $scopeList;
  }

  my $resp = $self->_doRequest('POST', {'requestData' => $hash, 'endpoint' => 'tokens'});
  if (ref($resp) ne 'HASH'){ 
    fail("invalid response from authvia: $resp");
  }

  $self->{'scope_list'} = '';
  my $time = new PlugNPay::Sys::Time();
  $time->addMinutes(15);
  $resp->{'expirationTime'} = $time->inFormat('unix');

  return $resp;
}

# generates token with role set to merchant, this is required by AuthVia to access certain endpoints.
sub getAuthorizationToken {
  my $self = shift;
  my $merchant = shift;
  if (!defined $merchant) {
    fail("No merchant set for getAuthorizationToken()");
  }

  my $now = new PlugNPay::Sys::Time()->nowInFormat('unix');
  my $merchantLoader = new PlugNPay::Partners::AuthVia::Merchant();
  my $authviaMerchantData = $merchantLoader->load({'gatewayAccount' => $self->getGatewayAccount()});
  my $authviaMerchantId = $authviaMerchantData->{'authViaMerchantId'};
 
  my $tokenData = $self->generateAuthorizationRequest({'role' => 'merchant', 'merchantId' => $authviaMerchantId});

  return $tokenData;
}

#takes in data, sends it thru callback, returns response
sub _doRequest {
  my $self = shift;
  my $method = uc(shift);
  my $data = shift;
  my $responseLink = new PlugNPay::ResponseLink();
  $responseLink->setUsername($self->getGatewayAccount());

  $responseLink->setRequestMethod($method || 'GET');
  $responseLink->setResponseAPIType('JSON');
  if (ref($data->{'headers'}) eq 'HASH') {
    foreach my $key (keys %{$data->{'headers'}}) {
      $responseLink->addRequestHeader($key, $data->{'headers'}{$key});
    }
  }
  my $url = $self->getAuthViaURL();
  $url .= $data->{'endpoint'};
  if (defined $method && $method ne 'GET') {
    $responseLink->setRequestContentType('application/json');
    $responseLink->setRequestData($data->{'requestData'});
  } else {
    if ($data->{'urlDataID'}) {
      $url .= '/' . $data->{'urlDataID'}
    } 

    $responseLink->setRequestData($data->{'requestData'});
  }

  $responseLink->setRequestURL($url);

  $responseLink->setRequestMode('PROXY');
  if ($ENV{'DEVELOPMENT'} eq 'TRUE') {
    $responseLink->setRequestMode('DIRECT');
  }

  $responseLink->doRequest();

  my %response = $responseLink->getResponseAPIData();
  return \%response;
}

sub getScopeList {
  my $self = shift;
  my $list = '';
  if (ref($self->{'scope_list'}) eq 'ARRAY') {
    $list = join(' ', @{$self->{'scope_list'}}); 
  }
  
  return $list;
}

sub log {
  my $self = shift;
  my $logData = shift || {};

  new PlugNPay::Logging::DataLog({'collection' => 'integrations'})->log({'partner' => 'authvia', 'logData' => $logData});
}

1;
