package PlugNPay::OnlineCheck;
use strict;
use PlugNPay::Token;
use PlugNPay::OnlineCheck::Encryption;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  return $self;
}

sub setName {
  my $self = shift;
  my $name = shift;
  # remove trailing whitespace
  $name =~ s/\s+$//;
  $self->{'name'} = $name;
}

sub getName {
  my $self = shift;
  return $self->{'name'};
}

sub isRoutingNumberABA {
  my $self = shift;
  return $self->{'routingNumberType'} eq 'aba';
}

sub setRoutingNumberIsABA {
  my $self = shift;
  $self->{'routingNumberType'} = 'aba';
}

sub setRoutingNumberIsInternational {
  my $self = shift;
  $self->{'routingNumberType'} = 'international';
}

sub setABARoutingNumber {
  my $self = shift;
  my $routingNumber = shift;
  $self->setRoutingNumber($routingNumber);
}

sub getABARoutingNumber {
  my $self = shift;
  return $self->getRoutingNumber();
}

sub setInternationalRoutingNumber {
  my $self = shift;
  my $routingNumber = shift;
  $self->setRoutingNumber($routingNumber);
}

sub getInternationalRoutingNumber {
  my $self = shift;
  return $self->getRoutingNumber();
}

sub setRoutingNumber {
  my $self = shift;
  my $routingNumber = shift;

  if ($routingNumber ne $self->{'routingNumber'}) {
    delete $self->{'paymentToken'};
  }

  if ($self->verifyABARoutingNumber($routingNumber)) {
    $self->setRoutingNumberIsABA();
  } else {
    $self->setRoutingNumberIsInternational();
  }

  $self->{'routingNumber'} = $routingNumber;
}

sub getRoutingNumber {
  my $self = shift;
  return $self->{'routingNumber'};
}

sub setAccountNumber {
  my $self = shift;
  my $accountNumber = shift;
  if ($accountNumber ne $self->{'accountNumber'}) {
    delete $self->{'paymentToken'};
    $self->{'accountNumber'} = $accountNumber;
  }
}

sub getAccountNumber {
  my $self = shift;
  return $self->{'accountNumber'};
}

sub getMaskedAccount {
  my $self = shift;
  my $number = $self->getAccountNumber();

  my $length = length $number;
  my $last  = ($length > 7 ? 4 : 2);
  my $maskLength = $length - $last + 1;
  my $mask  = '*';

  $mask = $mask x $maskLength;

  return $mask . substr($number, $maskLength);
}

sub getMaskedNumber {
  my $self = shift;
  my $first = shift;
  my $last = shift;
  my $mask = shift;
  my $maskLength = shift || 2;

  # set default mask if not supplied
  if (!defined $first) { $first = 4;   }
  if (!defined $last)  { $last  = 4;   }
  if (!defined $mask)  { $mask  = '*'; }

  # don't allow greater than first 6 last 4
  if ($first > 6) { $first = 6; }
  if ($last > 4)  { $last = 4; }

  my $number = $self->getABARoutingNumber() . $self->getAccountNumber();

  $mask = $mask x $maskLength;

  $number =~ s/^(\d{$first})\d+?(\d{$last})$/$1$mask$2/g;
  return $number;

}

sub setAccountType {
  my $self = shift;
  my $accountType = shift;
  if ($accountType =~ /^(checking|savings)$/) {
    $self->{'accountType'} = $accountType;
  }
}

sub getAccountType {
  my $self = shift;
  return $self->{'accountType'};
}

