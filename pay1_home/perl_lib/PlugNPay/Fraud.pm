package PlugNPay::Fraud;

use strict;
use PlugNPay::Features;
use PlugNPay::Sys::Time;
use PlugNPay::CreditCard;
use PlugNPay::Environment;
use PlugNPay::OnlineCheck;
use PlugNPay::DBConnection;
use PlugNPay::Util::IP::Geo;
use PlugNPay::GatewayAccount;
#Fraud Fun
use PlugNPay::Fraud::Bin;
use PlugNPay::Fraud::Proxy;
use PlugNPay::Fraud::Exempt;
use PlugNPay::Fraud::BankBin;
use PlugNPay::Fraud::Country;
use PlugNPay::Fraud::Logging;
use PlugNPay::Fraud::BankBin;
use PlugNPay::Fraud::Positive;
use PlugNPay::Fraud::Duplicate;
use PlugNPay::Fraud::Frequency;
use PlugNPay::Fraud::GeoLocate;
use PlugNPay::Fraud::IPAddress;
use PlugNPay::Fraud::Contact::Phone;
use PlugNPay::Fraud::Contact::PostalCode;
use PlugNPay::Fraud::GeoLocate::IPCountry;
use PlugNPay::Fraud::Contact::EmailAddress;

############################ Fraud ###############################
# Welcome to new fraud module, based on perl_lib/fraud.pm        #
#                                                                #
# preAuthScreen and postAuthScreen are the primary functions     #
# All other functions can be called directly where needed        #
# but all are called in the main screen functions already        #
#                                                                #
# preAuthScreen takes in a transaction object as input           #
# postAuthScreen takes transObj, response object and fraudConfig #
# Both return a hash reference as response                       #
#                                                                #
##################################################################

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $options = shift;

  if (defined $options->{'gatewayAccount'}) {
    $self->setGatewayAccount($options->{'gatewayAccount'});
  }

  if (defined $options->{'fraudConfig'}) {
    $self->setFraudConfig($options->{'fraudConfig'});
  } else {
    if ($self->getGatewayAccount()) {
      my $account = new PlugNPay::GatewayAccount($self->getGatewayAccount());
      $self->setFraudConfig($account->getFraudConfig());
    }
  }

  return $self;
}

sub setFraudConfig {
  my $self = shift;
  my $fraudConfig = shift;

  if (ref($fraudConfig) eq 'PlugNPay::Features') {
    $self->{'fraudConfig'} = $fraudConfig;
    $self->{'fraudConfigString'} = $fraudConfig->getFeatureString();
  } else {
    my $fraudObj = new PlugNPay::Features('fraud_config');
    $fraudObj->parseFeatureString($fraudConfig);
    $self->{'fraudConfig'} = $fraudObj;
    $self->{'fraudConfigString'} = $fraudConfig;
  }

}

sub getFraudConfig {
  my $self = shift;
  return $self->{'fraudConfig'};
}

sub getFraudString {
  my $self = shift;
  return $self->{'fraudConfigString'};
}

sub setGatewayAccount {
  my $self = shift;
  my $username = shift;

  my $gatewayAccountObj = new PlugNPay::GatewayAccount($username);
  if ($username ne $self->{'username'} && $gatewayAccountObj->exists()) {
    $self->setFraudConfig($gatewayAccountObj->getFraudConfig());
  }

  $self->{'username'} = $username;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'username'};
}

