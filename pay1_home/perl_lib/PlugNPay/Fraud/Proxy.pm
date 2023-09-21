package PlugNPay::Fraud::Proxy;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;


  return $self;
}

sub addProxies {
  my $self = shift;
  my $proxies = shift;

  if (ref($proxies) ne 'ARRAY') {
    $proxies = [$proxies];
  }

  my @qmarks = map { '(?)' } @{$proxies};

  my $insert = 'INSERT INTO proxy_fraud (`entry`) VALUES ' . join(',',@qmarks);

  eval {
    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('fraudtrack', $insert, $proxies);
  };

  if ($@) {
    $self->log($@, $proxies);
  }
}

sub exists {
  my $self = shift;
  my $proxy = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $select = q/
    SELECT COUNT(*) AS `count`
      FROM proxy_fraud
     WHERE entry = ?
  /;

  my $count = 0;
  eval {
    $count = $dbs->fetchallOrDie('fraudtrack', $select, [$proxy], {})->{'result'}[0]{'count'};
  };

  if ($@) {
    $self->log($@, $proxy);
  }

  return $count > 0;
}

sub log {
  my $self = shift;
  my $error = shift;
  my $proxies = shift;

  new PlugNPay::Logging::DataLog({'collection' => 'fraudtrack'})->log({
    'error'  => $error,
    'data'   => $proxies,
    'module' => 'PlugNPay::Fraud::Proxy'
  });
}

1;
