#!/bin/env perl

# Last Updated: 07/26/12

require 5.001;
$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use CGI qw/standard escapeHTML unescapeHTML/;
use DBI;
use miscutils;
use rsautils;
use mckutils_strict;
use constants qw(%countries %USstates %USterritories %CNprovinces %USCNprov);
use PlugNPay::CardData;
use PlugNPay::Logging::DataLog;
use strict;

my %query = ();
my $query = new CGI;

my @array = $query->param;
foreach my $var (@array) {
  $var =~ s/[^a-zA-Z0-9\_\-]//g;
  $query{$var} = &CGI::escapeHTML($query->param($var));
}

if (($ENV{'HTTP_X_FORWARDED_SERVER'} ne "") && ($ENV{'HTTP_X_FORWARDED_FOR'} ne "")) {
  $ENV{'HTTP_HOST'} = (split(/\,/,$ENV{'HTTP_X_FORWARDED_HOST'}))[0];
  $ENV{'SERVER_NAME'} = (split(/\,/,$ENV{'HTTP_X_FORWARDED_SERVER'}))[0];
}

# initialize attendant lib & create SQL DB handle
my $dbh = &miscutils::dbhconnect("pnppaydata");

my %countries = %constants::countries;
my %USstates = %constants::USstates;
my %USterritories = %constants::USterritories;
my %CNprovinces = %constants::CNprovinces;
my %USCNprov = %constants::USCNprov;

# create list of database field names to update
my @editfields = ("name","company","addr1","addr2","city","state","zip","country","email","phone","fax","routingnum","accountnum","commcardtype");

print "Content-Type: text/html\n\n";

if ($query{'mode'} eq "update") {
  &update_profile(%query);
}
else{
#elsif ($query{'mode'} eq "edit") {
  &edit_profile(%query);
}

&dbh_disconnect();
exit;

sub dbh_disconnect {
  $dbh->disconnect;
  return;
}

sub response_page {
  my ($message, $page_title) = @_;

  if ($page_title eq "") {
    $page_title = "Attendant";
  }

  &html_head("$page_title");

  print "<table>\n";
  print "  <tr>\n";
  print "    <td align=center colspan=2>$message</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<p><form><input type=\"button\" value=\"Close\" onClick=\"closeresults()\;\"></form>\n";

  &html_tail();
  return;
}

