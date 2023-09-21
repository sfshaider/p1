package PlugNPay::Transaction::Saver::Legacy;

use strict;
use PlugNPay::Die;
use PlugNPay::Sys::Time;
use PlugNPay::GatewayAccount;
use PlugNPay::Processor::Account;
use PlugNPay::CardData;
use PlugNPay::DBConnection;
use PlugNPay::Util::Array qw(inArray);
use PlugNPay::Transaction::State;
use PlugNPay::Transaction::Response;
use PlugNPay::Transaction::Formatter;
use PlugNPay::Transaction::MapLegacy;

our %_columnData;

sub new {
  my $class = shift;
  my $self  = {};
  bless $self, $class;
  return $self;
}

sub save {
  my $self                     = shift;
  my $transaction              = shift;
  my $response                 = shift;
  my $shouldBypassOrderSummary = shift;
  my @extraData                = @_;

  #formatting
  my $responseObj = new PlugNPay::Transaction::Response();
  $responseObj->setRawResponse($response);

  my $mapper      = new PlugNPay::Transaction::MapLegacy();
  if ( ref($transaction) !~ /^PlugNPay::Transaction/ ) {
    if (ref($transaction) eq 'HASH') {
      if (ref($response) eq 'HASH' && !$transaction->{'responseData'}) {
        $transaction->{'responseData'} = $response;
      }
      $transaction = $mapper->mapToObject($transaction);
    } else {
     die ('invalid transaction data sent for saving!');
    }
  }

  $transaction->setResponse($responseObj);

  my $dbs = new PlugNPay::DBConnection();
  $dbs->begin('pnpdata');
  eval {
    my $encCardNumber  = $transaction->getPayment()->getYearMonthEncryptedNumber();
    my $encLength      = length($encCardNumber);
    my $cardData       = new PlugNPay::CardData();
    my $cardDataStatus = $cardData->insertOrderCardData(
      { 'orderID'   => $transaction->getPNPOrderID(),
        'username'  => $transaction->getGatewayAccount(),
        'cardData'  => $encCardNumber,
        'transDate' => new PlugNPay::Sys::Time()->inFormatDetectType( 'yyyymmdd', $transaction->getTransactionDateTime() )
      }
    );

    # can't assume carddata is success
    if ( !$cardDataStatus ) {
      die('failed to insert card number into carddata service');
    }

    $self->saveToTransactionLog( $transaction, $encLength );
    if ( inArray( $transaction->getTransactionMode(), [ 'auth', 'authprev' ] ) ) {
      $self->saveToOperationLog( $transaction, $encLength );
      $self->storeTransactionOrderSummary( $transaction, $response ) unless $shouldBypassOrderSummary;
    } else {
      $self->updateOperationLog($transaction);
    }
  };

  if ($@) {
    $dbs->rollback('pnpdata');
    my $metaData = {
     'error'          => $@,
     'orderId'        => $transaction->getMerchantTransactionID(),
     'gatewayAccount' => $transaction->getGatewayAccount(),
     'processor'      => $transaction->getProcessor()
    };
    die_metadata(['An error occurred while saving transaction'], $metaData);
  } else {
    $dbs->commit('pnpdata');
  }

  return $mapper->map($transaction);
}

