package PlugNPay::Processor::Process::Settlement;

use strict;
use PlugNPay::Processor::Process::Settlement::Credit;
use PlugNPay::Processor::Process::Settlement::OnlineCheck;

# This is essentially a wrapper class for compatibility #
sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  $self->{'credit'} = new PlugNPay::Processor::Process::Settlement::Credit();
  $self->{'check'}  = new PlugNPay::Processor::Process::Settlement::OnlineCheck();

  return $self;
}

sub settle {
  my $self = shift;
  my $time = shift;
  my $username = shift || 'all';

  ################################################
  #  - Credit loads marked transactions          #
  #  - OnlineCheck loads successful auths        #
  #                                              #
  #  This is done because checks aren't settled, #
  #  simply updated by the processor. So the     #
  #  middle step isn't required.                 #
  ################################################

  my $results = {};
  eval {
    $results->{'creditCard'} = $self->{'credit'}->settle($time, $username);
  };

  if ($@) {
    $self->addError({'action' => 'Settle credit cards', 'error' => $@});
  }

  eval {
    $results->{'onlineCheck'} = $self->{'check'}->settle($time, $username);
  };

  if ($@) {
    $self->addError({'action' => 'ACH Status Changes', 'error' => $@});
  }

  return $results;
}

# settleTransactions
#   input: hash ref
#     {
#       <gatewayAccount> => [<transactionId>,...],
#     }
#   output: hash ref
#     {
#       <gatewayAccount> => $results
#     }
sub settleTransactions {
  my $self = shift;
  my $data = shift;
  # convert input to the following structure
  # {
  #   <gatewayAccount> => {
  #     'credit' => [<transactionId>,...],
  #        'ach' => [<transactionId>,...]
  #   },
  #   <gatewayAccount> => ...
  # }
  my $updater = new PlugNPay::Transaction::Updater();
  my $transactionsToSettle = {};
  my $vehicles = new PlugNPay::Transaction::Vehicle();
  my %results;
  foreach my $account (keys %{$data}) {
    my %accountResults;
    my $transactionData = $updater->loadTransactionsToSettle({ gatewayAccount => $account, transactionIds => $data->{$account}});
    my $transactions = $transactionData->{$account};
    my $cardTransactions = {};
    my $achTransactions  = {};
    foreach my $transactionId (keys %{$transactions}) {
      my $transaction = $transactions->{$transactionId};
      $cardTransactions->{$transactionId} = $transaction if $transaction->{'transaction_vehicle'} eq 'card';
      $achTransactions->{$transactionId}  = $transaction if $transaction->{'transaction_vehicle'} eq 'ach';
    }
    my $cardResults = {};
    if ((keys %{$cardTransactions}) > 0) {
      my $pending = $self->{'credit'}->requestSettlement($cardTransactions);
      $cardResults = $self->{'credit'}->redeemSettled($pending);
    }
    my $achResults = {};
    if ((keys %{$achTransactions}) > 0) {
      # crap
      # $self->{'ach'}->requestSettlement($achTransactions);
    }

    %accountResults = (%{$cardResults},%{$achResults});
    # remove processor from results
    my %reorganized;
    foreach my $processorId (keys %accountResults) {
      foreach my $transactionId (keys %{$accountResults{$processorId}}) {
        $reorganized{$transactionId} = $accountResults{$processorId}{$transactionId};
      }
    }
    my $updater = new PlugNPay::Transaction::Updater();
    $updater->finishSettlingTransactions(\%reorganized);

    $results{$account} = \%reorganized;
  }

  return \%results;
}

# For compatibility
sub markForSettlement {
  my $self = shift;
  return $self->{'credit'}->markForSettlement(@_);
}

sub setErrors {
  my $self = shift;
  my $errors = shift;
  $self->{'errors'} = $errors;
}

sub getErrors {
  my $self = shift;
  return $self->{'errors'} || [];
}

sub addError {
  my $self = shift;
  my $error = shift;
  chomp $error;
  push @{$self->{'errors'}},$error;
}

1;
