package PlugNPay::Transaction::Loader;

use strict;
use PlugNPay::Token;
use PlugNPay::Contact;
use PlugNPay::Currency;
use PlugNPay::Sys::Time;
use PlugNPay::CreditCard;
use PlugNPay::OnlineCheck;
use PlugNPay::Transaction;
use PlugNPay::DBConnection;
use PlugNPay::Util::HashMap;
use PlugNPay::Processor::ID;
use PlugNPay::Util::UniqueID;
use PlugNPay::Util::IP::Address;
use PlugNPay::Transaction::Type;
use PlugNPay::Transaction::Flags;
use PlugNPay::Transaction::State;
use PlugNPay::Transaction::Vehicle;
use PlugNPay::Transaction::Response;
use PlugNPay::Transaction::Formatter;
use PlugNPay::GatewayAccount::InternalID;
use PlugNPay::Transaction::AccountType;
use PlugNPay::Transaction::DetailKey;
use PlugNPay::Database::QueryBuilder;
use PlugNPay::Logging::Performance;
use PlugNPay::Transaction::Logging::Adjustment;
use PlugNPay::Transaction::Loader::History;
use PlugNPay::Transaction::State;
use PlugNPay::Logging::DataLog;
use PlugNPay::CardData;
use PlugNPay::Processor;
use PlugNPay::Die;
use PlugNPay::Legacy::Transflags;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $options = shift;

  $self->setLoadDetailedData(1); # default of on

  if (ref($options) eq 'HASH') {
    $self->setLoadPaymentData($options->{'loadPaymentData'}) if exists $options->{'loadPaymentData'};
    $self->setReturnAsHash($options->{'returnAsHash'}) if exists $options->{'returnAsHash'};
    $self->setLoadDetailedData($options->{'loadDetailedData'}) if exists $options->{'loadDetailedData'};
  }

  return $self;
}

sub setLoadPaymentData {
  my $self = shift;
  my $loadPaymentData = shift;
  $self->{'loadPaymentData'} = $loadPaymentData;
}

sub getLoadPaymentData {
  my $self = shift;
  return $self->{'loadPaymentData'};
}

sub setLoadDetailedData {
  my $self = shift;
  my $loadSummaryData = shift;
  $self->{'loadSummaryData'} = $loadSummaryData;
}

sub getLoadDetailedData {
  my $self = shift;
  return $self->{'loadSummaryData'};
}

sub getPNPOrderID {
  my $self = shift;
  my $transactionId = shift;
  my $orderId = '';

  my @loadTypes;

  my $dbs = new PlugNPay::DBConnection();

  # if the transaction contains A-F, then it is a unified transaction id
  if ($transactionId =~ /[A-F]/ || length($transactionId) > 23) {
    my $res = $dbs->fetchallOrDie('pnpmisc',q/
      SELECT pnp_order_id FROM transaction WHERE pnp_transaction_id = ? LIMIT 1
    /,[$transactionId],{});
    if ($res->{'result'}) {
      $orderId = $res->{'result'}[0]{'pnp_order_id'};
    }
  } else { # for legacy, the order id is equivilent to the transaction id
    return $transactionId;
  }
}

sub setReturnAsHash {
  my $self = shift;
  my $returnAsHash = shift;
  $self->{'returnAsHash'} = $returnAsHash;
}

sub getReturnAsHash {
  my $self = shift;
  return $self->{'returnAsHash'};
}

# example: data = { gatewayAccount => 'something', transactionID => 'order id or pnp_transaction_id' }
sub load {
  my $self = shift;
  my $data = shift || [];
  my $loader = $self;
  if (ref($loader) ne 'PlugNPay::Transaction::Loader') {
    $data = $self;
    $loader = new PlugNPay::Transaction::Loader();
  }

  # start time for calculating request duration
  my $metrics = new PlugNPay::Metrics();
  my $start = $metrics->timingStart();

  my $loadedData = $loader->routeLoad($data);

  $metrics->timingEnd({
    metric => 'transaction.loader.load_duration',
    start => $start
  });

  return $loadedData;
}

sub routeLoad {
  my $self = shift;
  my $data = shift;
  if (ref($data) eq 'HASH') {
    $data = [$data];
  }

  my @unifiedData;
  my @legacyData;

  my $uniqueIDChecker = new PlugNPay::Util::UniqueID();
  foreach my $datum (@{$data}) {
    my $optionCount = keys %{$datum};
    if ($optionCount == 1 && defined $datum->{'gatewayAccount'}) {
      my $startDate = new PlugNPay::Sys::Time();
      $startDate->subtractDays(1);
      $datum->{'start_date'} = $startDate->inFormat('yyyymmdd');
    }

    # infer unified from the orderID if version is not sent.
    # if that is not sent, try to infer from transactionID.
    # assumes hex formatted orderID or transactionID
    if (!defined $datum->{'version'}) {
      $uniqueIDChecker->fromHex($datum->{'orderID'});
      if ($uniqueIDChecker->validate() && $datum->{'orderID'}) {
        $datum->{'version'} = 'unified';
      }
    }

    if (!defined $datum->{'version'}) {
      $uniqueIDChecker->fromHex($datum->{'transactionID'});
      if ($uniqueIDChecker->validate() && $datum->{'transactionID'}) {
        $datum->{'version'} = 'unified';
      }
    }

    # if the order id was hex then we only have to check unified
    push @unifiedData,$datum;
    if ($datum->{'version'} ne 'unified') {
      push @legacyData,$datum;
    }
  }

  my $new = $self->unifiedLoad(\@unifiedData);
  my $legacy = $self->legacyLoad(\@legacyData);

  if (!$self->getReturnAsHash()) {
    $new = $self->makeTransactionObj($new);
    $legacy = $self->makeTransactionObj($legacy);
  }

  my $util = new PlugNPay::Util::HashMap();
  my $returnData = $util->hashMerge($new,$legacy);
  return $returnData;
}

######################
# Old Transaction DB #
######################
sub legacyLoad {
  my $self = shift;
  my $transactionsToLoad = shift;
  my $stateObj = new PlugNPay::Transaction::State();

  if (ref($transactionsToLoad) eq 'HASH') {
    $transactionsToLoad = [$transactionsToLoad];
  }
  my $dbs = new PlugNPay::DBConnection();
  new PlugNPay::Logging::Performance('Legacy Load begin');

  my $query = q/
    SELECT o.orderid AS merchant_order_id,
           o.orderid AS pnp_order_id,
           o.orderid AS pnp_transaction_id,
           o.username AS merchant,
           o.amount AS transaction_amount,
           o.lastop AS transaction_type,
           o.accttype AS accttype,
           o.processor AS processor,
           COALESCE(NULLIF('',o.merchant_id),t.merchant_id) AS processor_merchant_id,
           t.card_name AS full_name,
           t.card_addr AS address,
           t.card_city AS city,
           t.card_state AS state,
           t.card_country AS country,
           t.card_zip AS postal_code,
           t.card_exp AS expiration_date,
           t.card_number AS masked_card_number,
           t.enccardnumber AS encrypted_card_number,
           t.auth_code AS authorization_code,
           t.trans_time AS transaction_date_time,
           o.authtime AS processor_transaction_date_time,
           o.email AS email,
           COALESCE(t.refnumber,o.refnumber) AS reference_number,
           t.ipaddress AS ip_address,
           o.batch_time AS settlement_mark_time,
           o.postauthstatus,
           o.postauthtime AS processor_settlement_date,
           o.postauthamount AS settlement_amount,
           o.batchnum,
           o.batch_time,
           o.authstatus,
           o.authtime,
           o.origamount AS 'authamount',
           o.voidstatus,
           o.voidtime,
           o.lastopstatus,
           o.returnstatus,
           COALESCE(t.descr,o.descr) AS 'message',
           o.returntime,
           o.returnamount,
           o.reauthtime,
           o.reauthstatus,
           o.reauthamount,
           o.publisheremail,
           o.acct_code AS account_code1,
           o.acct_code2 AS account_code2,
           o.acct_code3 AS account_code3,
           o.acct_code4 AS account_code4,
           t.transflags,
           o.cvvresp AS cvv_response,
           o.avs AS avs_response,
           t.finalstatus AS status,
           t.result AS result,
           COALESCE(os.phone,'') AS phone,
           COALESCE(os.fax,'') AS fax,
           COALESCE(os.shipname,'') AS shipname,
           COALESCE(os.shipaddr1,'') AS shipaddr1,
           COALESCE(os.shipaddr2,'') AS shipaddr2,
           COALESCE(os.shipcountry,'') AS shipcountry,
           COALESCE(os.shipcity,'') AS shipcity,
           COALESCE(os.shipstate,'') AS shipstate,
           COALESCE(os.shipzip,'') AS shipzip,
           COALESCE(os.shipcompany,'') AS shipcompany,
           COALESCE(os.shipphone,'') AS shipphone,
           "legacy" AS `transaction_version`,
           COALESCE(t.auth_code,o.auth_code) AS `authorization_code`
    FROM /;

  #Buvez un litre de cola
  my $sth;
  my $dsth;
  my $parameters = $self->_generateLegacyQuery($transactionsToLoad);
  my $primaryQuery = $parameters->{'primaryIndex'};
  my $dateQuery = $parameters->{'dateIndex'};

  my $limitData = $self->getLoadLimit();
  my $orderByAndLimit = ' ORDER BY o.orderid ';
  if (defined $limitData && defined $limitData->{'length'} && defined $limitData->{'offset'}) {
    $orderByAndLimit = ' ORDER BY o.trans_date ASC LIMIT ?,? ';
    if (@{$primaryQuery->{'values'}} > 0) {
      push @{$primaryQuery->{'values'}},$limitData->{'offset'};
      push @{$primaryQuery->{'values'}},$limitData->{'length'};
    }

    if (@{$dateQuery->{'values'}} > 0) {
      push @{$dateQuery->{'values'}},$limitData->{'offset'};
      push @{$dateQuery->{'values'}},$limitData->{'length'};
    }
  }

  my $dateResults = [];
  my $primaryResults = [];
  eval {
    if (@{$primaryQuery->{'values'}} > 0) {
      $query = $query . '
        operation_log o FORCE INDEX (PRIMARY)
        JOIN trans_log t FORCE INDEX (PRIMARY) ON (o.username = t.username AND o.orderid = t.orderid)
        LEFT JOIN ordersummary os FORCE INDEX (PRIMARY) ON (t.username = os.username and t.orderid = os.orderid)
        WHERE t.trans_type <> \'query\' AND (' . join(' OR ',@{$primaryQuery->{'query'}}) . ')
        ' . $orderByAndLimit;
      $sth = $dbs->prepare('pnpdata', $query);
      $sth->execute(@{$primaryQuery->{'values'}}) or die $DBI::errstr;
      $primaryResults = $sth->fetchall_arrayref({});
    } elsif (@{$dateQuery->{'values'}} > 0) {
      $query = $query . '
        trans_log t FORCE INDEX (tlog_tdateuname_idx)
        JOIN operation_log o FORCE INDEX(PRIMARY) ON (t.username = o.username and t.orderid = o.orderid)
        LEFT JOIN ordersummary os FORCE INDEX (PRIMARY) ON (t.username = os.username and t.orderid = os.orderid)
        WHERE t.trans_type <> \'query\' AND (' . join(' OR ',@{$dateQuery->{'query'}}) . ')
        ' . $orderByAndLimit;
      $dsth = $dbs->prepare('pnpdata', $query);
      $dsth->execute(@{$dateQuery->{'values'}}) or die $DBI::errstr;
      $dateResults = $dsth->fetchall_arrayref({});
    }
  };

  if ($@) {
    new PlugNPay::Logging::DataLog({'collection' => 'transaction'})->log({
      'error' => ( "Database error while loading transaction(s): " . $@),
      'input' => $transactionsToLoad
    });
    die("An error occurred while attempting to load transaction data");
  }

  my $results = [@{$primaryResults},@{$dateResults}];
  return $self->_processLoadedData($results);
}

