#!/bin/env perl

# Purpose: provide interface to allow affiniscape reseller to set one of several pre-configured template to the given merchant's account.

# Last Updated: 01/15/11

require 5.001;
$|=1;

use lib '/home/p/pay1/perl_lib';
use CGI;
use miscutils;
use sysutils;
use strict;

my %query;
my $query = new CGI;

my @array = $query->param;
foreach my $var (@array) {
  $var =~ s/[^a-zA-Z0-9\_\-]//g;
  $query{"$var"} = &CGI::escapeHTML($query->param($var));
}

if (($ENV{'HTTP_X_FORWARDED_SERVER'} ne "") && ($ENV{'HTTP_X_FORWARDED_FOR'} ne "")) {
  $ENV{'HTTP_HOST'} = (split(/\,/,$ENV{'HTTP_X_FORWARDED_HOST'}))[0];
  $ENV{'SERVER_NAME'} = (split(/\,/,$ENV{'HTTP_X_FORWARDED_SERVER'}))[0];
}

## force a certain reseller for testing...
#if ($ENV{'REMOTE_USER'} eq "jamest") {
#  $ENV{'REMOTE_USER'} = "plugnpay"; # i.e. veromont, plugnpay, cynergy, affinisc
#}

# apply basic input filters to query data
if ($query{'mode'} ne "") {
  $query{'mode'} =~ s/[^a-zA-Z0-9\_\-]//g;
}
if ($query{'username'} ne "") {
  $query{'username'} =~ s/[^a-zA-Z0-9]//g;
  $query{'username'} = lc($query{'username'});
}
if ($query{'template'} ne "") {
  $query{'template'} =~ s/[^a-zA-Z0-9\_\-\.]//g;
  $query{'template'} = substr($query{'template'},0,60);
}
if ($query{'type'} ne "") {
  $query{'type'} =~ s/\W//g;
}
if ($query{'language'} ne "") {
  $query{'language'} =~ s/[^a-zA-Z]//g;
  $query{'language'} = lc("$query{'language'}");
  $query{'language'} = substr($query{'language'},0,2);
}
if ($query{'sort_by'} ne "") {
  $query{'sort_by'} =~ s/\W//g;
}

my $dbh_misc = &miscutils::dbhconnect("pnpmisc");

print "Content-Type: text/html\n\n";

## Uncomment For Testing
#foreach my $key (sort keys %query) {
#  print "QUERY: $key = $query{$key}<br>\n";
#}
#foreach my $key (sort keys %ENV) {
#  print "ENV: $key = $ENV{$key}<br>\n";
#}

my $script = "https://" . $ENV{'HTTP_HOST'} . $ENV{'SCRIPT_NAME'};

my $template_dir = "/home/p/pay1/web/admin/templates";

my $response = "";

# Select Mode
if ($query{'mode'} eq "edit_template") {
  &edit_template(%query);
}
elsif ($query{'mode'} eq "update_template") {
  &update_template(%query);
  #&view_account(%query);
  &show_menu(%query);
}
elsif ($query{'mode'} eq "delete_template") {
  &delete_template(%query);
  #&view_account(%query);
  &show_menu(%query);
}
elsif ($query{'mode'} eq "view_account") {
  &view_account(%query);
}
elsif ($query{'mode'} eq "list_accounts") {
  &list_accounts(%query);
}
else {
  &show_menu(%query);
}

$dbh_misc->disconnect;

exit;

sub html_head {
  print "<html>\n";
  print "<head>\n";
  print "<title>Affiniscape Template Config</title>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"https://pay1.plugnpay.com/css/style_green_beta.css\">\n";
  #print "<link rel=\"stylesheet\" type=\"text/css\" href=\"https://pay1.plugnpay.com/css/green.css\">\n";

  print "<script Language=\"Javascript\">\n";
  print "<!-- // Begin Script \n";
  print "function closewin() {\n";
  print "  self.close();\n";
  print "}\n";
  print "// end script -->\n";
  print "</script>\n";

  print "</head>\n";
  print "<body bgcolor=\"#ffffff\" text=\"#000000\" onLoad=\"hideit.style.display='none';\">\n";

  print "<table width=\"760\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\" id=\"header\">\n";
  print "  <tr>\n";
  print "    <td><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Payment Gateway Logo\"></td>\n";
  print "    <td class=\"right\">&nbsp;</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td colspan=\"2\"><img src=\"/adminlogos/masthead_background.gif\" alt=\"Corp. Logo\" width=\"750\" height=\"16\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td colspan=\"3\" valign=\"top\" align=\"left\"><h1><b><a href=\"$script\">Affiniscape Template Config</a></b></h1></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table width=\"760\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\">\n";
  print "  <tr>\n";
  print "    <td valign=\"top\" align=\"left\">";

  return;
}

