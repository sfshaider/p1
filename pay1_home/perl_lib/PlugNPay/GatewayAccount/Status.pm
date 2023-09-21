package PlugNPay::GatewayAccount::Status;

use strict;
use PlugNPay::DBConnection();

our $_statuses;
our $_reasons;
our $_validStatusReasonCombinations;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;
  $self->{'gatewayAccount'} = $gatewayAccount;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

sub setStatus {
  my $self = shift;
  my $statusNameOrID = shift;
  $self->{'currentStatus'} = $self->_findStatus($statusNameOrID);
}

sub getStatus {
  my $self = shift;
  return $self->{'currentStatus'}->{'status'}; 
}

sub getStatusID {
  my $self = shift;
  return $self->{'currentStatus'}->{'id'};
}

sub setReason {
  my $self = shift;
  my $reasonNameOrID = shift;
  my $reason = $self->_findReason($reasonNameOrID);

  foreach my $possibleReason (@{$self->getValidReasonsForStatus()}) {
    if ($reason->{'id'} == $possibleReason->{'reasonID'}) {
      $self->{'currentReason'} = $reason;
      return 1;
    }
  }

  # if here to prevent infinite loops
  if ($reason->{'id'} ne $self->getDefaultReasonIDForStatus()) {
    $self->setReason($self->getDefaultReasonIDForStatus());
  }
  return 0;
}

sub getReasonName {
  my $self = shift;
  return $self->{'currentReason'}->{'name'};
}

sub getReasonID {
  my $self = shift;
  return $self->{'currentReason'}->{'id'};
}

sub getDefaultReasonIDForStatus {
  my $self = shift;
  my $status = shift || $self->getStatusID();
  return $self->_findStatus($status)->{'defaultReasonID'};

}


sub getValidReasonsForStatus {
  my $self = shift;
  my $status = shift || $self->getStatusID();

  my @reasons;
  foreach my $combination (@{$_validStatusReasonCombinations}) {
    if ($status eq $combination->{'statusID'}) {
      push @reasons,$combination;
    }
  }

  return \@reasons;
}

sub _findStatus {
  my $self = shift;
  my $input = shift;
  my $returnStatus = {};

  foreach my $status (@{$_statuses}) {
    if ($input eq $status->{'id'} || $input eq $status->{'status'}) {
      $returnStatus = $status;
    }
  }

  return $returnStatus;
}

sub _findReason {
  my $self = shift;
  my $input = shift;
  my $returnStatusReason = {};

  foreach my $statusReason (@{$_reasons}) {
    if ($input eq $statusReason->{'id'} || $input eq $statusReason->{'reason'}) {
      $returnStatusReason = $statusReason;
    }
  }

  return $returnStatusReason;
}

sub getStatusList {
  my $self = shift;

  if (!defined $_statuses) {
    $self->_loadStatuses();
  }

  my @statusesCopy = @{$_statuses};
  return \@statusesCopy;
}

sub getStatusReasonList {
  my $self = shift;
  if (!defined $_reasons) {
    $self->_loadStatusReasons();
  }
  my @reasonsCopy = @{$_reasons};
  return \@reasonsCopy;
}

sub getStatusValidReasonList {
  my $self = shift;
  if (!defined $_validStatusReasonCombinations) {
    $self->_loadStatusValidReasons();
  }
  my @validCopy = @{$_validStatusReasonCombinations};
  return \@validCopy;
}

sub _loadStatuses {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT id,status,status_name,default_reason FROM gateway_account_status
  /);

  $sth->execute();

  my $results = $sth->fetchall_arrayref({});

  if ($results) {
    my @statuses;
    foreach my $row (@{$results}) {
      push @statuses,{ id => $row->{'id'}, status => $row->{'status'}, statusName => $row->{'status_name'}, defaultReasonID => $row->{'default_reason'} };
    }
    $_statuses = \@statuses;
  }
}

sub _loadStatusReasons {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT id, reason, reason_name FROM gateway_account_status_reason
  /);

  $sth->execute();

  my $results = $sth->fetchall_arrayref({});

  if ($results) {
    my @statusReasons;
    foreach my $row (@{$results}) {
      push @statusReasons, { id => $row->{'id'}, reason => $row->{'reason'}, reasonName => $row->{'reason_name'} };
    }
    $_reasons = \@statusReasons;
  }
}

sub _loadStatusValidReasons {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT status_id, reason_id FROM gateway_account_status_reason_valid_combination
  /);

  $sth->execute();

  my $results = $sth->fetchall_arrayref({});

  if ($results) {
    my @statusAllowedReasons;
    foreach my $row (@{$results}) {
      push @statusAllowedReasons, { statusID => $row->{'status_id'}, reasonID => $row->{'reason_id'} };
    }
    $_validStatusReasonCombinations = \@statusAllowedReasons;
  }
}
   



  


1;
