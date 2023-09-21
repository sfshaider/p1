package PlugNPay::Email;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Sys::Time;
use PlugNPay::Email::Domain;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::Status;

# NOTE: To prevent circular dependencies, note the "require" lines in sub new
#
# TODO: This module is doing too much.  It can be split into two, one to do the sending
#   and one to do the creation

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  # these must be requires to prevent circular dependency errors
  require PlugNPay::GatewayAccount;
  require PlugNPay::Reseller;
  require PlugNPay::UI::Template;

  my $version = shift;
  $self->setVersion($version);

  return $self;
}

sub setVersion {
  my $self = shift;
  my $version = shift;
  if ($version !~ /^(legacy|edge)$/) {
    $version = 'edge';
  }
  $self->{'version'} = $version;
}

sub getVersion {
  my $self = shift;
  return $self->{'version'};
}

sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;
  $gatewayAccount = PlugNPay::GatewayAccount::filterGatewayAccountName($gatewayAccount);
  $self->{'account'} = $gatewayAccount;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'account'};
}

sub setContent {
  my $self = shift;
  my $email = shift;

  if ($self->getVersion() ne 'legacy') {
    return undef;
  }

  $self->_setLegacyContent($email);

  return 1;
}

sub _setLegacyContent {
  my $self = shift;
  my $email = shift;
  $self->{'legacy'}{'content'} = $email;
}

sub getContent{
  my $self = shift;
  my $email = shift;

  if ($self->getVersion() ne 'legacy') {
    return undef;
  }

  return $self->_getLegacyContent();
}

sub _getLegacyContent {
  my $self = shift;
  return $self->{'legacy'}{'content'};
}

sub clearContent {
  my $self = shift;

  $self->_clearLegacyContent();
}

sub _clearLegacyContent {
  my $self = shift;
  delete $self->{'legacy'}{'content'};
}


sub setUseQueue {
  my $self = shift;
  my $boolean = shift;
  $self->{'useQueue'} = ($boolean ? 1 : 0);
}

sub getUseQueue {
  my $self = shift;
  return $self->{'useQueue'};
}

# Email format is only for the legacy queue
sub setFormat {
  my $self = shift;
  my $format = shift;

  if ($format !~ /^(text|html)$/) {
    $format = 'html';
  }

  $self->{'legacy'}{'format'} = $format;
}

# Email format is only for the legacy queue
sub getFormat {
  my $self = shift;
  return $self->{'legacy'}{'format'};
}

sub _addEmailAddress {
  my $self = shift;
  my $type = shift;
  my $address = shift;

  if (!defined $self->{$type}) {
    $self->_clearEmailAddresses($type);
  }

  push @{$self->{$type}},split(',',$address);
}

sub _clearEmailAddresses {
  my $self = shift;
  my $type = shift;
  my @array;
  $self->{$type} = \@array;
}


sub setTo {
  my $self = shift;
  my $to = shift;
  $self->clearTo();
  $self->addTo($to);
}

sub addTo {
  my $self = shift;
  my $to = shift;
  $to =~ s/\n//g;
  $self->_addEmailAddress('to',$to);
}

sub getTo {
  my $self = shift;
  my $to;
  if (defined $self->{'to'}) {
    $to = join(',',@{$self->{'to'}});
  }
  return $to;
}

sub clearTo {
  my $self = shift;
  $self->_clearEmailAddresses('to');
}

sub setCC {
  my $self = shift;
  my $cc = shift;
  $self->clearCC();
  $self->addCC($cc);
}

sub addCC {
  my $self = shift;
  my $cc = shift;
  $cc =~ s/\n//g;
  $self->_addEmailAddress('cc',$cc);
}

sub getCC {
  my $self = shift;
  my $cc;
  if (defined $self->{'cc'}) {
    $cc = join(',',@{$self->{'cc'}});
  }
  return $cc;
}

sub clearCC {
  my $self = shift;
  $self->_clearEmailAddresses('cc');
}

sub setBCC {
  my $self = shift;
  my $bcc = shift;
  $self->clearBCC();
  $self->addBCC($bcc);
}

sub addBCC {
  my $self = shift;
  my $bcc = shift;
  $bcc =~ s/\n//g;
  $self->_addEmailAddress('bcc',$bcc);
}

