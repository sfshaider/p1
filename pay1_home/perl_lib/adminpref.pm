#!/usr/local/bin/perl

require 5.001;
#$|=1;

package adminpref;
 
use CGI;
use DBI;
use miscutils;
use rsautils;
#use strict;

sub new {
  my $type = shift;

  $data = new CGI;
  my @params = $data->param;
  foreach $param (@params) {
    $query{$param} = $data->param($param);
  }

  $username = $ENV{"REMOTE_USER"};

  $goodcolor = "#000000";
  $badcolor = "#ff0000";
  $backcolor = "#ffffff";
  $fontface = "Arial,Helvetica,Univers,Zurich BT";

  &auth($username);

  if (($ENV{'HTTP_COOKIE'} ne "")){
    (@cookies) = split('\;',$ENV{'HTTP_COOKIE'});
    foreach $var (@cookies) {
      $var =~ /(.*?)=(.*)/;
      ($name,$value) = ($1,$2);
      $name =~ s/ //g;
      $cookie{$name} = $value;
    }
  }
  return [], $type;
}

sub report_head {
  print "Content-Type: text/html\n\n";
  print "<html>\n";
  print "<body>\n";
  print "<title>Edit Items</title>\n";
  print "<style type=\"text/css\">\n";
  print "<!--\n";
  print "th { font-family: $fontface; font-size: 70%; color: $goodcolor }\n";
  print "td { font-family: $fontface; font-size: 70%; color: $goodcolor }\n";
  print ".badcolor { color: $badcolor }\n";
  print ".goodcolor { color: $goodcolor }\n";
  print ".larger { font-size: 100% }\n";
  print ".smaller { font-size: 60% }\n";
  print ".short { font-size: 8% }\n";
  print ".itemscolor { background-color: $goodcolor; color: $backcolor }\n";
  print ".itemrows { background-color: #d0d0d0 }\n";
  print ".divider { background-color: #4a7394 }\n";
  print ".items { position: static }\n";
  print ".info { position: static }\n";
  print "-->\n";
  print "</style>\n";

  print "<script Language=\"Javascript\">\n";
  print "<!-- // Begin Script \n";

  print "function results() {\n";
  print "  resultsWindow = window.open(\"/payment/recurring/blank.html\",\"results\",\"menubar=no,status=no,scrollbars=yes,resizable=yes,width=350,height=350\");\n";
  print "}\n";

  print "function onlinehelp(subject) {\n";
  print "  helpURL = '/online_help/' + subject + '.html';\n";
  print "  helpWin = window.open(helpURL,\"helpWin\",\"menubar=no,status=no,scrollbars=yes,resizable=yes,width=350,height=350\");\n";
  print "}\n";

  print "// end script-->\n";
  print "</script>\n";


  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";

  print "<table border=\"0\" cellspacing=\"1\" cellpadding=\"0\" width=\"600\">\n";
  print "<tr><td align=\"center\" colspan=\"3\"><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corporate Logo\"></td></tr>\n";
  print "<tr><td align=\"center\" colspan=\"3\" bgcolor=\"#000000\" class=\"larger\"><font color=\"#ffffff\">Account Preferences</font></td></tr>\n";
  print "<tr><td align=\"center\" colspan=\"3\"><img src=\"/images/icons.gif\" alt=\"Cute Icons\"></td></tr>\n";
  print "<tr><td align=\"center\" colspan=\"3\">&nbsp;</td></tr>\n";
  print "<tr><td align=\"center\" colspan=\"3\">\n";
}

sub report_tail {
  print "</td></tr>\n";
  print "<tr><td colspan=\"3\" align=\"center\"><form action=\"index.cgi\">\n";
  print "<input type=\"submit\" value=\"Return To Main Administration Page\">\n";
  print "</form></td></tr>\n";
  print "</table>\n";
  print "</body>\n";
  print "</html>\n";

}

