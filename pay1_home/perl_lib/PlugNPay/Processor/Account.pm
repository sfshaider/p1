package PlugNPay::Processor::Account;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Die;
use PlugNPay::Processor;
use PlugNPay::Processor::Settings;
use PlugNPay::Features;
use PlugNPay::GatewayAccount::InternalID;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::Hash;
use PlugNPay::Util::Cache::TimerCache;

our $_cache_;

if (!defined $_cache_) {
  $_cache_ = new PlugNPay::Util::Cache::TimerCache(5);
}

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  $self->{'settings'} = {};

  my $parameters = shift;

  if ($parameters->{'processorName'}) {
    $self->setProcessorCodeHandle($parameters->{'processorName'});
  } elsif ($parameters->{'processorId'} || $parameters->{'processorID'}) {
    $self->setProcessorID($parameters->{'processorId'} || $parameters->{'processorID'});
  }

  if ($parameters->{'gatewayAccount'} && $self->getProcessorID()) {
    $self->setGatewayAccount($parameters->{'gatewayAccount'});
    $self->load();
  }

  return $self;
}

sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;
  $self->{'gatewayAccount'} = $gatewayAccount;
  $self->{'customerID'} = new PlugNPay::GatewayAccount::InternalID()->getIdFromUsername($gatewayAccount);
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

sub setProcessorCodeHandle {
  my $self = shift;
  my $codeHandle = shift;
  my $processor = new PlugNPay::Processor({'shortName' => $codeHandle});
  if (!$self->getProcessorID()) {
    $self->setProcessorID($processor->getID());
  }

  $self->{'processorCodeHandle'} = $processor->getShortName();
}

sub getProcessorCodeHandle {
  my $self = shift;
  return $self->{'processorCodeHandle'};
}

sub setProcessorID {
  my $self = shift;
  my $processorID = shift;
  $self->{'processorID'} = $processorID;
}

sub getProcessorID {
  my $self = shift;
  return $self->{'processorID'};
}

sub getCustomerID {
  my $self = shift;
  my $username = shift;

  return $self->{'customerID'};
}

sub setUpdateGatewayAccount {
  my $self = shift;
  my $update = shift;
  $self->{'updateGatewayAccount'} = ($update ? 1 : 0);
}

sub getUpdateGatewayAccount {
  my $self = shift;
  return ($self->{'udpateGatewayAccount'} ? 1 : 0);
}

sub setSettingValue {
  my $self = shift;
  my $setting = shift;
  my $value = shift;

  my $settings = new PlugNPay::Processor::Settings($self->getProcessorID());
  if ($settings->isValidSetting($setting)) {
    $self->{'settings'}{$setting} = $value;
  } else {
    die('Invalid setting name ("' . $setting . '") for processor id ("' . $self->getProcessorID() . '").');
  }
}

sub getSettingValue {
  my $self = shift;
  my $setting = shift;
  my $settings = new PlugNPay::Processor::Settings($self->getProcessorID());
  if ($settings->isValidSetting($setting)) {
    return $self->{'settings'}{$setting};
  } else {
    die('Invalid setting name ("' . $setting . '") for processor id ("' . $self->getProcessorID() . '").');
  }
}

sub hasSetting {
  my $self = shift;
  my $setting = shift;
  my $settings = $self->getSettings();
  return defined $settings->{$setting};
}

sub getSettings {
  my $self = shift;
  # return a copy to preserve internal consistency
  my $settings = $self->{'settings'} || {};
  my %settingsCopy = %{$settings};
  return \%settingsCopy;
}

