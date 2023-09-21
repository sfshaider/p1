package rsautils;

use strict;
use miscutils;
use PlugNPay::Util::Encryption::AES;
use PlugNPay::Util::Encryption::Random;
use PlugNPay::Token;
use PlugNPay::Email;
use PlugNPay::Util::Encryption::LegacyKey;
use PlugNPay::Logging::DataLog;

our %cryptokeys;
our %vectors;
our $random;

if (!defined $random) {
  $random = PlugNPay::Util::Encryption::Random::random(32);
}

sub new {
  my $type = shift;
  my %query = @_;

  return [], $type;
}


    # At this point the decrypted key is a hex string representation of 256 bits...which is 64 bytes.
    # The original decryption method in rsautils used this hex string directly (64 bytes) instead of
    # packing it into the bytes it represents, so the decrypted key was actually used as if it were
    # a 512 bit key and got truncated to 256 bits.  So for clarity, we are truncating the decrypted
    # key to 32 # bytes (characters) because the last 32 bytes are just garbage.
    # Unfortunately this results in a weaker key.
    #
    # The fix is to actually pack the bytes before writing them to the file in the future, and this
    # will turn a 32 byte string into a 32 byte string. (i.e. no change required here for that)
    # - cbi 4/17/2014

sub getYearMonth {
  my $dataType = shift;

  my $yearmonth = '';

  if ($dataType eq 'log') {
    my @time = gmtime(time());
    # month = 4, year = 5
    $yearmonth = sprintf('%04d%02d',$time[5]+1900,$time[4]+1);
  } elsif ($dataType =~ /\d{6}/) {
    $yearmonth = $dataType;
  }

  return $yearmonth;
}

sub rsa_encrypt_card {
  my $cardNumber = shift;
  my $keyPath = shift;
  my $dataType = shift;

  if ($dataType eq 'tok' || $dataType eq 'token') {
    my $tokenObj = new PlugNPay::Token();
    my $token = 'token ' . $tokenObj->getToken($cardNumber);
    return ($token,length($token));
  }

  # get yearmonth
  my $yearMonth = &rsautils::getYearMonth($dataType);

  my $ciphertext = &rsautils::aes_encrypt($cardNumber,$keyPath,$dataType,$yearMonth);

  $ciphertext = unpack('H*',$ciphertext);


  $ciphertext = (($dataType eq 'log' || $dataType =~ /\d{6}/) ? substr($yearMonth,0,6) . ' ' : '') . 'aes256 ' . $ciphertext;

  if (wantarray()) {
    # why is the length returned?
    return ($ciphertext,length($ciphertext));
  }
  return $ciphertext;
}

sub rsa_encrypt_file {
  my $username = shift;  # not used but remains for compatibility
  my $plaintext = shift;
  my $keyPath = shift;
  my $dataType = shift;

  if ($dataType eq 'tok' || $dataType eq 'token') {
    my $tokenObj = new PlugNPay::Token();
    my $token = 'token ' . $tokenObj->getToken($plaintext);
    return ($token,length($token));
  }

  # get yearmonth
  my $yearMonth = &rsautils::getYearMonth($dataType);

  my $ciphertext = &rsautils::aes_encrypt($plaintext,$keyPath,$dataType,$yearMonth);

  $ciphertext = unpack('H*',$ciphertext);

  $ciphertext = (($dataType eq 'log' || $dataType =~ /\d{6}/) ? $yearMonth . ' ' : '') . 'aes256 ' . $ciphertext;

  if (wantarray()) {
    # why is the length returned?
    return ($ciphertext,length($ciphertext));
  }
  return $ciphertext;
}

