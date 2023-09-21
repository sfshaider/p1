package PlugNPay::API::REST::Responder::Merchant::Order::Transaction::AuthVia;

use strict;
use PlugNPay::Die;
use PlugNPay::Logging::DataLog;
use PlugNPay::Email::Sanitize;
use PlugNPay::Partners::AuthVia::Merchant;
use PlugNPay::Partners::AuthVia::Conversation;
use base "PlugNPay::API::REST::Responder::Abstract::Merchant";

sub __getOutputData {
  my $self = shift;
  my $action = $self->getAction();

  my $data = shift;
  if ($action eq 'create') {
    $data = $self->_create();
  } elsif ($action eq 'options') {
    $self->setResponseCode(200);
    $data = {};
  } elsif ($action eq 'delete') {
    $data = $self->_delete();
  } else {
    $self->setResponseCode(501);
  }

  return $data;
}

sub _create {
  my $self = shift;
  my $merchant = lc($self->getResourceData()->{'merchant'} || $self->getGatewayAccount());
  my $inputData = $self->getInputData();

  my $phone = $inputData->{'phone'};
  my $email = $inputData->{'email'};
  my $amount = $inputData->{'amount'};
  my $description = $inputData->{'description'};
  my $currency = $inputData->{'currency'} || 'USD';
  my $name = $inputData->{'name'};
  my $deadline = $inputData->{'deadline'} || '1d';

  # filters, not using input validator because that was meant as a quick fix for existing code.
  $phone =~ s/[^\d\+]//g;
  $email = PlugNPay::Email::Sanitize::sanitize($email);
  $amount =~ s/[^\d\.]//g;
  $merchant =~ s/[^a-z\d]//g;
  $name =~ s/[^\p{Word}]//g;
  $deadline =~ s/[^\dwdhm]//g; # digits or w, d, h, or m
  $description =~ s/[^\p{Word}\-\s\.]//g;

  if (!defined $phone) {
    $self->setResponseCode(422);
    $self->setError("missing or invalid required data: phone");
  }

  my $response = {};
  my $conversationStarter = new PlugNPay::Partners::AuthVia::Conversation();
  eval {
    $conversationStarter->setGatewayAccount($merchant);
    my $convoData = {
      'phoneNumber' => $phone,
      'contextData' => {
        'amount' => sprintf("%.2f", $amount),
        'description' => $description
      },
      'topic' => 'payment'
    };
    $convoData->{'name'} = $name if defined $name;
    $convoData->{'deadline'} = $deadline;
    $response = $conversationStarter->create($convoData);
  };

  if ($@) {
    $conversationStarter->log({'error' => $@, 'merchant' => $merchant, 'amount' => $amount}); 
    $self->setResponseCode(520);
    $self->setError('An error occurred when starting Text2Pay Conversation');
    return {};
  }

  my $output = {
    'authViaId'    => $response->{'authViaId'},
    'status'       => $response->{'status'},
    'customerData' => $response->{'customerData'}
  };

  if ($response->{'status'} eq 'failed') {
    $self->setResponseCode(422);
    $self->setError('failed to create conversation');
  } elsif (!defined $response->{'authViaId'}) {
    $self->setResponseCode(400);
    $self->setError('failed to create conversation, unknown error');
  } else {
    $self->setResponseCode(201);
  }

  return $output;
}

sub _delete {
  my $self = shift;
  my $merchant = lc($self->getResourceData()->{'merchant'} || $self->getGatewayAccount());
  my $conversationId = $self->getResourceData()->{'authvia'};
  my $conversation = new PlugNPay::Partners::AuthVia::Conversation();
  $conversation->setGatewayAccount($merchant);
  my $results = {};
  eval {
    $results = $conversation->update($conversationId, {'status' => 'failed'});
  };
  if ($@) {
    $conversation->log({'merchant' => $merchant, 'conversationId' => $conversationId, 'error' => $@, 'action' => 'cancelConversation'});

    $self->setResponseCode(520);
    return {'status' => 'error', 'message' => 'An error occurred while cancelling conversation'};
  }

  if ($results->{'status'} eq 'failed') {
    $self->setResponseCode(200);
    return {'status' => 'success', 'message' => 'conversation cancelled'};
  } else {
    $self->setResponseCode(400);
    return {'status' => 'failure', 'message' => 'conversation failed to cancel, current status: ' . $results->{'status'}};
  }
}

1;
