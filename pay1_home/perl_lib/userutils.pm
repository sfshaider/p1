#!/usr/local/bin/perl

package userutils;
 
require 5.001;

use CGI;
use DBI;
use rsautils;
use miscutils;
use constants qw(%countries %USstates %USterritories %CNprovinces);

sub new {
  my $type = shift;
  %query = @_;

  $dbh = &miscutils::dbhconnect("$merchant");

  local($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());

  $_ = $query{'uname'};
  s/[^0-9a-zA-Z]//g;
  $query{'uname'} = $_;

  $_ = $query{'passwrd1'};
  s/[^0-9a-zA-Z]//g;
  $query{'passwrd1'} = $_;

  $_ = $query{'passwrd2'};
  s/[^0-9a-zA-Z]//g;
  $query{'passwrd2'} = $_;


  $badcolor = "\#ff0000";
  $badcolortxt = "RED";
  $goodcolor = "\#000000";
  $backcolor = "\#ffffff";
  $linkcolor = $goodcolor;
  $textcolor = $goodcolor;
  $alinkcolor = "\#187f0a";
  $vlinkcolor = "\#0b1f48";
  # $backimage = "path to background image";
  $fontface = "Arial,Helvetica,Univers,Zurich BT";
  @standardfields = ('card-name','card-address1','card-address2','card-city','card-state','card-zip','card-country',
                     'card-number','card-exp','card-type','tel','fax','email',
                     'shipname','address1','address2','city','state','zip','country'
                    );

  %USstates = %constants::USstates;

  %USterritories = %constants::USterritories;

  %CNprovences = %constants::CNprovinces;

  %countries = %constants::countries;

  return [], $type;

}

sub member_info {
  $sth = $dbh->prepare(qq{
      select password,email
      from customer
      where username='$query{'username'}'
      }) or die "Can't do: $DBI::errstr";

  $sth->execute or die "Can't execute: $DBI::errstr";
  ($pword,$query{'email'}) = $sth->fetchrow;
  $sth->finish;

  if (($pword ne "") && ($pword eq $query{'password'})) {
    $match = "1";
    return();
#    &update_screen1_badcard;
#    &update_screen1_body;
#    &update_screen1_pairs;
#    &update_screen1_tail;

  } else {
      $message = "Sorry, the Username and Password combination entered were not found in the database.  Please try again and becareful to use the proper CAPITALIZATION.";
      &response_page;
  }
}

sub response_page {
  print "Content-Type: text/html\n\n";
  print "<html>\n";
  print "<head>\n";
  print "<body bgcolor=\"#ffffff\">\n";
  print "<h3>$message</h3>\n";
  print "</body>\n";
  print "</html>\n";
}

###### Start Page 1 Table Pay Page
#  update_screen1_head
#  update_screen1_badcard
#  update_screen1_body
#  update_screen1_pairs
#  update_screen1_tail
#  un_pw 
#  input_check
#


sub update_screen1_head {
  # print "Content-Type: text/html\n\n";
  print "<HTML>\n";
  print "<HEAD>\n";
  print "<TITLE>Update User Information</TITLE> \n";
  print "</HEAD>\n";
  if ($backimage eq "") {
    print "<BODY BGCOLOR=\"$backcolor\" LINK=\"$goodcolor\" TEXT=\"$goodcolor\" ALINK=\"$alinkcolor\" VLINK=\"$vlinkcolor\">\n";
  }
  else {
    print "<BODY BGCOLOR=\"$backcolor\" LINK=\"$goodcolor\" TEXT=\"$goodcolor\" ALINK=\"$alinkcolor\" VLINK=\"$vlinkcolor\" background=\"$backimage\">\n";
  }

  if (($query{'image-placement'} ne "left") && ($query{'image-link'} ne "")) {
    print "<div align=center><center>\n";
    print "<img src=\"$query{'image-link'}\"><p><p>\n";
    print "</center></div><p>\n";
  }
  else {
    print "<br>\n";
  }
    print "<table border=\"1\" cellpadding=\"4\" width=\"600\">\n";
    print "<tr valign=\"top\" align=\"left\">\n";
    print "<TD WIDTH=50 HEIGHT=1 rowspan=\"1\"> &nbsp; </TD>\n";
    print "<TD WIDTH=\"150\" HEIGHT=\"1\" rowspan=\"1\"> &nbsp; </TD>\n";
    print "<TD WIDTH=\"440\" HEIGHT=\"1\" rowspan=\"1\"> &nbsp; </TD></tr>\n";
}

