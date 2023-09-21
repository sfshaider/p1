package miscutils;

use lib '/home/pay1/perlpr_lib';

use LWP::UserAgent;
use DBI;
use SHA;
use Net::SSLeay qw(get_https post_https sslcat make_headers make_form);
use MIME::Base64;
use Math::BigInt;
use Time::Local;
use IO::Socket;
use Socket;
use POSIX;
use sysutils;
use smpsutils;
use Date::Calc qw(Add_Delta_Days Delta_Days Days_in_Month);
use PlugNPay::Email;
use PlugNPay::Features;
use PlugNPay::Util::Array qw(inArray);
use strict;

$miscutils::earliest_date = "20070101";
$miscutils::mysqlport = "3306";
$miscutils::mysqlhost = "mysql-data1";

sub errmail {
  my ($line,$file,$error,%message) = @_;

  if (($file =~ /mckutils/) && ($error =~ /Duplicate entry/)) {
    return;
  }

  if ($message{'card-number'} ne "") {
    $message{'card-number'} = substr($message{'card-number'},0,4) . '**' . substr($message{'card-number'},-2,2);
  }
  if ($message{'enccardnumber'} ne "") {
  }

  #Magstrip data filter added by Nick 8/24/2010
  if ($message{'magstripe'} ne "") {
    $message{'magstripe'} = "<Present>";
  }
  if ($message{'publisher-name'} =~ /^(americanfi1)$/) {
    return;
  }


  $message{'PID'} = $$;
  my $severity = 0;

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
  $message{'ERROR_TIME'} = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);

  my $emailer = new PlugNPay::Email('legacy');
  $emailer->setTo('dprice@plugnpay.com');
  $emailer->addBCC('chris@plugnpay.com');
  if ($file !~ /affiliate/) {
    $emailer->addCC('cprice@plugnpay.com');
  }

  if ($error =~ /extend/i) {
    #TODO: How to change this to use Sys::Time and keep track of the last mod time?
    my ($dummy1,$dummy2,$dummy3,$dummy4,$dummy5,$dummy6,$dummy7,$dummy8,$dummy9,$modtime) = stat "/home/p/pay1/logfiles/tableerror.txt";
    my $mytime2 = time();
    my $delta = ($mytime2 - $modtime) / 60;
    if ($delta > 5) {
      $emailer->addBCC('3039219466\@vtext.com');
      $emailer->addBCC('6318061932@txt.att.net');
      open(TMPFILE,">/home/p/pay1/logfiles/tableerror.txt");
      close(TMPFILE);
    }
  }

  $emailer->setFrom('noc@plugnpay.com');
  my $source = $file;
  $source =~ s/.*\/([a-zA-Z0-9_]+)\.(cgi|pl)/$1/g;
  if ($error =~ /unique constraint/i) {
    $emailer->setSubject("PNP FAILURE - $source - unique constraint");
  } elsif ($error =~ /inserted value too large/i) {
    $emailer->setSubject("PNP FAILURE - $source - value too large");
  } elsif ($error =~ /invalid column name/i) {
    $emailer->setSubject("PNP FAILURE - $source - invalid column name");
  } else {
    $emailer->setSubject("PNP FAILURE - $source");
  }

  my $emailMessage = "File: $file\n";
  $emailMessage .= "Line: $line\n";
  $emailMessage .= "Error: $error\n\n";
  foreach my $key (sort keys %message) {
    if ($key !~ /password/) {
      $emailMessage .= "$key $message{$key}\n";
    } else {
      $emailMessage .= "$key XXXXXXXXXX\n";
    }
  }

  $emailer->setContent($emailMessage);

  if ($severity == 1) {
    my @pager_list = ("3039219466\@vtext.com","6318061932\@txt.att.net","6317046818\@txt.att.net");
    foreach my $telnum (@pager_list) {
      $emailer->addTo($telnum);
    }
  }

  $emailer->send();
}


sub errmaildie {
  my ($line,$file,$error,%message) = @_;
  my ($key,%errormsg);

  my %allowed_length = ('order-id','30','card-name','40','card-addr','40','card-city','40','card-state','20',
                        'card-zip','12','card-country','20','card-number','20','card-exp','10','amount','20',
                        'trans_date','10','trans_type','20','result','20','descr','120','acct_code','12',
                        'enccardnumber','256','length','10','shacardnumber','50','refnumber','60','trans_time','14',
                        'finalstatus','12','auth_code','128','avs','8','operation','20','ipaddress','24',
                        'publisheremail','50','successlink','2','duplicate','4','cardextra','8','batch_time','14',
                        'detailnum','20','currency','4','accttype','12','cvvresp','4');
  if ($error =~ /inserted value too large/) {
    foreach $key (sort keys %message) {
      if (length($message{$key}) > $allowed_length{$key} - 1) {
        $errormsg{$key} = "MesgLen:" . length($message{$key}) . " AllowdLen:" . $allowed_length{$key};
      }
    }
  }

  if ($message{'card-number'} ne "") {
    $message{'card-number'} = substr($message{'card-number'},0,4) . '**' . substr($message{'card-number'},-2,2);
  }
  if ($message{'enccardnumber'} ne "") {
    $message{'enccardnumber'} = "";
  }

  if ($message{'magstripe'} ne "") {
    $message{'magstripe'} = "<Present>";
  }
  my $mailer = new PlugNPay::Email('legacy');

  $mailer->addTo('cprice@plugnpay.com');
  $mailer->addCC('dprice@plugnpay.com');
  $mailer->addBCC('chris@plugnpay.com');

  if ($error =~ /extend/i) {
    my ($dummy1,$dummy2,$dummy3,$dummy4,$dummy5,$dummy6,$dummy7,$dummy8,$dummy9,$modtime) = stat "/home/p/logfiles/tableerror.txt";
    my $mytime2 = time();
    my $delta = ($mytime2 - $modtime) / 60;
    if ($delta > 5) {
      $mailer->addBCC('3039219466@vtext.com');
      $mailer->addBCC('6318061932@vtext.com');
      open(TMPFILE,">/home/p/pay1/logfiles/tableerror.txt");
      close(TMPFILE);
    }
  }

  $mailer->setFrom('noc@plugnpay.com');
  $mailer->setSubject('EMERGENCY - trans_log problem');
  my $emailMessage = "File $file\n";
  $emailMessage .= "Line $line\n";
  $emailMessage .= "Error: $error\n\n";

  foreach $key (sort keys %message) {
    $emailMessage .= "$key $message{$key} $errormsg{$key}\n";
  }

  $mailer->setContent($emailMessage);

  print "Content-Type: text/html\n\n";
  print "<html>\n";
  print "<body bgcolor=\"#ffffff\">\n";
  print "We are experiencing some technical difficulties. The techs have been notified.<br>\n";
  print "Sorry for the inconvenience. Please try again later.<br>\n";
  print "</body>\n";
  print "</html>\n";

  exit;
}

sub formpostproxy {
  my ($url,$querystring,$username,$method) = @_;
  $url =~ s/(\W)/'%' . unpack("H2",$1)/ge;
  $querystring =~ s/(\W)/'%' . unpack("H2",$1)/ge;
  my $addr = "http://successlink/successlink.cgi";
  my $pairs = "url=$url&method=$method&username=$username&querystring=$querystring";

  my (%headers);
  my $ua = new LWP::UserAgent;
  $ua->agent("AgentName/0.1 " . $ua->agent);
  $ua->timeout(60);

  my $req = new HTTP::Request POST => $addr;
  $req->content_type('application/x-www-form-urlencoded');
  $req->content($pairs);

  my $res = $ua->request($req);

  my $response = $res->content;
  my @headers = ();  ###  Obtain headers from response.
  foreach my $var (@headers) {
    $headers{$var} = "";   ### Obtain value for header in response.
  }

  return $response,%headers;
}

sub formpostmsg {
  my ($addr,$pairs,$message) = @_;
  my ($it);
  my $ua = new LWP::UserAgent;
  $ua->agent("AgentName/0.1 " . $ua->agent);
  $ua->timeout(1200);

  my $req = new HTTP::Request POST => $addr;
  $req->content_type('application/x-www-form-urlencoded');
  $req->content($pairs);

  my $res = $ua->request($req);

  if ($res->is_success) {
    print "Content-Type: text/html\n\n";
    print $res->content;
  } else {
    if (($res->content =~ /\(Operation already in progress\)/i) && ($it < 4)) {
      $it++;
      my $time500 = gmtime(time());
      &formpostmsg($addr,$pairs,$message);
    } elsif ($message ne "") {
      print "Content-Type: text/html\n\n";
      print "$message";
    } else {
      print "Content-Type: text/html\n\n";
      print $res->error_as_HTML;
    }
  }
}

sub formpost {
  my ($addr,$pairs,$myusername,$mypassword) = @_;

  if ($addr !~ /^https:/) {
    my $ua = new LWP::UserAgent;
    $ua->agent("MSIE 4.0b2");
    $ua->timeout(1200);

    my $req = new HTTP::Request POST => $addr;
    $req->content_type('application/x-www-form-urlencoded');
    if (($myusername ne "") && ($mypassword ne "")) {
      $req->authorization_basic("$myusername", "$mypassword");
    }
    $req->content($pairs);

    my $res = $ua->request($req);

    if ($res->is_success) {

      if ($res->content =~ /\(Operation already in progress\)/i) {
        &formpost2($addr,$pairs,$myusername,$mypassword);
      } else {
        print "Content-Type: text/html\n\n";
        print $res->content;
      }
    } else {

      if ($res->error_as_HTML =~ /\(Operation already in progress\)/i) {
        &formpost2($addr,$pairs,$myusername,$mypassword);
      } else {
        print "Content-Type: text/html\n\n";
        print $res->error_as_HTML;
      }
    }
  } else {
    my $host = $addr;
    $host =~ s/https:\/\///;
    $host =~ s/\/(.*)//;
    my $path = $1;
    $host =~ s/\:443//;
    my ($page, $response, %reply_headers) = post_https("$host", 443, "/$path", '', $pairs);
    print "Content-Type: text/html\n\n";
    print $page;
  }

}

sub formpost2 {
  my ($addr,$pairs,$myusername,$mypassword) = @_;

  if ($addr !~ /^https:/) {
    my $ua = new LWP::UserAgent;
    $ua->agent("AgentName/0.1 " . $ua->agent);
    $ua->timeout(1200);

    my $req = new HTTP::Request POST => $addr;
    $req->content_type('application/x-www-form-urlencoded');
    if (($myusername ne "") && ($mypassword ne "")) {
      $req->authorization_basic("$myusername", "$mypassword");
    }
    $req->content($pairs);

    my $res = $ua->request($req);

    if ($res->is_success) {
      print "Content-Type: text/html\n\n";
      print $res->content;

    } else {
      print "Content-Type: text/html\n\n";
      print $res->error_as_HTML;
    }
  } else {
    my $host = $addr;
    $host =~ s/https:\/\///;
    $host =~ s/\/(.*)//;
    my $path = $1;
    my ($page, $response, %reply_headers) = post_https("$host", 443, "/$path", '', $pairs);
    print "Content-Type: text/html\n\n";
    print $page;
  }
}

sub formpost_raw {
  my ($addr,$pairs,$myusername,$mypassword) = @_;

  if ($addr !~ /^https:/) {
    my $ua = new LWP::UserAgent;
    $ua->agent("AgentName/0.1 " . $ua->agent);
    $ua->timeout(1500);

    my $req = new HTTP::Request POST => $addr;
    $req->content_type('application/x-www-form-urlencoded');
    if (($myusername ne "") && ($mypassword ne "")) {
      $req->authorization_basic("$myusername", "$mypassword");
    }
    $req->content($pairs);

    my $res = $ua->request($req);

    if ($res->is_success) {
      return $res->content;
    } else {
      return $res->error_as_HTML;
    }
  } else {
    my ($port);
    my $host = $addr;
    $host =~ s/https:\/\///;
    $host =~ s/\/(.*)//;
    my $path = $1;

    if ($host =~ /:(\d+)$/) {
      $port = $1;
      $host =~ s/(.*):\d+$/$1/;
    }
    else {
      $port = 443;
    }

    my ($page, $response, %reply_headers) = post_https("$host", "$port", "/$path", '', $pairs);
    return $page;
  }
}

# formpost for UPS calculator
sub formpostUPS {
  my ($addr,$pairs) = @_;
  my ($content);
  my $ua = new LWP::UserAgent;
  $ua->agent("MSIE 4.0b2");
  $ua->timeout(1200);

  my $req = new HTTP::Request POST => $addr;
  $req->content_type('application/x-www-form-urlencoded');
  $req->content($pairs);

  my $res = $ua->request($req);

  if ($res->is_success) {
     $content =  $res->content;
  }
  return $content;
}

# formpost for USPS calculator similar to formpostpl
sub formpostUSPS {
  my ($addr,$pairs,$host,$path) = @_;
  my ($header);
  my $port = 80;
  my $paddr = &socketopen($host,$port);
  my $message = "POST /$path HTTP/1.0\r\n";
  $message = $message . "Host: $host\r\n";
  $message = $message . "Referrer: https://pay1.plugnpay.com/\r\n";
  $message = $message . "Content-Type: application/x-www-form-urlencoded\nContent-Length: ";
  $message = $message . length($pairs) . "\r\n\r\n";
  $message = $message . $pairs . "\r\n\r\n";
  my $content = &socketwrite2($message,$host,$path,$paddr);
  ($header,$content) = split(/\r\n\r\n|\n\n/,$content,2);
  return $content;
}

sub get {
  my ($addr,$myusername,$mypassword,$returntype) = @_;

  my $ua = new LWP::UserAgent;
  $ua->agent("AgentName/0.1 " . $ua->agent);
  $ua->timeout(1200);

  my $req = new HTTP::Request GET => $addr;
  $req->content_type('application/x-www-form-urlencoded');
  if (($myusername ne "") && ($mypassword ne "")) {
    $req->authorization_basic("$myusername", "$mypassword");
  }

  my $res = $ua->request($req);

  if ($res->is_success) {
    if ($returntype eq "raw") {
      my $page = $res->content;
      return $page;
    } else {
      print "Content-Type: text/html\n\n";
      print $res->content;
    }
  } else {
    if ($returntype eq "raw") {
      my $page = $res->error_as_HTML;
      return $page;
    } else {
      print "Content-Type: text/html\n\n";
      print $res->error_as_HTML;
    }
  }
}

##################################################
# This subroutine will read a list of files and  #
# replace all instances of xxxwhateverxxx with   #
# the contents of $whatever.                     #
# Usage: &miscutils::filesub(@files);            #
##################################################

sub filesub {
  my @files = @_;

  #NOTE: I don't know how well this would work
  my ($var,$temp);
  require PlugNPay::WebDataFile;
  my $fileManager = new PlugNPay::WebDataFile();
  foreach $var (@files) {
    my @currentFileAndPath = split('/', $var);
    my $fileName = pop(@currentFileAndPath);
    my $localPath = '/' . join('/', @currentFileAndPath);
    my $fileData = $fileManager->readFile({
      'localPath' => $localPath,
      'fileName'  => $fileName
    });

    my @newFile = ();
    foreach my $line (split("\n", $fileData)) {
      while($line =~ /xxx(.*)xxx/) {
        $temp = $1;
        $line =~ s/xxx$1xxx/$temp/g;
      }
      push @newFile, $line;
    }

    $fileManager->writeFile({
      'fileName'  => $fileName,
      'localPath' => $localPath,
      'content'   => join("\n", @newFile)
    });
  }
}

##################################################
# This subroutine will read an html template and #
# print the generated html to STDOUT.            #
# Usage: &miscutils::template("template.html");  #
##################################################

