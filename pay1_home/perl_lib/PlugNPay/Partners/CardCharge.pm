package PlugNPay::Partners::CardCharge;

use PlugNPay::COA;

sub new {
  shift;

  return new PlugNPay::COA(@_);
}

1;