# Loads settings from the processor table.
# If the processor uses the mid and tid in the customers table, then those are loaded from the customers table.
sub load {
  my $self = shift;
  my $options = shift;
  my $skipSearchCacheUpdate = $options->{'skipSearchCacheUpdate'};

  if ((my $s = $_cache_->get($self->cacheKey())) != undef) {
    $self->{'settings'} = $s;
    return;
  }

  my $processor = new PlugNPay::Processor({id => $self->getProcessorID()});
  my $processorTable = $processor->getSettingsTableName();
  my $processorSettings = new PlugNPay::Processor::Settings($self->getProcessorID);

  # set this as a hash because we will be deleting some elements
  my %settingNames = map { $_ => undef } @{$processorSettings->getSettingNames()};

  # load currencies from features
  if (defined $settingNames{'_allowedCurrencies'}) {
    my $features = new PlugNPay::Features($self->getGatewayAccount(),'general');
    # only load if the count is greater than 0, since if there is no value, an empty arrayref will be returned.
    if (@{$features->getFeatureValues('curr_allowed')} > 0) {
      $self->{'settings'}{'_allowedCurrencies'} = $features->getFeatureValues('curr_allowed');
    }
  }

  # delete all setting names that start with underscore before getting columns
  foreach my $key (grep { /^_/ } keys %settingNames) {
    delete $settingNames{$key};
  }

  my %customersTableSettings;

  if ($processor->getUsesCustomersMID()) {
    delete $settingNames{'mid'};
    $customersTableSettings{'mid'} = undef;
  }

  if ($processor->getUsesCustomersTID()) {
    delete $settingNames{'tid'};
    $customersTableSettings{'tid'} = undef;
  }

  if ($processor->getUsesCustomersAuthType()) {
    delete $settingNames{'authType'};
    $customersTableSettings{'authType'} = undef;
  }

  if ($processor->getUsesCustomersCurrency()) {
    delete $settingNames{'currency'};
    $customersTableSettings{'currency'} = undef;
  }
  if ($processorTable) {
    my $dbs = new PlugNPay::DBConnection();
    #Old processor table(s)
    if ($processorTable ne 'processor_setting' && $processorTable ne 'customer_processor_settings') {
      delete $settingNames{''};
      my $columnString = join(',',map { my $col = $processorSettings->getLegacyTableColumn($_); "`$col`" } grep { $_ ne 'gatewayAccount' } keys %settingNames);
      if ($columnString) {
        my $result;

        eval {
          my $sth = $dbs->prepare('pnpmisc','
              SELECT ' . $columnString . '
              FROM ' . $processorTable . '
              WHERE username = ?
          ');

          $sth->execute($self->getGatewayAccount()) or die($DBI::errstr);

          $result = $sth->fetchall_arrayref({});
        };

        if ($@) {
          my $db_error = $@;
          eval {
            Apache2::ServerRec::warn('Error occured in Processor::Account when trying to load ' . $columnString . ' from table ' . $processorTable . ': ' .$db_error);
          };

          if ($@) {
            print STDERR 'Error occured in Processor::Account when trying to load columns "' . $columnString . '" from table ' . $processorTable . ': ' .$db_error . "\n";
          }
        }

        if ($result && $result->[0]) {
          my %settings = map { $processorSettings->getSettingName($_) => $result->[0]{$_} } keys %{$result->[0]};
          # delete the "gatewayAccount" setting as it is not really a setting.
          delete $settings{'gatewayAccount'};
          $self->{'settings'} = \%settings;
        }
      }
    } else {
      #New unified table
      my $select = 'SELECT k.key AS "setting_name", s.value AS "setting_value", s.processor_id, s.customer_id, s.id
                   FROM customer_processor_settings s, customer_processor_setting_key k, customer_id c
                   WHERE c.username = ? AND s.processor_id = ? AND s.key_id = k.id AND c.id = s.customer_id';
      my $sth = $dbs->prepare('pnpmisc',$select);
      $sth->execute($self->getGatewayAccount(),$self->getProcessorID()) or die $DBI::errstr;

      my $rows = $sth->fetchall_arrayref({});
      if ($rows && $rows->[0]) {
        my %settings;
        foreach my $row (@{$rows}) {
          if ($row->{'setting_name'} ne 'gatewayAccount') {
            $settings{$row->{'setting_name'}} = $row->{'setting_value'};
          }
        }
        $self->{settings} = \%settings;
      }
    }
  }

  # if there are fields to load from customers
  if (keys %customersTableSettings) {
    my $customersData = $self->loadCustomersTableData();
    foreach my $customersSetting (keys %customersTableSettings) {
      $self->{'settings'}{$customersSetting} = $customersData->{$customersSetting} if defined ($customersData->{$customersSetting});;
    }
  }

  my %settingsCopy = %{$self->{'settings'}};
  $_cache_->set($self->cacheKey(),\%settingsCopy);

  if (!$skipSearchCacheUpdate) {
    $self->updateProcessorAccountCache({
      customerId  => $self->getCustomerID(),
      processorId => $self->getProcessorID(),
      mid => $self->{'settings'}{'mid'},
      tid => $self->{'settings'}{'tid'}
    });
  }
}

sub delete {
  my $self = shift;
  my $processor = new PlugNPay::Processor({id => $self->getProcessorID()});
  my $processorTable = $processor->getSettingsTableName();

  if ($processorTable) {
    my $dbs = new PlugNPay::DBConnection();

    if ($processorTable ne 'processor_setting' && $processorTable ne 'customer_processor_settings') {
      my $sth = $dbs->prepare('pnpmisc','
        DELETE FROM ' . $processorTable . '
              WHERE username = ?
      ');

      $sth->execute($self->getGatewayAccount());
    } else {
      my $customerID = $self->getCustomerID();

      my $sth = $dbs->prepare('pnpmisc', q/
                               DELETE FROM customer_processor_settings
                               WHERE customer_id = ? AND processor_id = ? /);
      $sth->execute($customerID,$self->getProcessorID());
    }
  }
}

# saves settings to the customers table.
# if the processor uses the mid and tid from the customers table, those are updated.
sub save {
  my $self = shift;

  my $processor = new PlugNPay::Processor({id => $self->getProcessorID()});
  my $processorSettings = new PlugNPay::Processor::Settings($self->getProcessorID());

  my $dbs = new PlugNPay::DBConnection();

  my $processorTable = $processor->getSettingsTableName();

  if ($processorTable) {
    # create a copy of the settings since we are going to modify it by adding the username
    my $insertValues = $self->getSettings();
    if (keys %{$insertValues} == 0) { # if there is nothing to save then return immedately.
      return 1;
    }

    # store the allowed currencies to features
    if (defined $insertValues->{'_allowedCurrencies'}) {
      my $features = new PlugNPay::Features($self->getGatewayAccount(),'general');
      $features->set('curr_allowed',$insertValues->{'_allowedCurrencies'});
      $features->saveContext();
    }

    # delete all setting names that start with underscore before getting columns
    foreach my $key (grep { /^_/ } keys %{$insertValues}) {
      delete $insertValues->{$key};
    }

    my $customersUpdateValues = {};

    if ($processor->getUsesCustomersMID()) {
      $customersUpdateValues->{'mid'} = $insertValues->{'mid'};
      delete $insertValues->{'mid'};
    }

    if ($processor->getUsesCustomersTID()) {
      $customersUpdateValues->{'tid'} = $insertValues->{'tid'};
      delete $insertValues->{'tid'};
    }

    if ($processor->getUsesCustomersAuthType()) {
      $customersUpdateValues->{'authType'} = $insertValues->{'authType'};
      delete $insertValues->{'authType'};
    }

    if ($processor->getUsesCustomersCurrency() && $processorSettings->isValidSetting('currency')) {
      $customersUpdateValues->{'currency'} = $insertValues->{'currency'};
      delete $insertValues->{'currency'};
    }


    # add the username to insertValues
    delete $insertValues->{''}; # and remove any value with en empty string as a key
    $insertValues->{'gatewayAccount'} = $self->getGatewayAccount();


    # do deletes, inserts, and updates as a single transaction
    $dbs->begin('pnpmisc');

    my $insert = '';
    my $executed = 0;
    $self->delete(1);

    if ($processorTable ne 'processor_setting' && $processorTable ne 'customer_processor_settings') {
      my $columnNameString = join(',',map { my $col = $processorSettings->getLegacyTableColumn($_); "`$col`" } keys %{$insertValues});
      my $placeholderString = join(',',map { '?' } keys %{$insertValues});
      $insert = qq/
        INSERT INTO $processorTable
                 ($columnNameString)
             VALUES
                 ($placeholderString)/;
      my @rawKeyNames = keys %{$insertValues};
      my $dieMetadata = { query => $insert, rawKeyNames => \@rawKeyNames };
      my $sth_proc = $dbs->prepare('pnpmisc',$insert) or die_metadata($DBI::errstr, $dieMetadata);
      $executed = $sth_proc->execute(values %{$insertValues}) or die_metadata($DBI::errstr, $dieMetadata);
    } else {
      my $insertData = $self->getUnifiedInsert($insertValues);

      $insert = qq/
        INSERT INTO customer_processor_settings
                 (`customer_id`, `processor_id`, `key_id`, `value`)
             VALUES
                 $insertData->{'params'}
             ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)
      /;
      my $sth_proc = $dbs->prepare('pnpmisc',$insert) or die($DBI::errstr);
      $executed = $sth_proc->execute(@{$insertData->{'data'}}) or die($DBI::errstr);
    }

    # only commit the transaction if insert is successful and, if there is an update to customers, that is successful as well
    if ($executed && $self->saveCustomersTableData($customersUpdateValues)) {
      $dbs->commit('pnpmisc');
      $self->updateProcessorAccountCache({
        customerId  => $self->getCustomerID(),
        processorId => $self->getProcessorID(),
        mid => $insertValues->{'mid'},
        tid => $insertValues->{'tid'}
      });

      my %settingsCopy = %{$self->{'settings'}};
      $_cache_->set($self->cacheKey(),\%settingsCopy);

      return 1;
    } else {
      my $logger = new PlugNPay::Logging::DataLog({'collection' => 'processor_account'});
      $logger->log({'error' => $DBI::errstr, 'account' => $self->getGatewayAccount(), 'processorID' => $self->getProcessorID()});
      $dbs->rollback('pnpmisc');
      return 0;
    }
  }
}

sub getUnifiedInsert {
  my $self = shift;
  my $data = shift;

  my @keys = keys( %{$data});

  # create keys that may not be defined yet
  my $keyParamString = join(',',map {'(?)'} @keys);
  my $dbs = new PlugNPay::DBConnection();
  my $insertQuery = q/INSERT IGNORE INTO customer_processor_setting_key (`key`) VALUES / . $keyParamString;
  $dbs->executeOrDie('pnpmisc',$insertQuery,\@keys);

  # load keys for insert
  my $loadQuery = q/SELECT `id`,`key` FROM customer_processor_setting_key WHERE `key` IN (/ . $keyParamString . ')';
  my $result = $dbs->fetchallOrDie('pnpmisc',$loadQuery,\@keys,{});
  my $rows = $result->{'rows'};

  my $loadedArray = [];
  my $params = [];
  foreach my $row (@{$rows}){
    push @{$loadedArray}, $self->getCustomerID();
    push @{$loadedArray}, $self->getProcessorID();
    push @{$loadedArray}, $row->{'id'};
    push @{$loadedArray}, $data->{$row->{'key'}} || ''; # always insert an empty string instead of null
    push @{$params}, '(?,?,?,?)';
  }

  return {'data' => $loadedArray, 'params' => join(',',@{$params})};
}

sub saveCustomersTableData {
  my $self = shift;
  my $data = shift;

  my $processor = new PlugNPay::Processor({id => $self->getProcessorID()});

  my %customersTableSettings;
  $customersTableSettings{'merchant_id'} = $data->{'mid'}         if (defined($data->{'mid'}) && $processor->getUsesCustomersMID());
  $customersTableSettings{'pubsecret'}   = $data->{'tid'}         if (defined($data->{'tid'}) && $processor->getUsesCustomersTID());
  $customersTableSettings{'proc_type'}   = $data->{'authType'}    if (defined($data->{'authType'}) && $processor->getUsesCustomersAuthType());
  $customersTableSettings{'currency'}    = $data->{'currency'}    if (defined($data->{'currency'}) && $processor->getUsesCustomersCurrency());

  if (keys %customersTableSettings) {
    my $updates = join(',',map { $_ . ' = ?' } keys %customersTableSettings);

    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnpmisc',q/
      UPDATE customers
         SET / . $updates . q/
       WHERE username = ?
    /) or die($DBI::errstr);

    return $sth->execute(values %customersTableSettings, $self->getGatewayAccount()) or die($DBI::errstr);
  } else {
    return 1;
  }
}

sub loadCustomersTableData {
  my $self = shift;

  my $data = {};

  my $processor = new PlugNPay::Processor({id => $self->getProcessorID()});
  my $processorSettings = new PlugNPay::Processor::Settings($self->getProcessorID());

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT merchant_id,
           pubsecret,
           currency,
           proc_type
      FROM customers
     WHERE username = ?
  /);

  $sth->execute($self->getGatewayAccount());

  my $result = $sth->fetchall_arrayref({});

  if ($result && $result->[0]) {
    $data->{'mid'}         = $result->[0]{'merchant_id'} if ($processor->getUsesCustomersMID()        && $processorSettings->isValidSetting('mid'));
    $data->{'tid'}         = $result->[0]{'pubsecret'}   if ($processor->getUsesCustomersTID()        && $processorSettings->isValidSetting('tid'));
    $data->{'authType'}    = $result->[0]{'proc_type'}   if ($processor->getUsesCustomersAuthType()   && $processorSettings->isValidSetting('authType'));
    $data->{'currency'}    = $result->[0]{'currency'}    if ($processor->getUsesCustomersCurrency()   && $processorSettings->isValidSetting('currency'));
  }

  return $data
}

