package reseller;

use miscutils;
use CGI;
use DBI;
use rsautils;
use SHA;
use File::Copy;
use isotables;
use sysutils;
use NetAddr::IP;
use PlugNPay::Util::Captcha::ReCaptcha;
use constants qw(%countries %USstates %USterritories %CNprovinces);
use PlugNPay::Features;
use POSIX qw/strftime/;
use PlugNPay::Email;
use PlugNPay::Transaction::TransactionProcessor;
use PlugNPay::Database::QueryBuilder;
use PlugNPay::Reseller::Query;
use PlugNPay::Authentication::Login;

sub new {
  my $type = shift;

  $reseller::path_cgi  = "$ENV{'SCRIPT_NAME'}";
  $reseller::tech_list = "karin|cprice|unplugged|michelle|barbara|scaldero|drew|scottm|jamest|mwilliams|isomaki|dmanitta";

  #$query = new CGI;
  $data = new CGI;
  my @params = $data->param;
  foreach my $param (@params) {
    $param =~ s/[^a-zA-Z0-9\_\-]//g;
    $query{"$param"} = $data->param($param);
  }

  %reseller::default_iplist = ();

  $reseller::answer = $query{'g-recaptcha-response'};
  $reseller::answer =~ s/[^a-zA-Z0-9\_\-]//g;

  $function       = $query{'function'};
  $srchreseller   = $query{'srchreseller'};
  $srchsalesagent = $query{'srchsalesagent'};

  $reseller::global_features = new PlugNPay::Features( $ENV{'REMOTE_USER'}, 'general' );

  $query{'tel'} =~ s/[^0-9]//g;

  $reseller = $ENV{"REMOTE_USER"};

  ### restricts operations on a merchant to only the reseller on the account.  Exception for PnP
  if ( $query{'username'} ne "" ) {
    &security( "$query{'username'}", "$reseller" );
  }

  $query{'resellmerchant'} = "";

  %processor_hash = (
    'buypass'      => 'Buypass',
    'elavon'       => 'Elavon',
    'epx'          => 'EPX',
    'firstcarib'   => 'First Caribbean',
    'fdms'         => 'FDMS Nashville',
    'fdmsintl'     => 'FDMS Intl',
    'fdmsrc'       => 'FDMS Rapid Connect',
    'universal'    => 'Universal',
    'wirecard'     => 'Wirecard',
    'global'       => 'Global Payments',
    'globalc'      => 'Global Collect',
    'paytechsalem' => 'Paymentech Salem',
    'paytechtampa' => 'Paymentech Tampa',
    'payvision'    => 'Payvision',
    'visanet'      => 'Vital/TSYS',
    'ncb'          => 'JNCB',
    'pago'         => 'Pago',
    'planetpay'    => 'Planet Payment',
    'fifththird'   => 'FifthThird',
    'barclays'     => 'Barclays',
    'rbc'          => 'Royal Bank Canada',
    'mercury'      => 'Mercury Payments',
    'catalunya'    => 'Caixa Catalunya',
    'intuit'       => 'Intuit',
    'rbs'          => 'RBS WorldPay',
    'moneris'      => 'Moneris',
    'gsopay'       => 'Gsopay',
    'litle'        => 'Litle',
    'securenet'    => 'Securenet'
  );

  %reseller::cb_processors = ( 'catalunya', 'Caixa Catalunya' );

  @processors = ( sort keys %processor_hash );

  @visanet_required           = ( 'bin',         'categorycode', 'agentbank',    'agentchain', 'storenum', 'terminalnum' );
  @paytechtampa_required      = ( 'banknum',     'clientid',     'merchant_id',  'pubsecret' );
  @elavon_required            = ( 'banknum',     'pubsecret' );
  @global_required            = ( 'banknum',     'pubsecret' );
  @global_required            = ( 'banknum',     'pubsecret' );
  @fifththird_required        = ( 'merchant_id', 'pubsecret',    'banknum',      'currency', 'categorycode' );
  @fdmsintl_required          = ( 'merchant_id', 'banknum',      'currency',     'categorycode' );
  @ncb_required               = ( 'merchant_id', 'pubsecret',    'banknum',      'currency', 'categorycode', 'poscond' );
  @planetpay_vital_required   = ( 'bin',         'categorycode', 'agentbank',    'agentchain', 'storenum', 'terminalnum' );
  @planetpay_humbolt_required = ( 'merchant_id', 'banknum',      'categorycode', 'currency' );
  @cccc_required              = ( 'merchant_id', 'pubsecret',    'banknum',      'currency', 'categorycode', 'poscond' );

  %reseller::hide_area = ( 'sftman', 'commissions|rates' );

  $reseller::reseller_list =
    "wta|epz|ecq|frt|ofx|cbs|ipy|nab|bri|sss|drg|crd|eci|ctc|itc|cbb|ncb|cdo|cyd|pya|hms|tri|aar|hom|jhew|jhrh|jhrr|jhdr|jhce|jhjd|jhst|jhtt|jhtn|jhmk|jhsu|jhlb|jgok|jgtn|jgtx|jhat|tri|mtr";
  %reseller::retailflag = (
    'ofx'  => '1',
    'cbs'  => '1',
    'bri'  => '1',
    'crd'  => '1',
    'jhew' => '1',
    'jhrh' => '1',
    'jhrr' => '1',
    'jhdr' => '1',
    'jhce' => '1',
    'jhjd' => '1',
    'jhst' => '1',
    'jhtt' => '1',
    'jhtn' => '1',
    'jhmk' => '1',
    'jhsu' => '1',
    'jhlb' => '1',
    'jgok' => '1',
    'jgtn' => '1',
    'jgtx' => '1',
    'jhat' => '1'
  );
  %reseller::reseller_hash = (
    'wta'  => 'webtrans',
    'epz'  => 'epenzio',
    'ecq'  => 'ecoquest',
    'frt'  => 'frontlin',
    'ofx'  => 'epayment',
    'cbs'  => 'ofxcentb',
    'ipy'  => 'ipayment2',
    'nab'  => 'northame',
    'bri'  => 'epayment',
    'sss'  => 'cardmt',
    'drg'  => 'durango',
    'crd'  => 'cardread',
    'eci'  => 'electro',
    'ctc'  => 'commerce',
    'itc'  => 'interna3',
    'cbb'  => 'cblbanca',
    'ncb'  => 'jncb',
    'cdo'  => 'cynergyo',
    'cyd'  => 'cynergy',
    'pya'  => 'payameri',
    'hms'  => 'payhms',
    'tri'  => 'tri8inc',
    'aar'  => 'aaronsin',
    'hom'  => 'homesmrt',
    'jhew' => 'jhtsjudy',
    'jhrh' => 'jhtsjudy',
    'jhrr' => 'jhtsjudy',
    'jhdr' => 'jhtsjudy',
    'jhce' => 'jhtsjudy',
    'jhjd' => 'jhtsjudy',
    'jhst' => 'jhtsjudy',
    'jhtt' => 'jhtsjudy',
    'jhtn' => 'jhtsjudy',
    'jhmk' => 'jhtsjudy',
    'jhsu' => 'jhtsjudy',
    'jhlb' => 'jhtsjudy',
    'jgok' => 'jhtsjudy',
    'jgtn' => 'jhtsjudy',
    'jgtx' => 'jhtsjudy',
    'jhat' => 'jhtsjudy',
    'mtr'  => 'metrowes'
  );

  %reseller::mastermerch = ( 'dcprice', ['quantumipgl'], 'eonlined', ['quantumipgl'] );

  $goodcolor = "#2020a0";
  $backcolor = "#ffffff";
  $badcolor  = "#ff0000";

  $fontface = "Arial,Helvetica,Univers,Zurich BT";

  @eft            = ('authcapture');
  @authorizenet   = ('authonly');
  @authorizenetdr = ('authcapture');
  @paytechsalem   = ('authonly');
  @paytechtampa   = ('authonly');
  @csi            = ('authonly');
  @elavon         = ('authonly');
  @fdms           = ('authonly');
  @fdmsintl       = ('authonly');
  @buypass        = ('authonly');
  @visanet        = ('authonly');
  @village        = ('authonly');
  @global         = ('authonly');

  @cards_allowed = ( 'Visa', 'Mastercard', 'Amex', 'Discover' );

  %countries = %constants::countries;

  %USstates = %constants::USstates;

  %USterritories = %constants::USterritories;

  %CNprovinces = %constants::CNprovinces;

  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);
  my $now = sprintf( "%04d%02d%02d %02d\:%02d\:%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec );
  my $remoteaddr = $ENV{'REMOTE_ADDR'};

  return [], $type;
}

