

#!/usr/bin/perl

use strict;
use lib $ENV{"PNP_PERL_LIB"};
use Data::Dumper;
use miscutils;
use PlugNPay::Sys::Time;
use PlugNPay::Transaction::TransactionProcessor;
use PlugNPay::Util::UniqueID;
use JSON::XS;
use Time::HiRes;
use MIME::Base64;
my $user = $ARGV[0];
&this($user);

sub this {
my $username = shift;

my $fd = {'custom_name1','the custom name','custom_value1','the custom value'};

my $time = new PlugNPay::Sys::Time();
  my $orderID = new PlugNPay::Transaction::TransactionProcessor()->generateOrderID();
  my $details = {};
  my %m = &miscutils::sendmserver($username,'auth','paymethod','credit','amount','usd 1.00','card-number','4200000000000000','card-exp','09/18','card-cvv','415','card-name','Vince Viza','card-zip','30329','card-address','4 Corporate Sq','card-state','GA','card-country','US','card-city','Atlanta','email','dylan@plugnpay.com','phone','555-555-5555','orderID', $orderID, 'order-id', $orderID,'tax','5.00','base_tax','2.00','__full_transaction_data__',$fd);
print "Auth1\n";
print Dumper(\%m);
return;
$details = $m{'additional_processor_details'};
$details->{'processor_reference_id'} = $m{'processor_reference_id'};
%m = &miscutils::sendmserver($username,'void','paymethod','credit','amount','usd 1.00','card-number','4200000000000000','card-exp','09/18','card-cvv','415','card-name','Vince Viza','card-zip','30329','card-address','4 Corporate Sq','card-state','GA','card-country','US','card-city','Atlanta','email','dylan@plugnpay.com','phone','555-555-5555','processorDataDetails',{'1' => $details},'authorzation_code',$m{'authorization_code'},'processor_token',$m{'processor_token'},'pnp_transaction_id',$m{'pnp_transaction_id'});

print "Void\n";
print Dumper(\%m);


  %m = &miscutils::sendmserver($username,'auth','paymethod','credit','amount','usd 1.00','card-number','4200000000000000','card-exp','09/18','card-cvv','415','card-name','Vince Viza','card-zip','30329','card-address','4 Corporate Sq','card-state','GA','card-country','US','card-city','Atlanta','email','dylan@plugnpay.com','phone','555-555-5555','orderID', $orderID, 'order-id', $orderID,'tax','5.00','base_tax','2.00');
print "Auht2\n";
print Dumper(\%m);
$details = $m{'additional_processor_details'};
$details->{'processor_reference_id'} = $m{'processor_reference_id'};
%m = &miscutils::sendmserver($username,'postauth','paymethod','credit','amount','usd 1.00','card-number','4200000000000000','card-exp','09/18','card-cvv','415','card-name','Vince Viza','card-zip','30329','card-address','4 Corporate Sq','card-state','GA','card-country','US','card-city','Atlanta','email','dylan@plugnpay.com','phone','555-555-5555','processorDataDetails',{'1' => $details},'authorzation_code',$m{'authorization_code'},'processor_token',$m{'processor_token'},'pnp_transaction_id',$m{'pnp_transaction_id'});
print "PA\n";
print Dumper(\%m);


use PlugNPay::Processor::Process::Settlement;

my $settlement = new PlugNPay::Processor::Process::Settlement();
my $time = new PlugNPay::Sys::Time();

my $resp = $settlement->settle($time->inFormat('db_gm'));
my $h = $resp->{'newly_settled_transactions'};
print Dumper($h);

my @keys = keys %{$h};
my @keys2 = keys %{$h->{$keys[0]}};
print $keys[0] . "\n\n" . $keys2[0] . "\n\n";
my $hash = $h->{$keys[0]}{$keys2[0]};
print Dumper($hash);

my %m = %{$hash};

$details = $m{'additional_processor_details'};
$details->{'processor_reference_id'} = $m{'processor_reference_id'};
  my %q = &miscutils::sendmserver($username,'credit','paymethod','credit','amount','usd 1.00','card-number','4200000000000000','card-exp','09/18','card-cvv','415','card-name','Vince Viza','card-zip','30329','card-address','4 Corporate Sq','card-state','GA','card-country','US','card-city','Atlanta','email','dylan@plugnpay.com','phone','555-555-5555','processorDataDetails',{'2' => $details},'authorzation_code',$m{'authorization_code'},'processor_token',$m{'processor_token'},'pnp_transaction_id',$m{'pnp_transaction_id'});

print "Return\n";
print Dumper (\%q);
}
