package PlugNPay::Partners::Cardinal::Settings;

use strict;
use PlugNPay::Die;
use PlugNPay::ResponseLink::Microservice;
use PlugNPay::Logging::DataLog;
use PlugNPay::GatewayAccount::InternalID;
use PlugNPay::GatewayAccount;
use PlugNPay::Util::Status;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $gatewayAccount = shift;
  if ($gatewayAccount) {
    $self->setGatewayAccount($gatewayAccount);
    $self->_loadSettings();

    # Get account status
    my $ga = new PlugNPay::GatewayAccount($self->getGatewayAccount());
    my $accountStatus = $ga->getStatus();

    # Log if staging is enabled on a live account
    if ($accountStatus eq 'live' && $self->getStaging()) {
      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'proc-cardinal' });
      $logger->log({
        'account' => $self->getGatewayAccount(),
        'message' => 'Configuration error: staging cannot be enabled on a live account'
      });
    }
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
  my $gatewayAccount = shift || $self->getGatewayAccount();

  my $iid = new PlugNPay::GatewayAccount::InternalID();
  my $customerId = $iid->getIdFromUsername($gatewayAccount);

  $self->{'customerId'} = $customerId + 0; # make numeric
  return $self->{'customerId'};
}

sub setOrgUnitId {
  my $self = shift;
  my $orgUnitId = shift;
  $self->{'orgUnitId'} = $orgUnitId;
}

sub getOrgUnitId {
  my $self = shift;
  return $self->{'orgUnitId'};
}

sub setProcessorId {
  my $self = shift;
  my $processorId = shift;
  $self->{'processorId'} = $processorId;
}

sub getProcessorId {
  my $self = shift;
  return $self->{'processorId'};
}

sub setMerchantId {
  my $self = shift;
  my $merchantId = shift;
  $self->{'merchantId'} = $merchantId;
}

sub getMerchantId {
  my $self = shift;
  return $self->{'merchantId'};
}

sub setTransactionPassword {
  my $self = shift;
  my $transactionPassword = shift;
  $self->{'transactionPassword'} = $transactionPassword;
}

sub getTransactionPassword {
  my $self = shift;
  return $self->{'transactionPassword'};
}

sub setEnabled {
  my $self = shift;
  my $enabled = shift;
  $self->{'enabled'} = $enabled;
}

sub getEnabled {
  my $self = shift;
  return ($self->{'enabled'} ? 1 : 0);
}

sub setStaging {
  my $self = shift;
  my $staging = shift;
  $self->{'staging'} = $staging;
}

sub getStaging {
  my $self = shift;
  return ($self->{'staging'} ? 1 : 0);
}

sub setDefaultApiKeyId {
  my $self = shift;
  my $defaultApiKeyId = shift;
  $self->{'defaultApiKeyId'} = $defaultApiKeyId;
}

sub getDefaultApiKeyId {
  my $self = shift;
  return $self->{'defaultApiKeyId'};
}

sub _loadSettings {
  my $self = shift;
  my $customerId = $self->getCustomerId();

  if (!defined $customerId) {
    die('missing customer id');
  }

  my $data = {'customerId' => $customerId};
  my $status = $self->_callService('GET', $data);

  if ($status) {
    my $decodedResponse = $status->get('decodedResponse');
    if ($decodedResponse->{'exists'}) {
      $self->setOrgUnitId($decodedResponse->{'orgUnitId'});
      $self->setProcessorId($decodedResponse->{'processorId'});
      $self->setMerchantId($decodedResponse->{'merchantId'});
      $self->setTransactionPassword($decodedResponse->{'transactionPassword'});
      $self->setEnabled($decodedResponse->{'enabled'});
      $self->setStaging($decodedResponse->{'staging'});
      $self->setDefaultApiKeyId($decodedResponse->{'defaultApiKeyId'});
    }
  }
  return $status;
}

sub saveSettings {
  my $self = shift;
  my $data;
  my $customerId = $self->getCustomerId();

  if (!defined $customerId) {
    die('missing customer id');
  }

  $data = {
    'customerId'          => $customerId,
    'orgUnitId'           => $self->getOrgUnitId(),
    'processorId'         => $self->getProcessorId(),
    'merchantId'          => $self->getMerchantId(),
    'transactionPassword' => $self->getTransactionPassword(),
    'enabled'             => $self->getEnabled() ? \1 : \0,
    'staging'             => $self->getStaging() ? \1 : \0,
    'defaultApiKeyId'     => $self->getDefaultApiKeyId()
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
    'customerId' => $customerId
  };
  my $status = $self->_callService('DELETE', $data);

  return $status;
}

sub _callService {
  my $self = shift;
  my $method = shift;
  my $data = shift;

  my $customerId = $data->{'customerId'};
  my $baseUrl = 'http://proc-cardinal.local/v1/customer-settings/';
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
    my $errorMessage = 'Cardinal settings service error: ' . $decodedResponse->{'errorMessage'};
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

sub isApiKeyIdDefault {
  my $self = shift;
  my $apiKeyId = shift;

  my $defaultApiKeyId = $self->getDefaultApiKeyId();

  return $apiKeyId eq $defaultApiKeyId ? 1 : 0;
}

sub customerHasSettings {
  my $self = shift;
  my $hasSettings;
  my $error;

  my $status = $self->_loadSettings();
  if ($status) {
    my $decodedResponse = $status->get('decodedResponse');
    $hasSettings = $decodedResponse->{'exists'} ? 1 : 0;
  } else {
    $error = 1;
  }

  my $result = {
    'hasSettings' => $hasSettings,
    'error'       => $error
  };

  return $result;
}

1;
