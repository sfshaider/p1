#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 34;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;

require_ok('PlugNPay::Password::Reset');
autoResetPassword('pnpdemo');

my $result; # used for results of sub calls to test for values

my $gaExistsDoesNotExistMock = sub {
  return 0;
};

my $gaExistsDoesExistMock = sub {
  return 1;
};

# set up mocking for tests
my $mock = Test::MockObject->new();

# Mock PlugNPay::Email subs
my $emailMock = Test::MockModule->new('PlugNPay::Email');

$emailMock->redefine(
'send' => sub {
  return 1;
},
'setGatewayAccount' => sub {
  return;
}
);


# Mock PlugNPay::Username subs
my $unMock = Test::MockModule->new('PlugNPay::Username');

$unMock->redefine(
'getGatewayAccount' => sub {
  return 'pnpdemo';
},
'load' => sub {
  return;
},
'save' => sub {
  return 1;
},
'getSubEmail' => sub {
  return 'noreply@plugnpay.com'
},
'exists' => sub {
  return 1;
});




# Mock PlugNPay::GatewayAccount subs
my $gaMock = Test::MockModule->new('PlugNPay::GatewayAccount');
$gaMock->redefine(
'new' => sub {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
},
'getReseller' => sub {
  return 'devresell'
},
'exists' => $gaExistsDoesExistMock,
'getMainContact' => sub {
  my $contact = new PlugNPay::Contact();
  $contact->setEmailAddress('noreply@plugnpay.com');
  return $contact;
}
);


# Mock PlugNPay::Reseller subs
my $raMock = Test::MockModule->new('PlugNPay::Reseller');
$raMock->redefine(
'getAdminDomain' => sub  {
  return 'test.plugnpay.com'
},
'getSupportEmail' => sub {
  return 'testSupport@plugnpay.com'
}
);


# Mock subs for PlugNPay::Password::Reset
my $selfMock = Test::MockModule->new('PlugNPay::Password::Reset');

my $reset = new PlugNPay::Password::Reset();

# check that correct context is set for merchant or reseller
# if reset context is merchant return merchant
my $merchantReset = new PlugNPay::Password::Reset('merchant');
is($merchantReset->getLoginType(), 'merchant', 'reset context is set as merchant');

# if reset context is reseller return reseller
my $resellerReset = new PlugNPay::Password::Reset('reseller');
is($resellerReset->getLoginType(), 'reseller', 'reset context is set as reseller');



# isLinkExpired()
my $theFuture = new PlugNPay::Sys::Time();
$theFuture->addMinutes(5);
my $futureTime = $theFuture->inFormat('gendatetime');

my $thePast = new PlugNPay::Sys::Time();
$thePast->subtractMinutes(5);
my $pastTime = $thePast->inFormat('gendatetime');

is($reset->isLinkExpired($futureTime), 0, '5 minutes in the future is not expired');
is($reset->isLinkExpired($pastTime), 1, '5 minutes ago is expired');




# sendResetConfirmation()
# set up mocks
$selfMock->redefine(
'getLoginEmailAddresses' => sub {
  return ['noreply@plugnpay.com'];
}
);

$result = $reset->sendResetConfirmation({
  loginUsername => 'pnpdemo',
  emailAddress => 'noreply@plugnpay.com',
  ip => 'localhost'
});

is($result, 1, 'sendResetConfirmation returns 1 for valid loginUsername');

# change unMock behavior to say username does not exist
$unMock->redefine(
'exists' => sub {
  return 0;
}
);

# run sendResetConfirmation again, this time with mocking that the username does not exist
$result = $reset->sendResetConfirmation({
  loginUsername => 'omedpnp',
  emailAddress=> 'noreply@plugnpay.com',
  ip => 'localhost'
});

ok(!$result,'sendResetConfirmation returns 0 for nonexistant loginUsername');

# change unMock behavior to say username does exist again for other tests
$unMock->redefine(
'exists' => sub {
  return 1;
}
);

