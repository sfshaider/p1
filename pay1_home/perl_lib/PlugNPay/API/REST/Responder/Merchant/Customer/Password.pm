package PlugNPay::API::REST::Responder::Merchant::Customer::Password;

use strict;
use PlugNPay::Email;
use PlugNPay::GatewayAccount;
use PlugNPay::Merchant::Customer;
use PlugNPay::Merchant::Customer::Password;

use base 'PlugNPay::API::REST::Responder::Abstract::Merchant::Customer';

sub _create {
  my $self = shift;
  my $merchant = $self->getMerchant();
  my $merchantCustomer = $self->getMerchantCustomer();

  my $customer = new PlugNPay::Merchant::Customer();
  $customer->loadCustomer($merchantCustomer->getCustomerID());

  my $username = $merchantCustomer->getUsername();
  my $email = $customer->getEmail();

  if (!$email || $email =~ /\@plugnpay\.pnp$/) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'Unable to send password reset email. Please use valid email address.' };
  }

  my $passwordReset = new PlugNPay::Merchant::Customer::Password();
  my $generated = $passwordReset->generatePasswordLink($merchant, $username);
  if (!$generated->{'status'}) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $generated->{'status'}->getError() };
  }

  my $resetPasswordLink = $generated->{'link'};

  my $gatewayAccount = new PlugNPay::GatewayAccount($merchant);

  my $resetEmail = new PlugNPay::Email();
  $resetEmail->setGatewayAccount($merchant);
  $resetEmail->setFormat('html');
  $resetEmail->setTo($customer->getEmail());
  $resetEmail->setFrom($gatewayAccount->getMainContact()->getEmailAddress());
  $resetEmail->setVersion('legacy');
  $resetEmail->setSubject('Reset Password');
  $resetEmail->setContent("<p>Click the link below to reset your password.<p><a href=\"$resetPasswordLink\">LINK</a>");
  $resetEmail->send();

  $self->setResponseCode(201);
  return { 'status' => 'success', 'message' => 'Password reset email sent.' };
}

1;
