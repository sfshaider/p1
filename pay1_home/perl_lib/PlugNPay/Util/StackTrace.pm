package PlugNPay::Util::StackTrace;

use strict;

sub new {
  my $class = shift;
  my $self = {};
  my $offset = shift || 0;

  # offset can not be negative
  $offset = 0 if ($offset < 0);

  my $i = 1 + $offset;
  my @trace;

  while ( (my @call_details = (caller($i++))) ){
    my %modData;

    my @modA = split('::', $call_details[3]);
    $modData{'called'}{'sub'} = pop(@modA);
    $modData{'called'}{'package'} = join('::', @modA);
    $modData{'called'}{'data'} = "$modData{'called'}{'package'}:$modData{'called'}{'sub'}";

    $modData{'caller'}{'line'} = $call_details[2];
    $modData{'caller'}{'package'} = $call_details[0];
    $modData{'caller'}{'data'} = "$modData{'caller'}{'package'}:$modData{'caller'}{'line'}";

    push @trace, $modData{'called'}{'data'} . " called from " . $modData{'caller'}{'data'};
  }

  $self->{'trace'} = \@trace;

  bless $self,$class;
  return $self;
}

sub string {
  my $self = shift;
  my $separator = shift || "\n";
  return join($separator,@{$self->{'trace'}});
}

sub arrayRef {
  my $self = shift;
  my @copy = @{$self->{'trace'}};
  return \@copy;
}

1;