# processing of loaded info via legacyLoad
sub _processLoadedData {
  my $self = shift;
  my $results = shift;

  my @summaryLoad = ();
  my %transactions = ();
  my $stateObj = new PlugNPay::Transaction::State();
  foreach my $row (@{$results}) {
    my $loadedData = {};
    my $contact = {
      'name' => $row->{'full_name'},
      'address' => $row->{'address'},
      'city' => $row->{'city'},
      'state' => $row->{'state'},
      'country' => $row->{'country'},
      'postal_code' => $row->{'postal_code'},
      'email' => $row->{'email'},
      'phone' => $row->{'phone'},
      'fax' => $row->{'fax'},
      'company' => $row->{'card_company'}
    };
    $loadedData->{'billing_information'} = $contact;

    my $shippingContact = {
      'name' => $row->{'shipname'},
      'company' => $row->{'shipcompany'},
      'phone' => $row->{'shipphone'},
      'address' => $row->{'shipaddr1'},
      'address2' => $row->{'shipaddr2'},
      'city' => $row->{'shipcity'},
      'state' => $row->{'shipstate'},
      'country' => $row->{'shipcountry'},
      'postal_code' => $row->{'shipzip'},
      'email' => $row->{'email'}
    };

    $loadedData->{'shipping_information'} = $shippingContact;

    my $currentOp = $stateObj->translateLegacyOperation($row->{'transaction_type'},$row->{'lastopstatus'});
    my $currentStateID = $stateObj->getTransactionStateID($currentOp);
    $loadedData->{'transaction_state'} = $currentOp;
    $loadedData->{'transaction_state_id'} = $currentStateID;
    $loadedData->{'merchant'} = $row->{'merchant'};
    $loadedData->{'merchant_order_id'} = $row->{'merchant_order_id'};
    $loadedData->{'processor_transaction_date_time'} = $row->{'processor_transaction_date_time'};
    $loadedData->{'processor_settlement_time'} = $row->{'processor_settlement_time'};
    $loadedData->{'settlement_mark_time'} = $row->{'settlement_mark_time'};
    $loadedData->{'account_type'} = $row->{'accttype'};
    $loadedData->{'transaction_date_time'} = $row->{'transaction_date_time'};
    $loadedData->{'processor_settlement_time'} = $row->{'transaction_date_time'};
    $loadedData->{'authorization_code'} = $row->{'authorization_code'};
    $loadedData->{'card_information'} = {'card_expiration' => $row->{'expiration_date'},
                                         'masked_number' => $row->{'masked_card_number'},
                                         'avs_response' => $row->{'avs_response'} || '',
                                         'cvv_response' => $row->{'cvv_response'} || ''
                                        };

    $loadedData->{'authorization_code'} = $row->{'authorization_code'};
    $loadedData->{'processor'} = $row->{'processor'};
    $loadedData->{'processorMerchantId'} = $row->{'processor_merchant_id'};
    $loadedData->{'finalstatus'} = $row->{'status'};
    $loadedData->{'status'} = $row->{'lastopstatus'};
    $loadedData->{'result'} = $row->{'result'};
    $loadedData->{'batch_number'} = $row->{'batchnum'};
    $loadedData->{'batch_time'} = $row->{'batch_time'};
    $loadedData->{'reference_number'} = $row->{'reference_number'};
    $loadedData->{'processor_message'} = $row->{'message'};# || $row->{'status'}; # why?!  this is bad i think...
    $loadedData->{'message'} = $row->{'message'} || '';
    $loadedData->{'ip_address'} = $row->{'ip_address'} || '';
    $loadedData->{'publisher_email'} = $row->{'publisheremail'} || '';
    #why twice? for JSON mapping of course!
    my $additionalProcessorDetails = {};
    $additionalProcessorDetails->{'batchID'} = $row->{'result'} if $row->{'result'} =~ /^[0-9]+$/;
    $additionalProcessorDetails->{'batchNumber'} = $row->{'batchnum'} if $row->{'batchnum'};
    $additionalProcessorDetails->{'batchTime'} = $row->{'batchTime'} if $row->{'batchTime'} ;
    $additionalProcessorDetails->{'processor_message'} = $loadedData->{'processor_message'} if $loadedData->{'processor_message'};
    $additionalProcessorDetails->{'processor_reference_id'} = $row->{'reference_number'} if $row->{'reference_number'};
    $loadedData->{'additional_processor_details'} = { $currentStateID => $additionalProcessorDetails};

    if ($row->{'transaction_type'} eq 'return') {
      my $isCredit = 1;
      if ($row->{'postauthstatus'} && $row->{'returnstatus'}) {
        $isCredit = 0;
      }
      #for compatibility!
      my $uuid = new PlugNPay::Util::UniqueID();
      $loadedData->{'pnp_transaction_ref_id'} = ($isCredit ? undef : $uuid->inBinary());
    }

    my $accountCodes = {};

    $accountCodes->{'1'} = $row->{'account_code1'};
    $accountCodes->{'2'} = $row->{'account_code2'};
    $accountCodes->{'3'} = $row->{'account_code3'};
    $accountCodes->{'4'} = $row->{'account_code4'};

    $loadedData->{'account_codes'} = {$loadedData->{'transaction_state_id'} => $accountCodes};

    my $paymentType = 'card';
    if ($row->{'accttype'} eq 'checking' || $row->{'accttype'} eq 'savings') {
      $paymentType = 'ach';
    }

    if ($self->getLoadPaymentData()) {
      my $cardData = new PlugNPay::CardData();
      my $paymentObj;
      if($paymentType eq 'card') {
        my $encCard = $row->{'encrypted_card_number'};
        eval {
          $encCard = $cardData->getOrderCardData({'orderID' => $row->{'merchant_order_id'},
                                                 'username' => $row->{'merchant'}});
        };

        $paymentObj = new PlugNPay::CreditCard();
        if ($encCard && !$@) {
          $paymentObj->setNumberFromEncryptedNumber($encCard);
        } else {
          new PlugNPay::Logging::DataLog({'collection' => 'transaction'})->log(
                         {'error' => ( $@ ? $@ : 'Bad enc card number returned'),
                          'merchant' => $row->{'merchant'},
                          'orderID' => $row->{'merchant_order_id'},
                          'function' => 'legacyLoad -> processData',
                          'module' => 'PlugNPay::Transaction::Loader'}
          );
        }
      } elsif ($paymentType eq 'ach') {
        $paymentObj = new PlugNPay::OnlineCheck();
        $paymentObj->decryptAccountInfo($row->{'encrypted_card_number'});
      }

      $loadedData->{'pnp_token'} = $paymentObj->getToken();
    }

    $loadedData->{'transaction_vehicle'} = $paymentType;
    my @amountAndCurrency = split(/\s+/,$row->{'transaction_amount'});

    $loadedData->{'currency'} = uc($amountAndCurrency[0]);
    $loadedData->{'transaction_amount'} = $amountAndCurrency[1];
    if ($row->{'transaction_type'} eq 'postauth') {
      my ($curr,$settledAmount) = split(/\s+/,$row->{'settlement_amount'});
      $loadedData->{'settlement_amount'} = $settledAmount;
      $loadedData->{'settled_amount'} = $settledAmount || $amountAndCurrency[1];
    }

    # HISTORY #

    #auth
    my $history = {};
    $history->{'auth_time'} = $row->{'authtime'} if ($row->{'authtime'});
    $history->{'auth_status'} = $row->{'authstatus'} if ($row->{'authstatus'});
    if ($row->{'authamount'}) {
      $row->{'authamount'} =~ s/[^\d\.]//g;
      $history->{'auth_amount'} = $row->{'authamount'};
    }

    #postauth
    $history->{'mark_time'} = $row->{'settlement_mark_time'} if ($row->{'settlement_mark_time'});
    $history->{'postauth_time'} = $row->{'processor_settlement_date'} if ($row->{'processor_settlement_date'});
    $history->{'postauth_status'} = $row->{'postauthstatus'} if ($row->{'postauthstatus'});
    if ($row->{'settlement_amount'} || ($row->{'transaction_type'} =~ /postauth|return|credit|mark/i && $row->{'transaction_amount'})) {
      #need to check return/credit because only settled transactions are returned, auths are voided
      my $settlementAmount = ($row->{'settlement_amount'} ? $row->{'settlement_amount'} : $row->{'transaction_amount'});
      $settlementAmount =~ s/[^\d\.]//g;
      if (lc($row->{'transaction_type'}) =~ /postauth|return|credit/i) {
        $history->{'postauth_amount'} = $settlementAmount;
      }

      $history->{'mark_amount'} = $settlementAmount;
    }

    #return
    $history->{'return_time'} = $row->{'returntime'} if ($row->{'returntime'});
    $history->{'return_status'} = $row->{'returnstatus'} if ($row->{'returnstatus'});
    if ($row->{'returnamount'} || ($row->{'transaction_type'} =~ /return|credit/i && $row->{'transaction_amount'})) {
      my $returnAmount = ($row->{'returnamount'} ? $row->{'returnamount'} : $row->{'transaction_amount'});
      $returnAmount =~ s/[^\d\.]//g;
      $history->{'return_amount'} = $returnAmount;
    }

    #void
    $history->{'void_time'} = $row->{'voidtime'} if ($row->{'voidtime'});
    $history->{'void_status'} = $row->{'voidstatus'} if ($row->{'voidstatus'});
    if ($row->{'transaction_type'} eq 'void' && $row->{'transaction_amount'}) {
      $row->{'transaction_amount'} =~ s/[^\d\.]//g;
      $history->{'void_amount'} = $row->{'transaction_amount'};
    }

    #reauth
    $history->{'reauth_time'} = $row->{'reauthtime'} if ($row->{'reauthtime'});
    $history->{'reauth_status'} = $row->{'reauthstatus'} if ($row->{'reauthstatus'});
    if ($row->{'reauthamount'}) {
      $row->{'reauthamount'} =~ s/[^\d\.]//g;
      $history->{'reauth_amount'} = $row->{'reauthamount'};
    }
    $loadedData->{'transaction_history'} = $history;
    # END HISTORY #

    $loadedData->{'paymentType'} = $paymentType;
    my $timeObject = new PlugNPay::Sys::Time();
    my $transDateTime = $timeObject->inFormatDetectType('unix',$row->{'transaction_date_time'});
    my $procDateTime = $timeObject->inFormatDetectType('unix',$row->{'processor_transaction_date_time'});
    my $valueToConvert = ( $transDateTime < $procDateTime ? $transDateTime : $procDateTime);

    $timeObject->fromFormat('unix',$valueToConvert);

    $loadedData->{'creation_date'} = $timeObject->inFormat('iso');

    my $transflagsString = $row->{'transflags'};
    # create transflags object in case they are stored as a hex bitmap string
    my $transflagsObject = new PlugNPay::Legacy::Transflags();
    $transflagsObject->fromString($transflagsString);
    $loadedData->{'transaction_flags'} = $transflagsObject->getFlags();

    #Building for ordersummary table
    push @summaryLoad,{'orderID' => $row->{'merchant_order_id'}, 'username' => $row->{'merchant'}};

    if ($row->{'merchant'} ne '' && $row->{'merchant_order_id'} ne '') {
      if (defined $transactions{$row->{'merchant'}}{$row->{'merchant_order_id'}} && $transactions{$row->{'merchant'}}{$row->{'merchant_order_id'}}{'transaction_state'} ne $currentOp) {
        $transactions{$row->{'merchant'}}{$row->{'merchant_order_id'}}{'related_transaction'}{$row->{'transaction_type'}} = $loadedData;
      } else {
        $transactions{$row->{'merchant'}}{$row->{'merchant_order_id'}} = $loadedData;
      }
    }
  }

  if ($self->getLoadDetailedData()) {
    my $historyObject = new PlugNPay::Transaction::Loader::History();
    foreach my $transactionMerchant (keys %transactions) {
      my @orderIDs = keys %{$transactions{$transactionMerchant}};
      my $historyData = $historyObject->loadMultipleLegacy($transactionMerchant, \@orderIDs);
      my $adjLogger = new PlugNPay::Transaction::Logging::Adjustment();
      $adjLogger->setGatewayAccount($transactionMerchant);
      my $logs = $adjLogger->loadMultipleWithStateInfo(\@orderIDs);
      foreach my $currentOrderID (@orderIDs) {
        if (ref($historyData->{$currentOrderID}) eq 'HASH') {
          my %tempHistory = %{$transactions{$transactionMerchant}{$currentOrderID}{'transaction_history'}};
          %tempHistory = (%tempHistory, %{$historyData->{$currentOrderID}});
          $transactions{$transactionMerchant}{$currentOrderID}{'transaction_history'} = \%tempHistory;
        }

        if ($logs->{$currentOrderID}) {
          # $transactions{$transactionMerchant}{$currentOrderID}{'base_amount'}          = $logs->{$currentOrderID}->getBaseAmount();
          $transactions{$transactionMerchant}{$currentOrderID}{'fee_amount'}           = $logs->{$currentOrderID}->getAdjustmentTotalAmount();
          $transactions{$transactionMerchant}{$currentOrderID}{'adjustment_model'}     = $logs->{$currentOrderID}->getAdjustmentModel();
          $transactions{$transactionMerchant}{$currentOrderID}{'adjustment_mode'}      = $logs->{$currentOrderID}->getAdjustmentMode();
          $transactions{$transactionMerchant}{$currentOrderID}{'adjustment_order_id'}  = $logs->{$currentOrderID}->getAdjustmentOrderID() || $currentOrderID;
          $transactions{$transactionMerchant}{$currentOrderID}{'adjustment_account'}   = $logs->{$currentOrderID}->getAdjustmentGatewayAccount() || $logs->{$currentOrderID}->getGatewayAccount();
        }
      }
    }
  }

  new PlugNPay::Logging::Performance('Legacy Load complete');
  return \%transactions;
}

