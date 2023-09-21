package billpay_security;

require 5.001;
$| = 1;

use billpay_adminutils;
use DBI;
use miscutils;
use SHA;
use CGI;
use PlugNPay::Email;
use strict;

sub new {
  my $type = shift;

  ## allow Proxy Server to modify ENV variable 'REMOTE_ADDR'
  if ($ENV{'HTTP_X_FORWARDED_FOR'} ne '') {
    $ENV{'REMOTE_ADDR'} = $ENV{'HTTP_X_FORWARDED_FOR'};
  }

  ($billpay_security::source) = @_;

  my $data = new CGI;

  %billpay_security::feature = ();

  @billpay_security::new_areas = ();

  my @params = $data->param();
  my $datetime = gmtime(time);
  print DEBUG "DATE:$datetime, UN:$billpay_security::login, FUNC:$billpay_security::function, RU:$ENV{'REMOTE_USER'}, IP:$ENV{'REMOTE_ADDR'}, ";
  foreach my $param (@params) {
    print DEBUG "$param:" . &CGI::escapeHTML($data->param($param)) . ", ";
  }
  print DEBUG "\n";
  close (DEBUG);

  %billpay_security::areas = ('/billpay','ADMIN');

  return [], $type;
}

sub delete_acl {
  my ($login) = @_;

  my $dbh = &miscutils::dbhconnect('billpres');

  my $sth = $dbh->prepare(q{
      DELETE FROM acl_login
      WHERE login=?
      AND username=? 
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute("$login", "$login") or die "Can't execute: $DBI::errstr";
  $sth->finish;

  my $sth1 = $dbh->prepare(q{
      DELETE FROM acl_dir
      WHERE login=? 
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth1->execute("$login") or die "Can't execute: $DBI::errstr";
  $sth1->finish;

  &log_acl($login, $login, 'delete login', $dbh);

  $dbh->disconnect;
}

# used to update or insert users into acl
sub update_acl {
  my ($login,$password,$directory,$oldpassword,$tempflag) = @_;

  my $sha1 = new SHA;
  $sha1->reset;
  $sha1->add($password);
  my $encpassword = $sha1->hexdigest();
  $sha1->reset;
  $sha1->add($oldpassword);
  my $encoldpassword = $sha1->hexdigest();
  my $pwtype = 'sha1';

  my $dbh = &miscutils::dbhconnect('billpres');
  my $sth = $dbh->prepare(q{
      SELECT login, password, username, pwtype, tempflag
      FROM acl_login 
      WHERE login=? 
    }) or die "Can't prepare: $DBI::errstr";
  $sth->execute("$login") or die "Can't execute: $DBI::errstr";
  my $data = $sth->fetchrow_hashref();
  $sth->finish;

  if (($data->{'password'} eq $encpassword) && ($encpassword eq $encoldpassword)) {
    # user exists but password hasn't changed just move along nothing to see here.
  }
  elsif (($data ne '') && ($oldpassword ne '') && ($data->{'password'} eq $encoldpassword)) {
    # update the user if it exists and an old password was provided and it matches
    my $sth = $dbh->prepare(q{
        UPDATE acl_login
        SET password=?, pwtype=?, tempflag=?
        WHERE login=?
      }) or die "Can't prepare: $DBI::errstr";
    $sth->execute("$encpassword", "$pwtype", "$tempflag", "$login") or die "Can't execute: $DBI::errstr";
    $sth->finish;

    # log change
    &log_acl($login, $login, 'update password', $dbh);
  }
  elsif ($data->{'login'} eq '') {
    # user doesn't exist so it's ok to insert
    my $sth = $dbh->prepare(q{
        INSERT INTO acl_login
        (username,password,seclevel,login,pwtype,tempflag,subacct)
        VALUES (?,?,?,?,?,?,?)
      }) or die "Can't prepare: $DBI::errstr";
    $sth->execute("$login", "$encpassword", '0', "$login", "$pwtype", "$tempflag", '');
    $sth->finish;

    &log_acl($login, $login, 'add login', $dbh);

    my $sth2 = $dbh->prepare(q{
        INSERT INTO acl_dir
        (login,directory)
        VALUES (?,?)
      }) or die "Can't prepare: $DBI::errstr";
    $sth2->execute("$login", "$directory");
    $sth2->finish;

    &log_acl($login, $login, "add directory for login $directory", $dbh);
  }
  else {
    # the user existed but the passwords do not match
    $dbh->disconnect;
    return 0;
  }
  $dbh->disconnect;

  return 1;
}

# used to log changes to acl
sub log_acl {
  my ($login, $username, $action, $dbh) = @_;

  my $sth1 = $dbh->prepare(q{ 
      INSERT INTO acl_changelog
      (login, username, trans_time, action, ipaddress)
      VALUES (?,?,?,?,?)
    }) or die "Can't prepare: $DBI::errstr";

  #get current date and time to input into the changelog      
  my ($dummy1, $dummy2, $currentdatetime) = &miscutils::gendatetime();

  $sth1->execute("$login", "$username", "$currentdatetime", "$action", "$ENV{'REMOTE_ADDR'}") or die("Can't execute: $DBI::errstr");
  $sth1->finish;      

  return;
}

sub log_in_cookie {
  my ($action, $destination, $message) = @_;

  &billpay_adminutils::head_login();
  print "</td></tr></table>\n";

  print "<form method=post action=\"$action\">\n";
  print "<input type=hidden name=\"destination\" value=\"$destination\">\n";

  print "<table width=760 border=0 cellpadding=3 cellspacing=0>\n";
  if ($message ne '') {
    print "  <tr>\n";
    print "    <td align=center colspan=3>$message</td>\n";
    print "  </tr>\n";
  }

  print "  <tr>\n";
  print "    <td align=center colspan=3>&nbsp;</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th align=right>Email Login:</th>\n";
  print "    <td colspan=2><input name=\"credential_0\" type=text size=16 maxlength=255 required></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th align=right>Password:</th>\n";
  print "    <td colspan=2><input name=\"credential_1\" type=password size=16 maxlength=255 required></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"leftside\">\&nbsp\;</th>\n";
  print "    <td colspan=2><input type=submit class=\"button\" value=\" &nbsp; Log In &nbsp; \"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=center colspan=3>&nbsp;</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=center colspan=3><a href=\"/billpay_signup.cgi\?merchant=$billpay_language::query{'merchant'}\">Click Here To Sign-Up For Free</a></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=center colspan=3><a href=\"/billpay_lostpass.cgi\?merchant=$billpay_language::query{'merchant'}\">Click Here If You Lost Your Password</a></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</form>\n";

  &billpay_adminutils::tail();
}

sub log_out_cookie {
  my $action = '';
  my $destination = '';

  if ($ENV{'REQUEST_URI'} =~ /\/eadmin\//) {
    $action = '/ADMIN';
    $destination = '/eadmin/';
  }
  elsif ($ENV{'REQUEST_URI'} =~ /\/ecard\//) {
    $action = '/ECARD';
    $destination = '/ecard/';
  }
  elsif ($ENV{'REQUEST_URI'} =~ /\/billpay\//) {
    $action = '/BILLPAY';
    $destination = '/billpay/';
  }

  &log_in_cookie($action, $destination, "<H4>You have been logged out.</H4>\n");
}

sub login_change_form {
  my (%query) = @_;

  &billpay_adminutils::head();

  print "<h1><a href=\"$billpay_adminutils::path_index\">$billpay_language::lang_titles{'service_title'}</a> / Update Login Info</h1>\n";

  print "<p>";
  if ($ENV{'TEMPFLAG'} == 1) {
    print "<font size=\"+1\">Your login password is flagged as temporary & must be changed.</font>\n";
    print "<br>&nbsp;<br>";
  }
  print "Please enter your current password \& the new password you would like to use below.</font>\n";
  print "<br>This will be used to update your login information to the $billpay_language::lang_titles{'service_title'} administration area.</p>\n";

  if ($query{'error_message'} ne '') {
    print "<p><font color=\"#CC0000\" size=\"+1\">$query{'error_message'}</font></p>\n";
  }

  print "<form action=\"$ENV{'SCRIPT_NAME'}\" method=post>\n";
  print "<input type=hidden name=\"function\" value=\"update_login\">\n";

  print "<br><table border=0>\n";
  print "  <tr>\n";
  print "    <td valign=top><p>Current Password: </p></td>\n";
  print "    <td><p><input type=text name=\"oldpassword\" value=\"$query{'oldpassword'}\" autocomplete=\"off\" required></p></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=top><p>New Password: </p></td>\n";
  print "    <td><p><input type=password name=\"password\" value=\"$query{'password'}\" required>\n";
  print "<br><i>Minimum COMBINATION of 8 Letters and Numbers Required.</i>\n";
  print "<br>[NO Spaces or Non-Alphanumeric Characters Permitted.]\n";
  print "</p></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=top><p>Confirm New Password: </p></td>\n";
  print "    <td><p><input type=password name=\"password2\" value=\"$query{'password2'}\" required></p></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=2 align=center><p><input type=submit class=\"button\" name=\"submit\" value=\"Update Login\"></p></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</form>\n";

  print "<blockquote><p><font color=\"#ff0000\"><b>IMPORTANT NOTE:</b></font><br>If your newly submitted password is accepted, you will be immediatly logged out.<br>You will need login with your new password to proceed.</p></blockquote>\n";

  &billpay_adminutils::tail();

  return;
}

sub update_login {
  my ($type, %query) = @_;

  # login password filter
  $query{'oldpassword'} =~ s/[^0-9a-zA-Z]//g;
  $query{'password'} =~ s/[^0-9a-zA-Z]//g;
  $query{'password2'} =~ s/[^0-9a-zA-Z]//g;

  if ($ENV{'REMOTE_USER'} =~ /^(trash\@plugnpay.com)$/i) {
    $query{'error_message'} = "Sorry, you cannot change the password on this account.";
    &login_change_form(%query);
    return;
  }

  # verify login email & password are filled in
  if ($query{'oldpassword'} eq '') {
    $query{'error_message'} = "Current password required. Please try again.";
    &login_change_form(%query);
    return;
  }
  elsif ($query{'password'} eq '') {
    $query{'error_message'} = "New Password required. Please try again.\n";
    &login_change_form(%query);
    return;
  }
  elsif ($query{'password2'} eq '') {
    $query{'error_message'} = "Confirm password required. Please try again.";
    &login_change_form(%query);
    return;
  }
  elsif ($query{'password'} ne $query{'password2'}) {
    $query{'error_message'} = "Passwords do not match. Please try again.\n";
    &login_change_form(%query);
    return;
  }

  # enforce min password length requirement
  if (length($query{'password'}) < 8) {
    $query{'error_message'} = "Password must be at least 8 characters long. Please try again.\n";
    &login_change_form(%query);
    return;
  }
  elsif ($query{'password'} !~ /[a-zA-Z]/) {
    $query{'error_message'} = "Password must contain at least 1 letter. Please try again.\n";
    &login_change_form(%query);
    return;
  }
  elsif ($query{'password'} !~ /[0-9]/) {
    $query{'error_message'} = "Password must contain at least 1 number. Please try again.\n";
    &login_change_form(%query);
    return;
  }

  $query{'login'} = $ENV{'REMOTE_USER'};
  $query{'directory'} = '/billpay';
  $query{'tempflag'} = '';

  # register login password
  my $result = &update_acl("$query{'login'}", "$query{'password'}", "$query{'directory'}", "$query{'oldpassword'}", "$query{'tempflag'}");

  if ($result == 1) {
    #&billpay_adminutils::head();
    #my $message = "<p><font size=\"+1\">Your login info has been updated.</font>\n";
    #$message .= "<br>You will need to login with your new password to proceed.</p>\n";
    #$message .= "<br><a href=\"https://$ENV{'SERVER_NAME'}/billpay/index.cgi\">Click Here To Login</a>\n";
    #print $message;
    #&billpay_adminutils::tail();

    &send_login_update_email("$ENV{'REMOTE_USER'}");

    #print "Content-Type: text/html\n\n";
    print "Location: https://$ENV{'SERVER_NAME'}/billpay/logout.cgi\n\n";
    exit;
  }
  else {
    $query{'error_message'} = "Login update failed. Please try again.";
    &login_change_form(%query);
  }

  return;
}

sub send_login_update_email {
  # send the billing presentment login info update notification email
  my ($db_username) = @_;

  my $merchant = 'unknown';
  my $merchant_email = "billpaysupport\@plugnpay.com";

  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setFormat('text');
  $emailObj->setFrom($merchant_email);
  $emailObj->setSubject("$billpay_language::lang_titles{'service_title'} Login Updated");

  # create login update email
  my $emailmessage = '';
  $emailmessage .= "Thank you for recently updating your account's login info.\n\n";
  $emailmessage .= "You may now go to the below URL to login using your new login info.\n";
  $emailmessage .= "\n";
  $emailmessage .= "https://$ENV{'SERVER_NAME'}/billpay/index.cgi\n";
  $emailmessage .= "\n";
  $emailmessage .= "For assistance or if you have questions on this, please ";
  $emailmessage .= "contact $merchant_email.\n";
  $emailmessage .= "\n";

  $emailmessage .= "When contacting us, please refer your account:\n";
  $emailmessage .= "Service: $billpay_language::lang_titles{'service_title'}\n";
  $emailmessage .= "Email:   $db_username\n";
  $emailmessage .= "\n";
  $emailmessage .= "Thank you,\n";
  $emailmessage .= "$billpay_language::lang_titles{'service_title'} Support Staff\n";

  $emailObj->setContent($emailmessage);
  $emailObj->send();

  return;
}

