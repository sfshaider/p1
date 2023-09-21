package PlugNPay::UploadTemplate;

use strict;
use PlugNPay::Receipt;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  $self->setGatewayAccount(shift);
  $self->setPaymentType(shift);
  $self->setReceiptType(shift);
  $self->setAccountType(shift);
  $self->setContext(shift);
  $self->setStatus(shift);

  return $self;
}

sub setPaymentType {
  my $self = shift;
  $self->{'payment_type'} = shift;
}

sub getPaymentType {
  my $self = shift;
  return $self->{'payment_type'};
}

sub setGatewayAccount {
  my $self = shift;
  $self->{'gatewayAccount'} = shift;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

sub setReceiptType {
  my $self = shift;
  $self->{'receipt_type'} = shift;
}

sub getReceiptType {
  my $self = shift;
  return $self->{'receipt_type'};
}

sub setAccountType {
  my $self = shift;
  $self->{'type'} = shift;
}

sub getAccountType {
  my $self = shift;
  return $self->{'type'};
}

sub setHTMLTemplate {
  my $self = shift;
  $self->{'html_template'} = shift;
}

sub getHTMLTemplate {
  my $self = shift;
  return $self->{'html_template'};
}

sub setTextTemplate {
  my $self = shift;
  $self->{'text_template'} = shift;
}

sub getTextTemplate {
  my $self = shift;
  return $self->{'text_template'};
}

sub getTemplate {
  my $self = shift;
  my $type = lc shift;

  return $self->{$type . '_template'};
}

sub setContext {
  my $self = shift;
  my $name = shift;

  my $receipt = new PlugNPay::Receipt();
  my $id = $receipt->getContextID($name);

  $self->{'context_id'} = $id;
}

sub getContext {
  my $self = shift;

  return $self->{'context_id'};
}

sub setStatus {
  my $self = shift;
  my $name = shift;

  my $receipt = new PlugNPay::Receipt();
  my $id = $receipt->getStatusID($name);

  $self->{'status_id'} = $id;
}

sub getStatus {
  my $self = shift;

  return $self->{'status_id'};
}


sub insertTemplate{
  my $self = shift;
  my $format = shift;
  my $template = shift;

  if ($format eq 'text') {
    $self->setTextTemplate($template);
  } elsif ($format eq 'html') {
    $self->setHTMLTemplate($template);
  }

  my $receipt = new PlugNPay::Receipt();
  $receipt->insertTemplates($self->getAccountType(),$self->getGatewayAccount(),$self->getReceiptType(),$self->getHTMLTemplate(),$self->getTextTemplate(),$self->getPaymentType(),1, $self->getContext(), $self->getStatus());
}

sub loadTemplate{
  my $self = shift; 
  my $values = { 'id' => $self->getGatewayAccount(), 'payment_type' => $self->getPaymentType(), 'receipt_type' => $self->getReceiptType(), 'type' => $self->getAccountType(), 'context_id' => $self->getContext(), 'status_id' => $self->getStatus() }; 
  my $receipt = new PlugNPay::Receipt();

  my $templates = $receipt->loadTemplates($values);
  $self->setTextTemplate($templates->{'text'});
  $self->setHTMLTemplate($templates->{'html'});
}

sub deleteTemplate{
  my $self = shift;
  my $values = { 'id' => $self->getGatewayAccount(), 'payment_type' => $self->getPaymentType(), 'receipt_type' => $self->getReceiptType(), 'type' => $self->getAccountType(), 'context_id' => $self->getContext(), 'status_id' => $self->getStatus() }; 
  my $receipt = new PlugNPay::Receipt();

  $receipt->deleteTemplates($values);
}

1;


