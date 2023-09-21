package billing;
 
use CGI;
use DBI;
use miscutils;
use rsautils;
use PlugNPay::GatewayAccount;

sub new {
  my $type = shift;

  my (%dlist,%dfixedlist,$dflag,$dfixedflag);

  $query = new CGI;
  my @params = $query->param;
  foreach $param (@params) {
    $data{$param} = $query->param($param);
    #print "PARAM:$param:$data{$param}<br>\n";
    if (($param =~ /([a-zA-Z]+)(\d+)_delete$/) && ($data{$param} eq "delete")) {
      $dlist{"$1:$2"} = $2;
      $dflag = 1;
      #print "DELETEEE:$1:$2<br>\n";
    }
    elsif (($param =~ /(fixed_\d+)_delete$/) && ($data{$param} eq "delete")) {
      $dfixedlist{$1} = 1;
      $dfixedflag = 1;
      #print "DELETEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE<br>\n";
    }
    elsif (($param =~ /(minimum)_delete$/) && ($data{$param} eq "delete")) {
      $dfixedlist{$1} = 1;
      $dfixedflag = 1;
      #print "DELETEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE<br>\n";
    }
    if (($param =~ /([a-zA-Z]+)(\d+)_update$/) && ($data{$param} eq "update")) {
      $uplist{"$1:$2"} = $2;
      $upflag = 1;
      $data{'mode'} = "addfee";
      print "UPDATE:$1:$2<br>\n";
    }
  }
  foreach $key (keys %data) {
    if ($key =~ /^fixed_feeid/) {   
      my $tmp = $data{$key};
      my $tmp1 = "$tmp\_rate";
      my $tmp2 = $data{$tmp1};
      if (($tmp2 ne "") && ($dl{$tmp} != 1)) {
        @fixedfees = (@fixedfees,$tmp);
      }
    }
    elsif ($key =~ /^minimum_feeid/) {
      my $tmp = $data{$key};
      my $tmp1 = "$tmp\_rate";
      my $tmp2 = $data{$tmp1};

      #print "DFD:T:$tmp, T1:$tmp1, T2:$tmp2, DL:$dl{$tmp}<br>\n";

      if (($tmp2 ne "") && ($dl{$tmp} != 1)) {
        @minimumfees = (@minimumfees,$tmp);
      }
    }
  }
#  @fixedfees = (@fixedfees,@minimumfees);

#  foreach $var (@fixedfees) {
#    print "$var<br>\n";
#  }

#  print "DELETE LIST<br>\n";
#  foreach $var (@deletelist) {
#    print "Delete:$tt:$var:<br>\n";
#  }

  $username = $data{'username'};
  $reseller = $ENV{'REMOTE_USER'};

  if ($dflag == 1) {
    &delete_billing(\%dlist);
  }
  elsif ($upflag ==1) {
    &update_billing(\%uplist);
  }

  if ($dfixedflag == 1) {
    &delete_fixed_billing(\%dfixedlist);
  }

  $data{'srchstartdate'} = $data{'startyear'} . $data{'startmon'} . $data{'startday'};
  $data{'srchenddate'} = $data{'endyear'} . $data{'endmon'} . $data{'endday'};

  local($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
  $yyear = $year+1900;
  $mmon = sprintf("%02d",$mon+1);

  %transfee = ('authfee','Auth','returnfee','Return','fraudfee','Fraud Screen','cybersfee','Cybersource','voidfee','Void','achfee','ACH');
  #my @transfee = keys %transfee; ###  No way to control order using this method.
  @transfee = ('authfee','returnfee','voidfee','fraudfee','cybersfee','achfee');


  @months = ('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec');
  %months = ('01','Jan','02','Feb','03','Mar','04','Apr','05','May','06','Jun','07','Jul','08','Aug','09','Sep','10','Oct','11','Nov','12','Dec');

  @days = ('01','02','03','04','05','06','07','08','09','10','11','12','13','14','15','16','17','18','19','20','21','22','23','24','25','26','27','28','29','30','31');

  %rate_blocks = ('0','0','100','100','250','250','500','500','1000','1,000','2000','2,000','3000','3,000','4000','4,000','5000','5,000','6000','6,000','7000','7,000','8000','8,000','9000','9,000','10000','10,000','20000','20,000','30000','30,000','40000','40,000','50000','50,000','60000','60,000','70000','70,000','80000','80,000','90000','90,000','100000','100,000','200000','200,000','300000','300,000','400000','400,000','500000','500,000','1000000','1,000,000','100000000','unlimited');


  @rate_blocks = keys %rate_blocks;
  @rate_blocks = sort { $a <=> $b } @rate_blocks;

  $i = 0;
  foreach $var (@rate_blocks) {
    $rateidx{$var} = $i;
    $i++;
  }

  $goodcolor = "#000000";
  $badcolor = "#ff0000";
  $backcolor = "#ffffff";
  $fontface = "Arial,Helvetica,Univers,Zurich BT";

  if ($source ne "private") {
    &auth(%data);
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

  #print "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFFDFDFDFDFDFDFDFDF<p>\n";
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

  print "<table border=\"0\" cellspacing=\"1\" cellpadding=\"0\" width=\"640\">\n";
  print "<tr><td align=\"center\" colspan=\"3\"><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corporate Logo\"></td></tr>\n";
  print "<tr><td align=\"center\" colspan=\"3\" bgcolor=\"#000000\" class=\"larger\"><font color=\"#ffffff\">Billing Module Administration Area</font></td></tr>\n";
  print "<tr><td align=\"center\" colspan=\"3\">&nbsp;</td></tr>\n";
  print "<tr><td align=\"left\" colspan=\"3\">\n";
}

sub generate_invoice {
  print "<form method=post action=\"/NAB/reports.cgi\" target=\"results\">\n";
  print "<table border=0 cellspacing=0 cellpadding=4>\n";
  print "<tr><th align=\"left\" bgcolor=\"#4a7394\" colspan=2><font size=\"2\">Generate Invoice</font>\n";
  print "<tr><th valign=top align=left bgcolor=\"#4a7394\"><font color=\"#ffffff\">Start Date:</font></th>\n";
  print "<td align=left><select name=startmonth>\n";
  $selected{$months{$mmon}} = " selected";
  foreach $var (@months) {
    print "<option $selected{$var}>$var</option>\n";
  }
  print "</select>\n";
  print "<select name=\"startday\">\n";
  $selected{'01'} = "selected";
  foreach $var (@days) {
    print "<option value=\"$var\" $selected{$var}>$var</option>\n";
  }
  print "</select>\n";
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
  $selected{$months{$mmon}} = " selected";
  foreach $var (@months) {
    print "<option $selected{$var}>$var</option>\n";
  }
  print "</select>\n";
  print "<select name=\"endday\">\n";
  $selected{'31'} = "selected";
  foreach $var (@days) {
    print "<option value=\"$var\" $selected{$var}>$var</option>\n";
  }
  print "</select>\n";
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
  print "<tr><th valign=top align=left bgcolor=\"#4a7394\"><font color=\"#ffffff\">Generate Invoice:</font></th>\n";
  print "<td align=left><input type=submit name=submit value=\" Generate Invoice \" onClick=\"results();\"></form></td></tr>\n";
  print "</table>\n";
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
    $qstr = "select feeid,feetype,feedesc,rate,buyrate,type,startblk,endblk from billing where username='$username' and subacct='$data{'subacct'}'";
  }
  else {
    $qstr = "select feeid,feetype,feedesc,rate,buyrate,type,startblk,endblk from billing where username='$username'";
  }

  #$qstr .= " order by startblk";

  $dbh = &miscutils::dbhconnect('misccrap');
  my $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
  $sth->execute() or die "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($db{'feeid'},$db{'feetype'},$db{'desc'},$db{'rate'},$db{'buyrate'},$db{'type'},$db{'startblk'},$db{'endblk'}));
  while ($sth->fetch) {
    #my ($rate,$buyrate,$start,$end) = split('\|',$db{'rate'});
    #print "UN:$username, ID:$db{'feeid'},FEETYPE:$db{'feetype'},DESC:$db{'desc'},RATE:$db{'rate'},BUYRATE:$db{'buyrate'},TYPE:$db{'type'},START:$db{'startblk'},END:$db{'endblk'}<br>\n";
    $feeid = $db{'feeid'} . $db{'startblk'};
    #@feelist = (@feelist,$feeid);
    $$feeid{'feetype'} = $db{'feetype'};
    $$feeid{'desc'} = $db{'desc'};
    $$feeid{'rate'} = $db{'rate'};
    $$feeid{'buyrate'} = $db{'buyrate'};
    $$feeid{'type'} = $db{'type'};
    if ($db{'feetype'} eq "fixed") {
      @fixedlist = (@fixedlist,$feeid);
    }
    else {
      $defaulttype = $db{'type'};
      @feelist = (@feelist,$feeid);
    }
    $$feeid{'startblk'} = $db{'startblk'};
    $$feeid{'endblk'} = $db{'endblk'};
    $$feeid{$db{'type'}} = "checked";
    $type = $db{'feetype'};
    push (@$type,$db{'startblk'});
    if ($db{'startblk'} > $$feeid{'maxstart'}) {
      $$feeid{'maxstart'} = $db{'startblk'};
    }
  }
  $sth->finish;
  $dbh->disconnect;

  if ($defaulttype eq "") {
    $defaulttype = "pertran";
  }

  &report_head();
  #&generate_invoice();
  
  print "<table border=1>\n";
  print "<tr><th align=\"left\" bgcolor=\"#4a7394\" colspan=6><font size=\"2\">Set Rates</font>\n";
  print "<form name=\"addfee\" method=post action=\"billing_pnp.cgi\" target=\"\"><input type=\"hidden\" name=\"mode\" value=\"updatefee\">\n";
  print "<input type=\"hidden\" name=\"username\" value=\"$username\"><input type=\"hidden\" name=\"subacct\" value=\"$data{'subacct'}\"></th></tr>\n";
#  print "<table>\n";
  print "<tr><th align=\"left\" bgcolor=\"#4a7394\">Transaction Fees</font></th>\n";
  print "<td>";
  $selected{$defaulttype} = " checked";
  print "<input type=\"radio\" name=\"feetype\" value=\"pertran\" $selected{'pertran'}> \# &nbsp; &nbsp;\n";
  print "<input type=\"radio\" name=\"feetype\" value=\"percent\" $selected{'percent'}> \% </td>\n";

  print "<tr><th bgcolor=\"#4a7394\">&nbsp;</th><td>Billed Rate</td><td>Buy Rate</td><td>Rate Type</td><td>Start Cnt Blk</td><td width=50>Action</td></tr>\n";

  foreach $key (@transfee) {
    my ($blkflag);
    @tmparray = @$key;
    @tmp2 = sort sort_numeric @tmparray;
    foreach my $var (@tmp2) {
      #print "VAR:$var<br>\n";
      if ($var eq "") {
        $var = 0;
      }
      $blkflag = 1;
      $feeid = $key . $var;
      $typelabel = $feeid . "type";
      #print "<tr><th align=\"right\" bgcolor=\"#4a7394\">$transfee{$key}:</th><td align=\"left\"> $$feeid{'rate'}</td>\n";
      #print "<td align=\"left\"> $$feeid{'buyrate'}</td>\n";
      #print "<td align=\"left\"> $$feeid{'type'}</td>\n";
      #print "<td align=\"right\"> $$feeid{'startblk'}</td>\n";
      #print "<td align=\"left\"> <input type=\"checkbox\" name=\"$feeid\_delete\" value=\"delete\"> Delete</td>\n";
      #print "</tr>\n";
      print "<tr><th align=\"right\" bgcolor=\"#4a7394\">$transfee{$key}:</th>\n";
      print "<td align=\"left\"> <input type=\"text\" name=\"$feeid\_rate\" value=\"$$feeid{'rate'}\" size=\"5\" maxlength=\"5\"></td>\n";
      print "<td align=\"left\"> <input type=\"text\" name=\"$feeid\_buyrate\" value=\"$$feeid{'buyrate'}\"  size=\"5\" maxlength=\"5\"></td>\n";
      print "<td align=\"left\"> $$feeid{'type'}</td>\n";
      if ($$feeid{'startblk'} == 0) {
        print "<td align=\"right\">0<input type=\"hidden\" name=\"$feeid\_start\" value=\"0\"><input type=\"hidden\" name=\"$feeid\_newstart\" value=\"0\"></td>\n";
      }
      else {
        print "<td align=\"right\"> <input type=\"text\" name=\"$feeid\_newstart\" value=\"$$feeid{'startblk'}\"  size=\"5\" maxlength=\"5\">\n";
        print "<input type=\"hidden\" name=\"$feeid\_start\" value=\"$$feeid{'startblk'}\"></td>\n";
      }
      #if ($$feeid{'startblk'} == 0) {
      #  print "<td align=\"left\"><input type=\"checkbox\" name=\"$feeid\_update\" value=\"update\"> Update </td>\n";
      #}
      #else {
        print "<td align=\"left\"> <input type=\"checkbox\" name=\"$feeid\_update\" value=\"update\"> Update\n";
        print " <input type=\"checkbox\" name=\"$feeid\_delete\" value=\"delete\"> Delete</td>\n";
      #}
      print "</tr>\n";

    }
    $typelabel = $key . "type";
    print "<tr><th align=\"right\" bgcolor=\"#4a7394\">$transfee{$key}:</th><td align=\"left\"> <input type=\"text\" name=\"$key\_rate\" value=\"$$key{'rate'}\" size=\"5\" maxlength=\"5\"></td>\n";
    print "<td align=\"left\"> <input type=\"text\" name=\"$key\_buyrate\" value=\"$$key{'buyrate'}\" size=\"5\" maxlength=\"5\"></td>\n";
    print "<td align=\"left\">\n";
    print "\&nbsp;";
    print "</td>\n";
    print "<td align=\"left\"> <select name=\"$key\_start\">\n";
    if (@$key < 1) {
      print "<option value=\"0\">0</option>\n";
    }
    else {
      foreach my $var (@rate_blocks) {
        if ($var == 0) {
        #  next;
        }
        print "<option value=\"$var\">$rate_blocks{$var}</option>\n";
      }
    }
    print "</select></td>\n";
    print "</tr>\n";

  }

  print "<tr><th align=\"left\" bgcolor=\"#4a7394\">Monthly Minimun Fees</th></tr>\n";
  print "<tr><th bgcolor=\"#4a7394\">&nbsp;</th><td>Billed Rate</td><td>Buy Rate</td></tr>\n";

  print "<tr><th align=\"right\" bgcolor=\"#4a7394\">Rate:</th>\n"; 
  print "<td align=\"left\"><input type=\"text\" name=\"minimum_rate\" value=\"$minimum{'rate'}\" size=\"5\" maxlength=\"5\"></td>
\n"; 
  print "<td align=\"left\"><input type=\"text\" name=\"minimum_buyrate\" value=\"$minimum{'buyrate'}\" size=\"5\" maxlength=\"5\"
></td></tr>"; 
  print "<tr><th align=\"right\" bgcolor=\"#4a7394\" colspan=1>Description:</th><td align=\"left\" colspan=5>Monthly Minimum <input type=\"hidden\" name=\"minimum_desc\" value=\"Monthly Minimum\">\n";
  print "<input type=\"hidden\" name=\"minimum_feeid\" value=\"minimum\">";
  print "<input type=\"checkbox\" name=\"minimum_delete\" value=\"delete\"> Delete</td></tr>\n";

  print "<tr><th align=\"left\" bgcolor=\"#4a7394\">Fixed Monthly Fees</th></tr>\n";
  print "<tr><th bgcolor=\"#4a7394\">&nbsp;</th><td>Billed Rate</td><td>Buy Rate</td></tr>\n";

  my ($i);
  foreach $var (@fixedlist) {
  #  print "VAR:$var<br>\n";
    $i++;
    print "<tr><th align=\"right\" bgcolor=\"#4a7394\">Rate:</th>\n";
    print "<td align=\"left\"><input type=\"text\" name=\"$var\_rate\" value=\"$$var{'rate'}\" size=\"5\" maxlength=\"5\"></td>\n";
    print "<td align=\"left\"><input type=\"text\" name=\"$var\_buyrate\" value=\"$$var{'buyrate'}\" size=\"5\" maxlength=\"5\"></td></tr>";
    print "<tr><th align=\"right\" bgcolor=\"#4a7394\" colspan=1>Description:</th><td align=\"left\" colspan=5><input type=\"text\" name=\"$var\_desc\" value=\"$$var{'desc'}\" size=\"25\" maxlength=\"25\">\n";
    #print "<input type=\"hidden\" name=\"fixed_feeid_$i\" value=\"$var\">";
    print "<input type=\"checkbox\" name=\"$var\_delete\" value=\"delete\"> Delete</td></tr>\n";
  }
  $i++;
  print "<tr><th align=\"left\" bgcolor=\"#4a7394\">Add Fixed Monthly Fees</th></tr>\n";
  print "<tr><th align=\"right\" bgcolor=\"#4a7394\">Rate:</th><td align=\"left\"><input type=\"text\" name=\"fixed_$i\_rate\" value=\"\" size=\"5\" maxlength=\"5\"></td><td><input type=\"text\" name=\"fixed_$i\_buyrate\" value=\"\" size=\"5\" maxlength=\"5\"></td></tr>\n";
  print "<tr><th align=\"right\" bgcolor=\"#4a7394\">Description:</th><td align=\"left\" colspan=5><input type=\"text\" name=\"fixed_$i\_desc\" value=\"\" size=\"25\" maxlength=\"25\">\n";
  print "<input type=\"hidden\" name=\"fixed_feeid\" value=\"fixed_$i\"><input type=\"hidden\" name=\"subacct\" value=\"$data{'subacct'}\"></td></tr>";

  print "<tr><td colspan=2><input type=\"submit\" value=\"Submit Form\"> <input type=\"reset\" value=\"Reset Form\"></td></tr>\n";
  print "</table>\n";
  print "</form><p>\n";
  &report_tail();

}


sub updatefee {
  #my %transfee = ('newauthfee','New Authorization','recauthfee','Recurring Authorization','returnfee','Return','fraudfee','Fraud Screen','creditfee','Credit','cybersfee','Cybersource Fraud Screen','voidfee','Voided Transactions','declinedfee','Declined Auhtorizations','discntfee','Discount Rate');

  #print "UPDATE FEES<p>\n";


  my $dbh = &miscutils::dbhconnect('misccrap');
  foreach $fee (keys %transfee) {
    $rate = $data{"$fee\_rate"};
    $rate =~ s/[^0-9\.]//g;
    if ($rate eq "") {
      next;
    }

    $type = $data{'feetype'};
    $type =~ s/[^a-z]//g;
    $buyrate = $data{"$fee\_buyrate"};
    $buyrate =~ s/[^0-9\.]//g;
    $startblk = $data{"$fee\_start"}; 
    $startblk =~ s/[^0-9\.]//g;
    $endblk = $data{"$fee\_end"};
    $endblk =~ s/[^0-9\.]//g;

    if ($data{'subacct'} ne "") {
      $qstr = "select feeid from billing where username='$username' and feeid='$fee' and startblk='$startblk' and subacct='$data{'subacct'}'";
    }
    else {
      $qstr = "select feeid from billing where username='$username' and feeid='$fee' and startblk='$startblk'";
    }

    my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
    $sth->execute or die "Can't execute: $DBI::errstr";
    my ($test) = $sth->fetchrow;
    $sth->finish;
    if ($test ne "") {
      if ($data{'subacct'} ne "") {
        $qstr = "update billing set feetype=?,feedesc=?,rate=?,buyrate=?,type=?,startblk=?,endblk=? where username='$username' and feeid='$fee' and startblk='$startblk' and subacct='$data{'subacct'}'";
      }
      else {
        $qstr = "update billing set feetype=?,feedesc=?,rate=?,buyrate=?,type=?,startblk=?,endblk=? where username='$username' and feeid='$fee' and startblk='$startblk'";
      }
      #print "TRANSUPDATE: UN:$username, FEEID:$fee, FEETYPE:$fee, FEEDESC:$transfees{$fee}, RATE:$rate, BUYRATE:$buyrate, TYPE:$type, START:$startblk, END:$endblk<br>\n";
      my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
      $sth->execute("$fee","$transfees{$fee}","$rate","$buyrate","$type","$startblk","$endblk")
                   or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
      $sth->finish;
    }
    else {
      #print "TRANSINSERT: UN:$username, FEEID:$fee, FEETYPE:$fee, FEEDESC:$transfees{$fee}, RATE:$rate, BUYRATE:$buyrate, TYPE:$type, START:$startblk, END:$endblk<br>\n";
      my $sth = $dbh->prepare(qq{
          insert into billing
          (username,feeid,feetype,feedesc,rate,buyrate,type,startblk,endblk,subacct)
          values (?,?,?,?,?,?,?,?,?,?)
          }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
      $sth->execute("$username","$fee","$fee","$transfees{$fee}","$rate","$buyrate","$type","$startblk","$endblk","$data{'subacct'}")
                   or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
      $sth->finish;
    }
  }
  #print "FIXED FEES<p>\n";
  #@fixedfees = (@fixedfees,@minimumfees);
  foreach $fee (@fixedfees) {
    #print "FEE:$fee<br>\n";
    $desc = $data{"$fee\_desc"};
    $rate = $data{"$fee\_rate"};
    $buyrate = $data{"$fee\_buyrate"};

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
        $qstr = "update billing set feetype=?,feedesc=?,rate=?,buyrate=?,type=? where username='$username' and feeid='$fee' and subacct='$data{'subacct'}'";
      }
      else {
        $qstr = "update billing set feetype=?,feedesc=?,rate=?,buyrate=?,type=? where username='$username' and feeid='$fee'";
      }

      my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
      $sth->execute("fixed","$desc","$rate","$buyrate","monthly")
                   or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
      $sth->finish;
    }
    else {
      #print "INSERT FEE:$fee, DESC:$desc, RATE:$rate<br>\n";
      my $sth = $dbh->prepare(qq{
          insert into billing
          (username,feeid,feetype,feedesc,rate,buyrate,type,subacct)
          values (?,?,?,?,?,?,?,?)
          }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
      $sth->execute("$username","$fee","fixed","$desc","$rate","$buyrate","monthly","$data{'subacct'}")
                   or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
      $sth->finish;
    }
  }

  foreach $fee (@minimumfees) {
    #print "FEE:$fee<br>\n";
    $desc = $data{"$fee\_desc"};
    $rate = $data{"$fee\_rate"};
    $buyrate = $data{"$fee\_buyrate"};
 
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
        $qstr = "update billing set feetype=?,feedesc=?,rate=?,buyrate=?,type=? where username='$username' and feeid='$fee' and subacct='$data{'subacct'}'";
      }
      else {
        $qstr = "update billing set feetype=?,feedesc=?,rate=?,buyrate=?,type=? where username='$username' and feeid='$fee'";
      }
 
      my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
      $sth->execute("minimum","$desc","$rate","$buyrate","monthly")
                   or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
      $sth->finish;
    }
    else {
      #print "INSERT FEE:$fee, DESC:$desc, RATE:$rate<br>\n";
      my $sth = $dbh->prepare(qq{
          insert into billing
          (username,feeid,feetype,feedesc,rate,buyrate,type,subacct)
          values (?,?,?,?,?,?,?,?)
          }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
      $sth->execute("$username","$fee","minimum","$desc","$rate","$buyrate","monthly","$data{'subacct'}")
                   or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
      $sth->finish;
    }
  }
  $dbh->disconnect;
  &addfee();
}