sub isMIDUnique {
  my $self = shift;
  my $username = shift;
  my %usernames = map { $_ => 1 } @{$self->_xidCount('mid')};
  delete $usernames{$username};
  my $count = keys %usernames;
  return $count == 0;
}

sub midExists {
  my $self = shift;
  my $username = shift;
  return !$self->isMIDUnique($username);
}

sub isTIDUnique {
  my $self= shift;
  my $username = shift;
  my %usernames = map { $_ => 1 } @{$self->_xidCount('tid')};
  delete $usernames{$username};
  my $count = keys %usernames;
  return $count == 0;
}

sub tidExists {
  my $self = shift;
  my $username = shift;
  return !$self->isTIDUnique($username);
}

sub _xidCount {
  my $self = shift;
  my $settingName = shift;
  my $settings = $self->getSettings();
  my $processor = new PlugNPay::Processor({id => $self->getProcessorID()});
  if (!defined $processor->getCodeHandle() || $processor->getCodeHandle() eq '') {
    $processor->reload();
  }

  my $legacyColumn;
  if ($settingName eq 'mid') {
    $legacyColumn = 'merchant_id';
  } elsif ($settingName eq 'tid') {
    $legacyColumn = 'pubsecret';
  }

  my $dbs = new PlugNPay::DBConnection();
  my $select = '';

  my $values;
  if ($processor->getUsesCustomersMID()) {
    $select = q/
      SELECT username
        FROM customers
       WHERE / . $legacyColumn . q/ = ?
         AND processor = ?
    /;
    $values = [$self->getSettingValue($settingName), $processor->getCodeHandle()];
  } else {
    $select = q/
      SELECT cust.username
        FROM customer_processor_settings s, customer_processor_setting_key k, customer_id c, customers cust
       WHERE k.key = ?
         AND cust.processor = ?
         AND c.username = cust.username
         AND s.key_id = k.id
         AND c.id = s.customer_id
         AND s.value = ?
    /;
    $values = [$settingName, $processor->getCodeHandle(), $self->getSettingValue($settingName)];
  }

  my $results = $dbs->fetchallOrDie('pnpmisc', $select, $values, {})->{'result'};

  my @usernames = map { $_->{'username'} } @{$results};
  return \@usernames;
}

