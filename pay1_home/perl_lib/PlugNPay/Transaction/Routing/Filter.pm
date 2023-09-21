package PlugNPay::Transaction::Routing::Filter;

use strict;
use PlugNPay::DBConnection;

sub new {
  my $self = {};
  my $class = shift;
  bless $self, $class;

  return $self;
}

sub setFilterID {
  my $self = shift;
  my $id = shift;
  $self->{'filterID'} = $id;
}

sub getFilterID {
  my $self = shift;
  return $self->{'filterID'};
}

sub setFilter {
  my $self = shift;
  my $filter = shift;
  $self->{'filter'} = $filter;
}

sub getFilter {
  my $self = shift;
  return $self->{'filter'};
}

sub setMaster {
  my $self = shift;
  my $master = shift;
  $self->{'master'} = $master;
}

sub getMaster {
  my $self = shift;
  return $self->{'master'};
}

sub setUsername {
  my $self = shift;
  my $username = shift;
  $self->{'username'} = $username;
}

sub getUsername {
  my $self = shift;
  return $self->{'username'};
}

sub setParam {
  my $self = shift;
  my $param = shift;
  $self->{'param'} = $param;
}

sub getParam {
  my $self = shift;
  return $self->{'param'};
}

sub setWeight {
  my $self = shift;
  my $weight = shift;
  $self->{'weight'} = $weight;
}

sub getWeight {
  my $self = shift;
  return $self->{'weight'};
}

sub save {
  my $self = shift;

  my $dbh = new PlugNPay::DBConnection()->getHandleFor('tranrouting');
  my $sth = $dbh->prepare(q/
    INSERT INTO filters
    (filterid,filter,master,param,username,weight)
    VALUES (?,?,?,?,?,?)
  /);
  $sth->execute($self->getFilterID(),
                $self->getFilter(),
                $self->getMaster(),
                $self->getParam(),
                $self->getUsername(),
                $self->getWeight()) or die $DBI::errstr;

  return;
}

sub get {
  my $self = shift;

  my $dbh = new PlugNPay::DBConnection()->getHandleFor('tranrouting');
  my $sth = $dbh->prepare(q/
    SELECT filterid,master,filter,param,username,weight
    FROM filters
    WHERE master=?
    ORDER BY weight,filterid
  /);
  $sth->execute($self->{'master'}) or die $DBI::errstr;
  my $results = $sth->fetchall_arrayref({});

  return $results;
}

sub getAll {
  my $self = shift;

  my $dbh = new PlugNPay::DBConnection()->getHandleFor('tranrouting');
  my $sth = $dbh->prepare(q/
    SELECT filterid,master,filter,param,username,weight
    FROM filters
    ORDER BY weight,filterid
  /);
  $sth->execute() or die $DBI::errstr;
  my $results = $sth->fetchall_arrayref({});

  return $results;
}

sub delete {
  my $self = shift;

  if (($self->getFilterID() ne "") && ($self->getMaster() ne "")) {
    my $dbh = new PlugNPay::DBConnection()->getHandleFor('tranrouting');
    my $sth = $dbh->prepare(q/
        DELETE FROM filters
        WHERE filterid=?
        AND master=?
    /);
    $sth->execute($self->getFilterID(),$self->getMaster()) or die $DBI::errstr;
  }

  return;
}

1;