# Load to populate Transaction Response object
sub loadLegacyResponse {
  my $self = shift;
  my $data = shift;
  my $responses = {};

  if (ref($data) eq 'HASH') {
     $data = [$data];
  }

  my $dbs = new PlugNPay::DBConnection();

  my $query = q/
    SELECT avs AS `avs_response`,
    auth_code AS `authorization_code`,
    cvvresp AS `cvv_response`,
    username,
    orderid,
    finalstatus AS `status`,
    descr AS `processor_message`
    FROM trans_log FORCE INDEX (PRIMARY)
    WHERE trans_type <> 'query' AND /;
  my @values = ();
  my @searches = ();
  foreach my $td (@{$data}) {
    my $orderID = $td->{'orderID'} || $td->{'transactionID'};
    my $username = $td->{'gatewayAccount'} || $td->{'username'};
    my $search = ' username = ? ';
    push @values,$username;
    if (defined $orderID) {
      $search .= ' AND orderid = ? ';
      push @values,$orderID;
    }
    push @searches,$search;
  }

  my $sth = $dbs->prepare('pnpdata',$query . join(' OR ',@searches));
  $sth->execute(@values) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});

  return $self->parseResponseData($rows);
}

sub _generateLegacyQuery {
  my $self = shift;
  my $transactionsToLoad = shift;
  #for trans_log force index primary
  my @primarySearch = ();
  my @primaryValues = ();
  #for trans_log force index tlog_tdateuname_idx
  my @dateSearch = ();
  my @dateValues = ();
  my $time = new PlugNPay::Sys::Time();
  foreach my $td (@{$transactionsToLoad}) {
    if (defined $td->{'transactionVersion'} && $td->{'transactionVersion'} ne 'legacy') {
      next;
    }
    my $isDateRangeSearch = 0;
    my $orderID = $td->{'orderID'} || $td->{'transactionID'} || $td->{'order_id'} || $td->{'pnp_transaction_id'};
    my $username = $td->{'gatewayAccount'} || $td->{'username'} || $td->{'merchant'};
    my @tempValues = ($username);
    my @completes;

    my $dateRange = {};

    if (defined $td->{'start_date'} || $td->{'start_time'}) {
      my $startDate = (defined ($td->{'start_time'}) ? $td->{'start_time'} : $td->{'start_date'});
      $isDateRangeSearch = 1;
      $dateRange->{'start_date'} = $time->inFormatDetectType('yyyymmdd',$startDate);
    }

    if (defined $td->{'end_date'} || $td->{'end_time'}) {
      my $endDate = (defined ($td->{'end_time'}) ? $td->{'end_time'} : $td->{'end_date'});
      $isDateRangeSearch = 1;
      $dateRange->{'end_date'} = $time->inFormatDetectType('yyyymmdd',$endDate);
    }

    if (defined $td->{'trans_time'} || defined $td->{'transaction_time'} || defined $td->{'transaction_date_time'}) {
       my $transTime = $td->{'trans_time'};
       if (!$transTime) {
         $transTime = (defined  $td->{'transaction_time'} ? $td->{'transaction_time'} : $td->{'transaction_date_time'});
       }
       push @completes, 't.trans_time = ?';
       push @tempValues,$time->inFormatDetectType('gendatetime',$transTime);
    }

    if ($isDateRangeSearch) {
      push @completes,'o.trans_date = t.trans_date';
    }

    push @completes,'o.username = ?';

    #For compatibility
    if (defined $orderID) {
      if (defined $td->{'pnp_transaction_ref_id'}) {
        push @completes,'(o.orderid = ? OR o.orderid = ?)';
        push @tempValues,$orderID;
        push @tempValues,$td->{'pnp_transaction_ref_id'};
      } else {
        push @completes,'o.orderid = ?';
        push @tempValues,$orderID;
      }
    } elsif (defined $td->{'pnp_transaction_ref_id'}) {
      push @completes,'o.orderid = ?';
      push @tempValues,$td->{'pnp_transaction_ref_id'};
    }

    if (defined $td->{'transaction_state_id'}) {
      my $stateMachine = new PlugNPay::Transaction::State();
      my $transactionState = $stateMachine->getStateNames()->{$td->{'transaction_state_id'}};

      my ($lastop,$lastopStatus) = split('_',$transactionState);
      $lastop = ($lastop eq 'CREDIT' ? 'return' : lc($lastop));
      push @completes, 'o.lastop = ?';
      push @tempValues,$lastop;

      unless (defined $td->{'get_all_statuses'} && $td->{'get_all_statuses'} eq 'true') {
        $lastopStatus = (!$lastopStatus ? 'success' : lc($lastopStatus));
        push @completes,'o.lastopstatus = ?';
        push @tempValues,$lastopStatus;
      }
    } elsif (defined $td->{'operation'}) {
      push @completes,'o.lastop = ?';
      push @tempValues,lc($td->{'operation'});
    } elsif (defined $td->{'operationIn'}) {
      if (ref($td->{'operationIn'}) ne 'ARRAY' || @{$td->{'operationIn'}} == 0) {
        die('operationIn is not an array ref, or has no operations');
      }
      my $operationInParameters = join(',',map {'?'} @{$td->{'operationIn'}});
      push @completes,'o.lastop in (' . $operationInParameters . ')';
      push @tempValues,@{$td->{'operationIn'}};
    }

    if ($td->{'batchid'}) {
      push @completes,'t.result = ?';
      push @tempValues,$td->{'batchid'};
    }

    if (defined $td->{'processor'}) {
      push @completes,'(t.processor = ? OR o.processor = ?)';
      push @tempValues,$td->{'processor'};
      push @tempValues,$td->{'processor'};
    }

    if (defined $td->{'authorization_code'} || defined $td->{'auth-code'}) {
      my $authcode = $td->{'authrorization_code'};
      $authcode = $td->{'auth-code'} if !defined($authcode);
      $authcode =~ tr/a-z/A-Z/;
      $authcode =~ s/[^0-9A-Z]//g;
      $authcode = substr($authcode,0,6);
      push @completes,'UPPER(auth_code) LIKE ?';
      push(@tempValues, "$authcode%");
    }

    if (defined $td->{'transaction_vehicle_id'}) {
      my $util = new PlugNPay::Transaction::Vehicle();
      my $unprocessedType = $util->getTransactionVehicleName($td->{'transaction_vehicle_id'});

      my $type = 'credit';
      if (lc($unprocessedType) eq 'ach') {
        $type = 'checking';
      }

      push @completes,'t.accttype = ?';
      push @tempValues,$type;

    } elsif (defined $td->{'accttype'} || defined $td->{'account_type'}) {
      my $type = (defined $td->{'accttype'} ? $td->{'accttype'} : $td->{'account_type'});
      push @completes,'t.accttype = ?';
      push @tempValues,$type;
    }

    if (defined $td->{'account_codes'} && ref($td->{'account_codes'}) eq 'HASH') {
      foreach my $accountCode (keys %{$td->{'account_codes'}}) {
        if ($accountCode eq '1') {
          push @completes,'t.acct_code = ?';
        } else {
          push @completes,'t.acct_code' . $accountCode . ' = ?';
        }

        push @tempValues, $td->{'account_codes'}{$accountCode};
      }
    }

    if (defined $td->{'status'}) {
      if (ref($td->{'status'}) eq 'ARRAY') {
        my $params = 'o.lastopstatus in (' . join(',',map { '?' } @{$td-{'status'}}) . ')';
        push @completes, $params;
        push @tempValues, @{$td->{'status'}};
      } else {
        push @completes,'o.lastopstatus = ?';
        push @tempValues, $td->{'status'};
      }
    }

    if ($isDateRangeSearch) {
      my $builder = new PlugNPay::Database::QueryBuilder();
      my $params = $builder->generateDateRange($dateRange);
      push @completes,'t.trans_date IN (' . $params->{'params'} . ') ';
      push @tempValues,@{$params->{'values'}};

      if ($td->{'start_time'}) {
         push @completes,'t.trans_time >= ? ';
         push @tempValues,$time->inFormatDetectType('gendatetime',$td->{'start_time'});
      }

      if ($td->{'end_time'}) {
         push @completes,' t.trans_time <= ? ';
         push @tempValues,$time->inFormatDetectType('gendatetime',$td->{'end_time'});
      }

      #Now we do the hokey pokey and we turn ourselves around
      my $completeQuery = ' ( ' . join(' AND ',@completes) . ' ) ';
      push @dateSearch,$completeQuery;
      push @dateValues,@tempValues;
    } else {
      my $completeQuery = ' ( ' . join(' AND ',@completes) . ' ) ';
      push @primarySearch,$completeQuery;
      push @primaryValues,@tempValues;
    }
  }

  return { 'primaryIndex' => {
                             'values' => \@primaryValues,
                             'query' => \@primarySearch
                             },
           'dateIndex' => {
                        'values' => \@dateValues,
                        'query' => \@dateSearch
                        }
         };
}