sub template {
  my ($file) = @_;
  my ($temp,$tempindirect);
  require PlugNPay::WebDataFile;
  my $fileManager = new PlugNPay::WebDataFile();
  my @fileData = split('/', $file);
  my $fileName = pop @fileData;
  my $templateFile = $fileManager->readFile({
    'storageKey' => 'templates',
    'fileName'   => $fileName,
  });

  foreach my $line (split("\n", $templateFile)) {
    while($line =~ /\[(.*)\]/) {
      $temp = $1;
      *tempindirect = $main::{$1};
      $line =~ s/\[$1\]/$tempindirect/g;
    }
    print $line . "\n";
  }
}

sub dbhconnect {
  require PlugNPay::DBConnection;
  my $dbc = new PlugNPay::DBConnection();
  return $dbc->getHandleFor(shift);
}

sub dbhconnectalrm {
  my ($username,$dontdieflag,$merchant) = @_;

  # this never worked well.  Something may use it so it's just here as a stub.

  my $dbh = &dbhconnect($username,$dontdieflag,$merchant);

  return $dbh;
}

sub get_db_info {
  my ($database) = @_;

  my $hostname = "mysql-dbinfo";
  my $password = "9ken6hgq";
  my ($result_password, $result_hosttype, $result_status, $result_host, $result_port, $result_username);

  my $dsn = "DBI:mysql:database=dbinfo;host=$hostname;port=$miscutils::mysqlport";
  # if this connect fails it will be caught by dbhconnect
  my $dbh = DBI->connect($dsn, "dbinfo", $password, {'RaiseError' => 0, 'PrintError' => 0});
  my $sth = $dbh->prepare(qq{
          SELECT password, host_type, status, host, port, username
          FROM db_login
          WHERE db_name=?
  });
  $sth->execute("$database");
  $sth->bind_columns(undef,\($result_password, $result_hosttype, $result_status, $result_host, $result_port, $result_username));
  $sth->fetch;
  $sth->finish;
  $dbh->disconnect;

  return ($result_password, $result_hosttype, $result_status, $result_host, $result_port, $result_username);
}

sub dbhconnect2 {
  $ENV{ORACLE_HOME} = '/usr/share/import/instantclient';
  $ENV{'TWO_TASK'} = 'orapay';
  $ENV{TNS_ADMIN} = '/usr/share/import/instantclient/network/admin';

  my ($password, $hosttype, $status);
 ($password, $hosttype, $status) = &get_db_info("pnpdata");

  my $dbh = DBI->connect("dbi:Oracle:","pnpdata","$password") or print "Can't connect: $DBI::errstr";

  return $dbh;
}

sub mysqlconnect {
  my ($username,$dontdieflag) = @_;

  # just a basic mysql connection
  my $dbh = &dbhconnect($username,$dontdieflag,"mysqlconnect");

  return $dbh;
}

sub get_db_pw {
  my ($database) = @_;
  my ($result_hosttype, $result_status, $result_host, $result_port);

  my %host_type = ('pnpdata','oracle','fraudtrack','mysql','pnpmisc','mysql');
  my %db_status = ('pnpdata','live','fraudtrack','live','pnpmisc','live');
  my %db_host = ('pnpdata','','fraudtrack','','pnpmisc','');
  my %db_port = ('pnpdata','','fraudtrack','','pnpmisc','');

  my $result_password = &sendipc($database);

  $result_hosttype = $host_type{$database};
  $result_status = $db_status{$database};
  $result_host = $db_host{$database};
  $result_port = $db_port{$database};
  return ($result_password, $result_hosttype, $result_status, $result_host, $result_port);
}

sub sendipc {
  my ($database) = @_;

  my $msqida = "";
  my $keya = "5592";

  if (!defined ($msqida = shmget($keya, 16384, 0))) {
    require PlugNPay::Logging::DataLog;
    new PlugNPay::Logging::DataLog({'collection' => 'miscutils'})->log({
      'message' => 'msqida miscutils: failure: ' . $!,
      'originalLogFile' => '/home/p/pay1/logfiles/pwserverlogmsg.txt'
    });

    return;
  }

  my $response = "";
  shmread($msqida, $response, 16300,60);

  my %keyarray = ();
  my (@lines) = split(/,/,$response);
  foreach my $line (@lines) {
    my ($date,$pw) = split(/ /,$line);
    if ($date eq $database) {
      return "$pw";
    }
  }
  return "";
}

sub genorderid {
  return gendatetime(0);
}

sub gendatetime {
  my $timeadjust = shift || 0;
  require PlugNPay::Transaction::TransactionProcessor;
  my $orderid = PlugNPay::Transaction::TransactionProcessor::generateOrderID();
  my ($date,$time) = gendatetime_only($timeadjust);
  return ("$orderid","$date","$time");
}

sub gendatetime_only {
  my $timeadjust = shift || 0;
  my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = gmtime(time() + $timeadjust);
  my $date = sprintf("%04d%02d%02d",$year+1900,$month+1,$day);
  my $time = sprintf("%04d%02d%02d%02d%02d%02d",$year+1900,$month+1,$day,$hour,$min,$sec);
  return ("$date","$time");
}