sub html_tail {

  my @now = gmtime(time);
  my $year = $now[5] + 1900;

  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table width=\"760\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\" id=\"footer\">\n";
  print "  <tr>\n";
  print "    <td align=\"left\"><p><a href=\"/logout.cgi\" title=\"Click to log out\">Log Out</a> | <a href=\"mailto:support\@plugnpay.com\">Contact Support</a> | <a id=\"close\" href=\"javascript:closewin();\" title=\"Click to close this window\">Close Window</a></p></td>\n";
  print "    <td align=\"right\"><p>\&copy; $year, ";
  if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
    print "Plug and Pay Technologies, Inc.";
  }
  else {
    print "$ENV{'SERVER_NAME'}";
  }
  print "</p></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</body>\n";
  print "</html>\n";
  return;
}

sub show_menu {
  my %query = @_;

  &html_head();

  print "<p>This portion of the site has been constructed to permit Affiniscape resellers to setup pre-configured templates to a given payment gateway account.  Below you should find all the tools necessary to handle the management of these templates.</p>\n";

  print "<p>&bull; <font color=\"#ff0000\"><b><u>IMPORTANT NOTE:</u></b></font> <i>Please be very careful when setting templates.  If a template already exists, submiting a template change will replace the template already set.  Contact us immediately in the event of template setting problem.</i></p>\n";

  print "<p>If you have any problems setting templates, please contact us via normal support channels or email <a href=\"mailto:support\@plugnpay.com\">support\@plugnpay.com</a>.  When submitting your support request, please be as specific as possible & provide examples where necessary.  Please also remember to include your contact information (name, email address &amp; phone number) & reseller userame.</p>\n";

  print "<p>Thank you,\n";
  print "<br>Plug 'n Pay Staff.</p>\n";

  print "<hr>\n";

  if ($response ne "") {
    print "$response\n";
    print "<hr>\n";
  }
 
  print "<table border=\"0\" cellspacing=\"0\" cellpadding=\"0\" width=\"760\">\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">List Accounts</td>\n";
  print "    <td class=\"menurightside\"><form action=\"$script\" mode=\"post\">\n";
  print "<input type=\"hidden\" name=\"mode\" value=\"list_accounts\">\n";
  print "<input type=\"submit\" value=\"List Accounts\">\n";
  print "  </td></form>\n";
  print "</tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menurightside\" colspan=\"2\"><hr></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">View Account</td>\n";
  print "    <td class=\"menurightside\"><form action=\"$script\" mode=\"post\">\n";
  print "<input type=\"hidden\" name=\"mode\" value=\"view_account\">\n";
  print "Username: <input type=\"text\" name=\"username\" value=\"\" size=\"12\" maxlength=\"12\">\n";
  print "<input type=\"submit\" value=\"View Account\">\n";
  print "  </td></form>\n";
  print "</tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menurightside\" colspan=\"2\"><hr></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Add Template</td>\n";
  print "    <td class=\"menurightside\"><form action=\"$script\" mode=\"post\">\n";
  print "<input type=\"hidden\" name=\"mode\" value=\"edit_template\">\n";
  print "Username: <input type=\"text\" name=\"username\" value=\"\" size=\"12\" maxlength=\"12\">\n";
  print "<input type=\"submit\" value=\"Add Template\">\n";
  print "  </td></form>\n";
  print "</tr>\n";

  print "</table>\n";

  &html_tail();
  return;
}

sub show_error {
  my ($message) = @_;

  &html_head();
  print "<div align=\"center\">\n";
  print "<font class=\"error_text\">$message</font>\n";
  print "<p><a href=\"$script\"><b>Click here to return to the main menu</b></a></p>\n";
  print "</div>\n";
  &html_tail();

  exit;
}

