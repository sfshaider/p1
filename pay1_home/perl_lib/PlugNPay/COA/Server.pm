package PlugNPay::COA::Server;

use strict;
use PlugNPay::AWS::ParameterStore;

our $cachedServer;
our $binInfoPath;

sub getServer {
  if (!defined $cachedServer) {
    $cachedServer = PlugNPay::AWS::ParameterStore::getParameter('/COA/SERVER',1);
  }

  return $cachedServer;
}

sub _getBinInfoPath {
  if (!defined $binInfoPath) {
    $binInfoPath = PlugNPay::AWS::ParameterStore::getParameter('/COA/SERVER/BIN_INFO_PATH');
  }

  return $binInfoPath;
}

sub getCalculationURL {
  return getServer();
}

sub getBinInfoURL {
  return getServer() . _getBinInfoPath();
}

1;
