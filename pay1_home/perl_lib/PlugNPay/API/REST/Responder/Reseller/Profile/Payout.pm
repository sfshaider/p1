package PlugNPay::API::REST::Responder::Reseller::Profile::Payout;

use strict;
use PlugNPay::Country;
use PlugNPay::Contact;
use PlugNPay::Reseller;
use PlugNPay::Sys::Time;
use PlugNPay::Reseller::Payout;
use PlugNPay::Reseller::Payout::History;

use base "PlugNPay::API::REST::Responder";

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();
  my $data = {};
  $self->setResponseCode('200');
  
  if ($action eq 'read') {
    $data = $self->_read();
  } elsif ($action == 'update') {
    $data = $self->_update();
  }
  
  return $data;
}

sub _read {
  my $self = shift;
  my $reseller = new PlugNPay::Reseller($self->getGatewayAccount());

  unless($reseller->getPayAllFlag() && !$reseller->getCommissionsFlag()){
    my $info = {};
    my $payout = new PlugNPay::Reseller::Payout($self->getGatewayAccount());
    my $pay_contact = $payout->getContact();
    my $payContent = {};
    $payContent->{'country'} = $pay_contact->getCountry();
    $payContent->{'name'} = $pay_contact->getFullName();
    $payContent->{'company'} = $pay_contact->getCompany();
    $payContent->{'address1'} = $pay_contact->getAddress1();
    $payContent->{'address2'} = $pay_contact->getAddress2();
    $payContent->{'city'} = $pay_contact->getCity();
    $payContent->{'state'} = $pay_contact->getState();
    $payContent->{'postal_code'} = $pay_contact->getPostalCode();
    $payContent->{'phone'} = $pay_contact->getPhone();
    $payContent->{'fax'} = $pay_contact->getFax();
    $payContent->{'email'} = $pay_contact->getEmailAddress();
    $info->{'contact'} = $payContent;
    $info->{'payment_data'}{'routing_number'} =  $payout->getMaskedRoutingNumber();
    $info->{'payment_data'}{'account_number'} =  $payout->getMaskedAccountNumber();
    $info->{'payment_data'}{'accountType'} = $payout->getCommCardType();
    $info->{'gatewayAccountName'} = $self->getGatewayAccount();

  
    return {'info' => $info};
  
  } else {

    return {'info' => {'status' => 'Payall is set'}};
  }
}

sub _update {
  my $self = shift;
  my $username = $self->getGatewayAccount();
  my $resellerAccount = new PlugNPay::Reseller($username);
  my $time = new PlugNPay::Sys::Time();
  my @currentTime = split(' ',$time->inFormat('db'));
  my $data = $self->getInputData();

  unless($resellerAccount->getPayAllFlag() && !$resellerAccount->getCommissionsFlag()){
    my $payout = new PlugNPay::Reseller::Payout($username);
    my $history = new PlugNPay::Reseller::Payout::History();
    my $contact = $payout->getContact();
    $contact->setFullName($data->{'contact'}{'name'});
    $contact->setCompany($data->{'contact'}{'company'});
    $contact->setAddress1($data->{'contact'}{'address1'});
    $contact->setAddress2($data->{'contact'}{'address2'});
    $contact->setCity($data->{'contact'}{'city'});
    $contact->setState($data->{'contact'}{'state'});
    $contact->setCountry($data->{'contact'}{'country'});
    $contact->setPostalCode($data->{'contact'}{'postal_code'});
    $contact->setPhone($data->{'contact'}{'phone'});
    $contact->setFax($data->{'contact'}{'fax'});
    $contact->setEmailAddress($data->{'contact'}{'email'});
    $payout->setContact($contact);
    $payout->setAccountType('ach');
    my $achAccount = $data->{'payment_data'}{'account_number'};
    my $achRouting = $data->{'payment_data'}{'routing_number'};
    if ( $achAccount && $achRouting ){
      $payout->setMaskedNumber($achAccount,$achRouting);
    }
    if ($data->{'payment_data'}{'accountType'} eq 'true' ){
      $payout->isBusinessAccount();
   } else {
      $payout->isPersonalAccount();
    }
    
    #History
    $history->setTransTime($currentTime[0]);
    $history->setGatewayAccount($username);
    $history->setAction('Customer Update');
    my $reason = 'User updated profile info from ' . $ENV{'REMOTE_ADDR'} . ', confirmation sent to PnP staff.';
    $history->setDescription($reason);

    $payout->save();
    $history->save();
    
   
    return $self->_read();

  } else {
    return { 'info' => {'status' => 'Payall is set'} };
  }
}

1;
