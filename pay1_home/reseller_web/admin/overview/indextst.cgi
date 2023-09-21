#!/bin/env perl

require 5.001;
$| = 1;

use lib '/home/p/pay1/perl_lib';
use miscutils;
use CGI;

$username = $ENV{"REMOTE_USER"};
$reseller = $username;

%overview = ();

%allowed = (
 'northame','1',
 'epayment', '1',
 'officetr', '1',
 'stkittsn', '1',
 'cynergy',  '1',
 'cynergyo', '1',
 'cufsmana', '1',
 'payright', '1',
 'smart2pa', '1',
 'planetpa', '1',
 'cccc',     '1',
 'jncb',     '1',
 'payameri', '1',
 'providen', '1',
 'cableand', '1',
 'electro',  '1',
 'planetp2', '1',
 'planpago', '1',
 'paymentd', '1',
 'bdagov',   '1',
 'imgloba1', '1',
 'paybyweb', '1',
 'processa', '1',
 'univers3', '1',
 'pinnacle', '1',
 'stkitts2', '1',
 'planetdm', '1',
 'premier2', '1',
 'premier3', '1',
 'palisade', '1', 
 'comertwg', '1', 
 'parkches', '1',
 'credico2', '1', 
 'unlimite', '1',
 'signatur', '1', 
 'manoaman', '1', 
 'sftman',   '1',
 'premier4', '1'
);

 
%fraudtrack = (
 'northame','1',
 'epayment', '1',
 'officetr', '1',
 'stkittsn', '1',
 'cynergy',  '1',
 'cynergyo', '1',
 'cufsmana', '1',
 'payright', '1',
 'smart2pa', '1',
 'planetpa', '1',
 'cccc',     '1',
 'jncb',     '1',
 'payameri', '1',
 'providen', '1',
 'cableand', '1',
 'electro',  '1',
 'planetp2', '1', 
 'planpago', '1', 
 'paymentd', '1', 
 'bdagov',   '1',
 'paybyweb', '1',
 'processa', '1',
 'univers3', '1',
 'pinnacle', '1', 
 'imgloba1', '1',
 'planetdm', '1',
 'premier2', '1',
 'premier3', '1',
 'palisade', '1',
 'tri8inc',  '1',
 'premier4', '1' 
);

%riskmgmt = (
 'epayment', '1',
 'officetr', '1',
 'stkittsn', '1',
 'cynergy',  '1',
 'cynergyo', '1',
 'cufsmana', '1',
 'payright', '1',
 'jncb',     '1',
 'cableand', '1',
 'planetp2', '1',
 'planpago', '1',
 'paymentd', '1',
 'imgloba1', '1',
 'pinnacle', '1',
 'planetdm', '1',
 'palisade', '1'
);

%smps = (
 'northame','1',
 'smart2pa', '1',
 'planetpa', '1',
 'cccc',     '1',
 'providen', '1',
 'cableand', '1',
 'jncb',     '1',
 'electro',  '1',
 'planetp2', '1',
 'planpago', '1',
 'paymentd', '1',
 'bdagov',   '1',
 'imgloba1', '1',
 'paybyweb', '1',
 'processa', '1',
 'univers3', '1',
 'pinnacle', '1',
 'stkitts2', '1',
 'planetdm', '1',
 'premier2', '1',
 'premier3', '1',
 'palisade', '1',
 'comertwg', '1', 
 'parkches', '1',
 'credico2', '1', 
 'unlimite', '1', 
 'manoaman', '1', 
 'sftman',   '1',
 'tri8inc',  '1', 
 'premier4', '1'
);

%orders = (
 'stkitts2', '1',
 'premier2', '1'
);


$dbh = &miscutils::dbhconnect("pnpmisc");

my $sth = $dbh->prepare(qq{
    select overview
    from salesforce
    where username='$ENV{'REMOTE_USER'}'
    }) or die "Can't do: $DBI::errstr";
$sth->execute or die "Can't execute: $DBI::errstr";
($allow_overview) = $sth->fetchrow;
$sth->finish;

$dbh->disconnect;


if ($allow_overview ne "") {
  $overview{'allowed'} = 1;
  my @array = split(/\|/,$allow_overview);
  foreach my $entry (@array) {
    $overview{$name} = 1;
  }
}

if ($allowed{$ENV{'REMOTE_USER'}} == 1) {
  $overview{'allowed'} = 1;
}

if ($smps{$ENV{'REMOTE_USER'}} == 1) {
  $overview{'smps'} = 1;
}