sub list_accounts {
  ## list reseller's accounts
  my %query = @_;

  my %selected;
  $query{'sort_by'} =~ s/\W//g;
  if ($query{'sort_by'} !~ /^(username|name|company|status)$/) {
    $query{'sort_by'} = "username";
  }
  $selected{"$query{'sort_by'}"} = "<font size=\"+1\">&raquo;</font>&nbsp;";

  &html_head();

  print "<p><b>This report lists all of your payment gateway accounts.</b>\n";
  #print "<br>&nbsp;\n";
  print "<br><b>Click on the Username of the account you wish to see additional details of.</b>\n";
  print "<br>&bull; The <font size=\"+1\">&raquo;</font> character shows what column the list is currently sorted by.\n";
  print "<br>&bull; To re-organize the list, click on the column's title you wish to sort by.</p>\n";

  print "<div id=\"hideit\">\n";
  print "<h2>Please wait for the list to complete.  Depending upon many factors, this may take a while...</h2>\n";
  print "</div>\n";

  print "<table width=\"760\" border=\"1\" cellpadding=\"0\" cellspacing=\"0\">\n";
  print "  <tr class=\"listsection_title\">\n";
  print "    <td><a href=\"$script\?mode=$query{'mode'}\&sort_by=username\">$selected{'username'}Username</td>\n";
  print "    <td><a href=\"$script\?mode=$query{'mode'}\&sort_by=name\">$selected{'name'}Name</th>\n";
  print "    <td><a href=\"$script\?mode=$query{'mode'}\&sort_by=company\">$selected{'company'}Company</td>\n";
  print "    <td><a href=\"$script\?mode=$query{'mode'}\&sort_by=status\">$selected{'status'}Status</td>\n";
  print "  </tr>\n";

  my $count = 0;
  my ($username, $name, $company, $status);
  my $color = 1;

  my $sth = $dbh_misc->prepare(qq{
    select username, name, company, status
    from customers
    where reseller=?
    order by ?
  }) or print "Can't do: $DBI::errstr";
  $sth->execute("$ENV{'REMOTE_USER'}", "$query{'sort_by'}") or print "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($username, $name, $company, $status));
  while ($sth->fetch) {
    if ($color == 1) {
      print "  <tr class=\"listrow_color1\">\n";
    }
    else {
      print "  <tr class=\"listrow_color0\">\n";
    }

    print "    <td><a href=\"$script\?mode=view_account\&username=$username\">$username</a></td>\n";
    print "    <td>$name</td>\n";
    print "    <td>$company</td>\n";
    print "    <td>$status</td>\n";
    print "  </tr>\n";

    $count = $count + 1;
    $color = ($color + 1) % 2;
  }
  $sth->finish;

  if ($count == 0) {
    print "  <tr class=\"listrow_color1\">\n";
    print "    <td colspan=4 align=\"center\"><b>No Matching Accounts Available.</b></td>\n";
    print "  </tr>\n";
  }

  print "</table>\n";
  &html_tail();

  return;
}

