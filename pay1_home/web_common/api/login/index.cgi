#!/bin/env perl

# accepts a csrf token and returns a new one, expiring the requested one in one minute.
use PlugNPay::CGI();
use CGI::Cookie;
use PlugNPay::Security::CSRFToken;
use PlugNPay::Authentication;
use JSON::XS ();

if (lc $ENV{'REQUEST_METHOD'} ne 'post') {
  print 'Content-type: application/json' . "\n\n";
  print JSON::XS::encode_json({'error' => "$ENV{'REQUEST_METHOD'} is not allowed."}) . "\n";
} else {
  my $cgi = new PlugNPay::CGI();
  my $content = $cgi->getRaw();
  my $data = {};

  eval {
    $data = JSON::XS::decode_json($content);
  };

  # check and replace CSRF token
  my $submittedToken = $cgi->http('X-Gateway-Request-Token');
  my $newTokenString = $submittedToken;
  
  if ($submittedToken ne '') {
    my $csrfToken = new PlugNPay::Security::CSRFToken();
    $csrfToken->setToken($submittedToken);
    
    if ($csrfToken->verifyToken()) {
      my $newToken = new PlugNPay::Security::CSRFToken();
      $newTokenString = $newToken->getToken();
    } else {
      print STDERR "Invalid token: $submittedToken\n";
    }
  }

  # get time remaining on login cookie
  my $timeRemaining = 900; # default to 15 minutes so no warnings display
  my $cookieName = $data->{'cookieName'};

  if ($cookieName ne '') {
    my %cookies = fetch CGI::Cookie;
    my $cookie = $cookies{$cookieName};
    if ($cookie) {
      my $auth = new PlugNPay::Authentication();
      $timeRemaining = $auth->getTimeRemaining({realm => $cookieName, cookie => $cookie->value});
    }
  }

  my $resp = {
    content => {
      data => {
        newToken => $newTokenString,
        loginTimeRemaining => $timeRemaining
      }
    }
  };

  print 'Content-type: application/json' . "\n\n";
  print JSON::XS::encode_json($resp) . "\n";
}
