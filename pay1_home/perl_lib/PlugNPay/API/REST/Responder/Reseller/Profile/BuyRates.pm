package PlugNPay::API::REST::Responder::Reseller::Profile::BuyRates;

use strict;
use PlugNPay::Reseller;
use PlugNPay::Reseller::Chain;

use base "PlugNPay::API::REST::Responder";

sub _getOutputData {
  my $self = shift;
  my $data = {};

  my $username = $self->getResourceData()->{'profile'};

  $data = $self->_checkAccount($username);
 
  return $data;
}

sub _checkAccount {
  my $self = shift;
  my $account = shift;
  my $isChild = ($account eq $self->getGatewayAccount() ? 1 : 0);
  my $chain = new PlugNPay::Reseller::Chain($self->getGatewayAccount());
  unless ($isChild) {
    $isChild = $chain->hasDescendant($account,$self->getGatewayAccount());
  }

  my $data = {};
  
  if ($isChild) {
    $self->setResponseCode('200');
    $data = $self->_getRates($account);
  } else {
    $self->setResponseCode('520');
  }

  return $data;
  
}

sub _getRates {
  my $self = shift;
  my $resellerAccount = new PlugNPay::Reseller(shift);

  #Buy Rate Info
  my @data;
  my @direct = ('Direct Link',$resellerAccount->getBuyRate_Direct(),$resellerAccount->getMonthly_Direct(), $resellerAccount->getPerTran_Direct(),$resellerAccount->getPerTranMax(),$resellerAccount->getPerTranExtra());
  push @data,\@direct;
  
  #Level 3
  my @level3 = ('Level 3',$resellerAccount->getBuyRate_Level(),$resellerAccount->getMonthly_Level(),$resellerAccount->getPerTran_Level(),'','');
  push @data, \@level3;
  
  #High Risk
  my @highrisk = ('High Risk', $resellerAccount->getBuyRate_HighRisk(),$resellerAccount->getMonthly_HighRisk(),$resellerAccount->getPerTran_HighRisk(),'','');
  push @data, \@highrisk;
  
  #Recurring
  my @recurring = ('Recurring', $resellerAccount->getBuyRate_Recurring(),$resellerAccount->getMonthly_Recurring(),$resellerAccount->getPerTran_Recurring(),'','');
  push @data, \@recurring;
  
  #Billing Presentment
  my @bill = ('Billing Presentment', $resellerAccount->getBuyRate_BillPres(),$resellerAccount->getMonthly_BillPres(),$resellerAccount->getPerTran_BillPres(),'','');
  push @data,\@bill;
  
   #Membership
  my @member = ('Membership', $resellerAccount->getBuyRate_Membership(),$resellerAccount->getMonthly_Membership(),$resellerAccount->getPerTran_Membership(),'','');
  push @data, \@member;
  
  #Digital
  my @digital = ( 'Digital',$resellerAccount->getBuyRate_Digital(),$resellerAccount->getMonthly_Digital(),$resellerAccount->getPerTran_Digital(),'','');
  push @data, \@digital;
  
  #Affiliate
  my @affiliate = ('Affiliate', $resellerAccount->getBuyRate_Affiliate(),$resellerAccount->getMonthly_Affiliate(),$resellerAccount->getPerTran_Affiliate(),'','');
  push @data, \@affiliate;
  
  #FraudTrak
  my @fraud = ('FraudTrak', $resellerAccount->getBuyRate_FraudTrak(),$resellerAccount->getMonthly_FraudTrak(),$resellerAccount->getPerTran_FraudTrak(),'','');
  push @data, \@fraud;
  
  #Coupon
  my @coupon = ('Coupon',$resellerAccount->getBuyRate_Coupon(),$resellerAccount->getMonthly_Coupon(),$resellerAccount->getPerTran_Coupon(),'','');
  push @data, \@coupon;
  
  my @cols = ({'type' => 'string', 'name' => 'Buy Rates'},
              {'type' => 'string', 'name' => 'Per Transaction'},
              {'type' => 'string', 'name' => 'Monthly Minimum'},
              {'type' => 'string', 'name' => 'Setup'},
              {'type' => 'string', 'name' => 'Transaction Maximum'},
              {'type' => 'string', 'name' => 'Extra'}
             );
  
  my $buyOptions = { 'columns' => \@cols, 'tableData' => \@data, 'id' => 'buyratesTable'};
  return $buyOptions;

}

1;
