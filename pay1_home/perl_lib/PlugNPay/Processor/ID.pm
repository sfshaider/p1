package PlugNPay::Processor::ID;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::Cache::LRUCache;

our $idCache;
our $processorCache;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  if (!defined $idCache || !defined $processorCache) {
    $idCache = new PlugNPay::Util::Cache::LRUCache(10);
    $processorCache = new PlugNPay::Util::Cache::LRUCache(10);
  }
  $self->{'processor_id'} = {};

  return $self;
}

sub getProcessorID {
  my $self = shift;
  my $processorName = shift;
  if ($processorName =~ /^\d+$/ && defined $self->getProcessorName($processorName)) {
    return $processorName; #If you send the processorID instead of processor name
  }

  unless($processorCache->contains($processorName)) {
    $self->loadProcessor($processorName,'processor');
  }

  return $processorCache->get($processorName);
}

sub loadProcessor {
  my $self = shift;
  my $value = shift;
  my $mode = lc shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/ 
                           SELECT id, code_handle
                           FROM processor
                           WHERE / . ($mode eq 'processor' ? ' code_handle = ? ' : ' id = ? '));
  $sth->execute($value) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my $id = $rows->[0]{'id'};
  my $processor = $rows->[0]{'code_handle'};

  if ($id && defined $processor) {
    $self->_addToCaches($id,$processor);
  }
}

sub getProcessorName {
  my $self = shift;
  my $id = shift;
  if ($id !~ /^\d+$/ && defined $self->getProcessorID($id)) {
    return $id; #send name instead of ID
  }

  unless($idCache->contains($id)) {
    $self->loadProcessor($id,'id');
  }

  return $idCache->get($id);
}

#These are to get the ID from the new DB only!! Situational, yet necessary...
sub generateProcessorReferenceID {
  my $self = shift;
  my $processor = lc shift;
  my $processorID = $self->getProcessorID($processor);

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/ 
            INSERT INTO processor
            (id,processor_code_handle)
            VALUES (?,?) /);
  $sth->execute($processorID,$processor) or die $DBI::errstr;

  $self->loadProcessorReferenceIDs();

  return $self->getProcessorReferenceID($processor);
}

sub getProcessorReferenceID {
  my $self = shift;
  my $processor = lc shift;

  my %reverseHash = reverse %{$self->{'processor_id'}};
  unless (defined $reverseHash{$processor}) {
    $self->loadProcessorReferenceIDs();
    %reverseHash = reverse %{$self->{'processor_id'}};
  }

  unless (defined $reverseHash{$processor}) {
    return $self->_insertNewProcessor($processor);
  } else {
    return $reverseHash{$processor};
  }
}

sub loadProcessorReferenceIDs {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/SELECT id,processor_code_handle
                            FROM processor/);
  $sth->execute() or die $DBI::errstr;

  my $rows = $sth->fetchall_arrayref({});
  my $ids = {};

  foreach my $row (@{$rows}) {
    $ids->{$row->{'id'}} = $row->{'processor_code_handle'};
  }

  $self->{'processor_id'} = $ids;
}

sub getProcessorFromReferenceID {
  my $self = shift;
  my $id = shift;

  unless (defined $self->{'processor_id'}{$id}) {
    $self->loadProcessorReferenceIDs();
  }

  return $self->{'processor_id'}{$id};
}

sub _insertNewProcessor {
  my $self = shift;
  my $processor = shift;

  if ($self->getProcessorID($processor)) {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnp_transaction',q/
              INSERT INTO processor
              (processor_code_handle)
              VALUES (?)/);
    $sth->execute($processor) or die $DBI::errstr;
    return $sth->{'mysql_insertid'};
  } else {
    return undef; #You tried doing something naughty
  }
}

sub _addToCaches {
  my $self = shift;
  my $key = shift;
  my $value = shift;

  $idCache->set($key,$value);
  $processorCache->set($value,$key);
}

1;