# unmock
$selfMock->unmock('getLoginEmailAddresses');

# confirmLinkIdAndSetPassword()
# this can not be tested with the current code in an automated fasion as there is no
# way to get the link ID to use to confirm.  Test using lostpass.cgi.

# sendNewPassword()
$result = $reset->sendNewPassword({
  loginUsername => 'pnpdemo',
  emailAddress => 'noreply@plugnpay.com',
  newPassword => 'ABCD1234EFGH5678'
});

is($result,1,'sendNewPassword returns 1 for valid input');

throws_ok(sub {
  $reset->sendNewPassword({
    newPassword => 'ABCD1234EFGH5678',
    emailAddress => 'noreply@plugnpay.com'
  });
}, qr/loginUsername not set/, 'sendNewPassword throws error for loginUsername not set');

throws_ok(sub {
  $reset->sendNewPassword({
    loginUsername => 'pnpdemo',
    emailAddress => 'noreply@plugnpay.com'
  });
}, qr/newPassword not set/, 'sendNewPassword throws error for newPassword not set');

# change unMock behavior to say username does not exist
$unMock->redefine(
'exists' => sub {
  return 0;
}
);

# change unMock behavior to say username does exist again for other tests
$unMock->redefine(
'exists' => sub {
  return 1;
}
);

# _getAdminDomainForLogin() and _getSupportEmailForLogin() and _getNoReplyEmailForLogin()
is($reset->_getAdminDomainForLogin('pnpdemo'),'test.plugnpay.com', 'admindomain for pnpdemo is test.plugnpay.com (mock)');
is($reset->_getSupportEmailForLogin('pnpdemo'),'testSupport@plugnpay.com', 'supportEmail for pnpdemo is testSupport@plugnpay.com (mock)');

# make reseller return 
$raMock->redefine(
'getSupportEmail' => sub {
  return 'support@plugnpay.com';
}
);

# a blank reseller name will return default support email: the support email for reseller plugnpay
is($reset->_getSupportEmailForLogin(''),'support@plugnpay.com', 'support email for blank reseller is support@plugnpay.com');

# check that domain is correct, reseller or pay1 depending on the context
# set up reseller Mock to return empty string
$raMock->redefine(
'getAdminDomain' => sub {
  return '';
});

# if the reseller getAdminDomain returns an empty string use pay1 as default domain
is($merchantReset->_getAdminDomainForLogin('pnpdemo'),'pay1.plugnpay.com', 'admindomain for pnpdemo is pay1.plugnpay.com (mock) if reseller getAdminDomain returns empty string');

# set up reseller Mock to return undef
$raMock->redefine(
'getAdminDomain' => sub {
  return undef;
});

# if the reseller getAdminDomain returns undef use pay1 as default domain
is($merchantReset->_getAdminDomainForLogin('pnpdemo'),'pay1.plugnpay.com', 'admindomain for pnpdemo is pay1.plugnpay.com (mock) if reseller getAdminDomain returns undef');

# if the context is reseller, use reseller domain
is($resellerReset->_getAdminDomainForLogin('pnpdemo'),'reseller.plugnpay.com', 'admindomain for pnpdemo in reseller context is reseller.plugnpay.com (mock)');

# return reseller mock to previous setting
$raMock->redefine(
'getAdminDomain' => sub {
  return 'test.plugnpay.com';
},
'getSupportEmail' => sub {
  return 'testSupport@plugnpay.com'
}
);

# check that a non undef reseller value is returned with a non undef login username 
my ($reseller, $ra) = $reset->_getReseller('pnpdemo');
is($reseller, 'devresell', 'a non undef reseller value is returned with a non undef login username');
is($ra->isa('PlugNPay::Reseller'), 1, 'a non undef reseller value is returned with a reseller module');

# bad gateway account for login
$gaMock->redefine(
'exists' => $gaExistsDoesNotExistMock
);

throws_ok( sub {
  $reset->_getReseller('pnpdemo');
}, qr/invalid gateway account/, 'error thrown on invalid gateway account for login in _getReseller()');

