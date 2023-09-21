#!/usr/local/bin/perl

use lib '/home/pay1/perl_lib';
use miscutils;
use procutils;

# check that worldpayfis is closing batches each night

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() );
my $fileyymmdd = sprintf( "%04d/%02d/%02d", $year + 1900, $month + 1, $day );

my $line = `grep -c '<HostItemID>1</HostItemID>' /home/pay1/batchfiles/logs/worldpayfis/$fileyymmdd/*.txt`;
my @lines = split( /\n/, $line );

my $cnt = 0;
foreach my $line (@lines) {
  $line =~ s/^.*\///g;
  print "$line\n";

  if ( ( $line !~ /\:1$/ ) && ( $line !~ /\:0$/ ) ) {
    $linearray{"$line"} = 1;
    $cnt++;
  }
}

#<ExpressResponseMessage>Need To Close Batch</ExpressResponseMessage>
my $line = `grep -c 'Need To Close' /home/pay1/batchfiles/logs/worldpayfis/$fileyymmdd/*.txt`;
my @lines = split( /\n/, $line );

foreach my $line (@lines) {
  $line =~ s/^.*\///g;
  print "$line\n";

  if ( $line !~ /\:0$/ ) {
    $linearray{"$line"} = 1;
    $cnt++;
  }
}

print "\n";
foreach my $key ( sort keys %linearray ) {
  print "$key\n";
}
print "$cnt\n";

if ( $cnt > 0 ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "Cc: dprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: worldpayfis - not setup for time initiated batch close\n";
  print MAILERR "\n";
  print MAILERR "The following are not setup for time initiated batch close at worldpayfis\n";
  foreach my $key ( sort keys %linearray ) {
    print MAILERR "$key\n";
  }
  close MAILERR;
}

exit;

