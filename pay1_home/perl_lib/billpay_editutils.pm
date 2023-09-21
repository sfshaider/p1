package billpay_editutils;

use CGI;
use SHA;
use rsautils;
use mckutils_strict;
use miscutils;
use remote_strict;
use PlugNPay::CardData;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::Captcha::ReCaptcha;
use PlugNPay::Transaction::TransactionProcessor;
use PlugNPay::Features;
use POSIX qw(ceil floor);
use constants qw(%countries %USstates %USterritories %CNprovinces %USCNprov);
use strict;

require billpay_adminutils; # for all sub function calls to its menus & response screens

# Purpose: This lib does all the work with respect to billpay database queries & updates.
#          All response screens & interface menus should be created in 'billpay_adminutils.pm'.

# Design Notes:
# 10/30/13
# - 'remnant' only applies to installment payment invoices; as it's the remainder of given installment payment to be paid
# - For 1-time payment invoices, we simply use 'balance' to track how much is left to be paid.

sub new {
  my $type = shift;

  ## allow Proxy Server to modify ENV variable 'REMOTE_ADDR'
  if ($ENV{'HTTP_X_FORWARDED_FOR'} ne '') {
    $ENV{'REMOTE_ADDR'} = $ENV{'HTTP_X_FORWARDED_FOR'};
  }

  # must pass in hash for this to work correctly.
  %billpay_editutils::query = @_;

  $billpay_editutils::dbh = &miscutils::dbhconnect("billpres");

  $billpay_editutils::path_index = "index.cgi";
  $billpay_editutils::path_edit = "edit.cgi";
  $billpay_editutils::path_logout = "logout.cgi";

  # pipe delimited email addresses that users cannot save billpay profile changes to
  $billpay_editutils::reject_email = "trash\@plugnpay\.com"; # pipe delimited email address list of users who cannot save billpay profile changes

  #my @now = gmtime(time);
  #my $date = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);
  #open(DEBUG,'>>',"/home/pay1/database/debug/billpayedit_debug.txt");
  #my $date = localtime(time);
  #print DEBUG "UN:$ENV{'REMOTE_USER'}, DATE:$date EST, PID:$$, ";
  #my @params = $query->param;
  #foreach my $param (@params) {
  #  my $s = &CGI::escapeHTML($query->param($param));
  #  print DEBUG "$param:$s, ";
  #}
  #print DEBUG "\n";
  #close(DEBUG);

  #@billpay_editutils::month_names = ("", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec");

  %billpay_editutils::countries = %constants::countries;
  %billpay_editutils::USstates = %constants::USstates;
  %billpay_editutils::USterritories = %constants::USterritories;
  %billpay_editutils::CNprovinces = %constants::CNprovinces;
  %billpay_editutils::USCNprov = %constants::USCNprov;

  return [], $type;
}

sub response_page {
  # this response page is for placing chunks of HTML code into the layout cleanly
  my ($response) = @_;

  &billpay_adminutils::head();

  if ($main::query{'function'} =~ /^(report_)/i) {
    print "<table border=0 cellspacing=2 cellpadding=0 width=760>\n";
    print "  <tr>\n";
    print "    <td><h1>$billpay_language::lang_titles{'service_title'} / $billpay_language::lang_titles{'service_subtitle_reportresults'}</h1></td>\n";
    print "    <td align=right><form><input type=button class=\"button\" value=\"$billpay_language::lang_titles{'button_closewindow'}\" onClick=\"window.close();\"> &nbsp;</td></form>\n";
    print "  </tr>\n";
    print "</table>\n";
  }
  if ($response !~ /^(\<table )/) {
    print "<table width=\"100%\" border=0 cellspacing=2 cellpadding=0>\n";
  }
  print "$response\n";
  if ($response !~ /(\<\/table\>)^/) {
    print "</table>\n";
  }

  &billpay_adminutils::tail();
  return;
}

sub error_response_page {
  # this response page is for placing an error response message on screen & exiting
  my ($response) = @_;

  &billpay_adminutils::head();

  if ($main::query{'function'} =~ /^(report_)/i) {
    print "<table border=0 cellspacing=2 cellpadding=0 width=760>\n";
    print "  <tr>\n";
    print "    <td><h1>$billpay_language::lang_titles{'service_title'} / $billpay_language::lang_titles{'service_subtitle_reportresults'}</h1></td>\n";
    print "    <td align=right><form><input type=button class=\"button\" value=\"$billpay_language::lang_titles{'button_closewindow'}\" onClick=\"window.close();\"> &nbsp;</td></form>\n";
    print "  </tr>\n";
    print "</table>\n";
  }
  if ($response !~ /^(\<table )/) {
    print "<table width=\"100%\" border=0 cellspacing=2 cellpadding=0>\n";
  }
  print "<b>$response</b>\n";
  if ($response !~ /(\<\/table\>)^/) {
    print "</table>\n";
  }

  &billpay_adminutils::tail();
  exit;
}

sub edit_cust_profile_form {
  my %query = @_;
  my ($data, $data1, $data2, $data3);

  my %selected;

  if ($query{'function'} eq "edit_cust_profile_form") {
    # import customer profile info
    my %query2 = &get_cust_profile_info("$ENV{'REMOTE_USER'}");
    foreach my $key (sort keys %query2) {
      $query{"$key"} = $query2{"$key"};
    }

    # import optout info
    my %query3 = &get_optout_info("$ENV{'REMOTE_USER'}");
    foreach my $key (sort keys %query3) {
      $query{"$key"} = $query3{"$key"};
    }
  }

  # build contact information section
  $data1 .= "<table border=0 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  $data1 .= "  <tr>\n";
  $data1 .= "    <td colspan=2 bgcolor=\"#f4f4f4\"><p><b>$billpay_language::lang_titles{'section_gencontact'}</b></p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'name'} *</p></td>\n";
  $data1 .= "    <td valign=top><p><input type=text name=\"name\" value=\"$query{'name'}\" size=20></p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'company'} </p></td>\n";
  $data1 .= "    <td valign=top><p><input type=text name=\"company\" value=\"$query{'company'}\" size=20></p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'address1'} *</p></td>\n";
  $data1 .= "    <td valign=top><p><input type=text name=\"addr1\" value=\"$query{'addr1'}\" size=20></p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'addres2'} </p></td>\n";
  $data1 .= "    <td valign=top><p><input type=text name=\"addr2\" value=\"$query{'addr2'}\" size=20></p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'city'} *</p></td>\n";
  $data1 .= "    <td valign=top><p><input type=text name=\"city\" value=\"$query{'city'}\" size=20></p></td>\n";
  $data1 .= "  </tr>\n";

  if ($query{'state'} ne "") {
    $selected{"$query{'state'}"} = "selected";
  }

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'state'} *</p></td>\n";
  $data1 .= "    <td valign=top><p><select name=\"state\">\n";
  $data1 .= "<option value=\"\">Select Your State/Province/Territory</option>\n";
  foreach my $key (sort keys %billpay_editutils::USstates) {
    $data1 .= "<option value=\"$key\" $selected{$key}>$billpay_editutils::USstates{$key}</option>\n";
  }
  foreach my $key (sort keys %billpay_editutils::USterritories) {
    $data1 .= "<option value=\"$key\" $selected{$key}>$billpay_editutils::USterritories{$key}</option>\n";
  }
  foreach my $key (sort keys %billpay_editutils::USCNprov) {
    $data1 .= "<option value=\"$key\" $selected{$key}>$billpay_editutils::USCNprov{$key}</option>\n";
  }
  foreach my $key (sort keys %billpay_editutils::CNprovinces) {
    $data1 .= "<option value=\"$key\" $selected{$key}>$billpay_editutils::CNprovinces{$key}</option>\n";
  }
  $data1 .= "</select></p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'zip'} *</p></td>\n";
  $data1 .= "    <td valign=top><p><input type=text name=\"zip\" value=\"$query{'zip'}\" size=20></p></td>\n";
  $data1 .= "  </tr>\n";

  if ($query{'country'} eq "") {
    $query{'country'} = "US";
  }
  $selected{"$query{'country'}"} = "selected";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'country'} *</p></td>\n";
  $data1 .= "    <td valign=top><p><select name=\"country\">\n";
  foreach my $key (sort keys %billpay_editutils::countries) {
    $data1 .= "<option value=\"$key\" $selected{$key}>$billpay_editutils::countries{$key}</option>\n";
  }
  $data1 .= "</select></p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td colspan=2 bgcolor=\"#f4f4f4\"><p><b>$billpay_language::lang_titles{'section_instcontact'}</b></p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'phone'}</p></td>\n";
  $data1 .= "    <td valign=top><p><input type=tel name=\"phone\" value=\"$query{'phone'}\" size=20></p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'fax'}</p></td>\n";
  $data1 .= "    <td valign=top><p><input type=tel name=\"fax\" value=\"$query{'fax'}\" size=20></p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'email'} *</p></td>\n";
  $data1 .= "    <td valign=top><p><input type=email name=\"email\" value=\"$query{'email'}\" size=20></p></td>\n";
  $data1 .= "  </tr>\n";
  $data1 .= "</table>\n";

  # build misc preferences section
  $data2 .= "<table border=0 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  $data2 .= "  <tr>\n";
  $data2 .= "    <td colspan=2 bgcolor=\"#f4f4f4\"><p><b>$billpay_language::lang_titles{'section_misccontact'}</b></p></td>\n";
  $data2 .= "  </tr>\n";

#  $data2 .= "  <tr>\n";
#  $data2 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'password'}</p></td>\n";
#  $data2 .= "    <td valign=top><p><input type=text name=\"password\" value=\"$query{'password'}\" size=20></p></td>\n";
#  $data2 .= "  </tr>\n";
  $data2 .= "<input type=hidden name=\"password\" value=\"$query{'password'}\">\n";

  $data2 .= "  <tr>\n";
  $data2 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'acctstatus'}</p></td>\n";
  $data2 .= "    <td valign=top><p><select name=\"status\">\n";
  if ($query{'status'} ne "") {
    $data2 .= "      <option value=\"$query{'status'}\">Use Current: $query{'status'}</option>\n";
  }
  $data2 .= "      <option value=\"active\">Active</option>\n";
  #$data2 .= "      <option value=\"pending\">Pending</option>\n";
  $data2 .= "      <option value=\"hold\">Hold</option>\n";
  #$data2 .= "      <option value=\"cancelled\">Cancelled</option>\n";
  #$data2 .= "      <option value=\"fraud\">Fraud</option>\n";
  #$data2 .= "      <option value=\"test\">Test</option>\n";
  #$data2 .= "      <option value=\"debug\">Debug</option>\n";
  $data2 .= "      </select></p></td>\n";
  $data2 .= "  </tr>\n";

  $data2 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'optout_reminder'}</p></td>\n";
  $data2 .= "    <td valign=top><p><input type=checkbox name=\"optout_reminder\" value=\"yes\"";
  if ($query{'optout_reminder'} =~ /y/i) {
    $data2 .= " checked";
  }
  $data2 .= "> $billpay_language::lang_titles{'description_optout_reminder'}</p></td>\n";
  $data2 .= "  </tr>\n";
  $data2 .= "</table>\n";

  # security question section aka captcha
  my $captcha = new PlugNPay::Util::Captcha::ReCaptcha();

  $data3 .= "<table border=0 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  $data3 = "  <tr>\n";
  $data3 .= "    <td colspan=2 bgcolor=\"#f4f4f4\"><p><b>$billpay_language::lang_titles{'section_security'}</b></p></td>\n";
  $data3 .= "  </tr>\n";

  $data3 .= "  <tr>\n";
  $data3 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'captcha'} *</p></td>\n";
  $data3 .= "    <td valign=top><p>" . $captcha->formHTML() . "</p></td>\n";
  $data3 .= "  </tr>\n";
  $data3 .= "</table>\n";

  # now build the entire layout here
  $data .= "<form method=post action=\"$billpay_editutils::path_edit\" name=\"cust_prof_form\">\n";
  $data .= "<input type=hidden name=\"function\" value=\"update_cust_profile\">\n";

  $data .= "<table border=0 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  $data .= "  <tr>\n";
  $data .= "    <td colspan=2><h1><a href=\"$billpay_editutils::path_index\">$billpay_language::lang_titles{'service_title'}</a> / $billpay_language::lang_titles{'service_subtitle_custprofile'}</h1></td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <td colspan=2><p>$billpay_language::lang_titles{'statement_enter_profile'}\n";
  $data .= "<br>$billpay_language::lang_titles{'statement_requiredfields'} <b>*</b>.</p></td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <td colspan=2 valign=top>$data1\n";
  $data .= "    <br>$data2\n";
  $data .= "    <br>$data3</td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <td colspan=2 align=center><input type=submit class=\"button\" value=\"Submit\"> &nbsp; <input type=reset class=\"button\" value=\"Reset\"></td></form>\n";
  $data .= "  </tr>\n";
  $data .= "</table>\n";

  return $data;
}

sub update_cust_profile {
  my %query = @_;

  my $data;

  if ($query{'email'} ne "") {
    $query{'email'} = lc("$query{'email'}");
  }

  # list minimum required fields
  my @required = ('name', 'addr1', 'city', 'state', 'zip', 'country', 'email', 'g-recaptcha-response');

  # now check to see if required fields are filled in
  my $error = 0;
  my $error_reason = "";
  foreach my $key (@required) {
    if ($query{$key} eq '') {
      $error = 1;
      $error_reason = "missing_required";
    }
  }

  if ($error == 1) {
    $data = "<p>$billpay_language::lang_titles{'error_missing_required'}</p>\n";
  }
  else {
    # check captcha answer
    my $captcha = new PlugNPay::Util::Captcha::ReCaptcha();
    my $ok = $captcha->isValid('billpay', $query{'g-recaptcha-response'}, $ENV{'REMOTE_ADDR'});
    if ($ok) {
      $error = 0;
      #$data = 'reCAPTCHA Success';
    }
    else {
      $error = 1;
      $error_reason = "invalid_captcha";
      $data = "<p>$billpay_language::lang_titles{'error_invalid_captcha'}</p>\n";
    }
  }

  if ($error == 1) {
    $data .= &billpay_editutils::edit_cust_profile_form(%query);
  }
  else {
    # check for profile existance
    my $sth1 = $billpay_editutils::dbh->prepare(q{
        SELECT username 
        FROM customer2
        WHERE username=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth1->execute("$ENV{'REMOTE_USER'}") or die "Cannot execute: $DBI::errstr";
    my ($db_customer_id) = $sth1->fetchrow;
    $sth1->finish;

    if ($db_customer_id eq "") {
      # if no match was found, allow the insert to happen
      if ($ENV{'REMOTE_USER'} !~ /^($billpay_editutils::reject_email)$/) {
        my $sth2 = $billpay_editutils::dbh->prepare(q{
            INSERT INTO customer2 
            (username, password, status, name, company, addr1, addr2, city, state, zip, country, phone, fax, email)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
          }) or die "Cannot prepare: $DBI::errstr";
        $sth2->execute("$ENV{'REMOTE_USER'}", "$query{'password'}", "$query{'status'}", "$query{'name'}", "$query{'company'}", "$query{'addr1'}", "$query{'addr2'}", "$query{'city'}", "$query{'state'}", "$query{'zip'}", "$query{'country'}", "$query{'phone'}", "$query{'fax'}", "$query{'email'}") or die "Cannot execute: $DBI::errstr";
        $sth2->finish;

        &record_history("$ENV{'REMOTE_USER'}", "", "add_cust", "Customer Profile Added");
      }
      $data .= "<p>$billpay_language::lang_titles{'statement_contact_added'}</p>\n";
    }
    else {
      # if match was found, allow the update to happen
      if ($ENV{'REMOTE_USER'} !~ /^($billpay_editutils::reject_email)$/) {
        my $sth2 = $billpay_editutils::dbh->prepare(q{
            UPDATE customer2
            SET username=?, password=?, status=?, name=?, company=?, addr1=?, addr2=?, city=?, state=?, zip=?, country=?, phone=?, fax=?, email=?
            WHERE username=? 
          }) or die "Cannot prepare: $DBI::errstr";
        $sth2->execute("$ENV{'REMOTE_USER'}", "$query{'password'}", "$query{'status'}", "$query{'name'}", "$query{'company'}", "$query{'addr1'}", "$query{'addr2'}", "$query{'city'}", "$query{'state'}", "$query{'zip'}", "$query{'country'}", "$query{'phone'}", "$query{'fax'}", "$query{'email'}","$ENV{'REMOTE_USER'}") or die "Cannot execute: $DBI::errstr";
        $sth2->finish;

        &record_history("$ENV{'REMOTE_USER'}", "", "update_cust", "Customer Profile Updated");
      }
      $data .= "<p>$billpay_language::lang_titles{'statement_contact_updated'}</p>\n";
    }

    # update reminder optout setting
    my $sth_opt = $billpay_editutils::dbh->prepare(q{
        SELECT optout_value 
        FROM optout
        WHERE username=?
        AND optout_type='reminder'
      }) or die "Cannot prepare: $DBI::errstr";
    my $rc = $sth_opt->execute("$ENV{'REMOTE_USER'}") or die "Cannot execute: $DBI::errstr";
    my ($db_optout_reminder) = $sth_opt->fetchrow;
    $sth_opt->finish;

    if ($rc >= 1) {
      # if optout match was found, update value as necessary
      my $sth_opt2 = $billpay_editutils::dbh->prepare(q{
          UPDATE optout
          SET optout_value=?
          WHERE username=?
          AND optout_type=?
        }) or die "Cannot prepare: $DBI::errstr";
      $sth_opt2->execute("$query{'optout_reminder'}", "$ENV{'REMOTE_USER'}", "reminder") or die "Cannot execute: $DBI::errstr";
      $sth_opt2->finish;
    }
    else {
      # if no optout match was found, allow the insert to happen
      my $sth_opt3 = $billpay_editutils::dbh->prepare(q{
          INSERT INTO optout 
          (username, optout_type, optout_value)
          VALUES (?,?,?)
        }) or die "Cannot prepare: $DBI::errstr";
      $sth_opt3->execute("$ENV{'REMOTE_USER'}", "reminder", "$query{'optout_reminder'}") or die "Cannot execute: $DBI::errstr";
      $sth_opt3->finish;
    }

    # calculate number of active billing profiles on file
    my $sth3 = $billpay_editutils::dbh->prepare(q{
        SELECT count(username)
        FROM billing2
        WHERE username=?
        AND status=?
      }) or die "Can't do: $DBI::errstr";
    $sth3->execute("$ENV{'REMOTE_USER'}", "active") or die "Can't execute: $DBI::errstr";
    my ($bill_profile_cnt) = $sth3->fetchrow;
    $sth3->finish;

    if ($bill_profile_cnt < 1) {
      $data .= "<p>$billpay_language::lang_titles{'statement_nobillprofiles1'}\n";
      $data .= "<br>$billpay_language::lang_titles{'statement_nobillprofiles2'}\n";
      $data .= "<br><a href=\"$billpay_editutils::path_edit\?function=add_new_bill_profile_form\">$billpay_language::lang_titles{'link_add_billprofile'}</a></p>\n";
    }

    $data .= "<p><a href=\"$billpay_editutils::path_index\?function=show_cust_profile_menu\">$billpay_language::lang_titles{'link_custprofmenu'}</a></p>\n";
  }

  return $data;
}

sub view_cust_profile_form {
  my %query = @_;
  my ($data, $data1, $data2);

  # import customer profile info
  my %query2 = &get_cust_profile_info("$ENV{'REMOTE_USER'}");
  foreach my $key (sort keys %query2) {
    $query{"$key"} = $query2{"$key"};
  }

  # import optout info
  my %query3 = &get_optout_info("$ENV{'REMOTE_USER'}");
  foreach my $key (sort keys %query3) {
    $query{"$key"} = $query3{"$key"};
  }

  # build contact information section
  $data1 .= "<table border=0 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  $data1 .= "  <tr>\n";
  $data1 .= "    <td colspan=2 bgcolor=\"#f4f4f4\"><p><b>$billpay_language::lang_titles{'section_gencontact'}</b></p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>&nbsp; </p></td>\n";
  $data1 .= "    <td valign=top>\n";
  $data1 .= "<p>$query{'name'}\n";
  $data1 .= "<br>$query{'company'}\n";
  $data1 .= "<br>$query{'addr1'}\n";
  $data1 .= "<br>$query{'addr2'}\n";
  $data1 .= "<br>$query{'city'}\n";
  $data1 .= "<br>$query{'state'}\n";
  $data1 .= "<br>$query{'zip'}\n";
  $data1 .= "<br>$query{'country'}</p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td colspan=2 bgcolor=\"#f4f4f4\"><p><b>$billpay_language::lang_titles{'section_instcontact'}</b></p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>&nbsp; </p></td>\n";
  $data1 .= "    <td valign=top>\n";
  $data1 .= "<p>$billpay_language::lang_titles{'phone'} $query{'phone'}\n";
  $data1 .= "<br>$billpay_language::lang_titles{'fax'} $query{'fax'}\n";
  $data1 .= "<br>$billpay_language::lang_titles{'email'} $query{'email'}</p></td>\n";
  $data1 .= "  </tr>\n";
  $data1 .= "</table>\n";

  # build preferences section
  $data2 .= "<table border=0 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  $data2 .= "  <tr>\n";
  $data2 .= "    <td colspan=2 bgcolor=\"#f4f4f4\"><p><b>$billpay_language::lang_titles{'section_misccontact'}</b></p></td>\n";
  $data2 .= "  </tr>\n";

  $data2 .= "  <tr>\n";
  $data2 .= "    <td valign=top width=170><p>&nbsp; </p></td>\n";
  $data2 .= "    <td valign=top>\n";
  #$data2 .= "<p>$billpay_language::lang_titles{'password'} $query{'password'}</p>\n";
  $data2 .= "<p>$billpay_language::lang_titles{'acctstatus'} $query{'status'}\n";
  if ($query{'optout_reminder'} =~ /y/i) {  
    $data2 .= "<br>$billpay_language::lang_titles{'optout_reminder'} $query{'optout_reminder'}\n";
  }
  $data2 .= "</p></td>\n";
  $data2 .= "  </tr>\n";
  $data2 .= "</table>\n";

  # now build the entire layout here
  $data .= "<table border=0 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  $data .= "  <tr>\n";
  $data .= "    <td colspan=2><h1><a href=\"$billpay_editutils::path_index\">$billpay_language::lang_titles{'service_title'}</a> / Profile Information</h1></td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <td colspan=2><p>$billpay_language::lang_titles{'statement_enter_profile'}</p></td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <td valign=top>$data1\n";
  $data .= "    <br>$data2</td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <td colspan=2 align=center><form method=post action=\"$billpay_editutils::path_edit\">\n";
  $data .= "<input type=hidden name=\"function\" value=\"edit_cust_profile_form\">\n";
  $data .= "<input type=submit class=\"button\" value=\"Edit Contact Profile\"></td></form>\n";
  $data .= "  </tr>\n";
  $data .= "</table>\n";

  return $data;
}

sub create_profileid {
  my @date = gmtime(time);
  $date[4] = $date[4] + 1; # for correct month number
  $date[5] = $date[5] + 1900; # for correct 4-digit year number
  my $profileid = sprintf("%04d%02d%02d%02d%02d%02d%05d", $date[5], $date[4], $date[3], $date[2], $date[1], $date[0], $$);
  return $profileid;
}

sub edit_bill_profile_form {
  my %query = @_;
  my ($data, $data1, $data2);

  my %selected;

  if ($query{'function'} eq "edit_bill_profile_form") {
    my %query2 = &get_bill_profile_info("$query{'profileid'}");

    foreach my $key (sort keys %query2) {
      $query{"$key"} = $query2{"$key"};
    }
  }
  else {
    # assume that new bill profile needs to be created, so generate a new unique profileid
    $query{'profileid'} = &create_profileid();
  }

  # build contact information section
  $data1 .= "<table border=0 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  $data1 .= "  <tr>\n";
  $data1 .= "    <td colspan=2 bgcolor=\"#f4f4f4\"><p><b>$billpay_language::lang_titles{'section_billcontact'}</b></p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>&nbsp; </p></td>\n";
  $data1 .= "    <td valign=top><p><input type=checkbox name=\"billsame\" value=\"yes\"> $billpay_language::lang_titles{'description_billsame'}</p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'name'} *</p></td>\n";
  $data1 .= "    <td valign=top><p><input type=text name=\"cardname\" value=\"$query{'cardname'}\" size=20></p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'company'}</p></td>\n";
  $data1 .= "    <td valign=top><p><input type=text name=\"cardcompany\" value=\"$query{'cardcompany'}\" size=20></p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'address1'} *</p></td>\n";
  $data1 .= "    <td valign=top><p><input type=text name=\"cardaddr1\" value=\"$query{'cardaddr1'}\" size=20></p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'address2'}</p></td>\n";
  $data1 .= "    <td valign=top><p><input type=text name=\"cardaddr2\" value=\"$query{'cardaddr2'}\" size=20></p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'city'} *</p></td>\n";
  $data1 .= "    <td valign=top><p><input type=text name=\"cardcity\" value=\"$query{'cardcity'}\" size=20></p></td>\n";
  $data1 .= "  </tr>\n";

  if ($query{'cardstate'} ne "") {
    $selected{"$query{'cardstate'}"} = "selected";
  }

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'state'} *</p></td>\n";
  $data1 .= "    <td valign=top><p><select name=\"cardstate\">\n";
  $data1 .= "<option value=\"\">Select Your State/Province/Territory</option>\n";
  foreach my $key (sort keys %billpay_editutils::USstates) {
    $data1 .= "<option value=\"$key\" $selected{$key}>$billpay_editutils::USstates{$key}</option>\n";
  }
  foreach my $key (sort keys %billpay_editutils::USterritories) {
    $data1 .= "<option value=\"$key\" $selected{$key}>$billpay_editutils::USterritories{$key}</option>\n";
  }
  foreach my $key (sort keys %billpay_editutils::USCNprov) {
    $data1 .= "<option value=\"$key\" $selected{$key}>$billpay_editutils::USCNprov{$key}</option>\n";
  }
  foreach my $key (sort keys %billpay_editutils::CNprovinces) {
    $data1 .= "<option value=\"$key\" $selected{$key}>$billpay_editutils::CNprovinces{$key}</option>\n";
  }
  $data1 .= "</select></p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'zip'} *</p></td>\n";
  $data1 .= "    <td valign=top><p><input type=text name=\"cardzip\" value=\"$query{'cardzip'}\" size=20></p></td>\n";
  $data1 .= "  </tr>\n";

  if ($query{'cardcountry'} eq "") {
    $query{'cardcountry'} = "US";
  }
  $selected{"$query{'cardcountry'}"} = "selected";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'country'} *</p></td>\n";
  $data1 .= "    <td valign=top><p><select name=\"cardcountry\">\n";
  foreach my $key (sort keys %billpay_editutils::countries) {
    $data1 .= "<option value=\"$key\" $selected{$key}>$billpay_editutils::countries{$key}</option>\n";
  }
  $data1 .= "</select></p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td colspan=2>&nbsp;<p>$billpay_language::lang_titles{'statement_enter_ccach'}</p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td colspan=2 bgcolor=\"#f4f4f4\"><p><b>$billpay_language::lang_titles{'section_ccinfo'}</b></p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'cardnumber'}</p></td>\n";
  $data1 .= "    <td valign=top><p><input type=text name=\"cardnumber\" value=\"$query{'cardnumber'}\" size=20 autocomplete=\"off\"></p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'exp'}</p></td>\n";
  $data1 .= "    <td valign=top><p><input type=text name=\"exp\" value=\"$query{'exp'}\" size=5 autocomplete=\"off\"> MM/YY</p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td colspan=2 bgcolor=\"#f4f4f4\"><p><b>$billpay_language::lang_titles{'section_achinfo'}</b></p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td colspan=2><p>$billpay_language::lang_titles{'warn_achnote'}</p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'routingnum'}</p></td>\n";
  $data1 .= "    <td valign=top><p><input type=text name=\"routingnum\" value=\"$query{'routingnum'}\" size=10 maxlength=9 autocomplete=\"off\"></p></td>\n";
  $data1 .= "  </tr>\n";

  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'accountnum'}</p></td>\n";
  $data1 .= "    <td valign=top><p><input type=text name=\"accountnum\" value=\"$query{'accountnum'}\" size=21 maxlength=20 autocomplete=\"off\"></p></td>\n";
  $data1 .= "  </tr>\n";
  $data1 .= "</table>\n";

  # build misc preferences section
  $data2 .= "<table border=0 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  $data2 .= "  <tr>\n";
  $data2 .= "    <td colspan=2 bgcolor=\"#f4f4f4\"><p><b>$billpay_language::lang_titles{'section_miscinfo'}</b></p></td>\n";
  $data2 .= "  </tr>\n";

  $data2 .= "<input type=hidden name=\"profileid\" value=\"$query{'profileid'}\">\n";
  $data2 .= "<input type=hidden name=\"shacardnumber\" value=\"$query{'shacardnumber'}\">\n";

