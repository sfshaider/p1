package PlugNPay::Processor::SeqNumber;
use strict;
use PlugNPay::DBConnection;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $processor = shift;
  if (defined $processor) {
    $self->loadNumberLength($processor);
  }

  return $self;
}

sub setMerchant {
  my $self = shift;
  my $merchant = shift;
  $self->{'merchant'} = $merchant;
}

sub getMerchant {
  my $self = shift;
  return $self->{'merchant'};
}

sub setProcessor {
  my $self = shift;
  my $processor = shift;
  $self->{'processor'} = $processor;
}

sub getProcessor {
  my $self = shift;
  return $self->{'processor'};
}

sub setSeqNumber {
  my $self = shift;
  my $seqNumber = shift;
  $self->{'seqNumber'} = $seqNumber;
}

sub getSeqNumber {
  my $self = shift;
  return $self->{'seqNumber'};
}

sub setRequiredLength {
  my $self = shift;
  my $requiredLength = shift;
  $self->{'requiredLength'} = $requiredLength;
}

sub getRequiredLength {
  my $self = shift;
  return $self->{'requiredLength'};
}

sub loadNumberLength {
  my $self = shift;
  my $processor = shift || $self->getProcessor();

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/ SELECT required_seq_number_length AS `length`
                             FROM processor
                             WHERE code_handle = ? /);
  $sth->execute($processor) or die $DBI::errstr;
  
  my $rows = $sth->fetchall_arrayref({});
  
  $self->setRequiredLength($rows->[0]{'length'});

}

sub generate {
  my $self = shift;
  my $merchant = shift;
  my $updateFlag = 0;
  
  my $dbs = new PlugNPay::DBConnection();
  $dbs->begin('pnpmisc');
  my $sth = $dbs->prepare('pnpmisc',q/ 
                           SELECT seq_number
                           FROM trans_seq_number
                           WHERE merchant = ?/);
  $sth->execute($merchant) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my $number = 0;
  if (defined $rows->[0]{'seq_number'}) {
     $number = $rows->[0]{'seq_number'};
     $updateFlag = 1;
  }

  $number++;
  
  if ($updateFlag) {
    $sth = $dbs->prepare('pnpmisc',q/ 
                          UPDATE trans_seq_number
                          SET seq_number = ?
                          WHERE merchant = ? /);
    $sth->execute($number,$merchant) or die $DBI::errstr;
    $sth->finish();
  } else {
    $sth = $dbs->prepare('pnpmisc',q/
                          INSERT INTO trans_seq_number
                          (merchant,seq_number)
                          VALUES (?,?) /);
    $sth->execute($merchant,$number);
    $sth->finish();
  }

  $dbs->commit('pnpmisc');

  if (defined $self->getRequiredLength()) {
    if (length($number) > $self->getRequiredLength()) {
      $number = 0;
    }
    my $length = $self->getRequiredLength() - length($number);
    $number = ('0' x $length) . $number;
  }
  
  return $number;
}

1;
