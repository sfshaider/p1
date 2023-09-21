package PlugNPay::Processor::Mode;

use strict;
use PlugNPay::Processor::ID;
use PlugNPay::DBConnection;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  $self->{'conditionData'} = {};

  my $processor = shift;
  if ($processor) {
    $self->setProcessor($processor);
    $self->loadConditions();
  }

  return $self;
}

sub setProcessor {
  my $self = shift;
  my $processor = shift;
  $self->{'processor'} = $processor;
  $self->loadConditions();
}

sub getProcessor {
  my $self = shift;
  return $self->{'processor'};
}

sub loadConditions {
  my $self = shift;
  my $processor = shift;

  if (!defined $processor) {
    $processor = $self->getProcessor();   
  }

  my $procIDLoader = new PlugNPay::Processor::ID();

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
            SELECT c.presence,c.condition_name, t.type, s.mode
            FROM processor_mode_condition c, processor_mode_condition_set s, processor_mode_condition_type t
            WHERE c.condition_set_id = s.id 
            AND t.id = c.condition_type_id 
            AND s.processor_id = ?
  /);
  $sth->execute($procIDLoader->getProcessorID($processor)) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});

  my $conditionHash = {};
  foreach my $row (@{$rows}) {
    my $mode = lc($row->{'mode'});
    if (ref($conditionHash->{$mode}) eq 'ARRAY') {
      push @{$conditionHash->{$mode}}, $row;
    } else {
      $conditionHash->{$mode} = [$row];
    }
  }
}

sub setConditionData {
  my $self = shift;
  my $mode = lc shift;
  my $rules = shift;
  $self->{'conditionData'}{$mode} = $rules;
}

sub getConditionData {
  my $self = shift;
  my $mode = lc shift;

  return $self->{'conditionData'}{$mode};
}

sub evaluateConditions {
  my $self = shift;
  my $mode = lc shift;
  my $data = shift;

  my $conditions = $self->getConditionData($mode);
  if (!defined $conditions || ref($conditions) ne 'ARRAY' || (@{$conditions} == 0 && defined $self->getProcessor())) {
    $self->loadConditions();
    $conditions = $self->getConditionData($mode);
  }

  my $isSatisfied = 1;
  if (ref($conditions) ne 'ARRAY' || @{$conditions} == 0) {
    return 0;
  } else {
    foreach my $condition (@{$conditions}) {
      my $exists = 0;
      if ($condition->{'type'} eq 'transflag') {
        $exists = $data->{'transflags'} =~ /$condition->{'condition_name'}/;
      } elsif ($condition->{'type'} eq 'parameter') {
        $exists = $data->{$condition->{'condition_name'}};
      }

      if (($condition->{'presence'} && $exists) || (!$condition->{'presence'} && !$exists)) {
        $isSatisfied *= 1;
      } else {
        $isSatisfied *= 0;
      }
    }

    return $isSatisfied;
  }
}

1;
