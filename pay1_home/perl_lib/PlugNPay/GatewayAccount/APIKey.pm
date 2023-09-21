package PlugNPay::GatewayAccount::APIKey;

use PlugNPay::API::Key;

sub new {
  my $self = shift;
  return new PlugNPay::API::Key(@_);
}

1;
