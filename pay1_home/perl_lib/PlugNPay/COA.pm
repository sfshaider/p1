package PlugNPay::COA;

use strict;
use CGI;
use PlugNPay::DBConnection;
use PlugNPay::Transaction::Adjustment;
use PlugNPay::Transaction::Adjustment::Settings;
use PlugNPay::Transaction::Adjustment::Settings::FailureMode;
use PlugNPay::Transaction::Adjustment::Settings::AuthorizationType;
use PlugNPay::Transaction::Adjustment::Session;
use PlugNPay::Transaction::Adjustment::Model;
use PlugNPay::Transaction::Adjustment::Model::Type;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;


  my $gatewayAccount = shift;

  if (defined $gatewayAccount) {
    $self->setGatewayAccount($gatewayAccount);
  }

  return $self;
}

sub setGatewayAccount {
  my $self = shift;
  my $account = lc shift;
  $account =~ s/[^a-z0-9]//g;
  $self->{'account'} = $account;
  $self->{'adjustment'} = new PlugNPay::Transaction::Adjustment($account);
  $self->{'settings'} = new PlugNPay::Transaction::Adjustment::Settings($account);
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'account'};
}

sub getState {
  my $self = shift;
  return $self->{'state'} || {};
}

sub getAuthorizationType {
  my $self = shift;
  my $authorizationTypeID = $self->{'settings'}->getAdjustmentAuthorizationTypeID();
  my $authorizationType = new PlugNPay::Transaction::Adjustment::Settings::AuthorizationType($authorizationTypeID);
  return $authorizationType->getType();
}

sub getEnabled {
  my $self = shift;
  return $self->{'settings'}->getEnabled();
}

sub getModel {
  my $self = shift;

  my $modelID = $self->{'settings'}->getModelID();
  my $model = new PlugNPay::Transaction::Adjustment::Model($modelID);
  return $model->getLegacyModel();
}

sub getChargeAccount {
  my $self = shift;
  return $self->{'settings'}->getAdjustmentAuthorizationAccount();
}

sub getRaw {
  return { error => 'getRaw() has been deprecated' };
}

sub loadSettings {
  # do nothing, settings are already loaded as soon as the gateway account is set.
}

sub getFormula {
  # do nothing
}

sub startSession {
  my $self = shift;
  my $gatewayAccount = shift || $self->getGatewayAccount();
  my $session = new PlugNPay::Transaction::Adjustment::Session({ gatewayAccount => $gatewayAccount });
  return $session->start();
}

sub cleanupSessions {
  my $self = shift;
  my $session = new PlugNPay::Transaction::Adjustment::Session();
  $session->cleanup();
}

sub verifySession {
  my $self = shift;
  my $sessionID = shift;
  my $session = new PlugNPay::Transaction::Adjustment::Session({ gatewayAccount => $self->getGatewayAccount() });
  return $session->verify($sessionID);
}



sub getCreditTotalRate {
  my $self = shift;
  return sprintf('%.04f',$self->{'response'}{'cardTotalRate'}/100);
}

sub getCreditFixedFee {
  my $self = shift;
  return sprintf('%.02f',$self->{'response'}{'cardFixedAdjustment'});
}

sub getDebitTotalRate {
  my $self = shift;
  return sprintf('%.04f',($self->{'response'}{'debitTotalRate'} || $self->{'response'}{'regulatedDebitTotalRate'})/100);
}

sub getDebitFixedFee {
  my $self = shift;
  return sprintf('%.02f',($self->{'response'}{'debitFixedAdjustment'} || $self->{'response'}{'regulatedDebitFixedAdjustment'}));
}

sub getACHTotalRate {
  my $self = shift;
  return sprintf('%.04f',$self->{'response'}{'achTotalRate'}/100);
}

sub getACHFixedFee {
  my $self = shift;
  return sprintf('%.02f',$self->{'response'}{'achFixedAdjustment'});
}


