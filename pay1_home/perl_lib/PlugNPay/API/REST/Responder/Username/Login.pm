package PlugNPay::API::REST::Responder::Username::Login;

use strict;
use PlugNPay::Username;
use PlugNPay::Logging::DataLog;

use base "PlugNPay::API::REST::Responder::Abstract::Username";

# Currently for sublogins only
sub _create {
  my $self = shift;
  my $username = $self->getResourceData()->{'username'};
  my $loginDetails = $self->getInputData();

  #Validate password
  my $password = $loginDetails->{'password'};
  my $passwordConf = $loginDetails->{'passwordConfirm'};
  $password =~ s/[^a-zA-Z0-9\+\-\.\*\@\$]//g;

  #Filter security level, default to 14
  my $secLevel = $loginDetails->{'securityLevel'};
  $secLevel =~ s/[^\d]//g;
  $secLevel = 14 if $secLevel !~ /^\d+$/;
  
  my $directories = $loginDetails->{'canAccess'};
  my $hasDirectories = ref($directories) eq 'ARRAY' && @{$directories} > 0;
  my $makeTemporary = $loginDetails->{'requirePasswordChange'} || 1;

  my $response = { 
    'login'         => $username,
    'securityLevel' => $secLevel,
    'temporaryFlag' => $makeTemporary,
    'directories'   => ($hasDirectories ? $directories : ['NA'])
  };

  if (PlugNPay::Username::exists($username) || $password ne $passwordConf) {
    $response->{'status'} = 'error';
    $response->{'message'} = 'Cannot create new login: ' . $username;
    $self->setResponseCode(409);
  } else {
    my $securityObject = new PlugNPay::Username($username);
    $securityObject->setSecurityLevel($secLevel);

    #Need to be careful when associating a GA
    my $gatewayAccount = $loginDetails->{'gatewayAccount'};
    if (PlugNPay::GatewayAccount::exists($gatewayAccount) && $self->validateCredentials($gatewayAccount)) {
      $securityObject->setGatewayAccount($gatewayAccount); #Function exists in abstract package
    } else {
      $securityObject->setGatewayAccount($self->getGatewayAccount());
    }

    
    #The following are not required, but can be passed in.
    my $email = $loginDetails->{'email'};
    my $validEmail = $email =~ /^[A-Za-z0-9\+\.\-\$\*\/=]+\@[A-Za-z0-9]+\.([A-Za-z0-9]+\.?)+$/;
    if ($validEmail) {
      $securityObject->setSubEmail($email);
      $response->{'subEmail'} = $email;
    }

    if ($hasDirectories) {
      foreach my $dir (@{$hasDirectories}) {
        $dir =~ s/[^a-zA-Z0-9\/_-]//g;
        if ($dir ne '') {
          $securityObject->addAccess($dir);
        }
      }
    }

    #setPassword done last because it calls save.
    $securityObject->setTemporaryPasswordFlag($makeTemporary);
    my $saved = 0;
    eval {
      $saved = $securityObject->setPassword($password);
    };

    if ($saved) {
      $self->setResponseCode(201);
      $response->{'message'} = 'Successfully created login';
      $response->{'status'} = 'success';
    } else {
      my $code = ($@ ? 520 : 409);
      my $status = ($@ ? 'error' : 'failure');
      $self->setResponseCode($code);
      $response->{'status'} = $status;
      $response->{'message'} = 'Failed to create login';
      $self->log({
        'method'     => 'create',
        'login'      => $username,
        'statusCode' => $code,
        'error'      => $@ || 'Failed to save in setPassword',
        'requestor'  => $self->getGatewayAccount(),
        'responder'  => 'PlugNPay::Username::Login'
      });
    }
  }

  return $response;
}

sub _read {
  my $self = shift;
  my $usernameToLoad = $self->getResourceData()->{'username'};
  my $response;
  if (!PlugNPay::Username::exists($usernameToLoad)) {
    $self->setResponseCode(404);
    $response = {
      'status'  => 'failure',
      'message' => 'Could not find login information',
      'login'   => $usernameToLoad
    };
  } else {
    $self->setResponseCode(200);
    my $username = new PlugNPay::Username($usernameToLoad);
    $response = {
      'status'        => 'success',
      'message'       => 'Successfully loaded login information',
      'login'         => $usernameToLoad,
      'directories'   => $username->getAccess(),
      'securityLevel' => $username->getSecurityLevel(),
      'subAccount'    => $username->getSubAccount() || '',
      'tempFlag'      => ($username->getTemporaryPasswordFlag() ? 'true' : 'false'),
      'subEmail'      => $username->getSubEmail() || ''
    };
  }

  return $response;
}

