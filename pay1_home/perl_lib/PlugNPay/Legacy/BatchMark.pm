package PlugNPay::Legacy::BatchMark;

use strict;

use PlugNPay::DBConnection;
use PlugNPay::Transaction::Loader;
use PlugNPay::Transaction::Saver::Legacy::Mark;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

# add pod here
# this is for calling via route
sub viaRoute {
  my $self = shift;
  my $gatewayAccount = shift;
  my $pairs = shift;

  my %ordersInfo;

  foreach my $key (keys %{$pairs}) {
    if ($key =~ /^order-id-(\d+)$/) {
      my $identifier = $1;
      my $orderId = $pairs->{$key};

      my $markAmount = $pairs->{'amount-' . $identifier};
      $markAmount =~ s/^\w{3}?\s*([\d\.]+)$/$1/; # remove leading currency and space if present

      my $gratuityAmount = $pairs->{'gratuity-' . $identifier};
      $gratuityAmount =~ s/^\w{3}?\s*([\d\.]+)$/$1/; # ditto

      my $accountCode4 = $pairs->{'acct_code4-' . $identifier};

      $ordersInfo{$orderId} = {
        id => $identifier,
        markAmount => $markAmount,
        gratuityAmount => $gratuityAmount,
        accountCode4 => $accountCode4
      };
    }
  }

  my $results = $self->batchMark({
    gatewayAccount => $gatewayAccount,
    ordersInfo => \%ordersInfo
  });

  my %emulatedResponse;
  # emulate sendmserver response
  foreach my $orderId (keys %{$results}) {
    my $identifier = $ordersInfo{$orderId}{'id'};
    $emulatedResponse{'order-id-' . $identifier} = $orderId;
    $emulatedResponse{'response-code-' . $identifier} = $results->{$orderId}{'responseCode'};
    $emulatedResponse{'exception-message-' . $identifier} = $results->{$orderId}{'exceptionMessage'};
  }

  $emulatedResponse{'MStatus'}     = "success";
  $emulatedResponse{'FinalStatus'} = "success";
  $emulatedResponse{'MErrMsg'}     = "Post Authorizations Attempted";
  
  return \%emulatedResponse;
}

sub batchMark {
  my $self = shift;
  my $input = shift;

  my $gatewayAccount = $input->{'gatewayAccount'};
  my $ordersInfo = $input->{'ordersInfo'};

  my @orderIds = keys %{$ordersInfo};

  if (@orderIds == 0) {
    # nothing to do
    return
  }

  my %errors;

  my $transactions = $self->_load({
    gatewayAccount => $gatewayAccount,
    orderIdsArray => \@orderIds
  });

  while (my ($orderId,$transaction) = each %{$transactions}) {
    my $info = $ordersInfo->{$orderId};

    my $markAmount = $info->{'markAmount'} || $transaction->getTransactionAmount();
    my $gratuityAmount = $info->{'gratuityAmount'} || 0;
    my $accountCode4 = $info->{'accountCode4'} || '';

    $transaction->setSettlementAmount($markAmount);
    $transaction->setGratuityAmount($gratuityAmount);
    $transaction->setAccountCode(4,$accountCode4);
  }

  my $errors = $self->_mark({
    gatewayAccount => $gatewayAccount,
    transactions => $transactions
  });

  my %results;

  foreach my $orderId (keys %{$transactions}) {
    my %result;
    if (defined $errors->{$orderId} && $errors->{$orderId} ne '') {
      $result{'responseCode'} = 'problem';
      $result{'exceptionMessage'} = $errors->{$orderId};
    } else { # SUCCESS!
      $result{'responseCode'} = 'success';
      $result{'exceptionMessage'} = '';
    }
    $results{$orderId} = \%result;
  }

  return \%results;
}

sub _mark {
  my $self = shift;
  my $input = shift;

  my $gatewayAccount = $input->{'gatewayAccount'};
  my $transactions = $input->{'transactions'};

  my $marker = new PlugNPay::Transaction::Saver::Legacy::Mark();
  my $result = $marker->mark({
    gatewayAccount => $gatewayAccount,
    transactions => $transactions
  });
  my $errors = $result->{'errors'};

  return $errors;
}

sub _load {
  my $self = shift;
  my $input = shift;

  my $gatewayAccount = $input->{'gatewayAccount'};
  my $orderIdsArray = $input->{'orderIdsArray'};

  my $loader = new PlugNPay::Transaction::Loader();

  # build input for loader from gateway account and order ids array
  my @loaderInput = map { 
    my $data = { 
      version => 'legacy', 
      gatewayAccount => $gatewayAccount, 
      orderID => $_ 
    };
    $data;
  } @{$orderIdsArray};

  my $loaded = $loader->load(\@loaderInput);

  # return empty array if no transactions are loaded for the gateway account
  return $loaded->{$gatewayAccount} || [];
}

1;