sub view_account {
  ## view a single reseller's account
  my %query = @_;

  # only let reseller view accounts which belong to them
  my $is_ok = &is_reseller_account("$query{'username'}");
  if ($is_ok ne "yes") {
    &show_error("Account Does Not Exist Or Does Not Belong To Reseller");
  }

  &html_head();

  if ($response ne "") {
    print "$response\n";
    print "<hr>\n";
  }

  print "<table width=\"760\" border=\"1\" cellpadding=\"0\" cellspacing=\"0\">\n";
  print "  <tr class=\"listsection_title\">\n";
  print "    <td>Username</td>\n";
  print "    <td>Name</td>\n";
  print "    <td>Company</td>\n";
  print "    <td>Status</td>\n";
  print "    <td>&nbsp;</td>\n";
  print "  </tr>\n";

  my $sth = $dbh_misc->prepare(qq{
    select username, name, company, status
    from customers
    where username=? and reseller=?
  }) or print "Can't do: $DBI::errstr";
  $sth->execute("$query{'username'}", "$ENV{'REMOTE_USER'}") or print "Can't execute: $DBI::errstr";
  my ($username1, $name1, $company1, $status1) = $sth->fetchrow;
  $sth->finish;

  if ($username1 ne "") {
    print "  <tr class=\"listrow_color2\">\n";
    print "    <td>$username1</td>\n";
    print "    <td>$name1</td>\n";
    print "    <td>$company1</td>\n";
    print "    <td>$status1</td>\n";
    print "    <td>&nbsp;</td>\n";
    print "  </tr>\n";

    my @billpaylite_files = glob("$template_dir\/billpaylite\/$username1\_*\.txt");
    my $billpaylite_cnt = @billpaylite_files;

    my @payscreen_files = glob("$template_dir\/payscreen\/$username1\_*\.txt");
    my $payscreen_cnt = @payscreen_files;

    my @thankyou_files = glob("$template_dir\/thankyou\/$username1\.htm*");
    my $thankyou_cnt = @thankyou_files;

    my @transition_files = glob("$template_dir\/transition\/$username1\_*\.html");
    my $transition_cnt = @transition_files;

    if (($billpaylite_cnt >= 1) || ($payscreen_cnt >= 1) || ($thankyou_cnt >= 1) || ($transition_cnt >= 1)) {
      print "  <tr>\n";
      print "    <th colspan=5>Current Templates</th>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <td class=\"menuleftside\">Current Templates</td>\n";
      print "    <td class=\"menurightside\" colspan=4>";

      if ($billpaylite_cnt >= 1) {
        # list current billpaylite page templates 
        print "<b>BillPay Lite Templates:</b> " . $billpaylite_cnt;
        foreach my $filename (sort @billpaylite_files) {
          $filename =~ s/.*[\/\\](.*)/$1/;
          my @temp = split(/\_|\./, $filename, 3); # split filename on "-" & "."
          print "<br>&nbsp; &nbsp; &nbsp; &bull; Custom BillPay Lite ";
          print " \[<a href=\"$script\?mode=delete_template\&username=$query{'username'}\&type=billpaylite&template=$temp[1]\">X</a>\]\n";
        }
        print "<br>\n";
      }

      if ($payscreen_cnt >= 1) {
        # list current payscreen templates 
        print "<b>PayScreen Templates:</b> " . $payscreen_cnt;
        foreach my $filename (sort @payscreen_files) {
          $filename =~ s/.*[\/\\](.*)/$1/;
          my @temp = split(/\_|\./, $filename, 4); # split filename on "-" & "."
          if ($temp[1] =~ /^([a-zA-Z][a-zA-Z])$/) { # detect language specific payscreen files
            print "<br>&nbsp; &nbsp; &nbsp; &bull; $temp[1] - $temp[2] ";
            print " \[<a href=\"$script\?mode=delete_template\&username=$query{'username'}\&type=payscreen\&template=$temp[2]\&language=$temp[1]\">X</a>\]\n";
          }
          else {
            print "<br>&nbsp; &nbsp; &nbsp; &bull; $temp[1] ";
            print " \[<a href=\"$script\?mode=delete_template\&username=$query{'username'}\&type=payscreen\&template=$temp[1]\&language=\">X</a>\]\n";
          }
        }
        print "<br>\n";
      }

      if ($thankyou_cnt >= 1) {
        # list current thankyou page templates 
        print "<b>Thank You Templates:</b> " . $thankyou_cnt;
        foreach my $filename (sort @thankyou_files) {
          $filename =~ s/.*[\/\\](.*)/$1/;
          my @temp = split(/\_|\./, $filename, 3); # split filename on "-" & "."
          print "<br>&nbsp; &nbsp; &nbsp; &bull; Custom Thank You ";
          print " \[<a href=\"$script\?mode=delete_template\&username=$query{'username'}\&type=thankyou\&template=$temp[0]\">X</a>\]\n";
        }
        print "<br>\n";
      }

      if ($transition_cnt >= 1) {
        # list current transition page templates 
        print "<b>Transition Templates:</b> " . $transition_cnt;
        foreach my $filename (sort @transition_files) {
          $filename =~ s/.*[\/\\](.*)/$1/;
          my @temp = split(/\_|\./, $filename, 3); # split filename on "-" & "."
          print "<br>&nbsp; &nbsp; &nbsp; &bull; $temp[1] ";
          print " \[<a href=\"$script\?mode=delete_template\&username=$query{'username'}\&type=transition\&template=$temp[1]\">X</a>\]\n";
        }
        print "<br>\n";
      }

      print "</td>\n";
      print "  </tr>\n";
    }

    print "  <tr class=\"listrow_color1\">\n";
    print "    <td colspan=4 align=\"center\"><form action=\"$script\" mode=\"post\">\n";
    print "<input type=\"hidden\" name=\"mode\" value=\"edit_template\">\n";
    print "<input type=\"hidden\" name=\"username\" value=\"$username1\">\n";
    print "<input type=\"submit\" value=\"Add Template\">\n";
    print "</td></form>\n";
    print "  </tr>\n";
  }
  else {
    print "  <tr class=\"listrow_color1\">\n";
    print "    <td colspan=4 align=\"center\"><b>No Matching Account Available.</b></td>\n";
    print "  </tr>\n";
  }

  print "</table>\n";
  &html_tail();

  return;
}