sub getLegacyCount {
  my $self = shift;
  my $data = shift;

  my $forceIndex = 'PRIMARY';
  my $selectQuery = 'SELECT COUNT(orderid) AS "count"
                     FROM trans_log ';
  my $completeQuery = ' WHERE username = ? ';
  my $orderID = $data->{'orderID'} || $data->{'transactionID'} || $data->{'order_id'};
  my $username = $data->{'gatewayAccount'} || $data->{'username'};
  my @values = ($username);

  if (defined $orderID) {
    $completeQuery .= ' AND orderid = ? ';
    push @values,$orderID;
  }

  if (defined $data->{'start_date'}) {
    $forceIndex = 'tlog_tdateuname_idx';
    $completeQuery .= ' AND trans_date >= ? ';
    push @values,$data->{'start_date'};
  }

  if (defined $data->{'end_date'}) {
    $forceIndex = 'tlog_tdateuname_idx';
    $completeQuery .= ' AND trans_date <= ? ';
    push @values,$data->{'end_date'};
  }

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpdata',$selectQuery . ' FORCE INDEX ( ' . $forceIndex . ' ) ' . $completeQuery);
  $sth->execute(@values);
  my $results = $sth->fetchall_arrayref({});

  return $results->[0]{'count'};
}

sub legacyTransactionExists {
  my $self = shift;
  my $transID = shift;
  my $merchant = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpdata',q/
                SELECT COUNT(orderid) AS `exists`
                FROM trans_log
                WHERE username = ?
                  AND orderid = ?/
             );
  $sth->execute($merchant,$transID) or die $DBI::errstr;

  my $rows = $sth->fetchall_arrayref({});
  return $rows->[0]{'exists'};
}

######################
# New Transaction DB #
######################
sub unifiedLoad {
  my $self = shift;
  my $loadOptions = shift;
  if (ref($loadOptions) eq 'HASH') {
    $loadOptions = [$loadOptions];
  }

  my $dbs = new PlugNPay::DBConnection();
  my $select = 'SELECT t.pnp_transaction_id,
                       t.pnp_order_id,
                       p.processor_code_handle AS `processor`,
                       t.transaction_state_id,
                       t.transaction_vehicle_id,
                       t.vendor_token,
                       t.transaction_type_id,
                       t.transaction_date_time,
                       t.authorization_code,
                       t.pnp_transaction_ref_id,
                       t.settlement_mark_date_time,
                       t.processor_transaction_date_time,
                       t.processor_settlement_date_time,
                       t.amount AS `transaction_amount`,
                       t.currency,
                       t.tax_amount,
                       t.settlement_amount,
                       t.settled_amount,
                       t.settled_tax_amount,
                       t.fee_amount,
                       t.fee_tax,
                       t.ip_address AS `ip_address_binary`,
                       t.account_type AS `account_type_id`,
                       t.pnp_token,
                       t.processor_token,
                       o.merchant_id,
                       o.merchant_order_id,
                       o.merchant_classification_id,
                       m.identifier AS `merchant`,
                       "unified" AS `transaction_version`
                FROM `transaction` t, `order` o, `merchant` m, `processor` p
                WHERE  ';

  my $data = {};
  my $stateObj = new PlugNPay::Transaction::State();
  my $typeObj = new PlugNPay::Transaction::Type();
  my $vehicleObj = new PlugNPay::Transaction::Vehicle();
  my $internalID = new PlugNPay::GatewayAccount::InternalID();
  my $processorIDObj = new PlugNPay::Processor::ID();
  my $accountTypeObj = new PlugNPay::Transaction::AccountType();
  my $currencyIDObj = new PlugNPay::Currency();
  my $historyObj = new PlugNPay::Transaction::Loader::History();

  my $uuid = new PlugNPay::Util::UniqueID();
  my $ip = new PlugNPay::Util::IP::Address();
  my @values = ();
  my @params = ();
  my $td = {};
  foreach my $options (@{$loadOptions}) {
    $options->{'hex'} = PlugNPay::Util::UniqueID::fromBinaryToHex($options->{'transactionID'});
    $options->{'pnp_transaction_id'} ||= $options->{'transactionID'}; # set for database column to be queried.
    $options->{'pnp_transaction_id'} = PlugNPay::Util::UniqueID::fromHexToBinary($options->{'pnp_transaction_id'});

    if (length($options->{'orderID'}) > 23) {
      $options->{'pnp_order_id'} ||= $options->{'orderID'}; # set for database column to be queried.
      $options->{'pnp_order_id'} = PlugNPay::Util::UniqueID::fromHexToBinary($options->{'pnp_order_id'});
    }

    my $searchString = ' (o.pnp_order_id = t.pnp_order_id  AND o.merchant_id = m.id AND p.id = t.processor_id  ';

    my $criteria = $self->_generateSearchCriteria($options);
    $searchString .= $criteria->{'searchString'} . ')';

    push @params,$searchString;
    push @values,@{$criteria->{'values'}};
  }
  if (@params == 0) {
    return {};
  }
  my $rows = [];
  eval {
    $select .= ' ' . join(' OR ',@params);
    my $sth = $dbs->prepare('pnp_transaction', $select) or die $DBI::errstr;
    $sth->execute(@values) or die $DBI::errstr;
    $rows = $sth->fetchall_arrayref({}) or die $DBI::errstr;
  };
  # TODO handle error
  my @PNPTransactionIDs = ();
  foreach my $row (@{$rows}) {
    push @PNPTransactionIDs,$row->{'pnp_transaction_id'};
  }

  my $billingInformation = $self->loadBillingInformation(\@PNPTransactionIDs);

  my $shippingInformation = $self->loadShippingInformation(\@PNPTransactionIDs);

  my $additionalProcessorDetails = $self->loadAdditionalProcessorDetails(\@PNPTransactionIDs);

  my $transactionFlags = $self->loadTransFlags(\@PNPTransactionIDs);

  my $accountCodes = $self->loadAccountCodes(\@PNPTransactionIDs);

  my $cardInfo = $self->loadCardInformation(\@PNPTransactionIDs);

  my $jobData = $self->getTransactionSettlementJobs(\@PNPTransactionIDs);

  my $historyData = $historyObj->buildMultiple(\@PNPTransactionIDs);

  my $timeObj = new PlugNPay::Sys::Time();
  my $batchStateID = $stateObj->getTransactionStateID('POSTAUTH_READY');
  my $x = 1;
  foreach my $row (@{$rows}) {
    my $loaded = $row;
    my $pnpTransactionID = $row->{'pnp_transaction_id'};
    $loaded->{'billing_information'} = $billingInformation->{$pnpTransactionID};
    $loaded->{'shipping_information'} = $shippingInformation->{$pnpTransactionID};
    $loaded->{'additional_processor_details'} = $additionalProcessorDetails->{$pnpTransactionID};
    $loaded->{'transaction_flags'} = $transactionFlags->{$pnpTransactionID};
    $loaded->{'account_codes'} = $accountCodes->{$pnpTransactionID};
    if ($additionalProcessorDetails->{$pnpTransactionID}{$batchStateID}{'pnp_batch_id'}) {
      $loaded->{'batchID'} = $additionalProcessorDetails->{$pnpTransactionID}{$batchStateID}{'pnp_batch_id'};
    }

    # IP Converting Binary->IPv4
    $ip->fromBinary($row->{'ip_address_binary'});
    $loaded->{'ip_address'} = $ip->toIP(4);

    # Load name from IDs
    $loaded->{'currency'} = $currencyIDObj->getTransactionCurrencyCode($row->{'currency_id'});
    $loaded->{'account_type'} = $accountTypeObj->getAccountTypeName($row->{'account_type_id'});
    $loaded->{'merchant'} = $internalID->getMerchantName($row->{'merchant_id'});
    $loaded->{'processor'} = $row->{'processor'};
    $loaded->{'processor_id'} = $processorIDObj->getProcessorID($row->{'processor'});
    $loaded->{'transaction_state'} = $stateObj->getTransactionStateName($row->{'transaction_state_id'});
    $loaded->{'transaction_vehicle'} = $vehicleObj->getTransactionVehicleName($row->{'transaction_vehicle_id'});
    $loaded->{'transaction_type'} = $typeObj->getTransactionTypeName($row->{'transaction_type_id'});

    if ($row->{'transaction_vehicle'} eq 'card' || $row->{'transaction_vehicle'} eq 'gift') {
       $loaded->{'card_information'} = $cardInfo->{$pnpTransactionID};
    }

    $uuid->fromBinary($pnpTransactionID);
    if (exists $jobData->{$uuid->inHex()} && $jobData->{$uuid->inHex()}) {
      $loaded->{'pnp_job_id'} = $jobData->{$uuid->inHex()};
    }

    my $details = $additionalProcessorDetails->{$pnpTransactionID}{$loaded->{'transaction_state_id'}};
    if ($details->{'processor_status'}) {
      $loaded->{'status'} = $details->{'processor_status'};
    } else {
      my @stateInfo = split('_',$loaded->{'transaction_state'});
      my $status = $stateInfo[@stateInfo-1];
      if (defined $status && $status =~ /PENDING|PROBLEM/) {
        $loaded->{'status'} = lc $status;
      } else {
        $loaded->{'status'} = 'success';
      }
    }

    if ($details->{'processor_message'}) {
      $loaded->{'processor_message'} = $details->{'processor_message'};
    }

    #Parse new time format
    $timeObj->fromFormat('iso',$row->{'transaction_date_time'});
    $loaded->{'transaction_date_time'} = $timeObj->inFormat('db_gm');
    $loaded->{'transaction_date'} = $timeObj->inFormat('iso_gm');

    $timeObj->fromFormat('iso',$row->{'processor_transaction_date_time'});
    $loaded->{'processor_transaction_date'} = $timeObj->inFormat('db_gm');

    $timeObj->fromFormat('iso',$row->{'processor_settlement_date_time'});
    $loaded->{'processor_settlement_time'} = $timeObj->inFormat('db_gm');

    $timeObj->fromFormat('iso',$row->{'settlement_mark_date_time'});
    $loaded->{'settlement_mark_time'} = $timeObj->inFormat('db_gm');

    my $pnpID = $uuid->inHex();
    if ($row->{'merchant'} ne '' && $pnpID ne '') {
      $data->{$row->{'merchant'}}{$pnpID} = $loaded;
    }
  }

  foreach my $transactionMerchant (keys %{$data}) {
    my $adjLogger = new PlugNPay::Transaction::Logging::Adjustment();
    $adjLogger->setGatewayAccount($transactionMerchant);
    my @transactionIDs = keys %{$data->{$transactionMerchant}};
    my @orderIDs = ();
    foreach my $id (@transactionIDs) {
      push @orderIDs,$data->{$transactionMerchant}{$id}{'merchant_order_id'};
    }
    my $logs = $adjLogger->loadMultipleWithStateInfo(\@orderIDs);
    foreach my $currentID (@transactionIDs) {
      #History
      my $currentTrans = $data->{$transactionMerchant}{$currentID};
      my $history = $self->generateHistory($currentTrans,$historyData->{$currentTrans->{'pnp_transaction_id'}});
      if ($currentTrans->{'pnp_transaction_ref_id'}) {
        my $refID = $currentTrans->{'pnp_transaction_ref_id'};
        $uuid->fromBinary($refID);
        my $refTrans =  $data->{$transactionMerchant}{$uuid->inHex()};
        my $refHistory = $self->generateHistory($refTrans,$historyData->{$refID});
        my %tempHash = (%{$refHistory},%{$history});
        $history = \%tempHash;
      }
      $data->{$transactionMerchant}{$currentID}{'transaction_history'} = $history;

      #Adjustment
      my $currentOrderID = $data->{$transactionMerchant}{$currentID}{'merchant_order_id'};
      if ($logs->{$currentOrderID} && $data->{$transactionMerchant}{$currentID}) {
        # $data->{$transactionMerchant}{$currentID}{'base_amount'}         = $logs->{$currentOrderID}->getBaseAmount();
        $data->{$transactionMerchant}{$currentID}{'adjustment_mode'}     = $logs->{$currentOrderID}->getAdjustmentMode();
        $data->{$transactionMerchant}{$currentID}{'adjustment_model'}    = $logs->{$currentOrderID}->getAdjustmentModel();
        $data->{$transactionMerchant}{$currentID}{'adjustment_order_id'} = $logs->{$currentOrderID}->getAdjustmentOrderID() || $currentOrderID;
        $data->{$transactionMerchant}{$currentID}{'adjustment_account'}  = $logs->{$currentOrderID}->getAdjustmentGatewayAccount() || $logs->{$currentOrderID}->getGatewayAccount();
        my $currentFeeAmount =  $data->{$transactionMerchant}{$currentID}{'fee_amount'};
        if (!$currentFeeAmount || $currentFeeAmount == 0.00) {
          $data->{$transactionMerchant}{$currentID}{'fee_amount'} = $logs->{$currentOrderID}->getAdjustmentTotalAmount();
        }
      }
    }
  }

  new PlugNPay::Logging::Performance('New load complete');
  return $data
}