sub update_screen1_badcard {
  if ($query{'MErrMsg'} ne "") {
    print "<tr><td></td><td colspan=\"2\" align=\"left\"><FONT SIZE=\"2\" FACE=\"$fontface\" color=\"$goodcolor\">\n";
    print "<font size=+1>There seems to be a problem with the information you entered.\n";
    print "<p>\n";
    if ($query{'MErrMsg'} =~ /fails LUHN-10 check/) {
      print "The number you entered is NOT a valid credit card number.  Please re-enter your credit ";
      print "card number and check it closely before resubmitting.\n";
      $color{'card-number'} = $badcolor;
    }
    else {
      print "The Credit Card Processor has returned the following error message: <br><b>$query{'MErrMsg'}</b>\n";
    }
    print "<p>\n";
    print "If you feel that you may have entered your billing information incorrectly or if \n";
    print "you wish to use another card, Please Re-Enter the Information Below.\n";
    print "<p>\n";
    print "If you feel this message is in error please call your credit card issuer for assistance.\n";
    print "</font><p>\n";
  }

  if (($error => 1) && ($query{'pass'} == 1)) {
    print "<tr><td colspan=1></td><td align=left colspan=2><FONT SIZE=\"2\" FACE=\"$fontface\" color=\"$goodcolor\">\n";
    print "Some <b>Required Information</b> has not been filled in correctly.  <br>Please re-enter \n";
    print "the information in the </font><font color=\"$badcolor\"><b>fields marked in $badcolortxt</b>.</font><br><br>";
    print "</TR>\n";
  }

}