sub edit_template {
  my %query = @_;

  # only let reseller update links to accounts which belong to them
  my $is_ok = &is_reseller_account("$query{'username'}");
  if ($is_ok ne "yes") {
    &show_error("Account Does Not Exist Or Does Not Belong To Reseller");
  }

  &html_head();

  print "<div id=\"hideit\">\n";
  print "<h2>Please wait for the list to complete.  Depending upon many factors, this may take a while...</h2>\n";
  print "</div>\n";

  print "<table width=\"760\" border=\"1\" cellpadding=\"0\" cellspacing=\"0\">\n";
  print "  <tr class=\"listsection_title\">\n";
  print "    <td>Username</td>\n";
  print "    <td>Name</td>\n";
  print "    <td>Company</td>\n";
  print "    <td>Status</td>\n";
  print "  </tr>\n";

  my $sth = $dbh_misc->prepare(qq{
    select username, name, company, status
    from customers
    where username=? and reseller=?
  }) or print "Can't do: $DBI::errstr";
  $sth->execute("$query{'username'}", "$ENV{'REMOTE_USER'}") or print "Can't execute: $DBI::errstr";
  my ($username1, $name1, $company1, $status1) = $sth->fetchrow;
  $sth->finish;

  # list merchant account
  print "  <tr class=\"listrow_color2\">\n";
  print "    <td>$username1</td>\n";
  print "    <td>$name1</td>\n";
  print "    <td>$company1</td>\n";
  print "    <td>$status1</td>\n";
  print "  </tr>\n";
  print "<table>\n";

  print "<p><b>Select a template you would like appled to this account.</b></p>\n";

  print "<form action=\"$script\" mode=\"post\" name=\"templateform\">\n";
  print "<input type=\"hidden\" name=\"mode\" value=\"update_template\">\n";
  print "<input type=\"hidden\" name=\"username\" value=\"$query{'username'}\">\n";
  print "<input type=\"hidden\" name=\"type\" value=\"\">\n";

  # display template options
  print "<table width=\"760\" border=\"1\" cellpadding=\"0\" cellspacing=\"0\">\n";
  print "  <tr class=\"listsection_title\">\n";
  print "    <td align=\"center\" colspan=2>Available Pre-Configured Templates</td>\n";
  print "  </tr>\n";

  print "  <tr class=\"listrow_color2\">\n";
  print "    <td colspan=2><b>BillPay Lite</b></td>\n";
  print "  </tr>\n";

  print "  <tr class=\"listrow_color1\">\n";
  print "    <td colspan=2><b><font color=\"#ff0000\"><u>NOTE:</u></font> BillPay Lite defaults to Affiniscape's Base Template when no other BillPay Lite template is set.</b>\n";
  print "<br><input type=\"radio\" name=\"template\" value=\"affiniscapebase_template\" onClick=\"document.templateform.type.value=\'billpaylite\';\"> Affiniscape - Base Template\n";
  print "<br><input type=\"radio\" name=\"template\" value=\"affiniscapebase_gray_template\" onClick=\"document.templateform.type.value=\'billpaylite\';\"> Affiniscape - Gray Template\n";
  print "<br><input type=\"radio\" name=\"template\" value=\"laywerbill_template\" onClick=\"document.templateform.type.value=\'billpaylite\';\"> Laywer Bill - Generic Template \n";
  print "<br><input type=\"radio\" name=\"template\" value=\"laywerbill_operating_template\" onClick=\"document.templateform.type.value=\'billpaylite\';\"> Laywer Bill - Operating Template\n";
  print "<br><input type=\"radio\" name=\"template\" value=\"laywerbill_trust_template\" onClick=\"document.templateform.type.value=\'billpaylite\';\"> Laywer Bill - Trust Template\n";
  print "</td>\n";
  print "  </tr>\n";

  print "  <tr class=\"listrow_color2\">\n";
  print "    <td colspan=2><b>Pay Screen</b></td>\n";
  print "  </tr>\n";

  print "  <tr class=\"listrow_color1\">\n";
  print "    <td colspan=2><input type=\"radio\" name=\"template\" value=\"affiniscap_logo\" onClick=\"document.templateform.type.value=\'payscreen\';\"> Affiniscape Gray Template with Logo\n";
  print "<br><input type=\"radio\" name=\"template\" value=\"affiniscap_nologo\" onClick=\"document.templateform.type.value=\'payscreen\';\"> Affiniscape Gray Template without Logo\n";
  print "</td>\n";
  print "  </tr>\n";

  print "  <tr class=\"listrow_color2\">\n";
  print "    <td colspan=2><b>Thank You</b></td>\n";
  print "  </tr>\n";

  print "  <tr class=\"listrow_color1\">\n";
  print "    <td colspan=2><i> &nbsp; No Pre-Configured Thank You Templates Available</i></td>\n";
  print "  </tr>\n";

  print "  <tr class=\"listrow_color2\">\n";
  print "    <td colspan=2><b>Transition</b></td>\n";
  print "  </tr>\n";

  print "  <tr class=\"listrow_color1\">\n";
  print "    <td colspan=2><i> &nbsp; No Pre-Configured Transition Templates Available</i></td>\n";
  print "  </tr>\n";

  print "</table>\n";

  print "<br><input type=\"submit\" value=\"Apply Template\">\n";
  print "</form>\n";

  &html_tail();
  return;
}

