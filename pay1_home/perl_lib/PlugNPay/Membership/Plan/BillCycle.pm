package PlugNPay::Membership::Plan::BillCycle;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::Cache::LRUCache;

our $idCache;
our $nameCache;

##################################
# Module: Plan::BillCycle
# --------------------------------
# Description:
#   Bill cycle defines the period
#   of when to bill the customer.
#   i.e Monthly, Bi-Monthly

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  if (!defined $idCache || !defined $nameCache) {
    $idCache = new PlugNPay::Util::Cache::LRUCache(4);
    $nameCache = new PlugNPay::Util::Cache::LRUCache(4);
  }

  return $self;
}

sub setBillCycleID {
  my $self = shift;
  my $billCycleID = shift;
  $self->{'billCycleID'} = $billCycleID;
}

sub getBillCycleID {
  my $self = shift;
  return $self->{'billCycleID'};
}

sub setDisplayName {
  my $self = shift;
  my $displayName = shift;
  $self->{'displayName'} = $displayName;
}

sub getDisplayName {
  my $self = shift;
  return $self->{'displayName'};
}

sub setCycleDuration {
  my $self = shift;
  my $cycleDuration = shift;
  $self->{'cycleDuration'} = $cycleDuration;
}

sub getCycleDuration {
  my $self = shift;
  return $self->{'cycleDuration'};
}

sub setPartialDayCredit {
  my $self = shift;
  my $partialDayCredit = shift;
  $self->{'partialDayCredit'} = $partialDayCredit;
}

sub getPartialDayCredit {
  my $self = shift;
  return $self->{'partialDayCredit'};
}

sub setCycleUnit {
  my $self = shift;
  my $cycleUnit = shift;
  $self->{'cycleUnit'} = $cycleUnit;
}

sub getCycleUnit {
  my $self = shift;
  return $self->{'cycleUnit'};
}

sub setDescription {
  my $self = shift;
  my $description = shift;
  $self->{'description'} = $description;
}

sub getDescription {
  my $self = shift;
  return $self->{'description'};
}

#################################
# Subroutine: loadBillCycle
# -------------------------------
# Description:
#   Loads the bill cycle info
#   for a plan.
sub loadBillCycle {
  my $self = shift;
  my $billCycleID = shift;

  if ($idCache->contains($billCycleID)) {
    my $data = $idCache->get($billCycleID);
    $self->_setBillCycleDataFromRow($data);
  } else {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $rows = $dbs->fetchallOrDie('merchant_cust',
        q/SELECT id,
                 display_name,
                 cycle_duration,
                 partial_day_credit,
                 cycle_unit,
                 description
          FROM recurring1_billing_cycles
          WHERE id = ?/, [$billCycleID], {})->{'result'};
      if (@{$rows} > 0) {
        my $row = $rows->[0];
        $idCache->set($billCycleID, $row);
        $self->_setBillCycleDataFromRow($row);
      }
    };

    if ($@) {
      $self->_log({
        'error' => $@
      });
    }
  }
}

sub loadBillCycleID {
  my $self = shift;
  my $displayName = uc shift;

  if ($nameCache->contains($displayName)) {
    my $data = $nameCache->get($displayName);
    $self->_setBillCycleDataFromRow($data);
  } else {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      my $rows = $dbs->fetchallOrDie('merchant_cust',
        q/SELECT id,
                 display_name,
                 cycle_duration,
                 partial_day_credit,
                 cycle_unit,
                 description
          FROM recurring1_billing_cycles
          WHERE UPPER(display_name) = ?/, [$displayName], {})->{'result'};
      if (@{$rows} > 0) {
        my $row = $rows->[0];
        $nameCache->set($displayName, $row);
        $self->_setBillCycleDataFromRow($row);
      }
    };

    if ($@) {
      $self->_log({
        'error' => $@
      });
    }
  }
}

sub _setBillCycleDataFromRow {
  my $self = shift;
  my $row = shift;

  $self->{'billCycleID'}      = $row->{'id'};
  $self->{'cycleUnit'}        = $row->{'cycle_unit'};
  $self->{'description'}      = $row->{'description'};
  $self->{'displayName'}      = $row->{'display_name'};
  $self->{'cycleDuration'}    = $row->{'cycle_duration'};
  $self->{'partialDayCredit'} = $row->{'partial_day_credit'};
}

######################################
# Subroutine: billCycleSelect
# ------------------------------------
# Description:
#   Helper function for loading bill
#   cycle information into a html
#   select tag.
sub billCycleSelect {
  my $self = shift;

  my $monthlyBillCycles = {};
  my $dailyBillCycles = {};
  my $noBillCycles = {};

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               display_name,
               cycle_duration,
               partial_day_credit,
               cycle_unit,
               description
        FROM recurring1_billing_cycles
        ORDER BY display_order ASC/, [], {})->{'result'};
    if (@{$rows} > 0) {
      foreach my $row (@{$rows}) {
        if (uc $row->{'cycle_unit'} =~ /MONTH/) {
          $monthlyBillCycles->{$row->{'id'}} = $row->{'display_name'};
        } elsif (uc $row->{'cycle_unit'} =~ /DAY/) {
          $dailyBillCycles->{$row->{'id'}} = $row->{'display_name'};
        } else {
          $noBillCycles->{$row->{'id'}} = $row->{'display_name'};
        }
      }
    }
  };

  if ($@) {
    $self->_log({
      'error' => $@
    });
  }

  return { 'monthlyBillCycles' => $monthlyBillCycles, 'dailyBillCycles' => $dailyBillCycles, 'noBillCycles' => $noBillCycles };
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'membership_bill_cycle' });
  $logger->log($logInfo);
}

1;
