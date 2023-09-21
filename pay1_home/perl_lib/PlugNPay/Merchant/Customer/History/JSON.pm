package PlugNPay::Merchant::Customer::History::JSON;

use strict;
use PlugNPay::Merchant;
use PlugNPay::Sys::Time;
use PlugNPay::Membership::Plan::Type;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}   

######################################
# Subroutine: transactionLogToJSON
# ------------------------------------
# Description:
#   Converts a history object from the 
#   customer transaction log table to
#   an object.
sub transactionLogToJSON {
  my $self = shift;
  my $historyEntry = shift;

  my $transactionType = new PlugNPay::Membership::Plan::Type();
  $transactionType->loadPlanType($historyEntry->getTransactionTypeID());
  
  my $billingAccount = new PlugNPay::Merchant($historyEntry->getBillingAccountID())->getMerchantUsername();
  
  # for Javascript
  my $dateTime = new PlugNPay::Sys::Time('iso', $historyEntry->getTransactionDateTime())->inFormat('db_gm');
  $dateTime =~ s/ /T/;
  $dateTime = $dateTime . 'Z';
  
  return {
    'billingAccount'    => $billingAccount,
    'amount'            => $historyEntry->getTransactionAmount(),
    'transactionDate'   => $dateTime,
    'transactionStatus' => $historyEntry->getTransactionStatus(),
    'description'       => $historyEntry->getTransactionDescription(),
    'orderID'           => $historyEntry->getOrderID(),
    'transactionID'     => $historyEntry->getTransactionID(),
    'transactionType'   => $transactionType->getType()
  };
}

1;
