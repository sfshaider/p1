package xsell;
 
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
#print "$param:$data{$param}:<br>\n";
  }
  $data{'username'} = $ENV{"REMOTE_USER"};
  $xsell::username = $data{'username'};

  $goodcolor = "#000000";
  $badcolor = "#ff0000";
  $backcolor = "#ffffff";
  $fontface = "Arial,Helvetica,Univers,Zurich BT";

  &auth(%data);

  %xsell::data = %data;

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

  print "function lookup_naics() {\n";
  print "  naicsWin = window.open(\"/admin/xsell/lookup_naics.cgi\",\"naicsWin\",\"menubar=no,status=no,scrollbars=yes,resizable=yes,width=500,height=400\");\n";
  print "}\n";

  print "function update_profile() {\n";
  print "  if ((document.editprofile.naics.value != '') && (document.editprofile.description.value != '')) {\n";
  print "  document.editprofile.submit();\n";
  print "  } else {\n";
  print "    window.alert('Please complete both fields.');\n";
  print "  }\n";
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
  print "<tr><td align=\"center\" colspan=\"3\" bgcolor=\"#000000\" class=\"larger\"><font color=\"#ffffff\">Power2Sell Administration Area</font></td></tr>\n";
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

sub add_profile {
  my $gatewayAccount = new PlugNPay::GatewayAccount($xsell::username);
  $db{'naics'} = $gatewayAccount->getNAICS();
  $db{'description'} = $gatewayAccount->getDescription();

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
      foreach $var (@fields) {
        $var =~ s/[^a-zA-Z0-9]//g;
        $fields[$i] = $var;
        $i++;
      }
      print "FF0:$fields[0]:$fields[1]:$fields[2]:$fields[3]:$fields[4]:<br>\n"; 
      next;
    }
    if ($parseflag == 1) {
      $i = 0;
      foreach $var (@fields) {
        $var =~ tr/A-Z/a-z/;
      #  print "$var:$data[$i], ";
        $data{$var} = $data[$i];
        #$data{$var} =~ /\"?(.*?)\"?/;
        #$data{$var} = $1;
        $i++;
      }
      my @array = %data;
      if ($fields[0] eq "prod") {
        &insert_sku(@array);
      }
      if ($fields[0] eq "naics") {
        &insert_naics(@array);
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

sub insert_sku {
  my (%data) = @_;
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

sub insert_profile {
  my (%data) = @_;
  if (($data{'naics'} ne "") && ($data{'description'} ne "")) {
    my $gatewayAccount = new PlugNPay::GatewayAccount($xsell::username);
    $gatewayAccount->setNAICS($data{'naics'});
    $gatewayAccount->setDescription($data{'description'});
  }
}

sub insert_naics {
  my (%data) = @_;
  print "NAICS:$data{'naics'},DESC:$data{'description'}<br>\n";
  my ($test);
  if ($data{'naics'} ne "") {
    my $dbh = &miscutils::dbhconnect("merchantdata");
    my $sth = $dbh->prepare(qq{
        select naics
        from naics
        where naics=? 
        }) or die "Can't do: $DBI::errstr";
    $sth->execute ($data{'naics'}) or die "Can't execute: $DBI::errstr";
    $sth->bind_columns(undef,\($test));
    $sth->fetch;
    $sth->finish;

    $data{'naics'} = substr($data{'naics'},0,9);
    $data{'description'} = substr($data{'description'},0,45);

    if ($test ne "") {
      $sth = $dbh->prepare(qq{
          update naics set description=?
          where naics=?
          }) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$data{'description'}","$data{'naics'}") or die "Can't execute: $DBI::errstr";
      $sth->finish;
    }
    else {
      $sth = $dbh->prepare(qq{
          insert into naics
           (naics,description)
          values (?,?)
        }  ) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$data{'naics'}","$data{'description'}") or die "Can't execute: $DBI::errstr";
      $sth->finish;
    }
    $dbh->disconnect;
  }
}

1;
