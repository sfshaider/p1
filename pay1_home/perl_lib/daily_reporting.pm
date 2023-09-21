package daily_reporting;

require 5.001;

use CGI;
use miscutils;
use sysutils;
use PlugNPay::Features;
use strict;

sub new {
  my $type = shift;

  ## allow Proxy Server to modify ENV variable 'REMOTE_ADDR'
  if ($ENV{'HTTP_X_FORWARDED_FOR'} ne '') {
    $ENV{'REMOTE_ADDR'} = $ENV{'HTTP_X_FORWARDED_FOR'};
  }

  $daily_reporting::query = new CGI;

  $daily_reporting::query_log = "/home/pay1/cronjobs/pay1/reports/logs/qry2.log";

  $daily_reporting::dbh_pnpmisc = &miscutils::dbhconnect("pnpmisc");
  $daily_reporting::dbh_reports = &miscutils::dbhconnect("reports");

  ($daily_reporting::login) = @_;

  $daily_reporting::domain = "pay1.plugnpay.com";
  $daily_reporting::mainhost = "https://pay1.plugnpay.com";
  $daily_reporting::data_path = "/home/pay1/cronjobs/pay1/reports/data/";

  %daily_reporting::columnlist = ("username","username","orderID","orderid","card-name","card_name","card-address","card_addr","card-city","card_city","card-state","card_state","card-zip","card_zip","card-country","card_country","card-number","card_number","card-exp","card_exp","card-amount","amount","MErrmsg","descr","acct_code","acct_code","time","trans_time","FinalStatus","finalstatus","auth-code","auth_code","avs-code","avs","ipaddress","ipaddress","currency","currency","accttype","accttype","cvvresp","cvvresp","acct_code2","acct_code2","acct_code3","acct_code3","trans_type","trans_type","trans_date","trans_date","acct_code4","acct_code4","operation","operation","transflags","transflags",'invoicerefnum','invoicerefnum');

  %daily_reporting::orderlist = ("email","email","card-company",'card_company');   ### List of columns to pull from orders database

  #%daily_reporting::usernamelist = ();

  @daily_reporting::report_list = ();

  $daily_reporting::reseller = &get_resellername();

  if ($ENV{'SERVER_NAME'} =~ /pay\-gate/) {
    $daily_reporting::domain = "www.pay\-gate.com";
    $daily_reporting::mainhost = "https://www.pay-gate.com";
  }
  elsif ($ENV{'SERVER_NAME'} =~ /penzpay/) {
    $daily_reporting::domain = "www.penzpay.com";
    $daily_reporting::mainhost = "https://www.penzpay.com";
  }
  elsif ($ENV{'SERVER_NAME'} =~ /ugateway/) {
    $daily_reporting::domain = "www.ugateway.com";
    $daily_reporting::mainhost = "https://www.ugateway.com";
  }
  elsif ($ENV{'SERVER_NAME'} =~ /icommerce/) {
    $daily_reporting::domain = "www.icommercegateway.com";
    $daily_reporting::mainhost = "https://www.icommercegateway.com";
  }
  elsif ($ENV{'SERVER_NAME'} =~ /mercurypay/) {
    $daily_reporting::domain = "gateway.mercurypay.com";
    $daily_reporting::mainhost = "https://gateway.mercurypay.com";
  }
  elsif ($ENV{'SERVER_NAME'} =~ /cw\-ebusiness/) {
    $daily_reporting::domain = "webcommerce.cw-ebusiness.com";
    $daily_reporting::mainhost = "https://webcommerce.cw-ebusiness.com";
  }
  elsif ($ENV{'SERVER_NAME'} =~ /eci\-pay/) {
    $daily_reporting::domain = "www.eci-pay.com";
    $daily_reporting::mainhost = "https://www.eci-pay.com";
  }
  elsif ($ENV{'SERVER_NAME'} =~ /secure\.creditcardpaymentsystems\.com/) {
    $daily_reporting::domain = "secure.creditcardpaymentsystems.com";
    $daily_reporting::mainhost = "https://secure.creditcardpaymentsystems.com";
  }

  $daily_reporting::path_to_cgi = "/admin/reports/index.cgi";

  ($daily_reporting::today) = &miscutils::gendatetime_only();

  # get date for 31 days ago
  ($daily_reporting::thirtydaysago) = &miscutils::gendatetime_only(-31*24*60*60);

  my $merchant = &CGI::escapeHTML($daily_reporting::login);
  $merchant =~ s/[^a-zA-Z0-9]//g;
  $merchant =~ lc("$merchant");
  if ($merchant !~ /\w/) {
    $merchant = $ENV{'REMOTE_USER'};
  }
  my $dbh = &miscutils::dbhconnect("pnpmisc");
  my $sth_cust = $dbh->prepare(q{
      SELECT processor
      FROM customers
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth_cust->execute("$merchant") or die "Can't execute: $DBI::errstr";
  my ($processor) = $sth_cust->fetchrow;
  $sth_cust->finish;
  $dbh->disconnect;

  if ($processor ne "fdms") {
    delete  $daily_reporting::columnlist{'invoicerefnum'};
  }

  return [], $type;
}

sub function {
  return &CGI::escapeHTML($daily_reporting::query->param('function'));
}

sub format {
  return &CGI::escapeHTML($daily_reporting::query->param('format'));
}

sub disconnect {
  $daily_reporting::dbh_pnpmisc->disconnect();
  $daily_reporting::dbh_reports->disconnect();
}

sub main {

  &review_reports();
  if (($ENV{'REMOTE_ADDR'} =~ /^(24.184.187.61|96.56.10.14|96.56.10.12|72.80.173.202)$/) || ($ENV{'TECH'} ne "")) {
    &configure_reports();
    &delete_report_list();
  }
  #&helpdesk();
}

sub head {

  my $merchant = &CGI::escapeHTML($daily_reporting::login);
  $merchant =~ s/[^a-zA-Z0-9]//g;
  $merchant =~ lc("$merchant");
  if ($merchant !~ /\w/) {
    $merchant = $ENV{'REMOTE_USER'};
  }

  my $dbh = &miscutils::dbhconnect("pnpmisc");
  my $sth_cust = $dbh->prepare(q{
      SELECT company
      FROM customers
      WHERE username=?
    }) or die "Can't do: $DBI::errstr";
  $sth_cust->execute("$merchant") or die "Can't execute: $DBI::errstr";
  my ($company) = $sth_cust->fetchrow;
  $sth_cust->finish;
  $dbh->disconnect;

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Merchant Reporting Area</title>\n";
  print "<link rel=\"shortcut icon\" href=\"favicon.ico\">\n";
  print "<meta http-equiv=\"expires\" content=\"0\">\n";

  print "<style type=\"text/css\">\n";
  print "th { font-family: Arial,Helvetica,Univers,Zurich BT; font-size: 11pt; color: #000000 }\n";
  print "td { font-family: Arial,Helvetica,Univers,Zurich BT; font-size: 10pt; color: #000000 }\n";
  print ".tdtitle { font-family: Arial,Helvetica,Univers,Zurich BT; font-size: 10pt; color: #000000; background: #d0d0d0 }\n";
  print ".tdleft { font-family: Arial,Helvetica,Univers,Zurich BT; font-size: 10pt; color: #000000; background: #d0d0d0 }\n";
  print ".tddark { font-family: Arial,Helvetica,Univers,Zurich BT; font-size: 10pt; color: #000000; background: #4a7394 }\n";
  print ".even {background: #ffffff}\n";
  print ".odd {background: #eeeeee}\n";
  print ".badcolor { color: #ff0000 }\n";
  print ".goodcolor { color: #000000 }\n";
  print ".larger { font-size: 100% }\n";
  print ".smaller { font-size: 60% }\n";
  print ".short { font-size: 8% }\n";
  print ".button { font-size: 75% }\n";
  print ".itemscolor { background-color: #000000; color: #ffffff }\n";
  print ".itemrows { background-color: #d0d0d0 }\n";
  print ".items { position: static }\n";
  print ".info { position: static }\n";
  print "DIV.section { text-align: justify; font-size: 12pt; color: white}\n";
  print "DIV.subsection { text-indent: 2em }\n";
  #print  H1 { font-style: italic; color: green }\n";
  #print  H2 { color: green }\n";
  print "</style>\n";
  print "<link href=\"/css/style_graphs.css\" type=\"text/css\" rel=\"stylesheet\">\n";

  print "<script type=\"text/javascript\">\n";
  print "<!-- Start Script\n";

  print "function disableForm(theform) {\n";
  print "  if (document.all || document.getElementById) {\n";
  print "    for (i = 0; i < theform.length; i++) {\n";
  print "      var tempobj = theform.elements[i];\n";
  print "      if (tempobj.type.toLowerCase() == 'submit' || tempobj.type.toLowerCase() == 'reset')\n";
  print "        tempobj.disabled = true;\n";
  print "    }\n";
  print "    return true;\n";
  print "  }\n";
  print "  else {\n";
  print "    return true;\n";
  print "  }\n";
  print "}\n";

  print "function change_win(helpurl,swidth,sheight,windowname) {\n";
  print "  SmallWin = window.open(helpurl, windowname,'scrollbars=yes,resizable=yes,status=yes,toolbar=yes,menubar=yes,height='+sheight+',width='+swidth);\n";
  print "}\n";

  print "function closewin() {\n";
  print "  self.close();\n";
  print "}\n";

  print "// end script-->\n";
  print "</script>\n";

  print "</head>\n";

  print "<body bgcolor=\"#ffffff\">\n";
  print "<table width=760 border=0 cellpadding=0 cellspacing=0 id=\"header\">\n";
  print "  <tr>\n";
  print "    <td colspan=3 align=left>";
  if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) { ## DCP 20100719 changed from Forwarded_server
    print "<img src=\"/images/global_header_gfx.gif\" width=760 alt=\"Plug 'n Pay Technologies - we make selling simple.\" height=44 border=0>";
  }
  else {
    print "<img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Logo\">\n";
  }
  print "</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=3 align=left><img src=\"/css/header_bottom_bar_gfx.gif\" width=760 height=14></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table border=0 cellspacing=0 cellpadding=5 width=760>\n";
  print "  <tr>\n";
  print "    <td colspan=2><h1><a href=\"$ENV{'SCRIPT_NAME'}\">Reporting Administration</a> - $company</h1>\n";

  print "<table border=0 cellspacing=0 cellpadding=4 width=\"100%\">\n";
}

sub helpdesk {
  print "  <tr class=\"across\">\n";
  print "    <th colspan=3 class=\"across\">Help</th>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"menuleftside\">Help Desk</th>\n";
  print "    <td class=\"menurightside\" colspan=2>\n";
  print "<form method=post action=\"/admin/helpdesk.cgi\" target=\"ahelpdesk\">\n";
  print "<input type=submit name=\"submit\" value=\"Help Desk\" onClick=\"window.open('','ahelpdesk','width=550,height=520,toolbar=no,location=no,directories=no,status=no,menubar=no,scrollbars=yes,resizable=yes'); return(true);\">\n";
  print "</form>\n";
  print "    </td>\n";
  print "  </tr>\n";
}

sub tail {
  print "</table>\n";

  my @now = gmtime(time);
  my $copy_year = $now[5]+1900;

  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";

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

sub review_reports {
  print "  <tr>\n";
  print "    <th colspan=2 valign=top align=center><h3>Reports will only be available for 30 days</h3></th>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th class=\"menuleftside\"> Review Reports </th>\n";
  print "    <td class=\"menurightside\">\n";

  if (($daily_reporting::reseller !~ /^(paynisc|payntel|siipnisc|siiptel|elretail|teretail)$/) && ($daily_reporting::login ne "pnpdemo")) {
    print "<form method=post action=\"https://$daily_reporting::domain$daily_reporting::path_to_cgi\" enctype=\"multipart/form-data\" onSubmit=\"return disableForm(this);\">\n";
    print "<input type=hidden name=function value=viewreport>\n";
    print "<select name=\"reportid\">\n";
  }

  my $sth_review = $daily_reporting::dbh_reports->prepare(q{
      SELECT reportname,reporttime
      FROM report_data
      WHERE username=?
      AND reporttime>?
      ORDER BY reporttime DESC
    }) or die "failed prepare $DBI::errstr\n";
  $sth_review->execute("$daily_reporting::login","$daily_reporting::thirtydaysago") or die "failed execute $DBI::errstr\n";

  if (($daily_reporting::reseller =~ /^(paynisc|payntel|siipnisc|siiptel|elretail|teretail)$/) || ($daily_reporting::login eq "pnpdemo")) {
    while (my $data = $sth_review->fetchrow_hashref) {
      print "\&nbsp;\&nbsp;" . substr($data->{'reporttime'},4,2) . "/" . substr($data->{'reporttime'},6,2) . "/" . substr($data->{'reporttime'},0,4);
      print "\&nbsp;\&nbsp;" . $data->{'reportname'} . "\&nbsp\;\&nbsp\;\&nbsp\;\&nbsp\;<a href=\"$daily_reporting::path_to_cgi?reportid=" . $data->{'reportname'} . "," . $data->{'reporttime'} ."&function=viewreport&format=html \"> html </a> \&nbsp\;\&nbsp\;\&nbsp\;\&nbsp\;<a href=\"$daily_reporting::path_to_cgi\?reportid=" . $data->{'reportname'} . "," . $data->{'reporttime'} ."&function=viewreport&format=text\"> download </a>";
      if ($ENV{'REMOTE_ADDR'} =~ /^(96\.56\.10\.14|96\.56\.10\.12)$/) {
        print "\&nbsp\;\&nbsp\;\&nbsp\;\&nbsp\;<a href=\"$daily_reporting::path_to_cgi?reportid=" . $data->{'reportname'} . "&reporttime=" . $data->{'reporttime'} ."&function=deletereportdata \"> Delete </a>";
      }
      print "<br>&nbsp;\n";
    }
  }
  else {
    while (my $data = $sth_review->fetchrow_hashref) {
      print "<option value=\"" . $data->{'reportname'} . "," . $data->{'reporttime'} . "\"> " . $data->{'reportname'} . " " . substr($data->{'reporttime'},4,2) . "/" . substr($data->{'reporttime'},6,2) . "/" . substr($data->{'reporttime'},0,4) . "</option>\n";
    }
  }
  $sth_review->finish;

  if (($daily_reporting::reseller !~ /^(paynisc|payntel|siipnisc|siiptel|elretail|teretail)$/) && ($daily_reporting::login ne "pnpdemo")) {
    print "</select>\n";
    print "<br><b>HTML</b> <input type=radio name=\"format\" value=\"html\" checked>\n";
    print " <b>Text</b> <input type=radio name=\"format\" value=\"text\">\n";
    print "<br><input type=submit value=\"Send\">\n";
    print "</form>\n";
  }
  print "<br><hr width=450>\n";
  print "  </td>\n";
}

sub configure_reports {

  print "  <tr>\n";
  print "    <th class=\"menuleftside\"> Configure Reports </th>\n";
  print "    <td class=\"menurightside\"><form method=post action=\"https://$daily_reporting::domain$daily_reporting::path_to_cgi\" enctype=\"multipart/form-data\" onSubmit=\"return disableForm(this);\">\n";
  print "<input type=hidden name=function value=addreport>\n";

  print "<table border=0 cellspacing=0 cellpadding=1>\n";
  print "  <tr>\n";
  print "    <td class=\"leftside\">Name:</td>\n";
  print "    <td><input type=text name=\"reportname\" value=\"\" size=16 maxlength=16></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"leftside\">Columns:</td>\n";
  print "    <td><select size=10 multiple name=\"columns\">\n";
  foreach my $name (sort keys %daily_reporting::columnlist) {
    print "<option value=\"$name\"> $name </option>\n";
  }
  print "</select></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"leftside\">Trans Type:</td>\n";
  print "    <td><select name=\"transtype\">\n";
  print "<option value=\"all\"> All </option>\n";
  print "<option value=\"auth\"> Authorized </option>\n";
  print "<option value=\"postauth\"> Settled </option>\n";
  print "</select></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"leftside\">Frequency:</td>\n";
  print "    <td><select name=\"frequency\">\n";
  print "<option value=\"\"> Manual </option>\n";
  print "<option value=\"daily\"> Daily </option>\n";
  print "<option value=\"weekly\"> Weekly </option>\n";
  print "<option value=\"monthly\"> Monthly </option>\n";
  print "</select></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td class=\"leftside\">Group by:</td>\n";
  print "    <td><select name=\"groupby\">\n";
  print "<option value=\"\"> None </option>\n";
  print "<option value=\"trans_date\"> Date </option>\n";
  print "<option value=\"card-type\"> Card Type </option>\n";
  print "<option value=\"acct_code4\"> Manual/Online </option>\n";
  print "<option value=\"username\"> Processor </option>\n";
  print "</select></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td colspan=2><input type=submit value=\"Add\"></td></form>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<br><hr width=450>\n";
  print "</td>\n";
}

sub delete_report_list {
  print "  <tr>\n";
  print "    <th class=\"menuleftside\"> Delete Reports </th>\n";
  print "    <td class=\"menurightside\"><form method=post action=\"https://$daily_reporting::domain$daily_reporting::path_to_cgi\" enctype=\"multipart/form-data\" onSubmit=\"return disableForm(this);\">\n";
  print "<input type=hidden name=function value=deletereport>\n";

  print "<table border=0 cellspacing=0 cellpadding=1>\n";
  print "  <tr>\n";
  print "    <td class=\"leftside\">Name:</td>\n";
  print "    <td><select name=\"reportname\">\n";

  my $sth_list = $daily_reporting::dbh_reports->prepare(q{
      SELECT reportname,transtype,frequency,groupby,tablename,columnlist
      FROM report_config
      WHERE username=?
    }) or die "failed prepare $DBI::errstr\n";
  $sth_list->execute("$daily_reporting::login") or die "faile execute $DBI::errstr\n";
  while(my ($reportname,$transtype,$frequency,$groupby,$tablename,$columnlist) = $sth_list->fetchrow) {
    #@daily_reporting::report_list = (@daily_reporting::report_list,$reportname);
    $daily_reporting::report_list[++$#daily_reporting::report_list] = "$reportname";
    print "<option value=\"$reportname\">$reportname</option><!-- <TT:$transtype, FREQ:$frequency, GRPBY:$groupby, TABLE:$tablename, COLS:$columnlist> -->\n";
    #print "UN:$username, RN:$reportname, TT:$transtype, FREQ:$frequency, GRPBY:$groupby, TABLE:$tablename, COLS:$columnlist<br>\n";
  }
  $sth_list->finish;

  print "</select>\n";
  print "<input type=submit value=\"Delete\"></td></form>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<br><hr width=450>\n";
  print "</td>\n";
  print "  </tr>\n";
}

sub delete_report {
  my $reportname = &CGI::escapeHTML($daily_reporting::query->param('reportname'));

  #print"XXXXXXXXXXXXXXXXXXXXXX UN:$daily_reporting::login, RN:$reportname<br>\n";
  #return;

  my $sth = $daily_reporting::dbh_reports->prepare(q{
      DELETE FROM report_config
      WHERE username=?
      AND reportname=?
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute("$daily_reporting::login", "$reportname") or die "Can't execute: $DBI::errstr";
  $sth->finish;
}

sub delete_report_data {
  my $reportname = &CGI::escapeHTML($daily_reporting::query->param('reportid'));
  my $reporttime = &CGI::escapeHTML($daily_reporting::query->param('reporttime'));

  my $sth = $daily_reporting::dbh_reports->prepare(q{
      SELECT filename
      FROM report_data
      WHERE username=?
      AND reportname=?
      AND reporttime=?
    }) or die "failed prepare $DBI::errstr\n";
  $sth->execute("$daily_reporting::login", "$reportname", "$reporttime") or die "failed execute $DBI::errstr";
  my ($filename) = $sth->fetchrow;
  $sth->finish;

  $filename = "$daily_reporting::data_path$filename";

  unlink("$filename");

  $sth = $daily_reporting::dbh_reports->prepare(q{
      DELETE FROM report_data
      WHERE username=?
      AND reportname=?
      AND reporttime=?
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute("$daily_reporting::login", "$reportname", "$reporttime") or die "Can't execute: $DBI::errstr";
  $sth->finish;

  #print "DELETEING: FN:$filename, UN:$daily_reporting::login, RN:$reportname, RT:$reporttime\n";
}

sub insert_report_config {
  my $reportname = &CGI::escapeHTML($daily_reporting::query->param('reportname'));
  $reportname =~ s/[^a-zA-Z0-9 ]//g;

  my $transtype = &CGI::escapeHTML($daily_reporting::query->param('transtype'));
  $transtype =~ s/[^a-zA-Z-_]//g;

  my $frequency = &CGI::escapeHTML($daily_reporting::query->param('frequency'));
  $frequency =~ s/[^a-zA-Z-_]//g;

  my $groupby = &CGI::escapeHTML($daily_reporting::query->param('groupby'));
  $groupby =~ s/[^0-9a-zA-Z-_]//g;

  my $tablename = "trans_log";

#  my @columns_used = &CGI::escapeHTML($daily_reporting::query->param('columns'));
  # columns_used is not displayed at this point to the user escaping it breaks the config.
  # the actual value is taken from columnlist
  my @columns_used = $daily_reporting::query->param('columns');
  my @columns_required = ("card-number");
#666
  my %columnlist = reverse %daily_reporting::columnlist;

  foreach my $name (keys %columnlist) {
    $columnlist{$name} = 0;
  }

  foreach my $column (@columns_required) {
    $columnlist{$column} = 2;
  }

  foreach my $column (@columns_used) {
    $columnlist{$column} = 1;
  }

  my $column_str = "";
  foreach my $name (keys %columnlist) {
    if ($columnlist{$name} > 0) {
      $column_str .= "$name|$columnlist{$name}\t";
    }
  }

  chop $column_str;

  my $sth_insert = $daily_reporting::dbh_reports->prepare(q{
      INSERT INTO report_config
      (username,reportname,transtype,frequency,groupby,tablename,columnlist)
      VALUES (?,?,?,?,?,?,?)
    }) or die "failed prepare $DBI::errstr\n";
  $sth_insert->execute("$daily_reporting::login","$reportname","$transtype","$frequency","$groupby","$tablename","$column_str") or die "failed execute $DBI::errstr\n";
  $sth_insert->finish;
}

sub save_report_data {
  my ($self,$report_ref) = @_;

  # filename "reportname"_"timestamp".dat
  my $report_year = substr($report_ref->{'date'},0,4);
  my $data_file_name = $report_year . "/" . $report_ref->{'username'} . "_" . $report_ref->{'reportname'} . "_" . $report_ref->{'date'} . ".dat";
  my $temp_header = $report_ref->{'header'};
  my @header_array = split(/\t/,$temp_header);

  my $report_dir = $daily_reporting::data_path . $report_year;
  if (! -e $report_dir) {
    `mkdir $report_dir`;
  }

  my $data = $report_ref->{'data'};

  &sysutils::filelog("write",">$daily_reporting::data_path$data_file_name");
  open(OUTFILE,'>',"$daily_reporting::data_path$data_file_name") or print "Can't open $daily_reporting::data_path$data_file_name for writing. $!";
  print OUTFILE $report_ref->{'header'} .  "\t$report_ref->{'settletimestart'}\t$report_ref->{'settletimeend'}\n";

  for (my $line=0;$line<=$#{$data};$line++) {
    my $entry = "";
    foreach my $key (@header_array) {
      my ($table_key,$table_flag) = split(/\|/,$key);
      $table_key = $daily_reporting::columnlist{$table_key};
      $table_key =~ tr/[a-z]/[A-Z]/;
      $entry .= $data->[$line]->{$table_key} . "\t";
    }
    chop $entry;
    print OUTFILE $entry . "\n";
  }
  close OUTFILE;

  my $sth_save = $daily_reporting::dbh_reports->prepare(q{
      INSERT INTO report_data
      (username,reportname,reporttime,filename)
      VALUES (?,?,?,?)
    }) or die "failed prepare $DBI::errstr\n";
  $sth_save->execute("$report_ref->{'username'}","$report_ref->{'reportname'}","$report_ref->{'date'}","$data_file_name") or die "failed execute $DBI::errstr\n";
  $sth_save->finish;

}

sub get_report_list {
  my $type = shift;
  my @results = ();
  my ($replist) = @_;

  my $sth_list = $daily_reporting::dbh_reports->prepare(q{
      SELECT username,reportname,transtype,frequency,groupby,tablename,columnlist
      FROM report_config
      WHERE frequency='daily'
    }) or die "failed prepare $DBI::errstr\n";
  $sth_list->execute() or die "faile execute $DBI::errstr\n";
  while (my $data = $sth_list->fetchrow_hashref) {
    $$replist{$data->{'username'}} = 1;
    $results[++$#results] = $data;
  }
  $sth_list->finish;

  return @results;
}

sub get_daily_data {
  my ($type,$starttime,$endtime,$table,$merchlist) = @_;
  my @result = ();

  if ($table eq "") {
    $table = "trans_log t, ordersummary o";
  }

  my $columns = "";
  foreach my $key (keys %daily_reporting::columnlist) {
    $columns .= "t\." . $daily_reporting::columnlist{$key} . ",";
  }
  if ($table =~ /ordersummary/) {
    foreach my $key (keys %daily_reporting::orderlist) {
      $columns .= "o\." . $daily_reporting::orderlist{$key} . ",";
    }
  }
  chop $columns;

  my @placeholder;
  my $sql_query = "SELECT " . $columns;
  $sql_query .= " from $table";
  $sql_query .= " WHERE t.trans_date between ? AND ?";
  push(@placeholder, substr($starttime,0,8), substr($endtime,0,8));
  if ($merchlist ne "") {
    $sql_query .= " AND t.username IN ($merchlist)";
  }
  $sql_query .= " AND t.trans_time BETWEEN ? AND ?";
  push(@placeholder, $starttime, $endtime);
  $sql_query .= " AND t.operation NOT IN ('query','batchprep')";
  $sql_query .= " AND t.finalstatus IN ('success','pending','badcard','problem')";

  if ($table =~ /ordersummary/) {
    $sql_query .= " AND o.trans_date BETWEEN ? AND ?";
    push(@placeholder, substr($starttime,0,8), substr($endtime,0,8));
    $sql_query .= " AND o.orderid=t.orderid";
  }

  &sysutils::filelog("append",">>$daily_reporting::query_log");
  open(OUTLOG,'>>',"$daily_reporting::query_log") or print "Can't open $daily_reporting::query_log for appending. $!";
  print OUTLOG gmtime(time) . "$sql_query\n\n";
  close OUTLOG;
  
  my $dbh_pnpdata = &miscutils::dbhconnect("pnpdata");
  my $sth_data = $dbh_pnpdata->prepare(qq{ $sql_query }) or die "failed prepare $DBI::errstr\n";
  $sth_data->execute(@placeholder) or die "failed execute $DBI::errstr\n";

  while (my $data = $sth_data->fetchrow_hashref) {
    if (exists $$data{'AUTH_CODE'}) {
      $$data{'AUTH_CODE'} = substr($$data{'AUTH_CODE'},0,6);
      $$data{'INVOICEREFNUM'} = substr($$data{'AUTH_CODE'},33,10);
    }
    #foreach my $key (sort keys %$data) {
    #  print "A:$key, $$data{$key}, ";
    #}
    #print "NEWLINE\n";
    $result[++$#result] = $data;
  }

  $sth_data->finish;
  $dbh_pnpdata->disconnect;

  return @result;
}

sub get_merchant_settletimes {
  shift;
  my @array = @_;
  my ($unamestr);
  foreach my $var (@array) {
    $unamestr .= "'$var',";
  }
  chop $unamestr;

  #print "UNSTR:$unamestr\n";
  #exit;

  my %results = ();

  my $sth_times = $daily_reporting::dbh_pnpmisc->prepare(qq{
      SELECT username
      FROM customers
      WHERE username IN ($unamestr)
      AND status='live'
      AND reseller NOT IN ('paynisc','payntel','siipnisc','siiptel','teretail','elretail')
    }) or die "failed prepare $DBI::errstr\n";
  $sth_times->execute() or die "failed execute $DBI::errstr\n";
  while (my ($username) = $sth_times->fetchrow) {
    #print "UN:$username\n";

    my $accountFeatures = new PlugNPay::Features("$username",'general');
    my $features = $accountFeatures->getFeatureString();

    if (($features ne "") && ($features =~ /settletime/)) {
      my @array = split(/\,/,$features);
      foreach my $entry (@array) {
        my ($name,$value) = split(/\=/,$entry);
        if ($name eq "settletime") {
          if ($value eq "24") {
            $value = "0";
          }
          $results{$username}{"time"} = $value;
        }
        if ($name eq "settletimezone") {
          $results{$username}{"zone"} = $value;
        }
      }
    }
  }
  $sth_times->finish;

  return %results;
}

sub view_report {

  my ($reportname,$reporttime) = split(/\,/,&CGI::escapeHTML($daily_reporting::query->param('reportid')));
  my $format = &CGI::escapeHTML($daily_reporting::query->param('format'));

  my $sth_view = $daily_reporting::dbh_reports->prepare(q{
      SELECT d.filename, c.transtype, c.groupby, c.status
      FROM report_data d, report_config c
      WHERE d.username=?
      AND d.reportname=?
      AND d.reporttime=?
      AND c.username=d.username
      AND c.reportname=d.reportname
    }) or die "failed prepare $DBI::errstr\n";
  $sth_view->execute("$daily_reporting::login","$reportname","$reporttime") or die "failed execute $DBI::errstr\n";
  my $data = $sth_view->fetchrow_hashref;
  $sth_view->finish;

  if ($data->{'status'} eq "") {
    $data->{'status'} = "success|problem|pending";
  }

  if ($format eq "html") {
    &head;
  }
  &sysutils::filelog("read","$daily_reporting::data_path$data->{'filename'}");
  open(INFILE,'<',"$daily_reporting::data_path$data->{'filename'}") or print "Can't open $daily_reporting::data_path$data->{'filename'} for reading. $!";
  my $header = <INFILE>;
  my @input = ();
  while (<INFILE>) {
    chomp;
    $input[++$#input] = $_;
  }
  close INFILE;

  my @header_array = split(/\t/,$header);

  if ($format eq "html") {
    print "<tr>";
    print "  <td> $reportname<br>" . substr($reporttime,4,2) . "/" . substr($reporttime,6,2) . "/" . substr($reporttime,0,4) . "</td>\n";
    print "</tr>\n";
    print "<tr>\n";
    for (my $pos=0;$pos<=$#header_array;$pos++) {
      my ($table_key,$table_flag) = split(/\|/,$header_array[$pos]);
      if ((($table_flag eq "") || ($table_flag == 1)) && ($table_key !~ /^(trans_type|trans_date|username)$/)) {
        print "  <th class=\"odd\">$table_key</th>\n";
      }
    }
    print "</tr>\n";
  }
  else {
    my $header = "";
    for (my $pos=0;$pos<=$#header_array;$pos++) {
      my ($table_key,$table_flag) = split(/\|/,$header_array[$pos]);
      if ((($table_flag eq "") || ($table_flag == 1)) && ($table_key !~ /^(trans_type|trans_date|username)$/)) {
        $header .= "$table_key\t";
      }
    }
    chomp $header;
    print "$header\n";;
  }

# 666 working here
  my %grouped_hash = ();
  foreach my $line (@input) {
    my %input_hash = ();
    my @input_line = split(/\t/,$line);

    # skip transactions when the status is not in the config list
    if ($data->{'status'} !~ /$input_hash{'FinalStatus'}/) {
      next;
    }

    for (my $pos=0;$pos<=$#header_array;$pos++) {
      my ($table_key,$table_flag) = split(/\|/,$header_array[$pos]);
      $input_hash{$table_key} = $input_line[$pos];
    }
    # check the type of transaction or do all
#print "tst $input_hash{'operation'} " . $data->{"transtype"} . "<br>\n";
    if (($input_hash{"operation"} eq $data->{"transtype"}) || ($data->{"transtype"} eq "all") || ($data->{"transtype"} eq "All")) {
      my $tmpgroup = "";
      # now we setup the group for card-type we have to do some special thingy
      if ($data->{"groupby"} eq "card-type") {
        if ($input_hash{'accttype'} eq "") {
          $tmpgroup = &card_type($input_hash{"card-number"});
        }
        else {
          $tmpgroup = "Check";
        }
      }
      else {
        $tmpgroup = $input_hash{$data->{"groupby"}};
      }
#      if (($daily_reporting::login ne "pnpnisc") && ($daily_reporting::login ne "blackriver")) {
#        if ((($input_hash{"accttype"} ne "") && ($input_hash{'FinalStatus'} eq "success")) || ((&card_type($input_hash{"card-number"}) eq "none") && ($input_hash{'FinalStatus'} eq "success"))) {
#          next;
#        }
#      }
      $grouped_hash{$tmpgroup}[++$#{$grouped_hash{$tmpgroup}}] = \%input_hash;
    }
  }

  my $grand_total = 0;
  my $trx_count = 0;
  foreach my $group (sort keys %grouped_hash) {
    my $group_total = 0;
    my $group_count = 0;
    # print group
    if ($format eq "html") {
      print "<tr>\n";
      print "  <th class=\"tddark\" align=left colspan=" . $#header_array  . "> $group </th>\n";
      print "</tr>\n";
    }
    else {
      # do nothing...
    }
    for (my $outer=0;$outer<=$#{$grouped_hash{$group}};$outer++) {
      $trx_count += 1;
# 666 a bit naughty maybe make a config option
#if (($group eq "Check") && ($grouped_hash{$group}[$outer]->{'FinalStatus'} eq "success")) {
#  if (($daily_reporting::login ne "pnpnisc")  && ($daily_reporting::login ne "blackriver")) {
#    next;
#  }
#}

#if (($daily_reporting::login eq "pnpnisc") && ($group eq "Check") && ($grouped_hash{$group}[$outer]->{'FinalStatus'} eq "pending")) {
#  next;
#}

      $group_total += (split(/\s/,$grouped_hash{$group}[$outer]->{'card-amount'}))[1];
      $group_count++;
      my $line = "";
      if ($format eq "html") {
        $line .= "<tr>\n";
      }
      for (my $pos=0;$pos<=$#header_array;$pos++) {
        my ($table_key,$table_flag) = split(/\|/,$header_array[$pos]);
        if ((($table_flag eq "") || ($table_flag == 1)) && ($table_key !~ /^(trans_type|trans_date|username)$/)) {
          if ($format eq "html") {
            $line .= "  <td class=\"";
            if (($outer%2) > 0) {
              $line .= "odd\"";
            }
            else {
              $line .= "even\"";
            }
            $line .= ">" . $grouped_hash{$group}[$outer]->{$table_key} . "</td>\n";
          }
          else {
            $line .= $grouped_hash{$group}[$outer]->{$table_key} . "\t";
          }
        }
      }
      if ($format eq "html") {
        $line .= "</tr>\n";
      }
      else {
        chomp $line;
      }
      print "$line\n";
    }
    $group_total = sprintf("%.2f",$group_total);
    if ($format eq "html") {
      print "  <tr>\n";
      print "    <td colspan=" . $#header_array  . "> Total: $group_total <td>\n";
      print "  </tr>\n";
      print "  <tr>\n";
      print "    <td colspan=" . $#header_array  . "> Count: $group_count <td>\n";
      print "  </tr>\n";
    }
    else {
      # do nothing...
    }
    $grand_total += $group_total;
  }
  $grand_total = sprintf("%.2f",$grand_total);
  if ($format eq "html") {
    print "  <tr>\n";
    print "    <td class=\"odd\" colspan=" . $#header_array  . "> Grand Total: $grand_total <td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td class=\"even\" colspan=" . $#header_array  . "> Transaction Count:  $trx_count <td>\n";
    print "  </tr>\n";
  }
  else {
    # do nothing...
  }

  if ($format eq "html") {
    &tail;
  }
}

sub get_resellername {
  my $result = "";

  my $sth_resell = $daily_reporting::dbh_pnpmisc->prepare(q{
      SELECT reseller
      FROM customers
      WHERE username=?
    }) or die "failed prepare $DBI::errstr\n";
  $sth_resell->execute("$daily_reporting::login") or die "failed execute $DBI::errstr";
  $result = $sth_resell->fetchrow;
  $sth_resell->finish;

  return $result;
}

sub card_type {
  my ($card_number) = @_;

  my $cardbin = substr($card_number,0,4);
  my $cardtype = "none";

  if ($cardbin =~ /^(4)/) {
    $cardtype = "VISA";
  }
  elsif ($cardbin =~ /^(51|52|53|54|55)/) {
    $cardtype = "MC";
  }
  elsif ($cardbin =~ /^(37|34)/) {
    $cardtype = "AMEX";
  }
#  elsif ($cardbin =~ /^(30|36|38[0-8])/) {
#    $cardtype = "DNRS";
#  }
  elsif ($cardbin =~ /^(389)/) {
    $cardtype = "CRTB";
  }
  elsif ($cardbin =~ /^(6011)/) {
    $cardtype = "DSCR";
  }
  elsif ($cardbin =~ /^(3528[0-9][0-9])/) {
    $cardtype = "JCB";
  }
  elsif ($cardbin =~ /^(1800|2131)/) {
    $cardtype = "JAL";
  }

  return $cardtype;
}

