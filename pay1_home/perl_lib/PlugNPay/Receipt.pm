package PlugNPay::Receipt;

use strict;

use PlugNPay::UI::Template;
use PlugNPay::Util::MetaTag;
use PlugNPay::Currency;
use PlugNPay::Sys::Time;
use PlugNPay::DBConnection;
use PlugNPay::Util::Cache::LRUCache;
use PlugNPay::Transaction::Loader;
use PlugNPay::Features;

our $cache;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!defined $cache) {
    $cache = new PlugNPay::Util::Cache::LRUCache(20);
  }

  return $self;
}

sub setGatewayAccount {
  my $self = shift;
  my $account = lc shift;
  $account =~ s/[^a-z0-9]//g;
  $self->{'account'} = $account;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'account'};
}

sub setTemplate {
  my $self = shift;
  my $template = shift;
  $self->{'template'} = $template;
}

sub getTemplate {
  my $self = shift;
  return $self->{'template'};
}

sub setTransaction {
  my $self = shift;
  my $transaction = shift;
  $self->{'transaction'} = $transaction;
  $self->setGatewayAccount($transaction->getGatewayAccount());
}

sub getTransaction {
  my $self = shift;
  return $self->{'transaction'};
}

sub setResponse {
  my $self = shift;
  my $response = shift;
  $self->{'transactionResponse'} = $response;
}

sub getResponse {
  my $self = shift;
  return $self->{'transactionResponse'};
}