sub _update {
  my $self = shift;
  my $usernameToUpdate = $self->getResourceData()->{'username'};
  my $response;
  if (!PlugNPay::Username::exists($usernameToUpdate)) {
    $self->setResponseCode(404);
    $response = { 
      'status'  => 'failure',
      'message' => 'Could not find login information',
      'login'   => $usernameToUpdate
    };
  } else {
    my $username = new PlugNPay::Username($usernameToUpdate);
    my $loginDetails = $self->getInputData();

    if (defined $loginDetails->{'securityLevel'}) {
      #Filter security level, default to 14
      my $secLevel = $loginDetails->{'securityLevel'};
      $secLevel =~ s/[^\d]//g;
      $username->setSecurityLevel($secLevel) if $secLevel ne '';
    }
    
    #Validate password
    my $saved = 0;
    if (defined $loginDetails->{'password'}) {
      my $password = $loginDetails->{'password'};
      my $passwordConf = $loginDetails->{'passwordConfirm'};
      $password =~ s/[^a-zA-Z0-9\+\-\.\*\@\$]//g;
      my $validPassword = $password ne '' && $password eq $passwordConf;
      eval {
        $saved = $username->setPassword($password) if $validPassword;
      };
    } else {
      eval {
        $saved = $username->saveUsername();
      };
    }


    if ($@) {
      $response = {
        'status'  => 'error',
        'message' => 'Failed to update login information',
        'login'   => $usernameToUpdate
      };

      $self->log({
        'method'     => 'update',
        'login'      => $usernameToUpdate,
        'statusCode' => 520,
        'error'      => $@,
        'requestor'  => $self->getGatewayAccount(),
        'responder'  => 'PlugNPay::Username::Login'
      });

      $self->setResponseCode(520);
    } else {
      $response = $self->_read();
      $response->{'message'} = 'Successfully update login information';
      $self->setResponseCode(200);
    }
  }

  return $response
}

sub _delete {
  my $self = shift;
  my $usernameToDelete = $self->getResourceData()->{'username'};
  my $parentAccount = new PlugNPay::Username($self->getGatewayAccount());
  my $response;
  if ($parentAccount->getSecurityLevel() eq '0' && PlugNPay::Username::exists($usernameToDelete)) {
    my $username = new PlugNPay::Username($usernameToDelete);
    eval{
      $username->deleteUsername($usernameToDelete);
    };

    if ($@) {
      $self->setResponseCode(520); 
      $response = {
        'status'  => 'error',
        'message' => 'failed to delete login',
        'login'   => $usernameToDelete
      };

      $self->log({
        'method'     => 'delete',
        'login'      => $usernameToDelete,
        'statusCode' => 520,
        'error'      => $@,
        'requestor'  => $self->getGatewayAccount(),
        'responder'  => 'PlugNPay::Username::Login'
      });
    } else {
      $self->setResponseCode(200);
      $response = {
        'status'  => 'success',
        'message' => 'Deleted login successfully',
        'login'   => $usernameToDelete
      };
    }
  } else {
    my $code = (PlugNPay::Username::exists($usernameToDelete) ? 403 : 404);
    $self->setResponseCode($code);
    $response = {
      'status'  => 'error',
      'message' => 'Unable to delete login',
      'login'   => $usernameToDelete
    };

    $self->log({
      'method'            => 'delete',
      'login'             => $usernameToDelete,
      'statusCode'        => $code,
      'error'             => 'Account attempted to delete login', 
      'requestorSecLevel' =>  $parentAccount->getSecurityLevel(),
      'requestor'         => $self->getGatewayAccount(),
      'responder'         => 'PlugNPay::Username::Login'
    });
  }

  return $response;
}

sub log {
  my $self = shift;
  my $data = shift;
  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'username' });
  $logger->log($data);
}

1;
