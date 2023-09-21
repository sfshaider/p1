#!/usr/local/bin/perl

## Purpose: provides functions for CAPTCHA initialization & verification
# "https://" . $ENV{'SERVER_NAME'} . "/captcha/captchaclient.cgi\?captchaid=";
# checking of answer is case insensitive 
# I filter my inputs but you should also

use PlugNPay::Sys::Time;
use PlugNPay::Util::UniqueID;
use miscutils;
use strict;

package PlugNPay::Util::CaptchaClient;

sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  # unique id to use for captcha
  $self->{'ID'} = new PlugNPay::Util::UniqueID();
 
  $self->{'err'} = "";

  # length for captcha max is 10 min is 4 default is 8
  # table supports up to 20 but the image generation sucks
  # when it is longer than 10
  $self->{'length'} = shift || undef;
  $self->{'length'} =~ s/[^0-9]//g;
  if ((!defined $self->{'length'}) || ($self->{'length'} < 4)) {
    $self->{'err'} = "bad length";
    $self->{'length'} = 8;
  } elsif ($self->{'length'} > 10) {
    $self->{'err'} = "bad length";
    $self->{'length'} = 8;
  }

  $self->{'currentTime'} = new PlugNPay::Sys::Time("unix",time());  # get the current time
  $self->{'expireTime'} = new PlugNPay::Sys::Time("unix",(time() - 900)); # used for max age of captchas

  if (defined $ENV{'SERVER_NAME'}) {
    $self->{'imageScript'} = "https://$ENV{'SERVER_NAME'}/captcha/captchaclient.cgi";
  } else {
    $self->{'imageScript'} = "https://pay1.plugnpay.com/captcha/captchaclient.cgi";
  }

  return $self;
}

# validate a captcha pass captchID, captchaAnswer, captchaIP
sub isValid {
  # validates presented captcha information
  my $self = shift;

  my $captchaID = shift || undef;
  if (!$self->setID($captchaID)) {
    $self->{'err'} = "bad captcha id";
    return 0;
  } 

  my $captchaAnswer = shift || undef;
  if ((defined $captchaAnswer) && ($captchaAnswer ne "")) {
    $self->setAnswer($captchaAnswer);
  } else {
    $self->{'err'} = "bad captcha answer";
    return 0;
  }

  my $captchaIP = shift || undef;
  if ((defined $captchaIP) && ($captchaIP ne "")) {
    $self->setIP($captchaIP);
  } else {
    $self->{'err'} = "bad captcha ip";
    return 0;
  }

  my $dbh = &miscutils::dbhconnect("pnpmisc");
  # first delete aged captchas they aren't valid anymore
  $self->__deleteAged($dbh);

  # pull captcha info from captcha database
  my $sth = $dbh->prepare(qq{
      select answer
      from captchaclient
      where id=? and ipaddress=? and lower(answer)=lower(?)
  }) or die "Can't prepare: $DBI::errstr";
  my $rv = $sth->execute($self->{'ID'}->inHex(),$self->{'ipaddress'},"$captchaAnswer") or die "Can't execute: $DBI::errstr";
  $sth->finish;

  $dbh->disconnect;

  if ((!defined $rv) || ($rv eq "0E0")) {
    $self->{'err'} = "captcha data invalid";
    return 0;
  }

  return 1;
}

sub createCaptcha {
  my $self = shift;

  my $captchaIP = shift || undef;
  $self->setIP($captchaIP);

  # generate captcha answer
  $self->setAnswer();

  # insert captcha info into database
  my $dbh = &miscutils::dbhconnect("pnpmisc");
  if (defined $dbh) {
    my $sth_insert = $dbh->prepare(qq{
        insert into captchaclient
        (id, created, answer, ipaddress)
        values (?,?,?,?)
    });
    $sth_insert->execute($self->{'ID'}->inHex(), $self->{'currentTime'}->inFormat('db_gm'), $self->{'answer'}, $self->{'ipaddress'});
    $sth_insert->finish;
    $dbh->disconnect;
  } else {
    $self->{'err'} = "problem connecting to the database";
    return 0;
  }

  return 1;
}

# error messages are not for the user
# they are for debugging your terrible code.
sub getError {
  my $self = shift;
  return $self->{'err'};
}

sub getID {
  my $self = shift;
  return $self->{'ID'}->inHex();
}

sub setID {
  my $self = shift;
  my $captchaID = shift || undef;

  if (defined $captchaID) {
    # filter captchaID
    $captchaID =~ s/[^0-9a-fA-F]//g;
    my $newID = new PlugNPay::Util::UniqueID();
    $newID->fromHex($captchaID);
    # validate the uniqueID a little bit
    if ($newID->validateUniqueID($captchaID)) {
      $self->{'ID'} = $newID;
      return 1;
    }
  } 

  return 0;
}

sub getURL {
  my $self = shift;
  return $self->{'imageScript'} . "\?captchaID=" . $self->getID;
}

### functions below this are really just for testing or internal use ###
sub getAnswer {
  my $self = shift;
  return $self->{'answer'};
}

sub setAnswer {
  my $self = shift;
  my $captchaAnswer = shift || undef;

  if (defined $captchaAnswer) {
    $captchaAnswer =~ s/[^a-zA-Z0-9]//g;
    $self->{'answer'} = $captchaAnswer;
  } else {
    $self->{'answer'} = $self->__randomalphanum($self->{'length'}); # generates random password
  }
}

sub getIP {
  my $self = shift;
  return $self->{'ipaddress'};
}

sub setIP {
  my $self = shift;

  my $captchaIP = shift || undef;
  if (defined $captchaIP) {
    $captchaIP =~ s/[^0-9\.]//g;
  } elsif (defined $ENV{'REMOTE_ADDR'}) {
    $captchaIP = $ENV{'REMOTE_ADDR'};
  } else {
    # default to localhost shouldn't ever happen
    $self->{'err'} = "You did something wrong";
    $captchaIP = "127.0.0.1";
  }

  $self->{'ipaddress'} = $captchaIP;
}

sub __randomalphanum {
  my $self = shift;

  # no 0oOlLiIjJ in set
  my @set = ('2'..'9','a'..'h','k','m','n','p'..'z','A'..'H','K','M','N','P'..'Z');
  my $answer = join '' => map $set[rand @set], 1 .. $self->{'length'};

  return $answer;
}

# expects a db handle to be passed to it
sub __deleteAged {
  my $self = shift;

  my $dbh = shift || undef;
  if (defined $dbh) {
    # now delete the specific captcha ID record, so no-one else can use it & remove any very old captchas as well.
    my $sth_del = $dbh->prepare(qq{
        delete from captchaclient
        where created<?
        });
    $sth_del->execute($self->{'expireTime'}->inFormat("db_gm"));
    $sth_del->finish;
  }
  # on db failure this isn't critical enough to fail on
}

1;
