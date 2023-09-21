package PlugNPay::Transaction::Receipt;

use strict;
use PlugNPay::Email;
use PlugNPay::Receipt;
use PlugNPay::GatewayAccount;

###########################################
# Right now this just sends email receipt #
# Function was moved from Trans Processor #
###########################################

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  return $self;
}

sub sendEmailReceipt {
  my $self = shift;
  my $data = shift;

  my $transaction = $data->{'transaction'};
  my $response = $data->{'response'};
  my $ccAddress = $data->{'ccAddress'};
  my $bccAddress = $data->{'bccAddress'};
  my $emailSubject = $data->{'emailSubject'};

  my $emailReceiptHTML = '';
  my $emailReceiptText = '';
  my $wasSent = 0;

  my $receiptGenerator = new PlugNPay::Receipt();
  $receiptGenerator->setTransaction($transaction);
  $receiptGenerator->setResponse($response);

  my $loadedEmailReceiptTemplate = $receiptGenerator->getReceipt('email');
  $emailReceiptHTML = $loadedEmailReceiptTemplate->{'html'};
  $emailReceiptText = $loadedEmailReceiptTemplate->{'text'};

  my $billingEmailAddress;
  my $billingInformation = $transaction->getBillingInformation();
  if ($billingInformation) {
    $billingEmailAddress = $billingInformation->getEmailAddress();
  }

  my $ga = new PlugNPay::GatewayAccount($transaction->getGatewayAccount());
  my $sendingEmailAddress = $ga->getSendingEmailAddress();

  if ($billingEmailAddress && $sendingEmailAddress) {
    my $emailReceiptTemplate;
    my $emailFormat;

    if ($emailReceiptHTML ne '') {
      $emailReceiptTemplate = $emailReceiptHTML;
      $emailFormat = 'html';
    } else {
      $emailReceiptTemplate = $emailReceiptText;
      $emailFormat = 'text';
    }

    my $emailer = new PlugNPay::Email();
    $emailer->setVersion('legacy');
    $emailer->setTo($billingEmailAddress);
    if ($ccAddress) {
      $emailer->setCC($ccAddress);
    }
    if ($bccAddress) {
      $emailer->setBCC($bccAddress);
    }
    $emailer->setFrom($sendingEmailAddress);
    $emailer->setContent($emailReceiptTemplate);
    $emailer->setFormat($emailFormat);
    $emailer->setSubject($emailSubject || 'Payment Receipt');
    $emailer->setGatewayAccount($transaction->getGatewayAccount());
    $wasSent = $emailer->send();
  }

  return $wasSent;
}

1;
