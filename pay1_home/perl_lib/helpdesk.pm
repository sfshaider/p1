package helpdesk;

use pnp_environment;
use miscutils;
use sysutils;
use PlugNPay::InputValidator;
use PlugNPay::Email;
use PlugNPay::GatewayAccount;
use PlugNPay::FAQ::Helpdesk;
use PlugNPay::Logging::DataLog;
use strict;

sub new {
  my $type1 = shift;

  %helpdesk::query = PlugNPay::InputValidator::filteredQuery('online_helpdesk'); 
  $helpdesk::faqObject = new PlugNPay::FAQ::Helpdesk();
  $helpdesk::function = $helpdesk::query{'function'};

  my $logData = {
    'originalLogFile' => '/home/p/pay1/database/helpdesk.txt',
    'remoteUser'      => $ENV{'REMOTE_USER'},
    'function'        => $helpdesk::function,
    'subject'         => $helpdesk::query{'subject'},
    'orderid'         => $helpdesk::query{'orderid'},
    'email'           => $helpdesk::query{'email'},
    'phone'           => $helpdesk::query{'phone'},
    'descr'           => $helpdesk::query{'descr'}
  };

  $helpdesk::faqObject->log($logData);
  return [], $type1;
}

sub html_head {
  print "Content-Type: text/html\n";
  print "X-Content-Type-Options: nosniff\n";
  print "X-Frame-Options: SAMEORIGIN\n\n";

  print "<html>\n";
  print "<head>\n";
  print "<link href=\"/css/style_faq.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  print "<title>Help Desk</title>\n";
  print "<META HTTP-EQUIV=\"Pragma\" CONTENT=\"no-cache\">\n";
  print "<META HTTP-EQUIV=\"Cache-Control\" CONTENT=\"no-cache\">\n";

  print "<script Language=\"Javascript\">\n";
  print "<!-- //\n";

  print "function validate(what) {\n";
  print "  if (what.length > 1000) {\n";
  print "    alert('Please limit your helpdesk message to under 1000 characters.');\n";
  print "    return false;\n";
  print "  }\n";
  print "  return true;\n";
  print "}\n";

  print "function textCounter(field,cntfield,maxlimit) {\n";
  print "  if (field.value.length > maxlimit) // if too long...trim it!\n";
  print "    field.value = field.value.substring(0, maxlimit);\n";
  print "  // otherwise, update 'characters left' counter\n";
  print "  else\n";
  print "    cntfield.value = maxlimit - field.value.length;\n";
  print "}\n";

  print "function closewin() {\n";
  print "  self.close();\n";
  print "}\n";

  print "// -->\n";
  print "</script>\n";

  print "</head>\n";
  print "<body bgcolor=\"#ffffff\" onLoad=\"self.focus();\">\n";

  print "<table width=\"760\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\" id=\"header\">\n";
  print "  <tr>\n";
  print "    <td colspan=\"3\" align=\"left\">";
  if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
    print "<img src=\"/images/global_header_gfx.gif\" width=\"760\" alt=\"Plug 'n Pay Technologies - we make selling simple.\" height=\"44\" border=\"0\">";
  } else {
    print "<img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Logo\">\n";
  }
  print "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"3\" align=\"left\"><img src=\"/css/header_bottom_bar_gfx.gif\" width=\"760\" height=\"14\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table border=\"0\" cellspacing=\"0\" cellpadding=\"5\" width=\"760\">\n";
  print "  <tr>\n";
  print "    <td colspan=\"2\"><h1><a href=\"$ENV{'SCRIPT_NAME'}\">Online Helpdesk</a></h1>\n";

  return;
}

sub html_tail {
  my @now = gmtime(time);
  my $copy_year = $now[5]+1900;

  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table width=\"760\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\" id=\"footer\">\n";
  print "  <tr>\n";
  print "    <td align=\"left\"><p><a href=\"/admin/logout.cgi\" title=\"Click to log out\">Log Out</a> | <a id=\"close\" href=\"javascript:closewin();\" title=\"Click to close this window\">Close Window</a></p></td>\n";
  print "    <td align=\"right\"><p>\&copy; $copy_year, ";
  if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
    print "Plug and Pay Technologies, Inc.";
  } else {
    print "$ENV{'SERVER_NAME'}";
  }
  print "</p></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</body>\n";
  print "</html>\n";

  return;
}