sub saveToTransactionLog {
  my $self           = shift;
  my $transaction    = shift;
  my $encLength      = shift;
  my $gatewayAccount = new PlugNPay::GatewayAccount( $transaction->getGatewayAccount() );
  my $settings       = new PlugNPay::Processor::Account( { 'gatewayAccount' => $transaction->getGatewayAccount(), 'processorName' => $transaction->getProcessor() } );
  my $time           = new PlugNPay::Sys::Time();
  my $transDate      = $time->inFormatDetectType( 'yyyymmdd',    $transaction->getTransactionDateTime() );
  my $transTime      = $time->inFormatDetectType( 'gendatetime', $transaction->getTransactionDateTime() );
  my $response       = $transaction->getResponse();
  my $bi             = $transaction->getBillingInformation();
  my $payment        = $transaction->getPayment();
  my $isCard         = ref( $transaction->getPayment() ) eq 'PlugNPay::CreditCard';
  my $extraData      = $transaction->getExtraTransactionData() || {};
  my $amount         = $transaction->getCurrency() . ' ' . $transaction->getTransactionAmount();
  my $accttype       = 'credit';
  if ($transaction->getTransactionPaymentType() eq 'ach') {
    $accttype = $transaction->getPayment()->getAccountType() || 'checking';
  }

  my %data = (
    username     => $transaction->getGatewayAccount(),                                                          #username
    merchant_id  => $settings->getSettingValue('mid'),                                                          #merchant_id
    orderid      => $transaction->getMerchantTransactionID(),                                                   #orderid
    card_name    => $bi->getName() || $payment->getName(),                                                      #card_name
    card_addr    => $bi->getAddress1(),                                                                         #card_addr
    card_city    => $bi->getCity(),                                                                             #card_city
    card_state   => $bi->getState(),                                                                            #card_state
    card_zip     => $bi->getPostalCode(),                                                                       #card_zip
    card_country => $bi->getCountry(),                                                                          #card_coutnry
    card_number  => $payment->getMaskedNumber(),                                                                #card_number
    card_exp     => ( $isCard ? $payment->getExpirationMonth() . '/' . $payment->getExpirationYear() : '' ),    #card_exp
    currency     => $transaction->getCurrency(),
    amount       => $amount,                                                                                    #amount
    trans_date   => $transDate,
    trans_time   => $transTime,
    trans_type  => $transaction->getTransactionMode(),                                                          #trans_type
    operation   => $transaction->getTransactionMode(),
    result      => $extraData->{'batchId'} || $response->getStatus(),                                           #result
    finalstatus => lc( $response->getStatus() ),                                                                #finalstatus
    descr       => $response->getMessage() || '',                                                          #descr
    acct_code   => $transaction->getAccountCode(1),                                            #acct_code
    acct_code2  => $transaction->getAccountCode(2),                                            #acct_code2
    acct_code3  => $transaction->getAccountCode(3),                                            #acct_code3
    acct_code4  => $transaction->getAccountCode(4),                                            #acct_code4
    auth_code => $response->getAuthorizationCode() || $transaction->getAuthorizationCode(),                     #auth_code
    avs           => $response->getAVSResponse(),                                                               #avs
    cvvresp       => $response->getSecurityCodeResponse(),                                                      #cvvresp
    shacardnumber => $payment->getCardHash(),                                                                   #shacardnumber
    length        => $encLength,                                                                                #length
    refnumber     => $transaction->getProcessorReferenceID(),                                                   #refnumber
    ipaddress     => $transaction->getIPAddress(),                                                              #ipaddress
    duplicate     => ( $response->getDuplicate() ? 'yes' : '' ),                                                #duplicate
    batch_time => $transTime,
    transflags => join( ',', $transaction->getTransFlags() ),                                                   #transflags
    publisheremail => $transaction->getReceiptSendingEmailAddress(),                                                #publisher-email
    refnumber      => $response->getReferenceNumber() || $transaction->getProcessorReferenceID(),
    accttype       => $accttype,
    processor      => $transaction->getProcessor(),
    subacct        => $gatewayAccount->getSubAccount()                                                          #subacct
  );


  my $columnData = $self->getTableColumnData('trans_log');
  my %columnLengths = map { lc($_) => $columnData->{$_}{'length'} } keys %{$columnData};

  my %insertData = map { $_ => substr( $data{$_}, 0, $columnLengths{$_} ) || '' } keys %data;
  $insertData{'enccardnumber'} = '';                                                                            # never store
  $insertData{'length'}        = '';                                                                            # not needed, related to length of unencrypted card number

  my $columns = join( ',', keys %insertData );
  my $placeholders = join( ',', map { '?' } keys %insertData );
  my @values = values %insertData;

  my $query = qq/INSERT INTO trans_log ($columns) VALUES ($placeholders)/;

  my $dbs = new PlugNPay::DBConnection();
  $dbs->executeOrDie( 'pnpdata', $query, \@values );

  return;
}

