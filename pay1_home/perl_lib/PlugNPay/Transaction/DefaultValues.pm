package PlugNPay::Transaction::DefaultValues;

use strict;
use PlugNPay::Currency;
use PlugNPay::CreditCard;
use PlugNPay::GatewayAccount;
use PlugNPay::Transaction::MapLegacy;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub setLegacyDefaultValues {
  my $self = shift;
  my $gatewayAccount = shift;
  my $pairs = shift;

  my $accountFeatures = new PlugNPay::GatewayAccount($gatewayAccount)->getFeatures();
  my $defaultValues = $accountFeatures->get('defaultValues');
 
  if (ref($defaultValues) eq 'HASH') {
    foreach my $key (keys %{$defaultValues}) {
      my $value = $defaultValues->{$key}{'defaultValue'};
      my $replaceArrayRef = $defaultValues->{$key}{'replace'};
      my $coefficient = $defaultValues->{$key}{'coefficient'};
      my $variable = $defaultValues->{$key}{'variable'};
      if (($value eq '') && (($coefficient ne '') && ($variable ne ''))) {
        $value = sprintf('%0.2f', $pairs->{$variable} * $coefficient);
      }
      foreach my $var (@{$replaceArrayRef}) {
        if ($var eq 'force') {
          $pairs->{$key} = $value;
        }
        elsif (($var eq 'null') && (!exists $pairs->{$key})) {
          $pairs->{$key} = $value;
        }
        elsif (($var eq 'empty') && (exists $pairs->{$key}) && ($pairs->{$key} eq '')) {
          $pairs->{$key} = $value;
        }
      }
    }
  }
 
  if ($accountFeatures->get('leastCost')) {
    $pairs = $self->leastCost($pairs);
  }

  return $pairs;
}

sub leastCost {
  my $self = shift;
  my $pairs = shift;

  my $creditCard = new PlugNPay::CreditCard($pairs->{'card-number'});
  if ($creditCard->isBusinessCard()) {
    if ($pairs->{'tax'} == 0 || !$pairs->{'tax'}) {
      my $transactionAmount = $pairs->{'amount'} || $pairs->{'card-amount'};
      (my $amount = $transactionAmount) =~ s/[^\d.]//g;
      my $tax = $amount * .1;

      my $currency;
      if ($pairs->{'currency'}) {
        $currency = $pairs->{'currency'};
      } else {
        ($currency = $transactionAmount) =~ s/[^a-zA-Z]//g;
      }

      if (!$currency) {
        $currency = 'usd';
      }

      my $currencyObj = new PlugNPay::Currency($currency);
      $pairs->{'tax'} = $currencyObj->format($tax, { 'digitSeparator' => '' });
    }

    if (!defined $pairs->{'ponumber'}) {
      $pairs->{'ponumber'} = $pairs->{'orderID'};
    }

    $pairs->{'commcardtype'} = 'purchase';
  }
  
  return $pairs;
}

sub setDefaultValues {
  my $self = shift;
  my $gatewayAccount = shift;
  my $transactionObject = shift;
  
  if (ref($transactionObject) =~ /^PlugNPay::Transaction/) {
    my $mapLegacy = new PlugNPay::Transaction::MapLegacy();
    $transactionObject = $mapLegacy->map($transactionObject, $gatewayAccount);
  }
 
  return $transactionObject;
}

1;
