package PlugNPay::API::REST::Responder::Merchant::API::Key;

use strict;
use Switch;
use PlugNPay::GatewayAccount::APIKey;
use PlugNPay::GatewayAccount::LinkedAccounts;

use base "PlugNPay::API::REST::Responder";

sub _getOutputData {
  my $self = shift;
  my $data = {};
  my $action = $self->getAction();

  if (defined $self->getInputData()){
    switch ($action) {
      case 'create' {$data = $self->create()}
      case 'update' {$data = $self->update()}
      case 'delete' {$data = $self->delete()}
      case 'read'   {$data = $self->read()}
      else { 
        $data = {'status' => 'failure','message' => 'Method Not Implemented'};
        $self->setResponseCode(501);
      }
    }
  } else {
    $self->setResponseCode(422);
    return {'status' => 'failure', 'message' => 'No data sent'};
  }

  return $data;
}

sub _update {
  my $self = shift;
  my $account = $self->_accountCheck();
  my $output = {};
  if ($account == 1) {
    my $data = $self->getInputData();
    my $apiKey = new PlugNPay::GatewayAccount::APIKey({'gatewayAccount'=>$account,'keyName'=>$data->{'keyName'}});
    if ($apiKey->getRevision > 0){
      my $expTime = $data->{'oldKeyExpiration'}; #optional
      my $newKey = $apiKey->generate($expTime); #If expTime isn't in seconds then generate defaults to 1 hour
      $self->setResponseCode(200);
      $output = {'keyName' => $data->{'keyName'}, 'key' => $newKey, 'username' => $account, 'status' => 'success'};
    } else {
      $self->setResponseCode(404);
      $output = {'status' => 'failure', 'message' => 'Key does not exist, cannot update. (Use POST instead)'};
    }
  } else {
    $self->setResponseCode(403);
    $output = {'status' => 'failure', 'message' => 'You do not have access to update keys for the username submitted'};
  }
  
  return $output;
}

sub _create {
  my $self = shift;
  my $account = $self->_accountCheck();
  my $output = {};
  if ($account == 1) { 
    my $data = $self->getInputData();
    my $apiKey = new PlugNPay::GatewayAccount::APIKey({'gatewayAccount'=>$account,'keyName'=>$data->{'keyName'}});
    unless (defined $apiKey->getKey() || $apiKey->getRevision() > 0) {
      my $newKey = $apiKey->generate();
      $self->setResponseCode(201);
      $output = {'status' => 'success','keyName' => $data->{'keyName'}, 'key' => $newKey, 'username' => $account};
    } else {
      $self->setResponseCode(409);
      $output = {'status' => 'failure','message'=>'Key already exists, cannot create new key. (Use PUT instead)'};
    }
  } else {
    $self->setResponseCode(403);
    $output = {'status' => 'failure', 'message' => 'You do not have access to create keys for the username submitted'};
  }
  return $output;
}

sub _delete {
  my $self = shift;
  my $account = $self->_accountCheck();
  my $data = $self->getInputData();
  my $output = {};
  if ($account == 1) {
    my $apiKey = new PlugNPay::GatewayAccount::APIKey({'gatewayAccount'=>$account,'keyName'=>$data->{'keyName'}});
    if ($apiKey->getKey() || $apiKey->getRevision > 0) {
      my $revision = $apiKey->getRevision();
      $apiKey->expireKey($data->{'keyName'},$revision);
      $self->setResponseCode(200);
      
      $output = {'status' => 'success','message' => 'Key was invalidated successfully',  'keyName' => $data->{'keyName'}, 'username' => $account};
    } else {
      $self->setResponseCode(404);
      
      $output = {'status' => 'failure', 'message' => 'Invalid key, please check the key name and username and try again!'};
    }
  } else {
    $self->setResponseCode(403);
    $output = {'status' => 'failure', 'message' => 'You do not have access to delete keys for the username submitted'};
  }

  return $output;
}

sub _read {
  my $self = shift;
  my $account = $self->_accountCheck();
  my $key = $self->getResourceData()->{'key'};
  my $output = {};
  if ($account == 1) {
    if (defined $key) {
      my $valid = new PlugNPay::GatewayAccount::APIKey({'gatewayAccount'=>$account})->verifyKey($key);
      if ($valid) {
        $self->setResponseCode(200);
        $output = {'key' => $key, 'isValid' => 'true'};
      } else {
        $self->setResponseCode(404);
        $output = {'key' => $key, 'isValid' => 'false','message' => 'Key not found'};
      }
  
    } else {
      $self->setResponseCode(400); 
      $output = {'message' => 'Bad Request Method', 'status' => 'failure'};
    }
  } else {
    $self->setResponseCode(403);
    $output = {'status' => 'failure', 'message' => 'You do not have access to check keys for the username submitted'};
  }
  
  return $output;
}

sub _accountCheck {
  my $self = shift;
  my $merchantAccount = $self->getResourceData()->{'merchant'};
  my $GatewayAccount = $self->getGatewayAccount();
  
  my $linked = new PlugNPay::GatewayAccount::LinkedAccounts($GatewayAccount);
  my $isLinked = $linked->isLinkedTo($merchantAccount);
  if (defined $merchantAccount) {  # Account was sent
    if ($isLinked) { # Linked Account
      return 1;
    } elsif (lc($GatewayAccount) eq lc($merchantAccount)) { # Is main account
      return 1;
    } else {  # Invalid Account
      return 0;
    }
  } else {  # No Merchant Account sent
    return 0;
  }
}

1;
