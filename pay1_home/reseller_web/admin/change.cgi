#!/bin/env perl 

require 5.001;
$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use CGI;
use miscutils;
use PlugNPay::Util::Captcha::ReCaptcha;
use strict;

print "Content-Type: text/html\n\n";

my %query;
my $query = new CGI;

if (($ENV{'HTTP_X_FORWARDED_SERVER'} ne '') && ($ENV{'HTTP_X_FORWARDED_FOR'} ne '')) {
  $ENV{'HTTP_HOST'} = (split(/\,/,$ENV{'HTTP_X_FORWARDED_HOST'}))[0];
  $ENV{'SERVER_NAME'} = (split(/\,/,$ENV{'HTTP_X_FORWARDED_SERVER'}))[0];
}

## allow Proxy Server to modify ENV variable 'REMOTE_ADDR'
if ($ENV{'HTTP_X_FORWARDED_FOR'} ne '') {
  $ENV{'REMOTE_ADDR'} = $ENV{'HTTP_X_FORWARDED_FOR'};
}

my $reseller = $ENV{'REMOTE_USER'};

$query{'function'} = &CGI::escapeHTML(&clean_up($query->param('function')));
$query{'name'} = &CGI::escapeHTML(&clean_up($query->param('name')));
$query{'company'} = &CGI::escapeHTML(&clean_up($query->param('company')));
$query{'addr1'} = &CGI::escapeHTML(&clean_up($query->param('addr1')));
$query{'addr2'} = &CGI::escapeHTML(&clean_up($query->param('addr2')));
$query{'city'} = &CGI::escapeHTML(&clean_up($query->param('city')));
$query{'state'} = &CGI::escapeHTML(&clean_up($query->param('state')));
$query{'zip'} = &CGI::escapeHTML(&clean_up($query->param('zip')));
$query{'country'} = &CGI::escapeHTML(&clean_up($query->param('country')));
$query{'tel'} = &CGI::escapeHTML(&clean_up($query->param('tel')));
$query{'fax'} = &CGI::escapeHTML(&clean_up($query->param('fax')));
$query{'merchemail'} = &CGI::escapeHTML(&clean_up_email($query->param('merchemail')));
$query{'url'} = &CGI::escapeHTML(&clean_up_url($query->param('url')));

my $answer = $query->param('g-recaptcha-response');
$answer =~ s/[^a-zA-Z0-9\_\-]//g;

if ($ENV{'SEC_LEVEL'} ne '0') {
  &deny();
  exit;
}

my $captcha_message = '';
# the pnpdemo thing is probably useless
if (($query{'function'} eq 'update') && ($reseller !~ /^(pnpdemo|pnpdemo2)$/)) {
  my $captcha = new PlugNPay::Util::Captcha::ReCaptcha();
  if ($captcha->isValid($reseller, $answer, $ENV{'REMOTE_ADDR'})) {
    &update(%query);
    exit;
  }
  else {
    $captcha_message = 'Invalid CAPTCHA Answer';
  }
}
else {
  my $dbh = &miscutils::dbhconnect('pnpmisc');
  my $sth = $dbh->prepare(q{
      SELECT name,company,addr1,addr2,city,state,zip,country,tel,fax,merchemail
      FROM customers
      WHERE username=?
    }) or die "Can't prepare: $DBI::errstr";
  $sth->execute($reseller) or die "Can't execute: $DBI::errstr";
  ($query{'name'},$query{'company'},$query{'addr1'},$query{'addr2'},$query{'city'},$query{'state'},$query{'zip'},$query{'country'},$query{'tel'},$query{'fax'},$query{'merchemail'}) = $sth->fetchrow;
  $sth->finish;
  $dbh->disconnect;
}

&head();
 
print "<form method=post action=\"$ENV{'SCRIPT_NAME'}\">\n";
print "<table border=0 cellspacing=0 cellpadding=4>\n";
print "  <tr>\n";
print "    <th>Username:</th>\n";
print "    <td><b>$reseller</b></td>\n";
print "  </tr>\n";

