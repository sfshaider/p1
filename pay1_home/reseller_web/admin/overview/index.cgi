#!/bin/env perl

require 5.001;
$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use CGI;
use PlugNPay::Environment;
use strict;

if (($ENV{'HTTP_X_FORWARDED_SERVER'} ne "") && ($ENV{'HTTP_X_FORWARDED_FOR'} ne "")) {
  $ENV{'HTTP_HOST'} = (split(/\,/,$ENV{'HTTP_X_FORWARDED_HOST'}))[0];
  $ENV{'SERVER_NAME'} = (split(/\,/,$ENV{'HTTP_X_FORWARDED_SERVER'}))[0];
}

my $username = $ENV{"REMOTE_USER"};
my $reseller = $username;

my %overview = ();

my %allowed = (
 'devresell','1',
 'northame', '1',
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
 'premier4', '1',
 'aaronsin', '1',
 'homesmrt', '1',
 'singular', '1',
 'premier5', '1',
 'jhewitt',  '1'
);

 
my %fraudtrack = (
 'devresell','1',
 'northame', '1',
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
 'premier4', '1', 
 'affinisc', '1',
 'lawpay',   '1',
 'monkeyme', '1',
 'singular', '0',
 'premier5', '1'
);

my %riskmgmt = (
 'devresell','1',
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
 'palisade', '1',
 'affinisc', '0',
 'lawpay',   '0',
 'singular', '0'
);

my %smps = (
 'devresell','1',
 'northame', '1',
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
 'premier4', '1',
 'affinisc', '1',
 'lawpay',   '1',
 'monkeyme', '1',
 'aaronsin', '1',
 'homesmrt', '1',
 'resruby',  '1',
 'cardwork', '1',
 'premier5', '1',
 'singular', '0',
 'jhewitt',  '1'

);

my %orders = (
 'devresell','1',
 'stkitts2', '1',
 'premier2', '1',
 'affinisc', '1',
 'lawpay',   '1',
 'aaronsin', '1',
 'homesmrt', '1',
 'singular', '1',
 'premier5', '1'
);

my %account_settings = (
 'devresell','1',
 'affinisc', '1',
 'lawpay',   '1',
 'singular', '1'
);

my $dbh = &miscutils::dbhconnect("pnpmisc");

my $sth = $dbh->prepare(qq{
    select overview
    from salesforce
    where username=?
    }) or die "Can't do: $DBI::errstr";
$sth->execute("$ENV{'REMOTE_USER'}") or die "Can't execute: $DBI::errstr";
my ($allow_overview) = $sth->fetchrow;
$sth->finish;

$dbh->disconnect;