sub check_faq {
  &html_filter();

  &html_head();

  if (($helpdesk::query{'descr'} !~ /\w/) || ($helpdesk::query{'subject'} !~ /\w/)) {
    # print web page here
    print "<p><b>There was a problem detected with your helpdesk submission.</b>\n";
    print "<p><b>A subject \&amp; breif description of your issue or question is required.</b>\n";
    print "<br>Please use the \'Back\' button below to enter the missing information.\n";
    print "<br><form><input type=button class=\"button\" value=\"Back\" onClick=\"javascript:history.go(-1);\"></form>\n";
    &html_tail();
    return;
  }

  if ($helpdesk::query{'email'} =~ /^(support\@plugnpay\.com|helpdesk\@plugnpay\.com|trash\@plugnpay\.com)$/i) {
    # print web page here
    print "<p><b>There was a problem detected with your helpdesk submission.</b>\n";
    print "<p><b>Real contact information (email address \&amp; phone number) required.</b>\n";
    print "<br>You may not use our support email addresses within your contact information.\n";
    print "<br>Please use the \'Back\' button below to enter the missing information.\n";
    print "<br><form><input type=button class=\"button\" value=\"Back\" onClick=\"javascript:history.go(-1);\"></form>\n";
    &html_tail();
    return;
  }

  if (($helpdesk::query{'email'} !~ /\w/) || ($helpdesk::query{'phone'} !~ /\w/)) {
    # print web page here
    print "<p><b>There was a problem detected with your helpdesk submission.</b>\n";
    print "<p><b>Full contact information (email address \&amp; phone number) required.</b>\n";
    print "<br>Please use the \'Back\' button below to enter the missing information.\n";
    print "<br><form><input type=button class=\"button\" value=\"Back\" onClick=\"javascript:history.go(-1);\"></form>\n";
    &html_tail();
    return;
  }

  my $path_webtxt = &pnp_environment::get('PNP_WEB_TXT');

  # Initialize Values Here
  my $faq_file      = "$path_webtxt/admin/wizards/faq_data/faq.db"; # Sets path to faq database text file
  my $count         = 0;        # initialize & clear line counter
  my $find_match    = 0;        # assume no matches will be found to user's query
  my $display_match = 0;        # assume no matches rate high enough to be displayed
  $helpdesk::color  = 0;        # used to alternate question colors
  my $data          = "";       # initialize & clear data value
 
  $data .= "<p><table width=\"100%\" border=\"0\">\n";
  $data .= "  <tr class=\"listsection_title\">\n";
  $data .= "    <td>&nbsp;</td>\n"; 
  $data .= "    <td>QA Number:</td>\n";
  $data .= "    <td>Question:</td>\n";
  $data .= "    <td>&nbsp;</td>\n";
  $data .= "  </tr>\n";
  my $category = $helpdesk::query{'category'};
  my @searchKeys = ($helpdesk::query{'descr'}, $helpdesk::query{'subject'});
 
  my $parsedData = $helpdesk::faqObject->searchItems({
    'searchKeys'             => \@searchKeys,
    'category'               => $category,
    'minimumMatchPercentage' => 20,
    'exclusions'             => []
  });

  foreach my $qaNum (keys %{$parsedData}) {
    @helpdesk::temp = @{$parsedData->{$qaNum}{'rowThatMatches'}};
    $helpdesk::match_percentage = $parsedData->{$qaNum}{'matchPercentage'};
    $helpdesk::color = $parsedData->{$qaNum}{'rowColorSwitch'};
    $helpdesk::match_color = $parsedData->{$qaNum}{'matchColor'};
    $count = $parsedData->{$qaNum}{'matchCount'};

    if ($parsedData->{$qaNum}{'inMatchBounds'}) {
      $display_match++;
      &view_question();
    }
  }

  if ($find_match == 0) {
      print "<p>No FAQ questions match keywords contained within your helpdesk message.\n";
      &addfinal_form();
      &html_tail();
    return;
  } elsif (($find_match > 0) && ($display_match == 0)) {
      print "<p>The following FAQ questions match keywords contained within your helpdesk message.\n";
      &addfinal_form();
      &html_tail();
    return;
  }

  $data .= "</table>\n";

  # print web page here
  &addfinal_form();

  print "<p>The following FAQ questions match keywords contained within your helpdesk message.\n";
  print "<!-- $find_match Matches in FAQ -->\n"; #big brain time
  print $data;
  print "<p>If the above FAQ questions do not address your question or issue and you have already searched our online FAQ &amp; Documetation center, please click the \'Submit Help Desk Issue\' button below to finalize your helpdesk submission.  If your issue was addressed above, please click the \'Cancel &amp; Close\' button.\n";

  &addfinal_form();
  &html_tail();
  return;
}

