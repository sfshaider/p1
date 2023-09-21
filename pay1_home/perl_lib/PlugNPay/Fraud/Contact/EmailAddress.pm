package PlugNPay::Fraud::Contact::EmailAddress;

use strict;
use base 'PlugNPay::Fraud::Abstract';

sub setBlockedAddresses {
  my $self = shift;
  my $blockedAddresses = shift;
  $self->{'blockedAddresses'} = $blockedAddresses;
}

sub getBlockedAddresses {
  my $self = shift;
  return $self->{'blockedAddresses'};
}

sub save {
  my $self = shift;
  my $username = shift;
  my $emailList = shift;

  if (ref($emailList) ne 'ARRAY') {
    $emailList = [$emailList];
  }

  my $insert = q/
    INSERT INTO email_fraud
    (username, entry) 
    VALUES /;

  my @params = ();
  my @qmarks = ();
  foreach my $email (@{$emailList}) {
    push @params, $username, $email;
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
      FROM emailaddr_fraud
     WHERE username = ?
 UNION ALL
    SELECT entry
      FROM email_fraud
     WHERE username = ?
  /;

  $self->_load($select, [$username, $username]);
}

sub isEmailBlocked {
  my $self = shift;
  my $emailAddress = shift;
  my $username = shift || $self->getGatewayAccount();

  if ($emailAddress =~ /,/) {
    $emailAddress = split(',',$emailAddress);
  } elsif (ref($emailAddress) ne 'ARRAY') {
    $emailAddress = [$emailAddress];
  }

  if (!defined $self->_getLoadedEntries()) {
    die "No account to load email data!\n" if !defined $username;
    $self->load($username);
  }

  my $hasBlockedAddress = 0;
  my $blockedAddress = $self->_isInEntriesMap($emailAddress);
  if (@{$blockedAddress} > 0) {
    $hasBlockedAddress = 1;
    $self->setBlockedAddresses($blockedAddress);
  }

  return $hasBlockedAddress;
}

1;
