package PlugNPay::Reseller::Chain;

use strict;

use PlugNPay::DBConnection;

our $_parentMap;
our $_childrenMap;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!$_parentMap) {
    $self->_loadMappings();
  }

  my $reseller = shift;
  if ($reseller) {
    $self->setReseller($reseller);
  }

  return $self;
}

sub _loadMappings {
  if (!defined $_parentMap) {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnpmisc',q/
      SELECT username,salesagent FROM salesforce where username <> salesagent
    /);

    $sth->execute();

    my $result = $sth->fetchall_arrayref({});

    if ($result) {
      my %map = map { $_->{'username'} => $_->{'salesagent'} } @{$result};
      $_parentMap = \%map;

      my %parents ;# love me
      foreach my $child (keys %map) {
        my $parent = $map{$child};
        if ($child ne $parent) {
          if (!defined $parents{$parent}) {
            $parents{$parent} = [];
          }
          push @{$parents{$parent}},$child;
        }
      }
      $_childrenMap = \%parents;
    }
  }
}

sub setReseller {
  my $self = shift;
  my $reseller = shift;
  $self->{'reseller'} = $reseller;
}

sub getReseller {
  my $self = shift;
  return $self->{'reseller'};
}

sub getParent {
  my $self = shift;
  my $reseller = shift || $self->getReseller();

  my $parent = $_parentMap->{$reseller};

  if ($parent ne $reseller) {
    return $parent;
  }
}

sub getChildren {
  my $self = shift;
  my $reseller = shift || $self->getReseller();

  return $_childrenMap->{$reseller} || [];
}

sub getDescendants {
  my $self = shift;
  my $reseller = shift || $self->getReseller();

  my %log;
  my %subTree;
  
  if (@{$self->getChildren($reseller)}) {
    foreach my $child (@{$self->getChildren($reseller)}) {
      if ($log{$child}) {
        die('Reseller chain loop detected.'); 
      }
      $log{$child} = 1;

      $subTree{$child} = $self->getDescendants($child);
    }
  }

  return \%subTree;
}

sub hasDescendant {
  my $self = shift;
  my $descendant = shift;
  my $parent = shift || $self->getReseller();

  my $descendants = $self->getDescendants($parent);

  my $result = 0;

  foreach my $possibleDescendant (keys %{$descendants}) {
    if ($descendant eq $possibleDescendant) {
      $result = 1;
      last;
    } else {
      $result = $self->hasDescendant($descendant,$possibleDescendant);
      last if $result;
    }
  }

  return $result;
}

sub getAncestors {
  my $self = shift;
  my $reseller = shift || $self->getReseller();

  my @ancestors;
 
  my $parent = $self->getParent($reseller);
  if ($parent) {
    push @ancestors,$parent;
    push @ancestors,@{$self->getAncestors($parent)};
  }

  return \@ancestors;
}

1;
