package billpay_adminutils;

require 5.001;

use pnp_environment;
use CGI;
use CGI::Cookie;
use miscutils;
use billpay_security;
use PlugNPay::Util::Captcha::ReCaptcha;
use PlugNPay::Email;
use strict;

require billpay_editutils; # for all sub function calls to menu & response screens database query stuff

# Purpose: billpay card issuer admin area interface
#          This lib is for all billpay admin area menus, interfaces & response screens
#          For all billpay database queries/updates, you should put them in 'billpay_edituils.pm'.

sub new {
  my $type = shift;

  %billpay_adminutils::query = @_;

  #$billpay_adminutils::dbh = &miscutils::dbhconnect("billpres");

  $billpay_adminutils::path_index = "index.cgi";
  $billpay_adminutils::path_edit = "edit.cgi";
  $billpay_editutils::path_logout = "logout.cgi";

  return [], $type;
}

sub head {
  my ($path_index, $path_logout);

  if ($billpay_adminutils::path_index eq "") {
    $path_index = "index.cgi";
  }
  else {
    $path_index = $billpay_adminutils::path_index;
  }

  if ($billpay_adminutils::path_logout eq "") {
    $path_logout = "logout.cgi";
  }
  else {
    $path_logout = $billpay_adminutils::path_logout;
  }

  # figure out cobrand stuff...
  my ($cobrand_title, $cobrand_logo, $cookie_set) = &cobrand_check();

  if ($cookie_set ne "yes") {
    # do not apply 'X-Content-Type-Options' & 'X-Frame-Options' for this script, as it breaks the success-link callbacks
    print "Content-Type: text/html\n\n";
  }

  if ($billpay_language::template{'doctype'} ne '') {
    print "$billpay_language::template{'doctype'}\n";
  }
  else {
    print "<!DOCTYPE html>\n";
  }
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>$billpay_language::lang_titles{'service_title'}</title>\n";
  print "<meta http-equiv=\"CACHE-CONTROL\" content=\"NO-CACHE\">\n";
  print "<meta http-equiv=\"PRAGMA\" content=\"NO-CACHE\">\n";
  print "<link rel=\"shortcut icon\" href=\"favicon.ico\">\n";

  $main::query{'merchant'} =~ s/[^a-zA-Z0-9]//g;
  $main::query{'merchant'} = lc("$main::query{'merchant'}");
  my $path_web = &pnp_environment::get('PNP_WEB');
  if (-e "$path_web/logos/upload/css/$main::query{'merchant'}\.css") {
    print "<link href=\"/logos/upload/css/$main::query{'merchant'}\.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  }
  else {
    print "<link href=\"/css/style_billpay.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  }

  print "<script type=\"text/javascript\">\n";
  print "//<!-- Start Script\n";

  print "function results(loadurl,swidth,sheight) {\n";
  print "  SmallWin = window.open(loadurl, 'results','scrollbars=yes,resizable=yes,status=no,toolbar=no,menubar=yes,height='+sheight+',width='+swidth);\n";
  print "}\n";

  print "//-->\n";
  print "</script>\n";

  if ($billpay_language::template{'head'} ne '') {
    print "$billpay_language::template{'head'}\n";
  }

  my $captcha = new PlugNPay::Util::Captcha::ReCaptcha;
  print $captcha->headHTML();

  print "</head>\n";
  print "<body>\n";

  if ($billpay_language::template{'top'} ne '') {
    print "$billpay_language::template{'top'}\n";
    return;
  }

  print "<table width=760 border=0 cellpadding=0 cellspacing=0 id=\"header\">\n";
  print "  <tr>\n";
  print "    <td colspan=3 align=left>";
  if ($cobrand_logo !~ /\w/) {
    if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
      print "<img src=\"/images/global_header_gfx.gif\" width=760 alt=\"Plug 'n Pay Technologies - we make selling simple.\" height=44 border=0>";
    }
    else {
      print "<img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Logo\">\n";
    }
  }

  #print "<!-- cobrand stuff -- User: $ENV{'REMOTE_USER'}, Title: $cobrand_title, Logo: $cobrand_logo -->\n";

  if ($cobrand_logo =~ /\w/) {
    print "<img src=\"$cobrand_logo\" alt=\"$cobrand_title\" border=0>\n";
    if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
      print "<br><div align=right><font size=2>Powered by Plug 'n Pay Technologies</font></div>\n";
    }
    else {
      print "<br><div align=right><font size=2>Powered by $ENV{'SERVER_NAME'}</font></div>\n";
    }
  }
  elsif ($cobrand_title =~ /\w/) {
    print "<br>In partnership with <b>$cobrand_title</b>.\n";
  }

  print "</td>\n";
  print "  </tr>\n";

  if (($ENV{'SCRIPT_NAME'} !~ /(logout|billpay_signup|billpay_confirm|billpay_express|billpay_optout|billpay_lostpass)\.cgi/)) {
    print "  <tr>\n";
    print "    <td align=left nowrap><p><a href=\"$path_index\">$billpay_language::lang_titles{'link_home'}</a></p></td>\n";
    print "    <td align=right nowrap><p><a href=\"$path_logout\">$billpay_language::lang_titles{'link_logout'}</a> &nbsp;\|&nbsp; <a href=\"$path_index\?function=help\">$billpay_language::lang_titles{'link_help'}</a></p></td>\n";
    print "  </tr>\n";
  }

  print "  <tr>\n";
  print "    <td colspan=3 align=left><img src=\"/images/header_bottom_bar_gfx.gif\" width=760 alt=\"plug \'n pay\"  height=14></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  if (($ENV{'SCRIPT_NAME'} =~ /(logout|billpay_signup|billpay_confirm|billpay_express|billpay_optout|billpay_lostpass|security)\.cgi/) || ($ENV{'TEMPFLAG'} == 1)) {
    # do nothing
  }
  elsif ($ENV{'SCRIPT_NAME'} =~ /(logout_beta|billpay_signup_beta|billpay_confirm_beta|billpay_express_beta|billpay_optout_beta|billpay_lostpass_beta|security_beta)\.cgi/) {
    # do nothing for these development scripts
  }
  elsif ($main::query{'function'} eq "") {

    my @now = gmtime(time);
    my $today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

    my $dbh = &miscutils::dbhconnect("billpres");

    # calculate number of open/unpaid bills
    my $sth1 = $dbh->prepare(q{
        SELECT COUNT(username)
        FROM bills2
        WHERE username=?
        AND status=?
        AND expire_date>=?
      }) or die "Can't do: $DBI::errstr";
    $sth1->execute("$ENV{'REMOTE_USER'}", "open", "$today") or die "Can't execute: $DBI::errstr";
    my ($open_cnt) = $sth1->fetchrow;
    $sth1->finish;

    # calculate number of expired open/unpaid bills
    my $sth2 = $dbh->prepare(q{
        SELECT COUNT(username)
        FROM bills2
        WHERE username=?
        AND status=?
        AND expire_date<?
      }) or die "Can't do: $DBI::errstr";
    $sth2->execute("$ENV{'REMOTE_USER'}", "open", "$today") or die "Can't execute: $DBI::errstr";
    my ($expired_cnt) = $sth2->fetchrow;
    $sth2->finish;

    # calculate number of closed bills (includes closed & merged status)
    my $sth3 = $dbh->prepare(q{
        SELECT COUNT(username)
        FROM bills2
        WHERE username=?
        AND (status=? OR status=?)
      }) or die "Can't do: $DBI::errstr";
    $sth3->execute("$ENV{'REMOTE_USER'}", "closed", "merged") or die "Can't execute: $DBI::errstr";
    my ($closed_cnt) = $sth3->fetchrow;
    $sth3->finish;

    # calculate number of paid bills
    my $sth4 = $dbh->prepare(q{
        SELECT COUNT(username)
        FROM bills2
        WHERE username=?
        AND status=?
      }) or die "Can't do: $DBI::errstr";
    $sth4->execute("$ENV{'REMOTE_USER'}", "paid") or die "Can't execute: $DBI::errstr";
    my ($paid_cnt) = $sth4->fetchrow;
    $sth4->finish;

    $dbh->disconnect;

    print "<table border=0 cellspacing=0 cellpadding=5 width=760>\n";
    print "  <tr>\n";
    print "    <td colspan=2 bgcolor=\"#f4f4f4\"><p><b>&nbsp; $billpay_language::lang_titles{'section_overview'} \[";
    print "$open_cnt $billpay_language::lang_titles{'section_overview_open'}, ";
    print "$expired_cnt $billpay_language::lang_titles{'section_overview_expired'}, ";
    print "$closed_cnt $billpay_language::lang_titles{'section_overview_closed'}, ";
    print "$paid_cnt $billpay_language::lang_titles{'section_overview_paid'} ";
    print "\]</b></p></td>\n";
    print "  </tr>\n";
    print "</table>\n";
  }
  else {
    print "<table border=0 cellspacing=0 cellpadding=5 width=760>\n";
    print "  <tr>\n";
    print "    <td colspan=2 bgcolor=\"#f4f4f4\">\n";
    print "<table border=0 cellspacing=0 cellpadding=2 width=\"100%\">\n";
    print "  <tr>\n";
    print "    <th width=\"20%\"><p><a href=\"$billpay_editutils::path_index\?function=show_pay_bills_menu\">$billpay_language::lang_titles{'link_paybills'}</a></p></th>\n";
    print "    <th width=\"20%\"><p><a href=\"$billpay_editutils::path_index\?function=show_view_bills_menu\">$billpay_language::lang_titles{'link_viewbills'}</a></p></th>\n";
    print "    <th width=\"20%\"><p><a href=\"$billpay_editutils::path_index\?function=show_cust_profile_menu\">$billpay_language::lang_titles{'link_custprofile'}</a></p></th>\n";
    print "    <th width=\"20%\"><p><a href=\"$billpay_editutils::path_index\?function=show_bill_profile_menu\">$billpay_language::lang_titles{'link_billprofile'}</a></p></th>\n";
    print "    <th width=\"20%\"><p><a href=\"$billpay_editutils::path_index\?function=show_docs_menu\">$billpay_language::lang_titles{'link_docs'}</a></p></th>\n";
    print "  </tr>\n";
    print "</table></td>\n";
    print "  </tr>\n";
    print "</table>\n";
  }

  if ($main::query{'function'} eq "") {
    print "<table border=0 cellspacing=0 cellpadding=5 width=760>\n";
    print "  <tr>\n";
    #print "    <td width=120 valign=top>\n";
    #print "    <p></p>\n";
    #print "    <div id=\"leftnav\">\n";
    #print "        <p><a href=\"$billpay_editutils::path_index\?function=show_pay_bills_menu\">$billpay_language::lang_titles{'link_paybills'}</a></p>\n";
    #print "        <p><a href=\"$billpay_editutils::path_index\?function=show_view_bills_menu\">$billpay_language::lang_titles{'link_viewbills'}</a></p>\n";
    #print "        <p><a href=\"$billpay_editutils::path_index\?function=show_cust_profile_menu\">$billpay_language::lang_titles{'link_custprofile'}</a></p>\n";
    #print "        <p><a href=\"$billpay_editutils::path_index\?function=show_bill_profile_menu\">$billpay_language::lang_titles{'link_billprofile'}</a></p>\n";
    #print "        <p><a href=\"$billpay_editutils::path_index\?function=show_docs_menu\">$billpay_language::lang_titles{'link_docs'}</a></p>\n";
    #print "    </div></td>\n";
    #print "    <td colspan=2 valign=top align=left>\n";
    print "    <td colspan=3 valign=top align=left>\n";
  }
  elsif ($main::query{'function'} =~ /^(show_)/i) {
    print "<table border=0 cellspacing=0 cellpadding=5 width=760>\n";
    print "  <tr>\n";
    print "    <td colspan=3 valign=top align=left>\n";
  }
  else {
    print "<table border=0 cellspacing=0 cellpadding=0 width=760>\n";
    print "  <tr>\n";
    print "    <td colspan=3 valign=top align=left>\n";
  }

  return;
}

