package PlugNPay::Processor::Settings::SECCodes;

use strict;
use PlugNPay::Logging::ApacheLogger;
use PlugNPay::DBConnection;
use PlugNPay::Processor;
use PlugNPay::SECCode;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $data = shift;

  if (defined $data->{'gatewayAccount'}) {
    $self->setGatewayAccount($data->{'gatewayAccount'});
  }

  if (defined $data->{'processorID'}) {
    $self->setProcessorID($data->{'processorID'});
  }

  $self->{'delete_array'} = [];

  return $self;
}

sub setGatewayAccount {
  my $self = shift;
  my $account = shift;
  if (defined $account) {
    # if gateway account is set as object, use it's string override by concatenating an empty string.
    $self->{'gatewayAccount'} = $account . '';
    $self->load();
  }
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

sub setProcessorID {
  my $self = shift;
  my $id = shift;
  $self->{'processorID'} = $id;
  $self->load();
}

sub getProcessorID {
  my $self = shift;
  return $self->{'processorID'};
}

sub getSECCodes {
  my $self = shift;
  my @codes = keys %{$self->{'codes'}};
  return \@codes;
}

sub getTIDForSECCode {
  my $self = shift;
  my $code = shift;
  my $processor = new PlugNPay::Processor({id => $self->getProcessorID()});
  return $self->{'codes'}{$code} || $processor->getTID();
}

sub addSECCode {
  my $self = shift;
  my $code = shift;
  my $tid = shift;
  my $secCode = new PlugNPay::SECCode();
  if ($secCode->isValid($code)) {
    $self->{'codes'}{$code} = $tid;
  } else {
    die('Invalid SEC code: ' . $code);
  }
}

sub deleteSECCode {
  my $self = shift;
  my $code = shift;
  delete $self->{'codes'}{$code};
  push @{$self->{'delete_array'}},$code;
}

sub save {
  my $self = shift;

  my $processor = new PlugNPay::Processor({id => $self->getProcessorID()});

  my $storageType = $processor->getSECCodeStorageType();

  if ($storageType eq 'array') {
    $self->saveArray();
  } elsif ($storageType eq 'hash') {
    $self->saveHash();
  } elsif ($storageType eq 'table') {
    $self->saveTable();
  }
}

sub load {
  my $self = shift;

  if (!$self->getProcessorID() || !$self->getGatewayAccount()) {
    return;
  } 

  my $processor = new PlugNPay::Processor({id => $self->getProcessorID()});

  my $storageType = $processor->getSECCodeStorageType();

  if ($storageType eq 'array') {
    $self->loadArray();
  } elsif ($storageType eq 'hash') {
    $self->loadHash();
  } elsif ($storageType eq 'table') {
    $self->loadTable();
  }
}

sub saveArray {
  my $self = shift;

  my @codes = keys %{$self->{'codes'}};
  my $value = join(',',@codes);
  $self->_saveSECCodeField($value);
}

sub saveHash {
  my $self = shift;

  my @codesAndTIDs = %{$self->{'codes'}};
  my $value = join(',',@codesAndTIDs);
  $self->_saveSECCodeField($value);
}

sub _saveSECCodeField {
  my $self = shift;
  my $value = shift;

  my $processor = new PlugNPay::Processor({id => $self->getProcessorID()});
  if ($processor->getUsesUnifiedTable()) {
    my @splitValues = split(',',$value);
    $self->_saveUnifiedSECCodes(\@splitValues);
  } else {
    $self->_saveLegacySECCodeField($value,$processor);
  }
}

sub _saveLegacySECCodeField {
  my $self = shift;
  my $value = shift;
  my $processor = shift;

  my $processorTable = $processor->getSettingsTableName();
  $processorTable =~ s/[^a-zA-Z0-9_]//g;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc','
    UPDATE ' . $processorTable . ' 
       SET seccodes = ? 
     WHERE username = ?
  ');

  $sth->execute($value,$self->getGatewayAccount());
}

sub loadArray {
  my $self = shift;

  my $secCodeString = $self->_loadSECCodeField();

  my %codes = map { $_ => undef } split(/,/,$secCodeString);
  $self->{'codes'} = \%codes;
}

sub loadHash {
  my $self = shift;

  my $secCodeString = $self->_loadSECCodeField();

  my %codes = split(/,/,$secCodeString);
  $self->{'codes'} = \%codes;
}

sub _loadSECCodeField {
  my $self = shift;

  my $processor = new PlugNPay::Processor({id => $self->getProcessorID()});
  if ($processor->getUsesUnifiedTable()) {
    my $array = $self->_loadUnifiedSECCodes();
    return join(',',@{$array});
  } else {
    return $self->_loadLegacySECCodeField($processor);
  }
}

sub _loadLegacySECCodeField {
  my $self = shift;
  my $processor = shift;
  
  my $processorTable = $processor->getSettingsTableName();

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc','
    SELECT seccodes 
      FROM ' . $processorTable . ' 
     WHERE username = ?
  ');

  $sth->execute($self->getGatewayAccount());

  my $result = $sth->fetchall_arrayref({});

  my $secCodeString = '';

  if ($result && $result->[0]) {
    $secCodeString = $result->[0]{'seccodes'};
  }

  return $secCodeString;
}


###############################
# Unified Processor Functions #
###############################
sub _saveUnifiedSECCodes{
  my $self = shift;
  my $codes = shift;

  my $dbs = new PlugNPay::DBConnection();
  $dbs->prepare('pnpmisc');
  eval {
    my $codeIDs = $self->loadSECCodeIDs($codes);
    my $username = $self->getGatewayAccount();
    my @values = ();
    foreach my $codeID (@{$codeIDs}) {
      push @values,$codeID;
      push @values,$username;
    }
    my $sth = $dbs->prepare('pnpmisc',q/
            INSERT IGNORE INTO customer_sec_code_account
            (sec_code_id,username)
            VALUES / . join(',', map{'(?,?)'} @{$codes}));
    $sth->execute(@values) or die $DBI::errstr;
    $self->deleteUnifiedSECCodes();
  };
  
  if ($@) {
    my $logger = new PlugNPay::Logging::ApacheLogger();
    $dbs->rollback('pnpmisc');
    $logger->log('An error has occurred while saving SEC codes: ' . $@);
    return 0;
  } else {
    $self->{'delete_array'} = [];
    $dbs->commit('pnpmisc');
    return 1;
  }
}

sub deleteUnifiedSECCodes {
  my $self = shift;
  my $codes = $self->{'delete_array'};
  if (@{$codes} == 0) {
    return 1;
  }

  my $username = $self->getGatewayAccount();

  my $dbs = new PlugNPay::DBConnection();
  my $codeIDs = $self->loadSECCodeIDs($codes);
  my $sth = $dbs->prepare('pnpmisc',q/
       DELETE FROM customer_sec_code_account
       WHERE username = ? AND sec_code_id IN (/ . join(',',map{'?'} @{$codeIDs}) . ')');
  $sth->execute($username,$codeIDs) or die $DBI::errstr;
}

sub _loadUnifiedSECCodes {
  my $self = shift;
  my $username = $self->getGatewayAccount();
  my $dbs = new PlugNPay::DBConnection();
  my @codeList = ();
  eval {
    my $sth = $dbs->prepare('pnpmisc',q/
       SELECT s.code
       FROM sec_code s, customer_sec_code_account a
       WHERE a.username = ?
       AND s.id = a.sec_code_id
       /);
    $sth->execute($username) or die $DBI::errstr;
    my $rows = $sth->fetchall_arrayref({});
    foreach my $row (@{$rows}) {
      push @codeList,$row->{'code'};
    }
  };
 
  if ($@) {
    my $logger = new PlugNPay::Logging::ApacheLogger();
    $logger->log('Unable to load SEC codes, an error occurred: ' . $@);
  }

  return \@codeList;
}

sub loadSECCodeIDs {
  my $self = shift;
  my $codeNames = shift;
  if (ref($codeNames) ne 'ARRAY') {
    $codeNames = [$codeNames];
  }

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
            SELECT id,code
            FROM sec_code
            WHERE / . join(' OR ', map { ' code = ? '} @{$codeNames}));
  $sth->execute(@{$codeNames}) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my @idList = ();
  foreach my $row (@{$rows}) {
    push @idList,$row->{'id'};
  }

  return \@idList;
}

sub loadUnifiedTIDOverride {
  my $self = shift;
  my $code = shift;
  my $codeID = $self->loadSECCodeIDs($code)->[0];
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc', q/
            SELECT t.tid 
            FROM customer_sec_code_tid_override t, customer_sec_code_account a 
            WHERE a.sec_code_id = ?
            AND a.username = ?
            AND a.id = t.sec_code_account_id /);
  $sth->execute($codeID,$self->getGatewayAccount()) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  if (@{$rows} > 0) {
    return $rows->[0]{'tid'};
  } else {
    return undef;
  }
}

1;
