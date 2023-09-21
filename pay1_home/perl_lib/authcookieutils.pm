package authcookieutils;

use miscutils;
use PlugNPay::Email;


use strict;


sub log {
  my($user,$chkuser,$password,$crypted_password,$ipaddress) = @_;
  my $path_log = "/home/p/pay1/database/debug/cookie_debug.txt";
  my $ua = $ENV{'USER_AGENT'};

  if ($user =~ /^($chkuser)$/) {
    my $now = localtime(time());
    open (DEBUG, ">>/home/p/pay1/database/debug/cookie_debug.txt");
    print DEBUG "$now, $user, $password, $crypted_password\n";
    close (DEBUG);
  }
  elsif (($ua =~ / ru\; /) && ($user !~ /^(onlinetran|fractalpub|smart2demo)$/i)) {
    my $now = localtime(time());
    open (DEBUG, ">>/home/p/pay1/database/debug/cookie_debug.txt");
    print DEBUG "$now, $user, $password, $crypted_password\n";
    close (DEBUG);
  }

  return;
}


sub check_geolocation {
  my ($ipaddress,$username,$login) = @_;
  my (%error,$w,$x,$y,$z,$elapse,$stime,$etime,$country,$mmcountry,$ipnum_from,$ipnum_to,$ipnum,$isp,$org);
  my (%percent,%cnt,$db_count,$days,$count,$db_country,$totalcnt,$db_org,$db_isp,$db_date,%dates);
  my ($threshold);

  if (-e "/home/p/pay1/outagefiles/stop_geolocation.txt") {
    return;
  }

  if ($username =~ /^(smart2demo|initaly|pnpdemo)$/) {
    return;
  }

  $threshold = 10;   ## %percent below at which a login violation warning is triggered.  The higher the number the more warnings will be sent.

  if ($ipaddress !~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/) {
    return;
  }

  $w = $1;
  $x = $2;
  $y = $3;
  $z = $4;

  $ipnum = int(16777216*$w + 65536*$x + 256*$y + $z);

  if (length($ipnum) > 11) {
    return;
  }

  $stime = time();

  my $dbh = &miscutils::dbhconnect("fraudtrack");

  my $sth = $dbh->prepare(qq{
        select ipnum_from, ipnum_to, country_code
        from ip_country
        where ipnum_to >= $ipnum
        ORDER BY ipnum_to ASC LIMIT 1
  }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute() or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
  ($ipnum_from, $ipnum_to, $mmcountry) = $sth->fetchrow;
  $sth->finish;

  if (($ipnum < $ipnum_from) || ($ipnum > $ipnum_to)) {
    $mmcountry = "";
  }

  if ($mmcountry =~ /^(UK|GB)$/) {
    $mmcountry = "GB";
  }

  $country = $mmcountry;

  if ($country eq "") {
    $country = "NA";
    return $country;
  }
  my ($data);
  my $sth = $dbh->prepare(qq{
        select ipnum_from, ipnum_to, geodata
        from ip_isp
        where ipnum_to >= $ipnum
        ORDER BY ipnum_to ASC LIMIT 1
  }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute() or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
  ($ipnum_from, $ipnum_to, $data) = $sth->fetchrow;
  $sth->finish;

  if (($ipnum < $ipnum_from) || ($ipnum > $ipnum_to)) {
    $data = "";
  }

  if ($data eq "") {
    $data = "ISP Not Found";
  }

  $isp = $data;

  my $sth = $dbh->prepare(qq{
        select ipnum_from, ipnum_to, geodata
        from ip_org
        where ipnum_to >= $ipnum
        ORDER BY ipnum_to ASC LIMIT 1
  }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute() or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
  ($ipnum_from, $ipnum_to, $data) = $sth->fetchrow;
  $sth->finish;

  if (($ipnum < $ipnum_from) || ($ipnum > $ipnum_to)) {
    $data = "";
  }

  if ($data eq "") {
    $data = "ORG Not Found";
  }

  $org = $data;

  my ($dummy,$trans_date,$trans_time) = &miscutils::gendatetime();

  my $sth = $dbh->prepare(qq{
        select count
        from login_stats
        where username=?
        and login=? 
        and trans_date=? 
        and country=?
        and isp=?
        and org=?
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",'username',$username);
  $sth->execute("$username","$login","$trans_date","$country","$isp","$org") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",'username',$username);
  my ($count) = $sth->fetchrow;
  $sth->finish;

  if ($count eq "") {
    my $sth = $dbh->prepare(qq{
        insert into login_stats
        (username,login,trans_date,country,count,isp,org)
        values (?,?,?,?,?,?,?)
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",'username',$username);
    $sth->execute("$username","$login","$trans_date","$country",'1',"$isp","$org") or &miscutils::errmail(__LINE__,__FILE__, "Can't execute: $DBI::errstr",'username',$username);
    $sth->finish;
  }
  else {
    $count++;
    my $sth = $dbh->prepare(qq{
        update login_stats
        set count=?
        where username=? 
        and login=?
        and trans_date=? 
        and country=?
        and isp=?
        and org=?
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",'username',$username);
    $sth->execute("$count","$username","$login","$trans_date","$country","$isp","$org") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",'username',$username);
    $sth->finish;
  }


  if (! -e "/home/p/pay1/logfiles/stop_smpsgeo.txt") {

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time() - (90 * 24 * 3600));
  my $startdate = sprintf("%04d%02d%02d",$year+1900,$mon+1,$mday);

  my $sth2 = $dbh->prepare(qq{
        select count,country,isp,org,trans_date
        from login_stats
        where username=?
        and login=?
        and trans_date>=?
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",'username',$username,%ENV);
  $sth2->execute("$username","$login","$startdate") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",'username',$username,%ENV);
  my $rv = $sth2->bind_columns(undef,\($db_count,$db_country,$db_isp,$db_org,$db_date));
  while($sth2->fetch) {
    if ($db_isp eq "") {
      next;
    }
    if ($db_country =~ /^GB\|/) {
      $db_country = "GB";
    }
    $dates{$db_date} = 1;
    $totalcnt += $db_count;
    $cnt{"$db_country/$db_isp/$db_org"} += $db_count;
  }
  $sth2->finish;

  $dbh->disconnect;

  my @days = keys %dates;
  $days = @days;

  open (DEBUG, ">>/home/p/pay1/database/debug/geodata_debug.txt");
  my $now = localtime(time());
  print DEBUG "$now, UN:$username, LOGIN:$login, IP:$ipaddress, CO:$country, ISP:$isp, ORG:$org\n";
  close (DEBUG);

  if (($days >= 5) && ($totalcnt > 0)) {
    foreach my $key (keys %cnt) {
      $percent{$key} = sprintf("%.1f",($cnt{$key}/$totalcnt) * 100);
    }

    if ($percent{"$country/$isp/$org"} < $threshold) {
      ## Current Country of Login < Threshold send warning.
      my $msg = "New ISP/Organization Signature Detected\n\n";
      $msg .= "current warning threshold:$threshold\%\n\n";
      $msg .= "username:$username\n";
      $msg .= "login:$login\n\n";
      $msg .= "current login country:$country\n";
      $msg .= "current isp:$isp\n";
      $msg .= "current org:$org\n";
      $msg .= "login history\n";
      $msg .= "total count:$totalcnt\n";
      foreach my $key (keys %percent) {
        $msg .= "country:$key, cnt:$cnt{$key}, percent:$percent{$key}\n";
      }
      $msg .= "\n\n";
      my $sub = "pnp - New ISP/Organization Signature Detected";
      if ($username !~ /^(pnpdemo|demo|anonymi)/) {
        &sendemail("$msg","$ENV{'SERVER_NAME'}","$sub");
      }
    }

  }


  } ###  End STop Loop


  return;
}



sub sendemail {
  my ($msg,$hostname,$sub) = @_;

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time());
  my $time = sprintf("%02d/%02d %02d:%02d",$mon+1,$mday,$hour,$min);

  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setTo('dprice@plugnpay.com');
  $emailObj->setCC('chris@plugnpay.com');
  $emailObj->setFrom('checklog@plugnpay.com');

  if ($sub =~ /Hacker/) {
    $emailObj->setBCC('6318061932@txt.att.net');
  }

  my $message = '';
  $message .= "$time\n\n";
  $message .= "$msg\n";

  $emailObj->setContent($message);
  $emailObj->send();
}




1;



