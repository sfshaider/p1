#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 14;
use Test::Exception;
use Test::MockModule;

require_ok('PlugNPay::Transaction::IpList::IpInfo');

my $ipInfo = new PlugNPay::Transaction::IpList::IpInfo();

my $username = 'twoallbeefpatties';
$ipInfo->setAccountUsername($username);
is($ipInfo->accountUsername(),$username,'account username is set/retrieved correctly');

my $recommendation = 'specialsauce';
dies_ok(sub { $ipInfo->setRecommendation($recommendation) },'invalid recommendaation dies');
$recommendation = 'allow';
$ipInfo->setRecommendation($recommendation);
is($ipInfo->recommendation(),$recommendation,'allow recommendation is set/retrieved correctly');
$recommendation = 'deny';
$ipInfo->setRecommendation($recommendation);
is($ipInfo->recommendation(),$recommendation,'deny recommendation is set/retrieved correctly');

my $forcedStatus = 'lettuce';
dies_ok(sub { $ipInfo->setForcedStatus($forcedStatus)},'invalid forced status dies');
$forcedStatus = 'neutral';
$ipInfo->setForcedStatus($forcedStatus);
is($ipInfo->forcedStatus(),$forcedStatus,'neutral forced status is set/retrieved correctly');
$forcedStatus = 'positive';
$ipInfo->setForcedStatus($forcedStatus);
is($ipInfo->forcedStatus(),$forcedStatus,'positive forced status is set/retrieved correctly');
$forcedStatus = 'negative';
$ipInfo->setForcedStatus($forcedStatus);
is($ipInfo->forcedStatus(),$forcedStatus,'negative forced status is set/retrieved correctly');

my $reason = 'cheese';
$ipInfo->setReason($reason);
is($ipInfo->reason(),$reason,'reason is set/retrieved correctly');

my $ip = 'pickles';
$ipInfo->setIp($ip);
is($ipInfo->ip(),$ip,'ip is set/retrieved correctly');

my $requests = ['sesame','seed','bun'];
$ipInfo->setRecentRequests($requests);
is($ipInfo->recentRequests(),$requests,'recent requests are set/retrieved correctly');

my $positiveCount = 5;
$ipInfo->setPositiveCount($positiveCount);
is($ipInfo->positiveCount,$positiveCount,'positive count is set/retrieved correctly');

my $negativeCount = 7;
$ipInfo->setNegativeCount($negativeCount);
is($ipInfo->negativeCount,$negativeCount,'positive count is set/retrieved correctly');

