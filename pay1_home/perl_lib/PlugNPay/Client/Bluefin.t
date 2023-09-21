#!/bin/env perl

use strict;
use warnings;
use Test::More tests => 10;
use Test::Exception;
use Test::MockModule;

use PlugNPay::Testing qw(skipIntegration);
require_ok('PlugNPay::Client::Bluefin');

# This is not a real credit card, so don't try and steal my money - Dylan
my $swipe = "02B601801F3B2500839B%7001********7136^MANITTA/DYLAN A           ^0000********?*;7001********7136=2412*************?*8985397598AC90966F4C86141A4A9E54E2080204F1A121BC372ADD3DA5A1037B9DA430AC2CB20582F30032B260BAF626F469D734D122724877C3305F51CC5B1AABA9D02AF89CC93006C62C492E93A57E05877DB6009D79C1BD4E9E6A2B1B64BB726B2D531352CF6B0000000000000000000000000000000000000000000000000000000000000000000000000000000032303752313037303332FFFFFF020009A1E000060F5F03";

my $bf = new PlugNPay::Client::Bluefin();
$bf->setGatewayAccount('dylaninc');
my $status = $bf->decryptSwipe($swipe, {});
is($bf->getServiceEndpoint(), 'https://microservice-bluefin.local/v1/decrypt', 'Got service url successfully');
ok($status, 'Successfully sent parse request');
ok($bf->getMessageID(), 'Message id was returned');
ok($bf->getSerial(), 'Device serial was returned');
ok($bf->getDevice(), 'Device type returned');
is($bf->getFirstName(),'DYLAN A', 'Card first name returned');
is($bf->getSurname(), 'MANITTA', 'Card surname returned');
is($bf->getCardNumber(),'7001111836277136', 'Card number was returned');
ok($bf->getTrack1(), 'Track1 ASCII returned');