sub searchProcessorAccountCache {
  my $self = shift;
  my $input = shift;
  my $mid = $input->{'mid'};
  my $tid = $input->{'tid'};

  my $hasher = new PlugNPay::Util::Hash();
  $hasher->add($mid);
  my $midHash = $hasher->sha256('0b');
  $hasher->reset();
  $hasher->add($tid);
  my $tidHash = $hasher->sha256('0b');

  my $whereClause = ' WHERE ';
  my @values;
  my $numberInputs = 0;
  if (defined $mid && $mid ne '') {
    $whereClause .= ' mid_hash = ? ';
    push @values,$midHash;
    $numberInputs++;
  }
  if (defined $tid && $tid ne '') {
    if ($numberInputs) {
      $whereClause .= ' AND ';
    }
    $whereClause .= ' tid_hash = ? ';
    push @values,$tidHash;
    # don't care about number of inputs at this point
  }

  my $whereClauseAddendum .= ' OR (';
  my $addAddendum = 0;
  if (defined $mid && $mid ne '') {
    my $partials = $self->generateXidPartials($mid);
    $addAddendum += @{$partials};

    my %partialsToMatch = map { '%|' . $_ . '|%' => 'mid_partial LIKE ?' } @{$partials};
    $whereClauseAddendum .= ' (' . join (' AND ', values %partialsToMatch) . ') ';
    push @values,keys %partialsToMatch;
  }
  if (defined $tid && $tid ne '') {
    if ($numberInputs) {
      $whereClauseAddendum .= ') AND (';
    }

    my $partials = $self->generateXidPartials($tid);
    $addAddendum += @{$partials};

    my %partialsToMatch = map { '%|' . $_ . '|%' => 'tid_partial LIKE ?' } @{$partials};
    $whereClauseAddendum .= ' (' . join (' AND ', values %partialsToMatch) . ') ';
    push @values,keys %partialsToMatch;
  }
  $whereClauseAddendum .= ')';

  if ($addAddendum) {
    $whereClause .= $whereClauseAddendum;
  }

  my $query = qq/
    SELECT customer_id, processor_id FROM customer_processor_search_cache $whereClause
  /;

  my @customerIds = ();

  my $dbs = new PlugNPay::DBConnection();
  my $result = $dbs->fetchallOrDie('pnpmisc', $query, \@values, {});
  my $rows = $result->{'result'};
  foreach my $row (@{$rows}) {
    my $customerID = $row->{'customer_id'};
    my $processorID = $row->{'processor_id'};

    my $merchant = new PlugNPay::GatewayAccount::InternalID()->getUsernameFromId($customerID);
    my $processorAccount = new PlugNPay::Processor::Account({
      'gatewayAccount' => $merchant,
      'processorID'    => $processorID
    });

    # checks for partial matches against values
    if (defined $mid) {
      my $loadedMid = $processorAccount->getSettingValue('mid');
      if ($loadedMid !~ /$mid/) {
        next;
      }
    }

    if (defined $tid) {
      my $loadedTid = $processorAccount->getSettingValue('tid');
      if ($loadedTid !~ /$tid/) {
        next;
      }
    }

    push (@customerIds, $customerID);
  }

  return \@customerIds;
}

