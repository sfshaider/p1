package PlugNPay::Processor::Process::MessageBuilder;

use strict;
use PlugNPay::Processor::ID;
use PlugNPay::Util::UniqueID;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;


  return $self;
}

sub build {
  my $self = shift;
  my $transactionHash = shift;
  my $uuid = new PlugNPay::Util::UniqueID();

  my $message = { messageID => $uuid->inHex(),requests => $transactionHash };
  return $message;
}

sub buildRedeemMessage {
  my $self = shift;
  my $transactions = shift;
  my $processorID = shift;

  my $pending = $self->prepareRedeem($transactions,$processorID);

  return $self->build($pending);
}

sub prepareRedeem {
  my $self = shift;
  my $transactions = shift;
  my $procID = shift;

  my $pending = {};
  foreach my $transaction (values %{$transactions}) {
    my $hash = $self->requestContent($transaction,$procID,5,'redeem');
    $pending->{$hash->{'requestID'}} = $hash;
  }
  return $pending;
}

sub requestContent {
  my $self = shift;
  my $transaction = shift;
  my $processorID = shift;
  my $priority = shift || 5;
  my $type = shift || 'redeem';
  my $util = new PlugNPay::Processor::ID();
  my $data = {'transactionData' => {'pnp_transaction_id' => $transaction->{"pnp_transaction_id"},'requestType'=>$type},
                'type' => $type, 'priority' => $priority,
                'processor' => $util->getProcessorName($processorID)
               };
  if (defined ($transaction->{'pnp_transaction_id'})) {
    $data->{'requestID'} = $transaction->{'pnp_transaction_id'},
  } else {
    $data->{'requestID'} = new PlugNPay::Util::UniqueID()->inHex();
  }
  return $data;

}

sub buildRemoveMessage {
  my $self = shift;
  my $transactions = shift;
  my $processorID = shift;
  my $error = shift;

  my $pending = $self->prepareRemove($transactions,$processorID,$error);

  return $self->build($pending);
}

sub prepareRemove {
  my $self = shift;
  my $transactions = shift;
  my $procID = shift;
  my $error = shift || {};
  my $uuidFormat = new PlugNPay::Util::UniqueID();
  my $pending = {};
  foreach my $transaction (values %{$transactions}) {
    $uuidFormat->fromHex($transaction->{'pnp_transaction_id'});
    my $pnpID = $uuidFormat->inBinary();
    if (!defined $error->{$pnpID} || $error->{$pnpID} == 0) {
      my $hash = $self->requestContent($transaction,$procID,3,'remove');
      $pending->{$hash->{'requestID'}} = $hash;
    }
  }

  return $pending;
}

sub buildStatusMessage {
  my $self = shift;
  my $message = shift;
  my $messageMap = {};
  foreach my $merchant (keys %{$message}) {
    my $tempMessage = $message->{$merchant};
    $messageMap->{$tempMessage->{'requestID'}} = $tempMessage;
  }

  return $self->build($messageMap);
}

1;
