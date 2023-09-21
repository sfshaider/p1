package PlugNPay::Fraud::IPAddress;

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
  my $ipList = shift;
  
  if (ref($ipList) ne 'ARRAY') {
    $ipList = [$ipList];
  }
  
  my $insert = q/
    INSERT INTO ip_fraud
    (username, entry) 
    VALUES /;
  
  my @params = ();
  my @qmarks = ();
  foreach my $ip (@{$ipList}) {
    push @params, $username, $ip;
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
      FROM ip_fraud
     WHERE username = ?
  /;

  $self->_load($select, [$username], '0-9\.');
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
  my $blockedIPs = $self->_isInEntriesMap($ipAddresses, '0-9\.');
  
  if (@{$blockedIPs} > 0) {
    $hasBlockedIP = 1;
    $self->setBlockedIPs($blockedIPs);
  }

  return $hasBlockedIP;
}

1;
