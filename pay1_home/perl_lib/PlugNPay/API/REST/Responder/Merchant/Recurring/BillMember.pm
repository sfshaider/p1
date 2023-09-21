package PlugNPay::API::REST::Responder::Merchant::Recurring::BillMember;

use strict;
use PlugNPay::Recurring::BillMember;
use PlugNPay::Transaction::Loader;
use PlugNPay::Transaction::JSON;
use PlugNPay::Transaction::JSON::Versioned;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();

  if ($action eq 'create') {
    $self->_create();
  } else {
    $self->setResponseCode(501);
    return {};
  }
}

sub _create {
  my $self = shift;
  my $merchant = $self->getResourceData()->{'merchant'} || $self->getGatewayAccount();
  my $customer = $self->getResourceData()->{'customer'};
  my $inputData = $self->getInputData();
  my $formattedTransaction = {};
  my $util = new PlugNPay::Transaction::JSON();

  my $biller = new PlugNPay::Recurring::BillMember();
  my $data = {
    'amount'      => $inputData->{'amount'},
    'description' => $inputData->{'description'},
    'cvv'         => $inputData->{'cvv'},
    'acctCode1'   => $inputData->{'acctCode1'},
    'acctCode2'   => $inputData->{'acctCode2'},
    'acctCode3'   => $inputData->{'acctCode3'},
    'recInit'   => $inputData->{'initRecurring'} ? 1 : 0,
    'recurring' => $inputData->{'recurring'}     ? 1 : 0,
    'merchantClassifierID' => $inputData->{'merchantClassifierID'},
    'sendEmailReceipt' => $inputData->{'sendEmailReceipt'}
  };

  if ($inputData->{'databaseName'}) {
    $data->{'databaseName'} = $inputData->{'databaseName'},
  }

  my $billStatus = $biller->billMember($merchant, $customer, $data);
  my $transactionID = $billStatus->{'transactionDetails'}{'pnpTransactionID'};
  my $orderID = $billStatus->{'transactionDetails'}{'orderID'};

  if ($billStatus->{'status'} && %{$billStatus->{'transactionDetails'}}) {
    if ($orderID ne '') {
      my $loader = new PlugNPay::Transaction::Loader({ loadPaymentData => 1 });
      my $transactions = $loader->load({ gatewayAccount => $merchant, orderID => $orderID, transactionID => $transactionID });
      my $transaction = $transactions->{$merchant}{$transactionID};

      if (!ref($transaction)) {
        $self->setResponseCode(501);
        return { status => 'error', message => 'Unknown error, failed to load transaction result.' };
      }

      $formattedTransaction = $util->transactionToJSON($transaction);
      $formattedTransaction = $self->formatTransactionResults({
        transaction => $transaction,
        reloadedData => $transaction
      });
    }
  }

  $self->setResponseCode(201);
  return { 'status' => $billStatus->{'transactionStatus'},
           'billed' => $billStatus->{'billed'} || 0,
           'message' => ($billStatus->{'billed'} ? 'Successfully billed member.'
                                                 : 'Bill member failed. ' . $billStatus->{'message'}),
           'transaction' => $formattedTransaction
         };
}


sub formatTransactionResults {
  my $self = shift;
  my $input = shift;
  my $transaction = $input->{'transaction'};
  my $reloadedData = $input->{'reloadedData'};

  my $featuresAccountUsername = $self->getGatewayAccount();
  my $featuresAccount = new PlugNPay::GatewayAccount($featuresAccountUsername);
  my $features = $featuresAccount->getFeatures();

  my $resourceOptions = $self->getResourceOptions();
  my $format = $resourceOptions->{'format'};

  my %transactionResults;

  my $jsonFormatter = new PlugNPay::Transaction::JSON();
  my $responseFormattedTran = $jsonFormatter->transactionToJSON($transaction);

  if ($features->get('rest_api_transaction_version') ne '') {
    $self->setWarning('An older response format is currently enabled for this account.  Please contact support for more information.');
  }

  if ($format || $features->get('rest_api_transaction_version') ne '') {
    my $reformatter = new PlugNPay::Transaction::JSON::Versioned();
    $responseFormattedTran = $reformatter->reformat({
      version => $format || $features->get('rest_api_transaction_version'),
      formatted => $responseFormattedTran,
      transaction => $transaction
    });
  }

  return $responseFormattedTran;
}

1;