if ($fraudtrack{$ENV{'REMOTE_USER'}} == 1) {
  $overview{'fraudtrack'} = 1;
}

if ($orders{$ENV{'REMOTE_USER'}} == 1) {
  $overview{'orders'} = 1;
}

if ($riskmgmt{$ENV{'REMOTE_USER'}} == 1) {
  $overview{'riskmgmt'} = 1;
}

if (! exists $overview{'allowed'}) {
  print "Content-Type: text/html\n\n";
  print "<html><body>Un-Authorized Access</body></html>\n";
  exit;
}

$query = new CGI;

if(0) {
if ($username eq "volpayin") {
#  $sth = $dbh->prepare(qq{
#      select username,name,company,subacct
#      from customers
#      where processor='volpay'
#      and status<>'cancelled'
#      order by username
#  }) or die "Can't prepare: $DBI::errstr";
#  $sth->execute or die "Can't execute: $DBI::errstr";
#  $sth->bind_columns(undef,\($username,$name,$company,$subacct));
#  while ($sth->fetch) {
#    @userarray = (@userarray,$username);
  #  if ($subacct ne "") {
  #    @subacct = (@subacct,$subacct);
  #  }
#    $companyarray{$username} = $company;
#  }
#  $sth->finish;
  #@userarray = (@userarray,"EVERY"); 
  #$companyarray{'EVERY'} = "Every Merchants";
}
else {
  $sth = $dbh->prepare(qq{
      select username,name,company,subacct
      from customers
      where reseller='$reseller'
      and status<>'cancelled'
      order by username
  }) or die "Can't prepare: $DBI::errstr";
  $sth->execute or die "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($username,$name,$company,$subacct));
  while ($sth->fetch) {
    @userarray = (@userarray,$username);
  #  if ($subacct ne "") {
  #    @subacct = (@subacct,$subacct);
  #  }
    $companyarray{$username} = $company;
  }
  $sth->finish;
}

$dbh->disconnect;
}

%companyarray = &overview("$reseller");
@userarray = (sort keys %companyarray);

@userarray = (@userarray,"ALL");
$companyarray{'ALL'} = "All Merchants";

if ($ENV{'REMOTE_ADDR'} eq "96.56.10.12") {
if ($ENV{'REMOTE_USER'} =~ /^(cableand)$/) {
  @userarray = (@userarray,"EVERY"); 
  $companyarray{'EVERY'} = "Every Merchants";
}
}

if (!exists $companyarray{$reseller}) {
  $companyarray{$reseller} = "Default Setting";
  @userarray = ($reseller,@userarray);
}

print $query->header(-type=>'text/html', -expires=>'-1d');

#print "Content-Type: text/html\n\n";
 
if (($ENV{'HTTP_COOKIE'} ne "")){
  (@cookies) = split('\;',$ENV{'HTTP_COOKIE'});
  foreach $var (@cookies) {
    ($name,$value) = split('=',$var);
    $name =~ s/ //g;
    $cookie{$name} = $value;
  }
}

&main_page();


