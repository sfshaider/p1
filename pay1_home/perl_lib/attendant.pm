package attendant;

## Purpose: provides functions for shared version of the Recurring Adminstration's Web Site Attendant
#  -- offers merchant's CSS, logo & background abilities
#  -- offers ability to taylor attendant options via feature settings
#  -- offers increased interface security & data validation.

require 5.001;
$| = 1;

use DBI;
use miscutils;
use rsautils;
use smpsutils;
use CGI;
use constants qw(%countries %USstates %USterritories %CNprovinces %USCNprov);
use PlugNPay::Logging::DataLog;
use strict;
use PlugNPay::GatewayAccount::Services;
use PlugNPay::Features;
use PlugNPay::DBConnection;
use PlugNPay::Email;

sub new {
  my $type = shift;

  %attendant::query = @_;

  my $services = new PlugNPay::GatewayAccount::Services($attendant::query{'publisher-name'});
  if (!$services->getMembership()) {
    print "Content-Type: text/plain\n\n";
    print "Invalid Merchant Username.\n";
    exit(0);
  }

  $attendant::accountFeatures = new PlugNPay::Features($attendant::query{'publisher-name'},'general');

  # set CSS color scheme params
  if ($attendant::accountFeatures->get('goodcolor') ne "") { $attendant::goodcolor = $attendant::accountFeatures->get('goodcolor'); }
    else { $attendant::goodcolor = "#2020a0"; }
  if ($attendant::accountFeatures->get('backcolor') ne "") { $attendant::backcolor = $attendant::accountFeatures->get('backcolor'); }
    else { $attendant::backcolor = "#ffffff"; }
  if ($attendant::accountFeatures->get('badcolor') ne "") { $attendant::badcolor = $attendant::accountFeatures->get('badcolor'); }
    else { $attendant::badcolor = "#ff0000"; }
  if ($attendant::accountFeatures->get('badcolortxt') ne "") { $attendant::badcolortxt = $attendant::accountFeatures->get('badcolortxt'); }
    else { $attendant::badcolortxt = "RED"; }
  if ($attendant::accountFeatures->get('linkcolor') ne "") { $attendant::linkcolor = $attendant::accountFeatures->get('linkcolor'); }
    else { $attendant::linkcolor = $attendant::goodcolor; }
  if ($attendant::accountFeatures->get('textcolor') ne "") { $attendant::textcolor = $attendant::accountFeatures->get('textcolor'); }
    else { $attendant::textcolor = $attendant::goodcolor; }
  if ($attendant::accountFeatures->get('alinkcolor') ne "") { $attendant::alinkcolor = $attendant::accountFeatures->get('alinkcolor'); }
    else { $attendant::alinkcolor = "#187f0a"; }
  if ($attendant::accountFeatures->get('vlinkcolor') ne "") { $attendant::vlinkcolor = $attendant::accountFeatures->get('vlinkcolor'); }
    else { $attendant::vlinkcolor = "#0b1f48"; }
  if ($attendant::accountFeatures->get('fontface') ne "") { $attendant::fontface = $attendant::accountFeatures->get('fontface'); }
    else { $attendant::fontface = "Arial,Helvetica,Univers,Zurich BT"; }
  if ($attendant::accountFeatures->get('itemrow') ne "") { $attendant::itemrow = $attendant::accountFeatures->get('itemrow'); }
    else { $attendant::itemrow = "#d0d0d0"; }

  # set other misc parmeters
  $attendant::script = "https://" . $ENV{'SERVER_NAME'} . $ENV{'SCRIPT_NAME'};

  $attendant::path_home = "http://xxxHOSTxxx/";
  $attendant::desc_home = "Return Home";

  # create list of database field names to update
  @attendant::editfields = ("name","company","addr1","addr2","city","state","zip","country");
  if ($attendant::accountFeatures->get('attendant_suppressemail') != 1) {
    push(@attendant::editfields, "email");
  }
  if ($attendant::accountFeatures->get('attendant_suppressphone') != 1) {
    push(@attendant::editfields, "phone", "fax");
  }
  if ($attendant::accountFeatures->get('attendant_suppresspw') != 1) {
    push(@attendant::editfields, "password");
  }
  if ($attendant::accountFeatures->get('attendant_edit_cc') == 1) {
    push(@attendant::editfields, "cardnumber","exp");
  }
  if ($attendant::accountFeatures->get('attendant_edit_shipping') == 1) {
    push (@attendant::editfields, "shipname","shipaddr1","shipaddr2","shipcity","shipstate","shipzip","shipcountry");
  }

  ## setup hashes that will be required.
  %attendant::countries = %constants::countries;
  %attendant::USstates = %constants::USstates;
  %attendant::USterritories = %constants::USterritories;
  %attendant::CNprovinces = %constants::CNprovinces;
  %attendant::USCNprov = %constants::USCNprov;

  return [], $type;
}


