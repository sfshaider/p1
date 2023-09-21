package PlugNPay::API::REST::Responder::Merchant::Order::Transaction::ConvenienceFee;

use strict;

use PlugNPay::Transaction::Loader;
use PlugNPay::Transaction::TransactionProcessor;
use PlugNPay::COA;
use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();
  my $data = {};
  if ($action eq 'create') {
    $data = $self->_create();
  } elsif ($action eq 'delete') {
    $data = $self->_delete();
  } else {
    $self->setResponseCode('501');
  }

  return $data;
}

sub _create {
  my $self = shift;

  my $transactionID = $self->getResourceData()->{'transaction'};
  my $gatewayAccount = $self->getGatewayAccount();

  my $data;

  eval {
    my $loader = new PlugNPay::Transaction::Loader({'loadPaymentData' => 1});
  
    my $transaction;
    eval {
      my $loadedData = $loader->load({ gatewayAccount => $gatewayAccount,  transactionID => $transactionID });
      $transaction = $loadedData->{$gatewayAccount}{$transactionID};
    };
  
    my $result;
    if (ref($transaction) =~ /^PlugNPay::Transaction::/ && !$@) {
      my $transactionProcessor = new PlugNPay::Transaction::TransactionProcessor();
      my $coa = new PlugNPay::COA($gatewayAccount);
      $result = $transactionProcessor->useCOA($transaction,$coa);

      $self->setResponseCode(201);
      $data = { 
                sourceTransactionID => $transactionID,
                amount => $result->getTransaction()->getTransactionAmount(),
              };
    } else {
      $self->setResponseCode(404);
      $data = {
                status  => 'ERROR', 
                sourceTransactionID => $transactionID,
                message => 'Source transaction not found.'
              };
    }
  };

  if ($@) {
    $self->setResponseCode(520);
    $data = {};
  }

  return $data;
}

sub _delete {
  my $self = shift;

  $self->setResponseCode(501);
  my $data = {
            status => 'ERROR',
            message => 'Voids not currently allowed.'
          };

  return $data;

}

1;