sub duplicateCheck {
  my $self = shift;
  my $input = shift;
  my $amount = $input->{'amount'};
  my $gatewayAccount = $input->{'gatewayAccount'};
  my $operation = $input->{'operation'};
  my $token = $input->{'token'};
  my $lookback = int($input->{'lookbackInSeconds'}) || 60;
  my $database = $input->{'databaseType'};

  my $merchantId = new PlugNPay::GatewayAccount::InternalID()->getMerchantID($gatewayAccount);
  my $stateId = new PlugNPay::Transaction::State()->getStateIDFromOperation($operation);

  my $oldest = new PlugNPay::Sys::Time();
  $oldest->subtractSeconds($lookback);
  my $oldestDateTime = $oldest->inFormat('iso_gm');
  my ($oldestDate) = split('T',$oldestDateTime);

  my $nowDateTime = new PlugNPay::Sys::Time()->inFormat('iso_gm');
  my ($nowDate) = split('T',$nowDateTime);

  my $dbs = new PlugNPay::DBConnection();

  my $values;

  my $query;
  my $databaseName;
  if ($database eq 'unified') {
    $databaseName = 'pnp_transaction';
    $query = q/
      SELECT count(*) AS duplicate
        FROM `transaction` t, `order` o
       WHERE o.merchant_id = ?
         AND o.pnp_order_id = t.pnp_order_id
         AND t.amount = ?
         AND t.state_id = ?
         AND t.transaction_date in (?,?)
         AND t.transaction_date_time >= ?
    /;

    # set values for query
    $values = [$merchantId, $amount, $stateId, $oldestDate, $nowDate, $oldestDateTime];
  } else {
    $databaseName = 'pnpdata';
    $query = q/
      SELECT count(*) AS duplicate
        FROM `operation_log` o FORCE KEY (`oplog_tdateuname_idx`)
       WHERE o.username = ?
         AND o.lastop = ?
         AND COALESCE(o.voidstatus,'') = ''
         AND o.amount LIKE(CONCAT('% ',?))
         AND o.trans_date IN (?,? )
         AND o.authtime >= ?
    /;

    # modify timestamps to work with operation_log time format
    $oldestDate =~ s/[^0-9]//g;
    $nowDate =~ s/[^0-9]//g;
    $oldestDateTime =~ s/[^0-9]//g;

    # set values for query, concatenated with empty string to ensure "VARCHAR" type for index use
    $values = [$gatewayAccount, $operation, $amount . "", $oldestDate . "", $nowDate . "", $oldestDateTime . ""];
  }

  if ($databaseName) {
    my $result = $dbs->fetchallOrDie($databaseName,$query,$values, {});
    return $result->{'result'}[0]{'duplicate'};
  } else {
    die('database type not specified')
  }
}


#Generate 'WHERE' clause #
sub _generateSearchCriteria {
  my $self = shift;
  my $options = shift;
  my @values = ();
  my $stateObj = new PlugNPay::Transaction::State();
  my $typeObj = new PlugNPay::Transaction::Type();
  my $vehicleObj = new PlugNPay::Transaction::Vehicle();
  my $internalID = new PlugNPay::GatewayAccount::InternalID();
  my $procIDObj = new PlugNPay::Processor::ID();
  my $builder = new PlugNPay::Database::QueryBuilder();
  my $time = new PlugNPay::Sys::Time();
  my $searchItems = '';
  if (defined $options->{'username'} || defined $options->{'gatewayAccount'} || defined $options->{'merchant'}) {
    $searchItems .= ' AND o.merchant_id = ?';
    my $id = $internalID->getMerchantID($options->{'username'} || $options->{'gatewayAccount'} || $options->{'merchant'});
    push @values, $id;
  }

  if (defined $options->{'order_classification_id'}) {
    $searchItems .= ' AND o.merchant_classification_id = ? ';
    push @values,$options->{'order_classification_id'};
  } elsif (defined $options->{'order-id'}) {
    $searchItems .= ' AND o.merchant_classification_id = ? ';
    push @values,$options->{'order-id'};
  }

  if (defined $options->{'amount'}) {
    $searchItems .= ' AND t.amount = ?';
    push @values,$options->{'amount'};
  } elsif (defined $options->{'transaction_amount'}) {
    $searchItems .= ' AND t.amount = ?';
    push @values,$options->{'transaction_amount'};
  }

  if (defined $options->{'pnp_order_id'}) {
    $searchItems .= ' AND o.pnp_order_id = ? ';
    push @values, $options->{'pnp_order_id'};
  } elsif (defined $options->{'orderID'}) {
    $searchItems .= ' AND o.merchant_order_id = ? ';
    push @values, $options->{'orderID'};
  } elsif (defined $options->{'merchant_order_id'}) {
    $searchItems .= ' AND o.merchant_order_id = ? ';
    push @values, $options->{'merchant_order_id'};
  }

  if (defined $options->{'pnp_transaction_id'}) {
    my $transID = PlugNPay::Util::UniqueID::fromHexToBinary($options->{'pnp_transaction_id'});

    $searchItems .= ' AND t.pnp_transaction_id = ?';
    push @values,$transID;
  } elsif (defined $options->{'transactionID'}) {
    my $transID = PlugNPay::Util::UniqueID::fromHexToBinary($options->{'transactionID'});

    $searchItems .= ' AND t.pnp_transaction_id = ?';
    push @values,$transID;
  }

  if (defined $options->{'auth-code'} || defined $options->{'authorization_code'}) {
    $searchItems .= ' AND t.authorization_code = ?';
    my $authCode = (defined $options->{'auth-code'} ? $options->{'auth-code'} : $options->{'authorization_code'});

    push @values,$authCode;
  }

  if (defined $options->{'operation'} || defined $options->{'transaction_state'}) {
    $searchItems .= ' AND t.transaction_state_id IN (?,?,?) ';
    my $transState = ($options->{'operation'} ? $options->{'operation'} : $options->{'transaction_state'});
    my $state = $stateObj->getStateIDFromOperation($transState);
    my @stateInfo = split('_',$transState);

    push @values,$stateObj->getTransactionStateID($stateInfo[0]);
    push @values,$stateObj->getTransactionStateID($stateInfo[0] . '_PENDING');
    push @values,$stateObj->getTransactionStateID($stateInfo[0] . '_PROBLEM');
  } elsif (defined $options->{'operationIn'}) {
    if (ref ($options->{'operationIn'} ne 'ARRAY')) {
      die('operationIn is not an array ref, or has no operations');
    }

    my $operationInParameters = join(',',map { '?,?,?' } @{$options->{'operationIn'}});

    $searchItems .= ' AND t.transaction_state_id IN (' . $operationInParameters . ')';

    foreach my $op (@{$options->{'operationIn'}}) {
      my $transState = ($options->{'operation'} ? $options->{'operation'} : $options->{'transaction_state'});
      my $state = $stateObj->getStateIDFromOperation($transState);
      my @stateInfo = split('_',$transState);

      push @values,$stateObj->getTransactionStateID($stateInfo[0]);
      push @values,$stateObj->getTransactionStateID($stateInfo[0] . '_PENDING');
      push @values,$stateObj->getTransactionStateID($stateInfo[0] . '_PROBLEM');
    }
  }

  if (defined $options->{'pnp_transaction_ref_id'}) {
    my $transRefID = $options->{'pnp_transaction_ref_id'};
    if ($options->{'pnp_transaction_ref_id'} =~ /^[a-fA-F0-9]+$/) {
      my $uuid = new PlugNPay::Util::UniqueID();
      $uuid->fromHex($options->{'pnp_transaction_ref_id'});
      $transRefID = $uuid->inBinary();
    }

    $searchItems .= ' AND t.pnp_transaction_ref_id = ?';
    push @values,$transRefID;
  }

  if (defined $options->{'processor'}) {
    $searchItems .= ' AND p.processor_code_handle = ? ';
    push @values,$options->{'processor'};
  }

  if (defined $options->{'vendor_token'}) {
    $searchItems .= ' AND t.vendor_token = ? ';
    push @values,$options->{'vendor_token'};
  }

  if (defined $options->{'transaction_date_time'}) {
    $searchItems .= ' AND t.transaction_date_time = ?';
    my $formattedTime = $time->inFormatDetectType('iso_gm',$options->{'transaction_date_time'});
    push @values,$formattedTime;
  } elsif (defined $options->{'transdate'}) {
    $searchItems .= ' AND t.transaction_date_time = ?';
    my $formattedTime = $time->inFormatDetectType('iso_gm',$options->{'transdate'});
    push @values,$formattedTime;
  }

  if (defined $options->{'transaction_state_id'}) {
    $searchItems .= ' AND t.transaction_state_id = ? ';
    push @values,$options->{'transaction_state_id'};
  } elsif (defined $options->{'transaction_state'}) {
    $searchItems .= ' AND t.transaction_state_id = ? ';
    push @values,$stateObj->getTransactionStateID($options->{'transaction_state'});
  }

  if (defined $options->{'transaction_vehicle_id'}) {
    $searchItems .= ' AND t.transaction_vehicle_id = ? ';
    push @values,$options->{'transaction_vehicle_id'};
  } elsif (defined $options->{'transaction_vehicle'}) {
    $searchItems .= ' AND t.transaction_vehicle_id = ? ';
    push @values,$vehicleObj->getTransactionVehicleID($options->{'transaction_vehicle'});
  }

  #New date format
  my $dateRange = {};
  my $tempSearch = '';
  my @tempValues = ();

  if ($options->{'start_time'} || $options->{'start_date'}) {
    my $date = $time->inFormatDetectType('yyyymmdd', ( $options->{'start_time'} ? $options->{'start_time'} : $options->{'start_date'}));
    $dateRange->{'start_date'} = $date;
    $tempSearch .= ' AND t.transaction_date_time >= ? ';
    push @tempValues,$date . 'T000000Z';
  }

  if ($options->{'end_time'} || $options->{'end_date'}) {
    my $date = $time->inFormatDetectType('yyyymmdd', ( $options->{'end_time'} ? $options->{'end_time'} : $options->{'end_date'}));
    $dateRange->{'end_date'} = $date;
    $tempSearch .= ' AND t.transaction_date_time <= ? ';
    push @tempValues,$date . 'T240000Z';
  }


  if ($dateRange->{'start_date'} || $dateRange->{'end_date'}) {
    my $params = $builder->generateDateRange($dateRange);
    $searchItems .= ' AND t.transaction_date IN (' . $params->{'params'} . ') ';
    push @values,@{$params->{'values'}};
  }

  if (@tempValues > 0) {
    $searchItems .= $tempSearch;
    push @values,@tempValues;
  }

  return {'searchString' => $searchItems, 'values' => \@values};
}