sub sendmserver { # We saved 1200 lines of code!!!
  my $username = shift;
  my $operation = shift;
  my @pairs = @_;
  my %query = @pairs;
  %miscutils::timetest = ();
  @miscutils::timetest = ();
  require PlugNPay::Processor::Route;
  my $router = new PlugNPay::Processor::Route();

  # put username and operation into the "query"
  $query{'username'} = $username;
  $query{'operation'} = $operation;
 #Swapping for new code consistency and future code changes
  my $temp = $query{'order-id'};
  $query{'order-id'} = $query{'orderID'};
  $query{'orderID'} = $temp;
  @pairs = %query;

  # NOTE: Route.pm only supports a single transaction right now.
  # But Process.pm accepts arrays of transactions as an input.
  # This way legacy code is still supported (for now.....)
  my $a = time();
  $miscutils::timetest[++$#miscutils::timetest] = "start_sendmserver_$query{'orderID'}";
  $miscutils::timetest[++$#miscutils::timetest] = "$a";

  my $result = $router->route({ transactionData => \%query });

  $a = time();
  $miscutils::timetest[++$#miscutils::timetest] = "end_processor_$query{'orderID'}";
  $miscutils::timetest[++$#miscutils::timetest] = "$a";

   return %{$result};
}

sub checkip {
  my ($username,$ipaddress) = @_;

  my $dbhmisc = &miscutils::dbhconnect("pnpmisc");

  my $sth1 = $dbhmisc->prepare(qq{
      SELECT username,ipaddress,ipcount,trans_date,status
        FROM ipcheck
       WHERE ipaddress = ?
      }) or die "Can't prepare: $DBI::errstr";
  $sth1->execute($ipaddress) or die "Can't execute: $DBI::errstr";
  my ($chkusername,$chkipaddress,$chkipcount,$chktrans_date,$chkstatus) = $sth1->fetchrow;
  $sth1->finish;

  $chkipcount++;

  my ($today) = &miscutils::gendatetime_only();

  if ($chktrans_date ne $today) {
    $chkipcount = 1;
  }

  if (($chkipcount == 4) && ($username ne $chkusername)) {
    $chkstatus = "block";
  }
  elsif ($chkstatus eq "") {
    $chkstatus = "ok";
  }

  if ($chkipaddress eq "") {
    my $sth3 = $dbhmisc->prepare(qq{
        INSERT INTO ipcheck
        (username,ipaddress,ipcount,trans_date,status)
        VALUES (?,?,?,?,?)
        }) or die "Can't prepare: $DBI::errstr";
    $sth3->execute("$username","$ipaddress","$chkipcount","$today","$chkstatus") or die "Can't execute: $DBI::errstr";
    $sth3->finish;

    my $now = time();
    my $deldate = &timetostr($now-(3600*24*60));
    $deldate = substr($deldate,0,8);

    my $sth4 = $dbhmisc->prepare(qq{
        DELETE FROM ipcheck
              WHERE trans_date < ?
        }) or die "Can't prepare: $DBI::errstr";
    $sth4->execute($deldate) or die "Can't execute: $DBI::errstr";
    $sth4->finish;
  }
  else {
    my $sth3 = $dbhmisc->prepare(qq{
        UPDATE ipcheck
           SET username=?,ipaddress=?,ipcount=?,trans_date=?,status=?
        WHERE ipaddress = ?
        }) or die "Can't prepare: $DBI::errstr";
    $sth3->execute("$username","$ipaddress","$chkipcount","$today","$chkstatus", $ipaddress) or die "Can't execute: $DBI::errstr";
    $sth3->finish;
  }

  if (($chkipcount == 4) && ($username ne $chkusername)) {
    my ($country) = &miscutils::check_geolocation($ipaddress);
    require PlugNPay::Logging::DataLog;
    new PlugNPay::Logging::DataLog({'collection' => 'hacker_data'})->log({
      'country'         => $country,
      'username'        => $username,
      'ipAddress'       => $ipaddress,
      'loadedUser'      => $chkusername,
      'originalLogFile' => '/home/p/pay1/logfiles/hackerinfo.txt'
    });


    my $emailMessage = "ipaddress is trying too many different usernames unsuccessfully\n";
    $emailMessage .= "$ipaddress should be blocked\n";
    $emailMessage .= "country: $country\n";
    $emailMessage .= "usernames: $username $chkusername\n\n";

    my $mailer = new PlugNPay::Email();
    $mailer->setTo('dprice@plugnpay.com');
    $mailer->setCC('cprice@plugnpay.com');
    $mailer->setFrom('dcprice@plugnpay.com');
    $mailer->setSubject('hacker info');
    $mailer->setContent($emailMessage);
    $mailer->send();
  }
}

sub precheckip {
  my $username = shift;
  my $ipaddress = shift;
  my $dbh =  shift || new PlugNPay::DBConnection()->getHandleFor("pnpmisc");

  my $sth = $dbh->prepare(qq{
      SELECT username,ipcount,trans_date
        FROM ipcheck
       WHERE ipaddress=?
  });
  $sth->execute($ipaddress);
  my ($chkusername,$chkipcount,$chktrans_date) = $sth->fetchrow;
  $sth->finish;

  my ($today) = &miscutils::gendatetime_only();
  if ($chktrans_date ne $today) {
    return;
  }
  if (($chkipcount > 3) && ($username ne $chkusername)) {
    return "block";
  }

  return;
}


sub strtodate {
  my ($string) = @_;
  if ($string ne "") {
    my $date = sprintf("%04d%02d%02d", substr($string,6,4), substr($string,0,2), substr($string,3,2));
    return $date;
  }
  return "";
}


sub datetostr {
  my ($date) = @_;
  if ($date ne "") {
    my $string = sprintf("%02d/%02d/%04d", substr($date,4,2), substr($date,6,2), substr($date,0,4));
    return $string;
  }
  return "";
}


sub timetostr {
  my ($time) = @_;

  if ($time ne "") {
    my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = gmtime($time);
    my $string = sprintf("%04d%02d%02d%02d%02d%02d",$year+1900,$month+1,$day,$hour,$min,$sec);
    return $string;
  }
  return "";
}


sub strtotime {
  my ($string) = @_;

  if ($string ne "") {
    my $year = substr($string,0,4);
    my $month = substr($string,4,2);
    my $day = substr($string,6,2);
    my $hour = substr($string,8,2);
    my $min = substr($string,10,2);
    my $sec = substr($string,12,2);

    if (($month =~ /^(04|06|09|11)$/) && ($day > 30)) {
      $day = 30;
    }
    elsif (($year =~ /^(2004|2008|2012|2016|2020|2024|2028)$/)
        && ($month eq "02") && ($day > 29)) {
      $day = 29;
    }
    elsif (($year !~ /^(2004|2008|2012|2016|2020|2024|2028)$/)
        && ($month eq "02") && ($day > 28)) {
      $day = 28;
    }
    elsif ($day > 31) {
      $day = 31;
    }

    if (($year < 1995) || ($year > 2032)
        || ($month < 1) || ($month > 12)
        || ($day < 1) || ($day > 31)
        || ($hour < 0) || ($hour > 23)
        || ($min < 0) || ($min > 59)
        || ($sec < 0) || ($sec > 59)) {
      return "";
    }

    $string = $string . "000000";
    my $time = timegm($sec,$min,$hour,$day,$month-1,$year-1900);
    return $time;
  }
  return "";
}


sub incorderid {
  my ($orderid) = @_;
  $orderid = Math::BigInt->new("$orderid");
  $orderid = $orderid + 1;
  $orderid =~ s/\+//;
  return "$orderid";
}


sub mod10 {
  my ($number) = @_;

  my $ztest = $number;
  $ztest =~ s/0//g;
  if (length($ztest) < 1) {
    return "failure";
  }

  my $sum = 0;
  my @digits = ();

  my ($route) = split(/ /,$number);

  @digits = split('',$route);

  $sum = ($digits[0] * 3) + ($digits[1] * 7) + ($digits[2] * 1) + ($digits[3] * 3) + ($digits[4] * 7) + ($digits[5] * 1) + ($digits[6] * 3) + ($digits[7] * 7);
  $sum = (10 - ($sum % 10)) % 10;

  if ($digits[8] == $sum) {
    return "success";
  }
  else {
    return "failure";
  }
}


sub luhn10 {
  my ($cardnumber) = @_;
  $cardnumber =~ s/[^0-9]//g;
  my $cardbin = substr($cardnumber,0,6);
  my ($cardtype);
  my %cardlengths = ('VISA','13|16|19','MSTR','16','AMEX','15','DNRS','14|16','CRTB','14','DSCR','16','JCB','16','JAL','16','MYAR','16','KC','16','SWTCH','16|17|18|19','SOLO','16|18|19','PP_','16','SV_','16','PL','16|18|19|20|21|22|23|24|25|26|27','WEX','13|19');

  if ( ($cardbin =~ /^(491101|491102)/)
    || ($cardbin =~ /^(564182)/)
    || ($cardbin =~ /^(490302|490303|490304|490305|490306|490307|490308|490309)/)
    || ($cardbin =~ /^(490335|490336|490337|490338|490339|490525|491174|491175|491176|491177|491178|491179|491180|491181|491182)/)
    || ($cardbin =~ /^(4936)/)
    || (($cardbin >= 633300) && ($cardbin < 633349))
    || (($cardbin >= 675900) && ($cardbin < 675999)) ) {
    $cardtype = "SWTCH";  ## UK Maestro
  }
  elsif ($cardbin =~ /^(048|0420|0430|0498|0481|690046|707138)/) {
    $cardtype = 'WEX';                    # wex
    $cardnumber = substr($cardnumber,-13);
  }
  elsif ( (($cardbin >= 633450) && ($cardbin < 633499)) || (($cardbin >= 676700) && ($cardbin < 676799)) ) {
    $cardtype = "SOLO";
  }
  elsif ($cardbin =~ /^(4)/) {
    $cardtype = "VISA";
  }
  elsif ($cardbin =~ /^(51|52|53|54|55)/) {
    $cardtype = "MSTR";
  }
  elsif (($cardbin >= 222100) && ($cardbin <= 272099)) { ## New MC Bin Range Effective Oct. 1, 2016
    $cardtype = "MSTR";
  }
  elsif ($cardbin =~ /^(37|34)/) {
    $cardtype = "AMEX";
  }
  elsif (($cardbin =~ /^(3088|3096|3112|3158|3337)/)
                 || (($cardbin >= 352800) && ($cardbin < 359000))) {
    $cardtype = "JCB";
  }
  elsif ( ($cardbin >= 300000) && ($cardbin <= 305999)
                 || (($cardbin >= 309500) && ($cardbin <= 309599))
                 || (($cardbin >= 360000) && ($cardbin <= 369999))
                 || (($cardbin >= 380000) && ($cardbin <= 399999))
     ) {
    $cardtype = "DNRS";
  }
  elsif ($cardbin =~ /^(389)/) {
    $cardtype = "CRTB";
  }
  elsif ( ($cardbin >= 601100) && ($cardbin <= 601109)
                 || (($cardbin >= 601120) && ($cardbin <= 601149))
                 || (($cardbin >= 601174) && ($cardbin <= 601174))
                 || (($cardbin >= 601177) && ($cardbin <= 601179))
                 || (($cardbin >= 601186) && ($cardbin <= 601199))
                 || (($cardbin >= 622126) && ($cardbin <= 622925))
                 || (($cardbin >= 624000) && ($cardbin <= 626999))
                 || (($cardbin >= 628200) && ($cardbin <= 628899))
                 || (($cardbin >= 644000) && ($cardbin <= 649999))
                 || (($cardbin >= 650000) && ($cardbin <= 659999))
     ) {
    $cardtype = "DSCR";
  }
  elsif ($cardbin =~ /^(1800|2131)/) {
    $cardtype = "JAL";
  }
  elsif ($cardbin =~ /^(7775|7776|7777)/) {
    $cardtype = "KC";
  }
  elsif ($cardbin =~ /^(7)/) {
    $cardtype = "MYAR";
  }
  elsif ($cardbin =~ /^(8)/) {
    $cardtype = "PP_";
  }
  elsif ($cardbin =~ /^(9)/) {
    $cardtype = "SV_";
  }
  elsif ($cardbin =~ /^(604626|605011|603028|603628)/) {
    $cardtype = "PL";
  }
  elsif ( (($cardbin >= 500000) && ($cardbin <= 509999))
    || (($cardbin >= 560000) && ($cardbin <= 589999))
    || (($cardbin >= 600000) && ($cardbin <= 699999)) ) {
    $cardtype = "SWTCH";  ### Int Maestro
  }
  else {
    return "failure";
  }

  if (length($cardnumber) !~ /$cardlengths{$cardtype}/) {
    return "failure";
  }
  elsif ($cardtype =~ /^(KC|PL|WEX)$/) {
    return "success";
  }


  my $sum = 0;
  my $len = length($cardnumber);
  my @digits = split('',$cardnumber);
  my ($k,$j,$a,$b,$c,$temp,$check);
  for($k=0; $k<$len; $k++) {
    $j = $len - 1 - $k;

    if (($j - 1) >= 0) {
      $a = $digits[$j-1] * 2;
    }
    else {
      $a = 0;
    }

    if (length($a) > 1) {
      ($b,$c) = split('',$a);
      $temp = $b + $c;
    }
    else {
      $temp = $a;
    }
    $sum = $sum + $digits[$j] + $temp;
    $k++;
  }

  $check = substr($sum,length($sum)-1);

  if ($check eq "0") {
    return "success";
  }
  else {
    return "failure";
  }
}

sub formpostpl {
  my ($addr,$pairs,$myusername,$mypassword,$httpsposttype) = @_;
  my ($port,$response,$unpw,%Header_Str,$page,%reply_headers,$posthttpsretries,$protocol);
  my $now = gmtime(time());

  if ($addr !~ /^https:/) {
    $addr =~ s/http:\/\///g;
    my $host = $addr;
    $host =~ s/https:\/\///;
    $host =~ s/\/(.*)//;
    my $path = $1;

    if ($host =~ /:(\d+)$/) {
      $port = $1;
      $host =~ s/(.*):\d+$/$1/;
    }
    else {
      $port = 80;
    }

    if ($host eq "") {
      print "Content-Type: text/html\n\n";
      print "Missing domain name in URL.  Please fix or contact technical support.";
    }

    my (%timetest);
    $timetest{time()} = "start";

    my $paddr = &socketopen($host,$port);

    $timetest{time()} = "postsocket";

    my $message = "POST /$path HTTP/1.0\r\n";
    $message = $message . "Host: $host\r\n";
    if (($myusername ne "") && ($mypassword ne "")) {
    }

    $message = $message . "Referrer: https://pay1.plugnpay.com/\r\n";
    $message = $message . "Content-Type: application/x-www-form-urlencoded\nContent-Length: ";
    my $temp = length($pairs);
    $message = $message . "$temp\r\n\r\n";
    $message = $message . $pairs . "\r\n\r\n";

    $response = &socketwrite($message,$host,$path,$paddr,$httpsposttype);

    $timetest{time()} = "postresponse";

    my $now = gmtime(time());

    if ($httpsposttype eq "raw") {
      return($response);
    }
  }
  else {
    if (($myusername ne "") && ($mypassword ne "")) {
      $unpw = encode_base64("$myusername:$mypassword");
      %Header_Str = (%Header_Str,'Authorization',"Basic $unpw");
    }
    my $host = $addr;
    $host =~ s/https:\/\///;
    $host =~ s/\/(.*)//;
    my $path = $1;

    if ($host =~ /:(\d+)$/) {
      $port = $1;
      $host =~ s/(.*):\d+$/$1/;
    }
    else {
      $port = 443;
    }

    if ($host eq "") {
      print "Content-Type: text/html\n\n";
      print "Missing domain name in URL.  Please fix or contact technical support.";
    }

    my $posthttpsretries = 0;
    if ($httpsposttype eq "low") {
      ($page, $response, %reply_headers) = post_https_low("$host",$port, "/$path",'',$pairs);
      my ($kk);
      if ($host =~ /dietsmart/i) {
        while(($response eq "") && ($kk < 5)) {
          ($page, $response, %reply_headers) = post_https_low("$host",$port, "/$path",'',$pairs);
          $kk++;
        }
      }
    }
    else {
      ($page, $response, %reply_headers) = post_https("$host", $port, "/$path", make_headers(%Header_Str), $pairs);
      while ($page =~ /Operation already in progress/) {
        if ($posthttpsretries >= 5) {
          last;
        }
        ($page, $response, %reply_headers) = post_https("$host", $port, "/$path", make_headers(%Header_Str), $pairs);
        $posthttpsretries++;
      }
    }
    if (($response =~ / 302 /) && ($reply_headers{'Location'} ne "")) {
      my $temp = $reply_headers{'Location'};
      if ($reply_headers{'Location'} =~ /^https:/) {
        $protocol = "https:";
      }
      else {
        $protocol = "http:";
      }
      $temp =~ s#.*/##;
      my $path2 = $path;
      $path2 =~ s/\w+\.\w+.*//;
      print "Location: $protocol//$host/$path2$temp\n\n";
    }
    else {
      if ($httpsposttype eq "raw") {
        return $page;
      }
      else {
        print "Content-Type: text/html\n\n";
        print $page;
      }
    }
  }
}

sub formpost_wallet {
    my ($addr,$pairs,$myusername,$mypassword) = @_;
    my ($unpw);
    if (($myusername ne "") && ($mypassword ne "")) {
      $unpw = encode_base64("$myusername:$mypassword");
    }
    my $host = $addr;
    $host =~ s/https:\/\///;
    $host =~ s/\/(.*)//;
    my $path = $1;

    my ($page, $response, %reply_headers) = post_https("$host", 443, "/$path", '', $pairs);
    print "Content-Type: text/html\n\n";
    return($page);
}


sub post_https_low {
  my ($count,$got,$respenc,$rlen,$respdec,$response,$page,$header,%headerhash,@headerlines,$rin,$rout,$temp);
  my ($site,$port,$path,$junk,$pairs) = @_;

  Net::SSLeay::load_error_strings();
  Net::SSLeay::SSLeay_add_ssl_algorithms();
  Net::SSLeay::randomize('/etc/passwd');
  if ($site =~ /dietsmart/) {
    $Net::SSLeay::slowly = 1;   # Add sleep so broken servers can keep up
  }
  # start building message
  my $message = "POST $path HTTP/1.0\r\n";
  $message = $message . "HOST: $site\r\n";
  $message = $message . "Content-Type: application/x-www-form-urlencoded\r\nContent-Length: ";
  my $pairslength = length($pairs);

  $message = $message . "$pairslength\r\n\r\n";
  $message = $message . $pairs . "\r\n\r\n";

  my $dest_ip = gethostbyname($site);
  my $dest_serv_params = sockaddr_in($port, $dest_ip);

  socket (S, &AF_INET, &SOCK_STREAM, 0) or die "socket: $!";
  my $numretries = 0;
  connect (S, $dest_serv_params) or ($numretries = &low_retry($dest_serv_params,$numretries));
  select  (S); $| = 1; select (STDOUT);

  my $ctx = Net::SSLeay::CTX_new() or die_now("Failed to create SSL_CTX $!");
  Net::SSLeay::CTX_set_options($ctx, &Net::SSLeay::OP_ALL)
  and Net::SSLeay::die_if_ssl_error("ssl ctx set options");
  my $ssl = Net::SSLeay::new($ctx) or die_now("Failed to create SSL $!");
  Net::SSLeay::set_fd($ssl, fileno(S));

  my $res = Net::SSLeay::connect($ssl) and Net::SSLeay::die_if_ssl_error("ssl connect");

  my $cipherListOutput = __FILE__ . ": " . Net::SSLeay::get_cipher($ssl);
  require PlugNPay::Logging::DataLog;
  new PlugNPay::Logging::DataLog({'collection' => 'cipher_list'})->log({
    'originalLogFile' => '/home/p/pay1/logfiles/ciphers.txt',
    'cipherList'      => $cipherListOutput
  });

  $res = Net::SSLeay::ssl_write_all($ssl, $message);
  Net::SSLeay::die_if_ssl_error("ssl write");
  shutdown S, 1;

  vec($rin, $temp = fileno(S),1) = 1;
  $count = 1024;
  if ($respenc =~ /443\s\(Operation already in progress\)/) {
    $respenc = "";
  }
  while($count && select($rout=$rin,undef,undef,90.0)) {
    $got = "";
    $got = Net::SSLeay::read($ssl);         # Perl returns undef on failure
    if ($got eq "") {
      last;
    }
    if ($got !~ /443\s\(Operation already in progress\)/) {
      $respenc = $respenc . $got;
    }
    Net::SSLeay::die_if_ssl_error("ssl read");
    $count--;
  }
  if ($count == 1) {
    &errmail("line 68","posthttpslow","no response received within timeout period $site, please try again\n","");
    exit;
  }
  $respdec = "";
  $rlen = length($respenc);
  my ($i);
  for ($i=0; $i<$rlen; $i++) {
    my $resp1 = substr($respenc,$i,1);
    my $newresp = $resp1 & "\x7f";
    $respdec = $respdec . $newresp;
  }
  $response = $respdec;

  Net::SSLeay::free ($ssl);               # Tear down connection
  Net::SSLeay::CTX_free ($ctx);
  # shutdown is a more insistant socket close than close from perl cookbook p621
  # also it doesn't return an error message like close does
  shutdown S,2;
  ($header,$page) = split(/\r\n\r\n/, $response,2);
  @headerlines = split(/\r\n/, $header);
  foreach (@headerlines) {
    if ($_ =~ /HTTP/) {
      $headerhash{'ResponseStatus'} = $_;
    }
    else {
      $_ =~ /^(\S+)\:\s*(.*)$/;
      $headerhash{$1} = $2;
    }
  }
  return $page,$response,%headerhash;
}


sub retry {
  my ($proto,$paddr,$numretries) = @_;
  $numretries++;
  if ($numretries >= 4) {
    die "connect: $!";
  }
  close(SOCK);
  socket(SOCK, PF_INET, SOCK_STREAM, $proto)  or die "socket: $!";
  connect(SOCK, $paddr) or ($numretries = &retry($proto,$paddr,$numretries));
  return($numretries);
}


sub low_retry {
  my ($dest_serv_params,$numretries) = @_;
  $numretries++;
  if ($numretries >= 4) {
    die "connect: $!";
  }
  shutdown S,2;
  socket (S, &AF_INET, &SOCK_STREAM, 0) or die "socket: $!";
  connect (S, $dest_serv_params) or ($numretries = &low_retry($dest_serv_params,$numretries));
}


sub socketopen {
  my ($addr,$port) = @_;
  my ($iaddr, $paddr, $proto, $line, $response);

  my $tstamp = scalar localtime(time());
  if ($port =~ /\D/) { $port = getservbyname($port, 'tcp') }
  die "No port" unless $port;
  $iaddr   = &inet_aton($addr) or die "$ENV{'REMOTE_ADDR'} no host: $$ $tstamp $addr $port";
  $paddr   = &sockaddr_in($port, $iaddr);

  $proto   = getprotobyname('tcp');

  socket(SOCK, PF_INET, SOCK_STREAM, $proto)  or die "socket: $!";
  my $numretries = 0;
  connect(SOCK, $paddr) or ($numretries = &retry($proto,$paddr,$numretries));
  return ($paddr);
}

sub socketwrite2 {
  my ($message,$host,$path,$paddr) = @_;
  my ($response,$headerflag,$finalresponse,$rin,$rout,$temp);
  send(SOCK, $message, 0, $paddr);
  $headerflag = 0;
  $finalresponse = "";

  vec($rin, $temp = fileno(SOCK),1) = 1;
  my $count = 1024;
  $response = "";
  $miscutils::socketfirstflag = 0;
  while ($count && select($rout=$rin,undef,undef,80.0)) {
    recv(SOCK,$response,32736,0);
    $finalresponse = $finalresponse . $response;
    $count--;
  }

  close(SOCK);
  return($finalresponse);
}


sub socketwrite {
  my ($message,$host,$path,$paddr,$httpsposttype) = @_;
  my ($response,$headerflag,$finalresponse,$rin,$rout,$temp);
  send(SOCK, $message, 0, $paddr);
  $headerflag = 0;
  $finalresponse = "";

  vec($rin, $temp = fileno(SOCK),1) = 1;
  my $count = 1024;
  $response = "";
  my $wholeresponse = "";
  $miscutils::socketfirstflag = 0;
  while ($count && select($rout=$rin,undef,undef,80.0)) {
    recv(SOCK,$response,32736,0);

    if ($headerflag == 0) {
      $finalresponse = $finalresponse . $response;
      if ($finalresponse =~ /\r{0,1}\n\r{0,1}\n/) {
        $_ = $response;
        my ($string,$dummy) = split(/\r{0,1}\n\r{0,1}\n/,$finalresponse);
        my $index = length($string);
        $response = substr($finalresponse,$index);
        $headerflag = 1;

        if ($finalresponse =~ /\nLocation:/) {
          my $temp = substr($finalresponse,index($finalresponse,"Location:")); if ($temp =~ /Location: \w+\.\w+\r*\n/) {
            $temp = substr($temp,10);
            my $path2 = $path;
            $path2 =~ s/\w+\.\w+.*//;
            if ($httpsposttype eq "raw") {
              $wholeresponse = "Location: http://$host/$path2$temp<br>\n";
            }
            else {
              print "Location: http://$host/$path2$temp<br>\n";
            }
          }
          else {
            if ($httpsposttype eq "raw") {
              $wholeresponse = "$temp\n";
            }
            else {
              print "$temp\n";
            }
          }
          close(SOCK);
          if ($httpsposttype eq "raw") {
            return $wholeresponse;
          }
          else {
            exit;
          }
        }
      }
      else {
        if ($response =~ /\<\/html\>/i) {
          if ($httpsposttype eq "raw") {
            $wholeresponse = $wholeresponse . $response;
          }
          else {
            print $response;
          }
          last;
        }
        next;
      }
    }

    if ($miscutils::socketfirstflag == 0) {
      if ($httpsposttype eq "raw") {
        $wholeresponse = "Content-Type: text/html\n\n";
      }
      else {
        print "Content-Type: text/html\n\n";
      }
      $miscutils::socketfirstflag = 1;
    }
    if ($httpsposttype eq "raw") {
      $wholeresponse = $wholeresponse . $response;
    }
    else {
      print $response;
    }

    if ($response =~ /\<\/html\>/i) {
      last;
    }

    $count--;
  }

  close(SOCK);
  if ($httpsposttype eq "raw") {
    return($wholeresponse);
  }
  else {
    return($finalresponse);
  }
}


sub ftp {
  #  $sourcefile  -  Name of File on our server
  #  $destfile    -  Name of File on remote server
  require Net::FTP;
  my($host,$FTPun,$FTPpw,$remotedir,$sourcefile,$destfile,$port,$action,$debug_level) = @_;
  my (%FTPresult);
  if ($debug_level eq "") {
    $debug_level = "1";
  }
  if ($port eq "") {
    $port = "21";
  }
  $|=1;
  if ($host eq "") {
    $FTPresult{'Msg'} = "Host name is blank";
    $FTPresult{'FinalStatus'} = "failure";
  }
  if ($FTPun eq "") {
    $FTPresult{'Msg'} = "FTP username is blank";
    $FTPresult{'FinalStatus'} =  "failure";
  }
  if ($FTPpw eq "") {
    $FTPresult{'Msg'} = "FTP password is blank";
    $FTPresult{'FinalStatus'} =  "failure";
  }
  if ($remotedir eq "") {
    $FTPresult{'Msg'} = "Remote directory is blank";
    $FTPresult{'FinalStatus'} =  "failure";
  }
  if ($sourcefile eq "") {
    $FTPresult{'Msg'} = "Source file is blank";
    $FTPresult{'FinalStatus'} =  "failure";
  }
  if ($destfile eq "") {
    $FTPresult{'Msg'} = "Destination file is blank";
    $FTPresult{'FinalStatus'} =  "failure";
  }

  my $ftp = Net::FTP->new("$host", 'Timeout' => 2400, 'Debug' => $debug_level, 'Port' => $port);
  if ($ftp eq "") {
    $FTPresult{'Msg'} = "Host $host is no good";
    $FTPresult{'FinalStatus'} =  "failure";
  }

  if ($ftp->login("$FTPun","$FTPpw") eq "") {
    $FTPresult{'Msg'} = "Username $FTPun and password don't work";
    $FTPresult{'FinalStatus'} =  "failure";
  }

  $FTPresult{'Msg'} = "Successful Login";
  $FTPresult{'FinalStatus'} = "success";

  if($FTPresult{'FinalStatus'} ne "success") {
    return %FTPresult;
  }

  my $mode = "A";

  $FTPresult{'Msg'} = $FTPresult{'Msg'} . $ftp->cwd("$remotedir");
  $FTPresult{'Msg'} = $FTPresult{'Msg'} . $ftp->type("$mode");

  if($action eq "put") {
    $FTPresult{'Msg'} = $FTPresult{'Msg'} . $ftp->put("$sourcefile", "$destfile");
  }
  elsif ($action eq "get") {
    $FTPresult{'Msg'} = $FTPresult{'Msg'} . $ftp->get("$sourcefile", "$destfile");
  }
  else {
    $FTPresult{'Msg'} = "Invalid Action";
    $FTPresult{'FinalStatus'} = "failure";
  }
  $FTPresult{'Msg'} = $FTPresult{'Msg'} . $ftp->quit;

  return %FTPresult;

}

sub underscore_to_hyphen {
  my (%query) = @_;
  my ($key);
  foreach $key (keys %query) {
    if(($key !~ /^acct_code/) && ($key =~ /\_/)) {
      my $temp = $query{$key};
      delete $query{$key};
      $key =~ tr/\_/\-/;
      $query{$key} = $temp;
    }
  }
  return (%query);
}

sub hyphen_to_underscore {
  my (%query) = @_;
  my ($key);
  foreach $key (keys %query) {
    if(($key ne "acct_code") && ($key =~ /\-/)) {
      my $temp = $query{$key};
      delete $query{$key};
      $key =~ tr/\-/\_/;
      $query{$key} = $temp;
    }
  }
  return (%query);
}

sub lower_to_uppercase {
  my (%query) = @_;
  my ($key);
  foreach $key (keys %query) {
    my $temp = $query{$key};
    delete $query{$key};
    $key = uc $key;
    $query{$key} = $temp;
  }
  return (%query);
}

sub upper_to_lowercase {
  my (%query) = @_;
  my ($key);
  foreach $key (keys %query) {
    if($key ne "orderID") {
      my $temp = $query{$key};
      delete $query{$key};
      $key = lc $key;
      $query{$key} = $temp;
   }
  }
  return (%query);
}

sub input_cold_fusion {
  my (%query) = @_;
  %query = &underscore_to_hyphen(%query);
  %query = &upper_to_lowercase(%query);
  if (($query{'orderID'} eq "") && ($query{'orderid'} ne "")) {
    $query{'orderID'} = $query{'orderid'};
  }
  return (%query);
}

# TODO add a metric here, doubt it ever gets called.
sub output_cold_fusion {
  my (%query) = @_;
  $query{'aux-msg'} =~ s/\:/ /g;
  $query{'auth-msg'} =~ s/\:/ /g;
  %query = &hyphen_to_underscore(%query);
  %query = &lower_to_uppercase(%query);
  return (%query);
}


sub check_trans {
  my %query = @_;
  require PlugNPay::GatewayAccount;
  my $username = $query{'publisher-name'};
  my $gatewayAccount = new PlugNPay::GatewayAccount($username);
  my $featureVersion = $gatewayAccount->getFeatures()->get('queryTransVersion');

  if ($featureVersion == 2 || $gatewayAccount->usesUnifiedProcessing()) {
    require PlugNPay::Processor::Process::Verification;
    my $verifier = new PlugNPay::Processor::Process::Verification();
    my $responses = $verifier->checkTransaction($username,\%query);
    my $response = $responses->{$query{'orderID'}};
    if (ref($response) ne 'HASH' && ref($responses) eq 'HASH') {
      my @keys = keys %{$responses};
      $response = $responses->{$keys[0]} || {};
    }
    return %{$response};
  } else {
    my $result = _legacyCheckTrans({
      orderId => $query{'orderID'},
      usernameParameter => $query{'merchant'} ? 'merchant' : 'publisher-name',
      username => $query{'merchant'} || $query{'publisher-name'},
      accountType => $query{'accttype'},
      processor => $query{'processor'},
      operation => $query{'mode'},
      amount => $query{'card-amount'},
      cardName => $query{'card-name'}
    });

    # the following is to ensure compatibility
    $result->{'order-id'} = $result->{'orderID'} = $result->{'orderId'} if defined $result->{'orderId'};

    return %{$result};
  }
}

# this one is actually testable
sub _legacyCheckTrans {
  my $input = shift;
  my $testData = shift || {};

  my ($chkfinalstatus,$chkdescr);

  my $orderId = $input->{'orderId'};
  my $username = $input->{'username'};
  my $accountType = $input->{'accountType'};
  my $processor = $input->{'processor'};
  my $operation = $input->{'operation'};
  my $amount = $input->{'card-amount'};
  my $cardName = $input->{'card-name'};
  my $usernameParameter = $input->{'usernameParameter'};

  ########################################################################################################################
  # This section loads account and processor information, or uses $testData if test the necessary test data is provided. #
  ########################################################################################################################
  # load gateway account if test data is not provided (i.e. normal circumstances)
  my $gatewayAccountTest = defined $testData->{'exists'}   && defined $testData->{'custstatus'} &&
                           defined $testData->{'testmode'} && defined $testData->{'features'}   &&
                           defined $testData->{'processor'};
  my $ga = $gatewayAccountTest || new PlugNPay::GatewayAccount($username);
  my $exists     = $testData->{'exists'}     || $ga->exists();
  my $custstatus = $testData->{'custstatus'} || $ga->getStatus();
  my $testmode   = $testData->{'testmode'}   || $ga->isTestModeEnabled();

  my %feature; # use testData's features if present.
  if ($testData->{'features'}) {
    %feature = %{$testData->{'features'}};
  } else {
    %feature = %{$ga->getFeatures()->getFeatures()};
  }


  my $allowMultipleReturns = $feature{'allow_multret'} ? 1 : 0;

  if (!defined $processor || $processor eq '') {
    $processor = $testData->{'processor'} || $ga->getCardProcessor();
  }

  require PlugNPay::Processor;
  # testData reauthAllowd will short circuit causing processor not to be loaded.
  my $processorTest = defined $testData->{'reauthAllowed'};
  my $processorObj = $processorTest || new PlugNPay::Processor({'shortName' => $processor});
  my $reauthAllowed = $testData->{'reauthAllowed'} || $processorObj->getReauthAllowed();

  # get processor info to get $authType
  my $processorAccountTest = defined $testData->{'authType'} && defined $testData->{'isPetroleum'};
  my $processorAccount = $processorAccountTest  || new PlugNPay::Processor::Account({ gatewayAccount => $username, processorName => $processor });
  my $authType    = $testData->{'authType'}    || $processorAccount->getSettingValue('authType');
  my $isPetroleum = $testData->{'isPetroleum'} || ($processorAccount->getIndustry() eq 'petroleum');
  ########################################################################
  # This is the end of the section that loads account and processor data #
  ########################################################################

  if (!$exists) {
    my %result;
    $result{'FinalStatus'} = "problem";
    $result{'MStatus'} = "problem";
    $result{'MErrMsg'} = sprintf('Invalid variable %s. Transaction could not be processed.', $usernameParameter);
    return \%result;
  }


  if ($custstatus eq "debug" || ($testmode eq "yes" && $cardName eq "pnptest")) {
    return _legacyCheckTransDebugMode({
      username  => $username,
      orderId   => $orderId,
      amount    => $amount,
      operation => $operation,
      testData  => $testData
    });
  }

  my $timeadjust = (180 * 24 * 3600);
  my (undef,$datestr) = &miscutils::gendatetime("-$timeadjust");

  #########################################################################
  # HEY LOOK AT ME I'M AN IMPORTANT LINE OF CODE AND I'M EASY TO OVERLOOK #
  #########################################################################
  $operation = $operation eq 'mark' ? 'postauth' : $operation;

  if (inArray($operation,['reauth','newreturn','return','returnprev','void','mark','postauth'])) {
    my $duplicateCheckResult = _legacyCheckTransDuplicateCheck({
      username             => $username,
      operation            => $operation,
      processor            => $processor,
      allowMultipleReturns => $allowMultipleReturns,
      orderId              => $orderId,
      allowMultipleReturns => $allowMultipleReturns,
      startDate            => $datestr
    },$testData);
    return $duplicateCheckResult if $duplicateCheckResult;
  }

  return _legacyCheckTransGetFlags({
    username             => $username,
    operation            => $operation,
    authType             => $authType,
    allowMultipleReturns => $allowMultipleReturns,
    orderId              => $orderId,
    startDate            => $datestr,
    accountType          => $accountType,
    reauthAllowed        => $reauthAllowed,
    allowMultipleReturns => $allowMultipleReturns,
    isPetroleum          => $isPetroleum
  }, $testData);
}

# returns a duplicate  response if there is a duplicate, or undef if it is not a duplicate.
sub _legacyCheckTransDuplicateCheck {
  my $input = shift;
  my $testData = shift || {};
  my $username             = $input->{'username'};
  my $orderId              = $input->{'orderId'};
  my $operation            = $input->{'operation'};
  my $allowMultipleReturns = $input->{'allowMultipleReturns'};
  my $processor            = $input->{'processor'};

  my ($chkfinalstatus,$chkdescr);

  my $dbs = new PlugNPay::DBConnection();
  if ($operation eq "reauth") {
    my $query = 'SELECT finalstatus,descr FROM trans_log FORCE INDEX(PRIMARY) WHERE orderid=? AND username=? AND operation=? AND finalstatus=? LIMIT 1';
    my $values = [$orderId,$username,'reauth','success'];
    $dbs->fetchallOrDie('pnpdata',$query,$values,{}, { callback => sub {
      my $row = shift;
      $chkfinalstatus = $row->{'finalstatus'};
      $chkdescr = $row->{'descr'};
    }, mockRows => $testData->{'mockDuplicateRows'} });
  } elsif ($operation eq "return" && $processor eq 'wirecard') {
    # this being wirecard specific seems rather odd, @dprice says it might be related to auth capture?  need to talk to @cprice
    # I'm wondering if wirecard had a high failure rate for returns
    my $query = 'SELECT finalstatus,descr FROM trans_log FORCE INDEX(PRIMARY) WHERE orderid=? AND username=? AND operation=? AND finalstatus IN (?,?,?) LIMIT 1';
    my $values = [$orderId,$username,'return','success','pending','locked'];
    $dbs->fetchallOrDie('pnpdata',$query,$values,{},{ callback => sub {
      my $row = shift;
      $chkfinalstatus = $row->{'finalstatus'};
      $chkdescr = $row->{'descr'};
    }, mockRows => $testData->{'mockDuplicateRows'} });
  } else { # all other operations
    my $query = 'SELECT finalstatus,descr FROM trans_log FORCE INDEX(PRIMARY) WHERE orderid=? AND username=? AND operation=? LIMIT 1';
    my $values = [$orderId,$username,$operation];
    $dbs->fetchallOrDie('pnpdata',$query,$values,{},{ callback => sub {
      my $row = shift;
      $chkfinalstatus = $row->{'finalstatus'};
      $chkdescr = $row->{'descr'};
    }, mockRows => $testData->{'mockDuplicateRows'} });
  }

  if (($operation ne "return" || !$allowMultipleReturns) && $chkfinalstatus ne '') {
    return {
      FinalStatus => "$chkfinalstatus",
      MStatus => "$chkfinalstatus",
      MErrMsg => "Duplicate $operation: $chkdescr",
      Duplicate => 'yes'
    };
  }

  return undef;
}

sub _legacyCheckTransDebugMode {
  my $input = shift;
  my $orderId   = $input->{'orderId'};
  my $amount    = $input->{'amount'};
  my $username  = $input->{'username'};
  my $operation = $input->{'operation'};

  my %result;

  $result{'debug'} = 1;
  $result{'MErrMsg'} = "SYSTEM IN DEBUG MODE:";

  if ($operation eq "return") {
    if ($orderId ne "" && $amount ne '' && $username ne '') {
      $result{'FinalStatus'} = "pending";
      $result{'MStatus'} = "pending";
    } else {
      $result{'FinalStatus'} = "problem";
      $result{'MStatus'} = "problem";
      $result{'MErrMsg'} .= "Missing information. Transaction could not be returned.";
    }
  } elsif ($operation eq "mark") {
    if ($orderId ne "" && $amount ne "" && $username ne "") {
      $result{'FinalStatus'} = "pending";
      $result{'MStatus'} = "pending";
    } else {
      $result{'FinalStatus'} = "problem";
      $result{'MStatus'} = "problem";
      $result{'MErrMsg'} .= "Missing information. Transaction could not be marked.";
    }
  } elsif ($operation eq "void") {
    if ($orderId ne '' && $username ne '') {
      $result{'FinalStatus'} = "success";
      $result{'MStatus'} = "success";
    } else {
      $result{'FinalStatus'} = "problem";
      $result{'MStatus'} = "problem";
      $result{'MErrMsg'} .= "Missing information. Transaction could not be voided.";
    }
  }

  return %result;
}

sub _legacyCheckTransGetFlags {
  my $input = shift;
  my $testData = shift || {};
  my $username      = $input->{'username'};
  my $authType      = $input->{'authType'};
  my $orderId       = $input->{'orderId'};
  my $startDate     = $input->{'startDate'};
  my $accountType   = $input->{'accountType'};
  my $reauthAllowed = $input->{'reauthAllowed'};
  my $isPetroleum   = $input->{'$isPetroleum'};
  my $allowMultipleReturns = $input->{'allowMultipleReturns'};

  my $queryInfo = _legacyCheckTransGetFlagsGenerateQuery($input);

  my $amount;
  my %trans;

  # reauth is the only one that starts out true.
  $trans{'reauth_flag'} = 1;

  my $dbs = new PlugNPay::DBConnection();

  $dbs->fetchallOrDie('pnpdata', $queryInfo->{'query'}, $queryInfo->{'values'}, {}, { callback => sub {
    my $row = shift; # the callback takes a row from the db as an argument

    # the following are expected to be in each row of the results or test data:
    my $operation   = $row->{'operation'};
    my $status      = $row->{'finalstatus'};
    my $amount      = $row->{'amount'};
    my $transDate   = $row->{'trans_date'};
    my $accountType = $row->{'accttype'};
    my $rowOrderId  = $row->{'orderid'};

    $trans{'orderId'} = $rowOrderId;
    $trans{'amount'} = $amount;

    if ($status eq 'success') {
      $trans{'authamt'} = $amount if ($operation eq 'auth');
      $trans{'auth_flag'} = 1     if (inArray($operation,['auth','forceauth']));
      $trans{'settled_flag'} = 1  if ($operation eq 'postauth');
      $trans{'void_flag'} = 1     if ($operation eq "void");
      $trans{'reauth_flag'} = 0   if (inArray($operation,['postauth','void','reauth']));
      $trans{'setlret_flag'} = 1  if ($operation eq "return");
      $trans{'settled_flag'} = 1  if ($operation eq "auth" && $authType eq "authcapture");
    }

    if ($status eq 'locked') {
      if ($operation eq "postauth") {
        $trans{'mark_flag'} = 0;
        $trans{'locked_flag'} = 1;
      }
    }

    if ($status eq 'pending') {
      if (inArray($operation,['postauth','return'])) {
        $trans{'mark_flag'} = 1;
      }
      if ($operation eq 'return') {
        $trans{'mark_ret_flag'} = 1;
      }
    }

    if ($operation eq 'storedata') {
      $trans{'storedata_flag'} = 1;
      $trans{'reauth_flag'} = 0;
    }
  }, mockRows => $testData->{'mockTransactionHistory' }});

  # Return
  if ($trans{'void_flag'} != 1 && $trans{'settled_flag'} == 1 && $trans{'mark_ret_flag'} == 0 && $trans{'locked_flag'} != 1) {
    if ($trans{'setlret_flag'} != 1 || $allowMultipleReturns eq "1") {
      $trans{'allow_return'} = 1;
    }
  }

  # Mark
  if ($trans{'auth_flag'} == 1 && $trans{'mark_flag'} == 0 && $trans{'void_flag'} !=1) {
    $trans{'allow_mark'} = 1;
  }

  # Re-auth

  if ($reauthAllowed == 1 && $accountType ne "checking" && $trans{'settled_flag'} == 0 && $trans{'reauth_flag'} == 1 && $trans{'storedata_flag'} == 0) {
    $trans{'allow_reauth'} = 1;
  }

  # Void
  if (($trans{'settled_flag'} == 0 || $isPetroleum) && $trans{'void_flag'} != 1 && $trans{'setlret_flag'} == 0 && $trans{'locked_flag'} != 1 && $trans{'storedata_flag'} == 0) {
    $trans{'allow_void'} = 1;
  }

  return \%trans;
}

sub _legacyCheckTransGetFlagsGenerateQuery {
  my $input = shift;
  my $username = $input->{'username'};
  my $orderId = $input->{'orderId'};
  my $startDate = $input->{'startDate'};
  my $accountType = $input->{'accountType'};

  my @queryValues;
  my @query;
  push @query, "SELECT orderid,amount,trans_date,trans_time,finalstatus,operation";
  push @query, "FROM trans_log FORCE INDEX(PRIMARY)"; # primary is orderid, username, operation, trans_time
  push @query, "WHERE orderid = ?";   push @queryValues, $orderId;
  push @query, "AND username  = ?";    push @queryValues, $username;

  my @operations = ('auth','postauth','return','void','reauth','retry','forceauth','storedata');
  push @query, 'AND operation IN (' . join(',',map {'?'} @operations) . ')';
  push @queryValues, @operations;

  my $qb = new PlugNPay::Database::QueryBuilder();
  my ($today) = &miscutils::gendatetime_only();
  my $dates = $qb->generateDateRange({ start_date => $startDate, end_date => $today });

  # we only want to look at
  push @query, sprintf('AND trans_date IN (%s)', $dates->{'params'});
  push @queryValues, @{$dates->{'values'}};



  push @query, "AND COALESCE(duplicate,'') = ?";
  push @queryValues, '';

  # matches against accttype, defaulting to 'credit' if null or empty string for what is in db and inputted into query.
  push @query, "AND COALESCE(NULLIF(accttype,''),'credit') = COALESCE(NULLIF(?,''),'credit')";
  push @queryValues, $accountType;

  # the following line used to be order by orderid, trans_time.  makes no sense to order by order id when the query is 'orderid = ?'
  push @query, "ORDER BY trans_time DESC";
  my $searchstr = join(' ',@query);

  return { query => $searchstr, values => \@queryValues};
}

sub start_date {
  my ($select_yr,$select_mo,$select_dy,$start_yr,$start_mo,$start_dy) = @_;
  my %endday = (1,31,2,28,3,31,4,30,5,31,6,30,7,31,8,31,9,30,10,31,11,30,12,31);
  my %month_array = (1,"Jan",2,"Feb",3,"Mar",4,"Apr",5,"May",6,"Jun",7,"Jul",8,"Aug",9,"Sep",10,"Oct",11,"Nov",12,"Dec");
  my %month_array2 = ("Jan","01","Feb","02","Mar","03","Apr","04","May","05","Jun","06","Jul","07","Aug","08","Sep","09","Oct","10","Nov","11","Dec","12");
  my ($dummy,$sday,$smonth,$syear);
  my (%selectedsday,%selectedmo,%selected,$yyear,$ii,$iii);
  ($dummy,$dummy,$dummy,$sday,$smonth,$syear) = gmtime(time());
  if ($select_yr eq "") {
    $yyear = $syear + 1900;
  }
  else {
    $yyear = $select_yr;
  }
  if ($select_mo eq "") {
    $ii = $smonth+1;
  }
  else {
    $ii = $select_mo;
  }
  if ($select_dy eq "") {
    $iii = "1";
  }
  else {
    $iii = $select_dy + 0;
  }
  $yyear = sprintf("%04d",$yyear);
  $ii = sprintf("%02d",$ii);
  $iii = sprintf("%02d",$iii);

  my $html = "<select name=\"startmonth\">\n";
  #my $ii = $smonth+1;
  $selectedmo{$ii} = " selected";
  for (my $i=1; $i<=12; $i++) {
    my $k = sprintf("%02d",$i);
    $html .= "<option value=\"$k\" $selectedmo{$k}>$month_array{$i}</option>\n";
  }
  $html .= "</select>";
  $html .= "<select name=\"startday\">\n";
  $selectedsday{$iii} = " selected";
  for (my $i=1; $i<=31; $i++) {
    my $k = sprintf("%02d",$i);
    $html .= "<option value=\"$k\" $selectedsday{$k}>$k</option>\n";
  }
  $html .= "</select>";
  $html .= "<select name=\"startyear\">\n";
  $selected{$yyear} = " selected";
  for(my $i=$yyear-4; $i<=$yyear+1; $i++) {
    if ($start_yr > $yyear) {
      next;
    }
    $html .= "<option value=\"$i\" $selected{$i}>$i</option>\n";
  }
  $html .= "</select>";

  return $html;
}


sub end_date {
  my ($select_yr,$select_mo,$select_dy) = @_;
  my %endday = (1,31,2,28,3,31,4,30,5,31,6,30,7,31,8,31,9,30,10,31,11,30,12,31);
  my %month_array = (1,"Jan",2,"Feb",3,"Mar",4,"Apr",5,"May",6,"Jun",7,"Jul",8,"Aug",9,"Sep",10,"Oct",11,"Nov",12,"Dec");
  my %month_array2 = ("Jan","01","Feb","02","Mar","03","Apr","04","May","05","Jun","06","Jul","07","Aug","08","Sep","09","Oct","10","
Nov","11","Dec","12");

  my (%selectedmo,%selectededay,%selected,$yyear,$ii,$iii,$dummy,$sday,$smonth,$syear);

  ($dummy,$dummy,$dummy,$sday,$smonth,$syear) = gmtime(time());
  if ($select_yr eq "") {
    $yyear = $syear + 1900;
  }
  else {
    $yyear = $select_yr;
  }
  if ($select_mo eq "") {
    $ii = $smonth+1;
  }
  else {
    $ii = $select_mo;
  }
  if ($select_dy eq "") {
    $iii = $endday{$ii};
  }
  else {
    $iii = $select_dy + 0;
  }
  $yyear = sprintf("%04d",$yyear);
  $ii = sprintf("%02d",$ii);
  $iii = sprintf("%02d",$iii);
  my $html = "<select name=endmonth xx=\"$smonth:$select_mo:$ii\">\n";

  $selectedmo{$ii} = " selected";
  for (my $i=1; $i<=12; $i++) {
    my $k = sprintf("%02d",$i);
    $html .= "<option value=\"$k\" $selectedmo{$k}>$month_array{$i}</option>\n";
  }
  $html .= "</select>";
  $html .= "<select name=\"endday\">\n";
  $selectededay{$iii} = " selected";
  for (my $i=1; $i<=31; $i++) {
    my $k = sprintf("%02d",$i);
    $html .= "<option value=\"$k\" $selectededay{$k}>$k</option>\n";
  }
  $html .= "</select>";
  $html .= "<select name=\"endyear\">\n";
  $selected{$yyear} = " selected";
  for(my $i=$yyear-5; $i<=$yyear+1; $i++) {
    $html .= "<option value=\"$i\" $selected{$i}>$i</option>\n";
  }
  $html .= "</select>";

  return $html;
}

sub exp_date {
  my ($expmonthname,$expyearname) = @_;
  my (%selectedmo,%selectedye,$selected_month,$selected_year,$dummy,$sday,$smonth,$syear);

  ($dummy,$dummy,$dummy,$sday,$smonth,$syear) = gmtime(time());
  $selected_month = sprintf("%02d",($smonth + 1));
  $selected_year = sprintf("%04d",($syear + 1900));

  # generate HTML for exp month
  my $html = "<select name=\"$expmonthname\">\n";
  $selectedmo{$selected_month} = "selected";
  for (my $i=1; $i<=12; $i++) {
    my $k = sprintf("%02d",$i);
    $html .= "<option value=\"$k\" $selectedmo{$k}>$k</option>\n";
  }
  $html .= "</select>";

  # generate HTML for exp year
  $html .= "<select name=\"$expyearname\">\n";
  $selectedye{$selected_year} = " selected";
  for (my $i=$selected_year; $i<=($selected_year + 10); $i++) {
    my $k = sprintf("%02d",$i);
    $html .= "<option value=\"" . substr($k,2)  . "\" $selectedye{$k}>$k</option>\n";
  }
  $html .= "</select>";

  return $html;
}

sub sslsocketwrite {
  my ($req,$host,$port,$returntype) = @_;

  Net::SSLeay::load_error_strings();
  Net::SSLeay::SSLeay_add_ssl_algorithms();
  Net::SSLeay::randomize('/etc/passwd');

  my $dest_serv = $host;
  $port = $port;

  my $dest_ip = gethostbyname ($dest_serv);
  my $dest_serv_params  = sockaddr_in($port, $dest_ip);

  my $flag = "pass";
  socket  (S, &AF_INET, &SOCK_STREAM, 0)  or return(&errmssg( "socket: $!",1));

  connect (S, $dest_serv_params)          or return(&errmssg("connect: $!",1));

  if ($flag ne "pass") {
    return;
  }
  select  (S); $| = 1; select (STDOUT);   # Eliminate STDIO buffering

  # The network connection is now open, lets fire up SSL
  my $ctx = Net::SSLeay::CTX_v2_new() or die_now("Failed to create SSL_CTX $!");
                     # stops "bad mac decode" and "data between ccs and finished" errors by forcing version 2


  Net::SSLeay::CTX_set_options($ctx, &Net::SSLeay::OP_ALL) and Net::SSLeay::die_if_ssl_error("ssl ctx set options");
  my $ssl = Net::SSLeay::new($ctx) or die_now("Failed to create SSL $!");
  Net::SSLeay::set_fd($ssl, fileno(S));   # Must use fileno
  my $res = Net::SSLeay::connect($ssl) or die "ssl connect: $!";

  my $cipherListOutput = __FILE__ . ": " . Net::SSLeay::get_cipher($ssl);
  require PlugNPay::Logging::DataLog;
  new PlugNPay::Logging::DataLog({'collection' => 'cipher_list'})->log({
    'originalLogFile' => '/home/p/pay1/logfiles/ciphers.txt',
    'cipherList'      => $cipherListOutput
  });

  # Exchange data
  $res = Net::SSLeay::ssl_write_all($ssl, $req);  # Perl knows how long $msg is
  Net::SSLeay::die_if_ssl_error("ssl write");

  my $respenc = "";

  my ($rin,$rout,$temp);
  vec($rin, $temp = fileno(S),1) = 1;
  my $count = 8;
  while($count && select($rout=$rin,undef,undef,20.0)) {
    my $got = Net::SSLeay::read($ssl);         # Perl returns undef on failure
    $respenc = $respenc . $got;
    if ($respenc =~ /\x03/) {
      last;
    }
    Net::SSLeay::die_if_ssl_error("ssl read");
    $count--;
  }

  my $response = $respenc;

  Net::SSLeay::free ($ssl);               # Tear down connection
  Net::SSLeay::CTX_free ($ctx);
  close S;

  my $header;
  ($header,$response) = split(/\r{0,1}\n\r{0,1}\n/, $response);

  return $response, $header;
}

# Removed multipart_post function in T1443 as per instructions

sub getquery {
  my ($querystr) = @_;

  require PlugNPay::CGI;

  ##  PlugNPay::CGI - caches the CGI object.
  ## Calling new CGI with a passed argument returns original object and passed argument is ignored.
  ## In order to bypass this issue calling originalNew CGI allows new CGI object to be created with passed argument.

  my $RM = $ENV{'REQUEST_METHOD'};
  my $CT = $ENV{'CONTENT_TYPE'};

  delete $ENV{'REQUEST_METHOD'};
  my $query = originalNew CGI($querystr);
  my %query = ();
  my $name = "";
  my (@names) = $query->param;
  foreach $name (@names) {
    $query{$name} = $query->param($name);
  }

  if (exists $query{'POSTDATA'}) {
    $query{'POSTDATA'} =~ /publisher-name=([a-z0-9]*)/;
    my $merchant = $1;
    my $date = gmtime(time());
    require PlugNPay::Logging::DataLog;
    new PlugNPay::Logging::DataLog({'collection' => 'debug'})->log({
      'originalLogFile' => '/home/p/pay1/database/debug/proxy_problem.txt',
      'username'        => $merchant,
      'ipAddress'       => $ENV{'REMOTE_ADDR'},
      'requestMethod'   => $RM,
      'contentType'     => $CT
    });

    my $data1 = originalNew CGI($query{'POSTDATA'});
    my %data = ();
    my (@names) = $data1->param;
    foreach $name (@names) {
      $data{$name} = $data1->param($name);
    }
    %query = (%data,%query);

  }
  return %query;
}

sub mysleep {
  my ($delayseconds) = @_;

  my $time1 = time();

  select undef,undef,undef,1.00;

  my $time2 = time();
  while ($time2 < $time1 + $delayseconds) {
    my $delta = $time2 - $time1;
    my $newdelay = $time1 + $delayseconds - $time2;
    $newdelay = sprintf("%.2f", $newdelay);
    select undef,undef,undef,$newdelay;
    $time2 = time();
  }
}

sub merch_fraud {
  my ($username,$operation,$limits,$status,$query,$feature) = @_;

  my %auth_warn_limit = ('jmd','750000','jpy','1500000');
  my %retn_warn_limit = ('jmd','150000','jpy','300000');

  my ($type,$settype,%stuff,%bindata);

  if ($operation =~ /^(auth|forceauth)$/) {
    $type = "auth";
    $settype = "auth";
  }
  elsif ($operation =~ /^(return)$/) {
    $type = "return";
    $settype = "retn";
  }
  else {
    return;
  }

  my $dbh = &dbhconnect("pnpmisc");

  my (%limits,%merchfraud,$logdesc,$checked_orderid,$chkorderid,$auth_warn_limit,$retn_warn_limit);
  my @array = split(/\,/,$limits);
  foreach my $entry (@array) {
    my($name,$value) = split(/\=/,$entry);
    if ($name eq "email") {
      $name = "riskemail";
    }
    $limits{$name} = $value;
    $limits{'merchfraudflag'} = 1;
  }

  if ($retn_warn_limit < $limits{'max_retn_vol'}) {
    $retn_warn_limit = sprintf("%.2f",$limits{'max_retn_vol'} * 0.75);
  }

  if ($auth_warn_limit < $limits{'max_auth_vol'}) {
    $auth_warn_limit = sprintf("%.2f",$limits{'max_auth_vol'} * 0.75);
  }

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
  my $date = sprintf("%04d%02d%02d",$year+1900,$mon+1,$mday);

  my ($currency,$amount) = split('\ ',$$query{'amount'});

  if (exists $auth_warn_limit{$currency}) {
    $auth_warn_limit = $auth_warn_limit{$currency};
  }
  else {
    $auth_warn_limit = "15000";
  }

  if (exists $retn_warn_limit{$currency}) {
    $retn_warn_limit = $retn_warn_limit{$currency};
  }
  elsif ($$query{'acct_code4'} =~ /credit$/i) {
    $retn_warn_limit = "300";
  }
  else {
    $retn_warn_limit = "3000";
  }

  if (($$query{'acct_code4'} =~ /credit$/i) && ($$feature{'skpcreditchk'} != 1)) {
    $stuff{'creditflg'} = 1;
  }

  my $sha = new SHA;
  $sha->add($$query{'card-number'});
  my $shacardnumber = $sha->hexdigest();

  if ($stuff{'creditflg'} == 1) {
    require MD5;
    my $md5 = new MD5;
    $md5->add("$$query{'card-number'}");
    my $cardnumber_md5 = $md5->hexdigest();
    my $dbh_fraud = &miscutils::dbhconnect("pnpmisc");
    my $sth_fraud = $dbh_fraud->prepare(qq{
      SELECT enccardnumber,trans_date,card_number,username,descr
      FROM fraud
      WHERE enccardnumber = ?
    });
    $sth_fraud->execute("$cardnumber_md5");
    my ($test,$orgdate,$fraudnumber,$username,$reason) = $sth_fraud->fetchrow;
    $sth_fraud->finish;

    if ($test ne "") {
      ### Crd is in Negative - What now.
      $merchfraud{'errmsg'} = "Warning:  \nThis transaction has triggered a fraud warning.\n";
      $merchfraud{'errmsg'} .= "A credit was issued to a credit card that is in the negative database and may have been used previously for fraudulent activity.\n\n";
      $merchfraud{'errmsg'} .= "The card, $fraudnumber, was inserted into the negative database on $orgdate by $username, for the reason, $reason.\n\n";
      $merchfraud{'level'} = 2;
      $logdesc = "Credit issued to flaged CC";
    }

    if ($$query{'card-number'} !~ / /) {
      %bindata = &check_bankbin($$query{'card-number'});
    }

    if ($bindata{'bbin_country'} =~ /^(MT|RU|PL|LTU)$/i) {
      $merchfraud{'errmsg'} = "Warning:  \nThis transaction has triggered a fraud warning.\n";
      $merchfraud{'errmsg'} .= "A credit was issued to a credit card that is was issued from a suspicous country.\n\n";
      $merchfraud{'errmsg'} .= "This transaction will be FROZEN.  Further action is required on your part to allow this transaction to settle.\n\n";
      $merchfraud{'level'} = 2;
      $logdesc = "Credit issued to flaged Country: $bindata{'bbin_country'}";
    }
  }

  my $orderid = $$query{'order-id'};

  my $sth = $dbh->prepare(qq{
        SELECT volume,count
          FROM merch_stats
        WHERE username = ?
          AND trans_date = ?
          AND type = ?
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query,'username',$username);
  $sth->execute($username, $date, $type) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query,'username',$username);
  my ($volume,$count) = $sth->fetchrow;
  $sth->finish;

  if ($count eq "") {
    my $sth = $dbh->prepare(qq{
        INSERT INTO merch_stats
        (username,type,trans_date,volume,count)
        VALUES (?,?,?,?,?)
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query,'username',$username);
    $sth->execute("$username","$type","$date","$amount",'1') or &miscutils::errmail(__LINE__,__FILE__, "Can't execute: $DBI::errstr",%$query,'username',$username);
    $sth->finish;
  } else {
    $volume += $amount;
    $count++;
    eval {
      local $SIG{ALRM} = sub { die 'Timeout updating merch_stats!' . "\n"; };
      alarm 2;
      my $sth = $dbh->prepare(q/
          UPDATE merch_stats
             SET volume = ?, count = ?
           WHERE username = ?
             AND trans_date = ?
             AND type = ?
          /) or die "Can't execute: $DBI::errstr";
      $sth->execute("$volume", "$count", "$username", "$date", "$type") or die "Can't execute: $DBI::errstr";
      alarm 0;
    };

    if ($@) {
      &miscutils::errmail(__LINE__,__FILE__,$@,%$query,'username',$username);
    }
  }

  my ($cc_volume,$cc_count,$days);
  my (%vol,%cnt,%tick);

  $sth = $dbh->prepare(qq{
        SELECT volume,count
          FROM cc_stats
         WHERE shacardnumber = ? AND trans_date = ? AND type = ?
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query,'username',$username);
  $sth->execute($shacardnumber, $date, $type) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query,'username',$username);
  ($cc_volume,$cc_count) = $sth->fetchrow;
  $sth->finish;

  if ($cc_count eq "") {
    my $sth = $dbh->prepare(qq{
        INSERT INTO cc_stats
        (shacardnumber,type,trans_date,volume,count)
        VALUES (?,?,?,?,?)
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query,'username',$username);
    $sth->execute("$shacardnumber","$type","$date","$amount",'1') or &miscutils::errmail(__LINE__,__FILE__, "Can't execute: $DBI::errstr",%$query,'username',$username);
    $sth->finish;
    $cc_volume = $amount;
    $cc_count++;
  } else {
    $cc_count++;
    $cc_volume += $amount;
    eval {
      local $SIG{ALRM} = sub { die 'Timeout updating cc_stats' . "\n"; };
      alarm 2;
      my $sth = $dbh->prepare(q/
        UPDATE cc_stats
           SET volume = ?, count = ?
         WHERE shacardnumber = ?
           AND trans_date = ?
           AND type= ?
        /) or die "Can't prepare: $DBI::errstr";
      $sth->execute($cc_volume, $cc_count, $shacardnumber, $date, $type) or "Can't prepare: $DBI::errstr";
      alarm 0;
    };

    if ($@) {
      &miscutils::errmail(__LINE__,__FILE__,$@,%$query,'username',$username);
    }
  }

  ##  Check return transaction amount against warning return limit. This is for an individual card number.
  if ( ($cc_volume > $retn_warn_limit) && ($retn_warn_limit > 0) && ($operation eq "return") && ($merchfraud{'level'} < 1) ) {
    my $dbhdata = &dbhconnect("pnpdata","","$username");

    my $sth3 = $dbhdata->prepare(qq{
        SELECT orderid
          FROM operation_log
         WHERE orderid = ?
           AND username = ?
           AND postauthstatus = ?
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query,'username',$username);
    $sth3->execute($orderid, $username, 'success') or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query,'username',$username);
    ($chkorderid) = $sth3->fetchrow;
    $sth3->finish;
    my $lookback = 90;
    my ($db_amt,$amt,%amt,$prevchrgflg);
    my ($junk, $ninetydays, $junk2) = &miscutils::gendatetime(-3600*24*$lookback);
    if ($stuff{'creditflg'} == 1) {
      require PlugNPay::CreditCard;
      my $cc = new PlugNPay::CreditCard($$query{'card-number'});
      my $shacardnumber = $cc->getCardHash();
      my @cardHashes = $cc->getCardHashArray();
      my $cardHashQmarks = '?' . ',?'x($#cardHashes);

      require PlugNPay::Sys::Time;
      my $timeObj = new PlugNPay::Sys::Time();
      $timeObj->subtractDays('90');

      require PlugNPay::Database::QueryBuilder;
      my $queryBuilder = new PlugNPay::Database::QueryBuilder();
      my $ninteyDayDateRange = $queryBuilder->generateDateRange({'start_date' => $timeObj->inFormat('yyyymmdd'), 'end_date' => $timeObj->nowInFormat('yyyymmdd')});
      my $sth3 = $dbhdata->prepare(qq{
        SELECT amount
        FROM operation_log FORCE INDEX(oplog_tdatesha_idx)
        WHERE trans_date IN ($ninteyDayDateRange->{'params'})
        AND shacardnumber IN ($cardHashQmarks)
        AND username=?
        AND authstatus=?
        AND postauthstatus=?
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query,'username',$username);
      $sth3->execute(@{$ninteyDayDateRange->{'values'}},@cardHashes,$username,'success','success') or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query,'username',$username);
      my $rv = $sth3->bind_columns(undef,\($db_amt));
      while($sth3->fetch) {
        $prevchrgflg = 1;
        my ($curr,$amt) = split(/ /,$db_amt);
        $amt{$curr} += $amt;
      }
      $sth3->finish;
    }

    $checked_orderid = 1;

    if ($chkorderid eq "") {
      $merchfraud{'errmsg'} = "Warning:  \nThis transaction has exceeded predefined warning limits.\n";
      if ($stuff{'creditflg'} == 1 ) {
        $merchfraud{'errmsg'} .= "The warning limit for daily credit volume for an individual credit card is set to $retn_warn_limit.\n\n";
        $merchfraud{'errmsg'} .= "NOTE: A credit is a return not associtated with a previous sale.\n\n";
        if ($prevchrgflg == 1) {
          $merchfraud{'errmsg'} .= "Amount(s) charged to this card in past $lookback days is:\n";
          foreach my $key (sort keys %amt) {
            $amt{$key} = sprintf("%.2f",$amt{$key});
            $merchfraud{'errmsg'} .= "$key $amt{$key}\n";
          }
          $merchfraud{'errmsg'} .= "\n";
        }
        else {
          $merchfraud{'errmsg'} .= "No previous settled charges found for this card number in past $lookback days.\n";
        }
      }
      else {
        $merchfraud{'errmsg'} .= "The warning limit for daily return volume for an individual credit card is set to $retn_warn_limit.\n";
      }
      $merchfraud{'errmsg'} .= "The daily return volume for the credit card used in this transaction is $cc_volume\.\n";
      $merchfraud{'errmsg'} .= "This is a warning message only.  No further actions is required if you believe the transaction is legitimate\.";

      $merchfraud{'errmsg1'} = "Daily return volume of $cc_volume exceeds warning limit.";
      $merchfraud{'level'} = 3;
      $logdesc = "Max return vol. $cc_volume:$retn_warn_limit";
    }
  } ##  Check transaction amount against warning auth limit.  This is for an individual card number.
  elsif ( ($cc_volume > $auth_warn_limit) && ($auth_warn_limit > 0) && ($operation eq "auth") ) {
    $merchfraud{'errmsg'} = "Warning:  This transaction has exceeded predefined warning limits.\n";
    $merchfraud{'errmsg'} .= "The warning limit for daily sales volume for an individual credit card is set to $auth_warn_limit.\n";
    $merchfraud{'errmsg'} .= "The daily sales volume for the credit card used in this transaction is $cc_volume\.";
    $merchfraud{'errmsg'} .= "This is a warning message only.  No further actions is required if you believe the transaction is legitimate\.";

    $merchfraud{'errmsg1'} = "Daily sale volume of $cc_volume for this CC exceeds warning limit.";
    $merchfraud{'level'} = 3;
    $logdesc = "Max auth vol. $cc_volume:$auth_warn_limit";
  }


  if ($limits{'merchfraudflag'} == 1) {
    ##  Check return transaction amount against max return limit.  This is for an individual card number.
    if ( ( $cc_volume > ($limits{'max_retn_vol'}) ) && ($limits{'max_retn_vol'} > 0) && ($operation eq "return") ) {
      if ($checked_orderid != 1) {
        my $dbhdata = &dbhconnect("pnpdata","","$username");

        my $sth3 = $dbhdata->prepare(qq{
            SELECT orderid
            FROM operation_log
            WHERE orderid = ?
            AND username = ?
            AND postauthstatus = ?
            }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query,'username',$username);
        $sth3->execute($orderid, $username, 'success') or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query,'username',$username);
        ($chkorderid) = $sth3->fetchrow;
        $sth3->finish;

        $checked_orderid = 1;

      }

      if ($chkorderid eq "") {
        $merchfraud{'errmsg'} = "Notice:  This transaction has exceeded predefined limits.\n";
        $merchfraud{'errmsg'} .= "The limit for daily return volume for an individual credit card is set to $limits{'max_retn_vol'}.\n";
        $merchfraud{'errmsg'} .= "The daily return volume for the credit card used in this transaction is $cc_volume\.";
        $merchfraud{'errmsg'} .= "This transaction will be FROZEN.  Further action is required on your part to allow this transaction to settle.";

        $merchfraud{'errmsg1'} = "Daily return volume of $cc_volume exceeds max limit per credit card of $limits{'max_retn_vol'}.";
        $merchfraud{'level'} = 2;
        $logdesc = "Max return vol. $cc_volume:$limits{'max_retn_vol'}";
      }
    } ##  Check auth transaction amount against max auth limit.  This is for an individual card number.
    elsif ( ($cc_volume > $limits{'max_auth_vol'}) && ($limits{'max_auth_vol'} > 0) && ($operation eq "auth") ) {
      $merchfraud{'errmsg'} = "Notice:  This transaction has exceeded predefined limits.\n";
      $merchfraud{'errmsg'} .= "The limit for daily sales volume for an individual credit card is set to $limits{'max_auth_vol'}.\n";
      $merchfraud{'errmsg'} .= "The daily sales volume for the credit card used in this transaction is $cc_volume\.";
      $merchfraud{'errmsg'} .= "This transaction will be FROZEN.  Further action is required on your part to allow this transaction to settle.";

      $merchfraud{'errmsg1'} = "Daily sale volume of $cc_volume for this CC exceeds warning limit.";
      $merchfraud{'level'} = 2;
      $logdesc = "Max auth vol. $cc_volume:$limits{'max_auth_vol'}";
    }

    ##  Grab merchant stat data for last 90 days.
    my ($db_volume,$db_count);
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time() - (90 * 24 * 3600));
    my $startdate = sprintf("%04d%02d%02d",$year+1900,$mon+1,$mday);
    my $sth = $dbh->prepare(qq{
          SELECT volume,count
          FROM merch_stats
          WHERE username = ? AND trans_date >= ? AND type = ?
          ORDER BY trans_date DESC
          }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query,'username',$username);
    $sth->execute($username, $startdate, $type) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query,'username',$username);
    my $rv = $sth->bind_columns(undef,\($db_volume,$db_count));
    while($sth->fetch) {
      $days++;
      if ($days <= 1) {
        $vol{'today'} += $db_volume;
        $cnt{'today'} += $db_count;
      }
      if ($days <= 7) {
        $vol{'7day'} += $db_volume;
        $cnt{'7day'} += $db_count;
      }
      if ($days <= 30) {
        $vol{'30day'} += $db_volume;
        $cnt{'30day'} += $db_count;
      }
      if ($days <= 90) {
        $vol{'90day'} += $db_volume;
        $cnt{'90day'} += $db_count;
      }
    }
    $sth->finish;

    if ($days >= 1) {
      $vol{'avg_today'} = $vol{'today'};
      $cnt{'avg_today'} = $cnt{'today'};
      $tick{'avg_today'} = $vol{'avg_today'}/$cnt{'avg_today'};
    }
    if ($days >= 7) {
      $vol{'avg_7day'} = $vol{'7day'}/7;
      $cnt{'avg_7day'} = $cnt{'7day'}/7;
      $tick{'avg_7day'} = $vol{'avg_7day'}/$cnt{'avg_7day'};
    }
    if ($days >= 30) {
      $vol{'avg_30day'} = $vol{'30day'}/30;
      $cnt{'avg_30day'} = $cnt{'30day'}/30;
      $tick{'avg_30day'} = $vol{'avg_30day'}/$cnt{'avg_30day'};
    }
    if ($days >= 90) {
      $vol{'avg_90day'} = $vol{'90day'}/90;
      $cnt{'avg_90day'} = $cnt{'90day'}/90;
      $tick{'avg_90day'} = $vol{'avg_90day'}/$cnt{'avg_90day'};
    }
    foreach my $key (keys %vol) {
      $vol{$key} = sprintf("%.2f",$vol{$key});
    }
    foreach my $key (keys %tick) {
      $tick{$key} = sprintf("%.2f",$tick{$key});
    }

    my $a = $settype . "_metric";
    my $b = "avg_" . $limits{"$a"} . "day";
    my $c = $settype . "_ovr";

    ## Check todays tran volume against set limits.
    if (( $vol{'today'} > ($vol{"$b"} * $limits{"$c"}) ) && (exists $vol{"$b"}) && ($limits{"$c"} > 0)) {
      my $threshold = $vol{"$b"} * $limits{"$c"};
      $merchfraud{'level'} = 1;
      my $per_ovr = sprintf("%.2f percent",(($vol{'today'}/$vol{"$b"}) - 1) * 100);
      my $lim_ovr = sprintf("%.2f percent",($limits{"$c"} - 1) * 100);
      my $a = $limits{"$settype\_metric"};

      $merchfraud{'errmsg'} = "Notice:  This transaction has exceeded predefined limits.\n";
      $merchfraud{'errmsg'} .= "This account has a $type limit set at $lim_ovr over a $a day average.\n";
      $merchfraud{'errmsg'} .= "This account has a $type $a day average of: $vol{$b}\n";
      $merchfraud{'errmsg'} .= "The daily $type volume for this account is currently: $vol{'today'}.\n";
      $merchfraud{'errmsg'} .= "This account will be SUSPENDED.  Further action is required on your part to allow ANY transaction to settle.";


      $merchfraud{'errmsg1'} .= "Daily $type volume of $vol{'today'} exceeds $a average by $per_ovr.  Limit is set to, $lim_ovr over $a day avg.";
      $logdesc = "Daily $type vol. $vol{'today'}:$threshold";
    }

    ##  Added DCP 20051212
    if ((exists $tick{'avg_90day'}) && ($limits{'skip_low_warn'} != 1)) {
    ## Check tranaction amount against 90 day avg. ticket and warn if below by some percentage.
      $a = $settype . "_metric";
      $b = "avg_90day";
      $c = $settype . "_ovr";
      my $limit = 0.25;
      if (($amount < ($tick{"$b"} * $limit)) && ($amount < 10)) {
        my $threshold = $tick{"$b"} * $limit;
        $merchfraud{'level'} = 3;
        my $per_undr = sprintf("%.2f percent",(($amount/$tick{"$b"}) - 1) * 100);
        my $lim_ovr = sprintf("%.2f percent",$limit * 100);
        my $a = $limits{"$settype\_metric"};

        $merchfraud{'errmsg'} = "Warning:  This transaction has exceeded predefined limits.\n";
        $merchfraud{'errmsg'} .= "This account has a $type limit set at $lim_ovr under the 90 day average ticket.\n";
        $merchfraud{'errmsg'} .= "This account has a $type $a day average ticket of: $tick{$b}\n";
        $merchfraud{'errmsg'} .= "This transaction of $amount is below this average.\n";
        $merchfraud{'errmsg'} .= "This is a WARNING only.\n";
        $merchfraud{'errmsg'} .= "A high number of low dollar transactions below an accounts 90 day average MAYBE an indication that the account is being used to process fraudulent transactions for the purpose of testing stolen or generated credit card numbers. NO Further action is required on your part if you believe this transaction is valid.\n";

        $merchfraud{'errmsg1'} .= "Warning Transaction Amount of $amount is below 90 day avg. by $per_undr.\n";
        $merchfraud{'errmsg1'} .= "Limit is set to, $lim_ovr under 90 day avg. of $tick{'avg_90day'}.\n";
        $merchfraud{'errmsg1'} .= "IP Address: $ENV{'REMOTE_ADDR'}\n";
        $logdesc = "Tran $type amount below threshold. $amount:$threshold";
      }
    }

    $a = "cc" . $settype . "_metric";
    $b = "avg_" . $limits{"$a"} . "day";
    $c = "cc" . $settype . "_ovr";

    ## Check todays average ticket value against set limits.  Compares daily sales or returns for a specific CC against avg ticket.  Does this make sense ?
    ## Should this be amount of individual sale or return and not daily total ?
    if (( $cc_volume > ($tick{"$b"} * $limits{"$c"}) ) && (exists $tick{"$b"}) && ($limits{"$c"} > 0)) {
      my $threshold = $tick{"$b"} * $limits{"$c"};
      my $per_ovr = sprintf("%.2f percent",(($volume/$tick{"$b"}) - 1) * 100);
      my $lim_ovr = sprintf("%.2f percent",($limits{"$c"} - 1) * 100);
      ## If limit is exceeded and tran is a return, check to see if prior sale exists.
      if ($operation eq "return") {
        if ($checked_orderid != 1) {
          my $dbhdata = &dbhconnect("pnpdata","","$username");

          my $sth3 = $dbhdata->prepare(qq{
            SELECT orderid
              FROM operation_log
             WHERE orderid = ?
               AND username = ?
               AND postauthstatus = ?
              }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query,'username',$username);
          $sth3->execute($orderid, $username, 'success') or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query,'username',$username);
          ($chkorderid) = $sth3->fetchrow;
          $sth3->finish;

          $checked_orderid = 1;
        }
        if ($chkorderid eq "") {
          $merchfraud{'errmsg'} = "Notice:  This transaction has exceeded predefined limits.\n";
          $merchfraud{'errmsg'} .= "This account has a $type average ticket limit set at $lim_ovr over a $limits{$a} day average.\n";
          $merchfraud{'errmsg'} .= "This account has a $type $limits{$a} day average ticket of: $tick{$b}\n";
          $merchfraud{'errmsg'} .= "The $type volume for this transaction is currently: $cc_volume.\n";
          $merchfraud{'errmsg'} .= "This transaction will be FROZEN.  Further action is required on your part to allow this transaction to settle.";

          $merchfraud{'errmsg1'} .= "Daily $type volume of $volume exceeds $limits{$a} average by $per_ovr.  Limit is set to, $lim_ovr over $a day avg..";
          $merchfraud{'level'} = 2;
          $logdesc = "Daily return vol. $volume:$threshold";
        }
      }
      else {
        $merchfraud{'errmsg'} = "Notice:  This transaction has exceeded predefined limits.\n";
        $merchfraud{'errmsg'} .= "This account has a $type average ticket limit set at $lim_ovr over a $limits{$a} day average.\n";
        $merchfraud{'errmsg'} .= "This account has a $type $limits{$a} day average ticket of: $tick{$b}\n";
        $merchfraud{'errmsg'} .= "The $type volume for this transaction is currently: $cc_volume.\n";
        $merchfraud{'errmsg'} .= "This transaction will be FROZEN.  Further action is required on your part to allow this transaction to settle.";

        $merchfraud{'errmsg1'} .= "Daily $type volume of $volume exceeds $limits{$a} average by $per_ovr.  Limit is set to, $lim_ovr over $limits{$a} day avg.";
        $merchfraud{'level'} = 2;
      }
    }

  }

  ## If error exists log transaction
  if ($merchfraud{'level'} >= 1) {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
    my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);

    my $description = substr($merchfraud{'errmsg1'},0,49);
    my $transtime =  sprintf("%04d%02d%02d%02d%02d%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
    my $ipaddress = $ENV{'REMOTE_ADDR'};
    my $orderid = $$query{'order-id'};

    if ($merchfraud{'level'} == 1) {
      ## Freeze Merchant
      if ($status ne "fraud") {
        my $sth = $dbh->prepare(qq{
            UPDATE customers
            SET status = ?
            WHERE username = ?
            }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query,'username',$username);
        $sth->execute('fraud', $username) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query,'username',$username);
        $sth->finish;

        my $action = "acct. suspended";

        $sth = $dbh->prepare(qq{
          INSERT INTO risk_log
          (username,orderid,trans_time,ipaddress,action,description)
          VALUES (?,?,?,?,?,?)
          }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query,'username',$username);
        $sth->execute("$username","$orderid","$transtime","$ipaddress","$action","$description") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query,'username',$username);
        $sth->finish;
      }
    }
    elsif ($merchfraud{'level'} == 2) {
      ## Freeze Transaction
      my $dbhpnp = &dbhconnect("pnpdata","","$username");

      if ($operation eq "return") {

        my $sth = $dbhpnp->prepare(qq{
           UPDATE trans_log
              SET finalstatus = ?
            WHERE orderid = ?
              AND username = ?
              AND operation = ?
              AND finalstatus = ?
            }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query,'username',$username);
        $sth->execute('hold', $orderid, $username, 'return', 'pending') or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query,'username',$username);
        $sth->finish;

        $sth = $dbhpnp->prepare(qq{
           UPDATE operation_log
              SET lastopstatus = ?
            WHERE orderid = ?
              AND username = ?
              AND returnstatus = ?
              AND lastopstatus = ?
            }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query,'username',$username);
        $sth->execute('hold', $orderid, $username, 'pending', 'pending') or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query,'username',$username);
        $sth->finish;
      }
      elsif ($operation eq "auth") {
        my $sth = $dbhpnp->prepare(qq{
            UPDATE trans_log
              SET finalstatus = ?
            WHERE orderid = ?
              AND username = ?
              AND operation = ?
              AND finalstatus = ?
            }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query,'username',$username);
        $sth->execute('hold', $orderid, $username, 'auth', 'success') or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query,'username',$username);
        $sth->finish;

        $sth = $dbhpnp->prepare(qq{
            UPDATE operation_log
               SET lastopstatus = ?
             WHERE orderid = ?
               AND username = ?
               AND authstatus = ?
               AND lastopstatus = ?
            }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query,'username',$username);
        $sth->execute('hold', $orderid, $username, 'success', 'success') or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query,'username',$username);
        $sth->finish;
      }

      my $action = "tran. frozen";
      my $sth = $dbh->prepare(qq{
        INSERT INTO risk_log
        (username,orderid,trans_time,ipaddress,action,description)
        VALUES (?,?,?,?,?,?)
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query,'username',$username);
      $sth->execute("$username","$orderid","$transtime","$ipaddress","$action","$description") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query,'username',$username);
      $sth->finish;
    }
    require PlugNPay::Logging::DataLog;
    my %logData = (%vol, %tick);
    $logData{'creditFlag'} = $stuff{'creditflg'}; #the super specific hash named stuff
    $logData{'message'}    = $merchfraud{'errmsg1'};
    $logData{'username'}   = $username;
    $logData{'orderID'}    = $orderid;
    $logData{'operation'}  = $operation;
    $logData{'amount'}     = $amount;
    $logData{'limits'}     = $limits;
    $logData{'volume'}     = $volume;

    $logData{'originalLogFile'} = '/home/p/pay1/database/debug/merchfraud_debug.txt';
    new PlugNPay::Logging::DataLog({'collection' => 'debug'})->log(\%logData);

    my @array = (%$query,%limits,%stuff,'username',$username);
    &riskemail ($merchfraud{'errmsg'},@array);
  }

  return %merchfraud;
}