sub head_login {
  my ($path_index, $path_logout);

  if ($billpay_adminutils::path_index eq "") {
    $path_index = "index.cgi";
  }
  else {
    $path_index = $billpay_adminutils::path_index;
  }

  if ($billpay_adminutils::path_logout eq "") {
    $path_logout = "logout.cgi";
  }
  else {
    $path_logout = $billpay_adminutils::path_logout;
  }

  my ($cobrand_title, $cobrand_logo, $cookie_set) = &cobrand_check();

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>$billpay_language::lang_titles{'service_title'}</title>\n";
  print "<meta http-equiv=\"CACHE-CONTROL\" content=\"NO-CACHE\">\n";
  print "<meta http-equiv=\"PRAGMA\" content=\"NO-CACHE\">\n";
  print "<link rel=\"shortcut icon\" href=\"favicon.ico\">\n";
  print "<link href=\"/css/style_billpay.css\" type=\"text/css\" rel=\"stylesheet\">\n";

  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";

  print "<table width=760 border=0 cellpadding=0 cellspacing=0 id=\"header\">\n";
  print "  <tr>\n";
  print "    <td colspan=3 align=left>";
  #if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
  #  print "<img src=\"/images/global_header_gfx.gif\" width=760 alt=\"Plug 'n Pay Technologies - we make selling simple.\" height=44 border=0>";
  #}
  #else {
  #  print "<img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Logo\">\n";
  #}

  if ($cobrand_logo !~ /\w/) {
    if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
      print "<img src=\"/images/global_header_gfx.gif\" width=760 alt=\"Plug 'n Pay Technologies - we make selling simple.\" height=44 border=0>";
    }
    else {
      print "<img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Logo\">\n";
    }
  }

  #print "<!-- cobrand stuff -- User: $ENV{'REMOTE_USER'}, Title: $cobrand_title, Logo: $cobrand_logo -->\n";
  if ($cobrand_logo =~ /\w/) {
    print "<img src=\"$cobrand_logo\" alt=\"$cobrand_title\" border=0>\n";
    if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
      print "<br><div align=right><font size=2>Powered by Plug 'n Pay Technologies</font></div>\n";
    }
    else {
      print "<br><div align=right><font size=2>Powered by $ENV{'SERVER_NAME'}</font></div>\n";
    }
  }
  elsif ($cobrand_title =~ /\w/) {
    print "<br>In partnership with <b>$cobrand_title</b>.\n";
  }

  print "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=3 align=left><img src=\"/images/header_bottom_bar_gfx.gif\" width=760 alt=\"plug \'n pay\" height=14></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table border=0 cellspacing=0 cellpadding=5 width=760>\n";
  print "  <tr>\n";
  print "    <td colspan=3 valign=top align=left>\n";
  print "<h1>$billpay_language::lang_titles{'service_title'}</h1>\n";

  return;
}

