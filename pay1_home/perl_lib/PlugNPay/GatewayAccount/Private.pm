package PlugNPay::GatewayAccount::Private;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::GatewayAccount;
use PlugNPay::GatewayAccount::Query;
use PlugNPay::Util::Cache::LRUCache;
use PlugNPay::Die;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

# used for web/private
sub queryAllAccounts {
  my $self = shift;
  my $q = new PlugNPay::GatewayAccount::Query;
  return $q->query(@_);
}

sub loadAccountsFromIds {
  my $self = shift;
  my $q = new PlugNPay::GatewayAccount::Query;
  return $q->loadAccountsFromIds(@_);
}

sub distinctValues {
  my $self = shift;
  my $q = new PlugNPay::GatewayAccount::Query;
  return $q->distinctValues(@_);
}

sub wipeEnccardnumber {
  my $self = shift;
  my $account = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $result = $dbs->executeOrDie('pnpmisc',q/
    UPDATE customers SET enccardnumber = '' WHERE username = ?
  /,[$account]);
}

1;
