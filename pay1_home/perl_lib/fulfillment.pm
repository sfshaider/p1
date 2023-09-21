package fulfillment;

use PlugNPay::Transaction::TransactionProcessor;
use miscutils;
use CGI;
use strict;

sub new {
  my $type = shift;
  $fulfillment::query = new CGI;

  $fulfillment::error = 0;

  $fulfillment::path_main_cgi = 'index.cgi';

  my @deletelist;

  my @params = $fulfillment::query->param;
  $fulfillment::function = $fulfillment::query->param('function');
  foreach my $param (@params) {
    if (($param =~ /^delete_(.*)/) && ($fulfillment::function eq 'delete_product')) {
      push(@deletelist, "$1");
    }
  }

  $fulfillment::goodcolor = '#000000';
  $fulfillment::badcolor = '#ff0000';

  $fulfillment::dbh = &miscutils::dbhconnect('merch_info');

  if (@deletelist > 0) {
    &delete_product(@deletelist);
  }

  &auth($ENV{'REMOTE_USER'}, $ENV{'SUBACCT'});

  return [], $type;
}

sub response_page {

  my ($message,$close) = @_;
  my $autoclose = '';

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Response Page</title>\n";
  print "<meta http-equiv=\"CACHE-CONTROL\" content=\"NO-CACHE\">\n";
  print "<meta http-equiv=\"PRAGMA\" content=\"NO-CACHE\">\n";
  print "<link rel=\"shortcut icon\" href=\"favicon.ico\">\n";
  print "<link href=\"/css/style_faq.css\" type=\"text/css\" rel=\"stylesheet\">\n";

  if ($close eq 'auto') {
    $autoclose = "onLoad=\"update_parent();\"";
  }
  elsif ($close eq 'relogin') {
    $autoclose = "onLoad=\"update_parent1();\"";
  }

  print "<script type=\"text/javascript\">\n";
  print "function closeresults() {\n";
  print "  resultsWindow = window.close('results');\n";
  print "}\n";

  print "function update_parent() {\n";
  print "  window.opener.location = 'fulfillment.cgi';\n";
  print "  self.close();\n";
  print "}\n";

  print "function update_parent1() {\n";
  print "  window.opener.location = '/adminlogin.html';\n";
  print "  self.close();\n";
  print "}\n";

  print "function change_win(helpurl,swidth,sheight,windowname) {\n";
  print "  SmallWin = window.open(helpurl, windowname,'scrollbars=yes,resizable=yes,status=yes,toolbar=yes,menubar=yes,height='+sheight+',width='+swidth);\n";
  print "}\n";

  print "function closewin() {\n";
  print "  self.close();\n";
  print "}\n";
  print "</script>\n";

  print "</head>\n";
  print "<body $autoclose>\n";

  print "<table width=760 border=0 cellpadding=0 cellspacing=0 id=\"header\">\n";
  print "  <tr>\n";
  print "    <td>";
  if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
    print "<img src=\"/images/global_header_gfx.gif\" width=760 alt=\"Corporate Logo\" border=0>";
  }
  else {
    print "<img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corporate Logo\" border=0>";
  }
  print "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=left><img src=\"/images/header_bottom_bar_gfx.gif\" width=760 alt=\"\" height=14></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table border=0 cellspacing=0 cellpadding=0 width=760>\n";
  print "  <tr>\n";
  print "    <td colspan=2 class=larger><h1><b><a href=\"index.cgi\">Digital Product Fulfillment Administration</a> - $fulfillment::company</b></h1>";
  print "<p>$message";
  if ($close eq 'yes') {
    print "<p><div align=center><a href=\"javascript:update_parent();\">Close Window</a></div>\n";
  }
  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  my @now = gmtime(time);
  my $copy_year = $now[5]+1900;

  print "<table width=760 border=0 cellpadding=0 cellspacing=0 id=\"footer\">\n";
  print "  <tr>\n";
  print "    <td align=left><a href=\"/admin/logout.cgi\" title=\"Click to log out\">Log Out</a> | <a href=\"javascript:change_win('/admin/helpdesk.cgi',600,500,'ahelpdesk')\">Help Desk</a> | <a id=\"close\" href=\"javascript:closewin();\" title=\"Click to close this window\">Close Window</a></td>\n";
  print "    <td align=right>\&copy; $copy_year, ";
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

  &disconnect();

  exit;
}

