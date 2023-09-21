package PlugNPay::Currency;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::Cache::LRUCache;

our $threeLetterCache;
our $numericCache;
our $transactionCurrencyIdMap;
our $transactionCurrencyThreeLetterMap;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  if(!defined $numericCache || !defined $threeLetterCache) {
    $threeLetterCache = new PlugNPay::Util::Cache::LRUCache(4);
    $numericCache = new PlugNPay::Util::Cache::LRUCache(4);
    $transactionCurrencyIdMap = {};
    $transactionCurrencyThreeLetterMap = {};
  }

  my $currencyData = shift;
  if ($currencyData) {
    if ($currencyData =~ /^\d+$/){ #regex to check for digits
      $self->setNumeric($currencyData);
    } else {
      $self->setThreeLetter($currencyData);
    }
  }

  return $self;
}

sub loadAllCurrencyData {
  my $self = shift;

  #Always reload
  my $dbs = new PlugNPay::DBConnection();
  my $rows = $dbs->fetchallOrDie('pnpmisc', q/
      SELECT iso4217_currencycode AS `code`,
             iso4217_currencynumber AS `number`,
             description,
             iso4217_currencyname AS `name`,
             html_encoding,`precision`
        FROM currency_information /,[],{})->{'result'};

  foreach my $row (@{$rows}) {
    $self->{'data'}{$row->{'code'}} = $row;
    $self->{'data'}{$row->{'number'}} = $row;
  }

  return $self->{'data'};
}

sub loadCurrencyIfNotLoaded {
  my $self = shift;
  my $currencyData = shift;
  my $isNumeric = $currencyData =~ /^\d+$/;

  $currencyData = $self->filterThreeLetter($currencyData) unless ($isNumeric);

  if ($isNumeric) {
    return if ($numericCache->contains($currencyData));
  } else {
    return if ($threeLetterCache->contains($currencyData));
  }

  if ($threeLetterCache->contains($currencyData)) {
    my $d = $threeLetterCache->get($currencyData);
    $self->{'data'}{$d->{'threeLetter'}} = $d;
    $self->{'data'}{$d->{'numeric'}} = $d;
  } elsif ($numericCache->contains($currencyData)) {
    my $d = $threeLetterCache->get($currencyData);
    $self->{'data'}{$d->{'threeLetter'}} = $d;
    $self->{'data'}{$d->{'numeric'}} = $d;
  }

  # if the currency code is not defined in the cache hash (haha that rhymes!) then load it from the database
  if (!defined $self->{'data'}{'threeLetter'}{$currencyData} || !defined $self->{'data'}{'numeric'}{$currencyData}) {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('pnpmisc', q/
      SELECT iso4217_currencycode AS `threeLetter`, iso4217_currencynumber AS `numeric`,
             description,iso4217_currencyname AS `name`,html_encoding,`precision`
      FROM currency_information
      WHERE iso4217_currencycode = ? OR iso4217_currencynumber = ?/,[$currencyData, $currencyData],{})->{'result'};
    if (@{$rows} > 0) {
      if ($isNumeric && !defined $self->{'data'}{'numeric'}{$currencyData}) {
        $threeLetterCache->set($rows->[0]{'threeLetter'}, $rows->[0]);
        $numericCache->set($rows->[0]{'numeric'}, $rows->[0]);
        $self->{'data'}{'numeric'}{$currencyData} = $rows->[0];
      	$self->{'data'}{'threeLetter'}{$rows->[0]->{'threeLetter'}} = $rows->[0];
      } elsif(!$isNumeric && !defined $self->{'data'}{'threeLetter'}{$currencyData}) {
        $threeLetterCache->set($rows->[0]{'threeLetter'}, $rows->[0]);
        $numericCache->set($rows->[0]{'numeric'}, $rows->[0]);
        $self->{'data'}{'threeLetter'}{$currencyData} = $rows->[0];
        $self->{'data'}{'numeric'}{$rows->[0]->{'numeric'}} = $rows->[0];
      }
    }
  }
}

