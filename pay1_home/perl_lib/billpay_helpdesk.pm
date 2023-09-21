package helpdesk;

# Purpose: Allow users to help review and manage their helpdesk issues
# - allows user to submit new helpdesk issues 
# - user to submit new helpdesk issues allows user to search their known (by matching username) opened & closed helpdesk messages

require 5.001;
#$|=1;

use pnp_environment;
require billpay_adminutils;
use billpay_language;
use DBI;
use miscutils;
use sysutils;
use strict;

sub new {
  my $type1 = shift;

  # predefine important stuff here.
  $helpdesk::script = $ENV{'SCRIPT_NAME'};

  $helpdesk::bgcolor1 = "eeeeee"; # was 4a7394
  $helpdesk::bgcolor2 = "aaaaaa"; # was 6688A4 

  return [], $type1;
}


sub check_faq {
  my %query = @_;

  #$query{'descr'} = &html_filter("$query{'descr'}");

  if (($query{'descr'} !~ /\w/) || ($query{'subject'} !~ /\w/)) {
    # print web page here
    &html_head(%query);
    print "<p><b>There was a problem detected with your helpdesk submission.</b>\n";
    print "<p><b>A subject \&amp; breif description of your issue or question is required.</b>\n";
    print "<br>Please use the \'Back\' button below to enter the missing information.\n";
    print "<br><form><input type=button class=\"button\" value=\"Back\" onClick=\"javascript:history.go(-1);\"></form>\n";
    &html_tail();
    return;
  }

  my $path_webtxt = &pnp_environment::get('PNP_WEB_TXT');

  # Initialize Values Here
  my $faq_file      = "$path_webtxt/ecard/billpay/faq_data/faq.db"; # Sets path to faq database text file
  my $count         = 0;        # initialize & clear line counter
  my $find_match    = 0;        # assume no matches will be found to user's query
  my $display_match = 0;        # assume no matches rate high enough to be displayed
  my $switch        = 0;        # used to alternate question colors
  my $color         = "ffffff"; # initialize color
  my $data          = "";       # initialize & clear data value
 
  $data .= "<p><table width=\"100\%\" border=0> \n";
  $data .= "  <tr> \n";
  $data .= sprintf("    <td align=left bgcolor=\"\#%s\"><p><font color=\"#ffffff\"> &nbsp; </font></p></td>\n", $helpdesk::bgcolor1); 
  $data .= sprintf("    <td align=left bgcolor=\"\#%s\"><p><font color=\"#ffffff\"> QA Number: </font></p></td>\n", $helpdesk::bgcolor1);
  $data .= sprintf("    <td align=left bgcolor=\"\#%s\"><p><font color=\"#ffffff\"> Question: </font></p></td>\n", $helpdesk::bgcolor1);
  $data .= sprintf("    <td align=left bgcolor=\"\#%s\"><p><font color=\"#ffffff\"> &nbsp; </font></p></td>\n", $helpdesk::bgcolor1);
  $data .= "  </tr> \n";
 
  # open faq file
  &sysutils::filelog("read","$faq_file");
  open(FAQFILE,'<',"$faq_file") or print "Can't open $faq_file for reading. $!";
  # read into memory
  while(<FAQFILE>) {
    chomp $_;
    my $theline = $_;
    my @temp = split(/\t/, $theline);

    my $search_match = 0; # assume no match
    my $match_count = 0;  # clear & initialize count

    # split keywords
    my @search_keys = split(/\, |\; /, $temp[3]);
    #print "<br>Checking against search keys: $temp[3] \n";

    # seach helpdesk issue description & subject for matching keywords
    for (my $b = 0; $b <= $#search_keys; $b++) {
      if (($query{'descr'} =~ /$search_keys[$b]/i) || ($query{'subject'} =~ /$search_keys[$b]/i)) {
        $search_match = 1;
        $match_count++; # incriment counter for each matching keyword
        #print "<p>Found Match: $search_keys[$b]\n";
      }
    }
 
    if ($search_match == 1) {
      $find_match++; # incriment to indicate we found a match (indicates number of matches)
      # figure out keyword match percentage

      # adjust for correct number of keysword in the FAQ
      my $num_of_keys = $#search_keys++; # number of keys

      my $match_percentage;

      if ($num_of_keys > 0) {
        $match_percentage = (($match_count / $num_of_keys) * 100);
      }
      # perform adjustment where some matches have over a 100% match rate
      if ($match_percentage > 100) {
        $match_percentage = 100;
      }

      if ($match_percentage >= 20) {
        # display matching question if the match is above xx%
        $display_match++; # incriment display match count
        ($switch, $color) = &switch_color($switch, $color);
        $data .= &view_question($theline, $match_percentage, $color);
      }
      else {
        $data .= sprintf("<!--%2.0d%% - $temp[4] -->\n", $match_percentage);
      }
    }

    $count++; # incriment line counter
  }

  # close faqs file
  close(FAQFILE);

  if ($find_match == 0) {
    &addfinal(%query);
    return;
  }
  elsif (($find_match > 0) && ($display_match == 0)) {
    &addfinal(%query);
    return;
  }

  $data .= "</table> \n";

  # print web page here
  &html_head(%query);

  print "<p>The following FAQ questions match keywords contained within your helpdesk message.\n";
  print "<!-- $find_match Matches in FAQ -->\n";
  print $data;

  print "<p>If the above FAQ questions do not address your question or issue and you have already searched our online FAQ &amp; Documetation center, please click the \'Submit Problem Report\' button below to finalize your helpdesk submission.  If your issue was addressed above, please click the \'Cancel &amp; Close\' button.\n";

  print "<p><form>\n";
  print "<input type=button class=\"button\" value=\"absmiddle\" alt=\"Cancel &amp; Close Window\" onclick=\"window.close();\">\n";
  print "</form>\n";
 
  &ticket_button(%query);
  &html_tail();
  return;
}

