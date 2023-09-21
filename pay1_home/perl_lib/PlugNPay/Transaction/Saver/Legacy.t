#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 48;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;
use PlugNPay::Transaction;
use PlugNPay::Contact;
use PlugNPay::Features;
use PlugNPay::Transaction::Response;

require_ok('PlugNPay::Transaction::Saver::Legacy');

# set up mocking for tests
my $mock = Test::MockObject->new();

# Mock PlugNPay::DBConnection
my $noQueries = sub {
  print STDERR new PlugNPay::Util::StackTrace()->string("\n") . "\n";
  die('unexpected query executed');
};
my $dbsMock = Test::MockModule->new('PlugNPay::DBConnection');
$dbsMock->redefine(
  'executeOrDie'  => $noQueries,
  'fetchallOrDie' => $noQueries
);

my $mckutilsData = {
  acct_code     => '123456789012345678901234567890',                                                                # 30
  acct_code2    => '123456789012345678901234567890',                                                                # 30
  acct_code3    => '123456789012345678901234567890',                                                                # 30
  acct_code4    => '123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890',    # 70
  card_name     => '123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890',
  enccardnumber => 'this should be turned into empty string'
};

my $queryData = {};
$dbsMock->redefine(
  executeOrDie => sub {
    my $self  = shift;
    my $query = $_[1];
    $query =~ s/\n|\r//g;
    $query =~ /.*?\((.*?)\).*/;
    my @fields = split( ',', $1 );
    my $values = $_[2];
    $queryData = {};
    my %qd = map { $_ => shift @{$values} } @fields;

    foreach my $key ( keys %qd ) {
      my $value = $qd{$key};
      $key =~ s/ //g;
      $queryData->{$key} = $value;
    }
  }
);

my $fMock = Test::MockModule->new('PlugNPay::Features');
my $fString;
$fMock->redefine(
  __loadContextFromFeatureString => sub {
    my $self = shift;
    $self->parseFeatureString($fString);
  }
);

