package PlugNPay::Fraud::Contact::Phone;

use strict;
use base 'PlugNPay::Fraud::Abstract';

sub setBlockedNumbers {
  my $self = shift;
  my $blockedNumbers = shift;
  $self->{'blockedNumbers'} = $blockedNumbers;
}

sub getBlockedNumbers {
  my $self = shift;
  return $self->{'blockedNumbers'};
}

sub save { 
  my $self = shift;
  my $username = shift;
  my $phoneList = shift;
  
  if (ref($phoneList) ne 'ARRAY') {
    $phoneList = [$phoneList];
  }
  
  my $insert = q/
    INSERT INTO phone_fraud
    (username, entry) 
    VALUES /;
  
  my @params = ();
  my @qmarks = ();
  foreach my $phone (@{$phoneList}) {
    push @params, $username, $phone;
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
      FROM phone_fraud
     WHERE username = ?
  /;

   $self->_load($select, [$username], '0-9');
}

sub isPhoneBlocked {
  my $self = shift;
  my $phone = shift;

  if ($phone =~ /,/) {
    $phone = split(',',$phone);
  } elsif (ref($phone) ne 'ARRAY') {
    $phone = [$phone];
  }
  
  my $username = shift || $self->getGatewayAccount();

  if (!defined $self->_getLoadedEntries()) {
    die "No account to load phone data!\n" if !defined $username;
    $self->load($username);
  }
  
  my $hasBlockedNumber = 0;
  my $blockedNumbers = $self->_isInEntriesMap($phone, '0-9');

  if (@{$blockedNumbers} > 0) {
    $hasBlockedNumber = 1;
    $self->setBlockedNumbers($blockedNumbers);
  }
  
  return $hasBlockedNumber;
}

1;