sub riskemail {
  my ($error,%message) = @_;

  if ($message{'username'} =~ /^(onestepdem|avrdev|pnpdemo)/) {
    return;
  }

  my %dntccemail = ('fandaconce','1','cyd0474831','1');
  if ($message{'card-number'} ne "") {
    $message{'card-number'} = substr($message{'card-number'},0,4) . '**' . substr($message{'card-number'},-2,2);
  }
  if ($message{'riskemail'} eq "kimberleym\@cynergydata.com") {
    $message{'riskemail'} = "sami\@cynergydata.com"
  }

  if ((! exists $message{'riskemail'}) && ($message{'creditflg'} == 1)) {
    $message{'riskemail'} = "RiskManager\@plugnpay.com";
  }

  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setFormat('text');
  $emailObj->setGatewayAccount($message{'username'});
  $emailObj->setTo($message{'riskemail'});
  $emailObj->setFrom('riskmanager@plugnpay.com');
  if (($message{'riskemail'} ne "RiskManager\@plugnpay.com") && (! exists $dntccemail{$message{'username'}})) {
    $emailObj->setBCC('riskmanager@plugnpay.com');
  } elsif ( ($message{'riskemail'} ne "RiskManager\@plugnpay.com") && ($message{'creditflg'} == 1) ) {
    $emailObj->setBCC('riskmanager@plugnpay.com');
  }

  if ($message{'creditflg'} == 1) {
    $emailObj->setSubject('Credit Risk Warning');
  } else {
    $emailObj->setSubject('Risk Management Warning');
  }
  my $message = '';
  $message .= "Username: $message{'username'}\n";
  $message .= "Error: $error\n\n";
  $message .= "TransactionID: $message{'order-id'}\n";
  $message .= "Amount: $message{'amount'}\n\n";
  $message .= "Customer Details:\n";
  $message .= "$message{'card-name'}\n";
  $message .= "$message{'card-address1'}\n";
  $message .= "$message{'card-address2'}\n";
  $message .= "$message{'card-city'}, $message{'card-state'}  $message{'card-zip'}\n";

  $emailObj->setContent($message);
  $emailObj->send();
}


