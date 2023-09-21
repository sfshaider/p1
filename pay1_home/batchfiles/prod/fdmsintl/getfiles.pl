#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::SFTP::Foreign;
use miscutils;
use procutils;

$devprod = "logs";

#$fdmsaddr = "test2-gw-na.firstdataclients.com";  # test server
$fdmsaddr = "prod-gw-na.firstdataclients.com";    # production server

#$fdmsaddr = "prod2-gw-na.firstdataclients.com";  # production server
$port = 6522;
$host = "processor-host";

### sftp -oIdentityFile=.ssh/id_rsa -oPort=1022 MSOD-000533@204.194.126.57        # test old
### sftp -oIdentityFile=.ssh/id_rsa -oPort=1022 MSOF-000533@204.194.128.58        # production old

# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-GAGVI002@test-gw-na.firstdataclients.com     # test
# sftp -oIdentityFile=.sshnew/id_rsa -oPort=6522 NAGW-GAGVI002@test2-gw-na.firstdataclients.com    # test
# sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-GAGVI002@prod-gw-na.firstdataclients.com     # prod
# sftp -oIdentityFile=.sshnew/id_rsa -oPort=6522 NAGW-GAGVI002@prod2-gw-na.firstdataclients.com    # prod
#### sftp -oIdentityFile=.ssh/id_rsa -oPort=6522 NAGW-GAGVI002@prod2-gw-na.firstdataclients.com # production

# ssh -p 1022 -l MSOF-000533 -v -i /home/pay1/batchfiles/prod/fdmsintl/.ssh/id_rsa 204.194.128.58
# ssh -2 -p 1022 -l MSOF-000533 -i /home/pay1/batchfiles/prod/fdmsintl/.ssh/id_rsa 204.194.128.58 -s sftp

#$redofile = "MRDXMPLC.09072022.115457.TXT";

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );

( $d1, $today, $todaytime ) = &miscutils::genorderid();
$ttime = &miscutils::strtotime($today);

$mytime = gmtime( time() );
my $printstr = "\n\ntoday: $mytime    getfiles\n";
&procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 4 ) );
$yesterday = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyearonly" ) {
  my $printstr = "creating $fileyearonly\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/fdmsintl/$fileyearonly");
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdmsintl/$filemonth" ) {
  my $printstr = "creating $filemonth\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/fdmsintl/$filemonth");
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear" ) {
  my $printstr = "creating $fileyear\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
  system("mkdir /home/pay1/batchfiles/$devprod/fdmsintl/$fileyear");
}
if ( !-e "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: fdmsintl - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory $devprod/fdmsintl/$fileyear.\n\n";
  close MAILERR;
  exit;
}

my $dbquerystr = <<"dbEOM";
        select distinct count,amount,username,batchnum,filename
        from batchfilesfdmsi
        where status='locked'
        and username not like 'testfdmsi%'
dbEOM
my @dbvalues = ();
my @sth3valarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

$batchcnt = 0;
$batchamt = 0;
for ( my $vali = 0 ; $vali < scalar(@sth3valarray) ; $vali = $vali + 6 ) {
  ( $count, $amount, $username, $batchnum, $batchfile ) = @sth3valarray[ $vali .. $vali + 5 ];

  my $dbquerystr = <<"dbEOM";
          select merchant_id
          from customers
          where username=?
dbEOM
  my @dbvalues = ("$username");
  my ($merchant_id) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $newmid = substr( $merchant_id, 0, 7 );
  $fileamount{"$batchfile"}        += $amount;
  $midamount{"$batchfile $newmid"} += $amount;
  $midcount{"$batchfile $newmid"}++;
  $filecount{"$batchfile"}++;
  $userarray{$newmid}      = $username;
  $batchnumarray{$newmid}  = $batchnum;
  $batchfilearray{$newmid} = $batchfile;
  $newmidcnt{$newmid}++;
  $batchamt = $batchamt + $amount;
  $batchcnt = $batchcnt++;
  my $printstr = "cccc  amount: $batchamt   $amount\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
}

$numfiles = keys %filecount;