sub update_screen1_body {

  print "<tr><td rowspan=50> &nbsp; ";
  print "<FORM METHOD=post ACTION=\"$path_cgi\"></td>\n";
  print "<td align=\"left\" colspan=\"2\"><font face=\"$payutils::fontface\" size=\"+1\" color=\"$payutils::goodcolor\">";
  print "Please Enter Only the Information you wish to change below:<br></font>";
  print "<font face=\"$payutils::fontface\" size=\"2\" color=\"$payutils::goodcolor\">Upon submission an email will be sent to the current email address on record confirming this change request.</font>\n";
  if ($query{'app-level'} > 1) {
    print "<table width=\"80%\"><tr><td><font size=\"3\" face=\"arial\"><b>NOTICE:</b> Address Verification is enforced.  ";
    print "Please enter your address exactly as it appears on your credit card statement or any future charges will be declined.";
    print "</font></td></tr></table>\n";
  }

  print "</td></tr>\n";
  print "<tr><td align=right><font size=\"2\" color=\"$color{'card-name'}\" FACE=\"$fontface\">Name:<b>*</b></font></td>";
  print "<td align=left><INPUT TYPE=\"text\" NAME=\"card-name\" SIZE=30 VALUE=\"$query{'card-name'}\" MAXLENGTH=\"39\"></td></tr>\n";

  if ($query{'showcountry'} eq "yes") {
    print "<tr><td align=right><font size=\"2\" color=\"$color{'card-company'}\" FACE=\"$fontface\">Company:<b>*</b></font></td>";
    print "<td align=left><INPUT TYPE=\"text\" NAME=\"card-company\" SIZE=30 VALUE=\"$query{'card-company'}\" MAXLENGTH=\"39\"></td></tr>\n";
  }

  print "<tr><td align=right><font size=\"2\" FACE=\"$fontface\" color=\"$color{'card-address1'}\">Billing Address:<b>*</b></font></td>";
  print "<td align=left><INPUT TYPE=\"text\" NAME=\"card-address1\" SIZE=30 VALUE=\"$query{'card-address1'}\" MAXLENGTH=\"39\"></td></tr>\n";

  print "<tr><td align=right><font size=\"2\" FACE=\"$fontface\" color=\"$color{'card-address2'}\">Line 2: </td>\n";
  print "<td align=left><INPUT TYPE=\"text\" NAME=\"card-address2\" SIZE=30 VALUE=\"$query{'card-address2'}\" MAXLENGTH=\"39\"></td></tr>\n";

  print "<tr><td align=right><font size=\"2\" FACE=\"$fontface\" color=\"$color{'card-city'}\">City:<b>*</b></td>";
  print "<td align=left><INPUT TYPE=\"text\" NAME=\"card-city\" SIZE=20 VALUE=\"$query{'card-city'}\" MAXLENGTH=30></td></tr>";

  if ($query{'nostatelist'} ne "yes") {
    print "<tr><td ALIGN=\"right\"><font size=\"2\" FACE=\"$fontface\" color=\"$color{'card-state'}\">State/Provence: </td><td align=\"left\"><SELECT NAME=\"card-state\">\n";

    foreach $key (sort keys %USstates) {
      if ($key eq $query{'card-state'}) {
        print "<option value=\"$key\" selected>$USstates{$key}</option>\n";
      }
      else {
        print "<option value=\"$key\">$USstates{$key}</option>\n";
      }
    }
    foreach $key (sort keys %USterritories) {
      if ($key eq $query{'card-state'}) {
        print "<option value=\"$key\" selected>$USterritories{$key}</option>\n";
      }
      else {
        print "<option value=\"$key\">$USterritories{$key}</option>\n";
      }
    }
    foreach $key (sort keys %CNprovences) {
      if ($key eq $query{'card-state'}) {
        print "<option value=\"$key\" selected>$CNprovences{$key}</option>\n";
      }
      else {
        print "<option value=\"$key\">$CNprovences{$key}</option>\n";
      }
    }
    print "</select></td></tr>\n";
  } else {
    print "<tr><td ALIGN=\"right\"><font size=\"2\" FACE=\"$fontface\" color=\"$color{'card-state'}\">State/Provence:<b>*</b></td>";
    print "<td align=\"left\"><INPUT TYPE=\"text\" NAME=\"card-state\" size=\"20\" VALUE=\"$query{'card-state'}\" MAXLENGTH=19></td></tr>\n";
  }
  print "<tr><td ALIGN=\"right\"><font size=\"2\" FACE=\"$fontface\" color=\"$color{'card-prov'}\">International Provence: </td>";
    print "<td align=\"left\"><INPUT TYPE=\"text\" NAME=\"card-prov\" size=\"20\" VALUE=\"$query{'card-prov'}\" MAXLENGTH=19></td></tr>\n";


  print "<tr><td align=right><font size=\"2\" FACE=\"$fontface\" color=\"$color{'card-zip'}\">Zip/Postal Code:<b>*</b></font></td>";
  print "<td align=left><INPUT TYPE=\"text\" NAME=\"card-zip\" SIZE=10 VALUE=\"$query{'card-zip'}\" MAXLENGTH=10></td></tr>\n";

  if ($query{'nocountrylist'} ne "yes") {
    print "<tr><td align=right><font size=\"2\" FACE=\"$fontface\">Country: </td><td align=left><SELECT NAME=\"card-country\">\n";
    foreach $var (@countries) {
      if ($var eq $query{'card-country'}) {
        print "<option value=\"$var\" selected>$var</option>\n";
      }
      else {
        print "<option value=\"$var\">$var</option>\n";
      }
    }
    print "</select></td></tr>\n";
  }
  else {
    print "<tr><td align=right><font size=\"2\" FACE=\"$fontface\" color=\"$color{'card-country'}\">Country: </td>";
    print "<td align=left><INPUT TYPE=\"text\" NAME=\"card-country\" SIZE=15 VALUE=\"$query{'card-country'}\" MAXLENGTH=20></td></tr>\n";
  }
  if ($query{'paymethod'} ne "check") {
    print "<tr><td align=right><font size=\"2\" FACE=\"$fontface\" color=\"$color{'card-type'}\">Card Type:<b>*</b></font></td>";
    print "<td align=left>";
    $checked{$query{'card-type'}} = ' checked';
    print " <input type=\"radio\" name=\"card-type\" value=\"Visa\"$checked{'Visa'}> <font size=\"2\" FACE=\"$fontface\" color=\"$goodcolor\">Visa</font>";
    print " <input type=\"radio\" name=\"card-type\" value=\"Mastercard\"$checked{'Mastercard'}> <font size=\"2\" FACE=\"$fontface\" color=\"$goodcolor\">Mastercard</font>";
    if ($query{'card-allowed'} =~ /Amex/i) {
      print " <input type=\"radio\" name=\"card-type\" value=\"Amex\"$checked{'Amex'}> <font size=\"2\" FACE=\"$fontface\" color=\"$goodcolor\">Amex</font>";
    }
    if ($query{'card-allowed'} =~ /Discover/i) {
      print " <input type=\"radio\" name=\"card-type\" value=\"Discover\"$checked{'Discover'}> <font size=\"2\" FACE=\"$fontface\" color=\"$goodcolor\">Discover</font>";
    }
    if ($query{'card-allowed'} =~ /Diners/i) {
      print " <input type=\"radio\" name=\"card-type\" value=\"Diners\"$checked{'Diners'}> <font size=\"2\" FACE=\"$fontface\" color=\"$goodcolor\">Diners Club</font>";
    }
    print "</td></tr>\n";

    print "<tr><td align=right><font size=\"2\" FACE=\"$fontface\" color=\"$color{'card-number'}\">Credit Card \#:<b>*</b></font></td>";
    print "<td align=left><input type=\"text\" name=\"card-number\" value=\"$query{'card-number'}\" size=16 maxlength=20></td></tr>\n";

    print "<tr><td align=right><font size=\"2\" FACE=\"$fontface\" color=\"$color{'card-exp'}\">Exp.Date:<b>*</b></font></td> ";
    print "<td align=left>\n";
    print "<select name=\"month-exp\">\n";
    @months = ("01","02","03","04","05","06","07","08","09","10","11","12");
    foreach $var (@months) {
      if ($var eq $query{'month-exp'}) {
        print "<option value=\"$var\" selected>$var</option>\n";
      }
      else {
        print "<option value=\"$var\">$var</option>\n";
      }
    }
    print "</select> ";

    print "<select name=\"year-exp\">\n";

    @years = ("1998","1999","2000","2001","2002","2003","2004","2005","2006","2007","2008","2009","2010");
    if ($query{'year-exp'} eq ""){
      $query{'year-exp'} = "99";
    }
    foreach $var (@years) {
      $val = substr($var,2,2);
      if ($val eq $query{'year-exp'}) {
        print "<option value=\"$val\" selected>$var</option>\n";
      }
      else {
        print "<option value=\"$val\">$var</option>\n";
      }
    }
    print "</select>\n";
    print "</td></tr>\n";
  }
  print "<tr><td align=right><font size=\"2\" FACE=\"$fontface\" color=\"$color{'email'}\">Email Address:<b>*</b></font></td>";
  print "<td align=left><input type=\"text\" name=\"email\" value=\"$query{'email'}\" size=30 MAXLENGTH=\"39\"></td></tr>\n";

  print "<tr><td align=right><font size=\"2\" FACE=\"$fontface\" color=\"$color{'tel'}\">Day Phone \#:</td>";
  print "<td align=left><input type=\"text\" name=\"tel\" value=\"$query{'tel'}\" size=15 maxlength=15></td></tr>\n";

  print "<tr><td align=right><font size=\"2\" FACE=\"$fontface\" color=\"$color{'fax'}\">Night Phone/FAX \#:</td>";
  print "<td align=left><input type=\"text\" name=\"fax\" value=\"$query{'fax'}\" size=15 maxlength=15></td></tr>\n";


  if ($query{'shipinfo'} == 1) {

    print "<p>";
    print "<tr><td align=left colspan=2><font  face=\"$fontface\" size=+1 color=\"$goodcolor\">";
    if ($query{'shipinfo-label'} ne ""){
      print "$query{'shipinfo-label'}</font></td>\n";
    } else {
      print "Please Enter Your Shipping Information Below</font></td>\n";
    }
    print "\n";
    print "<tr><td align=left colspan=2><input type=\"checkbox\" name=\"shipsame\" value=\"yes\"";

    if ($query{'shipsame'} eq "yes") {
      print " checked";
    }
    print "><font size=\"2\" FACE=\"$fontface\" color=\"$goodcolor\"> CHECK HERE if Address is Same as Billing Address</font></td></tr>\n";

    print "<tr><td align=right><font size=\"2\" FACE=\"$fontface\" color=\"$color{'shipname'}\">Name:</td>";
    print "<td align=left><INPUT TYPE=\"text\" NAME=\"shipname\" SIZE=30 VALUE=\"$query{'shipname'}\" MAXLENGTH=\"39\"></td></tr>\n";

    print "<tr><td align=right><font size=\"2\" FACE=\"$fontface\" color=\"$color{'address1'}\">Address:</td>";
    print "<td align=left><INPUT TYPE=\"text\" NAME=\"address1\" SIZE=30 VALUE=\"$query{'address1'}\" MAXLENGTH=\"39\"></td></tr>\n";

    print "<tr><td align=right><font size=\"2\" FACE=\"$fontface\" color=\"$color{'address2'}\">Line 2:</td>";
    print "<td align=left><INPUT TYPE=\"text\" NAME=\"address2\" SIZE=30 VALUE=\"$query{'address2'}\" MAXLENGTH=\"39\"></td></tr>\n";

    print "<tr><td align=right><font size=\"2\" FACE=\"$fontface\" color=\"$color{'city'}\">City:</td>";
    print "<td align=left><INPUT TYPE=\"text\" NAME=\"city\" SIZE=20 VALUE=\"$query{'city'}\" MAXLENGTH=30></td></tr>";

  if ($query{'nostatelist'} ne "yes") {
    print "<tr><td ALIGN=\"right\"><font size=\"2\" FACE=\"$fontface\" color=\"$color{'state'}\">State/Provence: </td><td align=\"left\"><SELECT NAME=\"state\">\n";

    foreach $key (sort keys %USstates) {
      if ($key eq $query{'state'}) {
        print "<option value=\"$key\" selected>$USstates{$key}</option>\n";
      }
      else {
        print "<option value=\"$key\">$USstates{$key}</option>\n";
      }
    }
    foreach $key (sort keys %USterritories) {
      if ($key eq $query{'state'}) {
        print "<option value=\"$key\" selected>$USterritories{$key}</option>\n";
      }
      else {
        print "<option value=\"$key\">$USterritories{$key}</option>\n";
      }
    }
    foreach $key (sort keys %CNprovences) {
      if ($key eq $query{'state'}) {
        print "<option value=\"$key\" selected>$CNprovences{$key}</option>\n";
      }
      else {
        print "<option value=\"$key\">$CNprovences{$key}</option>\n";
      }
    }
    print "</select></td></tr>\n";
  } else {
    print "<tr><td ALIGN=\"right\"><font size=\"2\" FACE=\"$fontface\" color=\"$color{'state'}\">State/Provence:<b>*</b></td>";
    print "<td align=\"left\"><INPUT TYPE=\"text\" NAME=\"state\" size=\"20\" VALUE=\"$query{'state'}\" MAXLENGTH=19></td></tr>\n";
  }
  print "<tr><td ALIGN=\"right\"><font size=\"2\" FACE=\"$fontface\" color=\"$color{'prov'}\">International Provence: </td>";
  print "<td align=\"left\"><INPUT TYPE=\"text\" NAME=\"provence\" size=\"20\" VALUE=\"$query{'provence'}\" MAXLENGTH=19></td></tr>\n";

  print "<tr><td align=right><font size=\"2\" FACE=\"$fontface\" color=\"$color{'zip'}\">Zip/Postal Code:<b>*</b></font></td>";
  print "<td align=left><INPUT TYPE=\"text\" NAME=\"zip\" SIZE=10 VALUE=\"$query{'zip'}\" MAXLENGTH=10></td></tr>\n";

    if ($query{'nocountrylist'} ne "yes") {
      print "<tr><td align=right><font size=\"2\" FACE=\"$fontface\">Country:</td><td align=left><SELECT NAME=\"country\">\n";
      foreach $var (@countries) {
        if ($var eq $query{'country'}) {
          print "<option value=\"$var\" selected>$var</option>\n";
        }
        else {
          print "<option value=\"$var\">$var</option>\n";
        }
      }
      print "</select></td></tr>\n";
    }
    else {
      print "<tr><td align=right><font size=\"2\" FACE=\"$fontface\" color=\"$color{'country'}\">Country:</td>";
      print "<td align=left><INPUT TYPE=\"text\" NAME=\"country\" SIZE=15 VALUE=\"$query{'country'}\" MAXLENGTH=20></td></tr>\n";
    }

  }
  if ($query{'comments'} ne "") {
    if ($query{'comm-title'} ne "") {
       print "<tr><td align=\"right\" valign=\"top\"><font size=\"2\" FACE=\"$fontface\" color=\"$goodcolor\">$query{'comm-title'}:</td>\n";
    }
    else {
       print "<tr><td align=\"right\"><font size=\"2\" FACE=\"$fontface\" color=\"$goodcolor\">Comments \&/or Shipping Instructions:</td>\n";
    }
    print "<td align=\"left\"><TEXTAREA NAME=\"comments\" ROWS=6 COLS=40></TEXTAREA></td></tr>\n";
  }

  print "</table>\n\n";
}



