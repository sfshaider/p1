## Base class for API Responder objects.
## -------------------------------------
## Pulls out the Schema for the response based on the package name of the responder.

package PlugNPay::API::REST::Responder;

use strict;
use PlugNPay::Logging::DataLog;
use PlugNPay::API::REST::WebHook;
use PlugNPay::API::REST::Format;
use PlugNPay::API::REST::Context;
use PlugNPay::GatewayAccount::InternalID;
use PlugNPay::Merchant::API::Policy;
use PlugNPay::Logging::Performance;
use PlugNPay::Logging::DataLog;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub setAuthenticationType {
  my $self = shift;
  my $authenticationType = shift;
  $self->{'authenticationType'} = $authenticationType;
}

sub getAuthenticationType {
  my $self = shift;
  return $self->{'authenticationType'};
}

sub getSchemaName {
  my $self = shift;
  my $package = ref $self;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT schema_name FROM api_responder WHERE package = ?
  /);

  $sth->execute($package);

  my $schemaName = '';

  my $result = $sth->fetchall_arrayref({});
  if ($result && $result->[0]) {
    $schemaName = $result->[0]{'schema_name'};
  }

  return $schemaName;
}

sub setAction {
  my $self = shift;
  my $action = shift;
  if ($action =~ /^(create|read|update|delete|options)$/) {
    $self->{'action'} = $action;
  }
}

sub getAction {
  my $self = shift;
  return $self->{'action'};
}

sub setResourcePath {
  my $self = shift;
  my $resourcePath = shift;
  $self->{'resourcePath'} = $resourcePath;
}

sub getResourcePath {
  my $self = shift;
  return $self->{'resourcePath'};
}

sub setContext {
  my $self = shift;
  my $context = shift;
  $self->{'context'} = $context;
}

sub getContext {
  my $self = shift;

  if (!$self->{'contextID'} && $self->getContextID()) {
    my $contextObj = new PlugNPay::API::REST::Context();
    $contextObj->setID($self->getContextID());
    $self->{'context'} = $contextObj->getName();
  }

  return $self->{'context'};
}

sub setContextID {
  my $self = shift;
  my $context = shift;
  $self->{'contextID'} = $context;
}

sub getContextID {
  my $self = shift;

  # set context id from context if context id is not defined
  if (!$self->{'contextID'} && $self->getContext()) {
    my $contextObj = new PlugNPay::API::REST::Context();
    $contextObj->setName($self->getContext());
    $self->{'contextID'} = $contextObj->getID();
  }

  my $contextID = $self->{'contextID'};
}