sub main {
  ($filename) = @_;

  my $dbh = &miscutils::dbhconnect('pnpmisc');

  my $sth = $dbh->prepare(
    q{
      SELECT overview, payallflag
      FROM salesforce
      WHERE username=?
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth->execute($reseller) or die "Can't execute: $DBI::errstr";
  my ( $allow_overview, $payallflag ) = $sth->fetchrow;
  $sth->finish;

  my $sql = "";
  if ( $reseller !~ /^(epenzio)$/ ) {
    $sql = "SELECT username,company,subacct,status,trans_date FROM customers ";

    if ( $reseller =~ /^($reseller::tech_list)$/ ) {
      $sql .= "WHERE username NOT LIKE 'epz%' AND status<>'cancelled'";
    } elsif ( $reseller eq "cableand" ) {
      $sql .= "WHERE reseller IN ('cableand','cccc','jncb','bdagov')";
    } elsif ( $reseller eq "manoaman" ) {
      $sql .= "WHERE reseller IN ('manoaman','sftman')";
    } else {
      $sql .= "WHERE reseller='$reseller'";
    }
    $sql .= " ORDER BY username";

    my $sth = $dbh->prepare(qq{$sql}) or die "Can't prepare: $DBI::errstr";
    $sth->execute() or die "Can't execute: $DBI::errstr";
    while ( my ( $username, $company, $tmp_subacct, $status, $trans_date ) = $sth->fetchrow ) {
      $userarray[ ++$#userarray ] = $username;
      if ( $tmp_subacct ne "" ) {
        $subacct[ ++$#subacct ] = $tmp_subacct;
      }
      $companyarray{$username}   = $company;
      $statusarray{$username}    = $status;
      $transdatearray{$username} = $trans_date;
    }
    $sth->finish;
  }

  if ( $reseller =~ /^($reseller::tech_list)$/ ) {
    my $sth = $dbh->prepare(
      q{
        SELECT DISTINCT reseller
        FROM customers
        ORDER BY reseller
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute or die "Can't execute: $DBI::errstr";
    while ( my ($var) = $sth->fetchrow ) {

      #@resellerarray = (@resellerarray,$var);
      $resellerarray[ ++$#resellerarray ] = "$var";
    }
    $sth->finish;

    my $sth2 = $dbh->prepare(
      q{
        SELECT username
        FROM salesforce
        ORDER BY username
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth2->execute or die "Can't execute: $DBI::errstr";
    while ( my ($var) = $sth2->fetchrow ) {

      #@salesagentarray = (@salesagentarray,$var);
      $salesagentarray[ ++$#salesagentarray ] = "$var";
    }
    $sth2->finish;
  }

  $dbh->disconnect;

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>PlugnPay/Reseller Administration Area</title>\n";
  print "<META HTTP-EQUIV='Pragma' CONTENT='no-cache'>\n";
  print "<META HTTP-EQUIV='Cache-Control' CONTENT='no-cache'>\n";

  print "<UN:$ENV{'REMOTE_USER'} SL:$ENV{'SEC_LEVEL'}, RES:$reseller>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"https://pay1.plugnpay.com/css/green.css\">\n";

  print "<script type=\"text/javascript\">\n";
  print "//<!-- Start Script\n";
  print "function results() {\n";
  print "  resultsWindow = window.open(\"/payment/recurring/blank.html\",\"results\",\"menubar=no,status=no,scrollbars=yes,resizable=yes,width=400,height=300\");\n";
  print "}\n";

  print "function onlinehelp(subject) {\n";
  print "  helpURL = '/online_help/' + subject + '.html';\n";
  print "  helpWin = window.open(helpURL,\"helpWin\",\"menubar=no,status=no,scrollbars=yes,resizable=yes,width=350,height=350\");\n";
  print "}\n";

  print "function change_win(targetURL,swidth,sheight) {\n";
  print "  SmallWin = window.open('', 'results','scrollbars=yes,resizable=yes,status=yes,toolbar=yes,menubar=yes,location=yes,height='+sheight+',width='+swidth);\n";
  print "  document.account.action = targetURL;\n";
  print "  document.account.target = 'results';\n";
  print "  document.account.submit();\n";
  print "}\n";

  print "//-->\n";
  print "</script>\n";
  print "</head>\n";

  print "<body>\n";

  print "<table>\n";
  print "  <tr>\n";
  print "    <td><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Payment Gateway Logo\" /></td>\n";
  print "    <td class=\"right\">&nbsp;</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td colspan=2><img src=\"/adminlogos/masthead_background.gif\" alt=\"Corp. Logo\" width=750 height=16 /></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table>\n";
  print "  <tr>\n";
  print "    <td><h1>Reseller Administration Area</h1></td>\n";
  if ( $ENV{'SERVER_NAME'} eq "reseller.plugnpay.com" ) {
    print "    <td align=right><a href=\"/admin/logout.cgi\">Logout</a></td>\n";
  }
  print "  </tr>\n";
  print "</table>\n";

  print "<hr id=\"under\" />\n";
  print "<table>\n";

  if ( $reseller::global_features->get('fileupload') == 1 ) {
    print "  <tr>\n";
    print "    <th class=\"labellp\" colspan=1 rowspan=2> Secure File Upload</th>\n";
    print "    <td><a href=\"/admin/secure_file_upload.cgi\">Secure File Upload</a></td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td colspan=2><hr id=\"middle\"></td>\n";
    print "  </tr>\n";
  }

  print "  <tr>\n";
  print "    <td colspan=2>&nbsp;</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th class=\"labellp\" colspan=1 rowspan=3>Information</th>\n";
  print "    <td colspan=1><form action=\"https://pay1.plugnpay.com/reseller_docs/\"><input type=submit value=\"Marketing\"></form></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=1><form method=\"post\" action=\"/admin/reseller_board.cgi\"><input type=submit value=\"Reseller FAQ\"></form></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=1><hr id=\"middle\"></td>\n";
  print "  </tr>\n";

  if ( $reseller =~ /^($reseller::tech_list)$/ ) {
    $rowspan = 10;
  } elsif ( $reseller =~ /^(epenzio)$/ ) {
    $rowspan = 10;
  } else {
    $rowspan = 13;
  }

  if ( $ENV{'SEC_LEVEL'} < 1 ) {
    print "  <tr>\n";
    print "    <th class=\"labellp\" colspan=1 rowspan=2> Security</th>\n";
    print "    <td><a href=\"/admin/security.cgi\">Change Reseller Password</a></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td colspan=2><hr id=\"middle\"></td>\n";
    print "  </tr>\n";
  }

  if ( $ENV{'SEC_LEVEL'} <= 4 ) {
    print "  <tr>\n";
    print "    <th class=\"labellp\" colspan=1 rowspan=\"$rowspan\"> Merchant Setup</th>\n";

    print "    <td><form action=\"$reseller::path_cgi\" method=post>\n";
    print "<input type=hidden name=\"function\" value=\"status\">\n";
    print "<input type=submit name=submit value=\"View Summary\"></form></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td>&nbsp;</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td colspan=1><form action=\"$reseller::path_cgi\" method=post>\n";
    print "<input type=hidden name=\"showcancelled\" value=\"no\">\n";
    print "<input type=submit name=\"function\" value=\"Show All Merchants\"></td></tr>\n";
    print "<tr><td><input type=submit name=\"function\" value=\"Show Non-cancelled Merchants Only\"></td></tr>\n";

    print "  <tr>\n";
    print "    <td>&nbsp;</td>\n";
    print "  </tr>\n";

    my %month_hash = ( '01', 'Jan', '02', 'Feb', '03', 'Mar', '04', 'Apr', '05', 'May', '06', 'Jun', '07', 'Jul', '08', 'Aug', '09', 'Sep', '10', 'Oct', '11', 'Nov', '12', 'Dec' );
    my ($date) = &miscutils::gendatetime_only();
    my $current_month = substr( $date, 4, 2 );
    my $current_year  = substr( $date, 0, 4 );
    print "<tr><td style=\"width:300px; background-color:#D0D0D0\"><b>Start Date: </b>\n";
    print "<select id=\"startmonth\" name=\"startmonth\">\n";
    if ( $query{'startmonth'} eq "" ) {
      $query{'startmonth'} = $current_month;
    }
    foreach my $var ( sort keys %month_hash ) {
      if ( $var eq $query{'startmonth'} ) {
        print "<option value=\"$var\" selected>$month_hash{$var}</option>\n";
      } else {
        print "<option value=\"$var\">$month_hash{$var}</option>\n";
      }
    }
    print "</select>\n";
    print "<select id=\"startyear\" name=\"startyear\">\n";
    if ( $query{'startyear'} eq "" ) {
      $query{'startyear'} = $current_year;
    }
    for ( my $var = 2009 ; $var <= $current_year + 1 ; $var++ ) {
      if ( $var eq $query{'startyear'} ) {
        print "<option value=\"$var\" selected>$var</option>\n";
      } else {
        print "<option value=\"$var\">$var</option>\n";
      }
    }
    print "</select>\n";
    print "<b> End Date: </b>\n";
    print "<select id=\"endmonth\" name=\"endmonth\">\n";
    if ( $query{'endmonth'} eq "" ) {
      $query{'endmonth'} = $current_month;
    }
    foreach my $var ( sort keys %month_hash ) {
      if ( $var eq $query{'endmonth'} ) {
        print "<option value=\"$var\" selected>$month_hash{$var}</option>\n";
      } else {
        print "<option value=\"$var\">$month_hash{$var}</option>\n";
      }
    }
    print "</select>\n";
    print "<select id=\"endyear\" name=\"endyear\">\n";
    if ( $query{'endyear'} eq "" ) {
      $query{'endyear'} = $current_year;
    }
    for ( my $var = 2009 ; $var <= $current_year + 1 ; $var++ ) {
      if ( $var eq $query{'endyear'} ) {
        print "<option value=\"$var\" selected>$var</option>\n";
      } else {
        print "<option value=\"$var\">$var</option>\n";
      }
    }
    print "</select>\n";
    print "<input type=submit name=\"function\" value=\"Show Merchants by Date Range\"></form>\n";
    print "</td></tr>\n";

    print "<tr><td>&nbsp;</td></tr>\n";

    if ( ( $reseller !~ /^($reseller::tech_list)$/ ) && ( $reseller !~ /^(epenzio)$/ ) ) {
      print "  <tr>\n";
      print "    <td colspan=1><form action=\"$reseller::path_cgi\" method=post>\n";
      print "<select name=\"username\">\n";
      if ( $query{'function'} eq "Show All Merchants" ) {
        foreach my $var (@userarray) {
          print "<option value=\"$var\"> $var, - $statusarray{$var} - $companyarray{$var} </option>\n";
        }
      } elsif ( $query{'function'} eq "Show Merchants by Date Range" ) {
        my $startdate = "$query{'startyear'}$query{'startmonth'}";
        my $enddate   = "$query{'endyear'}$query{'endmonth'}";
        foreach my $var (@userarray) {
          my $transyearmonth = substr( $transdatearray{$var}, 0, 6 );
          if ( ( $transyearmonth >= $startdate ) && ( $transyearmonth <= $enddate ) ) {
            print "<option value=\"$var\"> $var, - $statusarray{$var} - $companyarray{$var} - $transdatearray{$var}</option>\n";
          }
        }
      } else {    #show non-cancelled by default
        foreach my $var (@userarray) {
          if ( $statusarray{$var} ne "cancelled" ) {
            print "<option value=\"$var\"> $var, - $statusarray{$var} - $companyarray{$var} </option>\n";
          }
        }
      }
      print "</select></td>\n";
      print "  </tr>\n";

      #print "<select name=\"username\">\n";
      #foreach my $var (@userarray) {
      #  print "<option value=\"$var\"> $var, - $statusarray{$var} - $companyarray{$var} </option>\n";
      #}
      #print "</select></td>\n";
      #print "</tr>\n";

      print "  <tr>\n";
      print "    <td align=left><input type=submit name=function value=\"Edit Status\">\n";
      print " &nbsp; <input type=submit name=function value=\"Edit Account Info\"></td></form>\n";
      print "  </tr>\n";

      print "  <tr>\n";
      print "    <td>&nbsp;</td>\n";
      print "  </tr>\n";

    }

    print "  <tr>\n";
    print "    <td colspan=1><form action=\"$reseller::path_cgi\" method=post>\n";
    print "Username: <input type=text name=\"username\" size=16></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td align=left> <input type=submit name=function value=\"Edit Status\">\n";
    print " &nbsp; <input type=submit name=function value=\"Edit Account Info\"></td></form>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td colspan=2><hr id=\"middle\"></td>\n";
    print "  </tr>\n";

    if ( $reseller =~ /^(epenzio)$/ ) {
      print "  <tr>\n";
      print "    <th class=\"labellp\" colspan=1>Passwords</th>\n";
      print "    <td colspan=1><form action=\"$reseller::path_cgi\" method=post target=\"passwd_Win\">\n";
      print "<input type=hidden name=\"format\" value=\"text\">\n";
      print "<input type=submit name=function value=\"View Password File\"> &nbsp; <input type=submit name=function value=\"Delete Password File\"></form></td>\n";
      print "  </tr>\n";
    }
  }

  if ( ( $reseller::global_features->get('risktrak') == 1 ) && ( $ENV{'SEC_LEVEL'} <= 7 ) ) {
    print "  <tr>\n";
    print "    <th class=\"labellp\" rowspan=2>Risk Management</th>\n";
    print "    <td><form action=\"/admin/riskmgmt.cgi\" method=\"post\" target=\"passwd_Win\">\n";
    print "<input type=submit name=\"function\" value=\"Risk Management\"></form></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td colspan=2><hr id=\"middle\"></td>\n";
    print "  </tr>\n";
  }

  if ( $reseller =~ /^(northame)$/ ) {
    print "  <tr>\n";
    print "    <th class=\"labellp\" rowspan=1><font>Billing Rates \& Fees</font></th>\n";
    print "    <td colspan=1>\n";
    if ( $reseller =~ /^(unplugged)$/ ) {
      print "<form action=\"/admin/billing_pnp.cgi\" method=post>\n";
    } else {
      print "<form action=\"/admin/billing.cgi\" method=post>\n";
    }
    print "<select name=\"username\">\n";
    foreach my $var (@userarray) {
      print "<option value=\"$var\"> $var, - $statusarray{$var} - $companyarray{$var}</option>\n";
    }
    print "<option value=\"EVERY\"> EVERY MERCHANT </option>\n";
    print "</select><br>\n";
    print "Sub Acct: <select name=\"subacct\">\n";
    print "<option value=\"\" selected>No Subacct</option>\n";
    foreach my $var (@subacct) {
      print "<option value=\"$var\">$var </option>\n";
    }
    print "</select> If Applicable.<br>\n";
    print "<input type=hidden name=\"mode\" value=\"addfee\">\n";
    print "<input type=submit name=\"submit\" value=\"Add/Edit Merchant Fees\">\n";
    print "</form>\n";
    print "<br></td>\n";
    print "  </tr>\n";
  }

  if ( $ENV{'SEC_LEVEL'} <= 4 ) {
    print "  <tr>\n";
    print "    <th class=\"labellp\" colspan=1 rowspan=2>Application</th>\n";
    print "    <td><form action=\"$reseller::path_cgi\" method=\"post\">\n";
    print "<input type=hidden name=\"function\" value=\"editapp\">\n";
    print "<input type=submit name=\"submit\" value=\"Add New Merchant\"></form></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td colspan=2><hr id=\"middle\"></td>\n";
    print "  </tr>\n";
  }

  if ( ( $reseller::global_features->get('uploadbatch') == 1 ) && ( $ENV{'SEC_LEVEL'} <= 4 ) ) {

    print "  <tr>\n";
    print "    <th class=\"labellp\" rowspan=3>Upload Batch<br>Merchant File</th>\n";

    #print "    <td> Temporarily unavailable </td>\n";
    print "    <td><form action=\"$reseller::path_cgi\" method=\"post\" enctype=\"multipart/form-data\">\n";
    print "<input type=hidden name=\"function\" value=\"batch\">\n";
    print "<input type=file name=\"filename\" value=\"File\"></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td><input type=submit name=\"submit\" value=\"Upload\"></td></form>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td colspan=2><hr id=\"middle\"></td>\n";
    print "  </tr>\n";
  }

  if ( $allow_overview ne "" ) {
    print "  <tr>\n";
    print "    <th class=\"labellp\" rowspan=2>Merchant Overview</th>\n";
    print "    <td colspan=1><a href=\"overview/\">Merchant Overview</a><br>\n";
    print "  </td>\n";

    print "  <tr>\n";
    print "    <td colspan=1><hr id=\"middle\"></td>\n";
    print "  </tr>\n";
  }

  # only show button for resellers which are either not payall or were white listed
  if ( ( ( $payallflag != 1 ) || ( $ENV{'REMOTE_USER'} =~ /^(payameri|interna4|interna5|payprote|franchis|lawpay)$/ ) )
    && ( ( $ENV{'SEC_LEVEL'} < 1 ) && ( $reseller::hide_area{ $ENV{'REMOTE_USER'} } !~ /commissions/ ) ) ) {

    my @now          = gmtime(time);
    my $current_year = $now[5] + 1900;

    print "  <tr>\n";
    print "    <th class=\"labellp\" rowspan=7>Commissions</th>\n";

    if ( $ENV{'REMOTE_USER'} =~ /^(cprice|michelle|barbara|plugnpay|unplugged)$/ ) {
      print "<form action=\"$reseller::path_cgi\" method=\"post\" target=\"commissionwin\">\n";
    } else {
      print "<form action=\"$reseller::path_cgi\" method=\"post\">\n";
    }
    print "<input type=hidden name=\"resellmerchant\" value=\"$query{'resellmerchant'}\">\n";
    print "<input type=hidden name=\"function\" value=\"commission\">\n";

    if ( $reseller =~ /^($reseller::tech_list)$/ ) {
      print "  <td align=left>Reseller: &nbsp; &nbsp; &nbsp; &nbsp; <select name=\"srchreseller\" multiple size=4>\n";
      print "<option value=\"\">All</option>\n";
      foreach my $var (@resellerarray) {
        print "<option value=\"$var\">$var</option>\n";
      }
      print "</select>\n";
      print "<input type=checkbox name=\"not\" value=\"yes\"> Not</td>\n";
      print "  </tr>\n";

      print "  <td align=left>Sales Agent: &nbsp; <select name=\"srchsalesagent\">\n";
      print "<option value=\"\">All</option>\n";
      foreach my $var (@salesagentarray) {
        print "<option value=\"$var\">$var</option>\n";
      }
      print "</select></td>\n";
      print "  </tr>\n";
    } else {
      print "  <tr>\n";
      print "    <td>&nbsp;</td>\n";
      print "  </tr>\n";
    }

    print "  <tr>\n";
    print "    <td align=left>Start Date: &nbsp; &nbsp; &nbsp; \n";
    print "<select name=startmonth>\n";
    print "<option>Jan</option>\n";
    print "<option>Feb</option>\n";
    print "<option>Mar</option>\n";
    print "<option>Apr</option>\n";
    print "<option>May</option>\n";
    print "<option>Jun</option>\n";
    print "<option>Jul</option>\n";
    print "<option>Aug</option>\n";
    print "<option>Sep</option>\n";
    print "<option>Oct</option>\n";
    print "<option>Nov</option>\n";
    print "<option>Dec</option>\n";
    print "</select>\n";
    print "<select name=\"startday\">\n";

    for ( my $day = 1 ; $day <= 31 ; $day++ ) {
      print "<option";
      if ( $day == 20 ) {
        print " selected>";
      } else {
        print ">";
      }
      printf( "%02d</option>\n", $day );
    }

    print "</select>\n";
    print "<select name=startyear>\n";
    for ( my $year = 2009 ; $year <= $current_year + 1 ; $year++ ) {
      print "<option";
      if ( $year == $current_year ) {
        print " selected>";
      } else {
        print ">";
      }
      printf( "%04d</option>\n", $year );
    }
    print "</select></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td align=left>End Date: &nbsp; &nbsp; &nbsp;&nbsp;\n";
    print "<select name=endmonth>\n";
    print "<option>Jan</option>\n";
    print "<option>Feb</option>\n";
    print "<option>Mar</option>\n";
    print "<option>Apr</option>\n";
    print "<option>May</option>\n";
    print "<option>Jun</option>\n";
    print "<option>Jul</option>\n";
    print "<option>Aug</option>\n";
    print "<option>Sep</option>\n";
    print "<option>Oct</option>\n";
    print "<option>Nov</option>\n";
    print "<option>Dec</option>\n";
    print "</select>\n";
    print "<select name=\"endday\">\n";

    for ( my $day = 1 ; $day <= 31 ; $day++ ) {
      print "<option";
      if ( $day == 20 ) {
        print " selected>";
      } else {
        print ">";
      }
      printf( "%02d</option>\n", $day );
    }

    print "</select>\n";
    print "<select name=endyear>\n";
    for ( my $year = 2009 ; $year <= $current_year + 1 ; $year++ ) {
      print "<option";
      if ( $year == $current_year ) {
        print " selected>";
      } else {
        print ">";
      }
      printf( "%04d</option>\n", $year );
    }
    print "</select></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td align=left>Report Format: <input type=radio name=\"format\" value=\"table\" checked> Table &nbsp; <input type=radio name=\"format\" value=\"text\"> Text</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td><input type=submit name=\"submit\" value=\"Generate Commission Report\"></td></form>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td><hr id=\"middle\"></td>\n";
    print "  </tr>\n";
  }

  if ( $reseller::hide_area{ $ENV{'REMOTE_USER'} } !~ /rates/ ) {
    print "  <tr>\n";
    print "    <th class=\"labellp\" colspan=1 rowspan=2>Buy Rates</th>\n";
    print "  <td>\n";

    # if reseller display own buy rates
    # is sales display list of resellers

    print "<form action=\"$reseller::path_cgi\" method=\"post\">\n";
    print "<input type=hidden name=\"function\" value=\"viewbuyrates\">\n";

    if ( $reseller =~ /^(rriding|devresell)$/ ) {
      print "<select name=\"reseller\">\n";
      my $user    = "";
      my $sth_res = $dbh->prepare(
        q{
           SELECT username,company,status
           FROM salesforce
           ORDER BY username
        }
        )
        or die "cant prepare $DBI::errstr\n";
      $sth_res->execute() or die "cant execute $DBI::errstr\n";
      while ( my ( $user, $company, $status ) = $sth_res->fetchrow ) {
        print "<option value=\"$user\"> $user - $status - $company</option>\n";
      }
      $sth_res->finish;
      print "</select>\n";
    } elsif ( $reseller =~ /^(michell|brianro2|brianro3|bridgevi|cashlinq|cardpaym|cpscorp|dmongell|wdunkak|globalpy|planetpa)$/ ) {
      print "<select name=\"reseller\">\n";
      my $user    = "";
      my $sth_res = $dbh->prepare(
        q{
           SELECT username,company,status
           FROM salesforce
           WHERE salesagent=?
           ORDER BY username
        }
        )
        or die "cant prepare $DBI::errstr\n";
      $sth_res->execute("$reseller") or die "cant execute $DBI::errstr\n";
      print "<option value=\"$reseller\"> $reseller </option>\n";
      while ( my ( $user, $company, $status ) = $sth_res->fetchrow ) {
        print "<option value=\"$user\"> $user - $status - $company </option>\n";
      }
      $sth_res->finish;
      print "</select>\n";
    } else {
      print "<input type=hidden name=\"reseller\" value=\"$reseller\">\n";
    }
    print "<br><input type=submit value=\"View Rates\"></form></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td><hr id=\"middle\"></td>\n";
    print "  </tr>\n";
  }

  if ( $reseller::global_features->get('impchargebacks') == 1 ) {
    print "  <tr>\n";
    print "    <th class=\"labellp\" colspan=1 rowspan=4>Import Chargebacks</th>\n";
    print "    <td><form action=\"$reseller::path_cgi\" method=\"post\" enctype=\"multipart/form-data\">\n";
    print "<input type=hidden name=\"function\" value=\"chargeback_import\">\n";
    print " File: <input type=file name=\"data\"></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td>Processor: <select name=\"processor\">\n";
    foreach my $proc ( sort keys %reseller::cb_processors ) {
      print "<option value=\"$proc\">$reseller::cb_processors{$proc}</option>\n";
    }
    print "</select></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td><input type=submit name=\"submit\" value=\"Import File\"></form></td>\n";
    print "  </tr>\n";

    print qq|
    <tr>
      <td colspan=2><hr id="middle"></td>
    </tr>|;
  }

  # Edit Contact Info, Billing Auth, Commission Payment Info
  print qq|
  <tr>
    <th class="labellp" colspan=1 rowspan=2>Contact Information</th>
    <td>
      <form action="/admin/change.cgi" method=\"post\">
        <input type=submit name="submit" value="Edit Contact Information">
      </form>
    </td>
  </tr>|;

  print qq|
  <tr>
    <td colspan=2><hr id="middle"></td>
  </tr>|;

  print qq|
  <tr>
    <th class="labellp" colspan=1 rowspan=2>Billing Information</th>
    <td>
      Login to the <a href="https://pay1.plugnpay.com/admin/" target="_blank">PNP administration area</a> with your reseller username and password.<br>
      Under the Billing section - Click on Billing Authorization - complete form provided.<br>
      <em>Note:</em> All other links are not valid or usable for a reseller.
    </td>
  </tr>|;

  print qq|
  <tr>
    <td colspan=2><hr id="middle"></td>
  </tr>|;

  # only show button for resellers which has an account signed up & are either not payall or were white listed)
  if ( ( $payallflag != 1 ) || ( $ENV{'REMOTE_USER'} =~ /^(payameri|interna5|payprote|franchis|lawpay)$/ ) ) {
    print qq|
    <tr>
      <th class="labellp">Commission Information</th>
      <td>
        <form action="/admin/commission_change.cgi" method="post">
          <input type=submit name="submit" value="Commission Payout Information">
        </form>
      </td>
    </tr>|;
  }

  print "</table>\n";

  my @now          = gmtime(time);
  my $current_year = $now[5] + 1900;

  print "<hr id=\"over\" />\n";
  print "<table class=\"frame\">\n";
  print "  <tr>\n";
  print "    <td align=left><a href=\"/admin/online_helpdesk.cgi\" target=\"ahelpdesk\">Help Desk</a></td>\n";
  print "    <td class=\"right\">&copy; $current_year, Plug 'n Pay Technologies, Inc.</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</body>\n";
  print "</html>\n";
}

# Get an array of resellers that pay all
sub resellersThatPayAll {
  my @payAllResellers;
  my $dbh = &miscutils::dbhconnect( 'pnpmisc', 'yes' );
  my $sth = $dbh->prepare(
    q{
      SELECT username
      FROM salesforce
      WHERE payallflag = "1"
    }
    )
    or die("Can't prepare: $DBI::errstr");
  $sth->execute() or die("Can't execute: $DBI::errstr");
  while ( my @row = $sth->fetchrow_array() ) {
    push( @payAllResellers, $row[0] );
  }
  $sth->finish;
  $dbh->disconnect;

  return @payAllResellers;
}

# returns array of resellers that dont send bill auths, includes resellers that pay all
sub resellersThatDontSendBillAuth {
  my %sendBillAuthResellers;

  # all pay all resellers do not send bill auths.
  map { $sendBillAuthResellers{$_} = 1 } resellersThatPayAll();

  # get resellers that have send bill auths set.
  my $dbh = &miscutils::dbhconnect( 'pnpmisc', 'yes' );
  my $sth = $dbh->prepare(
    q{
      SELECT username
      FROM salesforce
      WHERE sendbillauth = "0"
    }
  );
  $sth->execute() or die("Can't execute: $DBI::errstr");
  while ( my @row = $sth->fetchrow_array() ) {
    $sendBillAuthResellers{ $row[0] } = 1;
  }
  $sth->finish;
  $dbh->disconnect;

  return keys %sendBillAuthResellers;
}

# returns wether or not a reseller sends bill auth, 0 is false, nonzero is true
# note that this checks both payallflag AND sendbillauth fields.
sub resellerSendsBillAuth {
  my $reseller = shift;
  $reseller =~ s/[^a-z0-9]//g;

  my $dbh = &miscutils::dbhconnect( 'pnpmisc', 'yes' );
  my $sth = $dbh->prepare(
    q{
      SELECT count(*) as b
      FROM salesforce
      WHERE (payallflag = "1"
      OR sendbillauth = "0")
      AND username = ?
    }
  );
  $sth->execute($reseller);
  my $row = $sth->fetchrow_hashref();
  my $val = $row->{'b'};
  $sth->finish;
  $dbh->disconnect;

  return !int($val);
}

# returns wether or not a reseller pays all fees, 0 is false, nonzero is true
sub resellerPaysAllFees {
  my $reseller = shift;
  $reseller =~ s/[^a-z0-9]//g;

  my $dbh = &miscutils::dbhconnect( 'pnpmisc', 'yes' );
  my $sth = $dbh->prepare(
    q/
      SELECT count(*) as b
      FROM salesforce
      WHERE payallflag = "1"
      AND username = ?
    /
  );
  $sth->execute($reseller);
  my $row = $sth->fetchrow_hashref();
  my $val = $row->{'b'};
  $sth->finish;
  $dbh->disconnect;

  return int($val);
}

sub editstatus {
  $username = $query{'username'};
  $username =~ s/[^a-zA-Z0-9]//g;

  $reseller =~ s/[^a-zA-Z0-9]//g;

  $dbh = &miscutils::dbhconnect('pnpmisc');

  $sth = $dbh->prepare(
    qq{
        SELECT merchacct,pnptype,hosting,shopcart,download,affiliate,membership,submit_date,submit_status,sent_date,tracknum,return_date,ftpun,ftppw,ftphost,url,fromemail,recmessage,memberdir,autobatch,chkautobatch,recurbatch,recurbill,refresh,lookahead,email_choice,recnotifemail,installbilling,fraudtrack,affiliate,coupon,fulfillment,chkrecurbatch,easycart,billpay
        FROM pnpsetups
        WHERE username=?
      }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth->execute("$username") or die "Can't execute: $DBI::errstr";
  ( $merchacct, $pnptype,      $hosting,       $shopcart,       $download,   $affiliate,  $membership, $submit_date, $submit_status, $sent_date,  $tracknum,  $return_date,
    $ftpun,     $ftppw,        $ftphost,       $url,            $fromemail,  $recmessage, $memberdir,  $autobatch,   $chkautobatch,  $recurbatch, $recurbill, $refresh,
    $lookahead, $email_choice, $recnotifemail, $installbilling, $fraudtrack, $affiliate,  $coupon,     $fulfillment, $chkrecurbatch, $easycart,   $billpay
  )
    = $sth->fetchrow;
  $sth->finish;

  $sth = $dbh->prepare(
    qq{
      SELECT status,company
      FROM customers
      WHERE username=?
      AND reseller=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth->execute( "$username", "$reseller" ) or die "Can't execute: $DBI::errstr";
  ( $status, $company ) = $sth->fetchrow;
  $sth->finish;

  $submit_date = &miscutils::datetostr($submit_date);
  $sent_date   = &miscutils::datetostr($sent_date);
  $return_date = &miscutils::datetostr($return_date);

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title> Reseller Administration</title>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"https://pay1.plugnpay.com/css/green.css\">\n";
  print "<META HTTP-EQUIV='Pragma' CONTENT='no-cache'>\n";
  print "<META HTTP-EQUIV='Cache-Control' CONTENT='no-cache'>\n";

  print "<style text=\"text/css\">\n";
  print "<\!--\n";
  print "th.labellp {\n";
  print "  padding: 2px 2px 10px 2px;\n";
  print "}\n";
  print "// -->\n";
  print "</style>\n";

  my $captcha = new PlugNPay::Util::Captcha::ReCaptcha();
  print $captcha->headHTML();

  print "</head>\n";

  print "<body bgcolor=\"#ffffff\">\n";

  print "<form action=\"$reseller::path_cgi\" method=post>\n";
  print "<input type=hidden name=\"pnptype\" value=\"core\">\n";
  print "<input type=hidden name=\"username\" value=\"$username\">\n";
  print "<input type=hidden name=\"function\" value=\"updatestatus\">\n";

  print "<table>\n";
  print "  <tr>\n";
  print "    <td><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Payment Gateway Logo\" /></td>\n";
  print "    <td class=\"right\">&nbsp;</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td colspan=2><img src=\"/adminlogos/masthead_background.gif\" alt=\"Corp. Logo\" width=750 height=16 /></td>\n";
  print "    </tr>\n";
  print "</table>\n";

  print "<table border=0 cellspacing=0>\n";

  if ( $error > 0 ) {
    print "  <tr>\n";
    print "    <th class=\"badcolor\" valign=top><b>ERROR: </b></th>\n";
    print "    <td class=\"badcolor\"><b>Some Required Information is missing.<br>Please complete the fields marked in RED. <br>\n";
    my @errors = split( /\:/, $errvar );
    foreach my $tmperr (@errors) {
      print "<i>$tmperr</i> <br>\n";
    }
    print "</b></td></tr>\n";
  }

  print "  <tr>\n";
  print "    <th class=\"labellp\">Username:</th>\n";
  print "    <td>$username</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th class=\"labellp\">Status:</th>\n";
  print "    <td>Submitted: $submit_date<br>\n";
  print "Status: $status</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th class=\"labellp\">Company:</th>\n";
  print "    <td>$company</td>\n";
  print "  </tr>\n";

  %selected = {};
  $selected{$autobatch} = " selected";
  print "  <tr>\n";
  print "    <th class=\"labellp\">Auto Batching:</th>\n";
  print "    <td><select name=\"autobatch\">\n";
  print "<option value=\"\">No autobatch</option>\n";
  print "<option value=\"0\"$selected{'0'}>Same Day</option>\n";
  print "<option value=\"1\"$selected{'1'}>Next Day</option>\n";
  print "<option value=\"2\"$selected{'2'}>2 Days</option>\n";
  print "<option value=\"3\"$selected{'3'}>3 Days</option>\n";
  print "<option value=\"4\"$selected{'4'}>4 Days</option>\n";
  print "<option value=\"5\"$selected{'5'}>5 Days</option>\n";
  print "<option value=\"6\"$selected{'6'}>6 Days</option>\n";
  print "<option value=\"7\"$selected{'7'}>7 Days</option>\n";
  print "<option value=\"14\"$selected{'14'}>14 Days</option>\n";
  print "</select> Delay\n";
  print "<p><nobr>* Selecting an option other than Same Day may result in an increase in merchant bank account rates</nobr></td>\n";
  print "  </tr>\n";

  %selected = {};
  $selected{$chkautobatch} = " selected";
  print "  <tr>\n";
  print "    <th class=\"labellp\">Auto Batching eChecks:</th>\n";
  print "    <td><select name=\"chkautobatch\">\n";
  print "<option value=\"\">No autobatch</option>\n";
  print "<option value=\"0\"$selected{'0'}>Same Day</option>\n";
  print "<option value=\"1\"$selected{'1'}>Next Day</option>\n";
  print "<option value=\"2\"$selected{'2'}>2 Days</option>\n";
  print "<option value=\"3\"$selected{'3'}>3 Days</option>\n";
  print "<option value=\"4\"$selected{'4'}>4 Days</option>\n";
  print "<option value=\"5\"$selected{'5'}>5 Days</option>\n";
  print "<option value=\"6\"$selected{'6'}>6 Days</option>\n";
  print "<option value=\"7\"$selected{'7'}>7 Days</option>\n";
  print "<option value=\"14\"$selected{'14'}>14 Days</option>\n";
  print "</select> Delay\n";
  print "<p><nobr>* Only used if merchant is setup for echeck processing</nobr></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"label\" colspan=2>Additional Services</td>\n";
  print "  </tr>\n";

  %selected = {};
  $selected{$download} = " checked";
  print "  <tr>\n";
  print "    <th class=\"labellp\">Download:</th>\n";
  print "    <td><input type=checkbox name=\"download\" value=\"yes\"$selected{'yes'} ";
  if ( ( $reseller::tech_list !~ /$reseller/i ) && ( $reseller::function ne "updateapp" ) ) {
    print "DISABLED";
  }
  print "> Download</td>\n";
  print "  </tr>\n";

  $selected{$fraudtrack} = " checked";
  print "  <tr>\n";
  print "    <th class=\"labellp\">FraudTrak 2:</th>\n";
  print "    <td><input type=checkbox name=\"fraudtrack\" value=\"1\"$selected{'1'} ";
  if ( ( $reseller::tech_list !~ /$reseller/i ) && ( $reseller::function ne "updateapp" ) ) {
    print "DISABLED";
  }
  print "> FraudTrak 2</td>\n";
  print "  </tr>\n";

  %selected = {};
  $selected{$coupon} = " checked";
  print "  <tr>\n";
  print "    <th class=\"labellp\">Coupon Management:</th>\n";
  print "    <td><input type=checkbox name=\"coupon\" value=\"1\"$selected{'1'} ";
  if ( ( $reseller::tech_list !~ /$reseller/i ) && ( $reseller::function ne "updateapp" ) ) {
    print "DISABLED";
  }
  print "> Coupon Management</td>\n";
  print "</tr>\n";

  %selected = {};
  $selected{$fulfillment} = " checked";
  print "  <tr>\n";
  print "    <th class=\"labellp\">Fulfillment Management:</th>\n";
  print "    <td><input type=checkbox name=\"fulfillment\" value=\"1\"$selected{'1'} ";
  if ( ( $reseller::tech_list !~ /$reseller/i ) && ( $reseller::function ne "updateapp" ) ) {
    print "DISABLED";
  }
  print "> Fulfillment Management</td>\n";
  print "  </tr>\n";

  %selected = {};
  $selected{$billpay} = " checked";
  print "  <tr>\n";
  print "    <th class=\"labellp\">BillPay:</th>\n";
  print "    <td><input type=checkbox name=\"billpay\" value=\"membership\"$selected{'membership'} ";
  if ( ( $reseller::tech_list !~ /$reseller/i ) && ( $reseller::function ne "updateapp" ) ) {
    print "DISABLED";
  }
  print "> Billing Presentment</td>\n";
  print "  </tr>";

  %selected = {};
  $selected{$membership} = " checked";
  print "  <tr>\n";
  print "    <th class=\"labellp\">Membership:</th>\n";
  print "    <td><input type=radio name=\"membership\" value=\"\"$selected{''}> None\n";
  print "      <input type=radio name=\"membership\" value=\"membership\"$selected{'membership'}> Recurring w/password management\n";
  print "      <input type=radio name=\"membership\" value=\"recurring\"$selected{'recurring'}> Recurring Only\n";
  print "    </td>\n";
  print "  </tr>\n";

  if ( $reseller =~ /^($reseller::tech_list)$/ ) {
    print "  <tr>\n";
    print "    <th class=\"labellp\" valign=top>Recurring<br>Info:</th>\n";
    print "    <td>";

    # start recurring settings section
    print "<table style=\"border:1px solid #dddddd;\">\n";
    print "  <tr>\n";
    print "    <th class=\"leftside\">RecurBill</th>\n";
    %selected = {};
    $selected{$recurbill} = " checked";
    print "    <td class=\"rightside\"><input type=checkbox name=\"recurbill\" value=\"yes\"$selected{'yes'}> RecurBill</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <th class=\"leftside\">Installment Billing</th>\n";
    %selected = {};
    $selected{$installbilling} = " checked";
    print "    <td class=\"rightside\"><input type=checkbox name=\"installbilling\" value=\"yes\"$selected{'yes'}> Enable Installment Billing</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <th class=\"leftside\">RecurBatch ACH</th>\n";
    %selected = {};
    $selected{$chkrecurbatch} = " checked";
    print "    <td class=\"rightside\"><input type=checkbox name=\"chkrecurbatch\" value=\"yes\"$selected{'yes'}> RecurBatch ACH</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <th class=\"leftside\">RecurBatch CC</th>\n";
    if ( $recurbatch eq "" ) {
      $recurbatch = "yes";
    }
    %selected = {};
    $selected{$recurbatch} = " checked";
    print "    <td class=\"rightside\"><input type=checkbox name=\"recurbatch\" value=\"yes\"$selected{'yes'}> RecurBatch Credit Cards</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <th class=\"leftside\">Refresh</th>\n";
    %selected = {};
    $selected{$refresh} = " checked";
    print "    <td class=\"rightside\"><input type=checkbox name=\"refresh\" value=\"yes\"$selected{'yes'}> Refresh</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <th class=\"leftside\">Lookahead Days</th>\n";
    print "    <td class=\"rightside\"><input type=text name=\"lookahead\" value=\"$lookahead\" size=2></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <th class=\"leftside\">Email Choice</th>\n";
    %selected = {};
    $selected{$email_choice} = " checked";
    print "    <td class=\"rightside\"><nobr><input type=radio name=\"email_choice\" value=\"\"$selected{''}> None \&nbsp;\&nbsp;\n";
    print "<input type=radio name=\"email_choice\" value=\"email_customer\"$selected{'email_customer'}> Email Customer \&nbsp;\&nbsp;\n";
    print "<input type=radio name=\"email_choice\" value=\"email_merchant\"$selected{'email_merchant'}> Email Merchant \&nbsp;\&nbsp;\n";
    print "<input type=radio name=\"email_choice\" value=\"email_both\"$selected{'email_both'}> Email Both</nobr></td>";
    print "  </tr>\n";

    #print "  <tr>\n";
    #print "    <th class=\"leftside\">DO NOT USE THESE YET -> \&nbsp;</th>\n";
    #print "    <td class=\"rightside\"><input type=radio name=\"email_choice\" value=\"email_cust_suc\"$selected{'email_cust_suc'}> Email Cust Success";
    #print "<input type=radio name=\"email_choice\" value=\"email_merch_suc\"$selected{'email_merch_suc'}> Email Merch Success";
    #print "<input type=radio name=\"email_choice\" value=\"email_both_suc\"$selected{'email_both_suc'}> Email Both Success";
    #print "<input type=radio name=\"email_choice\" value=\"email_both_all\"$selected{'email_both_all'}> Email Both All</td>\n";
    #print "  </tr>\n";

    print "  <tr>\n";
    print "    <th class=\"leftside\">FTP Username</th>\n";
    print "    <td class=\"rightside\"><input type=text name=\"ftpun\" value=\"$ftpun\" size=11 autocomplete=\"off\"></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <th class=\"leftside\">FTP Password</th>\n";
    print "    <td class=\"rightside\"><input type=text name=\"ftppw\" value=\"$ftppw\" size=11 autocomplete=\"off\"></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <th class=\"leftside\">FTP Host</th>\n";
    print "    <td class=\"rightside\"><input type=text name=\"ftphost\" value=\"$ftphost\" size=39></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <th class=\"leftside\">URL</th>\n";
    print "    <td class=\"rightside\"><input type=text name=\"url\" value=\"$url\" size=39></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <th class=\"leftside\">Member Dir</th>\n";
    print "    <td class=\"rightside\"><input type=text name=\"memberdir\" value=\"$memberdir\" size=39></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <th class=\"leftside\">Recurring Notification Email</th>\n";
    print "    <td class=\"rightside\"><input type=text name=\"recnotifemail\" value=\"$recnotifemail\" size=29></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <th class=\"leftside\">From Email</th>\n";
    print "    <td class=\"rightside\"><input type=text name=\"fromemail\" value=\"$fromemail\" size=29></td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <th class=\"leftside\">Rec Message</th>\n";
    print "    <td class=\"rightside\"><textarea name=\"recmessage\" rows=\"5\" cols=\"50\" wrap=\"virtual\">$recmessage</textarea></td>\n";
    print "  </tr>\n";
    print "</table>\n";

    # end recurring settings section
    print "</td>\n";
    print "  </tr>\n";
  }

  if ( $ENV{'REMOTE_USER'} =~ /^($reseller::tech_list)$/ ) {
    print "  <tr>\n";
    print "    <th class=\"labellp\">&nbsp;</th>\n";
    print "    <td>&nbsp;</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <th class=\"labellp\">Comments:</th>\n";
    print "    <td><b>*Comments are only viewed at time of signup*</b><br>\n";
    print "<select name=\"history\">";

    my $sth_comments = $dbh->prepare(
      q{
        SELECT username,orderid,message
        FROM comments
        WHERE username=?
        ORDER BY orderid
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_comments->execute("$username") or die "Can't execute: $DBI::errstr";
    while ( my ( $username, $orderid, $message ) = $sth_comments->fetchrow ) {
      $temp = substr( $message, 0, 80 );
      print "<option value=\"$orderid\">$temp</option>";
    }
    $sth_comments->finish;

    print "</select><br>";
    print "<textarea name=\"newcomment\" rows=\"5\" cols=\"40\" wrap=\"virtual\"></textarea></td>\n";
    print "  </tr>\n";
  }

  print "  <tr>\n";
  print "    <th class=\"labellp\">&nbsp;</th>\n";
  print "    <td>&nbsp;</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th class=\"labellp $color{'captcha'}\">Captcha:</th>\n";
  print "    <td>" . $captcha->formHTML() . "</td>\n";
  print "  </tr>\n";

  $dbh->disconnect;

  print "  <tr>\n";
  print "    <th class=\"labellp\">&nbsp;</th>\n";
  print "    <td><input type=submit name=\"submit\" value=\"Submit Changes\"></td></form>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th class=\"labellp\">&nbsp;</th>\n";
  print "    <td><form method=\"post\" action=\"$reseller::path_cgi\" target=\"comments\">\n";
  print "<input type=hidden name=\"function\" value=\"comments\">\n";
  print "<input type=hidden name=\"username\" value=\"$username\">\n";
  print "<input type=submit name=\"submit\" value=\"View Comments\">\n";
  print "</form></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th class=\"labellp\">&nbsp;</th>\n";
  print "    <td><form action=\"$reseller::path_cgi\" method=post>\n";
  print "<input type=submit name=\"submit\" value=\"Home Page\">\n";
  print "</form></td>\n";
  print "  </tr>\n";

  print "</table>\n";

  print "</body>\n";
  print "</html>\n";
}

sub comments {
  $username = $query{'username'};
  $username =~ s/[^0-9a-zA-Z]//g;
  $username = substr( $username, 0, 15 );

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Reseller Administration</title>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"stylesheet.css\">\n";
  print "<META HTTP-EQUIV='Pragma' CONTENT='no-cache'>\n";
  print "<META HTTP-EQUIV='Cache-Control' CONTENT='no-cache'>\n";
  print "</head>\n";

  print "<body bgcolor=\"#ffffff\">\n";
  print "<table border=1>\n";

  $dbh          = &miscutils::dbhconnect('pnpmisc');
  $sth_comments = $dbh->prepare(
    q{
      SELECT username,orderid,message
      FROM comments
      WHERE username=?
      ORDER BY orderid
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth_comments->execute("$username") or die "Can't execute: $DBI::errstr";
  while ( my ( $username, $orderid, $message ) = $sth_comments->fetchrow ) {
    print "  <tr>\n";
    printf( "    <th align=left valign=top>%02d/%02d/%04d</th>\n", substr( $orderid, 4, 2 ), substr( $orderid, 6, 2 ), substr( $orderid, 0, 4 ) );
    print "    <td>$message</td>\n";
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <th colspan=2><hr width=400></th>\n";
    print "  </tr>\n";
  }
  $sth_comments->finish;
  $dbh->disconnect;

  print "</table>\n";

  print "</body>\n";
  print "</html>\n";
}

sub editcust {
  $username = $query{'username'};

  $dbh = &miscutils::dbhconnect('pnpmisc');
  $qstr =
    "SELECT name,company,addr1,addr2,city,state,zip,country,tel,fax,email,techname,techtel,techemail,url,status,cards_allowed,bank,routing,acct,card_number,exp_date,processor,proc_type,merchant_id,pubsecret,merchemail,password,paymentmethod,enccardnumber,length,subacct,setupfee,monthly,extrafees,percent,pcttype,overtran,billauth FROM customers WHERE username=?";
  @earray = ($username);

  if ( $reseller !~ /^($reseller::tech_list)$/ ) {
    $qstr .= " AND reseller=?";
    push( @earray, $reseller );
  }
  $sth = $dbh->prepare($qstr) or die "Can't prepare: $DBI::errstr";
  $sth->execute(@earray) or die "Can't execute: $DBI::errstr";

  ( $query{'contact'},       $query{'company'},     $query{'addr1'},      $query{'addr2'},      $query{'city'},          $query{'state'},     $query{'zip'},       $query{'country'},
    $query{'tel'},           $query{'fax'},         $query{'email'},      $query{'techname'},   $query{'techtel'},       $query{'techemail'}, $query{'url'},       $query{'status'},
    $query{'cards_allowed'}, $query{'bank'},        $query{'routingnum'}, $query{'accountnum'}, $query{'card_number'},   $query{'exp_date'},  $query{'processor'}, $query{'proc_type'},
    $query{'merchant_id'},   $query{'terminal_id'}, $query{'merchemail'}, $query{'password'},   $query{'paymentmethod'}, $enccardnumber,      $length,             $query{'subacct'},
    $query{'setupfee'},      $query{'monthly'},     $query{'extrafees'},  $query{'percent'},    $query{'pcttype'},       $query{'overtran'},  $query{'billauth'}
  )
    = $sth->fetchrow;
  $sth->finish;
  $dbh->disconnect;

  &editapp();
  exit;
}

sub summary {
  $qstr =
    "SELECT name,company,addr1,addr2,city,state,zip,country,tel,fax,email,techname,techtel,techemail,url,status,cards_allowed,bank,routing,acct,card_number,exp_date FROM customers WHERE username=?";

  @earray = ($username);

  if ( $reseller !~ /^($reseller::tech_list)$/ ) {
    $qstr .= " AND reseller=?";
    push( @earray, $reseller );
  }

  $sth_merchants = $dbh->prepare($qstr) or die "Can't prepare: $DBI::errstr";
  $sth_merchants->execute(@earray) or die "Can't execute: $DBI::errstr";
  ( $name,     $company, $addr1,     $addr2, $city,   $state,         $zip,  $country,    $tel,        $fax,         $email,
    $techname, $techtel, $techemail, $url,   $status, $cards_allowed, $bank, $routingnum, $accountnum, $card_number, $exp_date
  )
    = $sth_merchants->fetchrow;
  $sth_merchants->finish;

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Plug and Pay Technologies, Inc. Merchant Directory</title>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"stylesheet.css\">\n";
  print "<META HTTP-EQUIV='Pragma' CONTENT='no-cache'>\n";
  print "<META HTTP-EQUIV='Cache-Control' CONTENT='no-cache'>\n";
  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";
  print "<center><div align=center>\n";
  print "<font size=+1>Plug and Pay Technologies, Inc. Merchant Directory</font><p>\n";

  print "<form action=\"$reseller::path_cgi\" method=post>\n";
  print "<table border=1>\n";
  print "  <tr>\n";
  print "    <td><font size=-1><b>Merchant Name:</b></font> $username\n";
  print "    <td colspan=2><font size=-1><b>Name:</b></font> $name\n";
  print "  <tr>\n";
  print "    <td><font size=-1><b>Status:</b></font> $status\n";
  print "    <td colspan=2><font size=-1><b>Company:</b></font> $company\n";
  print "  <tr>\n";
  print "    <td nowrap><font size=-1><b>Edit:</b> <input type=checkbox name=\"function\" value=\"Edit Account Info\"></font>\n";
  print "    <td><font size=-1><b>Tel:</b></font> $tel\n";
  print "    <td><font size=-1><b>Email:</b></font> $email\n";
  print "  <tr>\n";
  print "    <td align=center rowspan=2><input type=submit VALUE=\"Send Info\">\n";
  print "    <td colspan=2><font size=-1><b>Tech Name:</b></font>$techname\n";
  print "  <tr>\n";
  print "    <td><font size=-1><b>Tech Tel:</b></font> $techtel<br>\n";
  print "    <td><font size=-1><b>Tech Email:</b></font> $techemail<br>\n";
  print "  <tr>\n";
  print "    <td colspan=3><hr width=75% height=3></td>\n";
  print "</table><p>\n";
  print "<input type=hidden name=\"username\" value=\"$username\">\n";
  print "</form>\n";

  print "<form action=\"$reseller::path_cgi\" method=post>\n";
  print "<input type=submit name=\"submit\" value=\"Home Page\">\n";
  print "</form>";

  print "</body>\n";
  print "</html>\n";

  $dbh->disconnect;
}

sub updatestatus {

  if ( $client ne "remote" ) {

    # we aren't using remote, so we need to validate the captcha

    my $captcha = new PlugNPay::Util::Captcha::ReCaptcha();
    my $ok = $captcha->isValid( $ENV{'REMOTE_USER'}, $reseller::answer, $ENV{'REMOTE_ADDR'} );
    if ( !$ok ) {
      $error = 1;
      $errvar .= ":Invalid Captcha";
      $color{'captcha'} = "badcolor";
      &editstatus();
      exit;
    }
  }

  $username  = $query{'username'};
  $merchacct = $query{'merchacct'};
  $pnptype   = $query{'pnptype'};

  #$ach = $query{'ach'};
  $hosting        = $query{'hosting'};
  $autobatch      = $query{'autobatch'};
  $chkautobatch   = $query{'chkautobatch'};
  $shopcart       = $query{'shopcart'};
  $download       = $query{'download'};
  $affiliate      = $query{'affiliate'};
  $membership     = $query{'membership'};
  $submit_date    = $query{'submit_date'};
  $submit_status  = $query{'submit_status'};
  $sent_date      = $query{'sent_date'};
  $tracknum       = $query{'tracknum'};
  $return_date    = $query{'return_date'};
  $newcomment     = $query{'newcomment'};
  $ftpun          = $query{'ftpun'};
  $ftppw          = $query{'ftppw'};
  $ftphost        = $query{'ftphost'};
  $url            = $query{'url'};
  $memberdir      = $query{'memberdir'};
  $fromemail      = $query{'fromemail'};
  $recmessage     = $query{'recmessage'};
  $refresh        = $query{'refresh'};
  $recurbill      = $query{'recurbill'};
  $recnotifemail  = $query{'recnotifemail'};
  $installbilling = $query{'installbilling'};
  $recurbatch     = $query{'recurbatch'};
  $chkrecurbatch  = $query{'chkrecurbatch'};
  $lookahead      = $query{'lookahead'};
  $email_choice   = $query{'email_choice'};
  $fraudtrack     = $query{'fraudtrack'};
  $coupon         = $query{'coupon'};
  $fulfillment    = $query{'fulfillment'};
  $easycart       = $query{'easycart'};
  $billpay        = $query{'billpay'};

  if ( $reseller =~ /^($reseller::tech_list)$/ ) {
    my $loginClient = new PlugNPay::Authentication::Login( { login => $username } );
    $loginClient->setRealm('PNPSESSID');

    if ( $fraudtrack == 1 ) {
      $loginClient->addDirectories( { directories => [ "/admin/fraudtrack", ] } );
    } else {
      $loginClient->removeDirectories( { directories => [ "/admin/fraudtrack", ] } );
    }

    if ( $fulfillment == 1 ) {
      $loginClient->addDirectories( { directories => [ "/fulfillment", ] } );
    } else {
      $loginClient->removeDirectories( { directories => [ "/fulfillment", ] } );
    }
  } else {
    if ( $fraudtrack ne "1" ) {

      # remove access to fraudtrack for all sublogins
      my $loginClient = new PlugNPay::Authentication::Login( { login => $username } );
      $loginClient->setRealm('PNPSESSID');

      my $result = $loginClient->getLoginsForAccount( { account => $username } );

      if ($result) {
        foreach my $loginData ( @{ $result->{'logins'} } ) {
          $loginClient->setLogin( $loginData->{'login'} );
          $loginClient->removeDirectories( { directories => [ "/admin/fraudtrack", ] } );
        }
      }
    }
  }

  if ( $recurbatch ne "yes" ) {
    $recurbatch = "no";
  }

  ( undef, $datetime ) = &miscutils::gendatetime_only();

  $submit_date = &miscutils::strtodate($submit_date);
  $sent_date   = &miscutils::strtodate($sent_date);
  $return_date = &miscutils::strtodate($return_date);

  $dbh = &miscutils::dbhconnect('pnpmisc');

  $sth = $dbh->prepare(
    q{
      SELECT status
      FROM customers
      WHERE username=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth->execute("$username") or die "Can't execute: $DBI::errstr";
  my ($test) = $sth->fetchrow;
  $sth->finish;

  if ( $test ne "" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM pnpsetups
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    my ($test1) = $sth->fetchrow;
    $sth->finish;

    if ( $test1 eq "" ) {
      my $sth = $dbh->prepare(
        q{
          INSERT INTO pnpsetups
          (username)
          VALUES (?)
        }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth->execute("$username") or die "Can't execute: $DBI::errstr";
      $sth->finish;
    }
  }

  if ( $reseller =~ /^($reseller::tech_list)$/ ) {
    $sth_merchants = $dbh->prepare(
      q{
        UPDATE pnpsetups
        SET merchacct=?,pnptype=?,autobatch=?,chkautobatch=?,hosting=?,shopcart=?,download=?,membership=?,submit_status=?,sent_date=?,tracknum=?,return_date=?,ftpun=?,ftppw=?,ftphost=?,url=?,fromemail=?,recmessage=?,memberdir=?,recurbatch=?,recurbill=?,refresh=?,lookahead=?,email_choice=?,recnotifemail=?,installbilling=?,fraudtrack=?,affiliate=?,coupon=?,fulfillment=?,chkrecurbatch=?,easycart=?,billpay=?
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_merchants->execute(
      $merchacct,       $pnptype,       $autobatch,   $chkautobatch,   $hosting,         $shopcart,         $download,     $membership,   "$submit_status", "$sent_date",
      "$tracknum",      "$return_date", "$ftpun",     "$ftppw",        "$ftphost",       "$url",            "$fromemail",  "$recmessage", "$memberdir",     "$recurbatch",
      "$recurbill",     "$refresh",     "$lookahead", "$email_choice", "$recnotifemail", "$installbilling", "$fraudtrack", "$affiliate",  "$coupon",        "$fulfillment",
      "$chkrecurbatch", "$easycart",    "$billpay",   "$username"
      )
      or die "Can't execute: $DBI::errstr";
    $sth_merchants->finish;
  } else {
    $sth_merchants = $dbh->prepare(
      q{
        UPDATE pnpsetups
        SET merchacct=?,pnptype=?,autobatch=?,chkautobatch=?,hosting=?,shopcart=?,download=?,membership=?,sent_date=?,tracknum=?,return_date=?,recnotifemail=?,installbilling=?,fraudtrack=?,affiliate=?,coupon=?,fulfillment=?,chkrecurbatch=?,easycart=?,billpay=?
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_merchants->execute(
      $merchacct,     $pnptype,         $autobatch,     $chkautobatch,    $hosting,          $shopcart,     $download,    $membership,
      "$sent_date",   "$tracknum",      "$return_date", "$recnotifemail", "$installbilling", "$fraudtrack", "$affiliate", "$coupon",
      "$fulfillment", "$chkrecurbatch", "$easycart",    "$billpay",       "$username"
      )
      or die "Can't execute: $DBI::errstr";
    $sth_merchants->finish;
  }

  if ( $newcomment ne "" ) {
    $sth_comments = $dbh->prepare(
      q{
        INSERT INTO comments
        (username,orderid,message)
        VALUES (?,?,?)
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_comments->execute( "$username", $datetime, "$newcomment" ) or die "Can't execute: $DBI::errstr";
    $sth_comments->finish;
  }
  $dbh->disconnect;
  if ( ( $ENV{'REMOTE_USER'} ne "barbara" ) && ( $ENV{'REMOTE_USER'} ne "michelle" ) ) {
    &main("login.html");
  } else {
    print "DONE<br>\n";
  }
}

sub updatecust {
  my (@array) = %query;
  $error = &input_check(@array);
  if ( $error > 0 ) {
    &editapp();
  }
  $name          = $query{'contact'};
  $username      = $query{'username'};
  $company       = $query{'company'};
  $addr1         = $query{'addr1'};
  $addr2         = $query{'addr2'};
  $city          = $query{'city'};
  $state         = $query{'state'};
  $zip           = $query{'zip'};
  $country       = $query{'country'};
  $tel           = $query{'tel'};
  $fax           = $query{'fax'};
  $email         = $query{'email'};
  $card_number   = $query{'card_number'};
  $techname      = $query{'techname'};
  $techtel       = $query{'techtel'};
  $techemail     = $query{'techemail'};
  $url           = $query{'url'};
  $cards_allowed = $query{'cards_allowed'};
  $processor     = $query{'processor'};
  $proc_type     = $query{'proc_type'};
  $merchant_id   = $query{'merchant_id'};
  $terminal_id   = $query{'terminal_id'};
  $bank          = $query{'bank'};
  $routingnum    = $query{'routingnum'};
  $accountnum    = $query{'accountnum'};
  $merchemail    = $query{'merchemail'};
  $paymentmethod = $query{'paymentmethod'};
  $subacct       = $query{'subacct'};
  $agentcode     = $query{'agentcode'};

  $dbh = &miscutils::dbhconnect('pnpmisc');

  $card_number = $query{'card_number'};
  $cardlength  = length $card_number;
  if ( ( $card_number !~ /\*\*/ ) && ( $cardlength > 8 ) ) {
    ( $enccardnumber, $encryptedDataLen ) = &rsautils::rsa_encrypt_card( $card_number, '/home/p/pay1/pwfiles/keys/key' );

    $card_number = $query{'card_number'};
    $card_number = substr( $card_number, 0, 4 ) . '**' . substr( $card_number, length($card_number) - 2, 2 );

    $length = "$encryptedDataLen";

    if ( $reseller =~ /^($reseller::tech_list)$/ ) {
      $sth = $dbh->prepare(
        q/
          UPDATE customers
          SET card_number=?,enccardnumber=?,length=?
          WHERE username=?
      /
        )
        or die "Can't prepare: $DBI::errstr";
      $sth->execute( $card_number, $enccardnumber, $encryptedDataLen, "$username" ) or die "Can't execute: $DBI::errstr";

    } else {
      $sth = $dbh->prepare(
        q/
          UPDATE customers
          SET card_number=?,enccardnumber=?,length=?
          WHERE username=?
          AND reseller=?
      /
        )
        or die "Can't prepare: $DBI::errstr";
      $sth->execute( $card_number, $enccardnumber, $encryptedDataLen, "$username", "$reseller" ) or die "Can't execute: $DBI::errstr";

    }
  } else {
    $enccardnumber = "";
    $length        = "0";
  }

  $qstr = q/
    UPDATE customers 
       SET name=?,company=?,addr1=?,addr2=?,
           city=?,state=?,zip=?,country=?,tel=?,
           fax=?,email=?,techname=?,techtel=?,
           techemail=?,url=?,bank=?,merchemail=?,
           paymentmethod=?,agentcode=?,subacct=? 
     WHERE username=?/;
  @earray =
    ( $name, $company, $addr1, $addr2, $city, $state, $zip, $country, $tel, $fax, $email, $techname, $techtel, $techemail, $url, $bank, $merchemail, $paymentmethod, $agentcode, $subacct, $username );

  if ( $reseller !~ /^($reseller::tech_list)$/ ) {
    $qstr .= " AND reseller=?";
    push( @earray, $reseller );
  }
  $sth_merchants = $dbh->prepare($qstr) or die "Can't prepare: $DBI::errstr";
  $sth_merchants->execute(@earray) or die "Can't execute: $DBI::errstr";

  &summary();
}

sub status {
  $maxcnt = $query{'maxcnt'};

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title> Reseller Administration</title>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"https://pay1.plugnpay.com/css/green.css\">\n";
  print "<META HTTP-EQUIV='Pragma' CONTENT='no-cache'>\n";
  print "<META HTTP-EQUIV='Cache-Control' CONTENT='no-cache'>\n";

  print "<style text=\"text/css\">\n";
  print "<\!--\n";
  print "TABLE \{width: 100%;\}\n";
  print "HR \{width: 100%;\}\n";
  print "TH \{text-align: left;\}\n";
  print "-->\n";
  print "</style>\n";

  print "</head>\n";

  print "<body bgcolor=\"#ffffff\">\n";
  print "<table border=1 cellspacing=1 cellpadding=1>\n";
  print "  <tr bgcolor=\"#f3f9e8\">\n";
  print "    <th><b>Merchant</b></th>\n";
  print "    <th><b>Processor</b></th>\n";
  print "    <th><b>Acct/Type</b></th>\n";
  print "    <th><b>Hosting</b></th>\n";
  print "    <th><b>ACH</b></th>\n";
  print "    <th><b>ShopCart</b></th>\n";
  print "    <th><b>Download</b></th>\n";
  print "    <th><b>Affiliate</b></th>\n";
  print "    <th><b>Membership</b></th>\n";
  print "    <th><b>Status</b></th>\n";
  print "    <th><b>Comments</b></th>\n";
  print "  </tr>\n";

  $dbh = &miscutils::dbhconnect('pnpmisc');

  if ( $reseller =~ /^($reseller::tech_list)$/ ) {
    $sth = $dbh->prepare(
      q/
        SELECT c.username,c.name,c.company,c.status,p.merchacct,p.pnptype,p.hosting,p.shopcart,
               p.download,p.affiliate,p.membership,p.submit_date,p.submit_status,p.sent_date,
               p.tracknum,p.return_date,c.processor
        FROM customers c,pnpsetups p
        WHERE c.username=p.username
        AND c.status<>?
        ORDER BY c.username
    /
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute('cancelled') or die "Can't execute: $DBI::errstr";
  } else {
    $sth = $dbh->prepare(
      q/
        SELECT c.username,c.name,c.company,c.status,p.merchacct,p.pnptype,p.hosting,p.shopcart,
               p.download,p.affiliate,p.membership,p.submit_date,p.submit_status,p.sent_date,
               p.tracknum,p.return_date,c.processor
        FROM customers c,pnpsetups p
        WHERE c.reseller=?
        AND c.username=p.username
        AND c.status<>?
        ORDER BY c.username
    /
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute( "$reseller", 'cancelled' ) or die "Can't execute: $DBI::errstr";
  }

  $myi      = 0;
  $firstcnt = $maxcnt;
  $lastcnt  = $maxcnt + 25;

  while (
    my ( $username, $name, $company, $status, $merchacct, $pnptype, $hosting, $shopcart, $download, $affiliate, $membership, $submit_date, $submit_status, $sent_date, $tracknum, $return_date, $processor )
    = $sth->fetchrow ) {
    if ( ( $myi >= $firstcnt ) && ( $myi < $lastcnt ) ) {
      &genpage();
    } elsif ( $myi >= $lastcnt ) {
      last;
    }
    $myi++;
  }
  $sth->finish;

  $dbh->disconnect;

  print "</table>";

  print "<div align=center>\n";
  print "<table border=0>\n";
  print "  <tr>\n";
  if ( $lastcnt > 25 ) {
    $prevcnt = $maxcnt - 25;
    print "  <td align=right width=\"50%\"><form action=\"$reseller::path_cgi\" method=post>\n";
    print "<input type=hidden name=\"function\" value=\"status\">\n";
    print "<input type=hidden name=\"maxcnt\" value=\"$prevcnt\">\n";
    print "<input type=submit name=\"submit\" value=\"< Previous\" style=\"width:100px;\">\n";
    print "</form></td>\n";
  }
  print "  <td align=left width=\"50%\"><form action=\"$reseller::path_cgi\" method=post>\n";
  print "<input type=hidden name=\"function\" value=\"status\">\n";
  print "<input type=hidden name=\"maxcnt\" value=\"$lastcnt\">\n";
  print "<input type=submit name=\"submit\" value=\"Next >\" style=\"width:100px;\">\n";
  print "</form></td>";
  print "  </tr>\n";
  print "</table>\n";

  print "<form action=\"$reseller::path_cgi\" method=post>\n";
  print "<input type=submit name=\"submit\" value=\"Home Page\">\n";
  print "</form>\n";
  print "</div>";

  print "</body>";
  print "</html>";
}

sub editapp {
  if ( ( $function eq "editapp" ) or ( $function eq "updateapp" ) ) {
    $nextfunction = "updateapp";
  } elsif ( ( $function eq "editcust" ) or ( $function eq "updatecust" ) or ( $function eq "Edit Account Info" ) ) {
    $nextfunction = "updatecust";
  }

  $selected{ $query{'industrycode'} }          = " checked";
  $selected{ $query{'dccfhrzn_industrycode'} } = " checked";
  $selected{ $query{'tsys_industrycode'} }     = " checked";

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Merchant Registration Form</title>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"https://pay1.plugnpay.com/css/green.css\">\n";
  print "<META HTTP-EQUIV='Pragma' CONTENT='no-cache'>\n";
  print "<META HTTP-EQUIV='Cache-Control' CONTENT='no-cache'>\n";
  print "<script type=\"text/javascript\" src=\"/javascript/jquery.min.js\"></script>\n";

  print <<EOF;
<script type="text/javascript">
//<![CDATA[
//toggles color for focused text input and select fields

window.onload = function() {
  var field = document.getElementsByTagName("input");
    for(var i = 0; i < field.length; i++) {
      if (field[i].type == "text") {
        field[i].onfocus = function() {
          this.className += " focus";
        };
        field[i].onblur = function() {
          this.className = this.className.replace(/\\bfocus\\b/, "");
        };
      };
    };
field = null;
  var field = document.getElementsByTagName("select");
    for(var i = 0; i < field.length; i++) {
        field[i].onfocus = function() {
          this.className += " focus";
        };
        field[i].onblur = function() {
          this.className = this.className.replace(/\\bfocus\\b/, "");
        };
      };
field = null;
  var field = document.getElementsByTagName("textarea");
    for(var i = 0; i < field.length; i++) {
        field[i].onfocus = function() {
          this.className += " focus";
        };
        field[i].onblur = function() {
          this.className = this.className.replace(/\\bfocus\\b/, "");
        };
      };
field = null;
  };

//dispalys different form fields based on selected processor

var accountTypeHTML = '\\
    <th>Account Type:</th>\\
    <td>\\
	  <input type="radio" name="industrycode" value="" $selected{''}/> <b>NA</b><br>\\
	  <input type="radio" name="industrycode" value="retail" $selected{'retail'}/><b>Retail</b> * Select <span>only</span> if merchant will pass swipe data to a retail merchant account<br>\\
	  <input type="radio" name="industrycode" value="restaurant" $selected{'restaurant'}/><b>Restaurant</b> * Select <span>only</span> if the merchant will pass gratuity to a restaurant merchant account<br>\\
    </td>\\
  </tr>';

jQuery(document).ready(function(){
	showfield(jQuery('#processorName').val());
});

function showfield(name){
  if((name=='barclays') || (name=='globalc') || (name=='universal') || (name=='village')) {document.getElementById('procfields').innerHTML='<table><tr><th>Merchant ID: <\\/th><td><input type="text" name="merchant_id" size="30" maxlength="40" value="$query{'merchant_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Terminal ID: <\\/th><td><input type="text" name="terminal_id" size="30" maxlength="40" value="$query{'terminal_id'}" autocomplete="off"/><\\/td><\\/tr><\\/table>';
  country.style.display='none';
  currency.style.display='none';
  ppay.style.display='none';
  fthird.style.display='none';
}  else if(name=='buypass') {document.getElementById('procfields').innerHTML='<table><tr><th>Merchant ID: <\\/th><td><input type="text" name="merchant_id" size="30" maxlength="40" value="$query{'merchant_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Terminal ID: <\\/th><td><input type="text" name="terminal_id" size="30" maxlength="40" value="$query{'terminal_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Retail Account: <\\/th><td><nobr><input type="checkbox" name="industrycode" value="retail" $selected{'retail'}/>* Select <span>only<\\/span> if merchant will pass swipe data to a retail merchant account<\\/nobr><\\/td><\\/tr><\\/table>';
  country.style.display='none';
  currency.style.display='none';
  ppay.style.display='none';
  fthird.style.display='none';
}  else if(name=='epx') {document.getElementById('procfields').innerHTML='<table><tr><th>Merchant ID: <\\/th><td><input type="text" name="merchant_id" size="30" maxlength="40" value="$query{'merchant_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Terminal ID: <\\/th><td><input type="text" name="terminal_id" size="30" maxlength="40" value="$query{'terminal_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Retail Account: <\\/th><td><nobr><input type="checkbox" name="industrycode" value="retail" $selected{'retail'}/>* Select <span>only<\\/span> if merchant will pass swipe data to a retail merchant account<\\/nobr><\\/td><\\/tr><tr><th>Cust Number: <\\/th><td><input type="text" name="bankid" size="30" maxlength="40" value="$query{'bankid'}" autocomplete="off"><\\/td><\\/tr><tr><th>DBA Number: <\\/th><td><input type="text" name="dbanum" size="30" maxlength="40" value="$query{'dbanum'}" autocomplete="off"><\\/td><\\/tr><\\/table>';
  country.style.display='none';
  currency.style.display='none';
  ppay.style.display='none';
  fthird.style.display='none';
}  else if((name=='fdms') || (name=='paytechsalem') || (name=='firstcarib')) {document.getElementById('procfields').innerHTML='<table><tr><th>Merchant ID: <\\/th><td><input type="text" name="merchant_id" size="30" maxlength="40" value="$query{'merchant_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Terminal ID: <\\/th><td><input type="text" name="terminal_id" size="30" maxlength="40" value="$query{'terminal_id'}" autocomplete="off"/><\\/td><\\/tr>' + accountTypeHTML + '<\\/table>';
  country.style.display='none';
  if (name=='firstcarib') {
    currency.style.display='block';
  } else {
    currency.style.display='none';
  }
  ppay.style.display='none';
  fthird.style.display='none';
}  else if(name=='fdmsrc') {document.getElementById('procfields').innerHTML='<table><tr><th>Merchant ID: <\\/th><td><input type="text" name="merchant_id" size="30" maxlength="40" value="$query{'merchant_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Terminal ID: <\\/th><td><input type="text" name="terminal_id" size="30" maxlength="40" value="$query{'terminal_id'}" autocomplete="off"/><\\/td><\\/tr>' + accountTypeHTML + '<tr><th>Category Code: <\\/th><td><input type="text" name="categorycode" size="30" maxlength="40" value="$query{'categorycode'}" autocomplete="off"/> 4 digits<\\/td><\\/tr><tr><th>Fed Tax ID: <\\/th><td><input type="text" name="fedtaxid" size="30" maxlength="40" value="$query{'fedtaxid'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Group ID: <\\/th><td><input type="text" name="groupid" size="30" maxlength="5" value="$query{'groupid'}" autocomplete="off"/> 5 digits<\\/td><\\/tr><\\/table>';
  country.style.display='none';
  currency.style.display='none';
  ppay.style.display='none';
  fthird.style.display='none';
}  else if(name=='elavon') {document.getElementById('procfields').innerHTML='<table><tr><th>Merchant ID: <\\/th><td><input type="text" name="merchant_id" size="30" maxlength="40" value="$query{'merchant_id'}"  autocomplete="off"/><\\/td><\\/tr><tr><th>Terminal ID: <\\/th><td><input type="text" name="terminal_id" size="30" maxlength="40" value="$query{'terminal_id'}" autocomplete="off"/><\\/td><\\/tr>' + accountTypeHTML + '<tr><th>BankNum: <\\/th><td><input type="text" name="bin" size="30" maxlength="40" value="$query{'bin'}" autocomplete="off"/> 6 digits<\\/td><\\/tr><\\/table>';
  country.style.display='none';
  currency.style.display='none';
  ppay.style.display='none';
  fthird.style.display='none';
}
else if(name=='maverick') {document.getElementById('procfields').innerHTML='<table><tr><th>Merchant ID: <\\/th><td><input type="text" name="merchant_id" size="30" maxlength="40" value="$query{'merchant_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Terminal ID: <\\/th><td><input type="text" name="terminal_id" size="30" maxlength="40" value="$query{'terminal_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>BankNum: <\\/th><td><input type="text" name="bin" size="30" maxlength="40" value="$query{'bin'}" autocomplete="off"/> 6 digits<\\/td><\\/tr><tr><th>Retail Account: <\\/th><td><nobr><input type="checkbox" name="industrycode" value="retail" $selected{'retail'}/>* Select <span>only<\\/span> if merchant will pass swipe data to a retail merchant account<\\/nobr><\\/td><\\/tr><\\/table>';
  country.style.display='none';
  currency.style.display='none';
  ppay.style.display='none';
  fthird.style.display='none';
}
// terminal ID uses the merchant_id variable - this is done on purpose
  else if((name=='global') || (name=='mercury')) {document.getElementById('procfields').innerHTML='<table><tr><th>Terminal ID: <\\/th><td><input type="text" name="merchant_id" size="30" maxlength="40" value="$query{'merchant_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>BankID: <\\/th><td><input type="text" name="bankid" size="30" maxlength="40" value="$query{'bankid'}" autocomplete="off"> 6 digits<\\/td><\\/tr>' + accountTypeHTML + '<\\/table>';
  country.style.display='none';
  currency.style.display='none';
  ppay.style.display='none';
  fthird.style.display='none';
}  else if(name=='fdmsintl') {document.getElementById('procfields').innerHTML='<table><tr><th>Merchant ID: <\\/th><td><input type="text" name="merchant_id" size="30" maxlength="40" value="$query{'merchant_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Terminal ID: <\\/th><td><input type="text" name="terminal_id" size="30" maxlength="40" value="$query{'terminal_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Retail Account: <\\/th><td><nobr><input type="checkbox" name="industrycode" value="retail" $selected{'retail'}/>* Select <span>only<\\/span> if merchant will pass swipe data to a retail merchant account<\\/nobr><\\/td><\\/tr><tr><th>BankNum/ID: <\\/th><td><input type="text" name="banknum" size="30" maxlength="40" value="$query{'banknum'}" autocomplete="off"/> 6 digits<\\/td><\\/tr><tr><th>Category Code: <\\/th><td><input type="text" name="categorycode" size="30" maxlength="40" value="$query{'categorycode'}" autocomplete="off"/> 4 digits<\\/td><\\/tr><\\/table>';
  country.style.display='none';
  currency.style.display='block';
  ppay.style.display='none';
  fthird.style.display='none';
}  else if(name=='fifththird') {document.getElementById('procfields').innerHTML='';
  country.style.display='none';
  currency.style.display='none';
  ppay.style.display='none';
  fthird.style.display='block';
}  else if((name=='cccc') || (name=='ncb')) {document.getElementById('procfields').innerHTML='<table><tr><th>Merchant ID: <\\/th><td><input type="text" name="merchant_id" size="30" maxlength="40" value="$query{'merchant_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Terminal ID: <\\/th><td><input type="text" name="terminal_id" size="30" maxlength="40" value="$query{'terminal_id'}" autocomplete="off"/> 8 digits<\\/td><\\/tr><tr><th>BankNum/ID: <\\/th><td><input type="text" name="bankid" size="30" maxlength="40" value="$query{'bankid'}" autocomplete="off"/> 6 digits<\\/td><\\/tr><tr><th>Category Code: <\\/th><td><input type="text" name="categorycode" size="30" maxlength="40" value="$query{'categorycode'}" autocomplete="off"/> 4 digits<\\/td><\\/tr><tr><th>POS Condition Code: <\\/th><td><input type="text" name="poscond" size="30" maxlength="40" value="$query{'poscond'}" autocomplete="off"/> 4 digits<\\/td><\\/tr><\\/table>';
  country.style.display='none';
  currency.style.display='block';
  ppay.style.display='none';
  fthird.style.display='none';
}  else if(name=='pago') {document.getElementById('procfields').innerHTML='<table><tr><th>Merchant ID: <\\/th><td><input type="text" name="merchant_id" size="30" maxlength="40" value="$query{'merchant_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Terminal ID: <\\/th><td><input type="text" name="terminal_id" size="30" maxlength="40" value="$query{'terminal_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Client Name: <\\/th><td><input type="text" name="clientname" size="30" maxlength="40" value="$query{'clientname'}" autocomplete="off"/> 12 digits<\\/td><\\/tr><tr><th>Sales Channel: <\\/th><td><input type="text" name="saleschannel" size="30" maxlength="40" value="$query{'saleschannel'}" autocomplete="off"/> 6 digits<\\/td><\\/tr><\\/table>';
  country.style.display='none';
  currency.style.display='block';
  ppay.style.display='none';
  fthird.style.display='none';
}  else if(name=='paytechtampa') {document.getElementById('procfields').innerHTML='<table><tr><th>Merchant ID: <\\/th><td><input type="text" name="merchant_id" size="30" maxlength="40" value="$query{'merchant_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Terminal ID: <\\/th><td><input type="text" name="terminal_id" size="30" maxlength="40" value="$query{'terminal_id'}" autocomplete="off"/> 3 digits<\\/td><\\/tr><tr><th>ClientID/Name: <\\/th><td><input type="text" name="clientid" size="30" maxlength="40" value="$query{'clientid'}" autocomplete="off"/> 4 digits<\\/td><\\/tr>' + accountTypeHTML + '<\\/table>';
  country.style.display='none';
  currency.style.display='none';
  ppay.style.display='none';
  fthird.style.display='none';
}  else if(name=='payvision') {document.getElementById('procfields').innerHTML='<table><tr><th>Member ID: <\\/th><td><input type="text" name="memberid" size="30" maxlength="40" value="$query{'memberguid'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Memberguid: <\\/th><td><input type="text" name="memberguid" size="30" maxlength="40" value="$query{'memberguid'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Retail Account: <\\/th><td><nobr><input type="checkbox" name="industrycode" value="retail" $selected{'retail'}/>* Select <span>only<\\/span> if merchant will pass swipe data to a retail merchant account<\\/nobr><\\/td><\\/tr><\\/table>';
  country.style.display='none';
  currency.style.display='block';
  ppay.style.display='none';
  fthird.style.display='none';
}  else if(name=='rbs') {document.getElementById('procfields').innerHTML='<table><tr><th>Merchant ID: <\\/th><td><input type="text" name="merchant_id" size="30" maxlength="40" value="$query{'merchant_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Terminal ID: <\\/th><td><input type="text" name="terminal_id" size="30" maxlength="40" value="$query{'terminal_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Retail Account: <\\/th><td><nobr><input type="checkbox" name="industrycode" value="retail" $selected{'retail'}/>* Select <span>only<\\/span> if merchant will pass swipe data to a retail merchant account<\\/nobr><\\/td><\\/tr><tr><th>Store ID: <\\/th><td><input type="text" name="storeid" size="30" maxlength="40" value="$query{'storeid'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Seller ID: <\\/th><td><input type="text" name="sellerid" size="30" maxlength="40" value="$query{'sellerid'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Password: <\\/th><td><input type="test" name="rbspassword" size="30" maxlength="40" value="$query{'rbspassword'}" autocomplete="off"/><\\/td><\\/tr><\\/table>';
  country.style.display='none';
  currency.style.display='none';
  ppay.style.display='none';
  fthird.style.display='none';
} else if (name=='rbc') {document.getElementById('procfields').innerHTML='<table><tr><th>Merchant ID: <\\/th><td><input type="text" name="merchant_id" size="30" maxlength="40" value="$query{'merchant_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Terminal ID: <\\/th><td><input type="text" name="terminal_id" size="30" maxlength="40" value="$query{'terminal_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Server:<\\/th><td><select name="server"  required><option value="">Select<\\/option><option value="1">Bahamas<\\/option><option value="2">Cayman<\\/option><option value="3">Barbados<\\/option><option value="4">Eastern Carib<\\/option><\\/select><\\/td><\\/tr><\\/table>';
  jQuery('select[name=server]').val('$query{'server'}');
  country.style.display='none';
  currency.style.display='block';
  ppay.style.display='none';
  fthird.style.display='none';
}  else if(name=='surefire') {document.getElementById('procfields').innerHTML='<table><tr><th>Merchant ID: <\\/th><td><input type="text" name="merchant_id" size="30" maxlength="40" value="$query{'merchant_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Password: <\\/th><td><input type="text" name="password" size="30" maxlength="40" value="$query{'password'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Account #: <\\/th><td><input type="text" name="account" size="30" maxlength="40" value="$query{'account'}" autocomplete="off"/><\\/td><\\/tr><\\/table>';
  country.style.display='none';
  currency.style.display='block';
  ppay.style.display='none';
  fthird.style.display='none';
}  else if(name=='visanet') {document.getElementById('procfields').innerHTML='<table><tr><th>Merchant ID: <\\/th><td><input type="text" name="merchant_id" size="30" maxlength="40" value="$query{'merchant_id'}"  autocomplete="off"/><\\/td><\\/tr><tr><th>Terminal ID: <\\/th><td><input type="text" name="terminal_id" size="30" maxlength="40" value="$query{'terminal_id'}" autocomplete="off"/> 8 digits<\\/td><\\/tr><tr><th>Category Code: <\\/th><td><input type="text" name="categorycode" size="30" maxlength="40" value="$query{'categorycode'}" autocomplete="off"/> 4 digits<\\/td><\\/tr><tr><th>Bin: <\\/th><td><input type="text" name="bin" size="30" maxlength="40" value="$query{'bin'}" autocomplete="off"/> 6 digits<\\/td><\\/tr><tr><th>Agent Bank: <\\/th><td><input type="text" name="agentbank" size="30" maxlength="6" value="$query{'agentbank'}" autocomplete="off"/> 6 digits<\\/td><\\/tr><tr><th>Agent Chain: <\\/th><td><input type="text" name="agentchain" size="30" maxlength="40" value="$query{'agentchain'}" autocomplete="off"/> 6 digits<\\/td><\\/tr><tr><th>Store Number: <\\/th><td><input type="text" name="storenum" size="30" maxlength="40" value="$query{'storenum'}" autocomplete="off"/> 4 digits<\\/td><\\/tr><tr><th>Terminal Number: <\\/th><td><input type="text" name="terminalnum" size="30" maxlength="40" value="$query{'terminalnum'}" autocomplete="off"/> 4 digits<\\/td><\\/tr>' + accountTypeHTML + '<\\/table>';
  country.style.display='none';
  currency.style.display='block';
  ppay.style.display='none';
  fthird.style.display='none';
}  else if(name=='wirecard') {document.getElementById('procfields').innerHTML='<table><tr><th>Business Case Signature: <\\/th><td><input type="text" name="merchant_id" size="30" maxlength="40" value="$query{'merchant_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Login Username: <\\/th><td><input type="text" name="wc_loginun" size="30" maxlength="40" value="$query{'wc_loginun'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Login Password: <\\/th><td><input type="password" name="wc_loginpw" size="30" maxlength="40" value="$query{'wc_loginpw'}" autocomplete="off"/><\\/td><\\/tr><\\/table>';
  country.style.display='block';
  currency.style.display='none';
  ppay.style.display='none';
  fthird.style.display='none';
} else if(name=='moneris') {document.getElementById('procfields').innerHTML='<table><tr><th>Store ID: <\\/th><td><input type="text" name="merchant_id" size="30" maxlength="40" value="$query{'merchant_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>API Token: <\\/th><td><input type="text" name="terminal_id" size="30" maxlength="40" value="$query{'terminal_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Retail Account: <\\/th><td><nobr><input type="checkbox" name="industrycode" value="retail" $selected{'retail'}/>* Select <span>only<\\/span> if merchant will pass swipe data to a retail merchant account<\\/nobr><\\/td><\\/tr><\\/table>';
  country.style.display='none';
  currency.style.display='block';
  ppay.style.display='none';
  fthird.style.display='none';
} else if(name=='gsopay') {document.getElementById('procfields').innerHTML='<table><tr><th>Merchant ID: <\\/th><td><input type="text" name="merchant_id" size="30" maxlength="40" value="$query{'merchant_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Site: <\\/th><td><input type="text" name="terminal_id" size="30" maxlength="40" value="$query{'terminal_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Password: <\\/th><td><input type="test" name="gsopaypassword" size="30" maxlength="40" value="$query{'gsopaypassword'}" autocomplete="off"/><\\/td><\\/tr><\\/table>';
  country.style.display='none';
  currency.style.display='none';
  ppay.style.display='none';
  fthird.style.display='none';
} else if(name=='litle') {document.getElementById('procfields').innerHTML='<table><tr><th>Merchant ID: <\\/th><td><input type="text" name="merchant_id" size="30" maxlength="40" value="$query{'merchant_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Terminal ID: <\\/th><td><input type="text" name="terminal_id" size="30" maxlength="40" value="$query{'terminal_id'}" autocomplete="off"/><\\/td><\\/tr><tr><th>Retail Account: <\\/th><td><nobr><input type="checkbox" name="industrycode" value="retail" $selected{'retail'}/>* Select <span>only<\\/span> if merchant will pass swipe data to a retail merchant account<\\/nobr><\\/td><\\/tr><\\/table>';
  country.style.display='none';
  currency.style.display='none';
  ppay.style.display='none';
  fthird.style.display='none';
}  else if(name=='securenet') {document.getElementById('procfields').innerHTML='<table><tr><th>Merchant ID: <\\/th><td><input type="text" name="merchant_id" size="30" maxlength="40" value="$query{'merchant_id'}"  autocomplete="off"/><\\/td><\\/tr><tr><th>Category Code: <\\/th><td><input type="text" name="categorycode" size="30" maxlength="40" value="$query{'categorycode'}" autocomplete="off"/> 4 digits<\\/td><\\/tr><tr><th>Bin: <\\/th><td><input type="text" name="bin" size="30" maxlength="40" value="$query{'bin'}" autocomplete="off"/> 6 digits<\\/td><\\/tr><tr><th>Agent Bank: <\\/th><td><input type="text" name="agentbank" size="30" maxlength="6" value="$query{'agentbank'}" autocomplete="off"/> 6 digits<\\/td><\\/tr><tr><th>Agent Chain: <\\/th><td><input type="text" name="agentchain" size="30" maxlength="40" value="$query{'agentchain'}" autocomplete="off"/> 6 digits<\\/td><\\/tr><tr><th>Store Number: <\\/th><td><input type="text" name="storenum" size="30" maxlength="40" value="$query{'storenum'}" autocomplete="off"/> 4 digits<\\/td><\\/tr><tr><th>Terminal Number: <\\/th><td><input type="text" name="terminalnum" size="30" maxlength="40" value="$query{'terminalnum'}" autocomplete="off"/> 4 digits<\\/td><\\/tr><tr><th>Retail Account: <\\/th><td><nobr><input type="checkbox" name="industrycode" value="retail" $selected{'retail'}/>* Select <span>only<\\/span> if merchant will pass swipe data to a retail merchant account<\\/nobr><\\/td><\\/tr><\\/table>';
  country.style.display='none';
  currency.style.display='block';
  ppay.style.display='none';
  fthird.style.display='none';
}  else if(name=='planetpay') {document.getElementById('procfields').innerHTML='';
  country.style.display='none';
  ppay.style.display='block';
  currency.style.display='none';
  fthird.style.display='none';
}  else {document.getElementById('procfields').innerHTML='';
  country.style.display='none';
  currency.style.display='none';
  ppay.style.display='none';
  fthird.style.display='none';
 }

//toggles color for focused text input fields and select boxes displayed when a process is selected

  var field = document.getElementsByTagName("input");
    for(var i = 0; i < field.length; i++) {
      if (field[i].type == "text") {
        field[i].onfocus = function() {
          this.className += " focus";
        };
        field[i].onblur = function() {
          this.className = this.className.replace(/\\bfocus\\b/, "");
        };
      };
    };
field = null;
  var field = document.getElementsByTagName("select");
    for(var i = 0; i < field.length; i++) {
        field[i].onfocus = function() {
          this.className += " focus";
        };
        field[i].onblur = function() {
          this.className = this.className.replace(/\\bfocus\\b/, "");
        };
      };
field = null;
  };

 //toggles fields for fifththird

function fmcpActive() {
  fmcp.style.display ='block';
  nonfmcp.style.display ='none';
}
function nonfmcpActive() {
  fmcp.style.display ='none';
  nonfmcp.style.display ='block';
}

//handles display of suboptions for planetpay and fifththird

function tsysActive() {
  tsys.style.display ='block';
  hmblt.style.display ='none';
  fhrzn.style.display ='none';
  dccfhrzn.style.display ='none';
  curmcptsys.style.display ='none';
  curmcphmblt.style.display ='none';
  curmcpfhrzn.style.display ='none';
}

function mcptsysActive () {
  tsys.style.display ='block';
  hmblt.style.display ='none';
  fhrzn.style.display ='none';
  dccfhrzn.style.display ='none';
  curmcptsys.style.display ='block';
  curmcphmblt.style.display ='none';
  curmcpfhrzn.style.display ='none';
}

function nonmcptsysActive () {
  tsys.style.display ='block';
  hmblt.style.display ='none';
  fhrzn.style.display ='none';
  dccfhrzn.style.display ='none';
  curmcptsys.style.display ='none';
  curmcphmblt.style.display ='none';
  curmcpfhrzn.style.display ='none';
}

function hmbltActive() {
  tsys.style.display ='none';
  hmblt.style.display ='block';
  fhrzn.style.display ='none';
  dccfhrzn.style.display ='none';
  curmcptsys.style.display ='none';
  curmcphmblt.style.display ='none';
  curmcpfhrzn.style.display ='none';
}

function mcphmbltActive () {
  tsys.style.display ='none';
  hmblt.style.display ='block';
  fhrzn.style.display ='none';
  dccfhrzn.style.display ='none';
  curmcptsys.style.display ='none';
  curmcphmblt.style.display ='block';
  curmcpfhrzn.style.display ='none';
}

function nonmcphmbltActive () {
  tsys.style.display ='none';
  hmblt.style.display ='block';
  fhrzn.style.display ='none';
  dccfhrzn.style.display ='none';
  curmcptsys.style.display ='none';
  curmcphmblt.style.display ='none';
  curmcpfhrzn.style.display ='none';
}

function fhrznActive() {
  tsys.style.display ='none';
  hmblt.style.display ='none';
  fhrzn.style.display ='block';
  dccfhrzn.style.display ='none';
  curmcptsys.style.display ='none';
  curmcphmblt.style.display ='none';
  curmcpfhrzn.style.display ='none';
}

function mcpfhrznActive () {
  tsys.style.display ='none';
  hmblt.style.display ='none';
  fhrzn.style.display ='block';
  dccfhrzn.style.display ='none';
  curmcptsys.style.display ='none';
  curmcphmblt.style.display ='none';
  curmcpfhrzn.style.display ='block';
}

function nonmcpfhrznActive () {
  tsys.style.display ='none';
  hmblt.style.display ='none';
  fhrzn.style.display ='block';
  dccfhrzn.style.display ='block';
  curmcptsys.style.display ='none';
  curmcphmblt.style.display ='none';
  curmcpfhrzn.style.display ='none';
}

//]]>
</script>
EOF

  my $captcha = new PlugNPay::Util::Captcha::ReCaptcha();
  print $captcha->headHTML();

  print "</head>\n";

  print "<body>\n";

  print "<table>\n";
  print "  <tr>\n";
  print "    <td><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Payment Gateway Logo\" /></td>\n";
  print "    <td class=\"right\">&nbsp;</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=2><img src=\"/adminlogos/masthead_background.gif\" alt=\"Corp. Logo\" width=750 height=16 /></td>\n";
  print "    </tr>\n";
  print "</table>\n";

  print "<table class=\"frame\">\n";
  print "  <tr>\n";
  print "    <td><h1>Merchant Registration Form</h1></td>\n";
  print "    <td></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<hr id=\"under\" />\n";

  #print "  <form action=\"https://pay1.plugnpay.com/payment/inputtest.cgi\" method=\"post\" name=\"addmerchant\" id=\"addmerchant\">\n"; # for testing
  print "<form action=\"$reseller::path_cgi\" method=\"post\" name=\"addmerchant\">\n";
  print "<input type=hidden name=\"function\" value=\"$nextfunction\"><input type=hidden name=\"username\" value=\"$query{'username'}\">\n";

  print "<table>\n";

  if ( $error > 0 ) {
    print "  <tr>\n";
    print "    <th class=\"badcolor\">ERROR: </th>\n";
    print "    <td class=\"badcolor\">Some Required Information is missing.<br>Please complete the fields marked in RED. <br>\n";
    my @errors = split( /\:/, $errvar );
    foreach my $tmperr (@errors) {
      print "$tmperr <br>\n";
    }
    print "</td>\n";
    print "  </tr>\n";
  }

  if ( $reseller eq "globalox" ) {
    $prefilled{'techname'}  = "Cylde Brinley";
    $prefilled{'techtel'}   = "417\-725\-7610";
    $prefilled{'techemail'} = "webmaster\@natins.com";

    print "  <tr>\n";
    print "    <th class=\"right\">Online Exchange ID: </th>\n";
    print "    <td><input name=\"OnlineExchageID\" size=9 maxlength=9 type=text autocomplete=\"off\"></td>\n";
    print "  </tr>\n";

  } else {
    $prefilled{'techname'}  = $query{'techname'};
    $prefilled{'techtel'}   = $query{'techtel'};
    $prefilled{'techemail'} = $query{'techemail'};
  }

  if ( ( $function eq "editcust" ) or ( $function eq "Edit Account Info" ) ) {
    print "  <tr>\n";
    print "    <th class=\"right\">Username: </th>\n";
    print "    <td>$query{'username'}</td>\n";
    print "  </tr>\n";
    if ( $reseller::global_features->get('reseller_allowPwdReset') ) {
      print "  <tr>\n";
      print "    <th class=\"right\">Password: </th>\n";

      #print "    <td>Temporarily Unavailable</td></tr>\n";
      print "    <td><a href=\"$reseller::path_cgi?function=autochangepw\&username=$query{'username'}\" target=\"newWin\">Reset and Email Password</a></td>\n";
      print "  </tr>\n";
    }
  }

  if ( $reseller =~ /^(eonlined)$/ ) {
    my (%selected);
    $selected{ $query{'masteracct'} } = "selected";
    print "  <tr>\n";
    print "    <th>Master Merch Acct: </th>\n";
    print "    <td><select name=\"masteracct\">\n";
    print "<option value=\"\">Not Applicable</option>\n";
    foreach my $var ( @{ $reseller::mastermerch{$reseller} } ) {
      print "<option value=\"$var\" $selected{$var}>$var</option>\n";
    }
    print "</select></td>\n";
    print "  </tr>\n";

    $selected{'1'} = " checked";
    print "  <tr>\n";
    print "    <th>Sub Acct: </th>\n";
    print "    <td><input type=checkbox name=\"subacctflag\" value=\"1\" $selected{$query{'subacctflag'}}></td>\n";
    print "  </tr>\n";
  }

  print "  <tr>\n";
  print "    <th class=\"label\"><nobr>Merchant Contact Information</nobr></th>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th>Business Name: </th>\n";
  print "    <td><input name=\"company\" size=30 maxlength=39 type=text value=\"$query{'company'}\" /></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"$color{'contact'}\">Contact Name: </th>\n";
  print "    <td><input name=\"contact\" size=30 maxlength=39 type=text value=\"$query{'contact'}\" /></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th></th>\n";
  print "    <td>* Please enter first and last name only</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"$color{'addr1'}\">Address 1: </th>\n";
  print "    <td><input name=\"addr1\" size=30 maxlength=39 type=text value=\"$query{'addr1'}\" /></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"$color{'addr2'}\">Address 2: </th>\n";
  print "    <td><input name=\"addr2\" size=30 maxlength=39 type=text value=\"$query{'addr2'}\" /></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"$color{'city'}\">City: </th>\n";
  print "    <td><input name=\"city\" size=20 type=text value=\"$query{'city'}\" /></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"$color{'state'}\">State: </th>\n";
  print "    <td><select name=\"state\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\">\n";

  foreach my $key ( sort keys %USstates ) {
    if ( $key eq $query{'state'} ) {
      print "<option value=\"$key\" selected>$USstates{$key}</option>\n";
    } else {
      print "<option value=\"$key\">$USstates{$key}</option>\n";
    }
  }
  foreach my $key ( sort keys %USterritories ) {
    if ( $key eq $query{'state'} ) {
      print "<option value=\"$key\" selected>$USterritories{$key}</option>\n";
    } else {
      print "<option value=\"$key\">$USterritories{$key}</option>\n";
    }
  }
  if ( $usonly ne "yes" ) {
    foreach my $key ( sort keys %CNprovinces ) {
      if ( $key eq $query{'state'} ) {
        print "<option value=\"$key\" selected>$CNprovinces{$key}</option>\n";
      } else {
        print "<option value=\"$key\">$CNprovinces{$key}</option>\n";
      }
    }
  }
  print "</select></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"$color{'zip'}\">Zip: </th>\n";
  print "    <td><input name=\"zip\" size=10 type=text value=\"$query{'zip'}\" maxlength=10 /></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th>Country:</th>\n";
  print "    <td><select name=\"country\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\">\n";

  if ( ( $query{'country'} eq "" ) or ( $query{'country'} eq "USA" ) ) {
    $query{'country'} = "US";
  }
  foreach my $key ( sort_hash( \%countries ) ) {
    if ( $key eq $query{'country'} ) {
      print "<option value=\"$key\" selected>$countries{$key}</option>\n";
    } else {
      print "<option value=\"$key\">$countries{$key}</option>\n";
    }
  }
  print "</select></td></tr>\n";
  if ( $nextfunction eq "updatecust" ) {
    print "  <tr>\n";
    print "    <th class=\"$color{'tel'}\">Telephone: </th>\n";
    print "    <td><input name=\"tel\" size=20 type=tel value=\"$query{'tel'}\"></td>\n";
    print "  </tr>\n";
  } else {
    print "  <tr>\n";
    print "    <th class=\"$color{'tel'}\">Telephone: </th>\n";
    print "    <td><input name=\"tel\" size=20 type=tel value=\"$query{'tel'}\"></td>\n";
    print "  </tr>\n";
  }

  print "  <tr>\n";
  print "    <th>Fax: </th>\n";
  print "    <td><input name=\"fax\" size=20 type=tel value=\"$query{'fax'}\" /></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th class=\"$color{'merchemail'}\">Main Contact E-mail: </th>\n";
  my $escapedMerchEmail = CGI::escapeHTML( $query{'merchemail'} );
  print "    <td><input name=\"merchemail\" size=45 maxlength=45 type=text value=\"$escapedMerchEmail\" /></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th class=\"$color{'merchemail2'}\">Confirm Main Contact E-mail: </th>\n";
  my $escapedMerchEmail2 = CGI::escapeHTML( $query{'merchemail2'} );
  print "    <td><input name=\"merchemail2\" size=45 maxlength=45 type=text value=\"$escapedMerchEmail2\" /></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th></th>\n";
  print "    <td>* Integration instructions will be sent to this email address</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th>Tech. Contact - Name: </th>\n";
  print "    <td><input name=\"techname\" size=30 maxlength=39 type=text";
  if ( $prefilled{'techname'} ne "" ) {
    print " value=\"$prefilled{'techname'}\"";
  }
  print "></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th>Tech. Contact - Tel#: </th>\n";
  print "    <td><input name=\"techtel\" size=30 maxlength=39 type=text";
  if ( $prefilled{'techtel'} ne "" ) {
    print " value=\"$prefilled{'techtel'}\"";
  }
  print "></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th>Tech. Contact - Email: </th>\n";
  print "    <td><input name=\"techemail\" size=30 maxlength=39 type=text";
  if ( $prefilled{'techemail'} ne "" ) {
    my $escapedTechEmail = CGI::escapeHTML( $prefilled{'techemail'} );
    print " value=\"$escapedTechEmail\"";
  }
  print "></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th></th>\n";
  print "    <td> * Integration instructions will be sent to this email address</td>\n";
  print "  <tr>\n";

  print "  <tr>\n";
  print "    <th>Merchant's Website URL: </th>\n";
  print "    <td><input name=\"url\" size=30 maxlength=39 value=\"$query{'url'}\" type=text /></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th class=\"label\"><nobr>Account Billing Information</nobr></th>\n";
  print "    <td>&nbsp;</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"$color{'email'}\">Billing E-mail: </th>\n";
  my $escapedEmail = CGI::escapeHTML( $query{'email'} );
  print "    <td><input name=\"email\" size=35 maxlength=79 type=text value=\"$escapedEmail\" /></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"$color{'email2'}\">Confirm Billing E-mail: </th>\n";
  my $escapedEmail2 = CGI::escapeHTML( $query{'email2'} );
  print "    <td><input name=\"email2\" size=35 maxlength=79 type=text value=\"$escapedEmail2\" /></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td>&nbsp;</td>\n";
  print "    <td>* Monthly billing will be sent to this email address<br />\n";
  print " *IF YOU PAY THE MONTHLY FEES FOR YOUR MERCHANTS, enter your<br> email address instead of your merchant's </td>\n";
  print "  </tr>\n";

  ## talk to barbara about this, resellers were inputting mid & tid and they didn't make it into the database
  # if ($function eq "editapp")

  print "  <tr>\n";
  print "    <th class=\"label\"><nobr>Processor Information</nobr></th>\n";
  print "    <td>&nbsp;</td>\n";
  print "  </tr>\n";

  if ( $reseller =~ /^(planetpa|fifththird)$/ ) {
    print "  <tr>\n";
    print "    <th>Merchant Type:</th>\n";
    print
      "    <td><input type=radio name=\"merchant_type\" value=\"domestic\"> Domestic <input type=radio name=\"merchant_type\" value=\"mcp\" checked> MCP <input type=radio name=\"merchant_type\" value=\"dcc\"> DCC </td>\n";
    print "  </tr>\n";
  }
  if ( $reseller =~ /^planetpa$/ ) {
    print "  <tr>\n";
    print "    <th>Merchant Bank:</th>\n";
    print
      "    <td><input type=radio name=\"merchant_bank\" value=\"tsys\"> TSYS <input type=radio name=\"merchant_bank\" value=\"Humbolt\"> Humbolt <input type=radio name=\"merchant_bank\" value=\"other\" checked> Other </td>\n";
    print "  </tr>\n";
  }

  # for edit merchant - will need to print all fields?
  if ( $nextfunction eq "updatecust" ) {
    print "  <tr>\n";
    print "    <td align=right>Processor:</td>";
    print "    <td>$query{'processor'}</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td align=right>Merchant ID:</td>";
    print "    <td>$query{'merchant_id'}</td>\n";
    print "  </tr>\n";
    $query{'terminal_id'} =~ s/./X/g;
    print "  <tr>\n";
    print "    <td align=right>Terminal ID:</td>";
    print "    <td>$query{'terminal_id'}</td>\n";
    print "  </tr>\n";

    my $pcttype = "Percent";
    if ( $query{'pcttype'} eq "trans" ) {
      $pcttype = "Per Transaction";
    }

    my ($billauth);
    if ( $query{'billauth'} eq "yes" ) {
      $billauth = "<font color=\"#50ae26\"><b>Yes</b></font>";
    } else {
      $billauth = "<font color=\"#ff0000\"><b>No</b></font>";
    }

    print "  <tr>\n";
    print "    <th class=\"label\"><nobr>Monthly Billing</nobr></th>\n";
    print "    <td>&nbsp;</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td align=right>Setup Fee:</td>";
    printf( "    <td>%0.2f</td>\n", $query{'setupfee'} );
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td align=right>Monthly Min:</td>";
    printf( "    <td>%0.2f</td>\n", $query{'monthly'} );
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td align=right>Extra Fees:</td>";
    printf( "    <td>%0.2f</td>\n", $query{'extrafees'} );
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td align=right>Per Tran:</td>";
    printf( "    <td>%s %s</td>\n", $query{'percent'}, $pcttype );
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td align=right>Over:</td>";
    printf( "    <td>%s Transactions</td>\n", $query{'overtran'} );
    print "  </tr>\n";

    print "  <tr>\n";
    print "    <td colspan=2> </td>";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td align=right>Have Bill Auth:</td>";
    print "    <td>$billauth</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <td colspan=2> </td>";
    print "  </tr>\n";

    print "</table>\n";
  } else {

    print "  <tr>\n";
    print "    <th>Processor:</th>\n";

    print "    <td><select name=\"processor\"  id=\"processorName\" onchange=\"showfield(this.options[this.selectedIndex].value)\">\n";

    if ( $query{'processor'} ne "" ) {
      print "<option value=\"$query{'processor'}\">$query{'processor'}</option>\n";
    } else {
      print "<option value=\"\" selected=\"selected\">Select Processor</option>\n";
    }

    # sort by value instead of key
    foreach my $var ( sort { $processor_hash{$a} cmp $processor_hash{$b} } keys %processor_hash ) {
      print "<option value=\"$var\"> $processor_hash{$var}</option>";
    }

    print "</select>";
    print "<input type=hidden name=\"proc_type\" value=\"authonly\">\n";

    print "</td>\n";
    print "  </tr>\n";

    print "</table>\n";

    print "<div id=\"procfields\"></div>\n";

    print "<div id=\"fthird\" style=\"display:none\">\n";
    print "<table>\n";
    print "  <tr><th>Merchant ID: </th><td><input type=text name=\"merchant_id\" size=30 maxlength=40 value=\"$query{'merchant_id'}\" autocomplete=\"off\"/></td></tr>\n";
    print "  <tr><th>Terminal ID: <\/th><td><input type=text name=\"terminal_id\" size=30 maxlength=40 value=\"\" autocomplete=\"off\"/><\/td><\/tr>\n";
    print
      "  <tr><th>Retail Account: </th><td><nobr><input type=checkbox name=\"industrycode\" value=\"retail\" $selected{'retail'}/>* Select <span>only</span> if merchant will pass swipe data to a retail merchant account</nobr></td></tr>\n";
    print "  <tr>\n";
    print "    <th>BankNum/ID: </th>\n";
    print "    <td><input type=text name=\"fthird_bankid\" size=30 maxlength=40 value=\"$query{'fthird_bankid'}\" autocomplete=\"off\"/> 6 digits</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <th>Category Code: </th>\n";
    print "    <td><input type=text name=\"fthird_categorycode\" size=30 maxlength=40 value=\"$query{'fthird_categorycode'}\" autocomplete=\"off\"/> 4 digits</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <th>Merchant Type: </th>\n";
    print "    <td><input type=radio name=\"fthird_merchant_type\" value=\"domestic\" onclick=\"javascript:nonfmcpActive();\"> Domestic (USD Processing Only)\n";
    print "<input type=radio name=\"fthird_merchant_type\" value=\"mcp\" onclick=\"javascript:fmcpActive();\"> MCP\n";
    print "<input type=radio name=\"fthird_merchant_type\" value=\"dcc\" onclick=\"javascript:nonfmcpActive();\"> DCC</td>\n";
    print "  </tr>\n";
    print "</table>\n";

    print "<div id=\"nonfmcp\" style=\"display:none\">\n";

    # this div is here to prevent javascript error
    print "</div>\n";

    print "<div id=\"fmcp\" style=\"display:none\">\n";
    print "<table>\n";
    print "  <tr>\n";
    print "    <th>Currency: </th>\n";
    print "    <td><select name=\"fmcp_currency\" multiple=\"yes\" size=4>\n";
    print "<option value=\"aud\"> Australian Dollars </option>\n";
    print "<option value=\"cad\"> Canadian Dollar </option>\n";
    print "<option value=\"cny\"> Chinese RenMinBi</option>\n";
    print "<option value=\"eur\"> Euro </option>\n";
    print "<option value=\"gbp\"> British Pounds</option>\n";
    print "<option value=\"jpy\"> Japanese Yen </option>\n";
    print "<option value=\"krw\"> Korean Won </option>\n";
    print "<option value=\"nok\"> Norwgian Kroner </option>\n";

    #print "<option value=\"mxn\"> Mexican Peso </option>\n";
    print "<option value=\"usd\"> US Dollars </option>\n";
    print "</select></td>\n";
    print "    <td>Hold the 'Ctrl' key while clicking to select more than one option</td>\n";
    print "  </tr>\n";
    print "</table>\n";
    print "</div>\n";    # end div id fmcp

    print "</div>\n";    # end div fthird

    print "<div id=\"ppay\" style=\"display:none\">\n";
    print "<table>\n";
    print "  <tr>\n";
    print "    <th>Merchant ID: </th>\n";
    print "    <td><input type=text name=\"merchant_id\" size=30 maxlength=40 value=\"$query{'merchant_id'}\" autocomplete=\"off\"/></td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <th>Merchant Bank:</th>\n";
    print "    <td><input type=radio name=\"merchant_bank\" value=\"tsys\" onclick=\"javascript:tsysActive();\" /> TSYS\n";
    print "  <input type=radio name=\"merchant_bank\" value=\"Humbolt\" onclick=\"javascript:hmbltActive();\" /> Humbolt\n";
    print "  <input type=radio name=\"merchant_bank\" value=\"FirstHorizon\" onclick=\"javascript:fhrznActive();\" /> First Horizon\n";
    print "</td>\n";
    print "  </tr>\n";
    print "</table>\n";

    print "<div id=\"fhrzn\" style=\"display:none\">\n";
    print "<table>\n";
    print "  <tr>\n";
    print "    <th>Merchant Type: </th>\n";
    print "    <td><input type=radio name=\"fhrzn_merchant_type\" value=\"mcp\" onclick=\"javascript:mcpfhrznActive();\" /> MCP\n";
    print "<input type=radio name=\"fhrzn_merchant_type\" value=\"dcc\" onclick=\"javascript:nonmcpfhrznActive();\" /> DCC\n";
    print "</td>\n";
    print "  </tr>\n";
    print "</table>\n";
    print "</div>\n";    # end div id fhrcn

    print "<div id=\"dccfhrzn\" style=\"display:none\">\n";
    print "<table>\n";
    print "  <tr>\n";
    print "    <th>V#/Terminal ID: </th>\n";
    print "    <td><input type=text name=\"dccfhrzn_terminal_id\" size=30 maxlength=40 value=\"$query{'terminal_id'}\" autocomplete=\"off\"/> 8 digits</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <th>Category Code: </th>\n";
    print "    <td><input type=text name=\"dccfhrzn_categorycode\" size=30 maxlength=40 value=\"$query{'dccfhrzn_categorycode'}\" autocomplete=\"off\"/> 4 digits</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <th>Bin: </th>\n";
    print "    <td><input type=text name=\"dccfhrzn_bin\" size=30 maxlength=40 value=\"$query{'dccfhrzn_bin'}\" autocomplete=\"off\"/> 6 digits</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <th>Agent Bank: </th>\n";
    print "    <td><input type=text name=\"dccfhrzn_agentbank\" size=30 maxlength=40 value=\"$query{'dccfhrzn_agentbank'}\" autocomplete=\"off\"/> 6 digits</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <th>Agent Chain: </th>\n";
    print "    <td><input type=text name=\"dccfhrzn_agentchain\" size=30 maxlength=40 value=\"$query{'dccfhrzn_agentchain'}\" autocomplete=\"off\"/> 6 digits</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <th>Store Number: </th>\n";
    print "    <td><input type=text name=\"dccfhrzn_storenum\" size=30 maxlength=40 value=\"$query{'dccfhrzn_storenum'}\" autocomplete=\"off\"/> 4 digits</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <th>Terminal Number: </th>\n";
    print "    <td><input type=text name=\"dccfhrzn_terminalnum\" size=30 maxlength=40 value=\"$query{'dccfhrzn_terminalnum'}\" autocomplete=\"off\"/> 4 digits</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <th>Retail Account: </th>\n";
    print
      "    <td><nobr><input type=checkbox name=\"dccfhrzn_industrycode\" value=\"retail\" $selected{'retail'}/>* Select <span>only</span> if merchant will pass swipe data to a retail merchant account</nobr></td>\n";
    print "  </tr>\n";
    print "</table>\n";
    print "</div>\n";    # end div id dccfhrzn

    print "<div id=\"tsys\" style=\"display:none\">\n";
    print "<table>\n";
    print "  <tr>\n";
    print "    <th>Merchant Type: </th>\n";
    print "    <td><input type=radio name=\"tsys_merchant_type\" value=\"mcp\" onclick=\"javascript:mcptsysActive();\" /> MCP\n";
    print "  <input type=radio name=\"tsys_merchant_type\" value=\"dcc\" onclick=\"javascript:nonmcptsysActive();\" /> DCC\n";
    print "</td>\n";
    print "  </tr>\n";
    print "</table>\n";

    print "<table>\n";
    print "  <tr>\n";
    print "    <th>V#/Terminal ID: </th>\n";
    print "    <td><input type=text name=\"tsys_terminal_id\" size=30 maxlength=40 value=\"$query{'tsys_terminal_id'}\" autocomplete=\"off\"/> 8 digits</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <th>Category Code: </th>\n";
    print "    <td><input type=text name=\"tsys_categorycode\" size=30 maxlength=40 value=\"$query{'tsys_categorycode'}\" autocomplete=\"off\"/> 4 digits</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <th>Bin: </th>\n";
    print "    <td><input type=text name=\"tsys_bin\" size=30 maxlength=40 value=\"$query{'tsys_bin'}\" autocomplete=\"off\"/> 6 digits</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <th>Agent Bank: </th>\n";
    print "    <td><input type=text name=\"tsys_agentbank\" size=30 maxlength=40 value=\"$query{'tsys_agentbank'}\" autocomplete=\"off\"/> 6 digits</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <th>Agent Chain: </th>\n";
    print "    <td><input type=text name=\"tsys_agentchain\" size=30 maxlength=40 value=\"$query{'tsys_agentchain'}\" autocomplete=\"off\"/> 6 digits</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <th>Store Number: </th>\n";
    print "    <td><input type=text name=\"tsys_storenum\" size=30 maxlength=40 value=\"$query{'tsys_storenum'}\" autocomplete=\"off\"/> 4 digits</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <th>Terminal Number: </th>\n";
    print "    <td><input type=text name=\"tsys_terminalnum\" size=30 maxlength=40 value=\"$query{'tsys_terminalnum'}\" autocomplete=\"off\"/> 4 digits</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <th>Retail Account: </th>\n";
    print
      "    <td><nobr><input type=checkbox name=\"tsys_industrycode\" value=\"retail\" $selected{'retail'}/>* Select <span>only</span> if merchant will pass swipe data to a retail merchant account</nobr></td>\n";
    print "  </tr>\n";
    print "</table>\n";
    print "</div>\n";    # end div tsys

    print "<div id=\"hmblt\" style=\"display:none\">\n";

    # new expeirment
    print "<table>\n";
    print "  <tr>\n";
    print "    <th>Merchant Type: </th>\n";
    print "    <td><input type=radio name=\"hmblt_merchant_type\" value=\"mcp\" onclick=\"javascript:mcphmbltActive();\" /> MCP\n";
    print "  <input type=radio name=\"hmblt_merchant_type\" value=\"dcc\" onclick=\"javascript:nonmcphmbltActive();\" /> DCC\n";
    print "</td>\n";
    print "  </tr>\n";
    print "</table>\n";

    # end new expr

    print "<table>\n";
    print "  <tr>\n";
    print "    <th>BankNum/ID: </th>\n";
    print "    <td><input type=hidden name=\"hmblt_bin\" value=\"441895\" /> 441895</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <th>Category Code: </th>\n";
    print "    <td><input type=text name=\"hmblt_categorycode\" size=30 maxlength=40 value=\"$query{'hmblt_categorycode'}\" autocomplete=\"off\"/> 4 digits</td>\n";
    print "  </tr>\n";
    print "</table>\n";
    print "</div>\n";    # end div hmblt

    #Tsys/MCP currency
    print "<div id=\"curmcptsys\" style=\"display:none\">\n";
    print "<table>\n";
    print "  <tr>\n";
    print "    <th>Currency: </th>\n";
    print "    <td><select name=\"curmcptsys_currency\" multiple=\"yes\" size=4>\n";
    print "<option value=\"aud\"> Australian Dollars </option>\n";
    print "<option value=\"cad\"> Canadian Dollar </option>\n";
    print "<option value=\"cny\"> Chinese RenMinBi</option>\n";
    print "<option value=\"eur\"> Euro </option>\n";
    print "<option value=\"gbp\"> British Pounds</option>\n";
    print "<option value=\"jpy\"> Japanese Yen </option>\n";
    print "<option value=\"krw\"> Korean Won </option>\n";
    print "<option value=\"nok\"> Norwegian Kroner </option>\n";
    print "<option value=\"mxn\"> Mexican Peso </option>\n";
    print "<option value=\"usd\"> US Dollars </option>\n";
    print "</select></td>\n";
    print "    <td>Hold the 'Ctrl' key while clicking to select more than one option</td>\n";
    print "  </tr>\n";
    print "</table>\n";
    print "</div>\n";    # end div curmcptsys

    #Humboldt/MCP currency
    print "<div id=\"curmcphmblt\" style=\"display:none\">\n";
    print "<table>\n";
    print "  <tr>\n";
    print "    <th>Currency: </th>\n";
    print "    <td><select name=\"curmcphmblt_currency\" multiple=\"yes\" size=4>\n";
    print "<option value=\"aud\"> Australian Dollars </option>\n";
    print "<option value=\"cad\"> Canadian Dollar </option>\n";
    print "<option value=\"eur\"> Euro </option>\n";
    print "<option value=\"gbp\"> British Pounds</option>\n";
    print "<option value=\"jpy\"> Japanese Yen </option>\n";
    print "<option value=\"nok\"> Norwegian Kroner </option>\n";
    print "<option value=\"mxn\"> Mexican Peso </option>\n";
    print "<option value=\"sgd\"> Singapore Dollars </option>\n";
    print "</select></td>\n";
    print "    <td>Hold the 'Ctrl' key while clicking to select more than one option</td>\n";
    print "  </tr>\n";
    print "</table>\n";
    print "</div>\n";    # end div curmcphmblt

    #First Horizan /MCP currency and other fields
    print "<div id=\"curmcpfhrzn\" style=\"display:none\">\n";

    print "<table>\n";
    print "  <tr>\n";
    print "    <th>BankNum/ID: </th>\n";
    print "    <td><input type=text name=\"curmcpfhrzn_bin\" size=30 maxlength=40 value=\"$query{'curmcpfhrzn_bin'}\" autocomplete=\"off\"/> 6 digits</td>\n";
    print "  </tr>\n";
    print "  <tr>\n";
    print "    <th>Category Code: </th>\n";
    print "    <td><input type=text name=\"curmcpfhrzn_categorycode\" size=30 maxlength=40 value=\"$query{'curmcpfhrzn_categorycode'}\" autocomplete=\"off\"/> 4 digits</td>\n";
    print "  </tr>\n";
    print "</table>\n";

    print "<table>\n";
    print "  <tr>\n";
    print "    <th>Currency: </th>\n";
    print "    <td><select name=\"curmcpfhrzn_currency\" multiple=\"yes\" size=4>\n";
    print "<option value=\"aud\"> Australian Dollars </option>\n";
    print "<option value=\"cad\"> Canadian Dollar </option>\n";
    print "<option value=\"eur\"> Euro </option>\n";
    print "<option value=\"gbp\"> British Pounds</option>\n";
    print "<option value=\"jpy\"> Japanese Yen </option>\n";
    print "<option value=\"nok\"> Norwegian Kroner </option>\n";
    print "<option value=\"usd\"> US Dollars </option>\n";
    print "</select></td>\n";
    print "    <td>Hold the 'Ctrl' key while clicking to select more than one option</td>\n";
    print "  </tr>\n";
    print "</table>\n";
    print "</div>\n";    # end div curmcpfhrzn

    print "</div>\n";    # end div ppay

    print "<div id=\"currency\" style=\"display:none\">\n";

    print "<table>\n";
    print "  <tr>\n";
    print "    <th>Currency:</th>\n";
    print "    <td><select name=\"currency\">\n";
    if ( $currency eq "" ) {
      $currency = "USD";
    }
    foreach my $key ( sort keys %isotables::currencyUSD2 ) {
      print "<option value=\"$key\"";
      if ( $key =~ /$currency/i ) {
        print " selected";
      }
      print "> $key </option>\n";
    }
    print "</select></td>\n";
    print "  </tr>\n";
    print "</table>\n";
    print "</div>\n";    # end div currency

    print "<div id=\"country\" style=\"display:none\">\n";
    print "<table>\n";
    print "  <tr>\n";
    print "        <th>Country:</th>\n";
    print "        <td><select name=\"wc_country\" onfocus=\"this.style.backgroundColor='#f3f9e8'\" onblur=\"this.style.backgroundColor='#ffffff'\">\n";
    if ( ( $query{'wc_country'} eq "" ) or ( $query{'wc_country'} eq "USA" ) ) {
      $query{'wc_country'} = "US";
    }
    foreach my $key ( sort_hash( \%countries ) ) {
      if ( $key eq $query{'wc_country'} ) {
        print "<option value=\"$key\" selected>$countries{$key}</option>\n";
      } else {
        print "<option value=\"$key\">$countries{$key}</option>\n";
      }
    }
    print "</select></td></tr>\n";
    print "</table>\n";
    print "</div>\n";    # end div country

  }

  print "<table>\n";
  if ( $reseller =~ /^(electro|globalpy|payameri)$/ ) {
    print "<tr><th>Agent Code:</th><td><input type=text name=\"agentcode\" size=20 max=40 value=\"$agentcode\" autocomplete=\"off\"></td></tr>\n";
  }
  print "  <tr>\n";
  print "    <th>Comments:</th>\n";
  print "    <td><textarea name=\"newcomment\" rows=\"5\" cols=\"40\" wrap=\"virtual\">$query{'newcomment'}</textarea></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th class=\"$color{'captcha'}\">Captcha</th>\n";
  print "    <td>" . $captcha->formHTML() . "</td>\n";
  print "  </tr>\n";

  print "</table>\n";

  print "<table id=\"buttons\">\n";
  print "  <tr>\n";
  print "  <tr><td>&nbsp;</td></tr>\n";
  print "  <tr>\n";
  print "    <td>&nbsp;</td>\n";
  print "    <td><h1>Please be sure all appropriate fields are complete!</h1>\n";
  print "<br>\n";
  print "<input type=submit value=\"Submit Application\" />\n";
  print "<input type=reset value=\"Clear\" />\n";
  print "<input type=button value=\"Back to Reseller Admin Area\" onclick=\"javascript:history.go(-1)\"/>\n";

  print "  </tr>\n";
  print "</table>\n";
  print "</form>\n";

  my @now          = gmtime(time);
  my $current_year = $now[5] + 1900;

  print "<hr id=\"over\" />\n";
  print "<table class=\"frame\">\n";
  print "  <tr>\n";
  print "    <td align=left>&nbsp;</td>\n";
  print "    <td class=\"right\">&copy; $current_year, Plug 'n Pay Technologies, Inc.</td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</body>\n";
  print "</html>\n";
  exit;

}

sub updateapp {
  my (@array) = %query;
  $error = &input_check(@array);

  %features = ();

  $client = $query{'client'};

  if ( $client ne "remote" ) {

    # we aren't using remote so we need to validate the captcha

    my $captcha = new PlugNPay::Util::Captcha::ReCaptcha();
    my $ok = $captcha->isValid( $ENV{'REMOTE_USER'}, $reseller::answer, $ENV{'REMOTE_ADDR'} );
    if ( !$ok ) {
      $error = 1;
      $errvar .= ":Invalid Captcha";
      $color{'captcha'} = "badcolor";
    }
  }

  if ( $error > 0 ) {
    if ( $client eq "remote" ) {
      print "FinalStatus=failure\&MErrMsg=$errvar";
      exit;
    } else {
      &editapp();
    }
  }

  my %inherit = ();

  $username = $query{'username'};

  if ( $query{'pnpusername'} ne "" ) {
    $username = $query{'pnpusername'};
  }

  $company       = $query{'company'};
  $contact       = $query{'contact'};
  $addr1         = $query{'addr1'};
  $addr2         = $query{'addr2'};
  $city          = $query{'city'};
  $state         = $query{'state'};
  $zip           = $query{'zip'};
  $tel           = $query{'tel'};
  $fax           = $query{'fax'};
  $email         = $query{'email'};
  $techname      = $query{'techname'};
  $techtel       = $query{'techtel'};
  $techemail     = $query{'techemail'};
  $url           = $query{'url'};
  $processor     = $query{'processor'};
  $proc_type     = $query{'proc_type'};
  $merchant_id   = $query{'merchant_id'};
  $terminal_id   = $query{'terminal_id'};
  $busibnk       = $query{'bank'};
  $accountnum    = $query{'accountnum'};
  $routingnum    = $query{'routingnum'};
  $card_number   = $query{'card_number'};
  $monthexp      = $query{'month-exp'};
  $yearexp       = $query{'year-exp'};
  $country       = $query{'country'};
  $cards_allowed = $query{'cards_allowed'};
  $merchemail    = $query{'merchemail'};
  $exp_date      = $monthexp . '/' . $yearexp;
  $accttype      = $query{'paymentmethod'};
  $accttype =~ tr/A-Z/a-z/;

  $subacctflag = $query{'subacctflag'};
  $subacctflag =~ s/[^0-9]//g;
  $masteracct = $query{'masteracct'};
  $masteracct =~ s/[^a-zA-Z0-9]//g;

  if ( $query{'processor'} eq "planetpay" ) {    # figure out planetpayment fields
    if ( $query{'merchant_bank'} eq "FirstHorizon" ) {
      if ( $query{'fhrzn_merchant_type'} eq "dcc" ) {
        $pubsecret     = $query{'dccfhrzn_terminal_id'};
        $categorycode  = $query{'dccfhrzn_categorycode'};
        $bin           = $query{'dccfhrzn_bin'};
        $agentbank     = $query{'dccfhrzn_agentbank'};
        $agentchain    = $query{'dccfhrzn_agentchain'};
        $storenum      = $query{'dccfhrzn_storenum'};
        $terminalnum   = $query{'dccfhrzn_terminalnum'};
        $industrycode  = $query{'dccfhrzn_industrycode'};
        $merchant_bank = $query{'merchant_bank'};
        $merchant_type = $query{'fhrzn_merchant_type'};
      } elsif ( $query{'fhrzn_merchant_type'} eq "mcp" ) {
        $categorycode         = $query{'curmcpfhrzn_categorycode'};
        $bin                  = $query{'curmcpfhrzn_bin'};
        $merchant_bank        = $query{'merchant_bank'};
        $merchant_type        = $query{'fhrzn_merchant_type'};
        @curmcpfhrzn_currency = $data->param('curmcpfhrzn_currency');
        $currency             = join( " ", @curmcpfhrzn_currency );
      }
    } elsif ( $query{'merchant_bank'} eq "tsys" ) {
      $pubsecret     = $query{'tsys_terminal_id'};
      $categorycode  = $query{'tsys_categorycode'};
      $bin           = $query{'tsys_bin'};
      $agentbank     = $query{'tsys_agentbank'};
      $agentchain    = $query{'tsys_agentchain'};
      $storenum      = $query{'tsys_storenum'};
      $terminalnum   = $query{'tsys_terminalnum'};
      $industrycode  = $query{'tsys_industrycode'};
      $merchant_bank = $query{'merchant_bank'};
      $merchant_type = $query{'tsys_merchant_type'};

      if ( $query{'tsys_merchant_type'} eq "mcp" ) {
        @curmcptsys_currency = $data->param('curmcptsys_currency');
        $currency = join( " ", @curmcptsys_currency );
      }
    } elsif ( $query{'merchant_bank'} eq "Humbolt" ) {
      $categorycode  = $query{'hmblt_categorycode'};
      $bin           = $query{'hmblt_bin'};
      $merchant_bank = $query{'merchant_bank'};
      $merchant_type = $query{'hmblt_merchant_type'};
      if ( $query{'hmblt_merchant_type'} eq "mcp" ) {
        @curmcphmblt_currency = $data->param('curmcphmblt_currency');
        $currency = join( " ", @curmcphmblt_currency );
      }
    }

    #print "$currency";
    #exit;
  } elsif ( $query{'processor'} eq "fifththird" ) {    # figure out fifth third fields
    $bankid        = $query{'fthird_bankid'};
    $categorycode  = $query{'fthird_categorycode'};
    $merchant_type = $query{'fthird_merchant_type'};
    $industrycode  = $query{'industrycode'};
    $pubsecret     = $query{'terminal_id'};
    if ( $query{'fthird_merchant_type'} eq "mcp" ) {
      @fmcp_currency = $data->param('fmcp_currency');
      $currency = join( " ", @fmcp_currency );

      #print "$currency";
      #exit;
    }
  } elsif ( $query{'processor'} eq "wirecard" ) {
    $country = $query{'wc_country'};
    $loginun = $query{'wc_loginun'};
    $loginpw = $query{'wc_loginpw'};
  } else {
    $agentcode      = $query{'agentcode'};
    $bin            = $query{'bin'};
    $banknum        = $query{'banknum'};
    $bankid         = $query{'bankid'};                                        # needed to add this so it populates
    $saleschannel   = $query{'saleschannel'};                                  # "
    $account        = $query{'account'};                                       # "
    $password       = $query{'password'};                                      # "
    $pubsecret      = $query{'terminal_id'};                                   # "
    $industrycode   = $query{'industrycode'};                                  # "
    $proc_type      = $query{'proc_type'};
    $clientid       = $query{'clientid'};
    $categorycode   = $query{'categorycode'};
    $agentbank      = $query{'agentbank'};
    $agentbank      = substr( $agentbank, 0, 6 );
    $agentchain     = $query{'agentchain'};
    $storenum       = $query{'storenum'};
    $terminalnum    = $query{'terminalnum'};
    $poscond        = $query{'poscond'};
    $clientname     = $query{'clientname'};
    $fedtaxid       = $query{'fedtaxid'};
    $dbanum         = $query{'dbanum'};
    $memberid       = $query{'memberid'};
    $memberguid     = $query{'memberguid'};
    $sellerid       = $query{'sellerid'};
    $storeid        = $query{'storeid'};
    $server         = $query{'server'};
    $rbspassword    = $query{'rbspassword'};
    $gsopaypassword = $query{'gsopaypassword'};
    $groupid        = $query{'groupid'};
    $batchgroup     = $reseller::global_features->get('default_batchgroup');

    $currency = $query{'currency'};
    $currency =~ tr/A-Z/a-z/;
    $currency =~ s/[^a-z]//g;
    $currency = substr( $currency, 0, 3 );
  }
  if ( $query{'processor'} eq "fdms" ) {
    $batchtime = '2';
  }

  if ( ( $query{'processor'} eq "gsopay" ) || ( $query{'processor'} eq "moneris" ) ) {
    $merchant_id =~ s/[^0-9A-Za-z\-\/]//g;
    $pubsecret =~ s/[^0-9A-Za-z\-\/]//g;
  } else {
    $merchant_id =~ s/[^0-9\/]//g;
    $pubsecret =~ s/[^0-9A-Za-z\/]//g;
  }

  if ( ( $query{'industrycode'} eq "retail" ) || ( $query{'dccfhrzn_industrycode'} eq "retail" ) || ( $query{'tsys_industrycode'} eq "retail" ) ) {
    $retailflag = "1";
  }

  $accounttype = $query{'accounttype'};
  $newcomment  = $query{'newcomment'};

  my $orderid = PlugNPay::Transaction::TransactionProcessor::generateOrderID();
  my ($today) = &miscutils::gendatetime_only();

  $query{'autosetup'} = "yes";

  my $reseller_prefix = substr( $data{'username'}, 0, 3 );
  if ( $reseller_prefix =~ /^($reseller::reseller_list)$/i ) {
    $reseller          = $reseller::reseller_hash{$reseller_prefix};
    $data{'reseller2'} = $reseller;
    $retailflag        = $reseller::retailflag{$reseller_prefix};
  } elsif ( substr( $data{'username'}, 0, 4 ) =~ /^($reseller::reseller_list)$/i ) {
    $reseller          = $reseller::reseller_hash{$reseller_prefix};
    $data{'reseller2'} = $reseller;
    $retailflag        = $reseller::retailflag{"substr($data{'username'},0,3)"};
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /wta/i ) {
    $reseller = "webtrans";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /epz/i ) {
    $reseller = "epenzio";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /frt/i ) {
    $reseller = "frontlin";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /ofx/i ) {
    $reseller   = "epayment";
    $retailflag = "1";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /cbs/i ) {
    $reseller   = "ofxcentb";
    $retailflag = "1";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /ipy/i ) {
    $reseller = "ipaymen2";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /nab/i ) {
    $reseller = "northame";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /bri/i ) {
    $reseller   = "epayment";
    $retailflag = "1";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /sss/i ) {
    $reseller = "sovran";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /drg/i ) {
    $reseller = "durango";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /eci/i ) {
    $reseller = "electro";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /ctc/i ) {
    $reseller = "commerce";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /itc/i ) {
    $reseller = "interna3";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /cbb/i ) {
    $reseller = "cblbanca";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /ncb/i ) {
    $reseller = "jncb";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /cdo/i ) {
    $reseller = "cynergyo";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /cyd/i ) {
    $reseller = "cynergy";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /pya/i ) {
    $reseller = "payameri";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /hms/i ) {
    $reseller = "payhms";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /tri/i ) {
    $reseller = "tri8inc";
  }

  if ( $reseller =~ /^(webtrans)/ ) {
    $data{'proc_type'} = "authonly";
    if ( $data{'processor'} eq "" ) {
      $data{'processor'} = "global";
    }
    $data{'reseller2'} = "webtrans";
  } elsif ( $reseller =~ /^(totalme2)/ ) {
    $email = "info\@totalmerchantservices.com";
  } elsif ( $reseller =~ /^(epayment)/ ) {
    $data{'proc_type'} = "authonly";
    if ( $data{'processor'} eq "" ) {
      $data{'processor'} = "global";
    }
    $data{'reseller2'} = "epayment";
  } elsif ( $reseller =~ /^(ofxcentb)/ ) {
    $data{'proc_type'} = "authonly";
    if ( $data{'processor'} eq "" ) {
      $data{'processor'} = "global";
    }
    $data{'reseller2'} = "ofxcentb";
  } elsif ( $reseller =~ /^(cardread)/ ) {
    $data{'proc_type'} = "authonly";
    if ( $data{'processor'} eq "" ) {
      $data{'processor'} = "visanet";
    }
    $data{'reseller2'} = "cardread";
    $retailflag = "1";
  } elsif ( $reseller =~ /quiksto1$/ ) {
    $retailflag    = "1";
    $bypassipcheck = "1";
  } elsif ( $reseller =~ /electro$/ ) {
    $fraudtrack = "1";
    $features{'sndemail'} = "merchant";
  } elsif ( $reseller =~ /^sovran$/ ) {
    $batchtime = "2";
  } elsif ( $reseller =~ /^vermont/ ) {
    $fraudtrack = "1";
  } elsif ( $reseller =~ /^lawpay$/ ) {
    $retailflag = "1";
    $query{'industrycode'} = 'retail';
  }

  ### WTF does this do ?  Possible Grab %feature as pulled out in security_check ?  ,  security_check only used for remote.

  $dbh = &miscutils::dbhconnect('pnpmisc');

  ####  This is for remote only.  Allows update of MID and TID if pnpusername is passed. and pnpusername exists and MID and TID are blank
  $sth_merchants = $dbh->prepare(
    q{
      SELECT username,reseller,merchant_id,pubsecret
      FROM customers
      WHERE username=?
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth_merchants->execute("$query{'pnpusername'}") or die "Can't execute: $DBI::errstr";
  my ( $db_test, $db_reseller, $db_merchant_id, $db_pubsecret ) = $sth_merchants->fetchrow;
  $sth_merchants->finish;

  if ( ( $db_test ne "" )
    && ( $reseller eq $db_reseller )
    && ( $db_merchant_id eq "" )
    && ( $db_pubsecret eq "" )
    && ( $client eq "remote" ) ) {
    $allow_update = 1;

    my %fields = ( "merchant_id", "$merchant_id", "pubsecret", "$terminal_id" );

    my $qstr = "UPDATE customer SET ";
    my ($qstr1);
    foreach my $key ( sort keys %fields ) {
      if ( $fields{$key} ne "" ) {
        if ( $qstr1 ne "" ) {
          $qstr1 .= ",$key=?";
        } else {
          $qstr1 = "$key=?";
        }
        $customer_data[ ++$#customer_data ] = "$customer_fields{$key}";
      }
    }
    $qstr .= $qstr1;
    $qstr .= " WHERE username=?";
    $sth = $dbh->prepare($qstr) or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr,%query" );
    $sth->execute( @customer_data, $query{'pnpusername'} ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr,%query" );
    $sth->finish;
    $dbh->disconnect;

    &update_ip( $reseller, $query{'pnpusername'} );

    $result_str = "FinalStatus=success\&username=$query{'pnpusername'}";
    print "$result_str\n";
    exit;
  }
  ####  End of F'ed up update code.

  ####Create username
  if ( $username eq "" ) {
    if ( $company ne "" ) {
      $_ = $company;
    } elsif ( $contact ne "" ) {
      $_ = $contact;
    } else {
      $_ = "noname";
    }
    s/[^0-9a-zA-Z]//g;
    $_ =~ tr/A-Z/a-z/;

  } else {
    $_ = $username;
  }
  $mn = substr( $_, 0, 10 );

  $i        = "";
  $username = "x";
  while (1) {
    $mn = $mn . $i;
    my $sth_merchants = $dbh->prepare(
      q{
        SELECT username
        FROM customers
        WHERE username=?
      }
      )
      or die "Can't do: $DBI::errstr";
    $sth_merchants->execute("$mn") or die "Can't execute: $DBI::errstr";
    ($username) = $sth_merchants->fetchrow;
    $sth_merchants->finish;

    if ( $username eq "" ) {
      last;
    }
    $mn = substr( $mn, 0, length($mn) - length($i) );
    $i++;
  }

  $query{'username'} = $mn;

  if ( $subacctflag == 1 ) {
    $subacct = $query{'username'};
    $query{'subacct'} = $subacct;
  }

  if ( $query{'paymentmethod'} =~ /check/i ) {
    $card_number = "$routingnum $accountnum";
  }

  $cardnumber = substr( $card_number, 0, 4 ) . '**' . substr( $card_number, length($card_number) - 2, 2 );

  if ( $reseller =~ /^($reseller::tech_list)$/ ) {
    $reseller2 = 'plugnpay';
  } else {
    $reseller2 = $reseller;
  }

  $sth_merchants = $dbh->prepare(
    q{
      SELECT limits,fraud_config,noreturns
      FROM customers
      WHERE username=?
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth_merchants->execute("$reseller2") or die "Can't execute: $DBI::errstr";
  my ( $limits, $fraud_config, $noreturns ) = $sth_merchants->fetchrow;
  $sth_merchants->finish;

  my $accountFeatures = new PlugNPay::Features( "$reseller2", 'general' );
  my $feature_string = $accountFeatures->getFeatureString();

  if ( ( $query{'username'} =~ /^ebb/ ) && ( $reseller2 =~ /^monkey/ ) ) {
    my $accountFeatures = new PlugNPay::Features( 'ebb4018', 'general' );
    $feature_string = $accountFeatures->getFeatureString();
  }

  if ( $limits ne "" ) {
    $query{'limits'} = $limits;
  }
  if ( $fraud_config ne "" ) {
    $query{'fraud_config'} = $fraud_config;
  }
  if ( $noreturns ne "" ) {
    $query{'noreturns'} = $noreturns;
  }
  if ( $feature_string ne "" ) {
    my @array = split( /\,/, $feature_string );
    foreach my $entry (@array) {
      my ( $name, $value ) = split( /\=/, $entry );
      $feature{$name} = $value;
    }
  }

  $features = "";
  if ( $feature{'inherit'} ne "" ) {
    my @noninheritable_features = ( 'inherit', 'risktrak', 'fileupload', 'uploadbatch', 'impchargebacks' );
    foreach my $key ( keys %feature ) {
      if ( $key =~ /^reseller\_/ ) {
        push( @noninheritable_features, $key );
      }
    }
    my @inherit = split( /\|/, $feature{'inherit'} );
    foreach my $var (@inherit) {
      $inherit{$var} = 1;
    }
    foreach my $feat (@noninheritable_features) {
      delete $feature{$feat};
    }
    %features = %feature;
  } else {
    $features{'transition'}   = "1";
    $features{'socketflag'}   = "1";
    $features{'admn_sec_req'} = "ip";
  }

  foreach my $key ( keys %features ) {
    $features .= "$key=$features{$key},";
  }

  ## Replicate Fraud Config Tables
  my $dbh_ft = &miscutils::dbhconnect('fraudtrack');
  my @tables = ( 'bin_fraud', 'country_fraud', 'email_fraud', 'ip_fraud' );
  foreach my $table (@tables) {
    my $sth = $dbh_ft->prepare(
      qq{
        DELETE FROM $table
        WHERE username=?
      }
      )
      or die "failed prepare1.";
    $sth->execute("$query{'username'}") or die "failed execute.";
    $sth->finish();

    my $db_query = "SELECT entry FROM $table WHERE username=?";
    my $sth2     = $dbh_ft->prepare(qq{$db_query}) or die "failed prepare";
    my $rv       = $sth2->execute("$reseller2") or die "failed execute";
    while ( my ($blocked_entry) = $sth2->fetchrow ) {
      my $sth = $dbh_ft->prepare(
        qq{
          INSERT INTO $table
          (username,entry)
          VALUES(?,?)
      }
        )
        or die "failed prepare.";
      $sth->execute( "$query{'username'}", "$blocked_entry" );
      $sth->finish;
    }
    $sth2->finish();
  }
  $dbh_ft->disconnect();

  ### copy cmin and ctran from the reseller fields
  ### to the merchant fields, buy or sell based on payallflag
  my ( $cmin, $ctran, $ctranmax, $cpertran ) = ( "0", "0", "0", "0" );
  my ($debugoutputbuysell);

  #  if ($reseller eq "michell")
  my $sth_getresellercoredata = $dbh->prepare(
    q{
        SELECT b_cmin, b_ctran, b_ctranmax,
               s_cmin, s_ctran, s_ctranmax,
               payallflag
        FROM salesforce
        WHERE username=?
      }
    )
    or die("Can't do: $DBI::errstr");
  $sth_getresellercoredata->execute("$reseller");
  my ( $b_cmin, $b_ctran, $b_ctranmax, $s_cmin, $s_ctran, $s_ctranmax, $payallflag ) = $sth_getresellercoredata->fetchrow;
  $sth_getresellercoredata->finish;
  if ( $payallflag eq "1" ) {
    $cmin               = $b_cmin;
    $ctran              = $b_ctran;
    $ctranmax           = $b_ctranmax;
    $debugoutputbuysell = "buy";
  } else {
    $cmin               = $s_cmin;
    $ctran              = $s_ctran;
    $ctranmax           = $s_ctranmax;
    $debugoutputbuysell = "sell";
  }

  if ( $ctranmax eq "" ) {
    $ctranmax = "0";
  } else {
    $cpertran = $ctran;
  }

  if ( ( $client eq "remote" ) || ( $reseller =~ /^(barbara)$/ ) || ( $ENV{'LOGIN'} eq "unplugged" ) ) {
    my @array = %query;
    &insert_merchant(@array);
  } else {

    $sth_merchants = $dbh->prepare(
      q{
        INSERT INTO customers
        (username,name,company,addr1,addr2,city,state,zip,country,tel,fax,email,techname,techtel,techemail,url,status,cards_allowed,bank,monthly,percent,pcttype,pertran,overtran,reseller,processor,proc_type,merchant_id,pubsecret,exp_date,card_number,merchemail,trans_date,accttype,subacct,features,agentcode,parentacct,retailflag,contact_date,limits,fraud_config,noreturns,emv_processor)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_merchants->execute(
      "$query{'username'}", "$contact",       "$company",   "$addr1",       "$addr2",       "$city",       "$state",      "$zip",
      "$country",           "$tel",           "$fax",       "$email",       "$techname",    "$techtel",    "$techemail",  "$url",
      "pending",            "$cards_allowed", "$busibnk",   "$cmin",        "$ctran",       "trans",       "$cpertran",   "$ctranmax",
      "$reseller2",         "$processor",     "$proc_type", "$merchant_id", "$terminal_id", "$exp_date",   "$cardnumber", "$merchemail",
      "$today",             "$accttype",      "$subacct",   "$features",    $agentcode,     "$masteracct", "$retailflag", "$today",
      "$limits",            "$fraud_config",  "$noreturns", "$processor"
      )
      or die "Can't execute: $DBI::errstr";
    $sth_merchants->finish;

    $sth_pnpsetup = $dbh->prepare(
      q{
        INSERT INTO pnpsetups
        (username,trans_date,submit_date,orderid,submit_status,easycart,fraudtrack,accounttype)
        VALUES (?,?,?,?,?,?,?,?)
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth_pnpsetup->execute( "$query{'username'}", "$today", "$today", "$orderid", "form filled out", "1", "$fraudtrack", "$accounttype" ) or die "Can't execute: $DBI::errstr";
    $sth_pnpsetup->finish;

    # insert report config for nisc merchants.
    if ( ( $reseller2 eq "paynisc" ) || ( $reseller2 eq "payntel" ) || ( $reseller2 eq "siipnisc" ) || ( $reseller2 eq "siiptel" ) || ( $reseller2 eq "elretail" ) || ( $reseller2 eq "teretail" ) ) {
      &insert_nisc_report( $query{'username'} );
    }

    if ( $fraudtrack == 1 ) {
      my $login = "$query{'username'}";
      my $loginClient = new PlugNPay::Authentication::Login( { login => $login } );
      $loginClient->setRealm('PNPADMINID');
      $loginClient->addDirectories( { directories => ['/admin/fraudtrack'] } );
    }

    $cardlength = length $card_number;
    if ( ( $card_number !~ /\*\*/ ) && ( $cardlength > 8 ) ) {
      ( $enccardnumber, $encryptedDataLen ) = &rsautils::rsa_encrypt_card( $card_number, '/home/p/pay1/pwfiles/keys/key' );
      $length = "$encryptedDataLen";

      if ( $reseller =~ /^($reseller::tech_list)$/ ) {
        $sth = $dbh->prepare(
          q/
            UPDATE customers
            SET enccardnumber=?,length=?
            WHERE username=?
          /
          )
          or die "Can't prepare: $DBI::errstr";
        $sth->execute( $enccardnumber, $encryptedDataLen, $query{'username'} ) or die "Can't execute: $DBI::errstr";
      } else {
        $sth = $dbh->prepare(
          q/
            UPDATE customers
            SET enccardnumber=?,length=?
            WHERE username=?
            AND reseller=?
          /
          )
          or die "Can't prepare: $DBI::errstr";
        $sth->execute( $enccardnumber, $encryptedDataLen, $query{'username'}, $reseller ) or die "Can't execute: $DBI::errstr";
      }

    } else {
      $enccardnumber = "";
      $length        = "0";

    }
    if ( $newcomment ne "" ) {
      $sth_comments = $dbh->prepare(
        q{
           INSERT INTO comments
           (username,orderid,message)
           VALUES (?,?,?)
        }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_comments->execute( "$query{'username'}", "$orderid", "$newcomment" ) or die "Can't execute: $DBI::errstr";
      $sth_comments->finish;
    }
  }

  $dbh->disconnect;

  if ( $reseller =~ /^($reseller::tech_list)$/ ) {
    $reseller2 = 'plugnpay';
  } else {
    $reseller2 = $reseller;
  }

  &update_ip( $reseller, $query{'username'}, $inherit{'ip'} );

  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setGatewayAccount('reseller');
  $emailObj->setFormat('text');
  $emailObj->setTo('applications@plugnpay.com');
  $emailObj->setFrom($email);
  $emailObj->setSubject("Subject: Plug and Pay - $reseller2 - Reseller App Notification");

  my $emailmessage = '';
  $emailmessage .= $tel . "\n";
  $emailmessage .= "\nForm Information:\n";
  $emailmessage .= "Contact Email: " . $merchemail . "\n";
  $emailmessage .= "Billing Email: " . $email . "\n";
  if ( $subacct ne "" ) {
    $emailmessage .= "Sub Acct:" . $subacct . "\n";
  }
  $emailmessage .= "Username:" . $query{'username'} . "\n";
  $emailmessage .= "Compay: " . $company . "\n";
  $emailmessage .= "Contact: " . $contact . "\n";
  $emailmessage .= "Address: " . $addr1 . "\n";
  $emailmessage .= "         " . $addr2 . "\n";
  $emailmessage .= "City: " . $city . "\n";
  $emailmessage .= "State: " . $state . "\n";
  $emailmessage .= "Zip: " . $zip . "\n";
  $emailmessage .= "Country: " . $country . "\n";
  $emailmessage .= "Tel: " . $tel . "\n";
  $emailmessage .= "FAX: " . $fax . "\n";
  $emailmessage .= "URL: " . $url . "\n";
  $emailmessage .= "\n\n";
  $emailmessage .= "Reseller: " . $reseller2 . "\n";
  $emailmessage .= "Processor: " . $processor . "\n";
  $emailmessage .= "Account type: " . $accounttype . "\n";
  $emailmessage .= "Industry code: " . $industrycode . "\n";

  if ( $processor =~ /^(visanet|visanetemv|planetpay)$/ ) {
    $emailmessage .= "BIN:$bin\n";
    $emailmessage .= "CATCODE:$categorycode\n";
    $emailmessage .= "AGTBNK:$agentbank\n";
    $emailmessage .= "AGTCHN:$agentchain\n";
    $emailmessage .= "STRNUM:$storenum\n";
    $emailmessage .= "TERMNUM:$terminalnum\n";
    $emailmessage .= "CUR:$currency\n";
    $emailmessage .= "MERCHBNK:$merchant_bank\n";
    $emailmessage .= "MERCHTYP:$merchant_type\n";
  } elsif ( $processor eq "paytechtampa" ) {
    $emailmessage .= "CLIENT_ID:$clientid\n";
    $emailmessage .= "SETTLEMENTBANK:$banknum\n";
  } elsif ( $processor =~ /^(global|maverick|cccc|ncb|fdmsintl)$/ ) {
    $emailmessage .= "SETTLEMENTBANK:$banknum\n";
  } elsif ( $processor eq "elavon" ) {
    $emailmessage .= "SETTLEMENTBANK:$bin\n";
  } elsif ( $processor eq "fifththird" ) {
    $emailmessage .= "SETTLEMENTBANK:$banknum\n";
    $emailmessage .= "CUR:$currency\n";
    $emailmessage .= "MERCHTYP:$merchant_type\n";
  } elsif ( $processor =~ /^(cccc|ncb)$/ ) {
    $emailmessage .= "POSCODE:$poscond\n";
  }
  if ( $processor =~ /^(cccc|ncb|fdmsintl)$/ ) {
    $emailmessage .= "SETTLEMENTBANK:$banknum\n";
  }
  if ( $processor eq "fdmsrc" ) {
    $emailmessage .= "CATCODE:$categorycode\n";
    $emailmessage .= "FEDTAXID:$fedtaxid\n";
  }
  if ( $processor eq "rbc" ) {
    $emailmessage .= "SERVER:$server\n";
    $emailmessage .= "CURRENCY:$currency\n";
  }

  $emailmessage .= "Comments: $newcomment\n";

  $emailObj->setContent($emailmessage);

  $emailObj->send();

  if ( ( $query{'autosetup'} eq "yes" ) && ( $query{'username'} ne "" ) ) {
    if ( $reseller2 eq "cyberaut" ) {
      $a = &setup("$query{'username'}");
    } elsif ( $query{'status'} =~ /^(live|debug|hold)$/ ) {
      $a = &setup( "$query{'username'}", 'nopartner', "$query{'status'}" );
    } else {
      $a = &setup("$query{'username'}");
    }
  }
  if ( $client eq "remote" ) {
    if ( $a ne "" ) {
      $result_str = "FinalStatus=success\&username=$query{'username'}\&$a";
    } else {
      $result_str = "FinalStatus=success\&username=$query{'username'}";
    }
    print "$result_str\n";
    exit;
  } else {
    &editstatus();
  }

  &insert_processor_info();
}

sub support_email {
  my ( $email, $cc_email, $message ) = @_;

  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setFormat('text');
  $emailObj->setGatewayAccount('reseller');
  $emailObj->setTo($email);
  $emailObj->setCC($cc_email);
  $emailObj->setFrom('reseller@plugnpay.com');
  $emailObj->setSubject('PlugnPay Support Message');
  $emailObj->setContent($message);
  $emailObj->send();
}

sub app_email {
  my (%merchdata) = @_;
  if ( $reseller =~ /^($reseller::tech_list)$/ ) {
    $reseller2 = 'plugnpay';
  } else {
    $reseller2 = $reseller;
  }

  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setFormat('text');
  $emailObj->setGatewayAccount('reseller');
  $emailObj->setTo('application@plugnpay.com');
  $emailObj->setFrom( $merchdata{'email'} );
  $emailObj->setSubject("Plug and Pay - $reseller2 - Batch App Notification");
  my $emailmessage = '';
  $emailmessage .= "\nForm Information:\n";
  $emailmessage .= "Email:" . $merchdata{'email'} . "\n";
  $emailmessage .= "Username:" . $merchdata{'username'} . "\n";
  $emailmessage .= "Compay: " . $merchdata{'company'} . "\n";
  $emailmessage .= "Contact: " . $merchdata{'contact'} . "\n";
  $emailmessage .= "Address: " . $merchdata{'addr1'} . "\n";
  $emailmessage .= "         " . $merchdata{'addr2'} . "\n";
  $emailmessage .= "City: " . $merchdata{'city'} . "\n";
  $emailmessage .= "State: " . $merchdata{'state'} . "\n";
  $emailmessage .= "Zip: " . $merchdata{'zip'} . "\n";
  $emailmessage .= "Country: " . $merchdata{'country'} . "\n";
  $emailmessage .= "Tel: " . $merchdata{'tel'} . "\n";
  $emailmessage .= "FAX: " . $merchdata{'fax'} . "\n";
  $emailmessage .= "Technical Contact Name: " . $merchdata{'techname'} . "\n";
  $emailmessage .= "Technical Contact Tel: " . $merchdata{'techtel'} . "\n";
  $emailmessage .= "Technical Contact Email: " . $merchdata{'techemail'} . "\n";
  $emailmessage .= "URL: " . $merchdata{'url'} . "\n";
  $emailmessage .= "\n\n";
  $emailmessage .= "Reseller: " . $reseller2 . "\n";
  if ( $processor eq "visanet" ) {
    $emailmessage .= "BIN:$merchdata{'bin'}\n";
    $emailmessage .= "CATCODE:$merchdata{'categorycode'}\n";
    $emailmessage .= "AGTBNK:$merchdata{'agentbank'}\n";
    $emailmessage .= "AGTCHN:$merchdata{'agentchain'}\n";
    $emailmessage .= "STRNUM:$merchdata{'storenum'}\n";
    $emailmessage .= "TERMNUM:$merchdata{'terminalnum'}\n";
    $emailmessage .= "CUR:$merchdata{'currency'}\n";
  }
  if ( $processor eq "paytechtampa" ) {
    $emailmessage .= "CLIENT_ID:$clientid\n";
    $emailmessage .= "SETTLEMENTBANK:$banknum\n";
  }
  if ( ( $processor eq "elavon" ) || ( $processor eq "global" ) || ( $processor eq "maverick" ) ) {
    $emailmessage .= "SETTLEMENTBANK:$banknum\n";
  }

  $emailObj->setContent($emailmessage);

  $emailObj->send();
}

sub search {
  $status        = $query{'status'};
  $submit_status = $query{'submit_status'};
  $pnptype       = $query{'pnptype'};
  $shopcart      = $query{'shopcart'};
  $ach           = $query{'ach'};
  $hosting       = $query{'hosting'};
  $autobatch     = $query{'autobatch'};
  $chkautobatch  = $query{'chkautobatch'};
  $download      = $query{'download'};
  $affiliate     = $query{'affiliate'};
  $membership    = $query{'membership'};
  $processor     = $query{'processor'};

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title> Reseller Administration</title>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"https://pay1.plugnpay.com/css/green.css\">\n";

  print "<META HTTP-EQUIV='Pragma' CONTENT='no-cache'>\n";
  print "<META HTTP-EQUIV='Cache-Control' CONTENT='no-cache'>\n";

  print "<style text=\"text/css\">\n";
  print "<\!--\n";
  print "TABLE \{width: 100%;\}\n";
  print "HR \{width: 100%;\}\n";
  print "TH \{text-align: left;\}\n";

  print "-->\n";
  print "</style>\n";

  print "</head>\n";

  print "<body bgcolor=\"#ffffff\">\n";
  print "<table border=1 cellspacing=1 cellpadding=1>\n";
  print "  <tr bgcolor=\"#f3f9e8\">\n";
  print "    <th align=left>Merchant</th>";
  print "    <th align=left>Processor</th>";
  print "    <th align=left>Acct/Type</th>";
  print "    <th align=left>ShopCart</th>";
  print "    <th align=left>Download</th>";
  print "    <th align=left>Affiliate</th>";
  print "    <th align=left>Membership></th>";
  print "    <th align=left>Status</th>";
  print "    <th align=left colspan=4>Comments</th>";
  print "  </tr>\n";

  $dbh = &miscutils::dbhconnect('pnpmisc');

  my @placeholder;
  my $srchstr = "SELECT c.username,c.name,c.company,c.status,c.processor,p.merchacct,p.pnptype,p.hosting,p.shopcart,";
  $srchstr .= "p.download,p.affiliate,p.membership,p.submit_date,p.submit_status,p.sent_date,";
  $srchstr .= "p.tracknum,p.return_date";
  $srchstr .= " FROM customers c,pnpsetups p";
  $srchstr .= " WHERE c.username=p.username";

  if ( $status ne "" ) {
    $srchstr .= " AND c.status=?";
    push( @placeholder, "$status" );
  }

  if ( $submit_status ne "" ) {
    $srchstr .= " AND p.submit_status=?";
    push( @placeholder, "$submit_status" );
  }

  if ( $pnptype ne "" ) {
    $srchstr .= " AND p.pnptype=?";
    push( @placeholder, "$pnptype" );
  }

  if ( $hosting ne "" ) {
    $srchstr .= " AND p.hosting=?";
    push( @placeholder, "$hosting" );
  }

  if ( $autobatch ne "" ) {
    $srchstr .= " AND p.autobatch=?";
    push( @placeholder, "$autobatch" );
  }

  if ( $shopcart ne "" ) {
    $srchstr .= " AND p.shopcart=?";
    push( @placeholder, "$shopcart" );
  }

  if ( $membership ne "" ) {
    $srchstr .= " AND p.membership=?";
    push( @placeholder, "$membership" );
  }

  if ( $download ne "" ) {
    $srchstr .= " AND p.download=?";
    push( @placeholder, "$download" );
  }

  if ( $processor ne "" ) {
    $srchstr .= " AND c.processor=?";
    push( @placeholder, "$processor" );
  }

  #if ($srchacctcode ne "") {
  #  $srchstr .= " AND LOWER(acct_code) LIKE LOWER(?)";
  #  push(@placeholder, "\%srchacctcode\%$");
  #}

  if ( $reseller !~ /^($reseller::tech_list)$/ ) {
    $srchstr .= " AND c.reseller=?";
    push( @placeholder, "$reseller" );
  }

  $srchstr .= "ORDER BY c.username";

  $sth = $dbh->prepare(qq{$srchstr}) or die "Can't do: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  while (
    my ( $username, $name, $company, $status, $processor, $merchacct, $pnptype, $hosting, $shopcart, $download, $affiliate, $membership, $submit_date, $submit_status, $sent_date, $tracknum, $return_date )
    = $sth->fetchrow ) {
    &genpage();
  }
  $sth->finish;

  $dbh->disconnect;

  print "</table>";

  print "<form action=\"$reseller::path_cgi\" method=\"post\">\n";
  print "<input type=submit name=\"submit\" value=\"Home Page\">\n";
  print "</form>";

  print "</body>";
  print "</html>";
}

sub genpage {
  $submit_date = &miscutils::datetostr($submit_date);
  $sent_date   = &miscutils::datetostr($sent_date);
  $return_date = &miscutils::datetostr($return_date);

  print "  <tr>\n";
  print "    <th valign=top align=left>";
  print "<form action=\"$reseller::path_cgi\" method=\"post\">\n";
  print "<input type=hidden name=\"function\" value=\"editstatus\">";
  print "<input type=hidden name=\"username\" value=\"$username\">";
  print "<input type=submit name=\"submit\" value=\"$username\">";
  print "<br><b>$company</b></th>";
  print "    <td valign=top nowrap>$processor</td>\n";
  print "    <td valign=top nowrap>";

  print "$pnptype";


  print "</td>\n";

  print "    <td valign=top nowrap>";
  if ( $hosting eq "" ) {
    print "No Hosting";
  } else {
    print "$hosting";
  }
  print "</td>\n";

  print "    <td valign=top nowrap>";
  if ( $ach eq "" ) {
    print "No ACH";
  } else {
    print "$ach";
  }
  print "</td>\n";

  print "    <td valign=top nowrap>";
  if ( $shopcart eq "" ) {
    print "No ShopCart";
  } else {
    print "$shopcart";
  }
  print "</td>";

  print "    <td valign=top nowrap>";
  if ( $download eq "" ) {
    print "None";
  } else {
    print "$download";
  }
  print "</td>\n";

  print "    <td valign=top nowrap>\n";
  if ( $affiliate eq "" ) {
    print "None";
  } else {
    print "$affiliate";
  }
  print "</td>\n";

  print "    <td valign=top nowrap>";
  if ( $membership eq "" ) {
    print "None";
  } else {
    print "$membership";
  }
  print "</td>\n";

  print "    <td align=left valign=top>";

  print "$status";

  print "</td>\n";

  print "  <td valign=top>";
  print "<select name=\"history\">";
  $sth_comments = $dbh->prepare(
    q{
      SELECT orderid,message
      FROM comments
      WHERE username=?
      ORDER BY orderid
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth_comments->execute("$username") or die "Can't execute: $DBI::errstr";
  while ( my ( $orderid, $message ) = $sth_comments->fetchrow ) {
    $message = substr( $message, 0, 40 );
    print "<option value=\"$orderid\">$message</option>\n";
  }
  $sth_comments->finish;
  print "</select></td>\n";

  print "</form>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=10><hr width=400></td>\n";
  print "  </tr>\n";
}

sub updatepaid {
  @listval = $data->param('listval');

  if ( $reseller =~ /^($reseller::tech_list)$/ ) {
    ($today) = &miscutils::gendatetime_only();

    $dbh = &miscutils::dbhconnect('pnpmisc');

    $sth_report = $dbh->prepare(
      q{
        UPDATE billingreport
        SET paidamount=?, paiddate=?
        WHERE orderid=?
        AND amount=?
        AND descr=?
      }
      )
      or die "Can't prepare: $DBI::errstr";

    $sth_status = $dbh->prepare(
      q{
        UPDATE billingstatus
        SET paidamount=?, paiddate=?
        WHERE orderid=?
        AND amount=?
        AND descr=?
        AND result='success'
      }
      )
      or die "Can't prepare: $DBI::errstr";

    foreach $var (@listval) {
      $orderid    = $query{"orderid$var"};
      $amount     = $query{"amount$var"};
      $paidamount = $query{"paidamount$var"};
      $descr      = $query{"descr$var"};

      print "$orderid $amount $paidamount<br>\n";

      $sth_report->execute( "$paidamount", "$today", "$orderid", "$amount", "$descr" ) or die "Can't execute: $DBI::errstr";

      $sth_status->execute( "$paidamount", "$today", "$orderid", "$amount", "$descr" ) or die "Can't execute: $DBI::errstr";
    }
    $sth_report->finish;
    $sth_status->finish;

    $dbh->disconnect;
  }

  &main("login.html");
}

sub viewtransactions {
  $username  = $query{'username'};
  $startdate = $query{'startdate'};
  $enddate   = $query{'enddate'};

  my $starttimea = &miscutils::strtotime($startdate);
  my $endtimea   = &miscutils::strtotime($enddate);
  my $elapse     = $endtimea - $starttimea;

  if ( $elapse > ( 93 * 24 * 3600 ) ) {
    my $message = "Sorry, but no more than 3 months may be queried at one time.  Please use the back button and change your selected date range.";
    &response_page($message);
    exit;
  }

  if ( $reseller =~ /^($reseller::tech_list)$/ ) {
    $dbh = &miscutils::dbhconnect('pnpmisc');
    $sth = $dbh->prepare(
      q{
        SELECT c.username
        FROM pnpsetups p, customers c
        WHERE c.username=?
        AND c.username=p.username
        AND c.reseller=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute( "$username", "$reseller" ) or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername eq "" ) {
      $dbh->disconnect;
      return "failure";
    }
    $dbh->disconnect;
  }

  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Commission Report</title>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"stylesheet.css\">\n";
  print "<META HTTP-EQUIV='Pragma' CONTENT='no-cache'>\n";
  print "<META HTTP-EQUIV='Cache-Control' CONTENT='no-cache'>\n";
  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";

  print "<div align=center>\n";
  print "<table border=0 cellspacing=0 cellpadding=1>\n";
  print "<tr class=\"across\"><th align=left> &nbsp; Date</th><th> &nbsp; OrderID</th><th> &nbsp; Name</th><th> &nbsp; Amount</th>\n";

  my $starttranstime = &miscutils::strtotime($startdate);
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $starttranstime - ( 3600 * 24 * 7 ) );
  $starttransdate = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
  $starttime = $startdate . "000000";

  my @dateArray = ();
  my ($qmarks);
  my ( $qmarks2, $dateArray ) = &miscutils::dateIn( $starttransdate, $enddate );

  $dbh = &miscutils::dbhconnect('pnpdata');

  $sth = $dbh->prepare(
    qq{
      SELECT orderid,trans_date,card_name,amount
      FROM trans_log
      WHERE trans_date IN ($qmarks)
      AND username=?
      AND trans_time>=?
      AND finalstatus=?
      AND operation=?
      ORDER BY trans_time,orderid
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth->execute( @$dateArray, $username, $starttime, 'success', 'auth' ) or die "Can't execute: $DBI::errstr";
  while ( my ( $orderid, $trans_date, $name, $amount ) = $sth->fetchrow ) {
    $datestr = sprintf( "%02d/%02d/%04d", substr( $trans_date, 4, 2 ), substr( $trans_date, 6, 2 ), substr( $trans_date, 0, 4 ) );
    $amount = substr( $amount, 4 );
    $amount = sprintf( "%.2f", $amount );
    print "<tr><th align=left class=\"leftside\"> &nbsp; $datestr &nbsp; </th>";
    print "<td> &nbsp; $orderid &nbsp; </td>";
    print "<td> &nbsp; $name &nbsp; </td>";
    print "<td class=\"tdright\">\$$amount &nbsp; </td>\n";
  }
  $sth->finish;

  $dbh->disconnect;

  print "</table>\n";
  print "</body>\n";
  print "</html>\n";
}

sub cron_batch {
  my (@merchantArray) = @_;

  $reseller::reseller_list =
    "wta|epz|nat|adc|frt|ust|ofx|cbs|ipy|nab|bri|sss|drg|crd|eci|ctc|itc|cbb|ncb|cdo|cyd|pya|aar|hom|jhew|jhrh|jhrr|jhdr|jhce|jhjd|jhst|jhtt|jhtn|jhmk|jhsu|jhlb|jgok|jgtn|jgtx|jhat|tri|mtr";
  %reseller::retailflag = (
    'ofx',  '1', 'cbs',  '1', 'bri',  '1', 'crd',  '1', 'jhew', '1', 'jhrh', '1', 'jhrr', '1', 'jhdr', '1', 'jhce', '1', 'jhjd', '1',
    'jhst', '1', 'jhtt', '1', 'jhtn', '1', 'jhmk', '1', 'jhsu', '1', 'jhlb', '1', 'jgok', '1', 'jgtn', '1', 'jgtx', '1', 'jhat', '1'
  );
  %reseller::reseller_hash = (
    'wta',  'webtrans', 'epz',  'epenzio',  'frt',  'frontlin', 'ofx',  'epayment', 'cbs',  'ofxcentb', 'ipy',  'ipayment2', 'nab',  'northame', 'bri',  'epayment',
    'sss',  'cardmt',   'drg',  'durango',  'crd',  'cardread', 'eci',  'electro',  'ctc',  'commerce', 'itc',  'interna3',  'cbb',  'cblbanca', 'ncb',  'jncb',
    'cdo',  'cynergyo', 'cyd',  'cynergy',  'pya',  'payameri', 'hms',  'payhms',   'tri',  'tri8inc',  'aar',  'aaronsin',  'hom',  'homesmrt', 'jhew', 'jhtsjudy',
    'jhrh', 'jhtsjudy', 'jhrr', 'jhtsjudy', 'jhdr', 'jhtsjudy', 'jhce', 'jhtsjudy', 'jhjd', 'jhtsjudy', 'jhst', 'jhtsjudy',  'jhtt', 'jhtsjudy', 'jhtn', 'jhtsjudy',
    'jhmk', 'jhtsjudy', 'jhsu', 'jhtsjudy', 'jhlb', 'jhtsjudy', 'jgok', 'jhtsjudy', 'jgtn', 'jhtsjudy', 'jgtx', 'jhtsjudy',  'jhat', 'jhtsjudy', 'mtr',  'metrowes'
  );

  #$testmode = "yes";
  local ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime(time);
  $today = sprintf( "%04d%02d%02d%", $year + 1900, $mon + 1, $mday );

  foreach $merchantdata (@merchantArray) {
    chop;
    %merchdata = @$merchantdata;
    my @array = %merchdata;
    &insert_merchant(@array);
    if ( $testmode eq "yes" ) {
      print "$i:$merchdata{'username'}, Action:$action, AutoSetup:$merchdata{'autosetup'}, NewMerch:$newmerchantflag\n";
      if ( ( $merchdata{'merchemail'} ne $db_email ) || ( $merchdata{'resendemail'} =~ /yes/i ) ) {
        print "New Email:$merchdata{'merchemail'}, Old Email:$db_email Sending Setup Email Only\n";
      }
    } else {
      if ( ( $merchdata{'autosetup'} eq "yes" ) && ( $newmerchantflag eq "yes" ) && ( $merchdata{'username'} ne "" ) ) {
        if ( $merchdata{'partner'} eq "" ) {
          $partner = "AAAA";
        } else {
          $partner = $merchdata{'partner'};
        }
        $a = &setup( "$merchdata{'username'}", "$partner", 'AAAA', "$merchdata{'publisherpassword'}" );

      }
      if ( ( $newmerchantflag eq "yes" ) && ( $merchdata{'agentcode'} ne "rt" ) ) {
        &app_email(@array);
      } else {
        if ( ( $merchdata{'merchemail'} ne $db_email ) || ( $merchdata{'resendemail'} =~ /yes/i ) ) {
          $a = &setup( "$merchdata{'username'}", "emailonly" );
        }
      }
    }
  }
}

sub import_data {
  local ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime(time);
  $today = sprintf( "%04d%02d%02d", $year + 1900, $mon + 1, $mday );
  $time = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec );
  my @merchantArray = ();

  $filename = $data->param('filename');

  my ( @fields, %data );
  while (<$filename>) {
    if ( substr( $_, -1 ) eq "\n" ) {
      chop;
    }
    $linetest = $_;
    $linetest =~ s/^W//g;
    if ( length($linetest) < 1 ) {
      next;
    }

    my @data = split('\t');
    if ( ( $reseller eq "ecoquest" && ( $data[0] eq "acctno" ) && $parseflag != 1 ) ) {
      @fields = (
        'merchant', 'username',    'dummy',       'company', 'addr1', 'city',  'state', 'zip',   'dummy', 'dummy',
        'dummy',    'dummy',       'dummy',       'dummy',   'dummy', 'dummy', 'dummy', 'dummy', 'dummy', 'dummy',
        'dummy',    'merchant_id', 'terminal_id', 'tel',     'fax',   'email', 'dummy'
      );
      $parseflag    = 1;
      $ecoquestflag = 1;
      next;
    } else {
      if ( substr( $data[0], 0, 1 ) eq "\!" ) {
        $parseflag = 1;
        (@fields) = (@data);
        $fields[0] = substr( $data[0], 1 );
        next;
      }
    }
    if ( $parseflag == 1 ) {
      %merchdata = ();
      if ( $ecoquestflag == 1 ) {
        unshift( @data, 'merchant' );
      }
      $i = 0;
      foreach $var (@fields) {
        $var =~ tr/A-Z/a-z/;
        $var =~ s/\W//g;
        $merchdata{$var} = $data[$i];
        $merchdata{$var} =~ s/[^a-zA-Z0-9_\.\/\@:\-\ ]//g;

        $i++;
      }
      if ( $ecoquestflag == 1 ) {
        $merchdata{'merchant'}  = "merchant";
        $merchdata{'username'}  = "ecq" . $merchdata{'username'};
        $merchdata{'autosetup'} = "yes";
      }

      # Data Filters
      $merchdata{'partner'} =~ s/[^a-zA-Z0-9]//g;
      $merchdata{'routingnum'} =~ s/[^0-9]//g;
      $merchdata{'accountnum'} =~ s/[^0-9]//g;
      $merchdata{'card_number'} =~ s/[^0-9]//g;
      $merchdata{'tel'} =~ s/[^0-9]//g;
      $merchdata{'tel'} =~ s/^[0-1]//;
      if ( ( $merchdata{'email'} ne "" ) && ( $merchdata{'merchemail'} eq "" ) ) {
        $merchdata{'merchemail'} = $merchdata{'email'};
      }
      $merchdata{'username'} =~ s/[^a-zA-Z0-9]//g;
      $merchdata{'username'} =~ tr/A-Z/a-z/;
      $merchdata{'username'} = substr( $merchdata{'username'}, 0, 11 );
      $merchdata{'accttype'} = $merchdata{'paymentmethod'};
      $merchdata{'accttype'} =~ tr/A-Z/a-z/;
      $merchdata{'autosetup'} =~ tr/A-Z/a-z/;
      if ( $merchdata{'accttype'} =~ /check/i ) {
        $merchdata{'accttype'} = "checking";
      }
      if ( $merchdata{'currency'} eq "" ) {
        $merchdata{'currency'} = "usd";
      }

      $merchdata{'currency'} =~ tr/A-Z/a-z/;
      $merchdata{'currency'} =~ s/[^a-z]//g;
      $merchdata{'currency'} = substr( $merchdata{'currency'}, 0, 3 );

      # Expiration Date Filter
      $card_exp = $merchdata{'card-exp'};
      $card_exp =~ s/[^0-9]//g;
      $length = length($card_exp);
      $year = substr( $card_exp, -2 );
      if ( $length == 4 ) {
        $merchdata{'card-exp'} = substr( $card_exp, 0, 2 ) . "/" . $year;
      } elsif ( ( $length == 3 ) || ( $length == 5 ) ) {
        $merchdata{'card-exp'} = "0" . substr( $card_exp, 0, 1 ) . "/" . $year;
      }

      # chop fields so they fit in the DB
      my %lengthhash = (
        'COUNTRY',  '19', 'COMPANY',     '39', 'ROUTINGNUM',  '39', 'CITY',        '39', 'ACCOUNTNUM',  '39', 'MERCHANT_ID', '39', 'FAX',           '39',  'PAYMENTMETHOD', '13',
        'USERNAME', '11', 'STATE',       '19', 'CARD_NUMBER', '18', 'TEL',         '39', 'TERMINAL_ID', '39', 'EMAIL',       '79', 'AUTOSETUP',     '3',   'EXP_DATE',      '6',
        'CONTACT',  '39', 'ADDR1',       '39', 'ADDR2',       '39', 'BUSIBNK',     '39', 'URL',         '59', 'ZIP',         '11', '!MERCHANT',     '100', 'country',       '19',
        'company',  '39', 'routingnum',  '39', 'city',        '39', 'accountnum',  '39', 'merchant_id', '39', 'fax',         '39', 'paymentmethod', '13',  'username',      '11',
        'state',    '19', 'card_number', '18', 'tel',         '39', 'terminal_id', '39', 'email',       '79', 'autosetup',   '3',  'exp_date',      '6',   'contact',       '39',
        'addr1',    '39', 'addr2',       '39', 'busibnk',     '39', 'url',         '59', 'zip',         '11', '!merchant',   '100'
      );

      foreach $name ( keys %merchdata ) {
        if ( ( defined $lengthhash{$name} ) && ( length $merchdata{$name} > $lengthhash{$name} ) ) {
          $merchdata{$name} = substr( $merchdata{$name}, 0, $lengthhash{$name} );
        }
      }

      my @array = %merchdata;
      if ( ( $merchdata{'agentcode'} eq "rt" ) || ( $reseller::global_features->get('uploadbatch') == 1 ) ) {
        my @array = %merchdata;
        $error = &input_check(@array);
        if ( $error > 0 ) {
          $data_error{ $merchdata{'username'} } = $errvar;
          next;
        }
      } elsif ( ( substr( $merchdata{'username'}, 0, 3 ) !~ /^($reseller::reseller_list)/i ) && ( substr( $merchdata{'username'}, 0, 4 ) !~ /^($reseller::reseller_list)/i ) ) {
        $username_error{ $merchdata{'username'} } = 1;
        next;
      } else {
        my @array = %merchdata;
        $error = &input_check(@array);
        if ( $error > 0 ) {
          $data_error{ $merchdata{'username'} } = $errvar;
          next;
        }
      }
      if ( $fields[0] =~ /merchant/i ) {
        push( @merchantArray, \@array );
      }
    }
  }
  &cron_batch(@merchantArray);
  if ( $parseflag == 1 ) {
    my $message = "File Has Been Uploaded and Imported into Database";
    my $i       = 1;
    foreach $key ( keys %username_error ) {
      if ( $i == 1 ) {
        $message .= "<br>There was a problem with the following username(s).\n";
        $message .= "They were missing the proper username prefix and were not imported.<br>\n";
      }
      $message .= "$i: $key<br>";
      $i++;
    }
    $i = 1;
    foreach $key ( keys %data_error ) {
      if ( $i == 1 ) {
        $message .= "<br>There was a problem with the following username(s).\n";
        $message .= "They were missing the following mandatory information.<br>\n";
      }
      $message .= "$i: $key: $data_error{$key}<br>";
      $i++;
    }
    $message = "<p align=left>$message</p>";
    &response_page($message);
  } else {
    my $message = "Sorry Improper File Format";
    $message = "<p align=left>$message</p>";
    &response_page($message);
  }
}

sub response_page {
  my ($message) = @_;
  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title>Response Page</title>\n";
  print "<style type=\"text/css\">\n";
  print "<!--\n";
  print "th { font-family: $fontface; font-size: 75%; color: $goodcolor }\n";
  print "td { font-family: $fontface; font-size: 75%; color: $goodcolor }\n";
  print ".leftside { font-family: $fontface; font-size: 75%; color: goodcolor }\n";
  print ".badcolor { color: $badcolor }\n";
  print ".goodcolor { color: $goodcolor }\n";
  print ".larger { font-size: 100%; text-align: right; font-weight: bold }\n";
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
  print "<table border=0 cellspacing=0 cellpadding=1 width=500>\n";
  print "<tr><td align=center colspan=4><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corporate Logo\"></td></tr>\n";
  print "<tr><td align=center colspan=4 class=\"larger\" bgcolor=\"#000000\"><font color=\"#ffffff\">Reseller Administration Area</font></td></tr>\n";
  print "<tr><td>&nbsp;</td><td>&nbsp;</td><td colspan=2>&nbsp;</td></tr>\n";
  print "<tr><td colspan=4>$message</td></tr>\n";

  print "</table>\n";
  print "</body>\n";
  print "</html>\n";

}

sub insert_merchant {
  my (%data) = @_;
  my ( $test, $autobatch, $easycart, $chkautobatch );
  $newmerchantflag = "";

  my $orderid = PlugNPay::Transaction::TransactionProcessor::generateOrderID();
  my ($today) = &miscutils::gendatetime_only();

  if ( $data{'autobatch'} ne "" ) {
    $autobatch = $data{'autobatch'};
  }
  $chkautobatch = $data{'chkautobatch'};
  $autobatch    = $data{'autobatch'};

  local ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime(time);
  $today = sprintf( "%04d%02d%02d", $year + 1900, $mon + 1, $mday );

  my $reseller_prefix = substr( $data{'username'}, 0, 3 );
  if ( $reseller_prefix =~ /^($reseller::reseller_list)$/i ) {
    $reseller          = $reseller::reseller_hash{$reseller_prefix};
    $data{'reseller2'} = $reseller;
    $retailflag        = $reseller::retailflag{$reseller_prefix};

    #print "AA:$reseller, DR:$data{'reseller2'}, RF:$retailflag\n";
  } elsif ( substr( $data{'username'}, 0, 4 ) =~ /^($reseller::reseller_list)$/i ) {
    $reseller = $reseller::reseller_hash{ substr( $data{'username'}, 0, 4 ) };
    $data{'reseller2'} = $reseller;
    $retailflag = $reseller::retailflag{"substr($data{'username'},0,4)"};
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /epz/i ) {
    $reseller = "epenzio";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /nat/i ) {
    $reseller = "nationa3";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /adc/i ) {
    $reseller = "advancec";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /frt/i ) {
    $reseller = "frontlin";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /^(ofx)/i ) {
    $reseller = "officetr";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /^(cbs)/i ) {
    $reseller = "ofxcentb";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /^(ipy)/i ) {
    $reseller = "ipaymen2";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /^(nab)/i ) {
    $reseller = "northame";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /^(bri)/i ) {
    $reseller = "officetr";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /^(crd)/i ) {
    $reseller = "cardread";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /^(mtr)/i ) {
    $reseller = "metrowes";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /^(sss)/i ) {
    $reseller = "sovran";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /^(drg)/i ) {
    $reseller = "durango";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /^(eci)/i ) {
    $reseller = "electro";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /ctc/i ) {
    $reseller = "commerce";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /itc/i ) {
    $reseller = "interna3";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /cbb/i ) {
    $reseller = "cblbanca";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /ncb/i ) {
    $reseller = "jncb";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /cdo/i ) {
    $reseller = "cynergyo";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /cyd/i ) {
    $reseller = "cynergy";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /pya/i ) {
    $reseller = "payameri";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /hms/i ) {
    $reseller = "payhms";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /pp1/i ) {
    $reseller = "prontop1";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /ppa/i ) {
    $reseller = "prontopa";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /tri/i ) {
    $reseller = "tri8inc";
  } elsif ( substr( $data{'username'}, 0, 3 ) =~ /aar/i ) {
    $reseller = "aaronsin";
  } elsif ( $data{'agentcode'} eq "rt" ) {
    $reseller = "resruby";
  } elsif ( $data{'agentcode'} eq 'jh' ) {
    $reseller = 'jhtsjudy';
  }

  #print "RL:$reseller::reseller_list, RP:$reseller_prefix, UN:$data{'username'}, AA:$reseller, DR:$data{'reseller2'}, RF:$retailflag\n";

  if ( $reseller =~ /^(epenzio)/ ) {
    $data{'proc_type'} = "authonly";
    if ( $data{'processor'} eq "" ) {
      $data{'processor'} = "buypass";
    }
    $data{'reseller2'}         = "epenzio";
    $data{'monthly'}           = "10.00";
    $data{'percent'}           = "0";
    $data{'setupfee'}          = "0";
    $data{'monthlycommission'} = "0.40";
    $autobatch                 = "0";
  } elsif ( $reseller =~ /^(ecoquest)/ ) {
    $data{'proc_type'} = "authonly";
    if ( $data{'processor'} eq "" ) {
      $data{'processor'} = "fdms";
    }
    $data{'reseller2'}         = "ecoquest";
    $data{'monthly'}           = "10.00";
    $data{'percent'}           = "0";
    $data{'setupfee'}          = "0";
    $data{'monthlycommission'} = "0";
    $data{'merchemail'}        = $data{'email'};
    $data{'techemail'}         = "support\@ecoquest.com";
    $data{'url'}               = "http://www.ecoquest.com/";
  } elsif ( $reseller =~ /^(epayment)/ ) {
    $data{'proc_type'} = "authonly";
    if ( $data{'processor'} eq "" ) {
      $data{'processor'} = "global";
    }
    $data{'reseller2'} = "epayment";
    $autobatch = "0";
  } elsif ( $reseller =~ /^(officetr)/ ) {
    $data{'proc_type'} = "authonly";
    if ( $data{'processor'} eq "" ) {
      $data{'processor'} = "global";
    }
    $data{'reseller2'}  = "officetr";
    $data{'retailflag'} = "1";
    $autobatch          = "0";
  } elsif ( $reseller =~ /^(ofxcentb)/ ) {
    $data{'proc_type'} = "authonly";
    if ( $data{'processor'} eq "" ) {
      $data{'processor'} = "global";
    }
    $data{'reseller2'}  = "ofxcentb";
    $autobatch          = "0";
    $data{'retailflag'} = "1";
  } elsif ( $reseller =~ /^(ipaymen2)/ ) {
    $autobatch         = "0";
    $data{'proc_type'} = "authonly";
    $data{'reseller2'} = "ipaymen2";
  } elsif ( $reseller =~ /^(northame)/ ) {
    $data{'proc_type'} = "authonly";
    $data{'reseller2'} = "northame";
    $data{'monthly'}   = "5.00";
    $data{'percent'}   = "0";
    $data{'setupfee'}  = "0";
    $data{'overtran'}  = "250";
    $data{'pertran'}   = "0.08";
  } elsif ( $reseller =~ /^(cardread)/ ) {
    $data{'processor'}    = "visanet";
    $data{'proc_type'}    = "authonly";
    $data{'reseller2'}    = "cardread";
    $data{'monthly'}      = "5.00";
    $data{'percent'}      = "0.05";
    $data{'retailflag'}   = "1";
    $data{'agentbank'}    = "000000";
    $data{'agentchain'}   = "000000";
    $data{'storenum'}     = "0001";
    $data{'categorycode'} = "4225";
    $data{'bin'}          = "439883";
    $data{'terminalnum'}  = "0001";
    $data{'pcttype'}      = "trans";
  } elsif ( $reseller =~ /^(durango)/ ) {
    $autobatch         = "0";
    $data{'proc_type'} = "authonly";
    $data{'reseller2'} = "durango";
  } elsif ( $reseller =~ /^(electro)/ ) {
    $fraudtrack = "1";
  } elsif ( $reseller =~ /^(cblbanca)/ ) {
    $autobatch = "0";
  } elsif ( $reseller =~ /^(cynergyo)/ ) {
    $data{'proc_type'} = "authonly";
    $data{'monthly'}   = "5.00";
    $data{'percent'}   = ".05";
  } elsif ( $reseller =~ /^(cynergy)/ ) {
    $data{'proc_type'} = "authonly";
    $data{'monthly'}   = "5.00";
    $data{'percent'}   = ".05";
  } elsif ( $reseller =~ /^(paynisc)/ ) {
    $data{'cards_allowed'} = "VISA|MSTR";
  } elsif ( $reseller =~ /^(payhms)/ ) {
    $data{'proc_type'} = "authonly";
    $data{'monthly'}   = "10.00";
    $data{'percent'}   = ".05";
  } elsif ( $reseller =~ /^(sovran)$/ ) {
    $batchtime = "2";
  } elsif ( $reseller =~ /^(prontop1)$/ ) {
    $autobatch = "0";
  } elsif ( $reseller =~ /^(prontopa)$/ ) {
    $autobatch = "0";
  } elsif ( $reseller =~ /^vermont/ ) {
    $fraudtrack = "1";
  } elsif ( $reseller =~ /^(resruby)/ ) {
    $data{'processor'}    = "fifththird";
    $data{'reseller2'}    = "resruby";
    $data{'categorycode'} = "5812";
    $data{'banknum'}      = "4445";
    $data{'pcttype'}      = "trans";
    $data{'proc_type'}    = "authonly";
  } elsif ( $reseller =~ /^(jhtsjudy)/ ) {
    $data{'processor'}    = "fdms";
    $data{'reseller2'}    = "jhtsjudy";
    $data{'proc_type'}    = "authonly";
    $data{'chkprocessor'} = "telecheckftf";
    $data{'tempflag'}     = "1";
  }

  if ( $data{'processor'} eq "fdms" ) {
    $batchtime = '2';
  }

  $easycart = 1;

  if ( $data{'username'} ne "" ) {

    my $dbh = &miscutils::dbhconnect('pnpmisc');
    $dbh->do('BEGIN') or die "Can't do: $DBI::errstr";
    my $sth_merchants = $dbh->prepare(
      q{
         SELECT username,merchemail
         FROM customers
         WHERE username=?
      }
      )
      or die "Can't do: $DBI::errstr";
    $sth_merchants->execute("$data{'username'}") or die "Can't execute: $DBI::errstr";
    ( $test, $db_email ) = $sth_merchants->fetchrow;
    $sth_merchants->finish;

    if ( $testmode eq "yes" ) {
      if ( $test ne "" ) {
        $action = "Updated";
      } else {
        $newmerchantflag = "yes";
        $action          = "Inserted";
      }
      return;
    }

    $sth_merchants = $dbh->prepare(
      q{
        SELECT limits,fraud_config,noreturns
        FROM customers
        WHERE username=?
      }
      )
      or die "Can't do: $DBI::errstr";
    $sth_merchants->execute("$reseller") or die "Can't execute: $DBI::errstr";
    my ( $limits, $fraud_config, $noreturns ) = $sth_merchants->fetchrow;
    $sth_merchants->finish;

    my $accountFeatures = new PlugNPay::Features( "$reseller", 'general' );
    my $features = $accountFeatures->getFeatureString();

    if ( $limits ne "" ) {
      $data{'limits'} = $limits;
    }
    if ( $fraud_config ne "" ) {
      $data{'fraud_config'} = $fraud_config;
    }
    if ( $noreturns ne "" ) {
      $data{'noreturns'} = $noreturns;
    }

    my %feature = ();
    my %inherit = ();

    if ( $features ne "" ) {
      my @array = split( /\,/, $features );
      foreach my $entry (@array) {
        my ( $name, $value ) = split( /\=/, $entry );
        $feature{$name} = $value;
      }
    }

    if ( $feature{'inherit'} ne "" ) {
      my @noninheritable_features = ( 'inherit', 'risktrak', 'fileupload', 'uploadbatch', 'impchargebacks' );
      my @inherit = split( /\|/, $feature{'inherit'} );
      foreach my $var (@inherit) {
        $inherit{$var} = 1;
      }
      foreach my $feat (@noninheritable_features) {
        delete $feature{$feat};
      }
    }

    $features = "";
    foreach my $key ( keys %feature ) {
      $features .= "$key=$feature{$key},";
    }
    chop $features;

    if ( $features ne "" ) {
      $data{'features'} = $features;
    }

    if ( ( $test ne "" ) && ( $allow_update ne "no" ) ) {

      $update_cnt++;

      if ( $data{'paymentmethod'} =~ /check/i ) {
        $card_number = "$data{'routingnum'} $data{'accountnum'}";
        $card_number = substr( $card_number, 0, 4 ) . '**' . substr( $card_number, length($card_number) - 2, 2 );
      } elsif ( $data{'card_number'} ne "" ) {
        $card_number = $data{'card_number'};
        $card_number = substr( $card_number, 0, 4 ) . '**' . substr( $card_number, length($card_number) - 2, 2 );
      }

      $uname = $data{'username'};

      $sth_merch = $dbh->prepare(
        q{
          UPDATE customers
          SET username=? ,name=? ,company=? ,addr1=? ,addr2=? ,city=? ,state=? ,zip=? ,country=? ,tel=? ,fax=? ,email=? ,techname=? ,techtel=? ,techemail=? ,url=? ,cards_allowed=? ,bank=? ,monthly=? ,percent=? ,reseller=? ,processor=? ,proc_type=? ,merchant_id=? ,pubsecret=? ,exp_date=? ,card_number=?, merchemail=?, setupfee=?, accttype=?, currency=?, monthlycommission=?, pertran=?, overtran=?, contact_date=?, agentcode=?, pcttype=?
          WHERE username=?
        }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_merch->execute(
        "$data{'username'}",    "$data{'contact'}",           "$data{'company'}",   "$data{'addr1'}",      "$data{'addr2'}",         "$data{'city'}",
        "$data{'state'}",       "$data{'zip'}",               "$data{'country'}",   "$data{'tel'}",        "$data{'fax'}",           "$data{'email'}",
        "$data{'techname'}",    "$data{'techtel'}",           "$data{'techemail'}", "$data{'url'}",        "$data{'cards_allowed'}", "$data{'busibnk'}",
        "$data{'monthly'}",     "$data{'percent'}",           "$data{'reseller2'}", "$data{'processor'}",  "$data{'proc_type'}",     "$data{'merchant_id'}",
        "$data{'terminal_id'}", "$data{'exp_date'}",          "$card_number",       "$data{'merchemail'}", "$data{'setupfee'}",      "$data{'accttype'}",
        "$data{'currency'}",    "$data{'monthlycommission'}", "$data{'pertran'}",   "$data{'overtran'}",   "$today",                 "$data{'agentcode'}",
        "$data{'pcttype'}",     "$uname"
        )
        or die "Can't execute: $DBI::errstr";

      if ( $data{'paymentmethod'} =~ /check/i ) {
        $card_number = "$data{'routingnum'} $data{'accountnum'}";
      } elsif ( $data{'card_number'} ne "" ) {
        $card_number = $data{'card_number'};
      }

      $cardlength = length $card_number;

      if ( ( $card_number !~ /\*\*/ ) && ( $cardlength > 8 ) ) {
        ( $enccardnumber, $encryptedDataLen ) = &rsautils::rsa_encrypt_card( $card_number, '/home/p/pay1/pwfiles/keys/key' );
        $card_number = substr( $card_number, 0, 4 ) . '**' . substr( $card_number, length($card_number) - 2, 2 );
        $length      = "$encryptedDataLen";
        $reseller    = $data{'reseller2'};
        if ( $reseller =~ /^($reseller::tech_list)$/ ) {
          $sth = $dbh->prepare(
            q/
             UPDATE customers
             SET enccardnumber=?,length=?
             WHERE username=?
            /
            )
            or die "Can't prepare: $DBI::errstr";
          $sth->execute( "$enccardnumber", "$encryptedDataLen", "$uname" ) or die "Can't execute: $DBI::errstr";
        } else {
          $sth = $dbh->prepare(
            q/
             UPDATE customers
             SET enccardnumber=?,length=?
             WHERE username=?
             AND reseller=?
            /
            )
            or die "Can't prepare: $DBI::errstr";
          $sth->execute( "$enccardnumber", "$encryptedDataLen", "$uname", "$reseller" ) or die "Can't execute: $DBI::errstr";
        }
      } else {
        $enccardnumber = "";
        $length        = "0";
      }
      $action          = "Data Updated:";
      $newmerchantflag = "no";
    } else {
      $new_cnt++;
      $newmerchantflag = "yes";
      if ( $data{'paymentmethod'} =~ /check/i ) {
        $card_number = "$data{'routingnum'} $data{'accountnum'}";
        $card_number = substr( $card_number, 0, 4 ) . '**' . substr( $card_number, length($card_number) - 2, 2 );
      } elsif ( $data{'card_number'} ne "" ) {
        $card_number = $data{'card_number'};
        $card_number = substr( $card_number, 0, 4 ) . '**' . substr( $card_number, length($card_number) - 2, 2 );
      }

      $sth_merchants = $dbh->prepare(
        q{
          INSERT INTO customers
          (username,password,name,company,addr1,addr2,city,state,zip,country,
             tel,fax,email,techname,techtel,techemail,url,host,status,cards_allowed,
             bank,monthly,percent,reseller,processor,proc_type,
             merchant_id,pubsecret,exp_date,card_number,trans_date,merchemail,
             setupfee,accttype,startdate,currency,monthlycommission,pertran,overtran,
             contact_date,retailflag,limits,fraud_config,noreturns,features,agentcode,pcttype,chkprocessor,bypassipcheck,emv_processor)
          VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_merchants->execute(
        "$data{'username'}",          "$data{'password'}",      "$data{'contact'}",     "$data{'company'}",     "$data{'addr1'}",      "$data{'addr2'}",
        "$data{'city'}",              "$data{'state'}",         "$data{'zip'}",         "$data{'country'}",     "$data{'tel'}",        "$data{'fax'}",
        "$data{'email'}",             "$data{'techname'}",      "$data{'techtel'}",     "$data{'techemail'}",   "$data{'url'}",        "$data{'host'}",
        "$data{'status'}",            "$data{'cards_allowed'}", "$data{'busibnk'}",     "$data{'monthly'}",     "$data{'percent'}",    "$data{'reseller2'}",
        "$data{'processor'}",         "$data{'proc_type'}",     "$data{'merchant_id'}", "$data{'terminal_id'}", "$data{'exp_date'}",   "$card_number",
        "$today",                     "$data{'merchemail'}",    "$data{'setupfee'}",    "$data{'accttype'}",    "$today",              "$data{'currency'}",
        "$data{'monthlycommission'}", "$data{'pertran'}",       "$data{'overtran'}",    "$today",               "$data{'retailflag'}", "$data{'limits'}",
        "$data{'fraud_config'}",      "$data{'noreturns'}",     "$data{'features'}",    "$data{'agentcode'}",   "$data{'pcttype'}",    "$data{'chkprocessor'}",
        "$data{'bypassipcheck'}",     "$data{'processor'}"
        )
        or die "Can't execute: $DBI::errstr";

      $sth_pnpsetup = $dbh->prepare(
        q{
          INSERT INTO pnpsetups
          (username,trans_date,submit_date,orderid,submit_status,pnptype,easycart,fraudtrack,accounttype)
          VALUES (?,?,?,?,?,?,?,?,?)
        }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_pnpsetup->execute( "$data{'username'}", "$today", "$today", "$orderid", "form filled out", "Core", "$easycart", "$fraudtrack", "$data{'accounttype'}" ) or die "Can't execute: $DBI::errstr";
      $action = "Data Inserted";
    }

    if ( $data{'reseller2'} =~ /^(paynisc|payntel|siipnisc|siiptel|elretail|teretail)$/ ) {
      &insert_nisc_report( $data{'username'} );
    }

    #Modify Security IP Table
    &update_ip( $data{'reseller2'}, $data{'username'}, $inherit{'ip'} );

    if ( $data{'chkprocessor'} eq "telecheckftf" ) {
      my $table = $data{'chkprocessor'};
      my ($test);
      my $sth = $dbh->prepare(
        qq{
          SELECT username
          FROM $table
          WHERE username=?
        }
        )
        or die "Can't do: $DBI::errstr";
      $sth->execute("$data{'username'}") or die "Can't execute: $DBI::errstr";
      ($test) = $sth->fetchrow;
      $sth->finish;

      if ( $test ne "" ) {
        my $sth_proc = $dbh->prepare(
          qq{
            UPDATE $table
            SET merchantnum=?
            WHERE username=?
          }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_proc->execute( "$data{'chkmid'}", "$data{'username'}" ) or die "Can't execute: $DBI::errstr";
      } else {
        my $sth_proc = $dbh->prepare(
          qq{
            INSERT INTO $table
            (username,merchantnum)
            VALUES (?,?)
          }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_proc->execute( "$data{'username'}", "$data{'chkmid'}" ) or die "Can't execute: $DBI::errstr";
      }
    }

    my ($test);
    if ( $data{'processor'} =~ /^(paytechtampa|visanet|global|fifthird|planetpay|cccc|ncb|fdms)$/ ) {
      my $table = $data{'processor'};
      my $sth   = $dbh->prepare(
        qq{
          SELECT username
          FROM $table
          WHERE username=?
        }
        )
        or die "Can't do: $DBI::errstr";
      $sth->execute("$data{'username'}") or die "Can't execute: $DBI::errstr";
      ($test) = $sth->fetchrow;
      $sth->finish;
    }

    if ( $data{'processor'} eq "paytechtampa" ) {
      if ( $data{'reseller2'} eq "epenzio" ) {
        @parray = ( "093", "1701" );
      }

      if ( ( $test ne "" ) && ( @parray > 0 ) ) {
        $sth_proc = $dbh->prepare(
          qq{
            UPDATE paytechtampa
            SET banknum=?, clientid=?
            WHERE username=?
          }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_proc->execute( @parray, "$data{'username'}" ) or die "Can't execute: $DBI::errstr";
      } elsif ( @parray > 0 ) {
        $sth_proc = $dbh->prepare(
          q{
            INSERT INTO paytechtampa
            (banknum,clientid,username)
            VALUES (?,?,?)
        }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_proc->execute( @parray, "$data{'username'}" ) or die "Can't execute: $DBI::errstr";
      }
    } elsif ( $data{'processor'} eq "visanet" ) {
      if ( ( $test ne "" ) ) {
        $sth_proc = $dbh->prepare(
          q{
            UPDATE visanet
            SET agentbank=?,agentchain=?,storenum=?,categorycode=?,terminalnum=?,bin=?,vnumber=?,industrycode=?
            WHERE username=?
          }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_proc->execute( "$data{'agentbank'}", "$data{'agentchain'}", "$data{'storenum'}", "$data{'categorycode'}", "$data{'terminalnum'}", "$data{'bin'}", "$data{'vnumber'}", "$data{'industrycode'}",
          "$data{'username'}" )
          or die "Can't execute: $DBI::errstr";
      } else {
        $sth_proc = $dbh->prepare(
          q{
            INSERT INTO visanet
            (agentbank,agentchain,storenum,categorycode,terminalnum,bin,vnumber,username,industrycode)
            VALUES (?,?,?,?,?,?,?,?,?)
          }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_proc->execute( "$data{'agentbank'}", "$data{'agentchain'}", "$data{'storenum'}", "$data{'categorycode'}", "$data{'terminalnum'}", "$data{'bin'}", "$data{'vnumber'}", "$data{'username'}",
          "$data{'industrycode'}" )
          or die "Can't execute: $DBI::errstr";
      }
    } elsif ( $data{'processor'} eq "global" ) {
      if ( $data{'reseller2'} eq "epayment" ) {
        if ( $data{'bankid'} eq "" ) {
          $data{'bankid'} = "067600";
        }
      } elsif ( $data{'reseller2'} eq "northame" ) {
        if ( $data{'bankid'} eq "" ) {
          $data{'bankid'} = "025900";
        }
      }
      if ( ( $test ne "" ) ) {
        $sth_proc = $dbh->prepare(
          q{
            UPDATE global
            SET bankid=?
            WHERE username=?
          }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_proc->execute( "$data{'bankid'}", "$data{'username'}" ) or die "Can't execute: $DBI::errstr";
      } else {
        $sth_proc = $dbh->prepare(
          q{
            INSERT INTO global
            (bankid,username)
            VALUES (?,?)
          }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_proc->execute( "$data{'bankid'}", "$data{'username'}" ) or die "Can't execute: $DBI::errstr";
      }
    } elsif ( $data{'processor'} eq "planetpay" ) {
      if ( ( $test ne "" ) ) {
        $sth_proc = $dbh->prepare(
          q{
            UPDATE planetpay
            SET agentbank=?,agentchain=?,storenum=?,categorycode=?,terminalnum=?,bin=?,vnumber=?,industrycode=?
            WHERE username=?
          }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_proc->execute( "$data{'agentbank'}", "$data{'agentchain'}", "$data{'storenum'}", "$data{'categorycode'}", "$data{'terminalnum'}", "$data{'bin'}", "$data{'vnumber'}", "$data{'industrycode'}",
          "$data{'username'}" )
          or die "Can't execute: $DBI::errstr";
      } else {
        $sth_proc = $dbh->prepare(
          q{
            INSERT INTO planetpay
            (agentbank,agentchain,storenum,categorycode,terminalnum,bin,vnumber,username,industrycode)
            VALUES (?,?,?,?,?,?,?,?,?)
          }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_proc->execute( "$data{'agentbank'}", "$data{'agentchain'}", "$data{'storenum'}", "$data{'categorycode'}", "$data{'terminalnum'}", "$data{'bin'}", "$data{'vnumber'}", "$data{'username'}",
          "$data{'industrycode'}" )
          or die "Can't execute: $DBI::errstr";
      }
      if ( $data{'merchant_bank'} =~ /^tsys$/ ) {
        $sth_proc = $dbh->prepare(
          q{
            UPDATE planetpay
            SET ipaddress=?,port=?
            WHERE username=?
          }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_proc->execute( "10.120.12.24", "1022", "$data{'username'}" ) or die "Can't execute: $DBI::errstr";
      }
    } elsif ( $data{'processor'} =~ /^(cccc|ncb)$/ ) {
      my $table = $data{'processor'};
      if ( ( $test ne "" ) ) {
        $sth_proc = $dbh->prepare(
          q{
            UPDATE $table
            SET bankid=?,categorycode=?,poscond=?
            WHERE username=?
          }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_proc->execute( "$data{'banknum'}", "$data{'categorycode'}", "$data{'poscond'}", "$data{'username'}" ) or die "Can't execute: $DBI::errstr";
      } else {
        $sth_proc = $dbh->prepare(
          qq{
            INSERT INTO $table
            (bankid,categorycode,poscond)
            VALUEs (?,?,?)
          }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_proc->execute( "$data{'banknum'}", "$data{'categorycode'}", "$data{'poscond'}" ) or die "Can't execute: $DBI::errstr";
      }
    } elsif ( $data{'processor'} =~ /^(fifththird|fdmsintl)$/ ) {
      my $table = $data{'processor'};
      if ( ( $test ne "" ) ) {
        $sth_proc = $dbh->prepare(
          qq{
            UPDATE $table
            SET bankid=?,categorycode=?
            WHERE username=?
          }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_proc->execute( "$data{'banknum'}", "$data{'categorycode'}", "$data{'username'}" ) or die "Can't execute: $DBI::errstr";
      } else {
        $sth_proc = $dbh->prepare(
          qq{
            INSERT INTO $table
            (bankid,categorycode,username)
            VALUES (?,?,?)
          }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth_proc->execute( "$data{'banknum'}", "$data{'categorycode'}", "$data{'username'}" ) or die "Can't execute: $DBI::errstr";
      }
    } elsif ( $data{'processor'} eq "fdms" ) {
      if ( $test ne "" ) {
        $sth = $dbh->prepare(
          q{
            UPDATE fdms
            SET batchtime=?,industrycode=?
            WHERE username=?
          }
          )
          or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
        $sth->execute( $data{'batchtime'}, $data{'industrycode'}, $data{'username'} ) or die "Can't execute: $DBI::errstr";
      } else {
        $sth = $dbh->prepare(
          q{
            INSERT INTO fdms
            (username,batchtime,industrycode)
            VALUES (?,?,?)
          }
          )
          or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
        $sth->execute( "$data{'username'}", "$data{'batchtime'}", "$data{'industrycode'}" ) or die "Can't execute: $DBI::errstr";
      }
    } elsif ( $processor eq "fdmsrc" ) {
      if ( $test ne "" ) {
        $sth = $dbh->prepare(
          q{
            UPDATE fdmsrc
            SET industrycode=?,categorycode=?,fedtaxid=?,vattaxid=?,chargedescr=?,groupid=?
            WHERE username=?
          }
          )
          or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
        $sth->execute( $data{'industrycode'}, $data{'categorycode'}, $data{'fedtaxid'}, $data{'vattaxid'}, $data{'chargedescr'}, $data{'groupid'}, $data{'username'} ) or die "Can't execute: $DBI::errstr";
      } else {
        $sth = $dbh->prepare(
          q{
            INSERT INTO fdmsrc
            (username,industrycode,categorycode,fedtaxid,vattaxid,chargedescr,groupid)
            VALUES (?,?,?,?,?,?,?)
          }
          )
          or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
        $sth->execute( $data{'username'}, $data{'industrycode'}, $data{'categorycode'}, $data{'fedtaxid'}, $data{'vattaxid'}, $data{'chargedescr'}, $data{'groupid'} ) or die "Can't execute: $DBI::errstr";
      }
    }

    if ( $data{'paymentmethod'} =~ /check/i ) {
      $card_number = "$data{'routingnum'} $data{'accountnum'}";
    } else {
      $card_number = $data{'card_number'};
    }
    $cardlength = length $card_number;
    if ( ( $card_number !~ /\*\*/ ) && ( $cardlength > 8 ) ) {
      ( $enccardnumber, $encryptedDataLen ) = &rsautils::rsa_encrypt_card( $card_number, '/home/p/pay1/pwfiles/keys/key' );
      $card_number = substr( $card_number, 0, 4 ) . '**' . substr( $card_number, length($card_number) - 2, 2 );
      $length      = "$encryptedDataLen";
      $reseller    = $data{'reseller2'};
      if ( $reseller =~ /^($reseller::tech_list)$/ ) {
        $sth = $dbh->prepare(
          qq{
            UPDATE customers
            SET enccardnumber=?,length=?
            WHERE username=?
          }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth->execute( $enccardnumber, $encryptedDataLen, "$data{'username'}" ) or die "Can't execute: $DBI::errstr";
      } else {
        $sth = $dbh->prepare(
          qq{
            UPDATE customers
            SET enccardnumber=?,length=?
            WHERE username=?
            AND reseller=?
          }
          )
          or die "Can't prepare: $DBI::errstr";
        $sth->execute( $enccardnumber, $encryptedDataLen, "$data{'username'}", "$reseller" ) or die "Can't execute: $DBI::errstr";
      }
    } else {
      $enccardnumber = "";
      $length        = "0";
    }

    if ( $autobatch ne "" ) {
      $sth_merchants = $dbh->prepare(
        q{
          UPDATE pnpsetups
          SET autobatch=?
          WHERE username=?
        }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_merchants->execute( "$autobatch", "$data{'username'}" ) or die "Can't execute: $DBI::errstr";
    }

    if ( $chkautobatch ne "" ) {
      $sth_merchants = $dbh->prepare(
        q{
          UPDATE pnpsetups
          SET chkautobatch=?
          WHERE username=?
        }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_merchants->execute( "$chkautobatch", "$data{'username'}" ) or die "Can't execute: $DBI::errstr";
    }

    if ( $data{'newcomment'} ne "" ) {
      $sth_comments = $dbh->prepare(
        q{
          INSERT INTO comments
          (username,orderid,message)
          VALUES (?,?,?)
        }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_comments->execute( "$data{'username'}", "$orderid", "$data{'newcomment'}" ) or die "Can't execute: $DBI::errstr";
    }

    if ( ( $data{'username'} ne "" ) && ( $data{'password'} ne "" ) && ( $data{'autosetup'} ne "yes" ) ) {
      my $login = new PlugNPay::Authentication::Login( { login => $data{'username'} } );
      $login->setRealm('pnpadminid');
      my $loginInfo = {
        account             => $data{'username'},
        password            => $data{'password'},
        passwordIsTemporary => $data{'tempflag'} == 1 ? 1 : 0,
        securityLevel       => 0
      };

      my $result = $login->createLogin($loginInfo);

      # commit if we were able to create the login
      if ($result) {
        $dbh->do('COMMIT') or die "Can't do: $DBI::errstr";
      } else {
        $dbh->do('ROLLBACK') or die "Can't do: $DBI::errstr";
      }

      if ( $data{'remotepwd'} ne "" ) {
        $loginInfo->{'password'}      = $data{'remotepwd'};
        $loginInfo->{'securityLevel'} = 14;

        $login->setRealm("REMOTECLIENT");
        $login->createLogin($loginInfo);
      }
    } else {
      $dbh->do('COMMIT') or die "Can't do: $DBI::errstr";
    }

    # login can only be updated after it exists!
    if ( $fraudtrack == 1 ) {
      $sth_merchants = $dbh->prepare(
        q{
          UPDATE pnpsetups
          SET fraudtrack=?
          WHERE username=?
        }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth_merchants->execute( "$fraudtrack", "$data{'username'}" ) or die "Can't execute: $DBI::errstr";

      my $login = "$data{'username'}";
      my $loginClient = new PlugNPay::Authentication::Login( { login => $login } );
      $loginClient->setRealm('PNPADMINID');
      $loginClient->addDirectories( { directories => ['/admin/fraudtrack'] } );
    }

    $dbh->disconnect;
  }
}

sub sort_hash {
  my $x     = shift;
  my %array = %$x;
  sort { $array{$a} cmp $array{$b}; } keys %array;
}

sub input_check {
  my (%query) = @_;

  $errvar = "";
  $error  = "";
  @check  = ();
  @check1 = ();

  foreach $key ( keys %query ) {
    $color{$key} = 'goodcolor';
  }
  my $cardbin = substr( $query{'card_number'}, 0, 6 );
  if ( $cardbin =~ /^(4)/ ) {
    $cardtype = "Visa";
  } elsif ( $cardbin =~ /^(51|52|53|54|55)/ ) {
    $cardtype = "Mastercard";
  } elsif ( $cardbin =~ /^(37|34)/ ) {
    $cardtype = "Amex";
  } elsif ( $cardbin =~ /^(30|36|38[0-8])/ ) {
    $cardtype = "Diners";
  } elsif ( $cardbin =~ /^(389)/ ) {
    $cardtype = "Cartblanche";
  } elsif ( $cardbin =~ /^(6011)/ ) {
    $cardtype = "Discover";
  } elsif ( $cardbin =~ /^(3528[0-9][0-9])/ ) {
    $cardtype = "JCB";
  } elsif ( $cardbin =~ /^(1800|2131)/ ) {
    $cardtype = "JAL";
  } elsif ( $cardbin =~ /^(7)/ ) {
    $cardtype = "MYAR";
  }

  @check = @required_fields;

  if ( $reseller eq "ecoquest" ) {
    @check = ( @check, 'addr1', 'city', 'state' );
  } else {
    @check = ( @check, 'contact', 'addr1', 'city', 'state' );
  }

  $errhdr = "MissingValues,";
  foreach $var (@check) {
    $val = $query{$var};
    $val =~ s/[^a-zA-Z0-9]//g;
    my $tst = length($val);
    if ( $tst < 1 ) {
      $error = 1;
      $color{$var} = 'badcolor';
      $errvar .= "$var,";
    }
  }
  @check1 = ( @check1, 'zip', 'tel' );
  foreach $var (@check1) {
    $val = $query{$var};
    $val =~ s/[^0-9]//g;
    if ( length($val) < 1 ) {
      $error = 1;
      $color{$var} = 'badcolor';
      $errvar .= "$var, ";
    }
  }

  if ( $errvar ne "" ) {
    $errvar = $errhdr . $errvar;
  }

  if ( $query{'contact'} ne "" ) {
    my @name = split( /\s/, $query{'contact'} );
    if ( $#name < 1 ) {
      $error = 1;
      $color{'contact'} = "badcolor";
      $errvar .= ":InvalidContactFormat,$query{'contact'}";
    }
  } else {
    $error = 1;
    $color{'contact'} = 'badcolor';
    $errvar .= ":NoContactName,$query{'contact'}";
  }

  my $position = index( $query{'email'}, "\@" );
  my $position1 = rindex( $query{'email'}, "\." );
  my $elength = length( $query{'email'} );

  if ( ( $position < 1 )
    || ( $position1 < $position )
    || ( $position1 >= $elength - 2 )
    || ( $elength < 5 )
    || ( $position > $elength - 5 ) ) {
    $error          = 1;
    $color{'email'} = 'badcolor';
    $errvar         = $errvar .= ":InvalidEmail,$query{'email'}";
  }

  if ( $query{'paymentmethod'} =~ /check/i ) {
    my $ABAtest     = $query{'routingnum'};
    my $mod10test   = &modulus10($ABAtest);
    my $routenumlen = length( $query{'routingnum'} );
    if ( ( length( $query{'routingnum'} ) != 9 ) || ( $mod10test eq "FAIL" ) ) {
      $error = 1;
      $color{'routingnum'} = 'badcolor';
      $errvar .= ":InvalidRoutingnum,$query{'routingnum'}";
    }
  } elsif ( ( $query{'card_number'} !~ /\*\*/ ) && ( $query{'card_number'} ne "" ) ) {
    my $CCtest = $query{'card_number'};
    $CCtest =~ s/[^0-9]//g;
    my $luhntest = &miscutils::luhn10($CCtest);
    if ( $luhntest eq "failure" ) {
      $error = 1;
      $color{'card_number'} = 'badcolor';
      $errvar .= ":InvalidCardnumber,$CCtest";
    }
  }

  if ( $query{'processor'} eq "visanet" ) {
    foreach $var (@visanet_required) {
      if ( length( $query{$var} ) < 1 ) {
        $error = 1;
        $color{$var} = 'badcolor';
        $errvar .= ":Missing Visanet,$var";
      }
    }
  }

  # confirm email address
  if ( $query{'merchemail'} ne $query{'merchemail2'} ) {
    $error_string .= "Merchant Email Addresses Do Not Match. <br>";
    $error                = 1;
    $color{'merchemail'}  = 'badcolor';
    $color{'merchemail2'} = 'badcolor';
    $errvar .= ":MerchantEmailDoesNotMatch,$query{'merchemail'}";
  }
  if ( $query{'email'} ne $query{'email2'} ) {
    $error_string .= "Billing Email Addresses Do Not Match. <br>";
    $error           = 1;
    $color{'email'}  = 'badcolor';
    $color{'email2'} = 'badcolor';
    $errvar .= ":BillingEmailDoesNotMatch,$query{'email'}";
  }

  return $error;
}

sub luhn10 {

  # Allowed Card Lengths
  my $cardbin = substr( $query{'card_number'}, 0, 6 );
  if ( $cardbin =~ /^(4)/ ) {
    $cardtype = "Visa";
  } elsif ( $cardbin =~ /^(51|52|53|54|55)/ ) {
    $cardtype = "Mastercard";
  } elsif ( $cardbin =~ /^(37|34)/ ) {
    $cardtype = "Amex";
  } elsif ( $cardbin =~ /^(30|36|38[0-8])/ ) {
    $cardtype = "Diners";
  } elsif ( $cardbin =~ /^(389)/ ) {
    $cardtype = "Cartblanche";
  } elsif ( $cardbin =~ /^(6011)/ ) {
    $cardtype = "Discover";
  } elsif ( $cardbin =~ /^(3528[0-9][0-9])/ ) {
    $cardtype = "JCB";
  } elsif ( $cardbin =~ /^(1800|2131)/ ) {
    $cardtype = "JAL";
  } elsif ( $cardbin =~ /^(7)/ ) {
    $cardtype = "MYAR";
  }
  my ($CCtest) = @_;
  my $len = length($CCtest);
  my @digits = split( '', $CCtest );
  my ( $a, $b, $c, $temp, $j, $k, $sum, $check, $luhntest );
  for ( $k = 0 ; $k < $len ; $k++ ) {
    $j = $len - 1 - $k;
    if ( ( $j - 1 ) >= 0 ) {
      $a = $digits[ $j - 1 ] * 2;
    } else {
      $a = 0;
    }
    if ( length($a) > 1 ) {
      ( $b, $c ) = split( '', $a );
      $temp = $b + $c;
    } else {
      $temp = $a;
    }
    $sum = $sum + $digits[$j] + $temp;
    $k++;
  }
  $check = substr( $sum, length($sum) - 1 );
  if ( $check eq "0" ) {
    $luhntest = "PASS";
  } else {
    $luhntest = "FAIL";
  }
  return ($luhntest);
}

sub modulus10 {    # used to test check routing numbers
  my ($ABAtest) = @_;
  my @digits = split( '', $ABAtest );
  my ($modtest);
  my $sum = $digits[0] * 3 + $digits[1] * 7 + $digits[2] * 1 + $digits[3] * 3 + $digits[4] * 7 + $digits[5] * 1 + $digits[6] * 3 + $digits[7] * 7;
  my $check = 10 - ( $sum % 10 );
  $check = substr( $check, -1 );
  my $checkdig = substr( $ABAtest, -1 );

  if ( $check eq $checkdig ) {
    $modtest = "PASS";
  } else {
    $modtest = "FAIL";
  }
  return ($modtest);
}

sub fix_epenzio {
  my ($username) = @_;
  my $dbh_fix = &miscutils::dbhconnect('pnpmisc');
  $sth_fix = $dbh_fix->prepare(
    q{
      UPDATE pnpsetups
      SET pnptype=?
      WHERE username=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth_fix->execute( "Core", "$username" ) or die "Can't execute: $DBI::errstr";
  $sth_fix->finish;

  $dbh_fix->disconnect;
}

sub read_epenzio {
  my ($username) = @_;
  my $dbh_fix = &miscutils::dbhconnect('pnpmisc');
  $sth_r = $dbh_fix->prepare(
    q{
      SELECT username
      FROM pnpsetups
      WHERE username=?
      ORDER BY username
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth_r->execute("$username") or die "Can't execute: $DBI::errstr";
  while ( my ($uname) = $sth_r->fetchrow ) {
    print "UN:$uname:<br>\n";
  }
  $sth_r->finish;
  $dbh_fix->disconnect;
}

sub update_ip {
  my ( $reseller, $username, $inherit ) = @_;

  if ( ( !exists $reseller::default_iplist{$reseller} ) && ( $inherit != 1 ) ) {
    return;
  }

  my $dbh1 = &miscutils::dbhconnect('pnpmisc');
  if ( $inherit == 1 ) {
    $reseller::default_iplist{$reseller} = "";
    $dbh1->{FetchHashKeyName} = 'NAME_lc';
    my @iparray = ();
    my $sth     = $dbh1->prepare(
      q{
        SELECT ipaddress,netmask
        FROM ipaddress
        WHERE username=?
      }
      )
      or die "Can't do: $DBI::errstr";
    $sth->execute("$reseller") or die "Can't execute: $DBI::errstr";
    while ( my $data = $sth->fetchrow_hashref() ) {
      my $entry = $data->{'ipaddress'} . "/" . $data->{'netmask'};
      push( @iparray, $entry );
    }
    $sth->finish;

    $reseller::default_iplist{$reseller} = [@iparray];
  }

  my $email   = "dprice\@plugnpay.com";
  my $message = "Update IP called: Reseller:$reseller, UN:$username";

  foreach my $ipaddress ( @{ $reseller::default_iplist{$reseller} } ) {
    $message .= " IP:$ipaddress, ";

    if ( $ipaddress =~ /\// ) {
      ( $ipaddress, $netmask ) = split( /\//, $ipaddress );
    }
    if ( ( $netmask < 24 ) || ( $netmask > 32 ) ) {
      $netmask = "32";
    }

    my $ip = NetAddr::IP->new("$ipaddress/$netmask");
    my ( $firstip, $m );
    if ( defined $ip ) {
      ( $firstip, $m ) = split( /\//, $ip->first() );
    } else {
      $firstip = $ipaddress;
      $netmask = "32";
    }

    my $sth = $dbh1->prepare(
      q{
        SELECT ipaddress
        FROM ipaddress
        WHERE username=?
        AND ipaddress=?
      }
      )
      or die "Can't do: $DBI::errstr";
    $sth->execute( "$username", "$firstip" ) or die "Can't execute: $DBI::errstr";
    my ($test) = $sth->fetchrow;
    $sth->finish;

    if ( $test eq "" ) {
      $message .= "Insert UN:$username, IP:$ipaddress ";
      my $sth = $dbh1->prepare(
        q{
          INSERT INTO ipaddress
          (username,ipaddress,netmask)
          VALUES (?,?,?)
        }
        )
        or die "Can't prepare: $DBI::errstr";
      $sth->execute( $username, $firstip, $netmask ) or die "Can't prepare: $DBI::errstr";
      $sth->finish;
    }
  }

  $dbh1->disconnect;

  if ( $reseller =~ /monkeyme/ ) {
    &support_email( $email, $cc_email, $message );
  }
}

# old, wrapper call
sub autochangepw {
  my $loginObj = new PlugNPay::Login( $query{'username'} );
  my $result   = $loginObj->autoResetPassword($merchemail);

  my $message;
  if ($result) {
    $message = "Password has been reset and emailed.";
  } else {
    $message = $result->getError();
  }

  &response_page($message);
  exit;
}

sub viewpwfile {
  $reseller =~ s/[^0-9a-zA-Z]//g;
  my $filename = $reseller . "passwd.txt";
  &sysutils::filelog( "read", "/home/p/pay1/private/$filename" );
  open( INPUT, "/home/p/pay1/private/$filename" );
  while (<INPUT>) {
    chop;
    print "$_\n";
  }
  close(INPUT);
}

sub deletepwfile {
  my $filename = "/home/p/pay1/private/" . $reseller . "passwd.txt";

  copy( "/dev/null", "$filename" );

  #print "Content-Type: text/html\n\n";
  my $message = "File has been deleted.";
  &response_page($message);
  exit;
}

sub updatefee {

  my %transfee = (
    'newauthfee', 'New Auth', 'recauthfee',  'Rec. Auth',     'returnfee', 'Return',        'fraudfee', 'Fraud Screen', 'cybersfee', 'Cybersource',
    'voidfee',    'Void ',    'declinedfee', 'Declined Auth', 'discntfee', 'Discount Rate', 'resrvfee', 'Reserves',     'chargebck', 'Chargebacks'
  );

  my @transfee = ( 'newauthfee', 'recauthfee', 'declinedfee', 'returnfee', 'voidfee', 'fraudfee', 'cybersfee', 'discntfee', 'resrvfee', 'chargebck' );

  my %data = %query;

  foreach $key ( keys %data ) {
    if ( $key =~ /^fixed_feeid/ ) {
      my $tmp  = $data{$key};
      my $tmp1 = "$tmp\_rate";
      my $tmp2 = $data{$tmp1};
      if ( ( $tmp2 ne "" ) && ( $dl{$tmp} != 1 ) ) {
        @fixedfees = ( @fixedfees, $tmp );
      }
    }
    if ( $key =~ /^discnt_feeid/ ) {
      my $tmp  = $data{$key};
      my $tmp1 = "$tmp\_rate";
      my $tmp2 = $data{$tmp1};

      if ( ( $tmp2 ne "" ) && ( $dl{$tmp} != 1 ) ) {
        @discntfees = ( @discntfees, $tmp );
      }
    }
  }

  my $dbh = &miscutils::dbhconnect('merch_info');
  foreach $fee ( keys %transfee ) {
    $type = $data{ $fee . "type" };
    $type =~ s/[^a-z]//g;
    $rate = $data{$fee};
    $rate =~ s/[^0-9\.]//g;

    $qstr = "SELECT feeid FROM billing WHERE username=? AND feeid=?";
    my $sth = $dbh->prepare($qstr) or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sth->execute( $username, $fee ) or die "Can't execute: $DBI::errstr";

    my ($test) = $sth->fetchrow;
    $sth->finish;
    if ( $test ne "" ) {
      $qstr = "UPDATE billing SET feetype=?,feedesc=?,rate=?,type=? WHERE username=? AND feeid=?";

      #print "TRANSUPDATE: UN:$username<br>\n";
      my $sth = $dbh->prepare($qstr) or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sth->execute( "$fee", "$transfees{$fee}", "$rate", "$type", $username, $fee ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sth->finish;
    } else {
      my $sth = $dbh->prepare(
        q{
          INSERT INTO billing
          (username,feeid,feetype,feedesc,rate,type,subacct)
          VALUES (?,?,?,?,?,?,?)
        }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sth->execute( "$username", "$fee", "$fee", "$transfees{$fee}", "$data{$fee}", "$type", "$data{'subacct'}" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    }
  }

  foreach $fee (@fixedfees) {
    $desc = $data{"$fee\_desc"};
    $rate = $data{"$fee\_rate"};

    $qstr = "SELECT feeid FROM billing WHERE username=? AND feeid=?";

    my $sth = $dbh->prepare($qstr) or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sth->execute( $username, $fee ) or die "Can't execute: $DBI::errstr";
    my ($test) = $sth->fetchrow;
    $sth->finish;

    if ( $test ne "" ) {
      $qstr = "UPDATE billing SET feetype=?,feedesc=?,rate=?,type=? WHERE username=? AND feeid=?";

      my $sth = $dbh->prepare($qstr) or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sth->execute( "fixed", "$desc", "$rate", "monthly", $username, $fee )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    } else {
      my $sth = $dbh->prepare(
        q{
          INSERT INTO billing
          (username,feeid,feetype,feedesc,rate,type,subacct)
          VALUES (?,?,?,?,?,?,?)
        }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sth->execute( "$username", "$fee", "fixed", "$desc", "$rate", "monthly", "$data{'subacct'}" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    }
  }

  foreach $fee (@discntfees) {
    print "FEE:$fee<br>\n";
    $desc = $data{"$fee\_desc"};
    $rate = $data{"$fee\_rate"};

    $qstr = "SELECT feeid FROM billing WHERE username=? AND feeid=?";

    my $sth = $dbh->prepare($qstr) or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sth->execute( $username, $fee ) or die "Can't execute: $DBI::errstr";
    my ($test) = $sth->fetchrow;
    $sth->finish;

    if ( $test ne "" ) {
      $qstr = "UPDATE billing SET feetype=?,feedesc=?,rate=?,type=? WHERE username=? AND feeid=?";

      my $sth = $dbh->prepare($qstr) or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sth->execute( "discnt", "$desc", "$rate", "discnt", $username, $fee ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    } else {
      my $sth = $dbh->prepare(
        q{
          INSERT INTO billing
          (username,feeid,feetype,feedesc,rate,type,subacct)
          VALUES (?,?,?,?,?,?,?)
        }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sth->execute( "$username", "$fee", "discnt", "$desc", "$rate", "discnt", "$data{'subacct'}" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    }
  }

  $dbh->disconnect;
}

sub commission {

  # new scheme
  #  monthly calculated against monthly min amount
  #  extra againast monthly extra amount
  #  tran against amount - extra - monthly min

  # use billingreport table or billingstatus table for this reseller
  my ($newflag) = @_;

  my $startmonth = $query{'startmonth'};
  my $startday   = $query{'startday'};
  my $startyear  = $query{'startyear'};
  my $endmonth   = $query{'endmonth'};
  my $endday     = $query{'endday'};
  my $endyear    = $query{'endyear'};

  # used to negate reseller query
  my $not = $query{'not'};

  # ??
  $user = $reseller;

  my %month_array2 = ( "Jan", "01", "Feb", "02", "Mar", "03", "Apr", "04", "May", "05", "Jun", "06", "Jul", "07", "Aug", "08", "Sep", "09", "Oct", "10", "Nov", "11", "Dec", "12" );

  my $startdatestr = sprintf( "%04d%02d%02d", $startyear, $month_array2{$startmonth}, $startday );
  my $enddatestr   = sprintf( "%04d%02d%02d", $endyear,   $month_array2{$endmonth},   $endday );

  # variables used for select from customers
  my ( $username, $reseller, $origsalescommission, $origmonthlycommission, $cstartdate, $salesagent, $transcommission, $extracommission, $monthly_min, $extrafees );

  # used to store commssion amount paid
  my $commission = 0;

  my $resellertotal      = 0;
  my $resellercommission = 0;
  my $paidtotal          = 0;
  my $commtotal          = 0;
  my $resellerold        = "";
  my $usernameold        = "";

  # choose format of output and start printing stuff
  if ( $query{'format'} eq "text" ) {
    if ( $user =~ /^($reseller::tech_list)$/ ) {
      print "Reseller\t";
    }
    print "Username\tTrans Date\tAmount\tDescription\tCommission\tPaid\n";
  } else {
    print "<!DOCTYPE html>\n";
    print "<html lang=\"en-US\">\n";
    print "<head>\n";
    print "<meta charset=\"utf-8\">\n";
    print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
    print "<title>Commission Report</title>\n";
    print "<link rel=\"stylesheet\" type=\"text/css\" href=\"stylesheet.css\">\n";
    print "<META HTTP-EQUIV='Pragma' CONTENT='no-cache'>\n";
    print "<META HTTP-EQUIV='Cache-Control' CONTENT='no-cache'>\n";
    print "</head>\n";
    print "<body bgcolor=\"#ffffff\">\n";

    print "<div align=center>\n";
    print "<form action=\"$reseller::path_cgi\" method=\"post\">\n";
    print "<input type=hidden name=\"function\" value=\"updatepaid\">\n";
    print "<table border=0 cellspacing=0 cellpadding=1>\n";
    print "<tr class=\"across\"><th class=\"across\" colspan=7>Commission Schedule</th>\n";
    print "<tr class=\"across\">\n";
    if ( $user =~ /^($reseller::tech_list)$/ ) {
      print "<th>Reseller&nbsp;&nbsp;</th>";
    }
    print "<th>Username&nbsp;&nbsp;</th>";
    print "<th>Trans Date&nbsp;&nbsp;</th>";
    print "<th class=\"right\">Amount</th>";
    print "<th>&nbsp;&nbsp;Description</th>";
    print "<th class=\"right\">&nbsp;&nbsp;Commission</th>";
    print "<th>&nbsp;&nbsp;Paid</th>\n";
  }

  # connect to db
  my $dbh = &miscutils::dbhconnect('pnpmisc');
  $str = "";
  my @vars;
  if ( ( $srchreseller ne "" ) && ( $srchsalesagent ne "" ) ) {
    if ( $not eq "yes" ) {
      @resellers = $data->param('srchreseller');
      $tempstr   = "";
      foreach $var (@resellers) {
        $tempstr = $tempstr . "?,";
        push @vars, $var;
      }
      chop $tempstr;
      $str = " AND (c.reseller IS NULL OR c.reseller='' OR c.reseller NOT IN ($tempstr))";
      if ( $srchsalesagent ne "" ) {
        $str = " AND s.salesagent=?";
        push @vars, $srchsalesagent;
      }
    } else {
      $str = " AND ((c.reseller=?) OR (s.salesagent=?))";
      push @vars, ( $srchreseller, $srchsalesagent );
    }
  } elsif ( $srchreseller ne "" ) {
    if ( $not eq "yes" ) {
      @resellers = $data->param('srchreseller');
      $tempstr   = "";
      foreach $var (@resellers) {
        $tempstr = $tempstr . "?,";
        push @vars, $var;
      }
      chop $tempstr;
      $str = " AND (c.reseller IS NULL OR c.reseller='' OR c.reseller NOT IN ($tempstr))";
    } else {
      $str = " AND c.reseller=?";
      push @vars, $srchreseller;
    }
  } elsif ( $srchsalesagent ne "" ) {
    $str = " AND s.salesagent=?";
    push @vars, $srchsalesagent;
  }

  if ( $ENV{'REMOTE_USER'} =~ /^($reseller::tech_list)$/ ) {
    $sth = $dbh->prepare(
      qq/
        SELECT c.username,c.reseller,c.salescommission,c.monthlycommission,c.startdate,s.salesagent,c.transcommission,c.extracommission,c.monthly,c.extrafees
        FROM customers c,salesforce s
        WHERE (c.reseller IS NULL OR c.reseller=? OR c.reseller <> ?)
        AND c.reseller=s.username
        $str
        ORDER BY s.salesagent,c.reseller,c.username
      /
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute( '', 'plugnpay', @vars ) or die "Can't execute: $DBI::errstr";
    $sth->bind_columns( undef, \( $username, $reseller, $origsalescommission, $origmonthlycommission, $cstartdate, $salesagent, $transcommission, $extracommission, $monthly_min, $extrafees ) );
  } else {
    $sth = $dbh->prepare(
      q/
        SELECT username,reseller,salescommission,monthlycommission,startdate,transcommission,extracommission,monthly,extrafees
        FROM customers
        WHERE reseller=?
        ORDER BY username
      /
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute($user) or die "Can't execute: $DBI::errstr";
    $sth->bind_columns( undef, \( $username, $reseller, $origsalescommission, $origmonthlycommission, $cstartdate, $transcommission, $extracommission, $monthly_min, $extrafees ) );
  }

  $i = 1;

  # generate this only once
  my ($threeyearsago) = &miscutils::gendatetime_only( -3 * 365 * 24 * 60 * 60 );
  my ($twoyearsago)   = &miscutils::gendatetime_only( -2 * 365 * 24 * 60 * 60 );

  while ( $sth->fetch ) {

    # skip this customer totally if startdate is over 3 years ago and it's donna, will, or, well, scott mortenson doesn't work here anymore.
    if ( ( $reseller =~ /^(dmongell|wdunkak|smortens)$/ ) && ( $cstartdate ne "" ) && $cstartdate <= $threeyearsago ) {
      next;
    }

    # create date range from start and end date
    my $dateRange = new PlugNPay::Database::QueryBuilder()->generateDateRange( { start_date => $startdatestr, end_date => $enddatestr } );
    my $dateRangeParams = $dateRange->{'params'};

    my $table;
    my $statusCheck = '';
    my @values = ( $username, @{ $dateRange->{'values'} } );

    if ( $newflag eq "new" ) {
      $table = 'billingreport';
    } else {
      $table       = 'billingstatus';
      $resultCheck = ' AND result=? ';
      push @values, 'success';
    }

    my $query = qq/
      SELECT orderid,trans_date,amount,paidamount,paiddate,descr
      FROM $table
      WHERE username=?
      AND trans_date in ($dateRangeParams)
      AND (descr IS NULL OR descr='' OR descr NOT LIKE 'Return Fee%')
      $resultCheck
      ORDER BY trans_date
    /;

    $sth_billing = $dbh->prepare($query) or die "Can't prepare: $DBI::errstr";
    $sth_billing->execute(@values) or die "Can't execute: $DBI::errstr";

    my $rows = $sth_billing->fetchall_arrayref( [] );

    foreach $row ( @{$rows} ) {
      my ( $orderid, $trans_date, $amount, $paidamount, $paiddate, $descr ) = @{$row};
      $trans_datestr = sprintf( "%02d/%02d/%04d", substr( $trans_date, 4, 2 ), substr( $trans_date, 6, 2 ), substr( $trans_date, 0, 4 ) );

      $paiddatestr = sprintf( "%02d/%02d/%04d", substr( $paiddate, 4, 2 ), substr( $paiddate, 6, 2 ), substr( $paiddate, 0, 4 ) );

      $monthlycommission = $origmonthlycommission;

      if ( $origsalescommission =~ /,/ ) {
        @salesarray = split( /,/, $origsalescommission );
        $years = substr( $trans_date, 0, 4 ) - substr( $cstartdate, 0, 4 );
        $salescommission = $salesarray[$years];
      } else {
        $salescommission = $origsalescommission;
      }

      if ( ( $reseller =~ /^(dmongell|wdunkak|smortens)$/ ) && ( $cstartdate ne "" ) && $cstartdate <= $twoyearsago ) {

        # lower comission to 15%
        $salescommission   = .15;
        $monthlycommission = .15;
        $extracommission   = .15;
      }

      # actual calculation of commission
      $commission = 0;
      if ( ( $descr =~ /Monthly Billing/ ) && ( $amount > 0.0 ) ) {

        # if the amount paid is less than or equal to the monthly min
        # we calculate based on the monthly min commission
        if ( ( ( $amount <= $monthly_min ) && ( $monthly_min ne "" ) ) || ( $transcommission == 0 ) ) {

          # if it's greater than 1 then it is a flat rate
          if ( $monthlycommission >= 1 ) {
            $commission = $monthlycommission;

            # used somehow to fix returned amounts
            if ( $amount < 0 ) {
              $commission = -1 * $commission;
            }
          }

          # if it's less than 1 then it's a percentage of the amount
          else {
            # comm = amount - extra fees * monthlycommission
            # cprice changed $amount to $monthly_min 02/06/2012 based on michelle and barbara
            $commission = ( $monthly_min - $extrafees ) * $monthlycommission;
            if ( ( $amount < 0 ) && ( $commission > 0 ) ) {
              $commission = -1 * $commission;
            }
          }
        }

        # commission based on tran commission
        else {
          # flat commission for over monthly min uses per trans commission
          if ( $transcommission >= 1 ) {
            $commission = $monthlycommission;
          }

          # otherwise it's a percentage
          else {
            #print "tst a: $amount ex: $extrafees tc: $transcommission mm: $monthly_min <br>\n";
            $commission = ( $amount - $extrafees ) * $transcommission;

            #print "tst a: $amount ex: $extrafees tc: $transcommission mm: $monthly_min co: $commission<br>\n";
          }
        }

        if ( $commission < $monthlycommission ) {
          if ( $monthlycommission >= 1 ) {
            $commission = $monthlycommission;
          } else {
            $commission = $monthly_min * $monthlycommission;
          }
          if ( $amount < 0 ) {
            $commission = -1 * $commission;
          }
        }

        # check to see if extra fee commission should be added
        if ( $extrafees > 0 ) {

          # flat rate
          if ( $extracommission >= 1 ) {
            $commission += $extracommission;
          }

          # percentage of extrafee
          else {
            $commission += $extrafees * $extracommission;
          }
        }
      } elsif ( ( $descr eq "Return Monthly Billing" ) && ( $amount < 0 ) ) {
        if ( ( $reseller =~ /^(dmongell|wdunkak|smortens)$/ ) && ( $cstartdate <= $threeyearsago ) ) {

          # if will or donna and older than 3 years no return
          $commission = 0;
        } elsif ( $monthlycommission >= 1 ) {
          $commission -= $monthlycommission;
        } else {
          if ( $transcommission == 0 ) {
            $commission -= ( $monthly_min - $extrafees ) * $monthlycommission;
          } else {
            if ( ( -1 * $amount ) <= $monthly_min ) {
              $commission = -1 * ( ( $monthly_min + $extrafees ) * $monthlycommission );
            } else {
              $commission = ( $amount + $extrafees ) * $transcommission;
            }
          }
        }
        if ( $extrafees > 0 ) {
          if ( ( $reseller =~ /^(dmongell|wdunkak|smortens)$/ ) && ( $cstartdate <= $threeyearsago ) ) {

            # do nothing here in this case
          } elsif ( $extracommission >= 1 ) {
            $commission -= $extracommission;
          }

          # percentage of extrafee
          else {
            $commission -= $extrafees * $extracommission;
          }
        }
      } elsif ( $salescommission >= 1 ) {
        $commission = $salescommission;
        if ( $amount < 0 ) {
          $commission = -$commission;
        }
      } elsif ( $salescommission < 1 ) {
        $commission = $amount * $salescommission;
      } else {
        $commission = "";
      }

      $commission = sprintf( "%.2f", $commission );

      if ( $query{'format'} eq "text" ) {
        if ( $ENV{'REMOTE_USER'} =~ /^($reseller::tech_list)$/ ) {
          print "$resellertotal\t$resellercommission $reseller ($salesagent)\t";
          $resellertotal      = 0;
          $resellercommission = 0;
          if ( $paiddate eq "" ) {
            $resellertotal      = $resellertotal + $amount;
            $resellercommission = $resellercommission + $commission;
          }
        }
        print "$username\t$trans_datestr\t";
        printf( "%.2f\t", $amount );
        print "$descr\t";
        if ( $paiddate ne "" ) {
          printf( "%.2f\t", $paidamount );
        } else {
          printf( "%.2f\t", $commission );
        }
        $paiddatestr = &miscutils::datetostr($paiddate);
        print "$paiddatestr\t\n";
        $paidtotal   = $paidtotal + $paidamount;
        $resellerold = $reseller;
        $usernameold = $username;
      } else {
        print "<tr>\n";
        if ( $ENV{'REMOTE_USER'} =~ /^($reseller::tech_list)$/ ) {
          if ( $reseller ne $resellerold ) {
            print "<th class=\"leftside\"> &nbsp; </th>";
            print "<td colspan=2></td>";
            printf( "<th class=\"right\">%.2f</th>", $resellertotal );
            print "<td></td>";
            printf( "<th class=\"right\">%.2f</th>", $resellercommission );
            print "<tr>\n";
            print "<th class=\"leftside\">$reseller<br><font size=\"-1\">($salesagent)</font></th>";
            $resellertotal      = 0;
            $resellercommission = 0;
          } else {
            print "<th class=\"leftside\"> &nbsp; </th>";
          }

          #print "<td> &nbsp; $resellercommission &nbsp; $paidamount &nbsp; $commission</td>\n";
          if ( $paiddate eq "" ) {
            $resellertotal      = $resellertotal + $amount;
            $resellercommission = $resellercommission + $commission;
          }

          if ( $username ne $usernameold ) {
            print "<td><a href=\"$reseller::path_cgi?username=$username\&function=viewtransactions\&startdate=$startdatestr\&enddate=$enddatestr\&resellmerchant=$query{'resellmerchant'}\">$username</a></td>";
          } else {
            print "<th> &nbsp; </th>";
          }
        } else {
          if ( $username ne $usernameold ) {
            print
              "<th class=\"leftside\"><a class=\"awhite\" href=\"$reseller::path_cgi?username=$username\&function=viewtransactions\&startdate=$startdatestr\&enddate=$enddatestr\&resellmerchant=$query{'resellmerchant'}\">$username</a></th>";
          } else {
            print "<th class=\"leftside\"> &nbsp; </th>";
          }
        }

        print "<td>$trans_datestr</td>";
        printf( "<td class=\"tdright\">%.2f</td>", $amount );

        print "<td>&nbsp;&nbsp;$descr</td>";

        # xxxxxxxxxxxxxxxxx
        if ( $paidamount ne "" ) {
          printf( "<td class=\"tdright\">%.2f a</td>", $paidamount );

          #print "d $paidamount<br>\n";
        } else {
          printf( "<td class=\"tdright\">%.2f b</td>", $commission );

          #print "e $commission<br>\n";
        }

        # xxxx
        if ( ( $ENV{'REMOTE_USER'} =~ /^($reseller::tech_list)$/ ) && ( $paiddate eq "" ) ) {
          print "<td class=\"tdright\"><input type=checkbox name=\"orderid$i\" value=\"$orderid\" checked>";
          if ( $paidamount ne "" ) {
            print "<input type=hidden name=\"paidamount$i\" value=\"$paidamount\">";
            print "<input type=hidden name=\"amount$i\" value=\"$amount\">";
            print "<input type=hidden name=\"descr$i\" value=\"$descr\">";
            $commtotal = $commtotal + $paidamount;
          } else {
            print "<input type=hidden name=\"paidamount$i\" value=\"$commission\">";
            print "<input type=hidden name=\"amount$i\" value=\"$amount\">";
            print "<input type=hidden name=\"descr$i\" value=\"$descr\">";
            $commtotal = $commtotal + $commission;
          }
          print "<input type=hidden name=\"listval\" value=\"$i\"></td>\n";
          $i++;
        } else {
          $paiddatestr = &miscutils::datetostr($paiddate);
          print "<td> &nbsp; $paiddatestr</td>\n";
          $paidtotal = $paidtotal + $paidamount;
        }
        $resellerold = $reseller;
        $usernameold = $username;
      }
    }
    $sth_billing->finish;
  }
  $sth->finish;
  $dbh->disconnect;

  if ( $query{'format'} eq "text" ) {
    if ( $ENV{'REMOTE_USER'} =~ /^($reseller::tech_list)$/ ) {
      printf( "Reseller Total\t%.2f\n",      $resellertotal );
      printf( "Reseller Commission\t%.2f\n", $resellercommission );
    }
    printf( "Total Paid\t%.2f\n",   $paidtotal );
    printf( "Total Unpaid\t%.2f\n", $commtotal );
    printf( "Grand Total\t%.2f\n",  $commtotal + $paidtotal );
  } else {
    if ( $ENV{'REMOTE_USER'} =~ /^($reseller::tech_list)$/ ) {
      print "<tr>\n";
      print "<th class=\"leftside\"> &nbsp; </th>";
      print "<td colspan=2></td>";
      printf( "<th class=\"right\">%.2f</th>", $resellertotal );
      print "<td></td>";
      printf( "<th class=\"right\">%.2f</th>", $resellercommission );
    }

    printf( "<tr><th align=left>Total Paid</th><td colspan=5></td><th align=right>%.2f</th>",   $paidtotal );
    printf( "<tr><th align=left>Total Unpaid</th><td colspan=5></td><th align=right>%.2f</th>", $commtotal );
    printf( "<tr><th align=left>Grand Total</th><td colspan=5></td><th align=right>%.2f</th>",  $commtotal + $paidtotal );

    print "</table>\n";

    if ( $ENV{'REMOTE_USER'} =~ /^($reseller::tech_list)$/ ) {
      print "<input type=submit name=\"submit\" value=\"Submit Changes\">\n";
    }

    print "</form>\n";
    print "</div>\n";
    print "</body>\n";
    print "</html>\n";
  }
}

sub viewbuyrates {

  # shows reseller buyrates, so that it's backwards compatible with existing code

  my $is_ok = 0;    # set to 1 when allowed.

  my $account = $reseller::query{'reseller'};
  $account =~ s/[^a-zA-Z0-9]//g;

  my $dbh = &miscutils::dbhconnect('pnpmisc');

  #if ($reseller eq "rriding") {
  if ( ( $reseller =~ /^(rriding|devresell)$/ ) || ( $account ne "" ) ) {
    my $sth_res = $dbh->prepare(
      q{
        SELECT username
        FROM salesforce
        WHERE username=?
      }
      )
      or die "cant prepare $DBI::errstr\n";
    $sth_res->execute("$account") or die "cant execute $DBI::errstr\n";
    my ($test) = $sth_res->fetchrow;
    $sth_res->finish;

    if ( $test eq $account ) {
      $is_ok = 1;
    }
  } elsif ( $reseller =~ /^(michell|brianro2|brianro3|bridgevi|cashlinq|cardpaym|cpscorp|dmongell|wdunkak|globalpy|planetpa)$/ ) {
    my $sth_res = $dbh->prepare(
      q{
        SELECT username
        FROM salesforce
        WHERE username=?
        AND salesagent=?
      }
      )
      or die "cant prepare $DBI::errstr\n";
    $sth_res->execute( "$account", "$reseller" ) or die "cant execute $DBI::errstr\n";
    my ($test) = $sth_res->fetchrow;
    $sth_res->finish;

    if ( $test eq $account ) {
      $is_ok = 1;
    }
  } else {
    $account = $reseller;
    $is_ok   = 1;
  }

  $dbh->disconnect();

  if ( $is_ok == 1 ) {
    &showbuyrates("$account");
  } else {
    &response_page("Invalid Account Username.");
  }

  return;
}

sub showbuyrates {
  my ($account) = @_;
  &head;

  my $dbh = &miscutils::dbhconnect('pnpmisc');

  my $sth = $dbh->prepare(
    q{
      SELECT username,company,name,addr1,addr2,city,state,zip,country,tel,fax,email,taxid,status,startdate,referral
      FROM salesforce
      WHERE username=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth->execute("$account") or die "Can't execute: $DBI::errstr";
  my $results = $sth->fetchrow_hashref();
  $sth->finish;

  $results->{'startdate'} =~ s/^(....)(..)(..)\z/$2\/$3\/$1/s;

  print "<table border=1 cellspacing=1 cellpadding=4>\n";
  print "  <tr>\n";
  print "    <th colspan=4 class=\"tr1\"><font size=+1>Contact Information</font></th>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"tr5\">Username:</th><td class=\"tr2\">$results->{'username'}</td>\n";
  print "    <th class=\"tr5\">Start Date:</th><td class=\"tr2\">$results->{'startdate'}</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"tr5\">Company:</th><td class=\"tr2\" colspan=3>$results->{'company'}</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"tr5\">Contact Name:</th><td class=\"tr2\" colspan=3>$results->{'name'}</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"tr5\">Address:</th><td class=\"tr2\" colspan=3>$results->{'addr1'}<br>\n";

  if ( $results->{'addr2'} ne "" ) {
    print "$results->{'addr2'}<br>\n";
  }
  print "$results->{'city'} $results->{'state'} $results->{'zip'} $results->{'country'}</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"tr5\">Tel:</th><td class=\"tr2\">$results->{'tel'}</td>\n";
  print "    <th class=\"tr5\">Fax:</th><td class=\"tr2\">$results->{'fax'}</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  my $escapedEmail = CGI::escapeHTML( $results->{'email'} );
  print "    <th class=\"tr5\">Email:</th><td class=\"tr2\"><a href=\"mailto:$escapedEmail\">$escapedEmail</a></td>\n";
  print "    <th class=\"tr5\">Tax ID:</th><td class=\"tr2\">$results->{'taxid'}</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"tr5\">Referral:</th><td class=\"tr2\">";

  if ( $results->{'referral'} ne "" ) {
    print "$results->{'referral'}";
  } else {
    print "no";
  }
  print "</td>\n";
  print "  </tr>\n";

  print "</table>\n";
  print "<p>\n";

  $sth_salesforce = $dbh->prepare(
    q{
      SELECT b_csetup,b_cmin,b_ctranmax,b_ctran,b_ctranex,s_ctranmax,
        s_ctranex,s_csetup,s_cmin,s_ctran,b_rsetup,b_rmin,b_rtran,s_rmin,
        s_rtran,b_msetup,b_mmin,b_mtran,s_mmin,s_mtran,b_dsetup,b_dmin,
        b_dtran,s_dmin,s_dtran,b_fsetup,b_fmin,b_ftran,s_fmin,s_ftran,
        b_asetup,b_amin,b_atran,s_amin,s_atran,b_cosetup,b_comin,b_cotran,
        s_comin,s_cotran,payallflag,premiumflag,b_bpsetup,b_bpmin,b_bptran,
        s_bpmin,s_bptran,b_hrsetup,b_hrmin,b_hrtran,s_hrsetup,s_hrmin,s_hrtran,
        b_lsetup,b_lmin,b_ltran,s_lsetup,s_lmin,s_ltran
      FROM salesforce
      WHERE username=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth_salesforce->execute("$account") or die "Can't execute: $DBI::errstr";
  my (
    $b_csetup, $b_cmin,   $b_ctranmax, $b_ctran,  $b_ctranex,  $s_ctranmax,  $s_ctranex, $s_csetup, $s_cmin,   $s_ctran, $b_rsetup, $b_rmin,
    $b_rtran,  $s_rmin,   $s_rtran,    $b_msetup, $b_mmin,     $b_mtran,     $s_mmin,    $s_mtran,  $b_dsetup, $b_dmin,  $b_dtran,  $s_dmin,
    $s_dtran,  $b_fsetup, $b_fmin,     $b_ftran,  $s_fmin,     $s_ftran,     $b_asetup,  $b_amin,   $b_atran,  $s_amin,  $s_atran,  $b_cosetup,
    $b_comin,  $b_cotran, $s_comin,    $s_cotran, $payallflag, $premiumflag, $b_bpsetup, $b_bpmin,  $b_bptran, $s_bpmin, $s_bptran, $b_hrsetup,
    $b_hrmin,  $b_hrtran, $s_hrsetup,  $s_hrmin,  $s_hrtran,   $b_lsetup,    $b_lmin,    $b_ltran,  $s_lsetup, $s_lmin,  $s_ltran
    )
    = $sth_salesforce->fetchrow;
  $sth_salesforce->finish;

  $dbh->disconnect();

  print "<table border=1 cellspacing=1 cellpadding=4>\n";

  print "  <tr class=\"tr5\">\n";
  print "    <th> Buy Rates </th>\n";
  print "    <th> Setup </th>\n";
  print "    <th> Monthly Min </th>\n";
  print "    <th> PerTran </th>\n";
  print "  </tr>\n";
  print "  <tr class=\"tr2\">\n";
  print "    <td> Direct Link </td>\n";
  print "    <td> $b_csetup </td>\n";
  print "    <td> $b_cmin </td>\n";
  print "    <td class=\"tr2\">\n";

  if ( $b_ctranmax ne "" ) {
    print "  # $b_ctranmax\n";
  }
  print "  \$ $b_ctran <br>\n";
  if ( $b_ctranex ne "" ) {
    print "  Extra $b_ctranex\n";
  }
  print "</td>\n";
  print "  </tr>\n";
  print "  <tr class=\"tr2\">\n";
  print "    <td> Level 3 </td>\n";
  print "    <td> $b_lsetup </td>\n";
  print "    <td> $b_lmin </td>\n";
  print "    <td> $b_ltran </td>\n";
  print "  </tr>\n";
  print "  <tr class=\"tr2\">\n";
  print "    <td> High Risk </td>\n";
  print "    <td> $b_hrsetup </td>\n";
  print "    <td> $b_hrmin </td>\n";
  print "    <td> $b_hrtran </td>\n";
  print "  </tr>\n";
  print "  <tr class=\"tr2\">\n";
  print "    <td> Recurring </td>\n";
  print "    <td> $b_rsetup </td>\n";
  print "    <td> $b_rmin </td>\n";
  print "    <td> $b_rtran </td>\n";
  print "  </tr>\n";
  print "  <tr class=\"tr2\">\n";
  print "    <td> Billing<br>Presentment </td>\n";
  print "    <td> $b_bpsetup </td>\n";
  print "    <td> $b_bpmin </td>\n";
  print "    <td> $b_bptran </td>\n";
  print "  </tr>\n";
  print "  <tr class=\"tr2\">\n";
  print "    <td> Membership </td>\n";
  print "    <td> $b_msetup </td>\n";
  print "    <td> $b_mmin </td>\n";
  print "    <td> $b_mtran </td>\n";
  print "  </tr>\n";
  print "  <tr class=\"tr2\">\n";
  print "    <td> Digital </td>\n";
  print "    <td> $b_dsetup </td>\n";
  print "    <td> $b_dmin </td>\n";
  print "    <td> $b_dtran </td>\n";
  print "  </tr>\n";
  print "  <tr class=\"tr2\">\n";
  print "    <td> Affiliate </td>\n";
  print "    <td> $b_asetup </td>\n";
  print "    <td> $b_amin </td>\n";
  print "    <td> $b_atran </td>\n";
  print "  </tr>\n";
  print "  <tr class=\"tr2\">\n";
  print "    <td> Coupon </td>\n";
  print "    <td> $b_cosetup </td>\n";
  print "    <td> $b_comin </td>\n";
  print "    <td> $b_cotran </td>\n";
  print "  </tr>\n";
  print "  <tr class=\"tr2\">\n";
  print "    <td> FraudTrak </td>\n";
  print "    <td> $b_fsetup </td>\n";
  print "    <td> $b_fmin </td>\n";
  print "    <td> $b_ftran </td>\n";
  print "  </tr>\n";

  if ( $payallflag ne "0" ) {
    print "  <tr class=\"tr5\">\n";
    print "    <th> Sell Rates </th>\n";
    print "    <th> Setup </th>\n";
    print "    <th> Monthly Min </th>\n";
    print "    <th> PerTran </th>\n";
    print "  </tr>\n";
    print "  <tr class=\"tr2\">\n";
    print "    <td> Direct Link </td>\n";
    print "    <td> $s_csetup </td>\n";
    print "    <td> $s_cmin </td>\n";
    print "    <td>\n";

    if ( $s_ctranmax ne "" ) {
      print "  # $s_ctranmax\n";
    }
    print "  \$ $s_ctran <br>\n";
    if ( $s_ctranex ne "" ) {
      print "  Extra $s_ctranex \n";
    }
    print "</td>\n";
    print "  </tr>\n";
    print "  <tr class=\"tr2\">\n";
    print "    <td> Level 3 </td>\n";
    print "    <td> $s_lsetup </td>\n";
    print "    <td> $s_lmin </td>\n";
    print "    <td> $s_ltran </td>\n";
    print "  </tr>\n";
    print "  <tr class=\"tr2\">\n";
    print "    <td> High Risk </td>\n";
    print "    <td> \&nbsp\; </td>\n";
    print "    <td> $s_hrmin </td>\n";
    print "    <td> $s_hrtran </td>\n";
    print "  </tr>\n";

    if ( $premiumflag eq "1" ) {
      print "  <tr class=\"tr2\">\n";
      print "    <td> Recurring </td>\n";
      print "    <td> \&nbsp\; </td>\n";
      print "    <td> $s_rmin </td>\n";
      print "    <td> $s_rtran </td>\n";
      print "  </tr>\n";
      print "  <tr class=\"tr2\">\n";
      print "    <td> Billing<br>Presentment </td>\n";
      print "    <td> \&nbsp\; </td>\n";
      print "    <td> $s_bpmin </td>\n";
      print "    <td> $s_bptran </td>\n";
      print "  </tr>\n";
      print "  <tr class=\"tr2\">\n";
      print "    <td> Membership </td>\n";
      print "    <td> \&nbsp\; </td>\n";
      print "    <td> $s_mmin </td>\n";
      print "    <td> $s_mtran </td>\n";
      print "  </tr>\n";
      print "  <tr class=\"tr2\">\n";
      print "    <td> Digital </td>\n";
      print "    <td> \&nbsp\; </td>\n";
      print "    <td> $s_dmin </td>\n";
      print "    <td> $s_dtran </td>\n";
      print "  </tr>\n";
      print "  <tr class=\"tr2\">\n";
      print "    <td> Affiliate </td>\n";
      print "    <td> \&nbsp\; </td>\n";
      print "    <td> $s_amin </td>\n";
      print "    <td> $s_atran </td>\n";
      print "  </tr>\n";
      print "  <tr class=\"tr2\">\n";
      print "    <td> Coupon </td>\n";
      print "    <td> \&nbsp\; </td>\n";
      print "    <td> $s_comin </td>\n";
      print "    <td> $s_cotran </td>\n";
      print "  </tr>\n";
      print "  <tr class=\"tr2\">\n";
      print "    <td> FraudTrak </td>\n";
      print "    <td> \&nbsp\; </td>\n";
      print "    <td> $s_fmin </td>\n";
      print "    <td> $s_ftran </td>\n";
      print "  </tr>\n";
    }    # end premium flag if
  }

  if ( ( $ENV{'REMOTE_USER'} =~ /^($reseller::tech_list|dmongell|wdunkak|randy|rriding)$/ ) || ( $ENV{'REMOTE_ADDR'} eq "96.56.10.14" ) ) {
    my $patemp = "No";
    if ( $payallflag == 1 ) {
      $patemp = "Yes";
    }
    print "  <tr class=\"tr3\">\n";
    print "    <th>Pay All</th>\n";
    print "    <td colspan=3>$patemp</td>\n";
    print "  </tr>\n";
  }
  print "</table>\n";

  &tail;
}

sub head {
  print "<!DOCTYPE html>\n";
  print "<html lang=\"en-US\">\n";
  print "<head>\n";
  print "<meta charset=\"utf-8\">\n";
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
  print "<title> Reseller Administration</title>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"stylesheet.css\">\n";
  print "<META HTTP-EQUIV='Pragma' CONTENT='no-cache'>\n";
  print "<META HTTP-EQUIV='Cache-Control' CONTENT='no-cache'>\n";
  print "<style type=\"text/css\">\n";
  print "<!--\n";
  print "td { font-family: Arial; color: black }\n";
  print ".tr1 { background-color: #d0c0c0 }\n";
  print ".tr2 { background-color: #c0d0c0 }\n";
  print ".tr3 { background-color: #c0c0d0 }\n";
  print ".tr4 { background-color: #d0c0d0 }\n";
  print ".tr5 { background-color: #d0d0c0 }\n";
  print ".tr6 { background-color: #c0d0d0 }\n";
  print "th { font-family: Arial; font-weight: bold; color: black }\n";
  print "-->\n";
  print "</style>\n";
  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";
}

sub tail {
  print "</body>\n";
  print "</html>\n";
}

sub insert_nisc_report {
  my ($username) = @_;

  my $columns_type =
    "FinalStatus|1	acct_code|1	acct_code2|1	acct_code3|1	acct_code4|1	accttype|1	auth-code|1	card-amount|1	card-name|1	operation|2	orderID|1	trans_date|1	trans_type|1	transflags|1	card-number|2";
  my $columns_method =
    "FinalStatus|1	MErrmsg|1	acct_code|1	acct_code2|1	acct_code3|1	acct_code4|1	accttype|2	card-address|1	card-amount|1	card-city|1	card-country|1	card-exp|1	card-name|1	card-number|1	card-state|1	card-zip|1	operation|2	orderID|1	trans_date|2	transflags|1";
  my $columns_return =
    "FinalStatus|1	acct_code|1	acct_code2|1	acct_code3|1	acct_code4|1	accttype|1	auth-code|1	card-amount|1	card-name|1	operation|2	orderID|1	trans_date|1	trans_type|1	transflags|1	card-number|2";
  my $columns_void =
    "FinalStatus|1	MErrmsg|1	acct_code|1	acct_code2|1	acct_code3|1	acct_code4|1	accttype|2	card-address|1	card-amount|1	card-city|1	card-country|1	card-exp|1	card-name|1	card-number|1	card-state|1	card-zip|1	operation|2	orderID|1	trans_date|2	transflags|1";

  my $dbh_nisc = &miscutils::dbhconnect('reports');
  my $sth_nisc = $dbh_nisc->prepare(
    qq{
      INSERT INTO report_config
      (username,reportname,transtype,frequency,groupby,tablename,columnlist)
      VALUES (?,'DataEntryMethod','auth','daily','acct_code4','trans_log',?),
        (?,'CardType','auth','daily','card-type','trans_log',?),
        (?,'ReturnReport','return','daily','card-type','trans_log',?),
        (?,'VoidReport','void','daily','card-type','trans_log',?);
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth_nisc->execute( $username, $columns_method, $username, $columns_type, $username, $columns_return, $username, $columns_void ) or die "Can't execute: $DBI::errstr";
  $dbh_nisc->disconnect;
}

sub security_check {
  ####  Only appears to be used by regremote.cgi
  my ( $username, $password, $mode ) = @_;
  my $remoteaddr = $ENV{'REMOTE_ADDR'};
  my ( $ipaddr, %result, $login, $test, %feature );

  $username =~ s/[^a-zA-Z0-9]//g;

  my $authClient    = new PlugNPay::Authentication();
  my $authenticated = $authClient->validateLogin(
    { login    => $username,
      password => $password,
      realm    => 'REMOTECLIENT',
    }
  );

  my $dbh = &miscutils::dbhconnect('pnpmisc');
  my $sth = $dbh->prepare(
    q{
      SELECT reseller,bypassipcheck
      FROM customers
      WHERE username=?
    }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr" );
  $sth->execute("$username") or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr" );
  my ( $reseller, $bypassipcheck ) = $sth->fetchrow;
  $sth->finish;

  my $accountFeatures = new PlugNPay::Features( "$username", 'general' );
  my $features = $accountFeatures->getFeatureString();

  if ( $features ne "" ) {
    my @array = split( /\,/, $features );
    foreach my $entry (@array) {
      my ( $name, $value ) = split( /\=/, $entry );
      $feature{$name} = $value;
    }
  }

  my $sth3 = $dbh->prepare(
    q{
      SELECT ipaddress
      FROM ipaddress
      WHERE username=?
      AND ipaddress=?
    }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr" );
  $sth3->execute( "$username", "$remoteaddr" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr" );
  ($ipaddr) = $sth3->fetchrow;
  $sth3->finish;

  $dbh->disconnect;

  if ( $authenticated && $ipaddr ne "" ) {
    $result{'flag'} = 1;
  } elsif ( !$authenticated && $ipaddr ne "" ) {
    $result{'MErrMsg'} = "Missing/incorrect password";
    $result{'flag'}    = 0;
  } else {
    $result{'MErrMsg'} = "IP Not registered to username. Please register $remoteaddr in your admin area.";
    $result{'flag'}    = 0;
  }

  return %result;
}

sub update_fraud {
  my @array = %query;
  require fraudtrack;
  my $fraudtrack = fraudtrack->new(@array);

  my @table_list = ( 'ip_fraud', 'bin_fraud', 'phone_fraud', 'email_fraud' );

  if ( $query{'fconfig'} ne "" ) {
    $fraudtrack->update_config();
  }
  if ( $query{"country_block_list2"} ne "" ) {
    $fraudtrack->update_countries();
  }

  foreach my $var (@table_list) {
    if ( $query{$var} ne "" ) {
      $fraudtrack->update_entry( $var, 'update', $query{$var} );
    }
  }
}

sub insert_processor_info {    # from sub editfinal in processors.cgi
  $dbh = &miscutils::dbhconnect('pnpmisc');

  my $sthchk = $dbh->prepare(
    q{
      SELECT username
      FROM customers
      WHERE ((merchant_id IS NOT NULL AND merchant_id<>'' AND merchant_id=? AND processor<>'elavon' AND processor=?)
      OR (pubsecret IS NOT NULL AND pubsecret<>'' AND pubsecret=? AND processor='elavon'))
      AND username<>?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sthchk->execute( "$merchant_id", "$processor", "$pubsecret", "$username" ) or die "Can't execute: $DBI::errstr";
  ($chkusername) = $sthchk->fetchrow;
  $sthchk->finish;

  if ( ( $chkusername ne "" ) && ( $processor !~ /^gsopay/ ) && ( $processor !~ /^ncb/ ) && ( $processor !~ /^rbs/ ) ) {
    print "Merchant id $merchant_id or pubsecret $terminal_id already used by $chkusername<br>\n";
    exit;
  }

  $sth = $dbh->prepare(
    q{
      UPDATE customers
      SET merchant_id=?,pubsecret=?,currency=?
      WHERE username=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth->execute( "$merchant_id", "$pubsecret", "$currency", "$username" ) or die "Can't execute: $DBI::errstr";

  if ( $processor eq "paytechtampa" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM paytechtampa
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE paytechtampa
          SET username=?,banknum=?,clientid=?,industrycode=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$banknum", "$clientid", "$industrycode", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO paytechtampa
          (username,banknum,clientid,industrycode)
          VALUES (?,?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$banknum", "$clientid", "$industrycode" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "paytechsalem" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM paytechsalem
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE paytechsalem
          SET username=?,industrycode=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$industrycode", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO paytechsalem
          (username,industrycode)
          VALUES (?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$industrycode" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "ecb" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM ecb
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE ecb
          SET login=?,password=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$login", "$password", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO ecb
          (username,login,password)
          VALUES (?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$login", "$password" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "kwikpay" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM kwikpay
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE kwikpay
          SET un=?,pw=?,supplierid=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$un", "$pw", "$supplierid", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO kwikpay
          (username,un,pw,supplierid)
          VALUES (?,?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$un", "$pw", "$supplierid" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "fifththird" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM fifththird
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE fifththird
          SET bankid=?,categorycode=?,industrycode=?,dcctype=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$bankid", "$categorycode", "$industrycode", "$dcctype", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO fifththird
          (username,bankid,categorycode,industrycode,dcctype)
          VALUES (?,?,?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$bankid", "$categorycode", "$industrycode", "$dcctype" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "global" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM global
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE global
          SET bankid=?,industrycode=?,acctvmemberid=?,acctmmemberid=?,acctglobalid=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$bankid", "$industrycode", "$acctvmemberid", "$acctmmemberid", "$acctglobalid", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO global
          (username,bankid,industrycode,acctvmemberid,acctmmemberid,acctglobalid)
          VALUES (?,?,?,?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$bankid", "$industrycode", "$acctvmemberid", "$acctmmemberid", "$acctglobalid" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "fdmsintl" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM fdmsintl
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE fdmsintl
          SET banknum=?,categorycode=?,discovermid=?,amexmid=?,industrycode=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$banknum", "$categorycode", "$discovermid", "$amexmid", "$industrycode", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO fdmsintl
          (username,banknum,categorycode,discovermid,amexmid,industrycode)
          VALUES (?,?,?,?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$banknum", "$categorycode", "$discovermid", "$amexmid", "$industrycode" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "fdmsrc" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM fdmsrc
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE fdmsrc
          SET username=?,industrycode=?,categorycode=?,fedtaxid=?,vattaxid=?,chargedescr=?,groupid=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$industrycode", "$categorycode", "$fedtaxid", "$vattaxid", "$chargedescr", "$groupid", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO fdmsrc
          (username,industrycode,categorycode,fedtaxid,vattaxid,chargedescr,groupid)
          VALUES (?,?,?,?,?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$industrycode", "$categorycode", "$fedtaxid", "$vattaxid", "$chargedescr", "$groupid" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "vericheck" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM vericheck
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE vericheck
          SET merchantnum=?,fedtaxid=?,pass=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$merchantnum", "$fedtaxid", "$pass", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO vericheck
          (username,merchantnum,fedtaxid,pass)
          VALUES (?,?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$merchantnum", "$fedtaxid", "$pass" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "atlantic" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM atlantic
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE atlantic
          SET shopid=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$shopid", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO atlantic
          (username,shopid)
          VALUES (?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$shopid" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "barclays" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM barclays
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE barclays
          SET clientid=?,login=?,password=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$clientid", "$login", "$password", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO barclays
          (username,clientid,login,password)
          VALUES (?,?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$clientid", "$login", "$password" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "wirecard" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM wirecard
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE wirecard
          SET loginun=?,loginpw=?,country=?,returnflag=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$loginun", "$loginpw", "$country", "$returnflag", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO wirecard
          (username,loginun,loginpw,country,returnflag)
          VALUES (?,?,?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$loginun", "$loginpw", "$country", "$returnflag" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "maverick" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM maverick
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE maverick
          SET bin=?,industrycode=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$bin", "$industrycode", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO maverick
          (username,bin,industrycode)
          VALUES (?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$bin", "$industrycode" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "cccc" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM cccc
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE cccc
          SET bankid=?,categorycode=?,poscond=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$bankid", "$categorycode", "$poscond", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        qq{
          INSERT INTO cccc
          (username,bankid,categorycode,poscond)
          VALUES (?,?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$bankid", "$categorycode", "$poscond" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "elavon" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM elavon
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE elavon
          SET username=?,industrycode=?,batchgroup=?,banknum=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$industrycode", "$batchgroup", "$bin" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO elavon
          (username,industrycode,batchgroup,banknum)
          VALUES (?,?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$industrycode", "$batchgroup", "$bin" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "rbc" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM rbc
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE rbc
          SET server=?,industrycode=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$server", "$industrycode", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO rbc
          (username,server,industrycode)
          VALUES (?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$server", "$industrycode" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "ncb" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM ncb
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE ncb
          SET bankid=?,categorycode=?,poscond=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$bankid", "$categorycode", "$poscond", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO ncb
          (username,bankid,categorycode,poscond)
          VALUES (?,?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$bankid", "$categorycode", "$poscond" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "feds" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM feds
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE feds
          SET bankid=?,categorycode=?,poscond=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$bankid", "$categorycode", "$poscond", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO feds
          (username,bankid,categorycode,poscond)
          VALUES (?,?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$bankid", "$categorycode", "$poscond" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "rbs" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM rbs
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE rbs
          SET storeid=?,industrycode=?,sellerid=?,password=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$storeid", "$industrycode", "$sellerid", "$rbspassword", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO rbs
          (username,storeid,industrycode,sellerid,password)
          VALUES (?,?,?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$storeid", "$industrycode", "$sellerid", "$rbspassword" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "surefire" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM surefire
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE surefire
          SET username=?,password=?,account=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$password", "$account", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO surefire
          (username,password,account)
          VALUES (?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$password", "$account" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "sgs" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM sgs
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE sgs
          SET username=?,ipcode=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$ipcode", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO sgs
          (username,ipcode)
          VALUES (?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$ipcode" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "planetpay" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM planetpay
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    $sth = $dbh->prepare(
      q{
        UPDATE customers
        SET company=?,state=?,city=?,zip=?
        WHERE username=?
      }
      )
      or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
    $sth->execute( "$company", "$state", "$city", "$zip", "$username" ) or die "Can't execute: $DBI::errstr";

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE planetpay
          SET username=?,agentbank=?,agentchain=?,storenum=?,categorycode=?,terminalnum=?,bin=?,vnumber=?,industrycode=?,track=?,port=?,ipaddress=?,dcctype=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$agentbank", "$agentchain", "$storenum", "$categorycode", "$terminalnum", "$bin", "$vnumber", "$industrycode", "$track", "$port", "$ipaddress", "$dcctype", "$username" )
        or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO planetpay
          (username,agentbank,agentchain,storenum,categorycode,terminalnum,bin,vnumber,industrycode,track,port,ipaddress,dcctype)
          VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$agentbank", "$agentchain", "$storenum", "$categorycode", "$terminalnum", "$bin", "$vnumber", "$industrycode", "$track", "$port", "$ipaddress", "$dcctype" )
        or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "payvision" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM payvision
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE payvision
          SET memberid=?,memberguid=?,industrycode=?,allowavs=?,allowmarketdata=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$memberid", "$memberguid", "$industrycode", "$allowavs", "$allowmarketdata", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO payvision
          (username,memberid,memberguid,industrycode,allowavs,allowmarketdata)
          VALUES (?,?,?,?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$memberid", "$memberguid", "$industrycode", "$allowavs", "$allowmarketdata" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "pago" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM pago
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE pago
          SET clientname=?,saleschannel=?,branch=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$clientname", "$saleschannel", "$branch", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO pago
          (username,clientname,saleschannel,branch)
          VALUES (?,?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$clientname", "$saleschannel", "$branch" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "buypass" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM buypass
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE buypass
          SET username=?,industrycode=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$industrycode", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO buypass
          (username,industrycode)
          VALUES (?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$industrycode" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "cyberfns" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM cyberfns
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE cyberfns
          SET username=?,pin=?,ctype=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$pin", "$ctype", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO cyberfns
          (username,pin,ctype)
          VALUES (?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$pin", "$ctype" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "fdmsomaha" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM fdmsomaha
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE fdmsomaha
          SET username=?,batchtime=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$batchtime", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO fdmsomaha
          (username,batchtime)
          values (?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$batchtime" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "fdms" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM fdms
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE fdms
          SET username=?,batchtime=?,industrycode=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$batchtime", "$industrycode", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO fdms
          (username,batchtime,industrycode)
          VALUES (?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$batchtime", "$industrycode" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "epx" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM epx
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE epx
          SET username=?,bankid=?,dbanum=?,industrycode=?,allowmarketdata=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$bankid", "$dbanum", "$industrycode", "$allowmarketdata", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO epx
          (username,bankid,dbanum,industrycode,allowmarketdata)
          VALUES (?,?,?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$bankid", "$dbanum", "$industrycode", "$allowmarketdata" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "visanet" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM visanet
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    $sth = $dbh->prepare(
      q{
        UPDATE customers
        SET company=?,state=?,city=?
        WHERE username=?
      }
      )
      or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
    $sth->execute( "$company", "$state", "$city", "$username" ) or die "Can't execute: $DBI::errstr";

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE visanet
          SET username=?,agentbank=?,agentchain=?,storenum=?,categorycode=?,terminalnum=?,bin=?,vnumber=?,industrycode=?,track=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$agentbank", "$agentchain", "$storenum", "$categorycode", "$terminalnum", "$bin", "$vnumber", "$industrycode", "$track", "$username" )
        or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO visanet
          (username,agentbank,agentchain,storenum,categorycode,terminalnum,bin,vnumber,industrycode,track)
          VALUES (?,?,?,?,?,?,?,?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$agentbank", "$agentchain", "$storenum", "$categorycode", "$terminalnum", "$bin", "$vnumber", "$industrycode", "$track" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "cayman" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM cayman
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE cayman
          SET username=?,categorycode=?,industrycode=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$categorycode", "$industrycode", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO cayman
          (username,categorycode,industrycode)
          VALUES (?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$categorycode", "$industrycode" ) or die "Can't execute: $DBI::errstr";
    }
  }

  elsif ( $processor eq "mercury" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM mercury
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE mercury
          SET bankid=?,industrycode=?,acctvmemberid=?,acctmmemberid=?,acctglobalid=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$bankid", "$industrycode", "$acctvmemberid", "$acctmmemberid", "$acctglobalid", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO mercury
          (username,bankid,industrycode,acctvmemberid,acctmmemberid,acctglobalid)
          VALUES (?,?,?,?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$bankid", "$industrycode", "$acctvmemberid", "$acctmmemberid", "$acctglobalid" )
        or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "moneris" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM moneris
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE moneris
          SET username=?,industrycode=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$industrycode", "$username" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO moneris
          (username,industrycode)
          VALUES (?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$industrycode" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "gsopay" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM gsopay
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE gsopay
          SET username=?,password=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$gsopaypassword" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO gsopay
          (username,password)
          VALUES (?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$gsopaypassword" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "litle" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM litle
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE litle
          SET username=?,industrycode=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$industrycode" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO litle
          (username,industrycode)
          VALUES (?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$industrycode" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "securenet" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM securenet
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE securenet
          SET username=?,agentbank=?,agentchain=?,storenum=?,categorycode=?,terminalnum=?,bin=?,industrycode=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$agentbank", "$agentchain", "$storenum", "$categorycode", "$terminalnum", "$bin", "$industrycode" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO securenet
          (username,agentbank,agentchain,storenum,categorycode,terminalnum,bin,industrycode)
          VALUES (?,?,?,?,?,?,?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$agentbank", "$agentchain", "$storenum", "$categorycode", "$terminalnum", "$bin", "$industrycode" ) or die "Can't execute: $DBI::errstr";
    }
  } elsif ( $processor eq "universal" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM universal
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;
  } elsif ( $processor eq "firstcarib" ) {
    $sth = $dbh->prepare(
      q{
        SELECT username
        FROM firstcarib
        WHERE username=?
      }
      )
      or die "Can't prepare: $DBI::errstr";
    $sth->execute("$username") or die "Can't execute: $DBI::errstr";
    ($chkusername) = $sth->fetchrow;
    $sth->finish;

    if ( $chkusername ne "" ) {
      $sth = $dbh->prepare(
        q{
          UPDATE firstcarib
          SET username=?,industrycode=?
          WHERE username=?
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$industrycode" ) or die "Can't execute: $DBI::errstr";
    } else {
      $sth = $dbh->prepare(
        q{
          INSERT INTO firstcarib
          (username,industrycode)
          VALUES (?,?)
        }
        )
        or die "Content-Type: text/html\n\nCan't prepare: $DBI::errstr";
      $sth->execute( "$username", "$industrycode" ) or die "Can't execute: $DBI::errstr";
    }
  }

  $dbh->disconnect;
}

sub chargeback_import {
  require import_chargebacks;
  my $message = &import_chargebacks::import( 'reseller', "$query{'processor'}", $data );

  &response_page($message);
}

sub setup {
  my ( $mn, $partner, $curr_status, $submitted_pwrd, $loginEmail ) = @_;

  if ( $partner eq "AAAA" ) {
    $partner = "";
  }

  if ( $mn eq "" ) {
    return "Incorrect Syntax used.  Correct way is:  setup_merchant.pl USERNAME PARTNER\n";
  }

  if ( $partner =~ /emailonly/ ) {
    $mode    = "emailonly";
    $partner = "";
  } elsif ( $partner =~ /nopartner/ ) {
    $partner = "";
  }

  my $dbh = &miscutils::dbhconnect('pnpmisc');
  my $sth = $dbh->prepare(
    q{
      SELECT c.username,c.password,c.name,c.company,c.addr1,c.addr2,c.city,c.state,c.zip,c.country,c.tel,c.email,c.status,c.merchant_id,c.techemail,c.processor,c.merchemail,c.reseller,c.parentacct,c.subacct,c.proc_type,s.sendpwd,s.email,s.sendbillauth
      FROM customers c, salesforce s
      WHERE c.username=?
      AND s.username=c.reseller
    }
    )
    or die "Can't do: $DBI::errstr";
  $sth->execute($mn) or die "Can't execute: $DBI::errstr";
  ( $username, $password,    $name,      $company,   $addr1,      $addr2,    $city,       $state,   $zip,       $country, $tel,           $email,
    $status,   $merchant_id, $techemail, $processor, $merchemail, $reseller, $parentacct, $subacct, $proc_type, $sendpwd, $reselleremail, $sendbillauth
  )
    = $sth->fetchrow;

  $sth->finish();

  my $sth_merchants = $dbh->prepare(
    q{
      SELECT commonname,admindomain,emaildomain
      FROM privatelabel
      WHERE username=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth_merchants->execute("$reseller") or die "Can't execute: $DBI::errstr";
  ( $common_name, $admindomain, $emaildomain ) = $sth_merchants->fetchrow;
  $sth_merchants->finish;

  if ( $reseller::global_features->get('reseller_autolive') == 1 ) {
    $newstatus = "live";
    my ($date) = &miscutils::gendatetime_only();
    my $current_date = substr( $date, 0, 8 );
    $newstartdate = $current_date;
  } elsif ( $curr_status =~ /^(live|debug|hold)$/ ) {
    $newstatus = $curr_status;
  } else {
    $newstatus = 'debug';
  }

  if ( $emaildomain eq "" ) {
    $admindomain = "pay1.plugnpay.com";
    $emaildomain = "plugnpay.com";
    $common_name = "Plug & Pay Technologies, Inc.";
  }

  if ( $mode eq "emailonly" ) {
    &email();
    return;
  }

  # create a password if none was inputted
  my $password = $submitted_pwrd || new PlugNPay::Util::RandomString()->randomAlphaNumeric(16);

  $sth_merchants = $dbh->prepare(
    q{
      UPDATE customers
      SET status=?,startdate=?
      WHERE username=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth_merchants->execute( "$newstatus", "$newstartdate", "$username" ) or die "Can't execute: $DBI::errstr";
  $sth_merchants->finish;

  if ( substr( $username, 0, 3 ) =~ /^(ofx|cbs|cbb)/i ) {
    $tempflag = "0";
  } else {
    $tempflag = "1";
  }

  my $loginClient = new PlugNPay::Authentication::Login( { login => $username } );
  $loginClient->setRealm('PNPADMINID');

  my $exists = $loginClient->getLoginInfo();

  if (!$exists) {
    my $loginInfo = {
      account             => $username,
      password            => $password,
      passwordIsTemporary => $tempflag == 1 ? 1 : 0,
      securityLevel       => 0,
      directories => ['/admin']
    };
    my $result = $loginClient->createLogin($loginInfo);
    if (!$result) {
      print STDERR "Failed to create login for $username: " . $result->getError() . "\n";
    }
  }

  &email($tempflag,$password);

  if ( $sendbillauth ne "0" ) {
    &billauth_request;
  }

  return "autosetp=success\&password=$password\&status=$newstatus";
}

sub email {
  my ($tempflag,$password) = @_;

  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setGatewayAccount('reseller');
  $emailObj->setFormat('text');
  $emailObj->setTo($merchemail);
  $emailObj->setFrom( 'registration@' . $emaildomain );

  my $bccs = 'barbara@plugnpay.com,michelle@plugnpay.com';
  if ( $mode eq "emailonly" ) {
    $emailObj->setSubject("$username - Resend of Account Setup Information - Site Owner");
  } else {
    if ( $reseller eq "northame" ) {
      $bccs .= ',dataentry@nabancard.com';
    }

    if ( $sendpwd eq "1" ) {
      $emailObj->setCC($reselleremail);
    }
    $emailObj->setSubject("$username - Account Setup Information - Site Owner");
  }

  $emailObj->setBCC($bccs);

  my $emailmessage = '';

  if ( $reseller =~ /cardread/i ) {
    $emailmessage .= "Username: $username\n";
    $emailmessage .= "Password: $password\n\n";
    $emailmessage .= "Company:  $company\n\n";
    $emailmessage .= "Address:  $addr1\n";
    $emailmessage .= "City:     $city\n";
    $emailmessage .= "State:    $state\n";
    $emailmessage .= "Zip:      $zip\n";
  }

  else {
    $emailmessage .= "This is an Automated Broadcast Message to New Merchants.\n\n";
    $emailmessage .= "$company\n\n";
    $emailmessage .= "We want to welcome you to the $common_name secure eCommerce gateway.\n\n";
    $emailmessage .= "Please SAVE the following information for your records:\n\n";
    $emailmessage .= "username: $username\n";
    if ( $tempflag eq "1" ) {
      $emailmessage .= "Temporary password: $password\n\n";
      $emailmessage .= "The above password has been flagged as temporary and you will be required to choose a new one the first time you log in.";
      $emailmessage .= "We strongly encourage you to change it at your earliest convenience.  \n\n";
    } else {
      $emailmessage .= "password: $password\n\n";
    }
    $emailmessage .= "Go to our Administration server: https://$admindomain/admin and";
    $emailmessage .= " use the above Username and Password to login.\n";
    $emailmessage .= "This administration area is where you can view and manage your transactions.\n\n";

    if ( $reseller !~ /electro/ ) {
      $emailmessage .= "IMPORTANT - Please review the \"Getting Started Guide\" located in your administration area for";
      $emailmessage .= " information on how to use our services.\n\n";
    }

    if ( ( $reseller !~ /electro|webassis|optimalp/ ) ) {
      $emailmessage .= "Integration:\n";
      $emailmessage .= "Instructions on how to integrate the payment system onto your website are located at your Administration server.\n";
      $emailmessage .= "Click on the link labeled \"Integration\".\n\n";
    }

    $emailmessage .= "Technical Support:\n";
    $emailmessage .= "Click the \"Help Desk\" link on administration area located at";
    $emailmessage .= " https://$admindomain/admin\n";

    if ( ( $reseller !~ /webassis|optimalp/ ) ) {
      $emailmessage .= "Emergency Technical Support: Submit problem through \"Help Desk\" or email to: support\@$emaildomain\n\n";
    }

    #create hash of resellers that have payallflag = 1
    my %resellersThatPayAllHash = map { $_ => 1 } resellersThatPayAll();

    if ( !exists( $resellersThatPayAllHash{$reseller} ) ) {
      $emailmessage .= "Monthly Billing:\n";
      $emailmessage .= "Before your account will be activated you will need to choose a payment method.\n";
      $emailmessage .= "You can elect to pay the monthly fees by credit card or electronic ACH debit.\n";
      $emailmessage .= "To do this just click on the link labeled \"Billing Authorization\" ";
      $emailmessage .= "located at the bottom of the administration area at https://$admindomain/admin.\n\n";
      if ( $reseller =~ /webassis/ ) {
        $emailmessage .= "Your $common_name monthly bill will be sent to you via electronic mail.\n";
        $emailmessage .= "NOTE: The monthly fee will appear on your credit card or bank statement as being deducted by Plug'n Pay Technologies.\n\n";
      }
      $emailmessage .= "Your $common_name monthly bill will be sent to you via electronic mail.\n\n";
    }

    $emailmessage .= "Thank You for choosing us for your E-Commerce Solutions.\n\n";

    $emailmessage .= "Support Staff\n";

    $emailObj->setContent($emailmessage);
    $emailObj->send();
  }

  if ( $techemail ne "" ) {
    $emailObj->clear();
    $emailObj->setGatewayAccount($username);
    $emailObj->setFormat('text');
    $emailObj->setTo($techemail);
    $emailObj->setFrom( 'registration@' . $emaildomain );
    $emailObj->setSubject("$username - Integration Information - Tech. Contact");

    my $emailmessage = "";

    $emailmessage .= "This is an Automated Broadcast Message to new merchant Technical Support personnel.\n\n";

    $emailmessage .= "Dear Technical Support:\n\n";

    $emailmessage .= "Please SAVE the following information for your records:\n\n";

    $emailmessage .= "Username: $username\n";
    $emailmessage .= "Payment server: https://$admindomain/\n";
    $emailmessage .= "The password needed to access the Administration area has been sent to the site owner,";
    $emailmessage .= "  please contact them for this information\n";
    $emailmessage .= "Thank You for choosing us for your E-Commerce Solution.\n\n";
    $emailmessage .= "Support Staff\n";

    $emailObj->setContent($emailmessage);
    $emailObj->send();
  }
}

sub billauth_request {
  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setGatewayAccount('reseller');
  $emailObj->setFormat('text');
  $emailObj->setTo($email);
  $emailObj->setFrom( 'setup@' . $emaildomain );
  $emailObj->setSubject( $common_name . ' Billing Authorization-' . $username );

  my $emailmessage = '';
  $emailmessage .= "Dear Merchant\n";
  $emailmessage .= "\n";
  $emailmessage .= "To complete the setup of your $common_name account, we will require additional information.\n";
  $emailmessage .= "\n";
  $emailmessage .= "Before your account will be activated you will need to choose a payment\n";
  $emailmessage .= "method for your $common_name monthly fee.\n";
  $emailmessage .= "You can elect to pay the monthly fees by credit card or electronic debit.\n";
  $emailmessage .= "To do this just click on the link labeled \"Billing Authorization\" located at\n";
  $emailmessage .= "the bottom of the administration server at https://$admindomain/admin\n";
  $emailmessage .= "\n";
  $emailmessage .= "Your $common_name monthly bill will be sent to you via electronic mail.\n";
  $emailmessage .= "\n";
  $emailmessage .= "Thank you\n";
  $emailmessage .= "setup\@$emaildomain\n";

  $emailObj->setContent($emailmessage);
  $emailObj->send();
}

sub security {
  my ( $username, $reseller ) = @_;

  my $dbh = &miscutils::dbhconnect('pnpmisc');

  $sth = $dbh->prepare(
    q{
      SELECT username
      FROM customers
      WHERE username=?
      AND reseller=?
    }
    )
    or die "Can't prepare: $DBI::errstr";
  $sth->execute( "$username", "$reseller" ) or die "Can't execute: $DBI::errstr";
  my ($db_username) = $sth->fetchrow;
  $sth->finish;

  $dbh->disconnect;

  if ( ( $db_username eq "" ) && ( $ENV{'LOGIN'} !~ /^($reseller::tech_list)$/ ) ) {
    print "Content-Type: text/html\n\n";
    my $message = "Invalid Operation.";
    &response_page($message);
    exit;
  }
  return;
}

1;
