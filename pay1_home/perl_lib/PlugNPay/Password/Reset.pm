package PlugNPay::Password::Reset;

use strict;
use PlugNPay::Email;
use PlugNPay::Username;
use PlugNPay::Sys::Time;
use PlugNPay::Util::RandomString;
use PlugNPay::Die;
use PlugNPay::Util::Array;
use PlugNPay::Authentication::Login;
use PlugNPay::GatewayAccount;
use PlugNPay::Util::Status;

sub new {
  my $self = {};
  my $class = shift;
  bless $self, $class;

  # set login context, reseller or merchant from admin login page
  my $loginType = shift;
  if($loginType) {
    $self->setLoginType($loginType);
  }

  return $self;
}

sub getLoginType {
  my $self = shift;
  return $self->{'loginType'};
}

sub setLoginType {
  my $self = shift;
  my $loginType = shift;
  $self->{'loginType'} = $loginType;
}

sub sendResetConfirmation {
  my $self = shift;
  my $input = shift;

  my $loginUsername = $input->{'loginUsername'};
  die('loginUsername not set') if !defined $loginUsername || $loginUsername eq '';

  my $ip = $input->{'ip'};
  die('ip not set') if !defined $ip || $ip eq '';

  my $inputEmailAddress = $input->{'emailAddress'};
  die('emailAddress not set') if !defined $inputEmailAddress || $inputEmailAddress eq '';

  # override is optional
  my $override = $input->{'override'} || '';

  my $login = new PlugNPay::Authentication::Login({
    login => $loginUsername
  });
  $login->setRealm('PNPADMINID'); # needs realm set but the call to create link works regardless of realm

  my $loginInfo = $login->getLoginInfo();

  if ($loginInfo) {
    my $gatewayAccount = $loginInfo->get('loginInfo')->{'account'};
    my $loginEmails = $self->getLoginEmailAddresses($loginUsername);

    if (!inArray($inputEmailAddress, $loginEmails)) {
      die_metadata(['can not find email address for loginUsername'],{
        loginUsername => $loginUsername
      });
    }

    my $adminDomain = $self->_getAdminDomainForLogin($loginUsername);
    my $supportEmail = $self->_getSupportEmailForLogin($loginUsername);

    my $resetIDCreateStatus = $login->createPasswordResetID({
      emailAddress => $inputEmailAddress
    });

    if (!$resetIDCreateStatus) {
      die_metadata(["failed to create resetID for login"],{
        loginUsername => $loginUsername
      });
    }

    my $resetID = $resetIDCreateStatus->get('resetID');

    my $link = sprintf("https://%s/lostpass.cgi?function=confirm&id=%s",$adminDomain,$resetID);

    my $message = $self->_createConfirmationLinkMessage({
      confirmationLink => $link
    });

    my $emailObject = new PlugNPay::Email();
    $emailObject->setGatewayAccount($gatewayAccount);
    $emailObject->setVersion('legacy');
    $emailObject->addTo($inputEmailAddress);
    $emailObject->setFrom($supportEmail);
    $emailObject->setSubject('Reset Password Notification');
    $emailObject->setContent($message);
    $emailObject->setFormat('text');
    $emailObject->send();

    return 1;
  } else {
    my $message = $self->_createErrorMessage({
      loginUsername => $loginUsername,
      ip => $ip
    });

    my $emailObject = new PlugNPay::Email();
    $emailObject->setGatewayAccount('');
    $emailObject->setVersion('legacy');
    $emailObject->addTo('lostpass-warning@plugnpay.com');
    $emailObject->setFrom('support@plugnpay.com');
    $emailObject->setSubject('Password Recovery Failure - ' . $loginUsername);
    $emailObject->setContent($message);
    $emailObject->setFormat('text');
    $emailObject->send();

    return 0;
  }
}

# The ultimate function
sub confirmLinkIdAndSendNewPassword {
  my $self = shift;
  my $input = shift;
  my $result = $self->confirmLinkIdAndSetPassword($input);
  if (!$result->{'success'}) {
    return $result;
  }

  my $sendStatus = $self->sendNewPassword($result);

  return {
    'success' => $result->{'success'},
    'emailStatus' => $sendStatus
  };
}

sub confirmLinkIdAndSetPassword {
  my $self = shift;
  my $input = shift;

  my $confirmationId = $input->{'confirmationId'};
  die('confirmationId not set') if !defined $confirmationId || $confirmationId eq '';

  my $ip = $input->{'ip'};
  die('ip not set') if !defined $ip || $ip eq '';

  my $confirmationInfo = $self->getLinkInfo({
   'resetID' => $confirmationId
  });
  if (!defined $confirmationInfo || $confirmationInfo->{'expired'}) {
    return {
      success => 0
    };
  }

  return {
    success => 1,
    loginUsername => $confirmationInfo->{'login'},
    newPassword => $confirmationInfo->{'password'},
    emailAddress => $confirmationInfo->{'emailAddress'}
  };
}