sub cobrand_check {

  # Get CGI query data, filter it & use this for co-branding.
  # Doing this because it cannot be retrieved by some scripts calling this function (such as from the billpay login page)
  my %query = ();
  my $query = new CGI;
  my @array = $query->param;
  foreach my $var (@array) {
    $var =~ s/[^a-zA-Z0-9\_\-]//g;
    $query{$var} = &CGI::escapeHTML($query->param($var));
  }
  $query{'merchant'} =~ s/[^a-zA-Z0-9]//g;
  $query{'merchant'} = lc("$query{'merchant'}");
  $query{'cobrand'} =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;
  $query{'login'} =~ s/[^a-zA-Z0-9\_\-\@\.]//g;
  $query{'login'} = lc("$query{'login'}");

  # figure out cobrand stuff...
  my $cobrand = 0; # assume nothings set [0 = not set, 1 = cobrand cookie, 2 = cobrand lookup]
  my $cobrand_merchant = "";
  my $cobrand_title = "";
  my $cobrand_logo = "";
  my $cookie_set = "";

  # look through cookies & try to find cobrand cookie data
  my %cookies = fetch CGI::Cookie;

  if (($ENV{'SCRIPT_NAME'} =~ /(billpay_express.cgi)/i) && ($query{'merchant'} =~ /\w/)) {
    # set in cobrand data in memory
    $cobrand = 1;
    $cobrand_merchant = $query{'merchant'};
    $cobrand_title = $query{'cobrand'};
  }
  elsif ($cookies{'BILLPAY_COBRAND'} ne "") {
    my $cookie_data = $cookies{'BILLPAY_COBRAND'}->value;
    $cookie_data =~ tr/+/ /;
    $cookie_data =~ s/\%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;

    ## split cookie value
    my ($merchant, $title) = split(/\t/, $cookie_data);
    $merchant =~ s/[^a-zA-Z0-9]//g;
    $merchant = lc("$merchant");
    $title =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;

    # set in cobrand data in memory
    $cobrand = 1;
    $cobrand_merchant = $merchant;
    $cobrand_title = $title;
  }

  # if cobrand data is not defined, then read from cobrand table & set cookie
  if ($cobrand == 0) {
    my $srch_username = "";
    if ($ENV{'REMOTE_USER'} =~ /\w/) {
      $srch_username = $ENV{'REMOTE_USER'};
    }
    elsif (($query{'email'} =~ /\w/) && ($ENV{'SCRIPT_NAME'} =~ /billpay_express.cgi/i)) {
      $srch_username = $query{'email'};
    }
    else {
      $srch_username = $query{'login'};
    }

    if ($srch_username =~ /\w/) {
      my $dbh = &miscutils::dbhconnect("billpres");
      my $sth = $dbh->prepare(q{
          SELECT username, merchant, cobrand
          FROM cobrand2
          WHERE username=?
        }) or die "Can't do: $DBI::errstr";
      $sth->execute("$srch_username") or die "Can't execute: $DBI::errstr";
      my ($db_username, $db_merchant, $db_title) = $sth->fetchrow;
      $sth->finish;
      $dbh->disconnect;

      if ($srch_username eq $db_username) {
        $cobrand = 2;
        $cobrand_merchant = $db_merchant;
        $cobrand_title = $db_title;
        $cookie_set = "yes";
      }
    }
  }

  if (($cobrand_merchant eq "") && ($query{'merchant'} =~ /\w/)) {
    $cobrand_merchant = $query{'merchant'};
  }
  if (($cobrand_title eq "") && ($query{'cobrand'} =~ /\w/)) {
    $cobrand_title = $query{'cobrand'};
  }

  if (($cobrand == 2) || (($cobrand_merchant =~ /\w/) && ($cobrand_title =~ /\w/) && ($cookie_set eq "yes"))) {
    # set new cobrand cookie, when all required cobrand data is present
    # this keeps exising cobrand cookies fresh & sets it if none were set
    my $c = new CGI::Cookie(
                -name    => "BILLPAY_COBRAND",
                -value   => "$cobrand_merchant\t$cobrand_title",
                -expires => "+12M",
                -domain  => "$ENV{'SERVER_NAME'}",
                -path    => "/",
                -secure  => 1
               );
    # you can add:  "-secure => 1" to the CGI::Cookie parameters to set the cookie security flag
    # NOTE: leave -expires param blank, for session only cookie
    ##print "Set-Cookie: $c\n";
    print CGI::header(-cookie=>[$c]);

    $cookie_set = "yes";
  }

  my $path_web = &pnp_environment::get('PNP_WEB');

  if ($cobrand_merchant ne "") {
    my @logo_type = ('jpg', 'gif', 'png');
    for (my $i = 0; $i <= $#logo_type; $i++) {
      if (-e "$path_web/logos/upload/logos/$cobrand_merchant\.$logo_type[$i]") {
        $cobrand_logo = sprintf("%s\/%s\.%s", "\/logos\/upload\/logos", "$cobrand_merchant", "$logo_type[$i]");
      }
    }
  }

  return ("$cobrand_title", "$cobrand_logo", "$cookie_set");
}


