package PlugNPay::Transaction::Logging::CustomData;

use strict;
use JSON::XS;
use PlugNPay::Sys::Time;
use PlugNPay::GatewayAccount;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $merchant = shift;
  if ($merchant) {
    $self->setMerchant($merchant);
  }

  return $self;
}

sub setMerchant {
  my $self = shift;
  my $merchant = shift;
  $self->{'merchant'} = $merchant;
}

sub getMerchant {
  my $self = shift;
  return $self->{'merchant'};
}

sub loadCustomData {
  my $self = shift;
  my $orderIDs = shift || [];
  my $startTime = shift;
  my $endTime = shift;
  my $merchant = shift || $self->getMerchant();
  my $responseData = {};
  my $time = new PlugNPay::Sys::Time();
  $startTime = $time->inFormatDetectType('yyyymmdd',$startTime);
  $endTime = $time->inFormatDetectType('yyyymmdd',$endTime);
  while ($startTime <= $endTime) {
    if (@{$orderIDs} && PlugNPay::GatewayAccount::exists($merchant)){ 
      foreach my $id (@{$orderIDs}) {
        my $response = $self->_parseData($id,$startTime,$merchant);
        if (!defined $responseData->{$id} || ref($responseData->{$id}) ne 'HASH') {
          $responseData->{$id} = $response; 
        } else {
          my %merged = (%{$response}, %{$responseData->{$id}});
          $responseData->{$id} = \%merged;
        }
      }
    }
    $time->fromFormat('yyyymmdd',$startTime);
    $time->addHours(24);
    $startTime = $time->inFormat('yyyymmdd');
  }

  return $responseData;
}

sub _parseData {
  my $self = shift;
  my $orderID = shift;
  my $date = shift;
  my $merchant = shift || $self->getMerchant();
  my $buffer = '';
  my @lines = ();
  my $merchantInitials = substr(lc($merchant),0,2);
  my $customData = {};

  my $fileName = lc($merchant) . '.' . $date . '.log';
  eval {
    open (my $fh,'/home/pay1/logs/merchant/' . $date . '/' . $merchantInitials . '/' . $fileName);
    sysread($fh, $buffer, -s $fh);
    close($fh);
    @lines = grep {$orderID} split("\n", $buffer);
  };
  
  foreach my $line (@lines) {
    eval {
      my $json = decode_json($line);
      my $parsedData = $json->{'transactionData'};
      if ($parsedData->{'orderID'} == $orderID) {
        foreach my $key (keys %{$parsedData}) {
          if ($key =~ /customname/i) {
            my $convertedKey = $key;
            $convertedKey =~ s/name/value/i;
            $customData->{$parsedData->{$key}} = $parsedData->{$convertedKey};
          }
        }

        $customData->{'orderID'} = $parsedData->{'orderID'};
        $customData->{'FinalStatus'} = $parsedData->{'FinalStatus'};
        $customData->{'amountcharged'} = $parsedData->{'amountcharged'};
      }
    };
  }

  return $customData;
}

1;
