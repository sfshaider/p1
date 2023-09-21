package PlugNPay::Processor::Settings;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::Cache::LRUCache;

our $_processorCache;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!defined $_processorCache) {
    $_processorCache = new PlugNPay::Util::Cache::LRUCache(5);
  }

  if ((my $processorID = shift)) {
    $self->setProcessorID($processorID);
    $self->loadSettingData();
  } 

  return $self;
}

sub setProcessorID {
  my $self = shift;
  my $id = shift;
  $self->{'processorID'} = $id;
  $self->loadSettingData();
}

sub getProcessorID {
  my $self = shift;
  return $self->{'processorID'};
}

sub getSettings {
  my $self = shift;

  my @settings;
  foreach my $setting (keys %{$self->{'settings'}}) {
    my %settingData = %{$self->{'settings'}{$setting}};
    $settingData{'setting'} = $setting;
    push @settings,\%settingData;
  }
  return \@settings;
}

sub getSettingNames {
  my $self = shift;
  my @settings = keys %{$self->{'settings'}};
  return \@settings;
}

sub isValidSetting {
  my $self = shift;
  my $setting = shift;
  $setting =~ s/[^a-zA-Z0-9_]//g;
  return 0 if $setting eq '';
  return ((grep { $_ eq $setting } @{$self->getSettingNames()}) ? 1 : 0);
}

sub addSetting {
  my $self = shift;
  my $settingName = shift;

  $self->{'settings'}{$settingName} = {};
}

sub deleteSetting {
  my $self = shift;
  my $settingName = shift;
  delete $self->{'settings'}{$settingName};
}

sub setLegacyTableColumn {
  my $self = shift;
  my $setting = shift;
  my $legacy = shift;
  $self->{'settings'}{$setting}{'legacyTableColumn'} = $legacy;
}

sub getLegacyTableColumn {
  my $self = shift;
  my $setting = shift;
  if ($setting eq 'gatewayAccount') {
    return 'username';
  } else {
    return $self->{'settings'}{$setting}{'legacyTableColumn'};
  }
}

sub setDisplayName {
  my $self = shift;
  my $setting = shift;
  my $displayName = shift;
  $self->{'settings'}{$setting}{'displayName'} = $displayName;
}

sub getDisplayName {
  my $self = shift;
  my $setting = shift;
  return $self->{'settings'}{$setting}{'displayName'};
}

sub setHasOptions{
  my $self = shift;
  my $setting = shift;
  my $optionsFlag = shift;

  $self->{'settings'}{$setting}{'hasOptions'} = $optionsFlag;
}

sub getHasOptions {
  my $self = shift;
  my $setting = shift;
  return $self->{'settings'}{$setting}{'hasOptions'};
}

sub setMultipleOptions {
  my $self = shift;
  my $setting = shift;
  my $multipleOptions = shift;
  $self->{'settings'}{$setting}{'multipleOptions'} = $multipleOptions;
}

sub getMultipleOptions {
  my $self = shift;
  my $setting = shift;
  return $self->{'settings'}{$setting}{'multipleOptions'};
}

sub setRequired {
  my $self = shift;
  my $setting = shift;
  my $required = shift;

  $self->{'settings'}{$setting}{'required'} = $required;
}

sub getRequired {
  my $self = shift;
  my $setting = shift;
  return $self->{'settings'}{$setting}{'required'};
}

sub setDisplay {
  my $self = shift;
  my $setting = shift;
  my $display = shift;
  $self->{'settings'}{$setting}{'display'} = $display;
}

sub getDisplay {
  my $self = shift;
  my $setting = shift;
  return $self->{'settings'}{$setting}{'display'};
}

sub setDisplayOrder {
  my $self = shift;
  my $setting = shift;
  my $displayOrder = shift;
  $self->{'settings'}{$setting}{'displayOrder'} = $displayOrder;
}

sub getDisplayOrder {
  my $self = shift;
  my $setting = shift;
  return $self->{'settings'}{$setting}{'displayOrder'};
}

sub setIsHash {
  my $self = shift;
  my $setting = shift;
  my $isHash = shift;
  $self->{'settings'}{$setting}{'isHash'} = ($isHash ? 1 : 0);
}

sub getIsHash {
  my $self = shift;
  my $setting = shift;
  return $self->{'settings'}{$setting}{'isHash'};
}

sub setHashValueDisplayLabel {
  my $self = shift;
  my $setting = shift;
  my $displayLabel = shift;
  $self->{'settings'}{$setting}{'hashValueDisplayLabel'} = $displayLabel;
}

sub getHashValueDisplayLabel {
  my $self = shift;
  my $setting = shift;
  return $self->{'settings'}{$setting}{'hashValueDisplayLabel'} || 'Value';
}

sub setIsEncrypted {
  my $self = shift;
  my $setting = shift;
  my $isEncrypted = shift;
  $self->{'settings'}{$setting}{'isEncrypted'} = ($isEncrypted ? 1 : 0);
}

sub getIsEncrypted {
  my $self = shift;
  my $setting = shift;
  return $self->{'settings'}{$setting}{'isEncrypted'};
}

sub setSettingID{
  my $self = shift;
  my $settings = shift;
  my $id = shift;

  $self->{'settings'}{$settings}{'id'} = $id;
}

sub getSettingID{
  my $self = shift;
  my $settings = shift;
 
  return $self->{'settings'}{$settings}{'id'};
}

sub getSettingName {
  my $self = shift;
  my $legacy = shift;

  foreach my $setting (keys %{$self->{'settings'}}) {
    if ($self->getLegacyTableColumn($setting) eq $legacy) {
      return $setting;
    }
  }
}

sub loadSettingData {
  my $self = shift;

  if ($_processorCache->contains($self->getProcessorID())) {
    $self->{'settings'} = $_processorCache->get($self->getProcessorID());
    return;
  }

  my $dbs = new PlugNPay::DBConnection;
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT id,setting_name,legacy_table_column,display_name,
           has_options,multiple_options,required,display,display_order,
           is_hash, hash_value_display_label, encrypt
      FROM processor_setting WHERE processor_id = ?
  /) or die($DBI::errstr);

  $sth->execute($self->getProcessorID()) or die($DBI::errstr);

  my $result = $sth->fetchall_arrayref({});

  if ($result) {
    foreach my $row (@{$result}) {
      $self->addSetting($row->{'setting_name'});
      $self->setSettingID($row->{'setting_name'},$row->{'id'});
      $self->setLegacyTableColumn($row->{'setting_name'},$row->{'legacy_table_column'});
      $self->setDisplayName($row->{'setting_name'},$row->{'display_name'});
      $self->setHasOptions($row->{'setting_name'},$row->{'has_options'});
      $self->setMultipleOptions($row->{'setting_name'},$row->{'multiple_options'});
      $self->setRequired($row->{'setting_name'},$row->{'required'});
      $self->setDisplay($row->{'setting_name'},$row->{'display'});
      $self->setDisplayOrder($row->{'setting_name'},$row->{'display_order'});
      $self->setIsHash($row->{'setting_name'},$row->{'is_hash'});
      $self->setHashValueDisplayLabel($row->{'setting_name'},$row->{'hash_value_display_label'});
      $self->setIsEncrypted($row->{'setting_name'},$row->{'encrypt'});
    }

    $_processorCache->set($self->getProcessorID(),$self->{'settings'});
  }
}

1;
