#!/usr/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use adyen;
use JSON;

#use Data::Dumper;
use PlugNPay::Environment;
use strict;

my $accountcode      = "";
my $acctholdercode   = "";
my $amount           = "";
my $bankuuid         = "";
my $batch_date       = "";
my $batch_number     = "";
my $batchdetreccnt   = "";
my $batchfilestr     = "";
my $batchid          = "";
my $batchnum         = "";
my $batchreccnt      = "";
my $batchretamt      = "";
my $batchretcnt      = "";
my $batchsalesamt    = "";
my $batchsalescnt    = "";
my $batchtotamt      = "";
my $batchtotcnt      = "";
my $checkstring      = "";
my $chkbatch_date    = "";
my $chkbatch_number  = "";
my $chkfinalstatus   = "";
my $chkstatus        = "";
my $cnt              = "";
my $count            = "";
my $currency         = "";
my $datetime         = "";
my $descr            = "";
my $errorrecseqnum   = "";
my $failflag         = "";
my $feeamt1          = "";
my $feeamt2          = "";
my $feeamt3          = "";
my $feecurrency      = "";
my $filedetreccnt    = "";
my $filename         = "";
my $filereccnt       = "";
my $fileretamt       = "";
my $fileretcnt       = "";
my $filesalesamt     = "";
my $filesalescnt     = "";
my $filetotamt       = "";
my $finalstatus      = "";
my $grosscredit      = "";
my $grossdebit       = "";
my $guid             = "";
my $httpcode         = "";
my $line             = "";
my $mcompany         = "";
my $merchantacct     = "";
my $merchantref      = "";
my $msg              = "";
my $mytime           = "";
my $netcredit        = "";
my $netdebit         = "";
my $networkdtxref    = "";
my $operation        = "";
my $operationstatus  = "";
my $orderid          = "";
my $outfilestr       = "";
my $passflag         = "";
my $payout_pw        = "";
my $payout_un        = "";
my $proc_type        = "";
my $rcode            = "";
my $reason           = "";
my $recseqnum        = "";
my $refnumber        = "";
my $report_pw        = "";
my $report_un        = "";
my $starttransdate   = "";
my $tcode            = "";
my $templen          = "";
my $terminal_id      = "";
my $trans_type       = "";
my $transamt         = "";
my $transdate        = "";
my $transid          = "";
my $url              = "";
my $workingbatchdate = "";
my $workingbatchnum  = "";
my %checkdup         = ();
my %datainfo         = ();
my %errorderid       = ();
my %fundarray        = ();
my %payoutcurr       = ();
my @batchfail        = ();
my @userarray        = ();

my $gobackdays = "16";

my $devprod = "logs";

my $username    = "";
my %payoutarray = ();

my $redobatchnum    = "";               # 191
my $redodate        = "";               # 20210903
my $redopayoutflag  = 0;                # 0
my $redofile        = "";               # leave empty
my $masterusername  = "anddonefee";
my @masteruserarray = ("anddonefee");

#$checkstring = "and t.username='anddonefee'";
#$redofile = "settlement_detail_report_batch_114.csv";
#$redodate = "20210916";
#$redobatchnum = "114";

#my $config = new PlugNPay::Environment()->get('CONFIG_NAME');
my $config = $ENV{'CONFIG_NAME'};

my $processor = new PlugNPay::Processor( { 'shortName' => 'adyen' } );
my $processor_id = $processor->getID();

if ( $config eq "getfiles_manual" ) {
  my $dbquerystr = <<"dbEOM";
      select processor_id,config,`key`,`value`
      from get_settlement_args
      where processor_id=?
      and config=?
dbEOM
  my @dbvalues = ( "$processor_id", "$config" );
  my @sthvalarray = &procutils::dbread( "adyen", "getfiles", "proc", $dbquerystr, @dbvalues );

  my %testarray = ();
  for ( my $vali = 0 ; $vali < scalar(@sthvalarray) ; $vali = $vali + 4 ) {
    my ( $processor_id, $config, $key, $value ) = @sthvalarray[ $vali .. $vali + 3 ];
    $testarray{"$processor_id $config $key"} = $value;
  }

  my $chkgobackdays = $testarray{"$processor_id $config gobackdays"};    # 6
  my $usernames     = $testarray{"$processor_id $config username"};      # testadyen  or  testadyen1,testadyen2

  if ( $usernames =~ /[^0-9a-z,]/ ) {
    print "usernames list has bad characters, exiting...\n";
    exit;
  }
  if ( $usernames =~ /,/ ) {
    $checkstring = $usernames;
    $checkstring =~ s/,/','/g;
    $checkstring = "'" . $checkstring . "'";
    $checkstring = " and t.username in ($checkstring)";
  } elsif ( $usernames ne "" ) {
    $checkstring = " and t.username='" . $usernames . "'";
  }

  if ( $chkgobackdays =~ /^[0-9]{1,3}$/ ) {
    $gobackdays = $chkgobackdays;
  }

  $redobatchnum   = $testarray{"$processor_id $config redobatchnum"};      # 191
  $redodate       = $testarray{"$processor_id $config redodate"};          # 20210903
  $redopayoutflag = $testarray{"$processor_id $config redopayoutflag"};    # 0
  if ( $redobatchnum =~ /^[0-9]{1,6}$/ ) {
    $redofile = "settlement_detail_report_batch_$redobatchnum.csv";
  }

  print "config: $config\n";
  print "checkstring: $checkstring\n";
  print "redofile: $redofile\n";
  print "gobackdays: $gobackdays\n";

}

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * $gobackdays ) );
my $onemonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 90 ) );
my $twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() + ( 3600 * 24 ) );
my $tomorrow = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 4 ) );
my $yesterday = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
my $julian = $julian + 1;
$julian = substr( "000" . $julian, -3, 3 );

my ( $batchorderid, $today, $ttime ) = &miscutils::genorderid();
my $todaytime = $ttime;

#&processnotification("","2021090315030900789");	# pspreference, orderid
#&processnotification("862630678168072C","");	# pspreference, orderid
#&processnotification("","");	# pspreference, orderid

if ( $redodate ne "" ) {
  $today = $redodate;
}

my $fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
my $filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
my $fileyearonly = substr( $today, 0, 4 );

