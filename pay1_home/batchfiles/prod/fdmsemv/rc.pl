#!/usr/local/bin/perl

$| = 1;

use lib '/home/p/pay1/perl_lib';
use Net::FTP;
use Net::SSLeay qw(get_https post_https sslcat make_headers make_form);
use miscutils;
use smpsutils;
use isotables;
use IO::Socket;
use Socket;
use MIME::Base64;

print "input password: ";
$password = <stdin>;
chop $password;

# first login
$encpw = $password;
$encpw =~ s/(\W)/'%' . unpack("H2",$1)/ge;    # urlencode

$message = "username=vend.pricec1&password=$encpw&login-form-type=pwd";

my $host = "www.rapidconnect.com";
my $port = "443";
my $path = "/pkmslogin.form";

my $req = "POST $path HTTP/1.1\r\n";
$req .= "Host: $host\r\n";
$req .= "User-Agent: PlugNPay\r\n";
$req .= "Content-Type: text/xml\r\n";
$req .= "Content-Length: ";

my $msglen = length($message);
$req .= "$msglen\r\n";

$req .= "\r\n";
$req .= "$message";

my ( $response, $header ) = &sslsocketwrite( $req, "www.rapidconnect.com", "443" );
print "$header\n\n";
print "$response\n\n";
open( logfile, ">>/home/p/pay1/batchfiles/fdmsemv/rc.txt" );
print logfile "$response\n\n";
print logfile"\n----------------------------------------------------------------------------------------------\n\n";
close(logfile);

print "\n----------------------------------------------------------------------------------------------\n\n";

$cookie = $header;
$cookie =~ s/\r{0,1}\n/xxxxx/g;
$cookie =~ s/^.*Set-Cookie: //;
$cookie =~ s/;.*$//g;

$path = $header;
$path =~ s/\r{0,1}\n/xxxxx/g;
$path =~ s/^.*Location: //i;
$path =~ s/xxxxx.*$//g;
$path =~ s/https:\/\/www.rapidconnect.com//;

print "cookie: $cookie aa\n";
print "location: $path bb\n";

# after login redirect
my $req = "GET $path HTTP/1.1\r\n";
$req .= "Host: $host\r\n";
$req .= "User-Agent: PlugNPay\r\n";
$req .= "Cookie: $cookie\r\n\r\n";

my ( $response, $header ) = &sslsocketwrite( $req, "www.rapidconnect.com", "443" );
print "$header\n\n";
print "$response\n\n";
open( logfile, ">>/home/p/pay1/batchfiles/fdmsemv/rc.txt" );
print logfile "$response\n\n";
print logfile"\n----------------------------------------------------------------------------------------------\n\n";
close(logfile);

print "\n----------------------------------------------------------------------------------------------\n\n";

$cookie = $header;
$cookie =~ s/\r{0,1}\n/xxxxx/g;
$cookie =~ s/^.*?Set-Cookie: //;
$cookie =~ s/; Path.*?xxxxxSet-Cookie: /; /g;
$cookie =~ s/; Path.*$//;

$path = $header;
$path =~ s/\r{0,1}\n/xxxxx/g;
$path =~ s/^.*Location: //i;
$path =~ s/xxxxx.*$//g;
$path =~ s/https:\/\/www.rapidconnect.com//;

print "cookie: $cookie aa\n";
print "location: $path bb\n";

OWASP_CSRFTOKEN Project_ID _sourcePage __fp $path = "/rc/secapp/RapidConnect/SandBox.action?projectDetail=RPL001&Project_ID=RPL001";
< input type = "hidden" id = "csrf_Token" name = "OWASP_CSRFTOKEN" value = "3FI3-Y0AO-2BD6-I849-UCZN-8MXW-H8H2-AUT7-Q7BR-KPLV-OOAQ-UXOK-TRMK-13MU-6GZQ-KP7D-SM9O-C4VV-A6FH-STPB" / >;

# show all projects
my $req = "GET $path HTTP/1.1\r\n";
$req .= "Host: $host\r\n";
$req .= "User-Agent: PlugNPay\r\n";
$req .= "Cookie: $cookie\r\n\r\n";

my ( $response, $header ) = &sslsocketwrite( $req, "www.rapidconnect.com", "443" );
print "$header\n\n";
print "$response\n\n";

open( logfile, ">>/home/p/pay1/batchfiles/fdmsemv/rc.txt" );
print logfile "$response\n\n";
print logfile"\n----------------------------------------------------------------------------------------------\n\n";
close(logfile);