sub aes_encrypt {
  my $plaintext = shift;
  my $keyPath = shift;
  my $dataType = shift;
  my $yearMonth = shift;

  if ($dataType eq 'tok' || $dataType eq 'token') {
    my $tokenObj = new PlugNPay::Token();
    my $token = 'token ' . $tokenObj->getToken($plaintext);
    return ($token,length($token));
  }

  my ($key,$iv);

  # create an aes object
  my $aes = new PlugNPay::Util::Encryption::AES();

  # encrypt the plaintext
  my $ciphertext;
  eval {
    my $keyManager = new PlugNPay::Util::Encryption::LegacyKey();
    if ($yearMonth ne '') {
      $keyManager->loadMonthlyKey($yearMonth);
    } else {
      $keyManager->loadRecurringKey();
    }
    $key = $keyManager->getActiveKey();
    $iv = $keyManager->getInitializationVector();

    $ciphertext = $aes->encryptWithIV($key,$iv,$plaintext);
  };

  if ($@) {
    new PlugNPay::Logging::DataLog({ collection => 'rsautils' })->log({'error' => $@, 'identifier' => $yearMonth});
    die('Encryption failed for key: "' . $yearMonth . '""');
  }

  return $ciphertext;
}

sub rsa_decrypt_file {
  my $enccardnumber = shift;
  my $length = shift;        # not used but here for compatibility
  my $passphrase = shift;    # not used but here for compatibility
  my $keyPath = shift;

  # $enccardnumber format:
  #
  #   "$yearMonth aes256 $ciphertext"
  #                 or
  #        "aes256 $ciphertext"
  #
  my @data = split(/ /,$enccardnumber);
  my $ciphertext = $data[2] || $data[1];
  $ciphertext = pack('H*',$ciphertext);

  if ($data[0] eq 'token') {
    my $tokenObj = new PlugNPay::Token();
    my $decrypted = $tokenObj->fromToken($data[1],'PROCESSING');
    $decrypted =~ s/\+/ /g;

    return $decrypted;
  }

  # $yearMonth should be blank if $data[2] is not defined
  my $yearMonth = ($data[2] ? $data[0] : '');

  my $dataType = ($yearMonth ? 'log' : '');

  my $plaintext = &rsautils::aes_decrypt($ciphertext,$keyPath,$dataType,$yearMonth);

  return $plaintext;
}


sub aes_decrypt {
  my $ciphertext = shift;
  my $keyPath = shift;
  my $dataType = shift;
  my $yearMonth = shift;

  if ($dataType eq 'tok' || $dataType eq 'token') {
    my $tokenObj = new PlugNPay::Token();
    my $decrypted = $tokenObj->fromToken($ciphertext,'PROCESSING');
    $decrypted =~ s/\+/ /g;

    return $decrypted;
  }

  my ($key,$iv);

  # create an aes object
  my $aes = new PlugNPay::Util::Encryption::AES();

  # decrypt the ciphertext
  my $plaintext;
  eval {
    my $keyManager = new PlugNPay::Util::Encryption::LegacyKey();
    if ($yearMonth) {
      $keyManager->loadMonthlyKey($yearMonth);
    } else {
      $keyManager->loadRecurringKey();
    }
    $key = $keyManager->getActiveKey();
    $iv = $keyManager->getInitializationVector();

    $plaintext = $aes->decryptWithIV($key,$iv,$ciphertext);
  };

  if ($@) {
    new PlugNPay::Logging::DataLog({ collection => 'rsautils' })->log({'error' => $@, 'identifier' => $yearMonth});
  }

  return $plaintext;
}

sub keygen {
  my $yearMonth = shift;
  my $keyManager = new PlugNPay::Util::Encryption::LegacyKey();

  return $keyManager->generateMonthlyKey($yearMonth);
}

sub errormsg {
  my ($msg) = @_;

  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setFormat('text');
  $emailObj->setTo('cprice@plugnpay.com');
  $emailObj->setFrom('dcprice@plugnpay.com');
  $emailObj->setSubject('pwfiles - FAILURE');
  $emailObj->setContent($msg);
  $emailObj->send();
}

1;
