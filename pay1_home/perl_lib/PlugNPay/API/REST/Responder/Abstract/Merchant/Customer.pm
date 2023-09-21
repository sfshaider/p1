package PlugNPay::API::REST::Responder::Abstract::Merchant::Customer;

use strict;
use PlugNPay::Merchant::Customer::Link;
use PlugNPay::GatewayAccount::LinkedAccounts;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();

  # check linked account
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  if ($merchant ne $self->getGatewayAccount()) {
    my $linked = new PlugNPay::GatewayAccount::LinkedAccounts($self->getGatewayAccount())->isLinkedTo($merchant);
    if (!$linked) {
      $self->setResponseCode(403);
      return { 'error' => 'Access Denied' };
    }
  }

  # check customer
  my $customer = $self->getResourceData()->{'customer'};
  if (!$customer) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'Invalid customer username.' };
  }

  my $merchantCustomer = new PlugNPay::Merchant::Customer::Link($merchant);
  $merchantCustomer->loadCustomerIDByUsername($customer);
  if (!$merchantCustomer->getMerchantCustomerLinkID()) {
    $self->setResponseCode(404);
    return { 'status' => 'error', 'message' => 'Customer username not found.' };
  }

  $self->{'merchant'} = $merchant;
  $self->{'customer'} = $customer;
  $self->{'merchantCustomer'} = $merchantCustomer;

  if ($action eq 'create') {
    return $self->_create();
  } elsif ($action eq 'read') {
    return $self->_read();
  } elsif ($action eq 'update') {
    return $self->_update();
  } elsif ($action eq 'delete') {
    return $self->_delete();
  } else {
    $self->setResponseCode(501);
    return {};
  }
}

# set fields for derived modules
sub setMerchant {
  my $self = shift;
  my $merchant = shift;
  $self->{'merchant'} = $merchant;
}

sub setCustomer {
  my $self = shift;
  my $customer = shift;
  $self->{'customer'} = $customer;
}

sub setMerchantCustomer {
  my $self = shift;
  my $merchantCustomer = shift;
  $self->{'merchantCustomer'} = $merchantCustomer;
}

# get fields for derived modules
sub getMerchant {
  my $self = shift;
  return $self->{'merchant'};
}

sub getCustomer {
  my $self = shift;
  return $self->{'customer'};
}

sub getMerchantCustomer {
  my $self = shift;
  return $self->{'merchantCustomer'};
}

# not implemented routines.
sub _create {
  my $self = shift;
  # not implemented
  $self->setResponseCode(501);
  return {};
}

sub _read {
  my $self = shift;
  # not implemented
  $self->setResponseCode(501);
  return {};
}

sub _update {
  my $self = shift;
  # not implemented
  $self->setResponseCode(501);
  return {};
}

sub _delete {
  my $self = shift;
  # not implemented
  $self->setResponseCode(501);
  return {};
}

1;
