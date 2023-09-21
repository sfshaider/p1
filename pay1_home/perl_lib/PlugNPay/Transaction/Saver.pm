package PlugNPay::Transaction::Saver;

use strict;
use PlugNPay::Token;
use PlugNPay::Currency;
use PlugNPay::Sys::Time;
use PlugNPay::Transaction;
use PlugNPay::DBConnection;
use PlugNPay::Processor::ID;
use PlugNPay::Util::UniqueID;
use PlugNPay::Transaction::Type;
use PlugNPay::Transaction::Flags;
use PlugNPay::Transaction::State;
use PlugNPay::Transaction::Loader;
use PlugNPay::Transaction::Vehicle;
use PlugNPay::Logging::Performance;
use PlugNPay::Logging::DataLog;
use PlugNPay::Transaction::DetailKey;
use PlugNPay::Transaction::AccountType;
use PlugNPay::GatewayAccount::InternalID;
use PlugNPay::Environment;
use PlugNPay::Util::Status;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;


  return $self;
}

sub save {
  my $self = shift;
  my $orderID = shift;
  my $transactions = shift;
  my $stateID = shift;
  my $status;
  my $transactionsToSave = [];

  if (ref($transactions) eq 'HASH') {
    my @transArray = values %{$transactions};
    $transactionsToSave = \@transArray;
  } elsif (ref($transactions) eq 'ARRAY') {
    $transactionsToSave = $transactions;
  } elsif (ref($transactions) =~ /^PlugNPay::Transaction/) {
    $transactionsToSave = [$transactions];
  } else {
    $status = new PlugNPay::Util::Status();
    $status->setFalse();
    $status->setError('Invalid input');
  }

  if (!defined $status) {
    $status = $self->_save($orderID,$transactionsToSave,$stateID);
  }

  return $status;
}