sub addfinal_form {
    ## for new helpdesk ticket system usage
    print "<p><form method=\"post\" action=\"https://helpdesk.plugnpay.com/hd/open.php\">\n";
    print "<input type=\"hidden\" name=\"pnp_user\" value=\"$ENV{'REMOTE_USER'}\">\n";
    if ($helpdesk::query{'priority'} eq "emergency") {
      print "<input type=\"hidden\" name=\"pri\" value=\"3\">\n"; # flag as high priority
    } else {
      print "<input type=\"hidden\" name=\"pri\" value=\"2\">\n"; # flag as normal priority
    }
    print "<input type=\"hidden\" name=\"name\" value=\"$helpdesk::query{'name'}\">\n";
    print "<input type=\"hidden\" name=\"email\" value=\"$helpdesk::query{'email'}\">\n";
    print "<input type=\"hidden\" name=\"phone\" value=\"$helpdesk::query{'phone'}\">\n";
    print "<input type=\"hidden\" name=\"subject\" value=\"$helpdesk::query{'subject'}\">\n";
    print "<input type=\"hidden\" name=\"message\" value=\"$helpdesk::query{'descr'}\">\n";
    print "<input type=\"hidden\" name=\"type\" value=\"$helpdesk::query{'type'}\">\n";
    print "<input type=\"hidden\" name=\"topicId\" value=\"1\">\n"; # flag as 'support' help topic
    print "<input type=\"submit\" class=\"button\" name=\"submit\" value=\"Submit Help Desk Issue\"> &nbsp;\n";
    print "<input type=\"button\" class=\"button\" value=\"Cancel &amp; Close Window\" onclick=\"window.close();\">\n";
    print "</form>\n";

  return;
}

sub view_question {
  my ($match_color, $data);

  if ($helpdesk::match_percentage >= 75) {
    $match_color = "ff0000";
  } elsif ($helpdesk::match_percentage < 75 && $helpdesk::match_percentage >= 50) {
    $match_color = "00dd00";
  } elsif ($helpdesk::match_percentage < 50 && $helpdesk::match_percentage >= 25) {
    $match_color = "0000dd";
  } else {
    $match_color = "000000";
  }

  if ($helpdesk::color == 1) {
    $data .= "  <tr class=\"listrow_color1\">\n";
  } else {
    $data .= "  <tr class=\"listrow_color0\">\n";
  }
  $data .= sprintf("    <td width=\"5%%\" align=\"right\"><font color=\"\#%s\">%2.0d%%</font></td>\n", $match_color, $helpdesk::match_percentage);
  $data .= "    <td width=\"10\%\">$helpdesk::temp[4]</td>\n"; # this is the QA number
  $data .= "    <td align=\"left\">$helpdesk::temp[1]</td>\n"; # this is the question
  $data .= "    <td width=\"10\%\" align=\"center\"><form method=\"post\" action=\"/admin/wizards/faq_board.cgi\" target=\"faq-doc\">\n";
  $data .= "      <input type=\"hidden\" name=\"mode\" value=\"view_answer\">\n";
  $data .= "      <input type=\"hidden\" name=\"qa_number\" value=\"$helpdesk::temp[4]\">\n";
  $data .= "      <input type=\"submit\" class=\"button\" value=\"View Answer\"></form></td>\n";
  $data .= "  </tr>\n";

  $helpdesk::color = ($helpdesk::color + 1) % 2;

  return $data;
}

sub html_filter {
  # reformat description
  $helpdesk::query{'descr'} =~ s/\"/\&quot\;/g;
  $helpdesk::query{'descr'} =~ s/\r\n/\n/g;
  $helpdesk::query{'descr'} =~ s/\r//g;
 
  return;
}

