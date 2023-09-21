package PlugNPay::Reseller::Payout::History;

use PlugNPay::DBConnection;
use PlugNPay::Sys::Time;
use PlugNPay::Email;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  return $self;
}

sub setTransTime {
  my $self = shift;
  $self->_setAccountData('trans_time',shift);
}

sub getTransTime {
  my $self = shift;
  return $self->_getAccountData('trans_time');
}

sub setGatewayAccount {
  my $self = shift;
  $self->_setAccountData('username',shift);
}

sub getGatewayAccount {
  my $self = shift;
  return $self->_getAccountData('username');
}

sub setAction {
  my $self = shift;
  $self->_setAccountData('action', shift);
}

sub getAction {
  my $self = shift;
  return $self->_getAccountData('action');
}

sub setDescription {
  my $self = shift;
  $self->_setAccountData('descr',shift);
}  

sub getDescription {
  my $self = shift;
  return $self->_getAccountData('descr');
}

sub load {
  my $self = shift;
  my $dbconn = new PlugNPay::DBConnection()->getHandleFor('pnppaydata');
  my $sth = $dbconn->prepare(q/
                             SELECT trans_time,username,action,descr
                             FROM history
                             WHERE username=?
                             /) or die $DBI::errstr;
  $sth->execute($self->{'username'});
  my $row = $sth->ferchrow_hashref;
  $self->{'rawAccountData'} = $row;

}

sub save {
  my $self = shift;
  $self->_saveHistory();
}

sub _saveHistory {
  my $self = shift;
  my $dbh = new PlugNPay::DBConnection()->getHandleFor('pnppaydata');
  my $sth = $dbh->prepare(q/
                          INSERT INTO history
                          (trans_time,username,action,descr)
                          VALUES (?,?,?,?)
                          /) or die $DBI::errstr;
  $sth->execute($self->getTransTime(),$self->getGatewayAccount(),$self->getAction(),$self->getDescription());

}

sub _setAccountData {
  my $self = shift;

  return if (ref($self) ne caller());

  my $key = shift;
  my $value = shift;
  $self->{'rawAccountData'}{$key} = $value;
}

sub _getAccountData {
  my $self = shift;
  return if (ref($self) ne caller());
  my $key = shift;
  return $self->{'rawAccountData'}{$key};
}

# Email Notification #
sub _notify {
  my $self = shift;
  my $extraMessage = shift;
  my $email = new PlugNPay::Email();
  $email->setVersion('legacy');
  $email->setGatewayAccount($self->getGatewayAccount());
  $email->setTo('accounting@plugnpay.com');
  $email->setFrom('trash@plugnpay.com');
  $email->setSubject('pnppaydata - Commission Payout Info Update Confirmation');
  
  my $emailMessage .= "The following account has successfully updated their commission payout info online.\n\n";
  $emailMessage .= "Username: " . $self->getGatewayAccount() . "\n\n";
  if ($extraMessage) {
    $emailMessage .= $extraMessage;
  }
  $emailMessage .= "\n";
  
  $email->setContent($emailMessage);
  $email->setFormat('text');
  $email->send();
}

1;
