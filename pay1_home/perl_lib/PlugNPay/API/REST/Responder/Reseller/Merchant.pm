package PlugNPay::API::REST::Responder::Reseller::Merchant;

use strict;

use PlugNPay::Reseller;
use PlugNPay::Reseller::Chain;
use PlugNPay::Processor;
use PlugNPay::Processor::Account;
use PlugNPay::Processor::Settings;
use PlugNPay::GatewayAccount;
use PlugNPay::Contact;
use PlugNPay::Username;
use PlugNPay::Util::UniqueID;
use PlugNPay::Email;
use PlugNPay::GatewayAccount::Services;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;

  my $action = $self->getAction();

  my $reseller = $self->getGatewayAccount();
  my $chain = new PlugNPay::Reseller::Chain($reseller);

  my $submittedReseller = $self->getResourceData()->{'reseller'};

  my $merchant = $self->getResourceData()->{'merchant'};

  my $responseData = {};

  if ($action eq 'create' && ($submittedReseller eq $reseller || $chain->hasDescendant($submittedReseller))) {
    return $self->_create();
  } elsif ($action eq 'read' && ($submittedReseller eq $reseller || $chain->hasDescendant($submittedReseller))) {
    # allow resellers to view their own and subresellers merchantsist merchants if a merchant was specified
    if (defined $merchant) {
      return $self->_read();
    } else {                               # if no merchant was specified, return a list of merchants
      return $self->_readList();
    }
  } elsif ($reseller eq $submittedReseller) {
    # only the account's reseller can edit or cancel a merchant
    if ($action eq 'update') {
      return $self->_update();
    } elsif ($action eq 'delete') {
      return $self->_delete();
    }
  } else {
    # no other actions are permitted at this time
    $self->setResponseCode(403);
    return {};
  }
}