sub getReceipt {
  my $self = shift;
  my $settings = shift;
  my $type = $settings;

  if (ref($settings) eq 'HASH') {
    $type = $settings->{'type'};
  }

  my $templates = '';
  my $templateHTML = '';
  my $templateText = '';

  my $transaction = $self->getTransaction();
  my $response = $self->getResponse();
  my $account = new PlugNPay::GatewayAccount($self->getGatewayAccount());

  if (!defined $transaction || !defined $response) {
    return '';
  }

  my $paymentType = $transaction->getTransactionPaymentType();

  if (defined $type && $type ne '') {
    $templates = ($self->loadTemplateForTypeAndPaymentType($type,$paymentType));
    $templateHTML = $templates->{'html'};
    $templateText = $templates->{'text'};
  } else {
    $templates = $self->getTemplate();
  }

  my $currency = $self->getTransaction()->getCurrency();
  my $precision = new PlugNPay::Currency($currency)->getPrecision();

  # Turn [var:parameter] into <metavar="parameter"> so Template.pm can parse it
  # [var:parameter] syntax is much easier for customers to understand.
  $templateHTML =~ s/\[var:(.*?)\]/<metavar="$1">/g;
  $templateText =~ s/\[var:(.*?)\]/<metavar="$1">/g;
  
  my $t = new PlugNPay::UI::Template;

  my $amount = $transaction->getTransactionAmount();

  # format the transaction time (make this customziable?)
  my $transactionFeatures = $account->getFeatures();
  my $timezone = $transactionFeatures->get('timezone');
 
  my $transactionTime = new PlugNPay::Sys::Time();
  
  my $tempTransTime = $transactionTime->inFormatDetectType('unix',$transaction->getTime());
  $transactionTime->fromFormat('unix',$tempTransTime);
  $transactionTime->setTimeZone($timezone);

  my $timezoneCode = $transactionTime->getTimeZoneCode();
   
  my $formattedTime = $transactionTime->inFormat('log_timezone') . ' ' . $timezoneCode;
  
  # get the currency symbol/code
  $currency = $transaction->getCurrency();
  my $currencySymbol; 
  if ($templateHTML ne '') {
    my $currencyInfo = new PlugNPay::Currency($currency);
    $currencySymbol = $currencyInfo->getHTMLEncoding();
  } elsif ($templateText ne '') {
    $currencySymbol = (uc $currency) . ' ';
  }

  # Get the convenienceCharge if one exists
  my $convenienceChargeInfo = $transaction->getTransactionInfoForConvenienceCharge();
  my $convenienceChargeAmount = '0.00';
  if (defined $convenienceChargeInfo) {
    my $convenienceChargeTransaction = $transaction->getConvenienceChargeTransactionLink();

    # if loading it directly did not work, try loading it from the database
    if (!defined $convenienceChargeTransaction) {
      my $transactions = PlugNPay::Transaction::Loader::load($convenienceChargeInfo);
      $convenienceChargeTransaction = $transactions->{$convenienceChargeInfo->{'gatewayAccount'}}{$convenienceChargeInfo->{'orderID'}};
    }

    # if we were able to load a transaction, set the charge amount from the convenience charge transaction information
    if ($convenienceChargeTransaction) {
      $convenienceChargeAmount = $convenienceChargeTransaction->getTransactionAmount();
    }
  }

  my $total = sprintf('%.' . $precision . 'f',$amount + $convenienceChargeAmount);

  # get payment info
  my $payment = $transaction->getPayment();
  my $expiration; # only used if payment type is credit
  my $cardNumber; # same here.
  my $cardBrand;  # ditto.
  my $accountNumber; # used only if payment type is ach
  if ($paymentType eq 'credit') {
    $expiration = $payment->getExpirationMonth() . '/' . $payment->getExpirationYear();;
    $cardNumber = $payment->getMaskedNumber();
    $cardBrand = $payment->getBrand();
  } elsif ($paymentType eq 'ach') {
    $accountNumber = $payment->getMaskedNumber();
  }


  # Set the allowed variables
  $t->setVariables({
    pt_order_id                           => $transaction->getOrderID(),
    pt_transaction_amount                 => $amount,
    pt_transaction_base_amount            => $transaction->getBaseTransactionAmount(),
    pt_transaction_adjustment_amount      => $transaction->getTransactionAmountAdjustment(),
    pt_tax_amount                         => $transaction->getTaxAmount(),
    pt_convenience_charge_amount          => $convenienceChargeAmount,
    pt_total_amount                       => $total,
    pd_currency_symbol                    => $currencySymbol,
    pt_transaction_time                   => $formattedTime,
    pt_card_number                        => $cardNumber,
    pt_card_expiration                    => $expiration,
    pt_card_type                          => $cardBrand,
    pt_card_brand                         => $cardBrand,
    pt_ach_account_number                 => $accountNumber,
    pt_payment_name                       => $payment->getName(),
    pt_transaction_status                 => $response->getStatus(),
    pt_authorization_code                 => $response->getAuthorizationCode(),
    pb_confirmation_sending_email_address => $account->getSendingEmailAddress(),
    pt_account_code_1                     => $transaction->getAccountCode(1),
    pt_account_code_2                     => $transaction->getAccountCode(2),
  });

  # if there is billing info, set those variables
  my $billingInfo = $transaction->getBillingInformation();
  if ($billingInfo) {
    $t->setVariables({
      pt_billing_name                   => $billingInfo->getFullName(),
      pt_billing_address_1              => $billingInfo->getAddress1(),
      pt_billing_address_2              => $billingInfo->getAddress2(),
      pt_billing_city                   => $billingInfo->getCity(),
      pt_billing_state                  => $billingInfo->getState(),
      pt_billing_province               => $billingInfo->getProvince(),
      pt_billing_international_province => $billingInfo->getInternationalProvince(),
      pt_billing_postal_code            => $billingInfo->getPostalCode(),
      pt_billing_email_address          => $billingInfo->getEmailAddress(),
      pt_billing_phone_number           => $billingInfo->getPhone(),
      pt_billing_evening_phone_number   => $billingInfo->getEveningPhone(),
      pt_billing_fax_number             => $billingInfo->getFax()
    });
  }

  # if there is shipping info, set those variables
  my $shippingInfo = $transaction->getShippingInformation();
  if ($shippingInfo) {
    $t->setVariables({
      pt_shipping_name                   => $shippingInfo->getFullName(),
      pt_shipping_address_1              => $shippingInfo->getAddress1(),
      pt_shipping_address_2              => $shippingInfo->getAddress2(),
      pt_shipping_city                   => $shippingInfo->getCity(),
      pt_shipping_state                  => $shippingInfo->getState(),
      pt_shipping_province               => $shippingInfo->getProvince(),
      pt_shipping_international_province => $shippingInfo->getInternationalProvince(),
      pt_shipping_postal_code            => $shippingInfo->getPostalCode(),
      pt_shipping_email_address          => $shippingInfo->getEmailAddress(),
      pt_shipping_phone_number           => $shippingInfo->getPhone(),
      pt_shipping_evening_phone_number   => $shippingInfo->getEveningPhone(),
      pt_shipping_fax_number             => $shippingInfo->getFax()
    });
  }

  # set merchant info
  my $gatewayAccount = new PlugNPay::GatewayAccount($transaction->getGatewayAccount());
  my $companyInfo = $gatewayAccount->getMainContact();
  $t->setVariables({
    pb_receipt_company                => $companyInfo->getCompany(),
    pb_receipt_address_1              => $companyInfo->getAddress1(),
    pb_receipt_address_2              => $companyInfo->getAddress2(),
    pb_receipt_city                   => $companyInfo->getCity(),
    pb_receipt_state                  => $companyInfo->getState(),
    pb_receipt_postal_code            => $companyInfo->getPostalCode(),
    pb_receipt_email_address          => $companyInfo->getEmailAddress(),
    pb_receipt_phone_number           => $companyInfo->getPhone(),
    pb_receipt_fax_number             => $companyInfo->getFax()
  });
  
  my $customFields = $transaction->getCustomData();
  foreach my $field (keys %{$customFields}) {
    $t->setVariable($field,$customFields->{$field});
  }

   my %renderedTemplates;
  $renderedTemplates{'html'} = $t->parseTemplate($templateHTML);
  $renderedTemplates{'text'} = $t->parseTemplate($templateText);

  return \%renderedTemplates;
}

