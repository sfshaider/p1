package PlugNPay::Util::Captcha::ReCaptcha;

## Purpose: provides functions for Google reCAPTCHA initialization & verification

# This is a basic implimenttion of Google reCAPTCHA
# The reCAPTCHA documentation site describes more details and advanced configurations.
# https://developers.google.com/recaptcha/

use PlugNPay::AWS::ParameterStore;
use PlugNPay::ResponseLink;
use PlugNPay::UI::Template;
use JSON::XS;
use URI::Escape;
use strict;

our $PNP_RECAPTCHA_SITEKEY;
our $PNP_RECAPTCHA_SECRETKEY;

sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  if ((!$PNP_RECAPTCHA_SITEKEY) || (!$PNP_RECAPTCHA_SECRETKEY)) {
    my $keys = &PlugNPay::AWS::ParameterStore::getParameter('/PAY1/RECAPTCHA_KEYS');
    my $hashref = decode_json($keys);
    $PNP_RECAPTCHA_SITEKEY = $hashref->{'siteKey'};
    $PNP_RECAPTCHA_SECRETKEY = $hashref->{'secretKey'};
  }

  # Use this in the HTML code our site serves to users.
  $self->setSiteKey($PNP_RECAPTCHA_SITEKEY);

  # Use this for communication between our site and Google.
  $self->setSecretKey($PNP_RECAPTCHA_SECRETKEY);

  ## Ask Chris, Dave or James for the list of domains registered to our Google reCAPTCHA account.

  $self->{'err'} = '';

  return $self;
}


## required HTML code for the reCAPTCHA widget [both parts are required, for widget to appear]

sub headHTML {
  # place this snippet before the closing </head> tag on the HTML page
  my $self = shift;
  my $params = shift;

  my $head = new PlugNPay::UI::Template();
  $head->setCategory('/util/captcha/');
  if ($params->{'version'} == 2) {
    $head->setName('captcha2.head');
  } else {
    $head->setName('captcha.head');
  }
  return $head->render() . "\n";
}

sub formHTML {
  # place this snippet at the end of the <form> where you want the reCAPTCHA widget to appear
  my $self = shift;
  my $params = shift;

  my $content = new PlugNPay::UI::Template();
  $content->setCategory('/util/captcha/');
  if ($params->{'version'} == 2) {
    $content->setName('captcha2');
  } else {
    $content->setName('captcha');
  }
  $content->setVariable('sitekey', $self->getSiteKey());

  return $content->render() . "\n";
}


## validate a reCAPTCHA request 
sub isValid {
  # validates presented captcha information
  my $self = shift;
  my $merchant = shift;
  my $response = shift;
  my $ipaddress = shift;

  if ($ENV{'DEVELOPMENT'} eq "TRUE" && $ENV{'CAPTCHA_BYPASS'} eq 'TRUE') {
    print STDERR "CAPTCHA BYPASS ENABLED!!!\n";
    return 1;
  }

  if (!defined $merchant || $merchant eq '') {
    $self->{'err'} = 'Missing Username';
    return 0;
  }

  if (!defined $response || $response eq '') {
    $self->{'err'} = 'Missing Username';
    return 0;
  }

  if (!defined $ipaddress || $ipaddress eq '') {
    $self->{'err'} = 'Missing IP Address';
    return 0;
  }

  $self->setMerchant($merchant);
  $self->setResponse($response);
  $self->setIP($ipaddress);

  # When your users submit the form where you integrated reCAPTCHA, you'll get as part of the payload a string with the name "g-recaptcha-response".
  # In order to check whether Google has verified that user, send a POST request with these parameters:
  #
  # URL:  https://www.google.com/recaptcha/api/siteverify
  #
  # 'secret'   (required)  Insert our secret key here.
  # 'response' (required)  The value of 'g-recaptcha-response'.
  # 'remoteip' (optional)  The end user's ip address. [but highly recommended]
  #
  # The reCAPTCHA documentation site describes more details and advanced configurations.
  # https://developers.google.com/recaptcha/docs/verify

  my $url = 'https://www.google.com/recaptcha/api/siteverify';
  my $pairs = sprintf("remoteip=%s\&response=%s\&secret=%s", uri_escape($ipaddress), uri_escape($response), uri_escape($self->getSecretKey()));

  my $rl = new PlugNPay::ResponseLink($merchant, $url, $pairs, 'post', 'meta');
  $rl->doRequest();
  my $greply = $rl->getResponseContent();

  if ($greply ne '') {
    my $hashref = decode_json($greply);
    if ($hashref->{'success'}) {
      return 1;
    }
  }

  return 0;
}

sub getError {
  my $self = shift;
  return $self->{'err'};
}


### functions below this are really just for testing or internal use ###
sub getSiteKey {
  my $self = shift;
  return $self->{'_siteKey'};
}

sub setSiteKey {
  my $self = shift;
  my $sitekey = shift || undef;

  if (defined $sitekey) {
    $self->{'_siteKey'} = $sitekey;
    return 1;
  } 
  else {
    $self->{'err'} = 'Site Key Undefined';
    return 0;
  }
}


sub getSecretKey {
  my $self = shift;
  return $self->{'_secretKey'};
}

sub setSecretKey {
  my $self = shift;
  my $secretkey = shift || undef;

  if (defined $secretkey) {
    $self->{'_secretKey'} = $secretkey;
    return 1;
  }
  else {
    $self->{'err'} = 'Secret Key Undefined';
    return 0;
  }
}


sub getResponse {
  my $self = shift;
  return $self->{'g-recaptcha-response'};
}

sub setResponse {
  my $self = shift;
  my $response = shift || undef;

  if (defined $response) {
    $self->{'g-recaptcha-response'} = $response;
    return 1;
  }
  else {
    $self->{'err'} = 'reCAPTCHA Data Undefined';
    return 0;
  }
}


sub getIP {
  my $self = shift;
  return $self->{'ipaddress'};
}

sub setIP {
  my $self = shift;

  my $ipaddress = shift || undef;
  if (defined $ipaddress) {
    $ipaddress =~ s/[^0-9\.]//g;
    $self->{'ipaddress'} = $ipaddress;
    return 1;
  }
  elsif (defined $ENV{'REMOTE_ADDR'}) {
    $self->{'ipaddress'} = $ENV{'REMOTE_ADDR'};
    return 1;
  }
  else {
    $self->{'err'} = 'IP Address Undefined';
    return 0;
  }
}


sub getMerchant {
  my $self = shift;
  return $self->{'merchant'};
}

sub setMerchant {
  my $self = shift;

  my $merchant = shift || undef;
  if (defined $merchant) {
    $merchant =~ s/[^a-zA-Z0-9]//g;
    $self->{'merchant'} = $merchant;
    return 1;
  }
  else {
    $self->{'err'} = 'Username Undefined';
    return 0;
  }
}


1;