sub cardtype {
  my ($cardnumber) = @_;
  $cardnumber =~ s/[^0-9]//g;
  my $cardbin = substr($cardnumber,0,6);
  my ($cardtype);

  if ($cardbin =~ /^(6767)/) {   ## New Solo Card Range
    $cardtype = "SOLO";
  }
  elsif (($cardbin =~ /^(6759)/)
    || ($cardbin =~ /^(490303)/)  ## Can be removed after Nov. 30 2006
    ){   ## Maestro UK Card Range
    $cardtype = "SWTCH";
  }
  elsif ($cardbin =~ /^(048|0420|0430|690046|707138)/) {
    $cardtype = 'WEX';                    # wex  added 20100804
  }
  elsif ($cardbin =~ /^(4)/) {
    $cardtype = "VISA";
  }
  elsif ($cardbin =~ /^(51|52|53|54|55|56|57|58)/) {
    $cardtype = "MSTR";
  }
  elsif (($cardbin >= 222100) && ($cardbin <= 272099)) { ## New MC Bin Range Effective Oct. 1, 2016
    $cardtype = "MSTR";
  }
  elsif ($cardbin =~ /^(37|34)/) {
    $cardtype = "AMEX";
  }
  elsif (($cardbin =~ /^(3088|3096|3112|3158|3337)/)
                 || (($cardbin >= 352800) && ($cardbin < 359000))) {
    $cardtype = "JCB";
  }
  elsif ($cardbin =~ /^(30|36|38[0-8])/) {
    $cardtype = "DNRS";
  }
  elsif ($cardbin =~ /^(389)/) {
    $cardtype = "CRTB";
  }
  elsif ( ($cardbin >= 601100) && ($cardbin <= 601109)
                 || (($cardbin >= 601120) && ($cardbin <= 601149))
                 || (($cardbin >= 601174) && ($cardbin <= 601174))
                 || (($cardbin >= 601177) && ($cardbin <= 601179))
                 || (($cardbin >= 601186) && ($cardbin <= 601199))
                 || (($cardbin >= 622126) && ($cardbin <= 622925))
                 || (($cardbin >= 644000) && ($cardbin <= 649999))
                 || (($cardbin >= 650000) && ($cardbin <= 659999))
     ) {
    $cardtype = "DSCR";
  }
  elsif ($cardbin =~ /^(1800|2131)/) {
    $cardtype = "JAL";
  }
  elsif ($cardbin =~ /^(7775|7776|7777)/) {
    $cardtype = "KC";
  }
  elsif ($cardbin =~ /^(604626|605011|603028|603628)/) {
    $cardtype = "PL";
  }
  #elsif ($cardbin =~ /^(6019)/) {
  #  $cardtype = "MS";
  #}
  elsif ($cardbin =~ /^(8)/) {
    $cardtype = "PP";
  }
  elsif ($cardbin =~ /^(9)/) {
    $cardtype = "SV";
  }
  elsif ( (($cardbin >= 500000) && ($cardbin <= 509999))
    || (($cardbin >= 560000) && ($cardbin <= 589999))
    || (($cardbin >= 600000) && ($cardbin <= 699999)) ) {
    $cardtype = "SWTCH";  ### Int Maestro
  }
  else {
    return "failure";
  }
  return $cardtype;
}