sub _save {
  my $self = shift;
  my $orderID = shift;
  my $transactions = shift;
  my $stateID = shift;
  my $stateObj = new PlugNPay::Transaction::State();
  my $typeObj = new PlugNPay::Transaction::Type();
  my $vehicleObj = new PlugNPay::Transaction::Vehicle();
  my $procIDObj = new PlugNPay::Processor::ID();
  my $currencyObj = new PlugNPay::Currency();
  my $accountTypeObj = new PlugNPay::Transaction::AccountType();
  my $time = new PlugNPay::Sys::Time();
  my $uuid = new PlugNPay::Util::UniqueID();
  my $env = new PlugNPay::Environment();
  my $status = new PlugNPay::Util::Status();
  new PlugNPay::Logging::Performance('Save transaciton begin');

  if ($orderID =~ /^[a-zA-Z0-9]+$/) {
    $uuid->fromHex($orderID);

    $orderID = $uuid->inBinary();
  }

  unless (defined $stateID && $stateID =~ /^\d+$/) {
    $stateID = $stateObj->getStateIDFromOperation($stateID);
  }

  my @transParams = ();
  my @cardParams = ();
  my @billParams = ();
  my @shipParams = ();

  my @shipValues = ();
  my @billValues = ();
  my @cardValues = ();
  my @transValues = ();
  my @flags = ();
  my @accountCodes = ();
  my @customData = ();
  my $token = new PlugNPay::Token();

  my $dbs = new PlugNPay::DBConnection();
  $dbs->begin('pnp_transaction');
  my $validate;
  my $aaargg;
  foreach my $transaction (@{$transactions}) {
    my $loader = new PlugNPay::Transaction::Loader();
    if ($transaction->existsInDatabase() || $loader->transactionExists($transaction->getPNPTransactionID())) {
      my $updateStatus = $self->_updateTransaction({
        transaction => $transaction
      });
      next;
    }
    my @flagNames = $transaction->getTransFlags();
    push @flags,{'pnp_transaction_id' => $transaction->getPNPTransactionID(),'flags' => \@flagNames};
    my $pnpID = $transaction->getPNPTransactionID();
    $aaargg = $pnpID;
    $validate = $pnpID;
    my $billingInfo = $transaction->getBillingInformation();
    my $shippingInfo = $transaction->getShippingInformation();
    my $payType = ($transaction->getTransactionPaymentType() eq 'credit' ? 'card' : $transaction->getTransactionPaymentType());
    my $vehicleID = $vehicleObj->getTransactionVehicleID($payType);
    my $ip = new PlugNPay::Util::IP::Address();
    if ($transaction->getIPAddress()) {
      $ip->fromIP($transaction->getIPAddress());
    } else {
      $ip->fromIP($env->get('PNP_CLIENT_IP'));
    }

    my $hexToken;
    if($payType ne 'emv') {
      $hexToken = $transaction->getPayment()->getToken();
      if ($hexToken =~ /^[a-fA-F0-9]+$/) {
        $token->fromHex($hexToken);
      } else {
        $token->fromBinary($hexToken);
      }
    }
    my $pnpToken;
    if(defined $hexToken) {
      $pnpToken = $token->inBinary();
    }

    $pnpToken ||= '';

    my $amountAdj = $transaction->getTransactionAmount() - $transaction->getBaseTransactionAmount();
    $amountAdj -= $transaction->getTaxAmount();
    if (!$amountAdj && defined $transaction->getTransactionAmountAdjustment()) {
      $amountAdj = $transaction->getTransactionAmountAdjustment();
    }

    my $taxAdj = $transaction->getTaxAmount() - $transaction->getBaseTaxAmount();

    my $accountType;
    if ($payType eq 'credit' || $payType eq 'card' || $payType eq 'emv') {
      $accountType = 'credit';
    } elsif ($payType eq 'prepaid' || $payType eq 'gift') {
      $accountType = 'gift';
    } else {
      $accountType = $transaction->getPayment()->getAccountType();
    }

    my $pnpRefID = $transaction->getPNPTransactionReferenceID() || undef;

    if (defined $pnpRefID && $pnpRefID =~ /^[a-fA-F0-9]+$/) {
      $uuid->fromHex($pnpRefID);
      $pnpRefID = $uuid->inBinary();
    }

    my @tmpTransVals = ();
    push @tmpTransVals,$pnpID;
    push @tmpTransVals,$orderID;
    push @tmpTransVals,$procIDObj->getProcessorReferenceID($transaction->getProcessor()); #Gets private processor ID, should be renamed
    push @tmpTransVals,$stateID;
    push @tmpTransVals,$vehicleID;
    push @tmpTransVals,$typeObj->getTransactionTypeID($transaction->getTransactionType());
    push @tmpTransVals,$time->nowInFormat('iso_gm');
    push @tmpTransVals,$pnpRefID;
    push @tmpTransVals,$transaction->getTransactionAmount(); #default settlement amount
    push @tmpTransVals,$transaction->getTransactionAmount(); #transaction amount
    push @tmpTransVals,$currencyObj->getTransactionCurrencyID($transaction->getCurrency());
    push @tmpTransVals,$transaction->getTaxAmount();
    push @tmpTransVals,$ip->toBinary() || undef;
    push @tmpTransVals,$accountTypeObj->getAccountTypeID($accountType);
    push @tmpTransVals,$amountAdj;
    push @tmpTransVals,$taxAdj;
    push @tmpTransVals,$pnpToken;
    push @tmpTransVals,$transaction->getVendorToken();
    push @transValues,@tmpTransVals; #add values to query
    push @transParams,'(' . join(',',map {'?'} @tmpTransVals) . ')'; #add the params to query

    #Billing Info
    my @tmpBillVals = ();
    push @tmpBillVals,$pnpID;
    push @tmpBillVals,$billingInfo->getFullName() || $transaction->getPayment()->getName();
    push @tmpBillVals,$billingInfo->getCompany();
    push @tmpBillVals,$billingInfo->getAddress1();
    push @tmpBillVals,$billingInfo->getAddress2();
    push @tmpBillVals,$billingInfo->getCity();
    push @tmpBillVals,$billingInfo->getState();
    push @tmpBillVals,$billingInfo->getPostalCode();
    push @tmpBillVals,$billingInfo->getCountry();
    push @tmpBillVals,$billingInfo->getEmailAddress();
    push @tmpBillVals,$billingInfo->getPhone();
    push @tmpBillVals,$billingInfo->getFax();
    push @billValues,@tmpBillVals;
    push @billParams,'(' . join(',',map {'?'} @tmpBillVals) . ')';

    #Shipping Info
    if (defined $shippingInfo && defined $shippingInfo->getAddress1() && defined $shippingInfo->getPostalCode()) {
      my @tmpShipVals = ();
      push @tmpShipVals,$pnpID;
      push @tmpShipVals,$shippingInfo->getFullName();
      push @tmpShipVals,$shippingInfo->getAddress1();
      push @tmpShipVals,$shippingInfo->getAddress2();
      push @tmpShipVals,$shippingInfo->getCity();
      push @tmpShipVals,$shippingInfo->getState();
      push @tmpShipVals,$shippingInfo->getPostalCode();
      push @tmpShipVals,$shippingInfo->getCountry();
      push @tmpShipVals,$shippingInfo->getEmailAddress();
      push @tmpShipVals,$shippingInfo->getPhone();
      push @tmpShipVals,$shippingInfo->getFax();
      push @tmpShipVals,$transaction->getShippingNotes();
      push @shipValues,@tmpShipVals;
      push @shipParams,'(' . join(',',map {'?'} @tmpShipVals) . ')';
    }

    #Card Info
    if ($payType eq 'card' || $payType eq 'gift') {
      my $card = $transaction->getPayment();
      my $cardNumber = $card->getNumber();
      my @tmpCardVals = ();
      push @tmpCardVals,$pnpID;
      push @tmpCardVals,substr($cardNumber,0,6);
      push @tmpCardVals,substr($cardNumber,-4,4);
      push @tmpCardVals,$card->getExpirationMonth() . '/' . $card->getExpirationYear();

      push @cardValues,@tmpCardVals;
      push @cardParams,'(' . join(',',map {'?'} @tmpCardVals) . ')';
    }

    for (my $i = 1; $i < 4; $i++) {
      if (defined $transaction->getAccountCode($i)) {
        my $codes = {'pnp_transaction_id' => $pnpID, 'transaction_state_id' => $stateID, 'account_code_number' => $i, 'value' => $transaction->getAccountCode($i)};
        push(@accountCodes,$codes);
      }
    }

    my $additionalMerchantData = $transaction->getCustomData();
    foreach my $entry (keys %{$additionalMerchantData}) {
      push @customData,{'key' => $entry, 'value' =>$additionalMerchantData->{$entry},'pnp_transaction_id' => $pnpID, 'transaction_state_id' => $stateID};
    }
  }

  if (@transParams > 0) {
    # Finish insert statements #
    my $transInsert = 'INSERT INTO `transaction`
                       (`pnp_transaction_id`, `pnp_order_id`, `processor_id`, `transaction_state_id`,
                        `transaction_vehicle_id`, `transaction_type_id`, `transaction_date_time`,
                        `pnp_transaction_ref_id`, `settlement_amount`,
                        `amount`, `currency`, `tax_amount`, `ip_address`, `account_type`,
                        `fee_amount`,`fee_tax`,`pnp_token`,`vendor_token`)
                       VALUES ';
    my $billInsert = 'INSERT INTO `transaction_billing_information`
                      ( `transaction_id`, `full_name`, `company`, `address`,
                       `address2`, `city`, `state`, `postal_code`, `country`, `email`,
                       `phone`, `fax`)
                      VALUES ';
    my $shipInsert ='INSERT INTO `transaction_shipping_information`
                      (`transaction_id`, `full_name`, `address`,
                       `address2`, `city`, `state`, `postal_code`, `country`, `email`,
                       `phone`, `fax`, `notes`)
                      VALUES ';
    my $cardInsert = 'INSERT INTO `card_transaction`
                      (`pnp_transaction_id`, `card_first_six`,
                       `card_last_four`, `card_expiration`)
                      VALUES ';

    $transInsert .= join(',',@transParams);
    $billInsert  .= join(',',@billParams);
    $shipInsert  .= join(',',@shipParams);
    $cardInsert  .= join(',',@cardParams);

    eval {
      my $sth = $dbs->prepare('pnp_transaction',$transInsert);
      $sth->execute(@transValues) or die $DBI::errstr;

      if (defined $billValues[0]) {
        my $bsth = $dbs->prepare('pnp_transaction',$billInsert); #Billing Info
        $bsth->execute(@billValues) or die $DBI::errstr;
      }

      if (defined $shipValues[0]) {
        my $ssth = $dbs->prepare('pnp_transaction',$shipInsert); #Shipping Info
        $ssth->execute(@shipValues) or die $DBI::errstr;
      }

      if (defined $cardValues[0]) {
        my $csth = $dbs->prepare('pnp_transaction',$cardInsert); #Card
        $csth->execute(@cardValues) or die $DBI::errstr;
      }

      #Some sort of loop problem?
      if (@flags > 0) {
        $self->saveTransactionFlags(\@flags);
      }

      if (@accountCodes > 0) {
        $self->saveAccountCodes(\@accountCodes);
      }

      if (@customData > 0) {
        $self->saveCustomData(\@customData);
      }
    };
  }

  new PlugNPay::Logging::Performance('Save transaction finish');
  if ($@) {
    $dbs->rollback('pnp_transaction');
    my $dataLog = new PlugNPay::Logging::DataLog({'collection' => 'transaction'});
    $dataLog->log({'message' =>'Transaction save error','error' =>  $@});
    $status->setFalse();
    $status->setError('Failed to save transaction');
    $status->setErrorDetails($@);
  } else {
    $dbs->commit('pnp_transaction');
    $status->setTrue();
  }

  return $status;
}

