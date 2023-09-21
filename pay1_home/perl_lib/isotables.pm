package isotables;

use strict;
use PlugNPay::Currency::LegacyHash::Tied;
use PlugNPay::Country::LegacyHash::Tied;

#Currency
our %currencyUSD840;
tie %currencyUSD840, 'PlugNPay::Currency::LegacyHash::Tied', { key => 'code', value => 'number' };
our %currencyUSD2;
tie %currencyUSD2, 'PlugNPay::Currency::LegacyHash::Tied', { key => 'code', value => 'precision' };
our %currency8402;
tie %currency8402, 'PlugNPay::Currency::LegacyHash::Tied', { key => 'number', value => 'precision' };
our %currency840USD;
tie %currency840USD, 'PlugNPay::Currency::LegacyHash::Tied', { key => 'number', value => 'code' };

#Country
our %countryUSUSA;
tie %countryUSUSA, 'PlugNPay::Country::LegacyHash::Tied', { key => 'twoLetter', value => 'threeLetter' };
our %countryUS840;
tie %countryUS840, 'PlugNPay::Country::LegacyHash::Tied', { key => 'twoLetter', value => 'numeric' };
our %country840US;
tie %country840US, 'PlugNPay::Country::LegacyHash::Tied', { key => 'numeric', value => 'twoLetter' };

1;