sub main {
  &report_head();
  %selected = {};
  $selected{$autobatch} = " selected";
  print "<table>\n";
  print "<tr>\n";
  print "<th align=\"left\" bgcolor=\"#4a7394\"><font color=\"#ffffff\">Auto Batching</font><form method=\"post\" action=\"$path_cgi\"></th>";
  print "<td><select name=\"autobatch\">";
  print "<option value=\"\">No autobatch</option>";
  print "<option value=\"0\"$selected{'0'}>Same Day</option>";
  print "<option value=\"1\"$selected{'1'}>Next Day</option>";
  print "<option value=\"2\"$selected{'2'}>2 Days</option>";
  print "<option value=\"3\"$selected{'3'}>3 Days</option>";
  print "<option value=\"4\"$selected{'4'}>4 Days</option>";
  print "<option value=\"5\"$selected{'5'}>5 Days</option>";
  print "<option value=\"6\"$selected{'6'}>6 Days</option>";
  print "<option value=\"7\"$selected{'7'}>7 Days</option>";
  print "<option value=\"14\"$selected{'14'}>14 Days</option>";
  print "</select> Delay</td>";
  print "</tr>\n";
  print "<tr><td> &nbsp; </td><td><input type=\"submit\" value=\"Submit\"></form></td></tr>\n";
  print "</table>\n";
  &report_tail();
}


sub readpref {
  $dbh = &miscutils::dbhconnect("pnpdata");
  $sth_merchants = $dbh->prepare(qq{
      select autobatch,ach
      from pnpsetups
      where username=?
      }) or die "Can't prepare: $DBI::errstr";
  $sth_merchants->execute($autobatch,$ach,"$username") or die "Can't execute: $DBI::errstr";
  $sth_merchants->finish;
  $dbh->disconnect;

}

sub updatepref {
  $dbh = &miscutils::dbhconnect("pnpdata");
  $sth_merchants = $dbh->prepare(qq{
      update pnpsetups set autobatch=?,ach=?
      where username='$username'
      }) or die "Can't prepare: $DBI::errstr";
  $sth_merchants->execute($autobatch,$ach) or die "Can't execute: $DBI::errstr";
  $sth_merchants->finish;
  $dbh->disconnect;
  my $message = "Your account preferences have been updated.";
  &response_page($message);
  exit;
}


sub auth {
  my ($username) = @_;
  $dbh_auth = &miscutils::dbhconnect("pnpdata");
  my $sth_cust = $dbh_auth->prepare(qq{
          select status,reason
          from customers
          where username=?
          }) or die "Can't do: $DBI::errstr";
  $sth_cust->execute("$username") or die "Can't execute: $DBI::errstr";
  my ($custstatus,$custreason) = $sth_cust->fetchrow;
  $sth_cust->finish;
  $dbh_auth->disconnect;
  if ($custstatus eq "cancelled") {
    my $message = "Your account is closed. Reason: $custreason<br>\n";
    &response_page($message);
  }
}

sub add_profile {
  #print "Content-Type: text/html\n\n";
  $dbh = &miscutils::dbhconnect("pnpdata");
  my $sth = $dbh->prepare(qq{
          select naics,description
          from customers
          where username=? 
          }) or die "Can't do: $DBI::errstr";
  $sth->execute($xsell::username) or die "Can't execute: $DBI::errstr";
  ($db{'naics'},$db{'description'}) = $sth->fetchrow;;
  $sth->finish;
  $dbh->disconnect();

#print "$db{'naics'},$db{'description'}\n";

  $dbh = &miscutils::dbhconnect("merchantdata");
  my $sth = $dbh->prepare(qq{
          select description
          from naics
          where naics=?
          }) or die "Can't do: $DBI::errstr";
  $sth->execute($db{'naics'}) or die "Can't execute: $DBI::errstr";
  ($db1{'description'}) = $sth->fetchrow;
  $sth->finish;
  $dbh->disconnect;

  &report_head();

  print "<font size=\"3\">Edit Company Profile</font>\n";
  print "<form name=\"editprofile\" method=\"post\" action=\"xsell_admin.cgi\" target=\"\">\n";
  print "<table border=\"1\">\n";
  print "<tr><th align=\"right\">Help:</th><td align=\"left\"><a href=\"javascript:onlinehelp('addoffer');\">Documentation</a></td></tr>\n";
  print "<tr><th align=\"right\">NAICS Help:</th><td align=\"left\"><a href=\"http://www.census.gov/epcd/www/naics.html\" target=\"naicsWin\">What is a NAICS Code ?</a></td></tr>\n";
  print "<tr><th align=\"right\">NAICS Code:</th><td align=\"left\"><input type=\"text\" size=\"6\" name=\"naics\" value=\"$db{'naics'}\"> <a href=\"javascript:lookup_naics();\" alt=\"Look Up NAICS Code\">Look-Up NAICS Code</a> \n";
  print "<br>$db1{'description'}</td></tr>\n";

  print "<tr><th align=\"right\">Company Description:</th><td><textarea name=\"description\" cols=\"40\" rows=\"10\">$db{'description'}</textarea></td></tr>\n";
  print "<tr><td colspan=\"2\" align=\"center\">";
  print "<input type=\"hidden\" name=\"function\" value=\"update_profile\">";
  print "<input type=\"button\" value=\"Submit Form\" onClick=\"update_profile();\"> <input type=\"reset\" value=\"Reset Form\">\n";
  print "</td></tr></table>\n";
  print "</form><p>\n";
  &report_tail();
}