sub _updateTransaction {
  my $self = shift;
  my $input = shift;
  my $transaction = $input->{'transaction'};

  my $pnpTransactionId = $transaction->getPNPTransactionID();
  my $pnpTransactionIdHex = PlugNPay::Util::UniqueID::fromBinaryToHex($pnpTransactionId);

  my $transactionStates = new PlugNPay::Transaction::State();
  my $transactionStateId = $transactionStates->getTransactionStateID($transaction->getTransactionState());

  my %updateData;
  $updateData{'amount'} = $transaction->getTransactionAmount();
  $updateData{'tax_amount'} = $transaction->getTaxAmount();
  $updateData{'fee_amount'} = $transaction->getTransactionAmountAdjustment();
  if (defined $transaction->getBaseTaxAmount()) {
    $updateData{'fee_tax'} = $updateData{'tax_amount'} - $transaction->getBaseTaxAmount();
  }
  $updateData{'transaction_state_id'} = $transactionStateId;
  $updateData{'settlement_amount'}   = $transaction->getSettlementAmount();
  $updateData{'settled_amount'}      = $transaction->getSettledAmount();
  $updateData{'settled_tax_amount'}   = $transaction->getSettledTaxAmount();
  $updateData{'settlement_mark_time'} = $transaction->getTransactinMarkTime();

  my $allowedPreviousStates = $transactionStates->getAllowedPreviousStateIds($transactionStateId);
  my $allowedPreviousStatePlaceholders = join (',', map { '?' } @{$allowedPreviousStates});

  # build update string and values, skipping undefined inputs
  my @updates;
  my @values;
  foreach my $key (keys %updateData) {
    next if !defined $updateData{$key};
    push @updates,"`$key` = ?";
    push @values,$updateData{$key};
  }

  my $status = new PlugNPay::Util::Status(0);

  if (@values == 0) {
    $status->setError('nothing to update');
  } else {
    my $updateQuery = 'UPDATE `transaction` SET ' . join(',',@updates) . ' WHERE `pnp_transaction_id` = ? AND `transaction_state_id` IN (' . $allowedPreviousStatePlaceholders . ')';

    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('pnp_transaction',$updateQuery,[@values,$pnpTransactionId,@{$allowedPreviousStates}]);

    # ensure the update worked.
    my $verificationQuery = "SELECT COUNT(*) as `successful` FROM `transaction` WHERE `pnp_transaction_id` = ? AND " . join(' AND ',@updates);
    my $sanityQuery = "SELECT * FROM `transaction` WHERE `pnp_transaction_id` = ? AND " . join(' AND ',@updates);

    my $result = $dbs->fetchallOrDie('pnp_transaction',$verificationQuery,[$pnpTransactionId,@values],{});
    my $insanity = $dbs->fetchallOrDie('pnp_transaction',$sanityQuery,[$pnpTransactionId,@values],{});
    if ($result->{'result'}[0]{'successful'} == 1) {
      $status->setTrue();
    } else {
      $status->setFalse();
      $status->setError('verification of updated data failed');
    }
  }

  return $status;
}

