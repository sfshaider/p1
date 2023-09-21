package PlugNPay::Processor::Process::Batch::Result;

use strict;
use PlugNPay::Email;
use PlugNPay::Reseller;
use PlugNPay::DBConnection;
use PlugNPay::GatewayAccount;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $username = shift;
  if ($username) {
    $self->setGatewayAccount($username);
  }

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

sub setBatchID {
  my $self = shift;
  my $batchID = shift;
  $self->{'batchID'} = $batchID;
}

sub getBatchID {
  my $self = shift;
  return $self->{'batchID'};
}

sub loadResults {
  my $self = shift;
  my $batchID = shift || $self->getBatchID();
  my $username = shift || $self->getGatewayAccount();

   my $select = q/
     SELECT br.batchid, br.orderid, br.line, bid.username,
            bid.header, bid.headerflag, bid.trans_time,
            bid.emailflag, bid.emailaddress, bid.status
       FROM batchresult br, batchid bid
      WHERE bid.username = ?
        AND bid.batchid = ?
        AND br.batchid = bid.batchid
        AND br.username = bid.username
        AND br.orderid BETWEEN bid.firstorderid AND bid.lastorderid
   ORDER BY br.orderid ASC
   /; 
   my $dbs = new PlugNPay::DBConnection();
   my $rows = [];
   eval {
     $rows = $dbs->fetchallOrDie('uploadbatch', $select, [$username, $batchID], {})->{'result'};
   };

   my $results = {};
   my $batchFile = [];
   if (@{$rows} > 0) {
     $results->{'batchStatus'} = $rows->[0]{'status'};
     $results->{'batchID'} = $rows->[0]{'batchID'};
     $results->{'merchant'} = $rows->[0]{'username'};
     my @successes = ();
     my @failures = ();
     my @parsedHeader = split(/\t/,$rows->[0]{'header'}); #TODO: find out correct header
     $results->{'shouldIncludeHeader'} = ($rows->[0]{'headerflag'} eq 'yes' ? 'true' : 'false');

     #now add lines to "result file"
     foreach my $row (@{$rows}) {
       my @line = split(/\t/,$row->{'line'});
       push @{$batchFile},\@line;
       if ($line[0] eq 'success') {
         push @successes,$row->{'orderid'};
       } else {
         push @failures,$row->{'orderid'};
       }
     }

     $results->{'header'} = \@parsedHeader;
     $results->{'resultFile'} = $batchFile;
     $results->{'orderIDs'} = {
       'successes' => \@successes,
       'failures' => \@failures
     };

   }

   return $results;
}

sub sendBatchEmail {
  my $self = shift;
  my $batchFile = shift;
  my $emailAddress = shift;
  my $batchID = shift || $self->getBatchID();
  my $username = shift || $self->getGatewayAccount();
  my $ga = new PlugNPay::GatewayAccount($username);
  my $reseller = new PlugNPay::Reseller($ga->getReseller());
 
  my $emailer = new PlugNPay::Email('legacy');
  $emailer->setContent("Here is your batch results:\n\n" . join(/\n/,@{$batchFile}));
  $emailer->setGatewayAccount($username);
  $emailer->setTo($emailAddress);
  $emailer->setFrom($reseller->getNoReplyEmail() || 'noreply@plugnpay.com');
  $emailer->setSubject('Results for batch ' . $batchID);
 
  return $emailer->send();
}

sub getBatchStatuses {
  my $self = shift;
  my $startDate = shift;
  my $endDate = shift;
  my $username = shift || $self->getGatewayAccount();
  my $timeObj = new PlugNPay::Sys::Time();

  my $select = q/
    SELECT batchid, username, status, trans_time AS `batch_time`
      FROM batchid
     WHERE username = ?
       AND trans_time BETWEEN ? AND ? 
  /;

  my $dbs = new PlugNPay::DBConnection();
  my $rows = [];
  eval {
    $rows = $dbs->fetchallOrDie('uploadbatch',$select, [$username, $startDate, $endDate], {})->{'result'};
  };

  my $results = {};
  foreach my $row (@{$rows}) {
    my $batchID = $row->{'batchid'};
    $timeObj->fromFormat('gendatetime', $row->{'batch_time'});
    $results->{$username}{$batchID} = {
      'status'    => $row->{'status'},
      'batchTime' => $timeObj->inFormat('db_gm'),
      'batchID'   => $batchID,
      'username'  => $username
    };
  }

  return $results;
}

1;