# This functions does the majority of Fraud checking, is to be done before transaction is processed
sub preAuthScreen {
  my $self = shift;
  my $transactionObject = shift;
  my $errors = {};

  if ($transactionObject->getIgnoreFraudCheckResponse()) {
    return {'isFraud' => 0};
  }

  my $username = $self->getGatewayAccount() || $transactionObject->getGatewayAccount();
  if (!$self->getGatewayAccount() && $username) {
    $self->setGatewayAccount($username);
  }

  # Initialize data that is used throughout code
  my $accountObject = new PlugNPay::GatewayAccount($username);
  my $fraudConfig = $self->getFraudConfig() || $accountObject->getParsedFraudConfig();
  my $environment = new PlugNPay::Environment();
  my $blockedIPList = new PlugNPay::Fraud::IPAddress($username);
  my $features = $accountObject->getFeatures();
  my $paymentObject = $transactionObject->getPayment();
  my $hashedData = $paymentObject->getCardHash();

  # We do some input checks for some certain scripts, so most of the time this is bypassed
  if ($ENV{'SCRIPT_NAME'} =~ /pnpremote|payremote/) {
    my $inputCheck = $self->inputCheck($fraudConfig, $paymentObject, $transactionObject);
    $errors->{'inputCheck'} = $inputCheck->{'blockReason'} if $inputCheck->{'isBlocked'};

    # Make sure billing zip is valid and is in the billing state
    my $billingObject = $transactionObject->getBillingInformation();
    if (ref($billingObject) eq 'PlugNPay::Contact' && $billingObject->getPostalCode() && $billingObject->getCountry() eq 'US' && $billingObject->getState()) {
      my $postalCodeChecker = new PlugNPay::Fraud::Contact::PostalCode($billingObject->getPostalCode());
      if ($postalCodeChecker->isValid()) {
        $errors->{'postalCodeCheck'} = 'Billing address postal code is invalid';
      } elsif ($postalCodeChecker->matchesState($billingObject->getState())) {
        $errors->{'postalCodeCheck'} = 'Billing address postal code does not match billing state';
      }
    }

    # Make sure shipping zip code is valid and is actually in the shipping state
    my $shippingObject = $transactionObject->getShippingInformation();
    if (ref($shippingObject) eq 'PlugNPay::Contact' && $shippingObject->getPostalCode() && $shippingObject->getCountry() eq 'US') {
      my $postalCodeChecker = new PlugNPay::Fraud::Contact::PostalCode($shippingObject->getPostalCode());
      if ($postalCodeChecker->isValid()) {
        $errors->{'postalCodeCheck'} = 'Shipping address postal code is invalid';
      } elsif ($postalCodeChecker->matchesState($shippingObject->getState())) {
        $errors->{'postalCodeCheck'} = 'Shipping address postal code does not match shipping state';
      }
    }
  }

  # Checks to see if this transaction/account is exempt from fraud checks
  my $exemptionObj = new PlugNPay::Fraud::Exempt({'gatewayAccount' => $username});
  unless ($exemptionObj->isExempt($hashedData)) {
    my $binCheck = $self->checkBin({
     'gatewayAccount'  => $username,
     'features'        => $features,
     'fraudConfig'     => $fraudConfig,
     'paymentObject'   => $paymentObject,
     'transactionData' => $transactionObject
    });

    # Check if Bank Bin Region is blocked
    if ($binCheck->{'region'}{'isBlocked'}) {
      $errors->{'bankBinRegion'} = $binCheck->{'region'}{'blockReason'};
    }

    # Only do the following if they have a fraud_config string
    # NOTE: If you need to disable fraud, change this to if (0) or something like that
    if ($accountObject->getFraudConfig() ne '') {
      # Loads related accounts fraud settings, check certain values. If a block is foundthen we block this trans
      if ($fraudConfig->get('chkaccts') && $fraudConfig->get('acctlist')) {
        my $acctListCheck = $self->checkFraudAccounts($fraudConfig->get('acctlist'), $paymentObject);
        if ($acctListCheck->{'isBlocked'}) {
          $errors->{'accountListCheck'} = $acctListCheck->{'blockReason'} . ' Settings Account: ' . $acctListCheck->{'matchedAccount'};
        }
      }

      # Checks card type and brand, if not allowed then we block
      my $cardCheck = $self->checkCard($fraudConfig, $paymentObject);
      if ($cardCheck->{'isBlocked'}) {
        $errors->{'cardCheck'} = $cardCheck->{'blockReason'};
      }

      # Checks 3 fields to see if they are valid
      if ($fraudConfig->get('reqfields') && $transactionObject->hasTransFlag('posflag')) {
        my $requiredFields = $self->checkRequiredFields($fraudConfig, $transactionObject);
        if ($requiredFields->{'isBlocked'}) {
          $errors->{'requiredFieldCheck'} = $requiredFields->{'blockReason'};
        }
      }

      # Checks transaction to see if duplicate, matching info needs to be within specified time period
      # Info that must match is:
      # Amount, Card num, Billing Name, Billing Zip, Processor, Username, and within set time period
      if ($fraudConfig->get('dupchk') && !$transactionObject->hasTransFlag('skipdupchk')){
        my $duplicateChecker = new PlugNPay::Fraud::Duplicate($username);
        if ($duplicateChecker->isDuplicate($transactionObject)) {
          $errors->{'duplicateCheck'} = 'Transaction was flagged as a duplicate';
        }
      }

      #Checks email address to see if it is in the blocked table
      if ($transactionObject->getBillingInformation()) {
        my $emailCheck = $self->checkEmailAddresses($username, $transactionObject->getBillingInformation()->getEmailAddress());
        if ($emailCheck->{'isBlocked'}) {
          $errors->{'emailCheck'} = $emailCheck->{'blockReason'};
        }
      }

      # Blocks if the card country is not allowed
      if ($binCheck->{'country'}{'isBlocked'}) {
        $errors->{'countryCheck'} = $binCheck->{'country'}{'blockReason'};
      }

      # Match card country and billing country, if they do not match then block
      if ($binCheck->{'matchCountry'} && $binCheck->{'matchCountry'}{'isBlocked'}) {
        $errors->{'matchCountry'} = $binCheck->{'matchCountry'}{'blockReason'};
      }

      # Blocks based on BIN Card Brand and Type
      if ($binCheck->{'cardType'}{'isBlocked'}) {
        $errors->{'foreignCardCheck'} = $binCheck->{'cardType'}{'blockReason'};
      }

      # Frequency Check in PlugNPay/Fraud/Frequency.pm
      # Checks IP Frequency and Card Number frequency
      my $frequencyCheck = new PlugNPay::Fraud::Frequency()->checkFrequency({
        'fraudConfig'      => $fraudConfig,
        'gatewayAccount'   => $username,
        'hashedCardNumber' => $hashedData,
        'transactionTime'  => $transactionObject->getTransactionDateTime(),
        'ipAddress'        => $transactionObject->getIPAddress()
      });

      unless ($frequencyCheck) {
        $errors->{'frequencyCheck'} = $frequencyCheck->getError() . ': ' . $frequencyCheck->getErrorDetails();
      }

      # Blocks if transaction amount exceeds high limit setting
      my $limit = $fraudConfig->get('highlimit') || 0;
      if ($limit > 0 && $transactionObject->getTransactionAmount() > $limit) {
        $errors->{'highLimit'} = 'Transaction amount exceeds limit.';
      }

      #############
      # IP Checks #
      #############

      # Blocks based on passed in IP Address
      if ($fraudConfig->get('blkipaddr') && $blockedIPList->isIPBlocked($transactionObject->getIPAddress())) {
        $errors->{'ipAddress'} = 'Your IP Address is on Blocked List';
      }

      # Blocks based on environmental IP Address
      if ($fraudConfig->get('blksrcip') && $blockedIPList->isIPBlocked($environment->get('PNP_CLIENT_IP'))) {
        $errors->{'sourceIPAddress'} = 'Transactions from this source IP are currently not accepted';
      }

      #Checks the country of the IP Address passed in with the transaction
      if ($fraudConfig->get('blkipcntry')  && $transactionObject->getIPAddress()) {
        my $geoLocateResult = $self->checkIPCountry($username, $transactionObject->getIPAddress(), $fraudConfig);
        if ($geoLocateResult->{'isBlocked'}) {
          $errors->{'ipCountry'} = $geoLocateResult->{'blockReason'};
        }
      }

      # Match IP to Geo Location based on GEO-MS
      if ($fraudConfig->get('matchgeoip')) {
        my $localScript = $ENV{'SCRIPT_NAME'} =~ /pnpremote|systech|xml/i;
        my $ipaddr = $localScript ? $transactionObject->getIPAddress() : $environment->get('PNP_CLIENT_IP');
        my $geoIP = new PlugNPay::Util::IP::Geo();
        my $ipCountry;
        eval {
          $ipCountry = $geoIP->lookupCountryCode($ipaddr);
          $ipCountry = 'GB|UK' if $ipCountry =~ /UK|GB/;
        };

        if ($@) {
          #If microservice is unreachable, like on dev, then use the older geolcate code
          my $basicMatch = new PlugNPay::Fraud::GeoLocate($ipaddr);
          $ipCountry = $basicMatch->getCountry();
        }

        my $billingCountry = $transactionObject->getBillingInformation()->getCountry();
        if (uc($ipCountry) !~ /^($billingCountry)$/i) {
          $errors->{'matchGeoIP'} = 'Billing country does not match ipaddress country.';
        }
      }

      # By order of Dave I have commented out this code until such a time as we can determine if the IP is from a proxy
      # Checks the proxy IP and blocks if needed
      #if ($fraudConfig->get('blkproxy')) {
      #  my $proxyChecker = new PlugNPay::Fraud::Proxy();
      #  unless ($proxyChecker->exists($transactionObject->getIPAddress())){
      #    $errors->{'proxy'} = 'The proxy used by this request is blocked';
      #  }
      #}

      # Price Check - Overwrites easycart item price data... I do not think it belongs in fraud.
      #if ($fraudConfig->get('chkprice')) {
      #  $self->checkPrice($username, $transactionObject);
      #}

      # Blocks if billing address info doesn't match shipping address info
      if ($fraudConfig->get('billship') && !$self->billingMatchesShipping($transactionObject)) {
        $errors->{'billShip'} = 'Billing address does not match Shipping address';
      }
    }
  }

  #Because we also put fraud in pnpmisc :|
  if ($fraudConfig->get('status') eq 'live' && !defined $transactionObject->hasTransFlag('nofraudcheck') && !$transactionObject->getIgnoreFraudCheckResponse()) {
    if ($self->checkFraud($transactionObject->getPayment()->getCardHash())) {
      $errors->{'fraudCheck'} = 'Credit Card number has been flagged as fraudulent and can not be used to access this service';
    }
  }

  my @errorKeys = keys %{$errors};
  my $response = {'isFraud' => 0};

  #If blocked by at least one fraud check then we have error response, special case for duplicates
  if (@errorKeys > 0) {
    my $fraudLogger = new PlugNPay::Fraud::Logging();
    $response->{'errors'} = $errors;
    $response->{'isFraud'} = 1;
    $response->{'finalStatus'} = 'fraud';
    if (exists $errors->{'duplicateCheck'}) {
      $response->{'isDuplicate'} = 1;
      $response->{'duplicateData'} = $errors->{'duplicateCheck'};
      $response->{'finalStatus'} = 'duplicate';
    }
    $fraudLogger->log($transactionObject, $response);
    my $logId = $self->_logToDataLog($response->{'errors'}, {'username' => $username, 'orderID' => $transactionObject->getOrderID()});
    $response->{'logId'} = $logId;
  }

  return $response
}