sub update_screen1_pairs {

  foreach $key (keys %query) {
    if (($key !~ /card-/)
        && ($key ne "tel") && ($key ne "fax") && ($key ne "tax")
        && ($key ne "shipsame") && ($key ne "shipname") && ($key ne "address1")
        && ($key ne "address2") && ($key ne "max") && ($key ne 'month-exp')
        && ($key ne 'year-exp') && ($key !~ /item/)
        && ($key !~ /quantity/) && ($key !~ /cost/) && ($key !~ /description/)
        && ($key !~ /MErrMsg/) && ($key ne "provence")
        && ($key ne "city") && ($key ne "state") && ($key ne "zip")
        && ($key ne "country") && ($key ne "submit") && ($key ne "email")
        && ($key ne "roption") && ($key ne "passwrd1") && ($key ne "passwrd2")
        && ($key ne "uname") && ($key ne "passphrase")&& ($key ne "pass")) {
      print "<input type=\"hidden\"\n name=\"$key\" value=\"$query{$key}\">";
    }
  }

  print "<input type=\"hidden\"\n name=\"card-allowed\" value=\"$query{'card-allowed'}\">";
  print "<input type=\"hidden\"\n name=\"pass\" value=1>";
  print "<input type=\"hidden\"\n name=\"max\" value=\"$max\">";

}