sub generateHistory {
  my $self = shift;
  my $data = shift;
  my $loggingHistory = shift;
  my $history = {};
  my $timeObj = new PlugNPay::Sys::Time();
  my $stateObj = new PlugNPay::Transaction::State();
  my $stateName = $stateObj->getTransactionStateName($data->{'transaction_state_id'});
  if ($stateName =~ /AUTH/i || $stateName =~ /VOID/i) {
    my $timeForTrans;
    if ($data->{'processor_transaction_date_time'}) {
      $timeObj->fromFormat('iso',$data->{'processor_transaction_date_time'});
      $timeForTrans = $timeObj->inFormat('db_gm');
    } else {
      $timeForTrans = $data->{'transaction_date_time'};
    }

    $history->{'auth_amount'} = $data->{'transaction_amount'} || $data->{'amount'};

    if ($stateName eq 'VOID') {
      $history->{'void_time'} = $timeForTrans;
      $history->{'auth_time'} = $data->{'transaction_date_time'};
      $history->{'void_amount'} = $history->{'auth_amount'};
    } else {
       $history->{'auth_time'} = $timeForTrans;
    }
  } elsif ($stateName =~ /CREDIT/i) {
    if ($data->{'processor_transaction_date_time'}) {
      $timeObj->fromFormat('iso',$data->{'processor_transaction_date_time'});
      $history->{'return_time'} = $timeObj->inFormat('db_gm');
    } else {
      $history->{'return_time'} = $data->{'transaction_date_time'};
    }
    $history->{'return_amount'} = $data->{'transaction_amount'} || $data->{'amount'};
  }

  if ($data->{'settlement_mark_date_time'}) {
    $timeObj->fromFormat('iso',$data->{'settlement_mark_date_time'});
    $history->{'mark_time'} = $timeObj->inFormat('db_gm');
    $history->{'mark_amount'} = $data->{'settlement_amount'};
  }

  if ($data->{'processor_settlement_date_time'} || $data->{'settled_amount'}) {
    $timeObj->fromFormat('iso',$data->{'processor_settlement_date_time'});
    $history->{'postauth_time'} = $timeObj->inFormat('db_gm');
    $history->{'postauth_amount'} = $data->{'settled_amount'};
  }

  if ($history->{'VOID'}) {
    $timeObj->fromFormat('iso',$data->{'transaction_date_time'});
    $history->{'void_time'} = $timeObj->inFormat('db_gm');
    $history->{'void_status'} = $loggingHistory->{'VOID'}{'status'};
    $history->{'void_amount'} = $history->{'auth_amount'} if ($history->{'auth_amount'});
  }

  if ($history->{'AUTH'}) {
    $timeObj->fromFormat('iso',$data->{'transaction_date_time'});
    $history->{'auth_recieved_time'} = $timeObj->inFormat('db_gm');
    $history->{'auth_status'} = $loggingHistory->{'AUTH'}{'status'};
  }

  if ($history->{'CREDIT'}) {
    $history->{'return_received_time'} = $data->{'transaction_date_time'};
    $history->{'return_status'} = $loggingHistory->{'CREDIT'}{'status'};
  }

  if ($history->{'POSTAUTH'}) {
    $history->{'postauth_status'} = $loggingHistory->{'POSTAUTH'}{'status'};
  }

  return $history;
}

sub transactionExists {
  my $self = shift;
  my $pnp_transaction_id = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/ SELECT COUNT(id) AS `exists`
                          FROM `transaction`
                          WHERE pnp_transaction_id = ?
                        /);
  $sth->execute($pnp_transaction_id) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});

  my $exists = $rows->[0]{'exists'};

  return $exists;
}

sub checkMarkedTransactions {
  my $self = shift;
  my $ids = shift;

  my $existsHash = {};
  my ($query,$values) = $self->_generateCheckMarkedTransactionsQuery($ids);

  if (@{$values} > 0) {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnp_transaction',$query);
    $sth->execute(@{$values}) or die $DBI::errstr;

    my $rows = $sth->fetchall_arrayref({});
    my $uuid = new PlugNPay::Util::UniqueID();
    foreach my $row (@{$rows}) {
      my $hexID = $uuid->fromBinaryToHex($row->{'pnp_transaction_id'});
      # 1 if id exists, zero otherwise
      $existsHash->{$hexID} = $row->{'exists'} ? 1 : 0;
    }
  }

  return $existsHash;
}

sub _generateCheckMarkedTransactionsQuery {
  my $self = shift;
  my $ids = shift;

  if (ref($ids) ne 'ARRAY') {
    $ids = [$ids];
  }

  my @values = ();

  my $uuid = new PlugNPay::Util::UniqueID();

  foreach my $id (@{$ids}) {
    my $pnpID;
    if (ref($id) eq 'HASH') {
      $pnpID = $id->{'pnpTransactionID'} || $id->{'transactionID'};
    } else {
      $pnpID = $id;
    }

    if ($pnpID =~ /^[a-fA-F0-9]+$/) {
      $pnpID = $uuid->fromHexToBinary($pnpID);
    }
    push @values,$pnpID;
  }

  my $placeholders = join(',',map { '?' } @values);

  my $query = 'SELECT pnp_transaction_id, 1 AS `exists` FROM `transaction` WHERE pnp_transaction_id in (' . $placeholders . ')';
  return ($query,\@values);
}

sub loadByTransactionID {
  my $self = shift;
  my $pnpTransactionID = shift;

  my $options = {'pnp_transaction_id' => $pnpTransactionID};
  my $responses = $self->load($options);
  my @keys = keys %{$responses};
  my $uuid = new PlugNPay::Util::UniqueID();
  $uuid->fromBinary($pnpTransactionID);
  if (@keys > 0) {
    if (@keys == 1) {
      return $responses->{$keys[0]}{$uuid->inHex()};
    } else {
      return $responses;
    }
  } else {
    return {};
  }
}

sub loadTransactionIDs {
  my $self = shift;
  my $pnpOrderID = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/ SELECT pnp_transaction_id FROM `transaction` WHERE pnp_order_id = ? /);
  $sth->execute($pnpOrderID) or die $DBI::errstr;

  my @ids = ();

  foreach my $row (@{$sth->fetchall_arrayref({})}) {
    push @ids,$row->{'pnp_transaction_id'};
  }

  return \@ids;
}

sub checkIsPending {
  my $self = shift;
  my $pendingIDs = shift;
  if (ref($pendingIDs) ne 'ARRAY') {
    $pendingIDs = [$pendingIDs];
  }

  my $stateMachine = new PlugNPay::Transaction::State();
  my @values = ();
  my @params = ();
  foreach my $id (@{$pendingIDs}) {
    push @params, '?';
    push @values, $id;
  }

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/
                          SELECT transaction_state_id, pnp_transaction_id
                          FROM transaction
                          WHERE pnp_transaction_id IN (/ . join(',',@params) . ')'
  );
  $sth->execute(@values) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});

  my $pendingHash = {};
  foreach my $row (@{$rows}) {
    my $state = $stateMachine->getTransactionStateName($row->{'transaction_state_id'});
    $pendingHash->{$row->{'pnp_transaction_id'}} = ($state =~ /_PENDING$/ ? 1 : 0);
  }

  return $pendingHash;
}

#Get processor for pending transaction ID
sub loadPendingTransactionProcessor {
  my $self = shift;
  my $pendingIDs = shift;
  my $options = shift;
  my @values = ();
  my @params = ();

  if (@{$pendingIDs} == 0 && !$options->{'loadAllPending'}) {
    return {};
  }

  foreach my $id (@{$pendingIDs}) {
    push @values,$id;
    push @params, ' t.pnp_transaction_id = ? ';
  }

  my $selectQuery = (@params > 0 ? ' AND ( ' . join (' OR ',@params) . ' ) ' : '' );

  my $select = 'SELECT t.pnp_transaction_id,t.pnp_transaction_ref_id,
                       p.processor_code_handle AS `processor`
                FROM `transaction` t, `processor` p
                WHERE p.id = t.processor_id ' . $selectQuery;
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',$select);
  $sth->execute(@values) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my $data = {};
  my $uuid = new PlugNPay::Util::UniqueID();

  my $procIDObj = new PlugNPay::Processor::ID();
  foreach my $row (@{$rows}){
    $uuid->fromBinary($row->{'pnp_transaction_id'});
    my $info = { 'transactionData' => {
                         'pnp_transaction_id' => $uuid->inHex(),
                         'processor_id' => $procIDObj->getProcessorID($row->{'processor'})
                 },
                 'type' => 'redeem',
                 'processor' => $row->{'processor'},
                 'requestID' => $uuid->inHex(),
                 'priority' => '6'
               };
    if (!defined $data->{$row->{'processor_id'}}) {
      $data->{$procIDObj->getProcessorID($row->{'processor'})} = {};
    }
    $data->{$procIDObj->getProcessorID($row->{'processor'})}{$info->{'request_id'}} = $info;
  }

  return $data;
}

# Load transaction parts #
sub loadCardInformation {
  my $self = shift;
  my $pnpIDs = shift;

  if (ref($pnpIDs) ne 'ARRAY' && ref($pnpIDs) ne 'HASH') {
    $pnpIDs = [$pnpIDs];
  }

  my @params = ();
  foreach my $id (@{$pnpIDs}) {
    push @params,' (pnp_transaction_id = ?) ';
  }

  if (@params > 0) {

    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnp_transaction',q/
                              SELECT card_first_six, card_last_four, card_expiration,
                                     cvv_response, avs_response, pnp_transaction_id
                              FROM card_transaction
                              WHERE / . join(' OR ',@params));
    $sth->execute(@{$pnpIDs}) or die $DBI::errstr;
    my $rows = $sth->fetchall_arrayref({});
    my $idMap = {};

    foreach my $row (@{$rows}) {
      $idMap->{$row->{'pnp_transaction_id'}} = {
        'card_first_six' => $row->{'card_first_six'},
        'card_last_four' => $row->{'card_last_four'},
        'card_expiration' => $row->{'card_expiration'},
        'cvv_response' => $row->{'cvv_response'},
        'avs_response' => $row->{'avs_response'}
      };
    }

    return $idMap;
  } else {
    return {};
  }
}

