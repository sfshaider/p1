package joinpage_wizard;

# Membership Management - Join Page Wizard Module

require 5.001;
$|=1;

use pnp_environment;
use miscutils;
use PlugNPay::InputValidator;
use PlugNPay::Features;
use CGI qw/standard escapeHTML unescapeHTML/;
use strict;

sub new {
  %joinpage_wizard::query = PlugNPay::InputValidator::filteredQuery('context'); # see below for creating a context

  if (($ENV{'SEC_LEVEL'} eq '') && ($ENV{'REDIRECT_SEC_LEVEL'} ne '')) {
    $ENV{'SEC_LEVEL'} = $ENV{'REDIRECT_SEC_LEVEL'};
  }

  ## allow Proxy Server to modify ENV variable 'REMOTE_ADDR'
  if ($ENV{'HTTP_X_FORWARDED_FOR'} ne '') {
    $ENV{'REMOTE_ADDR'} = $ENV{'HTTP_X_FORWARDED_FOR'};
  }

  $joinpage_wizard::merchant = lc($ENV{'REMOTE_USER'});
  $joinpage_wizard::merchant =~ s/[^a-z0-9]//g;

  $joinpage_wizard::plan_limit = 100;  # Maximum number of items the wizard will allow.

  %joinpage_wizard::currencyUSDSYM = ('aud','A$','cad','C$','eur','&#8364;','gbp','&#163;','jpy','&#165;','usd','$','jmd','JMD');

  return;
}

