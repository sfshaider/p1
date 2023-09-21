package PlugNPay::Transaction::TransactionProcessor::Transform;
# Riddikulus (Harry Potter):
#   spell used when fighting a Boggart;
#   causes the Boggart to transform into something the caster finds humorous
#
# Transforms a transaction into a different type of transaction if necessary, or adds needful data.
# An example of this would be turning a return into a void if a transaction has not yet been settled

use strict;

use PlugNPay::Util::Array qw(inArray);
use PlugNPay::Die;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $input = shift;
  if (!defined $input->{'context'} || ref($input->{'context'}) eq '') {
    die("object requires a transaction context");
  }
  $self->{'context'} = $input->{'context'};

  return $self;
}

# transforms a transaction object into a related object under certian conditions:
#   If the transaction is a return on a transaction that is in the state AUTH, it will change it to a void
#   If the return does not have payment data, it will load the payment data from the auth.
#   if the transaction is a postauth with a lower amount, change the transaction into a reauth with a postauth
#   more to come?
sub transform {
  my $self = shift;
  my $input = shift;
  my $transaction = $input->{'transaction'};

  my $context = $self->{'context'};

  # currently only postauths and credits may be transformed
  if (!inArray($transaction->getTransactionType(),['postauth','mark','credit','return'])) {
    return;
  }

  my $currentTransactionData = $context->getDBTransactionData();

  if ($transaction->getTransactionMode() eq 'return') {
    $self->_modifyReturn($transaction, $currentTransactionData);
  } elsif ($transaction->getTransactionMode() eq 'postauth') {
    $self->_modifyPostauth($transaction, $currentTransactionData);
  }
}

sub _modifyPostauth {
  my $self = shift;
  my $transaction = shift;
  my $currentTransactionData = shift;

  if ($currentTransactionData) {
    if ($transaction->getTransactionAmount() < $currentTransactionData->getTransactionAmount()) {
      $self->_convertToReauth($transaction,$currentTransactionData);
    } else {
      $transaction->setTransactionState('POSTAUTH_READY');
    }
  }
}

sub _modifyReturn {
  my $self = shift;
  my $transaction = shift;
  my $currentTransactionData = shift;

  if ($currentTransactionData) {
    # copy order id, billing info, including payment info, to transaction
    $transaction->setPNPOrderID($currentTransactionData->getPNPOrderID());
    $transaction->setOrderID($currentTransactionData->getOrderID());
    # returns are unique transactions, so it would need a new pnp transaction id.
    $transaction->setBillingInformation($currentTransactionData->getBillingInformation());

    # this *should* always be true at this point, but hey, it's still worth checking.
    $transaction->setExistsInDatabase() if $currentTransactionData->existsInDatabase();

    my $paymentData = $currentTransactionData->getPayment();
    my $vehicleType = $paymentData->getVehicleType();

    if ($vehicleType eq 'ach') {
      $transaction->setOnlineCheck($paymentData);
      $transaction->setSECCode($currentTransactionData->getSECCode());
    } elsif ($vehicleType eq 'card') {
      $transaction->setCreditCard($paymentData);
    }

    # modify the transaction type/mode as needed
    # if the current transaction state is AUTH or POSTAUTH_PENDING, then there are some potential modifications
    if (inArray($currentTransactionData->getTransactionState(),['AUTH','POSTAUTH_READY'])) {
      # if the return amount is less than the original transaction amount, but greater than zero, do a reauth
      # if the return amount is equivilent to the original transaction amount, do a void
      my $returnTooHigh = $transaction->getTransactionAmount() > $currentTransactionData->getBaseTransactionAmount();
      my $reauthWithAdjustment = $transaction->getTransactionAmount() < $currentTransactionData->getBaseTransactionAmount();
      my $reauthWithOverride = $transaction->getTransactionAmount() < $currentTransactionData->getTransactionAmount() && $transaction->getOverrideAdjustment();
      my $voidWithAdjustment = $transaction->getTransactionAmount() == $currentTransactionData->getBaseTransactionAmount();
      my $voidWithOverride = $transaction->getTransactionAmount() == $currentTransactionData->getTransactionAmount() && $transaction->getOverrideAdjustment();

      if ( $transaction->getTransactionAmount() > 0 && ( $reauthWithAdjustment || $reauthWithOverride || $returnTooHigh ) ) {
        # reauths modify the original auth, so we keep the same transaction id.
        $self->_convertToReauth($transaction,$currentTransactionData, {
          reauthWithAdjustment => $reauthWithAdjustment,
          reauthWithOverride => $reauthWithOverride
        });
      } elsif ( $voidWithAdjustment || $voidWithOverride ) {
        $transaction->setPNPTransactionID($currentTransactionData->getPNPTransactionID());
        $transaction->setTransactionMode('void');
        $transaction->setTransactionType('void');
        $transaction->setTransactionState('VOID_PENDING');
      }
    }
  }
}

sub _convertToReauth {
  my $self = shift;
  my $transaction = shift;
  my $currentTransactionData = shift;
  my $adjustmentTestResults = shift;

  $transaction->setPNPTransactionID($currentTransactionData->getPNPTransactionID());

  # reauth amount is the original amount minus the return amount, taking into account adjustment override
  if ($adjustmentTestResults->{'reauthWithAdjustment'}) {
    my $reauthAmount = $currentTransactionData->getBaseTransactionAmount() - $transaction->getTransactionAmount();
    $transaction->setTransactionAmount($reauthAmount);
  } elsif ($adjustmentTestResults->{'reauthWithOverride'}) {
    my $reauthAmount = $currentTransactionData->getTransactionAmount() - $transaction->getTransactionAmount();
    $transaction->setTransactionAmount($reauthAmount);
  }
  my $originalMode = $transaction->getTransactionMode();
  $transaction->setTransactionMode('reauth');
  $transaction->setTransactionType('reauth');
  $transaction->setTransactionState('AUTH_REVERSAL_PENDING');
  if ($currentTransactionData->getTransactionState() eq 'POSTAUTH_READY' || $originalMode eq 'postauth') {
    $transaction->setPostAuth();
  }
}
1;