sub loadTemplateForTypeAndPaymentType {
  my $self = shift;
  my $type = shift;
  my $paymentType = shift || 'credit';
  my $contextID = shift || '1';
  my $statusID = shift || '1';

  $type =~ s/[^a-z_]//g;
  $paymentType =~ s/[^a-z]//g;

  my $account = $self->getGatewayAccount();

  my $templates;

  my $cacheKey = $account . ' ' . $type;

  if ($cache->contains($cacheKey)) {
    $templates = $cache->get($cacheKey);
  } else {
    if ($account ne '') {
      my $account = $self->getGatewayAccount();
      my $gatewayAccountObject = new PlugNPay::GatewayAccount($account);
      my $cobrand  = $gatewayAccountObject->getCobrand();
      my $reseller = $gatewayAccountObject->getReseller();

      my $dbh = PlugNPay::DBConnection::database('pnpmisc');
      my $sth = $dbh->prepare(q/
        SELECT html_template,text_template,type
        FROM ui_receipt_template
        WHERE ((type = 'default' && identifier = 'default') OR
               (type = 'reseller' && identifier = ?) OR
               (type = 'cobrand' && identifier = ?) OR
               (type = 'account' && identifier = ?))
          AND receipt_type = ?
          AND payment_type = ?
          AND context_id = ?
          AND status_id = ?
      /);

      $sth->execute($reseller,$cobrand,$account,$type,$paymentType,$contextID,$statusID);
      my $results = $sth->fetchall_arrayref({});
     
      TEMPLATESEARCH:
      foreach my $identifierType ('account','cobrand','reseller','default') {
        foreach my $row (@{$results}) {
          if ($row->{'type'} eq $identifierType) {
            $templates = {'html' => $row->{'html_template'}, 'text' => $row->{'text_template'}};
            last TEMPLATESEARCH;
          }
        }
      }

      $cache->set($cacheKey,$templates);
    }
  }
  return $templates;
}

sub insertTemplates {
  my $self = shift;

  my $accountType = shift;
  my $username = shift;
  my $receiptType = shift;
  my $htmlTemplate = shift;
  my $textTemplate = shift;
  my $paymentType = shift;
  my $approved = shift;
  my $contextID = shift || '1';
  my $statusID = shift || '1';

  if (defined $htmlTemplate && !defined $textTemplate) {
    $textTemplate = $self->convertHTMLToText($htmlTemplate);
  } elsif (!defined $htmlTemplate && defined $textTemplate) {
    $htmlTemplate = $textTemplate;
  }

  my @values = ($accountType,$username,$receiptType,$htmlTemplate,$textTemplate,$paymentType,$approved,$contextID,$statusID);

  my $dbs = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
  my $sth = $dbs->prepare(q/ 
                           INSERT INTO ui_receipt_template
                           (type,identifier,receipt_type,html_template,text_template,payment_type,approved,context_id,status_id)
                           VALUES(?,?,?,?,?,?,?,?,?)
                           ON DUPLICATE KEY UPDATE type = ?,identifier = ?,receipt_type = ?,html_template = ?,text_template = ?,payment_type = ?,approved = ?,context_id = ?,status_id = ?
                          /);
  $sth->execute(@values,@values) or die $DBI::errstr;
  
  $sth->finish();
}

