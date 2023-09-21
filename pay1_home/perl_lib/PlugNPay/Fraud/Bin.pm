package PlugNPay::Fraud::Bin;

use strict;
use base 'PlugNPay::Fraud::Abstract';
use PlugNPay::Fraud::BankBin;
use PlugNPay::CreditCard;

sub _setBankBinObject {
  my $self = shift;
  my $bankBinObject = shift;
  $self->{'bankBinObject'} = $bankBinObject;
}

sub getBankBinObject {
  my $self = shift;
  return $self->{'bankBinObject'};
}

sub save {
  my $self = shift;
  my $username = shift;
  my $binList = shift;

  if (ref($binList) ne 'ARRAY') {
    $binList = [$binList];
  }

  my $insert = q/
    INSERT INTO bin_fraud
    (username, entry) 
    VALUES /;

  my @params = ();
  my @qmarks = ();
  foreach my $bin (@{$binList}) {
    push @params, $username, $bin;
    push @qmarks, '(?,?)';
  }

  $insert . join(',',@qmarks);

  return $self->_save($insert, \@params);
}

sub load {
  my $self = shift;
  my $username = shift || $self->getGatewayAccount();
  my $select = q/
    SELECT entry
      FROM bin_fraud 
     WHERE username = ?
  /;

  $self->_load($select, [$username], '0-9');
}

sub isBinInTable {
  my $self = shift;
  my $bin = shift;

  $bin = substr($bin, 0, 6); 
  if (!defined $self->_getLoadedEntries()) {
    if (!defined $self->getGatewayAccount()) {
      die "No account data loaded!\n";
    }
    $self->load();
  }

  return $self->_isInEntriesMap($bin, '0-9');
}

sub checkBankBin {
  my $self = shift;
  my $bankBin = shift;
  $bankBin =~ s/[^0-9]//g;

  my $object = new PlugNPay::Fraud::BankBin($bankBin);
  $self->_setBankBinObject($object);

  return $object;
}

sub findMatchedBINCountry {
  my $self = shift;
  my $bin = shift;
  my $match = &PlugNPay::Fraud::BankBin::getMatchedBinCountry($bin);
  if (!$match) {
    my $cc = new PlugNPay::CreditCard($bin);
    $match = $cc->getCountryCode();
  }

  return $match || '';
}

1;