sub view_question {
  my ($theline, $match_percentage, $color) = @_;

  my ($match_color, $data);

  my @temp = split(/\t/, $theline);

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

  $data .= "  <tr> \n";
  $data .= sprintf("    <td width=\"5%%\" bgcolor=\"\#%s\" align=right><font color=\"\#%s\">%2.0d%%</font></td> \n", $color, $match_color, $match_percentage);
  $data .= "    <td width=\"10%\" bgcolor=\"\#$color\">$temp[4]</td> \n"; # this is the QA number
  $data .= "    <td align=left bgcolor=\"\#$color\">$temp[1]</td> \n"; # this is the question
  $data .= "    <td width=\"10%\" align=center bgcolor=\"\#$color\"><form method=post action=\"faq_board.cgi\" target=\"docs\"> \n";
  $data .= "<input type=hidden name=\"mode\" value=\"view_answer\"> \n";
  $data .= "<input type=hidden name=\"qa_number\" value=\"$temp[4]\"> \n";
  $data .= "<input type=submit class=\"button\" value=\"View Answer\"></td></form> \n";
  $data .= "  </tr> \n";

  return $data;
}

sub html_filter {
  my ($descr) = @_;

  # reformat description
  #$descr =~ s/\&/\&amp\;/g;
  $descr =~ s/\"/\&quot\;/g;
  #$descr =~ s/\</\&lt\;/g;
  #$descr =~ s/\>/\&gt\;/g;
  #$descr =~ s/  /\&nbsp\; /g;
  #$descr =~ s/[^a-zA-Z_0-9_\,_\._\;_\-_\?_\!_\@_\#_\$_\%_\^_\&_\*_\(_\)_ _\\_\+]//g;

  $descr =~ s/\r\n/\n/g;
  $descr =~ s/\r//g;
  #$descr =~ s/\n/<br>/g;
  #$descr =~ s/\t/ /g;
 
  return "$descr";
}

sub switch_color {
  my ($switch, $color) = @_;

  if ($switch == 0) {
    $switch = 1; # toggle switch
    $color = "ffffff"; # white bacground 
  }
  else {
    $switch = 0;
    $color = "dddddd"; # gray background
  }

  return ($switch, $color);
}

sub addfinal {
  my %query = @_;

  &html_head(%query);
  &ticket_button(%query);
  &html_tail();

  return;
}