sub loadTemplates{
  my $self = shift;
  my $values = shift;

  my $dbconn = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc'); 
  my $sth = $dbconn->prepare (q/
                               SELECT html_template,text_template FROM ui_receipt_template
                               WHERE identifier = ? AND payment_type = ? AND receipt_type = ? AND type = ? AND context_id = ? AND status_id = ?
                               /);
  $sth->execute($values->{'id'},$values->{'payment_type'},$values->{'receipt_type'}, $values->{'type'}, $values->{'context_id'} || '1', $values->{'status_id'} || '1') or die $DBI::errstr;
  my $hash = {};
  my $row = $sth->fetchrow_hashref();
  $hash->{'html'} = $row->{'html_template'};
  $hash->{'text'} = $row->{'text_template'};
  $sth->finish;

  return $hash;
}

sub deleteTemplates{
  my $self = shift;
  my $values = shift;

  my $dbconn = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
  my $sth = $dbconn->prepare(q/ 
                                DELETE FROM ui_receipt_template
                                WHERE identifier = ? AND payment_type = ? AND type = ? AND receipt_type = ? AND context_id = ? AND status_id = ?
                            /);
  $sth->execute($values->{'id'},$values->{'payment_type'},$values->{'type'}, $values->{'receipt_type'}, $values->{'context_id'} || '1', $values->{'status_id'} || '1') or die $DBI::errstr;
  $sth->finish();
  
}

sub convertHTMLToText {
  my $self = shift;
  my $text = shift;
  
  $text =~ s/<\/*br>/\n/g;
  $text =~ s/<\/*p>/\n/g;
  $text =~ s/<\/*[a-zA-Z]*>//g;

  return $text;
}

sub getContextID {
  my $self = shift;
  my $name = shift;
  
  my $dbh = PlugNPay::DBConnection::database('pnpmisc');
  my $sth = $dbh->prepare(q/
    SELECT id 
    FROM ui_receipt_template_context
    WHERE name = ?
  /);
  $sth->execute($name);
  
  my $results = $sth->fetchall_arrayref({});
  
  if ($results) {
    my $id = $results->[0]{'id'};
    return $id;
  }
}

sub getContextName {
  my $self = shift;
  my $id = shift;

  my $dbh = PlugNPay::DBConnection::database('pnpmisc');
  my $sth = $dbh->prepare(q/
    SELECT name 
    FROM ui_receipt_template_context
    WHERE id = ?
  /);
  $sth->execute($id);

  my $results = $sth->fetchall_arrayref({});

  if ($results) {
    my $name = $results->[0]{'name'};
    return $name;
  }
}

sub getStatusID {
  my $self = shift;
  my $name = shift;

  my $dbh = PlugNPay::DBConnection::database('pnpmisc');
  my $sth = $dbh->prepare(q/
    SELECT id 
    FROM ui_receipt_template_status
    WHERE name = ?
  /);
  $sth->execute($name);

  my $results = $sth->fetchall_arrayref({});

  if ($results) {
    my $id = $results->[0]{'id'};
    return $id;
  }
}

sub getStatusName {
  my $self = shift;
  my $id = shift;

  my $dbh = PlugNPay::DBConnection::database('pnpmisc');
  my $sth = $dbh->prepare(q/
    SELECT name 
    FROM ui_receipt_template_status
    WHERE id = ?
  /);
  $sth->execute($id);

  my $results = $sth->fetchall_arrayref({});

  if ($results) {
    my $name = $results->[0]{'name'};
    return $name;
  }
}

sub loadContexts {
  my $self = shift;

  my $dbh = PlugNPay::DBConnection::database('pnpmisc');
  my $sth = $dbh->prepare(q/
    SELECT id, name 
    FROM ui_receipt_template_context
  /);
  $sth->execute();
  
  my $results = $sth->fetchall_arrayref({});

  return $results;
}

sub loadStatuses {
  my $self = shift;

  my $dbh = PlugNPay::DBConnection::database('pnpmisc');
  my $sth = $dbh->prepare(q/
    SELECT id, name 
    FROM ui_receipt_template_status
  /);
  $sth->execute();

  my $results = $sth->fetchall_arrayref({});

  return $results;
}



1;


