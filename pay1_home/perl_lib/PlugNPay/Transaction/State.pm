package PlugNPay::Transaction::State;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Die;
use PlugNPay::Util::Cache::LRUCache;

####################### State #########################
# Used for transaction states to load/use state IDs   #
# Only needed in new processing method to track state #
#######################################################

#Adding a big cache to reduce load times
our $stateCache;
our $idCache;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  if (!defined $stateCache) {
    $stateCache = new PlugNPay::Util::Cache::LRUCache(31);
  }

  if (!defined $idCache) {
    $idCache = new PlugNPay::Util::Cache::LRUCache(31);
  }

  return $self;
}

sub getStates {
  my $self = shift;
  my $ids = $self->{'states'};

  unless (defined $ids) {
    $self->_buildStates();
    $ids = $self->{'states'};
  }
  return $ids;
}

sub _buildStates {
  my $self = shift;
  my $ids = {};
  my $names = {};
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnp_transaction');
  my $sth = $dbs->prepare(q/
                          SELECT id,state
                          FROM transaction_state
                          /);
  $sth->execute() or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  foreach my $row (@{$rows}) {
    $ids->{$row->{'state'}} = $row->{'id'};
    $stateCache->set($row->{'id'},$row->{'state'});
    $names->{$row->{'id'}} = $row->{'state'};
    $idCache->set($row->{'state'},$row->{'id'});
  }

  $self->{'states'} = $ids;
  $self->{'name_reversal_hash'} = $names;
}

sub getStateNames {
  my $self = shift;
  my $nameHash = $self->{'name_reversal_hash'};

  unless (defined $nameHash) {
    $self->_buildStates();
    $nameHash = $self->{'name_reversal_hash'};
  }

  return $nameHash;
}

sub getStateData {
  my $self = shift;
  if (!defined $self->{'stateData'}) {
    my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnp_transaction');
    my $sth = $dbs->prepare(q/
                             SELECT state_id,next_state_id
                             FROM transaction_state_machine
                             /);
    $sth->execute() or die $DBI::errstr;
    my $rows = $sth->fetchall_arrayref({});
    $self->{'stateData'} = $rows;
  }
  return $self->{'stateData'};
}

sub getStateMachine {
  my $self = shift;
  my $stateMachine = $self->{'state_machine'};
  unless (defined $stateMachine) {
    $stateMachine = {};
    my $stateData = $self->getStateData();
    foreach my $stateTransition (@{$stateData}){
      if (defined $stateMachine->{$stateTransition->{'state_id'}}) {
        my @states = @{$stateMachine->{$stateTransition->{'state_id'}}};
        push @states, $stateTransition->{'next_state_id'};
        $stateMachine->{$stateTransition->{'state_id'}} = \@states;
      } else {
        my @states = ($stateTransition->{'next_state_id'});
        $stateMachine->{$stateTransition->{'state_id'}} = \@states;
      }
    }
    $self->{'state_machine'} = $stateMachine;
  }

  return $stateMachine;
}

sub getReverseStateMachine {
  my $self = shift;
  my $reverseStateMachine = $self->{'reverse_state_machine'};
  unless (defined $reverseStateMachine) {
    $reverseStateMachine = {};
    my $stateData = $self->getStateData();
    foreach my $stateTransition (@{$stateData}){
      if (defined $reverseStateMachine->{$stateTransition->{'next_state_id'}}) {
        my @states = @{$reverseStateMachine->{$stateTransition->{'next_state_id'}}};
        push @states, $stateTransition->{'state_id'};
        $reverseStateMachine->{$stateTransition->{'next_state_id'}} = \@states;
      } else {
        my @states = ($stateTransition->{'state_id'});
        $reverseStateMachine->{$stateTransition->{'next_state_id'}} = \@states;
      }
    }
    $self->{'reverse_state_machine'} = $reverseStateMachine;
  }

  return $reverseStateMachine;
}

sub checkNextState {
  my $self = shift;
  my $currentState = uc shift;
  my $nextState = uc shift;
  my $machine = $self->getStateMachine();
  my $currentID;
  if ($currentState =~ /\d+/) {
    $currentID = $currentState;
  } else {
    $currentID = $self->getTransactionStateID($currentState);
  }


  my $nextID;
  if  ($nextState =~ /\d+/) {
    $nextID = $nextState;
  } else {
    $nextID = $self->getTransactionStateID($nextState);
  }

  my $validState = 0;

  if (defined $machine->{$currentID} ) {
    my @machineMove = @{$machine->{$currentID}};
    if (grep {$_ == $nextID} @machineMove) {
      $validState = 1;
    } else {
      $validState = 0;
    }
  }

  return $validState;
}