sub update_screen1_tail {

  print "\n";
  print "\n";
  print "<table width=\"640\" border=0 cellpadding=4>\n";
  print "<tr valign=\"top\" align=\"left\">\n";
  print "<TD WIDTH=10 HEIGHT=28 rowspan=5> &nbsp; </TD><td></td></TR>\n";
  print "<tr><td colspan=\"2\" align=\"center\">\n";
  print "<FONT SIZE=\"1\" FACE=\"$fontface\">";
  print "<input TYPE=\"submit\" VALUE=\"Summarize Change Request\"> <INPUT TYPE=\"reset\" VALUE=\"Reset Form\"></td></tr>\n";
  if ($browser !~ /AOL/) {
    print "<tr><td align=\"left\" colspan=\"2\">\n";
    print "<a href=\"http://www.plugnpay.com/\" target=\"newWin\"><img src=\"pnp_seal.gif\" border=0></a></td></tr>\n";
  }
  print "</table>\n\n";
  print "</FORM>\n</BODY>\n";
  print "</HTML>";

}


sub update_screen2_head {

  # print "Content-Type: text/html\n\n";
  print "<HTML>\n";
  print "<HEAD>\n";
  print "<TITLE>Order Confirmation Screen</TITLE> \n";

  print "<SCRIPT LANGUAGE=\"JavaScript\">\n";
  print "<!--  // beginning of script\n";
  print "pressed_flag = 0;\n";
  print "function mybutton(form) {\n";
  print "  if (pressed_flag == 0) {\n";
  print "    pressed_flag = 1;\n";
  print "    return true;\n";
  print "  }\n";
  print "  else {\n";
  print "    return false;\n";
  print "  }\n";
  print "}\n";
  print "// end of script -->\n";
  print "</SCRIPT>\n";

  print "</HEAD>\n";

  if ($backimage eq "") {
    print "<BODY BGCOLOR=\"$backcolor\" LINK=\"$goodcolor\" TEXT=\"$goodcolor\" ALINK=\"$alinkcolor\" VLINK=\"$vlinkcolor\">\n";
  }
  else {
    print "<BODY BGCOLOR=\"$backcolor\" LINK=\"$goodcolor\" TEXT=\"$goodcolor\" ALINK=\"$alinkcolor\" VLINK=\"$vlinkcolor\" background=\"$backimage\">\n";
  }

  if (($query{'image-placement'} ne "left") && ($query{'image-link'} ne "")) {
    print "<div align=center><center>\n";
    print "<img src=\"$query{'image-link'}\"><p><p>\n";
    print "</center></div>\n";
  }
  else {
    print "<br>\n";
  }

}



