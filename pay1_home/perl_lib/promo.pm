package promo;
 
use CGI;
use DBI;
use miscutils;
use rsautils;
use PlugNPay::GatewayAccount;
#use strict;

sub new {
  my $type = shift;
#  my (%data);
  $query = new CGI;
  my @params = $query->param;
  foreach $param (@params) {
    $data{$param} = $query->param($param);
print "$param:$data{$param}:<br>\n";
  }
  $data{'username'} = $ENV{"REMOTE_USER"};
  $promo::username = $data{'username'};

  $data{'expires'} = $data{'startyear'} . $data{'startmon'} . $data{'startday'};
  $data{'minpurchase'} =~ s/0-9\.//g;

  $goodcolor = "#000000";
  $badcolor = "#ff0000";
  $backcolor = "#ffffff";
  $fontface = "Arial,Helvetica,Univers,Zurich BT";

  &auth(%data);

  %promo::data = %data;

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


  print "function postoffer() {\n";
  print "  document.addoffer.target = '';\n";
  print "  document.addoffer.action = 'promo_admin.cgi';\n";
  print "  document.addoffer.submit();\n";
  print "}\n";

  print "function editsku() {\n";
  print "  document.addoffer.sku.value = document.addoffer.skulist.options[document.addoffer.skulist.selectedIndex].value;\n";
  print "}\n";


  print "// end script-->\n";
  print "</script>\n";


  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";

  print "<table border=\"0\" cellspacing=\"1\" cellpadding=\"0\" width=\"600\">\n";
  print "<tr><td align=\"center\" colspan=\"3\"><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corporate Logo\"></td></tr>\n";
  print "<tr><td align=\"center\" colspan=\"3\" bgcolor=\"#000000\" class=\"larger\"><font color=\"#ffffff\">Promotional Offers Module Administration Area</font></td></tr>\n";
  print "<tr><td align=\"center\" colspan=\"3\"><img src=\"/images/icons.gif\" alt=\"The PowertoSell\"></td></tr>\n";
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

sub auth {
  my (%data) = @_;
  my $gatewayAccount = new PlugNPay::GatewayAccount($data{'username'});
  if ($gatewayAccount->getStatus() eq 'cancelled') {
    &response_page('Your account is closed. Reason: ' . $gatewayAccount->getStatusReason() . "<br>\n");
  }
}

sub add_offer {
  #print "Content-Type: text/html\n\n";
  $dbh = &miscutils::dbhconnect("merchantdata");
  my $sth = $dbh->prepare(qq{
          select promocode,discount,disctype,usetype,minpurchase,sku,expires,status
          from promo_offers
          where username=? and promocode=?
          order by promocode
          }) or die "Can't do: $DBI::errstr";
  $sth->execute($promo::username,$data{'promocode'}) or die "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($db{'promocode'},$db{'discount'},$db{'disctype'},$db{'usetype'},$db{'minpurchase'},$db{'sku'},$db{'expires'},$db{'status'}));
  while ($sth->fetch) {
    @promolist = (@promolist,$db{'promocode'});
  }
  $sth->finish;

print "$db{'promocode'},$db{'discount'},$db{'disctype'},$db{'usetype'},$db{'minpurchase'},$db{'sku'},$db{'expires'},$db{'status'}\n";

  my $sth = $dbh->prepare(qq{
          select sku,cost,description,category
          from products
          where username=?
          order by sku
          }) or die "Can't do: $DBI::errstr";
  $sth->execute($promo::username) or die "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($db1{'sku'},$db1{'cost'},$db1{'description'},$db1{'category'}));
  while ($sth->fetch) {
    $product = $db1{'sku'};
    @prodlist = (@prodlist,$product);
    $$product{'cost'} = $db1{'cost'};
    $$product{'description'} = $db1{'description'};
    $$product{'category'} = $db1{'category'};
  }
  $sth->finish;
  $dbh->disconnect;



  if($db{'usetype'} eq "") {
    $db{'usetype'} = "unlimited";
  }
  if($db{'disctype'} eq "") {
    $db{'disctype'} = "percent";
  }
  if($db{'startday'} eq "") {
    $db{'startday'} = "01";
  }
  if($db{'startmon'} eq "") {
    $db{'startmon'} = "01";
  }
  if($db{'startyear'} eq "") {
    $db{'startyear'} = "2010";
  }
  $selected{$db{'startday'}} = " selected";
  $selected{$db{'startmon'}} = " selected";
  $selected{$db{'startyear'}} = " selected";
  $selected{$db{'usetype'}} = " checked";
  $selected{$db{'disctype'}} = " checked";
  $selected{$db{'status'}} = " checked";

  &report_head();

  print "<font size=\"3\">Create Promo Offer</font>\n";
  print "<form name=\"addoffer\" method=post action=\"promo_admin.cgi\" target=\"\">\n";
  print "<table border=\"1\">\n";
  print "<tr><th align=\"right\">Help:</th><td align=\"left\"><a href=\"javascript:onlinehelp('addoffer');\">Documentation</a></td></tr>\n";
  print "<tr><th align=\"right\">PromoCode:</th><td align=\"left\">$data{'promocode'} <input type=\"hidden\" name=\"promocode\" value=\"$data{'promocode'}\">\n";

  print "<tr><th align=\"right\">Sales SKU:</th><td align=\"left\"><input type=\"text\" name=\"sku\" value=\"$db{'sku'}\" size=\"12\" maxlength=\"12\"> \n";
  print " <select name=\"skulist\" onChange=\"editsku();\">\n";
  $selected{$db{'sku'}} = " selected";
  foreach $sku (@prodlist) {
    print "<option value=\"$sku\" $selected{$sku}>$sku</option>\n";
  }
  print "</select> You may use '*' for partial matches or leave blank for any SKU. </td></tr>\n";

#  print "<tr><th align=\"right\">PromoCode:</th><td align=\"left\">$data{'promocode'} <input type=\"hidden\" name=\"promocode\" value=\"$data{'promocode'}\">\n";
  #print " <select name=\"promocode\">\n";
  #$selected{$data{'promocode'}} = " selected"; 
  #foreach $promocode (@promolist) {
  #  print "<option value=\"$promocode\" $selected{$promocode}>$promocode</option>\n";
  #}
  #print "</select>\n";
  #print "</td></tr>\n";

  print "<tr><th align=\"right\">Discount:</th><td align=\"left\"><input type=\"text\" name=\"discount\" size=\"6\" value=\"$db{'discount'}\"> In Decimal Format, i.e. enter 0.30 for a 30 percent discount or 10.00 for a 10 dollar discount.</td></tr>\n";
  print "<tr><th align=\"right\">Discount Type:</th><td align=\"left\"><input type=\"radio\" name=\"disctype\" value=\"percent\" $selected{'percent'}> Percent \n";
  print "<input type=\"radio\" name=\"disctype\" value=\"dollar\" $selected{'dollar'}> Dollars</td></tr>\n";

  print "<tr><th align=\"right\">Allowed Use:</th><td align=\"left\"><input type=\"radio\" name=\"usetype\" value=\"unlimited\" $selected{'unlimited'}> Unlimited \n";
  print "<input type=\"radio\" name=\"usetype\" value=\"onetime\" $selected{'onetime'}> Onetime</td></tr>\n";

  print "<tr><th align=\"right\">Min. Purchase:</th><td align=\"left\"><input type=\"text\" name=\"minpurchase\" size=\"6\" value=\"$db{'minpurchase'}\"> No \$ signs please.</td></tr>\n";

  print "<tr><th align=\"right\">Status:</th><td align=\"left\"><input type=\"radio\" name=\"status\" value=\"active\" $selected{'active'}> Active \n";
  print "<input type=\"radio\" name=\"status\" value=\"inactive\" $selected{'inactive'}> Inactive</td></tr>\n";


  print "<tr><th align=\"left\" bgcolor=\"#ffffff\"><font color=\"#000000\">Expiration Date:</font></th><td>\n";

  print "<select name=\"startmon\">\n";
  @months = ("01","02","03","04","05","06","07","08","09","10","11","12");
  foreach $var (@months) {
    print "<option value=\"$var\" $selected{$var}>$var</option>\n";
  }
  print "</select> ";
  print "<select name=\"startday\">\n";
  @days = ("01","02","03","04","05","06","07","08","09","10","11","12","13","14","15","16","17","18","19","20","21","22","23","24","25","26","27","28","29","30","31");
  foreach $var (@days) {
    print "<option value=\"$var\" $selected{$var}>$var</option>\n";
  }
  print "</select> ";
  print "<select name=\"startyear\">\n";
  @years = ("2000","2001","2002","2003","2004","2005","2006","2007","2008","2009","2010");
  foreach $var (@years) {
    print "<option value=\"$var\" $selected{$var}>$var</option>\n";
  }
  print "</select>\n";
  print "</td></tr>\n";


  print "<tr><td colspan=\"2\" align=\"center\">";
  print "<input type=\"hidden\" name=\"function\" value=\"update_offer\">";
  print "<input type=\"button\" value=\"Submit Form\" onClick=\"postoffer();\"> <input type=\"reset\" value=\"Reset Form\">\n";
  print "</td></tr></table>\n";
  print "</form><p>\n";
  &report_tail();

}

sub view_offer {
  $dbh = &miscutils::dbhconnect("merchantdata");
  my $sth = $dbh->prepare(qq{
          select discount,disctype,usetype,minpurchase,sku,expires,status
          from promo_offers
          where username=? and promocode=?
          }) or die "Can't do: $DBI::errstr";
  $sth->execute($promo::username,$data{'promocode'}) or die "Can't execute: $DBI::errstr";
  ($db{'discount'},$db{'disctype'},$db{'usetype'},$db{'minpurchase'},$db{'sku'},$db{'expires'},$db{'status'}) = $sth->fetchrow;
  $sth->finish;
  $dbh->disconnect;
  $db{'promocode'} = $data{'promocode'};

  &report_head();

  print "<font size=\"+1\">View Offer</font>\n";
  print "<table border=1>\n";

  @array = ();
  @array = %db;

  &write_offer_entry(@array);

  print "</table><p>\n";
  &report_tail();
}


sub write_offer_entry {
  my (%data) = @_;
  print "<tr>\n";
  print "<td colspan=1 class=\"smaller\"><form method=post action=\"promo_admin.cgi\" target=\"newWin\">\n";
  print "<b>Promo Code:</b>$data{'promocode'}<input type=\"hidden\" name=\"promocode\" value=\"$data{'promocode'}\"></td>\n";
  print "<td>Status: $data{'status'}<input type=\"hidden\" name=\"cost\" value=\"$data{'cost'}\"></td>\n";
  print "<td>Exp. Date: $data{'expires'}<input type=\"hidden\" name=\"expires\" value=\"$data{'expires'}\"></td></tr>\n";
  print "<tr><td colspan=\"1\">Discount: $data{'discount'}<input type=\"hidden\" name=\"discount\" value=\"$data{'discount'}\"></td>\n";
  print "<td colspan=\"1\">Disc. Type: $data{'disctype'}<input type=\"hidden\" name=\"disctype\" value=\"$data{'disctype'}\"></td>\n";
  print "<td colspan=\"1\">Use Type: $data{'usetype'}<input type=\"hidden\" name=\"usetype\" value=\"$data{'usetype'}\"></td></tr>\n";

  print "<tr><td colspan=\"1\">Min. Purchase: $data{'minpurchase'}<input type=\"hidden\" name=\"minpurchase\" value=\"$data{'minpurchase'}\"></td>\n";
  print "<td colspan=\"1\">SKU:<br>$data{'sku'}<input type=\"hidden\" name=\"sku\" value=\"$data{'sku'}\"></td></tr>\n";

  print "<tr><td><input type=\"radio\" name=\"function\" value=\"edit_offer\" checked> Edit Offer</font><br>\n";
  print " <input type=\"radio\" name=\"function\" value=\"delete_offer\"> Delete Offer</font></td>\n";
  print "<td align=\"center\" rowspan=2 colspan=1><input type=\"submit\" value=\"Submit Request\"></form></td></tr>\n";
  print "<tr bgcolor=\"#80c0c0\"><td colspan=\"2\" class=\"divider\"><hr width=\"75%\" height=\"3\"></td>\n";
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

sub remove_offer {
  print "UN:$promo::username:$data{'promocode'}\n";
  my $dbh = &miscutils::dbhconnect("merchantdata");
  my $sth = $dbh->prepare(qq{
       delete from promo_offers where username=? and promocode=? 
        }) or die "Can't prepare: $DBI::errstr";
  $sth->execute($promo::username,$data{'promocode'}) or die "Can't execute: $DBI::errstr";
  $sth->finish;
  $dbh->disconnect;
  &response_page("Promotional Offer $data{'promocode'} has been removed from the database.");
}

sub import_data {
#  my $filename = $data{'upload-file'};
  $filename = $query->param('filename');
  my (@fields);
  while(<$filename>) {
    chop;
    my (@data) = split('\t');
    if (substr($data[0],0,1) eq "\!") {
      $parseflag = 1;
      (@fields) = (@data);
      $fields[0] = substr($data[0],1);
      print "FF0:$fields[0]:$fields[1]:$fields[2]:$fields[3]:$fields[4]:<br>\n"; 
      next;
    }
    if ($parseflag == 1) {
      $i = 0;
      foreach $var (@fields) {
      $var =~ tr/A-Z/a-z/;
      #  print "$var:$data[$i], ";
        $data{$var} = $data[$i];
        $i++;
      }
      if ($fields[0] eq "prod") {
        &insert_sku(%data);
      }
      if ($fields[0] eq "promo") {
        &insert_offer(%data);
      }
    }
  }
  if ($parseflag == 1) {
    my $message = "File Has Been Uploaded and Imported into Database";
    &response_page($message);
  }
  else {
    my $message = "Sorry Improper File Format";
    &response_page($message);
  }
}

sub insert_offer {
  my ($test);
  if ($data{'promocode'} ne "") {
    my $dbh = &miscutils::dbhconnect("merchantdata");
    my $sth = $dbh->prepare(qq{
        select promocode
        from promo_offers
        where username=? and promocode=? 
        }) or die "Can't do: $DBI::errstr";
    $sth->execute ($promo::username,$data{'promocode'}) or die "Can't execute: $DBI::errstr";
    $sth->bind_columns(undef,\($test));
    $sth->fetch;
    $sth->finish;

    if ($test ne "") {
      $sth = $dbh->prepare(qq{
          update promo_offers set discount=?,disctype=?,usetype=?,status=?,minpurchase=?,sku=?,expires=?
          where username=? and promocode=? 
          }) or die "Can't prepare: $DBI::errstr";
      $sth->execute($data{'discount'},$data{'disctype'},$data{'usetype'},$data{'status'},$data{'minpurchase'},$data{'sku'},$data{'expires'},$promo::username,$data{'promocode'}) or die "Can't execute: $DBI::errstr";
      $sth->finish;
    }
    else {
      $sth = $dbh->prepare(qq{
          insert into promo_offers
           (username,promocode,discount,disctype,usetype,status,minpurchase,sku,expires)
          values (?,?,?,?,?,?,?,?,?)
        }  ) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$promo::username",$data{'promocode'},$data{'discount'},$data{'disctype'},$data{'usetype'},$data{'status'},$data{'minpurchase'},$data{'sku'},$data{'expires'}) or die "Can't execute: $DBI::errstr";
      $sth->finish;
    }
    $dbh->disconnect;
  }
}

sub insert_sku {
  my ($test);
  if ($data{'sku'} ne "") {
    my $dbh = &miscutils::dbhconnect("merchantdata");
    my $sth = $dbh->prepare(qq{
        select sku
        from products
        where username=? and sku=?
        }) or die "Can't do: $DBI::errstr";
    $sth->execute ($upsell::username,$data{'sku'}) or die "Can't execute: $DBI::errstr";
    $sth->bind_columns(undef,\($test));
    $sth->fetch;
    $sth->finish;
#print "$upsell::username,$data{'sku'},$data{'sku'},$data{'cost'},$data{'description'}<br>\n";

    $data{'sku'} = substr($data{'sku'},0,24);
    $data{'cost'} = substr($data{'cost'},0,10);
    $data{'description'} = substr($data{'description'},0,24);
    $data{'category'} = substr($data{'category'},0,39);

    if ($test ne "") {
      $sth = $dbh->prepare(qq{
          update products set cost=?,description=?,category=?
          where username=? and sku=?
          }) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$data{'cost'}","$data{'description'}","$data{'category'}",$upsell::username,$data{'sku'}) or die "Can't execute: $DBI::errstr";
      $sth->finish;
    }
    else {
      $sth = $dbh->prepare(qq{
          insert into products
           (username,sku,cost,description,category)
          values (?,?,?,?,?)
        }  ) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$upsell::username","$data{'sku'}","$data{'cost'}","$data{'description'}","$data{'category'}") or die "Can't execute: $DBI::errstr";
      $sth->finish;
    }
    $dbh->disconnect;
  }
}

1;
