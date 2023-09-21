#!/bin/env perl

use strict;
# use warnings;

use Test::More tests => 127;
use Test::Exception;
use Test::MockModule;
use PlugNPay::Testing qw(skipIntegration);
use PlugNPay::Util::Array qw(inArray);

require_ok('PlugNPay::Transaction::Saver::Legacy::Mark');
require_ok('PlugNPay::Transaction::Loader');
require_ok('PlugNPay::CardData');
require_ok('PlugNPay::CreditCard');
require_ok('PlugNPay::Transaction::Legacy::AdditionalProcessorData');

my $bMock = Test::MockModule->new('PlugNPay::Transaction::Saver::Legacy::Mark');

my $username = 'pnpdemo';
my $orderId = '314159265358979';

test_amountFieldValueFromTransaction();

SKIP: {
  if (!skipIntegration('Integration testing not enabled',116)) {
    cleanup($username,$orderId);
    my $authAmount = '40.00';
    prepareTestData($username,$orderId,'auth',$authAmount);
    eval {
      TODO: {
        local $TODO = 'smpsutils.pm bug, search for "BUG 20220420-00001" in smpsutils.pm"';
        fail("batch-prep BUG 20220420-00001!");
        # unfortunate workaround for bug in testing, sleep a second before doing mark
        sleep 1;
      }
      runMarkTests($username,$orderId,'auth',$authAmount);
    };
    print $@ if $@;

    cleanup($username,$orderId);
    prepareTestData($username,$orderId,'reauth',$authAmount);
    eval {
      TODO: {
        local $TODO = 'smpsutils.pm bug, search for "BUG 20220420-00001" in smpsutils.pm"';
        fail("batch-prep BUG 20220420-00001!");
        # unfortunate workaround for bug, sleep a second before doing mark
        sleep 1;
      }
      runMarkTests($username,$orderId,'reauth',$authAmount);
    };
    print $@ if $@;
  }
}

sub test_amountFieldValueFromTransaction {
  my $transaction = new PlugNPay::Transaction('auth','credit');
  $transaction->setGatewayAccount('pnpdemo');
  $transaction->setCurrency('usd');
  $transaction->setTransactionAmount('1.50');

  my $value = PlugNPay::Transaction::Saver::Legacy::Mark::_amountFieldValueFromTransaction($transaction);
  is($value,'usd 1.50','_amoutnFieldValueFromTransaction generates the correct value format for amounts > 0');
  
  $transaction->setTransactionAmount('0');
  $value = PlugNPay::Transaction::Saver::Legacy::Mark::_amountFieldValueFromTransaction($transaction);
  is($value,'usd 0.00','_amoutnFieldValueFromTransaction generates the correct value format for amount of 0');
}