sub sendNewPassword {
  my $self = shift;
  my $input = shift;

  my $loginUsername = $input->{'loginUsername'};
  die('loginUsername not set') if !defined $loginUsername || $loginUsername eq '';

  my $newPassword = $input->{'newPassword'};
  die('newPassword not set') if !defined $newPassword || $newPassword eq '';

  my $inputEmailAddress = $input->{'emailAddress'};
  die('emailAddress not set') if !defined $inputEmailAddress || $inputEmailAddress eq '';

  my $loginEmails = $self->getLoginEmailAddresses($loginUsername);

  if (!inArray($inputEmailAddress, $loginEmails)) {
    die_metadata(['can not find email address for loginUsername'],{
      loginUsername => $loginUsername
    });
  }

  # get gateway account for loginUsername
  my $login = new PlugNPay::Authentication::Login({
    login => $loginUsername
  });
  $login->setRealm('PNPADMINID'); # needs realm set but the call to create link works regardless of realm

  my $loginInfo = $login->getLoginInfo();

  if (!$loginInfo) {
    die_metadata(['loginUsername does not exist'],{
      loginUsername => $loginUsername
    });
  }

  my $gatewayAccount = $loginInfo->get('loginInfo')->{'account'};

  # get reseller for gateway account
  my $ga = new PlugNPay::GatewayAccount($gatewayAccount);
  if (!$ga->exists()) {
    die_metadata(['gatewayAccount for loginUsername does not exist'],{
      loginUsername => $loginUsername,
      gatewayAccount => $gatewayAccount
    });
  }

  my $reseller = $ga->getReseller();

  # get support email and admin domain for reseller
  my $ra = new PlugNPay::Reseller($reseller);
  my $supportEmail = $ra->getSupportEmail();
  my $adminDomain = $ra->getAdminDomain();

  my $emailObj = new PlugNPay::Email();
  $emailObj->setGatewayAccount($gatewayAccount);

  my $message = $self->_createNewPasswordMessage({
    adminDomain => $adminDomain,
    newPassword => $newPassword
  });

  $emailObj->setTo($inputEmailAddress);
  $emailObj->setFrom($supportEmail);
  $emailObj->setVersion('legacy');
  $emailObj->setSubject("Subject: Password Change Confirmation");
  $emailObj->setContent($message);
  $emailObj->setFormat('text');
  my $status = $emailObj->send();

  return $status;
}

sub getLoginEmailAddresses {
  my $self = shift;
  my $loginUsername = shift;

  my $un = new PlugNPay::Username($loginUsername);

  my @loginEmails;

  # if the login is the primary login for the account, pull the email address from the gateway account object
  # otherwise pull from subEmail function in username object
  if ($un->isMainLogin()) {
    my $ga = new PlugNPay::GatewayAccount($loginUsername);
    my $contactEmail = $ga->getMainContact()->getEmailAddress();
    push @loginEmails, lc $contactEmail;
  }

  my $loginEmail = $un->getSubEmail();
  if (defined $loginEmail && $loginEmail ne '') {
    push @loginEmails, lc $loginEmail;
  }

  return \@loginEmails;
}



sub getLinkInfo {
  my $self = shift;
  my $input = shift;

  my $loginUsername = $input->{'loginUsername'};
  my $resetID = $input->{'resetID'} || $input->{'confirmationId'};

  die('loginUsername, resetID, or confirmationId is required') if (
    (!defined $loginUsername || $loginUsername eq '')
    &&
    (!defined $resetID || $resetID eq '')
  );

  my $login = new PlugNPay::Authentication::Login();
  $login->setRealm('PNPADMINID'); # needs realm set but the call to create link works regardless of realm

  my $resetIDUseStatus = $login->usePasswordResetID({
    resetID => $resetID
  });

  if (!$resetIDUseStatus) {
    die_metadata(["failed to use/load data for resetID"],{
      $resetID => $resetID
    });
  }
  return {
    login => $resetIDUseStatus->get('login'),
    password => $resetIDUseStatus->get('password'),
    emailAddress => $resetIDUseStatus->get('emailAddress'),
    expired => $resetIDUseStatus->get('expired')
  };
}

sub isLinkExpired {
  my $self = shift;
  my $expiration = shift;

  my $now = new PlugNPay::Sys::Time()->inFormat('gendatetime');

  return ($expiration > $now) ? 0 : 1;
}