if ( $redofile ne "" ) {
  my $dbquerystr = <<"dbEOM";
        select merchant_id,pubsecret,proc_type,status,company
        from customers
        where username=?
dbEOM
  my @dbvalues = ("$masterusername");
  ( $accountcode, $terminal_id, $proc_type, $chkstatus, $mcompany ) = &procutils::dbread( $masterusername, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $dbquerystr = <<"dbEOM";
        select merchantacct,report_un,report_pw,payout_un,payout_pw,acctholdercode,bankuuid,batch_date,batch_number
        from adyen
        where username=?
dbEOM
  my @dbvalues = ("$masterusername");
  ( $merchantacct, $report_un, $report_pw, $payout_un, $payout_pw, $acctholdercode, $bankuuid, $batch_date, $batch_number ) =
    &procutils::merchread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( $merchantacct eq "" ) {
    print "no merchantacct\n";
    exit;
  }

  $workingbatchnum  = $redobatchnum;
  $workingbatchdate = $redodate;

  print "old batch info: $batch_date $batch_number\n";
  print "working batch info: $workingbatchdate $workingbatchnum\n";

  my $httpcode = &getresults("$redofile");

  if ( $httpcode eq "200" ) {
    &processfile("$redofile");
    &updatebatchnum($masterusername);

    #if ($payoutarray{$username} ne "") {
    #  &sendpayout("$username","$payoutcurr{$username} $payoutarray{$username}");
    #}
  } else {
    print "httpcode: $httpcode\n";

    if ( (0) && ( $batch_date < $today ) ) {
      open( MAIL, "| /usr/lib/sendmail -t" );
      print MAIL "To: cprice\@plugnpay.com\n";
      print MAIL "From: dcprice\@plugnpay.com\n";
      print MAIL "Subject: adyen - genfiles error\n";
      print MAIL "\n";
      print MAIL "No file for today\n";
      print MAIL "masterusername: $masterusername\n\n";
      print MAIL "filename: $filename\n\n";
      print MAIL "httpcode: $httpcode\n\n";
      close(MAIL);
    }
  }

  exit;
}

$batchid = $batchorderid;

umask 0077;

if ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) {
  &procutils::filewrite( "$masterusername", "adyen", "/home/pay1/batchfiles/$devprod/adyen", "batchfile.txt", "write", "", "" );
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'adyen/genfiles.pl'`;
if ( $cnt > 1 ) {
  my $printstr = "genfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$masterusername", "adyen", "/home/pay1/batchfiles/$devprod/adyen", "miscdebug.txt", "append", "misc", $printstr );

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: adyen - genfiles already running\n";
  print MAILERR "\n";
  print MAILERR "Exiting out of genfiles.pl because it's already running.\n\n";
  close MAILERR;

  exit;
}

#%returncodes = ();

#my $dbquerystr = <<"dbEOM";
#        select t.username,count(t.username),min(o.trans_date)
#        from trans_log t, operation_log o
#        where t.trans_date>=?
#        and t.finalstatus='pending'
#        and (t.duplicate is NULL or t.duplicate='')
#        and (t.accttype is NULL or t.accttype='')
#        and o.orderid=t.orderid
#        and o.username=t.username
#        and o.trans_date>=?
#        and o.processor='adyen'
#        and o.lastopstatus in ('pending','locked')
#        group by t.username
#dbEOM
#my @dbvalues = ("$onemonthsago","$twomonthsago");
##print "dbvalues $checkstring  $onemonthsago  $twomonthsago\n";
#my @sthvalarray = &procutils::dbread($masterusername,$orderid,"pnpdata",$dbquerystr,@dbvalues);
#
#for (my $vali=0; $vali<scalar(@sthvalarray); $vali=$vali+3) {
#  ($username,$count,$starttransdate) = @sthvalarray[$vali .. $vali+2];
#
#  @userarray = (@userarray,$username);
#}

foreach $masterusername (@masteruserarray) {
  if ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) {
    &procutils::filewrite( "$masterusername", "adyen", "/home/pay1/batchfiles/$devprod/adyen", "batchfile.txt", "write", "", "" );
    last;
  }

  print "masterusername: $masterusername\n";

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$masterusername\n";
  &procutils::filewrite( "$masterusername", "adyen", "/home/pay1/batchfiles/$devprod/adyen", "genfiles.txt", "write", "", $batchfilestr );

  umask 0033;
  $batchfilestr = "";
  $batchfilestr .= "$masterusername\n";
  &procutils::filewrite( "$masterusername", "adyen", "/home/pay1/batchfiles/$devprod/adyen", "batchfile.txt", "write", "", $batchfilestr );

  %checkdup = ();

  my $dbquerystr = <<"dbEOM";
        select merchant_id,pubsecret,proc_type,status,company
        from customers
        where username=?
dbEOM
  my @dbvalues = ("$masterusername");
  ( $accountcode, $terminal_id, $proc_type, $chkstatus, $mcompany ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( $chkstatus ne "live" ) {
    next;
  }

  my $dbquerystr = <<"dbEOM";
        select merchantacct,report_un,report_pw,payout_un,payout_pw,acctholdercode,bankuuid,batch_date,batch_number
        from adyen
        where username=?
dbEOM
  my @dbvalues = ("$masterusername");
  ( $merchantacct, $report_un, $report_pw, $payout_un, $payout_pw, $acctholdercode, $bankuuid, $batch_date, $batch_number ) =
    &procutils::merchread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $workingbatchnum = $batch_number;

  if ( $merchantacct eq "" ) {
    print "no merchantacct\n";
    next;
  }

  print "old batch info: $batch_date $batch_number\n";

  for ( my $ii = 0 ; $ii < 30 ; $ii++ ) {
    $workingbatchnum  = $workingbatchnum + 1;
    $workingbatchdate = $today;

    print "working batch info: $workingbatchdate $workingbatchnum\n";
    $filename = "settlement_detail_report_batch_$workingbatchnum.csv";

    # update transaction status automatically
    print "get latest results\n";

    my $httpcode = &getresults("$filename");    # orderid, transid

    if ( $httpcode eq "200" ) {
      &processfile("$filename");
      &updatebatchnum($masterusername);
      if ( $payoutarray{$masterusername} ne "" ) {

        #&sendpayout("$masterusername","$payoutcurr{$username} $payoutarray{$username}");
      }
    } else {
      print "httpcode: $httpcode\n";

      if ( (0) && ( $batch_date < $today ) ) {
        open( MAIL, "| /usr/lib/sendmail -t" );
        print MAIL "To: cprice\@plugnpay.com\n";
        print MAIL "From: dcprice\@plugnpay.com\n";
        print MAIL "Subject: adyen - genfiles error\n";
        print MAIL "\n";
        print MAIL "No file for today\n";
        print MAIL "masterusername: $masterusername\n\n";
        print MAIL "filename: $filename\n\n";
        print MAIL "httpcode: $httpcode\n\n";
        close(MAIL);
      }
    }

    if ( $httpcode ne "200" ) {
      print "done with $masterusername\n\n";
      last;
    }
  }

}

&procutils::filewrite( "$masterusername", "adyen", "/home/pay1/batchfiles/$devprod/adyen", "batchfile.txt", "write", "", "" );

umask 0033;
$batchfilestr = "";
&procutils::filewrite( "$masterusername", "adyen", "/home/pay1/batchfiles/$devprod/adyen", "genfiles.txt", "write", "", $batchfilestr );

#system("/home/pay1/batchfiles/$devprod/adyen/putfiles.pl >> /home/pay1/batchfiles/$devprod/adyen/ftplog.txt 2>\&1");

exit;

sub getresults {
  my ($filename) = @_;

  print "in getresults\n";

  my %transarray = ();

  $batchdetreccnt++;
  $filedetreccnt++;
  $batchreccnt++;
  $filereccnt++;
  $recseqnum++;

  $recseqnum = substr( "0" x 7 . $recseqnum, -7, 7 );
  $transamt = sprintf( "%d", ( $transamt * 100 ) + .0001 );

  if ( $tcode =~ /^(27|37)$/ ) {
    $batchsalesamt = $batchsalesamt + $transamt;
    $batchsalescnt = $batchsalescnt + 1;
    $filesalesamt  = $filesalesamt + $transamt;
    $filesalescnt  = $filesalescnt + 1;
  } else {
    $batchretamt = $batchretamt + $transamt;
    $batchretcnt = $batchretcnt + 1;
    $fileretamt  = $fileretamt + $transamt;
    $fileretcnt  = $fileretcnt + 1;
  }
  $batchtotamt = $batchtotamt + $transamt;
  $batchtotcnt = $batchtotcnt + 1;
  $filetotamt  = $filetotamt + $transamt;

  if ( $masterusername =~ /^test/ ) {
    $url = "https:\/\/ca-test.adyen.com\/reports\/download\/MerchantAccount\/$merchantacct\/$filename";
  } else {
    $url = "https:\/\/ca-live.adyen.com\/reports\/download\/MerchantAccount\/$merchantacct\/$filename";
  }
  $url =~ s/^https:\/\///;
  my $host = $url;
  $host =~ s/\/.*$//g;
  my $path = $url;
  $path =~ s/^.*?\//\//;
  my $port = "443";

  my $message = "";

  my ( $response, $header, %resulthash ) = &sendmessage( "$message", "$host", "$port", "$path" );

  # _HTTP_CODE: 200
  # _HTTP_REASON: 200

  print "response: $response\n";
  print "header: $header\n";
  foreach my $key ( sort keys %resulthash ) {
    print "key  $key  $resulthash{$key}\n";
  }

  $httpcode = "";
  if ( $header =~ /_HTTP_CODE: ([0-9]+)/ ) {
    $httpcode = $1;    # 401 unauthorized, 404 not found
  } else {
    $httpcode = $resulthash{'MErrMsg'};
    $header   = $resulthash{'MErrMsg'};
  }
  print "ahttpcode: $httpcode\n";

  $mytime     = gmtime( time() );
  $outfilestr = "";
  if ( ( $httpcode eq "200" ) || ( $response =~ /,.*,.*,.*,/ ) ) {
    $outfilestr .= "$response\n";
    $httpcode = "200";
  } else {
    $outfilestr .= "$header\n";
  }
  print "aaaa $outfilestr aaaa\n";

  # fileencwrite
  if ( length($outfilestr) > 1 ) {
    my $status = &procutils::fileencwrite( "$masterusername", "adyen", "/home/pay1/batchfiles/$devprod/adyen/$fileyear", "$masterusername$filename", "write", "", $outfilestr );

    my $printstr = "fileencwrite: /home/pay1/batchfiles/$devprod/adyen/$masterusername$filename\n";
    $printstr .= "fileencwrite status: $status\n\n";
    &procutils::filewrite( "$masterusername", "adyen", "/home/pay1/batchfiles/$devprod/adyen", "ftplog.txt", "append", "misc", $printstr );

    print "after fileencwrite /home/pay1/batchfiles/$devprod/adyen/$fileyear/$masterusername$filename\n";
  }

  return $httpcode;
}

sub updatebatchnum {
  my ($updusername) = @_;

  print "in updatebatchnum\n";

  my $dbquerystr = <<"dbEOM";
        select batch_date,batch_number
        from adyen
        where username=?
dbEOM
  my @dbvalues = ("$updusername");
  ( $chkbatch_date, $chkbatch_number ) = &procutils::merchread( $updusername, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  if ( ( $workingbatchdate < $chkbatch_date ) || ( $workingbatchnum < $chkbatch_number ) ) {
    print "batch_number not updated\n";
    return;
  }

  my $dbquerystr = <<"dbEOM";
        update adyen
        set batch_date=?,batch_number=?
        where username=?
dbEOM
  my @dbvalues = ( "$workingbatchdate", "$workingbatchnum", "$updusername" );
  &procutils::merchupdate( $updusername, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  print "supposed new batch info: $today $workingbatchnum\n";

  # for debug only
  my $dbquerystr = <<"dbEOM";
        select batch_date,batch_number
        from adyen
        where username=?
dbEOM
  my @dbvalues = ("$updusername");
  ( $chkbatch_date, $chkbatch_number ) = &procutils::merchread( $updusername, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  print "new batch info: $chkbatch_date $chkbatch_number\n";

}

sub sendmessage {
  my ( $msg, $host, $port, $path ) = @_;

  #$adyen::mytime = gmtime(time());
  #open(logfile,">>/home/pay1/batchfiles/$adyen::devprod/adyen/serverloadyengtest.txt");
  #print logfile "$adyen::username  $adyen::datainfo{'order-id'}  $shacardnumber 3 $adyen::datainfo{'refnumber'}\n";
  #print logfile "$adyen::mytime send: $adyen::username $messagestr\n\n";
  #close(logfile);

  #my ($response,$header) = &adyen::sslsocketwrite("$msg","$host","$port","$path","$action");
  #my ($msg,$host,$port,$path,$action) = @_;

  my $len = length($msg);

  my $port = "443";

  my $msg = "GET $path HTTP/1.1\r\n";

  #$msg .= "X-API-KEY: $api_key\r\n";
  #$msg .= "Host: $host\r\n";
  #$msg .= "Authorization: Basic " . &MIME::Base64::encode("$un:$pw","") . "\r\n";
  #$msg .= "Accept: */*\r\n\r\n";

  my $header     = "";
  my %sslheaders = ();
  $sslheaders{'Host'} = "$host";

  #$sslheaders{'X-API-KEY'} = "$report_api_key";
  #$sslheaders{'X-CLIENT-KEY'} = "test_3Z6O7K6JVVF5DIN4QBF2ZYZGAUQS5SKV";
  $sslheaders{'Authorization'} = "Basic " . &MIME::Base64::encode( "$report_un:$report_pw", "" );

  #$sslheaders{'Content-Length'} = $len;
  #$sslheaders{'Content-Type'} = 'application/json; charset=utf-8';

  #print "report_api_key: $report_api_key\n";
  #print "report_un: $report_un\n";
  #print "report_pw: $report_pw\n";
  #print "host: $host\n";
  #print "port: $port\n";
  print "path: $path\n";
  print "msg: $msg\n";

  my $printstr = "path: $path\n";
  $printstr .= "msg: $path\n\n";
  &procutils::filewrite( "$masterusername", "adyen", "/home/pay1/batchfiles/$devprod/adyen", "ftplog.txt", "append", "misc", $printstr );

  my ( $response, $d1, %resulthash ) = &procutils::sendsslmsg( "processor_adyen", $host, $port, $path, $msg, "lwp,timeout=20", %sslheaders );

  #my ($response) = &procutils::sendsslmsg("processor_adyen",$host,"$port",$path,$msg,"nopost,got=\}",%sslheaders);

  #foreach my $key (sort keys %resulthash) {
  #  print "aa $key  bb $resulthash{$key}\n";
  #}

  #print "$response\n";
  #print "$resulthash{'headers'}\n";

  return $response, $resulthash{"headers"}, %resulthash;

}

sub findtransaction {
  my ( $findusername, $transid, $refnumber, $trans_type, $transdate ) = @_;

  $transdate = substr( $refnumber, 0, 8 );

  if ( ( $transdate < "20180101" ) || ( $transdate > 22000000 ) ) {
    return "";
  }

  my $dbquerystr = <<"dbEOM";
          select orderid,lastop,trans_date,lastoptime,lastopstatus,card_name
          from operation_log
          where trans_date=?
          and username=?
          and refnumber=?
          and lastop in ('auth','return')
          and lastopstatus not in ('badcard','problem') 
          and (accttype is NULL or accttype='')
dbEOM
  my @dbvalues = ( "$transdate", "$findusername", "$refnumber" );
  my ( $orderid, $operation, $trans_date, $trans_time, $lastopstatus, $card_name ) = &procutils::dbread( $findusername, $orderid, "pnpdata", $dbquerystr, @dbvalues );

  my $printstr = "aaaa $orderid bbbb $operation $lastopstatus\n";
  &procutils::filewrite( "$findusername", "adyen", "/home/pay1/batchfiles/$devprod/adyen", "miscdebug.txt", "append", "misc", $printstr );

  return $orderid, $operation, $lastopstatus, $card_name;
}

sub getdates {
  my ($transdate) = @_;

  my @datearray = ();
  $datearray[0] = &subtractoneday($transdate);
  $datearray[1] = &subtractoneday( $datearray[0] );
  $datearray[2] = &subtractoneday( $datearray[1] );
  $datearray[3] = &subtractoneday( $datearray[2] );
  $datearray[4] = &subtractoneday( $datearray[3] );
  $datearray[5] = &subtractoneday( $datearray[4] );
  $datearray[6] = &subtractoneday( $datearray[5] );

  return @datearray;

}

sub subtractoneday {
  my ($transdate) = @_;

  #my $year = substr($transdate,0,4);
  #my $month = substr($transdate,4,2);
  #my $day = substr($transdate,6,2);

  my $timenum = &miscutils::strtotime( $transdate . "000000" );
  $timenum = $timenum - ( 3600 * 24 );
  $transdate = &miscutils::timetostr($timenum);

  return $transdate;

}

sub createmessage {
  my (@transaction) = @_;

  my $message = "{";
  my $indent  = 0;
  foreach my $var (@transaction) {
    if ( $var ne "" ) {
      $message .= $var . ",";
    }
  }
  chop $message;
  $message .= "}";

  return $message;
}

sub processnotification {
  my ( $pspreference, $orderid ) = @_;

  my $host = "proc-adyen.local";

  #if ($username =~ /^test/) {
  #  $host = "checkout-test.adyen.com";
  #}
  my $port = "28442";
  my $port = "80";

  my $accountcode     = "8516263595604518";
  my $merchantaccount = "AndDone";

  # send fake json to /notify
  if (0) {
    my ( $oid, $date, $datetime ) = &miscutils::genorderid();

    my $eventDate =
        substr( $datetime, 0, 4 ) . '-'
      . substr( $datetime, 4,  2 ) . '-'
      . substr( $datetime, 6,  2 ) . 'T'
      . substr( $datetime, 8,  2 ) . ':'
      . substr( $datetime, 10, 2 ) . ':'
      . substr( $datetime, 12, 2 )
      . '+00:00';

    my $fakenotification =
      '{ "live": "false", "notificationItems": [ { "NotificationRequestItem": { "additionalData": { "modification.action": "cancel" }, "amount": { "currency": "EUR", "value": 1000 }, "eventCode": "CANCEL_OR_REFUND", "eventDate": "'
      . $eventDate
      . '", "merchantAccountCode": "8516263595604518", "merchantReference": "2021080917473114108", "originalReference": "9913140798220028", "paymentMethod": "visa", "pspReference": "883628531255268B", "reason": "", "success": "true" } } ] }';

#my $fakenotification = '{ "live": "false", "notificationItems": [ { "NotificationRequestItem": { "additionalData": { "modification.action": "cancel" }, "amount": { "currency": "EUR", "value": 1000 }, "eventCode": "CANCEL_OR_REFUND", "eventDate": "2021-01-01T01:00:00+01:00", "merchantAccountCode": "8516263595604518", "merchantReference": "2021080917473114108", "originalReference": "9913140798220028", "paymentMethod": "visa", "pspReference": "883628531255268B", "reason": "", "success": "true" } } ] }';

#notification: {"NotificationRequestItem":{"additionalData":{"modification.action":"cancel"},"amount":{"currency":"EUR","value":1000},"eventCode":"CANCEL_OR_REFUND","eventDate":"2021-08-24T15:33:25+00:00","merchantAccountCode":"8516263595604518","merchantReference":"2021080917473114108","originalReference":"9913140798220028","paymentMethod":"visa","pspReference":"883628531255268B","reason":"","success":"true"}}

    my $msg = $fakenotification;

    my $len    = length($msg);
    my $header = "";
    my $path   = "/notify";

    my %sslheaders = ();
    $sslheaders{'Host'}           = "$host";
    $sslheaders{'Content-Length'} = $len;
    $sslheaders{'Content-Type'}   = 'application/json; charset=utf-8';
    my ( $response, $header, %resulthash ) = &procutils::sendsslmsg( "processor_adyen", $host, $port, $path, $msg, "nossl", %sslheaders );

    print "header: $header\n\n";
    print "response: $response\n\n";
  }

  # request notification contents
  my @transaction = ();

  my $sincedate = "20210801010000";
  my $since =
      substr( $sincedate, 0, 4 ) . '-'
    . substr( $sincedate, 4,  2 ) . '-'
    . substr( $sincedate, 6,  2 ) . 'T'
    . substr( $sincedate, 8,  2 ) . ':'
    . substr( $sincedate, 10, 2 ) . ':'
    . substr( $sincedate, 12, 2 ) . "Z";

  if ( $pspreference ne "" ) {
    $transaction[0] = "\"pspReference\":\"$pspreference\"";
    $transaction[1] = "\"wait\":5000";                                  # wait for up to x seconds for a notification to arrive
                                                                        #$transaction[2] = "\"since\":\"yyy\"";	# "2021-08-21T09:35:26Z"
    $transaction[3] = "\"new\":false";                                  # default is true, only give new info
    $transaction[4] = "\"merchantAccountCode\":\"$merchantaccount\"";

    #$transaction[5] = "\"merchantReference\":\"$orderid\"";
  } elsif ( $orderid ne "" ) {

    #$transaction[0] = "\"pspReference\":\"$pspreference\"";
    $transaction[1] = "\"wait\":2000";                                  # wait for up to x milliseconds for a notification to arrive
    $transaction[2] = "\"since\":\"$since\"";                           # "2021-08-21T09:35:26Z"
    $transaction[3] = "\"new\":false";                                  # default is true, only give new info
    $transaction[4] = "\"merchantAccountCode\":\"$merchantaccount\"";
    $transaction[5] = "\"merchantReference\":\"$orderid\"";
  } else {

    #$transaction[0] = "\"pspReference\":\"$pspreference\"";
    $transaction[1] = "\"wait\":2000";                                  # wait for up to x milliseconds for a notification to arrive
    $transaction[2] = "\"since\":\"$since\"";                           # "2021-08-21T09:35:26Z"
    $transaction[3] = "\"new\":false";                                  # default is true, only give new info
    $transaction[4] = "\"merchantAccountCode\":\"$merchantaccount\"";

    #$transaction[5] = "\"merchantReference\":\"$orderid\"";
  }

  my $msg = &createmessage(@transaction);

  print "send: $msg\n\n";

  my $len    = length($msg);
  my $header = "";
  my $path   = "/request";

  my %sslheaders = ();
  $sslheaders{'Host'}           = "$host";
  $sslheaders{'Content-Length'} = $len;
  $sslheaders{'Content-Type'}   = 'application/json; charset=utf-8';
  my ( $response, $header, %resulthash ) = &procutils::sendsslmsg( "processor_adyen", $host, $port, $path, $msg, "lwp,nossl", %sslheaders );

#my $response = '{"timedOut":true,"notifications":[{"guid":"fb5586ee-efc5-45e2-8f7d-41bb396f7e2a","notification":"{\"NotificationRequestItem\":{\"additionalData\":{\"modification.action\":\"cancel\"},\"amount\":{\"currency\":\"EUR\",\"value\":1000},\"eventCode\":\"CANCEL_OR_REFUND\",\"eventDate\":\"2021-08-24T15:33:25+00:00\",\"merchantAccountCode\":\"8516263595604518\",\"merchantReference\":\"2021080917473114108\",\"originalReference\":\"9913140798220028\",\"paymentMethod\":\"visa\",\"pspReference\":\"883628531255268B\",\"reason\":\"\",\"success\":\"true\"}}","NotificationKeyDataPoints":{"eventCode":"CANCEL_OR_REFUND","eventDate":"2021-08-24T15:33:25Z","merchantAccountCode":"8516263595604518","merchantReference":"2021080917473114108","pspReference":"883628531255268B","confirmed":0}}],"count":1}';

  print "header: $header\n\n";
  print "resulthash: $resulthash{MErrMsg}\n\n";
  print "recv: $response\n\n";

# {"timedOut":false,"notifications":[{"guid":"4880cb27-c2ad-4b1d-9ac5-a3a844fbe72b","notification":"{\"NotificationRequestItem\":{\"additionalData\":{\" NAME1 \":\"VALUE1\",\"NAME2\":\"  VALUE2  \",\"authCode\":\"1234\",\"cardSummary\":\"7777\",\"expiryDate\":\"12/2012\",\"fraudCheck-6-ShopperIpUsage\":\"10\",\"hmacSignature\":\"2E4vqn1by9fbV/TJ/3CQHCSVobVrb5ZuKEx3N3pjO38=\",\"totalFraudScore\":\"10\"},\"amount\":{\"currency\":\"EUR\",\"value\":10100},\"eventCode\":\"AUTHORISATION\",\"eventDate\":\"2021-09-01T19:28:37+02:00\",\"merchantAccountCode\":\"AndDone\",\"merchantReference\":\"8313842560770001\",\"operations\":[\"CANCEL\",\"CAPTURE\",\"REFUND\"],\"paymentMethod\":\"visa\",\"pspReference\":\"test_AUTHORISATION_1\",\"reason\":\"1234:7777:12/2012\",\"success\":\"true\"}}","NotificationKeyDataPoints":{"eventCode":"AUTHORISATION","eventDate":"2021-09-01T17:28:37Z","merchantAccountCode":"AndDone","merchantReference":"8313842560770001","pspReference":"test_AUTHORISATI","confirmed":0,"live":"false"}},{"guid":"945595e0-b219-4b92-bd10-bd686e6b41c4","notification":"{\"NotificationRequestItem\":{\"additionalData\":{\" NAME1 \":\"VALUE1\",\"NAME2\":\"  VALUE2  \",\"authCode\":\"1234\",\"cardSummary\":\"7777\",\"expiryDate\":\"12/2012\",\"fraudCheck-6-ShopperIpUsage\":\"10\",\"hmacSignature\":\"k4k8mYQktgogoPYKAGsTMIzkw75qyPuJ/1ySfmaI7WM=\",\"totalFraudScore\":\"10\"},\"amount\":{\"currency\":\"GBP\",\"value\":20100},\"eventCode\":\"AUTHORISATION\",\"eventDate\":\"2021-09-01T19:28:37+02:00\",\"merchantAccountCode\":\"AndDone\",\"merchantReference\":\"8313842560770001\",\"operations\":[\"CANCEL\",\"CAPTURE\",\"REFUND\"],\"paymentMethod\":\"visa\",\"pspReference\":\"test_AUTHORISATION_2\",\"reason\":\"1234:7777:12/2012\",\"success\":\"true\"}}","NotificationKeyDataPoints":{"eventCode":"AUTHORISATION","eventDate":"2021-09-01T17:28:37Z","merchantAccountCode":"AndDone","merchantReference":"8

  my $jsonmsg = &JSON::decode_json($response);

  my $timedout = $jsonmsg->{"timedOut"};    # true false
  my $count    = $jsonmsg->{"count"};       # 1

  if ( $count < 1 ) {
    print "no notifications\n";
    return;
  }

  for ( my $cntidx = 0 ; $cntidx < $count ; $cntidx++ ) {
    my @notifications = $jsonmsg->{"notifications"};
    my $notification  = $jsonmsg->{"notifications"}->[$cntidx]->{"notification"};
    my $guid          = $jsonmsg->{"notifications"}->[0]->{"guid"};

    my $jsonmsg = &JSON::decode_json($notification);

    my $success            = $jsonmsg->{"NotificationRequestItem"}->{"success"};
    my $orderid            = $jsonmsg->{"NotificationRequestItem"}->{"merchantReference"};
    my $origref            = $jsonmsg->{"NotificationRequestItem"}->{"originalReference"};
    my $merchantacctcode   = $jsonmsg->{"NotificationRequestItem"}->{"merchantAccountCode"};
    my $eventcode          = $jsonmsg->{"NotificationRequestItem"}->{"eventCode"};
    my $eventdate          = $jsonmsg->{"NotificationRequestItem"}->{"eventDate"};
    my $paymentmethod      = $jsonmsg->{"NotificationRequestItem"}->{"paymentMethod"};
    my $pspreference       = $jsonmsg->{"NotificationRequestItem"}->{"pspReference"};
    my $merchantreference  = $jsonmsg->{"NotificationRequestItem"}->{"merchantReference"};
    my $descr              = $jsonmsg->{"NotificationRequestItem"}->{"reason"};
    my $modificationaction = $jsonmsg->{"NotificationRequestItem"}->{"additionalData"}->{"modification.action"};      # cancel
    my $authcode           = $jsonmsg->{"NotificationRequestItem"}->{"additionalData"}->{"authCode"};                 # cancel
                                                                                                                      #my $currency = $jsonmsg->{"NotificationRequestItem"}->{"amount"}->{"currency"}; # USD
                                                                                                                      #my $amount = $jsonmsg->{"NotificationRequestItem"}->{"amount"}->{"value"}; # 1000
    my $currency           = $jsonmsg->{"NotificationRequestItem"}->{"additionalData"}->{"authorisedAmountCurrency"};
    my $amount             = $jsonmsg->{"NotificationRequestItem"}->{"additionalData"}->{"authorisedAmountValue"};

    print "success: $success\n";
    print "modificationaction: $modificationaction\n";
    print "orderid: $orderid\n";
    print "origref: $origref\n";
    print "merchantacctcode: $merchantacctcode\n";
    print "eventcode: $eventcode\n";
    print "eventdate: $eventdate\n";
    print "paymentmethod: $paymentmethod\n";
    print "merchantreference: $merchantreference\n";
    print "pspreference: $pspreference\n";
    print "reason: $reason\n";
    print "currency: $currency\n";
    print "amount: $amount\n";
    print "authcode: $authcode\n\n";

    my $dbquerystr = <<"dbEOM";
        select username
        from operation_log
        where orderid=?
        and refnumber=?
dbEOM
    my @dbvalues = ( "$merchantreference", "$pspreference" );
    ($username) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    print "$username $orderid $eventcode $success $eventdate $paymentmethod $reason $currency $amount $authcode\n";
    if (1) {

      if ( ( $username ne "" ) && ( $orderid ne "" ) ) {
        my $dbquerystr = <<"dbEOM";
          select operation,finalstatus,auth_code
          from trans_log
          where orderid=?
          and username=?
          and finalstatus in ('pending','locked','success')
          and (duplicate is NULL or duplicate='')
          order by batch_time
dbEOM
        my @dbvalues = ( "$merchantref", "$username" );
        my @sth_statusvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

        my %oparray       = ();
        my %authcodearray = ();
        my $networktxref  = "";
        for ( my $vali = 0 ; $vali < scalar(@sth_statusvalarray) ; $vali = $vali + 3 ) {
          my ( $op, $fs, $auth_code ) = @sth_statusvalarray[ $vali .. $vali + 2 ];
          $oparray{"$op"}       = $fs;
          $authcodearray{"$op"} = $auth_code;
          print "oparray: $op $fs\n";
        }

        my %ophash = (
          'CANCEL_OR_REFUND', 'void',     'CANCELLATION',        'void',     'AUTHORISATION', 'auth',   'AUTHORISATION_ADJUSTMENT', 'reauth',
          'CAPTURE',          'postauth', 'CAPTURE_FAILED',      'postauth', 'REFUND',        'return', 'REFUND_REVERSED',          'void',
          'TECHNICAL_CANCEL', 'xxxx',     'VOID_PENDING_REFUND', 'void',
        );

        my $operation = $ophash{"$eventcode"};
        print "operation: $operation\n";

        my $updateop    = "";
        my $finalstatus = "";
        if ( ( $operation eq "void" ) && ( $success eq "true" ) ) {
          $updateop    = "void";
          $finalstatus = "success";
        } elsif ( ( $operation =~ /^(auth|postauth|reauth|return)$/ ) && ( $success eq "true" ) ) {
          $updateop     = "$operation";
          $finalstatus  = "success";
          $networktxref = substr( $authcodearray{"$operation"}, 6, 15 );
          if ( length($authcode) == 6 ) {
            $authcode = $authcode . $networkdtxref;
          }
        } elsif ( ( $operation =~ /^(auth|postauth|reauth|return)$/ ) && ( $success eq "false" ) ) {
          $updateop    = "$operation";
          $finalstatus = "badcard";
        }

        print "todaytime: $todaytime\n";
        print "orderid: $orderid  updateop: $updateop finalstatus: $finalstatus  descr: $descr\n";

        if ( ( $orderid ne "" ) && ( $updateop ne "" ) && ( $updateop ne "xxxx" ) ) {
          my $dbquerystr = <<"dbEOM";
            update trans_log
            set finalstatus=?,descr=?,result=?
            where orderid=?
            and username=?
            and operation=?
            and (duplicate is NULL or duplicate='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
          my @dbvalues = ( "$finalstatus", "$descr", "$todaytime", "$orderid", "$username", "$updateop" );
          &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

          $dbquerystr =~ s/\n/ /g;
          $dbquerystr =~ s/    / /g;
          print "\n$dbquerystr\n";
          foreach my $var (@dbvalues) {
            print "$var  ";
          }
          print "\n\n";

          $operationstatus = $updateop . "status";

          %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
          my $dbquerystr = <<"dbEOM";
            update operation_log set $operationstatus=?,batchnum=?
            where orderid=?
            and username=?
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
          my @dbvalues = ( "$finalstatus", "$todaytime", "$orderid", "$username" );
          &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
          $dbquerystr =~ s/\n/ /g;
          $dbquerystr =~ s/    / /g;
          print "\n$dbquerystr\n";
          foreach my $var (@dbvalues) {
            print "$var  ";
          }
          print "\n\n";

          # only update lastopstatus if updateop matches lastop
          my $dbquerystr = <<"dbEOM";
            update operation_log set lastopstatus=?,descr=?
            where orderid=?
            and username=?
            and lastop=?
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
          my @dbvalues = ( "$finalstatus", "$descr", "$orderid", "$username", "$updateop" );
          &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
          $dbquerystr =~ s/\n/ /g;
          $dbquerystr =~ s/  / /g;
          print "\n$dbquerystr\n";
          foreach my $var (@dbvalues) {
            print "$var  ";
          }
          print "\n\n";

          if ( ( $updateop =~ /^(auth|return)/ ) && ( $authcode ne "" ) ) {

            # only update authcode if updateop is auth or return

            my $dbquerystr = <<"dbEOM";
            update trans_log
            set auth_code =?
            where orderid=?
            and username=?
            and operation=?
            and (duplicate is NULL or duplicate='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
            my @dbvalues = ( "$authcode", "$orderid", "$username", "$updateop" );
            &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
            $dbquerystr =~ s/\n/ /g;
            $dbquerystr =~ s/  / /g;
            print "\n$dbquerystr\n";
            foreach my $var (@dbvalues) {
              print "$var  ";
            }
            print "\n\n";

            my $dbquerystr = <<"dbEOM";
            update operation_log set auth_code=?
            where orderid=?
            and username=?
            and lastop=?
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
            my @dbvalues = ( "$authcode", "$orderid", "$username", "$updateop" );
            &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );
            $dbquerystr =~ s/\n/ /g;
            $dbquerystr =~ s/  / /g;
            print "\n$dbquerystr\n";
            foreach my $var (@dbvalues) {
              print "$var  ";
            }
            print "\n\n";

          }

        }
      }
    }
    print "guid: $guid\n";
  }

# { "ConfirmIds": ["390cfb6b-90eb-44b7-9030-d7bbbfcc326a","ebb08e21-558d-4f4f-a779-ba1bb9dd446b","0825f6c1-0d4c-4244-9155-655167b3824c"] // array of the ids to mark as confirmed.  this marks them as confirmed in our database, not to adyen.   we confirm them to adyen as soon as they are received }

  # confirm receipt of notification
  my @transaction = ();

  $transaction[0] = "\"ConfirmIds\": \[\"$guid\"\]";

  my $msg = &createmessage(@transaction);

  print "send: $msg\n\n";

  my $len    = length($msg);
  my $header = "";
  my $path   = "/confirm";

  my %sslheaders = ();
  $sslheaders{'Host'}           = "$host";
  $sslheaders{'Content-Length'} = $len;
  $sslheaders{'Content-Type'}   = 'application/json; charset=utf-8';
  my ( $response, $header, %resulthash ) = &procutils::sendsslmsg( "processor_adyen", $host, $port, $path, $msg, "nossl", %sslheaders );

  print "recv: $response\n";

}

sub processfile {
  my ($filename) = @_;

  my $printstr = "$fileyear $filename  /home/pay1/batchfiles/$devprod/adyen/$fileyear/$filename\n";
  &procutils::filewrite( "$masterusername", "adyen", "/home/pay1/batchfiles/$devprod/adyen", "ftplog.txt", "append", "misc", $printstr );

  $templen = length($filename);
  if ( $templen < 4 ) {
    next;
  }

  # fileencread
  my $infilestr = &procutils::fileencread( "$masterusername", "adyen", "/home/pay1/batchfiles/$devprod/adyen/$fileyear", "$masterusername$filename" );
  my @infilestrarray = split( /\n/, $infilestr );
  print "in processfile /home/pay1/batchfiles/$devprod/adyen/$fileyear/$filename\n";

  umask 0077;
  $outfilestr = "";
  $passflag   = 0;
  $failflag   = 0;
  @batchfail  = ();
  foreach (@infilestrarray) {
    $line = $_;
    chop $line;

    if ( $line !~ /^Company Account/ ) {
      my (@fields) = split( /,/, $line, 21 );

      my $refnum = $fields[2];
      $orderid = $fields[3];
      my $cardtype     = $fields[4];
      my $datetime     = $fields[5];
      my $rcode        = $fields[7];
      my $currency     = $fields[9];
      my $amount       = $fields[11];
      my $exchangerate = $fields[12];
      my $feecurrency  = $fields[13];
      my $grossdebit   = $fields[14];
      my $grosscredit  = $fields[15];
      my $netdebit     = $fields[15];
      my $netcredit    = $fields[16];
      my $feeamt1      = $fields[17];    # commission
      my $feeamt2      = $fields[18];    # markup
      my $feeamt3      = $fields[19];    # scheme fees

      if ( $orderid !~ /^[0-9]+$/ ) {
        print "orderid: $orderid  ...skipping\n";
        next;
      } else {
        print "orderid: $orderid  ...ok\n";
      }

      my $dbquerystr = <<"dbEOM";
          select username
          from trans_log
          where orderid=?
          and refnumber=?
dbEOM
      my @dbvalues = ( "$orderid", "$refnum" );
      my ($un) = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      my $dbquerystr = <<"dbEOM";
          select operation,finalstatus
          from trans_log
          where orderid=?
          and username=?
          and finalstatus in ('pending','locked','success')
          and (duplicate is NULL or duplicate='')
          order by batch_time
dbEOM
      my @dbvalues = ( "$orderid", "$un" );
      my @sth_statusvalarray = &procutils::dbread( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      my %oparray = ();
      for ( my $vali = 0 ; $vali < scalar(@sth_statusvalarray) ; $vali = $vali + 2 ) {
        my ( $op, $fs ) = @sth_statusvalarray[ $vali .. $vali + 1 ];
        $oparray{"$op"} = $fs;
        $username = $un;
      }

      my $errorflag = 1;
      $finalstatus = "";
      if ( ( $oparray{"postauth"} eq "pending" ) && ( $rcode eq "Settled" ) ) {
        $operation                                               = "postauth";
        $finalstatus                                             = "success";
        $errorflag                                               = 0;
        $fundarray{"$username $orderid $operation $finalstatus"} = "fee";
        print "$username $orderid $operation $finalstatus\n";
      } elsif ( ( $oparray{"auth"} eq "pending" ) && ( $rcode eq "Settled" ) ) {
        $operation   = "auth";
        $finalstatus = "success";
        $errorflag   = 0;
        print "$username $orderid $operation $finalstatus\n";
      } elsif ( ( $oparray{"void"} eq "pending" ) && ( $oparray{"return"} eq "" ) && ( $rcode eq "Refunded" ) ) {
        $operation   = "void";
        $finalstatus = "success";
        $errorflag   = 0;
        print "$username $orderid $operation $finalstatus\n";
      } elsif ( ( $oparray{"return"} eq "pending" ) && ( $rcode eq "Refunded" ) ) {
        $operation   = "return";
        $finalstatus = "success";
        $errorflag   = 0;
        print "$username $orderid $operation $finalstatus\n";
      } elsif ( ( ( $oparray{"auth"} eq "success" ) && ( $rcode eq "Settled" ) )
        || ( ( $oparray{"postauth"} eq "success" ) && ( $rcode eq "Settled" ) )
        || ( ( $oparray{"void"} eq "success" )     && ( $rcode eq "Refunded" ) )
        || ( ( $oparray{"return"} eq "success" )   && ( $rcode eq "Refunded" ) ) ) {
        $errorflag = 2;    # do nothing, not an error
        print "skip $username $orderid $operation $finalstatus\n";
      } else {

        #$operation = "auth";
        #$finalstatus = "success";
        #$errorflag = 0;
        print "error  $username $orderid auth: $oparray{'auth'}  void: $oparray{'void'}  $rcode\n";
      }
      print "amount: $currency $amount  gross: $feecurrency $grossdebit $grosscredit    net: $netdebit $netcredit   fees: $feeamt1 $feeamt2 $feeamt3\n";

      $datetime =~ s/[^0-9]//g;

      my $printstr = "$username $orderid $operation $finalstatus $datetime\n";
      &procutils::filewrite( "$username", "adyen", "/home/pay1/batchfiles/$devprod/adyen", "ftplog.txt", "append", "misc", $printstr );

      $batchnum = "$workingbatchdate$workingbatchnum";

      if ( $errorflag == 0 ) {
        my $dbquerystr = <<"dbEOM";
            update trans_log
            set finalstatus=?,descr=?,result=?
            where orderid=?
            and username=?
            and operation=?
            and trans_date>=?
            and (duplicate is NULL or duplicate='')
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
        my @dbvalues = ( "$finalstatus", "$rcode", "$batchnum", "$orderid", "$username", "$operation", "$twomonthsago" );
        &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

        my $operationstatus = $operation . "status";

        %datainfo = ( "orderid", "$errorderid{$errorrecseqnum}", "username", "$username", "operation", "$operation", "descr", "$descr" );
        my $dbquerystr = <<"dbEOM";
            update operation_log set lastopstatus=?,$operationstatus=?,descr=?,batchnum=?
            where orderid=?
            and username=?
            and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
        my @dbvalues = ( "$finalstatus", "$finalstatus", "$rcode", "$batchnum", "$orderid", "$username" );
        &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

        if ( $rcode eq "Settled" ) {
          $payoutcurr{"$username"}  = $currency;
          $payoutarray{"$username"} = $payoutarray{"$username"} + $amount;
        } elsif ( $rcode eq "Refunded" ) {
          $payoutcurr{"$username"}  = $currency;
          $payoutarray{"$username"} = $payoutarray{"$username"} - $amount;
        }

        #$unlinkarray{$batchfilename} = 1;
      } elsif ( ( $redopayoutflag == 1 ) && ( $errorflag == 2 ) ) {
        if ( $rcode eq "Settled" ) {
          $payoutcurr{"$username"}  = $currency;
          $payoutarray{"$username"} = $payoutarray{"$username"} + $amount;
        } elsif ( $rcode eq "Refunded" ) {
          $payoutcurr{"$username"}  = $currency;
          $payoutarray{"$username"} = $payoutarray{"$username"} - $amount;
        }
      }

    }
  }

  #unlink "/home/pay1/batchfiles/$devprod/adyen/$fileyear/$filename";

  #foreach $filename (keys %unlinkarray) {
  #  $year = substr($filename,0,4);
  #  unlink "/home/pay1/batchfiles/$devprod/adyen/$year/$filename";
  #}

}

sub checkdir {
  my ($date) = @_;

  my $printstr = "checking $date\n";
  &procutils::filewrite( "getfiles", "adyen", "/home/pay1/batchfiles/$devprod/adyen", "miscdebug.txt", "append", "misc", $printstr );

  $fileyear = substr( $date, 0, 4 ) . "/" . substr( $date, 4, 2 ) . "/" . substr( $date, 6, 2 );
  $filemonth = substr( $date, 0, 4 ) . "/" . substr( $date, 4, 2 );
  $fileyearonly = substr( $date, 0, 4 );

  if ( !-e "/home/pay1/batchfiles/$devprod/adyen/$fileyearonly" ) {
    my $printstr = "creating $fileyearonly\n";
    &procutils::filewrite( "getfiles", "adyen", "/home/pay1/batchfiles/$devprod/adyen", "miscdebug.txt", "append", "misc", $printstr );
    system("mkdir /home/pay1/batchfiles/$devprod/adyen/$fileyearonly");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/adyen/$filemonth" ) {
    my $printstr = "creating $filemonth\n";
    &procutils::filewrite( "$masterusername", "adyen", "/home/pay1/batchfiles/$devprod/adyen", "miscdebug.txt", "append", "misc", $printstr );
    system("mkdir /home/pay1/batchfiles/$devprod/adyen/$filemonth");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/adyen/$fileyear" ) {
    my $printstr = "creating $fileyear\n";
    &procutils::filewrite( "$masterusername", "adyen", "/home/pay1/batchfiles/$devprod/adyen", "miscdebug.txt", "append", "misc", $printstr );
    system("mkdir /home/pay1/batchfiles/$devprod/adyen/$fileyear");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/adyen/$fileyear" ) {
    system("mkdir /home/pay1/batchfiles/$devprod/adyen/$fileyear");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/adyen/$fileyear" ) {
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: adyen - FAILURE\n";
    print MAILERR "\n";
    print MAILERR "Couldn't create directory logs/adyen/$fileyear.\n\n";
    close MAILERR;
    exit;
  }

}

sub sendpayout {
  my ( $payoutusername, $amount ) = @_;

  print "payout $payoutusername $amount\n";

  my @bd = ();

  #my $acctholdercode = "IPFSCORP";
  #my $accountcode = "8516263595604518";
  #my $bankuuid = "e766a359-0ba4-44e2-ae78-0752c25f8718";
  #my $payout_un = 'ws_874842@MarketPlace.IPFSCorp';
  #my $payout_pw = 'B;n,VPgt:Un8<6bu4,@$yPVDY';

  $bd[0] = "<accountCode>$accountcode</accountCode>";

  $bd[1] = "<amount>";
  my ( $curr, $amt ) = split( / /, $amount );
  $curr =~ tr/a-z/A-Z/;
  my $transamt = sprintf( "%d", ( $amt * 100 ) + .0001 );
  $bd[2] = "<value>$transamt</value>";      # 100
  $bd[3] = "<currency>$curr</currency>";    # USD
  $bd[4] = "</amount>";

  $bd[5] = "<accountHolderCode>$acctholdercode</accountHolderCode>";
  $bd[6] = "<description>Payout</description>";
  $bd[7] = "<bankAccountUUID>$bankuuid</bankAccountUUID>";

  my $message = "";
  my $indent  = 0;
  foreach my $var (@bd) {
    if ( $var eq "" ) {
      next;
    }
    if ( $var =~ /^<\/.*>/ ) {
      $indent--;
    }
    if ( $var =~ /></ ) {
      next;
    }

    #$message = $message . $var . "\n";
    $message = $message . " " x $indent . $var . "\n";
    if ( ( $var !~ /\// ) && ( $var != /<?/ ) ) {
      $indent++;
    }
    if ( $indent < 0 ) {
      $indent = 0;
    }
  }

  ($message) = &adyen::xmltojson( $message, $tcode );
  print "\n\nmessage: $message\n\n";

  my $chkmessage = $message;
  $chkmessage =~ s/accountCode": "[0-9a-zA-Z\-]+([0-9a-zA-Z\-]{4})"/accountCode": "xxxx$1"/;
  $chkmessage =~ s/bankAccountUUID": "[0-9a-zA-Z\-]+([0-9a-zA-Z\-]{4})"/bankAccountUUID": "xxxx$1"/;
  $mytime     = gmtime( time() );
  $outfilestr = "$mytime send: $chkmessage\n\n";
  &procutils::fileencwrite( "$payoutusername", "adyen", "/home/pay1/batchfiles/$devprod/adyen/$fileyear", "$payoutusername" . "_payout$todaytime.txt", "append", "", $outfilestr );

  my $host = "cal-test.adyen.com";
  my $path = "/cal/services/Fund/v6/payoutAccountHolder";
  my $port = "443";

  my $len = length($msg);

  my $port = "443";

  my $header     = "";
  my %sslheaders = ();
  $sslheaders{'Host'} = "$host";

  #$sslheaders{'X-API-KEY'} = "$report_api_key";
  #$sslheaders{'X-CLIENT-KEY'} = "test_3Z6O7K6JVVF5DIN4QBF2ZYZGAUQS5SKV";
  $sslheaders{'Authorization'} = "Basic " . &MIME::Base64::encode( "$payout_un:$payout_pw", "" );

  #$sslheaders{'Content-Length'} = $len;
  $sslheaders{'Content-Type'} = 'application/json; charset=utf-8';

  print "path: $path\n";

  my ( $response, $d1, %resulthash ) = &procutils::sendsslmsg( "processor_adyen", $host, "", $path, $message, "lwp", %sslheaders );

  #my ($response) = &procutils::sendsslmsg("processor_adyen",$host,"$port",$path,$msg,"nopost,got=\}",%sslheaders);

  # _HTTP_CODE: 200
  # _HTTP_REASON: 200

  my $header = $resulthash{"headers"};
  print "header: $header\n\n";

  my $httpcode = "";
  if ( $header =~ /_HTTP_CODE: ([0-9]+)/ ) {
    $httpcode = $1;    # 401 unauthorized, 404 not found
  }
  print "httpcode: $httpcode\n\n";

  print "response: $response\n\n";

  $mytime     = gmtime( time() );
  $outfilestr = "$mytime recv: ";
  if ( $httpcode eq "200" ) {
    my $chkmessage = $response;
    $chkmessage =~ s/accountCode": "[0-9a-zA-Z\-]+([0-9a-zA-Z\-]{4})"/accountCode": "xxxx$1"/;
    $chkmessage =~ s/bankAccountUUID":"[0-9a-zA-Z\-]+([0-9a-zA-Z\-]{4})"/bankAccountUUID":"xxxx$1"/;
    $outfilestr .= "$chkmessage\n\n";
  } else {
    $outfilestr .= "$header\n\n";
  }
  &procutils::fileencwrite( "$payoutusername", "adyen", "/home/pay1/batchfiles/$devprod/adyen/$fileyear", "$payoutusername" . "_payout$todaytime.txt", "append", "", $outfilestr );

}

