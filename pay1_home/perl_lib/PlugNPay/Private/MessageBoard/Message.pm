package PlugNPay::Private::MessageBoard::Message;

use strict;
use PlugNPay::Sys::Time;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Logging::DataLog;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub setMessageID {
  my $self = shift;
  my $messageID = shift;
  $self->{'messageID'} = $messageID;
}

sub getMessageID {
  my $self = shift;
  return $self->{'messageID'};
}

sub setMessageDate {
  my $self = shift;
  my $messageDate = shift;
  $self->{'messageDate'} = $messageDate;
}

sub getMessageDate {
  my $self = shift;
  return $self->{'messageDate'};
}

sub setOutage {
  my $self = shift;
  my $outage = shift;
  $self->{'outage'} = $outage;
}

sub getOutage {
  my $self = shift;
  return $self->{'outage'};
}

sub setMessageSubject {
  my $self = shift;
  my $messageSubject = shift;
  $self->{'messageSubject'} = $messageSubject;
}

sub getMessageSubject {
  my $self = shift;
  return $self->{'messageSubject'};
}

sub setMessage {
  my $self = shift;
  my $message = shift;
  $self->{'message'} = $message;
}

sub getMessage {
  my $self = shift;
  return $self->{'message'};
}

sub _setMessageDataFromRow {
  my $self = shift;
  my $row = shift;

  $self->{'messageID'}      = $row->{'message_id'};
  $self->{'messageDate'}    = $row->{'message_date'};
  $self->{'outage'}         = $row->{'outage'};
  $self->{'messageSubject'} = $row->{'message_subject'};
  $self->{'message'}        = $row->{'message'};
}

sub messageExists {
  my $self = shift;
  my $messageID = shift;

  my $exists = 0;
  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('pnpmisc',
      q/SELECT COUNT(*) as `exists`
          FROM private_message
		     WHERE message_id = ?/, [$messageID], {})->{'result'};
    $exists = $rows->[0]{'exists'};
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'private_message_board' });
    $logger->log({
      'error'     => $@,
      'messageID' => $messageID,
      'function'  => 'messageExists'
    });
  }

  return $exists;
}

sub loadMessage {
  my $self = shift;
  my $messageID = shift;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('pnpmisc',
      q/SELECT id,
               message_id,
               message_date,
               outage,
               message_subject,
               message
          FROM private_message
         WHERE message_id = ?/, [$messageID], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setMessageDataFromRow($rows->[0]);
    }
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'private_message_board' });
    $logger->log({
      'error'     => $@,
      'messageID' => $messageID,
      'function'  => 'loadMessage'
    });
  }
}

sub loadMessages {
  my $self = shift;

  my $messages = [];
  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('pnpmisc',
      q/SELECT message_id,
               message_date,
               outage,
               message_subject,
               message
          FROM private_message
      ORDER BY message_date DESC/, [], {})->{'result'};
    if (@{$rows} > 0) {
      foreach my $row (@{$rows}) {
        my $message = new PlugNPay::Private::MessageBoard::Message();
        $message->_setMessageDataFromRow($row);
        push (@{$messages}, $message);
      }
    }
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'private_message_board' });
    $logger->log({
      'error'    => $@,
      'function' => 'loadMessages'
    });
  }

  return $messages;
}

sub saveMessage {
  my $self = shift;

  my $status = new PlugNPay::Util::Status(1);
  eval {
    my $params = [
      $self->{'messageID'},
      new PlugNPay::Sys::Time()->nowInFormat('iso'),
      $self->{'outage'},
      $self->{'messageSubject'},
      $self->{'message'}
    ];

    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('pnpmisc',
      q/INSERT INTO private_message
        ( message_id,
          message_date,
          outage,
          message_subject,
          message )
        VALUES (?,?,?,?,?)/, $params);
  };

  if ($@) {
    $status->setFalse();
    $status->setError('Failed to save private message.');
    $status->setErrorDetails($@);
  }

  return $status;
}

sub updateMessage {
  my $self = shift;

  my $status = new PlugNPay::Util::Status(1);
  eval {
    my $params = [
      $self->{'outage'},
      $self->{'messageSubject'},
      $self->{'message'},
	    $self->{'messageID'}
    ];

    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('pnpmisc',
      q/UPDATE private_message
           SET outage = ?,
               message_subject = ?,
               message = ?
         WHERE message_id = ?/, $params);
  };

  if ($@) {
    $status->setFalse();
    $status->setError('Failed to update private message.');
    $status->setErrorDetails($@);
  }

  return $status;
}

sub deleteMessage {
  my $self = shift;
  my $messageID = shift;

  my $status = new PlugNPay::Util::Status(1);
  eval {
    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('pnpmisc',
      q/DELETE FROM private_message
         WHERE message_id = ?/, [$messageID]);
  };

  if ($@) {
    $status->setFalse();
    $status->setError('Failed to delete message');
    $status->setErrorDetails($@);
  }

  return $status;
}

1;