if ($allow_overview ne "") {
  $overview{'allowed'} = 1;
  my @array = split(/\|/,$allow_overview);
  foreach my $entry (@array) {
    $overview{$entry} = 1;
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

if ($account_settings{$ENV{'REMOTE_USER'}} == 1) {
  $overview{'account_settings'} = 1;
}

if (! exists $overview{'allowed'}) {
  print "Content-Type: text/html\n";
  print "X-Content-Type-Options: nosniff\n";
  print "X-Frame-Options: SAMEORIGIN\n\n";
  print "<html><body>Un-Authorized Access</body></html>\n";
  exit;
}

my $query = new CGI;

# get reseller feature settings
my $env = new PlugNPay::Environment();
my $reseller_features = $env->getFeatures();

# see if reseller has custom limit for the 'All Merchants' ability.
my $overview_all_limit = $reseller_features->get('overview_all_limit');
$overview_all_limit =~ s/[^0-9]//g;

# figure out what the all_limit should be for the given reseller.
my $all_limit = 20; # default max number of accounts, before 'All Merchants' option gets supressed.
# USAGE NOTE: when limit is '9999', it forces the 'All Merchants' option to appear, regardless of how many accounts reseller has
if ($overview_all_limit > 0) {
  # if reseller has a custom limit is set, use that limit instead.
  $all_limit = $overview_all_limit;
}

my %companyarray = ();
my @userarray = ();
my @subacct = ();
my @bill_files = ();

if(0) {
if ($username eq "volpayin") {
#  my ($username, $name, $company, $subacct);
#  $sth = $dbh->prepare(qq{
#      select username,name,company,subacct
#      from customers
#      where processor=?
#      and status<>?
#      order by username
#  }) or die "Can't prepare: $DBI::errstr";
#  $sth->execute("volpay", "cancelled") or die "Can't execute: $DBI::errstr";
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
  my ($username, $name, $company, $subacct);
  $sth = $dbh->prepare(qq{
      select username,name,company,subacct
      from customers
      where reseller=?
      and status<>?
      order by username
  }) or die "Can't prepare: $DBI::errstr";
  $sth->execute("$reseller", "cancelled") or die "Can't execute: $DBI::errstr";
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

if (($ENV{'REMOTE_USER'} =~ /^(northame|stkittsn|cableand|officetr|smart2pa|planetpa|cccc)$/) || ($#userarray <= $all_limit) || ($all_limit == 9999)) {
  @userarray = (@userarray,"ALL");
  $companyarray{'ALL'} = "All Merchants";
}

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

my $servername = $ENV{'SERVER_NAME'};
$servername =~ /(\w+)\.(\w+)\.(\w+)/;
my $cookiehost = "\.$2\.$3";
print "Set-Cookie: loginattempts=; path=/; expires=Fri, 01-Jul-11 23:00:00 GMT; domain=$cookiehost; secure=1; httponly=1;\n";

print $query->header(-type=>'text/html', -expires=>'-1d');

#print "Content-Type: text/html\n";
#print "X-Content-Type-Options: nosniff\n";
#print "X-Frame-Options: SAMEORIGIN\n\n";

&main_page();


sub overview {
  my($reseller) = @_;
  my ($db_merchant, $username, $name, $company, $subacct);

  my $env = new PlugNPay::Environment();
  my $features = $env->getFeatures();
  my $linked_overview_accts = $features->get('linked_overview_accts');
  my @linked_accts = split(/\|/,$linked_overview_accts);
  my $qmark = "?,";
  foreach my $var (@linked_accts) {
    $qmark .= "?,";
  }
  chop $qmark;

  push (@linked_accts, $reseller,'cancelled');
  my $dbh = &miscutils::dbhconnect("pnpmisc");

  my $sth = $dbh->prepare(qq{
      select username,name,company,subacct
      from customers
      where reseller IN ($qmark)
      and status<>?
      order by username
  }) or die "Can't prepare: $DBI::errstr";
  $sth->execute(@linked_accts) or die "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($username,$name,$company,$subacct));
  while ($sth->fetch) {
    $userarray[++$#userarray] = "$username";
    $companyarray{$username} = $company;
  }
  $sth->finish;

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
    if (confirm("Are You Sure That You Wish to TOGGLE the status of TESTING MODE.  Setting TESTING MODE to ENABLE will force any transactions with a card-name set to \\"pnptest\\" to be successful.  This is used for TESTING purposes.")) {;
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
<link rel="stylesheet" type="text/css" href="https://$ENV{'SERVER_NAME'}/css/green.css">
</head>

<body bgcolor="#ffffff">
<div align=center>
<form name="account" method="post" action="">
EOF

if ($reseller =~ /^(jncb|cccc|bdagov)$/) {
  print <<EOF;
  <table cellspacing="0" cellpadding="4" border="1" width="500">
  <tr>
    <td align="center" colspan="3"><img src="/adminlogos/cw_admin_logo.gif" alt="Corp. Logo"></td>
  </tr>
EOF
}
else {
  print <<EOF;
<table>
  <tr>
    <td><img src="/adminlogos/pnp_admin_logo.gif" alt="Payment Gateway Logo" /></td>
    <td class="right">&nbsp;</td>
  </tr>
  <tr>
    <td colspan="2"><img src="/adminlogos/masthead_background.gif" alt="Corp. Logo" width="750" height="16" /></td>
  </tr>
</table>
<table>
  <tr>
    <td><h1>Reseller Overview Administration Area</h1></td>
    <td align="right"><a href="/admin/logout.cgi">Logout</a></td>
  </tr>
  <tr>
    <td colspan="2"><hr id="under" /></td>
  </tr>
</table>
<table cellspacing="0" cellpadding="4" border="1" width="750">
EOF
}

&print_accounts();

if ($ENV{'REMOTE_USER'} =~ /^(processa)$/) {
  print <<EOF;
  <tr>
    <th class="labellp">&bull; <a href="javascript:change_win('/admin/overview/trans_correction.cgi',720,500)"><font id="corrections" color=\"#ff0000\"><nobr><b>Transaction Settlement Corrections</b></nobr></font></a></th>
    <td align="center" width="100"> &nbsp; </td>
  </tr>
EOF
}

if (exists $overview{'smps'}) {
  print <<EOF;
  <tr>
    <th class="labellp">&bull; <a href="javascript:change_win('/admin/overview/smps.cgi',720,500)"><font id="transaction"><nobr>Transaction Administration</nobr></font></a></th>
    <td align="center" width="100"> <a href="javascript:help_win('help.cgi?subject=transaction',600,500)">Online Help</a> </td>
  </tr>
EOF
}

if (exists $overview{'orders'}) {
  &print_orders();
}

if (exists $overview{'fraudtrack'}) {
  print <<EOF;
  <tr>
    <th class="labellp">&bull; <a href="javascript:change_win('/admin/overview/fraudtrack/index.cgi',600,500)"><font id="promotion">FraudTrak</font></a></th>
    <td align="center" width="20"> &nbsp; </td>
  </tr>
EOF
}

if (exists $overview{'riskmgmt'}) {
  &print_riskmgmt();
}

print <<EOF;
  <tr>
    <th class="labellp">&bull; <a href="javascript:open_win('/admin/overview/graphs.cgi',600,400)"><font id="graph">Graphs/Reports</font></a></th>
    <td align="center" width="100"> &nbsp; </td>
  </tr>
EOF

if (exists $overview{'account_settings'}) {
  &print_account_settings();
}

print <<EOF;
  <tr>
    <th class="labellp">&bull; <a href="javascript:help_win('/admin/overview/documentation.cgi',600,400)"><font id="documents">Documentation</font></a></th>
    <td align="center" width="100"> &nbsp; </td>
  </tr>

<!--
  <tr>
    <th class="labellp">&bull; <a href="javascript:change_win('/admin/overview/helpdesk.cgi',600,500)"><font id="help">Help Desk</font></a></th>
    <td align="center" width="100"> &nbsp; </td>
  </tr>
-->

  <tr>
    <td colspan=2><hr id="over" /></td>
  </tr>
</table>
<table class="frame">
  <tr>
    <td align="left"><a href="/admin/online_helpdesk.cgi" target="ahelpdesk">Help Desk</a></td>
    <td class="right">&copy; 2011, $ENV{'SERVER_NAME'}</td>
  </tr>
</table>

</form>
</body>
</html>
EOF

}

sub print_accounts {
  print <<EOF;
  <tr>
    <th class="labellp"><font id="transaction">Account:</font></th>
    <td align="center" width="100"><select name="merchant">
EOF
  foreach my $var (@userarray) {
    print "<option value=\"$var\">$var - $companyarray{$var}</option>\n";
  }
  print <<EOF;
</select>
<input type="hidden" name="gotourl" value=""></td>
  </tr>
EOF
}
 
sub print_subaccounts {
  print <<EOF;
  <tr>
    <th class="labellp"><font id="transaction">Sub Account:</font></th>
    <td align="center" width="100"><select name="subacct">
<option value=\"\" selected>No Subacct</option>
EOF
  foreach my $var (@subacct) {
    print "<option value=\"$var\">$var</option>\n";
  }
  print <<EOF;
</select>
<input type="hidden" name="gotourl" value=""></td>
  </tr>
EOF
}

sub print_riskmgmt {
  print <<EOF;
  <tr>
    <th class="labellp">&bull; <a href="javascript:change_win('/admin/risktrak/index.cgi',600,500)"><font id="promotion">RiskTrak</font></a></th>
    <td align="center" width="20"> &nbsp; </td>
  </tr>
EOF
}

sub print_billfiles {
  print <<EOF;
  <tr>
    <th class="labellp"><font id="transaction">Account:</font></font></th>
    <td align="center" width="100"><select name="merchant">
EOF
  foreach my $var (@bill_files) {
    print "<option value=\"$var\"></option>\n";
  }
  print <<EOF;
</select>
<input type="hidden" name="gotourl" value=""></td>
  </tr>
EOF
}


sub print_orders {
  print <<EOF;
  <tr>
    <th class="labellp">&bull; <a href="javascript:change_win('/admin/overview/orders.cgi',720,500)"><font id="transaction">Orders Database</font></a></th>
    <td align="center" width="100"> <a href="javascript:help_win('/admin/overview/help.cgi?subject=orders',600,500)">Online Help</a></td>
  </tr>
EOF
}

sub print_account_settings {
  print <<EOF;
  <tr>
    <th class="labellp">&bull; <a href="javascript:change_win('/admin/overview/account_settings.cgi',720,500)"><font id="transaction">Account Settings</font></a></th>
    <td align="center" width="100"> &nbsp; </td>
  </tr>
EOF
}