sub filter_log_data {
  my (%queryhash) = @_;
  foreach my $key (sort keys %queryhash) {
    $queryhash{$key} =~ s/(\n|\r)//g;
    if (($key =~ /^(Trackdata|TrakData|magstripe)$/i) && ($queryhash{$key} ne "")) {
      $queryhash{$key} = "Data Present:" . substr($queryhash{$key},0,6) . "****" . "0000";
    }
    elsif ($key =~ /^(message)$/i) {
      $queryhash{$key} = "XXXX";
    }
    elsif ($key =~ /(cvv|card_code|password)/i) {
      my $aaaa = $queryhash{$key};
      $aaaa =~ s/./X/g;
      $queryhash{$key} = "$aaaa";
    }
    elsif (($key =~ /(card_num|ccno|cardnumber)/i) || (($key =~ /(card)/i) && ($key =~ /(num)/i)) ){
      my $first6 = substr($queryhash{$key},0,6);
      my $last2 = substr($queryhash{$key},-2);
      my $CClen = length($queryhash{$key});
      my $tmpCC = $queryhash{$key};
      $tmpCC =~ s/./X/g;
      $tmpCC = $first6 . substr($tmpCC,6,$CClen - 8) . $last2;
      $queryhash{$key} = "$tmpCC, ";
    }
    elsif ($key =~ /(3|4|5|6|7)(\d{12,15})/)  {
      my $tempval = "$1$2";
      my $ct = &cardtype($tempval);
      $tempval =~ s/./X/g;
      $tempval = "CCKEY:$tempval";
      if ($ct ne "failure") {
        $queryhash{$tempval} = "$tempval";
      }
      delete $queryhash{$key};
    }
    elsif ($key =~ /^\%(b).+\?\*$/i) {
      $queryhash{$key} = "Data Present:" . substr($queryhash{$key},0,6) . "****" . "0000";
    }

    if ( ($queryhash{$key} =~ /(3|4|5|6|7)(\d{12,15})/) && ($key !~ /orderID|refnumber/i) ) {
      my $tempval = "$1$2";
      my $ct = &cardtype($tempval);
      $tempval =~ s/./X/g;
      $tempval = "CCVAL:$tempval";
      if ($ct ne "failure") {
        $queryhash{$key} = "$tempval";
      }
    }
    if ( ($queryhash{$key} =~ /^\%(b).+\?\*$/i) ) {
      my $FilterMag = "Mag_Data_Present_" . substr($queryhash{$key},0,6) . "****" . "0000";
      $queryhash{$FilterMag} = "$FilterMag";
      delete $queryhash{$key};
    }
  }
  return %queryhash;
}


