#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Contact;
use PlugNPay::Country;
use PlugNPay::UI::HTML;
use PlugNPay::Reseller;
use PlugNPay::Sys::Time;
use PlugNPay::CreditCard;
use PlugNPay::UI::Template;
use PlugNPay::GatewayAccount;
use PlugNPay::Reseller::Admin;
use PlugNPay::Reseller::Chain;
use PlugNPay::Reseller::Payout;
use PlugNPay::Recurring::PaymentSource;

##################
# initialization #
##################
my $username = $ENV{'REMOTE_USER'};
my $gatewayAccount = new PlugNPay::GatewayAccount($username);
my $reseller = $gatewayAccount->getReseller();
my $resellerAccount = new PlugNPay::Reseller($username);

####################
# Create Templates #
####################
my $mainTemplate = new PlugNPay::Reseller::Admin()->getTemplate();
my $contentTemplate = new PlugNPay::UI::Template('/reseller/admin/profile','index');
my $headTagsTemplate = new PlugNPay::UI::Template('/reseller/admin/profile','index.head');


###########
# Content #
###########

################################################
# Stuff that can be used in multiple locations #
################################################
my $htmlBuilder = new PlugNPay::UI::HTML();

my $countryData = new PlugNPay::Country();
my $stateData = new PlugNPay::Country::State();

my %countryOptions;
foreach my $country (@{$countryData->getCountries()}) {
  $countryOptions{$country->{'twoLetter'}} = $country->{'commonName'};
}

###################
# Contact Section #
###################
my $contact = $gatewayAccount->getMainContact();
my $billing = $gatewayAccount->getBillingContact();
my $tech = $gatewayAccount->getTechnicalContact();
my $contactTemplate = new PlugNPay::UI::Template('/reseller/admin/profile/index/','contact');

{ # creating a scope just for the contact template
  my $contactCountry = $contact->getCountry();
  my $contactState = $contact->getState();

  my $contactStates = $stateData->getStatesForCountry($contactCountry);
  my %contactStateOptions;
  foreach my $state (@{$contactStates}) {
    $contactStateOptions{$state->{'abbreviation'}} = $state->{'commonName'};
  }

  my $contactCountrySelectOptions = $htmlBuilder->selectOptions({ selected => $contactCountry, selectOptions => \%countryOptions });
  my $contactStateSelectOptions = $htmlBuilder->selectOptions({ selected => $contactState, selectOptions => \%contactStateOptions });

  $contactTemplate->setVariable('contactCountryOptions',$contactCountrySelectOptions);
  $contactTemplate->setVariable('contactStateOptions',$contactStateSelectOptions);
  $contactTemplate->setVariable('full_name',$contact->getFullName());
  $contactTemplate->setVariable('company', $contact->getCompany());
  $contactTemplate->setVariable('address1', $contact->getAddress1());
  $contactTemplate->setVariable('address2', $contact->getAddress2());
  $contactTemplate->setVariable('city', $contact->getCity());
  $contactTemplate->setVariable('postal_code',$contact->getPostalCode());
  $contactTemplate->setVariable('telephone', $contact->getPhone());
  $contactTemplate->setVariable('fax', $contact->getFax());
  $contactTemplate->setVariable('email',$contact->getEmailAddress());
  $contactTemplate->setVariable('url', $gatewayAccount->getURL());

  ## Billing
  $contactTemplate->setVariable('billing_email', $billing->getEmailAddress());

  ## Technical
  $contactTemplate->setVariable('tech_name', $tech->getFullName());
  $contactTemplate->setVariable('tech_email', $tech->getEmailAddress());
  $contactTemplate->setVariable('tech_phone', $tech->getPhone());
};

#####################
# Buy Rates Section #
#####################
my $buyRatesTemplate = new PlugNPay::UI::Template('/reseller/admin/profile/index/','buy_rates');