sub verifyABARoutingNumber {
  my $self = shift;
  my $number = shift; # optional argument

  if (!defined $number) {
    if (ref($self) eq 'PlugNPay::OnlineCheck') {
      $number = $self->getABARoutingNumber();
    } else {
      $number = $self;
    }
  }

  if ($number && length($number) == 9) {
    my @digits = split(//,"$number");
    my @validationSequence = (3,7,1);
    my $sum = 0;

    for (my $i = 0; $i < 9; $i++) {
      $sum += $digits[$i] * $validationSequence[$i % @validationSequence];
    }

    return (($sum % 10) == 0);
  }
  return 0;
}

sub getToken {
  my $self = shift;
  my $achNum = shift;
  if (!$achNum) {
    $achNum = $self->getRoutingNumber() . ' ' . $self->getAccountNumber();
  }

  my $requester = new PlugNPay::Token();
  my $token = $requester->getToken($achNum,'CREDENTIAL');

  return $token;
}

sub fromToken {
  my $self = shift;
  my $token = shift;
  my $redeem = uc shift;
  my $redeemer = new PlugNPay::Token();

  my $info = $redeemer->fromToken($token,$redeem);
  $info =~ s/\+/ /g; #Fix possible token server error
  my ($routing,$account) = split(' ',$info);
  
  if ($routing && $account) {
    $self->setAccountNumber($account);
    if ($self->verifyABARoutingNumber($routing)){
      $self->setABARoutingNumber($routing);
    } else {
      $self->setInternationalRoutingNumber($routing);
    }
  }

  return $info;
}

sub encryptAccountInfo {
  my $self = shift;
  return $self->encryptAccountInfoYearMonth();
}

sub getYearMonthEncryptedNumber {
  my $self = shift;

  my $encryptor = new PlugNPay::OnlineCheck::Encryption();

  my $acctInfo = '';

  $acctInfo = sprintf('%s %s', $self->{'routingNumber'}, $self->{'accountNumber'});

  my $encInfo = $encryptor->encrypt($acctInfo,'log');
  return $encInfo;
}

sub encryptAccountInfoYearMonth {
  my $self = shift;
  return $self->getYearMonthEncryptedNumber();
}

sub getPerpetualEncryptedNumber { # I wish perl had "Interfaces"
  my $self = shift;
  return $self->getPerpetualEncryptedAccountInfo();
}

sub getPerpetualEncryptedAccountInfo {
  my $self = shift;

  my $encryptor = new PlugNPay::OnlineCheck::Encryption();

  my $acctInfo = '';

  $acctInfo = sprintf('%s %s', $self->{'routingNumber'}, $self->{'accountNumber'});


  my $encInfo = $encryptor->encrypt($acctInfo);
  return $encInfo;
}

sub encryptAccountInfoPerpetual {
  my $self = shift;
  return $self->getPerpetualEncryptedAccountInfo();
}

# added for consistency with CreditCard
sub setNumberFromEncryptedNumber {
  my $self = shift;
  return $self->setAccountFromEncryptedNumber(@_);
}

sub setAccountFromEncryptedNumber {
  my $self = shift;
  my $encAcctInfo = shift;

  my $decryptor = new PlugNPay::OnlineCheck::Encryption();
  my $infoHash = $decryptor->decrypt($encAcctInfo);
  $self->setRoutingNumber($infoHash->{'routing'});
  $self->setAccountNumber($infoHash->{'account'});

  return $infoHash;
}

sub decryptAccountInfo {
  my $self = shift;
  return $self->setAccountFromEncryptedNumber(@_);
}



sub getSha1Hash {
  my $self = shift;
  my $achNumber = $self->getRoutingNumber() . ' ' . $self->getAccountNumber();

  my $sha1Token = "Sha1Token";
  my $sha = new SHA;
  $sha->reset;
  $sha->add($achNumber);
  $sha1Token = $sha->hexdigest();

  return $sha1Token;
}

sub getEncryptedInfo {
  my $self = shift;
  my $achNumber = $self->getRoutingNumber() . ' ' . $self->getAccountNumber();

  my ($enccardnumber, $encryptedDataLen) = &rsautils::rsa_encrypt_card($achNumber,"/home/p/pay1/pwfiles/keys/key");
  return { 'enccardnumber' => $enccardnumber, 'length' => $encryptedDataLen };
}

sub getEncHash {
  my $self = shift;
  my $achNumber = $self->getRoutingNumber() . ' ' . $self->getAccountNumber();

  my $encToken = "encToken";
  my $encCardInfo = $self->getEncryptedInfo();

  my $sha = new SHA;
  $sha->reset;
  $sha->add($encCardInfo->{'enccardnumber'});
  $encToken = $sha->hexdigest();

  return $encToken;
}

sub getCardHashHash {
  my $self = shift;

  my %cardHashHash = ();
  $cardHashHash{'sha1Hash'} = $self->getSha1Hash();
  $cardHashHash{'encShaHash'} = $self->getEncHash();
  $cardHashHash{'token'} = $self->getToken();

  return %cardHashHash;
}

sub getCardHashArray {
  my $self = shift;

  my @cardHashArray = ();
  if ($self->getSha1Hash() ne "") {
    push (@cardHashArray , $self->getSha1Hash());
  }
  if ($self->getEncHash() ne "") {
    push (@cardHashArray , $self->getEncHash());
  }
  if ($self->getToken ne "") {
    push (@cardHashArray , $self->getToken());
  }

  return @cardHashArray;
}

sub getCardHash {
  ## Return Preferred Method
  my $self = shift;
  #return $self->getSha1Hash();
  return $self->getEncHash();
  #return $self->getToken();
}

sub compareHash {
  my $self = shift;
  my $chkHashNumber = shift;
  my @cardArray = $self->getCardHashArray();
  my $match = 0;

  foreach my $var (@cardArray) {
    if ($var eq $chkHashNumber) {
      $match++;
      last;
    }
  }
  return $match;
}

sub getVehicleType {
  return 'ach';
}


1;
