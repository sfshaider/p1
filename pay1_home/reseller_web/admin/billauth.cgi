#!/bin/env perl

# Last Updated: 07/26/12

require 5.001;
$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use CGI;
use miscutils;
use rsautils;

my $query = new CGI;

my @array = $query->param;
foreach my $var (@array) {
  $var =~ s/[^a-zA-Z0-9\_\-]//g;
  $query{"$var"} = &CGI::escapeHTML($query->param($var));
  if (($var eq "card_number") || ($var eq "routing") || ($var eq "acct") || ($var eq "ssnum")) {
    $query{$var} =~ s/[^0-9]//g;
  }
  elsif ($var =~ /^(month-exp|year-exp)$/) {
    $query{$var} =~ s/[^0-9]//g;
  }
  else {
    $query{$var} =~ s/[^0-9a-zA-Z\_\.\/]//g;
  }
}

if (exists $query{'card-number'}) {
  $query{'card-number'} = substr($query{'card-number'},0,20);
}

if (exists $query{'routing'}) {
  $query{'routing'} = substr($query{'routing'},0,9);
}

if (exists $query{'accttype'}) {
  $query{'accttype'} = substr($query{'accttype'},0,10);
}

if (exists $query{'chkaccttype'}) {
  $query{'chkaccttype'} = substr($query{'chkaccttype'},0,10);
}

$username = $ENV{'REMOTE_USER'};
$script = $ENV{'SCRIPT_NAME'};
$showcc = "none";
$showcheck = "none";
$select_credit = "";
$select_checking = "";
$select_chkaccttype = "";

#print "Content-Type: text/html\n\n";

#Modes
if ($query{'mode'} eq "error_check") {
  &error_check(); 
} 
else {
  &main();
}

exit;

