#!/usr/local/bin/perl

$| = 1;

use lib '/home/p/pay1/perl_lib';
use Net::FTP;
use miscutils;
use Net::SSLeay qw(get_https post_https sslcat make_headers make_form);
use IO::Socket;
use Socket;
use rsautils;
use isotables;
use smpsutils;
use Time::Local;

# test ip 206.175.128.3

# visa net DirectLink-visanetemv version 1.7

my ($orderid)    = &miscutils::genorderid();
my $operation    = "forceauth";
my $price        = "usd 8.00";
my $cardnumber   = "4017779999999016";
my $trandatetime = "20150927100101";
my $auth_code    = "12345A";
my $refnumber    = "526400125130";             # YDDD00TTTTTT    T = trace number
my $networkid    = "Z";
my $settledate   = "0928";

&reenter( "testvisaemv", $orderid, $operation, $price, $cardnumber, $trandatetime, $auth_code, $refnumber, $networkid, $settledate );

($orderid) = &miscutils::incorderid($orderid);
$operation    = "return";
$price        = "usd 9.00";
$cardnumber   = "4017779999999016";
$trandatetime = "20150927100102";
$auth_code    = "12345B";
$refnumber    = "526400125230";                # YDDD00TTTTTT    T = trace number
$networkid    = "Z";
$settledate   = "0928";

&reenter( "testvisaemv", $orderid, $operation, $price, $cardnumber, $trandatetime, $auth_code, $refnumber, $networkid, $settledate );

sub reenter {
  my ( $username, $orderid, $operation, $price, $cardnumber, $trandatetime, $auth_code, $refnumber, $networkid, $settledate ) = @_;

  my ( $currency, $amount ) = split( / /, $price );
  $amount = sprintf( "%d", ( $amount * 100 ) + .0001 );
  $amount = substr( "0" x 12 . $amount, -12, 12 );

  $trandatetime = substr( $trandatetime, 2 );

  $authcode = $auth_code    # 0
    . " "                   # 6 aci
    . "E"                   # 7 auth_src
    . "  "                  # 8 pass
    . " " x 15              # 10 trans_id
    . " " x 4               # 25 val_code
    . " " x 10              # 29 comminfo
    . $trandatetime         # 39 trandate
                            # 45 trantime
    . "0001"                # 51 transseqnum
    . "0" x 8               # 55 tax
    . " " x 25              # 63 ponumber
    . "K"                   # 88 cardholderidcode
    . "D"                   # 89 acctdatasrc
    . " "                   # 90 requestedaci
    . "0" x 12              # 91 gratuity
    . $amount               # 103 origamount
    . "  "                  # 115 cardlevelresults
    . "    "                # 117 installinfo
    . " "                   # 121 eci
    . " "                   # 122 ucafind
    . " " x 10              # 123 shipzip
    . " " x 9               # 133 suppliernum
    . " " x 8               # 142 convfee
    . " "                   # 150 iiasind
    . " " x 12              # 151 posentry
    . " "                   # 163 sqi
    . $networkid            # 164 networkid
    . $settledate           # 165 settledate
    . "0" x 12;             # 169 cashback
  print "$orderid\n";
  print "$authcode\n";

  %result = &miscutils::sendmserver(
    "$username",    "$operation", 'order-id',  $orderid,    'amount',     $price,       'card-number', $cardnumber,     'card-name',  "",
    'card-address', "",           'card-city', "",          'card-state', "",           'card-zip',    "",              'zip',        $shipzip,
    'card-country', "",           'card-exp',  "12/15",     'auth-code',  "$authcode",  'installnum',  "$installnum",   'installtot', "$installtot",
    'gratuity',     "$gratuity",  'cashback',  "$cashback", 'healthamt',  "$healthamt", 'rxamt',       "$rxamt",        'visionamt',  "$visionamt",
    'dentalamt',    "$dentalamt", 'mvv',       "$mvv",      'refnumber',  "$refnumber", 'transflags',  "debit,reenter", @extrafields
  );
  print "$result{'FinalStatus'}\n";
  print "$result{'MErrMsg'}\n";

  if ( $operation eq "forceauth" ) {
    %result = &miscutils::sendmserver( "$username", "postauth", 'amount', $price, 'order-id', $orderid );
    print "$result{'FinalStatus'}\n";
    print "$result{'MErrMsg'}\n";
  }

}

exit;