throws_ok( sub {
  $reset->_getAdminDomainForLogin('pnpdemo');
}, qr/invalid gateway account/, 'error thrown on invalid gateway account for login in _getAdminDomainForLogin()');

throws_ok( sub {
  $reset->_getSupportEmailForLogin('pnpdemo');
}, qr/invalid gateway account/, 'error thrown on invalid gateway account for login in _getSupportEmailForLogin()');

# set mock back so gateway account exists
$gaMock->redefine(
'exists' => $gaExistsDoesExistMock
);


# _createConfirmationLinkMessage()
my $confirmationEmailContent = $reset->_createConfirmationLinkMessage({
  confirmationLink => 'https://test.plugnpay.com/lostpass.cgi?link=1234567890'
});

like($confirmationEmailContent, qr/Confirmation URL: https:\/\/test.plugnpay.com\/lostpass.cgi\?link=1234567890/, 'link is populated in confirmation email content');

throws_ok( sub {
  $reset->_createConfirmationLinkMessage({
  });
}, qr/confirmationLink not set/, 'error thrown on call to create error email with missing confirmationLink');

# check that correct greeting is sent for merchant or reseller
# if reset context is merchant greet with Dear Merchant
my $merchantConfirmationEmailContent = $merchantReset->_createConfirmationLinkMessage({
  confirmationLink => 'https://test.plugnpay.com/lostpass.cgi?link=1234567890'
});

is($merchantConfirmationEmailContent =~ /^Dear Merchant/, 1, 'greet with \'Dear Merchant\' under merchant context');

# if reset context is reseller greet with Dear Reseller
my $resellerconfirmationEmailContent = $resellerReset->_createConfirmationLinkMessage({
  confirmationLink => 'https://test.plugnpay.com/lostpass.cgi?link=1234567890'
});

is($resellerconfirmationEmailContent =~ /^Dear Reseller/, 1, 'greet with \'Dear Reseller\' under reseller context');


# _ceateNewPasswordMessage
my $newPasswordEmailContent = $reset->_createNewPasswordMessage({
  adminDomain => 'test.plugnpay.com',
  newPassword => 'ABCD1234EFGH5678'
});

like($newPasswordEmailContent, qr/New Password: ABCD1234EFGH5678/, 'password is populated in confirmation email content');

throws_ok( sub {
  $reset->_createNewPasswordMessage({
    loginUsername => 'pnpdemo',
    newPassword => 'ABCD1234EFGH5678'
  });
}, qr/adminDomain not set/, 'error thrown on call to create password email with missing adminDomain');

throws_ok( sub {
  $reset->_createNewPasswordMessage({
    loginUsername => 'pnpdemo',
    adminDomain => 'test.plugnpay.com'
  });
}, qr/newPassword not set/, 'error thrown on call to create password email with missing newPassword');




# _createErrorMessage()
my $errorEmailContent = $reset->_createErrorMessage({
  loginUsername => 'pnpdemo',
  ip => '10.9.8.7'
});

like($errorEmailContent, qr/Username: "pnpdemo"/, "username populated error email");
like($errorEmailContent, qr/cpwr\.cgi\?username=pnpdemo/, "username populated error email link");
like($errorEmailContent, qr/10\.9\.8\.7/, "ip populated in error email");

throws_ok( sub {
  $reset->_createErrorMessage({
    ip => '10.9.8.7'
  });
}, qr/loginUsername not set/, 'error thrown on call to create error email with missing loginUsername');

throws_ok( sub {
  $reset->_createErrorMessage({
    loginUsername => 'pnpdemo'
  });
}, qr/ip not set/, 'error thrown on call to create error email with missing ip');

sub autoResetPassword {
  my $merchant = shift;

  my $password = new PlugNPay::Password::Reset();
  my $result = $password->autoResetPassword($merchant);
  my $status = $result ? 1 : 0;

  is($status, 1, 'password reset successfully');
}

