package billing;
 
use CGI;
use DBI;
use miscutils;
use rsautils;
use PlugNPay::GatewayAccount;

sub new {
  my $type = shift;
  $query = new CGI;
  my @params = $query->param;
  foreach $param (@params) {
    $data{$param} = $query->param($param);
    if (($param =~ /delete$/) && ($data{$param} eq "delete")) {
      $di = substr($param,0,length($param) - 7);
      $dl{$di} = 1;
      @deletelist = (@deletelist,$di);
    }
  }
  if ($data{'discnt_feeid'} ne "250") {
    @deletelist = (@deletelist,'250');
  }
  foreach $key (keys %data) {
    #print "Key:$key:$data{$key}:<br>\n";
    if ($key =~ /^fixed_feeid/) {   
      my $tmp = $data{$key};
      my $tmp1 = "$tmp\_rate";
      my $tmp2 = $data{$tmp1};
      if (($tmp2 ne "") && ($dl{$tmp} != 1)) {
        @fixedfees = (@fixedfees,$tmp);
      }
    }
    if ($key =~ /^discnt_feeid/) {
      #print "<p>FFDFDFD<p>\n";

      my $tmp = $data{$key};
      my $tmp1 = "$tmp\_rate";
      my $tmp2 = $data{$tmp1};
      #print "T1:$tmp1 T2:$tmp2, AAAA:$dl{$tmp}<br>\n";

      if (($tmp2 ne "") && ($dl{$tmp} != 1)) {
        #print "AAA:$tmp\n";
        @discntfees = (@discntfees,$tmp);
      }
    }
  }
#  foreach $var (@fixedfees) {
#    print "$var<br>\n";
#  }

#  print "DELETE LIST<br>\n";
#  foreach $var (@deletelist) {
#    print "Delete:$tt:$var:<br>\n";
#  }

  $username = $data{'username'};
  $reseller = $ENV{'REMOTE_USER'};

  if (@deletelist > 0) {
    &delete_billing(@deletelist);
  }

  $data{'srchstartdate'} = $data{'startyear'} . $data{'startmon'} . $data{'startday'};
  $data{'srchenddate'} = $data{'endyear'} . $data{'endmon'} . $data{'endday'};

  local($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
  $yyear = $year+1900;
  $mmon = sprintf("%02d",$mon+1);

  %transfee = ('newauthfee','New Auth','recauthfee','Rec. Auth','returnfee','Return','fraudfee','Fraud Screen','cybersfee','Cybersource','voidfee','Void ','declinedfee','Declined Auth','discntfee','Discount Rate','resrvfee','Reserves','chargebck','Chargebacks');
  #my @transfee = keys %transfee; ###  No way to control order using this method.
  @transfee = ('newauthfee','recauthfee','declinedfee','returnfee','voidfee','fraudfee','cybersfee','discntfee','resrvfee','chargebck');


  @months = ('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec');
  %months = ('01','Jan','02','Feb','03','Mar','04','Apr','05','May','06','Jun','07','Jul','08','Aug','09','Sep','10','Oct','11','Nov','12','Dec');

  @days = ('01','02','03','04','05','06','07','08','09','10','11','12','13','14','15','16','17','18','19','20','21','22','23','24','25','26','27','28','29','30','31');

  $goodcolor = "#000000";
  $badcolor = "#ff0000";
  $backcolor = "#ffffff";
  $fontface = "Arial,Helvetica,Univers,Zurich BT";

  if ($source ne "private") {
  #  &auth(%data);
  }

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
  print "th { font-family: $fontface; font-size: 70%; color: #ffffff }\n";
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
  print "#badcard { position: static; color: red; border: solid red }\n";
  print ".info { position: static }\n";
  print "#tail { position: static }\n";
  print "-->\n";
  print "</style>\n";

  print "<script Language=\"Javascript\">\n";
  print "<!-- // Begin Script \n";

  print "function results() {\n";
  print "  resultsWindow = window.open(\"/payment/recurring/blank.html\",\"results\",\"menubar=yes,toolbar=yes,status=no,scrollbars=yes,resizable=yes,width=550,height=500\");\n";
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
  print "<tr><td align=\"center\" colspan=\"3\" bgcolor=\"#000000\" class=\"larger\"><font color=\"#ffffff\">Billing Module Administration Area</font></td></tr>\n";
  print "<tr><td align=\"center\" colspan=\"3\">&nbsp;</td></tr>\n";
  print "<tr><td align=\"left\" colspan=\"3\">\n";
  print "<form method=post action=\"/NAB/reports.cgi\" target=\"billing\">\n";
  print "<table border=0 cellspacing=0 cellpadding=4>\n";
  print "<tr><th align=\"left\" bgcolor=\"#4a7394\" colspan=2><font size=\"2\">Generate Invoice</font>\n";
  print "<tr><th valign=top align=left bgcolor=\"#4a7394\"><font color=\"#ffffff\">Start Date:</font></th>\n";
  print "<td align=left><select name=startmonth>\n";
  my (%selected);
  $selected{$mmon} = " selected";
  foreach $key (sort keys %months) {
    print "<option value=\"$key\" $selected{$key}>$months{$key}</option>\n";
  }
  print "</select>\n";
  print "<select name=\"startday\">\n";
  my (%selected);
  $selected{'01'} = "selected";
  foreach $var (@days) {
    print "<option value=\"$var\" $selected{$var}>$var</option>\n";
  }
  print "</select>\n";
  my (%selected);
  $selected{$yyear} = "selected";
  print "<select name=startyear>\n";
  for ($i=2000; $i<=2010; $i++) {
    print "<option $selected{$i}>$i</option>\n";
  }
  print "</select>\n";
  print "</td></tr>\n";
  print "<tr><th valign=top align=left bgcolor=\"#4a7394\"><font color=\"#ffffff\">End Date:</font></th>\n";
  print "<td align=left>\n";
  print "<select name=endmonth>\n";
  my (%selected);
  $selected{$mmon} = " selected";
  foreach $key (sort keys %months) {
    print "<option value=\"$key\" $selected{$key}>$months{$key}</option>\n";
  }
  print "</select>\n";
  print "<select name=\"endday\">\n";
  my (%selected);
  $selected{'31'} = "selected";
  foreach $var (@days) {
    print "<option value=\"$var\" $selected{$var}>$var</option>\n";
  }
  print "</select>\n";
  my (%selected);
  $selected{$yyear} = "selected";
  print "<select name=endyear>\n";
  for ($i=2000; $i<=2010; $i++) {
    print "<option $selected{$i}>$i</option>\n";
  }
  print "</select>\n";
  print "<input type=\"hidden\" name=\"mode\" value=\"billing\">\n";
  print "<input type=\"hidden\" name=\"subacct\" value=\"$data{'subacct'}\">\n";
  print "<input type=\"hidden\" name=\"merchant\" value=\"$username\">\n";
  print "</td></tr>\n";
  print "<tr><th valign=top align=left bgcolor=\"#4a7394\"><font color=\"#ffffff\">Format:</font></th>\n";
  print "<td align=left>\n";
  print "<input type=radio name=format value=table checked> Table <input type=radio name=format value=text> Text\n";
  print "</td></tr>\n";

  print "<tr><th valign=top align=left bgcolor=\"#4a7394\"><font color=\"#ffffff\">Generate Invoice:</font></th>\n";
  print "<td align=left><input type=submit name=submit value=\" Generate Invoice \" onClick=\"results();\"></form></td></tr>\n";
#  print "</table>\n";
#  print "</form>\n";
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

sub addfee {
  #print "Content-Type: text/html\n\n";
  if ($data{'subacct'} ne "") {
    $qstr = "select feeid,feetype,feedesc,rate,type from billing where username='$username' and subacct='$data{'subacct'}'";
  }
  else {
    $qstr = "select feeid,feetype,feedesc,rate,type from billing where username='$username'";
  }

  $dbh = &miscutils::dbhconnect('merch_info');
  my $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
  $sth->execute() or die "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($db{'feeid'},$db{'feetype'},$db{'desc'},$db{'rate'},$db{'type'}));
  while ($sth->fetch) {
    #print "UN:$username, ID:$db{'feeid'},TYPE:$db{'feetype'},DESC:$db{'desc'},RATE:$db{'rate'},TYPE:$db{'type'}<br>\n";
    $feeid = $db{'feeid'};
    @feelist = (@feelist,$feeid);
    $$feeid{'feetype'} = $db{'feetype'};
    $$feeid{'desc'} = $db{'desc'};
    $$feeid{'rate'} = $db{'rate'};
    $$feeid{'type'} = $db{'type'};
    if ($db{'feetype'} eq "fixed") {
      @fixedlist = (@fixedlist,$feeid);
    }
    elsif ($db{'feetype'} eq "discntfee") {
      $discntflag = " checked";
      @discntlist = (@discntlist,$feeid);
    }

    $$feeid{$db{'type'}} = "checked";
  }
  $sth->finish;
  $dbh->disconnect;

  &report_head();

  
  #my %transfee = ('newauthfee','New Auth','recauthfee','Rec. Auth','returnfee','Return','fraudfee','Fraud Screen','cybersfee','Cybersource','voidfee','Void ','declinedfee','Declined Auth','discntfee','Discount Rate','resrvfee','Reserves');
  #my @transfee = keys %transfee; ###  No way to control order using this method.
  #my @transfee = ('newauthfee','recauthfee','declinedfee','returnfee','voidfee','fraudfee','cybersfee','discntfee','resrvfee');


  print "<tr><th align=\"left\" bgcolor=\"#4a7394\" colspan=2><font size=\"2\">Set Rates</font>\n";
  print "<form name=\"addfee\" method=post action=\"billing.cgi\" target=\"\"><input type=\"hidden\" name=\"mode\" value=\"updatefee\">\n";
  print "<input type=\"hidden\" name=\"username\" value=\"$username\"><input type=\"hidden\" name=\"subacct\" value=\"$data{'subacct'}\"></th></tr>\n";
#  print "<table>\n";
  print "<tr><th align=\"left\" bgcolor=\"#4a7394\">Discount Program</font></th></tr>\n";

  $selected{'250'} = " checked";
  print "<tr><th align=\"right\" bgcolor=\"#4a7394\">Free 250:</th><td align=\"left\"> <input type=\"checkbox\" name=\"discnt_feeid\" value=\"250\" $discntflag> Not yet functional\n";
  print "<input type=\"hidden\" name=\"250_rate\" value=\"250\">\n";

  print "</td></tr>\n";

  print "<tr><th align=\"left\" bgcolor=\"#4a7394\">Transaction Fees</font></th></tr>\n";

  foreach $key (@transfee) {
    $typelabel = $key . "type";
    print "<tr><th align=\"right\" bgcolor=\"#4a7394\">$transfee{$key}:</th><td align=\"left\"> <input type=\"text\" name=\"$key\" value=\"$$key{'rate'}\" size=\"5\" maxlength=\"5\">\n";
    if ($key !~ /discntfee|resrvfee/) {
      print "<input type=\"radio\" name=\"$typelabel\" value=\"pertran\" $$key{'pertran'}> Pertran \n";
    }
    else {
      $$key{'percent'} = " checked";
    }
    print "<input type=\"radio\" name=\"$typelabel\" value=\"percent\" $$key{'percent'}> Percent </td></tr>\n";
  }

#  print "<tr><th align=\"right\" bgcolor=\"#4a7394\">New Auths:</th><td align=\"left\"> <input type=\"text\" name=\"newauthfee\" value=\"$newauthfee{'rate'}\" size=\"5\" maxlength=\"5\">\n";
#  print "<input type=\"radio\" name=\"newauthfeetype\" value=\"pertran\" $newauthfee{'pertran'}> Pertran <input type=\"radio\" name=\"newauthfeetype\" value=\"percent\" $newauthfee{'percent'}> Percent </td></tr>\n";
#  print "<tr><th align=\"right\" bgcolor=\"#4a7394\">Rec Auths:</th><td align=\"left\"> <input type=\"text\" name=\"recauthfee\" value=\"$recauthfee{'rate'}\" size=\"5\" maxlength=\"5\">\n";
#  print "<input type=\"radio\" name=\"recauthfeetype\" value=\"pertran\" checked> Pertran <input type=\"radio\" name=\"recauthfeetype\" value=\"percent\"> Percent </td></tr>\n";
#  print "<tr><th align=\"right\" bgcolor=\"#4a7394\">Declined Auths:</th><td align=\"left\"> <input type=\"text\" name=\"declinedfee\" value=\"$declinedfee{'rate'}\" size=\"5\" maxlength=\"5\">\n";
#  print "<input type=\"radio\" name=\"declinedfeetype\" value=\"pertran\" checked> Pertran <input type=\"radio\" name=\"declinedfeetype\" value=\"percent\"> Percent </td></tr>\n";
#  print "<tr><th align=\"right\" bgcolor=\"#4a7394\">Returns:</th><td align=\"left\"> <input type=\"text\" name=\"returnfee\" value=\"$returnfee{'rate'}\" size=\"5\" maxlength=\"5\">\n";
#  print "<input type=\"radio\" name=\"returnfeetype\" value=\"pertran\" checked> Pertran <input type=\"radio\" name=\"returnfeetype\" value=\"percent\"> Percent </td></tr>\n";
#  print "<tr><th align=\"right\" bgcolor=\"#4a7394\">Fraud Screen:</th><td align=\"left\"> <input type=\"text\" name=\"fraudfee\" value=\"$fraudfee{'rate'}\" size=\"5\" maxlength=\"5\">\n";
#  print "<input type=\"radio\" name=\"fraudfeetype\" value=\"pertran\" checked> Pertran <input type=\"radio\" name=\"fraudfeetype\" value=\"percent\"> Percent </td></tr>\n";
#  print "<tr><th align=\"right\" bgcolor=\"#4a7394\">Void:</th><td align=\"left\"> <input type=\"text\" name=\"voidfee\" value=\"$voidfee{'rate'}\" size=\"5\" maxlength=\"5\">\n";
#  print "<input type=\"radio\" name=\"voidfeetype\" value=\"pertran\" checked> Pertran <input type=\"radio\" name=\"voidfeetype\" value=\"percent\"> Percent </td></tr>\n";
#  print "<tr><th align=\"right\" bgcolor=\"#4a7394\">CyberSource:</th><td align=\"left\"> <input type=\"text\" name=\"cybersfee\" value=\"$cybersfee{'rate'}\" size=\"5\" maxlength=\"5\">\n";
#  print "<input type=\"radio\" name=\"cybersfeetype\" value=\"pertran\" checked> Pertran <input type=\"radio\" name=\"cybersfeetype\" value=\"percent\"> Percent </td></tr>\n";
#  print "<tr><th align=\"right\" bgcolor=\"#4a7394\">Discount Rate:</th><td align=\"left\"> <input type=\"text\" name=\"discntfee\" value=\"$discntfee{'rate'}\" size=\"5\" maxlength=\"5\">\n";
#  print "<input type=\"radio\" name=\"discntfeetype\" value=\"percent\" checked> Percent </td></tr>\n";

  print "<tr><th align=\"left\" bgcolor=\"#4a7394\">Fixed Monthly Fees</th></tr>\n";
  foreach $var (@fixedlist) {
  #  print "VAR:$var<br>\n";
    $i++;
    print "<tr><th align=\"right\" bgcolor=\"#4a7394\">Rate:</th><td align=\"left\"><input type=\"text\" name=\"$var\_rate\" value=\"$$var{'rate'}\" size=\"5\" maxlength=\"5\"></td></tr>";
    print "<tr><th align=\"right\" bgcolor=\"#4a7394\">Description:</th><td align=\"left\"><input type=\"text\" name=\"$var\_desc\" value=\"$$var{'desc'}\" size=\"25\" maxlength=\"25\">\n";
    print "<input type=\"hidden\" name=\"fixed_feeid_$i\" value=\"$var\">";
    print "<input type=\"checkbox\" name=\"$var\_delete\" value=\"delete\"> Delete</td></tr>\n";
  }
  $i++;
  print "<tr><th align=\"left\" bgcolor=\"#4a7394\">Add Fixed Monthly Fees</th></tr>\n";
  print "<tr><th align=\"right\" bgcolor=\"#4a7394\">Rate:</th><td align=\"left\"><input type=\"text\" name=\"fixed_$i\_rate\" value=\"\" size=\"5\" maxlength=\"5\"></td></tr>";
  print "<tr><th align=\"right\" bgcolor=\"#4a7394\">Description:</th><td align=\"left\"><input type=\"text\" name=\"fixed_$i\_desc\" value=\"\" size=\"25\" maxlength=\"25\">\n";
  print "<input type=\"hidden\" name=\"fixed_feeid\" value=\"fixed_$i\"><input type=\"hidden\" name=\"subacct\" value=\"$data{'subacct'}\"></td></tr>";

  print "<tr><td colspan=2><input type=\"submit\" value=\"Submit Form\"> <input type=\"reset\" value=\"Reset Form\"></td></tr>\n";
  print "</table>\n";
  print "</form><p>\n";
  &report_tail();

}


sub updatefee {
  #my %transfee = ('newauthfee','New Authorization','recauthfee','Recurring Authorization','returnfee','Return','fraudfee','Fraud Screen','creditfee','Credit','cybersfee','Cybersource Fraud Screen','voidfee','Voided Transactions','declinedfee','Declined Auhtorizations','discntfee','Discount Rate');
  my $dbh = &miscutils::dbhconnect("merch_info");
  foreach $fee (keys %transfee) {
    $type = $data{$fee . "type"};
    $type =~ s/[^a-z]//g;
    $rate = $data{$fee};
    $rate =~ s/[^0-9\.]//g;

    if ($data{'subacct'} ne "") {
      $qstr = "select feeid from billing where username='$username' and feeid='$fee' and subacct='$data{'subacct'}'";
    }
    else {
      $qstr = "select feeid from billing where username='$username' and feeid='$fee'";
    }


    my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
    $sth->execute or die "Can't execute: $DBI::errstr";
    my ($test) = $sth->fetchrow;
    $sth->finish;
    if ($test ne "") {
      if ($data{'subacct'} ne "") {
        $qstr = "update billing set feetype=?,feedesc=?,rate=?,type=? where username='$username' and feeid='$fee' and subacct='$data{'subacct'}'";
      }
      else {
        $qstr = "update billing set feetype=?,feedesc=?,rate=?,type=? where username='$username' and feeid='$fee'";
      }
      #print "TRANSUPDATE: UN:$username<br>\n";
      my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
      $sth->execute("$fee","$transfees{$fee}","$rate","$type")
                   or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
      $sth->finish;
    }
    else {
      #print "TRANSINSERT: UN:$username, FEE:$fee, RATE:$data{$fee}<br>\n";
      my $sth = $dbh->prepare(qq{
          insert into billing
          (username,feeid,feetype,feedesc,rate,type,subacct)
          values (?,?,?,?,?,?,?)
          }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
      $sth->execute("$username","$fee","$fee","$transfees{$fee}","$data{$fee}","$type","$data{'subacct'}")
                   or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
      $sth->finish;
    }
  }
  foreach $fee (@fixedfees) {
    #print "FEE:$fee<br>\n";
    $desc = $data{"$fee\_desc"};
    $rate = $data{"$fee\_rate"};

    if ($data{'subacct'} ne "") {
      $qstr = "select feeid from billing where username='$username' and feeid='$fee' and subacct='$data{'subacct'}'";
    }
    else {
      $qstr = "select feeid from billing where username='$username' and feeid='$fee'";
    }


    my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
    $sth->execute or die "Can't execute: $DBI::errstr";
    my ($test) = $sth->fetchrow;
    $sth->finish;

    if ($test ne "") {
     # print "UPDATE FEE:$fee, DESC:$desc, RATE:$rate<br>\n";
      if ($data{'subacct'} ne "") {
        $qstr = "update billing set feetype=?,feedesc=?,rate=?,type=? where username='$username' and feeid='$fee' and subacct='$data{'subacct'}'";
      }
      else {
        $qstr = "update billing set feetype=?,feedesc=?,rate=?,type=? where username='$username' and feeid='$fee'";
      }

      my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
      $sth->execute("fixed","$desc","$rate","monthly")
                   or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
      $sth->finish;
    }
    else {
      #print "INSERT FEE:$fee, DESC:$desc, RATE:$rate<br>\n";
      my $sth = $dbh->prepare(qq{
          insert into billing
          (username,feeid,feetype,feedesc,rate,type,subacct)
          values (?,?,?,?,?,?,?)
          }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
      $sth->execute("$username","$fee","fixed","$desc","$rate","monthly","$data{'subacct'}")
                   or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
      $sth->finish;
    }
  }

  foreach $fee (@discntfees) {
    print "FEE:$fee<br>\n";
    $desc = $data{"$fee\_desc"};
    $rate = $data{"$fee\_rate"};
 
    if ($data{'subacct'} ne "") {
      $qstr = "select feeid from billing where username='$username' and feeid='$fee' and subacct='$data{'subacct'}'";
    }
    else {
      $qstr = "select feeid from billing where username='$username' and feeid='$fee'";
    }
 
 
    my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
    $sth->execute or die "Can't execute: $DBI::errstr";
    my ($test) = $sth->fetchrow;
    $sth->finish;
 
    if ($test ne "") {
      #print "UPDATE FEE:$fee, DESC:$desc, RATE:$rate<br>\n";
      if ($data{'subacct'} ne "") {
        $qstr = "update billing set feetype=?,feedesc=?,rate=?,type=? where username='$username' and feeid='$fee' and subacct='$data{'subacct'}'";
      }
      else {
        $qstr = "update billing set feetype=?,feedesc=?,rate=?,type=? where username='$username' and feeid='$fee'";
      }
 
      my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
      $sth->execute("discnt","$desc","$rate","discnt")
                   or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
      $sth->finish;
    }
    else {
      #print "INSERT FEE:$fee, DESC:$desc, RATE:$rate<br>\n";
      my $sth = $dbh->prepare(qq{
          insert into billing
          (username,feeid,feetype,feedesc,rate,type,subacct)
          values (?,?,?,?,?,?,?)
          }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
      $sth->execute("$username","$fee","discnt","$desc","$rate","discnt","$data{'subacct'}")
                   or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
      $sth->finish;
    }
  }

  $dbh->disconnect;
  #&addfee();
  if ($data{'client'} eq "remote") {
    print "FinalStatus=success\n";
  }
}


sub response_page {
  my($message) = @_;
  print "<html><Head><title>Response Page</title></head>\n";
  print "<style type=\"text/css\">\n";
  print "<!--\n";
  print "th { font-family: $fontface; font-size: 75%; color: $goodcolor }\n";
  print "td { font-family: $fontface; font-size: 75%; color: $goodcolor }\n";
  print ".badcolor { color: $badcolor }\n";
  print ".goodcolor { color: $goodcolor }\n";
  print ".larger { font-size: 100% }\n";
  print ".smaller { font-size: 60% }\n";
  print ".short { font-size: 8% }\n";
  print ".button { font-size: 75% }\n";
  print ".itemscolor { background-color: $goodcolor; color: $backcolor }\n";
  print ".itemrows { background-color: #d0d0d0 }\n";
  print ".items { position: static }\n";
  print ".info { position: static }\n";
  print "-->\n";
  print "</style>\n\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"stylesheet.css\">\n";
  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";
  print "<table border=\"0\" cellspacing=\"0\" cellpadding=\"1\" width=\"500\">\n";
  print "<tr><td align=\"center\" colspan=\"4\"><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corporate Logo\"></td></tr>\n";
  print "<tr><td align=\"center\" colspan=\"4\" class=\"larger\" bgcolor=\"#000000\"><font color=\"#ffffff\">Reseller Administration Area</font></td></tr>\n";
  print "<tr><td align=\"center\" colspan=\"4\"><img src=\"/images/icons.gif\" alt=\"The PowertoSell\"></td></tr>\n";
  print "<tr><td>&nbsp;</td><td>&nbsp;</td><td colspan=2>&nbsp;</td></tr>\n";
  print "<tr><td colspan=\"4\">$message</td></tr>\n";

  print "</table>\n";
  print "</body>\n";
  print "</html>\n";

}

sub delete_billing {
  my (@deletelist) = @_;
  my $dbh = &miscutils::dbhconnect("merch_info");
  foreach $var (@deletelist) {
    #print "DELETE VAR:$var:$username:<br>\n";
    if ($data{'subacct'} ne "") {
      $qstr = "delete from billing where username='$username' and feeid='$var' and subacct='$data{'subacct'}'";
    }
    else {
      $qstr = "delete from billing where username='$username' and feeid='$var'";
    }

    my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
    $sth->execute or die "Can't execute: $DBI::errstr";
    $sth->finish;
  }

  $dbh->disconnect;
}


1;