sub update_template {
  my %query = @_;

  # define paired templates
  # Format: "TYPE,TEMPLATE" => ["TYPE2,TEMPLATE2", "TYPE3,TEMPLATE3","TYPE4,TEMPLATE4", ... ],
  my %template_pairs = (
    "billpaylite,affiniscapebase_gray_template" => ["payscreen,affiniscapebase_gray_paytemplate"],
    "billpaylite,laywerbill_operating_template" => ["payscreen,laywerbill_operating_paytemplate"],
    "billpaylite,laywerbill_trust_template"     => ["payscreen,laywerbill_trust_paytemplate"],
    "billpaylite,laywerbill_template"           => ["payscreen,lawyerbill_paytemplate"]
  );

  # only let reseller update links to accounts which belong to them
  my $is_ok = &is_reseller_account($query{'username'});
  if ($is_ok ne "yes") {
    &show_error("Account Does Not Exist Or Does Not Belong To Reseller");
  }

  # ensure no tampering with type
  if ($query{'type'} !~ /^(transition|payscreen|thankyou|billpaylite)$/) {
    my $error = "The location you are attempting to add to is not permitted.\n";
    &show_error("$error");
    return;
  }

  $response = &apply_template("$query{'username'}","$query{'type'}","$query{'template'}");

  # now see if we need to apply extra templates, if its paired
  my @templates;
  my $pair_name = "$query{'type'}\,$query{'template'}";

  if ($template_pairs{"$pair_name"}[0] =~ /[a-zA-Z0-9]\,[a-zA-Z0-9]/) {
    @templates = @{$template_pairs{"$pair_name"}};
    for (my $i = 0; $i <= $#templates; $i++) {
      my ($ptype, $ptemplate) = split(/\,/, $templates[$i], 2);
      $response .=  &apply_template("$query{'username'}","$ptype","$ptemplate");
    }
  }

  return;
}

