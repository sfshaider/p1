package PlugNPay::Recurring::Attendant::PaymentSource;

use strict;
use PlugNPay::CardData;
use PlugNPay::CreditCard;
use PlugNPay::OnlineCheck;
use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;
use PlugNPay::CreditCard::Encryption;


sub new {
  my $class = shift;
  my $self = {};

  bless $self,$class;

  return $self;
}


sub getSHACardNumber {
  my $self = shift;

  return $self->{'shaCardNumber'};
}

sub setSHACardNumber {
  my $self = shift;
  my $shaCardNumber = shift;

  $self->{'shaCardNumber'} = $shaCardNumber;
}

sub getCardNumber {
  my $self = shift;

  return $self->{'cardNumber'};
}

sub setCardNumber {
  my $self = shift;
  my $cardNumber = shift;

  $self->{'cardNumber'} = $cardNumber;
}

sub getExpMonth {
  my $self = shift;

  return $self->{'expMonth'};
}

sub setExpMonth {
  my $self = shift;
  my $expMonth = shift;

  $self->{'expMonth'} = $expMonth;
}

sub getExpYear {
  my $self = shift;

  return $self->{'expYear'};
}

sub setExpYear {
  my $self = shift;
  my $expYear = shift;

  $self->{'expYear'} = $expYear;
}

sub getEncCardNumber {
  my $self = shift;

  return $self->{'encCardNumber'};
}

sub setEncCardNumber {
  my $self = shift;
  my $encCardNumber = shift;

  $self->{'encCardNumber'} = $encCardNumber;
}


sub getPaymentSourceType {
  my $self = shift;

  return $self->{'type'};
}

sub setPaymentSourceType {
  my $self = shift;
  my $type = shift;

  $self->{'type'} = $type;
}

sub updatePaymentSource {
  my $self = shift;
  my $merchant = shift;
  my $customer = shift;
  my $data = shift;


  my $dbs = new PlugNPay::DBConnection();
  eval {

    $dbs->begin($merchant);

    my ($encCardNumber, $shaCardNumber, $masked, $exp, $response);

    if ($data->{'type'} =~ /card/i) {
      my $cc = new PlugNPay::CreditCard($data->{'cardNumber'});
      $cc->setExpirationMonth($data->{'expMonth'});
      $cc->setExpirationYear($data->{'expYear'});

      if (!$cc->verifyLength() || !$cc->verifyLuhn10() || $cc->isExpired()) {
        die  "Invalid card data.";
      }

      $masked = $cc->getMaskedNumber();
      $exp = $cc->getExpirationMonth() . '/' . $cc->getExpirationYear();
      $encCardNumber = $cc->getEncHash();
      $shaCardNumber = $cc->getSha1Hash();

    } else {
      my $oc = new PlugNPay::OnlineCheck();
      $oc->setABARoutingNumber($data->{'routingNumber'});
      $oc->setAccountNumber($data->{'accountNumber'});

      if (!$oc->verifyABARoutingNumber()) {
        die "Invalid routing number.";
      }

      $masked = $oc->getMaskedNumber();
      $encCardNumber = $oc->getEncHash();
      $shaCardNumber = $oc->getSha1Hash();

    }

    $response = new PlugNPay::CardData()->insertRecurringCardData({username => $merchant, cardData => $encCardNumber, customer => $customer});

    if ($response !~ /success/i) {
      die "Failed on inserting to card data.";
    }

    my $sth = $dbs->prepare($merchant, q/
                          UPDATE customer
                          SET length = ?, cardnumber = ?, exp = ?, shacardnumber = ?
                          WHERE username = ? /);

    $sth->execute(length $encCardNumber, $masked, $exp, $shaCardNumber, $customer) or die $DBI::errstr;
  };

  if ($@) {
    $dbs->rollback($merchant);
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'Attendant'});
    $logger->log({'status' => 'FAILURE', 'message' => 'Failed to update payment source for username ' . $customer . '.'});
    return 0;
  }

  $dbs->commit($merchant);
  return 1;
}

sub loadPaymentSource {
  my $self = shift;
  my $merchant = shift;
  my $customer = shift;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare($merchant, q/
                          SELECT cardnumber, exp
                          FROM customer
                          WHERE username = ? /);
    $sth->execute($customer) or die $DBI::errstr;

    my $row = $sth->fetchall_arrayref({});

    if ($row->[0]) {
      my ($expMonth, $expYear) = split('/', $row->[0]{'exp'});
      my $cardData = new PlugNPay::CardData()->getRecurringCardData({ username => $merchant, customer => $customer });
      my $decryptedCard = new PlugNPay::CreditCard::Encryption()->decrypt($cardData);
      my $type = split(' ', $decryptedCard);

      $self->setEncCardNumber($cardData);
      $self->setPaymentSourceType($type > 1 ? 'ach' : 'card');
      $self->setCardNumber($row->[0]{'cardnumber'});
      $self->setExpMonth($expMonth);
      $self->setExpYear($expYear);
    }
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'Attendant'});
    $logger->log('status' => 'FAILURE', 'message' => 'Failed loading payment source.');
    return 0;
  }
  return 1;
}

sub deletePaymentSource {
  my $self = shift;
  my $merchant = shift;
  my $customer = shift;

  my $dbs = new PlugNPay::DBConnection();
  eval {
    my $sth = $dbs->prepare($merchant, q/
                          UPDATE customer
                          SET shacardnumber = NULL, cardnumber = NULL, exp = NULL, length = NULL
                          WHERE username = ? /);

    $sth->execute($customer) or die $DBI::errstr;
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'Attendant'});
    $logger->({'status' => 'FAILURE', 'message' => 'Failed to remove payment source for username ' . $customer . '.'});
    return 0;
  }
  return 1;
}

1;