sub update_screen2_body {

  print "<p>\n";
  print "<FORM METHOD=post ACTION=\"$query{'path_cgi'}\">\n";
  print "<tr><td></td><td colspan=1 align=left><font size=\"2\" FACE=\"$fontface\">\n";
  print "<font color=\"$badcolor\">$error_string</font><p>\n";
  print "<font color=\"$goodcolor\">Please Check The Following Information Carefully.<br>\n";
  print "Use the \"Back Button\" on your Browser to make any necessary corrections.</font><p>\n";

  if (($query{'passwrd1'} ne "") && ($query{'uname'} ne "")) {
    print "<b><font size=+1 color=\"$badcolor\">NOTICE:</font><br>\n";
    print "Please copy the following information for your records, <br>it may be slightly different than from what you chose:<p>\n";
    print "Username: $query{'uname'}<br>\n";
    print "Password: $query{'passwrd1'}<p>\n";
    print "Remember, Usernames and Passwords are CASE SENSITIVE.<p>\n";
    print "You will receive an email confirmation of this purchase which will contain a CYBERCASH ORDER ID as well as a copy of your username and password. \n";
    print "It is VERY IMPORTANT that you save this email.  This information will be required if you experience any problems. \n";
    print "If you entered an incorrect email address, please use the back button and go back and change it.</b><p>\n";
  }


  if ($query{'shipinfo'} == 1) {
    print "<font color=\"$goodcolor\"><b>Shipping Information</b><br>\n";
    print "$query{'shipname'}<br>\n";
    print "$query{'address1'}<br>\n";
    if ($query{'address2'} ne "") {
      print "$query{'address2'}<br>\n";
    }
    print "$query{'city'}, $query{'state'} $query{'zip'}<br>\n";
    print "$query{'country'}</font><p>\n\n";
  }

  print "<font color=\"$goodcolor\"><b>Billing Information</b><br>\n";
  print "$query{'card-name'}<br>\n";
  if ($query{'card-company'} ne "") {
    print "$query{'card-company'} <br>\n";
  }
  print "$query{'card-address1'}<br>\n";
  if ($query{'card-address2'} ne "") {
    print "$query{'card-address2'}<br>\n";
  }
  print "$query{'card-city'}, $query{'card-state'}  $query{'card-zip'}<br>\n";
  print "$query{'card-country'}<br>\n";
  if ($query{'paymethod'} ne "check") {
    print "$query{'card-number'}  Exp. Date: $query{'month-exp'}/$query{'year-exp'} <br>\n";
  }
  print "$query{'email'}<br>\n";
  print "Tel: $query{'tel'}<br>\n";
  print "Fax: $query{'fax'}<br>\n";
  print "</font>\n\n";
  print "</td></tr></table>\n\n";

}


