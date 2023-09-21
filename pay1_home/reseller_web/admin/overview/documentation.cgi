#!/bin/env perl
 
require 5.001;
$| = 1;

# Note: All documentation listed on this page MUST go thought the 'doc_replace.cgi' script
#       in order to enforce PCI documentation restrictions for demo account access.
 
use lib $ENV{'PNP_PERL_LIB'};
use CGI;
use DBI;
use miscutils;
use strict;

my %query;
my $query = new CGI;

if ($ENV{'SEC_LEVEL'} > 12) {
  print "Content-Type: text/html\n\n";
  print "Your current security level is not cleared for this operation. <p>Please contact Technical Support if you believe this to be in error. ";
  exit;
}

 
my @array = $query->param;
foreach my $var (@array) {
  $var =~ s/[^a-zA-Z0-9\_\-]//g;
  $query{"$var"} = &CGI::escapeHTML($query->param($var));
}

my $dbh = &miscutils::dbhconnect("pnpmisc");
my $sth = $dbh->prepare(qq{
      select processor
      from customers 
      where username=?
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
$sth->execute("$ENV{'REMOTE_USER'}") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
my ($processor) = $sth->fetchrow;
$sth->finish; 

$dbh->disconnect;

$ENV{'REMOTE_ADDR'} = $ENV{'HTTP_X_REMOTE_ADDR'};

my $domain = $ENV{'HTTP_HOST'};

print "Content-Type: text/html\n\n";
#print "<!-- Domain: $domain -->";

&html_head();

print "<p>Welcome to your online documentation center. This portion of the site has been constructed to provide merchants access to service and integration documentation. By following the links below you should find all the information you will need in order to better integrate &amp; use our services. If you do not find the answer to your question or problem within our documentation, please see our online FAQ & glossary through the links below.\n";

print "<div align=\"center\">\n";
print "<p><a href=\"/admin/wizards/faq_board.cgi\">Online Frequently Asked Questions (FAQ)</a>\n";
print "<p><a href=\"/admin/wizards/glossary.cgi\">Online Glossary Of Terms</a>\n";
print "</div>\n";

print "<p>If after reading our documentation and visiting our FAQ section, you can't find the answers to your issue, please submit your question, comment or problem to your <a href=\"javascript:change_win('/admin/helpdesk.cgi',600,500,'ahelpdesk')\">online helpdesk</a>.\n";

print "<p>When submitting a message to your helpdesk, please be as specific as possible, providing examples or steps to reproduce the issue when possible. Please also remember to also submit your merchant username, without this information; we will not know which account requires our assistance.\n";

print "<p>Thank You,\n";
print "<br>Technical Support\n";

print <<EOF; 
<div align="center">
<p><table width="75%" border="0" cellspacing="0" cellpadding="2" style="border: 1px outset; border-style:solid; border-color:666666;">
  <tr class=\"listsection_title\">
    <th height="19">General Documents</th>
    <th height="19" align="center">File</th>
  </tr>

  <tr class="listrow_color0">
    <td>Getting Started Guide</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Getting_Started_Guide.htm">Click Here</a></td>
  </tr>

  <tr class="listrow_color1">
    <td>Document Appendix<br><em style="font-size:85%">(includes Response, Country, and State Codes)</em></td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Appendix.htm">Click Here</a></td>
  </tr>

  <tr class="listrow_color0">
    <td>Address Verification System (AVS)</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=AVS_Specifications.htm">Click Here</a></td>
  </tr>

  <tr class="listrow_color1">
    <td>Email Management</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Email_Management.htm">Click Here</a></td>
  </tr>

  <tr class="listrow_color0">
    <td>Security Administration</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Security_Administration.htm">Click Here</a></td>
  </tr>

  <tr class="listrow_color1">
    <td>QuickBooks&#153; Module</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=QuickBooks_Module.htm">Click Here</a></td>
  </tr>
</table>

<p><table width="75%" border="0" cellspacing="0" cellpadding="2" style="border: 1px outset; border-style:solid; border-color:666666;">
  <tr class=\"listsection_title\">
    <th height="19">Integration/Specifications Documents</th>
    <th height="19" align="center">File</th>
  </tr>

  <tr class="listrow_color0">
    <td>Integration Specifications</td>
    <td align="center"><a href=\"/admin/doc_replace.cgi?doc=Integration_Specification.htm\">Click Here</a></td>
  </tr>

  <tr class="listrow_color1">
    <td>Remote Client Specifications<br><em style="font-size:85%">(For use with API's)</em></td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Remote_Client_Integration_Specification.htm">Click Here</a></td>
  </tr>

  <tr class="listrow_color0">
    <td>Smart Screens v2 Specifications<br><em style="font-size:85%">(For Smart Screens v1 specs, see Integration Specifications)</em></td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Smart_Screens_v2.htm">Click Here</a></td>
  </tr>

  <tr class="listrow_color1">
    <td>Upload Batch Specifications</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Upload_Batch_Instructions.htm">Click Here</a></td>
  </tr>

  <tr class="listrow_color0">
    <td>Shipping Calculator Integration</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Shipping_Calculator_Integration.htm">Click Here</a></td>
  </tr>

  <tr class="listrow_color1">
    <td>XML Specifications</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=XML_Specifications.htm">Click Here</a></td>
  </tr>

  <tr class="listrow_color0">
    <td>iFrame API Setup</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=iFrame_API_Setup.htm">Click Here</a></td>
  </tr>

  <tr class="listrow_color1">
    <td>Level III Purchase Card Specifications<br><em style="font-size:85%">(Paytechtampa merchant account holders ONLY)<em></td>
    <td align="center"><a href="/docs/Level_III_Purchase_Card.html">Click Here</a></td>
  </tr>

  <tr class="listrow_color0">
    <td>Payment Script - Shipping Rules Wizard</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Shipping_Rule_Wizard.htm">Click Here</a></td>
  </tr>

  <tr class="listrow_color1">
    <td>Authorize.Net Emulation Guide<br></td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=AuthorizeNet_Emulation_Guide.htm">Click Here</a></td>
  </tr>

  <tr class="listrow_color0">
    <td>Custom Payscreen Templates<br></td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Payscreen_Template.htm">Click Here</a></td>
  </tr>

  <tr class="listrow_color1">
    <td>Custom Transition Templates<br></td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Transition_Template.htm">Click Here</a></td>
  </tr>
</table>

<p><table width="75%" border="0" cellspacing="0" cellpadding="2" style="border: 1px outset; border-style:solid; border-color:666666;">
  <tr class=\"listsection_title\">
    <th height="19">Electronic Checking Documents</th>
    <th height="19" align="center">File</th>
  </tr>

  <tr class="listrow_color0">
    <td>Electronic Checking Documentation</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Electronic_Checking.htm">Click Here</a></td>
  </tr>

  <tr class="listrow_color1">
    <td>SEC Code Documentation</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Electronic_Checking_-_SEC_Code_Documentation.htm">Click Here</a></td>
  </tr>
</table>

<p><table width="75%" border="0" cellspacing="0" cellpadding="2" style="border: 1px outset; border-style:solid; border-color:666666;">
  <tr class=\"listsection_title\">
    <th height="19">Premium Service Documents</th>
    <th height="19" align="center">File</th>
  </tr>

  <tr>
    <td class=\"listsection_title\" colspan="2"><i>Affiliate Management:</i></td>
  </tr>
  <tr class="listrow_color0">
    <td>Administration Area Instructions</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Affiliate_Management.htm">Click Here</a></td>
  </tr>

  <tr>
    <td class=\"listsection_title\" colspan="2"><i>Billing Presentment:</i></td>
  </tr>
  <tr class="listrow_color0">
    <td>Overview Documentation</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Billing_Presentment_-_Overview.htm">Click Here</a></td>
  </tr>
  <tr class="listrow_color1">
    <td>Invoice Upload File Specifications</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Billing_Presentment_-_Upload_Format.htm">Click Here</a></td>
  </tr>

  <tr>
    <td class=\"listsection_title\" colspan="2"><i>Coupon Management:</i></td>
  </tr>
  <tr class="listrow_color0">
    <td>Administration Area Instructions</td>
    <td align="center"><a
    href="/admin/doc_replace.cgi?doc=Coupon_Management.htm">Click Here</a></td>
  </tr>

  <tr>
    <td class=\"listsection_title\" colspan="2"><i>Digital Download Delivery:</i></td>
  </tr>
  <tr class="listrow_color0">
    <td>Overview Documentation</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Digital_Download_Overview.htm">Click Here</a></td>
  </tr>

  <tr>
    <td class=\"listsection_title\" colspan="2"><i>EasyCart Shopping Cart:</i></td>
  </tr>
  <tr class="listrow_color0">
    <td>Integration Instructions</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=EasyCart_Integration_Instructions.htm">Click Here</a></td>
  </tr>
  <tr class="listrow_color1">
    <td>Getting Started Guide</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=EasyCart_-_Getting_Started.htm">Click Here</a></td>
  </tr>
  <tr class="listrow_color0">
    <td>Product Database Specifications</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=EasyCart_Product_Database_Specifications.htm">Click Here</a></td>
  </tr>
  <tr class="listrow_color1"> 
    <td>Product Database Wizard</td> 
    <td align="center"><a href="/admin/doc_replace.cgi?doc=EasyCart_Product_Database_Wizard.htm">Click Here</a></td>
  </tr> 

  <tr>
    <td class=\"listsection_title\" colspan="2"><i>FraudTrak:</i></td>
  </tr>
  <tr class="listrow_color0">
    <td>Price Validation Upload Specifications</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=FraudTrak_-_Price_Validation_Upload_Specifications.htm">Click Here</a></td>
  </tr>
  <tr class="listrow_color1">
    <td>Fraudtrak2 Features</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=FraudTrak2.htm">Click Here</a></td>
  </tr>

  <tr>
    <td class=\"listsection_title\" colspan="2"><i>Membership Management:</i></td>
  </tr>
  <tr class="listrow_color0">
    <td>Administration Area Instructions</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Membership_Management_Administration_Area_Instructions.htm">Click Here</a></td>
  </tr>
  <tr class="listrow_color1">
    <td>Attendant Setup Instructions</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Membership_Management_Attendant_Web_Page_Setup.htm">Click Here</a></td>
  </tr>
  <tr class="listrow_color0">
    <td>Database Export Documentation</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Membership_Management_Database_Export.htm">Click Here</a></td>
  </tr>
  <tr class="listrow_color1">
    <td>Database Import Specifications</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Membership_Management_Database_Import_Specifications.htm">Click Here</a></td>
  </tr>
  <tr class="listrow_color0">
    <td>Join Page Wizard Instructions</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Membership_Management_Join_Web_Page_Wizard.htm">Click Here</a></td>
  </tr>
  <tr class="listrow_color1">
    <td>Overview Documentation</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Membership_Management_Overview.htm">Click Here</a></td>
  </tr>
  <tr class="listrow_color0">
    <td>Payment Plans Setup Instructions</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Membership_Management_Payment_Plans_Setup_Instructions.htm">Click Here</a></td>
  </tr>
</table>

<p><table width="75%" border="0" cellspacing="0" cellpadding="2" style="border: 1px outset; border-style:solid; border-color:666666;">
  <tr class=\"listsection_title\"> 
    <th height="19">Retail/POS Documents</th>
    <th height="19" align="center">File</th> 
  </tr>

  <tr>
    <td class=\"listsection_title\" colspan="2"><i>Retail Hardware:</i></td>
  </tr>
  <tr class="listrow_color0">
    <td>Compatible Retail Hardware</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Compatible_Retail_Hardware.htm">Click Here</a></td>
  </tr>
  <tr class="listrow_color1">
    <td>Card Swipe Reader: Setup and Use (PDF)</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=CSR.pdf">Click Here</a></td> 
  </tr>

  <tr>
    <td class=\"listsection_title\" colspan="2"><i>VeriFone: <font color="red">***Please note that we no longer support VeriFone POS terminals</i></td>
  </tr>
<!--  <tr class="listrow_color0">
    <td>Manual (PDF)</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Verifone_Manual.pdf">Click Here</a></td>
  </tr>
  <tr class="listrow_color1">
    <td>Manual (HTML)</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Verifone_Manual_(Text_Version).html">Click Here</a></td>
  </tr>
<!--
  <tr class="listrow_color1">
    <td>SYS MODE MENU</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=SYS_MODE_MENU.html">Click Here</a></td>
  </tr>
-->
<!--  <tr class="listrow_color0">
    <td>Download Guide</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Download_Guide.html">Click Here</a></td>
  </tr>
  <tr class="listrow_color1">
    <td>Parameter Guide</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=Parameter_Guide.html">Click Here</a></td>
  </tr> -->

  <tr class="listrow_color0">
    <td>ePayments Mobile App</td>
    <td align="center"><a href="/admin/doc_replace.cgi?doc=ePayments_Mobile_App.htm">Click Here</a></td> 
  </tr>
EOF

print "</table>\n";
print "</div>\n";

&html_tail();
exit;

sub html_head {
  my ($title) = @_;

  print "<html>\n";
  print "<head>\n";
  print "<title>Online Documentation</title>\n";
  print "<link href=\"/css/style_faq.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  print "</head>\n";

  print "<body bgcolor=\"#ffffff\">\n";
  print "<table width=\"760\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\" id=\"header\">\n";
  print "  <tr>\n";
  print "    <td colspan=\"3\" align=\"left\">";
  if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
    print "<img src=\"/images/global_header_gfx.gif\" width=\"760\" alt=\"Plug 'n Pay Technologies - we make selling simple.\" height=\"44\" border=\"0\">";
  }
  else {
    print "<img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Logo\">\n";
  }

  print "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"3\" align=\"left\"><img src=\"/images/header_bottom_bar_gfx.gif\" width=\"760\" alt=\"plug \'n pay\"  height=\"14\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"3\" valign=\"top\" class=\"larger\"><h1><b><a href=\"$ENV{'SCRIPT_NAME'}\">Online Documentation</a>";
  if ($title ne "") {
    print " / $title";
  }
  print "</b></h1></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table border=\"0\" cellspacing=\"0\" cellpadding=\"0\" width=\"760\">\n";
  print "  <tr>\n";
  print "    <td colspan=\"3\" valign=\"top\" align=\"left\">\n";

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
  print "    <td align=\"left\">\n";
  print "      <p>";
  print "<a href=\"/admin/logout.cgi\" title=\"Click to log out\">Log Out</a> | <a href=\"javascript:change_win('/admin/helpdesk.cgi',600,500,'ahelpdesk')\">Help Desk</a> | <a id=\"close\" href=\"javascript:closewin();\" title=\"Click to close this window\">Close Window</a>";
  #print "<!--<a href=\"mailto:support\@plugnpay.com\">support\@plugnpay.com</a>-->";
  print "</p></td>\n";
  print "    <td align=\"right\">\n";
  print "      <p>\&copy; $copy_year ";
  if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
    print "Plug and Pay Technologies, Inc.";
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