sub getStateIDFromOperation {
  my $self = shift;
  my $op = lc shift;
  my $start;

  if ($op =~ /^auth/ || $op eq 'forceauth') {
    $start = 'AUTH_PENDING';
  } elsif ($op =~ /^postauth/) {
    $start = 'AUTH_PENDING';
  } elsif ($op =~ /^return/ || $op =~ /^credit/) {
    $start = 'CREDIT_PENDING';
  } elsif ($op =~ /^storedata/) {
    $start = 'STOREDATA_PENDING';
  } elsif ($op eq 'issue') {
    $start = 'ISSUE_PENDING';
  } elsif ($op eq 'reload') {
    $start = 'RELOAD_PENDING';
  } elsif ($op eq 'balance') {
    $start = 'BALANCE';
  } elsif ($op =~ /^sale/ || $op eq 'emv_sale') {
    $start = 'SALE_PENDING';
  } elsif ($op eq 'void') {
    $start = 'VOID_PENDING';
  } elsif ($op eq 'reauth') {
    $start = 'AUTH_REVERSAL_PENDING';
  } else {
    $start = 'INIT';
  }

  return $self->getTransactionStateID($start);
}

sub getTransactionStateName {
  my $self = shift;
  my $stateID = shift;
  my $name = $stateID;

  if ($stateID =~ /^[\d]+$/) {
    unless ($stateCache->contains($stateID)) {
      my $states = $self->getStateNames();
      $name = $states->{$stateID};
    } else {
      $name = $stateCache->get($stateID);
    }
  }

  return $name;
}

sub getTransactionStateID {
  my $self = shift;
  my $name = uc shift;
  my $id = $name;

  if ($name !~ /^[\d]+$/) {
    unless ($idCache->contains($name)) {
      my $stateIDs = $self->getStates();
      $id = $stateIDs->{$name};
    } else {
      $id = $idCache->get($name);
    }
  }

  return $id;
}

sub getNextState {
  my $self = shift;
  my $state = shift;
  my $wasSuccess = shift;
  my $nextState;
  my $nextID;

  my @currentState = split(/_/,$self->getTransactionStateName($state));
  $nextState = $currentState[0];

  if ($wasSuccess ne 'true') {
    if ($currentState[0] ne 'VOID') {
      $nextState .= '_PROBLEM';
    } else {
      $nextState = 'AUTH';
    }
  }

  if($self->checkNextState($self->getTransactionStateName($state),$nextState)){
    $nextID = $self->getStates()->{$nextState};
  } else {
    my $availableState = $self->getStateMachine();
    foreach my $potentialStateID (@{$availableState->{$state}}){
      if ( $self->getTransactionStateName($potentialStateID) =~ /_PROBLEM$/ && $wasSuccess eq 'false') {
        $nextID = $potentialStateID;
      } elsif ( $self->getTransactionStateName($potentialStateID) !~ /_PROBLEM$/ && $wasSuccess eq 'true' ) {
        $nextID = $potentialStateID;
      }
    }
    if (!defined $nextID) {
      $nextID = $state;
    }
  }

  return $nextID;
}

sub getAllowedPreviousStateIds {
  my $self = shift;
  my $newState = uc shift;
  if ($newState =~ /[A-Z]/) {
    $newState = $self->getTransactionStateID($newState);
  }

  my $reverseStateMachine = $self->getReverseStateMachine();
  my $previousStates = $reverseStateMachine->{$newState};
  return $previousStates;
}

sub getSuccessStatus {
  my $self = shift;
  my $stateID = shift;
  my $state = $self->getTransactionStateName($stateID);

  my @transData = split('_',$state);

  if (!defined $transData[1] || $transData[1] eq '') {
    return 'success';
  } else {
    return $transData[1];
  }
}

sub translateLegacyOperation {
  my $self = shift;
  my $legacyOp = lc shift;
  my $status = lc shift;
  my $state = 'INIT';
  my $stateStatus = '';

  if ($legacyOp =~ /^auth/ || $legacyOp =~ /^reauth/ || $legacyOp eq 'forceauth') {
    $state = 'AUTH';
  } elsif ($legacyOp =~ /^(postauth|mark)/) {
    $state = 'POSTAUTH';
  } elsif ($legacyOp =~ /^(return|credit)/) {
    $state = 'CREDIT';
  } elsif ($legacyOp =~ /^void/) {
    $state = 'VOID';
  } elsif ($legacyOp =~ /^sale/) {
    $state = 'SALE';
  }

  my $stateAndStatus = $state;

  if ($state ne 'INIT') {
    if ($status eq 'hold') {
      $stateStatus .= 'HOLD';
    } elsif ($legacyOp eq 'postauth' && $status eq 'pending') {
      $stateStatus .= 'READY';
    } elsif ($legacyOp eq 'postauth' && $status eq 'locked') {
      $stateStatus .= 'PENDING';
    } elsif ($status eq 'pending') {
      $stateStatus .= 'PENDING';
    } elsif ($status !~ /success|pending/) {
      $stateStatus .= 'PROBLEM';
    }

    if ($stateStatus ne '') {
      $stateAndStatus = $state . '_' . $stateStatus;
    }
  }

  if (wantarray()) {
    return ($state,$stateStatus);
  }

  return $stateAndStatus;
}

1;