sub cancel_member {
  my %query = @_;

  my ($void, $expired);

  # safeguard account against hacks - 08/15/05
  $query{'username'} =~ s/[^0-9a-zA-Z\_\-\@\.]//g; # remove all non-allowed characters
  $query{'password'} =~ s/[^0-9a-zA-Z\_]//g; # remove all non-allowed characters

  if (($query{'username'} !~ /\w/) && ($query{'password'} !~ /\w/)) {
    my $message = "<font class=\"badcolor\"><b>Invalid Username or Password.  Please try again. [3]</b></font>\n";
    my $page_title = "Cancel Subscription";
    &response_page($message, $page_title);
    exit;
  }

  if ($attendant::accountFeatures->get('attendant_voidflag') == 1) {
    $void = "yes";
  }


  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor($attendant::query{'publisher-name'});

  my $sth = $dbh->prepare(q{
      SELECT username,password,orderid,email,enddate,billcycle
      FROM customer
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$query{'username'}") or die "Can't execute: $DBI::errstr";
  my ($uname,$pword,$orderID,$email,$end,$billcycle) = $sth->fetchrow;
  $sth->finish;

  my @current_date = gmtime(time);
  $current_date[4] = $current_date[4] + 1; # for currect month number
  $current_date[5] = $current_date[5] + 1900; # for correct 4-digit year
  my $todays_date = sprintf("%04d%02d%02d", $current_date[5], $current_date[4], $current_date[3]);
  if ($todays_date > $end) {
    $expired = 1;
  }
 
  my $end1 = sprintf("%02d/%02d/%04d", substr($end,4,2), substr($end,6,2), substr($end,0,4));

  if (($uname eq $query{'username'}) && ($pword eq $query{'password'})) {
    if ($expired == 1) {
      my $message = "<font class=\"badcolor\"><b>The account for username: $query{'username'}, has already expired.</font>\n";
      $message .= "<br>No cancellation is required.<b>";
      my $page_title = "Cancel Subscription";
      &response_page($message, $page_title);
    }
    elsif ($billcycle > 0) {
      if ($attendant::accountFeatures->get('attendant_termflag') == 1) {
        my @current_date = gmtime(time - 86400);
        $current_date[4] = $current_date[4] + 1; # for currect month number
        $current_date[5] = $current_date[5] + 1900; # for correct 4-digit year
        my $todays_date = sprintf("%04d%02d%02d", $current_date[5], $current_date[4], $current_date[3]);

        my $sth2 = $dbh->prepare(q{
            UPDATE customer
            SET billcycle='0',status='cancelled', enddate=?
            WHERE username=?
          }) or die "Can't prepare: $DBI::errstr";
        $sth2->execute("$todays_date","$uname") or die "Can't execute: $DBI::errstr";
        $sth2->finish;
        $end = $todays_date;
        $end1 = sprintf("%02d/%02d/%04d", substr($end,4,2), substr($end,6,2), substr($end,0,4));
      }
      else {
        my $sth3 = $dbh->prepare(q{
            UPDATE customer
            SET billcycle='0',status='cancelled'
            WHERE username=?
          }) or die "Can't prepare: $DBI::errstr";
        $sth3->execute("$uname") or die "Can't execute: $DBI::errstr";
        $sth3->finish;
      }

      $query{'orderID'} = $orderID;
      $query{'email'} = $email;
      $query{'enddate'} = $end;
      $query{'billcycle'} = $billcycle;
      $query{'end'} = $end1;

      my $message = "<font class=\"goodcolor\"><b>The account for username: $uname, has been successfully cancelled and will not be rebilled.</font>\n";
      $message .= "<br>The Username and Password will continue to be valid until $end1.</b>";
      &email(%query);
      my $page_title = "Cancel Subscription";
      &response_page($message, $page_title);
    }
    else {
      my $message = "<font class=\"badcolor\"><b>The account for username: $uname, has already been cancelled.</font>\n";
      $message .= "<br>The Username and Password will continue to be valid until $end1.</b>";
      my $page_title = "Cancel Subscription"; 
      &response_page($message, $page_title);
    }
  }
  else {
    my $message = "<font class=\"badcolor\"><b>Sorry, the Username and Password combination entered was not found in the database.</font>\n";
    $message .= "<br>Please try again and be careful to use the proper CAPITALIZATION.</b>";
    my $page_title = "Cancel Subscription"; 
    &response_page($message, $page_title);
  }

  if ($void eq "yes") {
    #%attendant::result = &voidtrans(%query);
    my %result = &voidtrans(%query);
  }

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

  print "<p><form><input type=button value=\"Close\" onClick=\"closeresults();\"></form>\n";

  &html_tail();
  return;
}

sub email {
  my %query = @_;

  $query{'email'} =~ s/[^0-9a-zA-Z\_\-\@\.]//g; # remove all non-allowed characters
  $query{'from-email'} =~ s/[^0-9a-zA-Z\_\-\@\.]//g; # remove all non-allowed characters
  $query{'publisher-email'} =~ s/[^0-9a-zA-Z\_\-\@\.]//g; # remove all non-allowed characters

  my $position = index($query{'email'},"\@");
  if (($position > 1) && (length($query{'email'}) > 5) && ($position < (length($query{'email'})-5))) {
    my $emailObj = new PlugNPay::Email('legacy');
    $emailObj->setFormat('text');
    $emailObj->setTo($query{'email'});

    if ($query{'from-email'} ne "") {
      $emailObj->setFrom($query{'from-email'});
    } elsif ($query{'publisher-email'} ne "") {
      $emailObj->setFrom($query{'publisher-email'});
    } else {
      $emailObj->setFrom('noreply@plugnpay.com');
    }

    $emailObj->setCC($query{'publisher-email'});

    if ($query{'subject'} ne "") {
      $emailObj->setSubject($query{'subject'});
    } else {
      $emailObj->setSubject("$query{'publisher-name'} - Membership Cancellation Confirmation");
    }

    my $emailmessage = '';
    $emailmessage .= "The following account has been successfully cancelled and will not be rebilled.\n\n";
    $emailmessage .= "Username: $query{'username'}\n\n";
    $emailmessage .= "The Username and Password may still be used until $query{'end'}.\n\n";

    $emailmessage .= $query{'email-message'};
    $emailmessage .= "\n";

    $emailObj->setContent($emailmessage);
    $emailObj->send();
  }

  return;
}

sub voidtrans {
  # Contact the credit server to do void
  my %query = @_;

  my $acct_code4 = "Cancel Member";
  my %result = &miscutils::sendmserver("$query{'publisher-name'}",'void'
     ,'txn-type','marked'
     ,'order-id',"$query{'orderID'}"
     ,'acct_code4', "$query{'acct_code4'}"
  );

  return %result;
}

sub remind_member {
  my %query = @_;

  my ($uname, $pword, $end, $status, $billcycle, $active_count, $expired_count);
  my ($today) = &miscutils::gendatetime_only();

  # filter special fields
  $query{'omitgrp'} =~ s/[^a-zA-Z0-9\-\_\,]//g;

  # email address filter
  $query{'email'} =~ s/\,(com|org|net|mil|gov|tv|cc|ws|info|biz|bz)$/\.$1/;
  $query{'email'} =~ s/[^_0-9a-zA-Z\-\@\.]//g;
  $query{'email'} =~ lc($query{'email'});

  # validiate email format
  my $position = index($query{'email'},"\@");
  my $position1 = rindex($query{'email'},"\.");
  my $elength  = length($query{'email'});
  my $pos1 = $elength - $position1;
  if (($position < 1) || ($position1 < $position) || ($position1 >= $elength - 2) || ($elength < 5) || ($position > $elength - 5)) {
    my $message = "<font class=\"badcolor\"><b>Invalid email address format. Please try again.</b></font>";
    my $page_title = "Subscription Reminder";
    &response_page($message, $page_title);
    exit;
  }

  my $emessage = "Your Username(s) and Password(s) are as follows:\n\n";

  my $email = $query{'email'};

  my @placeholder = ();
  my $qstr = "SELECT username,password,enddate,status,billcycle";
  $qstr .= " FROM customer";
  $qstr .= " WHERE LOWER(email) LIKE LOWER(?)";
  push (@placeholder, "\%$email\%");
  if ($query{'omitgrp'} =~ /\w/) {
    my @temp = split(/\,/, $query{'omitgrp'});
    for (my $i = 0; $i <= $#temp; $i++) {
      $qstr .= " AND LOWER(purchaseid) NOT LIKE LOWER(?)";
      push (@placeholder, "$temp[$i]");
    }
  }

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor($attendant::query{'publisher-name'});
  my $sth = $dbh->prepare(qq{ $qstr }) or die "Can't do: $DBI::errstr";
  my $rc = $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  if ($rc > 0) {
    $sth->bind_columns(undef,\($uname,$pword,$end,$status,$billcycle));
    while ($sth->fetch) {

      # figure out if profile is expired 
      my $expired = 0;
      if ($end < $today) {
        $expired = 1;
      }
      if (($status =~ /cancelled/) && ($pword =~ /^CN\d\d\d\d/)) {
        $expired = 1;
      }

      # append profile data to email message
      $emessage .= "Username: $uname\n";
      if ($expired == 1) {
        if (($status !~ /cancelled/) && ($pword !~ /^CN\d\d\d\d/)) {
          $emessage .= "Password: $pword\n";
        }
        $emessage .= "\n";
        $emessage .= "This username has expired.\n\n";
      }
      else {
        $emessage .= "Password: $pword\n\n";
        $end = sprintf("%02d/%02d/%04d", substr($end,4,2), substr($end,6,2), substr($end,0,4));
        if ($billcycle > 0) {
          $emessage .= "This username is set to rebill next by $end.\n\n";
        }
        else {
          $emessage .= "This username is set to expire on $end.\n\n";
        }
      }

      # track number of active & expired usernames
      if ($expired == 0) {
        $active_count = $active_count + 1;
      }
      else {
        $expired_count = $expired_count + 1;
      }
    }
  }
  $sth->finish;

  if ($rc <= 0) {
    my $message .= "<font class=\"badcolor\"><b>Sorry, the Email address entered was not found in the database.</b></font>";
    my $page_title = "Subscription Reminder";
    &response_page($message, $page_title);
    exit;
  }

  $query{'emessage'} = $emessage;
  &email1(%query);

  my $message;
  if ($uname ne "") {
    my $message;
    if ($active_count > 0) {
      $message .= "<font class=\"goodcolor\"><b>A username and password have been found for the email address entered.</font>\n";
      $message .= "<br>A copy is being emailed to you.</b>";
    }
    else {
      $message .= "<font class=\"badcolor\"><b>Username and password found are no longer active.</font>\n";
      $message .= "<br>Your subscription has expired.\n";
      $message .= "<br>A copy is being emailed to you for renewal purposes.</b>";
    }
    if ($query{'success_link'} ne "") {
      $message .= "<p><a href=\"$query{'success_link'}\">Click Here to Continue</a><p>";
    }
    my $page_title = "Subscription Reminder"; 
    &response_page($message, $page_title);
  }

  return;
}

sub email1 {
  my %query = @_;

  $query{'email'} =~ s/[^0-9a-zA-Z\_\-\@\.]//g; # remove all non-allowed characters
  $query{'from-email'} =~ s/[^0-9a-zA-Z\_\-\@\.]//g; # remove all non-allowed characters
  $query{'publisher-email'} =~ s/[^0-9a-zA-Z\_\-\@\.]//g; # remove all non-allowed characters

  my $position = index($query{'email'},"\@");
  if (($position > 1) && (length($query{'email'}) > 5) && ($position < (length($query{'email'})-5))) {

    my $emailObj = new PlugNPay::Email('legacy');
    $emailObj->setFormat('text');
    $emailObj->setTo($query{'email'});

    if ($query{'from-email'} ne "") {
      $emailObj->setFrom($query{'from-email'});
    } elsif ($query{'publisher-email'} ne "") {
      $emailObj->setFrom($query{'publisher-email'});
    } else {
      $emailObj->setFrom('noreply@plugnpay.com');
    }

    if ($query{'subject'} ne "") {
      $emailObj->setSubject($query{'subject'});
    } else {
      $emailObj->setSubject('Your Membership');
    }

    my $emailmessage = "";
    $emailmessage .= $query{'emessage'};
    $emailmessage .= $query{'email-message'};
    $emailmessage .= "\n";

    $emailObj->setContent($emailmessage);
    $emailObj->send();
  }

  return;
}

sub update_profile {
  my %query = @_;

  my ($enccardnumber,$encryptedDataLen);
  
  # safeguard account against hacks
  $query{'username'} =~ s/[^_0-9a-zA-Z\-\@\.]//g; # remove all non-allowed characters
  $query{'passwd1'} =~ s/[^_0-9a-zA-Z]//g; # remove all non-allowed characters
  $query{'passwd2'} =~ s/[^_0-9a-zA-Z]//g; # remove all non-allowed characters

  if ($query{'username'} !~ /\w/) {
    # reject usernames which do not contain at least 1 alphanumeric character
    my $message .= "<font class=\"badcolor\"><b>Invalid Username.</b></font>\n";
    my $page_title = "Edit Account Information";
    &response_page($message, $page_title);
    exit;
  }

  my $result = &checkunpw(%query);

  if ($result ne "success") {
    my $message = "<font class=\"badcolor\"><b>Sorry, the Username and Password combination entered was not found in the database.</font>\n";
    $message .= "<br>Please try again and be careful to use the proper CAPITALIZATION.</b>";
    my $page_title = "Edit Account Information";
    &response_page($message, $page_title);
    return "failure";
  }

  $query{'routingnum'} =~ s/[^0-9]//g; # ACH routing number filter
  $query{'accountnum'} =~ s/[^0-9]//g; # ACH account number filter

  if (($query{'routingnum'} ne "") && ($query{'accountnum'} ne "")) {
    $query{'cardnumber'} = sprintf("%s %s", $query{'routingnum'}, $query{'accountnum'});
  }

  my $cardnumber;

  if (($query{'cardnumber'} !~ /\*\*/) && ($attendant::accountFeatures->get('attendant_edit_cc') == 1)) {
    # check for cardtype & find out it's allowed
    my $cardtype = &detect_cardtype("$query{'cardnumber'}");

    if ($attendant::accountFeatures->get('attendant_cardsallowed') !~ /($cardtype)/i) {
      $query{'error_message'} = "Sorry, the merchant does not accept this payment type at this time.\n";
      $query{'error_message'} .= "<br>We accept: $attendant::accountFeatures->get('attendant_cardsallowed')\n";
      $query{'error_message'} .= "<br>Please register a different payment type.\n";
      &edit_profile(%query);
      return "failure";
    }

    if ($cardtype =~ /(checking|savings)/i) {
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
    }  

    # update payment data, if new data is provided
    $cardnumber = $query{'cardnumber'};
    $cardnumber =~ s/[^0-9\*]//g;
    my $cardlength = length($cardnumber);
    if (($cardnumber !~ /\*\*/) && ($cardlength > 8)) {
      $cardnumber = $query{'cardnumber'};
      $cardnumber =~ s/[^0-9]//g;
      my ($enccardnumber, $length) = &rsautils::rsa_encrypt_card($query{'cardnumber'},"/home/p/pay1/pwfiles/keys/key");
      $cardnumber = substr($cardnumber,0,4) . "**" . substr($cardnumber,-2,2);

      $enccardnumber = &smpsutils::storecardnumber($attendant::query{'publisher-name'},$query{'username'},'attendant_update',$enccardnumber,'rec');

      my $dbh = PlugNPay::DBConnection::connections()->getHandleFor($attendant::query{'publisher-name'});
      my $sth = $dbh->prepare(q{
          UPDATE customer
          SET enccardnumber=?,length=?,cardnumber=?
          WHERE username=?
        }) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$enccardnumber","$length","$cardnumber","$query{'username'}") or die "Can't execute: $DBI::errstr";
      $sth->finish;
    }
  }

  if ($query{'shipsame'} eq "yes") {
    $query{'shipname'} = $query{'name'};
    $query{'shipaddr1'} = $query{'addr1'};
    $query{'shipaddr2'} = $query{'addr2'};
    $query{'shipcity'} = $query{'city'};
    $query{'shipstate'} = $query{'state'};
    $query{'shipzip'} = $query{'zip'};
    $query{'shipcountry'} = $query{'country'};
  }

  my $updatestring = "UPDATE customer SET ";
  my @placeholder;
 
  my $message; 
  foreach my $var (@attendant::editfields) {
    if ($var ne "cardnumber") {
      if (($var ne "username") && ($var ne "")) {
        my $value;
        $updatestring .= "$var=?,";

        if ($var eq "password") {
          if (($query{'passwd1'} =~ /\w/) && (length($query{'passwd1'}) < 4)) {
            $query{'error_message'} = "<font class=\"badcolor\"><b>The password must be at least 4 characters long, please re-enter.</b></font>";
            &edit_profile(%query);
            return "failure";
          }
          if ($query{'passwd1'} ne $query{'passwd2'}) {
            $query{'error_message'} = "<font class=\"badcolor\"><b>The passwords do not match, please re-enter.</b></font>";
            &edit_profile(%query);
            return "failure";
          }

          if ($query{'passwd1'} =~ /\w/) {
            $value = $query{'passwd1'};
          }
          else {
            $value = $query{'password'};
          }
        }
        elsif ($var eq "exp") {
          my $exp_month = $query{'exp_month'};
          $exp_month =~ s/[^0-9]//g;
          $exp_month = sprintf("%02d", substr($exp_month,-2,2));
          my $exp_year = $query{'exp_year'};
          $exp_year =~ s/[^0-9]//g;
          $exp_year = sprintf("%02d", substr($exp_year,-2,2));
          my $exp = "$exp_month/$exp_year";
          $value = $exp;
        }
        else {
          $value = $attendant::query{"$var"};
          $value =~ s/[^_0-9a-zA-Z\-\@\.\ ]//g; # remove all non-allowed characters
        }

        push(@placeholder, "$value");
      }
    }
  }

  chop $updatestring;
  $updatestring .= " WHERE username=?";
  push(@placeholder, "$query{'username'}");

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor($attendant::query{'publisher-name'});
  my $sth = $dbh->prepare(qq{ $updatestring }) or die "Can't prepare: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  $sth->finish;

  # write to service history
  my $action = "Customer Update";
  my $reason = "User updated profile info from $ENV{'REMOTE_ADDR'}, merchant confirmation sent to ";
  if ($query{'from-email'} ne "") {
    $reason .= "$query{'from-email'}";
  }
  else {
    $reason .= "$query{'publisher-email'}";
  }
  my $now = time();
  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor($attendant::query{'publisher-name'});
  my $sth_history = $dbh->prepare(q{
      INSERT INTO history
      (trans_time,username,action,descr)
      VALUES (?,?,?,?)
    }) or die "Can't prepare: $DBI::errstr";
  $sth_history->execute("$now", "$query{'username'}", "$action", "$reason") or die "Can't execute: $DBI::errstr";
  $sth_history->finish;

  if ($query{'publisher-email'} ne "") {
    &email2(%query);
  }

  $attendant::dontupdate = 1;
  &display_profile(%query);

  #if ($chkfields[7] ne $temp) {
  #  $query{'subject'} = "Plug and Pay - Email Change";
  #  $query{'emailmessage'} = "Username: $query{'username'}\nEmail Address: $query{'email'}\n\n";
  #  &email(%query);
  #}

  return;
}

sub email2 { # electric boogaloo
  my %query = @_;

  $query{'publisher-email'} =~ s/[^0-9a-zA-Z\_\-\@\.]//g; # remove all non-allowed characters

  my $position = index($query{'publisher-email'},"\@");
  if (($position > 1) && (length($query{'publisher-email'}) > 5) && ($position < (length($query{'publisher-email'})-5))) {
    my $emailObj = new PlugNPay::Email('legacy');
    $emailObj->setFormat('text');
    $emailObj->setTo($query{'publisher-email'});
    $emailObj->setFrom('noreply@plugnpay.com');

    if ($query{'subject'} ne "") {
      $emailObj->setSubject($query{'subject'});
    } else {
      $emailObj->setSubject("$query{'publisher-name'} - Membership Profile Update Confirmation");
    }

    my $emailmessage = "";
    $emailmessage .= "The following account has successfully updated their profile information online.\n\n";
    $emailmessage .= "Username: $query{'username'}\n\n";
    $emailmessage .= $query{'email-message'};
    $emailmessage .= "\n";

    $emailObj->setContent($emailmessage);
    $emailObj->send();
  }

  return;
}

sub edit_profile {
  my %query = @_;

  my %selected;

  # safeguard account against hacks
  $query{'username'} =~ s/[^_0-9a-zA-Z\-\@\.]//g; # remove all non-allowed characters
  $query{'password'} =~ s/[^_0-9a-zA-Z]//g; # remove all non-allowed characters
  $query{'passwd1'} =~ s/[^_0-9a-zA-Z]//g; # remove all non-allowed characters

  if (($query{'username'} !~ /\w/) || (($query{'password'} !~ /\w/) && ($query{'passwd1'} !~ /\w/))) {
    # reject usernames/passwords which do not contain at least 1 alphanumeric character
    my $message = "<font class=\"badcolor\"><b>Invalid Username or Password. Please try again. [1]</b></font>";
    my $page_title = "Edit Account Information";
    &response_page($message, $page_title);
    exit;
  }

  if ($attendant::accountFeatures->get('attendant_nooutputflag') == 1) {
    return;
  }

  if ($attendant::dontupdate != 1) {
    my $result = &checkunpw(%query);

    if ($result eq "cancel") {
      my $message = "<font class=\"badcolor\"><b>Sorry, your account has been previously cancelled and may not be updated through this interface.</b></font>";
      my $page_title = "Edit Account Information";
      &response_page($message, $page_title);
      return "failure";
    }
    elsif ($result ne "success") {
      my $message = "<font class=\"badcolor\"><b>Sorry, the Username and Password combination entered was not found in the database.</font>\n";
      $message .= "<br>Please try again and be careful to use the proper CAPITALIZATION.</b>";
      my $page_title = "Edit Account Information";
      &response_page($message, $page_title);
      return "failure";
    }
  }

  # query the customer profile data
  if ($attendant::accountFeatures->get('attendant_dontquery') != 1) {
    my %data = &get_profile_info("$query{'username'}");
    foreach my $key (sort keys %data) {
      $query{"$key"} = $data{"$key"};
    }
  }

  if ($attendant::accountFeatures->get('attendant_displayonly') == 1) {
    &display_profile(%query);
    return;
  }

  # now build the entire page here
  &html_head("Edit Account Information");

  if ($query{'error_message'} ne "") {
    print "<font class=\"badcolor\">$query{'error_message'}</font>\n";
  }
  elsif ($query{'response_message'} ne "") {
    print "<font class=\"goodcolor\">$query{'response_message'}</font>\n";
  }

  if ($attendant::dontupdate != 1) {
    print "<form method=post action=\"$attendant::script\" name=\"profile_form\">\n";
    print "<input type=hidden name=\"publisher-name\" value=\"$query{'publisher-name'}\">\n";
    print "<input type=hidden name=\"publisher-email\" value=\"$query{'publisher-email'}\">\n";
    print "<input type=hidden name=\"mode\" value=\"update\">\n";
    print "<input type=hidden name=\"username\" value=\"$query{'username'}\">\n";
    print "<input type=hidden name=\"password\" value=\"$query{'password'}\">\n";
  }

  print "<table border=0 cellspacing=0 cellpadding=2>\n";
  print "  <tr>\n";
  print "    <td colspan=2><h1>Edit Account Information</h1></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=2>";
  if ($attendant::accountFeatures->get('attendant_dontquery') == 1) {
    print "Please enter your new information, so we can update our records.\n";
  }
  else {
    print "Please review &amp; edit the information you wish changed.\n";
  }
  print "<br>Click on the \'Submit\' button when finished.\n";
  print "<p>Required fields are marked with a <b>*</b>.</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=top>\n";

  # build contact information section
  print "<table border=0 cellspacing=0 cellpadding=2>\n";
  print "  <tr>\n";
  print "    <td colspan=2 bgcolor=\"#f4f4f4\"><b>Billing Address Information</b></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=top width=170>Name: *</td>\n";
  print "    <td valign=top><input type=text name=\"name\" value=\"$query{'name'}\" size=20 maxlength=39></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=top width=170>Company: </td>\n";
  print "    <td valign=top><input type=text name=\"company\" value=\"$query{'company'}\" size=20 maxlength=39></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=top width=170>Address Line 1: *</td>\n";
  print "    <td valign=top><input type=text name=\"addr1\" value=\"$query{'addr1'}\" size=20 maxlength=39></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=top width=170>Address Line 2: </td>\n";
  print "    <td valign=top><input type=text name=\"addr2\" value=\"$query{'addr2'}\" size=20 maxlength=39></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=top width=170>City: *</td>\n";
  print "    <td valign=top><input type=text name=\"city\" value=\"$query{'city'}\" size=20 maxlength=39></td>\n";
  print "  </tr>\n";

  if ($query{'state'} ne "") {
    $selected{"$query{'state'}"} = "selected";
  }

  print "  <tr>\n";
  print "    <td valign=top width=170>State: *</td>\n";
  print "    <td valign=top><select name=\"state\">\n";
  print "<option value=\"\">Select Your State/Province/Territory</option>\n";
  foreach my $key (&sort_hash(\%attendant::USstates)) {
    print "<option value=\"$key\" $selected{$key}>$attendant::USstates{$key}</option>\n";
  }
  foreach my $key (&sort_hash(\%attendant::USterritories)) {
    print "<option value=\"$key\" $selected{$key}>$attendant::USterritories{$key}</option>\n";
  }
  foreach my $key (&sort_hash(\%attendant::USCNprov)) {
    print "<option value=\"$key\" $selected{$key}>$attendant::USCNprov{$key}</option>\n";
  }
  foreach my $key (&sort_hash(\%attendant::CNprovinces)) {
    print "<option value=\"$key\" $selected{$key}>$attendant::CNprovinces{$key}</option>\n";
  }
  print "</select></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=top width=170>Zipcode: *</td>\n";
  print "    <td valign=top><input type=text name=\"zip\" value=\"$query{'zip'}\" size=20 maxlength=14></td>\n";
  print "  </tr>\n";

  if ($query{'country'} eq "") {
    $query{'country'} = "US";
  }
  $selected{"$query{'country'}"} = "selected";

  print "  <tr>\n";
  print "    <td valign=top width=170>Country: *</td>\n";
  print "    <td valign=top><select name=\"country\">\n";
  foreach my $key (&sort_hash(\%attendant::countries)) {
    print "<option value=\"$key\" $selected{$key}>$attendant::countries{$key}</option>\n";
  }
  print "</select></td>\n";
  print "  </tr>\n";

  if ($attendant::accountFeatures->get('attendant_edit_shipping') == 1) {
    print "  <tr>\n";
    print "    <td colspan=2>&nbsp;</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td colspan=2 bgcolor=\"#f4f4f4\"><b>Shipping Address Information</b></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td valign=top align=center colspan=2><input type=checkbox name=\"shipsame\" value=\"yes\"> Check here, if Shipping Address is same as Billing Address.</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td valign=top width=170>Name: </td>\n";
    print "    <td valign=top><input type=text name=\"shipname\" value=\"$query{'shipname'}\" size=20 maxlength=39></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td valign=top width=170>Address Line 1: </td>\n";
    print "    <td valign=top><input type=text name=\"shipaddr1\" value=\"$query{'shipaddr1'}\" size=20 maxlength=39></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td valign=top width=170>Address Line 2: </td>\n";
    print "    <td valign=top><input type=text name=\"shipaddr2\" value=\"$query{'shipaddr2'}\" size=20 maxlength=39></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td valign=top width=170>City: </td>\n";
    print "    <td valign=top><input type=text name=\"shipcity\" value=\"$query{'shipcity'}\" size=20 maxlength=39></td>\n";
    print "  </tr>\n";

    if ($query{'shipstate'} ne "") {
      $selected{"$query{'shipstate'}"} = "selected";
    }

    print "  <tr>\n";
    print "    <td valign=top width=170>State: </td>\n";
    print "    <td valign=top><select name=\"shipstate\">\n";
    print "<option value=\"\">Select Your State/Province/Territory</option>\n";
    foreach my $key (&sort_hash(\%attendant::USstates)) {
      print "<option value=\"$key\" $selected{$key}>$attendant::USstates{$key}</option>\n";
    }
    foreach my $key (&sort_hash(\%attendant::USterritories)) {
      print "<option value=\"$key\" $selected{$key}>$attendant::USterritories{$key}</option>\n";
    }
    foreach my $key (&sort_hash(\%attendant::USCNprov)) {
      print "<option value=\"$key\" $selected{$key}>$attendant::USCNprov{$key}</option>\n";
    }
    foreach my $key (&sort_hash(\%attendant::CNprovinces)) {
      print "<option value=\"$key\" $selected{$key}>$attendant::CNprovinces{$key}</option>\n";
    }
    print "</select></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td valign=top width=170>Zipcode: </td>\n";
    print "    <td valign=top><input type=text name=\"shipzip\" value=\"$query{'shipzip'}\" size=20 maxlength=14></td>\n";
    print "  </tr>\n";

    if ($query{'shipcountry'} eq "") {
      $query{'shipcountry'} = "US";
    }
    $selected{"$query{'shipcountry'}"} = "selected";

    print "  <tr>\n";
    print "    <td valign=top width=170>Country: </td>\n";
    print "    <td valign=top><select name=\"shipcountry\">\n";
    foreach my $key (&sort_hash(\%attendant::countries)) {
      print "<option value=\"$key\" $selected{$key}>$attendant::countries{$key}</option>\n";
    }
    print "</select></td>\n";
    print "  </tr>\n";
  }

  if (($attendant::accountFeatures->get('attendant_suppressemail') != 1) || ($attendant::accountFeatures->get('attendant_suppressphone') != 1)) {
    print "  <tr>\n";
    print "    <td colspan=2>&nbsp;</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td colspan=2 bgcolor=\"#f4f4f4\"><b>Instant Contact Information</b></td>\n";
    print "  </tr>\n";

    if ($attendant::accountFeatures->get('attendant_suppressemail') != 1) {
      print "  <tr>\n";
      print "    <td valign=top width=170>Email: *</td>\n";
      print "    <td valign=top><input type=email name=\"email\" value=\"$query{'email'}\" size=20 maxlength=50></td>\n";
      print "  </tr>\n";
    }

    if ($attendant::accountFeatures->get('attendant_suppressphone') != 1) {
      print "  <tr>\n";
      print "    <td valign=top width=170>Phone #: </td>\n";
      print "    <td valign=top><input type=tel name=phone value=\"$query{'phone'}\" size=20 maxlength=30></td>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <td valign=top width=170>Fax #: </td>\n";
      print "    <td valign=top><input type=tel name=\"fax\" value=\"$query{'fax'}\" size=20 maxlength=30></td>\n";
      print "  </tr>\n";
    }
  }

  if ($attendant::accountFeatures->get('attendant_edit_cc') == 1) {
    print "  <tr>\n";
    print "    <td colspan=2>&nbsp;</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td colspan=2 bgcolor=\"#f4f4f4\"><b>Credit Card Information</b></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td valign=top width=170>Card Number: </td>\n";
    print "    <td valign=top><input type=text name=\"cardnumber\" value=\"$query{'cardnumber'}\" size=20 maxlength=20></td>\n";
    print "  </tr>\n";

    my @now = gmtime(time);
    my $max_year = (($now[5]+1900) + 12);
  
    my $exp_month = substr($query{'exp'},0,2);
    my $exp_year = substr($query{'exp'},3,2);

    print "  <tr>\n";
    print "    <td valign=top width=170>Exp Date: </td>\n";
    print "    <td valign=top><select name=\"exp_month\">";
    %selected = ();
    $selected{$exp_month} = " selected";
    for (my $j=1; $j<=12; $j++) {
      my $month = sprintf("%02d", $j);
      printf("<option value=\"%02d\"$selected{$month}> %02d\n", $j, $j);
    }
    print "</select> <select name=\"exp_year\">";
    %selected = ();
    $selected{$exp_year} = " selected";
    for (my $j=2000; $j<=$max_year; $j++) {
      my $year = sprintf("%02d", substr($j,2,2));
      printf("<option value=\"%02d\"$selected{$year}> %04d\n", $year, $j);
    }
    print "</select></td>\n";
    print "  </tr>\n";

    if ($attendant::accountFeatures->get('attendant_cardsallowed') =~ /(checking|savings)/i) {
      print "  <tr>\n";
      print "    <td colspan=2>&nbsp;</td>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <td colspan=2 bgcolor=\"#f4f4f4\"><b>ACH Billing Information</b></td>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <td colspan=2><b>NOTE:</b> Fields are for data entry only.  Once entered, data is stored in credit card number field.</td>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <td valign=top width=170>Routing Number: </td>\n";
      print "    <td valign=top><input type=text name=\"routingnum\" value=\"$query{'routingnum'}\" size=10 maxlength=9></td>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <td valign=top width=170>Bank Account Number: </td>\n";
      print "    <td valign=top><input type=text name=\"accountnum\" value=\"$query{'accountnum'}\" size=20 maxlength=20></td>\n";
      print "  </tr>\n";

      #my %selected = ();
      #$selected{$query{'accttype'}} = " selected";
      #print "  <tr>\n";
      #print "    <td valign=top width=170>Account Type: </td>\n";
      #print "    <td valign=top><select name=\"accttype\">\n";
      #print "<option value=\"checking\" $selected{'checking'}>Checking</option>\n";
      #print "<option value=\"savings\" $selected{'savings'}>Savings</option>\n";
      #print "</select></td>\n";
      #print "  </tr>\n";

      #if ($attendant::chkprocessor =~ /^(echo|testprocessor)$/) {
      #  $selected{$query{'acctclass'}} = " selected";
      #  print "  <tr>\n";
      #  print "    <td valign=top width=170>Account Class: </td>\n";
      #  print "    <td valign=top><select name=\"acctclass\">\n";
      #  print "<option value=\"personal\" $selected{'personal'}>Personal</option>\n";
      #  print "<option value=\"business\" $selected{'business'}>Business</option>\n";
      #  print "</select></td>\n";
      #  print "  </tr>\n";
      #}
    }
  }

  if ($attendant::accountFeatures->get('attendant_suppresspw') != 1) {
    print "  <tr>\n";
    print "    <td colspan=2>&nbsp;</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td colspan=2 bgcolor=\"#f4f4f4\"><b>Login Password</b></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td valign=top width=170>Password: </td>\n";
    print "    <td><input type=password name=\"passwd1\" value=\"$query{'passwd1'}\" size=11 maxlength=19></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td valign=top width=170>Password (Confirm): </td>\n";
    print "    <td><input type=password name=\"passwd2\" value=\"$query{'passwd2'}\" size=11 maxlength=19></td>\n";
    print "  </tr>\n";
  }

  print "</table>\n";

  print "</td>\n";
  print "  </tr>\n";

  if ($attendant::dontupdate != 1) {
    print "  <tr>\n";
    print "    <td colspan=2>&nbsp;</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td colspan=2 align=center><input type=submit value=\"Submit\"> &nbsp; <input type=reset value=\"Reset\"></td></form>\n";
    print "  </tr>\n";    
  }

  print "</table>\n";

  if (($attendant::path_home eq "") || ($attendant::path_home eq "http:///")) {
    $attendant::path_home = "http://" . $ENV{'SERVER_NAME'} . $ENV{'SCRIPT_NAME'};
    #$path_home = "attendant.html";
  }
  if ($attendant::desc_home eq "") {
    $attendant::desc_home = "Return Home";
  }
  print "<p><form><input type=button name=\"submit\" value=\"Close Window\" onClick=\"self.close();\"></form>\n";

  &html_tail();

  return;
}

sub display_profile {
  my %query = @_;
  
  my %selected;

  # safeguard account against hacks
  $query{'username'} =~ s/[^_0-9a-zA-Z\-\@\.]//g; # remove all non-allowed characters
  $query{'password'} =~ s/[^_0-9a-zA-Z]//g; # remove all non-allowed characters
  $query{'passwd1'} =~ s/[^_0-9a-zA-Z]//g; # remove all non-allowed characters

  if (($query{'username'} !~ /\w/) || (($query{'password'} !~ /\w/) && ($query{'passwd1'} !~ /\w/))) {
    # reject usernames/passwords which do not contain at least 1 alphanumeric character
    my $message = "<font class=\"badcolor\"><b>Invalid Username or Password. Please try again. [1]</b></font>";
    my $page_title = "Edit Account Information";
    &response_page($message, $page_title);
    exit;
  }
  
  if ($attendant::accountFeatures->get('attendant_nooutputflag') == 1) {
    return;
  }
  
  if ($attendant::dontupdate != 1) {
    my $result = &checkunpw(%query);
  
    if ($result eq "cancel") {
      my $message = "<font class=\"badcolor\"><b>Sorry, your account has been previously cancelled and may not be accessed through this interface.</b></font>";
      my $page_title = "Edit Account Information";
      &response_page($message, $page_title);
      return "failure";
    }
    elsif ($result ne "success") {
      my $message = "<font class=\"badcolor\"><b>Sorry, the Username and Password combination entered was not found in the database.</font>\n";
      $message .= "<br>Please try again and be careful to use the proper CAPITALIZATION.</b>";
      my $page_title = "Edit Account Information";
      &response_page($message, $page_title);
      return "failure";
    }
  }

  my %data;
  if ($attendant::accountFeatures->get('attendant_dontquery') != 1) {
    # query the customer profile data
    %data = &get_profile_info("$query{'username'}");
  }
  else {
    # use data already present
    %data = %query;    
  }

  #foreach my $key (sort keys %data) {
  #  #$query{"$key"} = $data{"$key"};
  #}

  if (($data{'enccardnumber'} ne "") && ($data{'length'} ne "")) {
    my $cardnumber = &rsautils::rsa_decrypt_file($data{'enccardnumber'},$data{'length'},"print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");
    $data{'cardtype'} = &detect_cardtype("$cardnumber");
    if ($cardnumber =~ /\d{9} \d/) {
      ($data{'routingnum'}, $data{'accountnum'}) = split(/ /, $cardnumber, 2);
    }
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

    delete $query{'enccardnumber'};
    delete $query{'length'};

  # now build the entire page here
  &html_head("Edit Account Information");

  if ($query{'error_message'} ne "") {
    print "<font class=\"badcolor\">$query{'error_message'}</font>\n";
  }
  elsif ($query{'response_message'} ne "") {
    print "<font class=\"goodcolor\">$query{'response_message'}</font>\n";
  }

  print "<table border=0 cellspacing=0 cellpadding=2>\n";
  print "  <tr>\n";
  print "    <td colspan=2><h1>Your Account Information</h1></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=2>Please review your information for accuracy.</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=top>\n";

  # build contact information section
  print "<table border=0 cellspacing=0 cellpadding=2>\n";
  print "  <tr>\n";
  print "    <td colspan=2 bgcolor=\"#f4f4f4\"><b>Billing Address Information</b></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=top width=170>Name: </td>\n";
  print "    <td valign=top>$data{'name'}</td>\n";
  print "  </tr>\n";

  if ($data{'company'} ne "") {
    print "  <tr>\n";
    print "    <td valign=top width=170>Company: </td>\n";
    print "    <td valign=top>$data{'company'}</td>\n";
    print "  </tr>\n";
  }

  print "  <tr>\n";
  print "    <td valign=top width=170>Address Line 1: </td>\n";
  print "    <td valign=top>$data{'addr1'}</td>\n";
  print "  </tr>\n";

  if ($data{'addr2'} ne "") {
    print "  <tr>\n";
    print "    <td valign=top width=170>Address Line 2: </td>\n";
    print "    <td valign=top>$data{'addr2'}</td>\n";
    print "  </tr>\n";
  }

  print "  <tr>\n";
  print "    <td valign=top width=170>City: </td>\n";
  print "    <td valign=top>$data{'city'}</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=top width=170>State: </td>\n";
  print "    <td valign=top>$data{'state'}</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=top width=170>Zipcode: </td>\n";
  print "    <td valign=top>$data{'zip'}</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td valign=top width=170>Country: </td>\n";
  print "    <td valign=top>$data{'country'}</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=2>&nbsp;</td>\n";
  print "  </tr>\n";

  if ($attendant::accountFeatures->get('attendant_edit_shipping') == 1) {
    print "  <tr>\n";
    print "    <td colspan=2 bgcolor=\"#f4f4f4\"><b>Shipping Address Information</b></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td valign=top width=170>Name: </td>\n";
    print "    <td valign=top>$data{'shipname'}</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td valign=top width=170>Address Line 1: </td>\n";
    print "    <td valign=top>$data{'shipaddr1'}</td>\n";
    print "  </tr>\n";

    if ($data{'addr2'} ne "") {
      print "  <tr>\n";
      print "    <td valign=top width=170>Address Line 2: </td>\n";
      print "    <td valign=top>$data{'shipaddr2'}</td>\n";
      print "  </tr>\n";
    }

    print "  <tr>\n";
    print "    <td valign=top width=170>City: </td>\n";
    print "    <td valign=top>$data{'shipcity'}</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td valign=top width=170>State: </td>\n";
    print "    <td valign=top>$data{'shipstate'}</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td valign=top width=170>Zipcode: </td>\n";
    print "    <td valign=top>$data{'shipzip'}</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td valign=top width=170>Country: </td>\n";
    print "    <td valign=top>$data{'shipcountry'}</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td colspan=2>&nbsp;</td>\n";
    print "  </tr>\n";
  }

  if (($attendant::accountFeatures->get('attendant_suppressemail') != 1) || ($attendant::accountFeatures->get('attendant_suppressphone') != 1)) {
    print "  <tr>\n";
    print "    <td colspan=2 bgcolor=\"#f4f4f4\"><b>Instant Contact Information</b></td>\n";
    print "  </tr>\n";

    if ($attendant::accountFeatures->get('attendant_suppressemail') != 1) {
      print "  <tr>\n";
      print "    <td valign=top width=170>Email: </td>\n";
      print "    <td valign=top>$data{'email'}</td>\n";
      print "  </tr>\n";
    }

    if ($attendant::accountFeatures->get('attendant_suppressphone') != 1) {
      print "  <tr>\n";
      print "    <td valign=top width=170>Phone #: </td>\n";
      print "    <td valign=top>$data{'phone'}</td>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <td valign=top width=170>Fax #: </td>\n";
      print "    <td valign=top>$data{'fax'}</td>\n";
      print "  </tr>\n";
    }

    print "  <tr>\n";
    print "    <td colspan=2>&nbsp;</td>\n";
    print "  </tr>\n";
  }

  if ($attendant::accountFeatures->get('attendant_edit_cc') == 1) {
    if ($data{'cardtype'} !~ /(checking|savings)/i) {
      print "  <tr>\n";
      print "    <td colspan=2 bgcolor=\"#f4f4f4\"><b>Credit Card Information</b></td>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <td valign=top width=170>Card Number: </td>\n";
      print "    <td valign=top>$data{'cardnumber'}</td>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <td valign=top width=170>Exp Date: </td>\n";
      print "    <td valign=top>$data{'exp'}</td>\n";
      print "  </tr>\n";
    }

    if ($data{'cardtype'} =~ /(checking|savings)/i) {
      print "  <tr>\n";
      print "    <td colspan=2>&nbsp;</td>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <td colspan=2 bgcolor=\"#f4f4f4\"><b>ACH Billing Information</b></td>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <td valign=top width=170>Routing Number: </td>\n";
      print "    <td valign=top>$data{'routingnum'}</td>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <td valign=top width=170>Bank Account Number: </td>\n";
      print "    <td valign=top>$data{'accountnum'}</td>\n";
      print "  </tr>\n";

      #if ($data{'accttype'} ne "") {
      #  print "  <tr>\n";
      #  print "    <td valign=top width=170>Acct Type: </td>\n";
      #  print "    <td valign=top>Acct Type: $data{'accttype'}</td>\n";
      #  print "  </tr>\n";
      #}
      #if ($data{'acctclass'} ne "") {
      #  print "  <tr>\n";
      #  print "    <td valign=top width=170>Acct Class: </td>\n";
      #  print "    <td valign=top>$data{'acctclass'}</td>\n";
      #  print "  </tr>\n";
      #}
    }

    print "  <tr>\n";
    print "    <td colspan=2>&nbsp;</td>\n";
    print "  </tr>\n";
  }

  if ($attendant::accountFeatures->get('attendant_suppresspw') != 1) {
    print "  <tr>\n";
    print "    <td colspan=2 bgcolor=\"#f4f4f4\"><b>Login Password</b></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td valign=top width=170>Password: </td>\n";
    print "    <td>$data{'password'}</td>\n";
    print "  </tr>\n";
  }
  print "</table>\n";

  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  if (($attendant::path_home eq "") || ($attendant::path_home eq "http:///")) {
    $attendant::path_home = "http://" . $ENV{'SERVER_NAME'} . $ENV{'SCRIPT_NAME'};
    #$path_home = "attendant.html";
  }
  if ($attendant::desc_home eq "") {
    $attendant::desc_home = "Return Home";
  }
  print "<p><form><input type=button name=\"submit\" value=\"Close Window\" onClick=\"self.close();\"></form>\n";

  &html_tail();

  return;
}

sub checkunpw {
  my %query = @_;

  # safeguard account against hacks - 08/15/05
  $query{'username'} =~ s/[^_0-9a-zA-Z\-\@\.]//g; # remove all non-allowed characters
  $query{'password'} =~ s/[^0-9a-zA-Z]//g; # remove all non-allowed characters

  if ($query{'username'} !~ /\w/) {
    # reject usernames which do not contain at least 1 alphanumeric character
    print "Invalid Username\n";
    exit;
  }

  if ($query{'password'} !~ /\w/) {
    # reject usernames which do not contain at least 1 alphanumeric character
    print "Invalid Password\n";
    exit;
  }

  if (($query{'username'} !~ /\w/) || ($query{'password'} !~ /\w/)) {
   return "failure";
  }

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor($attendant::query{'publisher-name'});
  my $sth = $dbh->prepare(q{
      SELECT username,status
      FROM customer
      WHERE username=?
      AND password=?
    }) or die "Can't prepare: $DBI::errstr";
  $sth->execute("$query{'username'}", "$query{'password'}") or die "Can't execute: $DBI::errstr";
  my ($chkusername,$chkstatus) = $sth->fetchrow;
  $sth->finish;

  if ($chkusername eq "")  {
    return "failure";
  }
  elsif (($chkstatus =~ /cancel/i)) {
    return "canelled";
  }
  else {
    return "success";
  }
}

sub html_head {
  my ($title) = @_;

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";

  print "<script type=\"text/javascript\"><!--\n";
  print "function closeresults() \{\n";
  print "  resultsWindow = window.close('results');\n";
  print "\}\n";
  print "//-->\n";
  print "</script>\n";

  if ($attendant::accountFeatures->get('css-link') ne "") {
    printf("<link href=\"%s\" type=\"text/css\" rel=\"stylesheet\">\n", $attendant::accountFeatures->get('css-link'));
  }
  else {
    print "<style type=\"text/css\">\n";
    print "<!--\n";
    print "th { font-family: $attendant::fontface; font-size: 10pt; color: $attendant::goodcolor }\n";
    print "td { font-family: $attendant::fontface; font-size: 9pt; color: $attendant::goodcolor }\n";
    print ".badcolor { color: $attendant::badcolor }\n";
    print ".goodcolor { color: $attendant::goodcolor }\n";
    print ".larger { font-size: 12pt }\n";
    print ".smaller { font-size: 9pt }\n";
    print ".short { font-size: 8% }\n";
    print ".itemscolor { background-color: $attendant::goodcolor; color: $attendant::backcolor }\n";
    print ".itemrows { background-color: $attendant::itemrow }\n";
    print ".info { position: static }\n";
    print "#tail { position: static }\n";
    print "-->\n";
    print "</style>\n";
  }

  print "<title>$title</title>\n";
  print "</head>\n";

  if ($attendant::accountFeatures->get('backimage') ne "") {
    printf("<body background=\"%s\" bgcolor=\"$attendant::backcolor\" link=\"$attendant::goodcolor\" text=\"$attendant::goodcolor\" alink=\"$attendant::alinkcolor\" vlink=\"$attendant::vlinkcolor\">\n", $attendant::accountFeatures->get('backimage'));
  }
  else {
    print "<body bgcolor=\"$attendant::backcolor\" link=\"$attendant::goodcolor\" text=\"$attendant::goodcolor\" alink=\"$attendant::alinkcolor\" vlink=\"$attendant::vlinkcolor\">\n";
  }

  if ($attendant::accountFeatures->get('image-link') ne "") {
    printf("<div align=\"%s\"><img src=\"%s\" border=0></div>\n", $attendant::accountFeatures->get('image-placement'), $attendant::accountFeatures->get('image-link'));
  }

  print "<div align=center>\n";

  return;
}

sub html_tail {

  print "</div>\n";

  print "<body>\n";
  print "</html>\n";

  return;
}

sub detect_cardtype {
  my ($cardnumber) = @_;

  my ($cardtype);

  # test for ACH type
  if ($cardnumber =~ / /) {
    $cardtype = "Checking";
    return $cardtype;
  }

  # test for credit card type
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
  else {
    $cardtype = "UNKNOWN";
  }

  return $cardtype;
}

sub get_profile_info {
  my ($username) = @_; 

  $username =~ s/[^_0-9a-zA-Z\-\@\.]//g; # remove all non-allowed characters
 
  my %data;
  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor($attendant::query{'publisher-name'});
  my $sth = $dbh->prepare(q{
      SELECT *
      FROM customer
      WHERE username=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth->execute("$username") or die "Cannot execute: $DBI::errstr";
  my $results = $sth->fetchrow_hashref();
  $sth->finish;
  
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