sub check_bankbin {
  my ($cardnumber) = @_;
  my (%error,$test,%bindata);
  my $dbh = &dbhconnect("fraudtrack");

  my ($start1,$end1,$debitflg,$cardtype1,$region1,$country1,$producttype,$productid,$chipcrdflg);
  my ($start2,$end2,$ica,$region2,$country2,$electflg,$acquirer,$cardtype2,$mapping,$alm_part,$alm_date);

  my %binregion1 = ('1','USA','2','CAN','3','EUR','4','AP','5','LAC','6','SAMEA');
  my %binregion2 = ('1','USA','A','CAN','B','LAC','C','AP','D','EUR','E','SAMEA');
  my %bindebitflg = ('D','DBT','C','CRD','F','CHK');
  my %ardefpt = ('A','ATM','B','VISA-BUSINESS','C','VISA-CLASSIC','D','VISA-COMMERCE','E','ELECTRON','F','Visa-Check-Card2','G','Visa-Travel-Money','H','Visa-Infinite','H','Visa-Sig-Preferred',
                 'J','Visa-Platinum','K','Visa-Signature','L','VISA-PRIVATE-LABEL','M','MASTERCARD','O','V-Signature-Business','P','VISA-GOLD','Q','VISA-Proprietary','R','CORP-T-E',
                 'S','PURCHASING','T','TRAVEL-VOUCHER','V','VPAY','X','RESERVED-FUTURE','B','VISA-BIZ','H','VISA-BUSINESS','S','VISA-BUSINESS','O','VISA-BUSINESS');

  my %ardefpid = ('A','VS-TRADITIONAL','AX','VS-AMEX','B','VS-TRAD-REWARDS','C','VS-SIGNATURE','D','VS-SIG-PREFERRED','DI','VS-DISCOVER','E','VS-RESERVED-E','F','VS-RESERVED-F','G','VS-BUSINESS',
                   'G1','VS-SIG-BUSINESS','G2','VS-BUS-CHECK-CARD','H','VS-CHECK-CARD','I','VS-COMMERCE','J','VS-RESERVED-J','J1','VS-GEN-PREPAID','J2','VS-PREPAID-GIFT','J3','VS-PREPAID-HEALTH',
                   'J4','VS-PREPAID-COMM','K','VS-CORPORATE','K1','VS-GSA-CORP-TE','L','VS-RESERVED-L','M','VS-MASTERCARD','N','VS-RESERVED-N','O','VS-RESERVED-O','P','VS-RESERVED-P','Q','VS-PRIVATE',
                   'Q1','VS-PRIV-PREPAID','R','VS-PROPRIETARY','S','VS-PURCHASING','S1','VS-PURCH-FLEET','S2','VS-GSA-PURCH','S3','VS-GSA-PURCH-FLEET','T','VS-INTERLINK','U','VS-TRAVELMONEY','V','VS-RESERVED-V');

  my %icaxrfpt = ('MCC','norm','MCE','electronic','MCF','fleet','MGF','fleet','MPK','fleet','MNF','fleet','MCG','gold','MCP','purchasing','MCS','standard','MCU','standard','MCW','world',
                 'MNW','world','MWE','world-elite','MCD','MC-debit','MDS','MC-debit','MDG','gold-debit','TCG','gold-debit','MDO','other-debit','MDH','other-debit','MDJ','other-debit',
                 'MDP','platinum-debit','MDR','brokerage-debit','MXG','x-gold-debit','MXO','x-other-debit','MXP','x-platinum-debit','TPL','x-platinum-debit','MXR','x-brokerage-debit',
                 'MXS','x-standard-debit','MPP','prepaid-debit','MPL','platinum','MCT','platinum','PVL','private-label','MAV','activation','MBE','electronic-bus','MWB','world-bus',
                 'MAB','world-elite-bus','MWO','world-corp','MAC','world-elite-corp','MCB','distribution-card','MDP','premium-debit','MDT','business-debit','MDH','debit-other','MDJ','debit-other2',
                 'MDL','biz-debit-other','MCF','mid-market-fleet','MCP','mid-market-pruch','MCO','mid-market-corp','MCO','corp-card','MEO','large-market-exe','MDQ','middle-market-corp',
                 'MPC','small-bus-card','MPC','small-bus-card','MEB','exe-small-bus-card','MDU','x-debit-unembossed','MEP','x-premium-debit','MUP','x-premium-debit-ue','MGF','gov-comm-card',
                 'MPK','gov-comm-card-pre','MNF','pub-sec-comm-card','MRG','prepaid-consumer','MPG','db-prepd-gen-spend','MRC','prepaid-electronic','MRW','prepaid-bus-nonus','MEF','elect-pmt-acct',
                 'MBK','black','MPB','pref-biz','DLG','debit-gold-delayed','DLH','debit-emb-delayed','DLS','debit-st-delayed','DLP','debit-plat-delayed','MCV','merchant-branded',
                 'MPJ','debit-gold-prepaid','MRJ','gold-prepaid','MRK','comm-public-sector','TBE','elect-bus-debit','TCB','bus-debit','TCC','imm-debit','TCE','elect-debit','TCF','fleet-debit',
                 'TCO','corp-debit','TCP','purch-debit','TCS','std-debit','TCW','signia-debit','TNF','comm-pub-sect-dbt','TNW','new-world-debit','TPB','pref-bus-debit');


  my $ardef_bin = substr($cardnumber,0,9);
  my $sth = $dbh->prepare(qq{
        SELECT data
        FROM ardef
        WHERE startbin <= ?
        ORDER BY startbin DESC LIMIT 1
  }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute("$ardef_bin") or &errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
  my ($ardef_data) = $sth->fetchrow;
  $sth->finish;

  $end1 = substr($ardef_data,0,9);
  $end1 =~ s/[^0-9]//g;
  $start1 = substr($ardef_data,9,9);
  $start1 =~ s/[^0-9]//g;
  $debitflg = substr($ardef_data,18,1);
  $cardtype1 =  substr($ardef_data,19,1);
  $region1 =  substr($ardef_data,20,1);
  $country1 =  substr($ardef_data,21,2);
  $producttype = substr($ardef_data,23,1);
  $productid = substr($ardef_data,24,2);
  $chipcrdflg = substr($ardef_data,26,1);

  ## Work Around for old Data  DCP 20160725
  if ($cardnumber =~ /^440066/) {
    $country1 = "US";
    $region1 = "1";
  }

  $bindata{'bbin_region'} = $binregion1{"$region1"};
  $bindata{'bbin_country'} = $country1;
  $bindata{'bbin_debit'} = $bindebitflg{"$debitflg"};
  $bindata{'bbin_prodtype'} = $ardefpt{"$cardtype1"};
  if (($productid ne "") && (exists $ardefpid{"$productid"})) {
    $bindata{'bbin_prodtype'} = $ardefpid{"$productid"};
  }

  if ($bindata{'bbin_prodtype'} =~ /prepaid/i) {   ###  PrePaid Cards
    $bindata{'bbin_debit'} = 'PPD';
  }


  my $icaxrf_bin = substr($cardnumber,0,11);
  $icaxrf_bin .= "0000000000";
  $icaxrf_bin  = substr($icaxrf_bin,0,19);

  if ($icaxrf_bin =~ /^5/) {
    my $sth = $dbh->prepare(qq{
          SELECT data
          FROM icaxrf
          WHERE startbin <= $icaxrf_bin
          ORDER BY startbin DESC LIMIT 1
    }) or &errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
    $sth->execute() or &errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
    my ($icaxrf_data) = $sth->fetchrow;
    $sth->finish;

    $end2 = substr($icaxrf_data,0,19);
    $end2 =~ s/[^0-9]//g;
    $start2 = substr($icaxrf_data,19,19);
    $start2 =~ s/[^0-9]//g;
    $ica = substr($icaxrf_data,38,11);
    $region2 =  substr($icaxrf_data,49,1);
    $country2 =  substr($icaxrf_data,50,3);
    $electflg = substr($icaxrf_data,53,2);
    $acquirer = substr($icaxrf_data,55,1);
    $cardtype2 = substr($icaxrf_data,56,3);
    $mapping = substr($icaxrf_data,59,1);
    $alm_part = substr($icaxrf_data,60,1);
    $alm_date = substr($icaxrf_data,61,6);

    if ($icaxrfpt{"$cardtype2"} =~ /debit/i) {
      $bindata{'bbin_debit'} = 'DBT';
    }
    if ($icaxrfpt{"$cardtype2"} =~ /prepaid/i) {   ###  PrePaid Cards
      $bindata{'bbin_debit'} = 'PPD';
    }
    $bindata{'bbin_country'} = $country2;
    $bindata{'bbin_region'} = $binregion2{"$region2"};
    $bindata{'bbin_prodtype'} = $icaxrfpt{"$cardtype2"};
  }

  if (-e "/home/p/pay1/database/debug/please_debug_bindata.txt") {

    require PlugNPay::Logging::DataLog;
    my $logData = {
      'originalLogFile' => '/home/p/pay1/database/debug/bindatadebug_misc.txt',
      'ipAddress'       => $ENV{'REMOTE_ADDR'},
      'scriptName'      => $ENV{'SCRIPT_NAME'},
      'ranges'          => [
        { #card range 1
         'cardBin'     => $ardef_bin,
         'start'       => $start1,
         'end'         => $end1,
         'debitFlag'   => $bindebitflg{$debitflg},
         'cardType'    => $ardefpt{$cardtype1},
         'region'      => $binregion1{$region1},
         'country'     => $country1,
         'productType' => $ardefpt{$producttype},
         'productID'   => $ardefpid{$productid}
        },
        { #card range 2
         'cardBin'   => $icaxrf_bin,
         'start'     => $start2,
         'end'       => $end2,
         'cardType'  => $cardtype2,
         'region'    => $binregion2{$region2},
         'country'   => $country2,
         'electFlag' => $electflg,
         'ICA'       => $ica,
         'almPart'   => $alm_part,
         'almDate'   => $alm_date,
         'map'       => $mapping,
         'acquierer' =>
        }
       ]
    };

    %{$logData} = (%bindata, %{$logData});
    new PlugNPay::Logging::DataLog({'collection' => 'debug'})->log($logData);
  }

  return %bindata;
}


sub check_geolocation {
  my ($ip) = @_;
  my (%error,$w,$x,$y,$z);

  if ($ip !~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/) {
    return;
  }

  $w = $1;
  $x = $2;
  $y = $3;
  $z = $4;

  my $ipnum = int(16777216*$w + 65536*$x + 256*$y + $z);

  my $stime = gmtime(time());
  my $dbh = &miscutils::dbhconnect("fraudtrack");

  my $sth = $dbh->prepare(qq{
        SELECT ipnum_from, ipnum_to, country_code
        FROM ip_country
        WHERE ipnum_to >= ?
        ORDER BY ipnum_to ASC LIMIT 1
  }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute($ipnum) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
  my ($ipnum_from, $ipnum_to, $mmcountry) = $sth->fetchrow;
  $sth->finish;

  #$dbh->disconnect;  # 20170421 DCP

  if (($ipnum < $ipnum_from) || ($ipnum > $ipnum_to)) {
    $mmcountry = "";
  }

  if ($mmcountry =~ /^(UK|GB)$/) {
    $mmcountry = "UK|GB";
  }

  return $mmcountry;
}

sub dateIn {
  my ($start,$end,$endDateInclusive) = @_;
  my @dateArray = ();
  my ($qmarks,$offset);

  if ($endDateInclusive) {
    $offset = 0;
  }
  else {
    $offset = 1;
  }

  $start =~ s/[^0-9]//g;
  $end =~ s/[^0-9]//g;

  my $year = substr($start,0,4);
  my $month = substr($start,4,2);
  my $day = substr($start,6,2);

  my $endYear = substr($end,0,4);
  my $endMon = substr($end,4,2);
  my $endDay = substr($end,6,2);

  my $daysInMonth = Days_in_Month($endYear,$endMon);

  if ($endDay > $daysInMonth) {
    $endDay = $daysInMonth;
  }
  push (@dateArray,$start);

  my $Dd = Delta_Days($year,$month,$day,$endYear,$endMon,$endDay) - $offset;  ## To accomodate where our queries are typcially trans_ndate < X
  for(my $i=1; $i<=$Dd; $i++) {
    ($year,$month,$day) = Add_Delta_Days($year,$month,$day,1);
    my $incrementedDate = $year . sprintf("%02d",$month) . sprintf("%02d",$day);
    push (@dateArray,$incrementedDate);
  }
  $qmarks = '?,' x @dateArray;
  chop $qmarks;

  return $qmarks, \@dateArray;
}

1;
