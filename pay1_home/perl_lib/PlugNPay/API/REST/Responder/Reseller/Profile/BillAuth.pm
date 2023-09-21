package PlugNPay::API::REST::Responder::Reseller::Profile::BillAuth;

use strict;
use PlugNPay::Email;
use PlugNPay::Contact;
use PlugNPay::CreditCard;
use PlugNPay::OnlineCheck;
use PlugNPay::GatewayAccount;
use PlugNPay::Recurring::PaymentSource;
use PlugNPay::Reseller;

use base "PlugNPay::API::REST::Responder";

sub _getOutputData {
  my $self = shift;
  my $data = {};

  my $action = $self->getAction();
  if ($action eq 'create' || $action eq 'update') {
    $data = $self->_update();
  } elsif ($action eq 'read') {
    $data = $self->_read();
  }

  return $data;
}

sub _update{
  my $self = shift;
  my $username = $self->getGatewayAccount();
  my $data = $self->getInputData();
  my $gatewayAccount = new PlugNPay::GatewayAccount($username);
  my $resellerAccount = new PlugNPay::Reseller($username);
  my $contact = $gatewayAccount->getMainContact();
  my $resellerContact = $resellerAccount->getContactInfo();

  if ( $data->{'tac'} eq 'true'){
    $gatewayAccount->setSSNum($data->{'tax_id'});
    $resellerAccount->setTaxID($data->{'tax_id'});

    $contact->setFullName($data->{'full_name'});
    $gatewayAccount->setMainContact($contact);

    $resellerContact->setFullName($data->{'full_name'});
    $resellerAccount->setContactInfo($resellerContact);


    my $accountType = $data->{'billing_type'};
    if ($accountType eq 'ach') { # for backwards compatibility
      $accountType = 'checking';
    }

    my $paymentSource = new PlugNPay::Recurring::PaymentSource();
    $paymentSource->setPaymentSourceType($accountType);
    if ($accountType eq 'credit'){
      $paymentSource->setCardNumber($data->{'payment_data'}{'card_number'});
      $paymentSource->setExpirationYear($data->{'payment_data'}{'exp_year'});
      $paymentSource->setExpirationMonth($data->{'payment_data'}{'exp_month'});
    } elsif ($accountType eq 'checking' || $accountType eq 'savings') {
      $paymentSource->setRoutingNumber($data->{'payment_data'}{'routing'});
      $paymentSource->setAccountNumber($data->{'payment_data'}{'account'});
      $gatewayAccount->setBank($data->{'payment_data'}{'bank'});
      if ($data->{'payment_data'}{'business_account'} eq 'true') {
        $paymentSource->setIsBusiness();
      } else {
        $paymentSource->setIsNotBusiness();
      }
    }

    my $result = $paymentSource->updatePaymentSource('pnpbilling', $username);
    if ($result->{'status'}) {
      $gatewayAccount->save();
      $resellerAccount->save();
      $self->_notifyByEmail();
      return $self->_read();
    } else {
      $self->setResponseCode('200'); # keeping with the 200/failure for now...
      return { info => { status => 'failure', message => $result->{'errorMessage'} }};
    }
  } else {
    #Returns as a pass but is an error: didn't accept the Terms and Conditions on page.
    #JS handels this error in code, but shouldn't have error response code!
    $self->setResponseCode('200');
    return { info => { status => 'failure', message => 'Terms and conditions not accepted.' }};
  }
}

sub _read {
  my $self = shift;
  my $username = $self->getGatewayAccount();
  my $gatewayAccount = new PlugNPay::GatewayAccount($username);
  my $contact = $gatewayAccount->getMainContact();
  my $data = {};

  $data->{'gatewayAccountName'} = $username;
  $data->{'full_name'} = $contact->getFullName();

  my $paymentSource = new PlugNPay::PaymentSource();
  $paymentSource->loadPaymentSource('pnpbilling', $username);
  my $accountType = $paymentSource->getPaymentSourceType();
  $data->{'billing_info'}{'billing_type'} = ucfirst($accountType);
  if ($accountType eq 'credit') {
    $data->{'billing_info'}{'enccard'} = $paymentSource->getMaskedNumber(4,2,'*',2);
    $data->{'billing_info'}{'exp_date'} = $paymentSource->getExpirationMonth() . '/' . $paymentSource->getExpirationYear();
  } elsif ($accountType eq 'checking' || $accountType eq 'savings') {
    my $accountNumber = $paymentSource->getAccountNumber();
    my $maskLength = length($accountNumber) - 2;
    my $mask = '*' x $maskLength;
    $accountNumber =~ s/^\d{$maskLength}/$mask/;

    my $routingNumber = $paymentSource->getRoutingNumber();

    $data->{'billing_info'}{'routing'} = $routingNumber;
    $data->{'billing_info'}{'account'} = $accountNumber;
    $data->{'billing_info'}{'business_account'} = ($paymentSource->isBusiness() ? 'true' : 'false');
  }

  $data->{'status'} = 'success';
  $self->setResponseCode('200');
  return {'info' => $data};
}

sub _notifyByEmail {
  my $self = shift;
  my $email = new PlugNPay::Email();
  $email->setVersion('legacy');
  $email->setGatewayAccount($self->getGatewayAccount());
  $email->setTo('accounting@plugnpay.com');
  $email->setFrom('billaut@plugnpay.com');
  $email->setSubject('Billing Information Changed - ' . $self->getGatewayAccount());
  $email->setContent('This reseller, ' . $self->getGatewayAccount() . ', changed their billing authorization information.' . "\n");
  $email->setFormat('text');
  $email->send();

  return 1;
}

1;
