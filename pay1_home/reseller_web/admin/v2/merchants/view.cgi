#!/bin/env perl

use strict;

use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Reseller::Admin;
use PlugNPay::InputValidator;
use PlugNPay::GatewayAccount;
use PlugNPay::GatewayAccount::Services;
use PlugNPay::Reseller::Chain;
use PlugNPay::Environment;
use PlugNPay::Country;
use PlugNPay::UI::HTML;
use PlugNPay::Processor;
use PlugNPay::Processor::Account;
use PlugNPay::Transaction::Adjustment::Settings;
use PlugNPay::Transaction::Adjustment::Bucket;
use PlugNPay::Transaction::Adjustment::Model;
use PlugNPay::Transaction::Adjustment::Settings::Threshold;
use PlugNPay::Transaction::Adjustment::Settings::CustomerOverride;
use PlugNPay::Transaction::Adjustment::Settings::AuthorizationType;
use PlugNPay::Transaction::Adjustment::Settings::FailureMode;
use PlugNPay::Transaction::Adjustment::Settings::BucketMode;
use PlugNPay::Transaction::Adjustment::Settings::Cap;
use PlugNPay::Transaction::Adjustment::DefaultPaymentVehicle;
use PlugNPay::Transaction::PaymentVehicle::Subtype;
use JSON::XS qw(encode_json decode_json);

use Data::Dumper;

my %query = PlugNPay::InputValidator::filteredQuery('reseller_admin');

my $merchant = $query{'merchant'};

my $resellerAdmin = new PlugNPay::Reseller::Admin();
my $template = $resellerAdmin->getTemplate();


# load the merchant/gateway account
my $ga = new PlugNPay::GatewayAccount($merchant);
my $gaReseller = $ga->getReseller();

my $loggedInReseller = new PlugNPay::Environment()->get('PNP_ACCOUNT');

my $chain = new PlugNPay::Reseller::Chain();
$chain->setReseller($loggedInReseller);

