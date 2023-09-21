package PlugNPay::Fraud::Chargeback;

use strict;
use PlugNPay::Sys::Time;
use PlugNPay::DBConnection;
use PlugNPay::Database::QueryBuilder;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::Status;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  return $self;
}

sub save {
  my $self = shift;
  my $chargebackData = shift;

  my $insert = q/
    INSERT INTO `chargeback`
    (`username`, `orderid`, `trans_date`, `subacct`,
     `post_date`, `entered_date`, `amount`, `cardtype`,
     `country`, `returnflag`, `currency`, `origamt`,
     `origcurr`, `type`)
    VALUES 
  /;

  my $qmarkString = '(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)';
  my $values = [];
  my $qmarks = [];
  foreach my $entry (@{$chargebackData}) {
    my @local = (
      $entry->{'username'},
      $entry->{'orderID'},
      $entry->{'transactionDate'},
      $entry->{'subAccount'} || '',
      $entry->{'postDate'},
      $entry->{'enteredDate'},
      $entry->{'transactionAmount'},
      $entry->{'cardType'},
      $entry->{'country'},
      $entry->{'returnFlag'},
      $entry->{'currency'},
      $entry->{'originalAmount'},
      $entry->{'originalCurrency'},
      'chargeback'
    );

    push @{$qmarks}, $qmarkString;
    push @{$values}, @local;
  }

  my $status = new PlugNPay::Util::Status(1);
  my $dbs = new PlugNPay::DBConnection();
  eval {
    $dbs->executeOrDie('fraudtrack', $insert, $values);
  };

  if ($@) {
    $status->setFalse();
    $status->setError('Failed to insert into chargeback');
    $status->setErrorDetails($@);
  }

  return $status;
}

sub load {
  my $self = shift;
  my $input = shift;
  my $builder = new PlugNPay::Database::QueryBuilder();
  my $generated = $builder->generateDateRange($input);
  my $dbs = new PlugNPay::DBConnection();
  my $select = q/
    SELECT `username`, `orderid`, `trans_date`, `subacct`,
           `post_date`, `entered_date`, `amount`, `cardtype`,
           `country`, `returnflag`, `currency`, `origamt`,
           `origcurr`, `type`
      FROM `chargeback`
     WHERE entered_date IN (/ . $generated->{'params'} . ') ';
  my @values = @{$generated->{'values'}};
  my @additionalParams = ();
  foreach my $key (keys %{$input}) {
    if ($key !~ /start_date|end_date/i) {
      my $value = $input->{$key};
      $key =~ s/[^a-zA-Z0-9]//g;

      if (ref($value) eq 'ARRAY') {
        my @multipleValues = map {'?'} @{$value};
        push @additionalParams, $key . ' IN (' . join(',', @multipleValues) . ') ';
        push @values, @{$value};
      } else {
        push @additionalParams, $key . ' = ? ';
        push @values, $value;
      }
    }
  }

  $select .= join(' AND ', @additionalParams);
  my $results = [];
  eval {
    $results = $dbs->fetchallOrDie('fraudtrack', $select, \@values, {})->{'result'};
  }; 

  if ($@) {
    $self->log($input, $@);
  }

  return $results;
}

sub log {
  my $self = shift;
  my $input = shift; 
  my $error = shift;
  new PlugNPay::Logging::DataLog({'collection' => 'fraudtrack'})->log({
    'error'  => $error,
    'data'   => $input,
    'module' => ref($self)
  });
}

1;