# mock load so we don't get any db errors
my $gaMock = Test::MockModule->new('PlugNPay::GatewayAccount');
$gaMock->redefine(
  getFeatures => sub {
    my $self = shift;
    $fString =
      'pubemail=trash3@plugnpay.com,accountupdater=pnpdemo,admin_disabled_functions=none,admn_sec_req=ip,allow_pw_update=1,authcgiTransitionTemplate=,authhashkey=60|123456789abcdef|publisher-name|acct_code|card-amount,billpay_cardsallowed=Visa Mastercard Amex Discover,bindetails=1,bpltemplate=pnpdemo_template.txt,cobrand=,defaultValues={&quot;commcardtype&quot;: {&quot;defaultValue&quot;: &quot;purchase&quot;|&quot;replace&quot;: [&quot;null&quot;|&quot;empty&quot;]}|&quot;tax&quot;: {&quot;defaultValue&quot;:&quot;&quot;|&quot;replace&quot;: [&quot;null&quot;|&quot;empty&quot;|&quot;zero&quot;]|&quot;coefficient&quot;:&quot;0.1&quot;|&quot;variable&quot;:&quot;amount&quot;}|&quot;card-zip&quot;: {&quot;defaultValue&quot;: &quot;11111&quot;|&quot;replace&quot;: [&quot;null&quot;|&quot;empty&quot;]}},demoacct=1,hid_minimicr=1,leastCost=1,linked_accts=MASTER|pnpdemo|pnpdemo2,log_auth_tds=20140905,masterpass_enabled=1,paycgiTemplate={&quot;fileName&quot;:&quot;pnpdemo_paytemplate.txt&quot;|&quot;_md_&quot;:{}},postauthpending=no,response_format=JSON,rest_api_shrink_response=,rest_api_transaction_version=v1,routing_accts=pnpdemo2|iptest3,routing_balancemode=parallel,sec_certconf=1,sec_clientconf=1,sec_rempasswd=1,sec_verifyhash=1,slashpayStaticContent=forceFail,staticContentServer=sameHost,swipe_address=1,testproc1Return=realtime,testproc1Settle=0,transition=1,uploadbatch_forcelocal=1';
    my $f = new PlugNPay::Features( 'pnpdemo', 'general' );
    return $f;
  },
  load => sub {
    my $self = shift;
    $self->{'processorPackages'} = [
      { 'processor_name' => 'testprocessor',
        'payment_type'   => 'credit',
        'package_name'   => 'testprocessor'
      },
      { 'processor_name' => 'testprocessor',
        'payment_type'   => 'ach',
        'package_name'   => 'testprocessor'
      },
      { 'processor_name' => 'testprocessor',
        'payment_type'   => 'credit',
        'package_name'   => 'testprocessor'
      },
      { 'processor_name' => 'testprocessor',
        'payment_type'   => 'ach',
        'package_name'   => 'testprocessor'
      },
      { 'processor_name' => 'paay',
        'payment_type'   => 'credit',
        'package_name'   => undef
      },
      { 'processor_name' => 'paay',
        'payment_type'   => 'ach',
        'package_name'   => undef
      },
      { 'processor_name' => '',
        'payment_type'   => 'credit',
        'package_name'   => undef
      },
      { 'processor_name' => '',
        'payment_type'   => 'ach',
        'package_name'   => undef
      },
      { 'processor_name' => '',
        'payment_type'   => 'credit',
        'package_name'   => undef
      },
      { 'processor_name' => '',
        'payment_type'   => 'ach',
        'package_name'   => undef
      }
    ];
    $self->{'rawAccountData'} = {
      'emv_processor'   => '',
      'enccardnumber'   => '',
      'percent'         => '.05',
      'techtel'         => '',
      'startdate'       => '20210809',
      'cancelleddate'   => '20220425',
      'techname'        => ' ',
      'email'           => 'trash2@plugnpay.com',
      'password'        => 'pnpdemo',
      'tel'             => '631-761-0159',
      'trans_date'      => '19991005',
      'tds_config'      => '',
      'url'             => 'http://www.plugnpay.com',
      'processor'       => 'testprocessor',
      'name'            => 'PnP Demo',
      'reason'          => '',
      'description'     => 'I sold so much using PlugnPay that I am now retired.??',
      'username'        => 'pnpdemo',
      'switchtime'      => '',
      'chkaccttype'     => 'PPD',
      'bank'            => '',
      'pertran'         => '',
      'techemail'       => '',
      'monthly'         => '',
      'dcc'             => '',
      'merchant_bank'   => '',
      'salescommission' => '',
      'tdsprocessor'    => 'paay',
      'limits'   => 'max_auth_vol=100000000,max_retn_vol=250000000,ccretn_ovr=,ccauth_ovr=,ccretn_metric=30,ccauth_metric=30,retn_metric=30,retn_ovr=,auth_metric=9000,auth_ovr=,email=trash@plugnpay.com',
      'addr2'    => '',
      'setupfee' => '',
      'fraud_config'      => 'avs=2,blkipcntry=1,cvv_avs=,dupchk=0,dupchkresp=problem,dupchktime=5,eye4fraud=1,iovation=1,ipskip=1,precharge=off||||||||',
      'fax'               => '',
      'paymentmethod'     => 'Check',
      'country'           => 'US',
      'recurring'         => '',
      'ssnum'             => '564',
      'card_number'       => '',
      'cards_allowed'     => '',
      'pcttype'           => 'trans',
      'length'            => '71',
      'transcommission'   => '',
      'salesagent'        => '',
      'extrafees'         => '',
      'freetrans'         => '',
      'naics'             => '81411',
      'extracommission'   => '',
      'state'             => 'NY',
      'passphrase'        => '',
      'bypassipcheck'     => 'yes',
      'reseller'          => 'devresell',
      'softcart'          => '',
      'subacct'           => '',
      'overtran'          => '',
      'port'              => '',
      'billauthdate'      => 'Sun Oct 10 16:32',
      'zip'               => '11788',
      'nlevel'            => '',
      'walletprocessor'   => '',
      'digdownload'       => '',
      'status'            => 'live',
      'noreturns'         => '',
      'contact_date'      => '20101106',
      'agentcode'         => '',
      'merchemail'        => 'trash1@plugnpay.com',
      'city'              => 'Hauppauge',
      'parentacct'        => '',
      'addr1'             => '1363-26 Vets Highway',
      'company'           => 'PlugnPay Technologies Demo',
      'mservices'         => '',
      'lastbilled'        => '',
      'billauth'          => 'yes',
      'testmode'          => 'no',
      'features'          => '',
      'chkprocessor'      => 'testprocessor',
      'easycart'          => '',
      'monthlycommission' => '',
      'host'              => ''
    };
    $self->{'rawSetupsData'} = { 'trans_date' => '19991005' };
  }
);

my $currencyMock = Test::MockModule->new('PlugNPay::Currency');
$currencyMock->redefine(
  loadCurrencyIfNotLoaded => sub {
    $PlugNPay::Currency::threeLetterCache = new PlugNPay::Util::Cache::LRUCache(4);
    $PlugNPay::Currency::threeLetterCache->set(
      'USD',
      { threeLetter   => 'USD',
        numeric       => 840,
        precision     => '2',
        name          => 'Dollar',
        html_encoding => '&#36;'
      }
    );

    $PlugNPay::Currency::numericCache = new PlugNPay::Util::Cache::LRUCache(4);
    $PlugNPay::Currency::numericCache->set( 840, $PlugNPay::Currency::threeLetterCache->{'USD'} );
  }
);

