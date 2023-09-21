package PlugNPay::Transaction::JSON::Versioned;

use strict;
use PlugNPay::Transaction::JSON;
use PlugNPay::Util::Array qw(inArray);

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub reformat {
  my $self = shift;
  my $input = shift;
  my $version = $input->{'version'};
  my $formatted = $input->{'formatted'};
  my $transaction = $input->{'transaction'};
  my $originalTransaction = $input->{'originalTransaction'};

  my $options = $input->{'options'};
  my $reformatted = $formatted;
  if ($version ne 'current') {
    if ($version eq 'v1') {
      $reformatted = $self->v1({
        formatted => $formatted,
        transaction => $transaction,
        originalTransaction => $originalTransaction,
        options => $options
      });
    }
  }

  return $reformatted;
}

sub v1 {
  my $self = shift;
  my $input = shift;

  my $formatted = $input->{'formatted'};
  my $transaction = $input->{'transaction'};
  my $originalTransaction = $input->{'originalTransaction'};
  my $options = $input->{'options'};

  my $reformatted = {};

  # get status and finalstatus from transaction response status
  my $response = $transaction->getResponse();

  # in no particular order:
  $reformatted->{'accountCode'}  = $formatted->{'accountCode'}{1} || '';
  $reformatted->{'accountCode2'} = $formatted->{'accountCode'}{2} || '';
  $reformatted->{'accountCode3'} = $formatted->{'accountCode'}{3} || '';
  $reformatted->{'accountCode4'} = '';

  $reformatted->{'billingInfo'}  = $formatted->{'billingInfo'};
  $reformatted->{'shippingInfo'} = $formatted->{'shippingInfo'};
  # turn undefined values to empty strings for shipping and billing info

  foreach my $key (keys %{$reformatted->{'billingInfo'}}) {
    $reformatted->{'billingInfo'}{$key} ||= '';
  }

  foreach my $key (keys %{$reformatted->{'shippingInfo'}}) {
    $reformatted->{'shippingInfo'}{$key} ||= '';
  }

  $reformatted->{'payment'} = $formatted->{'payment'}; # mark has different masked format than on pay1.plugnpay.com
  if (defined $response && defined $response->getTransaction()) {
    $reformatted->{'payment'}{'mode'} = $response->getTransaction()->getTransactionMode();
  }
  if ($reformatted->{'payment'}{'mode'} eq 'authorization') {
    $reformatted->{'payment'}{'mode'} = 'auth';
  }

  if ($reformatted->{'payment'}{'card'}) {
    delete $reformatted->{'payment'}{'card'}{'isDebit'};
    delete $reformatted->{'payment'}{'card'}{'brand'};
    delete $reformatted->{'payment'}{'card'}{'type'};
  }

  $reformatted->{'hexToken'} = $reformatted->{'payment'}{'card'}{'token'} || $reformatted->{'payment'}{'ach'}{'token'} || "";

  $reformatted->{'currency'}  = $formatted->{'currency'};
  $reformatted->{'processor'} = $formatted->{'processor'};
  $reformatted->{'reason'}    = $formatted->{'reason'} || '';
  $reformatted->{'secCode'}   = $formatted->{'secCode'};
  $reformatted->{'feeAmount'} = $formatted->{'feeAmount'};
  $reformatted->{'purchaseOrderNumber'} = $formatted->{'purchaseOrderNumber'};
  $reformatted->{'customData'} = $formatted->{'customData'};
  $reformatted->{'markedSettlementAmount'} = $formatted->{'markedSettlementAmount'};
  $reformatted->{'settledAmount'}    = $formatted->{'settledAmount'};
  $reformatted->{'pnpTransactionID'} = $formatted->{'pnpTransactionID'};

  $reformatted->{'tax'} = $formatted->{'tax'};
  $reformatted->{'authorizationCode'} = $formatted->{'authorizationCode'} || $transaction->getAuthorizationCode();
  $reformatted->{'amount'}      = $formatted->{'amount'};
  $reformatted->{'feeTax'}      = $formatted->{'feeTax'};
  $reformatted->{'loadedState'} = $formatted->{'loadedState'};
  $reformatted->{'merchantClassifierID'} = $formatted->{'merchantClassifierID'};
  $reformatted->{'transactionHistory'}   = $formatted->{'transactionHistory'};
  $reformatted->{'baseAmount'}  = $formatted->{'baseAmount'};
  $reformatted->{'baseTax'}     = $formatted->{'baseTax'};

  $reformatted->{'status'}      = $response->getStatus();
  $reformatted->{'finalStatus'} = $response->getStatus();
  $reformatted->{'processorMessage'} = $response->getMessage();
  $reformatted->{'message'}     = $response->getMessage();
  $reformatted->{'cvvResponse'} = $formatted->{'cvvResponse'} || '';
  $reformatted->{'avsResponse'} = $formatted->{'avsResponse'} || '';

  $reformatted->{'transactionState'} = $formatted->{'transactionState'};
  $reformatted->{'gatewayAccount'} = $formatted->{'gatewayAccount'};
  $reformatted->{'transactionDateTime'} = $formatted->{'transactionDateTime'};
  $reformatted->{'merchantOrderID'} = $formatted->{'merchantOrderID'};
  $reformatted->{'orderID'} = $formatted->{'orderID'};
  $reformatted->{'processorReferenceID'} = $formatted->{'processorReferenceID'} || '';

  $reformatted->{'login'} = $formatted->{'login'};

  $reformatted->{'response'} = {
    'authorizationCode' => $formatted->{'authorizationCode'},
    'avsResponse' => $reformatted->{'avsResponse'},
    'cvvResponse' => $reformatted->{'cvvResponse'},
    'errorMessage' => $reformatted->{'message'},
    'fraud' => {},
    'isDuplicate' => $response->getDuplicate(),
    'status' => $reformatted->{'status'}
	};

  $reformatted->{'customData'} = $transaction->getCustomData();
  $reformatted->{'fraudResponse'} = $response->{'fraudResponse'} || {};

  $reformatted->{'adjustmetnInformation'} = $reformatted->{'adjustmentInformation'} = $formatted->{'adjustmentInformation'} || {}; # try to keep adjustmentAccount populated

  # optionally suppress additional merchant data field
  my $suppressMerchantData = $options->{'v1:suppressAdditionalMerchantData'};
  $reformatted->{'additionalMerchantData'} = $suppressMerchantData ? {} : $formatted->{'additionalMerchantData'} || {};

  # optionally suppress additional processor data field
  my $suppressProcessorData = $options->{'v1:suppressAdditionalProcessorData'};
  $reformatted->{'additionalProcessorData'} = $suppressProcessorData ? {} : $formatted->{'additionalProcessorData'};

  if ($formatted->{'processorDetails'}) {
    $reformatted->{'processorDetails'} = $formatted->{'processorDetails'}; # try to get processorMessage key/value in here
    if (defined $transaction->getResponse()) {
      $reformatted->{'processorDetails'}{'processorMessage'} ||= $transaction->getResponse()->getMessage();
      if (defined $originalTransaction && defined $originalTransaction->getResponse()) {
        $reformatted->{'processorDetails'}{'processorMessage'} ||= $originalTransaction->getResponse()->getMessage();
      }
    }
  }

  # display transaction status
  my $mode = $transaction->getTransactionMode();
  my $status = $response->getStatus();
  $reformatted->{'transactionStatus'} = PlugNPay::Transaction::JSON::getStatusFromState($mode,$status); # override below for previously broken void responses

  # super amazing fragile hack
  if ($options->{'v1:void'}) {
    my $oMode = $originalTransaction->getTransactionMode();
    my $oStatus = $originalTransaction->getResponse()->getStatus();

    $reformatted->{'loadedState'} = PlugNPay::Transaction::JSON::determineState($originalTransaction->getTransactionState(),$originalTransaction->getExtraTransactionData());
    $reformatted->{'transactionState'} = $formatted->{'transactionState'};

    if ($status eq 'success') { # old voids were completely broken where they always showed previous transaction state, but we are going to fix that only for void failure
      $reformatted->{'transactionStatus'} = PlugNPay::Transaction::JSON::getStatusFromState($oMode,$oStatus);
    } elsif ($status eq 'problem') {
      $reformatted->{'transactionStatus'} = PlugNPay::Transaction::JSON::getStatusFromState($oMode,$oStatus);
      $reformatted->{'finalStatus'} = $oStatus;
    }
  } elsif ($mode eq 'return') {
    $status = $transaction->getResponse()->getStatus();

    $reformatted->{'transactionState'} = PlugNPay::Transaction::JSON::determineState($transaction->getTransactionState(),$transaction->getExtraTransactionData());
    if (inArray($reformatted->{'transactionState'},['CREDIT_PENDING','CREDIT_PROBLEM']) && $status ne 'pending') {
      $reformatted->{'transactionState'} = 'CREDIT';
    }

    $reformatted->{'status'}      = $status;
    $reformatted->{'finalStatus'} = $status;
    $reformatted->{'loadedState'} = $reformatted->{'transactionState'};

  } elsif ($options->{'v1:method:POST'}) { # horrible horrible horrible hack right here.
    if ( $transaction->doPostAuth() ) { # this is only set on a postauth tran if it was an authpostauth, it is not set for normal postauths
      if ( $reformatted->{'transactionState'} =~ /^POSTAUTH/ ) {
        $reformatted->{'transactionState'} = $reformatted->{'loadedState'} = 'AUTH';
      }
    }
  }

  if ($options->{'v1:method:POST'} || $options->{'v1:method:DELETE'}) {
    delete $reformatted->{'pnpToken'};
    delete $reformatted->{'hexToken'};
  }

  # only for gets
  $reformatted->{'hexTransactionID'} = $reformatted->{'pnpTransactionID'} || "";
  $reformatted->{'pnpToken'} = $reformatted->{'hexToken'};

  if ($options->{'shrink'} eq 'v1:1') {
    $reformatted->{'transactionHistory'} = {};
    $reformatted->{'processorDetails'} = {};
    $reformatted->{'adjustmentInformation'} = {};
    if ($reformatted->{'message'} =~ /^APPROVED/) {
      my $message = 'APPROVED' . sprintf(" %08X", rand(0xffffffff)); # changes every time so the not validate message is implied
      $reformatted->{'message'} = $reformatted->{'processorMessage'} = $reformatted->{'response'}{'errorMessage'} = $message;
    }
  }

  return $reformatted;
}

1;