sub _getModelType {
  my $self = shift;
  my $modelID = $self->{'settings'}->getModelID();
  my $model = new PlugNPay::Transaction::Adjustment::Model($modelID);
  my $modelType = new PlugNPay::Transaction::Adjustment::Model::Type($model->getModelTypeID());
  return $modelType->getType();
}

sub isFee {
  my $self = shift;
  return ($self->_getModelType() eq 'fee');
}

sub isSurcharge {
  my $self = shift;
  return ($self->_getModelType() eq 'surcharge');
}

sub isOptional {
  my $self = shift;
  return ($self->_getModelType() eq 'optional');
}

sub isDiscount {
  my $self = shift;
  return ($self->_getModelType() eq 'discount');
}

sub getFailureRule {
  my $self = shift;
  my $failureModeID = $self->{'settings'}->getFailureModeID();
  my $failureMode = new PlugNPay::Transaction::Adjustment::Settings::FailureMode($failureModeID);
  return $failureMode->getMode();
}

sub getAdjustment {
  my $self = shift;
  $self->get(@_);
  return sprintf('%.02f',$self->{'response'}{'adjustment'});
}

sub get {
  my $self = shift;
  my $bin = shift;
  my $transactionAmount = shift;
  my $transactionIdentifier = shift || 'n/a';

  my $adjustment = $self->{'adjustment'};
  $adjustment->setTransactionAmount($transactionAmount);
  $adjustment->setTransactionIdentifier($transactionIdentifier);
  $adjustment->setCardNumber($bin);

  my $result = $adjustment->calculate();

  my $discount = ($self->getModel() eq 'instantdiscount' ? -1 : 1);

  # create a hash compatible with the way COA was...
  my $response = {
    threshold => $result->getThreshold(),
    adjustment => sprintf('%.02f',$result->getAdjustment('calculated') * $discount),
    maxAdjustment => sprintf('%.02f',$result->getMaxAdjustment() * $discount),
    minAdjustment => sprintf('%.02f',$result->getMinAdjustment() * $discount),
    debitAdjustment => sprintf('%.02f',$result->getAdjustment('regulatedDebit') * $discount),
    type => $result->getCardType(),
    brand => $result->getCardBrand(),
    model => $result->getModel()
  };

  my $maxCardTotalRate = 0;
  my $maxCardFixedAdjustment = 0;
  foreach my $type (@{$result->getAdjustmentTypes}) {
    $response->{$type . 'Adjustment'} = sprintf('%.02f',$result->getAdjustment($type) * $discount);
    $response->{$type . 'TotalRate'} = sprintf('%.02f',$result->getTotalRate($type));
    $response->{$type . 'FixedAdjustment'} = sprintf('%.2f',$result->getFixedAdjustment($type));
    if ($type =~ /^(cardMin|cardMax|rewards|business|international|consumer)$/ && $result->getTotalRate($type) > $maxCardTotalRate) {
      $maxCardTotalRate = $result->getTotalRate($type);
      $maxCardFixedAdjustment = sprintf('%.02f',$result->getFixedAdjustment($type));
    }
  }

  $response->{'cardTotalRate'} = sprintf('%.2f',$maxCardTotalRate);
  $response->{'cardFixedAdjustment'} = sprintf('%.2f',$maxCardFixedAdjustment);

  $self->{'response'} = $response;
  return $response;
}

sub getCustomerCanOverride {
  my $self = shift;

  return $self->{'settings'}->getCustomerCanOverride();
}

sub getOverrideCheckboxIsChecked {
  my $self = shift;

  return $self->{'settings'}->getOverrideCheckboxIsChecked();
}

sub getCheckCustomerState {
  my $self = shift;

  return $self->{'settings'}->getCheckCustomerState();
}

sub getAdjustmentIsTaxable {
  my $self = shift;

  return $self->{'settings'}->getAdjustmentIsTaxable();
}

1;
