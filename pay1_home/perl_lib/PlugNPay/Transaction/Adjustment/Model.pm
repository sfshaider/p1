package PlugNPay::Transaction::Adjustment::Model;

use strict;

use PlugNPay::DBConnection;

our $_modelData;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!defined $_modelData) {
    $self->_loadModelData();
  }

  my $id = shift;
  if ($id) {
    $self->setID($id);
    $self->_load();
  }

  return $self;
}

sub setID {
  my $self = shift;
  my $id = shift;
  $self->{'id'} = $id;
}

sub getID {
  my $self = shift;
  return $self->{'id'};
}

sub setModel {
  my $self = shift;
  my $model = shift;
  $self->{'model'} = $model;
}

sub getModel {
  my $self = shift;
  return $self->{'model'};
}

sub setLegacyModel {
  my $self = shift;
  my $model = shift;
  $self->{'legacyModel'} = $model;
}

sub getLegacyModel {
  my $self = shift;
  return $self->{'legacyModel'};
}

sub setModelTypeID {
  my $self = shift;
  my $modelTypeID = shift;
  $self->{'modelTypeID'} = $modelTypeID;
}

sub getModelTypeID {
  my $self = shift;
  return $self->{'modelTypeID'};
}

sub setFormula {
  my $self = shift;
  my $formula = shift;
  $self->{'formula'} = $formula;
}

sub getFormula {
  my $self = shift;
  return $self->{'formula'};
}

sub setEnabled {
  my $self = shift;
  my $enabled = shift;
  $self->{'enabled'} = $enabled;
}

sub getEnabled {
  my $self = shift;
  return $self->{'enabled'};
}

sub setName {
  my $self = shift;
  my $name = shift;
  $self->{'name'} = $name;
}

sub getName {
  my $self = shift;
  return $self->{'name'};
}

sub setDescription {
  my $self = shift;
  my $description = shift;
  $self->{'description'} = $description;
}

sub getDescription {
  my $self = shift;
  return $self->{'description'};
}

sub getAllRows {
  my $self = shift;

  return $_modelData;
}

sub getEnabledModels {
  my $self = shift;

  my @enabledModels;
  foreach my $model (@{$_modelData}) {
    if ($model->{'enabled'} == 1) {
      my $enabledModel = new ref($self);
      $enabledModel->load($model->{'id'});
      push @enabledModels, $enabledModel;
    }
  }

  return \@enabledModels;;
}

sub load {
  my $self = shift;
  my $id = shift;

  $self->setID($id);
  $self->_load();
}

sub _load {
  my $self = shift;

  foreach my $model (@{$_modelData}) {
    if ($self->getID() == $model->{'id'}) {
      $self->setID($model->{'id'});
      $self->setModel($model->{'model'});
      $self->setLegacyModel($model->{'legacy_model'});
      $self->setModelTypeID($model->{'model_type_id'});
      $self->setFormula($model->{'formula'});
      $self->setEnabled($model->{'enabled'});
      $self->setName($model->{'name'});
      $self->setDescription($model->{'description'});
      last;
    }
  }
}

sub _loadModelData {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection;
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT id,model,model_type_id,formula,legacy_model,enabled,name,description FROM adjustment_model
  /);

  $sth->execute();

  my $result = $sth->fetchall_arrayref({});

  if ($result) {
    my @modelData;
    foreach my $row (@{$result}) {
      my $model = {
        id => $row->{'id'},
        model => $row->{'model'},
        legacy_model => $row->{'legacy_model'},
        model_type_id => $row->{'model_type_id'},
        formula => $row->{'formula'},
        enabled => $row->{'enabled'},
        name => $row->{'name'},
        description => $row->{'description'},
      };
      push @modelData,$model;
    }
    $_modelData = \@modelData;
  }
}

1;
