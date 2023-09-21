#!/bin/env perl

require 5.001;
$|=1;

use lib $ENV{'PNP_PERL_LIB'};
use security;
use PlugNPay::Util::Captcha::ReCaptcha;
use strict;

#print "Content-Type: text/html\n\n";

if ($ENV{'SEC_LEVEL'} > 13) {
  print "Content-Type: text/html\n\n";
  print "Your current security level is not cleared for this operation. <p>Please contact Technical Support if you believe this to be in error. ";
  exit;
}

my $security = new security('reseller');

if (($ENV{'HTTP_X_FORWARDED_SERVER'} ne '') && ($ENV{'HTTP_X_FORWARDED_FOR'} ne '')) {
  $ENV{'HTTP_HOST'} = (split(/\,/,$ENV{'HTTP_X_FORWARDED_HOST'}))[0];
  $ENV{'SERVER_NAME'} = (split(/\,/,$ENV{'HTTP_X_FORWARDED_SERVER'}))[0];
}

## allow Proxy Server to modify ENV variable 'REMOTE_ADDR'
if ($ENV{'HTTP_X_FORWARDED_FOR'} ne '') {
  $ENV{'REMOTE_ADDR'} = $ENV{'HTTP_X_FORWARDED_FOR'};
}


if ( (($ENV{'TEMPFLAG'} == 1) || ($ENV{'REDIRECT_TEMPFLAG'} == 1)) && ($security::function !~ /^(update_passwrd)$/) && ($ENV{'TECH'} eq "") ) {
  $security::query{'merchant'} = "$ENV{'REMOTE_USER'}";
  $security::query{'login'} = $security::login;  ### DCP 20120131
  $security::function = "edit_passwrd";
}

my $captcha_match = 0;
if ($security::query{'g-recaptcha-response'} ne '') {
  my $captcha = new PlugNPay::Util::Captcha::ReCaptcha();
  $captcha_match = $captcha->isValid($ENV{'REMOTE_USER'}, $security::query{'g-recaptcha-response'}, $ENV{'REMOTE_ADDR'});
}

#if (($security::function =~ /xxxxx/) && ($security::query{'g-recaptcha-response'} eq '')) {
#  $security->head();
#  $security->captchaCheck('');
#  $security->tail();
#} elsif {...

if ($security::function eq "edit_user") {
  $security->details_acl();
  $security->head();
  $security->edit_user();
  $security->tail();
}
elsif ($security::function eq "edit_passwrd") {
  $security->details_acl();
  $security->head();
  $security->edit_passwrd();
  $security->tail();
}
elsif ($security::function eq 'add_new_user') {
  $security->details_acl();
  $security->head();
  $security->username_config_add();
  $security->tail();
}
elsif ($security::function =~ /^(add_user|update_passwrd)$/) {
  my $error = $security->input_check();
  #print "AA:$error:$security::error_string<br>\n";
  if (!$captcha_match) {
    $security::error_string .= "Invalid CAPTCHA Answer.<br>";
    $error = 15;
    $security::color{'captcha'} = 'badcolor';
    $security::color{'captcha'} = 'badcolor';
    $security::errvar .= "captchaAnswer\|";
  }
  if ($error > 0) {
    $security->head();
    if ($security::function eq "add_user") {
      $security->username_config_add();
    }
    elsif ($security::function eq "update_passwrd") {
      $security->edit_passwrd();
    }
    else {
      $security->edit_user();
    }
    $security->tail();
  }
  else {
    $security->update_acl();
    if ($security::reloginflag == 1) {
      print "Location: https://$ENV{'SERVER_NAME'}/admin/logout.cgi\n\n";
    }
    elsif (($ENV{'TEMPFLAG'} == 1) || ($ENV{'REDIRECT_TEMPFLAG'} == 1)) {
      ##print "Location: https://$ENV{'SERVER_NAME'}/reseller/index.cgi\n\n";     
      print "Location: https://$ENV{'SERVER_NAME'}/admin/index.cgi\n\n";
    }
    else {
      ##print "Location: https://$ENV{'SERVER_NAME'}/admin/security.cgi\n\n";
      print "Location: https://$ENV{'SERVER_NAME'}$ENV{'SCRIPT_NAME'}\n\n";
    }
    exit;
  }
}
elsif ($security::function eq "delete_user") {
  my $error = 0;
  if (!$captcha_match) {
    $security::error_string .= "Invalid CAPTCHA Answer.<br>";
    $error = 15;
    $security::color{'captcha'} = 'badcolor';
    $security::color{'captcha'} = 'badcolor';
    $security::errvar .= "captchaAnswer\|";
  }
  if ($error > 0) {
    $security->head();
    $security->unpw_menu();
    $security->tail();
  }
  else {
    $security->delete_acl();
    $security->head();
    $security->unpw_menu();
    $security->tail();
  }
}
elsif ($security::function eq "add_ip") {
  my $error = $security->input_check();
  if ($error > 0) {
    $security->head();
    $security->transsec_menu();
    $security->tail();
  }
  else {
    $security->update_ip();
    $security->head();
    $security->transsec_menu();
    $security->tail();
  }
}
elsif ($security::function eq 'hashkey') {
  ## for response verification hash
  if ($security::query{'hashkeyaction'} eq 'delete') {
    $security->delete_hashkey();
  }
  else {
    $security->add_hashkey();
  }
  $security->head();
  $security->verifyhash_menu();
  $security->tail();
}
elsif ($security::function eq 'authhashkey') {
  ## for authorization verification hash
  if ($security::query{'hashkeyaction'} eq 'delete') {
    $security->delete_authhashkey();
  }
  else {
    $security->add_authhashkey();
  }
  $security->head();
  $security->verifyhash_menu();
  $security->tail();
}
elsif ($ENV{'TEMPFLAG'} == 1) {
  $security->details_acl();
  $security->head();
  $security->edit_user();
  $security->tail();
}

elsif ($security::function eq "show_unpw_menu") {
  $security->head();
  $security->unpw_menu();
  $security->tail();
}
elsif ($security::function eq "show_transsec_menu") {
  $security->head();
  $security->transsec_menu();
  $security->tail();
}
elsif ($security::function eq 'show_verifyhash_menu') {
  $security->head();
  $security->verifyhash_menu();
  $security->tail();
}
else {
  $security->head();
  $security->main();
  $security->tail();
}

exit;

