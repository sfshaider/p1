package PlugNPay::API::REST::Responder::Reseller::Profile::Contact;

use strict;
use PlugNPay::Contact;
use PlugNPay::Reseller;
use PlugNPay::Username;
use PlugNPay::GatewayAccount;

use base "PlugNPay::API::REST::Responder";

sub _getOutputData {
  my $self = shift;

  my $action = $self->getAction();
  my $username = $self->getGatewayAccount();
  my $data = {};
  if (PlugNPay::GatewayAccount::exists($username)){
    if ($action eq 'read'){
      $data = $self->_read();
    } elsif ($action eq 'update'){
      $data = $self->_update();
    }
  }

  return $data;
}

sub _update {
  my $self = shift;
  my $gatewayAccount = new PlugNPay::GatewayAccount($self->getGatewayAccount());
  my $resellerAccount = new PlugNPay::Reseller($self->getGatewayAccount());
  my $data = $self->getInputData();
  my $mainContact = $gatewayAccount->getMainContact();
  my $resellerContact = $resellerAccount->getContactInfo();
  my $contact = $data->{'account'}{'contact'};
  my $Security = new PlugNPay::Username($self->getGatewayAccount());

  #Set Contact Values
  $mainContact->setFullName($contact->{'name'});
  $mainContact->setEmailAddress($contact->{'email'});
  $mainContact->setPhone($contact->{'phone'});
  $mainContact->setFax($contact->{'fax'});
  $mainContact->setAddress1($contact->{'address1'});
  $mainContact->setAddress2($contact->{'address2'});
  $mainContact->setCity($contact->{'city'});
  $mainContact->setCountry($contact->{'country'});
  $mainContact->setState($contact->{'state'});
  $mainContact->setInternationalProvince($contact->{'state'}); #State/Province are sent under state, depending on country
  $mainContact->setPostalCode($contact->{'postalCode'});
  $mainContact->setCompany($contact->{'company'});
  $gatewayAccount->setMainContact($mainContact);

  $resellerContact->setFullName($contact->{'name'});
  $resellerContact->setEmailAddress($contact->{'email'});
  $resellerContact->setPhone($contact->{'phone'});
  $resellerContact->setFax($contact->{'fax'});
  $resellerContact->setAddress1($contact->{'address1'});
  $resellerContact->setAddress2($contact->{'address2'});
  $resellerContact->setCity($contact->{'city'});
  $resellerContact->setCountry($contact->{'country'});
  $resellerContact->setInternationalProvince($contact->{'state'});
  $resellerContact->setPostalCode($contact->{'postalCode'});
  $resellerContact->setState($contact->{'state'});
  $resellerContact->setCompany($contact->{'company'});
  $resellerAccount->setContactInfo($resellerContact);

  my $techContact = $gatewayAccount->getTechnicalContact();
  my $tech = $data->{'account'}{'tech'};
  $techContact->setFullName($tech->{'name'});
  $techContact->setEmailAddress($tech->{'email'});
  $techContact->setPhone($tech->{'phone'});
  
  my $billingContact = $gatewayAccount->getBillingContact();
  $billingContact->setEmailAddress($data->{'account'}{'billing'}{'email'});
  
  #Save Contacts
  $gatewayAccount->setTechnicalContact($techContact);
  $gatewayAccount->setBillingContact($billingContact);
  $gatewayAccount->setURL($data->{'account'}{'url'});
  $gatewayAccount->save();
  $resellerAccount->save();

  #Password Changing!
  my $password = $data->{'password'}{'newPassword'};
  my $oldPass = $data->{'password'}{'oldPassword'};
  my $passCheck = $data->{'password'}{'checkPassword'};
  my $changeStatus = 0;
  my $didChange = 0;

  if ($password && $passCheck && $oldPass) {
    $didChange = 1;
    if ($Security->verifyPassword($oldPass)){
      if ($password eq $passCheck) {
        $changeStatus = $Security->setPassword($password);
      }
    }
  }
  return $self->_read($didChange,$changeStatus);
}

sub _read {
  my $self = shift;
  my $didChange = shift;
  my $passCheck = shift;
  
  my $account = {};
  my $gatewayAccount = new PlugNPay::GatewayAccount($self->getGatewayAccount());

  $account->{'gatewayAccountName'} = $gatewayAccount->getGatewayAccountName();

  my $mainContact = $gatewayAccount->getMainContact();
  my $billingContact = $gatewayAccount->getBillingContact();
  $account->{'url'} = $gatewayAccount->getURL();

  my $contact = { 'name' => $mainContact->getFullName(),
                  'email' => $mainContact->getEmailAddress(),
                  'address1' => $mainContact->getAddress1(),
                  'address2' => $mainContact->getAddress2(),
                  'city' => $mainContact->getCity(),
                  'postalCode' => $mainContact->getPostalCode(),
                  'country' => $mainContact->getCountry(),
                  'phone' => $mainContact->getPhone(),
                  'fax' => $mainContact->getFax(),
                  'company' => $gatewayAccount->getCompanyName() };
  if (defined $mainContact->getState) { 
    $contact->{'state'} = $mainContact->getState();
  } else {
    $contact->{'state'} = $mainContact->getInternationalProvince();
  }

  my $techContact = $gatewayAccount->getTechnicalContact();
  my $tech = { 'name' => $techContact->getFullName(),
               'email' => $techContact->getEmailAddress(),
               'phone' => $techContact->getPhone() };

  my $bilingContact = $gatewayAccount->getBillingContact();
  my $billing = { 'email' => $billingContact->getEmailAddress()};
  $account->{'contact'} = $contact;
  $account->{'tech'} = $tech;
  $account->{'billing'} = $billing;
  
  #Bad password isn't an error so we can pass back a 200 response code
  if ($didChange){
    if($passCheck) {
      $account->{'password'} = {'error' => 0, 'message' => 'pass'};
    } else {
      $account->{'password'} = {'error' => 1, 'message' =>'fail'};
    }
  } else {
     $account->{'password'} = {'error' => 0, 'message' => 'unchanged'};
  }
  
  $self->setResponseCode('200');
  return {'account' => $account };
}

1;
