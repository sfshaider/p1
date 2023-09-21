#!/usr/local/bin/perl

package promoadminutils;
 
require 5.001;

use CGI;
use DBI;
use miscutils;

sub new {
  my $type = shift;

  $query = new CGI;

  $month = $query->param('month');
  $year = $query->param('year');
  $billingflag = $query->param('billing');
  $function = $query->param('function');
  $username = $ENV{'REMOTE_USER'};
  $dropdown = $query->param('dropdown');

  ($sec,$min,$hour,$mday,$mon,$yyear,$wday,$yday,$isdst) = gmtime(time());
  $time = sprintf("%02d%02d%02d%02d%02d%05d",$yyear+1900,$mon+1,$mday,$hour,$min,$sec);
  $dday = $mday;
  $mmonth = $mon + 1;
  $yyear = $yyear + 1900;

  $now = sprintf("%04d%02d%02d",$yyear,$mmonth,$dday);
  %month_array = (1,"Jan",2,"Feb",3,"Mar",4,"Apr",5,"May",6,"Jun",7,"Jul",8,"Aug",9,"Sep",10,"Oct",11,"Nov",12,"Dec");
  %month_array2 = ("Jan","01","Feb","02","Mar","03","Apr","04","May","05","Jun","06","Jul","07","Aug","08","Sep","09","Oct","10","Nov","11","Dec","12");
 
  $yearmonth = $year . $month_array2{$month};
  $month_due = sprintf("%02d", substr($yearmonth,4,2) + 2);
  $billdate = $yearmonth . "31";

  ($sec,$min,$hour,$mday,$mon,$yyear,$wday,$yday,$isdst) = gmtime(time()+(24*3600));
  $dday = $mday;
  $mmonth = $mon + 1;
  $yyear = $yyear + 1900;
  $tomorrow = sprintf("%04d%02d%02d",$yyear,$mmonth,$dday);

  $path_cgi = "promo_admin.cgi";

  $goodcolor = "#000000";
  $badcolor = "#ff0000";
  $backcolor = "#ffffff";
  $fontface = "Arial,Helvetica,Univers,Zurich BT";


  if (($ENV{'HTTP_COOKIE'} ne "")){
    (@cookies) = split('\;',$ENV{'HTTP_COOKIE'});
    foreach $var (@cookies) {
      $var =~ /(.*?)=(.*)/;
      ($name,$value) = ($1,$2);
      $name =~ s/ //g;
      $cookie{$name} = $value;
    }
  }

  $dbh = &miscutils::dbhconnect("merchantdata");
  $sth = $dbh->prepare(qq{
      select promocode
      from promo_offers
      where username=?
      order by promocode
      }) or die "Can't do: $DBI::errstr";
  $sth->execute($username) or die "Can't execute: $DBI::errstr";
  $rv = $sth->bind_columns(undef,\($promocode));
  while($sth->fetch) {
    @promolist = (@promolist,"$promocode");
  }
  $sth->finish;

  $dbh->disconnect();

  return [], $type;
}


sub head {
  $i = 0;
  print  "<html>\n";
  print  "<head>\n";
  print  "<title>PlugnPay/Coupon Administration Area</title>\n";
  print "<script Language=\"Javascript\">\n";
  print "//<!-- Start Script\n";
  print "function results() {\n";
  print "  resultsWindow = window.open(\"/payment/recurring/blank.html\",\"results\",\"menubar=no,status=no,scrollbars=yes,resizable=yes,width=400,height=300\");\n";
  print "}\n";

  print "function onlinehelp(subject) {\n";
  print "  helpURL = '/online_help/' + subject + '.html';\n";
  print "  helpWin = window.open(helpURL,\"helpWin\",\"menubar=no,status=no,scrollbars=yes,resizable=yes,width=350,height=350\"
);\n";
 
  print "}\n";

  print "//-->\n";
  print "</script>\n";

  print "<style type=\"text/css\">\n";
  print "<!--\n";
  print "th { font-family: $fontface; font-size: 70%; color: $goodcolor }\n";
  print "td { font-family: $fontface; font-size: 70%; color: $goodcolor }\n";
  print ".badcolor { color: $badcolor }\n";
  print ".goodcolor { color: $goodcolor }\n";
  print ".larger { font-size: 100% }\n";
  print ".smaller { font-size: 60% }\n";
  print ".short { font-size: 8% }\n";
  print ".button { font-size: 50% }\n";
  print ".itemscolor { background-color: $goodcolor; color: $backcolor }\n";
  print ".itemrows { background-color: #d0d0d0 }\n";
  print ".items { position: static }\n";
  print ".info { position: static }\n";
  print "-->\n";
  print "</style>\n\n";



  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";
  print "<table border=\"0\" cellspacing=\"0\" cellpadding=\"1\" width=\"500\">\n";
  print "<tr><td align=\"center\" colspan=\"3\"><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corporate Logo\"></td></tr>\n";
  print "<tr><td align=\"center\" colspan=\"3\" class=\"larger\" bgcolor=\"#000000\"><font color=\"#ffffff\">Promotional Offers Administration Area</font></td></tr>\n";
  print "<tr><td align=\"center\" colspan=\"3\"><img src=\"/images/icons.gif\" alt=\"PnP - The PowertoSell\"></td></tr>\n";
  print "<tr><td width=\"150\">&nbsp;</td><td width=\"75\">&nbsp;</td><td width=\"275\">&nbsp;</td></tr>\n";
}

