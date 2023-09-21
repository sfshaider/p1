package PlugNPay::Transaction::Adjustment::COARemote::Account::MerchantAccount;

use strict;
use PlugNPay::ResponseLink;
use JSON::XS;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub setAccountNumber {
  my $self = shift;
  my $accountNumber = shift;
  $self->{'accountNumber'} = $accountNumber;
}

sub getAccountNumber {
  my $self = shift;
  return $self->{'accountNumber'};
}

sub setID {
  my $self = shift;
  my $id = shift;
  $self->{'id'} = $id;
}

sub getID {
  my $self = shift;
  return $self->{'id'};
}

sub setMerchantAccountIdentifier {
  my $self = shift;
  my $identifier = shift;
  $self->{'merchantAccountIdentifier'} = $identifier;
}

sub getMerchantAccountIdentifier {
  my $self = shift;
  return $self->{'merchantAccountIdentifier'};
}

sub setMID {
  my $self = shift;
  my $mid = shift;
  $self->{'mid'} = $mid;
}

sub getMID {
  my $self = shift;
  return $self->{'mid'};
}

sub setMCC {
  my $self = shift;
  my $mcc = shift;
  $self->{'mcc'} = $mcc;
}

sub getMCC {
  my $self = shift;
  return $self->{'mcc'};
}

sub setProcessorID {
  my $self = shift;
  my $id = shift;
  $self->{'processorID'} = $id;
}

sub getProcessorID {
  my $self = shift;
  return $self->{'processorID'};
}

sub setCountryCode {
  my $self = shift;
  my $code = shift;
  $self->{'countryCode'} = $code;
}

sub getCountryCode {
  my $self = shift;
  return $self->{'countryCode'};
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

sub load {
  my $self = shift;

  my $data = { 
    id => $self->getID(),
    accountNumber => $self->getAccountNumber()
  };

  $self->callAPI($data);
}

sub save {
  my $self = shift;

  my $data = { 
    id => $self->getID(),
    accountNumber => $self->getAccountNumber(),
    identifier => $self->getMerchantAccountIdentifier(),
    mid => $self->getMID(),
    mcc => $self->getMCC(),
    processorID => $self->getProcessorID(),
    countryCode => $self->getCountryCode(),
    type => $self->getType()
  };

  $self->callAPI($data);
}

sub callAPI {
  my $self = shift;
  my $requestData = shift;

  my $rl = new PlugNPay::ResponseLink();
  $rl->setRequestURL('http://coa-api/private/customer_merchant_account.cgi');
  $rl->setRequestMethod('post');
  $rl->setRequestData($requestData);
  $rl->setRequestMode('DIRECT');

  $rl->doRequest();

  if (!$rl->requestFailed) {
    my $data = decode_json($rl->getResponseContent());
    if (ref $data eq 'HASH') {
      $self->setMerchantAccountIdentifier($data->{'identifier'});
      $self->setMID($data->{'mid'});
      $self->setMCC($data->{'mcc'});
      $self->setProcessorID($data->{'processorID'});
      $self->setCountryCode($data->{'countryCode'});
      $self->setType($data->{'type'});
    }
  }
}

sub getMerchantAccounts {
  my $self = shift;
  my $accountNumber = shift || $self->getAccountNumber;

  my $rl = new PlugNPay::ResponseLink();
  $rl->setRequestURL('http://coa-api/private/customer_merchant_accounts.cgi');
  $rl->setRequestMethod('post');
  $rl->setRequestData({ accountNumber => $accountNumber });
#  $rl->setRequestMode('DIRECT');

  $rl->doRequest();

  if (!$rl->requestFailed) {
    my $data = decode_json($rl->getResponseContent());
    if (ref $data eq 'HASH') {
      my %merchantAccounts;
      foreach my $identifier (keys %{$data}) {
        my $class = ref $self;
        my $merchantAccount = eval "new $class()";
        my $accountData = $data->{$identifier};
  
        $merchantAccount->setID($accountData->{'id'});
        $merchantAccount->setMerchantAccountIdentifier($identifier);
        $merchantAccount->setMID($accountData->{'mid'});
        $merchantAccount->setMCC($accountData->{'mcc'});
        $merchantAccount->setProcessorID($accountData->{'processorID'});
        $merchantAccount->setCountryCode($accountData->{'countryCode'});
        $merchantAccount->setType($accountData->{'type'});

        $merchantAccounts{$identifier} = $merchantAccount;
      }
      return \%merchantAccounts;
    }
  }
}

1;
