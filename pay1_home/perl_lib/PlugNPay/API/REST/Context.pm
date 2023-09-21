package PlugNPay::API::REST::Context;

use strict;
use PlugNPay::DBConnection;

#
# INSERT INTO api_url_context (name) SELECT DISTINCT context FROM api_url;
# update api_url set context_id = (select id from api_url_context where api_url.context = api_url_context.name) 

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
  die('ID not set.') if (!defined $self->{'id'});
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

sub load {
  my $self = shift;

  my $id = $self->{'id'};
  my $name = $self->{'name'};

  eval {
    my $dbs = new PlugNPay::DBConnection();

    my $sth = $dbs->prepare('pnpmisc',q/
      SELECT id, name
        FROM api_url_context
       WHERE (id = ? AND ? IS NULL) OR (? IS NULL AND name = ?)
    /) or die($DBI::errstr);

    $sth->execute($id,$name,$id,$name) or die($DBI::errstr);

    my $results = $sth->fetchall_arrayref({}) or die ($DBI::errstr);

    if ($results && $results->[0]) {
      $self->setID($results->[0]{'id'});
      $self->setName($results->[0]{'name'});
    }
  };

  if ($@) {
    die('Failed to load API Context.');
  }
}

1;