sub overview {
  my($reseller) = @_;
  my ($db_merchant);

  my $dbh = &miscutils::dbhconnect("pnpmisc");

  if ($reseller eq "cableand") {
    $sth = $dbh->prepare(qq{
        select username,name,company,subacct
        from customers
        where reseller IN ('cableand','cccc','jncb','bdagov')
        and status<>'cancelled'
        order by username
    }) or die "Can't prepare: $DBI::errstr";
    $sth->execute or die "Can't execute: $DBI::errstr";
    $sth->bind_columns(undef,\($username,$name,$company,$subacct));
    while ($sth->fetch) {
      $userarray[++$#userarray] = "$username";
      $companyarray{$username} = $company;
    }
    $sth->finish;
  }
  elsif ($reseller eq "manoaman") {
    $sth = $dbh->prepare(qq{
        select username,name,company,subacct
        from customers
        where reseller IN ('manoaman','sftman')
        and status<>'cancelled'
        order by username
    }) or die "Can't prepare: $DBI::errstr";
    $sth->execute or die "Can't execute: $DBI::errstr";
    $sth->bind_columns(undef,\($username,$name,$company,$subacct));
    while ($sth->fetch) {
      $userarray[++$#userarray] = "$username";
      $companyarray{$username} = $company;
    }
    $sth->finish;
  }
  else {
    $sth = $dbh->prepare(qq{
        select username,name,company,subacct
        from customers
        where reseller=?
        and status<>'cancelled'
        order by username
    }) or die "Can't prepare: $DBI::errstr";
    $sth->execute($reseller) or die "Can't execute: $DBI::errstr";
    $sth->bind_columns(undef,\($username,$name,$company,$subacct));
    while ($sth->fetch) {
      $userarray[++$#userarray] = "$username";
      $companyarray{$username} = $company;
    }
    $sth->finish;
  }

  $dbh->disconnect;

  return %companyarray;

}


exit;

sub main_page {

  print <<EOF;
<html>
<head>
<title>Merchant Administration Area</title>
<!-- <base href="https://reseller.plugnpay.com/admin"> -->
<META HTTP-EQUIV="expires" CONTENT="0">
<!-- UN:$username, RSELL:$reseller -->
<style type="text/css">
  th { font-family: Arial,Helvetica,Univers,Zurich BT; font-size: 11pt; color: #000000 }
  td { font-family: Arial,Helvetica,Univers,Zurich BT; font-size: 10pt; color: #000000 }
  .badcolor { color: #ff0000 }
  .goodcolor { color: #000000 }
  .larger { font-size: 100% }
  .smaller { font-size: 60% }
  .short { font-size: 8% }
  .button { font-size: 75% }
  .itemscolor { background-color: #000000; color: #ffffff }
  .itemrows { background-color: #d0d0d0 }
  .items { position: static }
  .info { position: static }

  DIV.section { text-align: justify; font-size: 12pt; color: white}
  DIV.subsection { text-indent: 2em }
  H1 { font-style: italic; color: green }
  H2 { color: green }
</style>

<SCRIPT LANGUAGE="Javascript"  TYPE="text/javascript">
<!-- //
  function change_win(targetURL,swidth,sheight) {
    SmallWin = window.open('', 'results','scrollbars=yes,resizable=yes,status=yes,toolbar=yes,menubar=yes,location=yes,height='+sheight+',width='+swidth);
    document.account.action = targetURL;
    document.account.target = 'results';
    document.account.submit();
  }

  function open_win(targetURL,swidth,sheight) {
    SmallWin = window.open('', 'results','scrollbars=yes,resizable=yes,status=yes,toolbar=yes,menubar=yes,height='+sheight+',width='+swidth);
    //document.account.action = 'graphs.cgi';
    document.account.action = targetURL;
    document.account.target = 'results';
    //document.account.gotourl.value = targetURL;
    document.account.submit();
  }

  function help_win(helpurl,swidth,sheight) {
    SmallWin = window.open(helpurl, 'HelpWindow',
    'scrollbars=yes,resizable=yes,status=yes,toolbar=yes,menubar=yes,height='+sheight+',width='+swidth);
  }

  function modURL() {
    urlStr = location.protocol + "//" + location.host + location.pathname;
    //location = urlStr;
    //alert (urlStr);
  }

  function testmode() {
    if (confirm("Are You Sure That You Wish to TOGGLE the status of TESTING MODE.  Setting TESTING MODE to ENABLE will force any  transactions with a card-name set to \\"pnptest\\" to be successful.  This is used for TESTING purposes.")) {;
      urlStr = "/admin/testmode.cgi";
      location = urlStr;
    //alert (urlStr);
    }
  }

  function inward (thing,num){
    if (num == 1){
      thing.color="black";
    }
  }

//-->

</SCRIPT>

</head>

<body bgcolor="#ffffff" alink="#ffffff" link="#ffffff" vlink="#ffffff">
<div align=center>
<form name="account" method="post" action="">
<table cellspacing="0" cellpadding="4" border="1" width="500">
EOF

if ($reseller =~ /^(jncb|cccc|bdagov)$/) {
  print <<EOF;
<tr><td align="center" colspan="3"><img src="/adminlogos/cw_admin_logo.gif" alt="Corp. Logo"></td></tr>
EOF
}
else {
  print <<EOF;
<tr><td align="center" colspan="3"><img src="/adminlogos/pnp_admin_logo.gif" alt="Corp. Logo"></td></tr>
EOF
}


&print_accounts();


if (exists $overview{'smps'}) {
  print <<EOF;
<tr> <th valign=top align=left bgcolor="#4a7394" colspan="1"><font
color="#ffffff"><a href="javascript:change_win('/admin/overview/smpsdave.cgi',720,500)" ><font color=white id="transaction">Transaction Administration</font></a></font></th>

<td bgcolor="#4a7394" align="center" width="100"> <a href="javascript:help_win('help.cgi?subject=transaction',600,500)">Online Help</a> </td> </tr>
EOF
}

if (exists $overview{'orders'}) {
  &print_orders();
}

if (exists $overview{'fraudtrack'}) {
  print <<EOF;
 
<tr> <th valign=top align=left bgcolor="#4a7394" colspan="1"><font color="#ffffff">
<a href="javascript:change_win('/admin/overview/fraudtrack/index.cgi',600,500)" >
<font id="promotion" color="white"> FraudTrak </font></a></font></th>
<td bgcolor="#4a7394" align="center" width="20"> &nbsp; </td> </tr>
EOF
}

if (exists $overview{'riskmgmt'}) {
 &print_riskmgmt();
}

print <<EOF;
<tr>
<th valign=top align=left bgcolor="#4a7394" colspan="1"><font
color="#ffffff"><a href="javascript:open_win('/admin/overview/graphs.cgi',600,400)"><font id="graph" color=white>Graphs/Reports</font></a></font></th>
<td bgcolor="#4a7394" align="center" width="100">
&nbsp;
</td>

</tr>


<tr>
<th valign=top align=left bgcolor="#4a7394" colspan="1"><font
color="#ffffff"><a href="javascript:help_win('/admin/overview/documentation.cgi',600,400)"><font id="documents" color=white>Documentation</font></a></font></th>
<td bgcolor="#4a7394" align="center" width="100">
&nbsp;
</td>

</tr>

<!--
<tr>
<th valign=top align=left bgcolor="#4a7394" colspan="1"><font
color="#ffffff"><a href="javascript:change_win('/admin/overview/helpdesk.cgi',600,500)" ><font id="help" color=white>Help Desk</font></a></font></th>
<td bgcolor="#4a7394" align="center" width="100">
&nbsp;
</td>
</tr>
-->

</table>
</form>
</body>
</html>

EOF

}


sub print_accounts {
  print <<EOF;
<tr>
<th valign=top align=left bgcolor="#4a7394" colspan="1"><font color="#ffffff">
<font color=white id="transaction">Account</font></font></th>
<td bgcolor="#4a7394" align="center" width="100">
<select name="merchant">
EOF
  foreach $var (@userarray) {
    print "<option value=\"$var\">$var - $companyarray{$var}</option>\n";
  }
  print <<EOF;
</select>
<input type="hidden" name="gotourl" value="">
</td>
</tr>
EOF
}
 
sub print_subaccounts {
  print <<EOF;
<tr>
<th valign=top align=left bgcolor="#4a7394" colspan="1"><font color="#ffffff">
<font color=white id="transaction">Sub Account</font></font></th>
<td bgcolor="#4a7394" align="center" width="100">
<select name="subacct">
<option value=\"\" selected>No Subacct</option>
EOF
  foreach $var (@subacct) {
    print "<option value=\"$var\">$var</option>\n";
  }
  print <<EOF;
</select>
<input type="hidden" name="gotourl" value="">
</td>
</tr>
EOF
}

sub print_riskmgmt {
  print <<EOF;
<tr>
<th valign=top align=left bgcolor="#4a7394" colspan="1"><font color="#ffffff">
<a href="javascript:change_win('/admin/risktrak/index.cgi',600,500)" >
<font id="promotion" color="white"> RiskTrak </font></a></font></th>
<td bgcolor="#4a7394" align="center" width="20">
&nbsp;
</td>
</tr>
EOF
}

sub print_billfiles {
  print <<EOF;
<tr>
<th valign=top align=left bgcolor="#4a7394" colspan="1"><font color="#ffffff">
<font color=white id="transaction">Account</font></font></th>
<td bgcolor="#4a7394" align="center" width="100">
<select name="merchant">
EOF
  foreach my $var (@bill_files) {
    print "<option value=\"$var\"></option>\n";
  }
  print <<EOF;
</select>
<input type="hidden" name="gotourl" value="">
</td>
</tr>
EOF
}


sub print_orders {
  print <<EOF;
<tr> <th valign=top align=left bgcolor="#4a7394" colspan="1"><font
color="#ffffff"><a href="javascript:change_win('/admin/overview/fixdates.cgi',720,500)" ><font color=white id="transaction">Orders Database</font></a></font></th>
 
<td bgcolor="#4a7394" align="center" width="100"> <a href="javascript:help_win('/admin/overview/help.cgi?subject=orders',600,500)">Online Help</a> </td> </tr>
EOF
}