my $headTagsTemplate;
my $contentTemplate;
if ($loggedInReseller eq $gaReseller || $chain->hasDescendant($gaReseller)) {
  # get head tags
  $headTagsTemplate = new PlugNPay::UI::Template();
  $headTagsTemplate->setCategory('reseller/admin/merchants');
  $headTagsTemplate->setName('view.head');
  $headTagsTemplate->setVariable('merchant',$merchant);

  # get content template
  $contentTemplate = new PlugNPay::UI::Template();
  $contentTemplate->setCategory('reseller/admin/merchants');
  $contentTemplate->setName('view');

  # set content variables
  $contentTemplate->setVariable('editMode','Viewing');
  $contentTemplate->setVariable('merchant',$merchant);
  $contentTemplate->setDynamicTemplate('processorTemplate','/reseller/admin/merchants/view/','processor_info');

  my $htmlBuilder = new PlugNPay::UI::HTML();

  # set up country select options;
  my $countryList = new PlugNPay::Country->getCountries();
  my %countryOptions = map { $_->{'twoLetter'} => $_->{'commonName'} } @{$countryList};
  my $countryOptionsHTML = $htmlBuilder->selectOptions({ selectOptions => \%countryOptions, selected => $ga->getMainContact->getCountry() });

  # set up state select options:
  my $stateList = new PlugNPay::Country::State->getStatesForCountry($ga->getMainContact->getCountry());
  my %stateOptions = map { $_->{'abbreviation'} => $_->{'commonName'} } @{$stateList};
  my $stateOptionsHTML = $htmlBuilder->selectOptions({ selectOptions => \%stateOptions, selected => $ga->getMainContact->getState() });

  # create settings tables for processors
  my $cardProcessor = new PlugNPay::Processor({ shortName => $ga->getCardProcessor() });
  my $achProcessor = new PlugNPay::Processor({ shortName => $ga->getCheckProcessor() });
  my $tdsProcessor = new PlugNPay::Processor({ shortName => $ga->getTDSProcessor() });
  my $walletProcessor = new PlugNPay::Processor({ shortName => $ga->getWalletProcessor() });
  my $emvProcessor = new PlugNPay::Processor({ shortName => $ga->getEmvProcessor() });

  my $cardProcessorSettingsTable = buildProcessorSettingsTable($ga->getGatewayAccountName,$cardProcessor->getID());
  my $achProcessorSettingsTable = buildProcessorSettingsTable($ga->getGatewayAccountName,$achProcessor->getID());
  my $tdsProcessorSettingsTable = buildProcessorSettingsTable($ga->getGatewayAccountName,$tdsProcessor->getID());
  my $walletProcessorSettingsTable = buildProcessorSettingsTable($ga->getGatewayAccountName,$walletProcessor->getID());
  my $emvProcessorSettingsTable = buildProcessorSettingsTable($ga->getGatewayAccountName,$emvProcessor->getID());

  # set merchant info variables
  my $ct = $contentTemplate; # shorthand
  $ct->setVariable('companyName',$ga->getCompanyName());
  $ct->setVariable('primaryContactName',$ga->getMainContact->getFullName());
  $ct->setVariable('companyAddress1',$ga->getMainContact->getAddress1());
  $ct->setVariable('companyAddress2',$ga->getMainContact->getAddress2());
  $ct->setVariable('companyCity',$ga->getMainContact->getCity());
  $ct->setVariable('companyStateOptions',$stateOptionsHTML);
  $ct->setVariable('companyPostalCode',$ga->getMainContact->getPostalCode());
  $ct->setVariable('companyCountryOptions',$countryOptionsHTML);
  $ct->setVariable('companyPhone',$ga->getMainContact->getPhone());
  $ct->setVariable('companyFax',$ga->getMainContact->getFax());
  $ct->setVariable('companyEmail',$ga->getMainContact->getEmailAddress());
  $ct->setVariable('companyURL',$ga->getURL());
  $ct->setVariable('technicalContactName',$ga->getTechnicalContact->getFullName());
  $ct->setVariable('technicalContactPhone',$ga->getTechnicalContact->getPhone());
  $ct->setVariable('technicalContactEmail',$ga->getTechnicalContact->getEmailAddress());
  $ct->setVariable('billingContactEmail',$ga->getBillingContact->getEmailAddress());

  $ct->setVariable('cardProcessor',$ga->getCardProcessor());
  $ct->setVariable('cardProcessorSettingsTable',$cardProcessorSettingsTable);
  $ct->setVariable('achProcessor',$ga->getACHProcessor());
  $ct->setVariable('achProcessorSettingsTable',$achProcessorSettingsTable);
  $ct->setVariable('tdsProcessor',$ga->getTDSProcessor());
  $ct->setVariable('tdsProcessorSettingsTable',$tdsProcessorSettingsTable);
  $ct->setVariable('walletProcessor',$ga->getWalletProcessor());
  $ct->setVariable('walletProcessorSettingsTable',$walletProcessorSettingsTable);
  $ct->setVariable('emvProcessor',$ga->getEmvProcessor());
  $ct->setVariable('emvProcessorSettingsTable',$emvProcessorSettingsTable);

  ################
  # Services Tab #
  ################

  my $accountServices = new PlugNPay::GatewayAccount::Services($merchant);
  my $servicesTemplate = new PlugNPay::UI::Template();
  $servicesTemplate->setCategory('reseller/admin/merchants/view/');
  $servicesTemplate->setName('services');
  $servicesTemplate->setVariable('autoBatch',$accountServices->getAutoBatch());

  my $services = $accountServices->getServices();

  my $t = new PlugNPay::UI::Template();
  $t->setCategory('reseller/admin/merchants/view/services/');

  $servicesTemplate->setVariable('merchantBillPay', $services->{'billpay'});
  $servicesTemplate->setVariable('merchantMembership', $services->{'membership'});
  $servicesTemplate->setVariable('merchantRecurring', $services->{'recurring'});
  $servicesTemplate->setVariable('merchantPasswordManagement', $services->{'passwordmanagement'});
  $servicesTemplate->setVariable('merchantFraudtrak2', $services->{'fraudtrak2'});
  $servicesTemplate->setVariable('merchant',$merchant);
  $contentTemplate->setVariable('merchantServices',$servicesTemplate->render());

  ## End Services

  ##################
  # Adjustment Tab #
  ##################

  my $adjustmentTemplate = new PlugNPay::UI::Template();
  $adjustmentTemplate->setCategory('reseller/admin/merchants/view');
  $adjustmentTemplate->setName('adjustment');

  my $selects = {};#buildAdjustmentSelects($ga->getGatewayAccountName());
  my $options = $selects->{options};

  my $adjustmentSettings = new PlugNPay::Transaction::Adjustment::Settings($ga->getGatewayAccountName());
  my $adjustmentEnabledSelectOptions = $htmlBuilder->selectOptions({ selectOptions => {1 => 'Enabled', 0 => 'Disabled'},
                                                                          unsorted => 1,
                                                                          selected => $adjustmentSettings->getEnabled() });

  # get available payment vehicle options
  my $enabledPaymentVehicles = new PlugNPay::Transaction::PaymentVehicle::Subtype()->getEnabledSubtypes();
  my %mappedPaymentVehicles = map { $_->getID() => $_->getName() } @{$enabledPaymentVehicles};
  my $paymentVehicleOptions = $htmlBuilder->selectOptions({ selectOptions => \%mappedPaymentVehicles });
  my $bucketDefaultVehicleOptions = $htmlBuilder->selectOptions({ selectOptions => \%mappedPaymentVehicles,
                                                                       selected => $adjustmentSettings->getBucketDefaultSubtypeID() });
  my $capDefaultVehicleOptions = $htmlBuilder->selectOptions({ selectOptions => \%mappedPaymentVehicles,
                                                                    selected => $adjustmentSettings->getCapDefaultSubtypeID() });

  # get available adjustment model options
  my $enabledModels = new PlugNPay::Transaction::Adjustment::Model()->getEnabledModels();
  my %mappedModels = map { $_->getID() => $_->getName() } @{$enabledModels};
  my $modelOptions = $htmlBuilder->selectOptions({ selectOptions => \%mappedModels,
                                                        selected => $adjustmentSettings->getModelID() });

  my $enabledOverrideModes = new PlugNPay::Transaction::Adjustment::Settings::CustomerOverride()->getEnabledModes();
  my %mappedOverrideModes = map { $_->getMode() => $_->getDescription() } @{$enabledOverrideModes};
  my $overrideModes = $htmlBuilder->selectOptions({ selectOptions => \%mappedOverrideModes,
                                                        selected => $adjustmentSettings->getCustomerCanOverride() });

  my $overrideCheckboxSelect = $htmlBuilder->selectOptions({ selectOptions => {1 => 'CHECKED', 0 => 'NOT CHECKED'},
                                                                          unsorted => 1,
                                                                          selected => $adjustmentSettings->getOverrideCheckboxIsChecked() });

  my $checkCustomerStateSelect = $htmlBuilder->selectOptions({ selectOptions => {1 => 'CHECK STATE', 0 => 'DO NOT CHECK STATE'},
                                                                          unsorted => 1,
                                                                          selected => $adjustmentSettings->getCheckCustomerState() });

  my $adjustmentIsTaxableSelect = $htmlBuilder->selectOptions({ selectOptions => {1 => 'TAXABLE', 0 => 'NOT TAXABLE'},
                                                                          unsorted => 1,
                                                                          selected => $adjustmentSettings->getAdjustmentIsTaxable() });

  my $thresholdModes = new PlugNPay::Transaction::Adjustment::Settings::Threshold()->getEnabledModes();
  my %mappedThresholdModes = map { $_->getID() => $_->getName() } @{$thresholdModes};
  my $thresholdModeOptions = $htmlBuilder->selectOptions({ selectOptions => \%mappedThresholdModes,
                                                                selected => $adjustmentSettings->getThresholdModeID() });

  my $authorizationTypes = new PlugNPay::Transaction::Adjustment::Settings::AuthorizationType()->getEnabledTypes();
  my %mappedAuthorizationTypes = map { $_->getID() => $_->getName() } @{$authorizationTypes};
  my $authorizationTypeOptions = $htmlBuilder->selectOptions({ selectOptions => \%mappedAuthorizationTypes,
                                                                    selected => $adjustmentSettings->getAdjustmentAuthorizationTypeID() });

  my $authorizationFailureModes = new PlugNPay::Transaction::Adjustment::Settings::FailureMode()->getEnabledModes();
  my %mappedAuthorizationFailureModes = map { $_->getID() => $_->getName() } @{$authorizationFailureModes};
  my $failureModeOptions = $htmlBuilder->selectOptions({ selectOptions => \%mappedAuthorizationFailureModes,
                                                              selected => $adjustmentSettings->getFailureModeID() });

  my $bucketModes = new PlugNPay::Transaction::Adjustment::Settings::BucketMode()->getEnabledModes();
  my %mappedBucketModes = map { $_->getID() => $_->getName() } @{$bucketModes};
  my $bucketModeOptions = $htmlBuilder->selectOptions({ selectOptions => \%mappedBucketModes,
                                                             selected => $adjustmentSettings->getBucketModeID() });

  my $buckets = new PlugNPay::Transaction::Adjustment::Bucket($merchant)->getAllBuckets();
  my @bucketData;
  foreach my $bucket (@{$buckets}) {
    my %bucketHash;
    $bucketHash{'paymentVehicleID'} = $bucket->getPaymentVehicleSubtypeID();
    $bucketHash{'paymentVehicleText'} = new PlugNPay::Transaction::PaymentVehicle::Subtype($bucketHash{'paymentVehicleID'})->getName();
    $bucketHash{'base'}    = $bucket->getBase();
    $bucketHash{'coaRate'} = $bucket->getCOARate();
    $bucketHash{'totalRate'} = $bucket->getTotalRate();
    $bucketHash{'fixedAdjustment'} = $bucket->getFixedAdjustment();
    push @bucketData,\%bucketHash;
  }
  my $bucketString = encode_json(\@bucketData);

  my $capModes = new PlugNPay::Transaction::Adjustment::Settings::Cap()->getEnabledModes();
  my %mappedCapModes = map { $_->getID() => $_->getName() } @{$capModes};
  my $capModeOptions = $htmlBuilder->selectOptions({ selectOptions => \%mappedCapModes,
                                                          selected => $adjustmentSettings->getCapModeID() });

  my $caps = new PlugNPay::Transaction::Adjustment::Settings::Cap($merchant)->getCaps();
  my @capData;
  foreach my $cap (@{$caps}) {
    my %capHash;
    $capHash{'paymentVehicleID'} = $cap->getPaymentVehicleSubtypeID();
    $capHash{'paymentVehicleText'} = new PlugNPay::Transaction::PaymentVehicle::Subtype($capHash{'paymentVehicleID'})->getName();
    $capHash{'percentCap'} = $cap->getPercent();
    $capHash{'fixedCap'} = $cap->getFixed();
    push @capData,\%capHash;
  }
  my $capString = encode_json(\@capData);

  $adjustmentTemplate->setVariable('buckets',$bucketString);
  $adjustmentTemplate->setVariable('caps',$capString);
  $adjustmentTemplate->setVariable('enabledSelectOptions',$adjustmentEnabledSelectOptions);
  $adjustmentTemplate->setVariable('modelOptions', $modelOptions);
  $adjustmentTemplate->setVariable('overrideModes', $overrideModes);
  $adjustmentTemplate->setVariable('overrideCheckboxSelect', $overrideCheckboxSelect);
  $adjustmentTemplate->setVariable('checkCustomerStateSelect', $checkCustomerStateSelect);
  $adjustmentTemplate->setVariable('processorDiscountRate', $adjustmentSettings->getProcessorDiscountRate());
  $adjustmentTemplate->setVariable('adjustmentIsTaxableSelect', $adjustmentIsTaxableSelect);
  $adjustmentTemplate->setVariable('feeAccount',$adjustmentSettings->getAdjustmentAuthorizationAccount());
  $adjustmentTemplate->setVariable('authorizationTypeOptions', $authorizationTypeOptions);
  $adjustmentTemplate->setVariable('failureModeOptions', $failureModeOptions);
  $adjustmentTemplate->setVariable('fixedThreshold', $adjustmentSettings->getFixedThreshold());
  $adjustmentTemplate->setVariable('percentThreshold', $adjustmentSettings->getPercentThreshold());
  $adjustmentTemplate->setVariable('vehicleOptions', $paymentVehicleOptions);
  $adjustmentTemplate->setVariable('bucketModeOptions', $bucketModeOptions);
  $adjustmentTemplate->setVariable('defaultBucketVehicleOptions', $bucketDefaultVehicleOptions);
  $adjustmentTemplate->setVariable('defaultCapVehicleOptions', $capDefaultVehicleOptions);
  $adjustmentTemplate->setVariable('thresholdModeOptions', $thresholdModeOptions);
  $adjustmentTemplate->setVariable('capModeOptions', $capModeOptions);

  $adjustmentTemplate->setVariable('merchant',$merchant);
  $contentTemplate->setVariable('merchantAdjustment', $adjustmentTemplate->render());

  ## End Adjustment

  ################
  # Security Tab #
  ################

  my $securityTemplate = new PlugNPay::UI::Template();
  $securityTemplate->setCategory('reseller/admin/merchants/view/');
  $securityTemplate->setName('security');

  $contentTemplate->setVariable('merchantSecurity',$securityTemplate->render());

  # end security

} else {
  $headTagsTemplate = new PlugNPay::UI::Template();
  $headTagsTemplate->setCategory('reseller/admin/merchants');
  $headTagsTemplate->setName('unauthorized.head');

  $contentTemplate = new PlugNPay::UI::Template();
  $contentTemplate->setCategory('reseller/admin');
  $contentTemplate->setName('unauthorized');
}



### Insert Head tags and Content ###
$template->setVariable('headTags',$headTagsTemplate->render());
$template->setVariable('content',$contentTemplate->render());

my $html = $template->render();

print 'Content-type: text/html' . "\n\n";
print $html . "\n";



sub buildProcessorSettingsTable {
  my $ga = shift;
  my $processorID = shift;

  my $htmlBuilder = new PlugNPay::UI::HTML();

  my $processorAccount = new PlugNPay::Processor::Account({ gatewayAccount => $ga,
                                                            processorID => $processorID });
  my $processorSettings = $processorAccount->getSettings();
  my @processorSettingsArray = map { [$_,$processorSettings->{$_}] } keys %{$processorSettings};
  if (@processorSettingsArray == 0) {
    return "<div class='lightgraybox rounded rt-box noFinger'>Not Configured</div>";
  }
  my $processorSettingsTable = $htmlBuilder->buildTable({ id => 'cardProcessorSettingsTable',
                                                          class => 'lightgraybox rounded rt-box noFinger',
                                                          columns => [ { name => 'Setting Name', type => 'string' },
                                                                       { name => 'Setting Value', type => 'string' } ],
                                                          data => \@processorSettingsArray });
  return $processorSettingsTable;
}