sub runMarkTests {
  my $username = shift;
  my $orderId = shift;
  my $operation = shift;
  my $authAmount = shift;

  my $prefix = sub {
    my $message = shift;
    return "$operation: $message";
  };

  my $transactionInputMap = loadTransaction($username,$orderId);

  my $transaction = $transactionInputMap->{$orderId};
  if (!defined $transaction) {
    fail($prefix->('transaction can not be loaded to mark'));
    return;
  } else {
    pass($prefix->('transaction loaded to mark'));
  }

  my $settlementAmount = '30.00';
  my $accountCode4 = 'newvalue';
  my $gratuity = '10.00';
  $transaction->setSettlementAmount($settlementAmount);
  $transaction->setAccountCode(4,$accountCode4);
  $transaction->setGratuityAmount($gratuity);

  # call mark
  my $marker = new PlugNPay::Transaction::Saver::Legacy::Mark();
  $marker->mark({
    gatewayAccount => $username,
    transactions => $transactionInputMap
  });

  # load again and verify
  my $transactionAfterMarkMap = loadTransaction($username,$orderId);
  $transaction = $transactionAfterMarkMap->{$orderId};
  if (!defined $transaction) {
    fail($prefix->('transaction could not be loaded after postauth'));
    return;
  } else {
    pass($prefix->('transaction loaded after postauth'));
  }

  my $transactionState = $transaction->getTransactionState();
  is($transactionState,'POSTAUTH_READY',$prefix->('transaction was marked for postauth'));

  # as of writing, this is loaded from operation_log.batch_time by PlugNPay::Transaction::Loader
  my $transactionMarkTime = $transaction->getTransactionMarkTime();
  isnt($transactionMarkTime,'',$prefix->('transaction mark time is set'));

  # read operation log row and do some tests
  my $operationLogData = fetchOperationLogRow($username,$orderId);
  is($operationLogData->{'lastop'},'postauth',$prefix->('operation_log.lastop is postauth'));
  like($operationLogData->{'lastoptime'},qr/^\d{14}$/,$prefix->('operation_log.lastoptime is 14 digits (YYYYMMDDHHMMSS)'));
  is($operationLogData->{'lastopstatus'},'pending',$prefix->('operation_log.lastopstatus is pending'));

  my $amountValue = $operationLogData->{'amount'};
  $amountValue =~ s/[^\d\.]//g;

  my $origAmountValue = $operationLogData->{'origamount'};
  $origAmountValue =~ s/[^\d\.]//g;
  
  is($amountValue,$settlementAmount,$prefix->('operation_log.amount is correct'));
  is($origAmountValue,$authAmount,$prefix->('operation_log.origamount is correct'));
  is($operationLogData->{'postauthstatus'},'pending',$prefix->('operation_log.postauthstatus is pending'));
  isnt($operationLogData->{'postauthtime'},'',$prefix->('operation_log.postauthtime is not empty string'));
  isnt($operationLogData->{'acct_code4'},$accountCode4,$prefix->('operation_log.acct_code4 does not updated value'));
  isnt($operationLogData->{'batch_time'},'',$prefix->('operation_log.lastopstatus is not empty string'));

  # read trans_log row and do some tests
  my $transLogData = fetchTransLogRows($username,$orderId);
  my $authRow = $transLogData->{'auth'};
  my $postauthRow = $transLogData->{'postauth'};
  my $doNotCompare = [
    'acct_code4','auth_code','batch_time',
    'result','amount','finalstatus','trans_time',
    'descr','operation','trans_type','trans_date',
  ];

  # check values that should be equivilent between auth and postauth rows
  my $count = keys %{$authRow};
  is($count,42,'number of keys to check in trans_log is 42');
  foreach my $key (sort keys %{$authRow}) {
    next if inArray($key,$doNotCompare);
    is($authRow->{$key},$postauthRow->{$key},$prefix->("trans_log.$key matches between auth row and postauth row"));
  }

  # test acct_code4
  is($postauthRow->{'acct_code4'},$accountCode4,$prefix->('trans_log.acct_code4 has the correct value in postauth row'));
  
  # test amount currency
  my $authRowCurrency = $authRow->{'amount'};
  $authRowCurrency =~ s/[\s\d\.]//g;
  like($postauthRow->{'amount'},qr/^$authRowCurrency/,$prefix->('trans_log.amount starts with the same currency as auth row'));

  # test amount quantity
  my $postauthRowAmount = $postauthRow->{'amount'};
  $postauthRowAmount =~ s/[^\d\.]//g;
  is($postauthRowAmount,$settlementAmount,$prefix->('trans_log.amount has the correct amount in postauth row'));

  # test gratuity
  my $processorId = $transaction->getProcessorID();
  my $padm = new PlugNPay::Transaction::Legacy::AdditionalProcessorData({ processorId => $processorId });
  $padm->setAdditionalDataString($postauthRow->{'auth_code'});
  ok($padm->hasField('gratuity'),$prefix->('testing with gratuity enabled for testprocessor'));
  if ($padm->hasField('gratuity')) {
    my $gratuityValue = $padm->getField('gratuity');
    is($gratuityValue,$gratuity,$prefix->('trans_log.auth_code gratuity has the correct value'));
  }

  # test trans_date
  like($postauthRow->{'trans_date'},qr/^\d{8}$/,$prefix->('trans_log.trans_time is 8 digits (YYYYMMDD)'));

  # test trans_time
  ok($postauthRow->{'trans_time'} > $authRow->{'trans_time'},$prefix->('trans_log.trans_time for postauth is after trans_log.trans_time for auth, see BUG 20220420-00001'));
  like($postauthRow->{'trans_time'},qr/^\d{14}$/,$prefix->('trans_log.trans_time is 14 digits (YYYYMMDDHHMMSS)'));

  # test batch_time
  like($postauthRow->{'batch_time'},qr/^\d{14}$/,$prefix->('trans_log.batch_time is 14 digits (YYYYMMDDHHMMSS)'));

  # test descr
  is($postauthRow->{'descr'},'',$prefix->('trans_log.descr is blank for postauth row'));

  # test finalstatus
  is($postauthRow->{'finalstatus'},'pending',$prefix->('trans_log.finalstatus is "pending" or postauth row'));
  
  # test result
  is($postauthRow->{'result'},'pending',$prefix->('trans_log.result is "pending" or postauth row'));

  # test operation
  is($postauthRow->{'operation'},'postauth',$prefix->('trans_log.operation is "postauth" for postauth row'));

  # test trans_type
  is($postauthRow->{'trans_type'},'postauth',$prefix->('trans_log.trans_type is "postauth" for postauth row'));
}