sub getBCC {
  my $self = shift;
  my $bcc;
  if (defined $self->{'bcc'}) {
    $bcc = join(',',@{$self->{'bcc'}});
  }
  return $bcc;
}

sub clearBCC {
  my $self = shift;
  $self->_clearEmailAddresses('bcc');
}

sub setFrom {
  my $self = shift;
  my $from = shift;
  $from =~ s/\n//g;
  $from =~ s/,.*$//;
  $self->{'from'} = $from;
}

sub getFrom {
  my $self = shift;
  my $from = $self->{'from'};
  return $from;
}

sub clearFrom {
  my $self = shift;
  delete $self->{'from'};
}

sub setSubject {
  my $self = shift;
  my $subject = shift;
  $subject =~ s/\n//g;
  $self->{'subject'} = $subject;
}

sub getSubject {
  my $self = shift;
  return $self->{'subject'};
}

sub _loadTemplate {
  my $self = shift;
  my $name = shift;
  my $gatewayAccount = shift;

  my $dbh = PlugNPay::DBConnection::database('pnpmisc');
  my $sth = $dbh->prepare(q/
    SELECT username,name,subject,content
    FROM email_templates
    WHERE name = ? AND username = ?
  /);

  $sth->execute($name,$gatewayAccount) or die $DBI::errstr;
  my $results = $sth->fetchall_arrayref({});

  if ($results) {
    return $results->[0];
  }
}

sub loadTemplate {
  my $self = shift;
  my $name = shift;

  my $result = $self->_loadTemplate($name,$self->getGatewayAccount());
  if (!$result) {
   $result = $self->_loadTemplate($name,'default_temp');
  }


  return $result;
}

sub getPreformatted {
  my $self = shift;
  my $name = shift;
  my $substitutions = shift;
  my $loadedTemplate = $self->loadTemplate($name);

  my $template = new PlugNPay::UI::Template();

  foreach my $key (keys %{$substitutions}) {
    $template->setVariable($key,$substitutions->{$key});
  }

  my $parsedSubject = $template->parseTemplate($loadedTemplate->{'subject'});
  my $parsedContent = $template->parseTemplate($loadedTemplate->{'content'});

  return {subject => $parsedSubject, content => $parsedContent};
}

sub sendPreFormatted {
  my $self = shift;
  my $version = shift;
  my $name = shift;
  my $substitutions = shift;
  my $to = shift;
  my $cc = shift;
  my $bcc = shift;
  my $from = shift;
  my $username = shift;
  my $format = shift;

  my $template = $self->getPreformatted($name,$substitutions);

  $self->setVersion($version);
  $self->setSubject($template->{'subject'});
  $self->setContent($template->{'content'});
  $self->setTo($to);
  $self->setCC($cc);
  $self->setBCC($bcc);
  $self->setFrom($from);
  $self->setGatewayAccount($username);
  $self->setFormat($format);

  $self->send();
}


sub clearSubject {
  my $self = shift;
  delete $self->{'subject'};
}

sub setError {
  my $self = shift;
  my $error = shift;
  $self->{'error'} = $error;
}

sub getError {
  my $self = shift;
  return $self->{'error'};
}

sub clearError {
  my $self = shift;
  delete $self->{'error'};
}

sub clear {
  my $self = shift;
  $self->clearTo();
  $self->clearCC();
  $self->clearBCC();
  $self->clearFrom();
  $self->clearSubject();
  $self->clearContent();
  $self->clearError();
}

