package PlugNPay::API::REST::Responder::Account;

use strict;

use PlugNPay::Processor;
use PlugNPay::Processor::Account;
use PlugNPay::Processor::Settings;
use PlugNPay::GatewayAccount;
use PlugNPay::Contact;
use PlugNPay::Username;
use PlugNPay::Util::UniqueID;
use PlugNPay::Email;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;

  my $action = $self->getAction();

  my $account = $self->getResourceData()->{'account'};

  my $responseData = {};
  if ($action eq 'read' && $account eq $self->getGatewayAccount()) {
    return $self->_read();      
  } else {
    # no other actions are permitted at this time
    $self->setResponseCode(403);
    return {};
  }
}

############
### READ ###
############
sub _read {
  my $self = shift;

  my $account = {};

  # Load the gateway account
  my $ga = new PlugNPay::GatewayAccount($self->getResourceData()->{'account'});

 
  $account->{'gatewayAccountName'} = $ga->getGatewayAccountName();

  ###################
  # Billing Contact #
  ###################
  my $billingContactObj = $ga->getBillingContact();
  my %billingContact;

  $billingContact{'emailList'} = [{address => $billingContactObj->getEmailAddress(), type => 'primary'}];

  #####################
  # Technical Contact #
  #####################
  my $techContactObj = $ga->getTechnicalContact();
  my %techContact;

  $techContact{'name'} = $techContactObj->getFullName();
  $techContact{'emailList'} = [{address => $techContactObj->getEmailAddress(), type => 'primary'}];
  $techContact{'phoneList'} = [{number => $techContactObj->getPhone(), type => 'primary'}];


  ###################
  # Primary Contact #
  ###################
  my $primaryContactObj = $ga->getMainContact();
  my %primaryContact;

  $primaryContact{'name'} = $primaryContactObj->getFullName();

  my @primaryContactPhoneList;
  push @primaryContactPhoneList, {type => 'phone', number => $primaryContactObj->getPhone()};
  push @primaryContactPhoneList, {type => 'fax', number => $primaryContactObj->getFax()};
  $primaryContact{'phoneList'} = \@primaryContactPhoneList;

  my @primaryContactEmailList;
  push @primaryContactEmailList, {type => 'primary', address => $primaryContactObj->getEmailAddress()};
  $primaryContact{'emailList'} = \@primaryContactEmailList;

  my %primaryContactAddress;
  $primaryContactAddress{'type'} = 'primary';
  $primaryContactAddress{'streetLine1'}   = $primaryContactObj->getAddress1();
  $primaryContactAddress{'streetLine2'}   = $primaryContactObj->getAddress2();
  $primaryContactAddress{'city'}          = $primaryContactObj->getCity();
  $primaryContactAddress{'stateProvince'} = $primaryContactObj->getState();
  $primaryContactAddress{'postalCode'}    = $primaryContactObj->getPostalCode();
  $primaryContactAddress{'country'}       = $primaryContactObj->getCountry();
  
  my @primaryContactAddressList;
  push @primaryContactAddressList, \%primaryContactAddress;
  $primaryContact{'addressList'} = \@primaryContactAddressList;
  #######################
  # End Primary Contact #
  #######################

  ##############
  # Processors #
  ##############

  my @processors;

  # card processor
  if ($ga->getCardProcessor()) {
    my $cardProcessorSettings = $self->_processorDataFromShortName($ga->getCardProcessor());
    push @processors,$cardProcessorSettings;
  }

  if ($ga->getACHProcessor()) {
    my $achProcessorSettings = $self->_processorDataFromShortName($ga->getACHProcessor());
    push @processors,$achProcessorSettings;
  }
   

  $account->{'status'} = $ga->getStatus();
  $account->{'companyName'} = $ga->getCompanyName();
  $account->{'primaryContact'} = \%primaryContact;
  $account->{'technicalContact'} = \%techContact;
  $account->{'billing'}{'contact'} = \%billingContact;
  $account->{'billing'}{'authorized'} = $ga->getBillAuthorization();
  $account->{'billing'}{'authorizedDate'} = $ga->getBillAuthDate();
  $account->{'billing'}{'billingPaymentType'} = $ga->getPaymentMethod();
  $account->{'processors'}{'cardProcessor'} = $ga->getCardProcessor();
  $account->{'processors'}{'achProcessor'} = $ga->getACHProcessor();
  $account->{'processors'}{'tdsProcessor'} = $ga->getTDSProcessor();
  $account->{'processors'}{'walletProcessor'} = $ga->getWalletProcessor();
  $account->{'processors'}{'processor'} = \@processors;
  $account->{'url'} = $ga->getURL();

  # only set the status code if it is not already set.
  if (!$self->responseCodeSet()) {
    $self->setResponseCode(200);
  }
  return {'account' => $account};
}

sub _processorDataFromShortName {
  my $self = shift;
  my $processorName = shift;

  my $processor = new PlugNPay::Processor({shortName => $processorName});
  my $settings = new PlugNPay::Processor::Account({gatewayAccount => $self->getResourceData()->{'merchant'},
                                                   processorID => $processor->getID()});

  my %processorData;
  $processorData{'shortName'} = $processorName;
  $processorData{'type'} = $processor->getProcessorType();
  my @settings;
  foreach my $setting (keys %{$settings->getSettings()}) {
    push @settings,{name => $setting, value => $settings->getSettingValue($setting)};
  }
  $processorData{'setting'} = \@settings;
  return \%processorData;
}

1;
