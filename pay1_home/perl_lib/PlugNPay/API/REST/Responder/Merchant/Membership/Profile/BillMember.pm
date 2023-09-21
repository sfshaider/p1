package PlugNPay::API::REST::Responder::Merchant::Membership::Profile::BillMember;

use strict;
use PlugNPay::Membership::Profile::BillMember;

use base 'PlugNPay::API::REST::Responder::Abstract::Merchant::Customer';

sub _create {
  my $self = shift;
  my $merchant = $self->getMerchant();
  my $merchantCustomer = $self->getMerchantCustomer();
  my $profileIdentifier = $self->getResourceData()->{'profile'};
  my $inputData = $self->getInputData();

  my $signupFeePayment = 0;
  if ($inputData->{'signupFee'}) {
    $signupFeePayment = 1;
  }

  if ($profileIdentifier) {
    my $billMember = new PlugNPay::Membership::Profile::BillMember();
    my $billStatus = $billMember->billMemberProfile($merchantCustomer->getMerchantCustomerLinkID(), 
                                                    $profileIdentifier, {
      'operation'      => $inputData->{'operation'},
      'amount'         => $inputData->{'amount'},
      'tax'            => $inputData->{'tax'},
      'description'    => $inputData->{'description'},
      'billingAccount' => $merchant,
      'isSignUpFee'    => $signupFeePayment
    }); 

    if ($billStatus->{'status'}) {
      $self->setResponseCode(201);
      return { 'status' => 'success', 'transaction' => $billStatus->{'transactionDetails'} };
    } else {
      $self->setResponseCode(422);
      return { 'status' => 'error', 'message' => $billStatus->{'status'}->getError() };
    }
  } else {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'Missing billing profile identifier' };
  }
}

1;
