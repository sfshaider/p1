package PlugNPay::Logging::Performance;

use strict;
use Time::HiRes;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::UniqueID;

our $singleton = '';

sub new {
  my $class = shift;
  my $self;
  if ($singleton eq '') {
    $self = {};
    $self->{'requestID'} = new PlugNPay::Util::UniqueID()->inHex();
    $self->{'remoteAddress'} = $ENV{'REMOTE_ADDR'};
    $self->{'created'} = Time::HiRes::time();
    $singleton = $self;
  } else {
    $self = $singleton;
  }

  $self->{'start'} = Time::HiRes::time();

  bless $self,$class;


  if (!defined $self->{'entries'}) {
    $self->{'entries'} = [];
  }

  my $entry = $self->createEntry(shift);

  push @{$self->{'entries'}},$entry;

  return $self;
}

sub setCleanupHandler {
  my $self = shift;

  if (!exists $self->{'handlerSet'} && exists $ENV{'MOD_PERL'}) {
    # get a request object
    require Apache2::RequestUtil;
    my $r = Apache2::RequestUtil->request;

    # don't allow keepalive for requests that use Logging::Performance
    if (defined $r->connection()->keepalive) {
      $r->connection()->keepalive($Apache2::Const::CONN_CLOSE);
    }

    # add a call to the static method cleanup() as a PerlCleanupHandler
    my $selfType = ref($self);
    $r->push_handlers('PerlCleanupHandler' => eval "\&$selfType::write()");

    # remember that we've done this as if we don't, the call will be pushed
    # to the array over and over, and that means it'll be called as many times
    # as there have been requests for that thread....that's bad.
    $self->{'handlerSet'} = 1;
  }

  return $self;
}

sub addMetadata {
  my $self = shift;
  my $data = shift;

  eval {
    if (!defined $self->{'metadata'}) {
      $self->{'metadata'} = {};
    }

    foreach my $key (keys %{$data}) {
      $self->{'metadata'}{$key} = $data->{$key};
    }
  }
}

sub createEntry {
  my $self = shift;
  my $message = shift;
  my $now = Time::HiRes::time();
  my @location = caller(1);
 
  my $entry = {
    time => $now,
    delta => ($self->{'lastEntryTime'} ? ($now - $self->{'lastEntryTime'}) : 0),
    message => $message || '',
    location => $location[0] . ':line ' . $location[2]
  };

  $self->{'lastEntryTime'} = $now;

  return $entry;
}

sub DESTROY {
  my $self = shift;
  if ($singleton ne '') {
    $singleton->write();
  }
}

END {
  if ($singleton ne '') {
    $singleton->write();
  }
}

sub init {
  # name that makes sense for a specific use case
  flush();
}

sub write {
  # name that makes sense for a specific use case
  flush();
}

sub flush {
  if ($ENV{'PNP_PERFORMANCE_LOGGING'} eq 'TRUE' && $singleton ne '') {
    my $end = Time::HiRes::time();
    my $duration = $end - $singleton->{'start'};
    my $logEntry = {
      start => $singleton->{'start'},
      end => $end,
      duration => $duration,
      pid => $$,
      metadata => $singleton->{'metadata'},
      created => $singleton->{'created'},
      requestID => $singleton->{'requestID'},
      remoteAddress => $singleton->{'remoteAddress'},
      times => $singleton->{'entries'}
    };

    my $dataLog = new PlugNPay::Logging::DataLog({collection => 'performanceLogs'});
    $dataLog->log($logEntry);
    
    #Make singleton blank to prevent double write.
    $singleton = '';
  }
}

1;