sub format {
  my $self = shift;
  my $amount = shift;
  my $options = shift;

  my $decimalSeparator = $options->{'decimalSeparator'};  # OPTIONAL
  my $digitSeparator = $options->{'digitSeparator'};      # OPTIONAL
  my $truncateFlg = $options->{'truncate'};               # truncate => 1 -- 3.2 (rather than 3.20)

  if (!defined $decimalSeparator) {
    $decimalSeparator = '.';
  }

  # If decimal separator is a comma, typically a period is used for the digit separator.
  if (!defined $digitSeparator) {
    $digitSeparator = ',';
  }

  # Remove everything but the decimal separator
  $amount =~ s/[^0-9$decimalSeparator]//g;
  $amount =~ /(.*)($decimalSeparator)(\d*)$/;

  my $indexOfDecimalSeparator = rindex($amount,$decimalSeparator);

  my $beforeDecimal;
  my $afterDecimal;

  if ($indexOfDecimalSeparator >= 0) {
    $beforeDecimal = substr($amount,0,$indexOfDecimalSeparator);
    $afterDecimal = substr($amount,$indexOfDecimalSeparator+1);
  } else {
    $beforeDecimal = $amount;
    $afterDecimal = 0;
  }

  my $precision = $self->getPrecision();

  my $formattedAmount;
  my $results;

  if($afterDecimal ne '') {
    while(length($results->{'number'}) != $self->getPrecision()) {
      $results = $self->_format($afterDecimal);
      if($results->{'overflow'}) {
        last;
      }
      $afterDecimal = $results->{'number'};
    }
    $afterDecimal = $results->{'number'};
  }

  if($results->{'overflow'}) {
    $beforeDecimal++;
    $afterDecimal = '0' x $self->getPrecision();
  }

  # Prepend digits in groups of 3 with the digitSeparator between them
  my $amountBeforeDecimal = '';
  while ($beforeDecimal =~ s/(\d{0,3})$//) {
    my $last3 = $1;
    if (!$last3) {
      last;
    }
    $amountBeforeDecimal = ($beforeDecimal ? $digitSeparator : '') . $last3 . $amountBeforeDecimal;
  }

  if($amountBeforeDecimal eq '') {
    $amountBeforeDecimal = '0';
  }

  return ($truncateFlg) ? (($amountBeforeDecimal . $decimalSeparator . $afterDecimal) + 0.0) : ($amountBeforeDecimal . $decimalSeparator . $afterDecimal);
}

sub _format {
  my $self = shift;
  my $numberAfterDecimal = shift;
  if(length($numberAfterDecimal) == $self->getPrecision()) {
    return {
      'number' => $numberAfterDecimal
    };
  } elsif(length($numberAfterDecimal) < $self->getPrecision()) {
    return {
      'number' => $numberAfterDecimal . ('0' x ($self->getPrecision() - length($numberAfterDecimal)))
    };
  } else {
    my $lastNumber = $numberAfterDecimal % 10;
    chop($numberAfterDecimal);
    # return in else clause in case $numberAfterDecimal is equal to precision
    if($numberAfterDecimal == ('9' x length($numberAfterDecimal))) {
      if($lastNumber > 4) {
        return {
          'overflow' => 1
        };
      } else {
        return {
          'number' => $numberAfterDecimal
        };
      }
    }

    if($lastNumber > 4) {
      my $pad = length($numberAfterDecimal);
      ++$numberAfterDecimal;
      $numberAfterDecimal = sprintf('%0' . $pad . 's', $numberAfterDecimal);
    }
    return {
      'number' => $numberAfterDecimal
    };
  }
}

sub filterThreeLetter {
  my $self = shift;
  my $currencyCode = shift;

  # convert code to upper case before we do anything else
  $currencyCode = uc $currencyCode;

  # default to USD if the currency code is empty or not 3 alphabetic characters
  if ($currencyCode eq '' || $currencyCode !~ /^[A-Z]{3}$/) {
    $currencyCode = 'USD';
  }

  return $currencyCode;
}

# backwards compatibility, don't use in new code
sub setCurrencyCode {
  my $self = shift;
  $self->setThreeLetter(@_);
}

# backwards compatibility, don't use in new code
sub getCurrencyCode {
  my $self = shift;
  $self->getThreeLetter();
}

