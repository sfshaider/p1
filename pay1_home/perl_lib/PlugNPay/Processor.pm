package PlugNPay::Processor;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::Cache::LRUCache;
use PlugNPay::Processor::Package;

our $_processorIDCache;
our $_processorShortNameIDMap;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  # load the shortName => id mappings if not already loaded.
  if (!defined $_processorShortNameIDMap) {
    &loadProcessorShortNameIDMap();
  }

  if (!defined $_processorIDCache) {
    $_processorIDCache = new PlugNPay::Util::Cache::LRUCache(2);
  }


  my $settings = shift;

  if (defined $settings && ref($settings) eq 'HASH') {
    my $id;

    if (defined $settings->{'id'}) {
      $id = $settings->{'id'};
    } elsif (defined $settings->{'shortName'}) {
      $id = $_processorShortNameIDMap->{$settings->{'shortName'}};
    }

    if (defined $id) {
      $self->_load($id);
    }
  }

  return $self;
}

sub setShortName {
  my $self = shift;
  my $shortName = shift;
  $self->{'processorData'}{'shortName'} = $shortName;
}

sub getShortName {
  my $self = shift;
  return $self->{'processorData'}{'shortName'};
}

sub setCodeHandle {
  my $self = shift;
  my $handle = shift;
  $self->{'handle'} = $handle;
}

sub getCodeHandle {
  my $self = shift;
  return $self->{'handle'};
}

sub setName {
  my $self = shift;
  my $name = shift;
  $self->{'processorData'}{'name'} = $name;
}

sub getName {
  my $self = shift;
  return $self->{'processorData'}{'name'};
}

sub setID {
  my $self = shift;
  my $id = shift;
  $self->{'processorData'}{'id'} = $id;
}

sub getID {
  my $self = shift;
  return $self->{'processorData'}{'id'};
}

sub setProcessorType {
  my $self = shift;
  my $type = shift;
  $self->{'processorData'}{'type'} = $type;
}

sub getProcessorType {
  my $self = shift;
  return $self->{'processorData'}{'type'};
}

sub loaded {
  my $self = shift;
  return $self->{'loaded'};
}

sub valid {
  my $self = shift;
  if (!$self=>{'loaded'}) {
    $self->_load();
  }
  return $self->{'loaded'} ? 1 : 0;
}

sub forceLoad {
  my $self = shift;
  $self->{'forceLoad'} = 1;
}

sub setSettingsTableName {
  my $self = shift;
  my $tableName = shift;
  $tableName =~ s/[^a-z_]//g;
  $self->{'processorData'}{'settingsTableName'} = $tableName;
}

sub getSettingsTableName {
  my $self = shift;
  return $self->{'processorData'}{'settingsTableName'};
}

sub setUsesUnifiedTable {
  my $self = shift;
  my $isUnified = shift;
  $self->{'processorData'}{'usesUnifiedProcessorTable'} = $isUnified;
}

sub getUsesUnifiedTable {
  my $self = shift;
  return $self->{'processorData'}{'usesUnifiedProcessorTable'};
}

sub setStatus {
  my $self = shift;
  my $status = shift;
  $self->{'processorData'}{'status'} = $status;
}

sub getStatus {
  my $self = shift;
  return $self->{'processorData'}{'status'};
}

sub setForceAuthAllowed {
  my $self = shift;
  my $allowed = shift;
  $self->{'processorData'}{'forceAuthAllowed'} = ($allowed ? 1 : 0);
}

sub getForceAuthAllowed {
  my $self = shift;
  return ($self->{'processorData'}{'forceAuthAllowed'} ? 1 : 0);
}

sub setReauthAllowed {
  my $self = shift;
  my $allowed = shift;
  $self->{'processorData'}{'reAuthAllowed'} = ($allowed ? 1 : 0);
}

sub getReauthAllowed {
  my $self = shift;
  return ($self->{'processorData'}{'reAuthAllowed'} ? 1 : 0);
}

sub setDCCCapable {
  my $self = shift;
  my $capable = shift;
  $self->{'processorData'}{'dccCapable'} = ($capable ? 1 : 0);
}

sub getDCCCapable {
  my $self = shift;
  return ($self->{'processorData'}{'dccCapable'} ? 1 : 0);
}

sub setMultiCurrencyCapable {
  my $self = shift;
  my $capable = shift;
  $self->{'processorData'}{'multiCurrencyCapable'} = ($capable ? 1 : 0);
}

sub getMultiCurrencyCapable {
  my $self = shift;
  return ($self->{'processorData'}{'multiCurrencyCapable'} ? 1 : 0);
}

sub setBatchDetailTableName {
  my $self = shift;
  my $table = shift;
  $self->{'processorData'}{'batchDetailTable'} = $table;
}

sub getBatchDetailTableName {
  my $self = shift;
  return $self->{'processorData'}{'batchDetailTable'};
}

sub setSupportsCustomSweepTime {
  my $self = shift;
  my $supports = shift;
  $self->{'processorData'}{'supportsCustomSweepTime'} = ($supports ? 1 : 0);
}