{ # creating a scope just for the buy rates template
  my $chain = new PlugNPay::Reseller::Chain($username);
  $chain->setReseller($username);

  my $resellerData = {$username => $gatewayAccount->getCompanyName()};

  my $subresellerChain = new PlugNPay::Reseller::Chain($username);
  my $subresellers = &makeResellerArray($subresellerChain->getDescendants());
  my $subresellersHash = PlugNPay::Reseller::infoList($subresellers);

  foreach my $subreseller (sort keys %{$subresellersHash}) {
    $resellerData->{$subreseller} = $subresellersHash->{$subreseller}{'name'};
  }

  my $rateOptions = {selected => $username, selectOptions => $resellerData};

  $buyRatesTemplate->setVariable('subresellers',$htmlBuilder->selectOptions($rateOptions));

  ##Buy Rate Info
  my @data;
  my @direct = ('Direct Link',$resellerAccount->getBuyRate_Direct(),$resellerAccount->getMonthly_Direct(), $resellerAccount->getPerTran_Direct(),$resellerAccount->getPerTranMax(),$resellerAccount->getPerTranExtra());
  push @data,\@direct;

  #Level 3
  my @level3 = ('Level 3',$resellerAccount->getBuyRate_Level(),$resellerAccount->getMonthly_Level(),$resellerAccount->getPerTran_Level(),'','');
  push @data, \@level3;

  #High Risk
  my @highrisk = ('High Risk', $resellerAccount->getBuyRate_HighRisk(),$resellerAccount->getMonthly_HighRisk(),$resellerAccount->getPerTran_HighRisk(),'','');
  push @data, \@highrisk;

  #Recurring
  my @recurring = ('Recurring', $resellerAccount->getBuyRate_Recurring(),$resellerAccount->getMonthly_Recurring(),$resellerAccount->getPerTran_Recurring(),'','');
  push @data, \@recurring;

  #Billing Presentment
  my @bill = ('Billing Presentment', $resellerAccount->getBuyRate_BillPres(),$resellerAccount->getMonthly_BillPres(),$resellerAccount->getPerTran_BillPres(),'','');
  push @data,\@bill;

   #Membership
  my @member = ('Membership', $resellerAccount->getBuyRate_Membership(),$resellerAccount->getMonthly_Membership(),$resellerAccount->getPerTran_Membership(),'','');
  push @data, \@member;

  #Digital
  my @digital = ( 'Digital',$resellerAccount->getBuyRate_Digital(),$resellerAccount->getMonthly_Digital(),$resellerAccount->getPerTran_Digital(),'','');
  push @data, \@digital;

  #Affiliate
  my @affiliate = ('Affiliate', $resellerAccount->getBuyRate_Affiliate(),$resellerAccount->getMonthly_Affiliate(),$resellerAccount->getPerTran_Affiliate(),'','');
  push @data, \@affiliate;

  #FraudTrak
  my @fraud = ('FraudTrak', $resellerAccount->getBuyRate_FraudTrak(),$resellerAccount->getMonthly_FraudTrak(),$resellerAccount->getPerTran_FraudTrak(),'','');
  push @data, \@fraud;

  #Coupon
  my @coupon = ('Coupon',$resellerAccount->getBuyRate_Coupon(),$resellerAccount->getMonthly_Coupon(),$resellerAccount->getPerTran_Coupon(),'','');
  push @data, \@coupon;

  my @cols = ({'type' => 'string', 'name' => 'Buy Rates'},
              {'type' => 'string', 'name' => 'Per Transaction'},
              {'type' => 'string', 'name' => 'Monthly Minimum'},
              {'type' => 'string', 'name' => 'Setup'},
              {'type' => 'string', 'name' => 'Transaction Maximum'},
              {'type' => 'string', 'name' => 'Extra'}
             );

  my $buyOptions = { 'columns' => \@cols,
                     'data' => \@data,
                     'id' => 'buyratesTable'};
  my $buyTable = $htmlBuilder->buildTable($buyOptions);
  $buyRatesTemplate->setVariable('buytable',$buyTable);

};

#####################
# Bill Auth Section #
#####################
my $billAuthTemplate = new PlugNPay::UI::Template('/reseller/admin/profile/index/','bill_auth');

{
  my $sysTime = new PlugNPay::Sys::Time();
  my $time = $sysTime->inFormat('db');

  # Expiration Year options
  my $year = substr($time,0,4);
  my $years = {};
  for (my $i = 0; $i < 11; $i++) {
    $years->{substr($year + $i,2,2)} = $year + $i;
  }

  $years->{'0'} = 'Select Year';

  my $yearOptions = {'selected' => '0',
                     'selectOptions' => $years,
                     'first' => '0'};

  my $yearSelectOptions = $htmlBuilder->selectOptions($yearOptions);

  # Expiration Month Options
  my $month = substr($time,5,2);
  my $months = {};
  for( my $i = 1; $i < 13; $i++) {
    my $month = $i;
    $months->{$i} = sprintf('%02i',$month);
  }

  $months->{'0'} = 'Select Month';

  my $monthOptions = {'selected' => '0',
                      'selectOptions' => $months,
                      'first' => '0'};

  my $monthSelectOptions = $htmlBuilder->selectOptions($monthOptions);

  my $billingInfo = "";

  my $paymentSource = new PlugNPay::Recurring::PaymentSource();
  $paymentSource->loadPaymentSource('pnpbilling',$username);
  my $accountType = $paymentSource->getPaymentSourceType();
  if($accountType eq 'credit') {
    $billingInfo = '<span class="paymentAgree">Card Number:  </span><span>' . $paymentSource->getMaskedNumber(4,2,'*', 2);
    $billingInfo .= '</span><br><span class="paymentAgree">Exp Date:  </span><span>';
    $billingInfo .= $paymentSource->getExpirationMonth() . '/' . $paymentSource->getExpirationYear() . '</span>';

  } elsif ($accountType eq 'checking' || $accountType eq 'savings'){
    my $routingNumber = $paymentSource->getRoutingNumber();
    my $accountNumber = $paymentSource->getAccountNumber();

    $billingInfo = '<span class="paymentAgree">Routing Number: </span><span>' .  substr($routingNumber,0,4) . ('X' x (length($routingNumber) - 4)) . '</span><br>';
    $billingInfo .= '<span class="paymentAgree">Account Number: </span><span>' . ('X' x (length($accountNumber) - 4)) . substr($accountNumber,-4) . '</span>';

  } else {
    $billingInfo = '<span>No Payment Information Set</span>';
  }

  #content
  $billAuthTemplate->setVariable('current_bill_info',ucfirst($accountType));
  $billAuthTemplate->setVariable('billing_account_info', $billingInfo);
  $billAuthTemplate->setVariable('full_name',$contact->getFullName());
  $billAuthTemplate->setVariable('cardExpirationMonthSelectOptions',$monthSelectOptions);
  $billAuthTemplate->setVariable('cardExpirationYearSelectOptions', $yearSelectOptions);
}


