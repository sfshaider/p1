package PlugNPay::Metrics;

use strict;
use Time::HiRes;

BEGIN {
  eval {
    require Net::Statsd;
  };
}

our $_host_;
our $_port_;

sub new {
  my $class = shift;
  my $self = {};

  initHostAndPort();

  bless $self,$class;
  return $self;
}

sub increment {
  my $self = shift;
  my $input = shift;

  $input->{'value'} = 1 if !defined $input->{'value'}; # default to 1

  checkMetric($input->{'metric'});
  checkValueUnsignedInt($input->{'value'});

  _increment($input);
}

sub _increment {
  my $input = shift;
  my $metric = 'pnp.' . $input->{'metric'};
  my $value = $input->{'value'};
  return if $value == 0;

  eval {
    Net::Statsd::update_stats($metric,$value);
  };
}

sub decrement {
  my $self = shift;
  my $input = shift;

  $input->{'value'} = 1 if !defined $input->{'value'}; # default to 1

  checkMetric($input->{'metric'});
  checkValueUnsignedInt($input->{'value'});

  _decrement($input);
}

sub _decrement {
  my $input = shift;
  my $metric = 'pnp.' . $input->{'metric'};
  my $value = $input->{'value'};
  return if $value == 0;

  eval {
    Net::Statsd::update_stats($metric,'-' . $value);
  };
}

sub gauge {
  my $self = shift;
  my $input = shift;

  checkMetric($input->{'metric'});
  checkValue($input->{'value'});

  _gauge($input);
}

sub _gauge {
  my $input = shift;
  my $metric = 'pnp.' . $input->{'metric'};
  my $value = $input->{'value'};

  eval {
    Net::Statsd::gauge($metric,$value);
  };
}

sub timing {
  my $self = shift;
  my $input = shift;

  checkMetric($input->{'metric'});
  checkValueUnsignedInt($input->{'value'});

  _timing($input);
}

sub timingStart {
  my $self = shift;
  return Time::HiRes::time();
}

sub timingEnd {
  my $self = shift;
  my $input = shift;

  my $start = $input->{'start'} || die('no start time passed to timingEnd');
  my $metric = $input->{'metric'};

  checkMetric($metric);

  my $duration = (Time::HiRes::time() - $start);

  _timing({
    metric => $metric,
    value => int($duration * 1000)
  });

  return $duration;
}

sub _timing {
  my $input = shift;
  my $metric = 'pnp.' . $input->{'metric'};
  my $value = $input->{'value'};

  eval {
    Net::Statsd::timing($metric,$value);
  };
}

sub checkMetric {
  my $metric = shift;
  if ($metric !~ /^[a-zA-Z0-9_]([a-zA-Z0-9_\.]*[a-zA-Z0-9_]+)*$/) {
    $metric =~ s/\n/\\n/g;
    die('bad metric name, only alphanumeric, underscore, and period permitted, and must not start or end with a period, input: ' . $metric);
  }
}

sub checkValue {
  my $value = shift;
  if ($value !~ /^[+-]?\d+(\.\d+)?$/) {
    die('value must be numeric');
  }
}

sub checkValueUnsignedInt {
  my $value = shift;
  if ($value !~ /^\d+$/) {
    die('value must be unsigned integer');
  }
}

sub clearCachedHostAndPort {
  $_host_ = undef;
  $_port_ = undef;
}

sub initHostAndPort {
  if (!defined $_host_ || !defined $_port_) {
    $_host_ = getHost();
    $_port_ = getPort();
  }

  $Net::Statsd::HOST = $_host_;
  $Net::Statsd::PORT = $_port_;
}

sub getHost() {
  # try env, parameter, or default, in that order.
  if ($ENV{'STATSD_HOST'}) {
    return $ENV{'STATSD_HOST'};
  }

  my $hostAndPort = getParameterStoreHostAndPort();
  if ($hostAndPort->{'host'}) {
    return $hostAndPort->{'host'};
  }

  return 'statsd.local';
}

sub getPort() {
  if ($ENV{'STATSD_PORT'}) {
    return $ENV{'STATSD_PORT'};
  }

  my $hostAndPort = getParameterStoreHostAndPort();
  if ($hostAndPort->{'port'}) {
    return $hostAndPort->{'port'};
  }

  return '8125';
}

sub getParameterStoreHostAndPort {
  my $value;
  eval {
    $value = PlugNPay::AWS::ParameterStoregetParameter('/STATSD/SERVER');
  };
  my ($host,$port) = split(/:/,$value);
  return {
    host => $host,
    port => $port
  };
}

1;
