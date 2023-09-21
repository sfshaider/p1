package captcha;

## Purpose: provides functions for CAPTCHA initialization & verification

require 5.001;
$| = 1;

use DBI;
use miscutils;
use CGI;
use PlugNPay::Features;
use strict;

sub new {
  my $type = shift;

  %captcha::query = @_;

  ## allow Proxy Server to modify ENV variable 'REMOTE_ADDR'
  if ($ENV{'HTTP_X_FORWARDED_FOR'} ne '') {
    $ENV{'REMOTE_ADDR'} = $ENV{'HTTP_X_FORWARDED_FOR'};
  }

  if (($captcha::query{'publisher-name'} eq '') && ($captcha::query{'merchant'} ne '')) { 
    $captcha::query{'publisher-name'} = $captcha::query{'merchant'};
  }

  $captcha::query{'publisher-name'} =~ s/[^0-9a-zA-Z]//g;
  $captcha::query{'publisher-name'} = substr($captcha::query{'publisher-name'},0,12);

  # get feature settings
  my $accountFeatures = new PlugNPay::Features("$captcha::query{'publisher-name'}",'general');
  my $features = $accountFeatures->getFeatureString();

  # parse feature settings
  %captcha::feature = ();
  if ($features ne '') {
    my @array = split(/\,/,$features);
    foreach my $entry (@array) {
      my ($name, $value) = split(/\=/,$entry);
      $captcha::feature{"$name"} = $value;
    }
  }

  # set other misc parmeters
  $captcha::image  = "https://$ENV{'SERVER_NAME'}/captcha/captcha.cgi\?merchant=$captcha::query{'publisher-name'}\&captchaid=";

  return [], $type;
}

sub validate_captcha {
  # validates presented captcha information
  my ($merchant, $captchaid, $answer, $ipaddress) = @_;

  # filter input data
  $merchant =~ s/[^a-zA-Z0-9]//g;
  $captchaid =~ s/[^0-9]//g;
  $answer =~ s/[^a-zA-Z0-9]//g;
  $ipaddress =~ s/[^0-9\.]//g;

  my $dbh = &miscutils::dbhconnect('pnpmisc');

  # pull captcha info from captcha database
  my $sth = $dbh->prepare(q{
      SELECT answer, ipaddress
      FROM captcha
      WHERE merchant=?
      AND captchaid=?
    }) or die "Can't prepare: $DBI::errstr";
  $sth->execute("$merchant", "$captchaid") or die "Can't execute: $DBI::errstr";
  my ($db_answer, $db_ipaddress) = $sth->fetchrow();
  $sth->finish;

  # figure out cutoff time; for removeal of very old captcha entries.
  my @then = gmtime(time - 3600); # get time of 1 hour ago [3600 seconds]
  my $time_cutoff = sprintf("%04d%02d%02d%02d%02d%02d%s", $then[5]+1900, $then[4]+1, $then[3], $then[2], $then[1], $then[0], '00000');

  # now delete the specific captcha ID record, so no-one else can use it & remove any very old captchas as well.
  my $sth2 = $dbh->prepare(q{
      DELETE FROM captcha
      WHERE (merchant=? AND captchaid=?)
      OR (captchaid<=?)
    }) or die "Can't prepare: $DBI::errstr";
  $sth2->execute("$merchant", "$captchaid", "$time_cutoff") or die "Can't execute: $DBI::errstr";
  $sth2->finish;

  $dbh->disconnect;

  # now its OK to validate the captcha information
  my ($finalstatus, $merrmsg);

  # first step, validate captcha has not expired
  my $time_stored = substr($captchaid,0,14); # get time captcha was stored to database

  my @now = gmtime(time); # get the current time
  my $time_current = sprintf("%04d%02d%02d%02d%02d%02d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], $now[0]);

  my $time_difference = $time_current - $time_stored; # figure out the time difference in seconds
  if ($time_difference > 120) {
    # reject captchas that are over 2 minutes old. [120 seconds]
    $finalstatus = 'badcard';
    $merrmsg = "Captcha Expired";
    return ($finalstatus, $merrmsg);
  }

  # second step, make sure IPs match each other
  elsif ($ipaddress ne "$db_ipaddress") {
    # reject requests when they are not from the original requesting IP.
    $finalstatus = 'badcard';
    $merrmsg = "Captcha Invalid";
    return ($finalstatus, $merrmsg);
  }

  # final step, if everything was ok, now validate the captcha answer
  elsif ($db_answer =~ /^($answer)$/i) {
    # catcha matches, give success response
    $finalstatus = 'success';
    $merrmsg = "";
  }
  else {
    # captcha does not match, give rejection response
    $finalstatus = 'badcard';
    $merrmsg = "Captcha Incorrect";
  }

  return ($finalstatus, $merrmsg);
}

sub randomalphanum {
  my ($length) = @_;
  my ($pass,$letter,$asciicode);
  while($length > 0) {
    my $asciicode = int(rand 1 * 123);
    if ( ( $asciicode > 48 && $asciicode < 58 ) ||
         ( $asciicode > 64 && $asciicode < 91 ) ||
         ( $asciicode > 96 && $asciicode < 123) ) {
      $letter = chr($asciicode);
      if ($letter !~ /[Iijyvl10Oo]/) {
        $length--;
        $pass .= $letter;
      }
    }
  }
  return $pass;
}

sub create_new_captcha {
  # adds new captcha entry in captcha database
  my ($merchant, $ipaddress) = @_;

  $merchant =~ s/[^a-zA-Z0-9]//g;
  $ipaddress =~ s/[^0-9\.]//g;

  if ($ipaddress ne '') {
    $ipaddress = $ENV{'REMOTE_ADDR'};
  }

  # generate captcha ID
  my @now = gmtime(time);
  my $captchaid = sprintf("%04d%02d%02d%02d%02d%02d%05d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], $now[0], $$);

  # generate captcha answer
  my $answer = &randomalphanum(16); # generates random password
  $answer =~ s/[^a-zA-Z0-9]//g;
  $answer = uc(substr($answer,0,6));
  #print "Captcha Answer: $answer<br>\n";

  # insert captcha info into database
  my $dbh = &miscutils::dbhconnect('pnpmisc');
  my $sth_insert = $dbh->prepare(q{
      INSERT INTO captcha
      (merchant, captchaid, answer, ipaddress)
      VALUES (?,?,?,?)
    }) or die "Can't prepare: $DBI::errstr";
  $sth_insert->execute("$merchant", "$captchaid", "$answer", "$ipaddress") or die "Can't execute: $DBI::errstr";
  $sth_insert->finish;
  $dbh->disconnect;

  # wait a few seconds for database to catch up.
  #sleep(2);

  $captcha::image = "https://$ENV{'SERVER_NAME'}/captcha/captcha.cgi\?merchant=$merchant\&captchaid=$captchaid";

  return $captchaid;
}

