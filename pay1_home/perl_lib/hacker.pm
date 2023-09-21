package hacker;

use miscutils;
use strict;

# preload table entries
my $preloadedSignatures = __loadSignatures();
my $preloadTime = time();

sub new {
  my ($self) = @_;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  #$self->{'dbh'} = &miscutils::dbhconnect("pnpmisc");
  $self->{'Signatures'} = $preloadedSignatures;

  # add code here to reload signatures if 10 minutes old
  # if preloaded data is older than 10 minutes reload from table.
  my $maxTime = 60*10;  # 10 minutes
  if (((time() - $preloadTime) >= $maxTime) || (!defined $self->{'Signatures'})) {
    $self->{'Signatures'} = __loadSignatures();
    $preloadTime = time();
  }

  return $self;
}

#sub DESTROY {
#  my ($self) = @_;
#  $self->{'dbh'}->disconnect();
#}

sub __loadSignatures {
  my $dbh = &miscutils::dbhconnect("pnpmisc");
  my $sth = $dbh->prepare(qq{
      select signature,datakey,datavalue,caseflag
      from hacker_signature
      order by signature
    }) or die "Can't do: $DBI::errstr";
  $sth->execute() or die "Can't execute: $DBI::errstr";
  my $result = $sth->fetchall_arrayref({});
  $dbh->disconnect();

  return $result;
}

sub check_request {
  my($self, $query) = @_;

  my $hacker_flag = 0;
  my ($last_signature,$first_flag,%skip_signature);
  my ($signature,$datakey,$datavalue,$caseflag);

  for (my $pos=0;$pos<=$#{$self->{'Signatures'}};$pos++) {
    # just doing this to make code easier to read
    $signature = $self->{'Signatures'}->[$pos]->{'signature'};
    $datakey = $self->{'Signatures'}->[$pos]->{'datakey'};
    $datavalue = $self->{'Signatures'}->[$pos]->{'datavalue'};
    $caseflag = $self->{'Signatures'}->[$pos]->{'caseflag'};
    ## If tranaction already failed signature test then skip to next one.
    if ($skip_signature{$signature} != 1) {
      if ($last_signature eq "") {
        $last_signature = $signature;
        $first_flag = 1;
      }
      if (($last_signature ne $signature) && ($hacker_flag == 1)) {
        # if hacker flag is set we don't have to check anymore signatures
        last;
      }
      if (($datakey eq 'sourceip') && ($ENV{'REMOTE_ADDR'} eq "$datavalue")) {
        $hacker_flag = 1;
      }
      elsif  (($caseflag == 1) && ($$query{$datakey} =~ /$datavalue/i)) {
        $hacker_flag = 1;
      }
      elsif ($$query{$datakey} =~ /$datavalue/) {
        $hacker_flag = 1;
      }
      else {
        # some entry didn't match in the signature so reset for next signature check
        $skip_signature{$signature} = 1;
        $hacker_flag = 0;
        next;
      }
      $last_signature = $signature;
      $first_flag = 0;
    }
  }

  if ($hacker_flag == 1) {
    my $dbh = &miscutils::dbhconnect("pnpmisc");
    my $sth = $dbh->prepare(qq{
      select status,agentcode
      from customers
      where username=?
    }) or die "Can't do: $DBI::errstr";
    $sth->execute("$$query{'publisher-name'}") or die "Can't execute: $DBI::errstr";
    my ($status,$ac) = $sth->fetchrow;
    $sth->finish;
    $dbh->disconnect();

    if (($status =~ /live|fraud/i) && ($ac !~ /ff/i)) {
      $$query{'acct_code'} = $$query{'publisher-name'};
      $$query{'publisher-name'} = 'hackeracco';
      $$query{'hackersignature'} = $signature;
    }
    else {
      $hacker_flag = 0;
    }
  }

  return $hacker_flag;
}

sub log {
  my ($self, $query) = @_;

  my ($dummy,$datestr,$timestr) = &miscutils::gendatetime();
  my $dbh = &miscutils::dbhconnect("pnpmisc");
  my $sth = $dbh->prepare(qq{
      insert into hacker_log
      (trans_time,username,signature,orderid)   
      values (?,?,?,?)
    }) or die "Can't do: $DBI::errstr";
  $sth->execute($timestr,$$query{'acct_code'},$$query{'hackersignature'},$$query{'orderID'}) or die "Can't execute: $DBI::errstr";
  $dbh->disconnect();
  
  return;
}

1;
