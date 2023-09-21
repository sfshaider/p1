#!/bin/env perl

require 5.001;
$|=1;

use lib $ENV{'PNP_PERL_LIB'};
use security;
use PlugNPay::Util::Captcha::ReCaptcha;
use PlugNPay::Util::RandomString;
use strict;

#print "Content-Type: text/html\n\n";

if ($ENV{'SEC_LEVEL'} > 13) {
  print "Content-Type: text/html\n\n";
  print "Your current security level is not cleared for this operation. <p>Please contact Technical Support if you believe this to be in error. ";
  exit;
}

my $security = new security();

## allow Proxy Server to modify ENV variable 'REMOTE_ADDR'
if ($ENV{'HTTP_X_FORWARDED_FOR'} ne '') {
  $ENV{'REMOTE_ADDR'} = $ENV{'HTTP_X_FORWARDED_FOR'};
}

if ( (($ENV{'TEMPFLAG'} == 1) || ($ENV{'REDIRECT_TEMPFLAG'} == 1)) && ($security::function !~ /^(update_passwrd)$/) && ($ENV{'TECH'} eq '') ) {
  $security::query{'merchant'} = "$ENV{'REMOTE_USER'}";
  $security::query{'login'} = $security::login;  ### DCP 20120131
  $security::function = 'edit_passwrd';
}

my $captcha_match = 0;
if ($security::query{'g-recaptcha-response'} ne '') {
  my $captcha = new PlugNPay::Util::Captcha::ReCaptcha();
  $captcha_match = $captcha->isValid($ENV{'REMOTE_USER'}, $security::query{'g-recaptcha-response'}, $ENV{'REMOTE_ADDR'});
} 