print "  <tr>\n";
print "    <th>Contact:</th>\n";
print "    <td><input type=text name=\"name\" size=30 maxlength=40 value=\"$query{'name'}\"></td>\n";
print "  </tr>\n";

print "  <tr>\n";
print "    <th>Company:</th>\n";
print "    <td><input type=text name=\"company\" size=30 maxlength=40 value=\"$query{'company'}\"></td>\n";
print "  </tr>\n";

print "  <tr>\n";
print "    <th>Address 1:</th>\n";
print "    <td><input type=text name=addr1 size=30 maxlength=40 value=\"$query{'addr1'}\"></td>\n";
print "  </tr>\n";

print "  <tr>\n";
print "    <th>Address 2:</th>\n";
print "    <td><input type=text name=\"addr2\" size=30 maxlength=40 value=\"$query{'addr2'}\"></td>\n";
print "  </tr>\n";

print "  <tr>\n";
print "    <th>City, St Zip:</th>\n";
print "    <td><input type=text name=\"city\" size=20 maxlength=40 value=\"$query{'city'}\"> <b>,</b> <input type=text name=\"state\" size=3 maxlength=10 value=\"$query{'state'}\"> <input type=text name=\"zip\" size=10 maxlength=10 value=\"$query{'zip'}\"></td>\n";
print "  </tr>\n";

print "  <tr>\n";
print "    <th>Country:</th>\n";
print "    <td><input type=text name=\"country\" size=20 maxlength=20 value=\"$query{'country'}\"></td>\n";
print "  </tr>\n";

print "  <tr>\n";
print "    <th>Telephone #:</th>\n";
print "    <td><input type=tel name=\"tel\" size=20 maxlength=20 value=\"$query{'tel'}\"></td>\n";
print "  </tr>\n";

print "  <tr>\n";
print "    <th>Fax #:</th>\n";
print "    <td><input type=tel name=\"fax\" size=20 maxlength=20 value=\"$query{'fax'}\"></td>\n";
print "  </tr>\n";

if ($reseller !~ /^electro|paymentd|cblbanca$/) {
  print "  <tr>\n";
  print "    <th>Contact Email:</th>\n";
  print "    <td><input type=text name=\"merchemail\" size=30 maxlength=80 value=\"$query{'merchemail'}\"><br><i>If entering two email addresses, you must seperate them by a comma.</i></td>\n";
  print "  </tr>\n";
}

my $captcha = new PlugNPay::Util::Captcha::ReCaptcha();
print "  <tr>\n";
print "    <th>Captcha:<b>*</b></th>\n";
print "    <td>" . $captcha->formHTML() . "</td>\n";
print "  </tr>\n";

print "  <tr>\n";
print "    <th>&nbsp;</th>\n";
print "    <td><b><i>Upon clicking the 'Update Info' button, an email will be sent to the contact already on file to confirm the saving/changing of the contact information, even if no information has been changed.</i></b></td>\n";
print "  <tr>\n";

print "  <tr>\n";
print "    <th>&nbsp;</th>\n";
print "    <td><input type=submit value=\"Update Info\"> &nbsp; <input type=reset value=\"Reset Form\"></td>\n";
print "  </tr>\n";
print "</table>\n";

print "<input type=hidden name=\"function\" value=\"update\">\n";
print "<input type=hidden name=\"change\" value=\"0\">\n";
print "</form>\n";

print "<p>\n";

&tail();

exit;
 
