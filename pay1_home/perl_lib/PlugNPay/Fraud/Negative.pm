package PlugNPay::Fraud::Negative;

use strict;
use PlugNPay::Sys::Time;
use PlugNPay::CreditCard;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Logging::DataLog;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $username = shift;
  if ($username) {
    $self->setGatewayAccount($username);
  }

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

#Insert Functions
sub addNegativeData {
  my $self = shift;
  my $data = shift;
  if (ref($data) ne 'ARRAY') {
    $data = [$data];
  }

  my $cardObj = new PlugNPay::CreditCard();
  my @dataForEncoding = ();
  my @params = ();
  foreach my $entry (@{$data}) {
    my $insertData = [ 
      $entry->{'username'},
      $entry->{'transactionTime'},
      $entry->{'result'},
    ];
    my $hashedNum;
    if (defined $entry->{'cardNumber'}) {
      $cardObj->setNumber($entry->{'cardNumber'});
      $hashedNum = $cardObj->getCardHash();
    } else {
      $hashedNum = $entry->{'hashedNumber'};
      $cardObj->setNumber($hashedNum);
      if ($cardObj->verifyLuhn10()) {
        $hashedNum = $cardObj->getCardHash();
      }
    }

    push @{$insertData}, $hashedNum;
    push @dataForEncoding,@{$insertData};
    push @params, '(?,?,?,?)';
  }


  my $insert = q/
    INSERT INTO negative (`username`, `trans_time`, `result`, `shacardnumber`)
    VALUES / . join(',',@params);

  my $dbs = new PlugNPay::DBConnection();
  eval {
    $dbs->executeOrDie('fraudtrack', $insert, \@dataForEncoding);
  };

  my $status = new PlugNPay::Util::Status(1);
  if ($@) {
    $self->log($@);
    $status->setFalse();
    $status->setError('Failed to insert negative data');
    $status->setErrorDetails($@);
  }

  return $status;
}

#Search Functions
sub query {
  my $self = shift;
  my $input = shift;
  my @values = ();
  my @params = ();
  if ($input->{'username'}) {
    push @values, $input->{'username'};
    push @params, ' `username` = ? ';
  }

  if ($input->{'transactionTime'}) {
    push @values, $input->{'transactionTime'};
    push @params, ' `trans_time` = ? ';
  } 

  if ($input->{'startTime'}) {
    push @values, $input->{'startTime'};
    push @params, ' `trans_time` >= ? ';
  }

  if ($input->{'endTime'}) {
    push @values, $input->{'endTime'};
    push @params, ' `trans_time` <= ? ';
  }

  if ($input->{'result'}) {
    push @values, $input->{'result'};
    push @params, ' `result` = ? ';
  }

  if ($input->{'hashedCardNumber'}) {
    #TODO: possible search on unsafe hashing algorithm because old code does it badly
    push @values, $input->{'hashedCardNumber'};
    push @params, ' `shacardnumber` = ? ';
  } elsif ($input->{'hashedCardNumbers'}) {
    if (ref($input->{'hashedCardNumbers'}) eq 'ARRAY') {
      push @values, @{$input->{'hashedCardNumbers'}};
      push @params, ' `shacardnumber` IN (' . join(',', map{'?'} @{$input->{'hashedCardNumbers'}}) . ') ';
    }
  }

  my $dbs = new PlugNPay::DBConnection();
  my $select = q/
    SELECT username, trans_time, result, shacardnumber
      FROM negative
     WHERE / . join(' AND ', @params);
  
  my $rows = [];
  eval {
    $rows = $dbs->fetchallOrDie('fraudtrack', $select, \@values, {})->{'result'};
  };

  if ($@) {
    $self->log($@)
  }
  
  return $rows;
}

sub checkCardHashes {
  my $self = shift;
  my $cardHashes = shift;
  my $transTime = shift || new PlugNPay::Sys::Time()->nowInFormat('gendatetime');
  return $self->query({'end_time' => $transTime, 'shacardnumber' => $cardHashes});
}

sub log {
  my $self = shift;
  my $error = shift;

  new PlugNPay::Logging::DataLog({'collection' => 'fraudtrack'})->log({
    'error'  => $error,
    'module' => ref($self)
  });
}

1;
