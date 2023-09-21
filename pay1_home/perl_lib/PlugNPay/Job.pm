package PlugNPay::Job;

use strict;
use PlugNPay::DBConnection;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub setID {
  my $self = shift;
  $self->{'id'} = shift;
}

sub getID {
  my $self = shift;
  return $self->{'id'};
}

sub setName {
  my $self = shift;
  $self->{'name'} = shift;
}

sub getName {
  my $self = shift;
  return $self->{'name'};
}

sub setPath {
  my $self = shift;
  my $path = shift;
  $path =~ s/\.\.\///g;
  $self->{'path'} = $path;
}

sub getPath {
  my $self = shift;
  return $self->{'path'};
}

sub load {
  my $self = shift;

  eval {
    my $dbs = new PlugNPay::DBConnection();
  
    my $sth = $dbs->prepare('pnpmisc',q/
      SELECT id,name,path
        FROM job
       WHERE (id = ? and ? IS NULL) OR (name = ? AND ? IS NULL)
    /) or die($DBI::errstr);

    $sth->execute($self->{'id'},$self->{'name'},$self->{'name'},$self->{'id'}) or die($DBI::errstr);

    my $result = $sth->fetchall_arrayref({}) or die($DBI::errstr);

    my $row = $result->[0];

    if ($row) {
      $self->setID($row->{'id'});
      $self->setName($row->{'name'});
      $self->setPath($row->{'path'});
    } else {
      die('Failed to find a matching job job.')
    }
  };
    
  if ($@) {
    die('Failed to load job (' . $self->{'name'} . ').');
  }
}

sub save {
  my $self = shift;

  eval {
    my $dbs = new PlugNPay::DBConnection();

    my $sth = $dbs->prepare('pnpmisc',q/
      INSERT INTO job (name,path)
        VALUES (?,?)
        ON DUPLICATE KEY UPDATE
          path = VALUES(path)
    /) or die($DBI::errstr);

    $sth->execute($self->getName(),$self->getPath()) or die($DBI::errstr);
  };

  if ($@) {
    die('Failed to save job job.');
  }
}

sub rename {
  my $self = shift;
  my $newName = shift;

  eval {
    my $dbs = new PlugNPay::DBConnection();

    my $sth = $dbs->prepare('pnpmisc',q/
      UPDATE job SET name = ? WHERE name = ?
    /) or die($DBI::errstr);

    $sth->execute($newName, $self->getName()) or die($DBI::errstr);

    $self->setName($newName);
  };

  if ($@) {
    die('Failed to rename job job.');
  }
}

sub execute {
  my $self = shift;

  my $basePath = '/home/pay1/jobs/';

  my $path = $self->getPath();

  $path = $basePath . '/' . $path;

  my $error;
  my $job;
  my $buffer;

  open($job,'<',$path);
  sysread $job, $buffer, -s $job;
  close($job);

  if ($buffer eq '') {
    $error = 'Cowardly failing to run an empty job.';
  }

  eval($buffer);

  return $error || $@;
}

1;