sub loadTransaction {
  my $username = shift;
  my $orderId = shift;

  my $loader = new PlugNPay::Transaction::Loader({ loadPaymentData => 1 });
  my $loaded = $loader->load({
    gatewayAccount => $username,
    orderID => $orderId
  });
  my $transactionArray = $loaded->{$username};
  return $transactionArray;
}

sub prepareTestData {
  my $username = shift;
  my $orderId = shift;
  my $operation = shift;
  my $amount = shift;

  my $cc = new PlugNPay::CreditCard();
  $cc->setNumber('4111111111111111');
  my $masked = $cc->getMaskedNumber(6,4,'*',2);
  my $sha = $cc->getCardHash();
  my $encInfo = $cc->getEncryptedInfo();
  my $enc = $encInfo->{'enccardnumber'};

  my $data = {
    username => $username,
    orderId => $orderId,
    operation => $operation,
    amount => $amount,
    masked => $masked,
    sha => $sha
  };

  my %authData = %{$data};
  $authData{'operation'} = 'auth';

  my %reauthData = %{$data};
  $reauthData{'amount'} = $reauthData{'amount'} - 5.00;

  prepareCardData($username,$orderId,$enc);

  prepareTestOperationLogData(\%authData);
  if ($operation eq 'reauth') {
    updateOperationLogForReauth(\%reauthData);
  }

  prepareTestTransLogData(\%authData);
  if ($operation eq 'reauth') {
    prepareTestTransLogData(\%reauthData);
  }
}

sub cleanup {
  my $username = shift;
  my $orderId = shift;

  removeTestOperationLogData($username,$orderId);
  removeTestTransLogData($username,$orderId);
}

sub prepareCardData {
  my $username = shift;
  my $orderId = shift;
  my $cardData = shift;

  my $cd = new PlugNPay::CardData();
  $cd->insertOrderCardData({
    username => $username,
    orderID => $orderId,
    cardData => $cardData
  });
}

sub prepareTestOperationLogData {
  my $input = shift;
  my $username = $input->{'username'};
  my $orderId = $input->{'orderId'};
  my $operation = $input->{'operation'};
  my $amount = $input->{'amount'};
  my $masked = $input->{'masked'};
  my $sha = $input->{'sha'};

  my $amountField = "usd $amount";
  my $dbs = new PlugNPay::DBConnection();

  my %fieldValues = (
    processor => 'testprocessor',
    username => $username,
    orderid => $orderId,
    trans_date => '20220331',
    card_country => 'US',
    length => '',
    subacct => '',
    voidtime => '',
    postauthtime => '20220401013815',
    reauthamount => '',
    batchinfo => '',
    card_city => 'Metropolis',
    acct_code  => 'acctcode1',
    acct_code2 => 'acctcode2',
    acct_code3 => 'acctcode3',
    acct_code4 => 'acctcode4',
    ipaddress => '1.2.3.4',
    origamount => $amountField,
    currency => 'usd',
    email => 'usr@example.com',
    lastopstatus => 'success',
    postauthstatus => '',
    card_exp => '03/23',
    batch_time => '',
    lastop => 'auth',
    card_addr => '123 Lois Lane',
    cardtype => '',
    merchant_id => '',
    cvvresp => 'M',
    accttype => 'credit',
    card_zip => '11111',
    refnumber => '',
    batchnum => '',
    publisheremail => '',
    storedatatime => '',
    returnstatus => '',
    avs => 'M',
    batchfile => '',
    descr => 'APPROVED (DO NOT VALIDATE THIS FIELD)',
    transflags => '',
    voidstatus => '',
    auth_code => '123456gratuity##',
    detailnum => '',
    shacardnumber => $sha,
    postauthamount => '',
    storedatastatus => '',
    authtime => '20220331182241',
    reauthtime => '',
    enccardnumber => '',
    returnamount => '',
    amount => $amountField,
    card_number => $masked,
    card_name => 'Tester McTesterface',
    authstatus => 'success',
    processor => 'testprocessor',
    card_state => 'NY',
    lastoptime => '20220331182241',
    batchstatus => '',
    returntime => '',
    cardextra => '',
    reauthstatus => '',
    forceauthstatus => '',
    forceauthtime => ''
  );

  my $fields = join( ',', map { '`' . $_ . '`' } keys %fieldValues );
  my $params = join( ',', map { '?' } keys %fieldValues );
  my @values = values %fieldValues;

  my $query = "INSERT INTO operation_log ($fields) VALUES ($params)";

  my $dbs = new PlugNPay::DBConnection();
  $dbs->executeOrDie('pnpdata',$query, \@values);
}

sub updateOperationLogForReauth {
  my $input = shift;
  my $username = $input->{'username'};
  my $orderId = $input->{'orderId'};
  my $amount = $input->{'amount'};

  my $amountField = "usd $amount";

  my $dbs = new PlugNPay::DBConnection();

  my $query = q/
    UPDATE operation_log
    SET lastop = ?,
        lastopstatus = ?,
        amount = ?,
        reauthamount = ?
    WHERE username = ? AND orderid = ?
  /;

  $dbs->executeOrDie('pnpdata',$query,['reauth','success',$amountField,$amountField,$username,$orderId]);
}