sub start_page {
  my %features;

  my $dbh = &miscutils::dbhconnect('pnpmisc');
  my $sth = $dbh->prepare(q{
      SELECT currency,processor
      FROM customers
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute($joinpage_wizard::merchant) or die "Can't execute: $DBI::errstr";
  my ($currency,$processor) = $sth->fetchrow;
  $sth->finish();
  $dbh->disconnect;

  my $accountFeatures = new PlugNPay::Features("$joinpage_wizard::merchant",'general');
  my $features = $accountFeatures->getFeatureString();

  if ($features =~ /(.*)=(.*)/) {
    my @array = split(/\,/,$features);
    foreach my $entry (@array) {
      my($name,$value) = split(/\=/,$entry);
      $features{$name} = $value;
    }
  }

  $currency = lc($currency); # force currency value to lower case - 01/24/06

  &html_head();

  print "<p align=center>This wizard will generate fully functional join web pages for the Membership Management Services.\n";

  print "<form method=post action=\"$ENV{'SCRIPT_NAME'}\">\n";
  print "<input type=hidden name=\"function\" value=\"pass1\">\n";

  print "<div align=center>\n";
  print "<table border=1 cellspacing=0 cellpadding=3>\n";
  print "  <tr>\n";
  print "    <th>Number Of Plans:</th>\n";
  print "    <td><input type=text name=\"plan_count\" value=\"\" size=3 required></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th valign=top>Select wizard's output/display format:</th>\n";
  print "    <td><input type=radio name=\"output_format\" value=\"html_code\" checked> Web Page (HTML Code)\n";
  print "<br><input type=radio name=\"output_format\" value=\"form_only\"> Form Code Only</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<p>\n";
  print "<table border=0>\n";
  print "  <tr>\n";
  print "    <td><input type=checkbox name=\"logo\" value=\"yes\"></td>\n";
  print "    <td>Would you like to include a logo\?</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td><input type=checkbox name=\"background_image\" value=\"yes\"></td>\n";
  print "    <td>Would you like to include a background image\?</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td><input type=checkbox name=\"top_message\" value=\"yes\"></td>\n";
  print "    <td>Would you like to put a message at the top of the web page\?</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td><input type=checkbox name=\"bottom_message\" value=\"yes\"></td>\n";
  print "    <td>Would you like to put a message at the bottom of the web page\?</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=2>&nbsp;<br>Please select a currency type:\n";
  print "      <select name=\"currency_type\">\n";
  if ($processor =~ /^(pago|globalc|wirecard|ncb|planetpay|barclays|fifththird)$/) {
    foreach my $key (sort keys %joinpage_wizard::currencyUSDSYM) {
      print "<option value=\"$key\">$joinpage_wizard::currencyUSDSYM{$key}</option>\n";
    }
  }
  elsif ($features{'curr_allowed'} ne '') {
    ## Modifed 20060316 DCP.  Support for curr_allowed in features.  Also currency in customer table is never a pipe delimited list.
    my $currency = $features{'curr_allowed'};
    $currency = lc($currency);
    my @split_temp = split(/\|/, $currency);
    foreach my $var (@split_temp) {
      if ($var =~ /\w/i) {
        print "<option value=\"$var\">$joinpage_wizard::currencyUSDSYM{$var}</option>\n";
      }
    }
  }
  elsif ($currency ne '') {
    print "<option value=\"$currency\">$joinpage_wizard::currencyUSDSYM{$currency}</option>\n";
  }
  else {
    print "<option value=\"usd\">\$</option>\n";
  }
  print "</select></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<p>\n";
  print "<input type=submit class=\"button\" value=\"Proceed To Next Step\">\n";
  print "</div>\n";
  print "</form>\n";

  &html_tail();

  return;
}

sub pass1 {
  my $dbh = &miscutils::dbhconnect('pnpmisc');
  my $sth = $dbh->prepare(q{
      SELECT processor
      FROM customers
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$joinpage_wizard::merchant") or die "Can't execute: $DBI::errstr";
  my ($processor) = $sth->fetchrow;
  $sth->finish();
  $dbh->disconnect;

  &pass1_error_check();

  &html_head();
  print "<div align=center>Please wait for this page to load completely before attempting to define the order form.\n";
  print "<br>This process could take a few moments to complete, depending upon the number of plans requested. </div>\n";

  print "<form method=post action=\"$ENV{'SCRIPT_NAME'}/join.htm\">\n";
  print "<input type=hidden name=\"function\" value=\"pass2\">\n";
  print "<input type=hidden name=\"image\" value=\"$joinpage_wizard::query{'image'}\">\n";
  print "<input type=hidden name=\"logo\" value=\"$joinpage_wizard::query{'logo'}\">\n";
  print "<input type=hidden name=\"background_image\" value=\"$joinpage_wizard::query{'background_image'}\">\n";
  print "<input type=hidden name=\"currency_type\" value=\"$joinpage_wizard::query{'currency_type'}\">\n";
  print "<input type=hidden name=\"output_format\" value=\"$joinpage_wizard::query{'output_format'}\">\n";

  print "<table border=0 cellspacing=0 cellpadding=0 width=760>\n";

  print "  <tr>\n";
  print "    <td class=\"leftside\">Publisher Name:</td>\n";
  print "    <td class=\"rightside\">$joinpage_wizard::merchant</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"leftside\">Publisher Email:</td>\n";
  print "    <td class=\"rightside\"><input type=email name=\"publisher_email\" value=\"\" placeholder=\"you\@yourdomain.com\" size=35>\n";
  print "<br><i>This is the email address in which your merchant confirmation email are sent.</i>\n";
  print "<br><i>If omitted, the order form will use the email address set within the Email Management admin area.</i></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"leftside\">Order ID:</td>\n";
  print "    <td class=\"rightside\"><input type=text name=\"order_id\" value=\"\" placeholder=\"membership\" size=35 maxlength=23>\n";
  print "<br><i>This is a unique value to define the orders.</i></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"leftside\">Cards Allowed:</td>\n";
  print "    <td class=\"rightside\"><input checked type=checkbox name=\"card_allowed_Visa\" value=\"yes\"> Visa\n";
  print " <input checked type=checkbox name=\"card_allowed_Mastercard\" value=\"yes\"> Mastercard\n";
  print " <input type=checkbox name=\"card_allowed_Amex\" value=\"yes\"> American Express\n";
  print " <input type=checkbox name=\"card_allowed_Discover\" value=\"yes\"> Discover\n";
  print " <input type=checkbox name=\"card_allowed_Diners\" value=\"yes\"> Diners Club\n";
  print " <input type=checkbox name=\"card_allowed_JCB\" value=\"yes\"> JCB\n";
  print " <input type=checkbox name=\"card_allowed_KC\" value=\"yes\"> KeyCard\n";
  if ($processor =~ /^(pago|barclays)$/) {
    print " <input type=checkbox name=\"card_allowed_SWTCH\" value=\"yes\"> Switch\n";
    print " <input type=checkbox name=\"card_allowed_SOLO\" value=\"yes\"> Solo\n";
  }
  print "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"leftside\">Payment Methods:</td>\n";
  print "    <td class=\"rightside\"><input checked type=checkbox name=\"paymethod_credit\" value=\"yes\"> Credit Card\n";
  print " <input type=checkbox name=\"paymethod_onlinecheck\" value=\"yes\"> Online Check\n";
  print " <input type=checkbox name=\"paymethod_web900\" value=\"yes\"> Web-900</td></td>\n";
  print "  </tr>\n";

  if ($joinpage_wizard::query{'output_format'} !~ /^(form_only)$/) {
    if (($joinpage_wizard::query{'logo'} eq 'yes') || ($joinpage_wizard::query{'background_image'} eq 'yes')) {
      print "  <tr>\n";
      print "    <td class=\"leftside\">URL To Image Directory:</td>\n";
      print "    <td class=\"rightside\"><input type=text name=\"image_path\" value=\"\" size=45 placeholder=\"http://www.mysite.com/images\"></td>\n";
      print "  </tr>\n";
    }
    if ($joinpage_wizard::query{'logo'} eq 'yes') {
      print "  <tr>\n";
      print "    <td class=\"leftside\">Name Of Logo Image:</td>\n";
      print "    <td class=\"rightside\"><input type=text name=\"logo_name\" value=\"\" placeholder=\"logo.gif\"></td>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <td class=\"leftside\">Logo Alignment:</td>\n";
      print "    <td class=\"rightside\"><select name=\"logo_align\">\n";
      print "<option value=\"left\">Left</option>";
      print "<option selected value=\"center\">Center</option>";
      print "<option value=\"right\">Right</option>";
      print "</select></td>\n";
      print "  </tr>\n";
    }
  }

  print "</table>\n";

  if ($joinpage_wizard::query{'output_format'} !~ /^(form_only)$/) {
    print "<hr>\n";

    print "<div align=center>\n";
    print "<table border=0 cellspacing=0 cellpadding=3>\n";
    print "  <tr>\n";
    print "    <td class=\"section_title\" colspan=2>Color Scheme</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    if ($joinpage_wizard::query{'background_image'} eq 'yes') {
      print "    <td class=\"leftside\">Background Image</td>\n";
      print "    <td class=\"rightside\"><input type=text name=\"background_name\" value=\"\" placeholder=\"background.jpg\"></td>\n";
    }
    else {
      print "    <td class=\"leftside\">Background Color</td>\n";
      print "    <td class=\"rightside\">" . &hex_colors('background_color','FFFFFF') . "</td>\n";
    }
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Text Color</td>\n";
    print "    <td class=\"rightside\">" . &hex_colors('text_color','000000') . "</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Link Color</td>\n";
    print "    <td class=\"rightside\">" . &hex_colors('link_color','0000FF') . "</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Visited Link Color</td>\n";
    print "    <td class=\"rightside\">" . &hex_colors('vlink_color','FF00FF') . "</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftside\">Active Link Color</td>\n";
    print "    <td class=\"rightside\">" . &hex_colors('alink_color','FF0000') . "</td>\n";
    print "  </tr>\n";

    print "</table>\n";
    print "</div>\n";
  }

  print "<hr>\n";

  print "<table border=0 cellspacing=0 cellpadding=3 width=760>\n";

  if ($joinpage_wizard::query{'output_format'} !~ /^(form_only)$/) {
    if ($joinpage_wizard::query{'top_message'} eq 'yes') {
      print "  <tr>\n";
      print "    <td class=\"leftside\">Top Message:</td>\n";
      print "    <td class=\"rightside\">Please enter the message to be displayed at the top of the order form here:\n";
      print "<textarea name=\"top_message\" rows=5 cols=60></textarea>\n";
      print "<br>Top Message Alignment: <select name=\"top_message_align\">\n";
      print "<option value=\"left\">Left</option>\n";
      print "<option value=\"center\">Center</option>\n";
      print "<option value=\"right\">Right</option>\n";
      print "</select></td>\n";
      print "  </tr>\n";
    }

    if ($joinpage_wizard::query{'bottom_message'} eq 'yes') {
      print "  <tr>\n";
      print "    <td class=\"leftside\">Bottom Message:</td>\n";
      print "    <td class=\"rightside\">Please enter the message to be displayed at the bottom of the order form here:\n";
      print "<textarea name=\"bottom_message\" rows=5 cols=60></textarea>\n";
      print "<br>Bottom Message Alignment: <select name=\"bottom_message_align\">\n";
      print "<option value=\"left\">Left</option>\n";
      print "<option value=\"center\">Center</option>\n";
      print "<option value=\"right\">Right</option>\n";
      print "</select></td>\n";
      print "  </tr>\n";
    }
  }

  print "  <tr>\n";
  print "    <td class=\"leftside\">Offer Subscription Renewal Option:</td>\n";
  print "    <td class=\"rightside\"><select name=\"subscription_renewal\">\n";
  print "<option value=\"yes\">Yes</option>\n";
  print "<option value=\"no\" selected>No</option>\n";
  print "</select></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"leftside\">Suppress Username/Password Selection:</td>\n";
  print "    <td class=\"rightside\"><select name=\"suppress_unpw\">\n";
  print "<option value=\"yes\">Yes</option>\n";
  print "<option value=\"no\" selected>No</option>\n";
  print "</select>\n";
  print "<br><i>When set to 'yes', will suppress the selection of username/password on the payment billing & summery pages.</i>\n";
  print "<br><i>A unique username/password will be generated automatically for your customers.</i></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"leftside\">Please Select A Page Format:</td>\n";
  print "    <td class=\"rightside\"><input checked type=radio name=\"form_type\" value=\"radio_buttons\"> Radio Buttons\n";
  print "<br><input type=radio name=\"form_type\" value=\"select_box\"> Drop Down Select Box\n";
  print "<br><input type=radio name=\"form_type\" value=\"submit_buttons\"> Plain Submit Buttons</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"leftside\">Form Alignment:</td>\n";
  print "    <td class=\"rightside\"><select name=\"form_align\">\n";
  print "<option value=\"left\">Left</option>\n";
  print "<option selected value=\"center\">Center</option>\n";
  print "<option value=\"right\">Right</option>\n";
  print "</select></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<p>";

  print "<div align=center>\n";
  print "<table border=0 cellspacing=0 cellpadding=3>\n";
  print "  <tr>\n";
  print "    <td class=\"listsection_title\">PlanID</td>\n";
  print "    <td class=\"listsection_title\">SKU/Model #</td>\n";
  print "    <td class=\"listsection_title\">Cost</td>\n";
  print "    <td class=\"listsection_title\">Plan Description</td>\n";
  print "  </tr>\n";

  for (my $i = 1; $i <= $joinpage_wizard::query{'plan_count'}; $i++) {
    my $isRequired = '';
    if ($i == 1) {
      $isRequired = 'required';
    }

    print "  <tr>\n";
    printf("    <td align=center bgcolor=\"#eeeeee\"><input type=text name=\"plan%d\" value=\"\" size=4 %s></td>\n", $i, $isRequired);
    printf("    <td align=center bgcolor=\"#eeeeee\"><input type=text name=\"item%d\" value=\"\" %s></td>\n", $i, $isRequired);
    printf("    <td align=center bgcolor=\"#eeeeee\" nowrap> %s<input type=ext name=\"cost%d\" value=\"\" size=6 %s></td>\n", $joinpage_wizard::currencyUSDSYM{"$joinpage_wizard::query{'currency_type'}"}, $i, $isRequired);
    printf("    <td align=center bgcolor=\"#eeeeee\"><input type=text name=\"description%d\" value=\"\" size=30 %s></td>\n", $i, $isRequired);
    print "  </tr>\n";
  }

  print "</table>\n";
  print "</div>\n";

  print "<p>\n";
  print "<div align=center>\n";
  print "<input type=submit class=\"button\" value=\"Create Order Form\" onClick=\"alert('PLEASE NOTE: The following is your completed join page.  In order to publish this page to your web site, save a copy of this page to your computer.  Then upload or FTP the saved file to your web server.')\">\n";
  print "<br>&nbsp;\n";
  print "</div>\n";

  &html_tail();

  return;
}

sub pass2 {
  &pass2_error_check();

  if ($joinpage_wizard::query{'output_format'} !~ /^(form_only)$/) {
    &html_shead();

    if ($joinpage_wizard::query{'logo'} eq 'yes') {
      print "<div align=\"$joinpage_wizard::query{'logo_align'}\"><img src=\"$joinpage_wizard::query{'logo_name'}\"></div>\n";
    }

    if ($joinpage_wizard::query{'top_message'} ne '') {
      print "<div align=\"$joinpage_wizard::query{'top_message_align'}\"><p>$joinpage_wizard::query{'top_message'}</p></div>\n";
    }
  }

  ### For tabled form format
  if (($joinpage_wizard::query{'form_type'} eq 'radio_buttons') || ($joinpage_wizard::query{'form_type'} eq 'select_box')) {
    &form_head();

    my ($j);
    for (my $i = 1; $i > 0; $i++) {
      $joinpage_wizard::query{"cost$i"} = sprintf("%0.2f", $joinpage_wizard::query{"cost$i"});

      printf("<input type=hidden name=\"plan%d\" value=\"%s\">\n", $i, $joinpage_wizard::query{"plan$i"});
      printf("<input type=hidden name=\"item%d\" value=\"%s\">\n", $i, $joinpage_wizard::query{"item$i"});
      printf("<input type=hidden name=\"description%d\" value=\"%s\">\n", $i, $joinpage_wizard::query{"description$i"});
      printf("<input type=hidden name=\"cost%d\" value=\"%s\">\n", $i, $joinpage_wizard::query{"cost$i"});
      $j = $i + 1;

      if ($joinpage_wizard::query{"plan$j"} eq '') {
        #print "\n\n Plan$j Does Not Exist\nNormal Exit\n";
        $i = -2;
      }
      elsif ($i == $joinpage_wizard::plan_limit) {
        print "\n\n Plan Limit Reached - Program Protection\n\n";
        $i = -1;
      }
    }

    print "<div align=\"$joinpage_wizard::query{'form_align'}\">\n";

    if ($joinpage_wizard::query{'form_type'} eq 'radio_buttons') {
      print "<table border=1 cellspacing=0 cellpadding=3>\n";
      print "  <tr>\n";
      print "    <th>&nbsp;</th>\n";
      print "    <th>Membership Description</th>\n";
      print "    <th>Cost</th>\n";
      print "  </tr>\n";

      for (my $i = 1; $i > 0; $i++) {
        print "  <tr>\n";
        print "    <td><input type=radio name=\"roption\" value=\"$i\"";
        if ($i == 1) {
          print " checked></td>\n";
        }
        else {
          print"></td>\n";
        }
        printf("    <td align=center>%s</td>\n", $joinpage_wizard::query{"description$i"});
        printf("    <td align=left>%s%0.02f</td>\n", $joinpage_wizard::currencyUSDSYM{"$joinpage_wizard::query{'currency_type'}"}, $joinpage_wizard::query{"cost$i"});
        print "  </tr>\n";

        $j = $i + 1;

        if ($joinpage_wizard::query{"plan$j"} eq '') {
          #print "\n\n Item$j Does Not Exist\nNormal Exit\n";
          $i = -2;
        }
        elsif ($i == $joinpage_wizard::plan_limit) {
          print "\n\n Plan Limit Reached - Program Protection\n\n";
          $i = -1;
        }
      }
      print "</table>\n";
    } # End radio button form type
    if ($joinpage_wizard::query{'form_type'} eq 'select_box') {
      # Begin select box form type
      print "Membership Plan Descriptions</th>\n";
      print "<br><select name=\"roption\">\n";

      for (my $i = 1; $i > 0; $i++) {
        print "<option value=\"$i\"";
        if ($i == 1) {
          print " selected";
        }
        printf(">%s - %s%0.02f</option>\n", $joinpage_wizard::query{"description$i"}, $joinpage_wizard::currencyUSDSYM{"$joinpage_wizard::query{'currency_type'}"}, $joinpage_wizard::query{"cost$i"});

        $j = $i + 1;

        if ($joinpage_wizard::query{"plan$j"} eq '') {
          #print "\n\n Item$j Does Not Exist\nNormal Exit\n";
          $i = -2;
        }
        if ($i == $joinpage_wizard::plan_limit) {
          print "\n\n Plan Limit Reached - Program Protection\n\n";
          $i = -1;
        }
      }
      print "</select>\n";
      print "<br>\n";
    } # End select box for type

    if ($joinpage_wizard::query{'subscription_renewal'} eq 'yes') {
      print "<p>To renew your account, please select your payment plan from the above options.\n";
      print "<br>Then please enter your existing username & password below.\n";
      print "<table border=0>\n";
      print "  <tr>\n";
      print "    <th align=left>Username:</th>\n";
      print "    <td><input type=text name=\"username\" value=\"\" size=12></td>\n";
      print "  </tr>\n";
      print "  <tr>\n";
      print "    <th align=left>Password:</th>\n";
      print "    <td><input type=password name=\"password\" value=\"\" size=12></td>\n";
      print "  </tr>\n";
      print "</table>\n";
    }

    if (($joinpage_wizard::query{'paymethod_onlinecheck'} eq 'yes') || ($joinpage_wizard::query{'paymethod_web900'} eq 'yes')) {
      print "<p>Please Select Your Payment Method:\n";
      print "<select name=\"paymethod\">\n";
      if ($joinpage_wizard::query{'paymethod_credit'} eq 'yes') {
        print "<option value=\"credit\">Credit Card</option>\n";
      }
      if ($joinpage_wizard::query{'paymethod_onlinecheck'} eq 'yes') {
        print "<option value=\"onlinecheck\">Online Check</option>\n";
      }
      if ($joinpage_wizard::query{'paymethod_web900'} eq 'yes') {
        print "<option value=\"web900\">Web-900</option>\n";
      }
      print "</select>\n";
    }

    print "<p><input type=submit name=\"return\" value=\"PAY FOR SUBSCRIPTION\">\n";
    print "</form>\n";
    print "</div>\n";
  } # End tabled form format

  ### begin plain submit buttons format
  elsif ($joinpage_wizard::query{'form_type'} eq 'submit_buttons') {
    print "<div align=\"$joinpage_wizard::query{'form_align'}\">\n";

    my ($j);
    for (my $i = 1; $i > 0; $i++) {
      print "<p>\n";
      &form_head();
      printf("<input type=hidden name=\"plan\" value=\"%s\">\n", $joinpage_wizard::query{"plan$i"});
      printf("<input type=hidden name=\"item1\" value=\"%s\">\n", $joinpage_wizard::query{"item$i"});
      printf("<input type=hidden name=\"description1\" value=\"%s\">%s\n", $joinpage_wizard::query{"description$i"}, $joinpage_wizard::query{"description$i"});
      printf("<br><input type=hidden name=\"cost1\" value=\"%0.02f\">Price: %s%0.02f\n", $joinpage_wizard::query{"cost$i"}, $joinpage_wizard::currencyUSDSYM{"$joinpage_wizard::query{'currency_type'}"}, $joinpage_wizard::query{"cost$i"});
      print "<input type=hidden name=\"quantity1\" value=\"1\">\n";

      if (($joinpage_wizard::query{'paymethod_onlinecheck'} eq 'yes') || ($joinpage_wizard::query{'paymethod_web900'} eq 'yes')) {
        print "<p> Please Select Your Payment Method:\n";
        print "<select name=\"paymethod\">\n";
        if ($joinpage_wizard::query{'paymethod_credit'} eq 'yes') {
          print "<option value=\"credit\">Credit Card</option>\n";
        }
        if ($joinpage_wizard::query{'paymethod_onlinecheck'} eq 'yes') {
          print "<option value=\"onlinecheck\">Online Check</option>\n";
        }
        if ($joinpage_wizard::query{'paymethod_web900'} eq 'yes') {
          print "<option value=\"web900\">Web-900</option>\n";
        }
        print "</select>\n";
      }

      if ($joinpage_wizard::query{'subscription_renewal'} eq 'yes') {
        print "<p>To renew your account, please select your payment plan from the above options.\n";
        print "<br>Then please enter your existing username & password below.\n";
        print "<table border=0>\n";
        print "  <tr>\n";
        print "    <th align=left>Username:</th>\n";
        print "    <td><input type=text name=\"username\" value=\"\" size=12></td>\n";
        print "  </tr>\n";
        print "  <tr>\n";
        print "    <th align=left>Password:</th>\n";
        print "    <td><input type=password name=\"password\" value=\"\" size=12></td>\n";
        print "  </tr>\n";
        print "</table>\n";
      }

      print "<p><input type=submit name=\"return\" value=\"PAY FOR SUBSCRIPTION\">\n";
      print "</form>\n";
      $j = $i + 1;

      if ($joinpage_wizard::query{"plan$j"} eq '') {
        #print "\n\n Plan$j Does Not Exist\nNormal Exit\n";
        $i = -2;
      }
     elsif ($i == $joinpage_wizard::plan_limit) {
        print "\n\n Plan Limit Reached - Program Protection\n\n";
        $i = -1;
      }
    }
    print "</div>\n";
  }  # End plain submit buttons format

  if ($joinpage_wizard::query{'output_format'} !~ /^(form_only)$/) {
    if (($joinpage_wizard::query{'bottom_message'} ne 'yes') && ($joinpage_wizard::query{'bottom_message'} ne '')) {
      print "<div align=\"$joinpage_wizard::query{'bottom_message_align'}\">\n";
      print "<p>$joinpage_wizard::query{'bottom_message'}\n";
      print "</div>\n";
    }

    if ($joinpage_wizard::query{'output_format'} !~ /^(form_only)$/) {
      &html_stail();
    }
  }

  return;
}

sub html_shead {
  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Order Form</title>\n";
  if (($joinpage_wizard::query{'function'} eq 'pass2') && (($joinpage_wizard::query{'image'} eq 'yes') || ($joinpage_wizard::query{'logo'} eq 'yes') || ($joinpage_wizard::query{'background_image'} eq 'yes'))) {
    print "<base href=\"$joinpage_wizard::query{'image_path'}\/\">\n";
  }
  print "</head>\n\n";
  if (($joinpage_wizard::query{'function'} eq 'pass2') && ($joinpage_wizard::query{'background_image'} eq 'yes')) {
    if ($joinpage_wizard::query{'text_color'} eq '') { $joinpage_wizard::query{'text_color'} = '#000000'; }
    if ($joinpage_wizard::query{'link_color'} eq '') { $joinpage_wizard::query{'link_color'} = '#0000FF'; }
    if ($joinpage_wizard::query{'alink_color'} eq '') { $joinpage_wizard::query{'alink_color'} = '#FF0000'; }
    if ($joinpage_wizard::query{'vlink_color'} eq '') { $joinpage_wizard::query{'vlink_color'} = '#FF00FF'; }

    printf("<body background=\"%s\" text=\"%s\" link=\"%s\" alink=\"%s\" vlink=\"%s\">\n", $joinpage_wizard::query{'background_name'}, $joinpage_wizard::query{'text_color'}, $joinpage_wizard::query{'link_color'}, $joinpage_wizard::query{'alink_color'}, $joinpage_wizard::query{'alink_color'});
  }
  else {
    if ($joinpage_wizard::query{'background_color'} eq '') { $joinpage_wizard::query{'background_color'} = '#FFFFFF'; }
    if ($joinpage_wizard::query{'text_color'} eq '') { $joinpage_wizard::query{'text_color'} = '#000000'; }
    if ($joinpage_wizard::query{'link_color'} eq '') { $joinpage_wizard::query{'link_color'} = '#0000FF'; }
    if ($joinpage_wizard::query{'alink_color'} eq '') { $joinpage_wizard::query{'alink_color'} = '#FF0000'; }
    if ($joinpage_wizard::query{'vlink_color'} eq '') { $joinpage_wizard::query{'vlink_color'} = '#FF00FF'; }

    printf("<body bgcolor=\"%s\" text=\"%s\" link=\"%s\" alink=\"%s\" vlink=\"%s\">\n", $joinpage_wizard::query{'background_color'}, $joinpage_wizard::query{'text_color'}, $joinpage_wizard::query{'link_color'}, $joinpage_wizard::query{'alink_color'}, $joinpage_wizard::query{'alink_color'});
  }

  return;
}

sub html_stail {
  print "</body>\n";
  print "</html>\n";

  return;
}

sub html_head {
  my ($section_title) = @_;

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Membership Management / Join Page Generator</title>\n";
  print "<link href=\"/css/style_account_settings.css\" type=\"text/css\" rel=\"stylesheet\">\n";

  print "<script type=\"text/javascript\">\n";
  print "//<!-- Start Script\n";

  print "function help_win(helpurl,swidth,sheight) {\n";
  print "  SmallWin = window.open(helpurl, 'HelpWindow','scrollbars=yes,resizable=yes,toolbar=no,menubar=no,height='+sheight+',width='+swidth);\n";
  print "}\n";

  print "function change_win(helpurl,swidth,sheight,windowname) {\n";
  print "  SmallWin = window.open(helpurl, windowname,'scrollbars=yes,resizable=yes,status=yes,toolbar=yes,menubar=yes,height='+sheight+',width='+swidth);\n";
  print "}\n";

  print "function closewin() {\n";
  print "  self.close();\n";
  print "}\n";

  print "//-->\n";
  print "</script>\n";

  print "</head>\n";

  print "<body bgcolor=\"#ffffff\">\n";
  print "<table width=760 border=0 cellpadding=0 cellspacing=0 id=\"header\">\n";
  print "  <tr>\n";
  print "    <td colspan=3 align=left>";
  if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
    print "<img src=\"/images/global_header_gfx.gif\" width=760 alt=\"Plug 'n Pay Technologies - we make selling simple.\" height=44 border=0>";
  }
  else {
    print "<img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Logo\">";
  }
  print "</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td colspan=3 align=left><img src=\"/images/header_bottom_bar_gfx.gif\" width=760 height=14></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td colspan=3 valign=top align=left><h1><a href=\"$ENV{'SCRIPT_NAME'}\">Membership Management / Join Page Generator</a>";
  if ($section_title ne '') {
    print " / $section_title";
  }
  print "</h1></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table width=760 border=0 cellpadding=0 cellspacing=0>\n";
  print "  <tr>\n";
  print "    <td valign=top align=left>";

  return;
}

sub html_tail {
  my @now = gmtime(time);
  my $year = $now[5] + 1900;

  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table width=760 border=0 cellpadding=0 cellspacing=0 id=\"footer\">\n";
  print "  <tr>\n";
  print "    <td align=left><a href=\"/admin/logout.cgi\" title=\"Click to log out\">Log Out</a> | <a href=\"javascript:change_win('/admin/helpdesk.cgi',600,500,'ahelpdesk')\">Help Desk</a> | <a id=\"close\" href=\"javascript:closewin();\" title=\"Click to close this window\">Close Window</a></td>\n";
  print "    <td align=right>\&copy; $year, ";
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

sub form_head {
  my $path_web = &pnp_environment::get('PNP_WEB');

  my $legacyPayScript = $path_web . '/payment/' . $joinpage_wizard::merchant . 'pay.cgi';

  if (-e "$legacyPayScript") {
    my $paymentURL = 'https://' . $ENV{'SERVER_NAME'} . '/payment/' . $joinpage_wizard::merchant . 'pay.cgi';
    print "<form method=post action=\"$paymentURL\">\n";
  }
  else {
    my $paymentURL = 'https://' . $ENV{'SERVER_NAME'} . '/payment/pay.cgi';
    print "<form method=post action=\"$paymentURL\">\n";
  }
  if ($joinpage_wizard::query{'publisher_email'} ne '') {
    print "<input type=hidden name=\"publisher-email\" value=\"$joinpage_wizard::query{'publisher_email'}\">\n";
  }
  else {
    print "<!-- NOTE: 'publisher-email' is set within the Email Management admin area. -->\n";
  }
  print "<input type=hidden name=\"publisher-name\" value=\"$joinpage_wizard::merchant\">\n";
  print "<input type=hidden name=\"order-id\" value=\"$joinpage_wizard::query{'order_id'}\">\n";
  print "<input type=hidden name=\"card-allowed\" value=\"$joinpage_wizard::query{'card_allowed'}\">\n";
  print "<input type=hidden name=\"easycart\" value=\"1\">\n";
  print "<input type=hidden name=\"subject\" value=\"Membership Receipt\">\n";
  print "<input type=hidden name=\"currency_symbol\" value=\"$joinpage_wizard::currencyUSDSYM{\"$joinpage_wizard::query{'currency_type'}\"}\">\n";

  if ($joinpage_wizard::query{'suppress_unpw'} eq 'yes') {
    print "<input type=hidden name=\"suppress_unpw\" value=\"yes\">\n";
  }

  return;
}

sub hex_colors {
  my ($color_type, $default_color) = @_;

  $color_type =~ s/[^0-9a-zA-Z\_\-]//g;
  $default_color =~ s/[^0-9a-zA-Z]//g;

  my %colors = (
    "70DB93","Aquamarine",
    "5C3317","Baker\'s Chocolate",
    "000000","Black",
    "0000FF","Blue",
    "9F5F9F","Blue Violet",
    "B5A642","Brass",
    "D9D919","Bright Gold",
    "A62A2A","Brown",
    "8C7853","Bronze",
    "A67D3D","Bronze II",
    "5F9F9F","Cadet Blue",
    "D98719","Cool Copper",
    "B87333","Copper",
    "FF7F00","Coral",
    "00FFFF","Cyan",
    "42426F","Corn Flower Blue",
    "5C4033","Dark Brown",
    "2F4F2F","Dark Green",
    "4A766E","Dark Green Copper",
    "4F4F2F","Dark Olive Green",
    "9932CD","Dark Orchid",
    "871F78","Dark Purple",
    "6B238E","Dark Slate Blue",
    "2F4F4F","Dark Slate Gray",
    "97694F","Dark Tan",
    "7093DB","Dark Turquoise",
    "855E42","Dark Wood",
    "545454","Dim Gray",
    "856363","Dusty Rose",
    "D19275","Feldspar",
    "8E2323","Firebrick",
    "238E23","Forest Green",
    "CD7F32","Gold",
    "DBDB70","Goldenrod",
    "C0C0C0","Gray",
    "00FF00","Green",
    "527F76","Green Copper",
    "93DB70","Green Yellow",
    "215E21","Hunter Green",
    "4E2F2F","Indian Red",
    "9F9F5F","Khaki",
    "C0D9D9","Light Blue",
    "A8A8A8","Light Gray",
    "8F8FBD","Light Steel Blue",
    "E9C2A6","Light Wood",
    "32CD32","Lime Green",
    "FF00FF","Magenta",
    "E47833","Mandarin Orange",
    "8E236B","Maroon",
    "32CD99","Medium Aquamarine",
    "3232CD","Medium Blue",
    "6B8E23","Medium Forest Green",
    "EAEAAE","Meduim Goldenrod",
    "9370DB","Medium Orchid",
    "426F42","Medium Sea Green",
    "7F00FF","Medium Slate Blue",
    "7FFF00","Medium Spring Green",
    "70DBDB","Medium Turquoise",
    "DB7093","Medium Violet Red",
    "A68064","Medium Wood",
    "2F2F4F","Midnight Blue",
    "23238E","Navy Blue",
    "4D4DFF","Neon Blue",
    "FF6EC7","Neon Pink",
    "00009C","New Midnight Blue",
    "EBC79E","New Tan",
    "CFB53B","Old Gold",
    "FF7F00","Orange",
    "FF2400","Orange Red",
    "DB70DB","Orchid",
    "8FBC8F","Pale Green",
    "BC8F8F","Pink",
    "EAADEA","Plum",
    "D9D9F3","Quartz",
    "FF0000","Red",
    "5959AB","Rich Blue",
    "6F4242","Salmon",
    "8C1717","Scarlet",
    "238E68","Sea Grren",
    "6B4226","Semi-Sweet Chocolate",
    "8E6B23","Sienna",
    "E6E8FA","Silver",
    "3299CC","Sky Blue",
    "007FFF","Slate Blue",
    "FF1CAE","Spicy Pink",
    "00FF7F","Spring Green",
    "236B8E","Steel Blue",
    "38B0DE","Summer Sky",
    "DB9370","Tan",
    "D8BFD8","Thistle",
    "AFEAEA","Turquoise",
    "5C4033","Very Dark Brown",
    "CDCDCD","Very Light Gray",
    "4F2F4F","Violet",
    "CC3299","Violet Red",
    "D8D8BF","Wheat",
    "FFFFFF","White",
    "FFFF00","Yellow",
    "99CC32","Yellow Green"
  );

  my $html = "<select name=\"$color_type\">\n";
  $html .= "<option value=\"$default_color\">Default Color</option>\n";
  foreach my $key (&sort_hash(\%colors)) {
    $html .= sprintf("<option value=\"\#%s\">%s</option>\n", $key, $colors{$key});
  }
  $html .= "</select>"; # End of background_color list

  return $html;
}

sub sort_hash {
  my $x = shift;
  my %array=%$x;
  sort { $array{$a} cmp $array{$b}; } keys %array;
}

## The pass#_error_check sub-functions check for errors & strip out garbage from the input fields.
sub pass1_error_check {
  if ($joinpage_wizard::query{'plan_count'} eq '') {
    $joinpage_wizard::query{'plan_count'} = 1;
  }
  elsif ($joinpage_wizard::query{'plan_count'} > $joinpage_wizard::plan_limit) {
    print "\n\n You have specified more plans then this program will allow.  Maximum limit is $joinpage_wizard::plan_limit items.\n";
    print "<br>Please press the BACK button on your browser and enter valid number.\n";
    exit;
  }

  return;
}

sub pass2_error_check {
  $joinpage_wizard::query{'card_allowed'} = '';

  my @cards_types = ('Visa', 'Mastercard', 'Amex', 'Discover', 'Diners', 'JCB', 'KeyCard', 'SWTCH', 'SOLO');
  foreach my $type (@cards_types) {
    if ($joinpage_wizard::query{"card_allowed_$type"} eq 'yes') {
      if ($joinpage_wizard::query{'card_allowed'} ne '') {
        $joinpage_wizard::query{'card_allowed'} .= ',';
      }
      $joinpage_wizard::query{'card_allowed'} .= $type;
    }
  }

  my ($j);
  for (my $i = 1; $i > 0; $i++) {
    if ($joinpage_wizard::query{'item1'} eq '') {
      print "<p>You have neglected to input at least 1 plan into the form.  Please press the BACK button on your browser and enter the required information.\n";
      exit;
    }

    $j = $i + 1;

    if ($joinpage_wizard::query{"plan$j"} eq '') {
      #print "\n\n Plan$j Does Not Exist\nNormal Exit\n";
      $i = -2;
    }
    if ($i == $joinpage_wizard::plan_limit) {
      print "\n\n Plan Limit Reached - Program Protection\n\n";
      $i = -1;
    }
  }

  return;
}

sub reject_connection {
  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Order Form</title>\n";
  print "</head>\n\n";
  print "<body bgcolor=\"#ffffff\" text=\"#000000\">\n";

  print "<div align=center>\n";
  print "<p>When used outside of our demo account, your finalized join page form would appear here.\n";
  print "<p><a href=\"https://www.plugnpay.com/merchant-information-request/\">Please contact sales for additional access to this demo.</a>\n";
  print "</div>\n";

  print "</body>\n";
  print "</html>\n";

  exit;
}

1;
