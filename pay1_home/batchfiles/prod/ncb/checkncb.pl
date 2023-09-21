#!/usr/local/bin/perl

require 5.001;
$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;

$now = time();

$filestr = `tail -200 /home/pay1/batchfiles/logs/ncb/serverlogmsg.txt`;

$ncbfail = 0;

@lines = split( /\n/, $filestr );
$lastuser = "";
foreach $line (@lines) {
  if ( $line =~ /send:/ ) {
    $sendtimeold = $sendtime;
    ( $d1, $month, $day, $time, $year ) = split( / /, $line );
    ( $hour, $min, $sec ) = split( /:/, $time );
    $sendtime = $year . $month_array2{$month} . $day . $hour . $min . $sec;
    $sendcnt++;
  } elsif ( ( ( $line =~ /recv:/ ) && ( length($line) > 40 ) ) || ( $line =~ /null message found/ ) ) {
    $socketattemptcnt = 0;
    $recvtimeold      = $recvtime;
    ( $d1, $month, $day, $time, $year, $oper, $computer, $message ) = split( / +/, $line, 8 );
    ( $hour, $min, $sec ) = split( /:/, $time );
    if ( $line !~ /null message found/ ) {
      $recvtime = sprintf( "%04d%02d%02d%02d%02d%02d", $year, $month_array2{$month}, $day, $hour, $min, $sec );
      if ( ( $recvtime > 20000101000000 ) && ( $recvtime < 20370101000000 ) ) {
        $recvtimeval = &miscutils::strtotime($recvtime);
      } else {
        $processor = substr( $processor . " " x 12, 0, 12 );
        return "$processor";
      }
    }
    if ( $line =~ /failure/ ) {
      $failureflag = 1;
    } else {
      $failureflag = 0;
    }
    $sendcnt          = 0;
    $socketattemptcnt = 0;
  } elsif ( ( $line =~ /failure/ ) && ( $line !~ /Authorise card failure/ ) ) {
    $rcvsndfailurecnt++;
  } elsif ( $line =~ /socketopen attempt/ ) {
    $socketattemptcnt++;
  } elsif ( $line =~ /socketopen successful/ ) {
    $socketattemptcnt = 0;
    $rcvsndfailurecnt = 0;
  }

  #elsif ($line =~ /temporarily unavailable/) {
  #  $resourceunavailablecnt++;
  #}
  elsif ( ( $processor eq "mercury" ) && ( $line =~ /^[a-z0-9]{2,12}  [0-9]{12}/ ) ) {
    my $chkuser = $line;
    ( $lastuser, $lastoid ) = split( /  /, $line );
  }
}

$delta = $now - $recvtimeval;

$chksendcnt = 3;

if ( ( ( $sendcnt > $chksendcnt ) && ( $now > $recvtimeval + 60 ) )
  || ( $socketattemptcnt > 3 )
  || ( ( $accessdelta > 30 ) && ( $modtime ne "" ) && ( $computer ne "keystone" ) )
  || ( $rcvsndfailurecnt > 10 )
  || ( $failureflag == 1 ) ) {
  $processor = substr( $processor . " " x 12, 0, 12 );

  my $printstr = "$mytime EST $processor$group\nsendcnt: $sendcnt $chksendcnt  now: $now $recvtimeval accessdelta: $chtime $modtime $accessdelta    $rcvsndfailurecnt $failureflag $socketattemptcnt\n\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

  $ncbfail = 1;
}
if ( $resourceunavailablecnt > 1 ) {
  $ncbfail = 1;
}

if ( $ncbfail == 1 ) {
  my $infilestr = &procutils::fileread( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb", "checkncbfail.txt" );
  my @infilestrarray = split( /\n/, $infilestr );

  $emailsenttime = $infilestrarray[0];
  chop $emailsenttime;

  if ( $now - $emailsenttime > 1200 ) {
    my $printstr = "send email\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

    $outfilestr = "";
    $outfilestr .= "$now\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb", "checkncbfail.txt", "write", "", $outfilestr );

    if (1) {
      open( MAIL, "| /usr/lib/sendmail -t" );
      print MAIL "To: computeroperators\@jncb.com\n";
      print MAIL "From: cprice\@plugnpay.com\n";
      print MAIL "Cc: DataCentreMonitors\@jncb.com\n";
      print MAIL "Bcc: LewisRS\@jncb.com\n";
      print MAIL "Bcc: cprice\@plugnpay.com\n";
      print MAIL "Bcc: dprice\@plugnpay.com\n";
      print MAIL "Subject: Plug \& Pay Technologies - JNCB - cannot connect\n";
      print MAIL "\n";
      print MAIL "Plug \& Pay Technologies cannot connect. Can you reset the application?\n";
      print MAIL "\n";
      print MAIL "\n";
      print MAIL "Thank you,\n";
      print MAIL "Carol Price\n";
      print MAIL "Plug \& Pay Technologies, Inc.\n";
      print MAIL "cprice\@plugnpay.com\n";
      print MAIL "970-532-0607\n";
      close(MAIL);
    }
  }
}

exit;

