#!/bin/env perl

# Purpose: This script allows merchant's update their account feature settings & manage their templates
#          -- including color/style, CSS, logo, background & set other common service settings/templates

require 5.001;
$|=1;

use lib $ENV{'PNP_PERL_LIB'};
use pnp_environment;
use CGI;
use miscutils;
use sysutils;
use PlugNPay::GatewayAccount::LinkedAccounts;
use PlugNPay::Environment;
use strict;

#print "Content-Type: text/html\n";
#print "X-Content-Type-Options: nosniff\n";
#print "X-Frame-Options: SAMEORIGIN\n\n";

## allow Proxy Server to modify ENV variable 'REMOTE_ADDR'
my $environment = new PlugNPay::Environment();
my $remoteIP = $environment->get('PNP_CLIENT_IP');

if (($ENV{'SEC_LEVEL'} eq "") && ($ENV{'REDIRECT_SEC_LEVEL'} ne "")) {
  $ENV{'SEC_LEVEL'} = $ENV{'REDIRECT_SEC_LEVEL'};
}

if (($ENV{'LOGIN'} eq "") && ($ENV{'REDIRECT_LOGIN'} ne "")) {
  $ENV{'LOGIN'} = $ENV{'REDIRECT_LOGIN'};
}

my $allow_overview = "";

