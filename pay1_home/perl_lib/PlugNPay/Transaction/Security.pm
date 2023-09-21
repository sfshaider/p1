package PlugNPay::Transaction::Security;

use strict;
use PlugNPay::Features;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  return $self;
}

#AVS
sub checkFraudConfigAndResponse {
  #########################################################################################
  # The below is from mckutil_strict.pm; this function is to replicate this condition check.
  # Modified 20071029 to exempt transflags=recurring
  #   if ((($fraud::fraud_config{'cvv_avs'} != 1) || ($result{'cvvresp'} ne "M"))
  #       && ($fraud::exemptflag != 1) && ($mckutils::query{'accttype'} eq "credit")
  #       && ($mckutils::query{'paymethod'} !~ /^(invoice|web900)$/)
  #       && ($mckutils::query{'transflags'} !~ /recurring/) && ($purchasetype ne "storedata")
  #   ) {
  #   if (($mckutils::query{'app-level'} ne "")
  #     && (($fraud::fraud_config{'cvv_3dign'} != 1) || (($mckutils::query{'paresponse'} eq "") && ($mckutils::query{'cavv'} eq "")))) {
  #     $mckutils::timetest[++$#mckutils::timetest] = "pre_cvvavs_void";
  #     $mckutils::timetest[++$#mckutils::timetest] = time();
  #
  #     &avs_void($processor);
  #
  #     $mckutils::timetest[++$#mckutils::timetest] = "post_cvvavs_void";
  #     $mckutils::timetest[++$#mckutils::timetest] = time();
  #   }
  # }
  ##########################################################################################
  # The below is from mckutil_strict; replicate the condition check here to set purchasetype
  # if ( (($mckutils::feature{'allow_invoice'} == 1) && ($mckutils::query{'paymethod'} =~ /invoice/i))
  # || (($mckutils::feature{'allow_freeplans'} == 1) && ($mckutils::query{'plan'} ne "") && ($mckutils::query{'card-amount'} == 0.00) && ($mckutils::query{'transflags'} !~ /avsonly/))
  # || (($mckutils::feature{'allow_storedata'} == 1) && ($mckutils::query{'storedata'} == 1)) ) {
  #   $purchasetype = "storedata";
  # }
  # $mckutils::query{'plan'}?
  ###########################################################################################
  my $self = shift;
  my $transactionObject = shift;
  my $response = shift;
  my $fraudStr = shift;
  my $features = shift;
  my $result = 0;

  #Parse fraud_config
  my $fraudObj = new PlugNPay::Features('fraud_config');
  $fraudObj->parseFeatureString($fraudStr);

  if ($transactionObject->getTransactionType() ne 'void'){ #no need to proceed with check
    #seting value of purchasetype
    my $purchasetype = $self->checkIfStoreData($transactionObject, $features);
    if (  (($fraudObj->get('cvv_avs') != 1) || ($response->getSecurityCodeResponse() ne "M"))
       && (!$transactionObject->getIgnoreFraudCheckResponse())
       && ($transactionObject->getCreditCard())
       && ($transactionObject->getTransactionPaymentType() !~ /^(invoice|web900)$/)  #does not contain 'invoice' or 'web900'
       && (!$transactionObject->hasTransFlag('recurring'))
       && ($purchasetype ne 'storedata')
       && $fraudObj->get('avs')
       && (($fraudObj->get('cvv_3dign') != 1) || (!$transactionObject->getPaResponse() && !$transactionObject->getCAVV()) )
       )
    {
      $result = 1;
    }

  }

  return $result;
}

sub shouldAVSVoid {
  my $self = shift;
  my $transactionObject = shift;
  my $response = shift;
  my $fraudString = shift;
  my $features = shift;
  my $shouldVoid = 0;
  my $voidReason;
  my $paymentCardType = uc($transactionObject->getPayment()->getType());
  my $transactionAVSResponse = $response->getAVSResponse();
  my $fraudObj = new PlugNPay::Features('fraud_config');
  $fraudObj->parseFeatureString($fraudString);

  if ($transactionAVSResponse) {
    my $approvalLevel = $fraudObj->get('avs') || -1;

    if ($approvalLevel < 0 && $features->get('AVS')) { #Positive Response Check
      my @parsedAVS = split(':', $features->get('AVS'));
      unless ($self->_matchedCodes(\@parsedAVS, $paymentCardType, $transactionAVSResponse)) {
        $shouldVoid = 1;
        $voidReason = 'AVS Response failed to match accepted values';
      }

    } elsif ($approvalLevel < 0 && $features->get('AVSR')) { #Negative Response Check
      my @parsedAVSR = split(':', $features->get('AVSR'));
      if ($self->_matchedCodes(\@parsedAVSR, $paymentCardType, $transactionAVSResponse)) {
        $shouldVoid = 1;
        $voidReason = 'AVS Response matched rejected values';
      }

    } else { #Approval Level Check
      unless ($approvalLevel == 7 && $response->getCVVResponse() eq 'M') {
        unless ($self->responseCodeMeetsApprovalLevel($approvalLevel, $transactionAVSResponse)) {
          $shouldVoid = 1;
          $voidReason = 'Transaction voided based on AVS response approval level';
        }
      }
    }
  } else {
    $voidReason = 'Invalid AVS Response';
    $shouldVoid = 1;
  }

  my $response = {'shouldVoid' => $shouldVoid, 'reason' => $voidReason};

  # This is disabled for now, if need be we can turn it back on
  #if ($shouldVoid && $features->get('avshold') || $fraudObj->get('avshold')) {
  #  $response->{'shouldVoid'} = 0;
  #  $response->{'status'} = "hold";
  #  $response->{'reason'} = 'AVS Failure: ' . $transactionAVSResponse;
  #}

  return $response;
}

