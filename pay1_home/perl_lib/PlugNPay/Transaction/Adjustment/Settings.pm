package PlugNPay::Transaction::Adjustment::Settings;

use strict;
use PlugNPay::GatewayAccount;
use PlugNPay::Transaction::Adjustment::COA::Account::MerchantAccount;
use PlugNPay::DBConnection;
use PlugNPay::Util::Memcached;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  $self->{'memcached'} = new PlugNPay::Util::Memcached('Adjustment-Settings');

  my $gatewayAccount = shift;
  if ($gatewayAccount) {
    $self->setGatewayAccount($gatewayAccount);
    $self->_loadSettings($gatewayAccount);
  }

  return $self;
}

sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;
  $self->{'gatewayAccount'} = $gatewayAccount;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

sub setVersion {
  my $self = shift;
  my $version = shift;
  $self->{'version'} = $version;
}

sub getVersion {
  my $self = shift;
  return $self->{'version'};
}

sub setModelID {
  my $self = shift;
  my $model = shift;
  $self->{'modelID'} = $model;
}

sub getModelID {
  my $self = shift;
  return $self->{'modelID'};
}

sub setFixedThreshold {
  my $self = shift;
  my $fixedThreshold = shift;
  $self->{'fixedThreshold'} = $fixedThreshold;
}

sub getFixedThreshold {
  my $self = shift;
  return $self->{'fixedThreshold'};
}

sub setPercentThreshold {
  my $self = shift;
  my $percentThreshold = shift;
  $self->{'percentThreshold'} = $percentThreshold;
}

sub getPercentThreshold {
  my $self = shift;
  return $self->{'percentThreshold'};
}

sub setThresholdModeID {
  my $self = shift;
  my $thresholdModeID = shift;
  $self->{'thresholdModeID'} = $thresholdModeID;
}

sub getThresholdModeID {
  my $self = shift;
  return $self->{'thresholdModeID'};
}

sub setCOAAccountNumber {
  my $self = shift;
  my $coaAccountNumber = shift;
  $self->{'coaAccountNumber'} = $coaAccountNumber;
}

sub getCOAAccountNumber {
  my $self = shift;
  return $self->{'coaAccountNumber'};
}

sub setCOAAccountIdentifier {
  my $self = shift;
  my $coaAccountIdentifier = shift;
  $self->{'coaAccountIdentifier'} = $coaAccountIdentifier;
}

sub getCOAAccountIdentifier {
  my $self = shift;
  return $self->{'coaAccountIdentifier'};
}

sub setFailureModeID {
  my $self = shift;
  my $failureModeID = shift;
  $self->{'failureModeID'} = $failureModeID;
}

sub getFailureModeID {
  my $self = shift;
  return $self->{'failureModeID'};
}

sub setAdjustmentAuthorizationTypeID {
  my $self = shift;
  my $adjustmentAuthorizationTypeID = shift;
  $self->{'adjustmentAuthorizationTypeID'} = $adjustmentAuthorizationTypeID;
}

sub getAdjustmentAuthorizationTypeID {
  my $self = shift;
  return $self->{'adjustmentAuthorizationTypeID'};
}

sub setAdjustmentAuthorizationAccount {
  my $self = shift;
  my $adjustmentAuthorizationAccount = shift;
  $self->{'adjustmentAuthorizationAccount'} = $adjustmentAuthorizationAccount;
}

sub getAdjustmentAuthorizationAccount {
  my $self = shift;
  return $self->{'adjustmentAuthorizationAccount'};
}

sub setBucketModeID {
  my $self = shift;
  my $bucketModeID = shift;
  $self->{'bucketModeID'} = $bucketModeID;
}

sub getBucketModeID {
  my $self = shift;
  return $self->{'bucketModeID'};
}

sub setBucketDefaultSubtypeID {
  my $self = shift;
  my $subtype = shift;
  $self->{'bucketDefaultSubtype'} = $subtype;
}

sub getBucketDefaultSubtypeID {
  my $self = shift;
  return $self->{'bucketDefaultSubtype'};
}


sub setCapDefaultSubtypeID {
  my $self = shift;
  my $capDefaultSubtypeID = shift;
  $self->{'capDefaultSubtypeID'} = $capDefaultSubtypeID;
}

sub getCapDefaultSubtypeID {
  my $self = shift;
  return $self->{'capDefaultSubtypeID'};
}

sub setCapModeID {
  my $self = shift;
  my $capModeID = shift;
  $self->{'capModeID'} = $capModeID;
}

sub getCapModeID {
  my $self = shift;
  return $self->{'capModeID'};
}

sub setEnabled {
  my $self = shift;
  my $enabled = shift;
  $self->{'enabled'} = $enabled;
}

sub getEnabled {
  my $self = shift;
  return ($self->{'enabled'} ? 1 : 0);
}

sub setCustomerCanOverride {
  my $self = shift;
  my $setting = shift;
  $self->{'customerCanOverride'} = $setting;
}

