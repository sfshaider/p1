package PlugNPay::Transaction::MapAPI;

use strict;

use PlugNPay::API;
use PlugNPay::Transaction;
use PlugNPay::CreditCard;
use PlugNPay::OnlineCheck;
use PlugNPay::Contact;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  return $self;
}

sub setAPI {
  my $self = shift;
  $self->{'api'} = shift;
}

sub getAPI {
  my $self = shift;
  return $self->{'api'};
}

sub setAPIContext {
  my $self = shift;
  $self->getAPI()->setContext(shift);
}

sub setParameters {
  my $self = shift;
  $self->getAPI()->setParameters(shift);
}

sub getParameters {
  my $self = shift;
  return $self->getAPI()->getParameters();
}

sub setTransaction {
  my $self = shift;
  $self->{'transaction'} = shift;
}

sub getTransaction {
  my $self = shift;
  return $self->{'transaction'};
}

sub map {
  my $self = shift;

  my ($transaction,$api);
  if (@_) {
    # $api => $transaction # yes i'm sneaky, beautiful syntax eh?
    ($api,$transaction) = @_;
  } else {
    $transaction = $self->{'transaction'};
    $api = $self->{'api'};
  }


  ### Set the gateway account if none is currently set and it exists in $api ###
  if (!defined $transaction) {
    die('Transaction Object is not defined. MapAPI->map() called by: ' . join('::',caller()) . "\n");
  }

  my $currentGatewayAccount;

  # getGatewayAccount throws error if not already set.
  eval {
    $currentGatewayAccount = $transaction->getGatewayAccount();
  };

  if ($api->parameter('pt_gateway_account') ne '' && $currentGatewayAccount eq '') {
    $transaction->setGatewayAccount($api->parameter('pt_gateway_account'));
  }

  if ($api->parameter('pt_ip_address'))  {
    $transaction->setIPAddress($api->parameter('pt_ip_address'));
  }

  ### Start mapping
  #######################################################################################################################
  ### Note that transaction type is not set here as it is determined by the superclass of the transaction object used.
  #######################################################################################################################
  $transaction->setOrderID($api->parameter('pt_order_id'));
  $transaction->setInitialOrderID($api->parameter('pt_initial_order_id')) if $api->parameter('pt_initial_order_id');
  $transaction->setCurrency($api->parameter('pt_currency'));
  $transaction->setTransactionAmount($api->parameter('pt_transaction_amount'));
  $transaction->setTaxAmount($api->parameter('pt_tax_amount'));


  # Create Credit Card Object if pt_card_number, pt_magstripe, or pt_magensa exists
  if ($api->parameter('pt_card_number') || $api->parameter('pt_magstripe') || $api->parameter('pt_magensa')) {
    my $magstripe = $api->parameter('pt_magstripe');
    my $magensa = $api->parameter('pt_magensa');
    my $cc = new PlugNPay::CreditCard();
    $cc->setMagensa($magensa);
    $cc->setSwipeDevice($api->parameter('pt_swipe_device'));
    my $cvv;

    if ($magensa) {
      my $decryptedData = $cc->decryptMagensa($magensa, $transaction->getGatewayAccount());

      # set magstripe
      my $magensaMagstripe = $decryptedData->{'magstripe'};
      $cc->setMagstripe($magensaMagstripe);

      # set card number
      my $decryptedCardNumber = $decryptedData->{'card-number'};
      $cc->setNumber($decryptedCardNumber);

      # set cvv
      $cvv = $decryptedData->{'card-cvv'};

      # set error
      if ($decryptedData->{'error'}) {
        my $error = 'Decrypt Error: ' . $decryptedData->{'errorMessage'};
        $transaction->setValidationError($error);
      }
    }

    if ($magstripe) {
      $cc->setMagstripe($magstripe);
    }

    if (!$magensa) {
      $cc->setNumber($api->parameter('pt_card_number'));
    }

    $cc->setName($api->parameter('pt_payment_name'));
    $cc->setSecurityCode($cvv || $api->parameter('pt_card_security_code'));
    $cc->setExpirationMonth($api->parameter('pt_card_expiration_month'));
    $cc->setExpirationYear($api->parameter('pt_card_expiration_year'));
    if ($api->parameter('pt_is_business_account')) {
      $cc->setCommCardType('business');
    }
    if(($api->parameter('pt_purchase_order_number') && $api->parameter('pt_tax_amount'))) {
      $cc->setCommCardType('business');
    }

    $transaction->setCreditCard($cc);
  }

  #set fraud config
  if ($api->parameter('pb_ignore_security_code_response') eq 'yes') {
    $transaction->setIgnoreCVVResponse();
  }
  if ($api->parameter('pb_ignore_fraud_response') eq 'yes') {
    $transaction->setIgnoreFraudCheckResponse();
  }

  # Create Gift Card Object if pt_gift_card_number exists
  if ($api->parameter('pt_gift_card_number')) {
    my $gc = new PlugNPay::CreditCard();
    $gc->setNumber($api->parameter('pt_gift_card_number'));
    $gc->setSecurityCode($api->parameter('pt_gift_card_security_code'));

    $transaction->setGiftCard($gc);
  }

  # Create OnlineCheck object if routingnum and  accountnum exist
  if ($api->parameter('pt_ach_routing_number') && $api->parameter('pt_ach_account_number')) {
    my $oc = new PlugNPay::OnlineCheck();
    $oc->setName($api->parameter('pt_payment_name'));
    $oc->setABARoutingNumber($api->parameter('pt_ach_routing_number'));
    $oc->setAccountNumber($api->parameter('pt_ach_account_number'));
    $oc->setAccountType($api->parameter('pt_ach_account_type'));
    $transaction->setOnlineCheck($oc);
    $transaction->setSECCode($api->parameter('pt_ach_sec_code'));
  }

  if ($api->parameter('pb_post_auth') eq 'yes') {
    $transaction->setPostAuth();
  }

  # Create Billing Info Contact Object
  my $billingInfo = new PlugNPay::Contact();
  $billingInfo->setFullName($api->parameter('pt_billing_name'));
  $billingInfo->setAddress1($api->parameter('pt_billing_address_1'));
  $billingInfo->setAddress2($api->parameter('pt_billing_address_2'));
  $billingInfo->setCity($api->parameter('pt_billing_city'));
  $billingInfo->setState($api->parameter('pt_billing_state'));
  $billingInfo->setInternationalProvince($api->parameter('pt_billing_province'));
  $billingInfo->setPostalCode($api->parameter('pt_billing_postal_code'));
  $billingInfo->setCountry($api->parameter('pt_billing_country'));
  $billingInfo->setEmailAddress($api->parameter('pt_billing_email_address'));
  $billingInfo->setPhone($api->parameter('pt_billing_phone_number'));
  $transaction->setBillingInformation($billingInfo);

  # Create Shipping Info Contact Object
  my $shippingInfo = new PlugNPay::Contact();
  $shippingInfo->setFullName($api->parameter('pt_shipping_name'));
  $shippingInfo->setAddress1($api->parameter('pt_shipping_address_1'));
  $shippingInfo->setAddress2($api->parameter('pt_shipping_address_2'));
  $shippingInfo->setCity($api->parameter('pt_shipping_city'));
  $shippingInfo->setState($api->parameter('pt_shipping_state'));
  $shippingInfo->setInternationalProvince($api->parameter('pt_shipping_province'));
  $shippingInfo->setPostalCode($api->parameter('pt_shipping_postal_code'));
  $shippingInfo->setCountry($api->parameter('pt_shipping_country'));
  $shippingInfo->setEmailAddress($api->parameter('pt_shipping_email_address'));
  $shippingInfo->setPhone($api->parameter('pt_shipping_phone_number'));
  $transaction->setShippingInformation($shippingInfo);

  # Set Account Codes
  $transaction->setAccountCode(1,$api->parameter('pt_account_code_1'));
  $transaction->setAccountCode(2,$api->parameter('pt_account_code_2'));
  $transaction->setAccountCode(3,$api->parameter('pt_account_code_3'));

  # Set TransFlags
  if ($api->parameter('pr_is_recurring') eq "yes") {
    $transaction->addTransFlag('recurring');
  }
  if ($api->parameter('pr_is_initial')) {
    $transaction->addTransFlag('recinitial');
  }
  if ($api->parameter('pb_credit_fund_transfer') eq "yes") {
    $transaction->addTransFlag('fund');
  }

  # Set custom fields
  my $customFields = $api->getCustomFields();
  # get the numbers of the pt_custom_name_ fields
  my @customNumbers = sort { $a <=> $b } map { $_ =~ s/.+?_(\d+)$/\1/; $_ } grep { /^pt_custom_name/ } keys %{$customFields};
  my %customData;
  foreach my $number (@customNumbers) {
    $customData{$customFields->{'pt_custom_name_' . $number}} = $customFields->{'pt_custom_value_' . $number};
  }
  $transaction->setCustomData(\%customData);

  # Set item data.
  # Get item fields and then normalize them into new item numbers.
  # For example, if pt_item_identifier_100 was the first item, that becomes itemData{'item1'}{'identifier'})
  my %itemFields = $api->getItemFields();
  # get the numbers of the pt_item_identifier fields
  my @itemNumbers = sort { $a <=> $b } map { $_ =~ s/.+?_(\d+)$/$1/; } grep { /^pt_item_identifier/ } keys %itemFields;
  my %itemData;
  my $itemIndex = 1;
  foreach my $number (@itemNumbers) {
    $itemData{'item' . $itemIndex}{'identifier'}  = $itemFields{'pt_item_identifier_' . $number};
    $itemData{'item' . $itemIndex}{'cost'}        = $itemFields{'pt_item_cost_' . $number};
    $itemData{'item' . $itemIndex}{'quantity'}    = $itemFields{'pt_item_quantity_' . $number};
    $itemData{'item' . $itemIndex}{'description'} = $itemFields{'pt_item_description_' . $number};
    $itemData{'item' . $itemIndex}{'is_taxable'}  = $itemFields{'pt_item_is_taxable_' . $number};
    $itemIndex++;
  }
  $transaction->setItemData(\%itemData);

  # Set order id if one exists
  if ($api->parameter('pt_order_id')) {
    $transaction->setOrderID($api->parameter('pt_order_id'));
  }

  if ($api->parameter('pt_order_classifier')) {
    $transaction->setMerchantClassifierID($api->parameter('pt_order_classifier'));
  }

  # Set PO Number
  $transaction->setPurchaseOrderNumber($api->parameter('pt_purchase_order_number'));

  # Set Override Adjustment option
  if ($api->parameter('pb_override_adjustment') eq 'yes') {
    $transaction->setOverrideAdjustment();
  }
}


1;