sub update_profile {
  my %query = @_;

  # see if username exists
  my $sth0 = $dbh->prepare(qq{
      select username, cardnumber
      from customer
      where username=?
    }) or die "Can't prepare: $DBI::errstr";
  $sth0->execute("$ENV{'REMOTE_USER'}") or die "Can't execute: $DBI::errstr";
  my ($test,$cardtest) = $sth0->fetchrow;
  $sth0->finish;

  # should it not exist, create a blank profile for the username
  if ($test ne "$ENV{'REMOTE_USER'}") {
    my $sth1 = $dbh->prepare(qq{
        insert into customer
        (username, status)
        values (?,?)
      }) or die "Can't prepare: $DBI::errstr";
    $sth1->execute("$ENV{'REMOTE_USER'}","") or die "Can't execute: $DBI::errstr";
    $sth1->finish;
  }

  # now complete profile update normally

  $query{'routingnum'} =~ s/[^0-9]//g; # ACH routing number filter
  $query{'accountnum'} =~ s/[^0-9]//g; # ACH account number filter

  if ((($query{'routingnum'} ne "") || ($query{'accountnum'} ne "")) || ($cardtest !~ /\*\*/)) {
    $query{'cardnumber'} = sprintf("%s %s", $query{'routingnum'}, $query{'accountnum'});

    if (length($query{'accountnum'}) < 5) {
      $query{'error_message'} = "Account Number has too few characters.";
      &edit_profile(%query);
      return "failure";
    }
    my $ABAtest = $query{'routingnum'};
    $ABAtest =~ s/[^0-9]//g;
    my $luhntest = &modulus10($ABAtest);
    if ((length($query{'routingnum'}) != 9) || ($luhntest eq "FAIL")){
      $query{'error_message'} = "Invalid Routing Number.  Please check and re-enter.";
      &edit_profile(%query);
      return "failure";
    }

    # update ACH payment data, if new data is provided
    my $cardnumber = $query{'cardnumber'};
    $cardnumber =~ s/[^0-9\ ]//g;
    my $cardlength = length($cardnumber);

    if (($cardnumber =~ /^\d{9} \d{5,}$/) && ($cardlength >= 15)) {
      my ($enccardnumber, $length) = &rsautils::rsa_encrypt_card($query{'cardnumber'},"/home/p/pay1/pwfiles/keys/key");
      $cardnumber = substr($cardnumber,0,4) . "**" . substr($cardnumber,-2,2);

      my $cd = new PlugNPay::CardData();
      eval {
        $cd->insertRecurringCardData({customer => $ENV{'REMOTE_USER'}, username => 'pnppaydata', cardData => $enccardnumber});
      };
      if ($@) {
        my $datalog = new PlugNPay::Logging::DataLog({'collection' => 'commission_change'});
        $datalog->log({
          'error' => "Failed insertRecurringCardData, caused by: $@",
          'caller' => $ENV{'REMOTE_USER'},
          'sub_function' => 'update_profile',
          'customer' => $ENV{'REMOTE_USER'},
          'username' => 'pnppaydata'
        });
      }

      my $sth = $dbh->prepare(qq{
          update customer
          set enccardnumber=?,length=?,cardnumber=?
          where username=?
        }) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$enccardnumber","$length","$cardnumber","$ENV{'REMOTE_USER'}") or die "Can't execute: $DBI::errstr";
      $sth->finish;
    }
  }

  my $updatestring = "update customer set ";
  my @placeholder;
 
  my $message; 
  foreach my $var (@editfields) {
    if (($var !~ /^(username|routingnum|accountnum)$/) && ($var ne "")) {
      my $value;
      $updatestring .= "$var=?,";

      $value = $query{"$var"};
      $value =~ s/[^_0-9a-zA-Z\-\@\.\ ]//g; # remove all non-allowed characters

      push(@placeholder, "$value");
    }
  }

  chop $updatestring;
  $updatestring .= " where username=?";
  push(@placeholder, "$ENV{'REMOTE_USER'}");

  my $sth = $dbh->prepare(qq{ $updatestring }) or die "Can't prepare: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  $sth->finish;

  # write to service history
  my $action = "Customer Update";
  my $reason = "User updated profile info from $ENV{'REMOTE_ADDR'}, confirmation sent to PnP staff";

  my $now = time();
  my $sth_history = $dbh->prepare(qq{
      insert into history
      (trans_time,username,action,descr)
      values (?,?,?,?)
    }) or die "Can't prepare: $DBI::errstr";
  $sth_history->execute("$now", "$ENV{'REMOTE_USER'}", "$action", "$reason") or die "Can't execute: $DBI::errstr";
  $sth_history->finish;

  &email2(%query);

  &display_profile(%query);

  #if ($chkfields[7] ne $temp) {
  #  $query{'subject'} = "Plug and Pay - Email Change";
  #  $query{'emailmessage'} = "Username: $ENV{'REMOTE_USER'}\nEmail Address: $query{'email'}\n\n";
  #  &email(%query);
  #}

  return;
}

sub email2 {
  my %query = @_;

  my $emailmessage = "";

  #open(MAIL1,"| /usr/lib/sendmail -t");
  $emailmessage .= "To: accounting\@plugnpay.com\n";
  $emailmessage .= "From: trash\@plugnpay.com\n";
  $emailmessage .= "Subject: pnppaydata - Commission Payout Info Update Confirmation\n";
  $emailmessage .= "\n";
  $emailmessage .= "\n";
  $emailmessage .= "The following account has successfully updated their commission payout info online.\n\n";
  $emailmessage .= "Username: $ENV{'REMOTE_USER'}\n\n";

  $emailmessage .= $query{'email-message'};
  $emailmessage .= "\n";

  my %errordump = ("merchant","pnppaydata", "username","$ENV{'REMOTE_USER'}");
  my ($junk1,$junk2,$message_time) = &miscutils::genorderid();
  my $dbh_email = &miscutils::dbhconnect("emailconf");
  my $sth_email = $dbh_email->prepare(qq{
      insert into message_que2
      (message_time,username,status,format,body)
      values (?,?,?,?,?)
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%errordump);
  $sth_email->execute("$message_time","pnppaydata","pending","text","$emailmessage") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%errordump);
  $sth_email->finish;
  $dbh_email->disconnect;

  return;
}

