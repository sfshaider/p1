package PlugNPay::API::REST::Responder::Merchant::Recurring::PaymentSource;

use strict;
use PlugNPay::Recurring::Attendant;
use PlugNPay::Recurring::PaymentSource;
use PlugNPay::Token;
use PlugNPay::CreditCard;
use PlugNPay::Logging::DataLog;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();
  my $resourceData = $self->getResourceData();

  my $merchant = $resourceData->{'merchant'} || $self->getGatewayAccount();

  if(!$merchant || !$resourceData->{'customer'}) {
    $self->setResponseCode(422);
    return {'status' => 'failure', 'message' => 'Insufficient Data sent in request.'};
  }

  my $attendant = new PlugNPay::Recurring::Attendant();

  if(!$attendant->doesCustomerExist($merchant,$resourceData->{'customer'})) {
    $self->setResponseCode(404);
    return {'status' => 'failure', 'message' => 'Customer does not exist.'};
  }

  if ($action eq 'read') {
    return $self->_read();
  } elsif ($action eq 'update' || $action eq 'create') {
    return $self->_update();
  } elsif ($action eq 'delete') {
    return $self->_delete();
  }

  $self->setResponseCode(501);
  return {};
}

sub _read {
  my $self = shift;

  my $resourceData = $self->getResourceData();
  my $merchant = $resourceData->{'merchant'} || $self->getGatewayAccount();
  my $logger = new PlugNPay::Logging::DataLog({ collection => 'responder_merchant_recurring_paymentsource' });

  my %logdata = ( method => 'GET', merchant => $merchant, %{$resourceData} );
  $logger->log(\%logdata);

  my $paymentSource = new PlugNPay::Recurring::PaymentSource();
  my $suppressAlert = 1;
  if ($paymentSource->loadPaymentSource($merchant, $resourceData->{'customer'}, $suppressAlert)) {
    if ((grep { $paymentSource->getPaymentSourceType() eq $_ } ('credit','checking','savings')) > 0) {
      my $paymentSourceData = {
        maskedNumber => $paymentSource->getMaskedNumber(),
        expMonth     => $paymentSource->getExpMonth(),
        expYear      => $paymentSource->getExpYear(),
        type         => $paymentSource->getPaymentSourceType(),
        token        => $paymentSource->getToken()
      };

      $self->setResponseCode(200);
      return {'status' => 'success', 'paymentsource' => [$paymentSourceData]};
    }

    $self->setResponseCode(404);
    return {'status' => 'error', 'message' => 'Customer profile has no payment source.'};
  }

  $self->setResponseCode(422);
  return {'status' => 'failure', 'message' => 'Failed to load customer payment source.'};
}

sub _update {
  my $self = shift;
  my $resourceData = $self->getResourceData();
  my $inputData = $self->getInputData();
  my $merchant = $resourceData->{'merchant'} || $self->getGatewayAccount();
  my $customer = $resourceData->{'customer'};
  my $logger = new PlugNPay::Logging::DataLog({ collection => 'responder_merchant_recurring_paymentsource' });

  my %logdata = ( method => 'CREATE_OR_UPDATE', merchant => $merchant, %{$resourceData} );
  $logger->log(\%logdata);

  my $paymentSource = new PlugNPay::Recurring::PaymentSource();

  my $tokenServer = new PlugNPay::Token();

  if ($inputData->{'type'} =~ /card/i) {
    my $cardNumber = $inputData->{'cardNumber'};
    $cardNumber =~ s/[^\d]//g;
    my $token = $inputData->{'token'};

    my $cardNumberValid = &PlugNPay::CreditCard::verifyLuhn10($cardNumber);

    if (length($cardNumber) < 15 || !$cardNumberValid) {
      if ($token ne "") {                                                       # If we received a token...
        my $tokenCardNumber = $tokenServer->fromToken($token);
        my $tokenCardNumberValid = &PlugNPay::CreditCard::verifyLuhn10($tokenCardNumber);

        if ($tokenCardNumberValid) {                                            # ...and it redeems to a valid card number
          $cardNumber = $tokenCardNumber;                                       # ...set the card number to the value from the token
        } else {                                                                #            OTHERWISE
          $self->setResponseCode(422);                                          # Something is wrong...
          if ($tokenCardNumber eq "") {                                         # If the card number is blank...
            return({ 'status' => 'failure', 'message' => {'Invalid token.'}});  # ...then the token was invalid...
          } else {                                                              # ...or the token returned a bad card number
            return({ 'status' => 'failure', 'message' => {'Card number for token does not pass luhn10 check.'}});
          }
        }
      } else {                                                                  # If you made it here there was no token and the card number did not pass luhn10
        $self->setResponseCode(422);
        return({ 'status' => 'failure', 'message' => {'Card number did not pass luhn10 check.'}});
      }
    }

    $paymentSource->setPaymentSourceType($inputData->{'type'});
    $paymentSource->setCardNumber($cardNumber);
    $paymentSource->setExpMonth($inputData->{'expMonth'});
    $paymentSource->setExpYear($inputData->{'expYear'});
  } elsif ($inputData->{'type'} =~ /ach/i) {
    my $routingNumber = $inputData->{'routingNumber'};
    my $accountNumber = $inputData->{'accountNumber'};
    my $token         = $inputData->{'token'};

    if ($token ne "") {
      my $tokenACHData = $tokenServer->fromToken($token);
      if ($tokenACHData =~ /^\d{9} \d+$/) {
        my ($tokenACHRoutingNumber, $tokenACHAccountNumber) = split(' ', $tokenACHData);
        $routingNumber = $tokenACHRoutingNumber;
        $accountNumber = $tokenACHAccountNumber;
      } else {
        $self->setResponseCode(422);
        if ($tokenACHData eq "") {
          return({ 'status' => 'failure', 'message' => {'Invalid token.'}});  # ...then the token was invalid...
        } else {
          return({ 'status' => 'failure', 'message' => {'ACH data for token is invalid.'}});
        }
      }
    }

    $paymentSource->setAccountNumber($accountNumber);
    $paymentSource->setRoutingNumber($routingNumber);
    $paymentSource->setPaymentSourceType($inputData->{'accountType'});
  } else {
    $self->setResponseCode(422);
    return { 'status' => 'failure', 'message' => 'Failed to update payment source. Invalid payment type.' }
  }

  my $suppressAlert = 1;
  my $updateStatus = $paymentSource->updatePaymentSource($merchant, $customer, $suppressAlert);
  if ($updateStatus->{'status'}) {
    $self->setResponseCode(200);
    return { 'status' => 'success', 'message' => 'Successfully updated payment source information' };
  }

  $self->setResponseCode(422);
  return { 'status' => 'failure', 'message' => $updateStatus->{'errorMessage'} };
}

sub _delete {
  my $self = shift;
  my $resourceData = $self->getResourceData();
  my $merchant = $resourceData->{'merchant'} || $self->getGatewayAccount();
  my $paymentSource = new PlugNPay::Recurring::PaymentSource();
  my $logger = new PlugNPay::Logging::DataLog({ collection => 'responder_merchant_recurring_paymentsource' });

  my %logdata = ( method => 'DELETE', merchant => $merchant, %{$resourceData} );
  $logger->log(\%logdata);

  if ($paymentSource->deletePaymentSource($merchant, $resourceData->{'customer'})) {
    $self->setResponseCode(200);
    return {'status' => 'success', 'message' => 'Successfully removed customer payment source.'};
  }

  $self->setResponseCode(422);
  return {'status' => 'failure', 'message' => 'Failed to delete customer payment source.'};

}

1;