sub setGatewayAccount {
  my $self = shift;
  my $username = shift;
  $self->{'gatewayAccount'} = $username;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

sub setAuthenticatedGatewayAccount {
  my $self = shift;
  my $username = shift;
  $self->{'authenticatedGatewayAccount'} = $username;
}

sub getAuthenticatedGatewayAccount {
  my $self = shift;
  return $self->{'authenticatedGatewayAccount'};
}

sub setAPIKeyName {
  my $self = shift;
  my $keyName = shift;
  $self->{'keyName'} = $keyName;
}

sub getAPIKeyName {
  my $self = shift;
  return $self->{'keyName'};
}

sub setID {
  my $self = shift;
  my $id = shift;
  $self->{'id'} = $id;
}

sub getID {
  my $self = shift;
  return $self->{'id'};
}

sub setResourceOptionsArray {
  my $self = shift;
  my $resourceOptions = shift;
  $self->{'resourceOptionsArray'} = $resourceOptions;
}

sub getResourceOptionsArray {
  my $self = shift;
  return $self->{'resourceOptionsArray'} || {};
}

sub setResourceOptions {
  my $self = shift;
  my $resourceOptions = shift;
  $self->{'resourceOptions'} = $resourceOptions;
}

sub getResourceOptions {
  my $self = shift;
  return $self->{'resourceOptions'} || {};
}

sub setResourceData {
  my $self = shift;
  my $resourceData = shift;
  $self->{'resourceData'} = $resourceData;
}

sub getResourceData {
  my $self = shift;
  return $self->{'resourceData'} || {};
}

sub setResourceDataArray {
  my $self = shift;
  my $resourceData = shift;
  $self->{'resourceDataArray'} = $resourceData;
}

sub getResourceDataArray {
  my $self = shift;
  return $self->{'resourceDataArray'} || {};
}

sub setRequestOptions {
  my $self = shift;
  my $requestOptions = shift;
  $self->{'requestOptions'} = $requestOptions;
}

sub getRequestOptions {
  my $self = shift;
  return $self->{'requestOptions'} || {};
}

sub setInputData {
  my $self = shift;
  my $data = shift;
  $self->{'input'} = $data;
}

sub getInputData {
  my $self = shift;
  return $self->{'input'} || {};
}

sub create {
  my $self = shift;
  $self->_create();
}

sub _create {
  die ('_create not implemented.');
}

sub update {
  my $self = shift;
  $self->_update();
}

sub _update {
  die('_update not implemented.');
}

sub delete {
  my $self = shift;
  $self->_delete();
}

sub _delete {
  die('_delete not implemneted.');
}

sub responseCodeSet {
  my $self = shift;
  return ($self->{'responseCodeSet'} ? 1 : 0);
}

sub setResponseCode {
  my $self = shift;
  my $code = shift;
  $self->{'responseCodeSet'} = 1;
  $self->{'code'} = $code;
}

# Default to 501 (unimplemented) so all responders must implement this or they will not work at all
sub getResponseCode {
  my $self = shift;
  return $self->{'code'} || 501;
}

sub setError {
  my $self = shift;
  my $error = shift;
  $self->{'error'} = $error;
}

sub getError {
  my $self = shift;
  return $self->{'error'};
}

sub setWarning {
  my $self = shift;
  my $warning = shift;
  $self->{'warning'} = $warning;
}

sub getWarning {
  my $self = shift;
  return $self->{'warning'};
}

sub getOutputData {
  my $self = shift;

  if ($ENV{'DEVELOPMENT'} eq 'TRUE') {
    my $logger = new PlugNPay::Logging::DataLog({ collection => 'rest-responder-development'});
    $logger->log($self);
  }

  new PlugNPay::Logging::Performance('Starting call to responder subclass method.');
  my $data = {};
  eval {
    $data = $self->_getOutputData() || {};
  };
  if ($@) {
    $self->log({
      message => 'error while running responder',
      error => $@
    }, {
      stackTraceEnabled => 1
    });
  }
  new PlugNPay::Logging::Performance('Completed call to responder subclass method.');

  my $response = {data => $data};

  my $error = $self->getError();
  my $warning = $self->getWarning();

  $response->{'error'} = $error if $error;
  $response->{'warning'} = $warning if $warning;
  my $format = new PlugNPay::API::REST::Format();
  $format->setSchemaName($self->getSchemaName());
  $format->setSchemaMode('OUTPUT');
  $format->setData($response);

  if (!$self->getSchemaName()) {
    $self->setError('No Schema Defined.');
  } elsif (!$format->validateData()) {
    $self->setError($format->getLogs());
  }

  # check for webhook
  new PlugNPay::Logging::Performance('Check for webhook for hookName "result"');
  my $webhook = new PlugNPay::API::REST::WebHook({responderID => $self->getID(), hookName => 'result'});
  if ($webhook->exists()) {
    new PlugNPay::Logging::Performance('WebHook for hookName "result" exists.');
    my $keyName = $self->getAPIKeyName();
    my $internalIDObj = new PlugNPay::GatewayAccount::InternalID();
    my $customerID = $internalIDObj->getIdFromUsername($self->getAuthenticatedGatewayAccount() || $self->getGatewayAccount());
    new PlugNPay::Logging::Performance('Start call for hookName "result".');
    $webhook->call({contextID => $self->getContextID(), keyName => $keyName, customerID => $customerID, data => $response, responder => $self});
    new PlugNPay::Logging::Performance('End call for hookName "result".');
  } else {
    new PlugNPay::Logging::Performance('WebHook for hookName "result" does not exist.');
  }
  
  return $response;
}

sub _getOutputData {
  die('_getOutputData not implemented.');
}

###########
# Logging #
###########
sub log {
  my $self = shift;
  my $data = shift;
  $data->{'resource'} = $self->getResourcePath();
  my $logger = new PlugNPay::Logging::DataLog({'collection' => 'api_responder'});
  return $logger->log($data);
}

1;