# A small fraud check for after the transaction is complete
# Confusingly, or due to poor naming conventions, this is only for finished auths, NOT POSTAUTH TRANSACTION!
sub postAuthScreen {
  my $self = shift;
  my $transactionObject = shift;
  my $responseObject = shift;
  my $fraudConfig = shift || $self->getFraudConfig();
  my $accountObject = new PlugNPay::GatewayAccount($transactionObject->getGatewayAccount());

  if ($transactionObject->getIgnoreFraudCheckResponse()) {
    return {};
  }

  # If fraudConfig is a string not a Featurse obj
  if (ref($fraudConfig) ne 'PlugNPay::Features') {
    my $tempFraudConfig = new PlugNPay::Features('fraud_config');
    $tempFraudConfig->parseFeatureString($fraudConfig);
    $fraudConfig = $tempFraudConfig;
  }

  my $avsCode = uc($responseObject->getAVSResponse());
  $avsCode =~ s/[^A-Z]//g;
  $avsCode = substr($avsCode,-1,1);
  if ($avsCode eq '') {
    $avsCode = 'U';
  }

  my $cvvCode = $responseObject->getSecurityCodeResponse();
  my $finalStatus = $responseObject->getStatus();

  my $isBlocked = 0;
  my $message = $responseObject->getErrorMessage();

  # A fraud hold if CVV and AVS are bad values and we passed amount limit and we want to fraud hold
  if ($fraudConfig->get('fraudhold') && $fraudConfig->get('highlimit')
      && !$fraudConfig->get('ignhighlimit') && $cvvCode ne 'M' && $avsCode !~ /^(Y|X|D|M|F)$/)
  {
     my $limit = $fraudConfig->get('highlimit') || 0;
     if ($limit > 0 && $transactionObject->getTransactionAmount() > $limit) {
        $isBlocked = 1;
        $finalStatus = 'hold';
        $message .= ' ' . $avsCode . ':' . $cvvCode;
      }
  }

  # Card only checks
  if ($transactionObject->getTransactionPaymentType() ne 'ach') {
    # If we want to match billing and card countries, but after we do the transaction for some reason?
    if ($fraudConfig->get('matchcntry') && $accountObject->getFeatures()->get('postauthfraud') =~ /matchcntry/) {
      my $binCheckObj = new PlugNPay::Fraud::Bin($transactionObject->getGatewayAccount());
      my $countryMatch = $binCheckObj->matchBINCountry($transactionObject->getPayment()->getBIN());
      my $billingCountry = $transactionObject->getBillingInformation()->getCountry();
      if (lc($billingCountry) ne lc($countryMatch)) {
        $finalStatus = 'fraud';
        $message .= ' Billing country does not match card bin country.';
      }
    }

    #TODO: implement check_prepaid, but not sure how...

    # If we want to block card country after authorization
    if ($fraudConfig->get('blkcntrys') && $accountObject->getFeatures()->get('postauthfraud') =~ /blkcntrys/) {
      my $bankBinChecker = new PlugNPay::Fraud::BankBin($transactionObject->getPayment->getNumber());
      if (defined $bankBinChecker) {
        my $blockStatus = $self->checkCountry($accountObject->getGatewayAccountName(), $fraudConfig, $transactionObject, $bankBinChecker);
        if ($blockStatus->{'isBlocked'}) {
          $finalStatus = 'fraud';
          $message .= ' ' . $blockStatus->{'blockReason'};
        }
      }
    }
  }

  #TODO: Need to reimplement required, probably belongs in Route (definitely not in fraud)
  #my $customData = $transactionObject->getCustomData();
  #if ($customData->{'required'}) {
  #  my $required = $customData->{'required'};
  #  $required =~ s/\,/\|/g;
  #  my @fieldsToCheck = split('|', $required);
  #  foreach my $field (@fieldsToCheck) {
  #
  #  }
  #}

  # Insert into positive DB
  my $positiveDB = new PlugNPay::Fraud::Positive();
  $positiveDB->addPositiveData([{
    'username'          => $accountObject->getGatewayAccountName(),
    'hashedCardNumber'  => $transactionObject->getPayment->getCardHash(),
    'result'            => $finalStatus,
    'orderID'           => $transactionObject->getMerchantTransactionID()
  }]);

  return { 'finalStatus' => $finalStatus, 'message' => $message };
}