##############
### CREATE ###
##############
sub _create {
  my $self = shift;

  my $accountData = $self->getInputData()->{'account'};
  my $gatewayAccountName = $accountData->{'gatewayAccountName'};

  if (PlugNPay::GatewayAccount::exists($gatewayAccountName) || PlugNPay::Username::exists($gatewayAccountName)) {
    $self->setError('Username already exists.');
    $self->setResponseCode(409);
    return {};
  }

  if(length $gatewayAccountName < 6 || length $gatewayAccountName > 12) {
    $self->setResponseCode(422);
    $self->setError("Username length must be between six and twelve characters.");
    return {};
  }

  my $submittedReseller = $self->getResourceData()->{'reseller'};
  my $caller = $self->getGatewayAccount();
  my $reseller = $submittedReseller || $caller;

  my $ga = new PlugNPay::GatewayAccount();
  $ga->setGatewayAccountName($gatewayAccountName);
  $ga->setReseller($reseller);
  $ga->setDebug();
  $ga->setURL($accountData->{'url'});

  my $ra = new PlugNPay::Reseller($self->getGatewayAccount());

  #####################################
  # Fees, you know, how we make money #
  #####################################
  $ga->setPerTransaction($ra->getPerTran());
  $ga->setPercent($ra->getPercent());
  $ga->setMonthly($ra->getMonthly());

  # create primary contact;
  my $primaryContact = new PlugNPay::Contact();
  my $primaryContactData = $accountData->{'primaryContact'};
  $primaryContact->setFullName($primaryContactData->{'name'});

  # get the primary address data
  foreach my $address (@{$primaryContactData->{'addressList'}}) {
    if ($address->{'type'} eq 'primary') {
      $primaryContact->setAddress1($address->{'streetLine1'});
      $primaryContact->setAddress2($address->{'streetLine2'});
      $primaryContact->setCity($address->{'city'});
      $primaryContact->setState($address->{'stateProvince'});
      $primaryContact->setPostalCode($address->{'postalCode'});
      $primaryContact->setCountry($address->{'country'});
      last;
    }
  }

  # set the phone numbers
  foreach my $phoneData (@{$primaryContactData->{'phoneList'}}) {
    $primaryContact->setPhone($phoneData->{'number'}) if ($phoneData->{'type'} eq 'phone');
    $primaryContact->setFax($phoneData->{'number'}) if ($phoneData->{'type'} eq 'fax');
  }

  # set the primary email address
  foreach my $emailAddressData (@{$primaryContactData->{'emailList'}}) {
    if ($emailAddressData->{'type'} eq 'primary') {
      $primaryContact->setEmailAddress($emailAddressData->{'address'});
    }
  }

  # create technical contact
  my $technicalContact = new PlugNPay::Contact();
  my $technicalData = $accountData->{'technicalContact'};
  $technicalContact->setFullName($technicalData->{'name'});

  foreach my $emailData (@{$technicalData->{'emailList'}}) {
    if ($emailData->{'primary'} eq 'true') {
      $technicalContact->setEmailAddress($emailData->{'address'});
    }
  }

  foreach my $phoneData (@{$technicalData->{'phoneList'}}){
    $technicalContact->setPhone($phoneData->{'number'}) if ($phoneData->{'type'} eq 'phone');
    $technicalContact->setFax($phoneData->{'number'}) if ($phoneData->{'type'} eq 'fax');
  }

  # create billing contact

  my $billingContact = new PlugNPay::Contact();
  my $billingContactData = $accountData->{'billing'}{'contact'};

  foreach my $emailData (@{$billingContactData->{'emailList'}}) {
    if ($emailData->{'primary'} eq 'true') {
      $billingContact->setEmailAddress($emailData->{'address'});
    }
  }

  # set the contacts
  $ga->setMainContact($primaryContact);
  $ga->setTechnicalContact($technicalContact);
  $ga->setBillingContact($billingContact);
  $ga->setCompanyName($accountData->{'companyName'});

  #set processors
  my $processorData = $accountData->{'processors'};
  $ga->setCardProcessor($processorData->{'cardProcessor'});
  $ga->setCheckProcessor($processorData->{'checkProcessor'});

  #default emvProc
  my $emvProcessor = $processorData->{'emvProcessor'} ? $processorData->{'emvProcessor'} : $processorData->{'cardProcessor'};
  $ga->setEmvProcessor($emvProcessor);

  # save the account
  my $dbs = new PlugNPay::DBConnection();
  $dbs->begin('pnpmisc');

  my $status = $ga->save(); # save so that inheritFrom works
  $ga->inheritFrom($self->getGatewayAccount());
  $status &= $ga->save(); # save again so that features are saved

  if (!$status) {
    $dbs->rollback('pnpmisc');
    $self->setResponseCode(422);
    return { 'message' => 'Failed to save account' };
  }


  # Processor Settings
  foreach my $processorInfo (@{$processorData->{'processor'}}) {
    if ($status) {
      my $processorObj = new PlugNPay::Processor({'shortName' => $processorInfo->{'shortName'}});
      my $processorAccount = new PlugNPay::Processor::Account({'processorID' => $processorObj->getID(), 'gatewayAccount' => $accountData->{'gatewayAccountName'}});

      foreach my $settings (@{$processorInfo->{'setting'}}){
        $processorAccount->setSettingValue($settings->{'name'},$settings->{'value'});
      }
      $status &= $processorAccount->save();
    }
  }

  if (!$status) {
    $dbs->rollback('pnpmisc');
    $self->setResponseCode(422);
    return { 'message' => 'Failed to save account. Invalid processor settings' };
  } else {
    $dbs->commit('pnpmisc');

    ## Create User in ACL Login ##
    my $password = substr(new PlugNPay::Util::UniqueID()->inHex(),0,10);
    my $username = new PlugNPay::Username($gatewayAccountName);
    $username->setSecurityLevel(0);
    $username->addAccess('/admin');
    $username->setTemporaryPasswordFlag(1);
    $username->setPassword($password);
    $username->saveUsername();

    # save the services even if all other values are empty.
    my $services = new PlugNPay::GatewayAccount::Services($username);
    $services->save();

    ## Create Email ##
    my $resellerAccountInfo = new PlugNPay::Reseller($self->getGatewayAccount());
    my $resellerEmailAddress =  $resellerAccountInfo->getRegistrationEmail();

    my $mailer = new PlugNPay::Email();
    my $substitutions = {
                      'username' => $gatewayAccountName,
                      'password' => $password
                      };
    $mailer->sendPreFormatted('legacy',                           #Version
                              'new_merchant',                     #Template Name
                              $substitutions,                     #Template Substitutions
                              $primaryContact->getEmailAddress(), #Send To
                              undef,                              #Send CC
                              undef,                              #Send BCC
                              $resellerEmailAddress,              #Sent By
                              $self->getGatewayAccount(),         #Sender Gateway Account Name
                              'text'                              #Email Format
                             );

    ## Email Sent ##

    # copy gateway account name to resource data so _read can return it
    $self->setResponseCode(201);
    $self->setResourceData({merchant => $ga->getGatewayAccountName()});
  }

  return $self->_read();
}