$batchfile = substr( $redofile, 0, 14 );

if ( $redofile ne "" ) {
  &processfile($redofile);

  exit;
}

my $dbquerystr = <<"dbEOM";
        select distinct filename,batchheader
        from batchfilesfdmsi
        where status='locked'
dbEOM
my @dbvalues = ();
my @sthbatchvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

$batchcnt = 0;
for ( my $vali = 0 ; $vali < scalar(@sthbatchvalarray) ; $vali = $vali + 2 ) {
  ( $batchfile, $chkfileext ) = @sthbatchvalarray[ $vali .. $vali + 1 ];

  $filename = $batchfile;
  $batchcnt++;
  my $printstr = "aaaa $chkfileext.$filename.txt  $batchcnt\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
}

&ftpconnect($fdmsaddr);

my $ls = $ftp->ls('/available') or die "unable to retrieve directory: " . $ftp->error;
my $printstr = "$_->{filename}\n" for (@$ls);
&procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

$files = $ftp->ls("/available");

if ( @$files == 0 ) {
  my $printstr = "aa no report files\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
}

foreach $var (@$files) {
  $filename = $var->{"filename"};

  if ( $filename !~ /MRDX/ ) {
    next;
  }

  my $printstr = "aaaa $filename bbbb\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

  my $fileyear = substr( $filename, 13, 4 ) . "/" . substr( $filename, 9, 2 ) . "/" . substr( $filename, 11, 2 );
  my $fileyymmdd = substr( $filename, 13, 4 ) . substr( $filename, 9, 2 ) . substr( $filename, 11, 2 );

  my $printstr = "fileyear: $fileyear\n";
  $printstr .= "fileyymmdd: $fileyymmdd\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

  &checkdir($fileyymmdd);

  my $printstr = "filename: $filename\n";
  $printstr .= "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear/$filename\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

  $ftp->get( "available/$filename", "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear/$filename", copy_perm => 0, copy_time => 0 ) or die "file transfer failed: " . $ftp->error;

  @filenamearray = ( @filenamearray, $filename );
  $mycnt++;
  if ( $mycnt > 6 ) {
    last;
  }
}

foreach $filename (@filenamearray) {
  &processfile( $filename, $today );
}

exit;

sub checkdir {
  my ($date) = @_;

  my $printstr = "checking $date\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

  $fileyear = substr( $date, 0, 4 ) . "/" . substr( $date, 4, 2 ) . "/" . substr( $date, 6, 2 );
  $filemonth = substr( $date, 0, 4 ) . "/" . substr( $date, 4, 2 );
  $fileyearonly = substr( $date, 0, 4 );

  if ( !-e "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyearonly" ) {
    my $printstr = "creating $fileyearonly\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
    system("mkdir /home/pay1/batchfiles/$devprod/fdmsintl/$fileyearonly");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/fdmsintl/$filemonth" ) {
    my $printstr = "creating $filemonth\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
    system("mkdir /home/pay1/batchfiles/$devprod/fdmsintl/$filemonth");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear" ) {
    my $printstr = "creating $fileyear\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
    system("mkdir /home/pay1/batchfiles/$devprod/fdmsintl/$fileyear");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear" ) {
    system("mkdir /home/pay1/batchfiles/$devprod/fdmsintl/$fileyear");
  }
  if ( !-e "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear" ) {
    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: fdmsintl - FAILURE\n";
    print MAILERR "\n";
    print MAILERR "Couldn't create directory $devprod/fdmsintl/$fileyear.\n\n";
    close MAILERR;
    exit;
  }

}

sub ftpconnect {
  my ($fdmsaddr) = @_;

  $mytime = gmtime( time() );
  my $printstr = "$mytime trying to connect to $fdmsaddr $port\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

  my %args = (
    user     => "NAGW-GAGVI002",
    password => '5HXm19Etm',
    port     => 6522,
    key_path => '/home/pay1/batchfiles/prod/fdmsintl/.sshnew/id_rsa'
  );

  $ftp = Net::SFTP::Foreign->new( "$fdmsaddr", %args );

  $ftp->error and die "error: " . $ftp->error;

  if ( $ftp eq "" ) {
    my $printstr = "Username $ftpun and key don't work<br>\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
    my $printstr = "failure";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
    exit;
  }

  $mytime = gmtime( time() );
  my $printstr = "$mytime connected\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

}

