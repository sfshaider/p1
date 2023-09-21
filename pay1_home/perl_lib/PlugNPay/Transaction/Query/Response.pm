package PlugNPay::Transaction::Query::Response;

use strict;
use JSON::XS;

use PlugNPay::Util::Status;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  $self->{'true'} = \1;
  $self->{'false'} = \0;

  return $self;
}

sub setError {
  my $self = shift;
  my $bool = shift;
  if ($bool) {
    $self->{'error'} = $self->{'true'};
  } else {
    $self->{'error'} = $self->{'false'};
  }
}

sub getError {
  my $self = shift;
  if ($self->{'error'} == $self->{'true'}) {
    return 1;
  } else {
    return 0;
  }
}

sub setMessage {
  my $self = shift;
  my $message = shift;
  $self->{'message'} = $message;
}

sub getMessage {
  my $self = shift;
  my $message = $self->{'message'} || '';
  return $message;
}

sub setRows {
  my $self = shift;
  my $rows = shift;
  $self->{'rows'} = $rows;
  delete $self->{'row'};
}

sub getRows {
  my $self = shift;
  my $rows = $self->{'rows'} || [];
  return $rows;
}

sub nextRow {
  my $self = shift;
  if (!defined $self->{'row'}) {
    $self->{'row'} = 0;
  }

  my $currentRow = $self->{'rows'}[$self->{'row'}];
  $self->{'row'}++;
  
  return $currentRow;
}

sub setQueryId {
  my $self = shift;
  my $queryId = shift;
  $self->{'queryId'} = $queryId;
}

sub getQueryId {
  my $self = shift;
  my $queryId = $self->{'queryId'};
  return $queryId;
}

sub serialize {
  my $self = shift;

  my $data = {
    error => $self->getError(),
    message => $self->getMessage(),
    rows => $self->getRows(),
    queryId => $self->getQueryId()
  };

  my $status = new PlugNPay::Util::Status(0);

  eval {
    my $json = new JSON::XS();
    my $serialized = $json->encode($data);
    $status->setTrue();
    $status->set('serialized',$serialized);
  };

  if ($@) {
    $status->setError($@);
  }

  return $status;
}

sub deserialize {
  my $self = shift;
  my $serialized = shift;

  my $status = new PlugNPay::Util::Status(0);

  eval {
    my $json = new JSON::XS();
    my $data = $json->decode($serialized);
    $self->setError($data->{'error'});
    $self->setMessage($data->{'message'});
    $self->setRows($data->{'rows'});
    $self->setQueryId($data->{'queryId'});
    $status->setTrue();
  };

  if ($@) {
    $status->setError($@);
  }

  return $status;
}

1;