############
### READ ###
############
sub _read {
  my $self = shift;

  my $account = {};

  # Load the gateway account
  my $ga = new PlugNPay::GatewayAccount($self->getResourceData()->{'merchant'});

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

  if ($ga->getEmvProcessor()) {
    my $emvProcessorSettings = $self->_processorDataFromShortName($ga->getEmvProcessor());
    push @processors,$emvProcessorSettings;
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
  $account->{'processors'}{'emvProcessor'} = $ga->getEmvProcessor();
  $account->{'processors'}{'processor'} = \@processors;
  $account->{'url'} = $ga->getURL();

  # only set the status code if it is not already set.
  if (!$self->responseCodeSet()) {
    $self->setResponseCode(200);
  }
  return {'account' => $account};
}

sub _update {
  my $self = shift;

  my $ga = new PlugNPay::GatewayAccount($self->getResourceData()->{'merchant'});

  my $data = $self->getInputData();

  ###################
  # Primary Contact #
  ###################
  my $primaryContactObj = $ga->getMainContact();
  my $primaryContactData = $data->{'account'}{'primaryContact'};

  $primaryContactObj->setFullName($primaryContactData->{'name'});

  # set primary contact email address
  foreach my $emailAddress (@{$primaryContactData->{'emailList'}}) {
    if ($emailAddress->{'primary'} eq 'true') {
      $primaryContactObj->setEmailAddress($emailAddress->{'address'});
    }
  }

  # set primary contact phone numbers
  foreach my $phone (@{$primaryContactData->{'phoneList'}}) {
    if ($phone->{'primary'} eq 'true') {
      $primaryContactObj->setPhone($phone->{'number'});
    }
    if ($phone->{'type'} eq 'fax') {
      $primaryContactObj->setFax($phone->{'number'});
    }
  }

  # set primary contact address
  foreach my $address (@{$primaryContactData->{'addressList'}}) {
    if ($address->{'primary'} eq 'true') {
      $primaryContactObj->setAddress1($address->{'streetLine1'});
      $primaryContactObj->setAddress2($address->{'streetLine2'});
      $primaryContactObj->setCity($address->{'city'});
      $primaryContactObj->setState($address->{'stateProvince'});
      $primaryContactObj->setInternationalProvince($address->{'stateProvince'});
      $primaryContactObj->setPostalCode($address->{'postalCode'});
      $primaryContactObj->setCountry($address->{'country'});
    }
  }

  #####################
  # Technical Contact #
  #####################
  my $techContactObj = $ga->getTechnicalContact();
  my $techContactData = $data->{'account'}{'technicalContact'};

  $techContactObj->setFullName($techContactData->{'name'});

  # set tech contact email address
  foreach my $emailAddress (@{$techContactData->{'emailList'}}) {
    if ($emailAddress->{'primary'} eq 'true') {
      $techContactObj->setEmailAddress($emailAddress->{'address'});
    }
  }

  # set tech contact phone number
  foreach my $phone (@{$techContactData->{'phoneList'}}) {
    if ($phone->{'primary'} eq 'true') {
      $techContactObj->setPhone($phone->{'number'});
    }
  }

  ###################
  # Billing Contact #
  ###################
  my $billingContactObj = $ga->getBillingContact();
  my $billingContactData = $data->{'account'}{'billing'}{'contact'};

  # set billing contact email address
  foreach my $emailAddress (@{$billingContactData->{'emailList'}}) {
    if ($emailAddress->{'primary'} eq 'true') {
      $billingContactObj->setEmailAddress($emailAddress->{'address'});
    }
  }

  $ga->setMainContact($primaryContactObj);
  $ga->setTechnicalContact($techContactObj);
  $ga->setBillingContact($billingContactObj);

  $ga->setCompanyName($data->{'account'}{'companyName'});
  $ga->setURL($data->{'account'}{'url'});

  $ga->save();

  $self->setResponseCode(200);
  return $self->_read();
}

# Note: delete actually just sets status to cancelled.
sub _delete {
  my $self = shift;
  return {};
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

# read list
sub _readList {
  my $self = shift;

  my $reseller = $self->getResourceData()->{'reseller'} || $self->getGatewayAccount();
  my $options =  $self->getResourceOptions();

  my $merchantList = [];

  my $theReseller = new PlugNPay::Reseller($reseller);

  my $list = $theReseller->merchantList($options);

  foreach my $merchant (sort keys %{$list->{'list'}}) {
    my $name = $list->{'list'}{$merchant}{'name'} || '';
    my $status = $list->{'list'}{$merchant}{'status'} || '';
    my $startDate = $list->{'list'}{$merchant}{'startDate'} || '';
    my $merchantInfo = { merchant => $merchant, name => $name, status => $status, startDate => $startDate };
    push @{$merchantList},$merchantInfo;
  }
  $self->setResponseCode(200);
  return {'merchantList' => $merchantList, count => $list->{'count'} };
}

1;