sub update_billing {

  #print "UPDATEING FEES<p>\n";
  my $dbh = &miscutils::dbhconnect('misccrap');
  my ($uplist) = @_;
  foreach $key  (keys %$uplist) {
    #print "KEY1:$key<br>\n";

    my ($fee,$blk) = split(':',$key);
    $key = "$fee$blk";
    $rate = $data{"$key\_rate"};
    $rate =~ s/[^0-9\.]//g;

    #print "KEY1:$key, RATE:$rate<br>\n";
     
    if ($rate eq "") {
      next;
    }
    $type = $data{'feetype'};
    $type =~ s/[^a-z]//g;
    $buyrate = $data{"$key\_buyrate"};
    $buyrate =~ s/[^0-9\.]//g;
    $startblk = $data{"$key\_start"};
    $startblk =~ s/[^0-9\.]//g;
    $newstartblk = $data{"$key\_newstart"};
    $newstartblk =~ s/[^0-9\.]//g;
    $endblk = $data{"$key\_end"};
    $endblk =~ s/[^0-9\.]//g;

    #print "KEY1:$key, RATE:$rate, STRBLK:$startblk, NEWSTRT:$newstartblk<br>\n";
 
    if ($data{'subacct'} ne "") {
      $qstr = "select feeid from billing where username='$username' and feeid='$fee' and startblk='$startblk' and subacct='$data{'subacct'}'";
    }
    else {
      $qstr = "select feeid from billing where username='$username' and feeid='$fee' and startblk='$startblk'";
    }

    #print "QSTR:$qstr\n";
    #exit;

    my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
    $sth->execute or die "Can't execute: $DBI::errstr";
    my ($test) = $sth->fetchrow;
    $sth->finish;


    #print "TEST:$test<br>\n";

    #exit;

    if ($test ne "") {
      if ($data{'subacct'} ne "") {
        $qstr = "update billing set feetype=?,feedesc=?,rate=?,buyrate=?,type=?,startblk=?,endblk=? where username='$username' and feeid='$fee' and startblk='$startblk' and subacct='$data{'subacct'}'";
      }
      else {
        $qstr = "update billing set feetype=?,feedesc=?,rate=?,buyrate=?,type=?,startblk=?,endblk=? where username='$username' and feeid='$fee' and startblk='$startblk'";
      }
      #print "TRANSUPDATE: UN:$username, FEEID:$fee, FEETYPE:$fee, FEEDESC:$transfees{$fee}, RATE:$rate, BUYRATE:$buyrate, TYPE:$type, START:$startblk, END:$endblk<br>\n";

     # print "QSTR:$qstr<br>\n";
     # print "FEE:$fee, DESC:$transfees{$fee}, RATE:$rate, BRATE:$buyrate, TYPE:$type, NEWSTRT:$newstartblk, ENDBLE:$endblk<br>\n";
      #exit;
      
      my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
      $sth->execute("$fee","$transfees{$fee}","$rate","$buyrate","$type","$newstartblk","$endblk")
                   or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
      $sth->finish;
    }
    #else {
#      print "TRANSINSERT: UN:$username, FEEID:$fee, FEETYPE:$fee, FEEDESC:$transfees{$fee}, RATE:$rate, BUYRATE:$buyrate, TYPE:$type, START:$startblk, END:$endblk<br>\n";
    #  my $sth = $dbh->prepare(qq{
    #      insert into billing
    #      (username,feeid,feetype,feedesc,rate,buyrate,type,startblk,endblk,subacct)
    #      values (?,?,?,?,?,?,?,?,?,?)
    #      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
    #  $sth->execute("$username","$fee","$fee","$transfees{$fee}","$rate","$buyrate","$type","$startblk","$endblk","$data{'subacct'}")
    #               or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
    #  $sth->finish;
    #}
  }
  $dbh->disconnect;
  #&addfee();
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
  #print "DFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF<br>\n";
  my ($dlist) = @_;
  my $dbh = &miscutils::dbhconnect('misccrap');
  foreach $key  (keys %$dlist) {
    my ($a,$b) = split(':',$key);
    print "DELETE VAR:$a:A:$b:B:$username:<br>\n";
    if ($data{'subacct'} ne "") {
      $qstr = "delete from billing where username='$username' and feeid='$a' and startblk='$b' and subacct='$data{'subacct'}'";
    }
    else {
      $qstr = "delete from billing where username='$username' and feeid='$a' and startblk='$b'";
    }
    print "QSTR:$qstr<br>\n";

    my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
    $sth->execute or die "Can't execute: $DBI::errstr";
    $sth->finish;
  }

  $dbh->disconnect;
}

sub delete_fixed_billing {
  my ($dlist) = @_;
  my $dbh = &miscutils::dbhconnect('misccrap');
  foreach $key  (keys %$dlist) {
    print "DELETE VAR:$key:$username:<br>\n";
    if ($data{'subacct'} ne "") {
      $qstr = "delete from billing where username='$username' and feeid='$key' and subacct='$data{'subacct'}'";
    }
    else {
      $qstr = "delete from billing where username='$username' and feeid='$key' ";
    }
    my $sth = $dbh->prepare(qq{$qstr}) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
    $sth->execute or die "Can't execute: $DBI::errstr";
    $sth->finish;
  }

  $dbh->disconnect;
}


sub sort_alpha_hash {
  my $x = shift;
  my %array=%$x;
  sort { $array{$a} cmp $array{$b}; } keys %array;
}

sub sort_numeric_hash {
  my $x = shift;
  my %array=%$x;
  sort { $array{$b} <=> $array{$a}; } keys %array;
}

sub sort_numeric {
  $a <=>$b ;
}


1;