if ($security::function eq 'edit_user') {
  $security->details_acl();
  $security->head();
  $security->edit_user();
  $security->tail();
}
elsif ($security::function eq 'edit_passwrd') {
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
    if ($security::function eq 'add_user') {
      $security->username_config_add();
    }
    elsif ($security::function eq 'update_passwrd') {
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
      print "Location: https://$ENV{'SERVER_NAME'}/admin/index.cgi\n\n"; 
    }
    else {
      ##print "Location: https://$ENV{'SERVER_NAME'}/admin/security.cgi\n\n";
      $security->head();
      $security->unpw_menu();
      $security->tail();
    }
    exit;
  }
}
elsif ($security::function eq 'delete_user') {
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
elsif ($security::function eq 'add_ip') {
  my $error = $security->input_check();
  if (!$captcha_match) {
    $security::error_string .= "Invalid CAPTCHA Answer.<br>";
    $error = 15;
    $security::color{'captcha'} = 'badcolor';
    $security::color{'captcha'} = 'badcolor';
    $security::errvar .= "captchaAnswer\|";
  }
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
elsif ($security::function eq 'delete_ip') {
  # deletion is taken care of when $security is instantiated... real head scratcher, that one.
  $security->head();
  $security->transsec_menu();
  $security->tail();
}
elsif ($security::function eq 'enable_distclient') {
  $security->update_distclient();
  $security->head();
  $security->client_menu();
  $security->tail();
}
elsif ($security::function eq 'enable_noreturns') {
  $security->update_noreturns();
  $security->head();
  $security->transsec_menu();
  $security->tail();
}
elsif ($security::function eq 'add_rempasswd') {
  $security->add_rempasswd();
}
elsif ($security::function eq 'delete_rempasswd') {
  $security->delete_rempasswd();
  # Following 3 subroutines only called if delete checkbox is not checked.
  $security->head();
  $security->transkey_menu();
  $security->tail();
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
elsif ($security::function eq 'add_remotepwd') {
  my $error = $security->input_check();
  if (!$captcha_match) {
    $security::error_string .= "Invalid CAPTCHA Answer.<br>";
    $error = 15;
    $security::color{'captcha'} = 'badcolor';
    $security::color{'captcha'} = 'badcolor';
    $security::errvar .= "captchaAnswer\|";
  }
  if ($error > 0) {
    $security->head();
    $security->remoteclient_menu();
    $security->tail(); 
  }  
  else {
    my $login = $security->getCurrentAccountUsername();
    my $password = $security->getRemotePasswordFromQuery();
    if ( $security->shouldGenerateRandomPassword() ) {
      $password = new PlugNPay::Util::RandomString()->randomAlphaNumeric(16);
      $security->setRemotePasswordInQuery($password);
    }
    $security->add_remotepwd({
      login => $login,
      password => $password
    }); 
    $security->head();
    $security->remoteclient_menu();
    $security->tail();
  }
}
elsif ($security::function eq 'add_mobilepwd') {
  my $error = $security->input_check();
  if (!$captcha_match) {
    $security::error_string .= "Invalid CAPTCHA Answer.<br>";
    $error = 15;
    $security::color{'captcha'} = 'badcolor';
    $security::color{'captcha'} = 'badcolor';
    $security::errvar .= "captchaAnswer\|";
  }
  if ($error > 0) {
    $security->head();
    $security->mobileterm_menu();
    $security->tail();
  }
  else {
    my $login = $security->getCurrentAccountUsername();
    my $password = $security->getMobilePasswordFromQuery();
    if ( $security->shouldGenerateRandomPassword() ) {
      $password = new PlugNPay::Util::RandomString()->randomAlphaNumeric(16);
      $security->setMobilePasswordInQuery($password);
    }
    $security->add_mobilepwd({
      login => $login,
      password => $password
    }); 
    $security->head();
    $security->mobileterm_menu();
    $security->tail();
  }
}
elsif ($security::function eq 'set_req') {
  $security->set_req();
  $security->head();
  $security->transsec_menu();
  $security->tail();
}
#elsif ($security::function eq 'delete_hashkey') {
#  $security->delete_hashkey();
#  # Following 3 subroutines only called if delete checkbox is not checked.
#  $security->head();
#  $security->verifyhash_menu();
#  $security->tail();
#}
elsif ($security::function eq 'update_encpayload') {
  $security->update_encpayload();

  $security->head();
  $security->transsec_menu();
  $security->tail();
}
elsif ($security::function eq 'add_encpayload') {
  $security->add_encpayload();

  $security->head();
  $security->transsec_menu();
  $security->tail();
}
elsif ($security::function eq 'add_sitekey') {
  $security->add_sitekey();
  $security->head();
  $security->transsec_menu();
  $security->tail();
}
elsif ($security::function eq 'delete_sitekey') {
  # deletion is taken care of when $security is instantiated... real head scratcher, that one.
  $security->head();
  $security->transsec_menu();
  $security->tail();
}
## API key related function calls
elsif ($security::function eq "add_apikey") {
  if (!$captcha_match) {
    $security::error_string .= "Invalid CAPTCHA Answer.<br>";
    $security::color{'captcha'} = 'badcolor';
    $security::color{'captcha'} = 'badcolor';
    $security::errvar .= "captchaAnswer\|";
  }
  else {
    $security->add_apikey();
  }
  $security->head();
  $security->apikey_menu();
  $security->tail();
}
elsif ($security::function eq "reactivate_apikey") {
  $security->reactivate_apikey();
  $security->head();
  $security->apikey_menu();
  $security->tail();
}
elsif ($security::function eq "expire_apikey") {
  $security->expire_apikey();
  $security->head();
  $security->apikey_menu();
  $security->tail();
}
elsif ($security::function eq "delete_multi_apikey") {
  # deletion is taken care of when $security is instantiated... real head scratcher, that one.
  $security->head();
  $security->apikey_menu();
  $security->tail();
}
elsif ($security::function eq "delete_single_apikey") {
  $security->delete_single_apikey();
  $security->head();
  $security->apikey_menu();
  $security->tail();
}
## kiosk related function calls
elsif ($security::function eq 'kiosk_update_default_url') {
  $security->kiosk_update_default_url();

  $security->head();
  $security->kiosk_menu();
  $security->tail();
}
elsif ($security::function eq 'kiosk_delete_default_url') {
  $security->kiosk_delete_default_url();

  $security->head();
  $security->kiosk_menu();
  $security->tail();
}
elsif ($security::function eq 'kiosk_edit_id') {
  $security->head();
  $security->kiosk_edit_id();
  $security->tail();
}
elsif ($security::function eq 'kiosk_update_id') {
  $security->kiosk_update_id();

  $security->head();
  $security->kiosk_menu();
  $security->tail();
}
elsif ($security::function eq 'kiosk_delete_id') {
  $security->kiosk_delete_id();

  $security->head();
  $security->kiosk_menu();
  $security->tail();
}
elsif ($security::function eq 'revoke_kiosk_urls') {
  $security->revoke_kiosk_urls();

  $security->head();
  $security->kiosk_menu();
  $security->tail();
}
elsif ($security::function eq 'delete_kiosk_ids') {
  $security->delete_kiosk_ids();

  $security->head();
  $security->kiosk_menu();
  $security->tail();
}
## device related function calls
elsif ($security::function eq 'device_edit_id') {
  $security->head();
  $security->device_edit_id();
  $security->tail();
}
elsif ($security::function eq 'device_update_id') {
  $security->device_update_id();

  $security->head();
  $security->device_menu();
  $security->tail();
}
elsif ($security::function eq 'device_delete_id') {
  $security->device_delete_id();

  $security->head();
  $security->device_menu();
  $security->tail();
}
elsif ($security::function eq 'device_approve_id') {
  $security->device_approve_id();

  $security->head();
  $security->device_menu();
  $security->tail();
}
elsif ($security::function eq 'device_revoke_id') {
  $security->device_revoke_id();

  $security->head();
  $security->device_menu();
  $security->tail();
}
elsif ($security::function eq 'approve_devices') {
  $security->approve_devices();

  $security->head();
  $security->device_menu();
  $security->tail();
}
elsif ($security::function eq 'revoke_devices') {
  $security->revoke_devices();

  $security->head();
  $security->device_menu();
  $security->tail();
}
elsif ($security::function eq 'delete_devices') {
  $security->delete_devices();

  $security->head();
  $security->device_menu();
  $security->tail();
}
elsif (defined $ENV{'DEVELOPMENT'} && $ENV{'DEVELOPMENT'} ne 'TRUE' && 
        ($ENV{'TEMPFLAG'} == 1) &&   # allow the below ip's to change settings when not in development mode
        ($ENV{'REMOTE_ADDR'} !~ /^(96\.56\.10\.14|24\.184\.187\.61|96\.56\.10\.14|96\.56\.10\.12)/)) {
  $security->details_acl();
  $security->head();
  $security->edit_user();
  $security->tail();
}
elsif ($security::function eq 'show_unpw_menu') {
  $security->head();
  $security->unpw_menu();
  $security->tail();
}
elsif ($security::function eq 'show_transsec_menu') {
  $security->head();
  $security->transsec_menu();
  $security->tail();
} 
elsif ($security::function eq 'show_remoteclient_menu') {
  $security->head();
  $security->remoteclient_menu();
  $security->tail();
}
elsif ($security::function eq 'show_mobileterm_menu') {
  $security->head();
  $security->mobileterm_menu();
  $security->tail();
}
elsif ($security::function eq 'show_transkey_menu') {
  $security->head();
  $security->transkey_menu();
  $security->tail();
} 
elsif ($security::function eq 'show_verifyhash_menu') {
  $security->head();
  $security->verifyhash_menu();
  $security->tail();
} 
elsif ($security::function eq 'show_client_menu') {
  $security->head();
  $security->client_menu();
  $security->tail();
} 
elsif ($security::function eq 'show_kiosk_menu') {
  $security->head();
  $security->kiosk_menu();
  $security->tail();
}
elsif ($security::function eq 'show_device_menu') {
  $security->head();
  $security->device_menu();
  $security->tail();
}
elsif ($security::function eq "show_apikey_menu") {
  $security->head();
  $security->apikey_menu();
  $security->tail();
}
else {
  $security->head();
  $security->main();
  $security->tail(); 
}

exit;