sub _matchedCodes {
  my $self = shift;
  my $codes = shift;
  my $paymentCardType = shift;
  my $transactionAVSResponse = shift;

  my $matched = 0;
  foreach my $entry (@{$codes}) {
    my @allowed = split(/\|/,$entry);
    my $validCardType = shift @allowed;
    my %matchMap = map { $_ => 1 } @allowed;

    if ((uc($validCardType) eq 'ALL' || uc($validCardType) ne $paymentCardType)) {
      if ($matchMap{$transactionAVSResponse}) {
        $matched = 1;
        last;
      }
    }
  }

  return $matched;
}

sub responseCodeMeetsApprovalLevel {
  my $self = shift;
  my $appLevel = shift;
  my $avs = uc shift;
  my $mappedLevel = 0;

  if  ($avs =~ /^(Y|X|D|M|F)$/ )  {
    $mappedLevel = 5;
  } elsif ($avs =~ /^(A|B)$/)  {
    $mappedLevel = 4;
  } elsif ($avs =~ /^(W|Z|P)$/) {
    $mappedLevel = 3;
  } elsif ($avs =~ /^(U|G|C)$/) {
    $mappedLevel = 2;
  } elsif ($avs =~ /^(S|R)$/)  {
    $mappedLevel = 1;
  }

  my $isApproved = $mappedLevel >= $appLevel;
  if ($appLevel == 6 && $mappedLevel =~ /5|2|1/) {
    $isApproved = 1;
  }

  return $isApproved;
}

#CVV/CVC2 - Called shouldCVCVoid because shouldCVVVoid is too many V's
sub shouldCVCVoid {
  my $self = shift;
  my $transactionObject = shift;
  my $response = shift;
  my $fraudString = shift;
  my $features = shift;
  my $shouldVoid = 0;

  if ($transactionObject->getTransactionPaymentType() =~ /GIFT|CREDIT|CARD/i) {
    my $fraudConfig = new PlugNPay::Features('fraud_config');
    $fraudConfig->parseFeatureString($fraudString);
    my $cvvCode = $transactionObject->getCreditCard()->getSecurityCode();

    if (defined $cvvCode
       && $cvvCode ne ''
       && (($response->getSecurityCodeResponse() ne 'M'
            && $transactionObject->getCreditCard()->getBrand() ne 'AMEX'
            && $fraudConfig->get('cvv_xpl'))
          ||($response->getSecurityCodeResponse() eq 'N'
              && !$fraudConfig->get('cvv_ign')))
       && $response->getStatus() eq 'success'
       && !$transactionObject->hasTransFlag('recurring')
       && $self->checkIfStoreData($transactionObject, $features) ne 'storedata'
       && !($transactionObject->getIgnoreCVVResponse() || $transactionObject->getIgnoreFraudCheckResponse())
       && ($fraudConfig->get('cvv_3dign') != 1 || (!$transactionObject->getPaResponse() && !$transactionObject->getCAVV()))
       ) {
       $shouldVoid = 1;
    }
  }

  return $shouldVoid;
}

sub checkIfStoreData {
  my $self = shift;
  my $transactionObject = shift;
  my $features = shift;
  my $purchaseType = '';

  # Check if purchaseType should be storedata
  if ( (($features->get('allow_invoice') == 1) && ($transactionObject->getTransactionPaymentType() =~ /invoice/i))
     || (($features->get('allow_freeplans') == 1) && ($transactionObject->getTransactionAmount() == 0.00) && ($transactionObject->getTransFlags('avsonly') == undef) )
     || (($features->get('allow_storedata') == 1) && ($transactionObject->getTransactionMode() eq 'storedata'))
     ) {
    $purchaseType = 'storedata';
  }

  return $purchaseType;
}

1;
