package PlugNPay::Private::MessageBoard;

use strict;
use PlugNPay::Sys::Time;
use PlugNPay::UI::Template;
use PlugNPay::Util::UniqueID;
use PlugNPay::Logging::DataLog;
use PlugNPay::Private::MessageBoard::Message;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

##########################################
# Subroutines to serve message board html
##########################################

sub viewMessage {
  my $self = shift;
  my $messageData = shift || {};

  my $refreshMinutes = 10;
  my $refreshRate = $refreshMinutes * 60;

  my $template = new PlugNPay::UI::Template('/private/messageBoard', 'index');

  my $head = new PlugNPay::UI::Template('/private/messageBoard', 'index.head');
  $head->setVariable('auto_refresh', '<meta http-equiv="Refresh" content="' . $refreshRate . '">');

  my $tail = new PlugNPay::UI::Template('/private/messageBoard', 'index.tail');

  my $content = new PlugNPay::UI::Template('/private/messageBoard', 'view');
  $content->setVariable('refresh_minutes', $refreshMinutes);
  
  if ($messageData->{'show_archive'} eq 'yes') {
    $content->setVariable('message_status', 'no');
    $content->setVariable('message_status_action', 'Current');
  } else {
    $content->setVariable('message_status', 'yes');
    $content->setVariable('message_status_action', 'Archive');
  }

  my $activeMessages = 0;
  my $messageContent = '';
  my $messages = $self->viewMessageBoard();
  if (@{$messages} > 0) {
    foreach my $message (@{$messages}) {
      my $messageDate = new PlugNPay::Sys::Time('iso', $message->getMessageDate())->inFormat('yyyymmdd');
      my $now = new PlugNPay::Sys::Time()->nowInFormat('yyyymmdd');
      my $cutoffYear = substr($now, 0, 4);
      my $cutoffMonth = substr($now, 4, 2) - 1;
      my $cutoffDay = substr($now, 6, 2);

      if ($cutoffMonth == 0) {
        $cutoffMonth = 12;
        $cutoffYear = $cutoffYear - 1;
      }
      
      # if date is older than a month, it is archived
      my $cutoffDate = sprintf("%04d%02d%02d", $cutoffYear, $cutoffMonth, $cutoffDay);
      if ( ($messageDate < $cutoffDate) && ($messageData->{'show_archive'} ne 'yes' ) ) {
        next;
      }

      $activeMessages++;

      my $messageTemplate = new PlugNPay::UI::Template('/private/messageBoard', 'message');
      if ($message->getOutage()) {
        $messageTemplate->setVariable('table_color', '#C4C4ED');
      } else {
        $messageTemplate->setVariable('table_color', '#f4f4f4');
      }

      $messageTemplate->setVariable('message_id',      $message->getMessageID());
      $messageTemplate->setVariable('message_date',    new PlugNPay::Sys::Time('iso', $message->getMessageDate())->inFormat('db_gm') . ' UTC');
      $messageTemplate->setVariable('message_subject', $message->getMessageSubject());
      $messageTemplate->setVariable('message_content', $message->getMessage());
      $messageContent .= $messageTemplate->render();
    }
  } 
  
  if ($activeMessages == 0) {
    my $noMessageTemplate = new PlugNPay::UI::Template('/private/messageBoard', 'no_messages');
    $noMessageTemplate->setVariable('script_name', $ENV{'SCRIPT_NAME'});
    $noMessageTemplate->setVariable('message_date', new PlugNPay::Sys::Time()->nowInFormat('db_gm') . ' UTC');
    $messageContent = $noMessageTemplate->render();
  }

  $content->setVariable('messageboard', $messageContent);

  $template->setVariable('head',    $head->render());
  $template->setVariable('content', $content->render());
  $template->setVariable('tail',    $tail->render());

  return $template->render();
}

sub createMessage {
  my $self = shift;

  my $uniqueID = new PlugNPay::Util::UniqueID()->inHex();

  my $template = new PlugNPay::UI::Template('/private/messageBoard', 'index');

  my $head = new PlugNPay::UI::Template('/private/messageBoard', 'index.head');
  my $tail = new PlugNPay::UI::Template('/private/messageBoard', 'index.tail');

  my $content = new PlugNPay::UI::Template('/private/messageBoard', 'add');
  $content->setVariable('script_name', $ENV{'SCRIPT_NAME'});
  $content->setVariable('message_id', $uniqueID);

  $template->setVariable('head',    $head->render());
  $template->setVariable('content', $content->render());
  $template->setVariable('tail',    $tail->render());

  return $template->render();
}

