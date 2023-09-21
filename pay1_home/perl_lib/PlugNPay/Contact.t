#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 2;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;

require_ok('PlugNPay::Contact');

my $contact = new PlugNPay::Contact;

# attempt to set two email addresses separated by a comma
$contact->setEmailAddress('noreply@plugnpay.com,trash@plugnpay.com');
is($contact->getEmailAddress(),'noreply@plugnpay.com','ensure that only one email address can be set with setEmailAddress()');
