#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::FTP;
use miscutils;
use procutils;
use Net::SSLeay qw(get_https post_https sslcat make_headers make_form);
use IO::Socket;
use Socket;
use rsautils;
use isotables;
use smpsutils;

$devprod = "logs";

if ( -e "/home/pay1/batchfiles/stopgenfiles.txt" ) {
  my $printstr = "stopgenfiles.txt, exiting...\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
  exit;
}

$cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'visanet/genfiles.pl'`;
my $printstr = "cnt: $cnt\n";
&procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
if ( $cnt >= 1 ) {
  my $printstr = "genfiles.pl already running, exiting...\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );

  exit;
}

my $checkuser = &procutils::fileread( "$username", "visanet", "/home/pay1/batchfiles/$devprod/visanet", "genfiles0.txt" );
chop $checkuser;

if ( ( $checkuser =~ /^z/ ) || ( $checkuser eq "" ) ) {
  my $printstr = "visanet genfiles.pl finished normally, exiting...\n";
  &procutils::filewrite( "$username", "visanet", "/home/pay1/batchfiles/devlogs/visanet", "miscdebug.txt", "append", "misc", $printstr );
  exit;
} else {

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "Bcc: dprice\@plugnpay.com\n";
  print MAILERR "Bcc: 3039219466\@vtext.com\n";
  print MAILERR "Bcc: 6318061932\@vtext.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: visanet - genfiles failed, must be restarted\n";
  print MAILERR "\n";
  print MAILERR "visanet genfiles.pl must be restarted.\n\n";
  close MAILERR;

}

