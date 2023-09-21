package PlugNPay::Processor::ProcessorMessageServiceClient::GetTransactionsResponse;

use strict;

use JSON::XS;

use PlugNPay::Util::Status;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;
  return $self;
}

sub getError {
  my $self = shift;
  my $errorValue = $self->{'error'} ? 1 : 0;
  return $errorValue;
}

sub getMessage {
  my $self = shift;
  my $message = $self->{'message'} || '';
  return $message;
}

sub getRequestId {
  my $self = shift;
  my $requestId = $self->{'requestId'} || '';
  return $requestId;
}

sub getTransaction {
  my $self = shift;

  my $status = new PlugNPay::Util::Status(1);

  my $transactions = $self->{'transactions'};

  my $transactionIndex = ++$self->{'currentTransactionIndex'};

  if (length(@{$transactions}) >= $transactionIndex) {
    my $transaction = $transactions->[$transactionIndex];
    $status->set('transaction',$transaction);
  } else {
    $status->setFalse();
    $status->setError('no more transactions');
  }

  return $status;
}

sub fromJSON {
  my $self = shift;
  my $json = shift;

  $self->{'raw'} = $json;

  my $status = new PlugNPay::Util::Status(1);

  eval {
    my $data = decode_json($json);
    $self->_setFromData($data);
  };

  if ($@) {
    $status->setFalse();
    $status->setError($@);
  }

  return $status;
}

sub _setFromData {
  my $self = shift;
  my $data = shift;

  $self->{'currentTransactionIndex'} = -1;

  $self->{'transactions'} = _getTransactionsFromData($data);

  $self->{'error'}     = $data->{'error'};
  $self->{'message'}   = $data->{'message'};
  $self->{'requestId'} = $data->{'requestId'};
}

sub _getTransactionsFromData {
  my $data = shift;

  my $transactions = $data->{'transactions'};

  if (ref($transactions) ne 'ARRAY') {
    die('transactions is not an array reference');
  }

  my @transactionsList;

  foreach my $transaction (@{$transactions}) {
    my ($username, $orderId, $transactionData, $transactionRequestId);
    eval {
      $username = $transaction->{'username'};
      die('username not set in transaction') if !defined $username || $username eq '';

      $orderId = $transaction->{'orderId'};
      die('orderId not set in transaction') if !defined $orderId || $orderId eq '';

      $transactionData = $transaction->{'data'};
      die('data is not set in transaction') if !defined $transactionData;

      $transactionRequestId = $transaction->{'transactionRequestId'};
      die('transactionRequestId is not set in transaction') if !defined $transactionRequestId || $transactionRequestId eq '';
    };

    if ($@) {
      next;
    }

    my $t = {
      username => $username,
      orderId => $orderId,
      data => $transactionData,
      transactionRequestId => $transactionRequestId
    };

    push @transactionsList, $t;
  }

  return \@transactionsList;
}

1;