sub main_menu_links {

  my $dbh = &miscutils::dbhconnect("billpres");

  # get general contact address
  my $sth0 = $dbh->prepare(qq{
      SELECT name, company, addr1, addr2, city, state, zip, country
      FROM customer2
      WHERE username=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth0->execute("$ENV{'REMOTE_USER'}") or die "Cannot execute: $DBI::errstr";
  my ($db_name, $db_company, $db_addr1, $db_addr2, $db_city, $db_state, $db_zip, $db_country) = $sth0->fetchrow;
  $sth0->finish;

  $dbh->disconnect;

  if (($db_name eq "") || ($db_addr1 eq "") || ($db_city eq "") || ($db_state eq "") || ($db_zip eq "") || ($db_country eq "")) {
    print "<p><b>$billpay_language::lang_titles{'statement_nocontactinfo'}</b>\n";
    print "<br>$billpay_language::lang_titles{'statement_updatecontact'}</p>\n";

    print "<form method=post action=\"$billpay_adminutils::path_edit\">\n";
    print "<input type=hidden name=\"function\" value=\"edit_cust_profile_form\">\n";
    print "<input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_editcontact'}\"></form>\n";

    return;
  }

print<<EOF;
<h1><a href="/billpay/">$billpay_language::lang_titles{'service_title'}</a></h1>

<table width="100%" border="0" cellspacing="0" cellpadding="3">

  <tr>
    <td align="center" valign="top">
<table width="80" height="50" border="1" cellpadding="0" cellspacing="0" bgcolor="#CCCCCC">
        <tr>
          <td><a href="$billpay_adminutils::path_edit\?function=list_bills_form\&status=open"><img src="/images/acct_admin_8050px.jpg" border="0" alt="$billpay_language::lang_titles{'section_paybills'}"></a></td>
        </tr>
      </table></td>
    <td valign="top"><p><b><a href="$billpay_adminutils::path_edit\?function=list_bills_form\&status=open">$billpay_language::lang_titles{'section_paybills'}</a></b><br>
        $billpay_language::lang_titles{'description_paybills'}<br>
        <a href="$billpay_adminutils::path_edit\?function=list_bills_form\&status=open">$billpay_language::lang_titles{'link_clickbegin'}</a></p></td>
  </tr>

  <tr>
    <td align="center" valign="top">
<table width="80" height="50" border="1" cellpadding="0" cellspacing="0" bgcolor="#CCCCCC">
        <tr>
          <td><a href="$billpay_editutils::path_index\?function=show_view_bills_menu"><img src="/images/news_8050px.jpg" border="0" alt="$billpay_language::lang_titles{'section_viewbills'}"></a></td>
        </tr>
      </table></td>
    <td valign="top"><p><b><a href="$billpay_editutils::path_index\?function=show_view_bills_menu">$billpay_language::lang_titles{'section_viewbills'}</a></b><br>
        $billpay_language::lang_titles{'description_viewbills'}<br>
        <a href="$billpay_editutils::path_index\?function=show_view_bills_menu">$billpay_language::lang_titles{'link_clickbegin'}</a></p></td>
  </tr>

  <tr>
    <td align="center" valign="top">
<table width="80" height="50" border="1" cellpadding="0" cellspacing="0" bgcolor="#CCCCCC">
        <tr>
          <td><a href="$billpay_editutils::path_index\?function=show_cust_profile_menu"><img src="/images/config_8050px.jpg" border="0" alt="$billpay_language::lang_titles{'section_custprofile'}"></a></td>
        </tr>
      </table></td>
    <td valign="top"><p><b><a href="$billpay_editutils::path_index\?function=show_cust_profile_menu">$billpay_language::lang_titles{'section_custprofile'}</a></b><br>
        $billpay_language::lang_titles{'description_custprofile'}<br>
        <a href="$billpay_editutils::path_index\?function=show_cust_profile_menu">$billpay_language::lang_titles{'link_clickbegin'}</a></p></td>
  </tr>

  <tr>
    <td align="center" valign="top">
<table width="80" height="50" border="1" cellpadding="0" cellspacing="0" bgcolor="#CCCCCC">
        <tr>
          <td><a href="$billpay_editutils::path_index\?function=show_bill_profile_menu"><img src="/images/graphs_8050px.jpg" border="0" alt="$billpay_language::lang_titles{'section_billprofile'}"></a></td>
        </tr>
      </table></td>
    <td valign="top"><p><b><a href="$billpay_editutils::path_index\?function=show_bill_profile_menu">$billpay_language::lang_titles{'section_billprofile'}</a></b><br>
        $billpay_language::lang_titles{'description_billprofile'}<br>
        <a href="$billpay_editutils::path_index\?function=show_bill_profile_menu">$billpay_language::lang_titles{'link_clickbegin'}</a></p></td>
  </tr>

  <tr>
    <td align="center" valign="top">
<table width="80" height="50" border="1" cellpadding="0" cellspacing="0" bgcolor="#CCCCCC">
        <tr>
          <td><a href="$billpay_editutils::path_index\?function=show_docs_menu"><img src="/images/reports_8050px.jpg" border="0" alt="$billpay_language::lang_titles{'section_docs'}"></a></td>
        </tr>
      </table></td>
    <td valign="top"><p><b><a href="$billpay_editutils::path_index\?function=show_docs_menu">$billpay_language::lang_titles{'section_docs'}</a></b><br>
        $billpay_language::lang_titles{'description_docs'}<br>
        <a href="$billpay_editutils::path_index\?function=show_docs_menu">$billpay_language::lang_titles{'link_clickbegin'}</a></p></td>
  </tr>

</table>
</td></tr>
</table>
EOF
}

sub tail {

  if ($billpay_language::template{'tail'} ne '') {
    print "$billpay_language::template{'tail'}\n";
  }
  else {
    my @now = gmtime(time);
    my $year = sprintf("%4d", $now[5]+1900);

    print "</td>\n";
    print "  </tr>\n";
    print "</table>\n";

    print "<table width=760 border=0 cellpadding=0 cellspacing=0 id=\"footer\">\n";
    print "  <tr>\n";
    print "    <td align=left><p>";
    if ($ENV{'REMOTE_USER'} ne "") {
      print "<a href=\"/billpay/helpdesk.cgi\?mode=addnew\" target=\"docs\">";
    }
    else {
      print"<a href=\"mailto:billpaysupport\@plugnpay.com\">";
    }
    print "$billpay_language::lang_titles{'service_title'} Support</a></p></td>\n";
    print "    <td align=right><p>\&copy; $year, ";
    if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
      print "Plug 'n Pay Technologies, Inc.";
    }
    else {
      print "$ENV{'SERVER_NAME'}";
    }

    print "</p></td>\n";
    print "  </tr>\n";
    print "</table>\n";
  }

  print "</body>\n";
  print "</html>\n";

  #$billpay_adminutils::dbh->disconnect;
}

sub pay_bills_title {
  print "  <tr>\n";
  print "    <td colspan=2><h1><a href=\"$billpay_adminutils::path_index\">$billpay_language::lang_titles{'service_title'}</a> / $billpay_language::lang_titles{'service_subtitle_paybills'}</h1></td>\n";
  print "  </tr>\n";
}

sub view_bills_title {
  print "  <tr>\n";
  print "    <td colspan=2><h1><a href=\"$billpay_adminutils::path_index\">$billpay_language::lang_titles{'service_title'}</a> / $billpay_language::lang_titles{'service_subtitle_viewbills'}</h1></td>\n";
  print "  </tr>\n";
}

sub cust_profile_title {
  print "  <tr>\n";
  print "    <td colspan=2><h1><a href=\"$billpay_adminutils::path_index\">$billpay_language::lang_titles{'service_title'}</a> / $billpay_language::lang_titles{'service_subtitle_custprofile'}</h1></td>\n";
  print "  </tr>\n";
}

sub bill_profile_title {
  print "  <tr>\n";
  print "    <td colspan=2><h1><a href=\"$billpay_adminutils::path_index\">$billpay_language::lang_titles{'service_title'}</a> / $billpay_language::lang_titles{'service_subtitle_billprofile'}</h1></td>\n";
  print "  </tr>\n";
}

sub docs_title {
  print "  <tr>\n";
  print "    <td colspan=2><h1><a href=\"$billpay_adminutils::path_index\">$billpay_language::lang_titles{'service_title'}</a> / $billpay_language::lang_titles{'service_subtitle_docs'}</h1></td>\n";
  print "  </tr>\n";
}

sub help_title {
  print "  <tr>\n";
  print "    <td colspan=2><h1><a href=\"$billpay_adminutils::path_index\">$billpay_language::lang_titles{'service_title'}</a> / $billpay_language::lang_titles{'service_subtitle_help'}</h1></td>\n";
  print "  </tr>\n";
}

sub help_listing {
  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170>&nbsp;</td>\n";
  print "  <td><hr width=\"80%\"></td>\n";
  print "</tr>\n";

  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170><p><b>$billpay_language::lang_titles{'menu_docs'}</b></p></td>\n";
  print "  <td align=left><ul>\n";
  print "    <li><p><a href=\"/billpay/doc_replace.cgi?doc=Billing_Presentment.htm\">$billpay_language::lang_titles{'service_title'} $billpay_language::lang_titles{'link_docs'}</a></p>\n";
  print "    </ul></td>\n";
  print "</tr>\n";

  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170><p><b>$billpay_language::lang_titles{'menu_faq'}</b></p></td>\n";
  print "  <td align=left><ul>\n";
  print "    <li><p><a href=\"/billpay/faq_board.cgi\" target=\"docs\">$billpay_language::lang_titles{'link_faq'}</a></p>\n";
  print "    </ul></td>\n";
  print "</tr>\n";

  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170><p><b>$billpay_language::lang_titles{'menu_helpdesk'}</b></p></td>\n";
  print "  <td align=left><ul>\n";
  print "    <li><p><a href=\"/billpay/helpdesk.cgi\" target=\"docs\">$billpay_language::lang_titles{'link_helpdesk'}</a></p>\n";
  print "    </ul></td>\n";
  print "</tr>\n";

  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170><p><b>$billpay_language::lang_titles{'menu_login'}</b></p></td>\n";
  print "  <td align=left><ul>\n";
  print "    <li><p><a href=\"/billpay/security.cgi\">$billpay_language::lang_titles{'link_changepass'}</a></p>\n";
  print "    </ul></td>\n";
  print "</tr>\n";
}

sub docs_listing {
  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170>&nbsp;</td>\n";
  print "  <td><hr width=\"80%\"></td>\n";
  print "</tr>\n";

  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170><p><b>$billpay_language::lang_titles{'menu_docs'}</b></p></td>\n";
  print "  <td align=left><ul>\n";
  print "    <li><p><a href=\"doc_replace.cgi?doc=Billing_Presentment.htm\" target=\"docs\">$billpay_language::lang_titles{'service_title'} $billpay_language::lang_titles{'link_docs'}</a></p>\n";
  print "    </ul></td>\n";
  print "</tr>\n";

  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170><p><b>$billpay_language::lang_titles{'menu_faq'}</b></p></td>\n";
  print "  <td align=left><ul>\n";
  print "    <li><p><a href=\"/billpay/faq_board.cgi\" target=\"docs\">$billpay_language::lang_titles{'link_faq'}</a></p>\n";
  print "    </ul></td>\n";
  print "</tr>\n";

  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170><p><b>$billpay_language::lang_titles{'menu_helpdesk'}</b></p></td>\n";
  print "  <td align=left><ul>\n";
  print "    <li><p><a href=\"helpdesk.cgi\" target=\"docs\">$billpay_language::lang_titles{'link_helpdesk'}</a></p>\n";
  print "    </ul></td>\n";
  print "</tr>\n";
}

sub list_open_bills_section {
  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170>&nbsp;</td>\n";
  print "  <td><hr width=\"80%\"></td>\n";
  print "</tr>\n";

  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170><p><b>$billpay_language::lang_titles{'menu_list_open'}</b></p></td>\n";
  print "  <td align=left><form method=post action=\"$billpay_adminutils::path_edit\">\n";
  print "    <input type=hidden name=\"function\" value=\"list_bills_form\">\n";
  print "    <input type=hidden name=\"status\" value=\"open\">\n";
  print "    <input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_list_open'}\">\n";
  print "  </td></form>\n";
  print "</tr>\n";

  return;
}

sub list_expired_bills_section {
  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170>&nbsp;</td>\n";
  print "  <td><hr width=\"80%\"></td>\n";
  print "</tr>\n";

  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170><p><b>$billpay_language::lang_titles{'menu_list_expired'}</b></p></td>\n";
  print "  <td align=left><form method=post action=\"$billpay_adminutils::path_edit\">\n";
  print "    <input type=hidden name=\"function\" value=\"list_bills_form\">\n";
  print "    <input type=hidden name=\"status\" value=\"open\">\n";
  print "    <input type=hidden name=\"type\" value=\"expired\">\n";
  print "    <input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_list_expired'}\">\n";
  print "  </td></form>\n";
  print "</tr>\n";

  return;
}

sub list_closed_bills_section {
  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170>&nbsp;</td>\n";
  print "  <td><hr width=\"80%\"></td>\n";
  print "</tr>\n";

  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170><p><b>$billpay_language::lang_titles{'menu_list_closed'}</b></p></td>\n";
  print "  <td align=left><form method=\"post\" action=\"$billpay_adminutils::path_edit\">\n";
  print "    <input type=hidden name=\"function\" value=\"list_bills_form\">\n";
  print "    <input type=hidden name=\"status\" value=\"closed\">\n";
  print "    <input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_list_closed'}\">\n";
  print "  </td></form>\n";
  print "</tr>\n";

  return;
}

sub list_paid_bills_section {
  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170>&nbsp;</td>\n";
  print "  <td><hr width=\"80%\"></td>\n";
  print "</tr>\n";

  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170><p><b>$billpay_language::lang_titles{'menu_list_paid'}</b></p></td>\n";
  print "  <td align=left><form method=post action=\"$billpay_adminutils::path_edit\">\n";
  print "    <input type=hidden name=\"function\" value=\"list_bills_form\">\n";
  print "    <input type=hidden name=\"status\" value=\"paid\">\n";
  print "    <input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_list_paid'}\">\n";
  print "  </td></form>\n";
  print "</tr>\n";

  return;
}

sub autopay_bills_section {
if ($ENV{'REMOTE_USER'} =~ /(\w{1,}\@plugnpay.com|\w{1,}\@iconparking.com)/i) {
  # 07/16/11 - James - Disabled auto-pay ablity, until we can ensure the autopay script works properly.
  # 10/15/11 - James - Enabled sectioon for Icon Parking review of admin menu layout.
  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170>&nbsp;</td>\n";
  print "  <td><hr width=\"80%\"></td>\n";
  print "</tr>\n";

  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170><p><b>$billpay_language::lang_titles{'menu_autopay'}</b><br>[THIS FEATURE IS OFFLINE FOR MAINTENANCE]</p></td>\n";
  print "  <td align=left><form method=post action=\"$billpay_adminutils::path_edit\">\n";
  print "    <input type=hidden name=\"function\" value=\"autopay_bills_form\">\n";
  print "    <input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_autopay'}\">\n";
  print "  </td></form>\n";
  print "</tr>\n";
}
  return;
}

sub view_cust_profile_section {
  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170>&nbsp;</td>\n";
  print "  <td><hr width=\"80%\"></td>\n";
  print "</tr>\n";

  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170><p><b>$billpay_language::lang_titles{'menu_view_contact'}</b></p></td>\n";
  print "  <td align=left><form method=post action=\"$billpay_adminutils::path_edit\">\n";
  print "    <input type=hidden name=\"function\" value=\"view_cust_profile_form\">\n";
  print "    <input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_view_contact'}\">\n";
  print "  </td></form>\n";
  print "</tr>\n";

  return;
}

sub edit_cust_profile_section {
  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170>&nbsp;</td>\n";
  print "  <td><hr width=\"80%\"></td>\n";
  print "</tr>\n";

  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170><p><b>$billpay_language::lang_titles{'menu_edit_contact'}</b></p></td>\n";
  print "  <td align=left><form method=post action=\"$billpay_adminutils::path_edit\">\n";
  print "<input type=hidden name=\"function\" value=\"edit_cust_profile_form\">\n";
  print "<p><input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_edit_contact'}\"></td></form>\n";
  print "</tr>\n";

  return;
}

sub list_bill_profile_section {
  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170>&nbsp;</td>\n";
  print "  <td><hr width=\"80%\"></td>\n";
  print "</tr>\n";

  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170><p><b>$billpay_language::lang_titles{'menu_list_billing'}</b></p></td>\n";
  print "  <td align=left><form method=post action=\"$billpay_adminutils::path_edit\">\n";
  print "    <input type=hidden name=\"function\" value=\"list_bill_profile_form\">\n";
  print "    <input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_list_billing'}\">\n";
  print "  </td></form>\n";
  print "</tr>\n";

  return;
}

sub edit_bill_profile_section {
  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170>&nbsp;</td>\n";
  print "  <td><hr width=\"80%\"></td>\n";
  print "</tr>\n";

  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170><p><b>$billpay_language::lang_titles{'menu_edit_billing'}</b></p></td>\n";
  print "  <td align=left><form method=post action=\"$billpay_adminutils::path_edit\">\n";
  print "<input type=hidden name=\"function\" value=\"edit_bill_profile_form\">\n";
  print "<p><input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_edit_billing'}\"></td></form>\n";
  print "</tr>\n";

  return;
}

sub add_bill_profile_section {
  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170>&nbsp;</td>\n";
  print "  <td><hr width=\"80%\"></td>\n";
  print "</tr>\n";

  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170><p><b>$billpay_language::lang_titles{'menu_add_billing'}</b></p></td>\n";
  print "  <td align=left><form method=post action=\"$billpay_adminutils::path_edit\">\n";
  print "    <input type=hidden name=\"function\" value=\"add_new_bill_profile_form\">\n";
  print "    <input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_add_billing'}\">\n";
  print "  </td></form>\n";
  print "</tr>\n";

  return;
}

sub delete_bill_profile_section {
  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170>&nbsp;</td>\n";
  print "  <td><hr width=\"80%\"></td>\n";
  print "</tr>\n";

  print "<tr>\n";
  print "  <td valign=top bgcolor=\"#f4f4f4\" width=170><p><b>$billpay_language::lang_titles{'menu_delete_billing'}</b></p></td>\n";
  print "  <td align=left><form method=\"post\" action=\"$billpay_adminutils::path_edit\">\n";
  print "<input type=hidden name=\"function\" value=\"delete_bill_profile_form\">\n";
  print "<p><input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_delete_billing'}\"></td></form>\n";
  print "</tr>\n";

  return;
}

sub check_status {
  # checks the status of the account, checking for temp passwords, account validation/hold situations.

  # check if password is temporary
  if ($ENV{'TEMPFLAG'} == 1) {
    print "Location: https://$ENV{'SERVER_NAME'}/billpay/security.cgi\n\n";
    exit;
  }

  # check status of customer profile
  my $dbh = &miscutils::dbhconnect("billpres");
  my $sth1 = $dbh->prepare(q{
      SELECT status
      FROM customer2
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth1->execute("$ENV{'REMOTE_USER'}") or die "Can't execute: $DBI::errstr";
  my ($db_status) = $sth1->fetchrow;
  $sth1->finish;
  $dbh->disconnect;

  if ($db_status !~ /active/) {
    &billpay_adminutils::head();
    if ($db_status =~ /pending/) {
      print "<p>$billpay_language::lang_titles{'statement_account_activate'}</p>\n";
    }
    else {
      print "<p>$billpay_language::lang_titles{'statement_account_inactive'}</p>\n";
    }
    &billpay_adminutils::tail();
    exit;
  }

  return;
}

sub send_reg_conf_email {
  # send the billing presentment registration confirmation email
  my %query = @_;

  $query{'merchant'} = "unknown";
  $query{'merchant_email'} = "billpaysupport\@plugnpay.com";

  # create customer registration email confirmation

  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setGatewayAccount($query{'merchant'});
  $emailObj->setFormat('text');
  $emailObj->setTo($query{'login'});
  $emailObj->setFrom($query{'merchant_email'});
  $emailObj->setSubject($billpay_language::lang_titles{'service_title'} . ' Registration Confirmation');

  my $emailmessage = "";
  $emailmessage .= "Thank you for taking the time to register.\n\n";
  $emailmessage .= "Please go the the below URL to confirm your email address \& to active your account.\n";
  $emailmessage .= "\n";
  $emailmessage .= "https://$ENV{'SERVER_NAME'}/billpay_confirm.cgi\?$query{'shalogin'}\n";
  $emailmessage .= "\n";
  $emailmessage .= "For assistance or if you have questions on this, please ";
  $emailmessage .= "contact $query{'merchant_email'}.\n";
  $emailmessage .= "\n";

  $emailmessage .= "When contacting us, please refer your account:\n";
  $emailmessage .= "Service: $billpay_language::lang_titles{'service_title'}\n";
  $emailmessage .= "Email:   $query{'login'}\n";
  $emailmessage .= "\n";
  $emailmessage .= "Thank you,\n";
  $emailmessage .= "$billpay_language::lang_titles{'service_title'} Support Staff\n";

  $emailObj->setContent($emailmessage);
  $emailObj->send();
}

sub send_activation_email {
  # send the billing presentment registration activation email
  my ($db_username) = @_;

  my $merchant = "unknown";
  my $merchant_email = "billpaysupport\@plugnpay.com";

  # create account activation email
  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setFormat('text');
  $emailObj->setGatewayAccount('unknown');
  $emailObj->setTo($db_username);
  $emailObj->setFrom($merchant_email);
  $emailObj->setSubject($billpay_language::lang_titles{'service_title'} . ' Account Activation');

  my $emailmessage = "";
  $emailmessage .= "Thank you for activating your account.\n\n";
  $emailmessage .= "You may now go to the below URL to login and administer your account.\n";
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
}

1;

