package PlugNPay::Membership::Plan::FileTransfer::JSON;

use strict;
use PlugNPay::Merchant::HostConnection;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub fileTransferToJSON {
  my $self = shift;
  my $fileTransfer = shift;

  my $hostConnection = new PlugNPay::Merchant::HostConnection();
  $hostConnection->loadHostConnection($fileTransfer->getHostConnectionID());

  return {
    'fileTransferIdentifier'   => $fileTransfer->getIdentifier(),
    'description'              => $fileTransfer->getDescription(),
    'activationURL'            => $fileTransfer->getActivationURL(),
    'renamePreviousSuffix'     => $fileTransfer->getRenamePreviousSuffix(),
    'hostConnectionIdentifier' => $hostConnection->getIdentifier()
  };
}

1;