sub edit_profile {
  my %query = @_;

  my %selected;
  my $existed = 1;

  # query the customer profile data
  my %data = &get_profile_info("$ENV{'REMOTE_USER'}");
  foreach my $key (sort keys %data) {
    $query{"$key"} = $data{"$key"};
  }

  if ($query{'username'} ne "$ENV{'REMOTE_USER'}") {
    $existed = 0;
    my $dbh2 = &miscutils::dbhconnect("pnpmisc");
    my $sth = $dbh2->prepare(qq{
        select name,company,addr1,addr2,city,state,zip,country,email,tel,fax,merchemail
        from customers
        where username=?
      }) or die "Can't do: $DBI::errstr";
    $sth->execute("$ENV{'REMOTE_USER'}") or die "Can't execute: $DBI::errstr";
    ($query{'name'}, $query{'company'}, $query{'addr1'}, $query{'addr2'}, $query{'city'}, $query{'state'}, $query{'zip'}, $query{'country'}, $query{'email'}, $query{'phone'}, $query{'fax'}, $query{'email'}) = $sth->fetchrow;
    $sth->finish;
    $dbh2->disconnect;
  }

  my ($temp_routingnum, $temp_accountnum);

  my $cd = new PlugNPay::CardData();
  my $ecrypted_card_data = '';
  eval {
    $ecrypted_card_data = $cd->getRecurringCardData({customer => $ENV{'REMOTE_USER'}, username => 'pnppaydata'});
  };
  if (!$@) {
    $query->{'enccardnumber'} = $ecrypted_card_data;
  }

  if ($query{'enccardnumber'} ne "") {
    # decrypt card on file & see if its an Credit Card or ACH/eCheck account.
    my $temp_cc = &rsautils::rsa_decrypt_file($query{'enccardnumber'},$query{'length'},"print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");
    if ($temp_cc =~ /\W/) {
      ($temp_routingnum, $temp_accountnum) = split(/ /, $temp_cc, 2);

      # Account number filter
      $temp_accountnum =~ s/[^0-9]//g;
      $temp_accountnum = substr($temp_accountnum,0,20);
      my ($accountnum) = $temp_accountnum;
      my $acctlength = length($accountnum);
      my $last4 = substr($accountnum,-4,4);
      $accountnum =~ s/./X/g;
      $temp_accountnum = substr($accountnum,0,$acctlength-4) . $last4;

      # Routing number filter 
      $temp_routingnum =~ s/[^0-9]//g;
      $temp_routingnum = substr($temp_routingnum,0,9);
      my ($routingnum) = $temp_routingnum;
      my $routlength = length($routingnum);
      my $first4 = substr($routingnum,0,4);
      $routingnum =~ s/./X/g;
      $temp_routingnum = $first4 . substr($routingnum,4,$routlength-4);
    }
    $temp_cc = ""; # destroy decrypted card info, since its no longer needed.
  }

  delete $query{'enccardnumber'};
  delete $query{'length'};

  # now build the entire page here
  &html_head("Commission Payout Information");

  if ($query{'error_message'} ne "") {
    print "<font class=\"badcolor\">$query{'error_message'}</font>\n";
  }
  elsif ($query{'response_message'} ne "") {
    print "<font class=\"goodcolor\">$query{'response_message'}</font>\n";
  }

  if ($existed == 0) {
    print "<p><font class=\"badcolor\">No ACH account info on file.<br>Please take a moment to update your information.</font></p>\n";
  }

  print "<form method=\"post\" action=\"$ENV{'SCRIPT_NAME'}\" name=\"profile_form\">\n";
  print "<input type=\"hidden\" name=\"mode\" value=\"update\">\n";

  print "<table border=\"0\" cellspacing=\"0\" cellpadding=\"2\">\n";
  #print "  <tr>\n";
  #print "    <td colspan=\"2\"><h1>Commission Payout Information</h1></td>\n";
  #print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"2\">";
  print "Please review &amp; edit the information you wish changed.\n";
  print "<br>Click on the \"Submit\" button when finished.\n";
  print "<p>Required fields are marked with a <b>*</b>.</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=\"top\">\n";

  # build contact information section
  print "<table border=\"0\" cellspacing=\"0\" cellpadding=\"2\">\n";
  print "  <tr>\n";
  print "    <td colspan=\"2\" bgcolor=\"#f4f4f4\"><b>Billing Address Information</b></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">Name: *</td>\n";
  print "    <td valign=\"top\"><input type=\"text\" name=\"name\" value=\"$query{'name'}\" size=\"20\" maxlength=\"39\" required></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">Company: </td>\n";
  print "    <td valign=\"top\"><input type=\"text\" name=\"company\" value=\"$query{'company'}\" size=\"20\" maxlength=\"39\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">Address Line 1: *</td>\n";
  print "    <td valign=\"top\"><input type=\"text\" name=\"addr1\" value=\"$query{'addr1'}\" size=\"20\" maxlength=\"39\" required></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">Address Line 2: </td>\n";
  print "    <td valign=\"top\"><input type=\"text\" name=\"addr2\" value=\"$query{'addr2'}\" size=\"20\" maxlength=\"39\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">City: *</td>\n";
  print "    <td valign=\"top\"><input type=\"text\" name=\"city\" value=\"$query{'city'}\" size=\"20\" maxlength=\"39\" required></td>\n";
  print "  </tr>\n";

  $query{'state'} = uc("$query{'state'}");
  $selected{"$query{'state'}"} = "selected";

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">State: *</td>\n";
  print "    <td valign=\"top\"><select name=\"state\" required>\n";
  print "<option value=\"\">Select Your State/Province/Territory</option>\n";
  foreach my $key (&sort_hash(\%USstates)) {
    print "<option value=\"$key\" $selected{$key}>$USstates{$key}</option>\n";
  }
  foreach my $key (&sort_hash(\%USterritories)) {
    print "<option value=\"$key\" $selected{$key}>$USterritories{$key}</option>\n";
  }
  foreach my $key (&sort_hash(\%USCNprov)) {
    print "<option value=\"$key\" $selected{$key}>$USCNprov{$key}</option>\n";
  }
  foreach my $key (&sort_hash(\%CNprovinces)) {
    print "<option value=\"$key\" $selected{$key}>$CNprovinces{$key}</option>\n";
  }
  print "</select></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">Zipcode: *</td>\n";
  print "    <td valign=\"top\"><input type=\"text\" name=\"zip\" value=\"$query{'zip'}\" size=\"20\" maxlength=\"14\" required></td>\n";
  print "  </tr>\n";

  if ($query{'country'} eq "") {
    $query{'country'} = "US";
  }
  $selected{"$query{'country'}"} = "selected";

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">Country: *</td>\n";
  print "    <td valign=\"top\"><select name=\"country\" required>\n";
  foreach my $key (&sort_hash(\%countries)) {
    print "<option value=\"$key\" $selected{$key}>$countries{$key}</option>\n";
  }
  print "</select></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"2\">&nbsp;</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"2\" bgcolor=\"#f4f4f4\"><b>Instant Contact Information</b></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">Email: *</td>\n";
  print "    <td valign=\"top\"><input type=\"email\" name=\"email\" value=\"$query{'email'}\" size=\"20\" maxlength=\"50\" required></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">Phone #: </td>\n";
  print "    <td valign=\"top\"><input type=\"tel\" name=\"phone\" value=\"$query{'phone'}\" size=\"20\" maxlength=\"30\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">Fax #: </td>\n";
  print "    <td valign=\"top\"><input type=\"tel\" name=\"fax\" value=\"$query{'fax'}\" size=\"20\" maxlength=\"30\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"2\">&nbsp;</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"2\" bgcolor=\"#f4f4f4\"><b>ACH Billing Information</b></td>\n";
  print "  </tr>\n";

  if ($query{'cardnumber'} =~ /\d/) {
    print "  <tr>\n";
    print "    <td colspan=\"2\" align=\"center\">";
    print "<table style=\"border: 1px solid #000;\">\n";
    print "  <tr style=\"border-width: 0px;\">\n";
    print "    <td colspan=\"2\" align=\"left\"><b>Your account is presently set to use the following:</b></td>\n";
    print "  </tr>\n";
    print "  <tr style=\"border-width: 0px;\">\n";
    print "    <th width=\"35%\" align=\"right\">ACH Routing #:</th>\n";
    print "    <td>$temp_routingnum</td>\n";
    print "  </tr>\n";
    print "  <tr style=\"border-width: 0px;\">\n";
    print "    <th align=\"right\">Account #:</th>\n";
    print "    <td>$temp_accountnum</td>\n";
    print "  </tr>\n";
    print "</table>\n";

    print "</td>\n";
    print "  </tr>\n";
  }

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">Routing Number: </td>\n";
  print "    <td valign=\"top\"><input type=\"text\" name=\"routingnum\" value=\"$query{'routingnum'}\" size=\"10\" maxlength=\"9\" autocomplete=\"off\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">Bank Account Number: </td>\n";
  print "    <td valign=\"top\"><input type=\"text\" name=\"accountnum\" value=\"$query{'accountnum'}\" size=\"20\" maxlength=\"20\" autocomplete=\"off\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=\"right\">&nbsp;</td>";
  print "    <td><input type=\"checkbox\" name=\"commcardtype\" value=\"business\"";
  if ($query{'commcardtype'} eq "business") { print " checked"; }
  print "> Check when ACH account is a Commercial/Business account.</td>\n";
  print "  </tr>\n";

  #my %selected = ();
  #$selected{$query{'accttype'}} = " selected";
  #print "  <tr>\n";
  #print "    <td valign=\"top\" width=\"170\">Account Type: </td>\n";
  #print "    <td valign=\"top\"><select name=\"accttype\">\n";
  #print "<option value=\"checking\" $selected{'checking'}>Checking</option>\n";
  #print "<option value=\"savings\" $selected{'savings'}>Savings</option>\n";
  #print "</select></td>\n";
  #print "  </tr>\n";

  #if ($chkprocessor =~ /^(echo|testprocessor)$/) {
  #  $selected{$query{'acctclass'}} = " selected";
  #  print "  <tr>\n";
  #  print "    <td valign=\"top\" width=\"170\">Account Class: </td>\n";
  #  print "    <td valign=\"top\"><select name=\"acctclass\">\n";
  #  print "<option value=\"personal\" $selected{'personal'}>Personal</option>\n";
  #  print "<option value=\"business\" $selected{'business'}>Business</option>\n";
  #  print "</select></td>\n";
  #  print "  </tr>\n";
  #}

  print "  <tr>\n";
  print "    <td colspan=2><b>* <u>NOTE</u>: U.S. BANK ACCOUNT ONLY</b></td>\n";
  print "  </tr>\n";

  print "</table>\n";

  print "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"2\">&nbsp;</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"2\" align=\"center\"><input type=\"submit\" class=\"button\" value=\"Submit\"> &nbsp; <input type=\"reset\" class=\"button\" value=\"Reset\"></td></form>\n";
  print "  </tr>\n";    
  print "</table>\n";

  print "<p><form><input type=\"button\" class=\"button\" name=\"submit\" value=\"Close Window\" onClick=\"self.close();\"></form>\n";

  &html_tail();

  return;
}

