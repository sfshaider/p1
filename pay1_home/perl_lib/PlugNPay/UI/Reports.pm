package PlugNPay::UI::Reports;

use strict;
use Switch;
use JSON::XS;
use PlugNPay::UI::Reports::Table;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $options = shift;
 
  if (defined $options && ref($options) eq 'HASH') {
    $self->setSubType($options->{'subtype'});
    $self->setType($options->{'type'});
    $self->setGatewayAccount($options->{'gateway_account'});
  }

  return $self;
}

sub setType {
  my $self = shift;
  my $type = shift;
  $self->{'type'} = $type;
}

sub getType {
  my $self = shift;
  return $self->{'type'};
}

sub setSubType {
  my $self = shift;
  my $subType = shift;
  $self->{'subType'} = $subType;
}

sub getSubType {
  my $self = shift;
  return $self->{'subType'};
}

sub setContent {
  my $self = shift;
  my $content = lc shift;
  $self->{'content'} = $content;
}

sub getContent {
  my $self = shift;
  return $self->{'content'};
}

sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;
  $self->{'gatewayAccount'} = $gatewayAccount;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

sub generateReport {
  my $self = shift;
  my $data = shift;
  if (!defined $data) {
    $data = $self->getContent();
  }

  switch ($self->getType()) {
    case "transaction" {
      if (!defined $data) {
        return "No data to build report!";
      } else {
        if ($self->getSubType() eq 'text') {
          return "";
        } else {
          my $tableMaker = new PlugNPay::UI::Reports::Table();
          return $tableMaker->makeTransactionTable($data);
        }
      }
    }
    case "batch" {
      if (defined $data && $self->getSubType() eq 'table') {
        my $tableMaker = new PlugNPay::UI::Reports::Table();
        return $tableMaker->makeBatchTable($data);
      } else {
        return "Failed to build report!";
      }
    } else {
      if (!defined $data) {
        return '{"error": "No data to build report!"}';
      } else {
        eval {
          return encode_json($data);
        };
  
        if ($@) {
          return '{"error": "JSON encoding error"}';
        }
      }
    }
  }
}

1;