sub setThreeLetter {
  my $self = shift;
  my $threeLetter = shift;

  $threeLetter = $self->filterThreeLetter($threeLetter);
  $self->loadCurrencyIfNotLoaded($threeLetter);
  $self->_setThreeLetter($threeLetter);
  my $numeric = $threeLetterCache->get($threeLetter)->{numeric};
  $self->_setNumeric($numeric);
}

sub getThreeLetter {
  my $self = shift;
  return $self->{'threeLetter'};
}

sub _setThreeLetter {
  my $self = shift;
  my $threeLetter = shift;
  $self->{'threeLetter'} = $threeLetter;
}

# backwards compatibility, don't use in new code
sub setCurrencyNumber {
  my $self = shift;
  $self->setNumeric(@_);
}

# backwards compatibility, don't use in new code
sub getCurrencyNumber {
  my $self = shift;
  return $self->getNumeric();
  # return $self->getField($self->getCurrencyCode(),'numeric');
}

sub setNumeric {
  my $self = shift;
  my $numeric = shift;
  $numeric =~ s/[^\d]//g;

  $self->loadCurrencyIfNotLoaded($numeric);
  $self->_setNumeric($numeric);
  my $threeLetter = $numericCache->get($numeric)->{threeLetter};
  $self->setThreeLetter($threeLetter);
}

sub _setNumeric {
  my $self = shift;
  my $numeric = shift;
  $self->{'numeric'} = $numeric;
}

sub getNumeric {
  my $self = shift;
  return $self->{'numeric'};
}

sub getHTMLEncoding {
  my $self = shift;
  return $self->getField($self->getCurrencyCode(),'html_encoding') || $self->getCurrencyCode();
}

sub getName {
  my $self = shift;
  return $self->getField($self->getCurrencyCode(),'name');
}

sub getDescription {
  my $self = shift;
  return $self->getField($self->getCurrencyCode(),'description');
}

sub getPrecision {
  my $self = shift;
  my $precision = $self->getField($self->getCurrencyCode(),'precision');
  return (defined $precision && $precision ne '' ? $precision : 2);
}

sub getField {
  my $self = shift;
  my $currency = shift;
  my $field = shift;

  $self->loadCurrencyIfNotLoaded($currency);

  if (defined $currency && defined $field && defined $self->{'data'}{'threeLetter'}{$currency} && defined $self->{'data'}{'threeLetter'}{$currency}{$field}) {
    return $self->{'data'}{'threeLetter'}{$currency}{$field};
  } else {
    return '';
  }
}

sub loadTransactionCurrencyCode {
  my $self = shift;
  $self->loadTransactionCurrency(@_);
}

sub loadTransactionCurrency {
  my $self = shift;
  my $value = shift;
  my $mode = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $query = q/SELECT id,identifier
                FROM currency/;
  $query .= q/ WHERE / . ($mode eq 'code' ? 'identifier = ?' : 'id = ?');
  my $sth = $dbs->prepare('pnp_transaction',$query);
  $sth->execute($value) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my $id = $rows->[0]{'id'};
  my $code = $rows->[0]{'identifier'};
  if ($id && defined $code) {
    $transactionCurrencyIdMap->{$id} = $code;
    $transactionCurrencyThreeLetterMap->{$code} = $id;
  }
}

sub addTransactionCurrencyCode {
  my $self = shift;
  my $code = lc shift;
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/ INSERT IGNORE INTO currency (identifier) VALUES (?) /);
  $sth->execute($code) or die $DBI::errstr;

  $self->loadTransactionCurrency($code,'code');
}

sub getTransactionCurrencyCode {
  my $self = shift;
  my $id = shift;
  unless ($id =~ /^\d+$/) {
    return $id;
  }

  if (!defined $transactionCurrencyIdMap->{$id}) {
    $self->loadTransactionCurrency($id,'id');
  }

  return $transactionCurrencyIdMap->{$id};
}

sub getTransactionCurrencyID {
  my $self = shift;
  my $code = lc shift;

  # if it's not defined, try and load it.
  if (!defined $transactionCurrencyThreeLetterMap->{$code}) {
    $self->loadTransactionCurrencyCode($code,'code')
  }

  # if it's still not defined, add it.
  if (!defined $transactionCurrencyThreeLetterMap->{$code}) {
    $self->addTransactionCurrencyCode($code);
  }

  return $transactionCurrencyThreeLetterMap->{$code};
}


1;