sub addfinal {
  my $reseller = &get_reseller();

  my @now = gmtime(time);
  $helpdesk::query{'orderid'} = sprintf("%04d%02d%02d%02d%02d%05d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], $now[0]);
  $helpdesk::today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);
  $helpdesk::query{'descr'} = substr($helpdesk::query{'descr'},0,1000);

  # email HD issue directly to reseller, when necessary.
  if ($reseller =~ /^(usightco)$/) {
    &helpdesk_email("techsupport\@ugateway\.com");
  } elsif ($reseller =~ /(electro)$/) {
    &helpdesk_email("support\@eci-pay.com");
  } elsif ($reseller =~ /(paymentd|cblbanca)/) {
    &helpdesk_email("support\@paymentdata.com");
  } elsif ($reseller =~ /(webassis)$/) {
    &helpdesk_email("webassist\@e-onlinedata.com");
  } elsif ($reseller =~ /(optimalp)$/) {
    &helpdesk_email("support\@optimalpayments.com");
  } elsif ($reseller =~ /(processa)$/) {
    &helpdesk_email("support\@connectnpay.com");
  } elsif ($reseller =~ /(lawpay)$/) {
    &helpdesk_email("support\@lawpay.com");
  } elsif ($reseller =~ /^(singular)$/) {
    &helpdesk_email("tech_support\@singularbillpay.com");
  } else {
    # send email to merchant
    my $emailObj = new PlugNPay::Email('legacy');
    $emailObj->setGatewayAccount('helpdesk');
    $emailObj->setFormat('text');
    $emailObj->setTo($helpdesk::query{'email'});
    $emailObj->setFrom('support@plugnpay.com');
    $emailObj->setSubject('HelpDesk Support Issue ' . $helpdesk::query{'orderid'});

    my $emailmessage = "";
    $emailmessage .= "Your help desk issue has been received.\n";
    $emailmessage .= "You will be contacted by a technical support representative within 24 hrs.\n\n";
    $emailmessage .= "Help desk items submitted on the weekend are monitored for emergency issues.\n";
    $emailmessage .= "Non-emergency issues will be addressed on Monday.\n\n";
    $emailmessage .= "Thank you,\n";
    $emailmessage .= "Support Staff\n\n";
    $emailmessage .= "-- Help Desk Issue Submitted --\n";
    $emailmessage .= "Subject: $helpdesk::query{'subject'}\n\n";
    $emailmessage .= "$helpdesk::query{'descr'}\n";
    $emailObj->setContent($emailmessage);

    $emailObj->send();
  }

  &response_page();
  return;
}

sub add {
  $helpdesk::query{'refurl'} = $ENV{'HTTP_REFERER'};
  $helpdesk::query{'host'} = $ENV{'REMOTE_HOST'};
  $helpdesk::browser = $ENV{'HTTP_USER_AGENT'};

  my $gatewayAccount = new PlugNPay::GatewayAccount($ENV{'REMOTE_USER'});
  $helpdesk::query{'status'} = $gatewayAccount->getStatus();

  my $mainContact = $gatewayAccount->getMainContact();
  $helpdesk::query{'email'} = $mainContact->getEmailAddress();
  $helpdesk::query{'phone'} = $mainContact->getPhone();
  $helpdesk::query{'name'}  = $mainContact->getFullName();
  
  # do not allow PnP's support & helpdesk email address to be provided as a default.
  if ($helpdesk::query{'email'} =~ /^(support\@plugnpay\.com|helpdesk\@plugnpay\.com|trash\@plugnpay\.com)$/) {
    $helpdesk::query{'email'} = "";
  }

  &html_head();

  print "<p>Please refer to our online Documentation, FAQ & Glossary sections prior to submitting any new helpdesk issues to our online helpdesk.  The Documentation, FAQ & Glossary sections, will address many of your commonly asked questions.\n";

  print "<div align=\"center\">\n";
  print "<p><a href=\"/admin/documentation.html\" target=\"faq-doc\">Online Documentation</a> \&nbsp; \&nbsp; <a href=\"./wizards/faq_board.cgi\" target=\"faq-doc\">Frequently Asked Questions (FAQ)</a> &nbsp; &nbsp; <a href=\"./wizards/glossary.cgi\" target=\"faq-doc\">Online Glossary Of Terms</a>\n";
  print "</div>\n";

  print "<p>When submitting any messages to the helpdesk, please be brief \&amp; as specific as possible, providing examples or steps to reproduce the issue as necessary.  Please also remember to also include your merchant username, without this information\; we will not know which account requires our assistance.\n";

  print "<p>Thank You,\n";
  print "<br><br>Support Staff<br>\n";

  print "<hr>\n";

  print "<form name=\"helpdesk_form\" method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\" onSubmit=\"return validate(document.helpdesk_form.descr.value);\">\n";
  print "<input type=\"hidden\" name=\"type\" value=\"help\">\n";
  print "<input type=\"hidden\" name=\"function\" value=\"check_faq\">\n"; # do FAQ check
  print "<input type=\"hidden\" name=\"refurl\" value=\"$helpdesk::query{'refurl'}\">\n";
  print "<input type=\"hidden\" name=\"host\" value=\"$helpdesk::query{'host'}\">\n";

  print "<table border=\"0\" cellpadding=\"1\" cellspacing=\"0\" width=\"100%\">\n";
  print "  <tr>\n";
  print "    <td class=\"menusection_title\" colspan=2><font size=\"-1\"><i>Fields marked with a <font size=+1>*</font> are required.</i></font></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Username:</td>\n";
  print "    <td class=\"menurightside\">$ENV{'REMOTE_USER'}</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Previously Worked:</td>\n";
  print "    <td class=\"menurightside\"><input type=\"checkbox\" name=\"priority\" value=\"emergency\"> Check this if something is now broken that previously worked.</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Email: <font size=+1>*</font></td>\n";
  print "    <td class=\"menurightside\"><input type=\"text\" name=\"email\" value=\"$helpdesk::query{'email'}\" size=30 maxlength=50></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Phone: <font size=+1>*</font></td>\n";
  print "    <td class=\"menurightside\"><input type=\"text\" name=\"phone\" value=\"$helpdesk::query{'phone'}\" size=20 maxlength=32> &nbsp;</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Subject: <font size=+1>*</font></td>\n";
  print "    <td class=\"menurightside\"><input type=\"text\" name=\"subject\" size=40 maxlength=50></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Description: <font size=+1>*</font></td>\n";
  print "    <td class=\"menurightside\"><textarea name=\"descr\" rows=15 cols=60 maxlength=1000 wrap=\"physical\" onChange=\"validate(this.value);\"";
  print " onKeyDown=\"textCounter(document.helpdesk_form.descr,document.helpdesk_form..remLen,1000);\"";
  print " onKeyUp=\"textCounter(document.helpdesk_form.descr,document.helpdesk_form.remLen,1000);\"></textarea>\n";
  print "<br><input readonly type=\"text\" name=\"remLen\" size=\"4\" maxlength=\"4\" value=\"1000\"> characters left\n";
  print "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\"><input type=\"submit\" class=\"button\" name=\"submit\" value=\"Next\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</form>\n";
  &html_tail();
  return;
}