my $ga = new PlugNPay::GatewayAccount('pnpdemo');    # load is mocked so this doesn't call the db (in theory)

my $transMock = Test::MockModule->new('PlugNPay::Transaction');
$transMock->redefine(
  getProcessor => sub { return 'cccc2'; },
  new          => sub { my $self = {}; my $class = shift; bless $self, $class; return $self; },
  getTransactionAmount => sub {
    return '1.00';
  },
  getBaseTransactionAmount => sub {
    return '1.00';
  },

  getBillingInformation => sub {
    my $contact = new PlugNPay::Contact();
    $contact->setFullName("Herman Munster 123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890");
    $contact->setAddress1("1313 Mockingbird Lane");
    $contact->setCity("Mockingbird Heights");
    $contact->setState("California");
    $contact->setPostalCode("91602");
    $contact->setCountry("US");
    return $contact;
  },

  getShippingInformation => sub {
    my $contact = new PlugNPay::Contact();
    $contact->setFullName("Jessica Fletcher 123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890");
    $contact->setAddress1("698 Candlewood Lane");
    $contact->setCity("Cabot Cove");
    $contact->setState("Maine");
    $contact->setPostalCode("04046");
    $contact->setCountry("US");
    return $contact;
  },
  getResponse => sub {
    return new PlugNPay::Transaction::Response();
  },
  getGatewayAccount => sub {
    return $ga;
  },
  getProcessorID => sub {
    return 151;
  },
  getPayment => sub {
    return new PlugNPay::CreditCard('4111111111111111');
  },
  getCurrency => sub {
    return 'usd';
  },
  getReceiptSendingEmailAddress => sub {
    return 'test@example.com';
  }
);

my $sl = new PlugNPay::Transaction::Saver::Legacy();

my $transaction = new PlugNPay::Transaction();
$transaction->setAccountCode( 1, '123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890' );    # 30
$transaction->setAccountCode( 2, '123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890' );    # 30
$transaction->setAccountCode( 3, '123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890' );    # 30
$transaction->setAccountCode( 4, '123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890' );    #70

my $billingContact  = $transaction->getBillingInformation();
my $shippingContact = $transaction->getShippingInformation();

#oplog
$sl->saveToOperationLog($transaction);                                                                                              #saction);
is( $queryData->{'amount'}, 'usd 1.00', 'saveToOperationLog(): currency and amount combined' );
is( $queryData->{'card_name'}, substr( $billingContact->getFullName(), 0, 40 ), 'saveToOperationLog(): card_name stored successfully' );
is( $queryData->{'card_addr'},            $billingContact->getAddress1(),                'saveToOperationLog(): card_addr1 stored successfully' );
is( $queryData->{'card_city'},            $billingContact->getCity(),                    'saveToOperationLog(): card_city stored successfully' );
is( $queryData->{'card_state'},           $billingContact->getState(),                   'saveToOperationLog(): card_state stored successfully' );
is( $queryData->{'card_zip'},             $billingContact->getPostalCode(),              'saveToOperationLog(): card_zip stored successfully' );
is( $queryData->{'publisheremail'},       $transaction->getReceiptSendingEmailAddress(), 'saveToOperationLog(): publisher_email stored successfully' );
is( length( $queryData->{'acct_code'} ),  26,                                            'saveToOperationLog(): accct_code gets truncated to 26 characters' );
is( length( $queryData->{'acct_code2'} ), 26,                                            'saveToOperationLog(): accct_code2 gets truncated to 26 characters' );
is( length( $queryData->{'acct_code3'} ), 50,                                            'saveToOperationLog(): accct_code3 gets truncated to 50 characters' );
is( length( $queryData->{'acct_code4'} ), 60,                                            'saveToOperationLog(): accct_code4 gets truncated to 60 characters' );