sub response_page_blank {
  my($message,$close) = @_;
  my $autoclose = '';

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Response Page</title>\n";
  print "<meta http-equiv=\"CACHE-CONTROL\" content=\"NO-CACHE\">\n";
  print "<meta http-equiv=\"PRAGMA\" content=\"NO-CACHE\">\n";
  print "<link rel=\"shortcut icon\" href=\"favicon.ico\">\n";
  print "<link href=\"/css/style_faq.css\" type=\"text/css\" rel=\"stylesheet\">\n";

  if ($close eq 'auto') {
    $autoclose = "onLoad=\"update_parent();\"";
  }
  elsif ($close eq 'relogin') {
    $autoclose = "onLoad=\"update_parent1();\"";
  }

  print "<script type=\"text/javascript\">\n";
  print "function update_parent() {\n";
  print "  window.opener.location = '/admin/fulfillment.cgi';\n";
  print "  self.close();\n";
  print "}\n";

  print "function update_parent1() {\n";
  print "  window.opener.location = '/adminlogin.html';\n";
  print "  self.close();\n";
  print "}\n";
  print "</script>\n";

  print "</head>\n";
  print "<body $autoclose>\n";

  print "<table border=0 cellspacing=0 cellpadding=1 width=500>\n";
  print "  <tr>\n";
  print "    <td colspan=4>Working . . . . . . . . . . . . . . . . . </td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</body>\n";
  print "</html>\n";

  &disconnect();

  exit;
}

sub tail {
  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  my @now = gmtime(time);
  my $copy_year = $now[5]+1900;

  print "<table width=760 border=0 cellpadding=0 cellspacing=0 id=\"footer\">\n";
  print "  <tr>\n";
  print "    <td align=left><a href=\"/admin/logout.cgi\" title=\"Click to log out\">Log Out</a> | <a href=\"javascript:change_win('/admin/helpdesk.cgi',600,500,'ahelpdesk')\">Help Desk</a> | <a id=\"close\" href=\"javascript:closewin();\" title=\"Click to close this window\">Close Window</a></td>\n";
  print "    <td align=right>\&copy; $copy_year, ";
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
}