sub getSupportsCustomSweepTime {
  my $self = shift;
  return $self->{'processorData'}{'supportsCustomSweepTime'};
}

sub setAuthorizationInfoLocation {
  my $self = shift;
  my $location = shift;
  $self->{'processorData'}{'authorizationInfoLocation'} = $location;
}

sub getAuthorizationInfoLocation {
  my $self = shift;
  return $self->{'processorData'}{'authorizationInfoLocation'};
}

sub setUsesCustomersMID {
  my $self = shift;
  my $uses = shift;
  $self->{'processorData'}{'usesCustomersMID'} = ($uses ? 1 : 0);
}

sub getUsesCustomersMID {
  my $self = shift;
  return ($self->{'processorData'}{'usesCustomersMID'} ? 1 : 0);
}

sub setUsesCustomersTID {
  my $self = shift;
  my $uses = shift;
  $self->{'processorData'}{'usesCustomersTID'} = ($uses ? 1 : 0);
}

sub getUsesCustomersTID {
  my $self = shift;
  return ($self->{'processorData'}{'usesCustomersTID'} ? 1 : 0);
}

sub setUsesCustomersRetailFlag {
  my $self = shift;
  my $uses = shift;
  $self->{'processorData'}{'usesCustomersRetailFlag'} = ($uses ? 1 : 0);
}

sub getUsesCustomersRetailFlag {
  my $self = shift;
  return ($self->{'processorData'}{'usesCustomersRetailFlag'} ? 1 : 0);
}

sub setUsesCustomersAuthType {
  my $self = shift;
  my $uses = shift;
  $self->{'processorData'}{'usesCustomersAuthType'} = ($uses ? 1 : 0);
}

sub getUsesCustomersAuthType {
  my $self = shift;
  return ($self->{'processorData'}{'usesCustomersAuthType'} ? 1 : 0);
}

sub setUsesCustomersCurrency {
  my $self = shift;
  my $uses = shift;
  $self->{'processorData'}{'usesCustomersCurrency'} = ($uses ? 1 : 0);
}

sub getUsesCustomersCurrency {
  my $self = shift;
  return ($self->{'processorData'}{'usesCustomersCurrency'} ? 1 : 0);
}

sub setSECCodeStorageType {
  my $self = shift;
  my $type = shift;
  $self->{'processorData'}{'secCodeStorageType'} = $type;
}

sub getSECCodeStorageType {
  my $self = shift;
  return $self->{'processorData'}{'secCodeStorageType'};
}

sub setAllowsEMV {
  my $self = shift;
  my $allows = shift;
  $self->{'processorData'}{'allows_emv'} = ($allows ? 1 : 0);
}

sub getAllowsEMV {
  my $self = shift;
  return ($self->{'processorData'}{'allows_emv'} ? 1 : 0);
}

sub setAllowsDuplicateMID {
  my $self = shift;
  my $allows = shift;
  $self->{'processorData'}{'allowsDuplicateMID'} = $allows;
}

sub getAllowsDuplicateMID {
  my $self = shift;
  return $self->{'processorData'}{'allowsDuplicateMID'};
}

sub setUsesPnpTransaction {
  my $self = shift;
  my $uses = shift;
  $self->{'processorData'}{'usesPnpTransaction'} = $uses ? 1 : 0;
}

sub getUsesPnpTransaction {
  my $self = shift;
  return $self->{'processorData'}{'usesPnpTransaction'};
}

sub setUsesPnpData {
  my $self = shift;
  my $uses = shift;
  $self->{'processorData'}{'usesPnpData'} = $uses ? 1 : 0;
}

sub getUsesPnpData {
  my $self = shift;
  return $self->{'processorData'}{'usesPnpData'};
}

sub processorList {
  my $options = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT processor,name,type,status,display,allows_emv
    FROM processor
  /);

  $sth->execute();

  my $result = $sth->fetchall_arrayref({});

  my $info = [];

  if ($result) {
    foreach my $row (@{$result}) {
      my $processor = $row->{'processor'};
      my $name = $row->{'name'};
      my $type = $row->{'type'};
      my $status = $row->{'status'};
      my $allowsEMV = $row->{'allows_emv'};

      if ($options->{'display'}) { #If the caller wants only active processors
        my $shouldDisplay = $row->{'display'};
        if ($shouldDisplay) { #If active
          push @{$info},{'shortName'=>$processor,name=>$name,type=>$type, shouldDisplay => $shouldDisplay, status => $status, allowsEMV => $allowsEMV};
        }
      } else {
        push @{$info},{'shortName'=>$processor,name=>$name,type=>$type,allowsEMV=>$allowsEMV};
      }
    }
  }

  my $type = $options->{'type'};
  if (defined $type) {
    my @processorsThatMatch;
    foreach my $processor (@{$info}) {
      if ($processor->{'type'} eq $type) {
        push @processorsThatMatch,$processor;
      }
    }
    $info = \@processorsThatMatch;
  }

  my $status = $options->{'status'};
  if (defined $status) {
    # turn a single status into an array ref with that status as it's only element
    if (ref $status eq '') {
      $status = [$status];
    }
    my @processorsThatMatch;
    foreach my $processor (@{$info}) {
      foreach my $possibleStatus (@{$status}) {
        if (lc $processor->{'status'} eq lc $possibleStatus) {
          push @processorsThatMatch,$processor;
        }
      }
    }
    $info = \@processorsThatMatch;
  }

  return $info;
}