sub saveToOperationLog {
  my $self        = shift;
  my $transaction = shift;
  my $encLength   = shift;
  my $gaObject    = new PlugNPay::GatewayAccount( $transaction->getGatewayAccount() );
  my $settings    = new PlugNPay::Processor::Account( { 'gatewayAccount' => $transaction->getGatewayAccount(), 'processorName' => $transaction->getProcessor() } );
  my $time        = new PlugNPay::Sys::Time();
  my $response    = $transaction->getResponse();
  my $bi          = $transaction->getBillingInformation();
  my $payment     = $transaction->getPayment();
  my $isCard      = ref( $transaction->getPayment() ) eq 'PlugNPay::CreditCard';
  my $amount      = $transaction->getCurrency() . ' ' . $transaction->getTransactionAmount();
  my $accttype       = 'credit';
  if ($transaction->getTransactionPaymentType() eq 'ach') {
    $accttype = $transaction->getPayment()->getAccountType() || 'checking';
  }

  my %data = (
    username      => $transaction->getGatewayAccount() . "",                                                     #coerce to string                                                        #username
    trans_date    => $time->inFormatDetectType( 'yyyymmdd', $transaction->getTransactionDateTime() ),            #trans_date
    orderid       => $transaction->getMerchantTransactionID(),                                                   #orderid
    processor     => $transaction->getProcessor(),                                                               #processor
    lastop        => 'auth',                                                                                     #lastop
    lastopstatus  => lc( $response->getStatus() ),                                                               #lastopstatus
    lastoptime    => $time->inFormatDetectType( 'gendatetime', $transaction->getTransactionDateTime() ),         #lastoptime
    authstatus    => lc( $response->getStatus() ),                                                               #authstatus
    authtime      => $time->inFormatDetectType( 'gendatetime', $transaction->getTransactionDateTime() ),         #authtime
    amount        => $amount,                                                                                    #amount
    origamount    => $amount,                                                                                    #origamount
    descr         => $response->getMessage() || '',                                                         #descr
    shacardnumber => $payment->getCardHash(),                                                                    #shacardnum
    length        => $encLength,                                                                                 #length
    refnumber     => $transaction->getProcessorReferenceID(),                                                    #refnumber
    merchant_id   => $settings->getSettingValue('mid'),                                                          #merchant_id
    card_name     => $bi->getName() || $transaction->getPayment()->getName(),                                    #card-name
    card_addr     => $bi->getAddress1(),                                                                         #card-addr
    card_city     => $bi->getCity(),                                                                             #card-city
    card_state    => $bi->getState(),                                                                            #card-state
    card_zip      => $bi->getPostalCode(),                                                                       #card-zip
    card_country  => $bi->getCountry(),                                                                          #card-country
    card_number   => $payment->getMaskedNumber(),                                                                #card-number
    card_exp      => ( $isCard ? $payment->getExpirationMonth() . '/' . $payment->getExpirationYear() : '' ),    #card-exp
    auth_code => $response->getAuthorizationCode() || $transaction->getAuthorizationCode(),                      #auth-code
    avs            => $response->getAVSResponse(),                                                               #avs
    cvvresp        => $response->getSecurityCodeResponse(),                                                      #cvvresp
    ipaddress      => $transaction->getIPAddress(),                                                              #ipaddress
    currency       => $transaction->getCurrency(),                                                               #currency
    acct_code      => $transaction->getAccountCode(1),                                                           #acct_code1
    acct_code2     => $transaction->getAccountCode(2),                                                           #acct_code2
    acct_code3     => $transaction->getAccountCode(3),                                                           #acct_code3
    acct_code4     => $transaction->getAccountCode(4),                                                           #acct_code4
    transflags     => join( ',', $transaction->getTransFlags() ),                                                #transflags
    publisheremail => $transaction->getReceiptSendingEmailAddress(),                                                       #publisher-email
    subacct        => $gaObject->getSubAccount(),                                                                #subacct
    email          => $bi->getEmailAddress(),                                                                    #email
    refnumber      => $response->getReferenceNumber() || $transaction->getProcessorReferenceID(),
    accttype       => $accttype,
    cardtype       => ( $isCard ? $payment->getBrand( { 'legacy' => 1 } ) : '' )                                 #cardtype
  );

  my $columnData = $self->getTableColumnData('operation_log');
  my %columnLengths = map { lc($_) => $columnData->{$_}{'length'} } keys %{$columnData};

  my %insertData = map { $_ => substr( $data{$_}, 0, $columnLengths{$_} ) || '' } keys %data;
  $insertData{'enccardnumber'} = '';                                                                             # never store
  $insertData{'length'}        = '';                                                                             # not needed, related to length of unencrypted card number

  my $columns = join( ',', keys %insertData );
  my $placeholders = join( ',', map { '?' } keys %insertData );
  my @values = values %insertData;

  my $dbs = new PlugNPay::DBConnection();

  my $query = qq/INSERT INTO operation_log ($columns) VALUES ($placeholders)/;
  $dbs->executeOrDie( 'pnpdata', $query, \@values );
  return;
}