# Transaction Flag Saving below #
sub saveTransactionFlags {
  my $self = shift;
  my $flags = shift;
  my $saved = 0;

  if (ref($flags) eq 'ARRAY' && @{$flags} > 0) {
    $saved = $self->_saveTransactionFlags($flags);
  }

  return $saved;
}

sub _saveTransactionFlags {
  my $self = shift;
  my $transactions = shift;
  my $saved = 0;

  if (@{$transactions} > 0) {
    my $flagObj = new PlugNPay::Transaction::Flags();
    my $dbs = new PlugNPay::DBConnection();
    my @params = ();
    my @values = ();
    foreach my $transaction (@{$transactions}) {
      if (@{$transaction->{'flags'}} > 0 && defined $transaction->{'pnp_transaction_id'}) {
        foreach my $flagName (@{$transaction->{'flags'}}) {
          push @values,$transaction->{'pnp_transaction_id'};
          push @values,$flagObj->getFlagID($flagName);
          push @params,'(?,?)';
        }
      }
    }

    if (@params > 0 && @values > 0) {
      my $insert = 'INSERT INTO transaction_transflag
                    (transaction_id,transflag_id)
                    VALUES ' . join(',',@params);
      my $sth = $dbs->prepare('pnp_transaction',$insert);
      $sth->execute(@values) or die $DBI::errstr;
    }

    $saved = 1;
  }

  return $saved;
}