sub main {

  my $dbh = &miscutils::dbhconnect("pnpmisc");

  my $sth = $dbh->prepare(qq{
      select company,addr1,city,state,zip,tel,name,merchemail,monthly,percent,pertran,overtran,setupfee,pcttype,extrafees,reseller,accttype,card_number,billauthdate,exp_date
      from customers 
      where username=? 
    }) or die "Can't do: $DBI::errstr";
  $sth->execute($username) or die "Can't execute: $DBI::errstr";
  ($company,$addr1,$city,$state,$zip,$tel,$name,$merchemail,$monthly,$percent,$pertran,$overtran,$setupfee,$pcttype,$extrafees,$reseller,$accttype,$card_number,$billauthdate,$exp_date) = $sth->fetchrow;
  $sth->finish;

  $dbh->disconnect;

  print "Content-Type: text/html\n\n";
  print "<HTML>\n";
  print "<HEAD>\n";

  print "<script Language=\"Javascript\">\n";
  print "<!-- //\n";

  print "function change_win(helpurl,swidth,sheight,windowname) {\n";
  print "  SmallWin = window.open(helpurl, windowname,'scrollbars=yes,resizable=yes,status=yes,toolbar=yes,menubar=yes,height='+sheight+',width='+swidth);\n";
  print "}\n";

  print "function closewin() {\n";
  print "  self.close();\n";
  print "}\n";

  print "// -->\n";
  print "</script>\n";

  print "<script type=\"text/javascript\">\n";
  print " function ccActive() {\n";
  print "  cc.style.display='block';\n";
  print "  ach.style.display='none';\n"; 
  print "}\n";
  print " function achActive() {\n";
  print "  ach.style.display='block';\n"; 
  print "  cc.style.display='none';\n";          
  print "}\n"; 

  print <<EOF;

//toggles color for focused text input and select fields
 
window.onload = function() {
  var field = document.getElementsByTagName("input");
    for(var i = 0; i < field.length; i++) {
      if (field[i].type == "text") {
        field[i].onfocus = function() {
          this.className += " focus";
        };
        field[i].onblur = function() {
          this.className = this.className.replace(/\\bfocus\\b/, "");
        };
      };
    };
field = null;
  var field = document.getElementsByTagName("select");
    for(var i = 0; i < field.length; i++) {
        field[i].onfocus = function() {
          this.className += " focus";
        };
        field[i].onblur = function() {
          this.className = this.className.replace(/\\bfocus\\b/, "");
        };
      };
field = null;
  var field = document.getElementsByTagName("textarea");
    for(var i = 0; i < field.length; i++) {
      field[i].onfocus = function() {
        this.className += " focus";
      };
      field[i].onblur = function() {
        this.className = this.className.replace(/\\bfocus\\b/, "");
      };
    };
field = null;
  };

// agree to terms prompt
  function validate(agree2){
    if (agree2.checked != 1) {
      alert("Please agree to the terms by checking the box at the bottom of the form.")
      return false;
    }
    else {
      return true;
    }
  }
EOF

  print "</script>\n";

  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"https://pay1.plugnpay.com/css/green.css\">\n";
  print "<TITLE>Billing Authorization</TITLE>\n";
  print "</HEAD>\n";

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
  print "    <td><h1>Billing Authorization</h1></td>\n";
  #print "    <td align=\"right\"><a href=\"/logout.cgi\">Logout</a></td>\n";
  print "    </tr>\n";
  print "</table>\n";
 
  print "<hr id=\"under\" />\n";

  print "<BODY>\n";
  print "<TABLE BORDER=0 CELLSPACING=0 CELLPADDING=0 WIDTH=\"100%\">\n";
  if ($error_message ne "") {
    print "<tr><td colspan=\"2\" align=\"center\"><font color=\"#FF0000\"> $error_message</font></td></tr>\n";
  }
  if ($success_message ne "") {
    print "<tr><td class=\"label\" colspan=\"2\" align=\"center\"> $success_message</td></tr>\n";
  }
  print "<tr><td class=\"label\" colspan=\"2\">Service Agreement</td></tr>\n";
  print "<tr><td colspan=\"2\" align=\"left\">Plug & Pay Technologies (PNP) will enable the company described below to resell payment gateway services in accordance to their reseller agreement &amp; the following Terms and Conditions.</td></tr>\n";
  print "<tr><td colspan=\"2\" align=\"left\">PNP shall not be liable for any loss incurred as a result of use of system or software.</td></tr>\n";
  print "<tr><td colspan=\"2\" align=\"left\">In no event shall PNP be liable for any special, incidental, consequential or indirect damages (including, but not limited to, any claim for loss of services, lost profits, or lost revenues) arising from or in relation to this agreement or the use of the system or software, however caused and regardless of the theory of liability. This limitation will apply even if PNP has been advised or is aware of the possibility of such damages.</td></tr>\n";
 print "<tr><td>&nbsp;</td></tr>\n";
 print "</table>\n";

#form begins.
  print "<form method=post action=\"$script\" onsubmit=\"return validate(agree2);\">\n";
  print "<input type=\"hidden\" name=\"mode\" value=\"error_check\">\n";
  print "<table>\n";
  print "<tr><th colspan=\"1\">User Name: </th>\n";
  print "<td>$username&nbsp;&nbsp;</td>\n";
  print "<tr><th colspan=\"1\">Contact Name:</th><td>$name</td>\n";
  print "</tr>\n";
  print "<tr><th colspan=\"1\">Company Name: </th>\n";
  print "<td>$company</td></tr>\n"; 
  print "<tr><th colspan=\"1\">Address: </th>\n";
  print "<td>$addr1, $city, $state  $zip</td></tr>\n"; 
  print "<tr>\n";
  print "<th colspan=\"1\">Phone: </th>\n";
  print "<td>$tel&nbsp;&nbsp;<font class=\"bigger\">Email Address:</font> $merchemail</td>\n"; 
  print "</tr>\n";

  print "</table>\n";

  print "<table>\n"; 
  print "<tr><td class=\"label\" colspan=\"2\">Current Payment Information</td></tr>\n"; 
  if ($accttype eq "credit") {
    print "<tr><th colspan=\"1\">Account Type: </th>\n";
    print "<td>Credit Card</td></tr>\n";
    print "<tr><th colspan=\"1\">Card Number: </th>\n";
    print "<td>$card_number</td></tr>\n";
    print "<tr><th colspan=\"1\">Card Exp: </th>\n";
    print "<td>$exp_date</td></tr>\n";
  }
  elsif ($accttype eq "checking") {
    print "<tr><th colspan=\"1\">Account Type: </th>\n";
    print "<td>Checking</td></tr>\n";
    print "<tr><th colspan=\"1\">Account Information: </th>\n";
    print "<td>$card_number</td></tr>\n";
  }
  print "</table>\n";

  print "<table>\n";
  print "<tr><td class=\"label\">New Payment Information</td>\n";
  print "<tr><td class=\"date\">* indicates required field</td></tr>\n";
  print "<tr><td>&nbsp;</td></tr>\n";
  if ($error_message eq "") {
    if ($accttype eq "credit") {
      $select_credit = "checked";
      $showcc = "block";
    }
    elsif ($accttype eq "checking") {
      $select_checking = "checked"; 
      $showcheck = "block";
    }  
  }
  print "<tr><td> Credit Card: <input type=\"radio\" name=\"accttype\" value=\"credit\" $select_credit onclick=\"javascript:ccActive();\">\n";
  print " Checking: <input type=\"radio\" name=\"accttype\" value=\"checking\" $select_checking onclick=\"javascript:achActive();\"></td></tr>\n";
  #print "<tr><td>&nbsp;</td></tr>\n";
  print "</table>\n";
  
  print "<div id=\"cc\" style=\"display:$showcc\">\n";
 
  print "<table border=\"0\">\n";
  print "<tr><td colspan=\"2\"> I (we) authorize PNP to bill my (our) credit card.</td></tr>\n";
  print "<tr><td>&nbsp;</td></tr>\n";
  print "<br><th>Card Number:* </th>\n";
  print "<td><input type=\"text\" name=\"card_number\" size=\"16\" maxlength=\"16\" value=\"$query{'card_number'}\" autocomplete=\"off\"> (16 digits)</td></tr>\n";
  print "<th>Exp Date:*</th>\n";
  #print "<td><input type=\"text\" name=\"exp_date\" size=\"6\" maxlength=\"5\" value=\"$query{'exp_date'}\" autocomplete=\"off\"> eg. MM/YY</td></tr>\n";
  print "<td>\n";

  print "<select name=\"month-exp\">\n";
  my @months = ("01","02","03","04","05","06","07","08","09","10","11","12");
  my ($dummy,$date,$dummy2) = &miscutils::genorderid();
  my $current_month = substr($date,4,2);
  my $current_year = substr($date,0,4);
  if ($payutils::query{'month-exp'} eq "") {
    $payutils::query{'month-exp'} = $current_month;
  }
  foreach my $var (@months) {
    if ($var eq $payutils::query{'month-exp'}) {
      print "<option value=\"$var\" selected>$var</option>\n";
    }
    else {
      print "<option value=\"$var\">$var</option>\n";
    }
  }
  print "</select> ";
 
  print "<select name=\"year-exp\">\n";
 
  if ($payutils::query{'year-exp'} eq ""){
    $payutils::query{'year-exp'} = $current_year;
  }
  for (my $i; $i<=12; $i++) {
    my $var = $current_year + $i;
    my $val = substr($var,2,2);
    if ($val eq $payutils::query{'year-exp'}) {
      print "<option value=\"$val\" selected>$var</option>\n";
    }
    else {
      print "<option value=\"$val\">$var</option>\n";
    }
  }
  print "</select>\n";
  print "</td></tr>\n";

  print "<tr><th>NOTE:</th>\n";
  print "<td>Please check here if this is a Corporate/Business card Account. \n";
  print "<input type=\"checkbox\" name=\"chkaccttype\" value=\"CCD\" $select_chkaccttype></td></tr>\n";
  print "</table>\n";
  print "</div>\n";

  print "<div id=\"ach\" style=\"display:$showcheck\">\n";

  print "<table>\n";
  print "<tr><td>&nbsp;</td></tr>\n";
  print "<tr><td colspan=\"2\"><b>NOTE:</b> The ACH debit option is available only for U.S. banks.</td></tr>\n";
  print "<tr><td colspan=\"2\">Your bank might require you to authorize a debtor.</td></tr>\n";
  print "<tr><td colspan=\"2\">If so, please provide your bank with our NACHA bank code 1016207445.</td></tr>\n";
  print "<tr><td>&nbsp;</td></tr>\n";
  print "<tr><td colspan=\"2\">I/we  hereby authorize PNP to initiate debit and credit entries to my/our \n";
  print " checking account indicated below and the bank named below, hereinafter\n";
  print "bank, to debit or credit the same to such account. I further authorize PNP to debit said\n"; 
  print "account for such amount allowed by law in the event a debit entry is rejected by the depository.\n";
  print "There is a \$20.00 return check fee.\n"; 
  print "<tr><td>&nbsp;</td></tr>\n";
  print "</table>\n";
  print "<table>\n";
  print "</td></tr>\n";
  #print "<B> I agree.</b> <input type=\"checkbox\" name=\"agree1\" value=\"YES\"><br>\n";
  print "<tr><th>Bank Name:</th>\n";
  print "<td colspan=\"1\"><input type=\"text\" name=\"bank\" size=\"20\" maxlength=\"20\" value=\"$query{'bank'}\"><td></tr>\n";
# print "<b>City</b> ______________________________________<b>State</b>_______________<b>Zip</b>_______<br>\n";
  print "<tr><th>Transit/Route Number:*</th>\n";
  print "<td colspan=\"1\"><input type=\"text\" name=\"routing\" size=\"9\" maxlength=\"9\" value=\"$query{'routing'}\" autocomplete=\"off\"> (9 digits)</td></tr>\n";
  print "<tr><th>Account Number:*</th>\n";
  print "<td colspan=\"1\"><input type=\"text\" name=\"acct\" size=\"20\" maxlength=\"20\" value=\"$query{'acct'}\" autocomplete=\"off\"></td></tr>\n";
  print "<tr><th>NOTE:</th>\n";
  print "<td colspan=\"2\">Please check here if this is a Business Checking Account. \n";
  print "<input type=\"checkbox\" name=\"chkaccttype\" value=\"CCD\" $select_chkaccttype></td></tr>\n";
  print "</table>\n";
  print "</div>\n";

  print "<table border=\"0\">\n";
  print "<tr><td class=\"label\">Billing Authorization</td></tr>\n";
  print "<tr><td colspan=\"2\">I agree to pay Plug N Pay for all applicable fees and understand that PNP may terminate all services upon non-payment of any sum due PnP.<br></td></tr>\n";

#  print "<tr><td>&nbsp;</td></tr>\n";
#  $monthly=sprintf("%.2f",$monthly);
#  $setupfee=sprintf("%.2f",$setupfee);
#  $percent=sprintf("%.2f",$percent);
#  $extrafees=sprintf("%.2f",$extrafees);
#  print "<tr><td><b>\$$setupfee</b> Initial setup, <b>\$$monthly</b> Monthly Minimum, ";
#  #print "<tr><td><b>\$$monthly</b> Monthly Minimum</td></tr>\n";
#  if (($pcttype eq "trans") & ($overtran eq "0")) {
#     print "<b>\$$percent</b> Per Transaction, ";
#  } 
#  if ($pcttype eq "percent") {
#     print "<b>&#37; $percent</b> Percent, ";
#  }
#  if (($pcttype eq "trans") & ($overtran ne "0")) {
#     print "<b>\$$percent</b> over <b>$overtran</b> Transactions, ";
#  }
#  print "<b>\$$extrafees</b> Extra Fees";  
#  print "</td></tr>\n";
#
#  print "<tr><td>&nbsp;</td></tr>\n";
#  print "<tr><td colspan=\"3\">I understand that monthly invoices will be delivered via electronic mail and that Plug N Pay may terminate all services upon non-payment of any sum due to Plug N Pay from the reseller.<br></td></tr>\n";
#  print "<tr><td>&nbsp;</td></tr>\n";
#  print "<tr><td colspan=\"2\">NOTE: All billing is processed the 1st of the month for the prior months activity.</td></tr>\n";
#  #print "<tr><td>&nbsp;</td></tr>\n";
#  print "<tr><td class=\"label\">Cancellation Policy</td></tr>\n";
#  print "<tr><td colspan=\"3\">You can terminate your gateway account by sending a request to <a href=\"mailto:accounting\@plugnpay.com\">accounting\@plugnpay.com</a> or by faxing to 631-360-1213.</td></tr>\n";
#  print "<tr><td>Please include your account username in your request.</td></tr>\n";
  print "</table>\n";

  print "<table border=\"0\" width=\"50%\">\n";
  print "<tr><td class=\"label\">Identification</td></tr>\n";
  print "<tr><th align=\"right\" colspan=\"1\">Name on account:*</th>\n";
  print "<td><input type=\"text\" name=\"name\" size=\"30\" maxlength=\"30\" value=\"$name\"></td></tr>\n";
  #print "<tr><th>Last 4 digits of Social Security Number:*</th>\n";
  print "<tr>\n";
  print "<th>*</th>\n";
  print "<td><input type=\"text\" name=\"ssnum\" size=\"3\" maxlength=\"3\" value=\"$query{'ssnum'}\" autocomplete=\"off\"> Last 3 digits of Social Security Number or Tax ID Number</td>\n";
  #print "<td>*Last 4 digits of Social Security Number</td>\n";
  print "</tr>\n";
  print "<tr>\n";
  #print "<tr><th align=\"left\" colspan=\"1\">Please check this box to agree to the terms filed in this form.</th>\n";
  print "<th>*</th>\n";
  print "<td><input type=\"checkbox\" name=\"agree2\" value=\"YES\"> Please check this box to agree to the terms filed in this form. </td>\n";
  #print "<td align=\"left\" colspan=\"1\">Please check this box to agree to the terms filed in this form.</td>\n";
  print "</tr>\n";

  $date = localtime(time);
  $date =~ /.*? (.*)/;
  $date = $1;

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

  $year += 1900;
  if ($isdst == 1) {
    $date =~ s/$year/  EDT $year/;
  }
  else {
    $date =~ s/$year/  EST $year/;
  }

  #chomp( $date ); 

  print "<tr><td>&nbsp;</td></tr>\n";
  print "<tr>\n";
  print "<td class=\"date\" colspan=\"2\">$date</td>\n"; 
  print "</tr>\n";
  #print "<input type=\"hidden\" name=\"billauthdate\" value=\"$date\">\n";
  #print "<input type=\"hidden\" name=\"billauth\" value=\"yes\">\n"; 

  print "<tr><td colspan=\"2\" align=\"center\"><input type=\"submit\" value=\"Send Info\"> <input type=\"reset\" value=\"Reset Form\"></td></tr>\n";
  print "</table>\n";
  print "</form>\n";

  print "<hr id=\"over\" />\n";
  print "<table class=\"frame\">\n";
  print "  <tr>\n";
  print "    <td class=\"left\"><a href=\"/admin/logout.cgi\" title=\"Click to log out\">Log Out</a> | <a id=\"close\" href=\"javascript:closewin();\" title=\"Click to close this window\">Close Window</a></td>\n";
  print "    <td class=\"right\">&copy; $year, Plug 'n Pay Technologies, Inc.</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</BODY>\n";
  print "</HTML>\n";

  exit;
}
  