sub fetchOperationLogRow {
  my $username = shift;
  my $orderId = shift;

  my $dbs = new PlugNPay::DBConnection();

  my $result = $dbs->fetchallOrDie('pnpdata',q/
    SELECT * FROM operation_log WHERE username = ? AND orderid = ?
  /,[$username,$orderId],{});
  my $row = $result->{'rows'}[0];

  my %lowercased = map { lc($_) => $row->{$_} } keys %{$row};

  return \%lowercased;
}

sub removeTestOperationLogData {
  my $username = shift;
  my $orderId = shift;

  my $query = "DELETE FROM operation_log WHERE username = ? AND orderid = ?";
  my $values = [$username,$orderId];

  my $dbs = new PlugNPay::DBConnection();
  $dbs->executeOrDie('pnpdata',$query, $values);
}

sub prepareTestTransLogData {
  my $input = shift;
  my $username = $input->{'username'};
  my $orderId = $input->{'orderId'};
  my $operation = $input->{'operation'};
  my $amount = $input->{'amount'};
  my $masked = $input->{'masked'};
  my $sha = $input->{'sha'};

  my $amountField = "usd $amount";

  my %fieldValues = (
    processor     => 'testprocessor',
    username      => $username,
    orderid       => $orderId,
    merchant_id   => '1234',
    card_name     => 'Tester McTesterface',
    card_addr     => '123 Lois Lane',
    card_city     => 'Metropolis',
    card_state    => 'New York',
    card_zip      => '11111',
    card_country  => 'US',
    card_number   => $masked,
    card_exp      => '12/50',
    amount        => $amountField,
    trans_date    => '20220401',
    trans_time    => '20220401123456',
    trans_type    => $operation,
    operation     => $operation,
    accttype      => 'credit',
    result        => '',
    finalstatus   => 'success',
    descr         => 'APPROVED (DO NOT VALIDATE THIS FIELD)',
    acct_code     => 'acctcode1',
    acct_code2    => 'acctcode2',
    acct_code3    => 'acctcode3',
    acct_code4    => 'acctcode4',
    auth_code     => '123456gratuity##',
    avs           => 'M',
    cvvresp       => 'M',
    shacardnumber => $sha,
    length        => '',
    refnumber     => '',
    transflags    => '',
    ipaddress     => '1.2.3.4',
    duplicate     => '',
    batch_time    => ''
  );

  my $fields = join( ',', map { '`' . $_ . '`' } keys %fieldValues );
  my $params = join( ',', map { '?' } keys %fieldValues );
  my @values = values %fieldValues;

  my $query = "INSERT INTO trans_log ($fields) VALUES ($params)";

  my $dbs = new PlugNPay::DBConnection();
  $dbs->executeOrDie('pnpdata',$query, \@values);
}

sub fetchTransLogRows {
  my $username = shift;
  my $orderId = shift;

  my $dbs = new PlugNPay::DBConnection();

  # selecting auth and postauth rows, ordering by operation asc puts auth as the first row, postauth as the second
  my $result = $dbs->fetchallOrDie('pnpdata',q/
    SELECT * FROM trans_log WHERE username = ? AND orderid = ? AND operation IN (?,?) ORDER BY operation ASC
  /,[$username,$orderId,'auth','postauth'],{});
  my $authRow = $result->{'rows'}[0];
  my $postauthRow = $result->{'rows'}[1];

  # lowercase the keys BECAUSE THERE IS NO NEED TO SHOUT
  my %lowercasedAuthRow = map { lc($_) => $authRow->{$_} } keys %{$authRow};
  my %lowercasedPostauthRow = map { lc($_) => $postauthRow->{$_} } keys %{$postauthRow};

  return {
    auth => \%lowercasedAuthRow,
    postauth => \%lowercasedPostauthRow
  };
}


sub removeTestTransLogPostauthRow {
  my $username = shift;
  my $orderId = shift;

  my $query = "DELETE FROM trans_log WHERE username = ? AND orderid = ? AND operation = ?";
  my $values = [$username,$orderId,'postauth'];

  my $dbs = new PlugNPay::DBConnection();
  $dbs->executeOrDie('pnpdata',$query, $values);
}


sub removeTestTransLogData {
  my $username = shift;
  my $orderId = shift;

  my $query = "DELETE FROM trans_log WHERE username = ? AND orderid = ?";
  my $values = [$username,$orderId];

  my $dbs = new PlugNPay::DBConnection();
  $dbs->executeOrDie('pnpdata',$query, $values);
}
