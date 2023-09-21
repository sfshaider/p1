package PlugNPay::UI::Reports::Table;

use strict;
use PlugNPay::UI::HTML;
use PlugNPay::Sys::Time;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $data = shift;
  if (defined $data && ref($data) eq 'HASH') {
    $self->setTableData($data);
  }

  return $self;
}

sub setTableData {
  my $self = shift;
  my $tableData = shift;
  $self->{'tableData'} = $tableData;
}

sub getTableData {
  my $self = shift;
  return $self->{'tableData'};
}

#Make google chart or HTML table for transactions
sub makeTransactionTable {
  my $self = shift;
  my $transactions  = shift;

  if (!defined $transactions || ref($transactions) ne 'HASH') {
    $transactions = $self->getTableData();
  }

  my $htmlBuilder = new PlugNPay::UI::HTML();
  my @cols = (
    {'name'=>'Order ID','type'=>'string'},
    {'name'=>'Transaction Time','type'=>'string'},
    {'name'=>'Status','type'=>'string'},
    {'name'=>'Processor','type'=>'string'},
    {'name'=>'Amount','type'=>'string'},
    {'name'=>'Settlement Time','type'=>'string'},
    {'name'=>'Batch ID','type'=>'string'}
  );

  my @data = ();
  my $time = new PlugNPay::Sys::Time();
  foreach my $transactionID (keys %{$transactions}) {
    my $transaction = $transactions->{$transactionID};
    my @entry = ();
    my $settlementTime = $transaction->getTransactionSettlementTime();
    my $transactionTime = $transaction->getTransactionDateTime();
    $settlementTime =~ s/[^\d]//g;
    $transactionTime =~ s/[^\d]//g;

    $time->fromFormat('gendatetime',$transactionTime);
    push @entry,$transaction->getOrderID();
    push @entry,$time->inFormat('db_gm');
    push @entry,$transaction->getTransactionState();
    push @entry,$transaction->getProcessor();
    push @entry,$transaction->getTransactionAmount();

    $time->fromFormat('gendatetime',$settlementTime);
    push @entry,$time->inFormat('db_gm');

    my $batchID;
    eval { $batchID = $transaction->getExtraTransactionData()->{'batchID'}; };

    if (!$batchID || $@) {
      $batchID = 'N/A';
    }
    push @entry,$batchID;

    push @data, \@entry;
  }

  my $options = {'data' => \@data,'columns' => \@cols,id=>'ReportTable'};
  my $report = $htmlBuilder->buildTable($options);

  return $report;
}

sub makeBatchTable {
  my $self = shift;
  my $batches = shift;

  if (!defined $batches || ref($batches) ne 'HASH') {
    $batches = $self->getTableData();
  }

  my $htmlBuilder = new PlugNPay::UI::HTML();
  my @cols = (
    {'name'=>'Batch ID','type'=>'string'},
    {'name'=>'Batch Time','type'=>'string'},
    {'name'=>'Status','type'=>'string'}
  );

  my @data = ();
  my $time = new PlugNPay::Sys::Time();
  foreach my $batchID (keys %{$batches}) {
    my $temp = [
       $batchID,
       $batches->{$batchID}{'batchTime'},
       $batches->{$batchID}{'status'}
    ];
    push @data, $temp;
  }

  my $options = {'data' => \@data, 'columns' => \@cols, 'id' => 'BatchReportTable'};
  return $htmlBuilder->buildTable($options);
}

1;