#  $data2 .= "  <tr>\n";
#  $data2 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'orderid'}</p></td>\n";
#  $data2 .= "    <td valign=top><p><input type=text name=\"orderid\" value=\"$query{'orderid'}\" size=20></p></td>\n";
#  $data2 .= "  </tr>\n";

#  $data2 .= "  <tr>\n";
#  $data2 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'accttype'}</p></td>\n";
#  $data2 .= "    <td valign=top><p><input type=text name=\"accttype\" value=\"$query{'accttype'}\" size=20></p></td>\n";
#  $data2 .= "  </tr>\n";

#  $data2 .= "  <tr>\n";
#  $data2 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'billusername'}</p></td>\n";
#  $data2 .= "    <td valign=top><p><input type=text name=\"billusername\" value=\"$query{'billusername'}\" size=20></p></td>\n";
#  $data2 .= "  </tr>\n";

  $data2 .= "  <tr>\n";
  $data2 .= "    <td valign=top width=170><p>$billpay_language::lang_titles{'status'}</p></td>\n";
  $data2 .= "    <td valign=top><p><select name=\"status\">\n";
  if ($query{'status'} ne "") {
    $data2 .= "      <option value=\"$query{'status'}\">Use Current: $query{'status'}</option>\n";
  }
  $data2 .= "      <option value=\"active\">Active</option>\n";
  #$data2 .= "      <option value=\"pending\">Pending</option>\n";
  $data2 .= "      <option value=\"hold\">Hold</option>\n";
  #$data2 .= "      <option value=\"cancelled\">Cancelled</option>\n";
  #$data2 .= "      <option value=\"fraud\">Fraud</option>\n";
  #$data2 .= "      <option value=\"test\">Test</option>\n";
  #$data2 .= "      <option value=\"debug\">Debug</option>\n";
  $data2 .= "      </select></p></td>\n";
  $data2 .= "  </tr>\n";
  $data2 .= "</table>\n";


  # now build the entire layout here
  $data .= "<form method=post action=\"$billpay_editutils::path_edit\" name=\"bill_prof_form\">\n";
  $data .= "<input type=hidden name=\"function\" value=\"update_bill_profile\">\n";

  $data .= "<table border=0 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  $data .= "  <tr>\n";
  $data .= "    <td colspan=2><h1><a href=\"$billpay_editutils::path_index\">$billpay_language::lang_titles{'service_title'}</a> / $billpay_language::lang_titles{'service_subtitle_billprofile'}</h1></td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <td colspan=2><p>$billpay_language::lang_titles{'statement_enter_profile'}\n";
  $data .= "<br>$billpay_language::lang_titles{'statement_requiredfields'} <b>*</b>.</p></td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <td valign=top>$data1\n";
  $data .= "    <br>$data2</td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <td colspan=2 align=center><input type=submit class=\"button\" value=\"Submit\"> &nbsp;  <input type=reset class=\"button\" value=\"Reset\"></td></form>\n";
  $data .= "  </tr>\n";
  $data .= "</table>\n";

  return $data;
}