sub display_profile {
  my %query = @_;
  
  my %selected;

  my %data;
  # query the customer profile data
  %data = &get_profile_info("$ENV{'REMOTE_USER'}");


  #foreach my $key (sort keys %data) {
  #  #$query{"$key"} = $data{"$key"};
  #}

  if (($data{'enccardnumber'} ne "") && ($data{'length'} ne "")) {
    my $cardnumber = &rsautils::rsa_decrypt_file($data{'enccardnumber'},$data{'length'},"print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");
    if ($cardnumber =~ /\d{9} \d/) {
      ($data{'routingnum'}, $data{'accountnum'}) = split(/ /, $cardnumber, 2);
    }

    delete $data{'enccardnumber'};
    delete $data{'length'};
  }

  # Account number filter
  if (exists $data{'accountnum'}) {
    $data{'accountnum'} =~ s/[^0-9]//g;
    $data{'accountnum'} = substr($data{'accountnum'},0,20);
    my ($accountnum) = $data{'accountnum'};
    my $acctlength = length($accountnum);
    my $last4 = substr($accountnum,-4,4);
    $accountnum =~ s/./X/g;
    $data{'accountnum'} = substr($accountnum,0,$acctlength-4) . $last4;
  }
  
  # Routing number filter
  if (exists $data{'routingnum'}) {
    $data{'routingnum'} =~ s/[^0-9]//g;
    $data{'routingnum'} = substr($data{'routingnum'},0,9);
    my ($routingnum) = $data{'routingnum'};
    my $routlength = length($routingnum);
    my $last4 = substr($routingnum,-4,4);
    $routingnum =~ s/./X/g;
    $data{'routingnum'} = substr($routingnum,0,$routlength-4) . $last4;
  }

  # now build the entire page here
  &html_head("Commission Payout Information");

  if ($query{'error_message'} ne "") {
    print "<font class=\"badcolor\">$query{'error_message'}</font>\n";
  }
  elsif ($query{'response_message'} ne "") {
    print "<font class=\"goodcolor\">$query{'response_message'}</font>\n";
  }

  print "<table border=\"0\" cellspacing=\"0\" cellpadding=\"2\">\n";
  print "  <tr>\n";
  print "    <td colspan=\"2\"><h1>Your commission payout information has been updated.</h1></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"2\">Please review the information for accuracy.</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=\"top\">\n";

  # build contact information section
  print "<table border=\"0\" cellspacing=\"0\" cellpadding=\"2\">\n";
  print "  <tr>\n";
  print "    <td colspan=\"2\" bgcolor=\"#f4f4f4\"><b>Billing Address Information</b></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">Name: </td>\n";
  print "    <td valign=\"top\">$data{'name'}</td>\n";
  print "  </tr>\n";

  if ($data{'company'} ne "") {
    print "  <tr>\n";
    print "    <td valign=\"top\" width=\"170\">Company: </td>\n";
    print "    <td valign=\"top\">$data{'company'}</td>\n";
    print "  </tr>\n";
  }

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">Address Line 1: </td>\n";
  print "    <td valign=\"top\">$data{'addr1'}</td>\n";
  print "  </tr>\n";

  if ($data{'addr2'} ne "") {
    print "  <tr>\n";
    print "    <td valign=\"top\" width=\"170\">Address Line 2: </td>\n";
    print "    <td valign=\"top\">$data{'addr2'}</td>\n";
    print "  </tr>\n";
  }

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">City: </td>\n";
  print "    <td valign=\"top\">$data{'city'}</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">State: </td>\n";
  print "    <td valign=\"top\">$data{'state'}</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">Zipcode: </td>\n";
  print "    <td valign=\"top\">$data{'zip'}</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">Country: </td>\n";
  print "    <td valign=\"top\">$data{'country'}</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"2\">&nbsp;</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"2\" bgcolor=\"#f4f4f4\"><b>Instant Contact Information</b></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">Email: </td>\n";
  print "    <td valign=\"top\">$data{'email'}</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">Phone #: </td>\n";
  print "    <td valign=\"top\">$data{'phone'}</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">Fax #: </td>\n";
  print "    <td valign=\"top\">$data{'fax'}</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"2\">&nbsp;</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"2\">&nbsp;</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"2\" bgcolor=\"#f4f4f4\"><b>ACH Billing Information</b></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">Routing Number: </td>\n";
  print "    <td valign=\"top\">$data{'routingnum'}</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=\"top\" width=\"170\">Bank Account Number: </td>\n";
  print "    <td valign=\"top\">$data{'accountnum'}</td>\n";
  print "  </tr>\n";

  if ($data{'commcardtype'} ne '') {
    print "  <tr>\n";
    print "    <td valign=\"top\" width=\"170\"></td>\n";
    print "    <td valign=\"top\"\">Commercial/Business Account</td>\n";
    print "  </tr>\n";
  }

  #if ($data{'accttype'} ne "") {
  #  print "  <tr>\n";
  #  print "    <td valign=\"top\" width=\"170\">Acct Type: </td>\n";
  #  print "    <td valign=\"top\">Acct Type: $data{'accttype'}</td>\n";
  #  print "  </tr>\n";
  #}
  #if ($data{'acctclass'} ne "") {
  #  print "  <tr>\n";
  #  print "    <td valign=\"top\" width=\"170\">Acct Class: </td>\n";
  #  print "    <td valign=\"top\">$data{'acctclass'}</td>\n";
  #  print "  </tr>\n";
  #}

  print "  <tr>\n";
  print "    <td colspan=\"2\">&nbsp;</td>\n";
  print "  </tr>\n";

  print "</table>\n";

  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<p><form><input type=\"button\" class=\"button\" name=\"submit\" value=\"Close Window\" onClick=\"self.close();\"></form>\n";

  &html_tail();

  return;
}