sub update_screen2_pairs {
  foreach $key (keys %query) {
    if ($key ne "orderID") {
      print "<input TYPE=\"hidden\"\n name=\"$key\" VALUE=\"$query{$key}\">";
    }
  }
  print "<input TYPE=\"hidden\"\n name=\"orderID\" VALUE=\"$orderID\">";
  print "<input TYPE=\"hidden\"\n name=\"mode\" VALUE=\"update\">";
}


sub update_screen2_tail {

  print "<div align=\"center\"><center>";
  print "<input TYPE=\"submit\" VALUE=\"Submit Order\" onClick=\"return(mybutton(this.form));\"><p>\n";
  print "<font color=\"$goodcolor\">We appreciate your patience while your order is processed. It should take less than\n";
  print "1 minute. Please press the \"Submit Order\" only once to prevent any potential double billing.\n";
  print "If you have a problem please email us at <a href=\"mailto:\n";
  if ($query{'from-email'} ne "") {
    print "$query{'from-email'}\">$query{'from-email'}</a>.\n";
  }
  else {
    print "$query{'publisher-email'}\">$query{'publisher-email'}</a>.\n";
  }
  print "Please give your full name, order number (if you received a purchase confirmation), and ";
  print "the exact nature of the problem.\n";
  print "</font></center></div>\n";
  print "</FORM>\n";
  print "<p>\n";
  print "</BODY>\n";
  print "</HTML>\n";

}


sub colors {
  foreach $var (@standardfields) {
    $color{$var} = $goodcolor;
  }
}


sub input_check {
  foreach $key (keys %query) {
    $color{$key} = $goodcolor;
  }

  $query{'card-number'} =~ s/[^0-9]//g;
  &luhn10;
  if ((length($query{'card-number'}) < 10) || ($luhntest eq "FAIL")) {
    $error = 1;
    $color{'card-number'} = $badcolor;
  }

  $position = index($query{'email'},"\@");
  if (($position < 1) || (length($query{'email'}) < 5) || ($position > (length($query{'email'})-5))) {
    $error = 1;
    $color{'email'} = $badcolor;
  }

}



sub deny_access {
  # print "Content-Type: text/html\n\n";
  print "<html>\n";
  print "<head>\n";
  print "<title>Un-Authorized Access</title>\n";
  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";
  print "<div align=center>\n";
  print "<font size=+2>\n";
  print "Un-Authorized Access\n";
  print "</font>\n";
  print "<p>\n";
  print "<font size=+2>To Obtain Access to this private area, please register properly.</font>\n";
  print "</body>\n";
  print "</html>\n";

  exit;
}

sub luhn10{
  $len = length($query{'card-number'});
  @digits = split('',$query{'card-number'});
  for($k=0; $k<$len; $k++) {
    $j = $len - 1 - $k;
    if (($j - 1) >= 0) {
      $a = $digits[$j-1] * 2;
    } else {
      $a = 0;
    }
    if (length($a) > 1) {
      ($b,$c) = split('',$a);
      $temp = $b + $c;
    } else {
      $temp = $a;
    }
    $sum = $sum + $digits[$j] + $temp;
    $k++;
  }
  $check = substr($sum,length($sum)-1);
  if ($check eq "0") {
    $luhntest = "PASS";
  } else {
    $luhntest = "FAIL";
  }
}

