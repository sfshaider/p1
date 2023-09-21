use strict;
use warnings;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Username;

sub setupUser {
 my $username = new PlugNPay::Username('paddeninc');
 $username->setSubEmail('paddeninc@test.com');
 return $username;
}

sub testSaveSubEmail {
 my $username = setupUser();
 eval {
  $username->saveSubEmail();
 };

 if($@) {
  print "$@";
 } else {
  print "0";
 }

}

sub testSaveSubFeatures {
 my $username = new PlugNPay::Username('paddeninc');
 $username->setSubFeatures({'test' => 'test'});
 eval {
  $username->saveSubFeatures();
 };

 if($@) {
  print "$@\n";
 } else {
  print "0";
 }
}

testSaveSubEmail();
testSaveSubFeatures();