sub html_head {
  my ($title) = @_;

  print "<html>\n";
  print "<head>\n";
  print "<title>$title</title>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"https://pay1.plugnpay.com/css/green.css\">\n";
  
  print "<script Language=\"Javascript\"><!--\n";
  print "function closeresults() \{\n";
  print "  resultsWindow = window.close('results');\n";
  print "\}\n";
  print "//-->\n";
  print "</script>\n";

  print "</head>\n";
  print "<body bgcolor=\"#ffffff\" text=\"#333333\">\n";

  print "<table>\n";
  print "  <tr>\n";
  print "    <td><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Payment Gateway Logo\" /></td>\n";
  print "    <td class=\"right\">&nbsp;</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td colspan=\"2\"><img src=\"/adminlogos/masthead_background.gif\" alt=\"Corp. Logo\" width=\"750\" height=\"16\" /></td>\n";
  print "  </tr>\n";
  print "</table>\n";
  print "<table>\n";
  print "  <tr>\n";
  print "    <td><h1>Commission Payout Information</h1></td>\n";
  print "    <td align=\"right\"><a href=\"/admin/logout.cgi\">Logout</a></td>\n";
  print "  </tr>\n";
  print "</table>\n";
  print "<hr id=\"under\" />\n";

  return;
}

sub html_tail {

  my @now = gmtime(time);
  my $year = sprintf("%04d", $now[5]+1900);

  print "<hr id=\"over\" />\n";
  print "<table class=\"frame\">\n";
  print "  <tr>\n";
  print "    <td align=\"left\"><a href=\"/admin/online_helpdesk.cgi\" target=\"ahelpdesk\">Help Desk</a></td>\n";
  print "    <td class=\"right\">&copy; $year, Plug 'n Pay Technologies, Inc.</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<body>\n";
  print "</html>\n";

  return;
}

