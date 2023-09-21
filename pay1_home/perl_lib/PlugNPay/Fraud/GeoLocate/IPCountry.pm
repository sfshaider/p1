package PlugNPay::Fraud::GeoLocate::IPCountry;

use strict;
use base 'PlugNPay::Fraud::Abstract';

sub setBlockedIPs {
  my $self = shift;
  my $blockedIPs = shift;
  $self->{'blockedIPs'} = $blockedIPs;
}

sub getBlockedIPs {
  my $self = shift;
  return $self->{'blockedIPs'};
}

sub save { 
  my $self = shift;
  my $username = shift;
  my $ipcountryList = shift;
  
  if (ref($ipcountryList) ne 'ARRAY') {
    $ipcountryList = [$ipcountryList];
  }
  
  my $insert = q/
    INSERT INTO ipcountry_fraud
    (username, entry) 
    VALUES /;
  
  my @params = ();
  my @qmarks = ();
  foreach my $ipcountry (@{$ipcountryList}) {
    push @params, $username, $ipcountry;
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
      FROM ipcountry_fraud
     WHERE username = ?
  /;

  $self->_load($select, [$username], 'a-zA-Z ');
}

sub isIPBlocked {
  my $self = shift;
  my $ipAddresses = shift;
  my $username = shift || $self->getGatewayAccount();
  
  if ($ipAddresses =~ /,/) {
    $ipAddresses = split(',', $ipAddresses);
  } elsif (ref($ipAddresses) ne 'ARRAY') {
    $ipAddresses = [$ipAddresses];
  }

  if (!defined $self->_getLoadedEntries()) {
    die "No account to load ip data!\n" if !defined $username;
    $self->load($username);
  }

  my $hasBlockedIP = 0;
  my $blockedIPs = $self->_isInEntriesMap($ipAddresses, 'a-zA-Z ');
  
  if (@{$blockedIPs} > 0) {
    $hasBlockedIP = 1;
    $self->setBlockedIPs($blockedIPs);
  }

  return $hasBlockedIP;
}

1;
