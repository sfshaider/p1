use strict;
use warnings;

use Test::More tests => 19;
use Test::Exception;

require_ok('PlugNPay::Legacy::Transflags');

my $tfbm = new PlugNPay::Legacy::Transflags();

my $expected = 'capture,init,partial'; # sorted alphabetically
$tfbm->addFlag('capture','init','partial');
my $legacyString = $tfbm->toLegacyString();
is($legacyString,$expected,'adding capture,init, and partial results in properly formatted legacy string');
my $hex = $tfbm->toHexString();
is($hex,'0x248','capture, init, partial to hex is 0x248');

my $tfbm2 = new PlugNPay::Legacy::Transflags();
$tfbm2->fromHexString($hex);
my $legacyStringFromHex = $tfbm2->toLegacyString();
is($legacyStringFromHex,$expected,'setting transflags from hex results in properly formatted legacy string');

is("$tfbm2",$expected,'using object as a string results in properly formatted legacy string');
is($tfbm2,$expected,'using object with eq operator results in properly formatted legacy string');
like($tfbm2,qr/$expected/,'using object with regex results in properly formatted legacy string');

my $validFlags = $tfbm->getValidFlags();
ok(@{$validFlags} > 0, 'valid flags returns more than zero flags');

# edge case, all flags set
$tfbm->addFlag(@{$validFlags});
isnt("$tfbm",'','all flags set does not return an empty string');
lives_ok(sub {
  $tfbm->toHexString();
},'toHexString does not die when all flags are set');
$tfbm->removeFlag('init');
unlike("$tfbm",qr/,init,/,'init flag removed from legacy string format after transflag is removed');

$tfbm .= 'moto';
ok($tfbm->hasFlag('moto'),'operation .= adds transflag to object');

$tfbm = $tfbm . 'void';
ok($tfbm->hasFlag('void'),'operation . adds transflag to object');
ok($tfbm =~ /void/,'regex search successful');
is(ref($tfbm),'PlugNPay::Legacy::Transflags','object is still an...object...after regex search');

# test getFlags
my $flags = $tfbm->getFlags();
is(ref($flags),'ARRAY','getFlags returns an array reference');
ok(@{$flags} > 0,'getFlags returns a non-empty array reference');

# test fix recurring flags
$tfbm->addFlag('recinit');
ok($tfbm->hasFlag('init') && $tfbm->hasFlag('recurring'), 'recinit converted to init,recurring');

$tfbm->removeFlag('init','recurring','recinit');
$tfbm->addFlag('recinitial');
ok($tfbm->hasFlag('init') && $tfbm->hasFlag('recurring'), 'recinitial converted to init,recurring');
