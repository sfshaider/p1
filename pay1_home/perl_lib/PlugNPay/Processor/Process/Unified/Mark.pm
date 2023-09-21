package PlugNPay::Processor::Process::Unified::Mark;

use strict;

use PlugNPay::Transaction::State;
use PlugNPay::Transaction::Updater;


sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

# mark
#  - will take the transaction from the context and update the state and settle amount from the transaction
#  - sets the mark time of the transaction
#  - saves the transaction.
#  -
sub mark {
  my $self = shift;
  my $input = shift;
  my $transaction = $input->{'transaction'};
  my $context = $input->{'context'};

  my $sm = new PlugNPay::Transaction::State();
  my $allowedPreviousStates = $sm->getAllowedPreviousStateIds('POSTAUTH_READY');

  my $markTime = new PlugNPay::Sys::Time()->inFormat('iso_gm');

  my $amount = $transaction->getTransactionAmount();

  my $updater = new PlugNPay::Transaction::Updater();

  my $markData = {
    transactionId => $context->getDBTransactionData()->getPNPTransactionID(),
    settlementAmount => $transaction->getSettlementAmount()
  };

  my $result = $updater->markSettlement($markData);
  return $result;
}
1;