sub getCustomerCanOverride {
  my $self = shift;
  return ($self->{'customerCanOverride'} ? 1 : 0);
}

sub setOverrideCheckboxIsChecked {
  my $self = shift;
  my $setting = shift;
  $self->{'overrideCheckboxIsChecked'} = $setting;
}

sub getOverrideCheckboxIsChecked {
  my $self = shift;
  return $self->{'overrideCheckboxIsChecked'};
}

sub setMCC {
  my $self = shift;
  my $MCC = shift;
  $self->{'MCC'} = $MCC;
}

sub getMCC {
  my $self = shift;
  return $self->{'MCC'};
}

sub setDiscountRate {
  my $self = shift;
  my $discountRate = shift;
  $self->{'discountRate'} = $discountRate;
}

sub getDiscountRate {
  my $self = shift;
  return $self->{'discountRate'} || '0.00';
}

sub setMaxDiscountRate {
  my $self = shift;
  my $maxDiscountRate = shift;
  $self->{'maxDiscountRate'} = $maxDiscountRate;
}

sub getMaxDiscountRate {
  my $self = shift;
  return $self->{'maxDiscountRate'} || '0.00';
}

sub setFixedDiscount {
  my $self = shift;
  my $fixedDiscount = shift;
  $self->{'fixedDiscount'} = $fixedDiscount;
}

sub getFixedDiscount {
  my $self = shift;
  return $self->{'fixedDiscount'} || '0.00';
}

sub setMaxFixedDiscount {
  my $self = shift;
  my $maxFixedDiscount = shift;
  $self->{'maxFixedDiscount'} = $maxFixedDiscount;
}

sub getMaxFixedDiscount {
  my $self = shift;
  return $self->{'maxFixedDiscount'};
}

sub setProcessorDiscountRate {
  my $self = shift;
  my $processorDiscountRate = shift;
  $self->{'processorDiscountRate'} = $processorDiscountRate;
}

sub getProcessorDiscountRate {
  my $self = shift;
  return $self->{'processorDiscountRate'} || 0.00;
}

sub setRetailMode {
  my $self = shift;
  my $RetailMode = shift;
  $self->{'RetailMode'} = $RetailMode;
}

sub getRetailMode {
  my $self = shift;
  return $self->{'RetailMode'};
}

sub setCheckCustomerState {
  my $self = shift;
  my $setting = shift;
  $self->{'checkCustomerState'} = $setting;
}

sub getCheckCustomerState {
  my $self = shift;
  return ($self->{'checkCustomerState'} ? 1 : 0);
}

sub setAdjustmentIsTaxable {
  my $self = shift;
  my $setting = shift;
  $self->{'adjustmentIsTaxable'} = $setting;
}

sub getAdjustmentIsTaxable {
  my $self = shift;
  return ($self->{'adjustmentIsTaxable'} ? 1 : 0);
}

sub setIsSetup {
  my $self = shift;
  my $isSetup = shift;
  $isSetup = ($isSetup ? 1 : 0);
  $self->{'setup'} = $isSetup;
}
 
sub isSetup {
  my $self = shift;
  return $self->{'setup'}
}

sub _loadSettings {
  my $self = shift;

  my $username = shift || $self->getGatewayAccount();

  my $settings = $self->{'memcached'}->get("$username");

  if ($settings) {
    $self->__setSelfFromSettings($settings);
    return
  }
 
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT username,model_id, coa_account_number,coa_account_identifier,
           fixed_threshold,percent_threshold,threshold_mode_id,
           failure_mode_id,
           bucket_mode_id,
           cap_mode_id,
           adjustment_authorization_type_id,
           adjustment_authorization_account,
           adjustment_bucket_default_subtype_id,
           adjustment_cap_default_subtype_id,
           enabled,version,
           customer_can_override,
           override_checkbox_is_checked,
           discount_rate,
           fixed_discount,
           discount_rate_max,
           fixed_discount_max,
           check_customer_state, 
           adjustment_is_taxable,
           processor_discount_rate
      FROM adjustment_settings
     WHERE username = ?
  /);

  $sth->execute($username);

  my $result = $sth->fetchall_arrayref({});

  $self->setIsSetup(0);

  if ($result) {
    $settings = $result->[0];
    if ($settings) {
      $self->__setSelfFromSettings($settings);
      $self->{'memcached'}->set("$username",$settings);
    }
  }
}