sub addnew {
  my %query = @_;

  &html_head(%query);

  print "<p>Please refer to our online Documentation, FAQ sections prior to submitting any new helpdesk issues to our online helpdesk.  The Documentation & FAQ sections, will address many of your commonly asked questions.\n";

  print "<p><a href=\"index.cgi\?function=show_docs_menu\" target=\"docs\">Documentation</a> \&nbsp; \&nbsp; <a href=\"faq_board.cgi\" target=\"docs\">Frequently Asked Questions (FAQ)</a>\n";

  print "<p>When submitting any messages to the helpdesk, please be brief, but as specific as possible, providing examples or steps to reproduce the issue as necessary.  Please also remember to also include your login email address, without this information\; we will not know which account requires our assistance.\n";

  print "<p>Thank You,\n";
  print "<br><br>Support Staff<br>\n";

  print "<form name=\"helpdesk_form\" method=post action=\"$helpdesk::script\" onSubmit=\"return validate(document.helpdesk_form.descr.value);\">\n";
  print "<input type=hidden name=\"mode\" value=\"check_faq\">\n"; # do FAQ check

  print "<table border=0 cellpadding=2 cellspacing=0>\n";
  print "  <tr>\n";
  print "    <td bgcolor=\"#$helpdesk::bgcolor2\" width=\"10%\"><p><font color=\"#ffffff\"> &nbsp; </font></p></td>\n";
  print "    <td><p><i>Fields marked with a</i> <b>*</b> <i>are required.</i></p></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td bgcolor=\"#$helpdesk::bgcolor2\" width=\"10%\"><p><font color=\"#ffffff\"> Email: </font></p></td>\n";
  print "    <td><p>$ENV{'REMOTE_USER'}</p></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td bgcolor=\"#$helpdesk::bgcolor2\" width=\"10%\"><p><font color=\"#ffffff\"> Previously Worked: </font></p></td>\n";
  print "    <td><p><input type=checkbox name=\"priority\" value=\"emergency\"> Check this if something is now broken that previously worked.</p></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td bgcolor=\"#$helpdesk::bgcolor2\" width=\"10%\"><p><font color=\"#ffffff\"> Subject:<b>*</b> </font></p></td>\n";
  print "    <td><input type=text name=\"subject\" value=\"$query{'subject'}\" size=35 maxlength=35></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td bgcolor=\"#$helpdesk::bgcolor2\" width=\"10%\"><p><font color=\"#ffffff\"> Description:<b>*</b> </font></p></td>\n";
  print "    <td><textarea name=\"descr\" rows=15 cols=60 maxlength=1000 wrap=\"physical\" onChange=\"validate(this.value);\">$query{'descr'}</textarea></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td bgcolor=\"#$helpdesk::bgcolor2\" width=\"10%\"><p><font color=\"#ffffff\"> &nbsp; </font></p></td>\n";
  print "    <td><input type=submit class=\"button\" value=\"Next\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</form>\n";

  &html_tail();

  return;
}

sub ticket_button {
  my %query = @_;

  my $dbh = &miscutils::dbhconnect("billpres");
  my $sth = $dbh->prepare(qq{
      select name, phone
      from customer2
      where username=?
    }) or print "Can't do: $DBI::errstr"; #&miscutils::errmaildie(__LINE__,__FILE__,"Can't do: $DBI::errstr",%query);
  $sth->execute("$ENV{'REMOTE_USER'}") or print "Can't execute: $DBI::errstr"; #&miscutils::errmaildie(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%query);
  my ($name, $phone) = $sth->fetchrow;
  $sth->finish;
  $dbh->disconnect;

  # filter data, just to be on the safe side
  $name =~ s/[^A-Za-z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,\p{L&}]+//g;
  $phone =~ s/[^A-Za-z0-9\- ]+//g; 

  my $email = $ENV{'REMOTE_USER'};
  $email =~ s/[^a-zA-Z0-9\_\-\@\.]//g;
  $email = lc("$email");

  # figure out HD ticket priority number
  my $pri = 2; # normal
  if ($query{'priority'} eq "emergency") {
    $pri = 3; # emergency
  }

  # limit data to fit HD ticket system
  $query{'subject'} = substr($query{'subject'}, 0, 35);
  $query{'descr'} = substr($query{'descr'},0,1000);

  print "<p><b>No information in the FAQ matches your support issue.</b></p>\n";

  print "<div align=center>\n";
  print "<p><form action=\"https://helpdesk.plugnpay.com/hd/open.php\" method=post enctype=\"multipart/form-data\" target=\"hdticket\">\n";
  print "<input type=hidden name=\"email\" value=\"$email\">\n";
  print "<input type=hidden name=\"name\" value=\"$name\">\n";
  print "<input type=hidden name=\"phone\" value=\"$phone\">\n";
  print "<input type=hidden name=\"topicId\" value=\"4\">\n";
  print "<input type=hidden name=\"pri\" value=\"$pri\">\n";
  print "<input type=hidden name=\"subject\" value=\"$query{'subject'}\">\n";
  print "<input type=hidden name=\"message\" value=\"$query{'descr'}\">\n";
  print "<input type=submit class=\"button\" value=\"Click Here To Continue\"> &nbsp; \n";
  print "</form>\n";
  print "</div>\n";

  return;
}


