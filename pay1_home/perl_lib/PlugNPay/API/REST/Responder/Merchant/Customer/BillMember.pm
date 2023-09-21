package PlugNPay::API::REST::Responder::Merchant::Customer::BillMember;

use strict;
use PlugNPay::Merchant::Customer::BillMember;

use base 'PlugNPay::API::REST::Responder::Abstract::Merchant::Customer';

sub _create {
  my $self = shift;
  my $merchant = $self->getMerchant();
  my $merchantCustomer = $self->getMerchantCustomer();

  my $inputData = $self->getInputData();

  my $biller = new PlugNPay::Merchant::Customer::BillMember();
  my $billStatus = $biller->billCustomer($merchantCustomer->getMerchantCustomerLinkID(),
                                         $inputData->{'paymentSourceIdentifier'}, {
    'amount'              => $inputData->{'amount'},
    'description'         => $inputData->{'description'},
    'transactionType'     => $inputData->{'operation'},
    'billingAccount'      => $merchant
  });

  if (!$billStatus->{'status'}) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => $billStatus->{'status'}->getError() };
  }

  $self->setResponseCode(201);
  return { 'status' => 'success', 'transaction' => $billStatus->{'transactionDetails'} };
}

1;
