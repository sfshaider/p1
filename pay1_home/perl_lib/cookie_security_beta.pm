#!/usr/local/bin/perl

#$| = 1;

package cookie_security;

use CGI;
use strict;

sub new {
  my $type = shift;

  ($cookie_security::source) = @_;

  my $data = new CGI;

  %cookie_security::feature = ();

  @cookie_security::new_areas = ();

  my @params = $data->param();
  my $datetime = gmtime(time());

  %cookie_security::areas = ('/','ADMIN');

  return [], $type;
}

sub log_in_cookie {
  my ($action, $destination, $message) = @_;

  if (($destination =~ /ADMIN/) || ($destination eq "")) {
    $destination = "/admin/";
  }

  $ENV{'HTTP_HOST'} = (split(/\,/,$ENV{'HTTP_X_FORWARDED_HOST'}))[0];  #### DCP 20100713

  &displayHTML($action,$destination,$message);
}


# new login html function - cbi 2011-08-02
sub displayHTML {
  my ($action,$destination,$message) = @_;

  my $css;

  # determine what type of message shoud be displayed, an error, or normal message
  if ($message ne "") {
    if ($message =~ /password/i) {
      $css = 'h2.error { display: block }';
    } else {
      $css = 'h2.message { display: block }';
    }
  }

  # print the html
  print qq\
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">

<html>
  <head>
  <meta name="viewport" content="width=device-width,user-scalable=no">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <link type="text/css" rel='stylesheet' href='/css/login.css'>
    <title>Merchant Administration Area</title>
    <META HTTP-EQUIV="CACHE-CONTROL" CONTENT="NO-CACHE">
    <META HTTP-EQUIV="PRAGMA" CONTENT="NO-CACHE">
    <script type="text/javascript">
      function validateloginform()
      {
        if (document.loginform.credential_0.value == "" || document.loginform.credential_1.value == "")
        {
          alert("A Username and Password are required.");
          return false;
        }
        else
        {
          return true;
        }
      }
    </script>
    <style type='text/css'>
    $css
    </style>
  </head>
        <body bgcolor="#ffffff" alink="#ffffff" link="#ffffff" vlink="#ffffff" onLoad="document.loginform.credential_0.focus()">
                <div id='loginArea' class='center'><div id='form' class='center'>
                        <img id='logo' src='/adminlogos/pnp_admin_logo.gif' class='center' alt='Logo'>
                        <h2 class='error'>Error: $message</h2>
                        <h2 class='message'>$message</h2>
                        <form method='post' action='$action' name='loginform' onsubmit='return validateloginform()'>
                                <div class='loginItem graybg'>
                                        <label for='credential_0'>Username:</label>
                                        <input type='text' name='credential_0' id='username' class='loginInput'>
                                </div>
                                <div class='loginItem graybg'>
                                        <label for='credential_1'>Password:</label>
                                        <input type='password' name='credential_1' id='password' class='loginInput'>
                                </div>
                                <div class='loginItem'>
                                        <input type='submit' id='submit' class='loginSubmit center' value='Log In'>
                                </div>
                                <div class='loginItem'><a href='/lostpass.cgi'>Forgot your password?</a></div>
				<input type='hidden' name='destination' value='$destination'>

                        </form>

                        </div>
                </div>
        </body>
</html>\;
}

sub log_out_cookie {
  my ($action,$destination) = @_;

  # removed p tag and new line from this message - cbi 2011-08-02
  &log_in_cookie($action, $destination, "You have been logged out.");
}

1;