###########################
# All secondary functions #
###########################

# GeoLocation
# Checks the country associated with the IP Address
sub checkIPCountry {
  my $self = shift;
  my $username = shift;
  my $ipAddress = shift;
  my $fraudConfig = shift;
  my $matchedCountry;

  eval {
    my $locator = new PlugNPay::Util::IP::Geo();
    $matchedCountry = $locator->lookupCountryCode($ipAddress);
  };

  if ($@) {
    my $geoLocator = new PlugNPay::Fraud::GeoLocate($ipAddress);
    $matchedCountry = $geoLocator->getCountry();
  }

  my $isBlocked = 0;
  my $blockReason = '';

  if (length($matchedCountry) == 3) {
    $matchedCountry = new PlugNPay::Country()->twoFromThree($matchedCountry);
  } elsif (length($matchedCountry) != 2) {
    $matchedCountry = new PlugNPay::Country($matchedCountry)->getTwoLetter();
  }

  # Now we make sure our IP Country is one we allow from
  #TODO: better way of checking region
  if (!$fraudConfig->get('allow_src_all')) {
    if ((!$fraudConfig->get('allow_src_us') && $matchedCountry =~ /US|USA/i)
       || (!$fraudConfig->get('allow_src_ca') && $matchedCountry =~ /CA|CAN/i)
       || (!$fraudConfig->get('allow_src_mx') && $matchedCountry =~ /MX/i)
       || (!$fraudConfig->get('allow_src_eu') && $matchedCountry =~ /UK|GB|DE|ES|IE|IT|FR/i)
       || (!$fraudConfig->get('allow_src_lac') && $matchedCountry =~ /BZ|GT|EC|PA|HN|SV|CR|NI/i)
       || ($fraudConfig->get('blk_src_eastern') && $matchedCountry =~ /RS|UA|PL|HU|RU|CH/i))
    {
      $isBlocked = 1;
    } else {
      my $ipCountryChecker = new PlugNPay::Fraud::GeoLocate::IPCountry($username);
      $isBlocked = $ipCountryChecker->isIPBlocked([$matchedCountry]);
    }
  }

  if ($isBlocked) {
    $blockReason = 'This IPs source country is currently being blocked.';
  }

  return { 'isBlocked' => $isBlocked, 'blockReason' => $blockReason };
}