sub editMessage {
  my $self = shift;
  my $messageData = shift;

  my $message = new PlugNPay::Private::MessageBoard::Message();

  my $content = '';
  if ($message->messageExists($messageData->{'message_id'})) {
    $message->loadMessage($messageData->{'message_id'});

    my $template = new PlugNPay::UI::Template('/private/messageBoard', 'index');

    my $head = new PlugNPay::UI::Template('/private/messageBoard', 'index.head');
    my $tail = new PlugNPay::UI::Template('/private/messageBoard', 'index.tail');

    my $editTemplate = new PlugNPay::UI::Template('/private/messageBoard', 'edit');
    $editTemplate->setVariable('script_name', $ENV{'SCRIPT_NAME'});
    $editTemplate->setVariable('message_id',   $message->getMessageID());
    $editTemplate->setVariable('outage_check', ($message->getOutage() ? 'checked' : ''));
    $editTemplate->setVariable('subject',      $message->getMessageSubject());

    my $messageContent = $message->getMessage();
    $messageContent =~ s/<br>/\r\n/g;
    $editTemplate->setVariable('message_content', $messageContent);

    $template->setVariable('head',    $head->render());
    $template->setVariable('content', $editTemplate->render());
    $template->setVariable('tail',    $tail->render());
    $content = $template->render();
  } else {
    $content = $self->viewMessage();
  }

  return $content;
}

##############################################
# Subroutines for modifying the message board
##############################################

sub viewMessageBoard {
  my $self = shift;
  my $message = new PlugNPay::Private::MessageBoard::Message();
  return $message->loadMessages();
}

sub viewMessageOnMessageBoard {
  my $self = shift;
  my $messageData = shift;

  my $message = new PlugNPay::Private::MessageBoard::Message();
  $message->loadMessage($messageData->{'message_id'});
  return $message;
}

sub addMessageToMessageBoard {
  my $self = shift;
  my $messageData = shift;

  my $message = new PlugNPay::Private::MessageBoard::Message();
  $message->setMessageID($messageData->{'message_id'});
  $message->setMessageSubject($messageData->{'subject'});
  $message->setMessage($messageData->{'message'});
  $message->setOutage(($messageData->{'outage'} eq 'yes' ? 1 : 0));

  my $status = $message->saveMessage();
  if (!$status) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'private_message_board' });
    $logger->log({
      'error'       => $status->getErrorDetails(),
      'message'     => $status->getError(),
      'method'      => 'addToMessageBoard',
      'messageData' => $messageData
    });
  }
}

sub removeMessageFromMessageBoard {
  my $self = shift;
  my $messageData = shift;

  my $message = new PlugNPay::Private::MessageBoard::Message();

  if ($message->messageExists($messageData->{'message_id'})) {
    my $status = $message->deleteMessage($messageData->{'message_id'});
    if (!$status) {
      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'private_message_board' });
      $logger->log({
        'error'       => $status->getErrorDetails(),
        'message'     => $status->getError(),
        'method'      => 'removeFromMessageBoard',
        'messageData' => $messageData
      });
    }
  }
}

sub updateMessageOnMessageBoard {
  my $self = shift;
  my $messageData = shift;

  my $message = new PlugNPay::Private::MessageBoard::Message();

  if ($message->messageExists($messageData->{'message_id'})) {
    $message->loadMessage($messageData->{'message_id'});

    $message->setMessageSubject($messageData->{'subject'});
    $message->setMessage($messageData->{'message'});
    $message->setOutage(($messageData->{'outage'} eq 'yes' ? 1 : 0));

    my $status = $message->updateMessage();
    if (!$status) {
      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'private_message_board' });
      $logger->log({
        'error'       => $status->getErrorDetails(),
        'message'     => $status->getError(),
        'method'      => 'updateMessageOnMessageBoard',
        'messageData' => $messageData
      });
    }
  }
}

1;