sub __setSelfFromSettings {
  my $self = shift;
  my $s = shift;

  $self->setIsSetup(1);
  $self->setGatewayAccount($s->{'username'});
  $self->setModelID($s->{'model_id'});
  $self->setCOAAccountNumber($s->{'coa_account_number'});
  $self->setCOAAccountIdentifier($s->{'coa_account_identifier'});
  $self->setFixedThreshold($s->{'fixed_threshold'});
  $self->setPercentThreshold($s->{'percent_threshold'});
  $self->setThresholdModeID($s->{'threshold_mode_id'});
  $self->setFailureModeID($s->{'failure_mode_id'});
  $self->setAdjustmentAuthorizationTypeID($s->{'adjustment_authorization_type_id'});
  $self->setAdjustmentAuthorizationAccount($s->{'adjustment_authorization_account'});
  $self->setBucketDefaultSubtypeID($s->{'adjustment_bucket_default_subtype_id'});
  $self->setBucketModeID($s->{'bucket_mode_id'});
  $self->setCapDefaultSubtypeID($s->{'adjustment_cap_default_subtype_id'});
  $self->setCapModeID($s->{'cap_mode_id'});
  $self->setEnabled($s->{'enabled'});
  $self->setVersion($s->{'version'});
  $self->setCustomerCanOverride($s->{'customer_can_override'});
  $self->setOverrideCheckboxIsChecked($s->{'override_checkbox_is_checked'});
  $self->setDiscountRate($s->{'discount_rate'});
  $self->setMaxDiscountRate($s->{'discount_rate_max'});
  $self->setFixedDiscount($s->{'fixed_discount'});
  $self->setMaxFixedDiscount($s->{'fixed_discount_max'});
  $self->setCheckCustomerState($s->{'check_customer_state'});
  $self->setAdjustmentIsTaxable($s->{'adjustment_is_taxable'});
  $self->setProcessorDiscountRate($s->{'processor_discount_rate'});
}

sub _removeAll {
  my $self = shift;

  my $username = shift || $self->getGatewayAccount();

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc', q/
    DELETE FROM adjustment_settings
    WHERE username=?
  /);

  $sth->execute($username);

  $self->{'memcached'}->delete("$username");
}

sub save {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc', q/
    INSERT INTO adjustment_settings (
           username, model_id, coa_account_number, coa_account_identifier,
           fixed_threshold, percent_threshold, threshold_mode_id,
           failure_mode_id, bucket_mode_id, cap_mode_id,
           adjustment_authorization_type_id, adjustment_authorization_account,
           adjustment_bucket_default_subtype_id, adjustment_cap_default_subtype_id,
           enabled, version, customer_can_override, override_checkbox_is_checked,
           discount_rate,fixed_discount,discount_rate_max,fixed_discount_max,
           check_customer_state,adjustment_is_taxable,processor_discount_rate)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
         ON DUPLICATE KEY UPDATE
           model_id = VALUES(model_ID),
           coa_account_number = VALUES(coa_account_number),
           coa_account_identifier = VALUES(coa_account_identifier),
           fixed_threshold = VALUES(fixed_threshold),
           percent_threshold = VALUES(percent_threshold),
           threshold_mode_id = VALUES(threshold_mode_id),
           failure_mode_id = VALUES(failure_mode_id),
           bucket_mode_id = VALUES(bucket_mode_id),
           cap_mode_id = VALUES(cap_mode_id),
           adjustment_authorization_type_id = VALUES(adjustment_authorization_type_id),
           adjustment_authorization_account = VALUES(adjustment_authorization_account),
           adjustment_bucket_default_subtype_id = VALUES(adjustment_bucket_default_subtype_id),
           adjustment_cap_default_subtype_id = VALUES(adjustment_cap_default_subtype_id),
           enabled = VALUES(enabled),
           version = VALUES(version),
           customer_can_override = VALUES(customer_can_override),
           override_checkbox_is_checked = VALUES(override_checkbox_is_checked),
           discount_rate = VALUES(discount_rate),
           fixed_discount = VALUES(fixed_discount),
           discount_rate_max = VALUES(discount_rate_max),
           fixed_discount_max = VALUES(fixed_discount_max),
           check_customer_state = VALUES(check_customer_state),
           adjustment_is_taxable = VALUES(adjustment_is_taxable),
           processor_discount_rate = VALUES(processor_discount_rate)
  /) or die($DBI::errstr);

  $sth->execute(
    $self->getGatewayAccount(),
    $self->getModelID(),
    $self->getCOAAccountNumber(),
    $self->getCOAAccountIdentifier(),
    $self->getFixedThreshold(),
    $self->getPercentThreshold(),
    $self->getThresholdModeID(),
    $self->getFailureModeID(),
    $self->getBucketModeID(),
    $self->getCapModeID(),
    $self->getAdjustmentAuthorizationTypeID(),
    $self->getAdjustmentAuthorizationAccount(),
    $self->getBucketDefaultSubtypeID(),
    $self->getCapDefaultSubtypeID(),
    $self->getEnabled(),
    $self->getVersion(),
    $self->getCustomerCanOverride(),
    $self->getOverrideCheckboxIsChecked(),
    $self->getDiscountRate(),
    $self->getFixedDiscount(),
    $self->getMaxDiscountRate(),
    $self->getMaxFixedDiscount(),
    $self->getCheckCustomerState(),
    $self->getAdjustmentIsTaxable(),
    $self->getProcessorDiscountRate()
  ) or die($DBI::errstr);

  # clear the cache so it's forced to be reloaded
  my $username = $self->getGatewayAccount();
  $self->{'memcached'}->delete("$username");
}

1;