# Check that billing name is valid
sub checkCardName {
  my $self = shift;
  my $billingName = shift;

  $billingName =~ s/[^a-zA-Z\ ]//g;
  my @nameData = split(/\s+/,$billingName);
  my $isBlocked = 0;
  if (@nameData >= 2) {
    my $firstName = $nameData[0];
    my $lastName = $nameData[$#nameData];
    if ($lastName =~ /(i|ii|iii|iv|v|vi|vii|viii|ix|x|jr|sr|esq)$/i) { # Bill S. Preston Esquire
      $lastName = $nameData[$#nameData-1] . " " . $nameData[$#nameData];
    }

    my $firstNameLength = length($firstName);
    my $lastNameLength = length($lastName);
    $lastName =~ s/aeiouy//ig;
    my $filteredLastNameLength = length($lastName);

    my $validFirstName = $firstNameLength > 0;
    my $validLastName = ($lastNameLength > 2 && $filteredLastNameLength > 1);

    $isBlocked = !($validFirstName && $validLastName);
  } else {
    $isBlocked = 1;
  }

  return {
    'isBlocked' => $isBlocked,
    'blockReason' => $isBlocked ? 'Improper or illegal format for billing name' : ''
  }
}

# Call Email Address module to make sure our email is not in email_fraud tables
sub checkEmailAddresses {
  my $self = shift;
  my $username = shift;
  my $emailAddress = shift;

  my $emailChecker = new PlugNPay::Fraud::Contact::EmailAddress($username);
  my $response = {
    'isBlocked' => $emailChecker->isEmailBlocked($emailAddress)
  };

  if ($response->{'isBlocked'}) {
    $response->{'blockReason'} = 'Payments associated with this Email Address are currently not being accepted.';
  }

  return $response;
}

# Call Phone module to make sure our phone/fax number is not in phone_fraud
sub checkPhoneNumber {
  my $self = shift;
  my $username = shift;
  my $phoneNumber = shift;

  my $phoneChecker = new PlugNPay::Fraud::Contact::Phone($username);
  my $response = {
    'isBlocked' => $phoneChecker->isPhoneBlocked($phoneNumber)
  };

  if ($response->{'isBlocked'}) {
    $response->{'blockReason'} = 'Payments associated with this phone number(s) are currently not being accepted.';
  }

  return $response;
}

#Bin specific checks
sub checkBin {
  my $self = shift;
  my $options = shift;

  #parse options cause why not
  my $username = $options->{'gatewayAccount'};
  my $features = $options->{'features'};
  my $fraudConfig = $options->{'fraudConfig'} || $self->getFraudConfig();
  my $paymentObject = $options->{'paymentObject'};
  my $transactionObject = $options->{'transactionData'};
  my $response = {};

  # We need features
  if (ref($features) ne 'PlugNPay::Features') {
    my $accountObj = new PlugNPay::GatewayAccount($username);
    $features = $accountObj->getFeatures();
  }

  # These only work on cards because it is card checks
  if (ref($paymentObject) eq 'PlugNPay::CreditCard') {
    my $binCheckObj = new PlugNPay::Fraud::Bin($username);
    my $bankBinChecker = $binCheckObj->checkBankBin($paymentObject->getNumber());

    #Bank bin checker is only defined if the bankBin check was successful
    if (defined $bankBinChecker) {
      # If card region is not allowed then we block
      if ($features->get('bindetails') || $fraudConfig->get('chkbin') || $fraudConfig->get('bankbin_reg')) {
        $response->{'region'} = $self->checkBinRegion($fraudConfig, $bankBinChecker);
      }

      # If the card is a foregin Visa or MasterCard, and if we do not allow that, then we block
      if ($fraudConfig->get('blkfrgnvs') || $fraudConfig->get('blkfrgnmc')) {
        $response->{'card'} = $self->checkBinCardType($fraudConfig, $bankBinChecker);
      }

      # Checks if card should be blocked based on counry of origin
      if ($fraudConfig->get('blkcntrys') && $features->get('postauthfraud') !~ /blkcntrys/) {
        $response->{'country'} = $self->checkCountry($username, $fraudConfig, $transactionObject, $bankBinChecker);
      }

      # Checks if card BIN is in block table
      if ($fraudConfig->get('blkbin')) {
        my $isBlocked = $binCheckObj->isBinInTable($paymentObject->getBIN());
        $response->{'bin'} = {
          'isBlocked' => $isBlocked,
          'blockReason' => ($isBlocked ? 'Credit Cards issued from this bank are currently not being accepted.' : '')
        };
      } elsif ($fraudConfig->get('allowbin')) { # We check to see if BIN is in allowed table, otherwise we block
        my $isBlocked = !$binCheckObj->isBinInTable($paymentObject->getBIN());
        $response->{'bin'} = {
          'isBlocked' => $isBlocked,
          'blockReason' => ($isBlocked ? 'Credit Cards issued from this bank are currently not being accepted.' : '')
        };
      }

      #Match card country to billing
      if ($fraudConfig->get('matchcntry') && $features->get('postauthfraud') !~ /matchcntry/) {
        my $countryMatch = $binCheckObj->findMatchedBINCountry($paymentObject->getBIN());
        my $billingCountry = $transactionObject->getBillingInformation()->getCountry();
        my $isBlocked = lc($countryMatch) eq lc($billingCountry);
        $response->{'matchCountry'} = {
          'isBlocked' => $isBlocked,
          'blockReason' => ($isBlocked ? 'Billing country does not match card issuing country. ' . $countryMatch . ':' . $billingCountry : '')
        };
      }
    }
  }

  return $response;
}

# Checks if we should block card based on being a foreign Visa or MasterCard
sub checkBinCardType {
  my $self = shift;
  my $fraudConfig = shift;
  my $binChecker = shift;
  my $binCountry = uc($binChecker->getCountry());
  my $cardType = uc($binChecker->getCardType());
  my $response = {};

  if ($binCountry ne 'US') {
    if ($fraudConfig->get('blkfrgnvs') && $cardType eq 'VISA') {
      $response->{'isBlocked'} = 1;
      $response->{'blockReason'} = 'Foreign Visa cards are blocked. Country: ' . $binCountry;
    } elsif ($fraudConfig->get('blkfrgnmc') && $cardType eq 'MSTR') {
      $response->{'isBlocked'} = 1;
      $response->{'blockReason'} = 'Foreign MasterCard/Maestro cards are blocked. Country: ' . $binCountry;
    }
  }

  return $response;
}

# Checks if card is from blocked region
sub checkBinRegion {
  my $self = shift;
  my $fraudConfig = shift;
  my $bankBinChecker = shift;

  my $blockReason = '';
  my $bankBinAction = $fraudConfig->get('bankbin_reg_action');
  my $isBlocked = 0;
  my $matches = 0;
  my $binRegion = $bankBinChecker->getRegion();
  if (($fraudConfig->get('bin_reg_us') && $binRegion eq 'USA')
     || ($fraudConfig->get('bin_reg_ca') && $binRegion eq 'CAN')
     || ($fraudConfig->get('bin_reg_lac') && $binRegion eq 'LAC')
     || ($fraudConfig->get('bin_reg_ap') && $binRegion eq 'AP')
     || ($fraudConfig->get('bin_reg_eu') && $binRegion eq 'EU')
     || ($fraudConfig->get('bin_reg_samea') && $binRegion eq 'SAMEA')
     ) {
    $matches = 1; #bank bin region matches blocked region
  }

  if ($bankBinAction eq 'block') {
    $isBlocked = $matches ? 1 : 0;
  } elsif ($bankBinAction eq 'allow') {
    $isBlocked = $matches ? 0 : 1;
  }

  if ($isBlocked) {
    $blockReason = 'Cards issued from geographic region are not allowed. Region: ' . $binRegion;
  }

  return {'isBlocked' => $isBlocked, 'blockReason' => $blockReason};
}

# Checks if card should be blocked based on originating country
sub checkCountry {
  my $self = shift;
  my $username = shift;
  my $fraudConfig = shift;
  my $transactionObject = shift;
  my $bankBinChecker = shift;

  my $country = $bankBinChecker->getCountry() || $transactionObject->getBillingInformation()->getCountry();
  my $isBlocked = PlugNPay::Fraud::Country::isBlocked($username, $country);
  return {
     'isBlocked' =>  $isBlocked,
     'blockReason' => ($isBlocked ? 'Billing Country on Blocked List. Country: ' . $country : '')
  };
}

# Checks if we accept the card brand and type
sub checkCard {
  my $self = shift;
  my $fraudConfig = shift;
  my $paymentObject = shift;
  my $isBlocked = 0;
  my $blockReason = '';
  if (ref($paymentObject) eq 'PlugNPay::CreditCard') {
    if (($fraudConfig->get('blkvs') && $paymentObject->getBrand() =~ /VISA/i)  # Block Visa
       || ($fraudConfig->get('blkmc') && $paymentObject->getBrand() =~ /MSTR/i)  # Block Master Card
       || ($fraudConfig->get('blkax') && $paymentObject->getBrand() =~ /AMEX/i)  # Block American Express
       || ($fraudConfig->get('blkds') && $paymentObject->getBrand() =~ /DSCR|DNRS/i)) { # Block Discover and Diners Club
      $isBlocked = 1;
      $blockReason = 'Blocked by card brand: ' . $paymentObject->getBrandName();
   } elsif (($fraudConfig->get('blkdebit') && $paymentObject->getCategory() =~ /DEBIT/i) # Block Debit
        || ($fraudConfig->get('blkcredit') && $paymentObject->getCategory() !~ /DEBIT/i)) { # Block Credit
      $isBlocked = 1;
      $blockReason = 'Blocked by card type: ' . $paymentObject->getCategory();
    }
  }

  return {'isBlocked' => $isBlocked, 'blockReason' => $blockReason};
}

# Inputs and Fields
# Checks those three required fields
sub checkRequiredFields {
  my $self = shift;
  my $fraudConfig = shift;
  my $transactionObject = shift;
  my $isBlocked = 0;
  my $blockReason = '';
  my $address1 = $transactionObject->getBillingInformation()->getAddress1();
  $address1 =~ s/[^a-zA-Z0-9 \.\-,]//g;

  my $postalCode = $transactionObject->getBillingInformation()->getPostalCode();
  $postalCode =~ s/[^a-zA-Z0-9 ]//g;

  my $country = $transactionObject->getBillingInformation()->getCountry();
  $country =~ s/[^a-zA-Z ]//g;

  my @missingFields = ();
  if ($fraudConfig->get('reqaddr') && !$address1) {
    push @missingFields, 'address';
  }

  if ($fraudConfig->get('reqzip') && !$postalCode) {
    push @missingFields, 'postal code';
  }

  if ($fraudConfig->get('reqcountry') && !$country) {
    push @missingFields, 'country';
  }

  if (@missingFields > 0) {
    $isBlocked = 1;
    $blockReason = 'Blocked for missing field(s): ' . join(', ',@missingFields);
  }

  return {'isBlocked' => $isBlocked, 'blockReason' => $blockReason};
}

# Checks if PNP REMOTE sent valid inputs
sub inputCheck {
  my $self = shift;
  my $fraudConfig = shift;
  my $paymentObject = shift;
  my $transactionObject = shift;
  my $errors = {};
  my $accountCode4 = $transactionObject->getAccountCode(4);

  if ($transactionObject->getTransactionPaymentType() eq 'ach') {
    if (length($paymentObject->getAccountNumber()) < 5) {
      $errors->{'blockReason'} = 'invalid account number: insufficient length';
    } elsif (!$paymentObject->getInternationalRoutingNumber() && !$paymentObject->verifyABARoutingNumber()) {
      $errors->{'blockReason'} = 'invalid routing number: routing number failed MOD10 check';
    }
  } else {
    my $accountCode4 = $transactionObject->getAccountCode(4);
    if ($paymentObject->getNumber() < 10 && !$paymentObject->getMagstripe()) {
      $errors->{'blockReason'} = 'invalid card: invalid card number length';
    } elsif (!$paymentObject->verifyLuhn10()) {
      $errors->{'blockReason'} = 'invalid card: card failed LUHN10 check';
    } elsif ($fraudConfig->get('cvv') && (!$paymentObject->getMagstripe() && !$transactionObject->hasTransFlag('recurring') && $accountCode4 ne 'authprev')) {
      if (($paymentObject->getBrand() =~ /VISA|MSTR|DSCR|DNRS/ && length($paymentObject->getSecurityCode()) != 3)
         || ($paymentObject->getBrand() =~ /AMEX|AX/ && length($paymentObject->getSecurityCode()) != 4)) {
        $errors->{'blockReason'} = 'invalid card: cvv has an invalid length';
      }
    } elsif ($paymentObject->isExpired() && !$transactionObject->hasTransFlag('recurring')) {
      $errors->{'blockReason'} = 'invalid card: card is expired';
    }
  }

  if ($errors->{'blockReason'}) {
    $errors->{'isBlocked'} = 1;
  }

  return $errors;
}

#Check pnpmisc's fraud stuff (there's fraud tables in every db because what is organization)
sub checkFraud {
  my $self = shift;
  my $hashedNumber = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $rows = [];
  my $select = q/
    SELECT COUNT(*) AS `count`
      FROM fraud
     WHERE enccardnumber = ?
  /;
  eval {
    $rows = $dbs->fetchallOrDie('pnpmisc', $select, [$hashedNumber], {})->{'result'};
  };

  if ($@) {
    $self->_logToDataLog($@, {'function' => 'checkFraud'});
  }

  return $rows->[0]{'count'} > 0;
}

# This is a function that checks the fraud settings of "fraud linked accounts"
# Those are like linked accounts, but only for fraud
sub checkFraudAccounts {
  my $self = shift;
  my $accountListString = shift;
  my $paymentObject = shift;
  my $subAccountResponse = {};

  if ($accountListString && ref($paymentObject eq 'PlugNPay::CreditCard')) {
    my @accountList = split(/\|/,$accountListString);
    foreach my $subAccount (@accountList) {
      my $subAccountObj = new PlugNPay::GatewayAccount($subAccount);
      my $parsedConfig = $subAccountObj->getParsedFraudConfig();

      #Do the Dew
      if ($parsedConfig->get('blkfrgnvs') || $parsedConfig->get('blkfrgnmc')) {
        my $subBankBinChecker = new PlugNPay::Fraud::BankBin($paymentObject->getNumber());
        if (defined $subBankBinChecker) {
          $subAccountResponse = $self->checkBinCardType($parsedConfig, $subBankBinChecker);
        }
      }

      if ($subAccountResponse->{'isBlocked'}) {
        $subAccountResponse->{'matchedAccount'} = $subAccount;
        last;
      }
    }
  }

  return $subAccountResponse;
}

# Make sure Billing Address matches Shipping Address
sub billingMatchesShipping {
  my $self = shift;
  my $transactionObject = shift;

  my $matches = 0;
  my $billingObj = $transactionObject->getBillingInformation();
  my $shippingObj = $transactionObject->getShippingInformation();
  if (ref($billingObj) eq 'PlugNPay::Contact' && ref($shippingObj) eq 'PlugNPay::Contact') {
    my $address1Match = $shippingObj->getAddress1() eq $billingObj->getAddress1();
    my $address2Match = $shippingObj->getAddress2() eq $billingObj->getAddress2();
    my $cityMatch     = $shippingObj->getCity() eq $billingObj->getCity();
    my $stateMatch    = $shippingObj->getState() eq $billingObj->getState();
    my $countryMatch  = $shippingObj->getCountry() eq $billingObj->getCountry();
    my $zipMatch      = $shippingObj->getPostalCode() eq $billingObj->getPostalCode();

    $matches = $address1Match && $address2Match && $cityMatch && $stateMatch && $countryMatch && $zipMatch;
  }

  return $matches;
}

# Log to datalog collection 'fraudtrack'
sub _logToDataLog {
  my $self = shift;
  my $errors = shift;
  my $data = shift || {};

  my $dataLog = new PlugNPay::Logging::DataLog({'collection' => 'fraudtrack'});
  my (undef, $logId) = $dataLog->log({
    'error'  => $errors,
    'data'   => $data,
    'module' => 'PlugNPay::Fraud'
  });

  return $logId;
}

1;
