package PlugNPay::CreditCard::Encryption;

# eventually rsautils methods should be put in here instead.
use rsautils;
use PlugNPay::Token;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  return $self;
}

sub encrypt {
  my $self = shift;
  my $cardNumber = shift;
  my $perpetual = shift;
  my $keyPath = shift || '/home/p/pay1/pwfiles/keys/key';

  $cardNumber =~ s/[^\d]//g;

  my $encryptedCardNumber;
  if (defined $perpetual && ($perpetual eq 'tok' || $perpetual eq 'token')) {
    $encryptedCardNumber = $self->getTokenFromCardNumber($cardNumber);
  } elsif ($perpetual) {
    ($encryptedCardNumber) = &rsautils::rsa_encrypt_card($cardNumber,$keyPath);
  } else {
    ($encryptedCardNumber) = &rsautils::rsa_encrypt_card($cardNumber,$keyPath,'log');
  }

  return $encryptedCardNumber;
}

sub decrypt {
  my $self = shift;
  my $encryptedCardNumber = shift;
  my $keyPath = shift || '/home/p/pay1/pwfiles/keys/key';
  my $cardNumber;

  if ($encryptedCardNumber =~ /^token /) {
    my @token = split(' ',$encryptedCardNumber);
    $cardNumber = $self->getCardFromToken($token[1]);
  } else {
    $cardNumber = rsautils::rsa_decrypt_file($encryptedCardNumber,undef,undef,$keyPath);
  }

  return $cardNumber;
}

sub getTokenFromCardNumber {
  my $self = shift; 
  my $card = shift;
 
  my $tokenObject = new PlugNPay::Token();

  return 'token ' . $tokenObject->getToken($card);
}

sub getCardFromToken {
  my $self = shift;
  my $encrypted = shift;
  my $processingMethod = shift || 'PROCESSING';

  my $tokenObject = new PlugNPay::Token();

  return $tokenObject->fromToken($encrypted,$processingMethod);
}

sub encryptMagstripe {
  my $self = shift;
  my $magstripe = shift;
  my $perpetual = shift;
  my $keyPath = shift || '/home/p/pay1/pwfiles/keys/key';

  my $encryptedMagstripe;
  ($encryptedMagstripe) = &rsautils::rsa_encrypt_card($magstripe,$keyPath,'msg');

  return $encryptedMagstripe;
}

sub decryptMagstripe {
  my $self = shift;
  my $encryptedMagstripe = shift;

  return $self->decrypt($encryptedMagstripe);
}

1;