#translog
$sl->saveToTransactionLog($transaction);
is( $queryData->{'amount'}, 'usd 1.00', 'saveToTransactionLog(): currency and amount combined' );
is( $queryData->{'card_name'}, substr( $billingContact->getFullName(), 0, 40 ), 'saveToTransactionLog(): card_name stored successfully' );
is( $queryData->{'card_addr'},            $billingContact->getAddress1(),                'saveToTransactionLog(): card_addr1 stored successfully' );
is( $queryData->{'card_city'},            $billingContact->getCity(),                    'saveToTransactionLog(): card_city stored successfully' );
is( $queryData->{'card_state'},           $billingContact->getState(),                   'saveToTransactionLog(): card_state stored successfully' );
is( $queryData->{'card_zip'},             $billingContact->getPostalCode(),              'saveToTransactionLog(): card_zip stored successfully' );
is( $queryData->{'publisheremail'},       $transaction->getReceiptSendingEmailAddress(), 'saveToTransactionLog(): publisher_email stored successfully' );
is( length( $queryData->{'acct_code'} ),  26,                                            'saveToTransactionLog(): accct_code gets truncated to 26 characters' );
is( length( $queryData->{'acct_code2'} ), 26,                                            'saveToTransactionLog(): accct_code2 gets truncated to 26 characters' );
is( length( $queryData->{'acct_code3'} ), 50,                                            'saveToTransactionLog(): accct_code3 gets truncated to 50 characters' );
is( length( $queryData->{'acct_code4'} ), 60,                                            'saveToTransactionLog(): accct_code4 gets truncated to 60 characters' );

# order summary via transaction object
$sl->storeTransactionOrderSummary($transaction);
is( $queryData->{'amount'}, 'usd 1.00', 'storeTransactionOrderSummary(): currency and amount combined' );
is( $queryData->{'card_name'}, substr( $billingContact->getFullName(), 0, 40 ), 'storeTransactionOrderSummary(): card_name stored successfully' );
is( $queryData->{'card_addr'},  $billingContact->getAddress1(),   'storeTransactionOrderSummary(): card_addr1 stored successfully' );
is( $queryData->{'card_city'},  $billingContact->getCity(),       'storeTransactionOrderSummary(): card_city stored successfully' );
is( $queryData->{'card_state'}, $billingContact->getState(),      'storeTransactionOrderSummary(): card_state stored successfully' );
is( $queryData->{'card_zip'},   $billingContact->getPostalCode(), 'storeTransactionOrderSummary(): card_zip stored successfully' );
is( $queryData->{'shipname'}, substr( $shippingContact->getFullName(), 0, 40 ), 'storeTransactionOrderSummary(): shipname stored successfully' );
is( $queryData->{'shipaddr1'},            $shippingContact->getAddress1(),   'storeTransactionOrderSummary(): shipaddr1 stored successfully' );
is( $queryData->{'shipcity'},             $shippingContact->getCity(),       'storeTransactionOrderSummary(): shipcity stored successfully' );
is( $queryData->{'shipstate'},            $shippingContact->getState(),      'storeTransactionOrderSummary(): shipstate stored successfully' );
is( $queryData->{'shipzip'},              $shippingContact->getPostalCode(), 'storeTransactionOrderSummary(): shipzip stored successfully' );
is( length( $queryData->{'acct_code'} ),  26,                                'storeTransactionOrderSummary(): accct_code gets truncated to 26 characters' );
is( length( $queryData->{'acct_code2'} ), 26,                                'storeTransactionOrderSummary(): accct_code2 gets truncated to 26 characters' );
is( length( $queryData->{'acct_code3'} ), 26,                                'storeTransactionOrderSummary(): accct_code3 gets truncated to 26 characters' );
is( length( $queryData->{'acct_code4'} ), 60,                                'storeTransactionOrderSummary(): accct_code4 gets truncated to 60 characters' );
is( length( $queryData->{'card_name'} ),  40,                                'storeTransactionOrderSummary(): card_name gets truncated to 40 characters' );
is( $queryData->{'enccardnumber'},        '',                                'storeTransactionOrderSummary(): enccardnumber turned into empty string' );
is( $queryData->{'length'},               '',                                'storeTransactionOrderSummary(): length turned into empty string' );

#order summary via mckutils query
$sl->storeTransactionOrderSummaryMCKUtils($mckutilsData);
is( length( $queryData->{'acct_code'} ),  26, 'storeTransactionOrderSummaryMCKUtils(): accct_code gets truncated to 26 characters' );
is( length( $queryData->{'acct_code2'} ), 26, 'storeTransactionOrderSummaryMCKUtils(): accct_code2 gets truncated to 26 characters' );
is( length( $queryData->{'acct_code3'} ), 26, 'storeTransactionOrderSummaryMCKUtils(): accct_code3 gets truncated to 26 characters' );
is( length( $queryData->{'acct_code4'} ), 60, 'storeTransactionOrderSummaryMCKUtils(): accct_code4 gets truncated to 60 characters' );
is( length( $queryData->{'card_name'} ),  40, 'storeTransactionOrderSummaryMCKUtils(): card_name gets truncated to 40 characters' );
is( $queryData->{'enccardnumber'},        '', 'storeTransactionOrderSummaryMCKUtils(): enccardnumber turned into empty string' );
is( $queryData->{'length'},               '', 'storeTransactionOrderSummaryMCKUtils(): length turned into empty string' );
