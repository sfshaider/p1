package PlugNPay::API::REST::Responder::Merchant::Order::Transaction::StoreData;
use strict;
use PlugNPay::Contact;
use PlugNPay::Sys::Time;
use PlugNPay::CreditCard;
use PlugNPay::OnlineCheck;
use PlugNPay::Transaction;
use PlugNPay::Transaction::Vault;
use base "PlugNPay::API::REST::Responder";

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();
  my $data = {};

  if (lc($action) eq 'create') {
    $data = $self->_create();
  } elsif ($action eq 'options') {
    $data = $self->_options();
  } else {
    $data = $self->_read();
  }
  return $data;
}

sub _create {
  my $self = shift;
  my $info = $self->getInputData();
  my $transactions = $info->{'transactions'};

  my @keys = keys %{$transactions};
  if ( @keys > 20 ) {
    $self->setResponseCode(422);
    return {'status' => 'failure', 'message' => 'Transaction limit is 20 per request'};
  } elsif (@keys < 1) {
    $self->setResponseCode(422);
    return {'status' => 'failure', 'message' => 'No Transactions Set'};
  } else {
    $self->setResponseCode(200);
    return $self->_processTransactions($transactions);
  }
}

sub _processTransactions {
  my $self = shift;
  my $transactions = shift;
  my $info = $self->getInputData();
  my $time = new PlugNPay::Sys::Time();
  my $transactions = $info->{'transactions'};
  my $transactionList = {};
  my $errorList = {};
  my $vault = new PlugNPay::Transaction::Vault;

  foreach my $transID (keys %{$transactions}) {
    my $data = $transactions->{$transID};
    my $message = '';
    my $status = 0;
    my @datetime = split(' ',$time->inFormat('db'));
    my $type = lc($data->{'payment'}{'type'});
    if ($type eq 'credit' || $type eq 'ach' || $type eq 'card') {

      my $trans = new PlugNPay::Transaction('storedata',$type);

      my $contact = new PlugNPay::Contact();
      $contact->setFullName($data->{'billingInfo'}{'name'});
      $contact->setAddress1($data->{'billingInfo'}{'address'});
      $contact->setCity($data->{'billingInfo'}{'city'});
      $contact->setState($data->{'billingInfo'}{'state'});
      $contact->setPostalCode($data->{'billingInfo'}{'postalCode'});
      $contact->setCountry($data->{'billingInfo'}{'country'});
      $contact->setEmailAddress($data->{'billingInfo'}{'email'});
      $contact->setPhone($data->{'billingInfo'}{'phone'});


      my $orderID = $data->{'orderID'};
      if (defined $orderID) {
        $trans->setOrderID($orderID);
      }

      my $gatewayAccount = $self->getGatewayAccount() || $self->getResourceData()->{'merchant'};

      $trans->setGatewayAccount($gatewayAccount);
      $trans->setBillingInformation($contact);
      $trans->setTime($time->inFormat('db'));
      $trans->setAccountCode(1,$data->{'accountCode'});
      $trans->setTransactionAmount($data->{'amount'});
      $trans->setTransactionType('storedata');

      if ($type eq 'credit' || $type eq 'card') {
        #Verify Card Info
        my $month = $data->{'payment'}{'card'}{'expMonth'};
        my $year = $data->{'payment'}{'card'}{'expYear'};

        $month =~ s/^0+//g; #Clear off extra 0's from month (fixes 0012, 011, etc)
        if (length($month) < 2) {
          $month = '0' . $month; #If month is a single digit pad 1 zero to front
        }
        $year = substr($year,-2,2);  #Get last two digits of year

        my $card = new PlugNPay::CreditCard();
        $card->setName($data->{'billingInfo'}{'name'});
        $card->setNumber($data->{'payment'}{'card'}{'number'});
        $card->setExpirationMonth($month);
        $card->setExpirationYear($year);

        $trans->setCreditCard($card);

      } elsif ($type eq 'ach') {
        #Verify ACH Info
        my $check = new PlugNPay::OnlineCheck();
        $check->setName($data->{'billingInfo'}{'name'});
        $check->setABARoutingNumber($data->{'payment'}{'ach'}{'routingNumber'});
        $check->setAccountNumber($data->{'payment'}{'ach'}{'accountNumber'});
        $check->setAccountType($data->{'payment'}{'ach'}{'accountType'});

        $trans->setOnlineCheck($check);
      }

      $transactionList->{$transID} = $trans;
    } else {
      $errorList->{$transID}{'message'} = "Transaction was not processed: bad payment type";
      $errorList->{$transID}{'amount'} = $data->{'amount'};
      $errorList->{$transID}{'name'} = $data->{'billingInfo'}{'name'};
    }
  }

   my $output = $self->_buildResponse($vault->process($transactionList));
   foreach my $errorID (keys %{$errorList}) {
     $output->{'transactions'}{$errorID} = $errorList->{$errorID};
   }

   return $output;
}

sub _options {
  my $self = shift;
  $self->setResponseCode(200);
  return {};
}

sub _read {
  my $self = shift;

  # NOTE: Read does nothing now!
  # In the future, maybe we want to be able to get the info for a transaction here?
  # I'm not going to put this in now, but could be useful one day.
  # - Dylan

  $self->setResponseCode(400);
  return {'status' => '0', 'message' => 'Bad Request Method'};
}

sub _buildResponse {
  my $self = shift;
  my $responseHash = shift;
  my $outputHash = {};
  foreach my $responseID (keys %{$responseHash} ) {
    my $response = $responseHash->{$responseID};
    my $transaction = $response->{'transaction'};
    my $status = $response->{'status'};
    my $message = $response->{'message'};
    my $output = {};

    $output->{'message'} = $message;
    $output->{'status'} = $status;
    $output->{'amount'} = "" . $transaction->getTransactionAmount() . "";
    $output->{'date'} = $response->{'date'};
    $output->{'orderID'} = $status eq 'success' ? $transaction->getOrderID() : '';
    $output->{'name'} = $transaction->getBillingInformation()->getFullName();
    $outputHash->{$responseID} = $output;
  }

  return {'transactions' => $outputHash};
}


1;