sub response_page {
  &html_head();

  print "<p><b>Your help desk issue has been submitted to the Help Desk.";
  print "&nbsp; We will address it as soon as possible.</b>\n";

  print "<p>Thank You for using the Help Desk. By using the Help Desk, we can efficiently solve your problem.\n";
  print "<br>Support Staff<br>\n";

  print "<div align=\"center\">\n";
  print "<p><form><input type=button class=\"button\" value=\"Close Window\" onclick=\"window.close();\"></form>\n";
  print "</div>\n";

  print "<br>&nbsp;\n";

  &html_tail();
  return;
}


sub helpdesk_email {
  my $supportemail = shift;

  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setGatewayAccount('helpdesk');
  $emailObj->setFormat('text');
  $emailObj->setTo($supportemail);
  $emailObj->setFrom($helpdesk::query{'email'});
  $emailObj->setSubject('Gateway Helpdesk Request');

  my $emailmessage = "";
  $emailmessage .= "Date: $helpdesk::today\n";
  $emailmessage .= "Username:$ENV{'REMOTE_USER'}\n";
  $emailmessage .= "Subject:$helpdesk::query{'subject'}\n";
  $emailmessage .= "Phone:$helpdesk::query{'phone'}\n";
  $emailmessage .= "Best Time: $helpdesk::query{'hours'}\n";
  $emailmessage .= "Browser:$helpdesk::browser\n";
  $emailmessage .= "URL:$helpdesk::query{'refurl'}\n";
  $emailmessage .= "Type:$helpdesk::query{'type'}\n";
  $emailmessage .= "Message:$helpdesk::query{'descr'}\n";
  $emailObj->setContent($emailmessage);
  my $sent = $emailObj->send();

  if (not $sent) { #I like how this reads
    &log({
      'orderid'  => $helpdesk::query{'orderid'},
      'username' => $ENV{'REMOTE_USER'},
      'subject'  => $helpdesk::query{'subject'},
      'message'  => 'failed to send email to ' . $supportemail,
      'descr'    => $helpdesk::query{'descr'}
    });
  }

  return $sent;
}

sub get_reseller {
  my $gatewayAccount = new PlugNPay::GatewayAccount($ENV{'REMOTE_USER'});
  return $gatewayAccount->getReseller();
}

sub log {
  my $logData = shift;
  my $logger = new PlugNPay::Logging::DataLog({'collection' => 'helpdesk'})->log($logData);
}

1;