sub updateOperationLog {
  my $self             = shift;
  my $transaction      = shift;
  my $mode             = $transaction->getTransactionMode();
  my $responseStatus   = lc( $transaction->getResponse()->getStatus() );
  my $time             = new PlugNPay::Sys::Time()->inFormatDetectType( 'gendatetime', $transaction->getTransactionDateTime() );
  my $data             = [ $mode, $responseStatus, $time, $responseStatus, $time ];
  my @modeSpecificData = ( $mode . 'status = ?', $mode . 'time = ?' );
  if ( inArray( $mode, [ 'return', 'reauth', 'postauth' ] ) ) {
    my $updateAmount = $transaction->getCurrency() . ' ' . $transaction->getTransactionAmount();
    push @modeSpecificData, $mode . 'amount = ?';
    push @{$data}, $updateAmount;
    if ( $mode eq 'postauth' ) {
      push @modeSpecificData, 'batch_time = ?';
      push @{$data}, $time;
    }
  }

  my $query = q/
    UPDATE operation_log SET
      lastop = ?,
      lastopstatus = ?,
      lastoptime = ?,
  / . join( ', ', @modeSpecificData ) . q/
     WHERE orderid = ? AND username = ?
  /;
  push @{$data}, $transaction->getMerchantTransactionID();
  push @{$data}, $transaction->getGatewayAccount();

  my $dbs = new PlugNPay::DBConnection();
  $dbs->executeOrDie( 'pnpdata', $query, $data );

  return;
}

sub storeTransactionOrderSummary {
  my $self         = shift;
  my $t            = shift;    # transaction object, PlugNPay::Transaction
  my $responseData = shift;

  # Convert a transaction so that storeTransactionOrderSummaryMCKUtils can be called

  my $finalStatus = $responseData->{'FinalStatus'};
  my $message     = $responseData->{'MErrMsg'};
  my $avsResponse = $responseData->{'avs-code'};
  my $isDuplicate = $responseData->{'Duplicate'};

  my $dateTime = $t->getTransactionDateTime('db_gm');
  my ($date) = split( /\s+/, $dateTime );
  $date =~ s/[^\d]//g;
  $dateTime =~ s/[^\d]//g;

  my $bi = $t->getBillingInformation();
  my $s  = $t->getShippingInformation();
  my $p  = $t->getPayment();

  my $encryptedInfo = $p->getEncryptedInfo();

  my $data = {
    username     => $t->getGatewayAccount(),
    orderid      => $t->getPNPOrderID(),
    card_name    => $bi->getFullName(),
    card_company => $bi->getCompany(),
    card_addr    => $bi->getAddress1(),
    card_city    => $bi->getCity(),
    card_state   => $bi->getState(),
    card_zip     => $bi->getPostalCode(),
    card_country => $bi->getCountry(),
    amount       => $t->getCurrency() . ' ' . $t->getTransactionAmount(),
    tax          => $t->getTaxAmount(),
    shipping     => $t->getShippingAmount(),
    trans_date   => $date,
    trans_time   => $dateTime,
    result       => $finalStatus,
    descr        => $message,
    acct_code    => $t->getAccountCode(1),
    acct_code2   => $t->getAccountCode(2),
    acct_code3   => $t->getAccountCode(3),
    acct_code4   => $t->getAccountCode(4),
    morderid     => $t->getMerchantClassifierID(),

    # billing

    email => $bi->getEmailAddress(),
    phone => $bi->getPhone(),
    fax   => $bi->getFax(),

    # shipping
    shipname    => $s->getName(),
    shipcompany => $s->getCompany(),
    shipaddr1   => $s->getAddress1(),
    shipaddr2   => $s->getAddress2(),
    shipcity    => $s->getCity(),
    shipstate   => $s->getState(),
    shipzip     => $s->getPostalCode(),
    shipcountry => $s->getCountry(),
    shipphone   => $s->getPhone(),
    shipinfo    => "1",                   # this appears to never be loaded and used anywhere

    plan           => '',                 # unsupported with transaction/orders object currently, potentially added in future
    billcycle      => '',                 # unsupported with transaction/orders object currently, potentially added in future
    easycart       => '',                 # unsupported with transaction/orders object currently, no plans to add as there is no real need for it
    ipaddress      => $t->getIPAddress(),
    useragent      => '',                 # unsupported with transaction/orders object currently, no plans to add, logged
    referrer       => '',                 # unsupported with transaction/orders object currently, no plans to add, logged
    successlink    => '',                 # unsupported with transaction/orders object currently, no plans to add, logged
    publisheremail => '',                 # unsupported with transaction/orders object currently, no plans to add, logged

    card_number => $p->getMaskedNumber( 4, 4, '*', 2 ),

    # format expiration if card, otherwise blank
    card_exp => $t->getCreditCard() ? sprintf( "%02d/%02d", $p->getExpirationMonth(), $p->getExpirationYear() ) : '',
    enccardnumber => '',
    length        => '',

    avs       => $avsResponse,
    duplicate => $isDuplicate,
    cardextra => '',                      # after another branch gets merged that has checknum in the online check module

    subacct => '',                        # defunct
    customa => ''                         # unsupported with transaction/order objects currently
  };

  $self->storeTransactionOrderSummaryMCKUtils($data);
}

