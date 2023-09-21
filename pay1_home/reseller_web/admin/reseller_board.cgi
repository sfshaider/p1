#!/bin/env perl

# Online Reseller FAQ Board
# Version 1.5

# Written By James Turansky
# Last Updated: 08/06/15

require 5.001;

$|=1;

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use pnp_environment;
use miscutils;
use PlugNPay::Sys::Time;
use PlugNPay::UI::Template;
use PlugNPay::Reseller::FAQ;
use PlugNPay::InputValidator;

my %query = PlugNPay::InputValidator::filteredQuery('reseller_board');

if (($ENV{'HTTP_X_FORWARDED_SERVER'} ne "") && ($ENV{'HTTP_X_FORWARDED_FOR'} ne "")) {
  $ENV{'HTTP_HOST'} = (split(/\,/,$ENV{'HTTP_X_FORWARDED_HOST'}))[0];
  $ENV{'SERVER_NAME'} = (split(/\,/,$ENV{'HTTP_X_FORWARDED_SERVER'}))[0];
}

if (($ENV{'SEC_LEVEL'} eq "") && ($ENV{'REDIRECT_SEC_LEVEL'} ne "")) {
  $ENV{'SEC_LEVEL'} = $ENV{'REDIRECT_SEC_LEVEL'};
}

if (($ENV{'LOGIN'} eq "") && ($ENV{'REDIRECT_LOGIN'} ne "")) {
  $ENV{'LOGIN'} = $ENV{'REDIRECT_LOGIN'};
}

print "Content-Type: text/html\n\n";

# Initialize Values Here
my $path_webtxt = &pnp_environment::get('PNP_WEB_TXT');

my $reseller_faq_file = "$path_webtxt/newreseller/admin/reseller_board/reseller_board.db"; # Sets path to FAQ database text file
my $reseller_faq_swap = "$path_webtxt/newreseller/admin/reseller_board/reseller_board.swp"; # sets path to FAQ datbase swap/temp file
my $reseller_faq_help = "$path_webtxt/newreseller/admin/reseller_board/reseller_board_help.htm"; # Sets path to FAQ help document
my $reseller_faq_log = "$path_webtxt/newreseller/admin/reseller_board/reseller_board.log"; # Sets path to FAQ query/usage log
my $reseller_faq_most_active_file = "$path_webtxt/newreseller/admin/reseller_board/reseller_board_most_active.htm"; # sets path to FAQ most active doc.

my $enable_logging = "yes"; # set to "yes" if you want to log all FAQ searches, queries, etc.

my $set_auto_refresh = 0; # initialize value, default is refresh automatically (0 = off, 1 = off)
my $refresh_minutes = 30; # initialize value, minutes before page is automatically refreshed.

# Email Backup Options:
my $email      = "rridings\@plugnpay.com";  # TO Email Address to send FAQ issue.
my $cc_email   = "turajb\@plugnpay.com";                        # CC Email Address to send FAQ issue.  [default value is "" ==> NULL Value]
my $bcc_email  = "";                        # BCC Email Address to send FAQ issue. [default value is "" ==> NULL Value]
my $subject    = "";                        # Custom email Subject header [default value is "" ==> NULL Value]
my $from_email = "reseller_faq\@plugnpay.com"; # FROM/REPLY Email Address

my $data = ""; # initialize data field

# List Sections Here
my @sections = ();

my $FAQ = new PlugNPay::Reseller::FAQ();
my $categoryInfo = $FAQ->retrieveSections();

foreach my $category (sort keys %$categoryInfo){
  push @sections, [$category, $categoryInfo->{$category}];
}
#  ['all',           'All Categories'],
#  ['news_letter',   'News Letter Archive'],
#  ['news_announce', 'Service/News Announcements'],
#  ['product',       'Product Information'],
#  ['reseller_faq',  'Reseller FAQ'],
#  ['sales_faq',     'Sales FAQ'],
#  ['training',      'Reseller Training'],
#  ['support',       'Reseller Support'],
#  ['api',           'API Usage & Integration'],
#);

# list valid admin usernames here
my @admin_users = ('jamest', 'barbara', 'rriding', 'wdunkak', 'dmongell','dylaninc');

# see if user is an administrator
my $admin = 0; # initialize & assume user is not an admin user
for (my $a = 0; $a <= $#admin_users; $a++) {
  if ($ENV{'REMOTE_USER'} eq "$admin_users[$a]") {
    $admin = 1; # if match, set admin flag
  }
}

# Select Mode
if ($query{'mode'} eq "help") {
  &help();
}
elsif ($query{'mode'} eq "most_active") {
  &most_active();
}
elsif ($query{'mode'} eq "new_issue") {
  &new_issue();
}
elsif ($query{'mode'} eq "add_issue") {
  %query = &html_filter(%query);
  &add_issue($query{'category'}, $query{'issue'}, $query{'description'}, $query{'keywords'}, $query{'id_number'});
  &show_menu();
}
elsif ($query{'mode'} eq "edit_issue") {
  &edit_issue("$query{'id_number'}");
}
elsif ($query{'mode'} eq "update_issue") {
  %query = &html_filter(%query);
  &update_issue($query{'category'}, $query{'issue'}, $query{'description'}, $query{'keywords'}, $query{'id_number'});
  &show_menu();
}
elsif ($query{'mode'} eq "delete_issue") {
  &delete_issue("$query{'id_number'}");
  &show_menu();
}
elsif ($query{'mode'} eq "search_issue") {
  &search_issue($query{'search_keys'}, $query{'category'}, $query{'minimum_match'});
}
elsif ($query{'mode'} eq "view_description") {
  &view_description($query{'id_number'});
}
else {
  &show_menu();
}
exit;

