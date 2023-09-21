package PlugNPay::Legacy::Genfiles;

use strict;
use PlugNPay::Util::Status;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;
  return $self;
}

sub batchGroupMatch {
  my $self = shift;
  my $group = shift;
  my $batchGroup = shift;

  my $status = new PlugNPay::Util::Status(1);

  if ($group =~ /\D/ || $batchGroup =~ /\D/) {
    $status->setFalse();
    $status->setError('invalid group or batch group');
    return $status;
  }

  my $groupInt = int($group);
  my $batchGroupInt = int($batchGroup);

  if ($groupInt != $batchGroupInt) {
    $status->setFalse();
    my $errorMessage = "group, $group, and batch group, $batchGroup, do not match";
    $status->setError($errorMessage);
  }

  return $status;
}

1;