sub updateProcessorAccountCache {
  my $self = shift;
  my $input = shift;
  my $customerId = $input->{'customerId'};
  my $processorId = $input->{'processorId'};
  my $mid = $input->{'mid'};
  my $tid = $input->{'tid'};

  my $hasher = new PlugNPay::Util::Hash();
  $hasher->add($mid);
  my $midHash = $hasher->sha256('0b');
  $hasher->reset();
  $hasher->add($tid);
  my $tidHash = $hasher->sha256('0b');

  my $midPartial = $self->generateXidPartial5Map($mid);
  my $tidPartial = $self->generateXidPartial5Map($tid);

  my $dbs = new PlugNPay::DBConnection();
  $dbs->executeOrDie('pnpmisc',q/
    INSERT INTO customer_processor_search_cache
      (customer_id, processor_id, mid_hash, tid_hash, mid_partial, tid_partial)
    VALUES
      (?,?,?,?,?,?)
    ON DUPLICATE KEY UPDATE
      mid_hash = VALUES(mid_hash),
      tid_hash = VALUES(tid_hash),
      mid_partial = VALUES(mid_partial),
      tid_partial = VALUES(tid_partial)
  /, [$customerId, $processorId, $midHash, $tidHash, $midPartial, $tidPartial]);
}

sub generateXidPartial5Map {
  my $self = shift;
  my $xid = shift;
  my $partials = $self->generateXidPartials($xid);
  my $partialMap = sprintf('|%s|', join('|', sort @{$partials}));
  return $partialMap;
}

sub generateXidPartials {
  my $self = shift;
  my $xid = shift;
  $xid =~ s/[^0-9]//g;

  my $partials = {};
  foreach my $start (0..(length($xid)-5)) {
    my $partial = substr($xid,$start,5);
    my @digits = split(//,$partial);
    my $partialValue = $self->generatePartialValue(\@digits);
    $partials->{$partialValue} = 1;
  }
  my @partialArray = sort keys %{$partials};
  return \@partialArray;
}

sub generatePartialValue {
  my $self = shift;
  my $digits = shift;
  return 0 if ref($digits) ne 'ARRAY';
  return $digits->[0] * $digits->[1] + $digits->[2] * $digits->[3] + $digits->[4];
}

sub getIndustry {
  my $self = shift;

  my $industrycode;
  eval {
    $industrycode = {
      'retail' => 'retail',
      'moto' => 'moto',
      'restaurant' => 'restaurant',
      'petroleum' => 'petroleum'
    }->{$self->getSettingValue('industryCode')};
  };

  return $industrycode || 'ecommerce';
}

sub cacheKey {
  my $self = shift;
  return sprintf('%s:%s',$self->getGatewayAccount(),$self->getProcessorID());
}

1;
