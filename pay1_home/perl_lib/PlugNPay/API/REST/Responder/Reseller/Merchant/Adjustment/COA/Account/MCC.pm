package PlugNPay::API::REST::Responder::Reseller::Merchant::Adjustment::COA::Account::MCC;

use strict;
use PlugNPay::Transaction::Adjustment::COA::Account::MCC;

use base "PlugNPay::API::REST::Responder";

sub _getOutputData {
  my $self = shift;
  my $data = {};
  my $action = $self->getAction();
   
  $data = $self->_read();

  return $data;
}

sub _read {
  my $self = shift;
  my $MCC = $self->getResourceData->{'mcc'};
  my $output = {};

  my $COA = new PlugNPay::Transaction::Adjustment::COA::Account::MCC();
  $COA->setMCC($MCC);

  if ($COA->isValid()) {
    $self->setResponseCode(200);
    $output->{'mcc'} = $MCC;
  } else {
    $self->setResponseCode(404);
  }

  return $output;
}

1;
