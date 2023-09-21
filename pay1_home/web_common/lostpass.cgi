#!/usr/bin/perl

use strict;

use lib $ENV{'PNP_PERL_LIB'};
use CGI;
use HTML::Entities;
use SHA;
use miscutils;
use Time::Local;
use PlugNPay::Authentication::Login;
use PlugNPay::Email;
use PlugNPay::Username;
use PlugNPay::Reseller;
use PlugNPay::GatewayAccount;
use PlugNPay::Password::Reset;
use PlugNPay::Util::RandomString;
use PlugNPay::Util::Array qw(inArray);

my $self = "/lostpass.cgi";

my $notifylist = 'lostpass-warning@plugnpay.com';

# MAIN PART OF SCRIPT
my $query = new CGI;
eval {
  my $loginType = $query->param("loginType");

  my @loginTypes = ('reseller','merchant');
  if (!inArray($loginType,\@loginTypes)) {
    $loginType = 'merchant';
  }

  if (&CGI::escapeHTML($query->param("function")) eq "sendconfirmation") {
    &sendconfirmation(&CGI::escapeHTML($query->param("username")),&CGI::escapeHTML($query->param("email")),$loginType);
  }
  elsif (&CGI::escapeHTML($query->param("function")) eq "confirm") {
    &confirm(&CGI::escapeHTML($query->param("id")));
  }
  elsif (&CGI::escapeHTML($query->param("function")) eq "redirect") {
    &redirect();
  }
  else {
    &head("Request New Password");
    &lostpass_form($loginType);
    &tail();
  }
};

if ($@) {
  print STDERR $@;
  &head("An error occurred, our engineers have been notified.");
  &tail();
}
# END MAIN PART OF SCRIPT

exit;


# SUBROUTINES
sub head {
  my ($message) = @_;
  if (!($message eq "")) {
    $message = " - " . $message;
  }

  print "Content-Type: text/html\n\n";
  print <<EOF;
<html>
<head>
<title>Merchant Administration Area$message</title>
<link href="/css/style_security.css" type="text/css" rel="stylesheet">
</head>
<body bgcolor="#ffffff" alink="#ffffff" link="#ffffff" vlink="#ffffff">
<div align="center">
<table cellspacing="0" cellpadding="4" border="0">
  <tr>
    <td align="center" colspan="2"><img src="/adminlogos/pnp_admin_logo.gif" alt="Corp. Logo"></td>
  </tr>
</table>
EOF
}

sub tail() {
  print "  </body>\n";
  print "</html>\n";
}