sub error_check {
  $exp_date = $query{'month-exp'} . "/" . $query{'year-exp'};
  my $routing_length = length ($query{'routing'});
  my $acct_length = length ($query{'acct'});
  my $ssnum_length = length ($query{'ssnum'});
  my $name_length = length ($query{'name'});

  if ($query{'chkaccttype'} eq "CCD") { 
    $select_chkaccttype = "checked";
  }

  if ($ssnum_length != 3) {
    if ($query{'accttype'} eq "credit") {
      $showcc = "block";
      $select_credit = "checked";
    }
    elsif ($query{'accttype'} eq "checking") {
      $showcheck = "block";
      $select_checking = "checked";
    }
    $error_message = "<b>ERROR</b>: Please enter the last 3 digits of your Social Security Number or Tax ID Number\n";
    &main();
  }
  else {
    if ($query{'accttype'} eq "credit") {
      my ($dummy,$date,$dummy2) = &miscutils::genorderid();
      my $year_exp = substr($exp_date,-2);
      my $exptst1 =  $year_exp + 2000;
      my $mon_exp = substr($exp_date,0,2);
      $exptst1 .= $mon_exp;
      my $exptst2 =  substr($date,0,6);

      my $luhntest = &miscutils::luhn10($query{'card_number'});
      if ($luhntest eq "failure") {
        $showcc = "block";
        $select_credit = "checked";
        $error_message = "<b>ERROR</b>: Credit Card Number In-Valid.  Please check and re-enter.\n";
        &main();
      }
      elsif ($exptst1 < $exptst2) {
        $showcc = "block";
        $select_credit = "checked";
        $error_message = "<b>ERROR</b>: Please fill in a proper expiration date.\n";
        &main(); 
      }  
      else {
        &insert_info();
      }
    }
    elsif ($query{'accttype'} eq "checking") {  
      my $luhntest = &miscutils::mod10($query{'routing'});
      if (($routing_length != 9) || ($acct_length < 1) || ($luhntest eq "failure")) {
        $error_message = "<b>ERROR</b>: Please fill in all checking fields. The Transit/Route Number must be 9 digits.\n";
        $showcheck = "block";
        $select_checking = "checked";
        &main(); 
      }  
      else {
        $exp_date = ""; # so it does not populate database with default exp_date
        &insert_info();
      }
    }
    else {
      $error_message = "<b>ERROR</b>: Please fill in Payment Method information.\n";
      &main();
    }
  }
}