print "\n----------------------------------------------------------------------------------------------\n\n";

$cookie = $header;
$cookie =~ s/\r{0,1}\n/xxxxx/g;
$cookie =~ s/^.*?Set-Cookie: //;
$cookie =~ s/; Path.*?xxxxxSet-Cookie: /; /g;
$cookie =~ s/; Path.*$//;

$path = $header;
$path =~ s/\r{0,1}\n/xxxxx/g;
$path =~ s/^.*Location: //i;
$path =~ s/xxxxx.*$//g;
$path =~ s/https:\/\/www.rapidconnect.com//;

print "cookie: $cookie aa\n";
print "location: $path bb\n";

exit;

open( logfile, ">>/home/p/pay1/batchfiles/fdmsemv/logs/$fileyear/$username$time$pid.txt" );
print logfile "bbbb  newhour: $newhour  settlehour: $settlehour\n";
close(logfile);

sub sslsocketwrite {
  my ( $req, $host, $port ) = @_;

  Net::SSLeay::load_error_strings();
  Net::SSLeay::SSLeay_add_ssl_algorithms();
  Net::SSLeay::randomize('/etc/passwd');

  my $dest_serv = $host;

  my $dest_ip = gethostbyname($dest_serv);
  my $dest_serv_params = sockaddr_in( $port, $dest_ip );

  my $flag = "pass";
  socket( S, &AF_INET, &SOCK_STREAM, 0 ) or return ("socket: $!");

  connect( S, $dest_serv_params ) or return ("connect: $!");

  if ( $flag ne "pass" ) {
    return;
  }
  select(S);
  $| = 1;
  select(STDOUT);    # Eliminate STDIO buffering

  # The network connection is now open, lets fire up SSL
  my $ctx = Net::SSLeay::CTX_new() or die_now("Failed to create SSL_CTX $!");

  # stops "bad mac decode" and "data between ccs and finished" errors by forcing version 2

  Net::SSLeay::CTX_set_options( $ctx, &Net::SSLeay::OP_ALL ) and Net::SSLeay::die_if_ssl_error("ssl ctx set options");
  my $ssl = Net::SSLeay::new($ctx) or die_now("Failed to create SSL $!");
  Net::SSLeay::set_fd( $ssl, fileno(S) );    # Must use fileno
  my $res = Net::SSLeay::connect($ssl) or die "$!";

  # Exchange data
  $res = Net::SSLeay::ssl_write_all( $ssl, $req );    # Perl knows how long $msg is
                                                      #Net::SSLeay::die_if_ssl_error("ssl write");

  shutdown S, 1;                                      # Half close --> No more output, sends EOF to server

  my $respenc = "";

  my ( $rin, $rout, $temp );
  vec( $rin, $temp = fileno(S), 1 ) = 1;
  my $count = 8;
  while ( $count && select( $rout = $rin, undef, undef, 15.0 ) ) {

    my $got = Net::SSLeay::read($ssl);                # Perl returns undef on failure
                                                      #open(tmpfile,">>/home/p/pay1/batchfiles/wirecard/sslserverlogmsg.txt");
                                                      #print tmpfile "got: $got\n";
                                                      #close(tmpfile);
    $got =~ s/^[0-9a-zA-Z]{1,3}\r\n//;
    $respenc = $respenc . $got;
    if ( $respenc =~ /\x03/ ) {
      last;
    }

    $count--;
  }

  my $response = $respenc;

  Net::SSLeay::free($ssl);                            # Tear down connection
  Net::SSLeay::CTX_free($ctx);
  close S;

  $wirecard::mytime = gmtime( time() );
  my $chkmessage = $response;
  $chkmessage =~ s/\r{0,1}\n/;;;;/g;
  $chkmessage =~ s/^ {8}</  </g;
  $chkmessage =~ s/;;;;/\n/g;
  my ( $dummy, $mydate ) = &miscutils::genorderid();
  my $week = substr( $mydate, 6, 2 ) / 7;
  $week = sprintf( "%d", $week + .0001 );
  open( logfile, ">>/home/p/pay1/batchfiles/wirecard/serverlogmsg$week.txt" );
  print logfile "$wirecard::username $wirecard::datainfo{'order-id'}\n\n";
  print logfile "$wirecard::mytime recv: $chkmessage\n\n";

  close(logfile);

  my $header;
  ( $header, $response ) = split( /\r{0,1}\n\r{0,1}\n/, $response, 2 );

  return $response, $header;
}

1;

