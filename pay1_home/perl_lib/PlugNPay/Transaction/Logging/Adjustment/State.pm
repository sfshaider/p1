package PlugNPay::Transaction::Logging::Adjustment::State;

use strict;
use JSON::XS;
use PlugNPay::Util::Hash;
use PlugNPay::DBConnection;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  return $self;
}

sub setGatewayAccount {
  my $self = shift;
  my $account = shift;
  $self->{'account'} = $account;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'account'};
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

# convenience adjustment mode (surcharge or separate)
sub setMode {
  my $self = shift;
  my $mode = shift;
  $self->{'mode'} = $mode;
  $self->clearDataHash();
}

sub getMode {
  my $self = shift;
  return $self->{'mode'};
}

# convenience adjustment bucket data
sub setBucketData {
  my $self = shift;
  my $data = shift;
  $self->{'bucketData'} = $data;
  $self->clearDataHash();
}

sub getBucketData {
  my $self = shift;
  return $self->{'bucketData'};
}

sub setBucketDataString {
  my $self = shift;
  my $dataString = shift;
  my $data = decode_json($dataString);
  $self->setBucketData($data);
}

sub getBucketDataString {
  my $self = shift;
  return encode_json($self->getBucketData());
}

# coa data
sub setCOAData {
  my $self = shift;
  my $data = shift;
  $self->{'coaData'} = $data;
  $self->clearDataHash();
}

sub getCOAData {
  my $self = shift;
  return $self->{'coaData'};
}

sub setCOADataString {
  my $self = shift;
  my $dataString = shift;
  my $data = decode_json($dataString);
  $self->setCOAData($data);
}

sub getCOADataString {
  my $self = shift;
  return encode_json($self->getCOAData());
}

# coa model
sub setModel {
  my $self = shift;
  my $model = shift;
  $self->{'model'} = $model;
  $self->clearDataHash();
}

sub getModel {
  my $self = shift;
  return $self->{'model'};
}

# coa formula
sub setFormula {
  my $self = shift;
  my $formula = shift;
  $self->{'formula'} = $formula;
  $self->clearDataHash();
}

sub getFormula {
  my $self = shift;
  return $self->{'formula'};
}

# data hash
sub createDataHash {
  my $self = shift;

  my $dataString = join('|',($self->getBucketDataString(),
                             $self->getCOADataString(),
                             $self->getFormula(),
                             $self->getMode(),
                             $self->getModel()));

  my $hasher = new PlugNPay::Util::Hash();
  $hasher->add($dataString);
  $self->setDataHash($hasher->sha1('0x'));
}

sub clearDataHash {
  my $self = shift;
  delete $self->{'dataHash'};
}

sub setDataHash {
  my $self = shift;
  my $dataHash = shift;
  $self->{'dataHash'} = $dataHash;
}

sub getDataHash {
  my $self = shift;
  if (!defined $self->{'dataHash'}) {
    $self->createDataHash();
  }
  return $self->{'dataHash'};
}

sub load {
  my $self = shift;

  if (defined $self->getID()) {
    $self->_loadByID();
  } elsif(defined $self->getGatewayAccount() && defined $self->getDataHash()) {
    $self->_loadByUsernameAndDataHash();
  }
}


sub _loadByID {
  my $self = shift;
  
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT id, username, bucket_data, coa_data, formula, mode, model
      FROM adjustment_log_state
     WHERE id = ?
  /);

  $sth->execute($self->getID());

  my $result = $sth->fetchall_arrayref({});
  if ($result && $result->[0]) {
    $self->setValuesFromRow($result->[0]);
  }
}

sub _loadByUsernameAndDataHash {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT id, username, bucket_data, coa_data, formula, mode, model
      FROM adjustment_log_state
     WHERE username = ? AND data_hash = ?
  /);

  $sth->execute($self->getGatewayAccount(),$self->getDataHash());

  my $result = $sth->fetchall_arrayref({});
  if ($result && $result->[0]) {
    $self->setValuesFromRow($result->[0]);
  }
}

sub setValuesFromRow {
  my $self = shift;
  my $row = shift;

  $self->setID($row->{'id'});
  $self->setGatewayAccount($row->{'username'});
  $self->setBucketData($row->{'bucekt_data'});
  $self->setCOAData($row->{'coa_data'});
  $self->setFormula($row->{'formula'});
  $self->setMode($row->{'mode'});
  $self->setModel($row->{'model'});
}

sub exists {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT count(id) as `exists`
      FROM adjustment_log_state
     WHERE username = ? and data_hash = ?
  /);

  $sth->execute($self->getGatewayAccount(), $self->getDataHash());

  my $result = $sth->fetchall_arrayref({});
  if ($result) {
    my $row = $result->[0];
    return $row->{'exists'};
  }
}

sub save {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    INSERT IGNORE
      INTO adjustment_log_state (username,data_hash,bucket_data,coa_data,formula,mode,model)
    VALUES (?,?,?,?,?,?,?)
  /);

  $sth->execute(
    $self->getGatewayAccount(),
    $self->getDataHash(),
    $self->getBucketDataString(),
    $self->getCOADataString(),
    $self->getFormula(),
    $self->getMode(),
    $self->getModel()
  );
}

1;