sub auth {
  my ($username,$subacct) = @_;

  my ($custstatus,$custreason);

  my $dbh = &miscutils::dbhconnect('pnpmisc');
  my $sth_cust = $dbh->prepare(q{
      SELECT status,reason,reseller,company
      FROM customers
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth_cust->execute($username) or die "Can't execute: $DBI::errstr";
  ($custstatus,$custreason,$fulfillment::reseller,$fulfillment::company) = $sth_cust->fetchrow;
  $sth_cust->finish;

  $dbh->disconnect;
}

sub head {
  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Fullfilment </title>\n";
  print "<meta http-equiv=\"CACHE-CONTROL\" content=\"NO-CACHE\">\n";
  print "<meta http-equiv=\"PRAGMA\" content=\"NO-CACHE\">\n";
  print "<link rel=\"shortcut icon\" href=\"favicon.ico\">\n";
  print "<link href=\"/css/style_faq.css\" type=\"text/css\" rel=\"stylesheet\">\n";

  print "<script type=\"text/javascript\">\n";
  print "function results() {\n";
  print "  // resultsWindow = window.open('/payment/recurring/blank.html','results','menubar=yes,toolbar=yes,status=no,scrollbars=yes,resizable=yes,width=550,height=500');\n";
  print "}\n";

  print "function onlinehelp(subject) {\n";
  print "  helpURL = '/online_help/' + subject + '.html';\n";
  print "  helpWin = window.open(helpURL,'helpWin','menubar=no,status=no,scrollbars=yes,resizable=yes,width=350,height=350');\n";
  print "}\n";

  print "function help_win(helpurl,swidth,sheight) {\n";
  print "  SmallWin = window.open(helpurl, 'HelpWindow','scrollbars=yes,resizable=yes,status=yes,toolbar=yes,menubar=yes,height='+sheight+',width='+swidth);\n";
  print "}\n";

  print "function close_me() {\n";
  print "  document.editUser.submit();\n";
  print "}\n";

  print "function change_win(helpurl,swidth,sheight,windowname) {\n";
  print "  SmallWin = window.open(helpurl, windowname,'scrollbars=yes,resizable=yes,status=yes,toolbar=yes,menubar=yes,height='+sheight+',width='+swidth);\n";
  print "}\n";

  print "function closewin() {\n";
  print "  self.close();\n";
  print "}\n";
  print "</script>\n";

  print "</head>\n";
  print "<body>\n";

  print "<table width=760 border=0 cellpadding=0 cellspacing=0 id=\"header\">\n";
  print "  <tr>\n";
  print "    <td>";
  if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
    print "<img src=\"/images/global_header_gfx.gif\" width=760 alt=\"Corporate Logo\" border=0>";
  }
  else {
    print "<img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corporate Logo\" border=0>";
  }
  print "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=left><img src=\"/images/header_bottom_bar_gfx.gif\" width=760 alt=\"\" height=14></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table border=0 cellspacing=0 cellpadding=0 width=760>\n";
  print "  <tr>\n";
  print "    <td colspan=2 class=larger><h1><b><a href=\"index.cgi\">Digital Product Fulfillment Administration</a> - $fulfillment::company</b></h1></td>\n";
  print "  </tr>\n";
}

sub main {

  &displaylist_form();
  &batchupload_form();
  &compresslist_form();
  &docs_form();
  &print_company();
}

sub displaylist_form {
  print "<tr>\n";
  print "  <th class=\"menuleftside\">Display<br>Fulfillment Data</th>\n";
  print "  <td class=\"menurightside\"><form method=post action=\"$fulfillment::path_main_cgi\">\n";
  print "<input type=hidden name=\"function\" value=\"displaylist\">\n";

  print "<table border=0 cellpadding=0 cellspacing=0>\n";
  print "  <tr>\n";
  print "    <td class=\"leftside\">Filter:</td>\n";
  print "    <td class=\"rightside\"><input type=radio name=\"filter\" value=\"all\" checked> All Records.\n";
  print "&nbsp; <input type=radio name=\"filter\" value=\"issued\"> Delivered.\n";
  print "&nbsp; <input type=radio name=\"filter\" value=\"notissued\"> Not yet delivered.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"leftside\">Output Format:</td>\n";
  print "    <td class=\"rightside\"><input type=radio name=\"format\" value=\"table\" checked> Table\n";
  print "&nbsp; <input type=radio name=\"format\" value=\"text\"> Text\n";
  print "&nbsp; <input type=radio name=\"format\" value=\"download\"> Download</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"leftside\">Data Delimiter:</td>\n";
  print "    <td class=\"rightside\"><input type=radio name=\"delimiter_type\" value=\"comma\"> Quote/Comma";
  print "&nbsp; <input type=radio name=\"delimiter_type\" value=\"tab\" checked> Tab\n";
  print "<br> <i>Applicable for Text and Download Formats Only</i></td>\n";
  print "  </tr>\n";
  print "</table>\n";
  print "<input type=submit class=\"button\" value=\"Submit Request\"></form>\n";
  print "<br><hr width=400></td>\n";
  print "  </tr>\n";
}

sub compresslist_form {
  print "<tr>\n";
  print "  <th class=\"menuleftside\">Compress<br>Fulfillment Data</th>\n";
  print "  <td class=\"menurightside\"><form method=post action=\"$fulfillment::path_main_cgi\">\n";
  print "<input type=hidden name=\"function\" value=\"compresslist\">\n";
  print "<input type=submit class=\"button\" value=\"Remove issued products from database.\"></form>\n";
  print "<br><hr width=400></td>\n";
  print "  </tr>\n";
}

sub batchupload_form {
  print "<tr>\n";
  print "  <th class=\"menuleftside\">Upload<br>Fulfillment Data</th>\n";
  print "  <td class=\"menurightside\"><form method=post action=\"$fulfillment::path_main_cgi\" enctype=\"multipart/form-data\">\n";
  print "<input type=hidden name=\"function\" value=upload>\n";

  print "<table border=0 cellpadding=0 cellspacing=0>\n";
  print "  <tr>\n";
  print "    <td class=\"leftside\">File:</td>\n";
  print "    <td class=\"rightside\"><input type=file name=\"data\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";
  print "<input type=submit class=\"button\" value=\"Upload Data\"> &nbsp;  &nbsp;  &nbsp; <a href=\"/help.cgi?subject=fulfillment\" target=help>Help</a></form>\n";
  print "<br><hr width=400></td>\n";
  print "  </tr>\n";
}

sub docs_form {

  print "<tr>\n";
  print "  <th class=\"menuleftside\">Documentation</th>\n";
  print "  <td class=\"menurightside\">&nbsp; <a href=\"/help.cgi?subject=fulfillment\" target=\"newWin\">Documentation</a>\n";
  print "<br><hr width=400></td>\n";
  print "  </tr>\n";
}

sub ipaddress_config {
  print "  <tr>\n";
  print "    <th class=\"menusection_title\" colspan=2>Remote Client Configuration</th>\n";
  print "  </tr>\n";

  if (@fulfillment::ipaddress > 0) {
    print "  <tr>\n";
    print "    <th class=\"menuleftside\">Delete IP Addresses</th>\n";
    print "    <td class=\"menurightside\"><form method=post action=\"/admin/fulfillment.cgi\">\n";
    print "<input type=hidden name=\"function\" value=\"delete_ip\">\n";
    print "<input type=hidden name=\"merchant\" value=\"$fulfillment::username\">\n";

    my $cnt = 0;
    print "<table border=1 cellspacing=0 cellpadding=4 width=\"100%\">\n";
    print "  <tr class=\"listsection_title\">\n";
    print "    <td>IP Address</td>\n";
    print "    <td>Action</td>\n";
    print "  </tr>\n";
    foreach my $key (@fulfillment::ipaddress) {
      printf("  <tr class=\"listrow_color%0d\">\n", ($cnt % 2));
      printf("    <td>%s</td>\n", $key);
      printf("    <td><input type=checkbox name=\"delete\_%s\" value=\"1\"> Delete</td>\n", $key);;
      print "  </tr>\n";
      $cnt++;
    }
    print "</table>\n";
    print "<input type=submit class=\"button\" name=\"submit\" value=\" Delete IP Address \"></form></td>\n";
    print "  </tr>\n";
  }

  print "<tr>\n";
  print "  <th class=\"menuleftside\" rowspan=2>Add IP Addresses</th>\n";
  print "  <td class=\"menurightside\"><form method=post action=\"/admin/fulfillment.cgi\">\n";
  print "<input type=hidden name=\"function\" value=\"add_ip\">\n";
  print "<input type=hidden name=\"merchant\" value=\"$fulfillment::username\">\n";

  print "<table border=1 cellspacing=0 cellpadding=4 width=\"100%\">\n";
  print "  <tr class=\"listsection_title\">\n";
  print "    <td>IP Address</td>\n";
  print "    <td>Action</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"$fulfillment::color{'ipaddress'}\">IP Address</td>\n";
  print "    <td class=\"$fulfillment::color{'ipaddress'}\"><input type=text name=\"ipaddress\" value=\"$fulfillment::query{'ipaddress'}\" size=15 maxlength=15> &nbsp; &nbsp; <b>XXX.XXX.XXX.XXX</b></td>\n";
  print "  </tr>\n";
  print "</table>\n";
  print "<input type=submit class=\"button\" name=\"submit\" value=\" Add IP Address \">&nbsp; &nbsp; <a href=\"javascript:help_win('/admin/help.cgi?subject=ipaddressconfig',600,500)\">Online Help</a></form></td>\n";
  print "  </tr>\n";
}

sub input_check {
  my ($data) = @_;

  my ($error,$errvar);
  foreach my $key (keys %fulfillment::query) {
    $fulfillment::color{$key} = 'goodcolor';
  }

  my @check = ('sku','product');
  my $test_str = '';
  foreach my $var (@check) {
    $test_str .= "$var|";
  }

  foreach my $var (@check) {
    my $val = $data->{$var};
    $val =~ s/[^a-zA-Z0-9]//g;
    if (length($val) < 1) {
      $fulfillment::error_string .= "Missing Value for $var.<br>";
      $error = 1;
      $fulfillment::color{$var} = 'badcolor';
      $errvar .= "$var\|";
    }
  }

  if ($fulfillment::error_string ne '') {
    $fulfillment::error_string .= "Please Re-enter.";
  }
  $fulfillment::error = $error;

  return "$error $errvar";
}

sub sort_hash {
  my $x = shift;
  my %array=%$x;
  sort { $array{$a} cmp $array{$b}; } keys %array;
}

sub product_import {
  my $orderid = PlugNPay::Transaction::TransactionProcessor::generateOrderID();
  my ($today,$time) = &miscutils::gendatetime_only();

  my $itemID = $orderid;

  my $filename = $fulfillment::query->param('data');

  my $parseflag = 0;
  my $i = 0;

  my (@fields,%data,%data_error);
  my $header_string = <$filename>;
  chomp $header_string;
  $header_string =~ tr/[A-Z]/[a-z]/;
  if (($header_string !~ /sku/) || ($header_string !~ /product/) || ($header_string !~ /fulfillment/)) {
    my $message = "Sorry Improper File Format";
    $message = "<p align=left>$message</p>";
    &response_page($message);
  }

  my @header_fields = split(/\t/,$header_string);
  my $sth = $fulfillment::dbh->prepare(q{
      INSERT INTO fulfillment
      (username,itemid,sku,product,orderid)
      VALUES (?,?,?,?,?)
    }) or die "Can't prepare: $DBI::errstr";
  while(<$filename>) {
    chomp;
    my %merchdata = ();

    my $line = $_;
    $line =~ s/^W//g;
    if (length($line) < 1) {
      next;
    }

    my @data = split('\t',$line);

    for (my $field=0; $field <= $#header_fields; $field++) {
      $header_fields[$field] =~ s/[^a-z]//g;
      $merchdata{$header_fields[$field]} = $data[$field];
    }

    $merchdata{'username'} = $ENV{'REMOTE_USER'};
    $merchdata{'itemid'} = $itemID;

    # SKU Filter
    $merchdata{'sku'} =~ s/[^0-9a-zA-Z\_\-\.]//g;
    $merchdata{'sku'} = substr($merchdata{'sku'},0,24);

    # Product Filter
    $merchdata{'product'} =~ s/[^0-9a-zA-Z\_\-\.\ \:]//g;
    $merchdata{'product'} = substr($merchdata{'product'},0,254);

    ## username, itemid, sku, product
    my ($error,$errvar) = &input_check(\%merchdata);

    if ($error > 0) {
      $data_error{$merchdata{'sku'}} = $errvar . " " . $error;
      next;
    }

    $sth->execute($merchdata{'username'}, $merchdata{'itemid'}, $merchdata{'sku'}, $merchdata{'product'}, 'available') or die "Can't execute: $DBI::errstr";

    $itemID = &miscutils::incorderid($itemID);
  }
  $sth->finish;

  my $message = "File Has Been Uploaded and Imported into Database";

  if (keys %data_error) {
    $message .= "<br>There was a problem with the following record(s).\n";
    $message .= "They were missing the following mandatory information.<br>\n";
    foreach my $key (keys %data_error) {
      $message .= "$i: $key: $data_error{$key}<br>\n";
    }
  }
  $message = "<p align=left>$message</p>";
  &response_page($message);
}

sub list_product {
  my $username = $ENV{'REMOTE_USER'};
  my @result = ();

  my $offset = $fulfillment::query->param('offset');
  if ($offset eq '') {
    $offset = 0;
  }

  my $sth = $fulfillment::dbh->prepare(qq{
      SELECT itemid,sku,orderid,product
      FROM fulfillment
      WHERE username=?
      ORDER BY itemid
      LIMIT $offset, 1000
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute($username) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  while(my $data = $sth->fetchrow_hashref) {
    $result[++$#result] = $data;
  }
  $sth->finish;

  &display_list(@result);
}

sub display_list {
  my (@data) = @_;

  my $filter = $fulfillment::query->param('filter');
  my $format = $fulfillment::query->param('format');
  my $delim = $fulfillment::query->param('delimiter_type');
  my $offset = $fulfillment::query->param('offset');

  my $delimiter;
  if ($delim eq "comma") {
    $delimiter = "\",\"";
  }
  else {
    $delimiter = "\t";
  }

  if ($format =~ /^(text|download)$/) {
    if ($delim eq "comma") {
      print "\"";
    }
    print "SKU" . $delimiter . "ORDERID" . $delimiter . "PRODUCT";
    if ($delim eq "comma") {
      print "\"\n";
    }
    else {
      print "\n";
    }
    for (my $pos=0;$pos<=$#data;$pos++) {
      if ($filter eq "issued") {
        if ($data[$pos]->{'orderid'} eq "available") {
          next;
        }
      }
      elsif ($filter eq "notissued") {
        if ($data[$pos]->{'orderid'} ne "available") {
          next;
        }
      }
      else {
        # All
      }
      if ($delim eq "comma") {
        print "\"";
      }
      print $data[$pos]->{'sku'} . $delimiter . $data[$pos]->{'orderid'} . $delimiter . $data[$pos]->{'product'};
      if ($delim eq "comma") {
        print "\"\n";
      }
      else {
        print "\n";
      }
    }
  }
  else {
    &head();

    print "  <tr>\n";
    print "    <td colspan=3><form method=post action=\"$fulfillment::path_main_cgi\">\n";
    print "<input type=hidden name=\"function\" value=\"delete_product\">\n";

    print "<table width=\"100%\" border=1 cellpadding=0 >\n";
    print "  <tr class=\"listsection_title\">\n";
    print "    <td>SKU</td>\n";
    print "    <td>OrderID</td>\n";
    print "    <td>Product</td>\n";
    print "    <td>Action</td>\n";
    print "  </tr>\n";
    for (my $pos=0; $pos<=$#data; $pos++) {
      if ($filter eq 'issued') {
        if ($data[$pos]->{'orderid'} eq '') {
          next;
        }
      }
      elsif ($filter eq 'notissued') {
        if ($data[$pos]->{'orderid'} ne '') {
          next;
        }
      }
      else {
        # All
      }
      printf("  <tr class=\"listrow_color%0d\">\n", ($pos % 2));
      printf("    <td>%s</td>\n", $data[$pos]->{'sku'});
      printf("    <td>%s</td>\n", $data[$pos]->{'orderid'});
      printf("    <td>%s</td>\n", $data[$pos]->{'product'});
      printf("    <td><input type=checkbox name=\"delete\_%s\" value=\"1\"> Delete</td>\n", $data[$pos]->{'itemid'});
      print "  </tr>\n";
    }
    print "  <tr>\n";
    print "    <td colspan=4 align=center><input type=submit class=\"button\" value=\"Delete Fulfillment Data\"></td>\n";
    print "  </tr>\n";
    print "</table>\n";
    print "</form>\n";

    if ($#data == 999) {
      print "<table width=\"100%\" border=1 cellpadding=0 >\n";
      print "  <tr>\n";
      print "    <td colspan=4 align=center><form method=post action\"$fulfillment::path_main_cgi\">\n";
      print "<input type=submit class=\"button\" value=\"next page\">\n";
      print "<input type=hidden name=\"function\" value=\"displaylist\">\n";
      print "<input type=hidden name=\"offset\" value=\"" . ($offset + 1000) . "\">\n";
      print "</form></td>\n";
      print "  </tr>\n";
      print "</table\n";
    }

    print "</td>\n";
    print "  </tr>\n";

    &tail();
  }
}

sub delete_product {
  my (@product_list) = @_;
  foreach my $var (@product_list) {
    my $sth = $fulfillment::dbh->prepare(q{
        DELETE FROM fulfillment
        WHERE username=?
        AND itemid=?
      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
    $sth->execute($ENV{'LOGIN'}, $var) or die "Can't execute: $DBI::errstr";
    $sth->finish;
  }
}

sub compress_product {
  my $sth = $fulfillment::dbh->prepare(q{
      DELETE FROM fulfillment
      WHERE username=?
      AND orderid > 0
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute($ENV{'LOGIN'}) or die "Can't execute: $DBI::errstr";
  $sth->finish;
}

sub print_company {
  print "<tr><td align=right colspan=2>$fulfillment::company</td></tr>\n";
}

sub format {
  return $fulfillment::query->param('format');
}

sub disconnect {
  $fulfillment::dbh->disconnect();
}

sub check_count {
  my($username,$threshold) = @_;
  my ($sku,$count,%count);
  my $sth = $fulfillment::dbh->prepare(q{
      SELECT sku, COUNT(sku)
      FROM fulfillment
      WHERE username=?
      AND orderid='available'
      GROUP BY sku
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute($username) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  while(my ($sku,$count) = $sth->fetchrow) {
    if ($count <= $threshold) {
      $count{$sku} = $count;
    }
  }
  $sth->finish;
}

1;