sub show_menu {
  my %query = @_;

  my @now = gmtime(time);

  &html_head();

  print "<table border=0 cellpadding=1 cellspacing=0>\n";
  print "  <tr>\n";
  print "    <th bgcolor=\"#$helpdesk::bgcolor2\"><p><font color=\"#ffffff\">&nbsp; Submit New Issue: &nbsp;</font></p></th>\n";
  print "    <td><form method=post action=\"$helpdesk::script\">\n";
  print "<input type=hidden name=\"mode\" value=\"addnew\">\n";
  print "<input type=submit class=\"button\" value=\"Submit New HelpDesk Issue\">\n";
  print "</form></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th bgcolor=\"#$helpdesk::bgcolor2\"><p>&nbsp; &nbsp;</p></th>\n";
  print "    <td align=center><hr width=80% noshade></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th bgcolor=\"#$helpdesk::bgcolor2\" valign=top><font color=\"#ffffff\">&nbsp; Check Helpdesk<br>Ticket Status: &nbsp;</font></th>\n";
  print "    <td><form action=\"https://helpdesk.plugnpay.com/hd/login.php\" method=post target=\"hdticket\">\n";
  print "<input type=hidden name=\"lemail\" value=\"$ENV{'REMOTE_USER'}\">\n";
  print "<table border=0 cellpadding=2 cellspacing=0>\n";
  print "  <tr>\n";
  print "    <td>Ticket #:</td>\n";
  print "    <td><input type=text name=\"lticket\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td>&nbsp;</td>\n";
  print "    <td><input type=submit class=button value=\"Check Status\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";
  print "</form></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th bgcolor=\"#$helpdesk::bgcolor2\"><p>&nbsp; &nbsp;</p></th>\n";
  print "    <td align=center><hr width=80% noshade></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  &html_tail();
  return();
}

sub html_head {
  my %query = @_;

  my ($path_index, $path_logout);

  my $path_index = "index.cgi";
  my $path_logout = "logout.cgi";

  # figure out cobrand stuff... 
  my ($cobrand_title, $cobrand_logo, $cookie_set) = &billpay_adminutils::cobrand_check();

  if ($cookie_set ne "yes") {
    print "Content-Type: text/html\n";
    print "X-Content-Type-Options: nosniff\n";
    print "X-Frame-Options: SAMEORIGIN\n\n";
  }

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>$billpay_language::lang_titles{'service_title'} - Online Help Desk</title>\n";
  print "<meta http-equiv=\"CACHE-CONTROL\" content=\"NO-CACHE\">\n";
  print "<meta http-equiv=\"PRAGMA\" content=\"NO-CACHE\">\n";
  print "<link rel=\"shortcut icon\" href=\"favicon.ico\">\n";
  print "<link href=\"/css/style_billpay.css\" type=\"text/css\" rel=\"stylesheet\">\n";

  print "<script type=\"text/javascript\">\n";
  print "//<!-- Start Script\n";

  print "function validate(what) {\n";
  print "  if (what.length > 1000) {\n";
  print "    alert(\'Please limit your helpdesk message to under 1000 characters.\');\n";
  print "    return false;\n";
  print "  }\n";
  print "  return true;\n";
  print "}\n";

  print "function delete_confirm() {\n";
  print "  return confirm('Are you sure you want to close this helpdesk issue?\\r\\nIf you proceed, this will instantly stop all ongoing support activity for this helpdesk issue.');\n";
  print "}\n";

  print "function results(loadurl,swidth,sheight) {\n";
  print "  SmallWin = window.open(loadurl, 'results','scrollbars=yes,resizable=yes,status=no,toolbar=no,menubar=yes,height='+sheight+',width='+swidth);\n";
  print "}\n";

  print "//-->\n";
  print "</script>\n";

  print "</head>\n";
  print "<body bgcolor=\"#ffffff\" onLoad=\"self.focus();\">\n";

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

  print "  <tr>\n";
  print "    <td align=left nowrap><p><a href=\"./\" onclick=\"javascript:window.close();\">Close Window</a></p></td>\n";
  print "    <td align=right nowrap><p><a href=\"$path_logout\">$billpay_language::lang_titles{'link_logout'}</a> &nbsp;\|&nbsp; <a href=\"$path_index\?function=help\">$billpay_language::lang_titles{'link_help'}</a></p></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=3 align=left><img src=\"/images/header_bottom_bar_gfx.gif\" width=760 alt=\"plug \'n pay\"  height=14></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  if ($query{'function'} eq "") {
    print "<table border=0 cellspacing=0 cellpadding=5 width=760>\n";
    print "  <tr>\n";
    print "    <td colspan=3 valign=top align=left>\n";
  }
  elsif ($query{'function'} =~ /^(show_)/i) {
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

sub html_tail {

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

  print "</body>\n";
  print "</html>\n";

  return;
}

1;