sub apply_template {
  my ($username, $type, $template) = @_;

  # clean & filter template name & language
  $type =~ s/[^a-zA-Z0-9\_\-]//g; # remove all non-alphanumeric characters
  $type = lc("$type"); # for value to lower case
  $type = substr($type,0,60);

  $template =~ s/[^a-zA-Z0-9\_\-]//g; # remove all non-alphanumeric characters
  $template = lc("$template"); # for value to lower case
  $template = substr($template,0,60);

  $username =~ s/[^a-zA-Z0-9]//g; # remove all non-alphanumeric characters
  $username = lc("$username"); # for value to lower case
  $username = substr($username,0,12);

  my $display_name = $template;
  $display_name =~ s/\_/ /g;

  my $source_path = ""; # holds absolute path to the source template
  my $target_path = ""; # holds absolute path to the target template
  my $filename = ""; # holds filename of target path

  # apply template to merchant's account as necessasry
  if ($type =~ /^(billpaylite)$/) {
    if ($template eq "affiniscapebase_template") {
      $source_path = "$template_dir\/$type\/affiniscapebase_template\.txt";
      $filename = "$username\_template\.txt";
      $target_path = "$template_dir\/$type\/$filename";
    }
    elsif ($template eq "affiniscapebase_gray_template") {
      $source_path = "$template_dir\/$type\/affiniscapebase_gray_template\.txt";
      $filename = "$username\_template\.txt";
      $target_path = "$template_dir\/$type\/$filename";
    }
    elsif ($template eq "laywerbill_template") {
      $source_path = "$template_dir\/$type\/laywerbill_template.txt";
      $filename = "$username\_template\.txt";
      $target_path = "$template_dir\/$type\/$filename";
    }
    elsif ($template eq "laywerbill_operating_template") {
      $source_path = "$template_dir\/$type\/laywerbill_operating_template.txt";
      $filename = "$username\_template\.txt";
      $target_path = "$template_dir\/$type\/$filename";
    }
    elsif ($template eq "laywerbill_trust_template") {
      $source_path = "$template_dir\/$type\/laywerbill_trust_template.txt";
      $filename = "$username\_template\.txt";
      $target_path = "$template_dir\/$type\/$filename";
    }
  }
  elsif ($type =~ /^(payscreen)$/) {
    if ($template eq "affiniscap_logo") {
      $source_path = "$template_dir\/$type\/affiniscap_logo\.txt";
      $filename = "$username\_paytemplate\.txt";
      $target_path = "$template_dir\/$type\/$filename";
    }
    elsif ($template eq "affiniscap_nologo") {
      $source_path = "$template_dir\/$type\/affiniscap_nologo\.txt";
      $filename = "$username\_paytemplate\.txt";
      $target_path = "$template_dir\/$type\/$filename";
    }
    elsif ($template eq "affiniscapebase_gray_paytemplate") {
      $source_path = "$template_dir\/$type\/affiniscapebase_gray_paytemplate\.txt";
      $filename = "$username\_paytemplate\.txt";
      $target_path = "$template_dir\/$type\/$filename";
    }
    elsif ($template eq "laywerbill_operating_paytemplate") {
      $source_path = "$template_dir\/$type\/laywerbill_operating_paytemplate\.txt";
      $filename = "$username\_paytemplate\.txt";
      $target_path = "$template_dir\/$type\/$filename";
    }
    elsif ($template eq "laywerbill_trust_paytemplate") {
      $source_path = "$template_dir\/$type\/laywerbill_trust_paytemplate\.txt";
      $filename = "$username\_paytemplate\.txt";
      $target_path = "$template_dir\/$type\/$filename";
    }
    elsif ($template eq "lawyerbill_paytemplate") {
      $source_path = "$template_dir\/$type\/lawyerbill_paytemplate\.txt";
      $filename = "$username\_paytemplate\.txt";
      $target_path = "$template_dir\/$type\/$filename";
    }
  }
  elsif ($type =~ /^(thankyou)$/) {
    # nothing to do...
  }
  else { ## assume transition template
    # nothing to do...
  }

  if (($source_path ne "") && ($target_path ne "")) {
    my $tmptarget_path = "/home/p/pay1/webtxt/uploaddir/$username\_$filename"; # set path to temp location where template file needs to be placed

    &sysutils::filelog("write",">$tmptarget_path");
    open(INFILE, "$source_path") or print "Cannot open source template for reading. $!";
    open(OUTFILE, ">$tmptarget_path") or print "Cannot open target template for writing. $!";
    while (<INFILE>) {
      print OUTFILE $_;
    }
    close(INFILE);
    close(OUTFILE);

    chmod(0666, "$tmptarget_path"); # force 666 file permissions
    &sysutils::logupload("$username","upload","$target_path","$tmptarget_path"); # set temp file to be uploaded to final location

    return "<p class=\"response_text\">The \'$display_name\' template will be applied to the account in 1 minute.</p>\n";
  }
  else {
    return "<p class=\"error_text\">Could not apply \'$display_name\' template to the account.  Please try again.</p>\n";
  }
}

