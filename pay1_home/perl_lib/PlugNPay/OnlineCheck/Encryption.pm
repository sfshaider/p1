package PlugNPay::OnlineCheck::Encryption;

use strict;
use rsautils;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  return $self;
}

sub encrypt {
  my $self = shift;
  my $accountInfo = shift;
  my $dataType = shift;
  my $keyPath = shift || '/home/p/pay1/pwfiles/keys/key';

  my $ciphertext = &rsautils::aes_encrypt($accountInfo,$keyPath,$dataType);
  $ciphertext = unpack('H*',$ciphertext);
  my $yearMonth = &rsautils::getYearMonth($dataType);
  $ciphertext = ($dataType eq 'log' ? $yearMonth . ' ' : '') . 'aes256 ' . $ciphertext;

  return $ciphertext;
}

sub decrypt {
  my $self = shift;
  my $encNumber = shift;
  my $keyPath = shift || '/home/p/pay1/pwfiles/keys/key';

  my @data = split(/ /,$encNumber);
  my $ciphertext = $data[2] || $data[1];
  $ciphertext = pack('H*',$ciphertext);
  my $yearMonth = ($data[2] ? $data[0] : '');
  my $dataType = ($yearMonth ? 'log' : '');

  my @info = split(' ', &rsautils::aes_decrypt($ciphertext,$keyPath,$dataType,$yearMonth));
  my $acctInfo = {'routing' => $info[0], 'account' => $info[1]};

  return $acctInfo;
}

1;