sub update {
  my (%query) = @_;

  my $dbh = &miscutils::dbhconnect('pnpmisc');

  # update contact information
  if (($reseller !~ /^electro|paymentd|cblbanca$/)) {
    my $sth = $dbh->prepare(q{
        UPDATE customers
        SET name=?,company=?,addr1=?,addr2=?,city=?,state=?,zip=?,country=?,tel=?,fax=?,merchemail=?,url=?
        WHERE username=?
      }) or die "Can't prepare: $DBI::errstr";
    $sth->execute($query{'name'}, $query{'company'}, $query{'addr1'}, $query{'addr2'}, $query{'city'}, $query{'state'}, $query{'zip'}, $query{'country'}, $query{'tel'}, $query{'fax'}, $query{'merchemail'}, $query{'url'}, $reseller) or die "Can't execute: $DBI::errstr";
    $sth->finish;
  }
  else {
    my $sth = $dbh->prepare(q{
        UPDATE customers
        SET name=?,company=?,addr1=?,addr2=?,city=?,state=?,zip=?,country=?,tel=?,fax=?,url=?
        WHERE username=?
      }) or die "Can't prepare: $DBI::errstr";
    $sth->execute($query{'name'}, $query{'company'}, $query{'addr1'}, $query{'addr2'}, $query{'city'}, $query{'state'}, $query{'zip'}, $query{'country'}, $query{'tel'}, $query{'fax'}, $query{'url'}, $reseller) or die "Can't execute: $DBI::errstr";
    $sth->finish;
  }

  $dbh->disconnect;

  &genhtml();
}


sub genhtml {
  &head();
  print "<div align=center>\n";
  print "<br><b>The Update Completed Normally</b>\n";
  print "<p><form><input type=button value=\"Close Window\" onClick=\"window.close();\"></form>\n";
  print "<br>&nbsp;\n";
  print "</div>\n";
  &tail();
}

sub deny {
  &head();
  print "<div align=center>\n";
  print "<br>You are not authorized to edit this information.<br>\n";
  print "<form><input type=button value=\"Close Window\" onClick=\"window.close();\"></form>\n";
  print "</div>\n";
  &tail();
}

sub head {
  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Edit Contact Information</title>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"/css/green.css\">\n";

  print "<script type=\"text/javascript\">\n";
  print "<!-- //\n";

  print "function change_win(helpurl,swidth,sheight,windowname) {\n";
  print "  SmallWin = window.open(helpurl, windowname,'scrollbars=yes,resizable=yes,status=yes,toolbar=yes,menubar=yes,height='+sheight+',width='+swidth);\n";
  print "}\n";

  print "function closewin() {\n";
  print "  self.close();\n";
  print "}\n";

  print "// -->\n";
  print "</script>\n";

  my $captcha = new PlugNPay::Util::Captcha::ReCaptcha();
  print $captcha->headHTML();

  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";

  print "<table>\n";
  print "  <tr>\n";
  print "    <td><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Payment Gateway Logo\" /></td>\n";
  print "    <td class=\"right\">&nbsp;</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td colspan=2><img src=\"/adminlogos/masthead_background.gif\" alt=\"Corp. Logo\" width=750 height=16 /></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table border=0 cellspacing=0 cellpadding=5 width=760>\n";
  print "  <tr>\n";
  print "    <td colspan=2><h1>Edit Contact Information</h1> <div class=\"badcolor\">$captcha_message</div></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "  <hr id=\"under\" />\n";

  print "<table border=0 cellspacing=0 cellpadding=5 width=760>\n";
  print "  <tr>\n";
  print "    <td colspan=2>";

  return;
}

sub tail {
  my @now = gmtime(time);
  my $copy_year = $now[5]+1900;

  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<hr id=\"over\">\n";

  print "<table class=\"frame\">\n";
  print "  <tr>\n";
  print "    <td class=\"left\"><a href=\"/admin/logout.cgi\" title=\"Click to log out\">Log Out</a> | <a id=\"close\" href=\"javascript:closewin();\" title=\"Click to close this window\">Close Window</a></td>\n";
  print "    <td class=\"right\">\&copy; $copy_year, ";
  if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
    print "Plug and Pay Technologies, Inc.";
  }
  else {
    print "$ENV{'SERVER_NAME'}";
  }
  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</body>\n";
  print "</html>\n";

  return;
}

sub clean_up {
  my ($value) = @_;
  $value =~ s/[^a-zA-Z0-9\@\.\-\s]//g;
  return $value;
}

sub clean_up_url {
  my ($value) = @_;
  $value =~ s/[^a-zA-Z0-9\@\.\-\\\/\:]//g;
  return $value;
}

sub clean_up_email {
  my ($value) = @_;
  $value =~ s/[^a-zA-Z0-9\@\.\-\_\,]//g;
  return $value;
}