sub insert_info {
  $query{'billauth'} = "yes";
  #$query{'billauthdate'} = localtime(time);
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  my $newdate = sprintf "%.4d%.2d%.2d", $year+1900, $mon+1, $mday;
  $query{'billauthdate'} = $newdate;

  if ($query{'accttype'} eq "checking") {
    $card_number = "$query{'routing'} $query{'acct'}";
  }
  else {
    $card_number = $query{'card_number'};
  }

  $dbh = &miscutils::dbhconnect("pnpmisc");

  # card encryption stuff
  $cardlength = length $card_number;

  if (($card_number !~ /\*\*/) && ($cardlength > 8)) {
    ($enccardnumber,$encryptedDataLen) = &rsautils::rsa_encrypt_card($card_number,"/home/p/pay1/web/private/key");
    $card_number = substr($card_number,0,4) . '**' . substr($card_number,length($card_number)-2,2);
 
    $sth = $dbh->prepare(qq{
        update customers
        set enccardnumber=?,length=?
        where username=?
      }) or die "Can't prepare: $DBI::errstr";
    $sth->execute("$enccardnumber","$encryptedDataLen","$username") or die "Can't execute: $DBI::errstr";
    $sth->finish;
  }
  else {
    $enccardnumber = "";
    $encryptedDataLen = "";
  }
  # end card encryption stuff

  $sth = $dbh->prepare(qq{
      update customers 
      set accttype=?,card_number=?,exp_date=?,chkaccttype=?,billauthdate=?,ssnum=?,billauth=?,bank=?
      where username=?
    }) or die "Can't prepare: $DBI::errstr";
  $sth->execute("$query{'accttype'}","$card_number","$exp_date","$query{'chkaccttype'}","$query{'billauthdate'}","$query{'ssnum'}","$query{'billauth'}","$query{'bank'}","$username") or die "Can't execute: $DBI::errstr";
  $sth->finish;

  $dbh->disconnect;

  $success_message = "Your information has been updated successfully.\n";

  &send_email();

  #print "Location:  billauth.cgi\n\n";

  &main();

  exit;
}

sub send_email {

  open(MAILERR,"| /usr/lib/sendmail -t");

  print MAILERR "To: accounting\@plugnpay.com\n";
  print MAILERR "From: billauth\@plugnpay.com\n";
  print MAILERR "Subject: Billing Information Changed - $username\n";
  print MAILERR "\n";
  print MAILERR "Username: $username\n";
  print MAILERR "\n";
  print MAILERR "This reseller changed their billing authorization information using the Billing Authorization section of their Reseller Administration page.\n";

  close MAILERR;
}

exit;