sub is_reseller_account {
  # checks to see if username belongs to the given reseller
  my ($username) = @_;

  if ($username !~ /\w/) {
    return "no";
  }

  my $sth = $dbh_misc->prepare(qq{
    select username
    from customers
    where username=? and reseller=?
  }) or print "Can't do: $DBI::errstr";
  $sth->execute("$username", "$ENV{'REMOTE_USER'}") or print "Can't execute: $DBI::errstr";
  my ($test) = $sth->fetchrow;
  $sth->finish;

  # this code simply gives back a 'yes' or 'no' answer
  if ($test eq "$username") {
    return "yes";
  }
  else {
    return "no";
  }
}

sub delete_template {
  # unlink all accounts from the master username
  my %query = @_;

  # only let reseller view accounts which belong to them
  my $is_ok = &is_reseller_account("$query{'username'}");
  if ($is_ok ne "yes") {
    &show_error("Account Does Not Exist Or Does Not Belong To Reseller");
  }

  # ensure no tampering with upload_type
  if ($query{'type'} !~ /^(transition|payscreen|thankyou|billpaylite)$/) {
    my $error = "The location you are attempting to delete from is not permitted.\n";
    &show_error("$error");
    return;
  }

  # clean & filter template name & language
  $query{'template'} =~ s/[^a-zA-Z0-9]//g; # remove all non-alphanumeric characters
  $query{'template'} = lc("$query{'template'}"); # for value to lower case
  $query{'template'} = substr($query{'template'},0,60);

  $query{'language'} =~ s/[^a-zA-Z]//g; # remove all non-alpha characters
  $query{'language'} = lc("$query{'language'}"); # for value to lower case
  $query{'language'} = substr($query{'language'},0,2);

  # delete older file for merchant if necessary
  if ($query{'type'} =~ /^(billpaylite)$/) {
    unlink(glob("$template_dir\/$query{'type'}\/$query{'username'}\_template\.txt"));
    &sysutils::logupload("$query{'username'}","delete","$template_dir\/$query{'type'}\/$query{'username'}\_template\.txt");
  }
  elsif ($query{'type'} =~ /^(payscreen)$/) {
    if ($query{'language'} ne "") {
      unlink(glob("$template_dir\/$query{'type'}\/$query{'username'}\_$query{'language'}\_$query{'template'}\.txt"));
      &sysutils::logupload("$query{'username'}","delete","$template_dir\/$query{'type'}\/$query{'username'}\_$query{'language'}\_$query{'template'}\.txt");
    }
    else {
      unlink(glob("$template_dir\/$query{'type'}\/$query{'username'}\_$query{'template'}\.txt"));
      &sysutils::logupload("$query{'username'}","delete","$template_dir\/$query{'type'}\/$query{'username'}\_$query{'template'}\.txt");
    }
  }
  elsif ($query{'type'} =~ /^(thankyou)$/) {
    unlink(glob("$template_dir\/$query{'type'}\/$query{'username'}\.htm"));
    &sysutils::logupload("$query{'username'}","delete","$template_dir\/$query{'type'}\/$query{'username'}\.htm");
  }
  else { ## assume transition template
    unlink(glob("$template_dir\/$query{'type'}\/$query{'username'}\_$query{'template'}\.html"));
    &sysutils::logupload("$query{'username'}","delete","$template_dir\/$query{'type'}\/$query{'username'}\_$query{'template'}\.html");
  }

  $response = "<p class=\"response_text\">The template will be removed from the account in 1 minute.\n";

  return;
}

