package PlugNPay::Merchant::Host::JSON;

use strict;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub hostToJSON {
  my $self = shift;
  my $host = shift;

  return {
    'hostIdentifier' => $host->getIdentifier(),
    'merchantID'     => $host->getMerchantID(),
    'fqdn'           => $host->getFQDN(),
    'ipAddress'      => $host->getIPAddress(),
    'description'    => $host->getDescription()
  };
}

1;