#######################
# Payout Info Section #
#######################
my $payoutTemplate = new PlugNPay::UI::Template();

{
  if ($resellerAccount->getPayAllFlag != 1 || $resellerAccount->getCommissionsFlag){
    $payoutTemplate->setTemplate('reseller/admin/profile/index','payout');
    my $payout = new PlugNPay::Reseller::Payout($username);

    my $payoutContact = $payout->getContact();

    my $payoutCountry = $payoutContact->getCountry();
    my $payoutState   = $payoutContact->getState();


    my $payoutStates = $stateData->getStatesForCountry($payoutCountry);
    my %payoutStateOptions;
    foreach my $state (@{$payoutStates}) {
      $payoutStateOptions{$state->{'abbreviation'}} = $state->{'commonName'};
    }

    $payoutTemplate->setVariable('payoutCountryOptions',$htmlBuilder->selectOptions({selected => $payoutCountry, selectOptions => \%countryOptions}));
    $payoutTemplate->setVariable('payoutStateOptions',$htmlBuilder->selectOptions({selected => $payoutState, selectOptions => \%payoutStateOptions}));
    $payoutTemplate->setVariable('full_name',$payoutContact->getFullName());
    $payoutTemplate->setVariable('company_name',$payoutContact->getCompany());
    $payoutTemplate->setVariable('address1',$payoutContact->getAddress1());
    $payoutTemplate->setVariable('address2',$payoutContact->getAddress2());
    $payoutTemplate->setVariable('city',$payoutContact->getCity());
    $payoutTemplate->setVariable('postal_code',$payoutContact->getPostalCode());
    $payoutTemplate->setVariable('phone',$payoutContact->getPhone());
    $payoutTemplate->setVariable('fax',$payoutContact->getFax());
    $payoutTemplate->setVariable('commcardtype',$payout->getCommCardType());
    $payoutTemplate->setVariable('email',$payoutContact->getEmailAddress());
    $payoutTemplate->setVariable('ach_routing_number', $payout->getMaskedRoutingNumber());
    $payoutTemplate->setVariable('ach_account_number', $payout->getMaskedAccountNumber());
    if (defined $payout->getMaskedAccountNumber() && defined $payout->getMaskedRoutingNumber()) {
      $payoutTemplate->setVariable('display_class', 'info');
    } else {
      $payoutTemplate->setVariable('display_class', 'hidden');
    }
  } else {
    $payoutTemplate->setTemplate('reseller/admin/profile/index','payall');
  }
}

########################
# Add Sections to page #
########################
$contentTemplate->setVariable('payout_info',$payoutTemplate->render());
$contentTemplate->setVariable('bill_auth',$billAuthTemplate->render());
$contentTemplate->setVariable('buy_rates',$buyRatesTemplate->render());
$contentTemplate->setVariable('contactArea',$contactTemplate->render());

##############
# Build Page #
##############
$mainTemplate->setVariable('content',$contentTemplate->render());
$mainTemplate->setVariable('headTags',$headTagsTemplate->render());
my $html = $mainTemplate->render();

###################
# Send to Browser #
###################
print 'Content-type:text/html' . "\n\n";
print $html;

exit;

sub makeResellerArray {
  my $resellers = shift;
  my @subArray;
  foreach my $resellerName (keys %$resellers) {
    push @subArray, $resellerName;
    my $subresellers = &makeResellerArray($resellers->{$resellerName});
    foreach my $val ( @{$subresellers}) {
      push @subArray, $val;
    }
  }

  return \@subArray;
}