sub _getReseller {
  my $self = shift;
  my $loginUsername = shift;

  my $login = new PlugNPay::Username($loginUsername);
  my $gatewayAccount = $login->getGatewayAccount();
  my $ga = new PlugNPay::GatewayAccount($gatewayAccount);
  if (!$ga->exists()) {
    die_metadata(['invalid gateway account for loginUsername'],{
      loginUsername => $loginUsername
    });
  }

  my $reseller = $ga->getReseller();
  my $ra = new PlugNPay::Reseller($reseller);

  return ($reseller, $ra);
}

sub _getAdminDomainForLogin {
  my $self = shift;
  my $loginUsername = shift;

  my ($resellerAccount, $resellerObj) = $self->_getReseller($loginUsername);

  # if forgot password link was used in reseller context use reseller as domain otherwise pay1
  my $adminDomain;
  if ($self->getLoginType() eq 'reseller') {
    $adminDomain = 'reseller.plugnpay.com';
  } else {
    # $adminDomain = $ra->getAdminDomain() || 'pay1.plugnpay.com';
    $adminDomain = $resellerObj->getAdminDomain() || 'pay1.plugnpay.com';
  }

  return $adminDomain;
}

sub _getSupportEmailForLogin {
  my $self = shift;
  my $loginUsername = shift;

  my ($resellerAccount, $resellerObj) = $self->_getReseller($loginUsername);

  if (!$resellerAccount) {
    $resellerObj->loadEmailData($resellerAccount);
  }

  my $supportEmail = $resellerObj->getSupportEmail();

  return $supportEmail;
}

sub _createNewPasswordMessage {
  my $self = shift;
  my $input = shift;

  my $newPassword = $input->{'newPassword'};
  die('newPassword not set') if !defined $newPassword || $newPassword eq '';

  my $admindomain = $input->{'adminDomain'};
  die('adminDomain not set') if !defined $admindomain || $admindomain eq '';

  my $message = <<"END_MESSAGE";
Dear Merchant,

Your request to change your password has been confirmed. Your
new temporary password is below.

New Password: $newPassword

To log in with your new password, go to the following url:  https://$admindomain/admin/
END_MESSAGE

  return $message;
}

sub _createConfirmationLinkMessage {
  my $self = shift;
  my $input = shift;

  my $link = $input->{'confirmationLink'};
  die('confirmationLink not set') if !defined $link || $link eq '';

  my $context;
  if ($self->getLoginType() eq 'reseller') {
    $context = 'Reseller';
  } else {
    $context = 'Merchant';
  }

  my $message = <<"END_MESSAGE";
Dear $context,
A request to change your password has been made, please confirm this
by following this link below.


Note: This link will expire in 3 hours.

Confirmation URL: $link
END_MESSAGE
  return $message;
}

sub _createErrorMessage {
  my $self = shift;
  my $input = shift;

  my $loginUsername = $input->{'loginUsername'};
  die('loginUsername not set') if !defined $loginUsername || $loginUsername eq '';

  my $ip = $input->{'ip'};
  die('ip not set') if !defined $ip || $ip eq '';

  my $message = <<"END_MESSAGE";
Note: adminsitration privileges are not granted for this username

Username: "$loginUsername"
Remote Addr: "$ip"
View at: https://pay1.plugnpay.com/private/cpwr.cgi?username=$loginUsername
END_MESSAGE

  return $message;
}

sub getAutoResetPasswordEmail {
  my $self = shift;
  my $merchant = shift;

  my $loginClient = new PlugNPay::Authentication::Login({login => $merchant});
  $loginClient->setRealm('PNPADMINID');

  my $emailAddress = '';
  my $infoResult = $loginClient->getLoginInfo();
  if ($infoResult) {
    my $loginInfo = $infoResult->get('loginInfo');
    if ($loginInfo->{'account'} eq $loginInfo->{'login'}) {
      my $ga = new PlugNPay::GatewayAccount($loginInfo->{'login'});
      my $mainContact = $ga->getMainContact();
      $emailAddress = $mainContact->getEmailAddress();
    } else {
      $emailAddress = $loginInfo->{'emailAddress'} || '';
    }
  }

  return $emailAddress;
}

sub autoResetPassword {
  my $self = shift;
  my $merchant = shift;

  my $loginClient = new PlugNPay::Authentication::Login({login => $merchant});
  $loginClient->setRealm('PNPADMINID');

  my $emailAddress = $self->getAutoResetPasswordEmail($merchant);

  my $result;
  if ($emailAddress eq '') {
    $result = new PlugNPay::Util::Status(0);
    $result->setError('No email address on file for login');
  } else {
    $result = $loginClient->autoResetPassword($emailAddress);
  }

  return $result;
}



1;