# Sends a confirmation to the user requesting the password change
sub sendconfirmation() {
  my ($loginUsername, $inputEmailAddress, $loginType) = @_;

  $loginUsername =~ s/[^a-zA-Z0-9]//g;
  $loginUsername =~ tr/A-Z/a-z/;
  if ($loginUsername eq "") {
    $loginUsername = "[NO_USERNAME]";
  }

  $inputEmailAddress =~ s/[^a-zA-Z0-9\_\-\@\.\,\+]//g;
  $inputEmailAddress = lc $inputEmailAddress;

  my $env = new PlugNPay::Environment();
  my $ip = $env->get('PNP_CLIENT_IP');

  my $encodedLoginUsername =  encode_entities($loginUsername);
  my $encodedInputEmailAddress = encode_entities($inputEmailAddress);

  &log("$encodedLoginUsername attempting to recover password with email: $encodedInputEmailAddress");

  my $knownEmailAddresses = [];

  my $reset = new PlugNPay::Password::Reset();
  eval {
    $knownEmailAddresses = $reset->getLoginEmailAddresses($loginUsername);
  };

  if($@) {
    &log("failed to load known email address for $encodedLoginUsername: $@");
    &problem();
    return;
  }

  if (@{$knownEmailAddresses} > 0) {
    &log("$encodedLoginUsername found sub_emails: " . join(',',@{$knownEmailAddresses}));
  }

  if (!inArray(lc $inputEmailAddress,$knownEmailAddresses)) {
    &log("$encodedLoginUsername did not match email: $encodedInputEmailAddress");

    &head("Bad User");
    print "<p class=\"error_text\">User does not exist with specified email address</p>";
    &tail();

    #notify chris, michelle, and barbara of failed password recovery attempt

    my $emailObj = new PlugNPay::Email();
    $emailObj->setTo($notifylist);
    $emailObj->setFrom('support@plugnpay.com');
    $emailObj->setVersion('legacy');
    $emailObj->setSubject("Subject: Password Recovery Failure - $loginUsername");
    $emailObj->setContent("Note: partial email match\n\n
		     Username: $loginUsername\n
	             Email Used: $inputEmailAddress\n
		     Remote Address: $ip\n
                           View at: https://pay1.plugnpay.com/private/cpwr.cgi?username=$loginUsername\n");
    $emailObj->setFormat('text');
    my $status = $emailObj->send();

    if(!$status) {
      &log("Email did not send - username $encodedLoginUsername with email $encodedInputEmailAddress, error: " . $status->getError()); # log this
    }

    return;
  }

  #username exists with specified email address
  # check for admin priv
  my $un = new PlugNPay::Username($loginUsername);
  my $hasAdminAccess = $un->canAccess('/admin');

  if(!$hasAdminAccess) {
    &log("login $encodedLoginUsername does not have admin access"); # log this
    userDoesNotHaveAdminAccess($loginUsername,$inputEmailAddress);
    return;
  }

  goodUser($loginUsername,$inputEmailAddress,$loginType);
}

sub goodUser {
  my $loginUsername = shift;
  my $inputEmailAddress = shift;
  my $loginType = shift;

  # means they do have privileges, send link
  my $reset = new PlugNPay::Password::Reset($loginType);
  my $env = new PlugNPay::Environment();
  my $ip = $env->get('PNP_CLIENT_IP');
  eval {
    $reset->sendResetConfirmation({
      loginUsername => $loginUsername,
      emailAddress => $inputEmailAddress,
      ip => $ip
    });

    my $encodedLoginUsername =  encode_entities($loginUsername);
    my $encodedInputEmailAddress = encode_entities($inputEmailAddress);

    &log("$encodedLoginUsername was sent password recovery link/temporary password: $encodedInputEmailAddress");
    &head("Email Confirmation Sent");
    print "<p>Check your email for a link to confirm your password change.<br>The link will expire in 3 hours</p>";
    &tail();
  };

  if($@) {
    &log($@);
    &problem();
  }
}


sub userDoesNotHaveAdminAccess {
  my $loginUsername = shift;
  my $inputEmailAddress = shift;

  my $encodedLoginUsername =  encode_entities($loginUsername);
  my $encodedInputEmailAddress = encode_entities($inputEmailAddress);

  &head("Bad User");
  &log("$encodedLoginUsername requested password recovery without admin privs: $encodedInputEmailAddress");
  print "<p class=\"error_text\">User specified does not have admin privileges</p>";
  &tail();

  my $emailObj = new PlugNPay::Email();
  $emailObj->setTo($notifylist);
  $emailObj->setFrom('support@plugnpay.com');
  $emailObj->setVersion('legacy');
  $emailObj->setSubject("Subject: Password Recovery Failure - $loginUsername");
  $emailObj->setContent("Note: administration privileges not granted for this username\n\n
               Username: $loginUsername\n
             Email Used: $inputEmailAddress\n
       Remote Address: $ENV{'REMOTE_ADDR'}\n
                         View at: https://pay1.plugnpay.com/private/cpwr.cgi?username=$loginUsername\n");
  $emailObj->setFormat('text');
  my $status = $emailObj->send();
}

sub invalidEmail {
  my $loginUsername = shift;
  my $inputEmailAddress = shift;

  my $encodedLoginUsername =  encode_entities($loginUsername);
  my $encodedInputEmailAddress = encode_entities($inputEmailAddress);

  #user does not exist with specified email address
  &head("Bad User");
  &log("$encodedLoginUsername did not match email: $encodedInputEmailAddress");
  print "<p class=\"error_text\">User does not exist with specified email address</p>";
  &tail();

  #notify chris, michelle, and barbara of failed password recovery attempt
  my $emailObj = new PlugNPay::Email();
  $emailObj->setTo($notifylist);
  $emailObj->setFrom('support@plugnpay.com');
  $emailObj->setVersion('legacy');
  $emailObj->setSubject("Subject: Password Recovery Failure - $loginUsername");
  $emailObj->setContent("Note: email address did not match an email on record for this username or username does not exist\n\n
             Username: $loginUsername\n
             Email Used: $inputEmailAddress\n
       Remote Address: $ENV{'REMOTE_ADDR'}\n
                         View at: https://pay1.plugnpay.com/private/cpwr.cgi?username=$loginUsername\n");
  $emailObj->setFormat('text');
  $emailObj->send(); # ignore failures here TODO add logging in the future
}

# User visits link, this is executed.  Creates and emails temp password, sets
# tempflag to 1, as well as sets the pwtype to "sha1".  then the script redirects the
# user to the admin section, where they login with the new password and must
# change it (due to the temppass flag being set)
sub confirm {
  my $confirmationId = shift;

  my $env = new PlugNPay::Environment();
  my $ip = $env->get('PNP_CLIENT_IP');

  my $reset = new PlugNPay::Password::Reset();
  my $result;
  eval {
    $result = $reset->confirmLinkIdAndSendNewPassword({ confirmationId => $confirmationId, ip => $ip });
    if (!$result->{'success'}) {
      &head("Invalid Link");
      print "<p class=\"error_text\">This link has expired or does not exist.</p>";
      &tail();
      return;
    }
  };

  my $error = $@ || "Unknown error";

  if ($@ || !$result->{'emailStatus'}) {
    &log("error sending email: " . $error);
  }

  displayConfirmation($result->{'loginUsername'});
}

sub clearcookie {
  %main::query = ();
  $main::query = new CGI;

  my $env = new PlugNPay::Environment();
  my $servername = $env->get('PNP_SERVER_NAME');

  $servername =~ /(\w+)\.(\w+)\.(\w+)/;
  my $cookiehost = "\.$2\.$3";

  print "Set-Cookie: loginattempts=; path=/; expires=Fri, 01-Jul-11 23:00:00 GMT; domain=$cookiehost;\n";
}



sub displayConfirmation {
  my ($loginUsername) = @_;

  &clearcookie();

  print "Content-Type: text/html\n\n";
  print <<"EOF";
<html>
<head>
<META HTTP-EQUIV="CACHE-CONTROL" content="NO-CACHE">
<META HTTP-EQUIV="refresh" content="300;URL=/admin/">
<title>Merchant Administration Area - Redirecting...</title>
<link href="/css/style_security.css" type="text/css" rel="stylesheet">
</head>
<body bgcolor="#ffffff" alink="#000" link="#000" vlink="#000">
<div align="center">
<table cellspacing="0" cellpadding="4" border="0">
  <tr>
    <td align="center" colspan="2"><img src="/adminlogos/pnp_admin_logo.gif" alt="Corp. Logo"></td>
  </tr>
</table>
<p>Your new temporary password has been emailed to you.</p>
</div>
</body>
</html>
EOF
}

sub problem {
  &head("Problem");
  print "<p class=\"error_text\">There was a problem processing your request.  Please try again later or contact tech support for further assistance.</p>";
  &tail();
}

sub log {
  my ($message) = @_;
  eval {
    my $date = localtime(time);
    chomp $date;
    my $ip = $ENV{'REMOTE_ADDR'};
    open("LOGFILE",">> /home/p/pay1/logs/lostpass.cgi.log");
    print LOGFILE "$date : $ip : $message\n";
    close("LOGFILE");
  }
}


sub lostpass_form {
  my ($loginType) = @_;

  print <<"EOF";
<script type='text/javascript' src='/javascript/jquery.min.js'></script>
<script type='text/javascript' src='/javascript/page_lostpass.js'></script>


<div align='center'>
<p><h1>Forgot your password?</h1>


<p>To reset your password, please provide the following information and we&lsquo;ll help you get into your account.

<p>Type in the email address & login username associated with your account.</p>

<form method='post' action='$self' name='lostpass' id='lostpassForm' >
<input type="hidden" name="function" value="sendconfirmation">
<input type="hidden" name="loginType" value="$loginType">

<table border=0 cellspacing=0 cellpadding=2>
  <tr>
    <td align=right><b>Email Address:</b></td>
    <td align=left><input type="text" name="email" id='emailAddress' value="" size=30 maxlength=255></td>
  </tr>
  <tr>
    <td align=right><b>Login Username:</b></td>
    <td align=left><input type="text" name="username" id='username' value="" size=20 maxlength=255></td>
  </tr>

  <tr>
    <td align=right>&nbsp;</td>
    <td align=left>&nbsp;</td>
  </tr>

  <tr>
    <td colspan=2 align=center><input id='submitButton' type="button" value="Submit Password Request"></td>
  </tr>
</table>

<br>A new temporary password will be emailed to you in a few minutes.

</form>
</div>
EOF

  return;
}
