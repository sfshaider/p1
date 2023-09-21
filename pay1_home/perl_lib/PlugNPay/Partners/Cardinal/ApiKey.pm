package PlugNPay::Partners::Cardinal::ApiKey;

use strict;
use PlugNPay::Die;
use PlugNPay::ResponseLink::Microservice;
use PlugNPay::Logging::DataLog;
use PlugNPay::GatewayAccount::InternalID;
use PlugNPay::Util::Status;

sub new {
  my $self = {};
  my $class = shift;
  bless $self, $class;

  my $gatewayAccount = shift;
  if ($gatewayAccount) {
    $self->setGatewayAccount($gatewayAccount);
  }

  return $self;
}

sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;
  $self->{'gatewayAccount'} = $gatewayAccount;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

sub getCustomerId {
  my $self = shift;
  my $gatewayAccount = $self->getGatewayAccount();

  my $iid = new PlugNPay::GatewayAccount::InternalID();
  my $customerId = $iid->getIdFromUsername($gatewayAccount);

  $self->{'customerId'} = $customerId + 0; # make numeric
  return $self->{'customerId'};
}

sub setApiKeyName {
  my $self = shift;
  my $apiKeyName = shift;
  $self->{'apiKeyName'} = $apiKeyName;
}

sub getApiKeyName {
  my $self = shift;
  return $self->{'apiKeyName'};
}

sub setApiKey {
  my $self = shift;
  my $apiKey = shift;
  $self->{'apiKey'} = $apiKey;
}

sub getApiKey {
  my $self = shift;
  return $self->{'apiKey'};
}

sub setApiKeyId {
  my $self = shift;
  my $apiKeyId = shift;
  $self->{'apiKeyId'} = $apiKeyId;
}

sub getApiKeyId {
  my $self = shift;
  return $self->{'apiKeyId'};
}

sub getAllApiKeyData {
  my $self = shift;
  my $data;
  my $error = 0;

  my $status = $self->_loadApiKeyData();
  if ($status) {
    my $decodedResponse = $status->get('decodedResponse');
    $data = $decodedResponse->{'apiKeyData'};
  } else {
    $error = 1;
  }

  my $result = {
    'data'  => $data || [],
    'error' => $error
  };

  return $result;
}

sub _loadApiKeyData {
  my $self = shift;
  my $customerId = $self->getCustomerId();

  if (!defined $customerId) {
    die('missing customer id');
  }

  my $data = {'customerId' => $customerId};
  my $status = $self->_callService('GET', $data);

  return $status;
}

sub save {
  my $self = shift;
  my $data;
  my $customerId = $self->getCustomerId();

  if (!defined $customerId) {
    die('missing customer id');
  }

  $data = {
    'customerId' => $customerId,
    'apiKeyName' => $self->getApiKeyName(),
    'apiKey'     => $self->getApiKey(),
    'apiKeyId'   => $self->getApiKeyId()
  };
  my $status = $self->_callService('POST', $data);

  return $status;
}

sub delete {
  my $self = shift;
  my $data;
  my $customerId = $self->getCustomerId();

  if (!defined $customerId) {
    die('missing customer id');
  }

  $data = {
    'customerId' => $customerId,
    'apiKeyId'   => $self->getApiKeyId()
  };
  my $status = $self->_callService('DELETE', $data);

  return $status
}

sub _callService {
  my $self = shift;
  my $method = shift;
  my $data = shift;

  my $customerId = $data->{'customerId'};
  my $baseUrl = 'http://proc-cardinal.local/v1/api-key/';
  my $url = $method eq 'GET' ? $baseUrl . $customerId : $baseUrl;

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($url);
  $ms->setMethod($method);
  $ms->setContent($data);
  $ms->setContentType('application/json');
  my $success = $ms->doRequest();
  my $responseCode = $ms->getResponseCode();
  my $decodedResponse = $ms->getDecodedResponse();

  my $status = new PlugNPay::Util::Status(1);
  if ($success == 0 || $responseCode != 200) {
    my $errorMessage = 'Cardinal api key service error: ' . $decodedResponse->{'errorMessage'};
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'proc-cardinal' });
    $logger->log({
      'account'      => $self->getGatewayAccount(),
      'endpoint'     => $url,
      'message'      => $errorMessage,
      'responseCode' => $responseCode,
      'method'       => $method
    });
    if ($responseCode == 500) {
      $status->setFalse();
      $status->setError('Service returned 500 error');
    }
  }

  if ($status) {
    $status->set('decodedResponse', $decodedResponse);
  }

  return $status;
}

sub hasOnlyOneKey {
  my $self = shift;
  my $hasOnlyOne = 0;

  my $allData = $self->getAllApiKeyData();
  my $apiKeyData = $allData->{'data'};

  if (@{$apiKeyData} eq 1) {
    $hasOnlyOne = 1;
  }

  return $hasOnlyOne;
}

1;