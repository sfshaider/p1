#!/bin/env perl
BEGIN {
  $ENV{'DEBUG'} = '';
}

use strict;
use Test::More qw( no_plan );

require_ok('isotables');

# currency
testCurrencyUSD840();
testCurrencyUSD2();
testCurrency8402();
testCurrency840USD();

# country
testCountry840US();
testCountryUS840();
testCountryUSUSA();

sub testCurrencyUSD840 {
  is($isotables::currencyUSD840{'usd'},'840','currencyUSD840');
}
sub testCurrencyUSD2 {
  is($isotables::currencyUSD2{'USD'},'2','currencyUSD2');
}
sub testCurrency8402 {
  is($isotables::currency8402{'840'},'2','currency8402')
}
sub testCurrency840USD {
  is($isotables::currency840USD{'840'},'USD','currency840USD');
}

sub testCountryUSUSA {
  is($isotables::countryUSUSA{'us'},'USA','countryUSUSA');
}
sub testCountryUS840 {
  is($isotables::countryUS840{'us'},'840','countryUS840');
}
sub testCountry840US {
  is($isotables::country840US{'840'},'US','country840US');
}