sub update {

  $name = $query{'name'};
  $company = $query{'company'};
  $addr1 = $query{'addr1'};
  $addr2 = $query{'addr2'};
  $city = $query{'city'};
  $state = $query{'state'};
  $zip = $query{'zip'};
  $country = $query{'country'};
  $shipname = $query{'shipname'};
  $shipaddr1 = $query{'shipaddr1'};
  $shipaddr2 = $query{'shipaddr2'};
  $shipcity = $query{'shipcity'};
  $shipstate = $query{'shipstate'};
  $shipzip = $query{'shipzip'};
  $shipcountry = $query{'shipcountry'};
  $phone = $query{'phone'};
  $fax = $query{'fax'};
  $email = $query{'email'};
  $cardnumber = $query{'cardnumber'};
  $user1_val = $query{"$user1"};
  $user2_val = $query{"$user2"};
  $user3_val = $query{"$user3"};
  $user4_val = $query{"$user4"};
  $password = $query{'password'};
  $exp = $query{'exp'};
  $monthly = $query{'monthly'};
  $billcycle = $query{'billcycle'};

  $_ = $query{'start'};
  my($mmonth,$dday,$yyear) = split(/\//);
  if($_ ne "") {
        $start = sprintf("%04d%02d%02d",$yyear,$mmonth,$dday);
  }
  $_ = $query{'end'};
  ($mmonth,$dday,$yyear) = split(/\//);
  if($_ ne "") {
    $end = sprintf("%04d%02d%02d",$yyear,$mmonth,$dday);
  }
  $_ = $query{'lastbilled'};
  ($mmonth,$dday,$yyear) = split(/\//);
  if($_ ne "") {
    $lastbilled = sprintf("%04d%02d%02d",$yyear,$mmonth,$dday);
  }

  $cardlength = length $cardnumber;
  if(($cardnumber !~ /\*\*/) && ($cardlength > 8)) {
    ($enccardnumber,$encryptedDataLen) = &rsautils::rsa_encrypt_card($cardnumber,"/home/p/pay1/web/payment/recurring/$query{'publisher-name'}/admin/key");


    $cardnumber = $query{'cardnumber'};
    $cardnumber =~ s/[^0-9]//g;
    $cardnumber = substr($cardnumber,0,4) . '**' . substr($cardnumber,length($cardnumber)-2,2);
    $encryptedDataLen = "$encryptedDataLen";

    $sth = $dbh->prepare(qq{
          update customer set enccardnumber='$enccardnumber',length='$encryptedDataLen'
          where username='$username'
    }) or die "Can't prepare: $DBI::errstr";
    $sth->execute or die "Can't execute: $DBI::errstr";
    $sth->finish;
  }

  $querystring = 'update customer set name=?,company=?,addr1=?,addr2=?,city=?,state=?,zip=?,country=?,phone=?,fax=?,email=?,startdate=?,enddate=?,monthly=?,cardnumber=?,exp=?,lastbilled=?,password=?,billcycle=?,shipaddr1=?,shipaddr2=?,shipcity=?,shipstate=?,shipzip=?,shipcountry=?';
  @execstring = ("$name","$company","$addr1","$addr2","$city","$state","$zip","$country","$phone","$fax","$email","$start","$end","$monthly","$cardnumber","$exp","$lastbilled","$password","$billcycle","$shipaddr1","$shipaddr2","$shipcity","$shipstate","$shipzip","$shipcountry");

  if ($user1 ne "") {
    $querystring = $querystring . ",$user1=?";
    @execstring = (@execstring,"$user1_val");
  }
  if ($user2 ne "") {
    $querystring = $querystring . ",$user2=?";
    @execstring = (@execstring,"$user2_val");
  }
  if ($user3 ne "") {
    $querystring = $querystring . ",$user3=?";
    @execstring = (@execstring,"$user3_val");
  }
  if ($user4 ne "") {
    $querystring = $querystring . ",$user4=?";
    @execstring = (@execstring,"$user4_val");
  }
  $querystring = $querystring . " where username=?";
  @execstring = (@execstring,"$username");

  $sth = $dbh->prepare("$querystring") or die "Can't prepare: $DBI::errstr";
  $sth->execute(@execstring) or die "Can't execute: $DBI::errstr";
  $sth->finish;
  $message = "Update has been completed";
  &response_page;
}