# Account Codes #
sub saveAccountCodes {
  my $self = shift;
  my $codes = shift;
  my $saved = 0;
  my $dbs = new PlugNPay::DBConnection();
  my $insert = 'INSERT INTO transaction_account_code
                (transaction_id,transaction_state_id,account_code_number,value)
                VALUES ';
  my @values = ();
  my @params = ();
  foreach my $code (@{$codes}) {
    if (defined $code->{'pnp_transaction_id'} && defined $code->{'transaction_state_id'} && defined $code->{'value'}) {
      push @values, $code->{'pnp_transaction_id'};
      push @values, $code->{'transaction_state_id'};
      push @values, $code->{'account_code_number'};
      push @values, $code->{'value'};
      push @params, '(?,?,?,?)';
    }
  }

  if (@params > 0 && @values > 0) {
    my $sth = $dbs->prepare('pnp_transaction',$insert . ' ' . join(',',@params));
    $sth->execute(@values) or die $DBI::errstr;
    $sth->finish();
    $saved = 1;
  }

  return $saved;
}

sub saveCustomData {
  my $self = shift;
  my $dataArray = shift;
  my $saved = 0;
  my $dbs = new PlugNPay::DBConnection();
  my $insert = 'INSERT INTO transaction_additional_processor_detail
                (`transaction_id`,`transaction_state_id`,`key_id`,`value`)
                VALUES ';
  my $detailKeyObj = new PlugNPay::Transaction::DetailKey();

  my @params = ();
  my @values = ();
  foreach my $item (@{$dataArray}) {
    if (defined $item->{'key'} && defined $item->{'value'}) {
      my $keyID = $detailKeyObj->getDetailKeyID($item->{'key'});
      push @values,$item->{'pnp_transaction_id'};
      push @values,$item->{'transaction_state_id'};
      push @values,$keyID;
      push @values,$item->{'value'};
      push @params,'(?,?,?,?)';
    }
  }

  if (@params > 0 && @values > 0) {
    $insert .= join(',',@params);
    my $sth = $dbs->prepare('pnp_transaction',$insert);
    $sth->execute(@values) or die $DBI::errstr;
    $saved = 1;
  }

  return $saved;
}

1;
