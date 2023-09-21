#!/bin/env perl

# The Road goes ever on and on
# Down from the door where it began.
# Now far ahead the Road has gone,
# And I must follow, if I can,
# Pursuing it with eager feet,
# Until it joins some larger way
# Where many paths and errands meet.
# And whither then? I cannot say
#
# - J.R.R. Tolkien, The Fellowship of the Ring

use strict;
use warnings;

use Test::More tests => 32;
use Test::Exception;

require_ok('miscutils');

#VISA
my $visa = '4111111111111111';
is(&miscutils::luhn10($visa),'success', 'luhn10 check VISA');
is(&miscutils::cardtype($visa),'VISA', 'cardtype check VISA');

#MasterCard
my $mstr = '5555555555554444';
is(&miscutils::luhn10($mstr),'success', 'luhn10 check MasterCard');
is(&miscutils::cardtype($mstr),'MSTR', 'cardtype check MasterCard');

#AmericanExpress
my $amex = '378282246310005';
is(&miscutils::luhn10($amex),'success', 'luhn10 check American Express');
is(&miscutils::cardtype($amex),'AMEX', 'cardtype check American Express');
#DinersClub
my $dnrs = '38520000023237';
is(&miscutils::luhn10($dnrs),'success', 'luhn10 check Diners Club');
is(&miscutils::cardtype($dnrs),'DNRS', 'cardtype check Diners Club');

#Carte Blanche
my $crtb = '38900000000007';
is(&miscutils::luhn10($crtb),'success', 'luhn10 check Carte Blanche');
is(&miscutils::cardtype($crtb),'CRTB', 'cardtype check Carte Blanche');

#Discover
my $dscr = '6011000990139424';
is(&miscutils::luhn10($dscr),'success', 'luhn10 check Discover');
is(&miscutils::cardtype($dscr), 'DSCR', 'cardtype check Discover');

#JCB
my $jcb = '3530111333300000';
is(&miscutils::luhn10($jcb), 'success', 'luhn10 check JCB');
is(&miscutils::cardtype($jcb),'JCB', 'cardtype check JCB');

#WEX
my $wex = '0480000000000';
is(&miscutils::luhn10($wex), 'success', 'luhn10 check WEX Fleet');
is(&miscutils::cardtype($wex), 'WEX', 'cardtype check WEX Fleet');

#JAL
my $jal = '2131000000000008';
is(&miscutils::luhn10($jal), 'success', 'luhn10 check JAL');
is(&miscutils::cardtype($jal), 'JAL', 'cardtype check JAL');

#MYAR, whatever that stands for
my $myar = '7777666655550006';
is(&miscutils::luhn10($myar),'success', 'luhn10 check MYAR');

#Keycard
my $kc = '7777777777777777';
is(&miscutils::luhn10($kc),  'success', 'luhn10 check Keycard');
is(&miscutils::cardtype($kc), 'KC', 'cardtype check Keycard');

#Maestro UK/International and SWITCH cards
my $swtch = '6759649826438453';
is(&miscutils::luhn10($swtch),'success', 'luhn10 check Maestro Card');
is(&miscutils::cardtype($swtch), 'SWTCH', 'cardtype check Maestro/SWITCH cards');

#SOLO 
my $solo = '6767101999990019';
is(&miscutils::luhn10($solo),'success', 'luhn10 check SOLO card');
is(&miscutils::cardtype($solo), 'SOLO', 'cardtype check SOLO card');

#Plug & Pay Private Label Card
my $pp = '8111111111111112';
is(&miscutils::luhn10($pp),  'success', 'luhn10 check PnP Private Label card');
is(&miscutils::cardtype($pp), 'PP', 'cardtype check PnP Private Label card');

#Plug & Pay Stored Value Card
my $sv = '9111111111111110';
is(&miscutils::luhn10($sv),  'success', 'luhn10 check PnP Stored Value card');
is(&miscutils::cardtype($sv),'SV', 'cardtype check PnP Stored Value card');

#Private Label Cards
my $pl = '6046261100001111';
is(&miscutils::luhn10($pl),  'success', 'luhn10 check Private Label card');
is(&miscutils::cardtype($pl), 'PL', 'cardtype check Private Label card');
