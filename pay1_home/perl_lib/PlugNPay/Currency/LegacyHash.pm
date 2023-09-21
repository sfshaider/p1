package PlugNPay::Currency::LegacyHash;

use strict;
use PlugNPay::Currency;


#Currency
our %_currencyUSD840;
our %_currencyUSD2;
our %_currency8402;
our %_currency840USD;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!exists $_currencyUSD840{'USD'}) {
    my $currencyObj = new PlugNPay::Currency();
    my $currencyList = $currencyObj->loadAllCurrencyData();
    %_currencyUSD2 = ();
    %_currency8402 = ();
    %_currencyUSD840 = ();
    foreach our $currency (values %{$currencyList}) {
      $_currencyUSD840{$currency->{'code'}} = $currency->{'number'};
      $_currencyUSD2{$currency->{'code'}} = $currency->{'precision'};
      $_currency8402{$currency->{'number'}} = $currency->{'precision'};
    }

    %_currency840USD = reverse %_currencyUSD840;
  }

  return $self;
}

# the following return a copy of the hash so the original hash goes unmodified
sub getCurrencyUSD840 {
  my $self = shift;
  if (ref($self) ne 'PlugNPay::Currency::LegacyHash') {
    die('Incorrect implementation, call object method.');
  }
  return %_currencyUSD840;
}

sub getCurrencyUSD2 {
  my $self = shift;
  if (ref($self) ne 'PlugNPay::Currency::LegacyHash') {
    die('Incorrect implementation, call object method.');
  }
  return %_currencyUSD2;
}

sub getCurrency8402 {
  my $self = shift;
  if (ref($self) ne 'PlugNPay::Currency::LegacyHash') {
    die('Incorrect implementation, call object method.');
  }
  return %_currency8402;
}

sub getCurrency840USD {
  my $self = shift;
  if (ref($self) ne 'PlugNPay::Currency::LegacyHash') {
    die('Incorrect implementation, call object method.');
  }
  return %_currency840USD;
}

1;