sub update_bill_profile {
  my %query = @_;

  my $data;
  my $update_card_info = 0; # assume we do not need to update the CC/ACH info

  if ($query{'billsame'} eq "yes") {
    # get general contact address 
    my $sth0 = $billpay_editutils::dbh->prepare(q{
        SELECT name, company, addr1, addr2, city, state, zip, country 
        FROM customer2
        WHERE username=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth0->execute("$ENV{'REMOTE_USER'}") or die "Cannot execute: $DBI::errstr";
    my ($db_name, $db_company, $db_addr1, $db_addr2, $db_city, $db_state, $db_zip, $db_country) = $sth0->fetchrow;
    $sth0->finish;

    $query{'cardname'} = "$db_name";
    $query{'cardcompany'} = "$db_company";
    $query{'cardaddr1'} = "$db_addr1";
    $query{'cardaddr2'} = "$db_addr2";
    $query{'cardcity'} = "$db_city";
    $query{'cardstate'} = "$db_state";
    $query{'cardzip'} = "$db_zip";
    $query{'cardcountry'} = "$db_country";
  }

  # list minimum required fields
  my @required = ('cardname', 'cardaddr1', 'cardcity', 'cardstate', 'cardzip', 'cardcountry');

  # now check to see if required fields are filled in
  my $error = 0;
  foreach (my $a = 0; $a <= $#required; $a++) {
    if ($query{"$required[$a]"} !~ /[a-zA-Z_0-9]/) {
      $error = 1;
    }
  }

  # verify card # or routing/account number info
  my $cardlength = length $query{'cardnumber'};
  if (($query{'cardnumber'} !~ /\*\*/) && ($cardlength > 8)) {
    $query{'cardnumber'} =~ s/[^0-9]//g;
    $query{'cardnumber'} = substr($query{'cardnumber'},0,20);
    my $luhntest = &miscutils::luhn10($query{'cardnumber'});
    if ($luhntest eq "failure") {
      $data = "<p>$billpay_language::lang_titles{'error_invalid_cardnum'}</p>\n";
      $data .= &edit_bill_profile_form(%query);
      return $data;
    }
    else {
      $query{'accttype'} = "credit";
      $update_card_info = 1;
    }
  }
  elsif (($query{'routingnum'} ne "") || ($query{'accountnum'} ne "")) {
    if (length($query{'accountnum'}) < 5) {
      $data = "<p>$billpay_language::lang_titles{'error_invalid_accountnum'}</font></p>\n";
      $data .= &edit_bill_profile_form(%query);
      return $data;
    }

    $query{'routingnum'} =~ s/[^0-9]//g;
    my $luhntest = &modulus10($query{'routingnum'});
    if ((length($query{'routingnum'}) != 9) || ($luhntest eq "FAIL")){
      $data = "<p>$billpay_language::lang_titles{'error_invalid_routingnum'}</p>\n";
      $data .= &edit_bill_profile_form(%query);
      return $data;
    }

    if (($query{'routingnum'} ne "") && ($query{'accountnum'} ne "")) {
      $query{'cardnumber'} = sprintf("%s %s", $query{'routingnum'}, $query{'accountnum'});
      $query{'exp'} = "";
      $query{'accttype'} = "checking";
      $update_card_info = 1;
    }
  }

  # NOTE: need to add code here to flag errors when full credit card or ACH info is not provided, whenever $query{'cardnumber'} ne '**'

if ($error == 1) {
  $data = "<p>$billpay_language::lang_titles{'error_missing_required'}</p>\n";
  $data .= &billpay_editutils::edit_bill_profile_form(%query);
}
else {
  # check for shacardnumber existance, on new cards being entered
  if ($query{'shacardnumber'} eq "") {
    my $cardnumber = $query{'cardnumber'};
    my $sha = new SHA;
    $sha->add($cardnumber);
    my $shacardnumber = $sha->hexdigest();

    my $sth0 = $billpay_editutils::dbh->prepare(q{
        SELECT shacardnumber
        FROM billing2
        WHERE username=?
        AND shacardnumber=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth0->execute("$ENV{'REMOTE_USER'}", "$shacardnumber") or die "Cannot execute: $DBI::errstr";
    my ($db_shacardnumber) = $sth0->fetchrow;
    $sth0->finish;
    if ($db_shacardnumber ne "") {
      $data = "<p>$billpay_language::lang_titles{'error_card_onfile'}</font></p>\n";
      $data .= &billpay_editutils::edit_bill_profile_form(%query);
      return $data;
    }
  }

  # check for profile existance
  my $sth1 = $billpay_editutils::dbh->prepare(q{
      SELECT username
      FROM billing2
      WHERE username=?
      AND profileid=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth1->execute("$ENV{'REMOTE_USER'}", "$query{'profileid'}") or die "Cannot execute: $DBI::errstr";
  my ($db_customer_id) = $sth1->fetchrow;
  $sth1->finish;

  if ($db_customer_id eq "") {
    # if no match was found, allow the insert to happen
    if ($ENV{'REMOTE_USER'} !~ /^($billpay_editutils::reject_email)$/) {
      my $sth2 = $billpay_editutils::dbh->prepare(q{
          INSERT INTO billing2
          (username, profileid, orderid, status, cardname, cardcompany, cardaddr1, cardaddr2, cardcity, cardstate, cardzip, cardcountry, billusername, exp)
          VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        }) or die "Cannot prepare: $DBI::errstr";
      $sth2->execute("$ENV{'REMOTE_USER'}", "$query{'profileid'}", "$query{'orderid'}", "$query{'status'}", "$query{'cardname'}", "$query{'cardcompany'}", "$query{'cardaddr1'}", "$query{'cardaddr2'}", "$query{'cardcity'}", "$query{'cardstate'}", "$query{'cardzip'}", "$query{'cardcountry'}", "$query{'billusername'}", "$query{'exp'}") or die "Cannot execute: $DBI::errstr";
      $sth2->finish;

      &record_history("$ENV{'REMOTE_USER'}", "$query{'profileid'}", "add_bill", "Billing Profile Added");
    }
    $data .= "<p>$billpay_language::lang_titles{'statement_billing_added'}</p>\n";
  }
  else {
    # if match was found, allow the update to happen
    if ($ENV{'REMOTE_USER'} !~ /^($billpay_editutils::reject_email)$/) {
      my $sth2 = $billpay_editutils::dbh->prepare(q{
          UPDATE billing2
          SET username=?, profileid=?, orderid=?, status=?, cardname=?, cardcompany=?, cardaddr1=?, cardaddr2=?, cardcity=?, cardstate=?, cardzip=?, cardcountry=?, billusername=?, exp=?
          WHERE username=?
          AND profileid=?
        }) or die "Cannot prepare: $DBI::errstr";
      $sth2->execute("$ENV{'REMOTE_USER'}", "$query{'profileid'}", "$query{'orderid'}", "$query{'status'}", "$query{'cardname'}", "$query{'cardcompany'}", "$query{'cardaddr1'}", "$query{'cardaddr2'}", "$query{'cardcity'}", "$query{'cardstate'}", "$query{'cardzip'}", "$query{'cardcountry'}", "$query{'billusername'}", "$query{'exp'}", "$ENV{'REMOTE_USER'}", "$query{'profileid'}") or die "Cannot execute: $DBI::errstr";
      $sth2->finish;

      &record_history("$ENV{'REMOTE_USER'}", "$query{'profileid'}", "add_bill", "Billing Profile Updated");
    }
    $data .= "<p>$billpay_language::lang_titles{'statement_billing_updated'}</p>\n";
  }

  # store & encrypt card info, as needed 
  if (($update_card_info == 1) && ($ENV{'REMOTE_USER'} !~ /^($billpay_editutils::reject_email)$/)) {
    my $cardnumber = $query{'cardnumber'};
    my $sha = new SHA;
    $sha->add($cardnumber);
    my $shacardnumber = $sha->hexdigest();
    my ($enccardnumber, $length) = &rsautils::rsa_encrypt_card($query{'cardnumber'},"/home/pay1/pwfiles/keys/key");
    $query{'cardnumber'} = substr($query{'cardnumber'},0,4) . "**" . substr($query{'cardnumber'},-2,2);

    my $sth3 = $billpay_editutils::dbh->prepare(q{
        UPDATE billing2
        SET shacardnumber=?, cardnumber=?, enccardnumber=?, length=?, accttype=?
        WHERE username=?
        AND profileid=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth3->execute("$shacardnumber", "$query{'cardnumber'}", "$enccardnumber", "$length", "$query{'accttype'}", "$ENV{'REMOTE_USER'}", "$query{'profileid'}") or die "Cannot execute: $DBI::errstr";
    $sth3->finish;

    my $cd = new PlugNPay::CardData();
    eval {
      $cd->insertBillpayCardData({customer => "$ENV{'REMOTE_USER'}", profileID => "$query{'profileid'}", cardData => "$enccardnumber"});
    };
    if ($@) {
      my $datalog = new PlugNPay::Logging::DataLog({'collection' => 'billpay'});
      $datalog->log({
        'error' => "Failed insertBillpayCardData, caused by: $@",
        'caller' => $ENV{'REMOTE_USER'},
        'sub_function' => 'update_bill_profile',
        'customer' => $ENV{'REMOTE_USER'},
        'profileID' => $query{'profileid'}
      });
    }
  }
}

  my @now = gmtime(time);
  my $today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

  # calculate number of open/unpaid bills
  my $sth1 = $billpay_editutils::dbh->prepare(q{
      SELECT count(username)
      FROM bills2 
      WHERE username=?
      AND status=?
      AND expire_date>=?
    }) or die "Can't do: $DBI::errstr";
  $sth1->execute("$ENV{'REMOTE_USER'}", "open", "$today") or die "Can't execute: $DBI::errstr";
  my ($open_bill_cnt) = $sth1->fetchrow;
  $sth1->finish;

  if ($open_bill_cnt >= 1) {
    $data .= "<p>$billpay_language::lang_titles{'warn_openbills'} <a href=\"$billpay_editutils::path_edit\?function=list_bills_form\&status=open\">$billpay_language::lang_titles{'link_clickhere'}</a>.</p>\n";
  }

  $data .= "<p><a href=\"$billpay_editutils::path_index\?function=show_bill_profile_menu\">$billpay_language::lang_titles{'link_billprofmenu'}</a></p>\n";

  return $data;
}

sub list_bill_profile_hash {
  # produces a hash of all bill profilesIDs on file for the specified customer_id 
  my ($type, $cards_allowed) = @_;

  if ($cards_allowed ne "") {
    $cards_allowed =~ s/\W{1,}/\|/g;
  }

  my %profiles;
  my ($db_username, $db_profileid, $db_cardnumber, $db_enccardnumber, $db_length, $db_status, $db_accttype, $db_exp);

  my $sth = $billpay_editutils::dbh->prepare(q{
      SELECT username, profileid, cardnumber, enccardnumber, length, status, accttype, exp
      FROM billing2
      WHERE username=? 
      ORDER BY profileid
    }) or die "Cannot do: $DBI::errstr";
  $sth->execute("$ENV{'REMOTE_USER'}") or die "Cannot execute: $DBI::errstr";
  my $rv = $sth->bind_columns(undef,\($db_username, $db_profileid, $db_cardnumber, $db_enccardnumber, $db_length, $db_status, $db_accttype, $db_exp));
  while($sth->fetch) {
    if (($db_username eq "$ENV{'REMOTE_USER'}") && ($db_profileid ne "")) {
      if (($type eq "active_only") && ($db_status ne "active")) {
        # skip to next profile, don't list...
        next;
      }
      my ($cardtype_title);
      if ($db_accttype eq "credit") {
        my $cd = new PlugNPay::CardData();
        my $ecrypted_card_data = '';
        eval {
          $ecrypted_card_data = $cd->getBillpayCardData({customer => "$db_username", profileID => "$db_profileid"});
        };
        if (!$@) {
          $db_enccardnumber = $ecrypted_card_data;
        }

        my ($cardnumber, $cardtype);
        $cardnumber = &rsautils::rsa_decrypt_file($db_enccardnumber,$db_length,"print enccardnumber 497","/home/pay1/pwfiles/keys/key");
        $cardtype = &detect_cardtype("$cardnumber");

        if ($cardtype eq "SWTCH") {
          $cardtype_title = "Switch";
        }
        elsif ($cardtype eq "SOLO") {
          $cardtype_title = "Solo";
        }
        elsif ($cardtype eq "VISA") {
          $cardtype_title = "Visa";
        }
        elsif ($cardtype eq "MSTR") {
          $cardtype_title = "Mastercard";
        }
        elsif ($cardtype eq "AMEX") {
          $cardtype_title = "Amex";
        }
        elsif ($cardtype eq "JCB") {
          $cardtype_title = "JCB";
        }
        elsif ($cardtype eq "DNRS") {
          $cardtype_title = "Diners";
        }
        elsif ($cardtype eq "CRTB") {
          $cardtype_title = "CRTB";
        }
        elsif ($cardtype eq "DSCR") {
          $cardtype_title = "Discover";
        }
        elsif ($cardtype eq "JAL") {
          $cardtype_title = "JAL";
        }
        elsif ($cardtype eq "KC") {
          $cardtype_title = "KC";
        }
        elsif ($cardtype eq "MYAR") {
          $cardtype_title = "MYAR";
        }
        else {
          $cardtype_title = uc("$cardtype");
        }

        my ($exp_status, $exp_reason) = &check_expdate($db_exp, "", "");
        $profiles{"$db_profileid"}{'exp_status'} = $exp_status;
        $profiles{"$db_profileid"}{'exp_reason'} = $exp_reason;
      }
      elsif ($db_accttype eq "checking") {
        $cardtype_title = "Checking";
      }
      elsif ($db_accttype eq "savings") {
        $cardtype_title = "Savings";
      }

      $profiles{"$db_profileid"}{'accttype'} = $db_accttype; # e.g. credit/checking/savings
      $profiles{"$db_profileid"}{'type'} = $cardtype_title; # e.g. Visa, Mastercard, Discover, Checking, Savings, etc...
      $profiles{"$db_profileid"}{'cardnumber'} = $db_cardnumber; # e.g. 4111**11
      $profiles{"$db_profileid"}{'exp'} = $db_exp; # e.g. MM/YY

      $profiles{"$db_profileid"}{'title'} = "$cardtype_title - $db_cardnumber";
      #print "<!-- Username: $db_username, ProfileID: $db_profileid, Card Num: $db_cardnumber -->\n";

      # when cards_allowed is specified, skip any bill profiles which do not exist on that allowed list
      if (($cards_allowed ne "") && ($profiles{"$db_profileid"}{'type'} !~ /$cards_allowed/i)) {
        delete $profiles{"$db_profileid"};
      }
    }
  }
  $sth->finish;

  return %profiles;
}

sub check_expdate {
  # checks exp date given & returns if it's valid or not.
  my ($card_exp, $month_exp, $year_exp) = @_;

  my ($status, $response);

  # Possible status values:
  # 'valid'   - OK, exp is set into future
  # 'warn'    - OK, but warn it expires soon
  # 'expired' - reject as expired
  # 'problem' - reject as invalid

  # filter the values given
  $card_exp =~ s/[^0-9\/\-]//g;
  $month_exp =~ s/[^0-9]//g;
  $year_exp =~ s/[^0-9]//g;

  # get supplied exp date
  if ($card_exp ne "") {
    $month_exp = substr($card_exp, 0, 2);
    $year_exp = substr($card_exp, -2, 2);
  }
  else {
    $month_exp = substr($month_exp, 0, 2);
    $year_exp = substr($year_exp, -2, 2);
  }

  # check for invalid value
  if (($month_exp < 1) && ($month_exp > 12)) {
    return ("problem", "Invalid Expiration Date.");
    $month_exp = substr($month_exp, 0, 2);
  }

  # adjust for correct 4-digit year
  if ($year_exp > 90) {
    $year_exp = 1900 + $year_exp;
  }
  else {
    $year_exp = 2000 + $year_exp;
  }

  my $check_exp = $year_exp . $month_exp;

  # set cutoff exp date.
  my $time = time();
  my @now = gmtime($time);
  my $cutoff_exp = sprintf("%04d%02d", $now[5]+1900, $now[4]+1);

  # set warning exp date
  my @notify = gmtime($time + 2678400); # 31 days in future
  my $notify_exp = sprintf("%04d%02d", $notify[5]+1900, $notify[4]+1);

  # check the expiration date, return status
  if ($check_exp < $cutoff_exp) {
    return ("expired", "Card Expired");
  }
  elsif ($check_exp >= $cutoff_exp) {
    if ($check_exp <= $notify_exp) {
      return ("warn", "Card Expiration Approaching");
    }
    else {
      return ("valid", "Card Expiration Valid");
    }
  }
  else {
    return ("problem", "Invalid Expiration Date");
  }
}

sub list_bill_profile_form {

  my %profiles = &list_bill_profile_hash("", "");

  # draw table of customer's profiles.
  # user can select from the list the profile they want to pull up

  my $data = "";
  my $cnt = 0;

  $data .= "<table border=0 cellspacing=0 cellpadding=5 width=\"100%\">\n";
  $data .= "  <tr>\n";
  $data .= "    <td colspan=2><h1><a href=\"$billpay_editutils::path_index\">$billpay_language::lang_titles{'service_title'}</a> / $billpay_language::lang_titles{'service_subtitle_billoptions'}</h1></td>\n";
  $data .= "  </tr>\n"; 

  $data .= "  <tr>\n";
  $data .= "    <td bgcolor=\"#f4f4f4\" valign=top><p><b>$billpay_language::lang_titles{'menu_profiles'}</b></p></td>\n";
  $data .= "    <td><form method=post action=\"$billpay_editutils::path_edit\">\n";
  $data .= "<input type=hidden name=\"function\" value=\"edit_bill_profile_form\">\n";
  $data .= "<table border=0 cellspacing=0 cellpadding=2 width=500>\n";
  $data .= "  <tr>\n";
  $data .= "    <td valign=top colspan=5><p>$billpay_language::lang_titles{'statement_select_editprofile'}</p></td>\n";
  $data .= "  </tr>\n";

  foreach my $key (sort keys %profiles) {
    $data .= "  <tr>\n";
    $data .= "    <td><input type=radio name=\"profileid\" value=\"$key\"";
    if ($cnt == 0) { $data .= " checked"; }
    $data .= "></td>\n";
    $data .= "    <td>$profiles{$key}{'type'}</td>\n";
    $data .= "    <td>&nbsp; $profiles{$key}{'cardnumber'}</td>\n";
    $data .= "    <td>&nbsp; $profiles{$key}{'exp'}</td>";
    if (($profiles{$key}{'accttype'} !~ /^(checking|savings)$/i) && ($profiles{$key}{'exp_status'} ne "valid")) {
      $data .= "    <td>&nbsp; <b>$profiles{$key}{'exp_reason'}</b></td>";
    }
    else {
      $data .= "    <td>&nbsp; </td>\n";
    }
    $data .= "  </tr>\n";
    $cnt = $cnt + 1;
  }

  if ($cnt >= 1) {
    $data .= "  <tr>\n";
    $data .= "    <td colspan=5><input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_edit_billing'}\"></td></form>\n";
    $data .= "  </tr>\n";
  }
  else {
    $data .= "  <tr>\n";
    $data .= "    <td><p>$billpay_language::lang_titles{'statement_nobillprofiles'}\n";
    $data .= "<br>$billpay_language::lang_titles{'statement_nobillprofiles2'}</p></td></form>\n";
    $data .= "  </tr>\n";

    $data .= "  <tr>\n";
    $data .= "    <td align=left><form method=post action=\"$billpay_editutils::path_edit\">\n";
    $data .= "      <input type=hidden name=\"function\" value=\"add_new_bill_profile_form\">\n";
    $data .= "      <input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_add_billing'}\">\n";
    $data .= "    </td></form>\n";
    $data .= "  </tr>\n";
  }
  $data .= "</table></td>\n";

  $data .= "  </tr>\n";
  $data .= "</table>\n";

  return $data;
}

sub delete_bill_profile_form {

  my %profiles = &list_bill_profile_hash("", "");

  # draw table of customer's profiles.
  # user can select from the list the profile they want to delete

  my $data = "";
  my $cnt = 0;

  $data .= "<table border=0 cellspacing=0 cellpadding=5 width=\"100%\">\n";
  $data .= "  <tr>\n";
  $data .= "    <td colspan=2><h1><a href=\"$billpay_editutils::path_index\">$billpay_language::lang_titles{'service_title'}</a> / $billpay_language::lang_titles{'service_subtitle_billoptions'}</h1></td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <td bgcolor=\"#f4f4f4\" valign=top><p><b>$billpay_language::lang_titles{'menu_profiles'}</b></p></td>\n";
  $data .= "    <td><form method=post action=\"$billpay_editutils::path_edit\">\n";
  $data .= "<input type=hidden name=\"function\" value=\"delete_bill_profile\">\n";
  $data .= "<table border=0 cellspacing=0 cellpadding=2 width=500>\n";
  $data .= "  <tr>\n";
  $data .= "    <td valign=top colspan=5><p>$billpay_language::lang_titles{'statement_select_delprofile'}</p></td>\n";
  $data .= "  </tr>\n";

  foreach my $key (sort keys %profiles) {
    $data .= "  <tr>\n";
    $data .= "    <td><input type=radio name=\"profileid\" value=\"$key\"";
    if ($cnt == 0) { $data .= " checked"; }
    $data .= "></td>\n";
    $data .= "    <td>$profiles{$key}{'type'}</td>\n";
    $data .= "    <td>&nbsp; $profiles{$key}{'cardnumber'}</td>\n";
    $data .= "    <td>&nbsp; $profiles{$key}{'exp'}</td>";
    if (($profiles{$key}{'accttype'} !~ /^(checking|savings)$/i) && ($profiles{$key}{'exp_status'} ne "valid")) {
      $data .= "    <td>&nbsp; <b>$profiles{$key}{'exp_reason'}</b></td>";
    }
    else {
      $data .= "    <td>&nbsp; </td>\n";
    }
    $data .= "  </tr>\n";
    $cnt = $cnt + 1;
  }

  $data .= "  <tr>\n";
  $data .= "    <td colspan=5><input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_delete_billing'}\"></td></form>\n";
  $data .= "  </tr>\n";
  $data .= "</table></td>\n";

  $data .= "  </tr>\n";
  $data .= "</table>\n";

  return $data;
}

sub delete_bill_profile {
  my %query = @_;

  my $data;

  if ($ENV{'REMOTE_USER'} !~ /^($billpay_editutils::reject_email)$/) {
    # check for profile existance
    my $sth = $billpay_editutils::dbh->prepare(q{
        DELETE FROM billing2
        WHERE username=?
        AND profileid=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth->execute("$ENV{'REMOTE_USER'}", "$query{'profileid'}") or die "Cannot execute: $DBI::errstr";
    $sth->finish;

    # delete any related autopay profiles, which use the same profileid 
    my $sth2 = $billpay_editutils::dbh->prepare(q{
        DELETE FROM autopay2
        WHERE username=?
        AND profileid=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2->execute("$ENV{'REMOTE_USER'}", "$query{'profileid'}") or die "Cannot execute: $DBI::errstr";
    $sth2->finish;

    &record_history("$ENV{'REMOTE_USER'}", "$query{'profileid'}", "delete_bill", "Billing Profile Deleted");
  }

  $data .= "<p>$billpay_language::lang_titles{'statement_billing_deleted'}\n";
  $data .= "<br>$billpay_language::lang_titles{'warn_billing_deleted'}</p>\n";

  $data .= "<p><a href=\"$billpay_editutils::path_index\?function=show_bill_profile_menu\">$billpay_language::lang_titles{'link_billprofmenu'}</a></p>\n";

  return $data;
}

sub get_cust_profile_info {
  my %query;

  my $sth = $billpay_editutils::dbh->prepare(q{
      SELECT *
      FROM customer2
      WHERE username=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth->execute("$ENV{'REMOTE_USER'}") or die "Cannot execute: $DBI::errstr";
  my $results = $sth->fetchrow_hashref();
  $sth->finish;

  # copy the name/value pairs in the results hash reference data to %query hash for later usage
  foreach my $key (keys %$results) {
    $query{"$key"} = $results->{$key};
  }

  return %query;
}

sub get_optout_info {
  my %data;

  my $sth = $billpay_editutils::dbh->prepare(q{
      SELECT *
      FROM optout
      WHERE username=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth->execute("$ENV{'REMOTE_USER'}") or die "Cannot execute: $DBI::errstr";
  while (my $results = $sth->fetchrow_hashref()) {
    my $type = $results->{'optout_type'};
    my $value = $results->{'optout_value'};
    $data{"optout_$type"} = $value;
  }
  $sth->finish;

  return %data;
}

sub get_bill_profile_info {
  my ($profileid) = @_;

  my %query;

  my $sth = $billpay_editutils::dbh->prepare(q{
      SELECT *
      FROM billing2
      WHERE username=?
      AND profileid=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth->execute("$ENV{'REMOTE_USER'}", "$profileid") or die "Cannot execute: $DBI::errstr";
  my $results = $sth->fetchrow_hashref();
  $sth->finish;

  # copy the name/value pairs in the results hash reference data to %query hash for later usage
  foreach my $key (keys %$results) {
    $query{"$key"} = $results->{$key};
  }

  return %query;
}

sub list_bills_form {
  my %query = @_;

  # draw table of invoiced bills.
  # user can select from the list of the bill they want to pull up

  my @now = gmtime(time);
  my $today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

  my $data = "";
  $data .= "<table border=0 cellspacing=0 cellpadding=5 width=\"100%\">\n";
  $data .= "  <tr>\n";
  $data .= "    <td colspan=2><h1><a href=\"$billpay_editutils::path_index\">$billpay_language::lang_titles{'service_title'}</a> / $billpay_language::lang_titles{'service_subtitle_billlistings'}</h1></td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <td colspan=2 valign=top><p>$billpay_language::lang_titles{'statement_select_invoiceno'}</p></td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <td bgcolor=\"#f4f4f4\" valign=top><p><b>$billpay_language::lang_titles{'menu_bills'}</b></p></td>\n";
  $data .= "    <td>\n";

  $data .= "<table border=0 cellspacing=0 cellpadding=2>\n";
  #$data .= "  <tr>\n";
  #$data .= "    <td valign=top><p>$billpay_language::lang_titles{'statement_select_editprofile'}</p></td>\n";
  #$data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <th valign=top><p>$billpay_language::lang_titles{'column_merchant'}</p></th>\n";
  #$data .= "    <th valign=top><p>$billpay_language::lang_titles{'column_username'}</p></th>\n";
  $data .= "    <th valign=top><p>$billpay_language::lang_titles{'column_invoice_no'}</p></th>\n";
  $data .= "    <th valign=top><p>$billpay_language::lang_titles{'column_enterdate'}</p></th>\n";
  $data .= "    <th valign=top><p>$billpay_language::lang_titles{'column_expiredate'}</p></th>\n";
  $data .= "    <th valign=top><p>$billpay_language::lang_titles{'column_account_no'}</p></th>\n";
  $data .= "    <th valign=top><p>$billpay_language::lang_titles{'column_amount'}</p></th>\n";
  #$data .= "    <th valign=top><p>$billpay_language::lang_titles{'column_tax'}</p></th>\n";
  #$data .= "    <th valign=top><p>$billpay_language::lang_titles{'column_shipping'}</p></th>\n";
  #$data .= "    <th valign=top><p>$billpay_language::lang_titles{'column_handling'}</p></th>\n";
  #$data .= "    <th valign=top><p>$billpay_language::lang_titles{'column_discount'}</p></th>\n";
  #$data .= "    <th valign=top><p>$billpay_language::lang_titles{'column_balance'}</p></th>\n";
  #$data .= "    <th valign=top><p>$billpay_language::lang_titles{'column_installment'}</p></th>\n";
  #$data .= "    <th valign=top><p>$billpay_language::lang_titles{'column_remnant'}</p></th>\n";
  $data .= "    <th valign=top><p>$billpay_language::lang_titles{'column_status'}</p></th>\n";
  $data .= "  </tr>\n";

  my ($db_merchant, $db_username, $db_invoice_no, $db_enter_date, $db_expire_date, $db_account_no, $db_amount, $db_status, $db_merch_company, $db_merch_status, $db_tax, $db_shipping, $db_handling, $db_discount, $db_balance, $db_monthly, $db_percent, $db_remnant);

  my $count = 0;

  if ($query{'status'} eq "closed") {
    $query{'status'} = "closed|merged";
  }

  my $sth = $billpay_editutils::dbh->prepare(q{
      SELECT merchant, username, invoice_no, enter_date, expire_date, account_no, amount, status, tax, shipping, handling, discount, balance, monthly, percent, remnant
      FROM bills2
      WHERE username=?
      AMD status RLIKE ?
      order by expire_date
    }) or die "Cannot do: $DBI::errstr";
  $sth->execute("$ENV{'REMOTE_USER'}", "^($query{'status'})\$") or die "Cannot execute: $DBI::errstr";
  my $rv = $sth->bind_columns(undef,\($db_merchant, $db_username, $db_invoice_no, $db_enter_date, $db_expire_date, $db_account_no, $db_amount, $db_status, $db_tax, $db_shipping, $db_handling, $db_discount, $db_balance, $db_monthly, $db_percent, $db_remnant));
  while($sth->fetch) {
    if (($db_username eq "$ENV{'REMOTE_USER'}") && ($db_merchant ne "")) {

      if ($query{'status'} eq "open") {
        if ($query{'type'} eq "") {
          # show only open, payable bills
          if ($db_expire_date < $today) {
            # skip listing this bill, since it expired.
            next;
          }
        }
        elsif ($query{'type'} eq "expired") {
          # show only expired, non-payable bills
          if ($db_expire_date >= $today) {
            # skip listing this bill, since it is still open & can be paid
            next;
          }
          else {
            # change the status on screen, to show as expired 
            $db_status = "expired";
          }
        }
      }

      # get merchant's company name & account status
      my $dbh = &miscutils::dbhconnect("pnpmisc");
      my $sth2 = $dbh->prepare(q{
          SELECT company, status
          FROM customers 
          WHERE username=?
        }) or die "Cannot prepare: $DBI::errstr";
      $sth2->execute("$db_merchant") or die "Cannot execute: $DBI::errstr";
      ($db_merch_company, $db_merch_status) = $sth2->fetchrow;
      $sth2->finish;
      $dbh->disconnect;

      if ($db_merch_status !~ /(live|debug|test)/i) {
        # skip entries where account is not active.
        next;
      }

      $db_amount = sprintf("%0.02f", $db_amount);
      $db_tax = sprintf("%0.02f", $db_tax);
      $db_shipping = sprintf("%0.02f", $db_shipping);
      $db_handling = sprintf("%0.02f", $db_handling);
      $db_discount = sprintf("%0.02f", $db_discount);

      if ($db_balance ne "") { $db_balance = sprintf("%0.02f", $db_balance); }
      if ($db_percent > 0) { $db_monthly = sprintf("%f", $db_percent); }
      if ($db_monthly > 0) { $db_monthly = sprintf("%0.02f", $db_monthly); }
      if ($db_remnant > 0) { $db_remnant = sprintf("%0.02f", $db_remnant); }

      $db_enter_date = sprintf("%02d\/%02d\/%04d", substr($db_enter_date,4,2), substr($db_enter_date,6,2), substr($db_enter_date,0,4));
      $db_expire_date = sprintf("%02d\/%02d\/%04d", substr($db_expire_date,4,2), substr($db_expire_date,6,2), substr($db_expire_date,0,4));
 
      $data .= "  <tr>\n";
      $data .= "    <td valign=top><p>$db_merch_company</p></td>\n";
      #$data .= "    <td valign=top><p>$db_username</p></td>\n";
      $data .= "    <td valign=top><p><a href=\"$billpay_editutils::path_edit\?function=view_bill_details_form\&type=$query{'type'}\&invoice_no=$db_invoice_no\&merchant=$db_merchant\">$db_invoice_no</a></p></td>\n";
      $data .= "    <td valign=top><p>$db_enter_date</p></td>\n";
      $data .= "    <td valign=top><p>$db_expire_date</p></td>\n";
      $data .= "    <td valign=top><p>$db_account_no</p></td>\n";
      $data .= "    <td valign=top align=right><p>$db_amount</p></td>\n";
      #$data .= "    <td valign=top align=right><p>$db_tax</p></td>\n";
      #$data .= "    <td valign=top align=right><p>$db_shipping</p></td>\n";
      #$data .= "    <td valign=top align=right><p>$db_handling</p></td>\n";
      #$data .= "    <td valign=top align=right><p>$db_discount</p></td>\n";
      #$data .= "    <td valign=top align=right><p>$db_balance</p></td>\n";
      #$data .= "    <td valign-top align=right><p>$db_percent</p></td>\n";
      #$data .= "    <td valign=top align=right><p>$db_monthly</p></td>\n";
      #$data .= "    <td valign=top align=right><p>$db_remnant</p></td>\n";
      $data .= "    <td valign=top><p>$db_status</p></td>\n";
      $data .= "  </tr>\n";

      $count = $count + 1;
    }
  }
  $sth->finish;

  if ($count == 0) {
    $data .= "  <tr>\n";
    $data .= "    <td colspan=7><b>$billpay_language::lang_titles{'statement_notfound_query'}</b></td>\n";
    $data .= "  </tr>\n";
  }
  $data .= "</table></td>\n";

  $data .= "  </tr>\n";
  $data .= "</table>\n";

  return $data;
}

sub view_bill_details_form {
  my %query = @_;

  if ($query{'comments'} ne "") {
    $query{'comments'} =~ s/^\s+//g; # strip leading whitespace
    $query{'comments'} =~ s/\s+$//g; # strip tailing whitespace
  }

  my $data;

  my @now = gmtime(time);
  my $today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

  $data .= "<table border=0 cellspacing=0 cellpadding=5 width=\"100%\">\n";
  $data .= "  <tr>\n";
  $data .= "    <td colspan=2><h1><a href=\"$billpay_editutils::path_index\">$billpay_language::lang_titles{'service_title'}</a> / $billpay_language::lang_titles{'service_subtitle_billdetails'}</h1></td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <td bgcolor=\"#f4f4f4\" valign=top width=60><p> &nbsp; </p></td>\n";
  $data .= "    <td>";
  $data .= "<table border=0 cellspacing=0 cellpadding=2>\n";

  my $sth = $billpay_editutils::dbh->prepare(q{
      SELECT * 
      FROM bills2
      WHERE username=?
      AND invoice_no=?
      AND merchant=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth->execute("$ENV{'REMOTE_USER'}", "$query{'invoice_no'}", "$query{'merchant'}") or die "Cannot execute: $DBI::errstr";
  my $invoice = $sth->fetchrow_hashref();
  $sth->finish;

  my %invoice;
  foreach my $key (keys %$invoice) {
    $invoice{"$key"} = $invoice->{$key};
  }

  # if ok, see if we need to display client contact info
  my $sth2 = $billpay_editutils::dbh->prepare(q{
      SELECT *
      FROM client_contact
      WHERE username=?
      AND merchant=?
    }) or die "Cannot prepare: $DBI::errstr";
  my $rv2 = $sth2->execute("$invoice{'username'}", "$invoice{'merchant'}") or die "Cannot execute: $DBI::errstr";
  my $client = $sth2->fetchrow_hashref();
  $sth2->finish;

  my %client;
  foreach my $key (keys %$client) {
    $client{"$key"} = $client->{$key};
  }

  # get merchant's company name & account status
  my $dbh_pnpmisc = &miscutils::dbhconnect("pnpmisc");
  my $sth3 = $dbh_pnpmisc->prepare(q{
      SELECT company, status, chkprocessor
      FROM customers
      WHERE username=?
    }) or die "Cannot prepare: $DBI::errstr";
  my $rv3 = $sth3->execute("$invoice{'merchant'}") or die "Cannot execute: $DBI::errstr";
  my $merch = $sth3->fetchrow_hashref();
  $sth3->finish;
  $dbh_pnpmisc->disconnect;

  my $accountFeatures = new PlugNPay::Features("$invoice{'merchant'}",'general');
  my $merch_features = $accountFeatures->getFeatureString();

  my %merch;
  foreach my $key (keys %$merch) {
    $merch{"$key"} = $merch->{$key};
  }

  ## parse list into hash
  if ($merch_features =~ /(.*)=(.*)/) {
    my @array = split(/\,/,$merch_features);
    foreach my $entry (@array) {
      my ($name, $value) = split(/\=/, $entry);
      $billpay_editutils::feature_list{"$name"} = "$value";
    }
  }

  #if ($merch{'status'} !~ /(live|debug|test)/i) {
  #  # skip entries where account is not active.
  #  next;
  #}

  $invoice{'amount'} = sprintf("%0.02f", $invoice{'amount'});
  $invoice{'tax'} = sprintf("%0.02f", $invoice{'tax'});
  $invoice{'shipping'} = sprintf("%0.02f", $invoice{'shipping'});
  $invoice{'handling'} = sprintf("%0.02f", $invoice{'handling'});
  $invoice{'discount'} = sprintf("%0.02f", $invoice{'discount'});

  if ($invoice{'balance'} ne "") { $invoice{'balance'} = sprintf("%0.02f", $invoice{'balance'}); }
  if ($invoice{'percent'} > 0) { $invoice{'percent'} = sprintf("%f", $invoice{'percent'}); }
  if ($invoice{'monthly'} > 0) { $invoice{'monthly'} = sprintf("%0.02f", $invoice{'monthly'}); }
  if ($invoice{'remnant'} > 0) { $invoice{'remnant'} = sprintf("%0.02f", $invoice{'remnant'}); }

  ($invoice{'installment'}, $invoice{'installment_type'}) = &calc_payment_default($invoice{'amount'}, $invoice{'balance'}, $invoice{'billcycle'}, $invoice{'monthly'}, $invoice{'percent'}, $invoice{'remnant'});

  $invoice{'installment'} = sprintf("%0.02f", $invoice{'installment'});

  my $enter = sprintf("%02d\/%02d\/%04d", substr($invoice{'enter_date'},4,2), substr($invoice{'enter_date'},6,2), substr($invoice{'enter_date'},0,4));
  my $expire = sprintf("%02d\/%02d\/%04d", substr($invoice{'expire_date'},4,2), substr($invoice{'expire_date'},6,2), substr($invoice{'expire_date'},0,4));

  if (($invoice{'status'} eq "open") && ($invoice{'expire_date'} < $today)) {
    # change the status on screen, to show as expired
    $invoice{'status'} = "expired";
  }

  # setup easycart form hidden fields
  my %easycart_form_data = (
    "username", "$invoice{'merchant'}",
    "function", "add",
    "currency_symbol", "",
    "ec_version", "2.0"
  );

  ## pre-generate customer section
  my $data_cust = "";
  if (($client{'clientname'} ne "") || ($client{'clientcompany'} ne "")) {
    $data_cust .= "<fieldset style=\"width: 97%; height: 95%; position: relative; border: 1px solid; margin: none; padding: 0px 5px 5px; background: #eeeeee; -moz-border-radius: 10px;\">\n";
    $data_cust .= "<legend style=\"padding: 0px 8px;\"><b>$billpay_language::lang_titles{'legend_customer'}</b></legend>\n";
    $data_cust .= "<p>";
    if ($client{'clientname'} ne "") {
      $data_cust .= "$client{'clientname'}<br>\n";
    }
    if ($client{'clientcompany'} ne "") {
      $data_cust .= "$client{'clientcompany'}<br>\n";
    }
    if ($client{'clientaddr1'} ne "") {
      $data_cust .= "$client{'clientaddr1'}<br>\n";
    }
    if ($client{'clientaddr2'} ne "") {
      $data_cust .= "$client{'clientaddr2'}<br>\n";
    }
    if ($client{'clientcity'} ne "") {
      $data_cust .= "$client{'clientcity'} \n";
    }
    if ($client{'clientstate'} ne "") {
      $data_cust .= "$client{'clientstate'} \n";
    }
    if ($client{'clientzip'} ne "") {
      $data_cust .= "$client{'clientzip'} \n";
    }
    if ($client{'clientcountry'} ne "") {
      $data_cust .= "$client{'clientcountry'}\n";
    }
    if ($client{'clientphone'} ne "") {
      $data_cust .= "<br>$billpay_language::lang_titles{'phone'} $client{'clientphone'}\n";
    }
    if ($client{'clientfax'} ne "") {
      $data_cust .= "<br>$billpay_language::lang_titles{'fax'} $client{'clientfax'}\n";
    }
    $data_cust .= "</p>\n";
    $data_cust .= "</fieldset>\n";
  }

  ## pre-generate shipping section
  my $data_ship = "";
  if (($invoice{'shipname'} ne "") || ($invoice{'shipcompany'} ne "")) {
    $data_ship .= "<fieldset style=\"width: 97%; height: 95%; position: relative; border: 1px solid; margin: none; padding: 0px 5px 5px; background: #eeeeee; -moz-border-radius: 10px;\">\n";
    $data_ship .= "<legend style=\"padding: 0px 8px;\"><b>$billpay_language::lang_titles{'legend_shipping'}</b></legend>\n";
    $data_ship .= "<p>";
    if ($invoice{'shipname'} ne "") {
      $data_ship .= "$invoice{'shipname'}<br>\n";
    }
    if ($invoice{'shipcompany'} ne "") {
      $data_ship .= "$invoice{'shipcompany'}<br>\n";
    }
    if ($invoice{'shipaddr1'} ne "") {
      $data_ship .= "$invoice{'shipaddr1'}<br>\n";
    }
    if ($invoice{'shipaddr2'} ne "") {
      $data_ship .= "$invoice{'shipaddr2'}<br>\n";
    }
    if ($invoice{'shipcity'} ne "") {
      $data_ship .= "$invoice{'shipcity'} \n";
    }
    if ($invoice{'shipstate'} ne "") {
      $data_ship .= "$invoice{'shipstate'} \n";
    }
    if ($invoice{'shipzip'} ne "") {
      $data_ship .= "$invoice{'shipzip'} \n";
    }
    if ($invoice{'shipcountry'} ne "") {
      $data_ship .= "$invoice{'shipcountry'}\n";
    }
    if ($invoice{'shipphone'} ne "") {
      $data_ship .= "<br>$billpay_language::lang_titles{'phone'} $invoice{'shipphone'} \n";
    }
    if ($invoice{'shipfax'} ne "") {
      $data_ship .= "<br>$billpay_language::lang_titles{'fax'} $invoice{'shipfax'} \n";
    }
    $data_ship .= "</p>\n";
    $data_ship .= "</fieldset>\n";
  }

  ## pre-generate invoice info
  my $data_info = "";
  $data_info .= "<fieldset style=\"width: 97%; height: 95%; position: relative; border: 1px solid; margin: none; padding: 0px 5px 5px; background: #eeeeee; -moz-border-radius: 10px;\">\n";
  $data_info .= "<legend style=\"padding: 0px 8px;\"><b>$billpay_language::lang_titles{'legend_invoiceinfo'}</b></legend>\n";
  $data_info .= "<p>$billpay_language::lang_titles{'invoice_no'} $invoice{'invoice_no'}\n";
  if ($invoice{'account_no'} =~ /\w/) {
    $data_info .= "<br>$billpay_language::lang_titles{'account_no'} $invoice{'account_no'}\n";
  }
  $data_info .= "<br>$billpay_language::lang_titles{'enterdate'} $enter\n";
  $data_info .= "<br>$billpay_language::lang_titles{'expiredate'} $expire\n";
  $data_info .= "<br>$billpay_language::lang_titles{'status'} $invoice{'status'}\n";
  if ($invoice{'orderid'} =~ /\w/) {
    $data_info .= "<br>$billpay_language::lang_titles{'orderid'} $invoice{'orderid'}\n";
  }
  if ($billpay_editutils::feature_list{'billpay_showalias'} eq "yes") {
    $data_info .= "<br>&billpay_language::lang_titles{'alias'} $invoice{'alias'}\n";
  }
  $data_info .= "</p>\n";
  $data_info .= "</fieldset>\n";

  ## start generating the actual invoice's HTML 
  $data .= "<b>$merch{'company'}</b>\n";

  $data .= $billpay_language::template{'body_merchcontact'};

  $data .= "<table width=700>\n";
  $data .= "  <tr>\n";
  $data .= "    <td colspan=4><hr width=\"100%\"></td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  if (($data_cust ne "") && ($data_ship eq "")) {
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\">$data_cust</td>\n";
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\">$data_info</td>\n";
  }
  elsif (($data_cust eq "") && ($data_ship ne "")) {
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\">$data_ship</td>\n";
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\">$data_info</td>\n";
  }
  else {
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\"> &nbsp; </td>\n";
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\">$data_info</td>\n";
  }
  $data .= "  </tr>\n";

  if (($data_cust ne "") && ($data_ship ne "")) {
    $data .= "  <tr>\n";
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\">$data_cust</td>\n";
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\">$data_ship</td>\n";
    $data .= "  </tr>\n";
  }

  $data .= "  <tr>\n";
  $data .= "    <td colspan=4><hr width=\"100%\"></td>\n";
  $data .= "  </tr>\n";
  $data .= "</table>\n";

  my $subtotal = 0;
  my $totalwgt = 0;

  my $i = 0;
  my ($db_item, $db_cost, $db_qty, $db_descr, $db_weight, $db_descra, $db_descrb, $db_descrc);
  my $sth4 = $billpay_editutils::dbh->prepare(q{
      SELECT item, cost, qty, descr, weight, descra, descrb, descrc
      FROM billdetails2
      WHERE username=?
      AND invoice_no=?
      AND merchant=?
      ORDER BY item
    }) or die "Cannot do: $DBI::errstr";
  my $rc = $sth4->execute("$invoice{'username'}", "$invoice{'invoice_no'}", "$invoice{'merchant'}") or die "Cannot execute: $DBI::errstr";

  if ($rc >= 1) {
    $data .= "<table width=700 class=\"invoice\">\n";
    $data .= "  <tr>\n";
    $data .= "    <td colspan=4 bgcolor=\"#f4f4f4\"><p><b>$billpay_language::lang_titles{'section_productdetails'}</b></p></td>\n";
    $data .= "  </tr>\n";

    $data .= "  <tr>\n";
    if ($billpay_editutils::feature_list{'billpay_showcols'} =~ /item/) {
      $data .= "    <th valign=top align=left width=\"8%\"><p>$billpay_language::lang_titles{'column_item'}</p></th>\n";
    }
    $data .= "    <th valign=top align=left width=\"\"><p>$billpay_language::lang_titles{'column_descr'}</p></th>\n";
    $data .= "    <th valign=top align=left width=\"8%\"><p>$billpay_language::lang_titles{'column_qty'}</p></th>\n";
    $data .= "    <th valign=top align=left width=\"14%\"><p>$billpay_language::lang_titles{'column_cost'}</p></th>\n";

    if (($billpay_editutils::feature_list{'billpay_extracols'} =~ /weight/) && ($billpay_editutils::feature_list{'billpay_showcols'} =~ /weight/)) {
      $data .= "    <th valign=top align=left><p>$billpay_language::lang_titles{'column_weight'}</p></th>\n";
    }
    if (($billpay_editutils::feature_list{'billpay_extracols'} =~ /descra/) && ($billpay_editutils::feature_list{'billpay_showcols'} =~ /descra/)) {
      $data .= "    <th valign=top align=left><p>$billpay_language::lang_titles{'column_descra'}</p></th>\n";
    }
    if (($billpay_editutils::feature_list{'billpay_extracols'} =~ /descrb/) && ($billpay_editutils::feature_list{'billpay_showcols'} =~ /descrb/)) {
      $data .= "    <th valign=top align=left><p>$billpay_language::lang_titles{'column_descrb'}</p></th>\n";
    }
    if (($billpay_editutils::feature_list{'billpay_extracols'} =~ /descrc/) && ($billpay_editutils::feature_list{'billpay_showcols'} =~ /descrc/)){
      $data .= "    <th valign=top align=left><p>$billpay_language::lang_titles{'column_descrc'}</p></th>\n";
    }
    $data .= "  </tr>\n";

    my $rv = $sth4->bind_columns(undef,\($db_item, $db_cost, $db_qty, $db_descr, $db_weight, $db_descra, $db_descrb, $db_descrc));
    while($sth4->fetch) {
      $db_cost = sprintf("%0.02f", $db_cost);

      ## add itemized product to form
      $data .= "  <tr>\n";
      if ($billpay_editutils::feature_list{'billpay_showcols'} =~ /item/) {
        $data .= "    <td valign=top><p>$db_item</p></td>\n";
      }
      $data .= "    <td valign=top><p>$db_descr</p></td>\n";
      $data .= "    <td valign=top><p>$db_qty</p></td>\n";
      $data .= "    <td valign=top align=right><p>$db_cost</p></td>\n";

      if (($billpay_editutils::feature_list{'billpay_extracols'} =~ /weight/) && ($billpay_editutils::feature_list{'billpay_showcols'} =~ /weight/)) {
        $data .= "    <td valign=top><p>$db_weight</p></td>\n";
      }
      if (($billpay_editutils::feature_list{'billpay_extracols'} =~ /descra/) && ($billpay_editutils::feature_list{'billpay_showcols'} =~ /descra/)) {
        $data .= "    <td valign=top><p>$db_descra</p></td>\n";
      }
      if (($billpay_editutils::feature_list{'billpay_extracols'} =~ /descrb/) && ($billpay_editutils::feature_list{'billpay_showcols'} =~ /descrb/)) {
        $data .= "    <td valign=top><p>$db_descrb</p></td>\n";
      }
      if (($billpay_editutils::feature_list{'billpay_extracols'} =~ /descrc/) && ($billpay_editutils::feature_list{'billpay_showcols'} =~ /descrc/)) {
        $data .= "    <td valign=top><p>$db_descrc</p></td>\n";
      }
      $data .= "  </tr>\n";

      $i++;
      $subtotal += ($db_cost * $db_qty);
      $totalwgt += ($db_weight * $db_qty);

      ## add itemized product to easycart form data
      $easycart_form_data{"item$i"} = $db_item;
      if ($db_descr =~ /\, /) {
        my @temp_item = split(/\, /, $db_descr);
        if (scalar(@temp_item) >= 4) {
          $easycart_form_data{"descra$i"} = $temp_item[$#temp_item-2];
          $easycart_form_data{"descrb$i"} = $temp_item[$#temp_item-1];
          $easycart_form_data{"descrc$i"} = $temp_item[$#temp_item];
        }
        if (scalar(@temp_item) == 3) {
          $easycart_form_data{"descra$i"} = $temp_item[$#temp_item-1];
          $easycart_form_data{"descrb$i"} = $temp_item[$#temp_item];
        }
        if (scalar(@temp_item) == 2) {
          $easycart_form_data{"descra$i"} = $temp_item[$#temp_item];
        }
      }
      $easycart_form_data{"quantity$i"} = $db_qty;
    }

    $data .= "</table>\n";
    if ($billpay_editutils::feature_list{'billpay_totalwgt'} == 1) {
      $totalwgt = sprintf("%s", $totalwgt);
      $data .= "<div align=left><p><b>$billpay_language::lang_titles{'totalwgt'}</b> $totalwgt lbs.</p></div>\n";
    }
  }
  $sth4->finish;

  $data .= "<table width=700>\n";
  if ($rc >= 1) {
    $data .= "  <tr>\n";
    $data .= "    <td colspan=4><hr width=\"100%\"></td>\n";
    $data .= "  </tr>\n";
  }

  $data .= "  <tr>\n";
  $data .= "    <td width=\"77%\" valign=top><fieldset style=\"width: 97%; height: 95%; position: relative; border: 1px solid; margin: none; padding: 0px 5px 5px; background: #eeeeee; -moz-border-radius: 10px;\">\n";
  $data .= "<legend style=\"padding: 0px 8px;\"><b>$billpay_language::lang_titles{'legend_paymentdetails'}</b></legend>\n";
  $data .= "<p>$billpay_language::lang_titles{'statement_accepts'}\n";
  $data .= "<br><b>$billpay_editutils::feature_list{'billpay_cardsallowed'}</b>\n";
  $data .= "<br>\n";

  if ($invoice{'balance'} != 0) {
    $data .= "<p><table border=1 class=\"invoice\">\n";
    $data .= "  <tr>\n";
    $data .= "    <td colspan=2><p><b>$billpay_language::lang_titles{'section_balance_amount'}</b></p></td>\n";
    $data .= "  </tr>\n";

    $data .= "  <tr>\n";
    $data .= "    <th align=right><p>$billpay_language::lang_titles{'balance'}</p></th>\n";
    $data .= "    <td align=right><p>$invoice{'balance'}</p></td>\n";
    $data .= "  </tr>\n";

    if ((($invoice{'percent'} > 0) || ($invoice{'monthly'} > 0)) && ($invoice{'billcycle'} > 0) && ($invoice{'balance'} > 0)) {
      if ($invoice{'percent'} > 0) {
        $data .= "  <tr>\n";
        $data .= "    <th align=right><p>$billpay_language::lang_titles{'percentage'}</p></th>\n";
        $data .= "    <td align=right><p>$invoice{'percent'}\%</p></td>\n";
        $data .= "  </tr>\n";

        if ($invoice{'monthly'} > 0) {
          $data .= "  <tr>\n";
          $data .= "    <th align=right><p>$billpay_language::lang_titles{'installment_min'}</p></th>\n";
          $data .= "    <td align=right><p>$invoice{'monthly'}</p></td>\n";
          $data .= "  </tr>\n";
        }
      }
      else {
        $data .= "  <tr>\n";
        $data .= "    <th align=right><p>$billpay_language::lang_titles{'installment_fee'}</p></th>\n";
        $data .= "    <td align=right><p>$invoice{'monthly'}</p></td>\n";
        $data .= "  </tr>\n";
      }

      if (($invoice{'remnant'} > 0) && ($invoice{'installment'} > $invoice{'remnant'})) {
        $invoice{'installment'} = $invoice{'remnant'};
      }

      $data .= "  <tr>\n";
      if ($invoice{'remnant'} > 0) {
        $data .= "    <th align=right><p>$billpay_language::lang_titles{'remnant_due'}</p></th>\n";
      }
      else {
        $data .= "    <th align=right><p>$billpay_language::lang_titles{'installment_due'}</p></th>\n";
      }
      $data .= "    <td align=right><p>$invoice{'installment'}</p></td>\n";
      $data .= "  </tr>\n";
    }

    #$data .= "  <tr>\n";
    #$data .= "    <th align=right><p>$billpay_language::lang_titles{'billcycle'}</p></th>\n";
    #$data .= "    <td align=right><p>$invoice{'billcycle'} Month(s)</p></td>\n";
    #$data .= "  </tr>\n";

    if ($invoice{'lastbilled'} ne "") {
      my $lastbilled = sprintf("%02d\/%02d\/%04d", substr($invoice{'lastbilled'},4,2), substr($invoice{'lastbilled'},6,2), substr($invoice{'lastbilled'},0,4));
      $data .= "  <tr>\n";
      $data .= "    <th align=right><p>$billpay_language::lang_titles{'lastbilled'}</p></th>\n";
      $data .= "    <td align=right><p>$lastbilled</p></td>\n";
      $data .= "  </tr>\n";
    }

    #if ($invoice{'lastattempted'} ne "") {
    #  my $lastattempted = sprintf("%02d\/%02d\/%04d", substr($invoice{'lastattempted'},4,2), substr($invoice{'lastattempted'},6,2), substr($invoice{'lastattempted'},0,4));
    #  $data .= "  <tr>\n";
    #  $data .= "    <th align=right><p>$billpay_language::lang_titles{'lastattempted'}</p></th>\n";
    #  $data .= "    <td align=right><p>$invoice{'lastattempted'}</p></td>\n";
    #  $data .= "  </tr>\n";
    #}

    $data .= "</table>\n";
  }

  if (($invoice{'status'} eq "open") && ($invoice{'expire_date'} >= $today) && (
       ($invoice{'installment'} > 0) || (($billpay_editutils::feature_list{'billpay_nbalance_plus'} eq "yes") && ($invoice{'balance'} < 0)) )) {
    # get which cards types merchant accepts
    my ($cards_allowed, $allow_overpay, $allow_partial, $allow_nbalance) = &get_merchant_cards_allowed("$invoice{'merchant'}");

    # generate list of user's active bill profiles, which merchant can accept
    my %profiles = &list_bill_profile_hash("active_only", "$cards_allowed");
    my $cnt = 0;

    if ($billpay_editutils::feature_list{'billpay_force_expresspay'} eq "yes") {
      $data .= "<form method=post action=\"/billpay_express.cgi\">\n";
      $data .= "<input type=hidden name=\"email\" value=\"$ENV{'REMOTE_USER'}\">\n";
    }
    else {
      $data .= "<form method=post action=\"$billpay_editutils::path_edit\">\n";
      $data .= "<input type=hidden name=\"function\" value=\"pay_bill_form\">\n";
    }
    $data .= "<input type=hidden name=\"merchant\" value=\"$invoice{'merchant'}\">\n";
    $data .= "<input type=hidden name=\"invoice_no\" value=\"$invoice{'invoice_no'}\">\n";

    if (($billpay_editutils::feature_list{'billpay_comments'} =~ /(1|y)/i) && ($billpay_editutils::feature_list{'billpay_force_expresspay'} ne "yes")){
      $data .= "<p><b>$billpay_language::lang_titles{'comments'}</b>\n";
      $data .= "<br><textarea name=\"comments\" rows=6 cols=40></textarea></p>\n";
    }

    if ( ($allow_overpay eq "yes") || ($allow_partial eq "yes")
         || ((($billpay_editutils::feature_list{'billpay_nbalance_plus'} eq "yes")) && ($invoice{'balance'} < 0)) ){
      # permit customer to pay variable amount on payment
      my ($pay_min, $pay_min_type) = &calc_payment_min($invoice{'amount'}, $invoice{'balance'}, $invoice{'installment'}, $invoice{'remnant'}, $allow_overpay, $allow_partial, $billpay_editutils::feature_list{'billpay_partial_min'});
      my ($pay_max, $pay_max_type) = &calc_payment_max($invoice{'amount'}, $invoice{'balance'}, $invoice{'installment'}, $invoice{'remnant'}, $allow_overpay, $allow_partial);

      $data .= "<p><table border=1 class=\"invoice\">\n";
      $data .= "  <tr>\n";
      $data .= "    <td colspan=2><p><b>$billpay_language::lang_titles{'section_payment_amount'}</a></p></td>\n";
      $data .= "  </tr>\n";

      $data .= "  <tr>\n";
      $data .= "    <th valign=top><p>$billpay_language::lang_titles{'payment_min'}</p></th>\n";
      $data .= "    <td><p>$pay_min</p></td>\n";
      $data .= "  </tr>\n";

      $data .= "  <tr>\n";
      $data .= "    <th valign=top><p>$billpay_language::lang_titles{'payment_max'}</p></th>\n";
      if ($billpay_editutils::feature_list{'billpay_allow_nbalance'} eq "yes") {
        $data .= "    <td><p>Unlimited</p></td>\n";
      }
      else {
        $data .= "    <td><p>$pay_max</p></td>\n";
      }
      $data .= "  </tr>\n";

      if (($invoice{'billcycle'} > 0) && ($invoice{'balance'} > 0) && ($invoice{'installment'} > 0)) {
        if ($invoice{'remnant'} > 0) {
          $data .= "  <tr>\n";
          $data .= "    <th valign=top><p>$billpay_language::lang_titles{'payment_remnant'}</p></th>\n";
          $data .= "    <td><p>$invoice{'remnant'}</p></td>\n";
          $data .= "  </tr>\n";
        }
      }
      elsif ($invoice{'balance'} > 0) {
        $invoice{'installment'} = $invoice{'balance'};
      }

      if ($billpay_editutils::feature_list{'billpay_force_expresspay'} ne "yes") {
        $data .= "  <tr>\n";
        $data .= "    <th valign=top><p>$billpay_language::lang_titles{'payment_amt'}</p></th>\n";
        $data .= "    <td><input type=text name=\"payment_amount\" value=\"$invoice{'installment'}\" size=10 maxlength=9></td>\n";
        $data .= "  </tr>\n";

        if (($billpay_editutils::feature_list{'billpay_nbalance_plus'} eq "yes") && ($invoice{'balance'} < 0)) {
          $data .= "  <tr>\n";
          $data .= "    <td valign=top colspan=2><p><input type=checkbox class=\"checkbox\" name=\"terms_nbalance_plus\" value=\"agree\"> <b>$billpay_language::lang_titles{'statement_terms_nbalance_plus'}</b>\n";
          $data .= "</p></td>\n";
          $data .= "  </tr>\n";
        }
      }
      $data .= "</table>\n";
    }

    if ($billpay_editutils::feature_list{'billpay_terms_pay'} eq "yes") {
      $data .= "<p><span class=\"statement_terms\">$billpay_language::lang_titles{'section_terms_pay'}</span>\n";
      if ($billpay_language::template{'body_terms_pay'} ne "") {
        $data .= "<div class=\"terms\">$billpay_language::template{'body_terms_pay'}</div>\n";
      }
      if ($billpay_editutils::feature_list{'billpay_force_expresspay'} ne "yes") {
        $data .= "<br><input type=checkbox class=\"checkbox\" name=\"terms_pay\" value=\"agree\"> $billpay_language::lang_titles{'statement_terms_pay'}</p>\n";
      }
    }

    if ($billpay_editutils::feature_list{'billpay_terms_service'} eq "yes") {
      $data .= "<p><span class=\"statement_terms\">$billpay_language::lang_titles{'section_terms_service'}</span>\n";
      if ($billpay_language::template{'body_terms_service'} ne "") {
        $data .= "<div class=\"terms\">$billpay_language::template{'body_terms_service'}</div>\n";
      }
      if ($billpay_editutils::feature_list{'billpay_force_expresspay'} ne "yes") {
        $data .= "<br><input type=checkbox class=\"checkbox\" name=\"terms_service\" value=\"agree\"> $billpay_language::lang_titles{'statement_terms_service'}</p>\n";
      }
    }

    if ($billpay_editutils::feature_list{'billpay_terms_use'} eq "yes") {
      $data .= "<p><span class=\"statement_terms\">$billpay_language::lang_titles{'section_terms_use'}</span>\n";
      if ($billpay_language::template{'body_terms_use'} ne "") {
        $data .= "<div class=\"terms\">$billpay_language::template{'body_terms_use'}</div>\n";
      }
      if ($billpay_editutils::feature_list{'billpay_force_expresspay'} ne "yes") {
        $data .= "<br><input type=checkbox class=\"checkbox\" name=\"terms_use\" value=\"agree\"> $billpay_language::lang_titles{'statement_terms_use'}</p>\n";
      }
    }

    if ($billpay_editutils::feature_list{'billpay_terms_privacy'} eq "yes") {
      $data .= "<p><span class=\"statement_terms\">$billpay_language::lang_titles{'section_terms_privacy'}</span>\n";
      if ($billpay_language::template{'body_terms_privacy'} ne "") {
        $data .= "<div class=\"terms\">$billpay_language::template{'body_terms_privacy'}</div>\n";
      }
      if ($billpay_editutils::feature_list{'billpay_force_expresspay'} ne "yes") {
        $data .= "<br><input type=checkbox class=\"checkbox\" name=\"terms_privacy\" value=\"agree\"> $billpay_language::lang_titles{'statement_terms_privacy'}</p>\n";
     }
    }

    $data .= "<table border=0 cellspacing=0 cellpadding=2>\n";

    if ($billpay_editutils::feature_list{'billpay_force_expresspay'} ne "yes") {
      $data .= "  <tr>\n";
      $data .= "    <td valign=top><p><b>$billpay_language::lang_titles{'statement_select_paymethod'}</b></p></td>\n";
      $data .= "  </tr>\n";
      $data .= "  <tr>\n";
      $data .= "    <td valign=top><table border=0 cellspacing=0 cellpadding=2>\n";
      my $default = 0;
      foreach my $key (sort keys %profiles) {
        $data .= "  <tr>\n";
        if (($profiles{$key}{'accttype'} =~ /^(checking|savings)$/i) || ($profiles{$key}{'exp_status'} =~ /^(valid|warn)$/)) {
          $data .= "    <td><input type=radio name=\"profileid\" value=\"$key\"";
          if ($default == 0) {
            $data .= " checked";
            $default = 1;
          }
          $data .= "></td>\n";
        }
        else {
          $data .= "    <td>&nbsp; </td>\n";
        }
        $data .= "    <td>$profiles{$key}{'type'}</td>\n";
        $data .= "    <td>&nbsp; $profiles{$key}{'cardnumber'}</td>\n";
        $data .= "    <td>&nbsp; $profiles{$key}{'exp'}</td>";
        if (($profiles{$key}{'accttype'} !~ /^(checking|savings)$/i) && ($profiles{$key}{'exp_status'} !~ /^(valid|warn)$/)) {
          $data .= "    <td>&nbsp; <b>$profiles{$key}{'exp_reason'}</b> <a href=\"$billpay_editutils::path_edit\?function=edit_bill_profile_form\&profileid=$key\"><span class=\"button\">Update</span></a></td>";
        }
        else {
          $data .= "    <td>&nbsp; </td>\n";
        }
        $data .= "  </tr>\n";
        $cnt = $cnt + 1;
      }
      $data .= "</table></td>\n";
      $data .= "  </tr>\n";
    }

    if (($cnt > 0) || ($billpay_editutils::feature_list{'billpay_force_expresspay'} eq "yes")) {
      $data .= "  <tr>\n";
      $data .= "    <td><p><input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_paybill'}\"></p></td></form>\n";
      $data .= "  </tr>\n";

      if ($billpay_editutils::feature_list{'billpay_force_expresspay'} ne "yes") {
        $data .= "  <tr>\n";
        $data .= "    <td><p><form method=post action=\"$billpay_editutils::path_edit\">\n";
        $data .= "<input type=hidden name=\"function\" value=\"add_new_bill_profile_form\">\n";
        $data .= "<input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_addalt_billing'}\"></form></p></td>\n";
        $data .= "  </tr>\n";
      }
    }
    else {
      $data .= "</form>\n"; # close previous form

      $data .= "  <tr>\n";
      $data .= "    <td><p>$billpay_language::lang_titles{'statement_nobillprofiles3'}\n";
      $data .= "<br>$billpay_language::lang_titles{'statement_accepts2'}\n";
      $data .= "<br><b>$cards_allowed</b>\n";
      $data .= "<br>$billpay_language::lang_titles{'statement_add_billprof'}</p>\n";

      $data .= "<form method=post action=\"$billpay_editutils::path_edit\">\n";
      $data .= "<input type=hidden name=\"function\" value=\"list_bill_profile_form\">\n";
      $data .= "<input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_activate_billing'}\"></form></p></td>\n";
      $data .= "  </tr>\n";
    }

    if ($billpay_editutils::feature_list{'billpay_cardsallowed'} =~ /(zipmark)/i) {
      ## output Pay Bill via Zipmark form
      $data .= "  <tr>\n";
      $data .= "    <td><b>OR</b><br><form method=post action=\"/billpay_express.cgi\">\n";
      $data .= "<input type=hidden name=\"merchant\" value=\"$invoice{'merchant'}\">\n";
      $data .= "<input type=hidden name=\"email\" value=\"$ENV{'REMOTE_USER'}\">\n";
      $data .= "<input type=hidden name=\"invoice_no\" value=\"$invoice{'invoice_no'}\">\n";
      $data .= "<input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_zipmark'}\"></form></td>\n";
      $data .= "  </tr>\n";
    }

    if ($billpay_editutils::feature_list{'billpay_sendto_easycart'} eq "yes") {
      ## output Send To EasyCart form
      $data .= "  <tr>\n";
      $data .= "    <td><p><form method=post action=\"https://easycart.plugnpay.com/easycart.cgi\" target=\"easycart\">\n";
      foreach my $key (sort keys %easycart_form_data) {
        $data .= "<input type=hidden name=\"$key\" value=\"$easycart_form_data{$key}\">\n";
      }
      $data .= "<input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_easycart'}\"></form></p></td>\n";
      $data .= "  </tr>\n";
    }

    # show consolidate options/status as necessary.
    if (($client{'consolidate'} eq "yes") && ($invoice{'account_no'} !~ /^(consolidated_)/)) {
      if ($invoice{'consolidate'} eq "yes") {
        $data .= "  <tr>\n";
        $data .= "    <td><p><b><i>$billpay_language::lang_titles{'statement_consolidate_flag'}</i></b></p></td>\n";
        $data .= " </tr>\n";

        $data .= "<form method=post action=\"$billpay_editutils::path_edit\">\n";
        $data .= "<input type=hidden name=\"function\" value=\"consolidate_bill_form\">\n";
        $data .= "<input type=hidden name=\"merchant\" value=\"$invoice{'merchant'}\">\n";
        $data .= "<input type=hidden name=\"invoice_no\" value=\"$invoice{'invoice_no'}\">\n";
        $data .= "<input type=hidden name=\"consolidate\" value=\"\">\n";
        $data .= "  <tr>\n";
        $data .= "    <td><input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_unconsolidate'}\"></form></td>\n";
        $data .= "  </tr>\n";
      }
      else {
        $data .= "  <tr>\n";
        $data .= "    <td><p>&nbsp;</p></td>\n";
        $data .= " </tr>\n";

        $data .= "<form method=post action=\"$billpay_editutils::path_edit\">\n";
        $data .= "<input type=hidden name=\"function\" value=\"consolidate_bill_form\">\n";
        $data .= "<input type=hidden name=\"merchant\" value=\"$invoice{'merchant'}\">\n";
        $data .= "<input type=hidden name=\"invoice_no\" value=\"$invoice{'invoice_no'}\">\n";
        $data .= "<input type=hidden name=\"consolidate\" value=\"yes\">\n";
        $data .= "  <tr>\n";
        $data .= "    <td><input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_consolidate'}\"></form></td>\n";
        $data .= "  </tr>\n";
      }

      # outoput consolidation warning for installment based invoices, in necessary.
      if (($invoice{'monthly'} > 0) || ($invoice{'percent'} > 0) || ($invoice{'billcycle'} > 0)) {
        $data .= "  <tr>\n";
        $data .= "    <td><p><b>$billpay_language::lang_titles{'warn_consolidation'}</b></p></td>\n";
        $data .= " </tr>\n";
      }
    }

    $data .= "</table>\n";
  }
  elsif ($invoice{'status'} eq "expired") {
    $data .= "<p><b>$billpay_language::lang_titles{'statement_invoice_expired'}</b>\n";
    $data .= "<br>$billpay_language::lang_titles{'statement_merchassist1'} $merch{'company'} $billpay_language::lang_titles{'statement_merchassist2'}</p>\n";
  }
  elsif ($invoice{'status'} eq "closed") {
    $data .= "<p><b>$billpay_language::lang_titles{'statement_invoice_closed'}</b>\n";
    $data .= "<br>$billpay_language::lang_titles{'statement_merchassist1'} $merch{'company'} $billpay_language::lang_titles{'statement_merchassist2'}</p>\n";
  }
  elsif ($invoice{'status'} eq "merged") {
    $data .= "<p><b>$billpay_language::lang_titles{'statement_invoice_merged'}</b>\n";
    $data .= "<br>$billpay_language::lang_titles{'statement_merchassist1'} $merch{'company'} $billpay_language::lang_titles{'statement_merchassist2'}</p>\n";
  }
  elsif ($invoice{'status'} eq "paid") {
    $data .= "<p><b>$billpay_language::lang_titles{'statement_invoice_paid'}</b>\n";
    $data .= "<br>$billpay_language::lang_titles{'statement_merchassist1'} $merch{'company'} $billpay_language::lang_titles{'statement_merchassist2'}</p>\n";
    $data .= "<p><form><input type=button class=\"button\" name=\"print_button\" value=\"Print Page\" onclick=\"window.print();\"></form></p>\n";
  }

  $data .= "</fieldset></td>\n";

  $subtotal = sprintf("%0.02f", $subtotal);

  $data .= "    <td valign=top><table width=\"100%\" class=\"invoice\">\n";
  if ($subtotal > 0) {
    $data .= "  <tr>\n";
    $data .= "    <th width=\"50%\" align=right nowrap><p>$billpay_language::lang_titles{'subtotal'}</p></th>\n";
    $data .= "    <td width=\"50%\" align=right><p>$subtotal</p></td>\n";
    $data .= "  </tr>\n";
  }
  if ($invoice{'shipping'} > 0) {
    $data .= "  <tr>\n";
    $data .= "    <th align=right nowrap><p>$billpay_language::lang_titles{'shipping'}</p></th>\n";
    $data .= "    <td align=right><p>$invoice{'shipping'}</p></td>\n";
    $data .= "  </tr>\n";
  }
  if ($invoice{'handling'} > 0) {
    $data .= "  <tr>\n";
    $data .= "    <th align=right nowrap><p>$billpay_language::lang_titles{'handling'}</p></th>\n";
    $data .= "    <td align=right><p>$invoice{'handling'}</p></td>\n";
    $data .= "  </tr>\n";
  }
  if ($invoice{'discount'} > 0) {
    $data .= "  <tr>\n";
    $data .= "    <th align=right nowrap><p>$billpay_language::lang_titles{'discount'}</p></th>\n";
    $data .= "    <td align=right><p>$invoice{'discount'}</p></td>\n";
    $data .= "  </tr>\n";
  }
  if ($invoice{'tax'} > 0) {
    $data .= "  <tr>\n";
    $data .= "    <th align=right nowrap><p>$billpay_language::lang_titles{'tax'}</p></th>\n";
    $data .= "    <td align=right><p>$invoice{'tax'}</p></td>\n";
    $data .= "  </tr>\n";
  }
  $data .= "  <tr>\n";
  $data .= "    <th align=right nowrap><p>$billpay_language::lang_titles{'amount'}</p></th>\n";
  $data .= "    <td align=right><p>$invoice{'amount'}</p></td>\n";
  $data .= "  </tr>\n";
  $data .= "</table></td>\n";
  $data .= "  </tr>\n";
  $data .= "</table>\n";

  $data .= "<table width=700>\n";
  $data .= "  <tr>\n";
  $data .= "    <td colspan=2><hr width=\"100%\"></td>\n";
  $data .= "  </tr>\n";

  if ($invoice{'datalink_url'} ne "") {
    if ($billpay_editutils::feature_list{'billpay_datalink_type'} =~ /^(post|get)$/) {
      # use datalink form post/get format
      $data .= "  <tr>\n";
      $data .= "    <td align=left><p><b>$billpay_language::lang_titles{'datalink'}</b></p></td>\n";
      $data .= "    <td valign=top align=left><p><form name=\"datalink\" action=\"$invoice{'datalink_url'}\" method=\"$billpay_editutils::feature_list{'billpay_datalink_type'}\" target=\"_blank\">\n";
      if ($invoice{'datalink_pairs'} ne "") {
        my @pairs = split(/\&/, $invoice{'datalink_pairs'});
        for (my $i = 0; $i <= $#pairs; $i++) {
          my $pair = $pairs[$i];
          $pair =~ s/\[client_([a-zA-Z0-9\-\_]*)\]/$client{$1}/g;
          $pair =~ s/\[invoice_([a-zA-Z0-9\-\_]*)\]/$invoice{$1}/g;
          $pair =~ s/\[query_([a-zA-Z0-9\-\_]*)\]/$query{$1}/g;
          my ($name, $value) = split(/\=/, $pair, 2);
          $data .= "<input type=hidden name=\"$name\" value=\"$value\">\n";
        }
      }
      $data .= "<input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_datalink'}\"></form></p></td>\n";
      $data .= "  </tr>\n";
    }
    else {
      # use datalink link format
      my $url = $invoice{'datalink_url'};
      if ($invoice{'datalink_pairs'} ne "") {
        $url .= "\?" . $invoice{'datalink_pairs'};
      }
      $url =~ s/\[client_([a-zA-Z0-9\-\_]*)\]/$client{$1}/g;
      $url =~ s/\[invoice_([a-zA-Z0-9\-\_]*)\]/$invoice{$1}/g;
      $url =~ s/\[query_([a-zA-Z0-9\-\_]*)\]/$query{$1}/g;

      $data .= "  <tr>\n";
      $data .= "    <td align=left><p><b>$billpay_language::lang_titles{'datalink'}</b></p></td>\n";
      $data .= "    <td valign=top align=left><p><a href=\"$url\" target=\"_blank\">$billpay_language::lang_titles{'link_datalink'}</a></p></td>\n";
      $data .= "  </tr>\n";
    }
  }

  if ($invoice{'public_notes'} =~ /\w/) {
    $data .= "  <tr>\n";
    $data .= "    <td align=left><p><b>$billpay_language::lang_titles{'public_notes'}</b></p></td>\n";
    $data .= "    <td valign=top align=left><p>$invoice{'public_notes'}</p></td>\n";
    $data .= "  </tr>\n";
  }

  $data .= "</table>\n";

  $data .= $billpay_language::template{'body_terms'};

  $data .= "</td>\n";
  $data .= "  </tr>\n";
  $data .= "</table>\n";

  return $data;
}

sub get_merchant_cards_allowed {
  # gets which cards types merchant accepts, from merchant's features settings
  my ($merchant) = @_;

  #### query merchant's feature list from SQL table
  my $accountFeatures = new PlugNPay::Features("$merchant",'general');
  my $db_features = $accountFeatures->getFeatureString();

  #### parse feature list into hash
  if ($db_features =~ /(.*)=(.*)/) {
    my @array = split(/\,/,$db_features);
    foreach my $entry (@array) {
      my ($name, $value) = split(/\=/, $entry);
      $billpay_editutils::feature_list{"$name"} = "$value";
    }
  }

  my ($cards_allowed, $allow_overpay, $allow_partial, $allow_nbalance);

  ### if defined, grab 'billpay_cardsallowed' value
  if ($billpay_editutils::feature_list{'billpay_cardsallowed'} =~ /\w/) {
    $cards_allowed = $billpay_editutils::feature_list{'billpay_cardsallowed'};
    # now filter the  value, to be extra careful
    $cards_allowed =~ s/\W{1,}/ /g; # replace all non-alphanumber characters with spaces
    $cards_allowed =~ s/^\s+//; # remove all leading whitespace characters
    $cards_allowed =~ s/\s+$//; # remove all trailing whitespace characters 
    $cards_allowed =~ s/\s+/ /g; # convert multiple whitespace characters into a single space character
  }

  if ($cards_allowed eq "") {
    $cards_allowed = "Visa Mastercard";
  }

  if ($billpay_editutils::feature_list{'billpay_allow_overpay'} =~ /yes/i) {
    $allow_overpay = "yes";
  }

  if ($billpay_editutils::feature_list{'billpay_allow_partial'} =~ /yes/i) {
    $allow_partial = "yes";
  }

  if ($billpay_editutils::feature_list{'billpay_allow_balance'} =~ /yes/i) {
    $allow_nbalance = "yes";
    $allow_overpay = "yes"; # auto-enables overpay option
  }

  return $cards_allowed, $allow_overpay, $allow_partial, $allow_nbalance;
}

sub consolidate_bill_form {
  my %query = @_;

  my ($data, $merchant, $username, $invoice_no);

  $query{'merchant'} =~ s/[^a-zA-Z0-9]//g;
  $query{'invoice_no'} =~ s/[^a-zA-Z0-9\_\-]//g;

  if ($query{'consolidate'} ne "yes") { 
    $query{'consolidate'} = "";
  }

  # see if invoice exists
  my $sth = $billpay_editutils::dbh->prepare(q{
      SELECT merchant, username, invoice_no, consolidate
      FROM bills2
      WHERE merchant=?
      AND username=?
      AND invoice_no=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth->execute("$query{'merchant'}", "$ENV{'REMOTE_USER'}", "$query{'invoice_no'}") or die "Cannot execute: $DBI::errstr";
  ($merchant, $username, $invoice_no) = $sth->fetchrow;
  $sth->finish;

  if (($merchant ne "") && ($username ne "") && ($invoice_no ne "")) {
    my $sth2 = $billpay_editutils::dbh->prepare(q{
        UPDATE bills2
        SET consolidate=?
        WHERE merchant=?
        AND username=?
        AND invoice_no=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2->execute("$query{'consolidate'}", "$merchant", "$ENV{'REMOTE_USER'}", "$invoice_no") or die "Cannot execute: $DBI::errstr";
    $sth2->finish;

    $data = "$billpay_language::lang_titles{'statement_consolidate_updated'}\n";
  }
  else {
    $data = "$billpay_language::lang_titles{'error_nomatch'}\n";
  }

  return $data;
}

sub pay_bill_form {
  my %query = @_;

  my ($data, $merchant, $username, $invoice_no, $account_no, $status, $expire_date, $amount, $profileid, $shacardnumber, $cardname, $cardcompany, $cardaddr1, $cardaddr2, $cardcity, $cardstate, $cardzip, $cardcountry, $cardnumber, $exp, $enccardnumber, $length, $shipcompany, $shipname, $shipaddr1, $shipaddr2, $shipcity, $shipstate, $shipzip, $shipcountry, $shipphone, $shipfax, $phone, $fax, $email, $db_item, $db_cost, $db_qty, $db_descr, $db_weight, $db_descra, $db_descrb, $db_descrc, $accttype, $routingnum, $accountnum, $tax, $shipping, $handling, $discount, $balance, $percent, $monthly, $remnant, $billcycle, $public_notes, $private_notes, $lastbilled, $lastattempted, $merch_company, $merch_status, $merch_cards_allowed, $merch_chkprocessor, $merch_feature, $merch_alliance_status, $charge, $charge_type, $charge_diff, $installment, $installment_type);

  my @now = gmtime(time);
  my $today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

  # get general transaction info
  my $sth = $billpay_editutils::dbh->prepare(q{
      SELECT merchant, username, invoice_no, account_no, status, expire_date, amount, tax, shipping, handling, discount, balance, percent, monthly, remnant, billcycle, public_notes, private_notes, lastbilled, lastattempted, shipcompany, shipname, shipaddr1, shipaddr2, shipcity, shipstate, shipzip, shipcountry, shipphone, shipfax
      FROM bills2
      WHERE username=?
      AND invoice_no=?
      AND merchant=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth->execute("$ENV{'REMOTE_USER'}", "$query{'invoice_no'}", "$query{'merchant'}") or die "Cannot execute: $DBI::errstr";
  ($merchant, $username, $invoice_no, $account_no, $status, $expire_date, $amount, $tax, $shipping, $handling, $discount, $balance, $percent, $monthly, $remnant, $billcycle, $public_notes, $private_notes, $lastbilled, $lastattempted, $shipcompany, $shipname, $shipaddr1, $shipaddr2, $shipcity, $shipstate, $shipzip, $shipcountry, $shipphone, $shipfax) = $sth->fetchrow;
  $sth->finish;

  # get billing profile info
  my $sth2 = $billpay_editutils::dbh->prepare(q{
      SELECT username, profileid, shacardnumber, cardname, cardcompany, cardaddr1, cardaddr2, cardcity, cardstate, cardzip, cardcountry, cardnumber, exp, enccardnumber, length
      FROM billing2
      WHERE username=?
      AND profileid=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth2->execute("$ENV{'REMOTE_USER'}", "$query{'profileid'}") or die "Cannot execute: $DBI::errstr";
  ($username, $profileid, $shacardnumber, $cardname, $cardcompany, $cardaddr1, $cardaddr2, $cardcity, $cardstate, $cardzip, $cardcountry, $cardnumber, $exp, $enccardnumber, $length) = $sth2->fetchrow;
  $sth2->finish;

  if ($shacardnumber ne "") {
    my $cd = new PlugNPay::CardData();
    my $ecrypted_card_data = '';
    eval {
      $ecrypted_card_data = $cd->getBillpayCardData({customer => "$username", profileID => "$profileid"});
    };
    if (!$@) {
      $enccardnumber = $ecrypted_card_data;
    }

    $cardnumber = &rsautils::rsa_decrypt_file($enccardnumber,$length,"print enccardnumber 497","/home/pay1/pwfiles/keys/key");

    if ($cardnumber =~ /\d{9} \d/) {
      ($routingnum, $accountnum) = split(/ /, $cardnumber, 2);
      $accttype = "checking";
      $cardnumber = "";
    }
    else {
      $accttype = "";
    }
  }

  # get instant contact info 
  my $sth3 = $billpay_editutils::dbh->prepare(q{
      SELECT username, phone, fax, email
      FROM customer2
      WHERE username=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth3->execute("$ENV{'REMOTE_USER'}") or die "Cannot execute: $DBI::errstr";
  ($username, $phone, $fax, $email) = $sth3->fetchrow;
  $sth3->finish;

  # get merchant's company name, account status, allowed card types & ach processor info
  my $dbh_pnpmisc = &miscutils::dbhconnect("pnpmisc");
  my $sth_pnpmisc = $dbh_pnpmisc->prepare(q{
      SELECT company, status, cards_allowed, chkprocessor
      FROM customers
      WHERE username=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth_pnpmisc->execute("$merchant") or die "Cannot execute: $DBI::errstr";
  ($merch_company, $merch_status, $merch_cards_allowed, $merch_chkprocessor) = $sth_pnpmisc->fetchrow;
  $sth_pnpmisc->finish;
  $dbh_pnpmisc->disconnect;

  my $accountFeatures = new PlugNPay::Features("$merchant",'general');
  my $merch_feature = $accountFeatures->getFeatureString();

  my %feature;
  my @array = split(/\,/,$merch_feature);
  foreach my $entry (@array) {
    my($name,$value) = split(/\=/,$entry);
    $feature{"$name"} = $value;
  }

  # verify merchant can accept that payment type &/or card type
  if ($merch_status !~ /(live|debug|test)/i) {
    # error: merchant account not active
    $data = "$billpay_language::lang_titles{'error_merchant_inactive'}\n";
    $data .= "<br>$billpay_language::lang_titles{'statement_merchassist1'} $merch_company $billpay_language::lang_titles{'statement_merchassist2'}\n";
    return $data;
  }

  if ($accttype eq "checking") {
    # check for ACH/echeck ability
    my $allow_ach = &detect_ach("$merch_chkprocessor","$merchant"); 
    if ($allow_ach !~ /yes/i) {
      # error: ACH/eCheck not supported
      $data = "$billpay_language::lang_titles{'error_merchant_noach'}\n";
      $data .= "<br>$billpay_language::lang_titles{'statement_use_cc'} \'$allow_ach\'\n";
      return $data;
    }
  }
  else {
    # check for cardtype & find out it's allowed
    my $cardtype = &detect_cardtype("$cardnumber");
    if ($cardtype !~ /($merch_cards_allowed)/) {
      # error: card type not supported
      $data = "$billpay_language::lang_titles{'error_merchant_noaccept'}\n";
      $data .= "<br>$billpay_language::lang_titles{'statement_usediff_cc'}\n";
      return $data;
    }
  }

  # enforce payment, service, usage &/or privacy terms agreements, as necessary
  if ( ($feature{'billpay_nbalance_plus'} eq "yes")
    || ($feature{'billpay_terms_pay'} eq "yes")
    || ($feature{'billpay_terms_service'} eq "yes")
    || ($feature{'billpay_terms_use'} eq "yes")
    || ($feature{'billpay_terms_privacy'} eq "yes") ) {
    my $error = 0; # assume no terms/agreement errors are present
    my $reason = "";

    if (($feature{'billpay_nbalance_plus'} eq "yes") && ($query{'terms_nbalance_plus'} ne "agree") && ($balance < 0)) {
      # error: nbalance_plus terms declined
      $error = 1;
      $reason .= "$billpay_language::lang_titles{'error_terms_nbalance_plus'}<br>\n";
    }

    if (($feature{'billpay_terms_pay'} eq "yes") && ($query{'terms_pay'} ne "agree")) {
      # error: payment terms declined
      $error = 1;
      $reason .= "$billpay_language::lang_titles{'error_terms_pay'}<br>\n";
    }

    if (($feature{'billpay_terms_service'} eq "yes") && ($query{'terms_service'} ne "agree")) {
      # error: service terms declined
      $error = 1;
      $reason .= "$billpay_language::lang_titles{'error_terms_service'}<br>\n";
    }

    if (($feature{'billpay_terms_use'} eq "yes") && ($query{'terms_use'} ne "agree")) {
      # error: usage terms declined
      $error = 1;
      $reason .= "$billpay_language::lang_titles{'error_terms_use'}<br>\n";
    }

    if (($feature{'billpay_terms_privacy'} eq "yes") && ($query{'terms_privacy'} ne "agree")) {
      # error: payment terms declined
      $error = 1;
      $reason .= "$billpay_language::lang_titles{'error_terms_privacy'}<br>\n";
    }

    if ($error == 1) {
      $reason .= "<br>$billpay_language::lang_titles{'statement_back_tryagain'}\n";
      return $reason;
    }
  }

  # calcualte the default amount of the payment
  ($installment, $installment_type) = &calc_payment_default($amount, $balance, $billcycle, $monthly, $percent, $remnant);

  if ($query{'payment_amount'} > 0) {
    $charge = $query{'payment_amount'};
  }
  else {
    $charge = $installment;
  }

  # get payment min & max values
  my ($pay_min, $pay_min_type) = &calc_payment_min($amount, $balance, $installment, $remnant, $feature{'billpay_allow_overpay'}, $feature{'billpay_allow_partial'}, $feature{'billpay_partial_min'});
  my ($pay_max, $pay_max_type) = &calc_payment_max($amount, $balance, $installment, $remnant, $feature{'billpay_allow_overpay'}, $feature{'billpay_allow_partial'});

  ## enforce minimum payment amount
  if ($charge < $pay_min) {
    # error: payment amount less then minimum allowed
    $data = "$billpay_language::lang_titles{'error_payment_min'}\n";
    $data .= "<br>$billpay_language::lang_titles{'statement_back_tryagain'}\n";
    return $data;
  }

  ## enforce maximum payment amount
  if (($charge > $pay_max) && ($feature{'billpay_allow_nbalance'} ne "yes")) {
    # error: payment amount more then maximum allowed
    $data = "$billpay_language::lang_titles{'error_payment_max'}\n";
    $data .= "<br>$billpay_language::lang_titles{'statement_back_tryagain'}\n";
    return $data;
  }

  # calculate payment different, in case its a partial payment or negative balance payment.
  if (($feature{'billpay_nbalance_plus'} eq "yes") && ($balance < 0)) {
    $charge_diff = $balance - $charge;
  }
  else {
    $charge_diff = $installment - $charge;
  }

  # reformat charge amounts
  $charge = sprintf("%0.02f", $charge);
  $charge_diff = sprintf("%0.02f", $charge_diff);

  # do API's auth here
  #use remote_strict;

  my $orderid = PlugNPay::Transaction::TransactionProcessor::generateOrderID();

  my @array1 = (
    "publisher-name","$merchant",
    "mode","auth",
    "card-amount","$charge",
    "tax","$tax",
    "shipping","$shipping",
    "handling","$handling",
    "discount","$discount",
    "orderID","$orderid",
    "ipaddress","$ENV{'REMOTE_ADDR'}",
    "acct_code","$account_no",
    "acct_code2","$invoice_no",
    "acct_code3","billpay",
    "card-name","$cardname",
    "card-address1","$cardaddr1",
    "card-address2","$cardaddr2",
    "card-city","$cardcity",
    "card-state","$cardstate",
    "card-zip","$cardzip",
    "card-country","$cardcountry",
    "shipinfo","1",
    "shipcompany","$shipcompany",
    "shipname","$shipname",
    "address1","$shipaddr1",
    "address2","$shipaddr2",
    "city","$shipcity",
    "state","$shipstate",
    "zip","$shipzip",
    "country","$shipcountry",
    "shipphone", "$shipphone",
    "shipfax", "$shipfax",
    "email","$email",
    "phone","$phone",
    "fax","$fax",
    "public_notes", "$public_notes",
    "billpay_invoice_no", "$invoice_no",
    "billpay_account_no", "$account_no",
    "billpay_email", "$ENV{'REMOTE_USER'}"
  );

  if ($accttype =~ /checking|savings/i) {
    push (@array1, "paymethod", "onlinecheck", "accttype", "$accttype", "routingnum", "$routingnum", "accountnum", "$accountnum");

    if ($merch_chkprocessor ne "") {
      # apply required ACH setting, as necessary
      if ($query{'checktype'} ne "") {
        push (@array1, "checktype", "$query{'checktype'}");
      }
      elsif ($feature{'billpay_checktype'} ne "") {
        push (@array1, "checktype", "$feature{'billpay_checktype'}");
      }
      else {
        push (@array1, "checktype", "WEB");
      }
    }
  }
  else {
    push (@array1, "card-number", "$cardnumber", "card-exp", "$exp");
  }

  if ($query{'comments'} =~ /\w/) {
    push(@array1, "comments", "$query{'comments'}");
  }

  my $subtotal = 0;
  my $totalwgt = 0;

  my $cnt = 0;
  my $sth4 = $billpay_editutils::dbh->prepare(q{
      SELECT item, cost, qty, descr, weight, descra, descrb, descrc
      FROM billdetails2
      WHERE username=?
      AND invoice_no=?
      AND merchant=?
      ORDER BY item
    }) or die "Cannot do: $DBI::errstr";
  $sth4->execute("$ENV{'REMOTE_USER'}", "$invoice_no", "$merchant") or die "Cannot execute: $DBI::errstr";
  my $rv = $sth4->bind_columns(undef,\($db_item, $db_cost, $db_qty, $db_descr, $db_weight, $db_descra, $db_descrb, $db_descrc));
  while($sth4->fetch) {
    if (($db_item ne "") && ($db_cost =~ /\d/) && ($db_qty > 0) && ($db_descr ne "")) {
      $cnt = $cnt + 1;
      $db_cost = sprintf("%0.02f", $db_cost);
      push (@array1, "item$cnt", "$db_item", "cost$cnt", "$db_cost", "quantity$cnt", "$db_qty", "description$cnt", "$db_descr");

      if ($feature{'billpay_extracols'} =~ /weight/) {
        push (@array1, "weight$cnt", "$db_weight");
      }
      if ($feature{'billpay_extracols'} =~ /descra/) {
        push (@array1, "descra$cnt", "$db_descra");
      }
      if ($feature{'billpay_extracols'} =~ /descrb/) {
        push (@array1, "descrb$cnt", "$db_descrb");
      }
      if ($feature{'billpay_extracols'} =~ /descrc/) {
        push (@array1, "descrc$cnt", "$db_descrc");
      }

      $subtotal += ($db_cost * $db_qty);
      $totalwgt += ($db_weight * $db_qty);
    }
  }
  $sth4->finish;

  $totalwgt = sprintf("%s", $totalwgt);
  if ($totalwgt > 0) {
    push (@array1, "test_wgt", "$totalwgt");
  }

  $subtotal = sprintf("%0.02f", $subtotal);
  if ($subtotal > 0) {
    push (@array1, "subtotal", "$subtotal");
  }

  if ($cnt > 0) {
    push (@array1, "receipt_type", "itemized", "easycart", "1");
  }
  else {
    push (@array1, "receipt_type", "simple");
  }

  my $payment = mckutils->new(@array1);
  my %result = $payment->purchase("auth");
  $result{'auth-code'} = substr($result{'auth-code'},0,6);
  $payment->database();
  %remote::query = (%remote::query,%mckutils::query,%result);
  $payment->email();

  # record payment attempt
  my $sth5 = $billpay_editutils::dbh->prepare(q{
      INSERT INTO billingstatus2 
      (orderid, username, profileid, invoice_no, account_no, trans_date, amount, descr, result, billusername)
      VALUES (?,?,?,?,?,?,?,?,?,?)
    }) or die "Cannot prepare: $DBI::errstr";
  $sth5->execute("$orderid", "$ENV{'REMOTE_USER'}", "$profileid", "$invoice_no", "$account_no", "$today", "$charge", "$remote::query{'descr'}", "$remote::query{'result'}", "$merchant") or die "Cannot execute: $DBI::errstr";
  $sth5->finish;

  &record_history("$ENV{'REMOTE_USER'}", "$profileid", "pay_bill", "Bill Payment Attempted - $remote::query{'result'}");

  if ($result{'FinalStatus'} =~ /success/i) {
    # update transaction status

    # adjust balance, if needed
    if ( ($balance eq "")
      || (($feature{'billpay_allow_nbalance'} eq "yes") && ($balance == 0) && ($charge_diff < 0))
      || (($feature{'billpay_nbalance_plus'} eq "yes") && ($balance < 0) && ($charge_diff < 0)) ) {
      $balance = $charge_diff;
      $balance = sprintf("%0.02f", $balance);
    }
    elsif ($balance > 0) {
      $balance = $balance - $charge;
      $balance = sprintf("%0.02f", $balance);
    }

    # set installment remnant, if necessary [if not needed, blank the value]
    if (($billcycle > 0) && ($balance > 0) && (($monthly > 0) || ($percent > 0))) {
      if (($charge_diff < $installment) && ($charge_diff > 0)) {
        $remnant = $charge_diff;
      }
      else {
        $remnant = "";
      }
    }
    else {
      $remnant = "";
    }

    # extend expire_date, if needed
    if (($billcycle > 0) && ($balance > 0) && (($monthly > 0) || ($percent > 0))) {
      # figure out what the new expire date will be
      my $expire_year  = substr($expire_date, 0, 4);
      my $expire_month = substr($expire_date, 4, 2);
      my $expire_day   = substr($expire_date, 6, 2);

      $expire_month = $expire_month + $billcycle;
      $expire_month = ceil($expire_month);

      if ($expire_month > 12) {
        my $c = $expire_month % 12;
        $expire_month = $expire_month - ($c * 12);
        $expire_year = $expire_year + $c;
      }

      $expire_date = sprintf("%04d%02d%02d", $expire_year, $expire_month, $expire_day);
      $remote::query{'expire_date'} = $expire_date;
    }

    if (($feature{'billpay_nbalance_plus'} eq "yes") && ($balance < 0)) {
      $status = "open";
      $remote::query{'balance'} = $charge_diff;
    }
    elsif ($balance > 0) {
      $status = "open";
      $remote::query{'balance'} = $balance;
    }
    else {
      $status = "paid";
    }

    if ($query{'comments'} =~ /\w/) {
      my @now = gmtime(time);
      my $today = sprintf("%02d\/%02d\/%04d \@ %02d\:%02d\:%02d GMT", $now[4]+1, $now[3], $now[5]+1900, $now[2], $now[1], $now[0]);
      $private_notes .= "\n$today - Customer Comments:\n$query{'comments'}\n";
      $private_notes =~ s/^\s+//g; # strip leading whitespace
      $private_notes =~ s/\s+$//g; # strip tailing whitespace
    }

    my $sth2 = $billpay_editutils::dbh->prepare(q{
        UPDATE bills2
        SET status=?, orderid=?, lastbilled=?, lastattempted=?, balance=?, remnant=?, expire_date=?, private_notes=?
        WHERE username=?
        AND invoice_no=?
        AND merchant=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2->execute("$status", "$remote::query{'orderID'}", "$today", "$today", "$balance", "$remnant", "$expire_date", "$private_notes", "$ENV{'REMOTE_USER'}", "$invoice_no", "$merchant") or die "Cannot execute: $DBI::errstr";
    $sth2->finish;

    #$data = "$billpay_language::lang_titles{'statement_payment_success'}\n";
    #$data .= "<br>$billpay_language::lang_titles{'orderid'} $remote::query{'orderID'}\n";

    $data = &thankyou_template($billpay_editutils::dbh, %remote::query);
  }
  elsif ($result{'FinalStatus'} =~ /^(badcard|problem|fraud)$/i) {
    # don't do anything - leave transaction as is
    my $sth3 = $billpay_editutils::dbh->prepare(q{
        UPDATE bills2
        SET lastattempted=?
        WHERE username=?
        AND invoice_no=?
        AND merchant=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth3->execute("$today", "$ENV{'REMOTE_USER'}", "$invoice_no", "$merchant") or die "Cannot execute: $DBI::errstr";
    $sth3->finish;

    if ($result{'FinalStatus'} =~ /^(badcard|problem|fraud)$/i) {
      $data = "$billpay_language::lang_titles{'statement_payment_badcard'}\n";
      $data .= "<br>$billpay_language::lang_titles{'reason'} $result{'MErrMsg'}\n";
    }
    elsif ($result{'FinalStatus'} =~ /problem/i) {
      $data = "$billpay_language::lang_titles{'statement_payment_problem'}\n";
      $data .= "<br>$billpay_language::lang_titles{'reason'} $result{'MErrMsg'}\n";
    }
    elsif ($result{'FinalStatus'} =~ /fraud/i) {
      $data = "$billpay_language::lang_titles{'statement_payment_fraud'}\n";
      $data .= "<br>$billpay_language::lang_titles{'reason'} $result{'MErrMsg'}\n";
    }
  }
  else {
    # Error: unknown FinalStatus response
    $data .= "$billpay_language::lang_titles{'error_payment_unknown'}\n";
    $data .= "<br>$billpay_language::lang_titles{'statement_contact_support'}\n";
    $data .= sprintf("<br>Date: %02d\/%02d\/04d\n", substr($today,4,2), substr($today,6,2), substr($today,0,4));
    $data .= "<br>$billpay_language::lang_titles{'orderid'} $remote::query{'orderID'}\n";
    $data .= "<br>$billpay_language::lang_titles{'amount'} $remote::query{'card-amount'}\n";

    #if ($ENV{'REMOTE_ADDR'} eq "96.56.10.14") {
    #  foreach my $key (sort keys %result) {
    #    $data .= "<br>RESULT: $key = \'$result{$key}\'\n";
    #  }
    #}
  }

  return $data;
}

sub calc_payment_min {
  # figure out what the absolute minimum of the allowed payment amount should be.
  my ($amount, $balance, $installment, $remnant, $allow_overpay, $allow_partial, $partial_min) = @_;

  ## fields to use for calculations
  # amount => total amount of invoice
  # balance => remaining balance of invoice
  # installment => installment amount
  # remnant => is remainder of installment payment

  #my ($pay_due);
  #if ($remnant > 0) {
  #  $pay_due = $remnant;
  #}
  #elsif ($installment > 0) {
  #  $pay_due = $installment;
  #}
  #elsif ($balance > 0) {
  #  $pay_due = $balance;
  #}
  #else {
  #  $pay_due = $amount;
  #}

  ## settings that are enabled.
  # allow_overpay  => [yes] (min is 'installment', max is 'balance' or 'amount')
  # allow_partial  => [yes] (min is '0.01', max is 'remainder', 'installment', 'balance' or 'amount')
  # allow_nbalance => [yes] (min is 'remainder', 'installment', 'balance' or 'amount' + 0.01 to produce a negative balance on invoice)
  #
  # billpay_partial_min => [1234.56] artificial minimum amount allowed limit for partial payments

  ## logics is laid out from most to least specific rule conditions
  my ($pay_min, $pay_min_type);

  if ($allow_partial eq "yes") {
    if ($partial_min > 0) {
      $pay_min = $partial_min;
      $pay_min_type = "partial_min";
    }
    else {
      $pay_min = 0.01;
      $pay_min_type = "smallest_min";
    }
  }
  elsif ($allow_overpay eq "yes") {
    $pay_min = $installment;
    $pay_min_type = "overview_installment";
  }
  else {
    $pay_min = $installment;
    $pay_min_type = "installment";
  }

  #print "<br>Result: Payment Min: $pay_min\n";
  return ($pay_min, $pay_min_type);
}

sub calc_payment_max {
  # figure out what the absolute maximum of the allowed payment amount should be.
  my ($amount, $balance, $installment, $remnant, $allow_overpay, $allow_partial) = @_;

  ## fields to use for calculations
  # amount => total amount of invoice
  # balance => remaining balance of invoice
  # installment => installment amount
  # remnant => is remainder of installment payment

  #my ($pay_due);
  #if ($remnant > 0) {
  #  $pay_due = $remnant;
  #}
  #elsif ($installment > 0) {
  #  $pay_due = $installment;
  #}
  #elsif ($balance > 0) {
  #  $pay_due = $balance;
  #}
  #else {
  #  $pay_due = $amount;
  #}

  ## settings that are enabled.
  # allow_overpay  => [yes] (min is 'installment', max is 'balance' or 'amount')
  # allow_partial  => [yes] (min is '0.01', max is 'remainder', 'installment', 'balance' or 'amount')
  # allow_nbalance => [yes] (min is 'remainder', 'installment', 'balance' or 'amount' + 0.01 to produce a negative balance on invoice)

  my ($pay_max, $pay_max_type);

  if (($allow_overpay eq "yes") && ($balance > 0)) {
    $pay_max = $balance;
    $pay_max_type = "overpay_balance";
  }
  elsif (($allow_overpay eq "yes") && ($installment > 0)) {
    $pay_max = $installment;
    $pay_max_type = "overpay_installment";
  }
  elsif (($allow_overpay ne "yes") && ($remnant > 0)) {
    $pay_max = $remnant;
    $pay_max_type = "remnant";
  }
  elsif (($allow_overpay ne "yes") && ($installment > 0)) {
    $pay_max = $installment;
    $pay_max_type = "installment";
  }
  elsif (($allow_overpay ne "yes") && ($remnant > 0)) {
    $pay_max = $balance;
    $pay_max_type = "balance";
  }
  else {
    $pay_max = $amount;
    $pay_max_type = "amount";
  }

  #print "<br>Result: Payment Max: $pay_max\n";
  return ($pay_max, $pay_max_type);
}

sub calc_payment_default {
  # figure out what the default amount of the invoice payment should be
  my ($amount, $balance, $billcycle, $monthly, $percent, $remnant) = @_;

  my ($installment, $installment_type);

  # calculate installment amount
  if (($billcycle > 0) && ($balance > 0) && (($monthly > 0) || ($percent > 0))) {
    if (($balance > 0) && (($monthly > 0) || ($percent > 0))) {
      if ($percent > 0) {
        # figure out percentage installment amount
        $installment = ($percent / 100) * $balance;
        $installment_type = "percent_installment";

        if (($percent > 0) && ($installment < $monthly)) {
          # now if installment is less then monthly minimim, charge the minimum
          $installment = $monthly;
          $installment_type = "minimum_installment";
        }
      }
      else {
        # when invoice is only monthly based, set the monthly amount for the installment amount.
        $installment = $monthly;
        $installment_type = "flatrate_installment";
      }

      # apply remnant, if less then installment amount
      if (($remnant > 0) && ($installment > $remnant)) {
        $installment = $remnant;
        $installment_type = "remnant_installment";
      }

      # now if the balanace is less then the installment amount, charge the remaining balance only
      if ($installment > $balance) {
        $installment = $balance;
        $installment_type = "remainder_installment";
      }
    }
  }
  ## since we are not charging the installment fee, see if we need to charge the balance on the invoice
  elsif ($balance > 0) {
    # charge the balance on an invoice
    $installment = $balance;
    $installment_type = "balance";
  }
  elsif ($balance < 0) {
    $installment = 0.00;
    $installment_type = "negative_balance";
  }
  # since we are not charging a balance or an installment payment payment, charge the full amount of the bill
  else {
    # charge the full amount of the bill
    $installment = $amount;
    $installment_type = "full_amount";
  }

  #print "<br>RESULT: Installment: $installment, Type: $installment_type\n";
  return ($installment, $installment_type);
}

sub detect_ach {
  # checks to see if ACH/eCheck can be used or not. (Yes = ok,  No = no ach)
  my ($merch_chkprocessor, $merchant) = @_;

  if ($merch_chkprocessor ne "") {
    my $ach_allowed = "no"; # assume ACH not allowed by default
    my ($cards_allowed, $allow_overpay) = &get_merchant_cards_allowed("$merchant"); # now get card types allowed

    # now see if checking or savings is allowed by the merchant
    my @temp = split(/ /, $cards_allowed);
    for (my $i = 0; $i <= $#temp; $i++) {
      if ($temp[$i] =~ /(checking|savings)/i) {
        $ach_allowed = "yes";
      }
    }
    return "$ach_allowed";
  }
  else {
    # error: no ACH/eCheck processor
    return "no";
  }
}

sub detect_cardtype {
  my ($cardnumber) = @_; 

  my ($cardtype);

  my $cardbin = substr($cardnumber,0,6);
  if ( ($cardbin =~ /^(491101|491102)/)
    || ($cardbin =~ /^(564182)/)
    || ($cardbin =~ /^(490302|490303|490304|490305|490306|490307|490308|490309)/)
    || ($cardbin =~ /^(490335|490336|490337|490338|490339|490525|491174|491175|491176|491177|491178|491179|491180|491181|491182)/)
    || ($cardbin =~ /^(4936)/)
    || (($cardbin >= 633300) && ($cardbin < 633349))
    || (($cardbin >= 675900) && ($cardbin < 675999)) ) {
    $cardtype = "SWTCH";
  }
  elsif ( (($cardbin >= 633450) && ($cardbin < 633499)) || (($cardbin >= 676700) && ($cardbin < 676799)) ) {
    $cardtype = "SOLO";
  }
  elsif ($cardbin =~ /^(4)/) {
    $cardtype = "VISA";
  }
  elsif ($cardbin =~ /^(51|52|53|54|55)/) {
    $cardtype = "MSTR";
  }
  elsif ($cardbin =~ /^(37|34)/) {
    $cardtype = "AMEX";
  }
  elsif (($cardbin =~ /^(3088|3096|3112|3158|3337)/)
    || (($cardbin >= 352800) && ($cardbin < 359000))) {
    $cardtype = "JCB";
  }
  elsif ($cardbin =~ /^(30|36|38[0-8])/) {
    $cardtype = "DNRS";
  }
  elsif ($cardbin =~ /^(389)/) {
    $cardtype = "CRTB";
  }
  elsif ($cardbin =~ /^(6011)/) {
    $cardtype = "DSCR";
  }
  elsif ($cardbin =~ /^(1800|2131)/) {
    $cardtype = "JAL";
  }
  elsif ($cardbin =~ /^(7775|7776|7777)/) {
    $cardtype = "KC";
  }
  elsif ($cardbin =~ /^(7)/) {
    $cardtype = "MYAR";
  }

  return $cardtype;
}

sub thankyou_template {
  my ($dbh, %query) = @_;
  my $data = "";

  if ($ENV{'REMOTE_USER'} ne "") {
    $query{'billpay_email'} = $ENV{'REMOTE_USER'};
  }

  # get merchant's company name & account status
  my $dbh_misc = &miscutils::dbhconnect("pnpmisc");
  my $sth = $dbh_misc->prepare(q{
      SELECT company
      FROM customers
      WHERE username=?
    }) or die "Cannot prepare1: $DBI::errstr";
  $sth->execute("$query{'publisher-name'}") or die "Cannot execute1: $DBI::errstr";
  my ($db_merch_company) = $sth->fetchrow;
  $sth->finish;
  $dbh_misc->disconnect;

  my $accountFeatures = new PlugNPay::Features("$query{'publisher-name'}",'general');
  my $db_feature = $accountFeatures->getFeatureString();

  my %feature;
  my @array = split(/\,/,$db_feature);
  foreach my $entry (@array) {
    my($name,$value) = split(/\=/,$entry);
    $feature{"$name"} = $value;
  }

  # if ok, see if we need to display client contact info
  my $sth2 = $dbh->prepare(q{
      SELECT *
      FROM client_contact
      WHERE username=?
      AND merchant=?
    }) or die "Cannot prepare2: $DBI::errstr";
  $sth2->execute("$query{'billpay_email'}", "$query{'publisher-name'}") or die "Cannot execute2: $DBI::errstr";
  my $client = $sth2->fetchrow_hashref();
  $sth2->finish;

  my %client;
  foreach my $key (keys %$client) {
    $client{"$key"} = $client->{$key};
  }

  my $sth3 = $dbh->prepare(q{
      SELECT *
      FROM bills2
      WHERE username=?
      AND invoice_no=?
      AND merchant=?
    }) or die "Cannot prepare3: $DBI::errstr";
  $sth3->execute("$query{'billpay_email'}", "$query{'billpay_invoice_no'}", "$query{'publisher-name'}") or die "Cannot execute3: $DBI::errstr";
  my $invoice = $sth3->fetchrow_hashref();
  $sth3->finish;

  my %invoice;
  foreach my $key (keys %$invoice) {
    $invoice{"$key"} = $invoice->{$key};
  }

  my $enter = sprintf("%02d\/%02d\/%04d", substr($invoice{'enter_date'},4,2), substr($invoice{'enter_date'},6,2), substr($invoice{'enter_date'},0,4));
  my $expire = sprintf("%02d\/%02d\/%04d", substr($invoice{'expire_date'},4,2), substr($invoice{'expire_date'},6,2), substr($invoice{'expire_date'},0,4));

  my $order_date = substr($query{'orderID'}, 0, 8);
  $order_date = sprintf("%02d\/%02d\/%04d", substr($order_date,4,2), substr($order_date,6,2), substr($order_date,0,4));

  $data .= "<div align=left>\n";
  $data .= "<br><font size=+1><b>$billpay_language::lang_titles{'section_orderreceipt'}</b></font>\n";
  $data .= "<br><p><b>$billpay_language::lang_titles{'statement_printsave'}</b>\n";
  $data .= "<br>$billpay_language::lang_titles{'statement_merchant_support1'} <a href=\"mailto:$feature{'pubemail'}\">$feature{'pubemail'}</a>.\n";
  $data .= "<br>$billpay_language::lang_titles{'statement_merchant_support2'}</p></div>\n";

  ## pre-generate customer section
  my $data_cust = "";
  if (($client{'clientname'} ne "") || ($client{'clientcompany'} ne "")) {
    $data_cust .= "<fieldset style=\"width: 97%; height: 95%; position: relative; border: 1px solid; margin: none; padding: 0px 5px 5px; background: #eeeeee; -moz-border-radius: 10px;\">\n";
    $data_cust .= "<legend style=\"padding: 0px 8px;\"><b>$billpay_language::lang_titles{'legend_customer'}</b></legend>\n";
    $data_cust .= "<p>";
    if ($client{'clientname'} ne "") {
      $data_cust .= "$client{'clientname'}<br>\n";
    }
    if ($client{'clientcompany'} ne "") {
      $data_cust .= "$client{'clientcompany'}<br>\n";
    }
    if ($client{'clientaddr1'} ne "") {
      $data_cust .= "$client{'clientaddr1'}<br>\n";
    }
    if ($client{'clientaddr2'} ne "") {
      $data_cust .= "$client{'clientaddr2'}<br>\n";
    }
    if ($client{'clientcity'} ne "") {
      $data_cust .= "$client{'clientcity'} \n";
    }
    if ($client{'clientstate'} ne "") {
      $data_cust .= "$client{'clientstate'} \n";
    }
    if ($client{'clientzip'} ne "") {
      $data_cust .= "$client{'clientzip'} \n";
    }
    if ($client{'clientcountry'} ne "") {
      $data_cust .= "$client{'clientcountry'}\n";
    }
    if ($client{'clientphone'} ne "") {
      $data_cust .= "<br>$billpay_language::lang_titles{'phone'} $client{'clientphone'}\n";
    }
    if ($client{'clientfax'} ne "") {
      $data_cust .= "<br>$billpay_language::lang_titles{'fax'} $client{'clientfax'}\n";
    }
    $data_cust .= "</p>\n";
    $data_cust .= "</fieldset>\n";
  }
  else {
    $data_cust .= "<fieldset style=\"width: 97%; height: 95%; position: relative; border: 1px solid; margin: none; padding: 0px 5px 5px; background: #eeeeee; -moz-border-radius: 10px;\">\n";
    $data_cust .= "<legend style=\"padding: 0px 8px;\"><b>$billpay_language::lang_titles{'legend_customer'}</b></legend>\n";
    $data_cust .= "<p>$query{'card-name'}<br>\n";
    if ($query{'card-company'} ne "") {
      $data_cust .= "$query{'card-company'}<br>\n";
    }
    $data_cust .= "$query{'card-address1'}<br>\n";
    if ($query{'card-address2'} ne "") {
      $data_cust .= "$query{'card-address2'}<br>\n";
    }
    $data_cust .= "$query{'card-city'} \n";
    $data_cust .= "$query{'card-state'} \n";
    $data_cust .= "$query{'card-zip'} \n";
    $data_cust .= "$query{'card-country'}\n";
    $data_cust .= "</p>\n";
    $data_cust .= "</fieldset>\n";
  }

  ## pre-generate shipping section
  my $data_ship = "";
  if (($invoice{'shipname'} ne "") || ($invoice{'shipcompany'} ne "")) {
    $data_ship .= "<fieldset style=\"width: 97%; height: 95%; position: relative; border: 1px solid; margin: none; padding: 0px 5px 5px; background: #eeeeee; -moz-border-radius: 10px;\">\n";
    $data_ship .= "<legend style=\"padding: 0px 8px;\"><b>$billpay_language::lang_titles{'legend_shipping'}</b></legend>\n";
    $data_ship .= "<p>";
    if ($invoice{'shipname'} ne "") {
      $data_ship .= "$invoice{'shipname'}<br>\n";
    }
    if ($invoice{'shipcompany'} ne "") {
      $data_ship .= "$invoice{'shipcompany'}<br>\n";
    }
    if ($invoice{'shipaddr1'} ne "") {
      $data_ship .= "$invoice{'shipaddr1'}<br>\n";
    }
    if ($invoice{'shipaddr2'} ne "") {
      $data_ship .= "$invoice{'shipaddr2'}<br>\n";
    }
    if ($invoice{'shipcity'} ne "") {
      $data_ship .= "$invoice{'shipcity'} \n";
    }
    if ($invoice{'shipstate'} ne "") {
      $data_ship .= "$invoice{'shipstate'} \n";
    }
    if ($invoice{'shipzip'} ne "") {
      $data_ship .= "$invoice{'shipzip'} \n";
    }
    if ($invoice{'shipcountry'} ne "") {
      $data_ship .= "$invoice{'shipcountry'}\n";
    }
    if ($invoice{'shipphone'} ne "") {
      $data_ship .= "<br>$billpay_language::lang_titles{'phone'} $invoice{'shipphone'}\n";
    }
    if ($invoice{'shipfax'} ne "") {
      $data_ship .= "<br>$billpay_language::lang_titles{'fax'} $invoice{'shipfax'}\n";
    }
    $data_ship .= "</p>\n";
    $data_ship .= "</fieldset>\n";
  }

  ## pre-generate invoice info
  my $data_info = "";
  $data_info .= "<fieldset style=\"width: 97%; height: 95%; position: relative; border: 1px solid; margin: none; padding: 0px 5px 5px; background: #eeeeee; -moz-border-radius: 10px;\">\n";
  $data_info .= "<legend style=\"padding: 0px 8px;\"><b>$billpay_language::lang_titles{'legend_invoiceinfo'}</b></legend>\n";
  $data_info .= "<p>$billpay_language::lang_titles{'invoice_no'} $invoice{'invoice_no'}\n";
  if ($invoice{'account_no'} =~ /\w/) {
    $data_info .= "<br>$billpay_language::lang_titles{'account_no'} $invoice{'account_no'}\n";
  }
  $data_info .= "<br>$billpay_language::lang_titles{'enterdate'} $enter\n";
  $data_info .= "<br>$billpay_language::lang_titles{'expiredate'} $expire\n";
  $data_info .= "<br>$billpay_language::lang_titles{'status'} $invoice{'status'}\n";
  if ($invoice{'orderid'} =~ /\w/) {
    $data_info .= "<br>$billpay_language::lang_titles{'orderid'} $invoice{'orderid'}\n";
  }
  if ($billpay_editutils::feature_list{'billpay_showalias'} eq "yes") {
    $data_info .= "<br>&billpay_language::lang_titles{'alias'} $invoice{'alias'}\n";
  }
  $data_info .= "</p>\n";
  $data_info .= "</fieldset>\n";

  # start generating the actual invoice's HTML 
  $data .= "<br><b>$db_merch_company</b>\n";

  $data .= "<table width=700>\n";
  $data .= "  <tr>\n";
  $data .= "    <td colspan=4><hr width=\"100%\"></td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  if (($data_cust ne "") && ($data_ship eq "")) {
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\">$data_cust</td>\n";
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\">$data_info</td>\n";
  }
  elsif (($data_cust eq "") && ($data_ship ne "")) {
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\">$data_ship</td>\n";
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\">$data_info</td>\n";
  }
  else {
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\"> &nbsp; </td>\n";
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\">$data_info</td>\n";
  }
  $data .= "  </tr>\n";

  if (($data_cust ne "") && ($data_ship ne "")) {
    $data .= "  <tr>\n";
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\">$data_cust</td>\n";
    $data .= "    <td colspan=2 width=\"50%\" height=\"100%\">$data_ship</td>\n";
    $data .= "  </tr>\n";
  }

  $data .= "  <tr>\n";
  $data .= "    <td colspan=4><hr width=\"100%\"></td>\n";
  $data .= "  </tr>\n";
  $data .= "</table>\n";

  my $subtotal = 0;
  my $totalwgt = 0;

  if ($query{'easycart'} == 1) {
    $data .= "<table width=700 class=\"invoice\">\n";
    $data .= "  <tr>\n";
    $data .= "    <td colspan=4 bgcolor=\"#f4f4f4\"><p><b>$billpay_language::lang_titles{'section_productdetails'}</b></p></td>\n";
    $data .= "  </tr>\n";

    $data .= "  <tr>\n";
    if ($billpay_editutils::feature_list{'billpay_showcols'} =~ /item/) {
      $data .= "    <th valign=top align=left width=\"8%\"><p>$billpay_language::lang_titles{'column_item'}</p></th>\n";
    }
    $data .= "    <th valign=top align=left width=\"\"><p>$billpay_language::lang_titles{'column_descr'}</p></th>\n";
    $data .= "    <th valign=top align=left width=\"8%\"><p>$billpay_language::lang_titles{'column_qty'}</p></th>\n";
    $data .= "    <th valign=top align=left width=\"14%\"><p>$billpay_language::lang_titles{'column_cost'}</p></th>\n";

    if (($feature{'billpay_extracols'} =~ /weight/) && ($feature{'billpay_showcols'} =~ /weight/)) {
      $data .= "    <th valign=top align=left><p>$billpay_language::lang_titles{'column_weight'}</p></th>\n";
    }
    if (($feature{'billpay_extracols'} =~ /descra/) && ($feature{'billpay_showcols'} =~ /descra/)) {
      $data .= "    <th valign=top align=left><p>$billpay_language::lang_titles{'column_descra'}</p></th>\n";
    }
    if (($feature{'billpay_extracols'} =~ /descrb/) && ($feature{'billpay_showcols'} =~ /descrb/)) {
      $data .= "    <th valign=top align=left><p>$billpay_language::lang_titles{'column_descrb'}</p></th>\n";
    }
    if (($feature{'billpay_extracols'} =~ /descrc/) && ($feature{'billpay_showcols'} =~ /descrc/)) {
      $data .= "    <th valign=top align=left><p>$billpay_language::lang_titles{'column_descrc'}</p></th>\n";
    }
    $data .= "  </tr>\n";

    for (my $i = 0; $i <= 1000; $i++) {
      if ($query{"item$i"} ne "") {
        $data .= "  <tr>\n";
        if ($billpay_editutils::feature_list{'billpay_showcols'} =~ /item/) {
          $data .= "    <td valign=top><p>$query{\"item$i\"}</p></td>\n";
        }
        $data .= "    <td valign=top><p>$query{\"description$i\"}</p></td>\n";
        $data .= "    <td valign=top><p>$query{\"quantity$i\"}</p></td>\n";
        $data .= "    <td valign=top align=right><p>$query{\"cost$i\"}</p></td>\n";

        if (($feature{'billpay_extracols'} =~ /weight/) && ($feature{'billpay_showcols'} =~ /weight/)) {
          $data .= "    <td valign=top><p>$query{\"weight$i\"}</p></td>\n";
        }
        if (($feature{'billpay_extracols'} =~ /descra/) && ($feature{'billpay_showcols'} =~ /descra/)) {
          $data .= "    <td valign=top><p>$query{\"descra$i\"}</p></td>\n";
        }
        if (($feature{'billpay_extracols'} =~ /descrb/) && ($feature{'billpay_showcols'} =~ /descrb/)) {
          $data .= "    <td valign=top><p>$query{\"descrb$i\"}</p></td>\n";
        }
        if (($feature{'billpay_extracols'} =~ /descrc/) && ($feature{'billpay_showcols'} =~ /descrc/)) {
          $data .= "    <td valign=top><p>$query{\"descrc$i\"}</p></td>\n";
        }
        $data .= "  </tr>\n";

        $subtotal += ($query{"cost$i"} * $query{"quantity$i"});
        $totalwgt += ($query{"weight$i"} * $query{"quantity$i"});
      }
    }

    $data .= "</table>\n";
    if ($feature{'billpay_totalwgt'} == 1) {
      $data .= "<div align=right><p><b>$billpay_language::lang_titles{'totalwgt'}</b> $totalwgt lbs.</p></div>\n";
    }
  }
  else {
    $data .= "<table width=700 class=\"invoice\">\n";
    $data .= "  <tr>\n";
    $data .= "    <td colspan=4 bgcolor=\"#f4f4f4\"><p><b>$billpay_language::lang_titles{'statement_thankyou'}</b></p></td>\n";
    $data .= "  </tr>\n";
    $data .= "</table>\n";
  }

  $data .= "<table width=700>\n";
  $data .= "  <tr>\n";
  $data .= "    <td colspan=4><hr width=\"100%\"></td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <td width=\"77%\" valign=top><fieldset style=\"width: 97%; height: 95%; position: relative; border: 1px solid; margin: none; padding: 0px 5px 5px; background: #eeeeee; -moz-border-radius: 10px;\">\n";
  $data .= "<legend style=\"padding: 0px 8px;\"><b>$billpay_language::lang_titles{'legend_paymentdetails'}</b></legend>\n";
  #$data .= "$billpay_language::lang_titles{'statement_accepts'} $feature{'billpay_cardsallowed'}<br>\n";

  if ($invoice{'balance'} ne "") {
    $invoice{'balance'} = sprintf("%0.02f", $invoice{'balance'});

    $data .= "<p><table border=1 class=\"invoice\">\n";

    if (($invoice{'billcycle'} > 0) && (($invoice{'monthly'} > 0) || ($invoice{'percent'} > 0))) {
      if ($invoice{'percent'} > 0) {
        $data .= "  <tr>\n";
        $data .= "    <th align=right><p>$billpay_language::lang_titles{'percentage'}</p></th>\n";
        $data .= "    <td align=right><p>$invoice{'percent'}\%</p></td>\n";
        $data .= "  </tr>\n";
        if ($invoice{'monthly'} > 0) {
          $data .= "  <tr>\n";
          $data .= "    <th align=right><p>$billpay_language::lang_titles{'installment_min'}</p></th>\n";
          $data .= "    <td align=right><p>$invoice{'monthly'}</p></td>\n";
          $data .= "  </tr>\n";
        }
      }
      else {
        $data .= "  <tr>\n";
        $data .= "    <th align=right><p>$billpay_language::lang_titles{'installment_fee'}</p></th>\n";
        $data .= "    <td align=right><p>$invoice{'monthly'}</p></td>\n";
        $data .= "  </tr>\n";
      }

      if ($invoice{'remnant'} > 0) {
        $data .= "  <tr>\n";
        $data .= "    <th align=right><p>$billpay_language::lang_titles{'payment_remnant'}</p></th>\n";
        $data .= "    <td align=right><p>$invoice{'remnant'}</p></td>\n";
        $data .= "  </tr>\n";
      }
    }

    if ($query{'card-amount'} > 0) {
      $data .= "  <tr>\n";
      $data .= "    <th align=right><p>$billpay_language::lang_titles{'payment_amt'}</p></th>\n";
      $data .= "    <td align=right><p>$query{'card-amount'}</p></td>\n";
      $data .= "  </tr>\n";
    }

    $data .= "  <tr>\n";
    if ($invoice{'balance'} < 0) {
      $data .= "    <th align=right><p>$billpay_language::lang_titles{'balance'}</p></th>\n";
    }
    else {
      $data .= "    <th align=right><p>$billpay_language::lang_titles{'remain_balance'}</p></th>\n";
    }
    $data .= "    <td align=right><p>$invoice{'balance'}</p></td>\n";
    $data .= "  </tr>\n";

    #$data .= "  <tr>\n";
    #$data .= "    <th align=right><p>$billpay_language::lang_titles{'billcycle'}</p></th>\n";
    #$data .= "    <td align=right><p>$invoice{'billcycle'} Month(s)</p></td>\n";
    #$data .= "  </tr>\n";
    $data .= "</table>\n";
  }
  $data .= "<p>";

  $data .= "<table border=0>\n";
  $data .= "  <tr>\n";
  ## start billing info
  $data .= "    <td align=left valign=top><p><b><u>$billpay_language::lang_titles{'section_billinginfo'}</u></b>\n";
  $data .= "<br>$query{'card-name'}\n";
  if ($query{'card-company'} ne "") {
    $data .= "<br>$query{'card-company'}\n";
  }
  $data .= "<br>$query{'card-address1'}\n";
  if ($query{'address2'} ne "") {
    $data .= "<br>$query{'card-address2'}\n";
  }
  $data .= "<br><nobr>$query{'card-city'}, $query{'card-prov'}</nobr>\n";
  $data .= "<br><nobr>$query{'card-state'} $query{'card-zip'} $query{'card-country'}</nobr>\n";
  if ($query{'phone'} ne "") {
    $data .= "<br>$billpay_language::lang_titles{'phone'} $query{'phone'}\n";
  }
  if ($query{'fax'} ne "") {
    $data .= "<br>$billpay_language::lang_titles{'fax'} $query{'fax'}\n";
  }
  if ($query{'email'} ne "") {
    $data .= "<br>$billpay_language::lang_titles{'email'} $query{'email'}\n";
  }
  $data .= "</p></td>\n";
  ## end billing info

## 06/17/11 - this section should not be necessary any more, since we are never collecting shipping info from smart screens
##          - all the shipping address info should be stored with the invoice data at this point.
##          - should be safe to remove this section of code completely...
#  ##  start shipping info
#  $data .= "  <td align=left valign=top><p><b><u>$billpay_language::lang_titles{'section_shippinginfo'}</u></b>\n";
#  $data .= "<br>$query{'shipname'}\n";
#  if ($query{'shipcompany'} ne "") {
#    $data .= "<br>$query{'shipcompany'}\n";
#  }
#  $data .= "<br>$query{'address1'}\n";
#  if ($query{'address2'} ne "") {
#    $data .= "<br>$query{'address2'}\n";
#  }
#  $data .= "<br><nobr> $query{'city'}, $query{'province'}</nobr>\n";
#  $data .= "<br><nobr> $query{'state'} $query{'zip'} $query{'country'}</nobr>\n";
#  if ($query{'shipphone'} ne "") {
#    $data .= "<br>$billpay_language::lang_titles{'phone'} $query{'shipphone'}\n";
#  }
#  if ($query{'shipfax'} ne "") {
#    $data .= "<br>$billpay_language::lang_titles{'fax'} $query{'shipfax'}\n";
#  }
#  if ($query{'shipemail'} ne "") {
#    $data .= "<br>$billpay_language::lang_titles{'email'} $query{'shipemail'}\n";
#  }
#  $data .= "</p></td>\n";
#  ## end shipping info

  $data .= "  </tr>\n";
  $data .= "</table>\n";

  if (($query{'routingnum'} ne "") && ($query{'accountnum'} ne "")) {
    $data .= sprintf("<br>Routing Number: %s\*\*%s\n", substr($query{'routingnum'},0,4), substr($query{'routingnum'},-2,2));
    $data .= sprintf("<br>Account Number: %s\*\*%s\n", substr($query{'accountnum'},0,4), substr($query{'accountnum'},-2,2));
  }
  elsif ($query{'card-number'} ne "") {
    $query{'card-number'} =~ s/[^0-9]//g;
    $query{'card-number'} = substr($query{'card-number'},0,20);
    my ($cardnumber) = $query{'card-number'};
    my $cclength = length($cardnumber);
    my $last4 = substr($cardnumber,-4,4);
    $cardnumber =~ s/./X/g;
    $query{'card-number'} = substr($cardnumber,0,$cclength-4) . $last4;
    $query{'card-exp'} =~ s/\d/X/g;

    $data .= "<br>$billpay_language::lang_titles{'cardnumber'} $query{'card-number'}\n";
    $data .= "<br>$billpay_language::lang_titles{'exp'} $query{'card-exp'}\n";
    $data .= "<br>$billpay_language::lang_titles{'authcode'} $query{'auth-code'}\n";
  }

  $data .= "</p>\n";
  $data .= "</fieldset></td>\n";

  $subtotal = sprintf("%0.02f", $subtotal);

  $data .= "    <td valign=top><table width=\"100%\" class=\"invoice\">\n";
  if ($subtotal > 0) {
    $data .= "  <tr>\n";
    $data .= "    <th width=\"50%\" align=right nowrap><p>$billpay_language::lang_titles{'subtotal'}</p></th>\n";
    $data .= "    <td width=\"50%\" align=right><p>$subtotal</p></td>\n";
    $data .= "  </tr>\n";
  }
  if ($invoice{'shipping'} > 0) {
    $data .= "  <tr>\n";
    $data .= "    <th align=right nowrap><p>$billpay_language::lang_titles{'shipping'}</p></th>\n";
    $data .= "    <td align=right><p>$invoice{'shipping'}</p></td>\n";
    $data .= "  </tr>\n";
  }
  if ($invoice{'handling'} > 0) {
    $data .= "  <tr>\n";
    $data .= "    <th align=right nowrap><p>$billpay_language::lang_titles{'handling'}</p></th>\n";
    $data .= "    <td align=right><p>$invoice{'handling'}</p></td>\n";
    $data .= "  </tr>\n";
  }
  if ($invoice{'discount'} > 0) {
    $data .= "  <tr>\n";
    $data .= "    <th align=right nowrap><p>$billpay_language::lang_titles{'discount'}</p></th>\n";
    $data .= "    <td align=right><p>$invoice{'discount'}</p></td>\n";
    $data .= "  </tr>\n";
  }
  if ($invoice{'tax'} > 0) {
    $data .= "  <tr>\n";
    $data .= "    <th align=right nowrap><p>$billpay_language::lang_titles{'tax'}</p></th>\n";
    $data .= "    <td align=right><p>$invoice{'tax'}</p></td>\n";
    $data .= "  </tr>\n";
  }
  $data .= "  <tr>\n";
  $data .= "    <th align=right nowrap><p>$billpay_language::lang_titles{'amount'}</p></th>\n";
  $data .= "    <td align=right><p>$invoice{'amount'}</p></td>\n";
  $data .= "  </tr>\n";
  $data .= "</table></td>\n";
  $data .= "  </tr>\n";
  $data .= "</table>\n";

  $data .= "<table width=700>\n";
  $data .= "  <tr>\n";
  $data .= "    <td colspan=2><hr width=\"100%\"></td>\n";
  $data .= "  </tr>\n";

  if ($invoice{'datalink_url'} ne "") {
    if ($billpay_editutils::feature_list{'billpay_datalink_type'} =~ /^(post|get)$/) {
      # use datalink form post/get format
      $data .= "  <tr>\n";
      $data .= "    <td align=left><p><b>$billpay_language::lang_titles{'datalink'}</b></p></td>\n";
      $data .= "    <td valign=top align=left><p><form name=\"datalink\" action=\"$invoice{'datalink_url'}\" method=\"$billpay_editutils::feature_list{'billpay_datalink_type'}\" target=\"_blank\">\n";
      if ($invoice{'datalink_pairs'} ne "") {
        my @pairs = split(/\&/, $invoice{'datalink_pairs'});
        for (my $i = 0; $i <= $#pairs; $i++) {
          my $pair = $pairs[$i];
          $pair =~ s/\[client_([a-zA-Z0-9\-\_]*)\]/$client{$1}/g;
          $pair =~ s/\[invoice_([a-zA-Z0-9\-\_]*)\]/$invoice{$1}/g;
          $pair =~ s/\[query_([a-zA-Z0-9\-\_]*)\]/$query{$1}/g;
          my ($name, $value) = split(/\=/, $pair, 2);
          $data .= "<input type=hidden name=\"$name\" value=\"$value\">\n";
        }
      }
      $data .= "<input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_datalink'}\"></form></p></td>\n";
      $data .= "  </tr>\n";
    }
    else {
      # use datalink link format
      my $url = $invoice{'datalink_url'};
      if ($invoice{'datalink_pairs'} ne "") {
        $url .= "\?" . $invoice{'datalink_pairs'};
      }
      $url =~ s/\[client_([a-zA-Z0-9\-\_]*)\]/$client{$1}/g;
      $url =~ s/\[invoice_([a-zA-Z0-9\-\_]*)\]/$invoice{$1}/g;
      $url =~ s/\[query_([a-zA-Z0-9\-\_]*)\]/$query{$1}/g;

      $data .= "  <tr>\n";
      $data .= "    <td align=left><p><b>$billpay_language::lang_titles{'datalink'}</b></p></td>\n";
      $data .= "    <td valign=top align=left><p><a href=\"$url\" target=\"_blank\">$billpay_language::lang_titles{'link_datalink'}</a></p></td>\n";
      $data .= "  </tr>\n";
    }
  }

  if ($invoice{'public_notes'} =~ /\w/) {
    $data .= "  <tr>\n";
    $data .= "    <td align=left><p><b>$billpay_language::lang_titles{'public_notes'}</b></p></td>\n";
    $data .= "    <td valign=top align=left><p>$invoice{'public_notes'}</p></td>\n";
    $data .= "  </tr>\n";
  }

  $data .= "</table>\n";

  $data .= "<p><form><input type=button class=\"button\" name=\"print_button\" value=\"Print Page\" onclick=\"window.print();\"></form></p>\n";
  return $data;
}

sub modulus10 { # used to test check routing numbers
  my($ABAtest) = @_;
  my @digits = split('',$ABAtest);
  my ($modtest);
  my $sum = $digits[0] * 3 + $digits[1] * 7 + $digits[2] * 1 + $digits[3] * 3 + $digits[4] * 7 + $digits[5] * 1 + $digits[6] * 3 + $digits[7] * 7;
  my $check = 10 - ($sum % 10);
  $check = substr($check,-1);
  my $checkdig = substr($ABAtest,-1);
  if ($check eq $checkdig) {
    $modtest = "PASS";
  }
  else {
    $modtest = "FAIL";
  }
  return $modtest;
}

sub record_history {
  my ($username, $profileid, $action, $descr) = @_;

  if ($username eq "") {
    $username = $ENV{'REMOTE_USER'};
  }
  else {
    $username = substr($username,0,255);
  }

  $action = substr($action,0,20);
  $descr = substr($descr,0,200);

  my $ipaddress = $ENV{'REMOTE_ADDR'};

  my @now = gmtime(time);
  my $trans_time = sprintf("%04d%02d%02d%02d%02d%02d", $now[5], $now[4], $now[3], $now[2], $now[1], $now[0]);
  my $entryid = sprintf("%04d%02d%02d%02d%02d%02d%05d", $now[5], $now[4], $now[3], $now[2], $now[1], $now[0], $$);

  my $sth = $billpay_editutils::dbh->prepare(q{
      INSERT INTO history2
      (entryid, ipaddress, trans_time, username, profileid, action, descr)
      VALUES (?,?,?,?,?,?,?)
    }) or die "Cannot prepare: $DBI::errstr";
  $sth->execute("$entryid", "$ipaddress", "$trans_time", "$username", "$profileid", "$action", "$descr") or die "Cannot execute: $DBI::errstr";
  $sth->finish;

  return;
}

sub list_invoice_merchant_hash {
  # produces a hash of all merchant usernames of uploaded invoices for a specific username (results are based on status given)
  my ($status) = @_;

  my %list;
  my ($db_merchant, $db_merch_company);

  my $dbh_pnpmisc = &miscutils::dbhconnect("pnpmisc");

  my $sth = $billpay_editutils::dbh->prepare(q{
      SELECT merchant
      FROM bills2
      WHERE username=?
      AND status=?
    }) or die "Cannot do: $DBI::errstr";
  $sth->execute("$ENV{'REMOTE_USER'}", "$status") or die "Cannot execute: $DBI::errstr";
  my $rv = $sth->bind_columns(undef,\($db_merchant));
  while($sth->fetch) {
    if (($db_merchant ne "") && ($list{"$db_merchant"} eq "")) {
      # get merchant's company name
      my $sth2 = $dbh_pnpmisc->prepare(q{
          SELECT company
          FROM customers
          WHERE username=?
        }) or die "Cannot prepare: $DBI::errstr";
      $sth2->execute("$db_merchant") or die "Cannot execute: $DBI::errstr";
      ($db_merch_company) = $sth2->fetchrow;
      $sth2->finish;

      if ($db_merch_company ne "") {
        $list{"$db_merchant"} = "$db_merch_company";
      }
      else {
        $list{"$db_merchant"} = "\[Company ID: $db_merchant\]";
      }
    }
  }
  $sth->finish;

  $dbh_pnpmisc->disconnect;

  return %list;
}

sub list_autopay_merchant_hash {
  # produces a hash of all merchant usernames of auto payment profiles for a specific username (results are based on status given)
  my ($status) = @_;

  my %list;
  my ($db_merchant);

  my $dbh_pnpmisc = &miscutils::dbhconnect("pnpmisc");

  my $sth = $billpay_editutils::dbh->prepare(q{
      SELECT merchant
      FROM autopay2
      WHERE username=?
      AND status=?
    }) or die "Cannot do: $DBI::errstr";
  $sth->execute("$ENV{'REMOTE_USER'}", "$status") or die "Cannot execute: $DBI::errstr";
  my $rv = $sth->bind_columns(undef,\($db_merchant));
  while($sth->fetch) {
    if (($db_merchant ne "") && ($list{"$db_merchant"} eq "")) {
      # get merchant's company name
      my $sth2 = $dbh_pnpmisc->prepare(q{
          SELECT company
          FROM customers
          WHERE username=?
        }) or die "Cannot prepare: $DBI::errstr";
      $sth2->execute("$db_merchant") or die "Cannot execute: $DBI::errstr";
      my ($db_merch_company) = $sth2->fetchrow;
      $sth2->finish;

      if ($db_merch_company ne "") {
        $list{"$db_merchant"} = "$db_merch_company";
      }
      else {
        $list{"$db_merchant"} = "\[Company ID: $db_merchant\]";
      }
    }
  }
  $sth->finish;

  $dbh_pnpmisc->disconnect;

  return %list;
}

sub autopay_bills_form {
  my %query = @_;
  my ($data, $data1, $data2);

  # build form for new auto payments
  $data1 .= "<form method=post action=\"$billpay_editutils::path_edit\">\n";
  $data1 .= "<input type=hidden name=\"function\" value=\"update_autopay_profile\">\n";
  $data1 .= "<input type=hidden name=\"status\" value=\"active\">\n";

  $data1 .= "<table border=0 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  $data1 .= "  <tr>\n";
  $data1 .= "    <td bgcolor=\"#f4f4f4\" valign=top width=170><p><b>$billpay_language::lang_titles{'menu_activate_autopay'}</b></p></td>\n";
  $data1 .= "    <td valign=top>\n";
  $data1 .= "<table border=0 cellspacing=0 cellpadding=2>\n";
  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top><p><b>$billpay_language::lang_titles{'statement_select_company'}</b></p></td>\n";
  $data1 .= "  </tr>\n";

  my %invoice_merchants = &list_invoice_merchant_hash("open");
  my $invoice_cnt = 0;

  foreach my $key (sort keys %invoice_merchants) {
    $data1 .= "  <tr>\n";
    $data1 .= "    <td valign=top><p><input type=radio name=\"merchant\" value=\"$key\"";
    if ($invoice_cnt == 0) { $data1 .= " checked"; }
    $data1 .= "> $invoice_merchants{$key}</p></td>\n";
    $data1 .= "  </tr>\n";
    $invoice_cnt = $invoice_cnt + 1;
  }
  if ($invoice_cnt == 0) {
    $data1 .= "  <tr>\n";
    $data1 .= "    <td><p>$billpay_language::lang_titles{'statement_noopenbills'}\n";
    $data1 .= "<br>$billpay_language::lang_titles{'statement_autopay_usage'}</p></td>\n";
    $data1 .= "  </tr>\n";
  }

  $data1 .= "</table></td>\n";
  $data1 .= "  </tr>\n";

  my %profiles = &list_bill_profile_hash("active_only", "");
  my $profiles_cnt = 0;

  $data1 .= "  <tr>\n";
  $data1 .= "    <td bgcolor=\"#f4f4f4\" valign=top><p>&nbsp; </p></td>\n";
  $data1 .= "    <td>\n";
  $data1 .= "<table border=0 cellspacing=0 cellpadding=2>\n";
  $data1 .= "  <tr>\n";
  $data1 .= "    <td valign=top><p><b>$billpay_language::lang_titles{'statement_select_paymethod'}</b></p></td>\n";
  $data1 .= "  </tr>\n";

  foreach my $key (sort keys %profiles) {
    if ($profiles{"$key"} ne "") {
      $data1 .= "  <tr>\n";
      $data1 .= "    <td valign=top><p><input type=radio name=\"profileid\" value=\"$key\"";
      if ($profiles_cnt == 0) { $data1 .= " checked"; }
      $data1 .= "> $profiles{$key}</p></td>\n";
      $data1 .= "  </tr>\n";
      $profiles_cnt = $profiles_cnt + 1;
    }
  }

  if ($profiles_cnt == 0) {
    $data1 .= "  <tr>\n";
    $data1 .= "    <td><p>$billpay_language::lang_titles{'statement_nobillprofiles1'}</p></td>\n";
    $data1 .= "  </tr>\n";
  }

  $data1 .= "</table></td>\n";
  $data1 .= "  </tr>\n";

  if (($profiles_cnt > 0) && ($invoice_cnt > 0)) {
    $data1 .= "  <tr>\n";
    $data1 .= "    <td bgcolor=\"#f4f4f4\" valign=top><p>&nbsp; </p></td>\n";
    $data1 .= "    <td><input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_activate_autopay'}\"></td></form>\n";
    $data1 .= "  </tr>\n";
  }
  else {
    $data1 .= "</form>\n";

    $data1 .= "  <tr>\n";
    $data1 .= "    <td bgcolor=\"#f4f4f4\" valign=top><p>&nbsp; </p></td>\n";
    $data1 .= "    <td align=left><form method=post action=\"$billpay_editutils::path_edit\">\n";
    $data1 .= "      <input type=hidden name=\"function\" value=\"add_new_bill_profile_form\">\n";
    $data1 .= "      <input type=submit class=\"button\" value==\"$billpay_language::lang_titles{'button_add_billing'}\n";
    $data1 .= "    </td></form>\n";
    $data1 .= "  </tr>\n";
  }
  $data1 .= "</table>\n";

  # build form for removing auto-payment profiles
  $data2 .= "<form method=post action=\"$billpay_editutils::path_edit\">\n";
  $data2 .= "<input type=hidden name=\"function\" value=\"delete_autopay_profile\">\n";
  $data2 .= "<input type=hidden name=\"status\" value=\"hold\">\n";

  $data2 .= "<table border=0 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  $data2 .= "<tr>\n";
  $data2 .= "  <td valign=top bgcolor=\"#f4f4f4\" width=170>&nbsp;</td>\n";
  $data2 .= "  <td><hr width=\"80%\"></td>\n";
  $data2 .= "</tr>\n";

  $data2 .= "  <tr>\n";
  $data2 .= "    <td valign=top bgcolor=\"#f4f4f4\" width=170><p><b>$billpay_language::lang_titles{'menu_delete_autopay'}</b></p></td>\n";
  $data2 .= "    <td valign=top>";
  $data2 .= "<table border=0 cellspacing=0 cellpadding=2>\n";
  $data2 .= "  <tr>\n";
  $data2 .= "    <td valign=top><p><b>$billpay_language::lang_titles{'statement_select_autopay'}</b></p></td>\n";
  $data2 .= "  </tr>\n";

  my %autopay_merchants = &list_autopay_merchant_hash("active");
  my $autopay_cnt = 0;

  foreach my $key (sort keys %autopay_merchants) {
    if ($autopay_merchants{"$key"} ne "") {
      $data2 .= "  <tr>\n";
      $data2 .= "    <td valign=top><p><input type=radio name=\"merchant\" value=\"$key\"";
      if ($autopay_cnt == 0) { $data2 .= " checked"; }
      $data2 .= "> $autopay_merchants{$key}</p></td>\n";
      $data2 .= "  </tr>\n";
      $autopay_cnt = $autopay_cnt + 1;
    }
  }

  if ($autopay_cnt == 0) {
    $data2 .= "  <tr>\n";
    $data2 .= "    <td><p>$billpay_language::lang_titles{'statement_noautopay'}</p></td></form>\n";
    $data2 .= "  </tr>\n";
  }

  $data2 .= "</table></td>\n";
  $data2 .= "  </tr>\n";

  if ($autopay_cnt > 0) {
    $data2 .= "  <tr>\n";
    $data2 .= "    <td bgcolor=\"#f4f4f4\" valign=top><p>&nbsp; </p></td>\n";
    $data2 .= "    <td><input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_delete_autopay'}\"></td></form>\n";
    $data2 .= "  </tr>\n";
  }
  $data2 .= "</table>\n";

  # now build the entire layout here
  $data .= "<table border=0 cellspacing=0 cellpadding=2 width=\"100%\">\n";
  $data .= "  <tr>\n";
  $data .= "    <td colspan=2><h1><a href=\"$billpay_editutils::path_index\">$billpay_language::lang_titles{'service_title'}</a> / $billpay_language::lang_titles{'service_subtitle_autopay'}</h1></td>\n";
  $data .= "  </tr>\n";

#  $data .= "  <tr>\n";
#  $data .= "    <td colspan=2><p>$billpay_language::lang_titles{'statement_enter_profile'}</p></td>\n";
#  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <td valign=top>$data1\n";
  $data .= "$data2</td>\n";
  $data .= "  </tr>\n";

#  $data .= "  <tr>\n";
#  $data .= "    <td colspan=2 align=center><form method=post action=\"$billpay_editutils::path_edit\">\n";
#  $data .= "<input type=hidden name=\"function\" value=\"edit_cust_profile_form\">\n";
#  $data .= "<input type=submit class=\"button\" value=\"$billpay_language::lang_titles{'button_editcontact'}\"></td></form>\n";
#  $data .= "  </tr>\n";
  $data .= "</table>\n";

  return $data;
}

sub update_autopay_profile {
  my %query = @_;

  my $data;

  # check for profile existance
  my $sth1 = $billpay_editutils::dbh->prepare(q{
      SELECT profileid
      FROM autopay2
      WHERE username=?
      AND merchant=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth1->execute("$ENV{'REMOTE_USER'}", "$query{'merchant'}") or die "Cannot execute: $DBI::errstr";
  my ($db_profileid) = $sth1->fetchrow;
  $sth1->finish;

  if ($db_profileid eq "") {
    # if no match was found, allow the insert to happen
    my $sth2 = $billpay_editutils::dbh->prepare(q{
        INSERT INTO autopay2
        (merchant, username, profileid, status)
        VALUES (?,?,?,?)
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2->execute("$query{'merchant'}", "$ENV{'REMOTE_USER'}", "$query{'profileid'}", "$query{'status'}") or die "Cannot execute: $DBI::errstr";
    $sth2->finish;

    &record_history("$ENV{'REMOTE_USER'}", "$query{'profileid'}", "add_autopay", "Auto-Pay Profile Added - $query{'merchant'}");

    $data .= "<p>$billpay_language::lang_titles{'statement_autopay_added'}</p>\n";
  }
  else {
    # if match was found, allow the update to happen
    my $sth2 = $billpay_editutils::dbh->prepare(q{
        UPDATE autopay2
        SET merchant=?, username=?, profileid=?, status=?
        WHERE username=?
        AND merchant=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2->execute("$query{'merchant'}", "$ENV{'REMOTE_USER'}", "$query{'profileid'}", "$query{'status'}", "$ENV{'REMOTE_USER'}", "$query{'merchant'}") or die "Cannot execute: $DBI::errstr";
    $sth2->finish;

    &record_history("$ENV{'REMOTE_USER'}", "$query{'profileid'}", "update_autopay", "Auto-Pay Profile Updated - $query{'merchant'}");

    $data .= "<p>$billpay_language::lang_titles{'statement_autopay_updated'}</p>\n";
  }

  $data .= "<p><a href=\"$billpay_editutils::path_edit\?function=autopay_bills_form\">$billpay_language::lang_titles{'link_autopaymenu'}</a></p>\n";

  return $data;
}

sub delete_autopay_profile {
  my %query = @_;

  my $data;

  # check for profile existance
  my $sth = $billpay_editutils::dbh->prepare(q{
      DELETE FROM autopay2
      WHERE username=?
      AND merchant=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth->execute("$ENV{'REMOTE_USER'}", "$query{'merchant'}") or die "Cannot execute: $DBI::errstr";
  $sth->finish;

  &record_history("$ENV{'REMOTE_USER'}", "$query{'profileid'}", "delete_autopay", "Auto-Pay Profile Deleted - $query{'merchant'}");

  $data .= "<p>$billpay_language::lang_titles{'statement_autopay_deleted'}</p>\n";

  $data .= "<p><a href=\"$billpay_editutils::path_edit\?function=autopay_bills_form\">$billpay_language::lang_titles{'link_autopaymenu'}</a></p>\n";

  return $data;
}


1;