sub get_profile_info {
  my ($username) = @_; 

  $username =~ s/[^_0-9a-zA-Z\-\@\.]//g; # remove all non-allowed characters
 
  my %data;
  my $sth = $dbh->prepare(qq{
      select *
      from customer
      where username=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth->execute("$username") or die "Cannot execute: $DBI::errstr";
  my $results = $sth->fetchrow_hashref();
  $sth->finish;

  my $cd = new PlugNPay::CardData();
  my $ecrypted_card_data = '';
  eval {
    $ecrypted_card_data = $cd->getRecurringCardData({customer => $results->{'username'}, username => 'pnppaydata'});
  };
  if (!$@) {
    $results->{'enccardnumber'} = $ecrypted_card_data;
  }

  # copy the name/value pairs in the results hash reference data to %query hash for later usage
  foreach my $key (keys %$results) {
    $data{"$key"} = $results->{$key};
  }

  return %data;
}

sub sort_hash {
  my $x = shift;
  my %array=%$x; 
  sort { $array{$a} cmp $array{$b}; } keys %array;
}   

sub modulus10{ # used to test check routing numbers
  my($ABAtest) = @_;
  my @digits = split('',$ABAtest);
  my ($modtest);
  my $sum = $digits[0] * 3 + $digits[1] * 7 + $digits[2] * 1 + $digits[3] * 3 + $digits[4] * 7 + $digits[5] * 1 + $digits[6] * 3 + $digits[7] * 7;
  my $check = 10 - ($sum % 10);
  $check = substr($check,-1);
  my $checkdig = substr($ABAtest,-1);
  if ($check eq $checkdig) {
    $modtest = "PASS";
  } else {
    $modtest = "FAIL";
  }
  return($modtest);
}

