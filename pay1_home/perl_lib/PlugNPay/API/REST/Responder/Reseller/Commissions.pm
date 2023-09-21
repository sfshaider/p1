package PlugNPay::API::REST::Responder::Reseller::Commissions;

use strict;
use PlugNPay::Reseller::Commissions;

use base "PlugNPay::API::REST::Responder";

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();

  return $self->_read();
}

sub _read {
  my $self = shift;
  my $output = {};
  my $options = $self->getResourceOptions();
  my $username = $self->getGatewayAccount();
  my $comms = new PlugNPay::Reseller::Commissions($username);
  $comms->setStartDate($options->{'startyear'},$options->{'startmonth'});
  $comms->setEndDate($options->{'endyear'},$options->{'endmonth'});

  #Build data for table
  my $data = $comms->getCommissions('table');
  my @rows;
  foreach my $user (sort keys %{$data->{'data'}}){
    foreach my $order (sort keys %{$data->{'data'}{$user}} ){
        my @row;
        my $orderRef = $data->{'data'}{$user}{$order};
        push @row,$orderRef->{'username'};
        push @row,$orderRef->{'orderid'};
        push @row,$orderRef->{'transdate'};
        push @row,$orderRef->{'amount'};
        push @row,$orderRef->{'descr'};
        push @row,$orderRef->{'commission'};
        push @row,$orderRef->{'paydate'};
        push @rows,\@row;
    }
  }

  my @cols = (
              {'name'=>'Username','type'=>'string','id'=>'gatewayAccountName'},
              {'name'=>'Order ID', 'type' => 'string','id'=>'CommOrderID'},
              {'name'=>'Transaction Date','type'=>'string','id'=>'TransDate'},
              {'name'=>'Billed Amount','type'=>'string','id'=>'BilledAmount'},
              {'name'=>'Description','type'=>'string','id'=>'CommDescr'},
              {'name'=>'Commission','type'=>'string','id'=>'CommAmount'},
              {'name'=>'Payout Date','type'=>'string','id'=>'PayDate'} );

  my $tableOptions = {'columns' => \@cols, 'data' => \@rows, 'id' => 'mainTable'};
  my $grandTotal = $data->{'paidtotal'} + $data->{'commtotal'};

  $output = {'table' => $tableOptions, 'comm' =>  sprintf("%.2f",$data->{'commtotal'}), 'paid' =>  sprintf("%.2f",$data->{'paidtotal'}), 'total' =>  sprintf("%.2f",$grandTotal)};

  if (length(@rows) > 0) {
    $self->setResponseCode('200');
  } else {
    $self->setResponseCode('520');
  }
  return $output;
}

1;