sub send {
  my $self = shift;
  my $logger = new PlugNPay::Logging::DataLog({'collection' => 'email_send'});
  my $emailLog = {};
  my $status = new PlugNPay::Util::Status(1);

  $emailLog->{'postSend'}{'status'} = 'sent';

  $self->clearError();
  my $error;

  $emailLog->{'preSend'}{'to'} = $self->getTo();
  $emailLog->{'preSend'}{'from'} = $self->getFrom();
  $emailLog->{'preSend'}{'cc'} = $self->getCC();
  $emailLog->{'preSend'}{'bcc'} = $self->getBCC();
  $emailLog->{'preSend'}{'subject'} = $self->getSubject();
  $emailLog->{'preSend'}{'content'} = $self->getContent();

  if ($self->getVersion() eq 'legacy') {
    my $ref = $self->_insertLegacy();
    $error = $ref->{'error'};
  }

  $emailLog->{'postSend'}{'to'} = $self->getTo();
  $emailLog->{'postSend'}{'from'} = $self->getFrom();
  $emailLog->{'postSend'}{'cc'} = $self->getCC();
  $emailLog->{'postSend'}{'bcc'} = $self->getBCC();
  $emailLog->{'postSend'}{'subject'} = $self->getSubject();
  $emailLog->{'postSend'}{'content'} = $self->getContent();

  if ($error) {
    $self->setError($error);
    $status->setFalse();
    $status->setError($error);
    $emailLog->{'postSend'}{'status'} = 'failed to send';
  }

  $logger->log($emailLog);
  return $status;
}


sub _insertLegacy {
  my $self = shift;

  my $to = $self->getTo();
  my $cc = $self->getCC();
  my $bcc = $self->getBCC();
  my $from = $self->getFrom();
  my $subject = $self->getSubject();
  my $content = $self->getContent();
  my $format = $self->getFormat();
  my $replyTo;

  my $ref;
  if ($to eq '') {
    $ref = {
      mode => 'legacy',
      error => "Missing data: To"
    };
  } elsif ($from eq '') {
    $ref = {
      mode => 'legacy',
      error => "Missing data: From"
    };
  } elsif ($subject eq '') {
    $ref = {
      mode => 'legacy',
      error => "Missing data: Subject"
    };
  } elsif ($content eq '') {
    $ref = {
      mode => 'legacy',
      error => "Missing data: Content"
    };
  }

  # check if there's a ref to return yet
  if ($ref) {
    return $ref;
  }

  # Change FROM address based on SPF settings;
  my $emd = new PlugNPay::Email::Domain();
  my $spfConfigured = $emd->validate($from);

  # change from address if SPF for from address domain is not configured to include PNP servers
  if (!$spfConfigured) {
    my $gatewayAccount = $self->getGatewayAccount();

    if (PlugNPay::GatewayAccount::exists($gatewayAccount)) {
      my $ga = new PlugNPay::GatewayAccount($gatewayAccount);
      my $ra = new PlugNPay::Reseller($ga->getReseller());
      $from = $ra->getNoReplyEmail();
    }

    $replyTo ||= $self->getFrom();
  }

  # create headers;
  # Adding HTML headers here because the email queue process script doesn't do it...ugh.
  my $headers = '';
  if ($format eq 'html') {
    $headers .= 'Content-Type: text/html; name="mail.htm"' . "\n";
    $headers .= 'Content-Disposition: inline; filename="mail.htm"' . "\n";
    $headers .= 'Content-Transfer-Encoding: 8bit' . "\n";
    $headers .= 'Mime-Version: 1.0' . "\n";
  }
  $headers .= 'X-Mailer: PlugNPay Message Queue (Legacy)' . "\n";
  $headers .= 'To: ' . $to . "\n";
  if ($cc ne '') { $headers .= 'CC: ' . $cc . "\n"; }
  if ($bcc ne '') { $headers .= 'BCC: ' . $bcc . "\n"; }
  $headers .= 'From: ' . $from . "\n";
  $headers .= 'Reply-To: ' . $replyTo . "\n";
  $headers .= 'Subject: ' . $subject . "\n";

  # create the WHOLE EMAIL!
  my $theWholeEmail = $headers . "\n" . $content;

  eval {
    my $time = new PlugNPay::Sys::Time()->inFormat('gendatetime');

    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('emailconf',q/
      INSERT INTO message_que2 (message_time,username,status,format,body)
      VALUES (?,?,?,?,?)
    /,[$time,$self->getGatewayAccount(),'pending',$format,$theWholeEmail]);

    my $res = $dbs->fetchallOrDie('pnpmisc',q/
      SELECT LAST_INSERT_ID() as messageId
    /,[],{});

    my $id = $res->{'result'}[0]{'messageId'};
    if (defined $id) {
      $ref = {
        mode => 'legacy',
        id => $id
      };
    }
  };

  if ($@) {
    $ref = {
      mode => 'legacy',
      error => $@
    };
  }

  return $ref;
}

1;
