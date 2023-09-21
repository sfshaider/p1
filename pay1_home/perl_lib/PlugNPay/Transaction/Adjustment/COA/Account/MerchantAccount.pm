package PlugNPay::Transaction::Adjustment::COA::Account::MerchantAccount;

use strict;
use JSON::XS;

use PlugNPay::ResponseLink;
use PlugNPay::Transaction::Adjustment::GlobalSettings;


sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
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
  my $mode = shift;

  my $data = {
    gateway => 'plugnpay',
    gatewayAccountIdentifier => $self->getGatewayAccount(),
    identifier => $self->getMerchantAccountIdentifier(),
    mode => 'read'
  };

  my $apiData = $self->callAPI($data);

  if (ref $apiData eq 'HASH' && $apiData->{'exists'}) {
    $self->setMerchantAccountIdentifier($apiData->{'identifier'});
    $self->setMID($apiData->{'mid'});
    $self->setMCC($apiData->{'mcc'});
    $self->setProcessorID($apiData->{'processorID'});
    $self->setCountryCode($apiData->{'countryCode'});
    $self->setType($apiData->{'type'});
    return 1;
  }
}

sub exists {
  my $self = shift;
  my $data = {
    gateway => 'plugnpay',
    gatewayAccountIdentifier => $self->getGatewayAccount(),
    identifier => $self->getMerchantAccountIdentifier(),
    mode => 'exists'
  };

  my $apiData = $self->callAPI($data);

  if (ref $apiData eq 'HASH' && $apiData->{'exists'}) {
    return 1;
  }
  return 0;
}

sub create {
  my $self = shift;
  if (!$self->exists) {
    return $self->_save('create')->{'success'};
  }
}

sub update {
  my $self = shift;
  if ($self->exists()) {
    my $result = $self->_save('update');
    return $result->{'success'};
  }
}

sub _save {
  my $self = shift;
  my $mode = shift;

  my $data = {
    mode => $mode,
    gateway => 'plugnpay',
    gatewayAccountIdentifier => $self->getGatewayAccount(),
    identifier => $self->getMerchantAccountIdentifier(),
    mid => $self->getMID(),
    mcc => $self->getMCC(),
    processorID => $self->getProcessorID(),
    countryCode => $self->getCountryCode(),
    type => $self->getType()
  };

  return $self->callAPI($data);
}

sub callAPI {
  my $self = shift;
  my $requestData = shift;

  my $gs = new PlugNPay::Transaction::Adjustment::GlobalSettings();
  my $host = $gs->getHost();

  my $url = sprintf('http://%s/private/customer_merchant_account.cgi',$host);

  my $rl = new PlugNPay::ResponseLink();
  $rl->setRequestURL($url);
  $rl->setRequestMethod('post');
  $rl->setRequestData($requestData);
  $rl->setRequestMode('DIRECT');

  $rl->doRequest();

  if (!$rl->requestFailed) {
    my $data;
    eval {
      $data = decode_json($rl->getResponseContent());
    };
    return $data;
  }
  return {};
}

sub getMerchantAccounts {
  my $self = shift;
  my $accountNumber = shift || $self->getAccountNumber;

  my $gs = new PlugNPay::Transaction::Adjustment::GlobalSettings();
  my $host = $gs->getHost();

  my $url = sprintf('http://%s/private/customer_merchant_accounts.cgi',$host);

  my $rl = new PlugNPay::ResponseLink();
  $rl->setRequestURL($url);
  $rl->setRequestMethod('post');
  $rl->setRequestData({ accountNumber => $accountNumber });
  $rl->setRequestMode('DIRECT');

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

sub accountTypeAndIdentifier {
  my $processorAccountObject = shift;

  my $retailSetting = $processorAccountObject->getIndustry();

  my ($accountType,$identifier);
  if ($retailSetting eq 'retail') {
    $accountType = 'retail';
    $identifier |= 'retail';
  } elsif ($retailSetting eq 'petroleum') {
    $accountType = 'petroleum';
    $identifier |= 'petrol';
  } elsif ($retailSetting eq 'restaurant') {
    $accountType = 'restaurant';
    $identifier |= 'restaurant';
  } else {
    $accountType = 'ecommerce';
    $identifier |= 'ecom';
  }

  return { accountType => $accountType, identifier => $identifier };
}
1;
