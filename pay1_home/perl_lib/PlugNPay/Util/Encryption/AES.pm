package PlugNPay::Util::Encryption::AES;

use strict;
use Crypt::Rijndael;
use POSIX;

use PlugNPay::Util::Encryption::Random;

sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  return $self;
}

sub encryptWithIV {
  my $self = shift;
  my $key = shift;
  my $iv = shift;
  my $plaintext = shift;

  # plaintext must be a multiple of 16 bytes long so pad it with the number of bytes.
  # the pad is the number of bytes repeated over and over.
  # example:
  #   if the pad is 12 bytes, the binary representation of 12 is 0b00001100.
  #   so the pad would look like this in binary:
  #     binary: 00001100 00001100 00001100 00001100 00001100 00001100 00001100 00001100 00001100 00001100 00001100 00001100
  #     hex:    0c 0c 0c 0c 0c 0c 0c 0c 0c 0c 0c 0c
  #
  #  if the plaintext is a multiple of 16 bytes, you still pad 16 bytes of "16"
  #     binary: 00010000 00010000 00010000 00010000 00010000 00010000 00010000 00010000 00010000 00010000 00010000 00010000 00010000 00010000 00010000 00010000
  #     hex:    10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10
  my $padLength = int((16 - (length($plaintext) % 16)) || 16);
  my $pad = pack('c', $padLength) x $padLength;;

  my $plaintextPadded = $plaintext . $pad;

  my $key2 = substr($key,0,32);
  my $iv2 = substr($iv,0,16);

  my $cipher = Crypt::Rijndael->new($key2,Crypt::Rijndael::MODE_CBC());
  $cipher->set_iv($iv2);

  my $ciphertext = $cipher->encrypt($plaintextPadded);

  return $ciphertext;
}

sub decryptWithIV {
  my $self = shift;
  my $key = shift;
  my $iv = shift;
  my $ciphertext = shift;


  my $key2 = substr($key,0,32);
  my $iv2 = substr($iv,0,16);

  my $cipher;
  eval {
    $cipher = Crypt::Rijndael->new($key2,Crypt::Rijndael::MODE_CBC());
  };
  if ($@) {
    die('Invalid key length.  Caller: ' . join(', ',caller()));
  }
  $cipher->set_iv($iv2);

  my $plaintext = $cipher->decrypt($ciphertext);

  # the length of the pad is encoded into the last byte
  my $padLength = hex(unpack('H*',substr($plaintext,-1,1)));

  $plaintext = substr($plaintext,0,length($plaintext) - $padLength);

  return $plaintext;
}


sub encrypt {
  my $self = shift;
  my ($data,$key,$settings) = @_;

  my $initializationVector = $settings->{'initializationVector'};
  my $mode = $settings->{'mode'} || 'default';

  my $random = new PlugNPay::Util::Encryption::Random();

  # figure out the length of the data so we can null pad it
  my $dataLength = length($data);

  # the block size is 16 bytes, so we figure out how many blocks we are encrypting
  my $blockCount = POSIX::ceil($dataLength / 16);

  my $padSize = ($blockCount * 16) - $dataLength;

  # create the "null" block to XOR with the data to do the padding
  my $nullString = "\0" x 16;

  my $padDescriptor = $nullString ^ unpack('H*',$padSize);

  # pad the data, put a 16 block random pad in front for the initialization vector to do it's magic, then
  # pad the end with nulls to get a multiple of 16 bytes

  my $frontPad = $random->random(16);
  $data = $frontPad . ($nullString x $blockCount ^ $data);

  # create a new instance of Crypt::Rijndael;
  # untaint the key first
  $key = pack "B*", do { unpack "B*", $key };  # untainting
  my $cipher = Crypt::Rijndael->new( $key , Crypt::Rijndael::MODE_CBC() );

  # create a random, one time, initialization vector
  if (!$initializationVector) {
    $initializationVector = $random->random(16);
  }

  $cipher->set_iv($initializationVector);

  # encrypt!
  return ($padDescriptor . $cipher->encrypt($data)),$initializationVector;
}

sub decrypt {
  my $self = shift;
  my ($encryptedData,$key) = @_;

  my $padDescriptor = substr($encryptedData,0,16);
  $encryptedData = substr($encryptedData,16);

  # create a new instance of Crypt::Rijndael
  my $cipher = Crypt::Rijndael->new( $key , Crypt::Rijndael::MODE_CBC() );

  # decrypt!
  my $decryptedData = $cipher->decrypt($encryptedData);

  #my $decryptedLength = length($decryptedData);

  $decryptedData =~ s/^\0{16}//;

  $decryptedData = undef ^ $decryptedData;

  $decryptedData = substr($decryptedData,16);
  $decryptedData = substr($decryptedData,0,-pack('H*',$padDescriptor));

  return $decryptedData;
}

sub aesKeyLength {
  my $self = shift;

  return 256;
}

1;