sub category_list {
  my ($mode, $category) = @_;

  # generates category list drop-down
  my $data = "<select name=\"category\">\n";
  for (my $s = 0; $s <= $#sections; $s++) {
    if ((($mode eq "new_issue") || ($mode eq "edit_issue")) && ($s == 0)) {
      # skip 'all' option if it's a new issue or if you are editing a issue
    }
    else {
      $data .= "<option value=\"$sections[$s][0]\"";
      if (($category eq "$sections[$s][0]") && ($query{'mode'} ne "update_issue")) {
        $data .= " selected";
      }
      $data .= ">$sections[$s][1]</option>\n";
    }
  }
  $data .= "</select>\n";

  return $data;
}

sub new_issue {

  # output new issue form
  &html_head();
  print "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
  print "<input type=\"hidden\" name=\"mode\" value=\"add_issue\">\n";
  print "<p><table border=\"0\">\n";
  print "  <tr>\n";
  print "    <th class=\"menutitle\" colspan=\"2\">Add New Issue:</th>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"menuleft\">&nbsp; Category: &nbsp;</th>\n";
  print "    <td>";
  print &category_list("new_issue", "");
  print "</td>\n";
  print "  </tr>\n";
  print "    <th class=\"menuleft\">&nbsp; Issue: &nbsp;</th>\n";
  print "    <td><input type=\"text\" name=\"issue\" value=\"\" size=\"50\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"menuleft\">&nbsp; Description: &nbsp;</th>\n";
  print "    <td><textarea name=\"description\" cols=\"50\" rows=\"15\"></textarea></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"menuleft\">&nbsp; Keywords: &nbsp;</th>\n";
  print "    <td><input type=\"text\" name=\"keywords\" value=\"\" size=\"50\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"menuleft\">&nbsp; &nbsp;</th>\n";
  print "    <td><table border=\"0\">\n";
  print "      <tr>\n";
  print "        <td><input type=\"submit\" class=\"button\" value=\"Add Issue\"></td></form>\n";
  print "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
  print "<input type=\"hidden\" name=\"mode\" value=\"show_menu\">\n";
  print "        <td><input type=\"submit\" class=\"button\" value=\"Cancel Operation\"></td>\n";
  print "      </tr>\n";
  print "    </table>\n";
  print "    </form></td>\n";
  print "  </tr>\n";
  print "</table>\n";
  &html_tail();

  return;
}