# grab POSTed params
my %query;
my $query = new CGI;
my @params = $query->param;
foreach my $param (@params) {
  $param =~ s/[^a-zA-Z0-9\_\-]//g;
  # filter non-allowed characters from all field values to prevent injection of new/extra fields into the features string (replace with a space character)
  $query{"$param"} = &CGI::escapeHTML($query->param($param));

  if ($param =~ /(card-allowed|attendant_cardsallowed|billpay_exclude_state|billpay_exclude_country)/) {
    $query{"$param"} =~ s/(\'|\;)/ /g;
  }
  else {
    $query{"$param"} =~ s/(\,|\'|\;)/ /g;
  }
}

$query{'merchant'} =~ s/[^0-9a-zA-Z]//g;
$query{'function'} =~ s/[^a-zA-Z0-9\_\-]//g;

if ($query{'function'} ne "download_template") {
  print "Content-Type: text/html\n";
  print "X-Content-Type-Options: nosniff\n";
  print "X-Frame-Options: SAMEORIGIN\n\n";
}


my $dbh = &miscutils::dbhconnect("pnpmisc");

if (($query{'merchant'} ne "") && ($ENV{'SCRIPT_NAME'} =~ /overview/)) {
  my $sth = $dbh->prepare(q{
      SELECT overview
      FROM salesforce
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$ENV{'REMOTE_USER'}") or die "Can't execute: $DBI::errstr";
  my ($overview) = $sth->fetchrow;
  $sth->finish;
  if ($overview =~ /account/i) {
    $allow_overview = 1;
  }
}

my $merchant;
if ($allow_overview) {
  $merchant = &overview($ENV{'REMOTE_USER'}, $query{'merchant'});
  $ENV{'REMOTE_USER'} = $merchant; 
  $ENV{'SEC_LEVEL'} = 10;
}

if (($query{'merchant'} ne "") && ($allow_overview != 1)) {
  $merchant = &is_linked_acct("$ENV{'REMOTE_USER'}", "$query{'merchant'}");
}

$query{'merchant'} = $merchant || $ENV{'REMOTE_USER'};  # set by linked acct or environment

# check what services merchant is subscribed to
my $sth = $dbh->prepare(qq{
    SELECT p.membership, p.fraudtrack, p.coupon, p.fulfillment, p.affiliate, p.easycart, p.billpay, c.processor, c.chkprocessor, c.reseller, c.company
    FROM pnpsetups p, customers c
    WHERE c.username=?
    AND c.username=p.username
  }) or die "Can't prepare: $DBI::errstr";
$sth->execute("$query{'merchant'}") or die "Can't execute: $DBI::errstr";
my ($service_membership, $service_fraudtrack, $service_coupon, $service_fulfillment, $service_affiliate, $service_easycart, $service_billpay, $merch_processor, $merch_chkprocessor, $merch_reseller, $merch_company) = $sth->fetchrow;
$sth->finish;

my $supports_sweeptime;
if ($merch_processor =~ /^(citynat|fdms|fdmsintl|global|litle|mercury|moneris|nova|paytechtampa|payvision|securenet|visanet)$/) {
  # list is based on merchant processors that use 'sweeptime' feature accounts to the webpl/batchfiles/XXXXXX/genfiles.pl scripts.
  $supports_sweeptime = 1;
}

$dbh->disconnect;

# set section titles here for section menu selection.
my @sections = ("Payment Script Style", "Payment Script Config", "Transaction Admin");

# set the feature fields the merchant can modify 
# Format: ["category", "field_name", "default_value", "field_type|settings", "field_title", "exclude_regex"]
my @data_fields = (
  ["Payment Script Style", "goodcolor",       "#2020a0", "text|", "Page Text Color", "a-zA-Z0-9\#"],
  ["Payment Script Style", "backcolor",       "#ffffff", "text|", "Page Background Color", "a-zA-Z0-9\#"],
  ["Payment Script Style", "badcolor",        "#ff0000", "text|", "Error Field Color", "a-zA-Z0-9\#"],
  ["Payment Script Style", "badcolortxt",     "RED",     "text|", "Name Of Error Field Color", "a-zA-Z"],
  ["Payment Script Style", "linkcolor",       "#2020a0", "text|", "Link Color", "a-zA-Z0-9\#"],
  ["Payment Script Style", "alinkcolor",      "#187f0a", "text|", "Active Link Color", "a-zA-Z0-9\#"],
  ["Payment Script Style", "vlinkcolor",      "#0b1f48", "text|", "Visited Link Color", "a-zA-Z0-9\#"],
  ["Payment Script Style", "fontface",        "Arial",   "text|", "Font Type", "a-zA-Z0-9\#"],
  ["Payment Script Style", "itemrow",         "#d0d0d0", "text|", "Item Row Color", "a-zA-Z0-9\#"],
  ["Payment Script Style", "titlecolor",      "#ffffff", "text|", "Item Text Color", "a-zA-Z0-9\#"],
  ["Payment Script Style", "titlebackcolor",  "#2020a0", "text|", "Item Background Color", "a-zA-Z0-9\#"],
  ["Payment Script Style", "backimage",       "",        "justtext|", "Background Image", "a-zA-Z0-9\-\_\/\ \."],
  ["Payment Script Style", "image-link",      "",        "justtext|", "Logo Image", "a-zA-Z0-9\-\_\/\ \."],
  ["Payment Script Style", "image-placement", "center",  "select|center,left,lefttop,right,table", "Logo Alignment", "a-z"],
  ["Payment Script Style", "css-link",        "",        "justtext|", "CSS File", "a-zA-Z0-9\-\_\/\ \."],

  ["Payment Script Style", "mobileimage-link", "",       "justtext|", "Mobile Logo Image", "a-zA-Z0-9\-\_\/\ \."],
  ["Payment Script Style", "mobilebackimage",  "",       "justtext|", "Mobile Background Image", "a-zA-Z0-9\-\_\/\ \."],
  ["Payment Script Style", "mobilecss-link",   "",       "justtext|", "Mobile CSS File", "a-zA-Z0-9\-\_\/\ \."],

  ["Payment Script Config", "minpurchase",    "",        "text|",           "Min Purchase Amount", "0-9\."],
  ["Payment Script Config", "maxpurchase",    "",        "text|",           "Max Purchase Amount", "0-9\."],
  ["Payment Script Config", "allow_invoice",  "0",       "checkbox|1",      "Allow Invoiced Orders", "01"],
  ["Payment Script Config", "allow_checkcard","0",       "checkbox|1",      "Allow Checkcard Orders", "01"],
  ["Payment Script Config", "splitname",      "0",       "checkbox|1",      "Split First/Last Name", "01"],
  ["Payment Script Config", "usonly",         "0",       "checkbox|1",      "Limit Country To US Only", "01"],
  ["Payment Script Config", "uscanonly",      "0",       "checkbox|1",      "Limit Country To US/Canada Only", "01"],
  ["Payment Script Config", "usterrflag",     "",        "checkbox|0",      "Hide US Territories", "01"],
  ["Payment Script Config", "nophone",        "0",       "checkbox|1",      "Hide Phone/Fax Fields", "01"],
  ["Payment Script Config", "skipsummaryflg", "0",       "checkbox|1",      "Skip Summery Page", "01"],
  ["Payment Script Config", "transition",     "1",       "checkbox|1",      "Use Transition Page", "01"],
  ["Payment Script Config", "transitiontype", "get",     "select|get,post", "Transition Page Type", "a-z"],
  ["Payment Script Config", "seal",           "0",       "checkbox|1",      "Show SSL Security Seal", "01"],
  ["Payment Script Config", "dispcardlogo",   "0",       "checkbox|1",      "Show Credit Card Logos", "01"],
  ["Payment Script Config", "securecode",     "0",       "checkbox|1",      "Show MasterCard Secure Code Seal", "01"],
  ["Payment Script Config", "omitstatement",  "0",       "checkbox|1",      "Hide Privacy Policy Statement", "01"],
  ["Payment Script Config", "hide_security_policy", "0", "checkbox|1",      "Hide Security Policy Link", "01"],
  ["Payment Script Config", "indicate_processing",  "0", "checkbox|1",      "Show Processing Payment Indication", "01"],
  ["Payment Script Config", "onload",         "",        "checkbox|clear",  "Auto Erase Form Data", "a-z"],
  ["Payment Script Config", "staticemailflg", "",        "checkbox|1",      "Use Static \'From\' Address In Merchant Conf Email", "01"],
  ["Payment Script Config", "card-allowed",   "",        "text|",           "Smart Screens - Card Types Allowed", "a-zA-Z0-9\,\|"],
  ["Payment Script Config", "use_captcha",    "0",       "checkbox|1",      "Use CAPTCHA Verification", "01"],
  ["Payment Script Config", "keyswipe",       "",        "checkbox|secure", "Use Credit Card Reader", "secure"],
  ["Payment Script Config", "cardnumfield",   "0",       "checkbox|1",      "Broden Credit Card Number Mask", "01"],
  ["Payment Script Config", "maskexp",        "0",       "checkbox|1",      "Broden Credit Card Exp Date Mask", "01"],

  ["Transaction Admin",   "settletimezone",    "", "select|,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1,0,1,2,3,4,5,6,7,8,9,9.5,10,11,12", "Settle Time Zone (GMT Hour Offset)", "a-zA-Z0-9\-"],
  ["Transaction Admin",   "display_ac4",       "", "checkbox|1", "Display \'acct_code4\' In Review Batch", "01"],
  ["Transaction Admin",   "display_cc",        "", "checkbox|1", "Display Partial CC\# in Review Batch", "01"],
  ["Transaction Admin",   "display_cclast4",   "", "checkbox|1", "Display Last 4 Digits of CC\# In Review Batch", "01"],
  ["Transaction Admin",   "display_authcode",  "", "checkbox|1", "Display Auth Code In Review Batch", "01"],
  ["Transaction Admin",   "specify_ac",        "", "checkbox|1", "Specify Acct Code within Recharge Customer Transactions", "01"],
  ["Transaction Admin",   "vtreceipt_company", "", "checkbox|1", "Include Company Name in VT Std Printer Receipts", "01"]
);

# check to see if we need to add extra features, based on merchant processor.
if ($supports_sweeptime == 1) {
  push(@sections, "Settlement Config");
  push(@data_fields, ["Settlement Config", "sweeptime",          "",    "invisible",  "Sweeptime for Settlement:", ""] );
  push(@data_fields, ["Settlement Config", "sweeptime_enable",   "0",   "checkbox|1", "Enable Sweeptime Ability", "01"] );
  push(@data_fields, ["Settlement Config", "sweeptime_dstflag",  "1",   "checkbox|1", "Adjust For Daylight Savings", "01"] );
  push(@data_fields, ["Settlement Config", "sweeptime_timezone", "EST", "select|EST,CST,MST,PST", "Settlement Time Zone", "A-Z"] );
  push(@data_fields, ["Settlement Config", "sweeptime_cutoff",   "1",   "select|0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23", "Settlement Transaction Cutoff", "0-9"] );
}

# check to see if we need to add extra features, based on subscribed services.
if ($service_membership ne "") {
  push(@sections, "Membership Management");
  push(@data_fields, ["Membership Management", "allow_freeplans",         "0", "checkbox|1",    "Allow \$0.00 Plans", "01"] );
  push(@data_fields, ["Membership Management", "attendant_termflag",      "0", "checkbox|1",    "Attendant - Terminate Profile Upon Cancel", "01"] );
  push(@data_fields, ["Membership Management", "attendant_nooutputflag",  "0", "checkbox|1",    "Attendant - Completely Disable Profile Edit Ability", "01"] );
  push(@data_fields, ["Membership Management", "attendant_displayonly",   "0", "checkbox|1",    "Attendant - Prevent Editing (Displays Current Info Only)", "01"] );
  push(@data_fields, ["Membership Management", "attendant_suppresspw",    "0", "checkbox|1",    "Attendant - Suppress Password Updates", "01"] );
  push(@data_fields, ["Membership Management", "attendant_suppressemail", "0", "checkbox|1",    "Attendant - Suppress Email Updates", "01"] );
  push(@data_fields, ["Membership Management", "attendant_suppressphone", "0", "checkbox|1",    "Attendant - Suppress Phone/Fax Updates", "01"] );
  push(@data_fields, ["Membership Management", "attendant_edit_shipping", "0", "checkbox|1",    "Attendant - Allow Shipping Info Updates", "01"] );
  push(@data_fields, ["Membership Management", "attendant_edit_cc",       "0", "checkbox|1",    "Attendant - Allow CC/ACH Info Updates", "01"] );
  push(@data_fields, ["Membership Management", "attendant_cardsallowed",  "visa|mstr|amex|dscr|checking|savings", "text|", "Attendant - Card Types Allowed", "a-zA-Z0-9\,\|"] );
}

#if ($service_fraudtrack ne "") {
#  push(@sections, "FraudTrak");
#  push(@data_fields, ["FraudTrak", "xxxxxxflag", "0", "checkbox|1", "Show xxxxxx Field", "01"] );
#}

if ($service_coupon ne "") {
  push(@sections, "Coupon Management");
  push(@data_fields, ["Coupon Management", "couponflag", "0", "checkbox|1", "Show Coupon Code Field", "01"] );
}

#if ($service_fulfillment ne "") {
#  push(@sections, "Fulfillment");
#  push(@data_fields, ["Fulfillment", "xxxxxxflag", "0", "checkbox|1", "Show xxxxxx Field", "01"] );
#}

#if ($service_affiliate ne "") {
#  push(@sections, "Affiliate Management");
#  push(@data_fields, ["Affiliate Management", "xxxxxxflag", "0", "checkbox|1", "Show xxxxxx Field", "01"] );
#}

#if ($service_easycart ne "") {
#  push(@sections, "EasyCart Shopping Cart");
#  push(@data_fields, ["EasyCart Shopping Cart", "xxxxxxflag", "0", "checkbox|1", "Show xxxxxx Field", "01"] );
#}

#my $service_billpay = 1;
if ($service_billpay ne "") {
  push(@sections, "Billing Presentment");
  push(@data_fields, ["Billing Presentment", "billpay_cardsallowed",    "Visa Mastercard", "text|", "Card Types Allowed", "a-zA-Z0-9\ "] );
  push(@data_fields, ["Billing Presentment", "billpay_remind_days",     "", "select|,3,7,14,30", "Send Invoice Reminder (Every X Days)", "0-9"] );
  push(@data_fields, ["Billing Presentment", "billpay_email_merch",     "", "checkbox|yes",      "Send Merchant Copy Of Invoice Email Notification", "a-z"] ),
  push(@data_fields, ["Billing Presentment", "billpay_email_cust",      "", "checkbox|yes",      "Default Select Send Email Notification", "a-z"] );
  push(@data_fields, ["Billing Presentment", "billpay_express_pay",     "", "checkbox|yes",      "Default Select Express Pay Link", "a-z"] );
  push(@data_fields, ["Billing Presentment", "billpay_overwrite",       "", "select|,none,same,match,all,purge", "Default Overwrite Setting", "a-z"] ),
  push(@data_fields, ["Billing Presentment", "billpay_express_prepop",  "", "checkbox|yes",      "Prepopulate Address In Express Pay", "a-z"] );
  push(@data_fields, ["Billing Presentment", "billpay_shipinfo",        "", "checkbox|1",        "Collect Separate Shipping Address In Invoices", "01"] );
  push(@data_fields, ["Billing Presentment", "billpay_payperiod",       "7", "text|",            "Pay Period For Consolidated Invoices (X Days)", "0-9"] );
  push(@data_fields, ["Billing Presentment", "billpay_allow_partial",   "", "checkbox|yes",      "Allow Partial Payment Of Invoiced Amount", "a-z"] );
  push(@data_fields, ["Billing Presentment", "billpay_partial_min",     "", "text|",             "Partial Payment Minimum Amount", "0-9\."] );
  push(@data_fields, ["Billing Presentment", "billpay_allow_overpay",   "", "checkbox|yes",      "Allow Overpayment Of Installment Amount", "a-z"] );
  push(@data_fields, ["Billing Presentment", "billpay_allow_nbalance",  "", "checkbox|yes",      "Allow Negative Balance Of Payment Amount", "a-z"] );
  push(@data_fields, ["Billing Presentment", "billpay_nbalance_plus",   "", "checkbox|yes",      "Allow Payments on Negative Balance Invoices", "a-z"] );
  push(@data_fields, ["Billing Presentment", "billpay_use_percent",     "", "checkbox|yes",      "Make Installment Fee Percentage Based", "a-z"] );

  push(@data_fields, ["Billing Presentment", "billpay_terms_pay",       "", "checkbox|yes",      "Enable Payment Terms \& Conditions Agreement.", "a-z"] );
  push(@data_fields, ["Billing Presentment", "billpay_terms_service",   "", "checkbox|yes",      "Enable Terms of Service Agreement.", "a-z"] );
  push(@data_fields, ["Billing Presentment", "billpay_terms_use",       "", "checkbox|yes",      "Enable Acceptable Use Policy Agreement.", "a-z"] );
  push(@data_fields, ["Billing Presentment", "billpay_terms_privacy",   "", "checkbox|yes",      "Enable Privacy Policy Agreement.", "a-z"] );

  push(@data_fields, ["Billing Presentment", "billpay_usonly",          "", "checkbox|yes",      "Limit Client Contact Country To US Only", "a-z"] );
  push(@data_fields, ["Billing Presentment", "billpay_uscanonly",       "", "checkbox|yes",      "Limit Client Contact Country To US/Canada Only", "a-z"] );
  push(@data_fields, ["Billing Presentment", "billpay_usterrflag",      "", "checkbox|no",       "Hide US Territories in Client Contact", "a-z"] );
  push(@data_fields, ["Billing Presentment", "billpay_exclude_state",   "", "text|",             "Exclude Specific States from Client Contact", "a-zA-Z0-9\,\|"] );
  push(@data_fields, ["Billing Presentment", "billpay_exclude_country", "", "text|",             "Exclude Specific Countries from Client Contact", "a-zA-Z0-9\,\|"] );

  #push(@data_fields, ["Billing Presentment", "billpay_datalink_url",    "",    "text|",                  "Data Link URL",   "a-zA-Z0-9\_\.-\~\[\]"] );
  #push(@data_fields, ["Billing Presentment", "billpay_datalink_pairs",  "",    "text|",                  "Data Link Pairs", "a-zA-Z0-9\_\.-\~\[\]"] );
  push(@data_fields, ["Billing Presentment", "billpay_datalink_type",   "get", "select|get,post,hidden", "Data Link Transition Type", "a-z"] );
}

my $allowed_ascii_types  = "CSS|TXT"; # allowed ASCII files types (pipe delimited)
my $allowed_binary_types = "JPG|GIF|PNG"; # allowed Binary files types (pipe delimited)

my $allowed_template_ascii_types  = "HTM|HTML|TXT|CSV"; # allowed template ASCII files types (pipe delimited)

# If you want to restrict the upload file size (in bytes), uncomment the next line and change the number
$CGI::POST_MAX = 1048576 * 1; # set to 1 Megs max file size
# Converion Notes: 1K = 1024 bytes, 1Meg = 1048576 bytes.

my $path_web = &pnp_environment::get('PNP_WEB');

my $upload_dir = "$path_web/logos/upload"; # folder where all merchant's logos & background images will be uploaded to
my $web_upload_dir = "/logos/upload"; # sets the relative link to the upload folder from the browser point of view

my $template_dir = "$path_web/admin/templates"; # folder where all merchant's templates will be uploaded to
my $web_template_dir = "/admin/templates"; # sets the relative link to the templates folder from the browser point of view

my $script = "https://" . $ENV{'SERVER_NAME'} . $ENV{'SCRIPT_NAME'}; # URL self-reference to this script (should never need to be changed)

if ( (($ENV{'SCRIPT_NAME'} =~ /overview/) && ($allow_overview != 1)) ||
     (($ENV{'SCRIPT_NAME'} !~ /overview/) && ($ENV{'SEC_LEVEL'} > 4) && ($ENV{'SEC_LEVEL'} != 11)) ) {
  &html_head();
  print "<div align=center><b>You are not authorized to edit this information.</b>\n";
  print "<form><input type=button value=\"Close Window\" onClick=\"window.close();\"></form></div>\n";
  &html_tail();
  exit;
}

if ($query{'merchant'} =~ /^(pnpdemo|pnptest|pnpdemo2|billpaydem|demoacct1)$/) {
  # do not allow certain accounts to apply changes
  # force them to always see the main page.
  if ($query{'function'} eq "section_menu") {
    &section_menu(%query);
  }
  else {
    &main(%query);
  }
  exit;
}
elsif ($query{'function'} eq "update") {
  &update(%query);
}
elsif ($query{'function'} eq "upload_file") {
  &upload_file(%query);
}
elsif ($query{'function'} eq "remove_file") {
  &remove_file(%query);
}
elsif ($query{'function'} eq "download_template") {
  &download_template(%query);
}
elsif ($query{'function'} eq "remove_template") {
  &remove_template(%query);
}
elsif ($query{'function'} eq "section_menu") {
  &section_menu(%query);
}
else {
  &main(%query);
}

exit;

sub html_head {
  my ($section_title) = @_;

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Account Settings - $merch_company</title>\n";
  print "<meta http-equiv=\"CACHE-CONTROL\" content=\"NO-CACHE\">\n";
  print "<meta http-equiv=\"PRAGMA\" content=\"NO-CACHE\">\n";
  print "<link rel=\"shortcut icon\" href=\"favicon.ico\">\n";
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

  print "<body>\n";
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
  print "    <td colspan=3 valign=top align=left><h1><a href=\"$ENV{'SCRIPT_NAME'}";
  if ($query{'merchant'} ne "") {
    print "\?merchant=$query{'merchant'}";
  }
  print "\">Account Settings</a>";
  if ($section_title ne "") {
    print " / $section_title"; 
  }
  print " - $merch_company</h1></td>\n";
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

sub main {
  my %query = @_;
  my $username = $query{'merchant'};
  my %feature;

  my $dbh = &miscutils::dbhconnect("pnpmisc");
  my $sth_merchants = $dbh->prepare(q{
      SELECT features
      FROM customers
      WHERE username=?
    }) or die "Can't prepare: $DBI::errstr";
  $sth_merchants->execute("$username") or die "Can't execute: $DBI::errstr";
  my ($features) = $sth_merchants->fetchrow;
  $sth_merchants->finish;

  if ($features ne "") {
    my @array = split(/\,/,$features);
    foreach my $entry (@array) {
      my ($name, $value) = split(/\=/,$entry,2);
      if ($value =~ /\w/) {
        $feature{"$name"} = $value;
      }
    }
  }
  $dbh->disconnect;

  # perform special specific field adjustments here.
  if ($feature{'card-allowed'} =~ /\|/) {
    # convert pipes to commas
    $feature{'card-allowed'} =~ s/\|/\,/g;
  }
  if ($feature{'attendant_cardsallowed'} =~ /\|/) {
    # convert pipes to commas
    $feature{'attendant_cardsallowed'} =~ s/\|/\,/g;
  }

  if ($feature{'billpay_exclude_state'} =~ /\|/) {
    # convert pipes to commas
    $feature{'billpay_exclude_state'} =~ s/\|/\,/g;
    $feature{'billpay_exclude_state'} = uc("$feature{'billpay_exclude_state'}");
  }
  if ($feature{'billpay_exclude_country'} =~ /\|/) {
    # convert pipes to commas
    $feature{'billpay_exclude_country'} =~ s/\|/\,/g;
    $feature{'billpay_exclude_country'} = uc("$feature{'billpay_exclude_country'}");
  }

  if ($feature{'sweeptime'} ne "") {
    my @temp = split(/\:/, $feature{'sweeptime'}, 3);
    # set seperate fields
    $feature{'sweeptime_enable'} = 1;
    $feature{'sweeptime_dstflag'} = $temp[0];
    $feature{'sweeptime_timezone'} = $temp[1];
    $feature{'sweeptime_cutoff'} = sprintf("%d", $temp[2]);
    # remove combined field
    delete $feature{'sweeptime'};
  }

  &html_head();

  print "<p>This portion of the site has been constructed to assist you in customizing your payment script & other service features on our secure server.  Below you should find all the options necessary to apply your site's color scheme, upload your own CSS or logo/background image & set other service settings.  If you have not used this interface before, the default values for the various fields will be provided.  If you have a problem with this wizard, please submit your problem to the Online Helpdesk.\n";

  print "<hr>\n";

  # show config section options
  print "<p><table border=0 cellspacing=0 cellpadding=1 width=\"100%\">\n";
  print "  <tr>\n";
  print "    <th colspan=2>Customizable Section Options</th>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Edit Section Options</td>\n";
  print "    <td class=\"menurightside\">";
  for (my $i=0; $i <= $#sections; $i++) {
    print "&bull; <a href=\"$script\?function=section_menu\&merchant=$username\&section=$sections[$i]\"><b>$sections[$i]</b></a>\n";
    if ($i != $#sections) {
      print "<br>";
    }
  }
  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<hr>\n";

  print "<p><table border=0 cellspacing=0 cellpadding=1 width=\"100%\">\n";

  # show logo/background/css configuration
  if (($feature{'image-link'} =~ /\w/) || ($feature{'backimage'} =~ /\w/) || ($feature{'css-link'} =~ /\w/)) {
    print "  <tr>\n";
    print "    <th colspan=2>Current Logo/Background/CSS</th>\n";
    print "  </tr>\n";
  }
  if ($feature{'image-link'} =~ /\w/) {
    print "  <tr>\n";
    print "    <td class=\"menuleftside\">Logo</td>\n";
    print "    <td class=\"menurightside\"><img src=\"$feature{'image-link'}\" border=1></td>\n";
    print "  </tr>\n";
  }
  if ($feature{'backimage'} =~ /\w/) {
    print "  <tr>\n";
    print "    <td class=\"menuleftside\">Background</td>\n";
    print "    <td class=\"menurightside\"><a href=\"$feature{'backimage'}\" target=\"_blank\">Click Here To View Background</a></td>\n";
    print "  </tr>\n";
  }
  if ($feature{'css-link'} =~ /\w/) {
    print "  <tr>\n";
    print "    <td class=\"menuleftside\">CSS File</td>\n";
    print "    <td class=\"menurightside\"><a href=\"$feature{'css-link'}\" target=\"_blank\">Click Here To View CSS File</a></td>\n";
    print "  </tr>\n";
  }

  # show mobile logo/background/css configuration
  if (($feature{'mobileimage-link'} =~ /\w/) || ($feature{'mobilebackimage'} =~ /\w/) || ($feature{'mobilecss-link'} =~ /\w/)) {
    print "  <tr>\n";
    print "    <th colspan=2>Current Mobile Logo/Background/CSS</th>\n";
    print "  </tr>\n";
  }
  if ($feature{'mobileimage-link'} =~ /\w/) {
    print "  <tr>\n";
    print "    <td class=\"menuleftside\">Mobile Logo</td>\n";
    print "    <td class=\"menurightside\"><img src=\"$feature{'mobileimage-link'}\" border=1></td>\n";
    print "  </tr>\n";
  }
  if ($feature{'mobilebackimage'} =~ /\w/) {
    print "  <tr>\n";
    print "    <td class=\"menuleftside\">Mobile Background</td>\n";
    print "    <td class=\"menurightside\"><a href=\"$feature{'mobilebackimage'}\" target=\"_blank\">Click Here To View Background</a></td>\n";
    print "  </tr>\n";
  }
  if ($feature{'mobilecss-link'} =~ /\w/) {
    print "  <tr>\n";
    print "    <td class=\"menuleftside\">Mobile CSS File</td>\n";
    print "    <td class=\"menurightside\"><a href=\"$feature{'mobilecss-link'}\" target=\"_blank\">Click Here To View CSS File</a></td>\n";
    print "  </tr>\n";
  }

  # create CSS/logo/background config options
  print "  <tr>\n";
  print "    <th colspan=2>Logo/Background/CSS Options</th>\n";
  print "  </tr>\n";

  if (($username !~ /^(affinisc|lawpay)$/) && ($ENV{'REMOTE_USER'} !~ /^(affinisc|lawpay)$/)) {
    # 11/17/11 - prevent 'affinisc' & 'lawpay' resellers from accidentially uploading logo/background/css files into their reseller account
    #          - yet permit resellers & all others to upload into their merchant PnP account normally

    print "  <tr>\n";
    print "    <td class=\"menuleftside\">Upload File</td>\n";
    print "    <td class=\"menurightside\"><form method=post action=\"$script\" enctype=\"multipart/form-data\">\n";
    print "<input type=hidden name=\"function\" value=\"upload_file\">\n";
    print "<input type=hidden name=\"merchant\" value=\"$username\">\n";
    print "<table border=0 cellspacing=2 cellpadding=2>\n";
    print "  <tr>\n";
    print "    <td class=\"leftcell\">Type:</td>\n";
    print "    <td class=\"rightcell\"><select name=\"upload_type\">\n";
    print "<option value=\"logos\">Company Logo</option>\n";
    print "<option value=\"backgrounds\">Background Image</option>\n";
    print "<option value=\"css\">Cascading Style Sheet (CSS)</option>\n";
    print "</select></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftcell\">Usage:</td>\n";
    print "    <td class=\"rightcell\"><select name=\"upload_usage\">\n";
    print "<option value=\"\">Normal</option>\n";
    print "<option value=\"mobile\">Mobile</option>\n";
    print "</select></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"leftcell\">File:</td>\n";
    print "    <td class=\"rightcell\"><input type=file class=\"button\" name=\"upload_file\"></td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td class=\"leftcell\" colspan=2><input type=submit class=\"button\" name=\"submit\" value=\"Upload File\"></td>\n";
    print "  </tr>\n";
    print "</table>\n";
    print "</td></form>\n";
    print "  </tr>\n";
  }

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\">&nbsp;</td>\n";
  print "  </tr>\n";

  ## logo files
  if ($feature{"image-link"} =~ /\w/) {
    print "  <tr>\n";
    print "    <td class=\"menuleftside\">&nbsp;</td>\n";
    print "    <td class=\"menurightside\"><form method=post action=\"$script\">\n";
    print "<input type=hidden name=\"function\" value=\"remove_file\">\n";
    print "<input type=hidden name=\"merchant\" value=\"$username\">\n";
    print "<input type=hidden name=\"upload_type\" value=\"logos\">\n";
    print "<input type=hidden name=\"upload_usage\" value=\"\">\n";
    print "<input type=submit class=\"button\" name=\"submit\" value=\"Remove Logo\">\n";
    print "</td></form>\n";

    print "  </tr>\n";
  }
  if ($feature{"mobileimage-link"} =~ /\w/) {
    print "  <tr>\n";
    print "    <td class=\"menuleftside\">&nbsp;</td>\n";
    print "    <td class=\"menurightside\"><form method=post action=\"$script\">\n";
    print "<input type=hidden name=\"function\" value=\"remove_file\">\n";
    print "<input type=hidden name=\"merchant\" value=\"$username\">\n";
    print "<input type=hidden name=\"upload_type\" value=\"logos\">\n";
    print "<input type=hidden name=\"upload_usage\" value=\"mobile\">\n";
    print "<input type=submit class=\"button\" name=\"submit\" value=\"Remove Mobile Logo\">\n";
    print "</td></form>\n";

    print "  </tr>\n";
  }

  ## background files
  if ($feature{"backimage"} =~ /\w/) {
    print "  <tr>\n";
    print "    <td class=\"menuleftside\">&nbsp;</td>\n";
    print "    <td class=\"menurightside\"><form method=post action=\"$script\">\n";
    print "<input type=hidden name=\"function\" value=\"remove_file\">\n";
    print "<input type=hidden name=\"merchant\" value=\"$username\">\n";
    print "<input type=hidden name=\"upload_type\" value=\"backgrounds\">\n";
    print "<input type=hidden name=\"upload_usage\" value=\"\">\n";
    print "<input type=submit class=\"button\" name=\"submit\" value=\"Remove Background\">\n";
    print "</td></form>\n";
    print "  </tr>\n";
  }
  if ($feature{"mobilebackimage"} =~ /\w/) {
    print "  <tr>\n";
    print "    <td class=\"menuleftside\">&nbsp;</td>\n";
    print "    <td class=\"menurightside\"><form method=post action=\"$script\">\n";
    print "<input type=hidden name=\"function\" value=\"remove_file\">\n";
    print "<input type=hidden name=\"merchant\" value=\"$username\">\n";
    print "<input type=hidden name=\"upload_type\" value=\"backgrounds\">\n";
    print "<input type=hidden name=\"upload_usage\" value=\"mobile\">\n";
    print "<input type=submit class=\"button\" name=\"submit\" value=\"Remove Mobile Background\">\n";
    print "</td></form>\n";
    print "  </tr>\n";
  }

  ## CSS files
  if ($feature{"css-link"} =~ /\w/) {
    print "  <tr>\n";
    print "    <td class=\"menuleftside\">&nbsp;</td>\n";
    print "    <td class=\"menurightside\"><form method=post action=\"$script\">\n";
    print "<input type=hidden name=\"function\" value=\"remove_file\">\n";
    print "<input type=hidden name=\"merchant\" value=\"$username\">\n";
    print "<input type=hidden name=\"upload_type\" value=\"css\">\n";
    print "<input type=hidden name=\"upload_usage\" value=\"\">\n";
    print "<input type=submit class=\"button\" name=\"submit\" value=\"Remove CSS\">\n";
    print "</td></form>\n";
    print "  </tr>\n";
  }
  if ($feature{"mobilecss-link"} =~ /\w/) {
    print "  <tr>\n";
    print "    <td class=\"menuleftside\">&nbsp;</td>\n";
    print "    <td class=\"menurightside\"><form method=post action=\"$script\">\n";
    print "<input type=hidden name=\"function\" value=\"remove_file\">\n";
    print "<input type=hidden name=\"merchant\" value=\"$username\">\n";
    print "<input type=hidden name=\"upload_type\" value=\"css\">\n";
    print "<input type=hidden name=\"upload_usage\" value=\"mobile\">\n";
    print "<input type=submit class=\"button\" name=\"submit\" value=\"Remove Mobile CSS\">\n";
    print "</td></form>\n";
    print "  </tr>\n";
  }

  my @transition_files = glob("$template_dir\/transition\/$username\_*\.html");
  my $transition_cnt = @transition_files;

  my @payscreen_files = glob("$template_dir\/payscreen\/$username\_*\.txt");
  my $payscreen_cnt = @payscreen_files;

  my @billpay_files = glob("$template_dir\/billpay\/$username\_*\.txt");
  my $billpay_cnt = @billpay_files;

  my @billpaylite_files = glob("$template_dir\/billpaylite\/$username\_*\.txt");
  my $billpaylite_cnt = @billpaylite_files;

  my @thankyou_files = glob("$template_dir\/thankyou\/$username\_*\.htm");
  my $thankyou_cnt = @thankyou_files;

  if (($transition_cnt >= 1) || ($payscreen_cnt >= 1) || ($billpay_cnt >= 1) || ($billpaylite_cnt >= 1) || (-e "$template_dir\/thankyou\/$username\.htm") || ($thankyou_cnt >= 1)) {
    print "  <tr>\n";
    print "    <th colspan=2>Current Templates</th>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td class=\"menuleftside\">Current Templates</td>\n";
    print "    <td class=\"menurightside\">";

    if ($transition_cnt >= 1) {
      # list current transition page templates 
      print "<b>Transition Templates:</b> " . $transition_cnt;
      print "<table border=0 cellspacing=0 cellpadding=1 width=\"100%\">\n";
      print "  <tr>\n";
      print "    <td bgcolor=\"#eeeeee\" width=\"25%\">Template</td>\n";
      print "    <td bgcolor=\"#eeeeee\" width=\"5%\"> &nbsp;</td>\n";
      print "    <td bgcolor=\"#eeeeee\"> &nbsp;</td>\n";
      print "  </tr>\n";
      foreach my $filename (sort @transition_files) {
        $filename =~ s/.*[\/\\](.*)/$1/;
        my @temp = split(/\_|\./, $filename, 3); # split filename on "-" & "."
        print "  <tr>\n";
        print "    <td><a href=\"$script\?function=download_template\&merchant=$username\&upload_type=transition\&template_name=$temp[1]\">$temp[1]</a></td>\n";
        print "    <td>\[<a href=\"$script\?function=remove_template\&merchant=$username\&upload_type=transition\&template_name=$temp[1]\">X</a>\]</td>\n"; 
        print "    <td> &nbsp;</td>\n";
        print "  </tr>\n";
      }
      print "</table>\n";
      print "<br>\n";
    }

    if ($payscreen_cnt >= 1) {
      # list current payscreen templates 
      print "<b>PayScreen Templates:</b> " . $payscreen_cnt;
      print "<table border=0 cellspacing=0 cellpadding=1 width=\"100%\">\n";
      print "  <tr>\n";
      print "    <td bgcolor=\"#eeeeee\" width=\"25%\">Template</td>\n";
      print "    <td bgcolor=\"#eeeeee\" width=\"5%\"> &nbsp;</td>\n";
      print "    <td bgcolor=\"#eeeeee\">Preview Example</td>\n";
      print "  </tr>\n";
      foreach my $filename (sort @payscreen_files) {
        $filename =~ s/.*[\/\\](.*)/$1/;
        my @temp = split(/\_|\./, $filename, 4); # split filename on "-" & "."
        print "  <tr>\n";
        if ($temp[3] =~ /\w/) {
          print "    <td><a href=\"$script\?function=download_template\&merchant=$temp[0]\&upload_type=payscreen\&template_name=$temp[2]\&language=$temp[1]\">$temp[1] - $temp[2]</a></td>\n";
          print "    <td>\[<a href=\"$script\?function=remove_template\&merchant=$temp[0]\&upload_type=payscreen\&template_name=$temp[2]\&language=$temp[1]\">X</a>\]</td>\n";
          print "    <td><a href=\"https://$ENV{'SERVER_NAME'}/payment/pay.cgi?publisher-name=$temp[0]\&paytemplate\=$temp[2]\&languange=$temp[1]\&easycart=1\&item1=widget\&description1=Some Widget\&cost1=1.00\&quantity1=1\" target=\"_blank\">Preview</a></td>\n";
        }
        else {
          print "    <td><a href=\"$script\?function=download_template\&merchant=$temp[0]\&upload_type=payscreen\&template_name=$temp[1]\">$temp[1]</a></td>\n";
          print "    <td>\[<a href=\"$script\?function=remove_template\&merchant=$temp[0]\&upload_type=payscreen\&template_name=$temp[1]\">X</a>\]</td>\n";
          print "    <td><a href=\"https://$ENV{'SERVER_NAME'}/payment/pay.cgi?publisher-name=$temp[0]\&paytemplate\=$temp[1]\&easycart=1\&item1=widget\&description1=Some Widget\&cost1=1.00\&quantity1=1\" target=\"_blank\">Preview</a></td>\n";
        }
        print "  </tr>\n";
      }
      print "</table>\n";
      print "<br>\n";
    }

    if ((-e "$template_dir\/thankyou\/$username\.htm") || ($thankyou_cnt >= 1)){
      # list current thankyou receipt templates 
      print "<b>Thank You Receipt Templates:</b> ";
      print "<table border=0 cellspacing=0 cellpadding=1 width=\"100%\">\n";
      print "  <tr>\n";
      print "    <td bgcolor=\"#eeeeee\" width=\"25%\">Template</td>\n";
      print "    <td bgcolor=\"#eeeeee\" width=\"5%\"> &nbsp;</td>\n";
      print "    <td bgcolor=\"#eeeeee\"> &nbsp;</td>\n";
      print "  </tr>\n";

      if (-e "$template_dir\/thankyou\/$username\.htm") {
        print "  <tr>\n";
        print "    <td><a href=\"$web_template_dir\/thankyou\/$username\.htm\" target=\"_blank\">Default Receipt</a></td>\n";
        print "    <td>\[<a href=\"$script\?function=remove_template\&merchant=$username\&upload_type=thankyou\">X</a>\]</td>\n";
        print "    <td> &nbsp;</td>\n";
        print "  </tr>\n";
      }

      foreach my $filename (sort @thankyou_files) {
        $filename =~ s/.*[\/\\](.*)/$1/;
        my @temp = split(/\_|\./, $filename, 4); # split filename on "-" & "."
        print "  <tr>\n";
        if ($temp[3] =~ /\w/) {
          print "    <td><a href=\"$script\?function=download_template\&merchant=$temp[0]\&upload_type=thankyou\&template_name=$temp[2]\&template_type=$temp[1]\">$temp[1] - $temp[2]</a></td>\n";
          print "    <td>\[<a href=\"$script\?function=remove_template\&merchant=$temp[0]\&upload_type=thankyou\&template_name=$temp[2]\&template_type=$temp[1]\">X</a>\]</td>\n";
          print "    <td><a href=\"$web_template_dir\/thankyou\/$filename\" target=\"_blank\">Preview</a></td>\n";
        }
        else {
          print "    <td><a href=\"$script\?function=download_template\&merchant=$temp[0]\&upload_type=thankyou\&template_name=$temp[1]\">$temp[1]</a></td>\n";
          print "    <td>\[<a href=\"$script\?function=remove_template\&merchant=$temp[0]\&upload_type=thankyou\&template_name=$temp[1]\">X</a>\]</td>\n";
          print "    <td><a href=\"$web_template_dir\/thankyou\/$filename\" target=\"_blank\">Preview</a></td>\n";
        }
        print "  </tr>\n";
      }
      print "</table>\n";
      print "<br>\n";
    }

    if ($billpay_cnt >= 1) {
      # list current billpay language 
      print "<b>Billing Presentment Language:</b> " . $billpay_cnt;
      print "<table border=0 cellspacing=0 cellpadding=1 width=\"100%\">\n";
      print "  <tr>\n";
      print "    <td bgcolor=\"#eeeeee\" width=\"25%\">Template</td>\n";
      print "    <td bgcolor=\"#eeeeee\" width=\"5%\"> &nbsp;</td>\n";
      print "    <td bgcolor=\"#eeeeee\"> &nbsp;</td>\n";
      print "  </tr>\n";
      foreach my $filename (sort @billpay_files) {
        $filename =~ s/.*[\/\\](.*)/$1/;
        my @temp = split(/\_|\./, $filename, 4); # split filename on "-" & "."
        print "  <tr>\n";
        if ($temp[3] =~ /\w/) {
          print "    <td><a href=\"$script\?function=download_template\&merchant=$temp[0]\&upload_type=billpay\&template_name=$temp[2]\&language=$temp[1]\">$temp[1] - $temp[2]</a></td>\n";
          print "    <td>\[<a href=\"$script\?function=remove_template\&merchant=$temp[0]\&upload_type=billpay\&template_name=$temp[2]\&language=$temp[1]\">X</a>\]</td>\n";
          print "    <td> &nbsp;</td>\n";
        }
        else {
          print "    <td><a href=\"$script\?function=download_template\&merchant=$temp[0]\&upload_type=billpay\&template_name=$temp[1]\">$temp[1]</a></td>\n";
          print "    <td>\[<a href=\"$script\?function=remove_template\&merchant=$temp[0]\&upload_type=billpay\&template_name=$temp[1]\">X</a>\]</td>\n";
          print "    <td> &nbsp;</td>\n";
        }
        print "  </tr>\n";
      }
      print "</table>\n";
      print "<br>\n";
    }

    if ($billpaylite_cnt >= 1) {
      # list current billpay lite templates 
      print "<b>BillPay Lite Templates:</b> " . $billpaylite_cnt;
      print "<table border=0 cellspacing=0 cellpadding=1 width=\"100%\">\n";
      print "  <tr>\n";
      print "    <td bgcolor=\"#eeeeee\" width=\"25%\">Template</td>\n";
      print "    <td bgcolor=\"#eeeeee\" width=\"5%\"> &nbsp;</td>\n";
      print "    <td bgcolor=\"#eeeeee\">Example URL</td>\n";
      print "  </tr>\n";
      foreach my $filename (sort @billpaylite_files) {
        $filename =~ s/.*[\/\\](.*)/$1/;
        my @temp = split(/\_|\./, $filename, 4); # split filename on "-" & "."
        print "  <tr>\n";
        print "    <td><a href=\"$script\?function=download_template\&merchant=$temp[0]\&upload_type=billpaylite\&template_name=$temp[1]\">$temp[1]</a></td>\n";
        print "    <td>\[<a href=\"$script\?function=remove_template\&merchant=$temp[0]\&upload_type=billpaylite\&template_name=$temp[1]\">X</a>\]</td>\n";
        print "    <td><a href=\"https://$ENV{'SERVER_NAME'}/bpl/$temp[0]\,paytemplate=$temp[1]\" target=\"_blank\">https://$ENV{'SERVER_NAME'}/bpl/$temp[0]\,paytemplate=$temp[1]</a></td>\n";
        print "  </tr>\n";
      }
      print "</table>\n";
      print "<br>\n";
    }
    print "</td>\n";
    print "  </tr>\n";
  }

  # create preview form
  print "  <tr>\n";
  print "    <th colspan=2>Payment Script Preview</th>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Preview Screen</td>\n";
  print "    <td class=\"menurightside\">\n";
  &create_preview_buttons($username);
  print "</td>\n";
  print "  </tr>\n";

  print "</table>\n";

  &html_tail();

  return;
}

sub section_menu {
  my %query = @_;
  my $username = $query{'merchant'};
  my %feature;

  my $dbh = &miscutils::dbhconnect("pnpmisc");
  my $sth_merchants = $dbh->prepare(q{
      SELECT features
      FROM customers
      WHERE username=?
    }) or die "Can't prepare: $DBI::errstr";
  $sth_merchants->execute("$username") or die "Can't execute: $DBI::errstr";
  my ($features) = $sth_merchants->fetchrow;
  $sth_merchants->finish;

  if ($features ne "") {
    my @array = split(/\,/,$features);
    foreach my $entry (@array) {
      my ($name, $value) = split(/\=/,$entry,2);
      if ($value =~ /\w/) {
        $feature{"$name"} = $value;
      }
    }
  }
  $dbh->disconnect;

  # perform special specific field adjustments here.
  if ($feature{'card-allowed'} =~ /\|/) {
    # convert pipes to commas
    $feature{'card-allowed'} =~ s/\|/\,/g;
  }
  if ($feature{'attendant_cardsallowed'} =~ /\|/) {
    # convert pipes to commas
    $feature{'attendant_cardsallowed'} =~ s/\|/\,/g;
  }

  if ($feature{'billpay_exclude_state'} =~ /\|/) {
    # convert pipes to commas
    $feature{'billpay_exclude_state'} =~ s/\|/\,/g;
    $feature{'billpay_exclude_state'} = uc("$feature{'billpay_exclude_state'}");
  }
  if ($feature{'billpay_exclude_country'} =~ /\|/) {
    # convert pipes to commas
    $feature{'billpay_exclude_country'} =~ s/\|/\,/g;
    $feature{'billpay_exclude_country'} = uc("$feature{'billpay_exclude_country'}");
  }

  if ($feature{'sweeptime'} ne "") {
    my @temp = split(/\:/, $feature{'sweeptime'}, 3);
    # set seperate fields
    $feature{'sweeptime_enable'} = 1;
    $feature{'sweeptime_dstflag'} = $temp[0];
    $feature{'sweeptime_timezone'} = $temp[1];
    $feature{'sweeptime_cutoff'} = sprintf("%d", $temp[2]);
    # remove combined field
    delete $feature{'sweeptime'};
  }

  &html_head("$query{'section'}");

  # show config options
  print "<p><table border=0 cellspacing=0 cellpadding=1 width=\"100%\">\n";
  #print "  <tr>\n";
  #print "    <th colspan=2>Customizable Options</th>\n";
  #print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"leftcell\" colspan=2><b>* NOTE: Leave field empty for default value to be specified.</b></td>\n";
  print "  </tr>\n";

  # create config form
  print "<form method=post action=\"$script\" name=\"features_form\">\n";
  print "<input type=hidden name=\"function\" value=\"update\">\n";
  print "<input type=hidden name=\"merchant\" value=\"$username\">\n";
  print "<input type=hidden name=\"section\" value=\"$query{'section'}\">\n";

  my %category_data; # hold HTML code for each category

  # build html code for each field within the necessary category
  for (my $i = 0; $i <= $#data_fields; $i++) {
    my $category = $data_fields[$i][0];
    my $key      = $data_fields[$i][1];
    my $default  = $data_fields[$i][2];
    my ($format_type, $format_setting) = split(/\|/, $data_fields[$i][3], 2);
    my $title    = $data_fields[$i][4];
    my $exclude  = $data_fields[$i][5];

    # remove all characters not listed within given field's exclude regex
    if ($exclude ne "") {
      if ($query{"$key"} ne "") {
        # clean query field value
        $query{"$key"} =~ s/[^$exclude]//g;
      }
      if ($feature{"$key"} ne "") {
        # clean feature field value
        $feature{"$key"} =~ s/[^$exclude]//g;
      }
    }

    if ($category ne "$query{'section'}") {
      next;
    }

    my $data = "";
    #print "<!-- $i -- \'$category\', \'$key\', \'$default\', \'$format\', \'$title\', SET: \'$feature{$key}\' -->\n";

    $data .= "  <tr>\n";
    $data .= "    <td class=\"leftcell\"><a href=\"javascript:help_win('/admin/help/help.cgi?topic=$key\&section=accountsettings',300,200);\">$title</a></td>\n";
    $data .= "    <td class=\"rightcell\">";
    if ($format_type =~ /^invisible/) {
      # do nothing...
      # NOTE: invisible fields should be hidden from user's view & not included in HTML forms
      #       these fields are overwritten at time of update, under special usage conditions
    }
    elsif ($format_type eq "justtext") {
      $data .= "$feature{$key}\n";
      # NOTE: justtext fields only show text to the user's view & won't add anything to the HTML form
    }
    elsif ($format_type =~ /^text/) {
      if ($format_setting eq "readonly") {
        $data .= "$feature{$key}\n";
        $data .= "<input type=hidden name=\"$key\" value=\"$feature{$key}\">";
      }
      elsif ((exists $feature{$key}) && ($feature{$key})) {
        $data .= "<input type=text name=\"$key\" value=\"$feature{$key}\">";
      }
      else {
        $data .= "<input type=text name=\"$key\" value=\"$default\">";
      }
    }
    elsif ($format_type =~ /^checkbox/) {
      if ((exists $feature{$key}) && ($format_setting eq "$feature{$key}")) {
        $data .= "<input type=checkbox name=\"$key\" value=\"$format_setting\" checked> Check To Enable";
      }
      else {
        $data .= "<input type=checkbox name=\"$key\" value=\"$format_setting\"> Check To Enable";
      }
    }
    elsif ($format_type =~ /^select/) {
      my @options = split(/\,/, $format_setting);
      my $found = 0;

      $data .= "<select name=\"$key\">\n";
      for (my $i = 0; $i <= $#options; $i++) {
        $data .= "<option value=\"$options[$i]\"";
        if ((exists $feature{$key}) && (defined $feature{$key}) && ($options[$i] eq "$feature{$key}") && ($feature{$key} ne "")) {
          $data .= " selected";
          $found = 1;
        }
        elsif (($options[$i] eq "$default") && ((!exists $feature{$key}) || ($feature{$key} eq ""))) {
          $data .= " selected";
          $found = 1;
        }
        $data .= ">$options[$i]</option>\n";
      }
      if ((exists $feature{$key}) && (defined $feature{$key}) && ($found == 0)) {
        $data .= "<option value=\"$feature{$key}\" selected>$feature{$key}</option>\n";
      }
      $data .= "</select>\n";
    }
    else {
      # default to text, for unknown format_types
      if ((exists $feature{$key}) && (defined $feature{$key})) {
        $data .= "<input type=text name=\"$key\" value=\"$feature{$key}\">";
      }
      else {
        $data .= "<input type=text name=\"$key\" value=\"$default\">";
      }
    }
    $data .= "</td>\n";
    $data .= "  </tr>\n";

    $category_data{$category} .= $data; # append data into necessary category
  }

  # now print the data for each category;
  foreach my $key1 (sort keys %category_data) {
    print "  <tr>\n";
    print "    <th colspan=2><i>$key1 Options</i></th>\n";
    print "  </tr>\n";

    print $category_data{$key1};
  }

  #print "  <tr>\n";
  #print "  <th colspan=2 bgcolor=#eeeeee>&nbsp;</th>\n";
  #print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"leftside\">&nbsp;</td>\n";
  print "    <td class=\"rightside\"><input type=submit class=\"button\" name=\"submit\" value=\"Update Settings\"> <input type=reset class=\"button\" value=\"Reset Form\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";
  print "</form>\n";

  &html_tail();

  return;
}

sub update {
  my %query = @_;
  my $username = $query{'merchant'};
  my %feature;

  # clean-up input field values, if necessary.
  if ($query{'card-allowed'} =~ /\,/) {
    # convert commas to pipes
    $query{'card-allowed'} =~ s/\,/\|/g;
  }
  if ($query{'attendant_cardsallowed'} =~ /\,/) {
    # convert commas to pipes
    $query{'attendant_cardsallowed'} =~ s/\,/\|/g;
  }
  if ($query{'billpay_exclude_state'} =~ /\,/) {
    # convert commas to pipes
    $query{'billpay_exclude_state'} =~ s/\,/\|/g;
    $query{'billpay_exclude_state'} = uc("$query{'billpay_exclude_state'}");
  }
  if ($query{'billpay_exclude_country'} =~ /\,/) {
    # convert commas to pipes
    $query{'billpay_exclude_country'} =~ s/\,/\|/g;
    $query{'billpay_exclude_country'} = uc("$query{'billpay_exclude_country'}");
  }

  # perform special processor specific field adjustments here.
  if (($query{'sweeptime_dstflag'} ne "") || ($query{'sweeptime_timezone'} ne "") || ($query{'sweeptime_cutoff'} ne "")) {
    if ($query{'sweeptime_enable'} == 1) {
      $query{'sweeptime'} = sprintf("%1d\:%s\:%02d", $query{'sweeptime_dstflag'}, $query{'sweeptime_timezone'}, $query{'sweeptime_cutoff'});
    }
    else {
      $query{'sweeptime'} = "";
    }
    # remove seperate fields
    delete $query{'sweeptime_enable'};
    delete $query{'sweeptime_dstflag'};
    delete $query{'sweeptime_timezone'};
    delete $query{'sweeptime_cutoff'};
  }


  my $dbh = &miscutils::dbhconnect("pnpmisc");

  # get the features list from the database
  my $sth_merchants = $dbh->prepare(q{
      SELECT features
      FROM customers
      WHERE username=?
    }) or die "Can't prepare: $DBI::errstr";
  $sth_merchants->execute("$username") or die "Can't execute: $DBI::errstr";
  my ($features) = $sth_merchants->fetchrow;
  $sth_merchants->finish;

  # set the features into a hash
  if ($features ne "") {
    my @array = split(/\,/,$features);
    foreach my $entry (@array) {
      my ($name, $value) = split(/\=/,$entry);
      if ($value =~ /\w/) {
        $feature{"$name"} = $value;
      }
    }
  }

  # update features that merchants were permitted to manipulate
  for (my $i = 0; $i <= $#data_fields; $i++) {
    my $category = $data_fields[$i][0];
    my $key      = $data_fields[$i][1];
    my $default  = $data_fields[$i][2];
    my ($format_type, $format_setting) = split(/\|/, $data_fields[$i][3], 2);
    my $title    = $data_fields[$i][4];
    my $exclude  = $data_fields[$i][5];

    # remove all characters not listed within given field's exclude regex
    if ($exclude ne "") {
      if ($query{"$key"} ne "") {
        # clean query field value
        $query{"$key"} =~ s/[^$exclude]//g;
      }
      if ($feature{"$key"} ne "") {
        # clean feature field value
        $feature{"$key"} =~ s/[^$exclude]//g;
      }
    }

    # when a specific section was only updated, skip the other feature fields in the list not assocated to the section edited.
    if (($query{'section'} ne "") && ($category ne "$query{'section'}")) {
      next;
    }

    #print "CAT:$category, KEY:$key, DEF:$default, FT:$format_type, FS:$format_setting, TITLE:$title<br>\n";

    # skip updating these keys, as they are only used with special 'invisible' format_type keys.
    if ($key =~ /^(sweeptime_enable|sweeptime_dstflag|sweeptime_timezone|sweeptime_cutoff)$/) {
      next;
    }

    if ($format_type =~ /invisible/i) {
      $feature{"$key"} = $query{"$key"};
    }
    elsif ($format_type =~ /checkbox/i) {
      $feature{"$key"} = $query{"$key"};
    }
    elsif ((exists $query{"$key"}) && (defined $query{"$key"})) {
      $feature{"$key"} = $query{"$key"};
    }
    else {
      $feature{"$key"} = $default;
    }
  }

  # reset features list, so we can create new one from the features hash 
  my $features_new = "";

  # create new features list from the updated features hash
  foreach my $key (keys %feature) {
    if ($feature{$key} =~ /\w/) {
      if ($features_new ne "") {
        $features_new .= ",";
      }
      $features_new .= "$key=$feature{$key}";
    }
  }

  # write entry the debug log file
  my %log_data = %query;
  $log_data{'FEATURES_OLD'} = $features;
  $log_data{'FEATURES_NEW'} = $features_new;
  &log_changes(%log_data);

  # update the features list in the database
  my $sth = $dbh->prepare(q{
      UPDATE customers
      SET features=?
      WHERE username=?
    }) or die "Can't prepare: $DBI::errstr";
  $sth->execute("$features_new", "$username") or die "Can't execute: $DBI::errstr";
  $sth->finish;

  $dbh->disconnect;

  &html_head();
  print "<p class=\"response_text\">The updates have been applied to your account.</p>\n";
  &create_preview_buttons($username);
  &create_nav_buttons($username);
  &html_tail();

  return;
}

sub upload_file {
  my %query = @_;
  my $username = $query{'merchant'};

  # ensure no tampering with upload_type
  if ($query{'upload_type'} !~ /^(logos|backgrounds|css)$/) {
    my $error = "The location are attempting to upload to is not permitted.\n";
    &error_form("$error");
    return;
  }

  # only allow certain types of usage (Defaults to blank for normal usage)
  if ($query{'upload_usage'} !~ /^(mobile)$/) {
    $query{'upload_usage'} = "";
  }

  # look for uploads that exceed $CGI::POST_MAX
  if (!&CGI::escapeHTML($query->param('upload_file')) && $query->cgi_error()) {
    my $error = $query->cgi_error();
    $error .= "The file you are attempting to upload exceeds the maximum allowable file size.\n";
    &error_form("$error");
    return;
  }

  # delete older file from merchant
  if ($query{'upload_usage'} eq "mobile") {
    unlink(glob("$upload_dir\/$query{'upload_type'}\/$username\_mobile\.*"));
  }
  else {
    unlink(glob("$upload_dir\/$query{'upload_type'}\/$username\.*"));
  }

  # get filename
  my $filename = &CGI::escapeHTML($query->param("upload_file"));
  $filename =~ s/.*[\/\\](.*)/$1/;
  $filename =~ s/[^a-zA-Z0-9\-\_\.]//g;
  $filename =~ s/\.\.//g;

  # get filename's extention
  my @temp = split(/\./, $filename);
  my $filename_ext = $temp[$#temp];
  $filename_ext = lc($filename_ext);

  # make list of all allowed file_extentions
  my @allowed_types;
  my @temp_ascii = split(/\|/, $allowed_ascii_types);
  for (my $i = 0; $i <= $#temp_ascii; $i++) {
    push (@allowed_types, $temp_ascii[$i]);
  }
  my @temp_binary = split(/\|/, $allowed_binary_types);
  for (my $i = 0; $i <= $#temp_binary; $i++) {
    push (@allowed_types, $temp_binary[$i]);
  }

  # test file extention, to ensure file is of an allowed type
  if (($filename_ext !~ /($allowed_ascii_types)$/i) && ($filename_ext !~ /($allowed_binary_types)$/i)) {
    &error_form("Invalid File Type... You may only upload files with the following extentions: @allowed_types");
    return;
  }

  # grab the file uploaded
  my $upload_filehandle = $query->upload("upload_file");
  $upload_filehandle =~ s/[^a-zA-Z0-9\_\-\.\ \:\\]//g;

  # now set the filename as USERNAMElogo.ext (for example: pnpdemo.jpg)
  if ($query{'upload_usage'} eq "mobile") {
    $filename = "$username\_mobile\.$filename_ext";
  }
  else {
    $filename = "$username\.$filename_ext";
  }
  $filename = lc($filename);
  $filename =~ s/\.\.//g;

  # open target file on harddisk
  my $target_file = "$upload_dir\/$query{'upload_type'}\/$filename";
  my $path_webtxt = &pnp_environment::get('PNP_WEB_TXT');
  my $tmptarget_file = "$path_webtxt/uploaddir/$username\_$query{'upload_type'}\_$filename";
  &sysutils::filelog("write",">$target_file");
  open(UPLOADFILE,'>',"$tmptarget_file") or die "Cant open target file for writing. $!";

  # use/assume binary format
  binmode UPLOADFILE;

  # write the uploaded file to the target file
  while(<$upload_filehandle>) {
    print UPLOADFILE;
  }

  # close targe file handle
  close(UPLOADFILE);

  # force 666 file permissions - to ensure files Cant be executed
  chmod(0666, "$upload_dir\/$filename");
  &sysutils::logupload("$username","upload","$target_file","$tmptarget_file"); # carol

  my $dbh = &miscutils::dbhconnect("pnpmisc");

  # add the image (logo or background) to the proper /pay/ setting/
  my $settingName;
  my $imageName;

  if ($query{'upload_type'} eq 'logos') {
    $settingName = 'logoURL';
    $imageName = 'logo';
  } elsif ($query{'upload_type'} eq 'backgrounds') {
    $settingName = 'backgroundURL';
    $imageName = 'background';
  }

  if (defined $settingName) {
    my $sth_pay_settings = $dbh->prepare(q{
        DELETE FROM ui_payscreens_general_settings
        WHERE type=?
        AND identifier=?
        AND setting_name=?
      });
    $sth_pay_settings->execute('account',$username,$settingName);
  
    $sth_pay_settings = $dbh->prepare(q{
        INSERT INTO ui_payscreens_general_settings
        (type,identifier,setting_name,setting_value)
        VALUES (?,?,?,?)
      });
    my $relativeURL = '/_img/merchant/' . $username . '/' . $imageName . '.' . $filename_ext;
    $sth_pay_settings->execute('account',$username,$settingName,$relativeURL);
  }
  # end of adding the image to the proper setting
  

  # this section of code adds XXXXX-link to the features list
  my %feature;


  # get the features list from the database
  my $sth_merchants = $dbh->prepare(q{
      SELECT features
      FROM customers
      WHERE username=?
    }) or die "Can't prepare: $DBI::errstr";
  $sth_merchants->execute("$username") or die "Can't execute: $DBI::errstr";
  my ($features) = $sth_merchants->fetchrow;
  $sth_merchants->finish;

  # set the features into a hash
  if ($features ne "") {
    my @array = split(/\,/,$features);
    foreach my $entry (@array) {
      my ($name, $value) = split(/\=/,$entry);
      if ($value =~ /\w/) {
        $feature{"$name"} = $value;
      }
    }
  }

  # update parameter in features hash
  if (($query{'upload_type'} eq "logos") && ($query{'upload_usage'} eq "")) {
    $feature{'image-link'} = "$web_upload_dir\/$query{'upload_type'}\/$filename";
  }
  elsif (($query{'upload_type'} eq "backgrounds") && ($query{'upload_usage'} eq "")) {
    $feature{'backimage'} = "$web_upload_dir\/$query{'upload_type'}\/$filename";
  }
  elsif (($query{'upload_type'} eq "css") && ($query{'upload_usage'} eq "")) {
    $feature{'css-link'} = "$web_upload_dir\/$query{'upload_type'}\/$filename";
  }

  elsif (($query{'upload_type'} eq "logos") && ($query{'upload_usage'} eq "mobile")) {
    $feature{'mobileimage-link'} = "$web_upload_dir\/$query{'upload_type'}\/$filename";
  }
  elsif (($query{'upload_type'} eq "backgrounds") && ($query{'upload_usage'} eq "mobile")) {
    $feature{'mobilebackimage'} = "$web_upload_dir\/$query{'upload_type'}\/$filename";
  }
  elsif (($query{'upload_type'} eq "css") && ($query{'upload_usage'} eq "mobile")) {
    $feature{'mobilecss-link'} = "$web_upload_dir\/$query{'upload_type'}\/$filename";
  }

  # reset features list, so we can create new one from the features hash
  my $features_new = "";

  # create new features list from the updated features hash
  foreach my $key (keys %feature) {
    if ($features_new ne "") { 
      $features_new .= ","; 
    }
    $features_new .= "$key=$feature{$key}";
  }

  # write entry the debug log file
  my %log_data = %query;
  $log_data{'TARGET_FILE'} = $target_file;
  $log_data{'FEATURES_OLD'} = $features;
  $log_data{'FEATURES_NEW'} = $features_new;
  &log_changes(%log_data);

  # update the features list in the database
  my $sth = $dbh->prepare(q{
      UPDATE customers
      SET features=?
      WHERE username=?
    }) or die "Can't prepare: $DBI::errstr";
  $sth->execute("$features_new", "$username") or die "Can't execute: $DBI::errstr";
  $sth->finish;

  $dbh->disconnect;


  &html_head();
  print "<p class=\"response_text\">The file will be uploaded to your account in 1 minute.</p>\n";
  &create_preview_buttons($username);
  &create_nav_buttons($username);

  #if ($query{'upload_type'} =~ /^(logos|backgrounds)$/) {
  #  print "<p><b>Image you just uploaded:</b>\n";
  #  print "<br><img src=\"$web_upload_dir\/$query{'upload_type'}\/$filename\" border=1>\n";
  #}

  &html_tail();

  return;
}

sub error_form {
  my ($error) = @_;

  &html_head();
  print "<p class=\"error_text\"><b>ERROR:</b> $error</p>\n";
  &html_tail();

  exit;
}

sub remove_file {
  my %query = @_;
  my $username = $query{'merchant'};
  my %feature;

  if ($username !~ /^(pnpdemo|pnptest|billpaydem|demoacct1)$/) {

    # ensure no tampering with upload_type
    if ($query{'upload_type'} !~ /^(logos|backgrounds|css)$/) {
      my $error = "The location are attempting to delete from is not permitted.\n";
      &error_form("$error");
      return;
    }

    # only allow certain types of usage (Defaults to blank for normal usage)
    if ($query{'upload_usage'} !~ /^(mobile)$/) {
      $query{'upload_usage'} = "";
    }

    my $dbh = &miscutils::dbhconnect("pnpmisc");

    # get the features list from the database
    my $sth_merchants = $dbh->prepare(q{
        SELECT features
        FROM customers
        WHERE username=?
      }) or die "Can't prepare: $DBI::errstr";
    $sth_merchants->execute("$username") or die "Can't execute: $DBI::errstr";
    my ($features) = $sth_merchants->fetchrow;
    $sth_merchants->finish;

    # set the features into a hash
    if ($features ne "") {
      my @array = split(/\,/,$features);
      foreach my $entry (@array) {
        my ($name, $value) = split(/\=/,$entry);
        if ($value =~ /\w/) {
          $feature{"$name"} = $value;
        }
      }
    }

    # remove field & delete related files.
    if (($query{'upload_type'} eq "logos") && ($query{'upload_usage'} eq "")) {
      delete($feature{"image-link"});
      #unlink(glob("$upload_dir\/$query{'upload_type'}\/$username\.*"));
      &sysutils::logupload("$username","delete","$upload_dir\/$query{'upload_type'}\/$username\.*"); # carol
    }
    elsif (($query{'upload_type'} eq "backgrounds") && ($query{'upload_usage'} eq "")) {
      delete($feature{"backimage"});
      #unlink(glob("$upload_dir\/$query{'upload_type'}\/$username\.*"));
      &sysutils::logupload("$username","delete","$upload_dir\/$query{'upload_type'}\/$username\.*"); # carol
    }
    elsif (($query{'upload_type'} eq "css") && ($query{'upload_usage'} eq "")) {
      delete($feature{"css-link"});
      #unlink(glob("$upload_dir\/$query{'upload_type'}\/$username\.*"));
      &sysutils::logupload("$username","delete","$upload_dir\/$query{'upload_type'}\/$username\.*"); # carol
    }

    elsif (($query{'upload_type'} eq "logos") && ($query{'upload_usage'} eq "mobile")) {
      delete($feature{"mobileimage-link"});
      #unlink(glob("$upload_dir\/$query{'upload_type'}\/$username\_mobile\.*"));
      &sysutils::logupload("$username","delete","$upload_dir\/$query{'upload_type'}\/$username\_mobile\.*"); # carol
    }
    elsif (($query{'upload_type'} eq "backgrounds") && ($query{'upload_usage'} eq "mobile")) {
      delete($feature{"mobilebackimage"});
      #unlink(glob("$upload_dir\/$query{'upload_type'}\/$username\_mobile\.*"));
      &sysutils::logupload("$username","delete","$upload_dir\/$query{'upload_type'}\/$username\_mobile\.*"); # carol
    }
    elsif (($query{'upload_type'} eq "css") && ($query{'upload_usage'} eq "mobile")) {
      delete($feature{"mobilecss-link"});
      #unlink(glob("$upload_dir\/$query{'upload_type'}\/$username\_mobile\.*"));
      &sysutils::logupload("$username","delete","$upload_dir\/$query{'upload_type'}\/$username\_mobile\.*"); # carol
    }

    # reset features list, so we can create new one from the features hash
    my $features_new = "";

    # create new features list from the updated features hash
    foreach my $key (keys %feature) {
      if ($features_new ne "") { 
        $features_new .= ","; 
      }
      $features_new .= "$key=$feature{$key}";
    }

    # write entry the debug log file
    my %log_data = %query;
    $log_data{'FEATURES_OLD'} = $features;
    $log_data{'FEATURES_NEW'} = $features_new;
    &log_changes(%log_data);

    # update the features list in the database
    my $sth = $dbh->prepare(q{
        UPDATE customers
        SET features=?
        WHERE username=?
      }) or die "Can't prepare: $DBI::errstr";
    $sth->execute("$features_new", "$username") or die "Can't execute: $DBI::errstr";
    $sth->finish;

    $dbh->disconnect;
  }

  &html_head();
  print "<p class=\"response_text\">The file will be removed from your account in 1 minute.\n";

  print "<p><form method=post action=\"$script\">\n";
  print "<input type=hidden name=\"merchant\" value=\"$username\">\n";
  print "<input type=submit class=\"button\" name=\"submit\" value=\"Make Additional Changes\">\n";
  print "<p><input type=button class=\"button\" value=\"Completed Changes - Exit Wizard\" onClick=\"javascript:closewin();\">\n";
  print "</form>\n";

  &html_tail();

  return;
}

sub create_preview_buttons {
  my $username = shift;
  # create preview form button
  print "<form method=post action=\"/payment/pay.cgi\" target=\"_blank\">\n";
  print "<input type=hidden name=\"publisher-email\" value=\"trash\@plugnpay.com\">\n";
  print "<input type=hidden name=\"publisher-name\" value=\"$username\">\n";
  print "<input type=hidden name=\"order-id\" value=\"PreviewForm\">\n";
  #print "<input type=hidden name=\"card-allowed\" value=\"Visa,Mastercard\">\n";
  print "<input type=hidden name=\"easycart\" value=\"1\">\n";
  print "<input type=hidden name=\"item1\" value=\"SKU1\">\n";
  print "<input type=hidden name=\"quantity1\" value=\"1\">\n";
  print "<input type=hidden name=\"cost1\" value=\"1.00\">\n";
  print "<input type=hidden name=\"description1\" value=\"Sample Product #1\">\n";
  print "<input type=hidden name=\"item2\" value=\"SKU1\">\n";
  print "<input type=hidden name=\"quantity2\" value=\"2\">\n";
  print "<input type=hidden name=\"cost2\" value=\"2.00\">\n";
  print "<input type=hidden name=\"description2\" value=\"Sample Product #2\">\n";
  print "<input type=hidden name=\"item3\" value=\"SKU1\">\n";
  print "<input type=hidden name=\"quantity3\" value=\"3\">\n";
  print "<input type=hidden name=\"cost3\" value=\"3.00\">\n";
  print "<input type=hidden name=\"description3\" value=\"Sample Product #3\">\n";
  #print "<input type=checkbox name=\"shipinfo\" value=\"1\"> Show With Optional Shipping Address\n";
  print "<input type=submit class=\"button\" name=\"return\" value=\"Review Changes With Saved Options\">\n";
  print "</form>\n";

  return;
}

sub create_nav_buttons {
  my $username = shift;
  # create navigation buttons
  print "<p><form method=post action=\"$script\">\n";
  print "<input type=hidden name=\"merchant\" value=\"$username\">\n";
  print "<input type=submit class=\"button\" name=\"submit\" value=\"Make Additional Changes\">\n";
  print "<p><input type=button class=\"button\" value=\"Completed Changes - Exit Wizard\" onClick=\"javascript:closewin();\">\n";
  print "</form>\n";

  return;
}

sub download_template {
  my %query = @_;
  my $username = $query{'merchant'};

  # ensure no tampering with upload_type
  if ($query{'upload_type'} !~ /^(transition|payscreen|billpay|billpaylite|thankyou)$/) {
    print "Content-Type: text/html\n";
    print "X-Content-Type-Options: nosniff\n";
    print "X-Frame-Options: SAMEORIGIN\n\n";
    my $error = "The location are attempting to download from is not permitted.\n";
    &error_form("$error");
    return;
  }

  # default template name, when no template name is provided
  if (($query{'template_name'} eq "") && ($query{'upload_type'} =~ /^(payscreen|billpay)$/)) {
    $query{'template_name'} = "paytemplate";
  }
  elsif (($query{'template_name'} eq "") && ($query{'upload_type'} =~ /^(billpaylite)$/)) {
    $query{'template_name'} = "template";
  }

  # clean & filter template name & language
  $query{'template_name'} =~ s/[^a-zA-Z0-9]//g; # remove all non-alphanumeric characters
  $query{'template_name'} = lc("$query{'template_name'}"); # for value to lower case
  $query{'template_name'} = substr($query{'template_name'},0,20);

  $query{'language'} =~ s/[^a-zA-Z]//g; # remove all non-alpha characters
  $query{'language'} = lc("$query{'language'}"); # for value to lower case
  $query{'language'} = substr($query{'language'},0,2);

  my ($target_file);

  # limit location in which template files can be downloaded from
  if ($query{'upload_type'} =~ /^(payscreen|billpay)$/) {
    if ($query{'language'} ne "") {
      $target_file = "$template_dir\/$query{'upload_type'}\/$username\_$query{'language'}\_$query{'template_name'}\.txt";
    }
    else {
      $target_file = "$template_dir\/$query{'upload_type'}\/$username\_$query{'template_name'}\.txt";
    }
  }
  elsif ($query{'upload_type'} =~ /^(billpaylite)$/) {
    $target_file = "$template_dir\/$query{'upload_type'}\/$username\_$query{'template_name'}\.txt";
  }
  elsif ($query{'upload_type'} =~ /^(thankyou)$/) {
    if (($query{'template_type'} ne "") && ($query{'template_name'} ne "")) {
      $target_file = "$template_dir\/$query{'upload_type'}\/$username\_$query{'template_type'}\_$query{'template_name'}\.htm";
    }
    elsif ($query{'template_name'} ne "") {
      $target_file = "$template_dir\/$query{'upload_type'}\/$username\_$query{'template_name'}\.htm";
    }
    else {
      $target_file = "$template_dir\/$query{'upload_type'}\/$username\.htm";
    }
  }
  else { ## assume transition template
    if ($query{'template_name'} ne "") {
      $target_file = "$template_dir\/$query{'upload_type'}\/$username\_$query{'template_name'}\.html";
    }
    else {
      $target_file = "$template_dir\/$query{'upload_type'}\/$username\_deftran\.html";
    }
  }

  # write entry the debug log file
  my %log_data = %query;
  $log_data{'TARGET_FILE'} = $target_file;
  &log_changes(%log_data);

  if (-e "$target_file") {
    my @temp = split("\/", $target_file);
    my $filename = $temp[$#temp];
    $filename =~ s/.*[\/\\](.*)/$1/;
    $filename =~ s/[^a-zA-Z0-9\-\_\.]//g;
    $filename =~ s/\.\.//g;

    print "Content-Type: text/plain\n";
    print "X-Content-Type-Options: nosniff\n";
    print "X-Frame-Options: SAMEORIGIN\n";
    print "Content-Disposition: attachment; filename=\"$filename\"\n\n";

    # open target file on harddisk
    &sysutils::filelog("read",">$target_file");
    open(INFILE,'<',"$target_file") or die "Cant open target file for reading. $!";
    while(<INFILE>) {
      print $_;
    }
    close(INFILE);
  }
  else {
    print "Content-Type: text/html\n";
    print "X-Content-Type-Options: nosniff\n";
    print "X-Frame-Options: SAMEORIGIN\n\n";
    my $error = "The template you're attempting to download Cant be found.\n";
    &error_form("$error");
    return;
  }

  return;
}

sub remove_template {
  my %query = @_;
  my $username = $query{'merchant'};

  # ensure no tampering with upload_type
  if ($query{'upload_type'} !~ /^(transition|payscreen|billpay|billpaylite|thankyou)$/) {
    my $error = "The location are attempting to delete from is not permitted.\n";
    &error_form("$error");
    return;
  }

  if ($username =~ /^(affinisc|lawpay)$/) {
    # prevent template removal from specific PnP accounts
    my $error = "The template Cant be removed, due to restriction on account. Contact tech support.\n";
    &error_form("$error");
    return;
  }

  # clean & filter template name & language
  $query{'template_name'} =~ s/[^a-zA-Z0-9]//g; # remove all non-alphanumeric characters
  $query{'template_name'} = lc("$query{'template_name'}"); # for value to lower case
  $query{'template_name'} = substr($query{'template_name'},0,20);

  $query{'template_type'} =~ s/[^a-zA-Z]//g; # remove all non-alpha characters
  $query{'template_type'} = lc("$query{'template_name'}"); # for value to lower case
  $query{'template_type'} = substr($query{'template_name'},0,3);

  $query{'language'} =~ s/[^a-zA-Z]//g; # remove all non-alpha characters
  $query{'language'} = lc("$query{'language'}"); # for value to lower case
  $query{'language'} = substr($query{'language'},0,2);

  # write entry the debug log file
  my %log_data = %query;
  &log_changes(%log_data);

  # delete older file for merchant if necessary
  if ($query{'upload_type'} =~ /^(payscreen|billpay)$/) {
    if ($query{'language'} ne "") {
      unlink(glob("$template_dir\/$query{'upload_type'}\/$username\_$query{'language'}\_$query{'template_name'}\.txt"));
      &sysutils::logupload("$username","delete","$template_dir\/$query{'upload_type'}\/$username\_$query{'language'}\_$query{'template_name'}\.txt"); # carol
    }
    else {
      unlink(glob("$template_dir\/$query{'upload_type'}\/$username\_$query{'template_name'}\.txt"));
      &sysutils::logupload("$username","delete","$template_dir\/$query{'upload_type'}\/$username\_$query{'template_name'}\.txt"); # carol
    }
  }
  elsif ($query{'upload_type'} =~ /^(billpaylite)$/) {
    unlink(glob("$template_dir\/$query{'upload_type'}\/$username\_$query{'template_name'}\.txt"));
    &sysutils::logupload("$username","delete","$template_dir\/$query{'upload_type'}\/$username\_$query{'template_name'}\.txt"); # carol
  }
  elsif ($query{'upload_type'} =~ /^(thankyou)$/) {
    if (($query{'template_type'} ne "") && ($query{'template_type'} ne "")) {
      unlink(glob("$template_dir\/$query{'upload_type'}\/$username\_$query{'template_type'}\_$query{'template_name'}\.txt"));
      &sysutils::logupload("$username","delete","$template_dir\/$query{'upload_type'}\/$username\_$query{'template_type'}\_$query{'template_name'}\.txt"); # carol
    }
    elsif ($query{'template_name'}) {
      unlink(glob("$template_dir\/$query{'upload_type'}\/$username\_$query{'template_name'}\.txt"));
      &sysutils::logupload("$username","delete","$template_dir\/$query{'upload_type'}\/$username\_$query{'template_name'}\.txt"); # carol
    }
    else {
      unlink(glob("$template_dir\/$query{'upload_type'}\/$username\.htm"));
      &sysutils::logupload("$username","delete","$template_dir\/$query{'upload_type'}\/$username\.htm"); # carol
    }
  }
  else { ## assume transition template
    if ($query{'template_name'} ne "") {
      unlink(glob("$template_dir\/$query{'upload_type'}\/$username\_$query{'template_name'}\.html"));
      &sysutils::logupload("$username","delete","$template_dir\/$query{'upload_type'}\/$username\_$query{'template_name'}\.html"); # carol
    }
    else {
      unlink(glob("$template_dir\/$query{'upload_type'}\/$username\_deftran\.html"));
      &sysutils::logupload("$username","delete","$template_dir\/$query{'upload_type'}\/$username\_deftran\.html"); # carol
    }
  }

  &html_head();
  print "<p class=\"response_text\">The template file will be removed from your account in 1 minute.\n";
  &create_nav_buttons($username);
  &html_tail();

  return;
}

sub is_linked_acct {
  # Purpose: Check merchant name given & make sure its a linked account username
  #          Returns validated username to use (supplied merchant if linked, or login username if not linked)
  my ($username, $merchant) = @_;
  if (new PlugNPay::GatewayAccount::LinkedAccounts($username)->isLinkedTo($merchant)) {
    return "$merchant";
  } else {
    return "$username";
  }
}

sub overview {
  my ($reseller, $merchant) = @_;
  my ($db_merchant);

  my $dbh = &miscutils::dbhconnect("pnpmisc");

  if ($reseller eq "cableand") {
    my $sth = $dbh->prepare(q{
        SELECT username   
        FROM customers
        WHERE reseller IN ('cableand','cccc','jncb','bdagov') 
        AND username=? 
      }) or die "Can't do: $DBI::errstr";
    $sth->execute("$merchant") or die "Can't execute: $DBI::errstr";
    ($db_merchant) = $sth->fetchrow;
    $sth->finish;
  }
  elsif ($reseller eq "volpayin") {
    my $sth = $dbh->prepare(q{
        SELECT username   
        FROM customers
        WHERE processor='volpay'
        AND username=? 
      }) or die "Can't do: $DBI::errstr";
    $sth->execute("$merchant") or die "Can't execute: $DBI::errstr";
    ($db_merchant) = $sth->fetchrow;
    $sth->finish;
  }
  else {
    my $sth = $dbh->prepare(q{ 
        SELECT username 
        FROM customers 
        WHERE reseller=?
        AND username=?
      }) or die "Can't do: $DBI::errstr";
    $sth->execute("$reseller", "$merchant") or die "Can't execute: $DBI::errstr";
    ($db_merchant) = $sth->fetchrow;
    $sth->finish;
  }

  $dbh->disconnect;

  return $db_merchant;
}

sub log_changes {
  my %query = @_;

  my $t = time();
  my $time = gmtime($t);
  my @now = gmtime($t);
  my $month = sprintf("%02d", $now[4]+1);

  open(DEBUG,'>>',"/home/pay1/database/debug/account_settings$month\.txt");
  print DEBUG "TIME:$time, RA:$remoteIP, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, PID:$$, RM:$ENV{'REQUEST_METHOD'}, USERNAME:$ENV{'REMOTE_USER'}, LOGIN:$ENV{'LOGIN'}, SEC_LEVEL:$ENV{'SEC_LEVEL'}";

  if ($query{'FEATURES_OLD'} ne "") {
    # URL encode old feature string, to make parsing the log entry easier.
    $query{'FEATURES_OLD'} =~ s/([\W])/"%" . uc(sprintf("%2.2x",ord($1)))/eg;
  }

  if ($query{'FEATURES_NEW'} ne "") {
    # URL encode new feature string, to make parsing the log entry easier.
    $query{'FEATURES_NEW'} =~ s/([\W])/"%" . uc(sprintf("%2.2x",ord($1)))/eg;
  }

  foreach my $key (sort keys %query) {
    print DEBUG ", $key:$query{$key}";
  }
  print DEBUG "\n";
  close(DEBUG);

  return;
}