sub addoffer {
  print "<tr><td bgcolor=\"#4a7394\">&nbsp;</td><td colspan=\"2\"><hr width=\"80%\"></td></tr>\n";
  print "<tr><th valign=\"top\" align=\"left\" bgcolor=\"#4a7394\" rowspan=\"2\">Add New Offer</th><th align=\"left\" class=\"smaller\">\n";
  print "<form method=\"post\" action=\"$path_cgi\" target=\"newWin\">\n";
  print "Promo. Code:</th><td class=\"smaller\"><input type=\"text\" name=\"promocode\" size=\"20\" maxlength=\"20\"></td></tr>\n";
  print "<tr><td colspan=\"2\" class=\"button\"><input type=\"hidden\" name=\"function\" value=\"add_offer\">\n";
  print "<input type=\"submit\" value=\"Add/Edit Offer\">\n";
  print "</form>\n";
  print "</td></tr>\n";
}

sub droplist {
  print "<tr><td bgcolor=\"#4a7394\">&nbsp;</td><td colspan=\"2\"><hr width=\"80%\"></td></tr>\n";
  print "<tr>\n";
  print "<th valign=\"top\" align=\"left\" bgcolor=\"#4a7394\" rowspan=\"2\">Promotional<br>Offer's</th><th align=\"left\" class=\"smaller\">\n";
  print "<form method=\"post\" action=\"$path_cgi\" target=\"newWin\">\n";
  print "Promo. Code:</th><td align=\"left\" class=\"smaller\">\n";
  print "<select name=\"promocode\">\n";
  foreach $offer (@promolist) {
    print "<option value=\"$offer\">$offer</option>\n";
  }
  print "</select></td></tr>\n";
  print "<tr><td colspan=\"2\" class=\"button\"><input type=\"hidden\" name=\"function\" value=\"view_offer\">\n";
  print "<input type=\"submit\" value=\"View/Edit Promotional Offers\"></form>\n";
  print "</td></tr>\n";
}

sub import_data {

  print "<tr><td bgcolor=\"#4a7394\">&nbsp;</td><td colspan=\"2\"><hr width=\"80%\"></td></tr>\n";
  print "<tr> <th valign=top align=left bgcolor=\"#4a7394\" rowspan=\"2\">Import Data</th>\n";
  print "<th align=\"left\" class=\"smaller\">\n";
  print "<form method=\"post\" enctype=\"multipart/form-data\" action=\"$path_cgi\" target=\"newWin\">\n";
  print "File:</th><td class=\"smaller\"><input type=\"file\" name=\"filename\"></td></tr>\n";
  print "<tr><td colspan=\"2\" align=\"left\" class=\"button\"><input type=\"hidden\" name=\"function\" value=\"import\">\n";
  print "<input type=\"submit\" value=\"Import Data List\">\n";
  print "</form>\n";
  print "</td>\n";
}

sub addsku {
  print "<tr><td bgcolor=\"#4a7394\">&nbsp;</td><td colspan=\"2\"><hr width=\"80%\"></td></tr>\n";
  print "<tr><th valign=\"top\" align=\"left\" bgcolor=\"#4a7394\" rowspan=\"2\">Add/Edit<br>Product List</th><th align=\"left\" class=\"smaller\">\n";
  print "<form method=\"post\" action=\"$path_cgi\" target=\"newWin\">\n";
  print "Sales SKU:</th><td class=\"smaller\"><input type=\"text\" name=\"sku\" size=\"20\" maxlength=\"20\"></td></tr>\n";
  print "<tr><td colspan=\"2\" class=\"button\"><input type=\"hidden\" name=\"function\" value=\"add_sku\">\n";
  print "<input type=\"submit\" value=\"Add/Edit Product\">\n";
  print "</form>\n";
  print "</td></tr>\n";
}


sub helpdesk {
  print  "<tr><td bgcolor=\"#ffffff\">&nbsp;</td><td><hr width=\"80%\"></td></tr>\n";
  print  "<tr bgcolor=\"#4a7394\"><th colspan=\"2\" align=\"left\">Help</th></tr>\n";
  print  "<tr><th valign=\"top\" align=\"left\" bgcolor=\"#c080c0\">Help Desk</th>\n";
  print  "<td class=\"smaller\"><form method=\"post\" action=\"helpdesk.cgi\" target=\"ahelpdesk\">\n";
  print  "<input type=\"submit\" name=\"submit\" value=\"Help Desk\" onClick=\"window.open(\'\',\'ahelpdesk\',\'width=550,height=520,toolbar=no,location=no,directories=no,status=no,menubar=no,scrollbars=yes,resizable=yes\'); return(true);\">\n";
  print  "</form>\n";
  print  "</td></tr>\n";
}

sub documentation {
  print "<tr><td bgcolor=\"#4a7394\">&nbsp;</td><td colspan=\"2\"><hr width=\"80%\"></td></tr>\n";
  print "<tr><th valign=\"top\" align=\"left\" bgcolor=\"#4a7394\">Help</th>\n";
  print "<td align=\"left\"><a href=\"javascript:onlinehelp('promooffer');\">Documentation</a></td></tr>\n";
}


sub tail {
  print "</table>\n";
  print "</body>\n";
  print "</html>\n";
}