sub _load {
  my $self = shift;
  $self->{'loaded'} = 0;
  my $id = shift || $self->getID();

  if (!$self->{'forceLoad'} && $_processorIDCache->contains($id)) {
    $self->{'processorData'} = $_processorIDCache->get($id);
    $self->{'loaded'} = 1;
  } else {
    # was not in cache or forceLoad was true, load from db
    $self->{'forceLoad'} = 0;
    my $dbs = new PlugNPay::DBConnection();
    my $query = q/
      SELECT id,processor,code_handle,name,type,settings_table_name,status,
             force_auth_allowed,reauth_allowed,dcc,multicurrency,
             batch_detail_table,authorization_info_location,supports_sweeptime,
             uses_customers_mid,uses_customers_tid,uses_customers_retail_flag,
             uses_customers_auth_type,uses_customers_currency,sec_code_storage,
             uses_unified_processor_table,allows_emv,allows_duplicate_mid,
             uses_pnp_transaction,uses_pnpdata
        FROM processor
       WHERE id = ?
    /;
    my $sth = $dbs->prepare('pnpmisc',$query);

    $sth->execute($id);

    my $result = $sth->fetchall_arrayref({});

    if ($result && $result->[0]) {
      $self->_setDataFromHashRef($result->[0]);
      $_processorIDCache->set($id,$self->{'processorData'});
      $self->{'loaded'} = 1;
    }
  }
}

sub _setDataFromHashRef {
  my $self = shift;
  my $hashRef = shift;

  if ($hashRef) {
    $self->setID($hashRef->{'id'});
    $self->setShortName($hashRef->{'processor'});
    $self->setCodeHandle($hashRef->{'code_handle'});
    $self->setName($hashRef->{'name'});
    $self->setProcessorType($hashRef->{'type'});
    $self->setStatus($hashRef->{'status'});
    $self->setSettingsTableName($hashRef->{'settings_table_name'});
    $self->setForceAuthAllowed($hashRef->{'force_auth_allowed'});
    $self->setReauthAllowed($hashRef->{'reauth_allowed'});
    $self->setMultiCurrencyCapable($hashRef->{'multicurrency'});
    $self->setDCCCapable($hashRef->{'dcc'});
    $self->setBatchDetailTableName($hashRef->{'batch_detail_table'});
    $self->setAuthorizationInfoLocation($hashRef->{'authorization_info_location'});
    $self->setSupportsCustomSweepTime($hashRef->{'supports_sweeptime'});
    $self->setUsesCustomersMID($hashRef->{'uses_customers_mid'});
    $self->setUsesCustomersTID($hashRef->{'uses_customers_tid'});
    $self->setUsesCustomersRetailFlag($hashRef->{'uses_customers_retail_flag'});
    $self->setUsesCustomersAuthType($hashRef->{'uses_customers_auth_type'});
    $self->setUsesCustomersCurrency($hashRef->{'uses_customers_currency'});
    $self->setSECCodeStorageType($hashRef->{'sec_code_storage'});
    $self->setUsesUnifiedTable($hashRef->{'uses_unified_processor_table'});
    $self->setAllowsEMV($hashRef->{'allows_emv'});
    $self->setAllowsDuplicateMID($hashRef->{'allows_duplicate_mid'});
    $self->setUsesPnpTransaction($hashRef->{'uses_pnp_transaction'});
    $self->setUsesPnpData($hashRef->{'uses_pnpdata'});
  }
}

sub loadProcessorShortNameIDMap {
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT processor,id FROM processor
  /);

  $sth->execute();

  my $result = $sth->fetchall_arrayref({});

  if ($result) {
    my %mapping = map { $_->{'processor'} => $_->{'id'} } @{$result};
    $_processorShortNameIDMap = \%mapping;
  }
}

sub usesUnifiedProcessing {
  my $self = shift;
  my $processor = lc shift;
  my $payType = lc shift;

  if (ref($self) ne 'PlugNPay::Processor') {
    $payType = $processor;
    $processor = $self;
    $self = new PlugNPay::Processor({'shortName' => $self});
  }

  if (!$processor) {
    $processor = $self->getCodeHandle();
  }

  if (!$payType) {
    my $payType = lc $self->getProcessorType();
  }

  $payType = ($payType eq 'card' ? 'credit' : $payType);
  my $packageRouter = new PlugNPay::Processor::Package();
  my $package = $packageRouter->getProcessorPackage($processor, $payType);

  return $package eq 'PlugNPay::Processor::Route';
}

sub reload {
  my $self = shift;
  $self->forceLoad();
  $self->_load();
}

1;