sub loadTransFlags {
  my $self = shift;
  my $pnpIDs = shift;

  if (ref($pnpIDs) ne 'ARRAY' && ref($pnpIDs) ne 'HASH') {
    $pnpIDs = [$pnpIDs];
  }

  my @params = ();
  foreach my $id (@{$pnpIDs}) {
     push @params,' (f.id = t.transflag_id AND t.transaction_id = ?) ';
  }

  if (@params > 0) {

    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnp_transaction',q/
                             SELECT f.name AS `transflag`, transaction_id
                             FROM transflag f, transaction_transflag t
                             WHERE / . join(' OR ',@params));
    $sth->execute(@{$pnpIDs}) or die $DBI::errstr;
    my $rows = $sth->fetchall_arrayref({});
    my $transFlags = {};
    foreach my $row (@{$rows}) {
      if (ref($transFlags->{$row->{'transaction_id'}}) eq 'ARRAY') {
        push @{$transFlags->{$row->{'transaction_id'}}}, $row->{'transflag'};
      } else {
        $transFlags->{$row->{'transaction_id'}} = [$row->{'transFlag'}];
      }
    }

    return $transFlags;
  } else {
    return {};
  }
}

sub loadAccountCodes {
  my $self = shift;
  my $pnpIDs = shift;

  if (ref($pnpIDs) ne 'ARRAY' && ref($pnpIDs) ne 'HASH') {
    $pnpIDs = [$pnpIDs];
  }

  my @params = ();
  foreach my $id (@{$pnpIDs}) {
    push(@params,' (transaction_id = ?) ');
  }

  if (@params > 0) {

    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnp_transaction',q/
                               SELECT transaction_state_id AS `code_state_id`,
                                      account_code_number, value, transaction_id
                               FROM transaction_account_code
                               WHERE / . join(' OR ',@params));
    $sth->execute(@{$pnpIDs}) or die $DBI::errstr;
    my $rows = $sth->fetchall_arrayref({});
    my $codes = {};
    foreach my $row (@{$rows}) {
      $codes->{$row->{'transaction_id'}}{$row->{'code_state_id'}}{$row->{'account_code_number'}} = $row->{'value'};
    }

    return $codes;
  } else {
    return {};
  }
}

sub loadShippingInformation {
  my $self = shift;
  my $pnpIDs = shift;

  if (ref($pnpIDs) ne 'ARRAY' && ref($pnpIDs) ne 'HASH') {
    $pnpIDs = [$pnpIDs];
  }

  my @params = ();

  foreach my $id (@{$pnpIDs}) {
    push(@params,' (transaction_id = ?) ');
  }

  if (@params > 0) {

    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnp_transaction',q/
                             SELECT full_name AS `name`, address, address2,
                                    city, state, postal_code, country, email,
                                    phone, fax, notes, transaction_id
                             FROM transaction_shipping_information
                             WHERE / . join(' OR ',@params));
    $sth->execute(@{$pnpIDs}) or die $DBI::errstr;
    my $rows = $sth->fetchall_arrayref({});
    my $idMap = {};

    foreach my $row (@{$rows}) {
      $idMap->{$row->{'transaction_id'}} = {
           'name' => $row->{'full_name'},
           'address' => $row->{'address'},
           'address2' => $row->{'address2'},
           'city' => $row->{'city'},
           'state' => $row->{'state'},
           'country' => $row->{'country'},
           'postal_code' => $row->{'postal_code'},
           'email' => $row->{'email'},
           'phone' => $row->{'phone'},
           'fax' => $row->{'fax'},
           'notes' => $row->{'notes'}
      };
    }

    return $idMap;
  } else {
    return {};
  }
}

sub loadBillingInformation {
  my $self = shift;
  my $pnpIDs = shift;

  if (ref($pnpIDs) ne 'ARRAY' && ref($pnpIDs) ne 'HASH') {
    $pnpIDs = [$pnpIDs];
  }

  my @params = ();
  foreach my $id (@{$pnpIDs}) {
    push(@params,' (transaction_id = ?) ');
  }

  if (@params > 0) {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnp_transaction',q/
                              SELECT full_name, address, address2, email,
                                     city, state, postal_code, country,
                                     phone, fax, company, transaction_id
                              FROM transaction_billing_information
                              WHERE / . join(' OR ',@params));
    $sth->execute(@{$pnpIDs}) or die $DBI::errstr;
    my $rows = $sth->fetchall_arrayref({});
    my $idMap = {};

    foreach my $row (@{$rows}) {
      $idMap->{$row->{'transaction_id'}} = {
           'name' => $row->{'full_name'},
           'address' => $row->{'address'},
           'address2' => $row->{'address2'},
           'city' => $row->{'city'},
           'state' => $row->{'state'},
           'country' => $row->{'country'},
           'postal_code' => $row->{'postal_code'},
           'email' => $row->{'email'},
           'phone' => $row->{'phone'},
           'fax' => $row->{'fax'},
           'company' => $row->{'company'}
      };
    }

    return $idMap;
  } else {
    return {};
  }
}

sub loadAdditionalProcessorDetails {
  my $self = shift;
  my $pnpIDs = shift;

  if (ref($pnpIDs) ne 'ARRAY' && ref($pnpIDs) ne 'HASH') {
    $pnpIDs = [$pnpIDs];
  }

  my @params = ();
  foreach my $id (@{$pnpIDs}) {
    push(@params,' ( k.id = d.key_id AND transaction_id = ?) ');
  }

  if (@params > 0) {

    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnp_transaction',q/
                               SELECT d.transaction_state_id AS `detail_state_id`,
                                      k.name, d.value, d.transaction_id
                               FROM transaction_additional_processor_detail_key k, transaction_additional_processor_detail d
                               WHERE / . join(' OR ',@params));
    $sth->execute(@{$pnpIDs}) or die $DBI::errstr;
    my $rows = $sth->fetchall_arrayref({});
    my $idMap = {};

    foreach my $row (@{$rows}) {
      $idMap->{$row->{'transaction_id'}}{$row->{'detail_state_id'}}{$row->{'name'}} = $row->{'value'};
    }

    return $idMap;
  } else {
    return {};
  }
}
# Finish transaction part loading #

# Get response data
sub getReturnedProcessorData {
  my $self = shift;
  my $data = shift;
  my $vehicle = shift;
  my $username = shift;
  my $processorRefIDKey = new PlugNPay::Transaction::DetailKey()->getDetailKeyID('processor_reference_id');
  my $merchantID = new PlugNPay::GatewayAccount::InternalID()->getMerchantID($username);

  my $select = 'SELECT t.authorization_code,t.pnp_transaction_id,t.processor_token,a.value,t.pnp_token
                FROM `transaction` t, transaction_additional_processor_detail a, `order` o
                WHERE a.transaction_id = t.pnp_transaction_id
                  AND o.pnp_order_id = t.pnp_order_id
                  AND (t.processor_token = ?
                       OR (a.key_id = ? AND a.value = ?)
                       OR t.pnp_transaction_id = ?)
                  AND o.merchant_id = ?';


  my $util = new PlugNPay::Util::UniqueID();
  my $pnpRefID = $data->{'pnp_transaction_ref_id'};
  if ($pnpRefID =~ /^[a-fA-F0-9]+$/) {
    $util->fromHex($pnpRefID);

    $pnpRefID = $util->inBinary();
  }

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',$select);
  $sth->execute($data->{'processor_token'},$processorRefIDKey,$data->{'processor_reference_id'},$pnpRefID,$merchantID) or die $DBI::errstr;

  my $rows = $sth->fetchall_arrayref({});
  my $loadedData = $rows->[0];
  my $binaryPNPToken = $loadedData->{'pnp_token'};
  $util->fromBinary($binaryPNPToken);
  $loadedData->{'pnp_token'} = $util->inHex();

  my $processorDetails = $self->loadAdditionalProcessorDetails($pnpRefID);
  $loadedData->{'additional_processor_details'} = $processorDetails->{$pnpRefID};

  return $loadedData;
}

# Transaction info loading
sub getPreviousTransactionState {
  my $self = shift;
  my $transactionID = shift;

  my $id = $self->loadStateID($transactionID);
  my $util = new PlugNPay::Transaction::State();

  return $util->getTransactionStateName($id);
}

sub loadVehicleID {
  my $self = shift;
  my $transactionID = shift;

  if ($transactionID =~ /^[a-fA-F0-9]+$/) {
    my $uuid = new PlugNPay::Util::UniqueID();
    $uuid->fromHex($transactionID);
    $transactionID = $uuid->inBinary();
  }

  my $select = 'SELECT transaction_vehicle_id
                FROM transaction
                WHERE pnp_transaction_id = ?';
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',$select);
  $sth->execute($transactionID) or die $DBI::errstr;
  my $row = $sth->fetchall_arrayref({});

  return $row->[0]{'transaction_vehicle_id'};
}

sub loadStateID {
  my $self = shift;
  my $transactionID = shift;

  if ($transactionID =~ /^[a-fA-F0-9]+$/) {
    my $uuid = new PlugNPay::Util::UniqueID();
    $uuid->fromHex($transactionID);
    $transactionID = $uuid->inBinary();
  }

  my $select = 'SELECT transaction_state_id
                FROM transaction
                WHERE pnp_transaction_id = ?';
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',$select);
  $sth->execute($transactionID) or die $DBI::errstr;
  my $row = $sth->fetchall_arrayref({});

  return $row->[0]{'transaction_state_id'};
}

sub getTransactionSettlementJobs {
  my $self = shift;
  my $pnpIDs = shift;
  if (ref($pnpIDs) ne 'ARRAY' && ref($pnpIDs) ne 'HASH') {
    $pnpIDs = [$pnpIDs];
  }

  my @values = ();
  my @params = ();
  my $uuid = new PlugNPay::Util::UniqueID();
  foreach my $pnpID (@{$pnpIDs}) {
    if ($pnpID =~ /^[0-9a-fA-F]+$/) {
      $uuid->fromHex($pnpID);
      $pnpID = $uuid->inBinary();
    }
    push @params,' ( pnp_transaction_id = ? ) ';
    push @values,$pnpID;
  }

  my $dbs = new PlugNPay::DBConnection();
  if (@params == 0) {
    return {};
  }
  my $sth = $dbs->prepare('pnp_transaction',q/
                            SELECT pnp_transaction_id,job_id
                            FROM mark_settlement_job
                            WHERE / . join(' OR ',@params));
  $sth->execute(@values) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});

  my $response = {};
  foreach my $row (@{$rows}) {
    $uuid->fromBinary($row->{"pnp_transaction_id"});
    my $transID = $uuid->inHex();

    $uuid->fromBinary($row->{'job_id'});
    my $jobID = $uuid->inHex();
    $response->{$transID} = $jobID;
  }

  return $response;
}

####################
# Shared Functions #
####################
sub loadByMerchantOrderID {
  my $self = shift;
  my $orderID = shift;
  my $merchantName = shift;

  #Lets see if this is actually a merchant_id
  if ($merchantName =~ /^\d+$/) {
    my $tempName = new PlugNPay::GatewayAccount::InternalID()->getMerchantName($merchantName);
    $merchantName = (defined $tempName ? $tempName : $merchantName);
  }

  my $transactions = $self->load({'orderID' => $orderID, 'gatewayAccount' => $merchantName});

  my @transArray = ();
  foreach my $key (keys %{$transactions->{$merchantName}}) {
    push @transArray, $transactions->{$merchantName}{$key};
  }

  return \@transArray;
}

