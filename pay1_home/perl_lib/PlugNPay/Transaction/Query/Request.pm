package PlugNPay::Transaction::Query::Request;

# Note:  this module does *not* validate query syntax
 
use strict;
use JSON::XS;

use PlugNPay::Util::Status;

use overload '""' => 'serialize';

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  $self->{'true'} = \1;
  $self->{'false'} = \0;

  return $self;
}

sub setRawQuery {
  my $self = shift;
  my $query = shift;
  $self->{'rawQuery'} = $query;
}

sub getRawQuery {
  my $self = shift;
  my $query = $self->{'rawQuery'} || '';
  return $query;
}

sub setRawValues {
  my $self = shift;
  my $values = shift;
  $self->{'rawValues'} = $values;
}

sub getRawValues {
  my $self = shift;
  my $values = $self->{'rawValues'} || [];
  return $values;
}

sub setProcessors {
  my $self = shift;
  my $processors = shift;

  if (ref($processors) eq '') {
    $processors = [$processors];
  } elsif (ref($processors) ne 'ARRAY') {
    die('setProcessors input must be a scalar or an array ref');
  }

  $self->{'processors'} = $processors;
}

sub getProcessors {
  my $self = shift;
  my $processors = $self->{'processors'} || [];
  return $processors;
}

sub setSkipPnpData {
  my $self = shift;
  my $skip = shift;

  if ($skip) {
    $self->{'skipPnpData'} = $self->{'true'};
  } else {
    $self->{'skipPnpData'} = $self->{'false'};
  }
}

sub getSkipPnpData {
  my $self = shift;

  if (!defined $self->{'skipPnpData'}) {
    return $self->{'false'};
  }

  return $self->{'skipPnpData'};
}

sub serialize {
  my $self = shift;

  my $data = {
    rawQuery => $self->getRawQuery(),
    rawValues => $self->getRawValues(),
    processors => $self->getProcessors(),
    skipPnpData => $self->getSkipPnpData()
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
    $self->setRawQuery($data->{'rawQuery'});
    $self->setRawValues($data->{'rawValues'});
    $self->setProcessors($data->{'processors'});
    $self->setSkipPnpData($data->{'skipPnpData'});

    $status->setTrue();
  };

  if ($@) {
    $status->setError($@);
  }

  return $status;
}


1;
