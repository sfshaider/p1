package PlugNPay::PayScreens::Cookie;
  
use strict;
use CGI;
use JSON::XS;
use PlugNPay::Util::Encryption::AES;
use PlugNPay::AWS::ParameterStore;
use PlugNPay::Util::Temp;

our $encryptionKey;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  return $self;
}

sub createEncryptedCookie {
  my $self = shift;
  my $data = shift;

  my $query = new CGI();
  my $name = $data->{'name'} || '';
  my $value = $data->{'value'} || '';
  my $host = $data->{'host'} || '';

  if ($name ne '' && $value ne '') {
    # JSON encode, encrypt, convert to hex
    $value = (ref($data) eq 'HASH') ? encode_json($value) : '';
    $value = $self->encrypt($value);
    $value = unpack('H*',$value);

    my $cookie = $query->cookie( -name=> $name,
                                 -value=> $value,
                                 -expires=> '+1h',
                                 -path=> '/',
                                 -secure=> 1,
                                 -host=> $host);

    return $cookie;
  }
}

sub getDecryptedCookie {
  my $self = shift;
  my $cookie = shift;

  # Convert to binary, decrypt, decode JSON
  $cookie = pack('H*',$cookie);
  $cookie = $self->decrypt($cookie);
  $cookie = eval {decode_json($cookie)};

  return $cookie;
}

sub getEncryptionKey {
  my $self = shift;

  if (!$encryptionKey) {
    $encryptionKey = PlugNPay::AWS::ParameterStore::getParameter('/PAYSCREENS/COOKIE/KEY',1);
  }

  return $encryptionKey;
}

sub encrypt {
  my $self = shift;
  my $data = shift;

  my $key = $self->getEncryptionKey();
  my $aes = new PlugNPay::Util::Encryption::AES();
  my ($encryptedData,$iv) = eval {$aes->encrypt($data,$key)};

  return $encryptedData;
}

sub decrypt {
  my $self = shift;
  my $data = shift;

  my $key = $self->getEncryptionKey();
  my $aes = new PlugNPay::Util::Encryption::AES();
  my $decryptedData = eval {$aes->decrypt($data,$key)};

  return $decryptedData;
}

sub validateCookie {
  my $self = shift;
  my $cookieData = shift;
  my $minTimeAllowed = 10;
  my $errorMessage = '';

  my $cookie = $cookieData->{'cookie'};
  my $decryptedCookie = $cookieData->{'decryptedCookie'};
  my $cookieIP = $cookieData->{'cookieIP'};
  my $remoteIP = $cookieData->{'remoteIP'};
  my $cookieTime = $cookieData->{'cookieTime'};
  my $validationTime = $cookieData->{'validationTime'};
  my $oneTimeUseId = $cookieData->{'oneTimeUseId'};

  if ($cookie eq '') {
    $errorMessage = 'missing cookie';
  } elsif ($decryptedCookie eq '') {
    $errorMessage = 'failed to decrypt cookie';
  } elsif ($cookieIP ne $remoteIP) {
    $errorMessage = 'IP does not match remote IP';
  } elsif ($cookieTime eq '') {
    $errorMessage = 'missing timestamp in cookie';
  } elsif (($validationTime - $cookieTime) < $minTimeAllowed) {
    $errorMessage = 'did not reach required minimum time';
  } elsif (!$self->fetchOneTimeUseId($oneTimeUseId)) {
    $errorMessage = 'one-time-use id invalid';
  }

  return $errorMessage;
}

sub getOneTimeUseIdPrefix {
  my $self = shift;
  return 'payscreens/security/';
}

sub getOneTimeUseContext {
  my $self = shift;
  return 'payscreenscookie';
}

sub storeOneTimeUseId {
  my $self = shift;
  my $id = shift;

  my $temp = new PlugNPay::Util::Temp();
  my $key = $self->getOneTimeUseIdPrefix() . $id;
  $temp->setKey($key);
  $temp->setValue({'isValid' => 'true'});
  $temp->setPassword($self->getOneTimeUseContext());
  $temp->setExpirationTime(1); # 1 hour
  my $status = $temp->store();

  return $status;
}

sub fetchOneTimeUseId {
  my $self = shift;
  my $id = shift;

  my $temp = new PlugNPay::Util::Temp();
  my $key = $self->getOneTimeUseIdPrefix() . $id;
  $temp->setKey($key);
  $temp->setPassword($self->getOneTimeUseContext());
  my $status = $temp->fetch();

  return $status;
}


1;
