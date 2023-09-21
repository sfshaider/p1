#!/usr/bin/perl

use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Token::Client;
use PlugNPay::Token::Request;
use Time::HiRes qw(time);

my $cardNumber = '4111111111111111';
my $req = new  PlugNPay::Token::Request();
$req->setRequestType('REQUEST_TOKENS');
$req->addCardNumber('cardnumber',$cardNumber,25);
  
print "Testing token request for '4111111111111111'.\n";
my $client = new PlugNPay::Token::Client();
$client->setRequest($req);
my $resp = $client->getResponse();
my $token = $resp->get('cardnumber');
print 'Token: ' . $token . "\n";


print "Redeeming token from previous request.\n";
my $req2 = new PlugNPay::Token::Request();
$req2->setRequestType('REDEEM_TOKENS');
$req2->setRedeemMode('REPORTING');
$req2->addToken('tok',$token,25);
$client->setRequest($req2);
my $resp2 = $client->getResponse();
my $tokenRedemption = $resp2->get('tok');
print 'Token redeemed to: ' . $tokenRedemption . "\n";