sub storeTransactionOrderDetails {

  # stubby
}

sub getTableColumnData {
  my $self  = shift;
  my $table = shift;
  my $dbs   = new PlugNPay::DBConnection();

  if ( !defined $_columnData{$table} ) {
    $_columnData{$table} = $dbs->getColumnsForTable(
      { database => 'pnpdata',
        table    => $table,
      }
    );
  }

  return $_columnData{$table};
}

sub storeTransactionOrderSummaryMCKUtils {
  my $self      = shift;
  my $fieldData = shift;

  my @insertFields = (
    'username',  'orderid',     'card_name',   'card_company',   'card_addr', 'card_city', 'card_state',    'card_zip',   'card_country', 'amount',
    'tax',       'shipping',    'trans_date',  'trans_time',     'result',    'descr',     'acct_code',     'acct_code2', 'acct_code3',   'acct_code4',
    'morderid',  'shipname',    'shipcompany', 'shipaddr1',      'shipaddr2', 'shipcity',  'shipstate',     'shipzip',    'shipcountry',  'phone',
    'shipphone', 'fax',         'email',       'plan',           'billcycle', 'easycart',  'ipaddress',     'useragent',  'referrer',     'card_number',
    'card_exp',  'successlink', 'shipinfo',    'publisheremail', 'avs',       'duplicate', 'enccardnumber', 'length',     'cardextra',    'subacct',
    'customa'
  );

  my $columnData = $self->getTableColumnData('ordersummary');
  my %columnLengths = map { lc($_) => $columnData->{$_}{'length'} } keys %{$columnData};

  my %insertData = map { $_ => substr( $fieldData->{$_}, 0, $columnLengths{$_} ) || '' } @insertFields;
  $insertData{'enccardnumber'} = '';    # never store
  $insertData{'length'}        = '';    # not needed, related to length of unencrypted card number

  my $query = 'INSERT INTO ordersummary (' . join( ',', keys %insertData ) . ') VALUES (' . join( ',', map { '?' } @insertFields ) . ')';
  my @data = values %insertData;

  my $dbs = new PlugNPay::DBConnection();
  $dbs->executeOrDie( 'pnpdata', $query, \@data );
}

sub storeTransactionOrderDetailsMCKUtils {

  # stubby
}

1;
