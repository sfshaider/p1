package PlugNPay::GatewayAccount::Services::Service;

use strict;

use PlugNPay::DBConnection;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  my $input = shift;
  if ($input->{'id'}) {
    $self->setService({id => $input->{'id'}});
  } elsif ($input->{'handle'}) {
    $self->setService({handle => $input->{'handle'}});
  }

  return $self;
}

sub setService {
  my $self = shift;
  my $input = shift;

  if (!defined $self->{'idMap'} || !defined $self->{'handleMap'}) {
    $self->_loadServices();
  }

  if ($input->{'id'}) {
    $self->{'id'} = $input->{'id'};
    $self->{'name'}   = $self->{'idMap'}{$self->{'id'}}{'name'};
    $self->{'handle'} = $self->{'idMap'}{$self->{'id'}}{'handle'};
  } elsif ($input->{'handle'}) {
    $self->{'handle'} = $input->{'handle'};
    $self->{'name'} = $self->{'handleMap'}{$self->{'handle'}}{'name'};
    $self->{'id'}   = $self->{'handleMap'}{$self->{'handle'}}{'id'};
  }
}

sub _loadServices {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $result = $dbs->fetchallOrDie('pnpmisc',q/
    SELECT id, name, handle
      FROM service
  /, [],{});

  my $data = $result->{'result'};

  my %idMap = map { $_->{'id'} => $_ } @{$data};
  my %handleMap = map { $_->{'handle'} => $_ } @{$data};

  # create a map of id to info, and handle to info
  $self->{'idMap'} = \%idMap;
  $self->{'handleMap'} = \%handleMap;
}

sub getId {
  my $self = shift;
  return $self->{'id'};
}

sub getName {
  my $self = shift;
  return $self->{'name'};
}

sub getHandle {
  my $self = shift;
  return $self->{'handle'};
}

sub getServiceIdList {
  my $self = shift;

  if (!defined $self->{'idMap'}) {
    $self->_loadServices();
  }

  return $self->{'idMap'};
}

sub getServiceHandleList {
  my $self = shift;

  if (!defined $self->{'handleMap'}) {
    $self->_loadServices();
  }

  return $self->{'handleMap'};
}





1;
