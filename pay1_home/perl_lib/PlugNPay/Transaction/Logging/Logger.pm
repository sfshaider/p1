  package PlugNPay::Transaction::Logging::Logger;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::UniqueID;
use PlugNPay::Sys::Time;

###################### Logger ########################
# Only used to log state changes in new transactions #
######################################################

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;


  return $self;
}

sub loadMultipleLogs {
  my $self = shift;
  my $transactionIDs = shift;
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnp_transaction');
  my @params = ();
  my @values = ();

  foreach my $id (@{$transactionIDs}) {
    push @values,$id;
    push @values,$id;
    push @params,' (transaction_id = ? OR transaction_ref_id = ?) ';
  }

  if (@values == 0) {
    return {};
  }

  my $sth = $dbs->prepare(q/
                           SELECT transaction_id,transaction_ref_id,previous_state_id,new_state_id,message
                           FROM transaction_log
                           WHERE / . join (' OR ' , @params));
  $sth->execute(@values) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my $logs = {};
  foreach my $row (@{$rows}) {
    if ($logs->{$row->{'transaction_id'}}) {
      push @{$logs->{$row->{'transaction_id'}}},$row;
    } else {
      $logs->{$row->{'transaction_id'}} = [$row];
    }
  }

  return $logs;
}

sub loadLogs {
  my $self = shift;
  my $transactionID = shift;
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnp_transaction');
  my $sth = $dbs->prepare(q/
                           SELECT transaction_id,transaction_ref_id,previous_state_id,new_state_id,message
                           FROM transaction_log
                           WHERE transaction_id = ? OR transaction_ref_id = ?
                           /);
  $sth->execute($transactionID,$transactionID) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});

  return $rows;
}

sub log {
  my $self = shift;
  my $data = shift;
  my $response = 0;
  eval {
    $response = $self->_logTransaction($data);
  };

  return $response;
}

sub _logTransaction {
  my $self = shift;
  my $data = shift;
  my $uuid = new PlugNPay::Util::UniqueID();
  my $time = new PlugNPay::Sys::Time();
  if (defined $data->{'transaction_id'} && defined $data->{'new_state_id'} && $data->{'previous_state_id'}) {
    my $transactionID = $data->{'transaction_id'};
    if ($transactionID =~ /^[0-9a-fA-F]+$/) {
      $uuid->fromHex($transactionID);
      $transactionID = $uuid->inBinary();
    }

    my $refID;
    if (defined $data->{'transaction_ref_id'}) {
      my $refID = $data->{'transaction_id'};
      if ($refID =~ /^[0-9a-fA-F]+$/) {
        $uuid->fromHex($refID);
        $refID = $uuid->inBinary();
      }
    }

    my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnp_transaction');
    my $sth = $dbs->prepare(q/
                             INSERT INTO transaction_log
                             (transaction_id,transaction_ref_id,previous_state_id,new_state_id,message,change_date_time)
                             VALUES (?,?,?,?,?,?)
                             /);
    $sth->execute($transactionID,$refID,$data->{'previous_state_id'},$data->{'new_state_id'},$data->{'message'},$time->nowInFormat('iso_gm')) or die $DBI::errstr;
    $sth->finish();

    return 1;
  } else {
    return 0;
  }
}

sub jobLog {
  my $self = shift;
  my $data = shift;
  my $response = 0;

  eval {
    $response = $self->_jobLog($data);
  };

  return $response;
}

sub _jobLog {
  my $self = shift;
  my $data = shift;

  my @values = ();
  my @params = ();
  my $uuid = new PlugNPay::Util::UniqueID();
  my $time = new PlugNPay::Sys::Time();
  foreach my $jobID (keys %{$data}) {

    if ($jobID =~ /^[a-fA-F0-9]+$/) {
      $uuid->fromHex($jobID);
      push @values,$uuid->toBinary();
    } else {
      push @values,$jobID;
    }
    my $message =  ($data->{$jobID}{'status'} ? 'Successfully batched settlement' : 'Settlement batching failed, rolledback changes');
    push @values,$message;
    push @values,$time->nowInFormat('iso_gm');
    push @params,'(?,?,?)';
  }

  eval {
    my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnp_transaction');
    my $sth = $dbs->prepare(q/
                             INSERT INTO settlement_job_log
                             (job_id,message,log_time)
                             VALUES / . join(',',@params));
    $sth->execute(@values) or die $DBI::errstr;
    $sth->finish();
  };

  if ($@) {
    return 0;
  } else {
    return 1;
  }
}

1;