sub _convertToTransactionObject {
  my $self = shift;
  my $data = shift;

  # convert the state to a mode
  # TODO maybe: put this into Transaction::State?
  my $mode = $data->{'transaction_state'};
  if ( $mode eq 'INIT' || $mode eq 'POSTAUTH_READY' ) {
    $mode = 'auth';
  } elsif ($mode eq 'POSTAUTH_PENDING') { # postauth pending means the postauth is committed, it has been picked up by a process to send to the processor
    $mode = 'postauth';
  }

  my $procMessage = $data->{'processor_message'} || $data->{'message'};
  my $responseData = {'authorization_code' => substr($data->{'authorization_code'},0,6),
                      'status' => $data->{'status'},
                      'processor_message' => $procMessage
                     };

  my $transaction = new PlugNPay::Transaction($mode, $data->{'transaction_vehicle'});
  my $billingInfo = new PlugNPay::Contact();
  my $shippingInfo = new PlugNPay::Contact();
  my $paymentObj = ($data->{transaction_vehicle} eq 'ach' ? new PlugNPay::OnlineCheck() : new PlugNPay::CreditCard());
  $transaction->setGatewayAccount($data->{'merchant'});
  $transaction->setTransactionState($data->{'transaction_state'});
  $transaction->setPNPToken($data->{'pnp_token'});
  $transaction->setReceiptSendingEmailAddress($data->{'publisher_email'} || '');

  my $token = new PlugNPay::Token();
  my $paymentData = '';
  if ($self->getLoadPaymentData()) {
    if ($data->{'pnp_token'} =~ /^[a-fA-F0-9]+$/) {
      $token->fromHex($data->{'pnp_token'});
    } else {
      $token->fromBinary($data->{'pnp_token'});
    }

    $paymentData = $token->fromToken($token->inHex());
  }

  if ($data->{transaction_vehicle} ne 'ach') {
    my @expData = split ('/',$data->{'card_information'}{'card_expiration'});
    my $constructedMasked = $data->{'card_information'}{'card_first_six'} . '******' . $data->{'card_information'}{'card_last_four'};
    my $masked = $data->{'card_information'}{'masked_number'} || $constructedMasked;
    $paymentObj->setNumber($paymentData);
    $paymentObj->setMaskedNumber($masked);
    $paymentObj->setName($data->{'billing_information'}{'name'});
    $paymentObj->setExpirationMonth($expData[0]);
    $paymentObj->setExpirationYear($expData[1]);
    $transaction->setCreditCard($paymentObj);
    $responseData->{'cvv_response'} = $data->{'card_information'}{'cvv_response'};
    $responseData->{'avs_response'} = $data->{'card_information'}{'avs_response'};
  } else {
    my @check = split(' ',$paymentData);
    my $routing = '';
    my $account = '';
    if (@check > 1) {
      $routing = $check[0];
      $account = $check[1];
    }

    if ($paymentObj->verifyABARoutingNumber($routing)) {
      $paymentObj->setABARoutingNumber($routing);
    } else {
      $paymentObj->setInternationalRoutingNumber($routing);
    }

    $paymentObj->setAccountNumber($account);
    $paymentObj->setAccountType($data->{account_type});
    $paymentObj->setName($data->{'billing_information'}{'name'});
    $transaction->setOnlineCheck($paymentObj);
  }

  $billingInfo->setFullName($data->{'billing_information'}{'name'});
  $billingInfo->setAddress1($data->{'billing_information'}{'address'});
  $billingInfo->setAddress2($data->{'billing_information'}{'address2'});
  $billingInfo->setCity($data->{'billing_information'}{'city'});
  $billingInfo->setState($data->{'billing_information'}{'state'});
  $billingInfo->setPostalCode($data->{'billing_information'}{'postal_code'});
  $billingInfo->setCountry($data->{'billing_information'}{'country'});
  $billingInfo->setCompany($data->{'billing_information'}{'company'});
  $billingInfo->setPhone($data->{'billing_information'}{'phone'});
  $billingInfo->setFax($data->{'billing_information'}{'fax'});
  $billingInfo->setEmailAddress($data->{'billing_information'}{'email'});
  $transaction->setBillingInformation($billingInfo);

  $shippingInfo->setFullName($data->{'shipping_information'}{'name'});
  $shippingInfo->setAddress1($data->{'shipping_information'}{'address'});
  $shippingInfo->setAddress2($data->{'shipping_information'}{'address2'});
  $shippingInfo->setCity($data->{'shipping_information'}{'city'});
  $shippingInfo->setState($data->{'shipping_information'}{'state'});
  $shippingInfo->setPostalCode($data->{'shipping_information'}{'postal_code'});
  $shippingInfo->setCountry($data->{'shipping_information'}{'country'});
  $shippingInfo->setPhone($data->{'shipping_information'}{'phone'});
  $shippingInfo->setFax($data->{'shipping_information'}{'fax'});
  $shippingInfo->setEmailAddress($data->{'shipping_information'}{'email'});
  $transaction->setShippingNotes($data->{'shipping_information'}{'notes'});
  $transaction->setShippingInformation($shippingInfo);
  $transaction->setPNPTransactionID($data->{'pnp_transaction_id'});
  $transaction->setExistsInDatabase(); # only after we've set the pnp transaction id is this safe to do.
  $transaction->setPNPTransactionReferenceID($data->{'pnp_transaction_ref_id'});
  $transaction->setCurrency($data->{'currency'});
  $transaction->setTransactionAmount($data->{'transaction_amount'});
  $transaction->setProcessorDataDetails($data->{'additional_processor_details'});
  foreach my $flag (@{$data->{'transaction_flags'}}){
    $transaction->addTransFlag($flag);
  }
  $transaction->setTaxAmount($data->{'tax_amount'});
  $transaction->setTransactionDateTime($data->{'transaction_date_time'});
  $transaction->setOrderID($data->{'merchant_order_id'}, 1);
  $transaction->setPNPOrderID($data->{'pnp_order_id'});
  $transaction->setAuthorizationCode($data->{'authorization_code'});
  $transaction->setProcessorReferenceID($data->{'additional_processor_details'}{$data->{'transaction_state_id'}}{'processor_reference_id'} || $data->{'reference_number'});
  $transaction->setProcessorToken($data->{'processor_token'});
  $transaction->setVendorToken($data->{'vendor_token'});
  $transaction->setBaseTaxAmount($data->{'tax_amount'} - $data->{'fee_tax'});
  $transaction->setProcessorShortName($data->{'processor'});

  #proper base amounts
  my $baseAmount = $data->{'base_amount'};
  if (!$baseAmount) {
    $baseAmount = $data->{'transaction_amount'} - ($data->{'fee_amount'} ? $data->{'fee_amount'} : 0.00);
  }
  $transaction->setBaseTransactionAmount($baseAmount);

  $transaction->setTransactionAmountAdjustment($data->{'fee_amount'});
  $transaction->setTransactionSettlementTime($data->{'processor_settlement_time'});
  $transaction->setSettlementAmount($data->{'settlement_amount'});
  $transaction->setSettledAmount($data->{'settled_amount'});
  $transaction->setSettledTaxAmount($data->{'settled_tax_amount'});
  $transaction->setHistory($data->{'transaction_history'});
  $transaction->setIPAddress($data->{'ip_address'});

  $transaction->setProcessorShortName($data->{'processor'});
  $transaction->setProcessorMerchantId($data->{'processorMerchantId'});

  if ($data->{'custom_data'} && ref($data->{'custom_data'}) eq 'HASH') {
    $transaction->setCustomData($data->{'custom_data'});
  }

  for(my $i = 1; $i<5; $i++) {
    $transaction->setAccountCode($i,$data->{'account_codes'}{$data->{'transaction_state_id'}}{$i});
  }

  $transaction->setReason($data->{'account_codes'}{$data->{'transaction_state_id'}}{'4'});

  my $extra = {};

  if (defined $data->{'related_transaction'}) {
    foreach my $state (keys %{$data->{'related_transaction'}}) {
      $extra->{$state} = $self->_convertToTransactionObject($data->{'related_transaction'}{$state});
    }
  }

  if (defined $data->{'creation_date_time'}) {
    my $timeObj = new PlugNPay::Sys::Time();
    $timeObj->fromFormat('iso',$data->{'creation_date'});
    $extra->{'creation_date'} = $timeObj->inFormat('db_gm');
  } elsif (defined $data->{'creation_date'}) {
    $extra->{'creation_date'} = $data->{'creation_date'};
  }

  if (defined $data->{'pnp_job_id'}) {
    $extra->{'pnp_job_id'} = $data->{'pnp_job_id'};
    $extra->{'has_settlement_job'} = 1;
  }

  $extra->{'fee_model'} = $data->{'adjustment_model'};
  $extra->{'fee_mode'} = $data->{'adjustment_mode'};
  $extra->{'fee_account'} = $data->{'adjustment_account'};

  if (defined $data->{'batchID'}) {
    $extra->{'batchID'} = $data->{'batchID'};
  }

  if (defined $data->{'batch_number'}) {
    $extra->{'batch_number'} = $data->{'batch_number'};
  }

  if (defined $data->{'batch_time'}) {
    $extra->{'batch_time'} = $data->{'batch_time'};
  }

  $extra->{'response_data'} = $responseData;
  $transaction->setExtraTransactionData($extra);
  my $respObj = $self->makeResponseObj($responseData);
  $transaction->setResponse($respObj);
  if (defined $data->{'fee_amount'}) {
    $transaction->setConvenienceChargeInfoForTransaction({
      'orderID' => $data->{'adjustment_order_id'},
      'gatewayAccount' => $data->{'adjustment_account'}
    });
  }

  return $transaction;
}

sub parseResponseData {
  my $self = shift;
  my $rows = shift;
  my $responses = {};
  foreach my $loaded (@{$rows}) {
    my $response = $self->makeResponseObj($loaded);
    $responses->{$loaded->{'username'}}{$loaded->{'orderid'}} = $response;
  }

  return $responses;
}

#Turn loaded data into transaction object
sub makeTransactionObj {
  my $self = shift;
  my $transactions = shift;

  my $objectifiedTransactions = {};
  foreach my $merchant (keys %{$transactions}) {
    foreach my $transaction (keys %{$transactions->{$merchant}}) {
      $objectifiedTransactions->{$merchant}{$transaction} = $self->_convertToTransactionObject($transactions->{$merchant}{$transaction});
    }
  }

  return $objectifiedTransactions;
}

sub getNewProcessorID {
  my $self = shift;
  my $processor = shift;
  my $procID = new PlugNPay::Processor::ID();

  return $procID->getProcessorReferenceID($processor);
}

sub setLoadLimit {
  my $self = shift;
  my $limitHash = shift;

  $self->{'limitData'} = $limitHash;
}

sub getLoadLimit {
  my $self = shift;
  return $self->{'limitData'};
}

sub makeResponseObj {
  my $self = shift;
  my $loaded = shift;

  my $response = new PlugNPay::Transaction::Response();
  $response->setStatus($loaded->{'status'});
  $response->setSecurityCodeResponse($loaded->{'cvv_response'});
  $response->setAVSResponse($loaded->{'avs_response'});
  $response->setAuthorizationCode($loaded->{'authorization_code'});
  $response->setMessage($loaded->{'error_message'} || $loaded->{'processor_message'} || $loaded->{'message'});
  $response->setTransaction($loaded->{'transaction'}) if (defined $loaded->{'transaction'});
  return $response;
}

1;