sub processfile {
  my ($filename) = @_;

  my $printstr = "in processfile\n";
  $printstr .= "filename: $filename\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

  my $fileyear = substr( $filename, 13, 4 ) . "/" . substr( $filename, 9, 2 ) . "/" . substr( $filename, 11, 2 );
  my $fileyymmdd = substr( $filename, 13, 4 ) . substr( $filename, 9, 2 ) . substr( $filename, 11, 2 );
  my $printstr = "fileyear: $fileyear\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

  my $infilestr = &procutils::fileread( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl/$fileyear", "$filename" );
  my @infilestrarray = split( /\n/, $infilestr );

  foreach (@infilestrarray) {
    $line = $_;
    chop $line;

    if ( $line =~ /Sending data set REMOTES.RCVPLU2.CONFIRM/ ) {
      my $myindex = index( $line, "CONFIRM" );
      my $filenum = substr( $line, $myindex + 8 );
      ($filenum) = split( / /, $filenum );
    }
    if ( $line !~ /^[0-9]/ ) {
      next;
    }

    $fields[0] = substr( $line, 0, 7 );
    $fields[1] = substr( $line, 7, 7 );
    $fields[1] =~ s/ //g;
    $fields[2] = substr( $line, 15, 11 );
    $fields[3] = substr( $line, 26, 7 );
    $fields[3] =~ s/ //g;
    $fields[4] = substr( $line, 34, 11 );
    $fields[5] = substr( $line, 46, 7 );

    $descr = $fields[5];
    $descr =~ s/ +$//g;

    my $printstr = "merchant_id: $fields[0]\n";
    $printstr .= "count: $fields[1]\n";
    $printstr .= "amount: $fields[2]\n";
    $printstr .= "descr: $descr\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

    $mid      = $fields[0];
    $batchnum = $batchnumarray{$mid};

    $username = "";

    $username = $userarray{"$mid"};

    $amtsign = substr( $fields[2],          -1,  1 );
    $fileamt = substr( $fields[2],          0,   length( $fields[2] ) - 1 );
    $fileamt = substr( "0" x 12 . $fileamt, -12, 12 );
    if ( $amtsign eq "-" ) {
      $fileamt = "-$fileamt";
    }

    my $dbquerystr = <<"dbEOM";
        select username,merchant_id
        from customers
        where merchant_id like ?
        and processor in ('fdmsintl','fdmsintlus')
        and status='live'
dbEOM
    my @dbvalues = ("$mid%");
    ( $username, $merchant_id ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    my $printstr = "username: $username\n";
    $printstr .= "merchant_id: $merchant_id\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

    if ( $username eq "" ) {
      open( MAILERR, "| /usr/lib/sendmail -t" );
      print MAILERR "To: cprice\@plugnpay.com\n";
      print MAILERR "From: dcprice\@plugnpay.com\n";
      print MAILERR "Subject: fdmsintl - FAILURE\n";
      print MAILERR "\n";
      print MAILERR "Couldn't find username for result file\n\n";
      print MAILERR "filename: /home/pay1/batchfiles/$devprod/fdmsintl/$fileyear/$filename\n";
      print MAILERR "merchant_id: $fields[0]\n";
      print MAILERR "count: $fields[1]\n";
      print MAILERR "amount: $fields[2]\n";
      print MAILERR "fileamt: $fileamt\n";
      print MAILERR "descr: $descr\n";
      close MAILERR;
      exit;
      return;
    }

    my $printstr = "yesterday: $yesterday\n";
    $printstr .= "fileamt: $fileamt\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

    $batchfile = "";
    $count     = "";
    $batchamt  = "";
    foreach $key ( sort keys %midamount ) {
      ( $batchfile, $newmid ) = split( / /, $key );

      $amount = $fileamount{"$batchfile"};

      my $printstr = "key: $key\n";
      $printstr .= "amount: $amount\n";
      $printstr .= "newmid: $newmid $mid  amount: $amount  $fileamt\n";
      &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

      if ( ( $newmid eq $mid ) && ( $amount == $fileamt ) ) {
        $batchamt = $amount;
        $count    = $filecount{"$batchfile"};
        last;
      }
    }

    my $printstr = "batchamt: $batchamt\n";
    $printstr .= "count: $count\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

    if ( $count < 1 ) {
      open( MAILERR, "| /usr/lib/sendmail -t" );
      print MAILERR "To: cprice\@plugnpay.com\n";
      print MAILERR "From: dcprice\@plugnpay.com\n";
      print MAILERR "Subject: fdmsintl - FAILURE\n";
      print MAILERR "\n";
      print MAILERR "Couldn't find batch for result file\n\n";
      print MAILERR "filename: /home/pay1/batchfiles/$devprod/fdmsintl/$fileyear/$filename\n";
      print MAILERR "username: $username\n";
      print MAILERR "merchant_id: $fields[0]\n";
      print MAILERR "count: $fields[1]\n";
      print MAILERR "amount: $fields[2]\n";
      print MAILERR "fileamt: $fileamt\n";
      print MAILERR "descr: $descr\n";
      close MAILERR;
      exit;
      return;
    }

    my $printstr = "dddd: $batchamt  $fileamt  $username  $batchfile  $batchnum\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

    if ( ( $descr ne "" ) && ( $batchamt == $fileamt ) && ( $username ne "" ) ) {
      my $dbquerystr = <<"dbEOM";
          update batchfilesfdmsi set status='done'
          where filename=?
          and status='locked'
dbEOM
      my @dbvalues = ("$batchfile");
      &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    }
    my $printstr = "before if\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );

    if ( ( $descr eq "MATCH" ) && ( $batchamt == $fileamt ) && ( $username ne "" ) ) {
      my $printstr = "success aa: $username (not related)  $midamount{$mid}  $fields[2]\n";
      &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
      $myyear = substr( $batchfile, 0, 4 );
      unlink "/home/pay1/batchfiles/$devprod/fdmsintl/$myyear/$batchfile";

      my $dbquerystr = <<"dbEOM";
            select orderid,username,batchnum
            from batchfilesfdmsi
            where filename=?
dbEOM
      my @dbvalues = ("$batchfile");
      my @sthordvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

      for ( my $vali = 0 ; $vali < scalar(@sthordvalarray) ; $vali = $vali + 3 ) {
        ( $orderid, $username, $batchnum ) = @sthordvalarray[ $vali .. $vali + 2 ];

        my $printstr = "successful: $username  $batchfile  $orderid  $batchnum\n";
        &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "ftplog.txt", "append", "misc", $printstr );
        my $dbquerystr = <<"dbEOM";
                update trans_log
                set finalstatus='success',trans_time=?
                where orderid=?
                and username=?
                and result=?
                and finalstatus='locked'
                and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
        my @dbvalues = ( "$todaytime", "$orderid", "$username", "$batchnum" );
        &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

        my $dbquerystr = <<"dbEOM";
                update operation_log set returnstatus='success',lastopstatus='success',returntime=?,lastoptime=?
                where orderid=?
                and username=?
                and batchfile=?
                and processor in ('fdmsintl','fdmsintlus')
                and lastop='return'
                and lastopstatus='locked'
                and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
        my @dbvalues = ( "$todaytime", "$todaytime", "$orderid", "$username", "$batchnum" );
        &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

        my $dbquerystr = <<"dbEOM";
                update operation_log set postauthstatus='success',lastopstatus='success',postauthtime=?,lastoptime=?
                where orderid=?
                and username=?
                and batchfile=?
                and processor in ('fdmsintl','fdmsintlus')
                and lastop='postauth'
                and lastopstatus='locked'
                and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
        my @dbvalues = ( "$todaytime", "$todaytime", "$orderid", "$username", "$batchnum" );
        &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      }

    }
  }

}

exit;