sub add_sku {
  #print "Content-Type: text/html\n\n";
  $dbh = &miscutils::dbhconnect("merchantdata");
  my $sth = $dbh->prepare(qq{
          select sku,cost,description,category
          from products
          where username=?
          order by sku
          }) or die "Can't do: $DBI::errstr";
  $sth->execute($xsell::username) or die "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($db{'sku'},$db{'cost'},$db{'description'},$db{'category'}));
  while ($sth->fetch) {
    $product = $db{'sku'};
    @prodlist = (@prodlist,$product);
    $$product{'cost'} = $db{'cost'};
    $$product{'description'} = $db{'description'};
    $$product{'category'} = $db{'category'};
  }
  $sth->finish;
  $dbh->disconnect;

  &report_head();

  print "<font size=\"+1\">Add/Edit Product</font>\n";
  print "<form name=\"addsku\" method=post action=\"xsell_admin.cgi\" target=\"\">\n";
  print "<table>\n";
  if ($data{'sku'} ne "") {
    print "<tr><th align=\"right\">Sales SKU:</th><td align=\"left\">$data{'sku'} <input type=\"hidden\" name=\"sku\" value=\"$data{'sku'}\"></td></tr>\n";
  }
  else {
    print "<tr><th><align=\"left\" font color=\"#000000\">Sales SKU:</th><td> <select name=\"sku\">\n";
    foreach $sku (@produlist) {
      print "<option value=\"$sku\">$sku</option>\n";
    }
    print "</td></tr>\n";
  }
  print "<tr><th align=\"right\">Cost:</th><td align=\"left\"><input type=\"text\" name=\"cost\" size=\"6\" value=\"$$data{'sku'}{'cost'}\"></td></tr>\n";

  print "<tr><th align=\"right\">Description:</th><td align=\"left\"><input type=\"text\" name=\"description\" size=\"39\" maxlength=\"39\" value=\"$$data{'sku'}{'description'}\"></td></tr>\n";

  print "<tr><th align=\"right\">Category:</th><td align=\"left\"><input type=\"text\" name=\"catergory\" size=\"39\" value=\"$$data{'sku'}{'category'}\"></td></tr>\n";

  print "<tr><td colspan=\"2\" align=\"center\"><input type=\"hidden\" name=\"function\" value=\"update_sku\">";
  print "<input type=\"submit\" value=\"Send Info\"> <input type=\"reset\" value=\"Reset Form\">\n";
  print "</td></tr></table>\n";
  print "</form><p>\n";

  &report_tail();
}


sub response_page {
  my ($message) = @_;
  print "Content-Type: text/html\n\n";
  print "<HTML>\n";
  print "<HEAD>\n";
  print "<TITLE>PlugnPay System Response</TITLE> \n";
  print "<style type=\"text/css\">\n";
  print "<!--\n";
  print "th { font-family: $fontface; font-size: 70%; color: $goodcolor }\n";
  print "td { font-family: $fontface; font-size: 70%; color: $goodcolor }\n";
  print ".badcolor { color: $badcolor }\n";
  print ".goodcolor { color: $goodcolor }\n";
  print ".larger { font-size: 100% }\n";
  print ".smaller { font-size: 60% }\n";
  print ".short { font-size: 8% }\n";
  print ".itemscolor { background-color: $goodcolor; color: $backcolor }\n";
  print ".itemrows { background-color: #d0d0d0 }\n";
  print ".items { position: static }\n";
  print ".info { position: static }\n";
  print "-->\n";
  print "</style>\n";

  print "<script Language=\"Javascript\">\n";
  print "<\!-- Start Script\n";
  print "function closeresults\(\) \{\n";
  print "  resultsWindow = window.close(\"results\")\;\n";
  print "\}\n";
  print "// end script-->\n";
  print "</script>\n";
  print "</HEAD>\n";
  print "<BODY BGCOLOR=#FFFFFF>\n";
  print "<div align=center><p>\n";
  print "<font size=+1>$message</font><p>\n";
  print "<p>\n";
  print "<form><input type=button value=\"Close\" onClick=\"closeresults();\"></form>\n";
  print "</div>\n";
  print "</BODY>\n";
  print "</HTML>\n";
}



1;