sub add_issue {
  my ($category, $issue, $description, $keywords, $id_number) = @_;

  if ($admin != 1) {
    # if not admin, do not allow update
    return;
  }

  # check for ID number; if non-assigned, assign one
  if ($id_number eq "") {
    $id_number = &create_id_number();
  }

  my $FAQ = new PlugNPay::Reseller::FAQ();
  $FAQ->addFAQIssue($category,$issue,$description,$keywords,$id_number,'ID');

  if ($enable_logging eq "yes") {
    my @now = gmtime(time); # grab current time/date
    my $time_stamp = sprintf("%04d%02d%02d%02d%02d%02d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], $now[0]);
    # store ID number viewed
    $reseller_faq_file =~ s/[^a-zA-Z0-9\_\-\.\/]//g;
    open(LOG, ">>$reseller_faq_log") or die "Cannot open $reseller_faq_log for appending. $!";
    print LOG "$ENV{'REMOTE_ADDR'}\t$time_stamp\tADD";
    print LOG "\tusername|$ENV{'REMOTE_USER'}";
    print LOG "\tid_number|$id_number";
    print LOG "\n";
    close(LOG);
  }

  &email_backup()
  &view_description($id_number);
  return;
}

sub html_filter {
  my %query = @_;

  # reformat issue
  $query{'issue'} =~ s/\&/\&amp\;/g;
  $query{'issue'} =~ s/\"/\&quot\;/g;
  $query{'issue'} =~ s/\</\&lt\;/g;
  $query{'issue'} =~ s/\>/\&gt\;/g;
  $query{'issue'} =~ s/  /\&nbsp\; /g;
  #$query{'issue'} =~ s/[^a-zA-Z_0-9_\,_\._\;_\-_\?_\!_\@_\#_\$_\%_\^_\&_\*_\(_\)_ _\\_\+]//g;

  # reformat description
  $query{'description'} =~ s/\&/\&amp\;/g;
  $query{'description'} =~ s/\"/\&quot\;/g;
  $query{'description'} =~ s/\</\&lt\;/g;
  $query{'description'} =~ s/\>/\&gt\;/g;
  $query{'description'} =~ s/  /\&nbsp\; /g;
  #$query{'description'} =~ s/[^a-zA-Z_0-9_\,_\._\;_\-_\?_\!_\@_\#_\$_\%_\^_\&_\*_\(_\)_ _\\_\+]//g;

  # format faq description
  $query{'description'} =~ s/\r\n/<br> /g;
  $query{'description'} =~ s/\r/<br>/g;
  $query{'description'} =~ s/\n/<br>/g;
  $query{'description'} =~ s/\t/ /g;

  # reformat keywords
  $query{'keywords'} =~ s/\&/\&amp\;/g;
  $query{'keywords'} =~ s/\"/\&quot\;/g;
  $query{'keywords'} =~ s/\</\&lt\;/g;
  $query{'keywords'} =~ s/\>/\&gt\;/g;
  $query{'keywords'} =~ s/  /\&nbsp\; /g;
  #$query{'keywords'} =~ s/[^a-zA-Z_0-9_\,_\._\;_\-_\?_\!_\@_\#_\$_\%_\^_\&_\*_\(_\)_ _\\_\+]//g;

  return %query;
}

sub create_id_number {
  my @now = gmtime(time); # initialize value
  my $id = sprintf("ID%04d%02d%02d%02d%02d%02d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], $now[0]);
  return $id;
}

sub output_header {
  my $data  = ""; # re-initialize data value

  # output page head section
  $data .= "<table border=\"0\" width=\"100%\">\n";
  #$data .= "  <tr>\n";
  #$data .= "    <td align=\"center\" colspan=\"3\"><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Logo\"></td>\n";
  #$data .= "  </tr>\n";
  $data .= "  <tr>\n";
  $data .= "    <td align=\"center\"><font size=\"+1\"><b>Online Reseller Issuer Center &amp; FAQ</b></font>\n";
  if ($set_auto_refresh == 1) {
    $data .= "      <br><font size=\"2\" color=\"\#FF0000\">* Please Note: This page will refresh itself every $refresh_minutes minutes.</font></td>\n";
  }
  $data .= "    <td align=\"right\" width=\"10\%\"><form><input type=\"button\" class=\"button\" value=\"Previous Screen\" onClick=\"javascript:history.go(-1)\"></td></form>\n";
  $data .= "    <td align=\"right\" width=\"10\%\"><form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
  $data .= "      <input type=\"hidden\" name=\"mode\" value=\"show_menu\">\n";
  $data .= "      <input type=\"submit\" class=\"button\" value=\"FAQ Main Menu\"></td></form>\n";

  # output new issue button
  if ($admin == 1) {
    $data .= "    <td align=\"right\" width=\"10\%\"><form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
    $data .= "      <input type=\"hidden\" name=\"mode\" value=\"new_issue\">\n";
    $data .= "      <input type=\"submit\" class=\"button\" value=\"Add New Issue\">\n";
    $data .= "   </td></form>\n";
    $data .= "  </tr>\n";
  }
  $data .= "</table>\n";
  $data .= "<hr>\n";

  return $data;
}

sub search_issue {
  my ($search_keys, $category, $minimum_match) = @_;

  my $switch = 0; # used to alternate issue colors
  my $find_match = 0; # total number of issues matched
  my $display_match = 0; # number of issues displayed

  my $data .= &output_header();
  $data .= "<table width=\"100\%\" border=\"0\">\n";
  $data .= "  <tr>\n";
  if ($search_keys ne "") {
    $data .= "    <th class=\"menutitle\">Match:</th>\n";
  }
  $data .= "    <th class=\"menutitle\">Issue:</th>\n";
  $data .= "    <th class=\"menutitle\">Category:</th>\n";
  $data .= "    <th class=\"menutitle\">ID Number:</th>\n";
  $data .= "    <th class=\"menutitle\">&nbsp; </th>\n";
  if ($admin == 1) {
    $data .= "    <th class=\"menutitle\" colspan=\"2\">&nbsp;</th>\n";
  }
  $data .= "  </tr>\n";

  my $FAQ = new PlugNPay::Reseller::FAQ();

  my @split_words = split(',',$search_keys);
  my $num_of_keys = @split_words;

  # open faq file
  my $answers = $FAQ->searchKeywords($search_keys,$category,1);
  # read into memory
  foreach my $key ( keys %$answers) {
    my $issue = $answers->{$key};

    $find_match++;
    my $match_percentage;
    if ($search_keys ne "") {
      # figure out keyword match percentage
      $match_percentage = (($issue->{'matches'} / $num_of_keys) * 100);
      # perform adjustment where some matches have over a 100% match rate
      if ($match_percentage > 100) {
        $match_percentage = 100;
      }
    }

    if (($minimum_match eq "") || ($minimum_match <= $match_percentage)) {
      $display_match++; # incriment the displayed match counter (indicates issue was displayed)
      # display matching issue
      $switch = ($switch + 1) % 2;
      $data .= &view_issue($switch, $match_percentage,$issue->{'category'}, $issue->{'shortQuestion'}, $issue->{'answer'}, $issue->{'keywords'},$issue->{'issueID'});
    }
  }

  if ($find_match == 0) {
    $data .= "  <tr>\n";
    $data .= "    <td>Sorry, there are no frequently asked issues which match your query.</td>\n";
    $data .= "  </tr>\n";
  }
  elsif (($display_match < $find_match) && ($search_keys ne "")) {
    $data .= "  <tr>\n";
    $data .= "    <td colspan=\"5\" align=\"center\"><b>&nbsp;<br>Your search criteria resulted in $display_match of $find_match possible matches.</b></td>\n";
    $data .= "  </tr>\n";
  }

  $data .= "  <tr>\n";
  $data .= "    <td colspan=\"5\" align=\"center\">&nbsp;<br>\n";

  $data .= "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
  $data .= "<input type=\"hidden\" name=\"mode\" value=\"search_issue\">\n";
 
  $data .= "<table border=\"0\">\n";
  $data .= "  <tr>\n";
  $data .= "    <th class=\"menutitle\" colspan=\"3\">Can't find what you are looking for? Try refining your search criteria:</th>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <th class=\"menuleft\"> Search For: </th>\n";
  $data .= "    <td><input type=\"text\" name=\"search_keys\" value=\"$search_keys\" size=\"40\">\n";
  $data .= "      <br><font size=\"-2\" color=\"#bb0000\"><i>* Note: Separate Keywords &amp; Key Phrases With a \" \, \" or \" \; \"</i></font></td>\n";
  $data .= "    <td><a href=\"$ENV{'SCRIPT_NAME'}\?mode=help\" target=\"faq_help\"><font size=\"2\" color=\"\#0000ff\"><b>Help</b></font></a></td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <th class=\"menuleft\">&nbsp; In Category: &nbsp;</th>\n";
  $data .= "    <td>";

  $data .= "<select name=\"category\">\n";
  for ($a = 0; $a <= $#sections; $a++) {
    $data .= "<option value=\"$sections[$a][0]\"";
    if ($category eq $sections[$a][0]) {
      $data .= " selected";
    }
    $data .= ">$sections[$a][1]</option>\n";
  }
  $data .= "</select>\n";

  $data .= "</td>\n";
  $data .= "    <td>&nbsp;</td>\n";
  $data .= "  </tr>\n";
 
  $data .= "  <tr>\n";
  $data .= "    <th class=\"menuleft\">&nbsp; Minimum Match: &nbsp;</th>\n";
  $data .= "    <td>Show <select name=\"minimum_match\">\n";
  $data .= "      <option value=\"\">All Matching Issues</option>\n";
  for ($a = 5; $a <= 100; $a = $a + 5) {
    $data .= "      <option value=\"$a\" ";
    if ($minimum_match == $a) {
      $data .= "selected";
    }
    $data .= ">$a \% match or greater</option>\n";
  }
  $data .= "      </select></td>\n";
  $data .= "    <td><input type=\"submit\" class=\"button\" value=\"Search\"></td></form>\n";
  $data .= "  </tr>\n";
  $data .= "</table>\n";

  $data .= "    </td>\n";
  $data .= "  </tr>\n";
  $data .= "</table>\n";

  # output to screen
  &html_head();
  print "<script Language=\"Javascript\">\n";
  print "function delete_confirm() {\n";
  print "  return confirm('Are you sure?')\;\n";
  print "}\n";
  print "</script>\n";
  print $data;
  &html_tail();

  if ($enable_logging eq "yes") {
    my @now = gmtime(time); # grab current time/date
    my $time_stamp = sprintf("%04d%02d%02d%02d%02d%02d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], $now[0]);
    # store ID number viewed
    $reseller_faq_file =~ s/[^a-zA-Z0-9\_\-\.\/]//g;
    open(LOG, ">>$reseller_faq_log") or die "Cannot open $reseller_faq_log for appending. $!";
    print LOG "$ENV{'REMOTE_ADDR'}\t$time_stamp\tQUERY";
    print LOG "\tsearch_keys|$search_keys";
    print LOG "\tcategory|$category";
    print LOG "\tminimum_match|$minimum_match";
    print LOG "\n";
    close(LOG);
  }
  return;
}

sub view_issue {
  my ($switch, $match_percentage, $category, $question, $answer, $keywords, $id) = @_;

  my ($color, $match_color);

  if ($switch == 0) {
    $color = "ffffff"; # white bacground
  }
  else {
    $color = "f3f9e8"; # gray background
  }

  if ($match_percentage >= 75) {
    $match_color = "ff0000";
  }
  elsif (($match_percentage < 75) && ($match_percentage >= 50)) {
    $match_color = "00dd00";
  }
  elsif (($match_percentage < 50) && ($match_percentage >= 25)) {
    $match_color = "0000dd";
  }
  else {
    $match_color = "000000";
  }

  my $data = "  <tr>\n";
  if ($query{'search_keys'} ne "") {
    $data .= sprintf("    <td width=\"5%%\" bgcolor=\"\#%s\" align=\"right\"><font color=\"\#%s\">%2.0d%%</font></td>\n", $color, $match_color, $match_percentage);
  }
  $data .= "    <td align=\"left\" bgcolor=\"\#$color\" style=\"white-space:pre-wrap\">$question</td>\n"; # this is the issue
  $data .= "    <td width=\"20\%\" bgcolor=\"\#$color\">";
  for ($a = 0; $a <= $#sections; $a++) {
    if ($category eq $sections[$a][0]) {
      $data .= $sections[$a][1] . "\n";
    }
  }
  $data .= "</td>\n"; # this is the category
  $data .= "    <td width=\"10\%\" bgcolor=\"\#$color\">" . $id . "</td>\n"; # this is the ID nuumber
  $data .= "    <td width=\"10\%\" align=\"center\" bgcolor=\"\#$color\"><form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
  $data .= "      <input type=\"hidden\" name=\"mode\" value=\"view_description\">\n";
  $data .= "      <input type=\"hidden\" name=\"id_number\" value=\"" . $id . "\">\n";
  $data .= "      <input type=\"submit\" class=\"button\" value=\"View Description\"></td></form>\n";

  # output delete/edit buttons
  if ($admin == 1) {
    $data .= "    <td width=\"5\%\" bgcolor=\"\#$color\"><form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
    $data .= "      <input type=\"hidden\" name=\"mode\" value=\"delete_issue\">\n";
    $data .= "      <input type=\"hidden\" name=\"id_number\" value=\"" . $id . "\">\n";
    $data .= "      <input type=\"submit\" class=\"button\" value=\"Delete\" onClick=\"return delete_confirm()\;\">\n";
    $data .= "    </td></form>\n";
    $data .= "    <td width=\"5\%\" bgcolor=\"\#$color\"><form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
    $data .= "      <input type=\"hidden\" name=\"mode\" value=\"edit_issue\">\n";
    $data .= "      <input type=\"hidden\" name=\"id_number\" value=\"" . $id . "\">\n";
    $data .= "      <input type=\"submit\" class=\"button\" value=\"Edit\">\n";
    $data .= "    </td></form>\n";
  }
  $data .= "  </tr>\n";

  return $data;
}

sub view_description {
  my ($id_number) = @_;

  my @temp = ();

  my $data = &output_header();
  my $FAQ = new PlugNPay::Reseller::FAQ();
  my $issue = $FAQ->get(uc($id_number),1);

  my @temp = ($issue->{'category'},$issue->{'question'},$issue->{'answer'},$issue->{'keywords'},$issue->{'issueID'});


  # inset domain where necessary
  $temp[2] =~ s/{your-secure-payment-server-domain}/$ENV{'HTTP_HOST'}/g;

  $data .= "<table border=\"0\" width=\"100%\">\n";
  $data .= "  <tr>\n";
  $data .= "    <th class=\"menutitle\" colspan=\"2\"> ID Number: $temp[4]</th>\n";
  $data .= "  </tr>\n";

  #$data .= "  <tr>\n";
  #$data .= "    <th class=\"menuleft\" width=\"12\%\"> ID Number: </th>\n";
  #$data .= "    <td>$temp[4]</td>\n";
  #$data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <th class=\"menuleft\" width=\"10%\"> Category: </th>\n";
  $data .= "    <td>";
  for ($a = 0; $a <= $#sections; $a++) {
    if ($temp[0] eq "$sections[$a][0]") {
      $data .= "$sections[$a][1]\n";
    }
  }
  $data .= "</td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <th class=\"menuleft\" width=\"10%\"> Issue: </th>\n";
  $data .= "    <td style=\"white-space:pre-wrap\">$temp[1] <br>&nbsp;</td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <th valign=\"top\" class=\"menuleft\" width=\"10%\"> &nbsp;<br> Description: </th>\n";
  $data .= "    <td style=\"white-space:pre-wrap\">$temp[2] <br> &nbsp;</td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <th class=\"menuleft\" width=\"10%\"> Keywords: </th>\n";
  $data .= "    <td>$temp[3]</td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <th class=\"menuleft\" width=\"10%\"> &nbsp; </th>\n";
  $data .= "    <td align=\"right\">\n";
  # print page button
  $data .= "<form><input type=\"button\" class=\"button\" name=\"print_button\" value=\"Print Page\" onclick=\"window.print()\;\">\n";

  # clean up after the issue raw data
  chomp $temp[0];
  chomp $temp[1];
  chomp $temp[2];
  chomp $temp[3];
  chomp $temp[4];

  # email ISSUE ID number
  $data .= "<script language=\"JavaScript\">\n";
  $data .= "<\!--\n";
  $data .= "function mailpage()\n";
  $data .= "\{\n";
  $data .= "  mail_str = \"mailto\:\?subject=FAQ Issue Forward: $temp[4]\"\;\n";
  $data .= "  mail_str += \"\&body=Reseller FAQ Issue: $temp[1] -- Please see ID number $temp[4] in the online reseller FAQ for description details.\"\;\n";
  $data .= "  location.href = mail_str\;\n";
  $data .= "\}\n";
  $data .= "-->\n";
  $data .= "</script>\n";
  $data .= "<input type=\"button\" class=\"button\" name=\"email_button2\" value=\"Email ID Number\" onclick=\"javascript\:mailpage()\;\">\n";
  $data .= "</td></form>\n";
  $data .= "  </tr>\n";
  $data .= "</table>\n";

  # output delete/edit buttons
  if ($admin == 1) {
    $data .= "<div align=\"right\">\n";
    $data .= "<p><table border=\"1\">\n";
    $data .= "  <tr>\n";
    $data .= "    <td><form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
    $data .= "      <input type=\"hidden\" name=\"mode\" value=\"delete_issue\">\n";
    $data .= "      <input type=\"hidden\" name=\"id_number\" value=\"$temp[4]\">\n";
    $data .= "      <input type=\"submit\" class=\"button\" class=\"button\" value=\"Delete Issue\" onClick=\"return delete_confirm()\;\">\n";
    $data .= "    </td></form>\n";
    $data .= "    <td><form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
    $data .= "      <input type=\"hidden\" name=\"mode\" value=\"edit_issue\">\n";
    $data .= "      <input type=\"hidden\" name=\"id_number\" value=\"$temp[4]\">\n";
    $data .= "      <input type=\"submit\" class=\"button\" class=\"button\" value=\"Edit Issue\">\n";
    $data .= "    </td></form>\n";
    $data .= "  </tr>\n";
    $data .= "</table>\n";
    $data .= "</div>\n";
  }

  # output to screen
  &html_head();
  print "<script Language=\"Javascript\">\n";
  print "function delete_confirm() {\n";
  print "  return confirm('Are you sure?')\;\n";
  print "}\n";
  print "</script>\n";
  print "$data";
  &html_tail();

  if ($enable_logging eq "yes") {
    my @now = gmtime(time); # grab current time/date
    my $time_stamp = sprintf("%04d%02d%02d%02d%02d%02d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], $now[0]);
    # store ID number viewed
    $reseller_faq_file =~ s/[^a-zA-Z0-9\_\-\.\/]//g;
    open(LOG, ">>$reseller_faq_log") or die "Cannot open $reseller_faq_log for appending. $!";
    print LOG "$ENV{'REMOTE_ADDR'}\t$time_stamp\tVIEW";
    print LOG "\tid_number|$temp[4]";
    print LOG "\n";
    close(LOG);
  }

  return;
}

sub edit_issue {
  my ($id_number) = @_;
  
  my $FAQ = new PlugNPay::Reseller::FAQ();
  my $issueHash = $FAQ->get(uc($id_number), 0);

  my @temp = ();

  # read faq file until found issue to edit
  push @temp, $issueHash->{'category'};
  push @temp, $issueHash->{'question'};
  push @temp, $issueHash->{'answer'};
  push @temp, $issueHash->{'keywords'};
  push @temp, $issueHash->{'issueID'};
  
  # reformat data to properly display in text are box
  $temp[2] =~ s/<br> /\r\n/g;

  # output edit issue form to screen
  &html_head();
  print "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
  print "<input type=\"hidden\" name=\"mode\" value=\"update_issue\">\n";
  print "<p><table border=\"0\">\n";
  print "  <tr>\n";
  print "    <th colspan=\"2\" class=\"menutitle\">Edit Issue:</th>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"menuleft\">&nbsp; ID Number: &nbsp;</th>\n";
  print "    <td><input type=\"hidden\" name=\"id_number\" value=\"$temp[4]\">$temp[4]</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"menuleft\">&nbsp; Category: &nbsp;</th>\n";
  print "    <td>";
  print &category_list("edit_issue", $temp[0]);
  print "</td>\n";
  print "  </tr>\n";
  print "    <th class=\"menuleft\">&nbsp; Issue: &nbsp;</th>\n";
  print "    <td><input type=\"text\" name=\"issue\" value=\"$temp[1]\" size=\"50\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"menuleft\">&nbsp; Description: &nbsp;</th>\n";
  print "    <td><textarea name=\"description\" cols=\"50\" rows=\"15\">$temp[2]</textarea></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"menuleft\">&nbsp; Keywords: &nbsp;</th>\n";
  print "    <td><input type=\"text\" name=\"keywords\" value=\"$temp[3]\" size=\"50\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"menuleft\">&nbsp; &nbsp;</th>\n";
  print "    <td><table border=\"0\">\n";
  print "      <tr>\n";
  print "        <td><input type=\"submit\" class=\"button\" value=\"Update Issue\"></td></form>\n";
  print "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
  print "<input type=\"hidden\" name=\"mode\" value=\"show_menu\">\n";
  print "        <td><input type=\"submit\" class=\"button\" value=\"Cancel Operation\"></td>\n";
  print "      </tr>\n";
  print "    </table>\n";
  print "    </form></td>\n";
  print "  </tr>\n";
  print "</table>\n";
  &html_tail();
  return;
}

sub update_issue {
  my ($category, $issue, $description, $keywords, $id_number) = @_;

  if ($admin != 1) {
    # if not admin, do not allow update
    return;
  }

  # check for ID number; if non-assigned, assign one
  if ($id_number eq "") {
    $id_number = &create_id_number();
  }

  my $FAQ = new PlugNPay::Reseller::FAQ();
  $FAQ->addFAQIssue($category,$issue,$description,$keywords,$id_number);

  if ($enable_logging eq "yes") {
    my @now = gmtime(time); # grab current time/date
    my $time_stamp = sprintf("%04d%02d%02d%02d%02d%02d", $now[5], $now[4], $now[3], $now[2], $now[1], $now[0]);
    # store ID number viewed
    $reseller_faq_file =~ s/[^a-zA-Z0-9\_\-\.\/]//g;
    open(LOG, ">>$reseller_faq_log") or die "Cannot open $reseller_faq_log for appending. $!";
    print LOG "$ENV{'REMOTE_ADDR'}\t$time_stamp\tUPDATE";
    print LOG "\tusername|$ENV{'REMOTE_USER'}";
    print LOG "\tid_number|$id_number";
    print LOG "\n";
    close(LOG);
  }

  &email_backup();
  &view_description($id_number);
  return;
}

sub delete_issue {
  my ($id_number) = @_;

  my $FAQ = new PlugNPay::Reseller::FAQ();
  $FAQ->deleteFAQIssue($id_number);

  if ($enable_logging eq "yes") {
    my @now = gmtime(time); # grab current time/date
    my $time_stamp = sprintf("%04d%02d%02d%02d%02d%02d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], $now[0]);
    # store ID number viewed
    $reseller_faq_file =~ s/[^a-zA-Z0-9\_\-\.\/]//g;
    open(LOG, ">>$reseller_faq_log") or die "Cannot open $reseller_faq_log for appending. $!";
    print LOG "$ENV{'REMOTE_ADDR'}\t$time_stamp\tDELETE";
    print LOG "\tusername|$ENV{'REMOTE_USER'}";
    print LOG "\tid_number|$id_number";
    print LOG "\n";
    close(LOG);
  }

  &show_menu();
  return;
}

sub html_head {

  my $refresh_seconds = $refresh_minutes * 60; # figure up how many seconds.

  print "<html>\n";
  print "<head>\n";
  print "<title>Online Reseller Issue Center &amp; FAQ</title>\n";
  if ($set_auto_refresh == 1) {
    print "<meta http-equiv=\"Refresh\" content=\"$refresh_seconds; URL=$ENV{'SCRIPT_NAME'}\">\n";
  }
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"https://pay1.plugnpay.com/css/green.css\">\n";
  print "</head>\n";
  print "<body bgcolor=\"\#ffffff\" text=\"\#000000\">\n";

  print "<table width=\"750\">\n";
  print "  <tr>\n";
  print "    <td><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Payment Gateway Logo\"></td>\n";
  print "    <td class=\"right\">&nbsp;</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td colspan=\"2\"><img src=\"/adminlogos/masthead_background.gif\" alt=\"Corp. Logo\" width=\"750\" height=\"16\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table width=\"750\">\n";
  print "  <tr>\n";
  print "    <td align=\"left\">\n";

  return;
}

sub html_tail {

  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</body>\n";
  print "</html>\n";
  return;
}

sub show_menu {
  $data  = ""; # re-initialize data value

  # output page head section
  $data .= "<table border=\"0\" width=\"100%\">\n";
  #$data .= "  <tr>\n";
  #$data .= "    <td align=\"center\"><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Logo\"></td>\n";
  #$data .= "  </tr>\n";
  $data .= "  <tr>\n";
  $data .= "    <td align=\"left\"><font size=\"+1\"><b>Online Reseller Issue Center &amp; FAQ</b></font>\n";
  if ($set_auto_refresh == 1) {
    $data .= "      <br><font size=\"2\" color=\"\#FF0000\">* Please Note: This page will refresh itself every $refresh_minutes minutes.</font>\n";
  }
  $data .= "</td>\n";

  # output new issue button
  if ($admin == 1) {
    $data .= "  <td align=\"right\" width=\"10\%\"><form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
    $data .= "    <input type=\"hidden\" name=\"mode\" value=\"new_issue\">\n";
    $data .= "    <input type=\"submit\" class=\"button\" value=\"Add New Issue\">\n";
    $data .= "   </td></form>\n";
    $data .= "  </tr>\n";
  }
  $data .= "</table>\n";

  $data .= "<p>This portion of the site has been constructed to address reseller issues & frequently asked questions related to our services.  Below you should find all the information you will need in order to better resell & promote our services.  If you do not find the answer to your issue or question, please check out our merchant based online FAQ & documentation center.  If you find our information centers do not answer your issue or question, please submit your issue, comment, question or problem to <a href=\"mailto:sales\@plugnpay.com\">sales\@plugnpay.com</a>.</p>\n";
  $data .= "<p>When submitting a message, please be as specific as possible, providing examples where necessary.  Please also remember to include your contact information (name, email address &amp; phone number).</p>\n";
  $data .= "<p>Thank you,\n";
  $data .= "<br>Plug 'n Pay Sales Staff.</p>\n";

  $data .= "<hr>\n";

  # output to screen
  &html_head();
  print "$data";

  print "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\" name=\"TESTING\">\n";
  print "<input type=\"hidden\" name=\"mode\" value=\"search_issue\">\n";
  print " <table border=\"0\" width=\"100%\">\n";
  print "  <tr>\n";
  print "    <th class=\"menutitle\" colspan=\"3\">List Issues By Category:</th>\n";
  print "  </tr>\n";

  # category only search
  print "  <tr>\n";
  print "    <th class=\"menuleft\"> Category: </th>\n";
  print "    <td>";
  print &category_list("show_menu", "");
  print "</td>\n";
  print "    <td><input type=\"submit\" class=\"button\" value=\"View Category\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleft\">&nbsp;</td>\n";
  print "    <td colspan=\"2\">&nbsp;</td>\n"; 
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th class=\"menutitle\" colspan=\"3\">Search by Keywords or Key Phrases:</th>\n";
  print "  </tr>\n";
  print " </table>\n";
  print "</form>\n";

  # category/keyword search
  print "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
  print "<input type=\"hidden\" name=\"mode\" value=\"search_issue\">\n";

  print " <table border=\"0\" width=\"100%\">\n";
  print "  <tr>\n";
  print "    <th class=\"menuleft\"> Search For: </th>\n";
  print "    <td><input type=\"text\" name=\"search_keys\" value=\"\" size=\"40\">\n";
  print "      <br><font size=\"-2\" color=\"#bb0000\"><i>* Note: Separate Keywords &amp; Key Phrases With a \" \, \" or \" \; \"</i></font></td>\n";
  print "    <td><a href=\"$ENV{'SCRIPT_NAME'}\?mode=help\" target=\"faq_help\"><font size=\"2\" color=\"\#0000ff\"><b>Help</b></font></a></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th class=\"menuleft\">&nbsp; In Category: &nbsp;</th>\n";
  print "    <td>";
  print &category_list("show_menu", "");
  print "</td>\n";
  print "    <td>&nbsp;</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th class=\"menuleft\">&nbsp; Minimum Match: &nbsp;</th>\n";
  print "    <td>Show <select name=\"minimum_match\">\n";
  print "      <option value=\"\">All Matching Issues</option>\n";
  for (my $a = 5; $a <= 100; $a = $a + 5) {
    print "      <option value=\"$a\">$a \% match or greater</option>\n";
  }
  print "      </select></td>\n";
  print "    <td><input type=\"submit\" class=\"button\" value=\"Search\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleft\">&nbsp;</td>\n";
  print "    <td colspan=\"2\">&nbsp;</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th class=\"menutitle\" colspan=\"3\">Search by ID Number:</th>\n";
  print "  </tr>\n";
  print " </table>\n";
  print "</form>\n";

 
  # ID number search
  print "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
  print "<input type=\"hidden\" name=\"mode\" value=\"search_issue\">\n";
  print "<input type=\"hidden\" name=\"category\" value=\"all\">\n";

  print " <table border=\"0\" width=\"100%\">\n";
  print "  <tr>\n";
  print "    <th class=\"menuleft\">&nbsp; ID Number: &nbsp;</th>\n";
  print "    <td><input type=\"text\" name=\"search_keys\" value=\"\" size=\"40\"></td>\n";
  print "    <td colspan=\"2\"><input type=\"submit\" class=\"button\" value=\"Search\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleft\">&nbsp;</td>\n";
  print "    <td colspan=\"2\">&nbsp;</td>\n"; 
  print "  </tr>\n";
  print " </table>\n";
  print "</form>\n";

  # FAQ Most Active
  print "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\">\n";
  print "<input type=\"hidden\" name=\"mode\" value=\"most_active\">\n";

  print " <table border=\"0\" width=\"100%\">\n";
  print "    <th class=\"menutitle\" colspan=\"3\">Most Active \&amp; Hot Topics:</th>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th class=\"menuleft\">&nbsp;  &nbsp;</th>\n";
  print "    <td colspan=\"3\"><input type=\"submit\" class=\"button\" value=\"Most Active &amp; Hot Topics\"></td>\n";
  print "  </tr>\n";

  print " </table>\n";
  print "</form>\n";

  &html_tail();
  return;
}

sub help {
  $reseller_faq_help =~ s/[^a-zA-Z0-9\_\-\.\/]//g;
  open (HELP_FILE, "$reseller_faq_help") or die "Cannot open $reseller_faq_help for reading. $!";
  while (<HELP_FILE>) {
    print $_;
  }
  close(HELP_FILE);
  return;
}

sub most_active {
  my $FAQ = new PlugNPay::Reseller::FAQ();

  # For Issues
  my $data = "" ;
  my $issues = $FAQ->mostSearched(1);
  foreach my $id (@$issues) {
    my $issueInfo = $FAQ->get(uc($id->{'term'}),0);
    my $idTest = $issueInfo->{'issueID'};
    $idTest =~ s/\s//g;

    if (defined $idTest && $idTest ne '' ){
      $data .= '<tr><td>' . $issueInfo->{'question'} . '</td>';
      $data .= '<td width="10%" align="center"><form method="post" action="reseller_board.cgi">
        <input type="hidden" name="mode" value="view_description">
        <input type="hidden" name="id_number" value="' . uc($issueInfo->{'issueID'}) . '">
        <input type="submit" value="View Description"></form></td> </tr>';
    }
  }

  # For terms
  my $data2 = '';
  my $searchTerms = $FAQ->mostSearched(0);
  foreach my $term (@$searchTerms){
    my $termCheck = $term->{'term'};
    $termCheck =~ s/\s//g;
    if (defined $termCheck && $termCheck ne '') {
    $data2 .= '<tr><td align="center">' . ucfirst($term->{'term'}) . '</td>
      <td width="10%" align="center"><form method="post" action="reseller_board.cgi">
        <input type="hidden" name="mode" value="search_issue">
        <input type="hidden" name="category" value="all">
        <input type="hidden" name="search_keys" value="' . $term->{'term'} . '">
        <input type="submit" value="Access Issue(s)"></form></td>
      </tr>';
    }
  }

  my $time = new PlugNPay::Sys::Time();
  my $currentTime = $time->inFormat('db_local');

  my $HTML = q{<html>
<head>
<title>Online Reseller Issuer Center & FAQ's Most Active</title>
</head>
<body bgcolor="#ffffff" text="#000000">
<div align="center">
<font size="+1"><b>Online Reseller Issuer Center & FAQ 's Most Active</b></font>
<br><font size="-1" color="#000000"><i>Last Updated: } . $currentTime . q{</i></font>
<br><font size="-1" color="#ff0000"><i>This Page Is Updated On Load.</i></font>
<p>Below you will find the most active content in which resellers have read &amp; searched for.  We believe the below information will assist you in finding answers to those most frequently asked questions from our extensive online reseller FAQ database. If you do not find what you are looking for, don't forget to search the rest of our extensive online reseller FAQ database and review our documentation center.
<p>
<table border="1" width="80%">
  <tr>
    <th colspan="3" bgcolor="#6688A4"><font color="#ffffff">Top 25 Most Active Issues</font></th>
  </tr>
  <tr>
    <th bgcolor="#99BBD7">Issue:</th>
    <th bgcolor="#99BBD7">&nbsp;</th>
  </tr>} . $data . q{</table>

<p><table border="1" width="50%">
  <tr>
    <th colspan="3" bgcolor="#6688A4"><font color="#ffffff">Top 25 Most Active Keywords</font></th>
  </tr>
  <tr>
    <th bgcolor="#99BBD7">Keyword or Key Phrase:</th>
    <th bgcolor="#99BBD7">&nbsp;</th>
  </tr>} . $data2 . q{ </table>

</div>
<div align="center">
<p><form><input type="button" value="Back To Online Reseller FAQ" onClick="javascript:history.go(-1);"></form>
</div>
</body>
</html>};

print $HTML;


  
  return;
}

sub email_backup {
  # Function: Email FAQ Issue updates to admin user for backup purposes

  my @now = gmtime(time); # grab current time/date
  my $time_stamp = sprintf("%04d%02d%02d%02d%02d%02d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], $now[0]);

  $query{'issue'} =~ s/\&amp;/\&/g;
  $query{'issue'} =~ s/\&nbsp;/ /g;
  $query{'issue'} =~ s/\&quot;/\"/g;
  $query{'issue'} =~ s/\&lt;/\</g;
  $query{'issue'} =~ s/\&gt;/\>/g;

  $query{'description'} =~ s/\&amp;/\&/g;
  $query{'description'} =~ s/\<br\> /\n/g;
  $query{'description'} =~ s/\&nbsp;/ /g;
  $query{'description'} =~ s/\&quot;/\"/g;
  $query{'description'} =~ s/\&lt;/\</g;
  $query{'description'} =~ s/\&gt;/\>/g;


  # email the report
  my $emailmessage = "To: $email\n";
  $emailmessage .= "From: $from_email\n";
  if ($cc_email ne "") {
    $emailmessage .= "Cc: $cc_email\n";
  }
  if ($bcc_email ne "") {
    $emailmessage .= "Bcc: $bcc_email\n";
  }
  if ($subject ne ""){
    $emailmessage .= "Subject: $subject\n";
  }
  else {
    $emailmessage .= "Subject: Reseller FAQ Issue - ID: $query{'id_number'} - Version: $time_stamp\n";
  }
  $emailmessage .= "\n";
  $emailmessage .= "ID Number: $query{'id_number'}\n";
  $emailmessage .= "Category: $query{'category'}\n";
  $emailmessage .= "\n";
  $emailmessage .= "Issue: $query{'issue'}\n";
  $emailmessage .= "\n";
  $emailmessage .= "Description: $query{'description'}\n";
  $emailmessage .= "\n";
  $emailmessage .= "Keywords: $query{'keywords'}\n";
  $emailmessage .= "\n\n";

  #open(MAIL1, "| /usr/lib/sendmail -t");
  #print MAIL1 $emailmessage;
  #close(MAIL1);

  my $today = sprintf("%04d%02d%02d%02d%02d%02d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], $now[0]);

  my %errordump = ("billpres_upload","$today");
  my ($junk1,$junk2,$message_time) = &miscutils::genorderid();
  my $dbh_email = &miscutils::dbhconnect("emailconf");
  my $sth_email = $dbh_email->prepare(qq{
            insert into message_que2
            (message_time,username,status,format,body)
            values (?,?,?,?,?)
  }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%errordump);
  $sth_email->execute("$message_time","reseller_faq","pending","html","$emailmessage")
     or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%errordump);
  $sth_email->finish;
  $dbh_email->disconnect;

  return;
}

