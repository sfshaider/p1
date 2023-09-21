package PlugNPay::GatewayAccount;

################################################################################
# Note:                                                                        #
#   Remember, all functions that start with _ are private.  Do not use them.   #
################################################################################

##############################################
# Fields that apear to be no longer in use:  #
#  freetrans                                 #
#  tds_config                                #
#  password                                  #
#  nlevel                                    #
#  softcart                                  #
#  easycart (only 7 rows use it)             #
#  host and port (not sure about this one)   #
##############################################


use strict;
use PlugNPay::DBConnection;
use PlugNPay::Contact;
use PlugNPay::Currency;
use PlugNPay::CreditCard;
use PlugNPay::Die;
use PlugNPay::Features;
use PlugNPay::GatewayAccount::Services;
use PlugNPay::Logging::DataLog;
use PlugNPay::OnlineCheck;
use PlugNPay::Processor;
use PlugNPay::Processor::Package;
use PlugNPay::Processor::Settings::SECCodes;
use PlugNPay::Processor::Account;
use PlugNPay::RemoteClient;
use PlugNPay::Sys::Time;
use PlugNPay::Transaction::PaymentVehicle;
use PlugNPay::Transaction::PaymentVehicle::Subtype;

use PlugNPay::Util::UniqueList;
use PlugNPay::Util::Memcached;
use PlugNPay::Util::Array qw(inArray);
use PlugNPay::Email;
use PlugNPay::Debug;

use overload '""' => 'getGatewayAccountName';

our @_columns_ = (
  'username','merchemail','billauth','trans_date','testmode',
  'fraud_config','features','subacct','pertran','overtran','chkprocessor',
  'parentacct','noreturns','bypassipcheck','tdsprocessor','agentcode',
  'card_number','monthly','percent','startdate','lastbilled',
  'salesagent','salescommission','paymentmethod','enccardnumber','length',
  'easycart','softcart','recurring','mservices','digdownload','password',
  'passphrase','monthlycommission','pcttype','reason','reseller','cancelleddate',
  'merchant_bank','description','naics','nlevel','extrafees','setupfee','name',
  'company','addr1','addr2','city','state','zip','country','tel','fax','email',
  'techname','techtel','techemail','url','port','host','status','cards_allowed',
  'bank','processor','walletprocessor','limits','contact_date','tds_config','dcc',
  'transcommission','extracommission','chkaccttype','switchtime','ssnum',
  'billauthdate','freetrans','emv_processor'
);

our $_badFieldRegex_;

sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  $self->{'memcached'} = new PlugNPay::Util::Memcached('GatewayAccount');

  my $accountName = shift;
  if ($accountName) {
    # the following are quoted to account for the possibility of an object being passed in.
    $self->load("$accountName");
    $self->getProcessorPackages("$accountName");
  }

  return $self;
}

sub getColumns {
  my @copy = @_columns_;
  return \@copy;
}

sub reload {
  my $self = shift;
  my $gatewayAccountName = $self->getGatewayAccountName();
  $self->load($gatewayAccountName);
}

######################
# Loading and Saving #
######################
sub load {
  my $self = shift;
  my $accountName = shift;
  my $options = shift;

  $accountName =~ s/[^a-z0-9]//g;

  my $cacheKey = "$accountName-accountData";
  my $cachedAccountData = $self->{'memcached'}->get($cacheKey);
  if ($cachedAccountData ne '') {
    debug { message => 'loaded account data from cache', gatewayAccount => $accountName };
    $self->{'rawAccountData'} = $cachedAccountData;
    return;
  }

  my $accountData;

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
  my $columns = '`' . join('`,`', @_columns_) . '`';
  my $sth = $dbh->prepare(qq{
    SELECT $columns FROM customers WHERE username = ?
  });
  $sth->execute($accountName) or die $DBI::ERRSTR;
  my $row = $sth->fetchrow_hashref;

  $self->{'memcached'}->set($cacheKey, $row, 60);

  $self->{'rawAccountData'} = $row;

  $self->_loadSetupsData($accountName);
}

sub _loadSetupsData {
  my $self = shift;
  my $accountName = shift;

  $accountName =~ s/[^a-z0-9]//g;

  my $cacheKey = "$accountName-setupsData";
  my $cachedSetupsData = $self->{'memcached'}->get($cacheKey);
  if ($cachedSetupsData ne '') {
    debug { message => 'loaded setups data from cache', gatewayAccount => $accountName };
    $self->{'rawSetupsData'} = $cachedSetupsData;
    return;
  }

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
  my $sth = $dbh->prepare(qq{
    SELECT trans_date FROM pnpsetups WHERE username = ?
  });
  $sth->execute($accountName) or die $DBI::ERRSTR;
  my $row = $sth->fetchrow_hashref;

  $self->{'memcached'}->set($cacheKey, $row, 60);

  $self->{'rawSetupsData'} = $row;
}

sub save {
  my $self = shift;

  if (!defined $self->getGatewayAccountName() || $self->getGatewayAccountName() eq '') {
    die('No account name specified in GatewayAccount object.');
  }

  my $accountName = $self->getGatewayAccountName();
  my $cacheKey = "$accountName-accountData";

  my @fieldValues = map { $self->_getAccountData($_) || '' } @_columns_;
  my $fieldNamesString = '`' . join('`,`',map { $_ } @_columns_) . '`';
  my $insertPlaceholdersString = join(',',map { '?' } @_columns_);
  my $updateString = join(',',map { $_ . ' = ?' } @_columns_);

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
  my $insert = 'INSERT INTO customers (' . $fieldNamesString . ') VALUES (' . $insertPlaceholdersString . ')';
  my $update = 'UPDATE customers SET ' . $updateString . ' WHERE username = ?';

  my $sth;


  # remove the account from the cache if we change it.
  if ($self->exists) {
    $sth = $dbh->prepare($update) or die($DBI::errstr);
    $sth->execute(@fieldValues, $self->getGatewayAccountName()) or die($DBI::errstr);
    $self->{'memcached'}->delete($cacheKey);
    return 1;
  } else { # insert, also adds row to pnpsetups by calling _saveSetupsData
    $sth = $dbh->prepare($insert) or die($DBI::errstr);
    $sth->execute(@fieldValues) or die($DBI::errstr);
    $self->_saveSetupsData();
    my $email = new PlugNPay::Email('legacy');
    $email->setFormat('text');
    $email->setTo('applications@plugnpay.com');
    $email->setFrom('noreply@plugnpay.com');
    $email->setSubject('Plug and Pay - ' . $self->getReseller() . ' - Reseller App Notification');
    $email->setContent(
      sprintf(q/
reseller: %s
username: %s/,
      $self->getReseller(),
      $self->getGatewayAccountName())
    );
    $email->send();

    return 1;
  }
}

# TODO this should update too?
sub _saveSetupsData {
  my $self = shift;

  if (!defined $self->getGatewayAccountName() || $self->getGatewayAccountName() eq '') {
    die('No account name specified in GatewayAccount object.');
  }

  my $accountName = $self->getGatewayAccountName();
  my $cacheKey = "$accountName-setupsData";

  my $gatewayAccountName = $self->getGatewayAccountName();
  my $submitDate = $self->getCreationDate();
  my $dbs = new PlugNPay::DBConnection();
  my $insert = 'INSERT IGNORE INTO pnpsetups (username,submit_date) VALUES (?,?)';
  eval {
    $dbs->executeOrDie('pnpmisc',$insert,[$gatewayAccountName,$submitDate]);
  };
  $self->{'memcached'}->delete($cacheKey);
}

sub delete {
  # this MUST be called statically.
  my $username = shift;

  my $accountDataCacheKey = "$username-accountData";
  my $setupsCacheKey = "$username-setupsData";

  my $dbs = PlugNPay::DBConnection();
  $dbs->executeOrDie('pnpmisc',q/
    DELETE FROM customers WHERE username = ?
  /,[$username]);

  my $memcached = new PlugNPay::Util::Memcached('GatewayAccount');
  $memcached->delete($accountDataCacheKey);
  $memcached->delete($setupsCacheKey);

  PlugNPay::GatewayAccount::Services::delete($username);
}

sub exists {
  my $self = shift;
  my $account = shift;

  # the following is so that it can be called without having an instance of GatewayAccount
  if (!defined $account) {
    if (ref($self)) {
      $account = $self->getGatewayAccountName();
    } else {
      $account = $self;
    }
  }

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
  my $sth = $dbh->prepare(q/
    SELECT count(username) as `exists`
    FROM customers
    WHERE username = ?
  /);

  $sth->execute($account);

  my $results = $sth->fetchall_arrayref({});
  if ($results && $results->[0]) {
    return ($results->[0]{'exists'} == 1);
  }
}

sub setReseller {
  my $self = shift;
  my $reseller = lc shift;
  $reseller =~ s/[^a-z0-9]//g;
  $self->_setAccountData('reseller',$reseller);
}

sub getReseller {
  my $self = shift;
  return $self->_getAccountData('reseller');
}

sub setCreationDate {
  my $self = shift;
  my $today = shift || new PlugNPay::Sys::Time()->inFormat('yyyymmdd');
  $self->_setSetupsData('submit_date',$today);
}

sub getCreationDate {
  my $self = shift;
  my $creationDate = $self->_getSetupsData('submit_date');
  if (!$creationDate) {
    $self->setCreationDate();
  }
  return $self->_getSetupsData('submit_date');
}

sub setCobrand {
  my $self = shift;
  my $cobrand = shift;
  $cobrand =~ s/[^A-Za-z0-9_-]//g;
  my $features = $self->getFeatures();
  $features->set('cobrand',$cobrand);
}

sub getCobrand {
  my $self = shift;
  my $features = $self->getFeatures();
  return $features->get('cobrand');
}

sub checkMid {
  my $self = shift;
  my $validMid = 0;
  my $account = {
    'gatewayAccount' => $self->getGatewayAccountName(),
    'processorName'  => $self->getCardProcessor()
  };

  eval {
    my $processorAccount = new PlugNPay::Processor::Account($account);
    $validMid = $processorAccount->isMIDUnique($self->getGatewayAccountName());
  };

  if ($@) {
    my $datalog = new PlugNPay::Logging::DataLog({'collection' => 'gatewayaccount'});
    $datalog->log({
      'accountData' => $account,
      'error' => $@,
      'function' => 'PlugNPay::GatewayAccount::checkMid'
    });
  }

  return $validMid;
}

###########################################################################################
# The following two methods are for compatibility with a previous version of this module. #
###########################################################################################
sub getCreditCardProcessor {
  my $self = shift;
  return $self->getCardProcessor();
}

sub getOnlineCheckProcessor {
  my $self = shift;
  return $self->getCheckProcessor();
}

sub getACHProcessor {
  my $self = shift;
  return $self->getCheckProcessor();
}

sub getProcessorByProcMethod {
  my $self = shift;
  my $procMethod = shift;

  if ($procMethod eq 'ach') {
    return $self->getACHProcessor();
  } elsif ($procMethod eq 'wallet') {
    return $self->getWalletProcessor();
  } elsif ($procMethod eq 'emv') {
    return $self->getEmvProcessor();
  }

  return $self->getCardProcessor();
}

###################
# Package methods #
###################
sub getProcessorPackages {
  my $self = shift;
  my $username = shift || $self->getGatewayAccountName();
  my $data = $self->{'processorPackages'};

  if (!$data || ref($data) ne 'ARRAY') {
    my $processorList = [
               $self->getCheckProcessor(),
               $self->getCardProcessor(),
               $self->getTDSProcessor(),
               $self->getWalletProcessor(),
               $self->getEmvProcessor()
    ];

    my $packageHandler = new PlugNPay::Processor::Package();
    $data = $packageHandler->loadMultipleProcessors($processorList);

  }

  foreach my $row (@{$data}) {
    if ($row->{'package_name'} eq 'PlugNPay::Processor::Route' ) {
      $self->setUnifiedProcessing();
    }
  }

  $self->setProcessorPackages($data);
  return $data;
}

sub setProcessorPackages {
  my $self = shift;
  my $processorPackages = shift;

  if (ref($processorPackages) eq 'ARRAY') {
    $self->{'processorPackages'} = $processorPackages;
  }
}

sub usesUnifiedProcessing {
  my $self = shift;
  my $usesProcessing = $self->{'usesNewProcessing'};

  #This if will only be satisfied if load wasn't called.
  if ($usesProcessing != 1 || $usesProcessing != 0) {
    $self->getProcessorPackages($self->getGatewayAccountName());
    $usesProcessing = $self->{'usesNewProcessing'};
  }

  return $usesProcessing || 0;
}

sub setUnifiedProcessing {
  my $self = shift;
  $self->{'usesNewProcessing'} = 1;
}

sub setLegacyProcessing {
  my $self = shift;
  $self->{'usesNewProcessing'} = 0;
}

#############################
# Processor related methods #
#############################
sub getCardProcessor {
  my $self = shift;
  return $self->_getAccountData('processor');
}

sub setCardProcessor {
  my $self = shift;
  my $cardProcessor = shift;
  $self->_setAccountData('processor',$cardProcessor);
}

sub getCheckProcessor {
  my $self = shift;
  return $self->_getAccountData('chkprocessor');
}

sub setCheckProcessor {
  my $self = shift;
  my $checkProcessor = shift;
  $self->_setAccountData('chkprocessor',$checkProcessor);
}

sub setTDSProcessor {
  my $self = shift;
  my $tdsProcessor = shift;
  $self->_setAccountData('tdsprocessor',$tdsProcessor);
}

sub getTDSProcessor {
  my $self = shift;
  my $tdsProcessor = shift;
  $self->_getAccountData('tdsprocessor');
}

sub setWalletProcessor {
  my $self = shift;
  my $walletProcessor = shift;
  $self->_setAccountData('walletprocessor',$walletProcessor);
}

sub getWalletProcessor {
  my $self = shift;
  return $self->_getAccountData('walletprocessor');
}

sub setEmvProcessor {
  my $self = shift;
  my $emvProcessor = shift;
  $self->_setAccountData('emv_processor',$emvProcessor);
}

sub getEmvProcessor {
  my $self = shift;
  return $self->_getAccountData('emv_processor');
}

sub getProcessingType {
  my $self = shift;
  return "";
}

sub setProcessingType {
  # do nothing.
}

sub setAgentCode {
  my $self = shift;
  my $agentCode = shift;
  $self->_setAccountData('agentcode', $agentCode);
}

sub getAgentCode {
  my $self = shift;
  return $self->_getAccountData('agentcode');
}

sub setBillAuthorization {
  my $self = shift;
  my $auth = lc shift | '';

  $self->_setAccountData('billauth', $auth);
}

sub getBillAuthorization {
  my $self = shift;
  return $self->_getAccountData('billauth');
}

sub setMonthly {
  my $self = shift;
  my $monthly = shift;

  $self->_setAccountData('monthly',$monthly);
}

sub getMonthly {
  my $self = shift;

  return $self->_getAccountData('monthly');
}

sub setPerTransaction {
  my $self = shift;
  my $percent = shift;

  $self->_setAccountData('pertran',$percent);
}

sub getPerTransaction {
  my $self = shift;
  return $self->_getAccountData('pertran');
}

sub setOverTransaction {
  my $self = shift;
  my $over = shift;
  $self->_setAccountData('overtran', $over);
}

sub getOverTransaction {
  my $self = shift;
  $self->_getAccountData('overtran');
}

sub setPercent {
  my $self = shift;
  my $percent = shift;

  $percent =~ s/[^0-9.]//g;

  $self->_setAccountData('percent',$percent);
}

sub getPercent {
  my $self = shift;
  return $self->_getAccountData('percent');
}

sub setStartDate {
  my $self = shift;
  my $date = shift;

  $self->_setAccountData('startdate',$date);
}

sub getStartDate {
  my $self = shift;
  return $self->_getAccountData("startdate");
}

sub setLastBilled {
  my $self = shift;
  my $lastBilled = shift;
  $self->_setAccountData('lastbilled', $lastBilled);
}

sub getLastBilled {
  my $self = shift;
  return $self->_getAccountData('lastbilled');
}

sub setMonthlyCommission {
  my $self = shift;
  my $monthlyCommission = shift;
  $self->_setAccountData('monthlycommission', $monthlyCommission);
}

sub getMonthlyCommission {
  my $self = shift;
  return $self->_getAccountData('monthlycommission');
}

sub setSalesCommission {
  my $self = shift;
  my $salesCommission = shift;
  $self->_setAccountData('salescommission', $salesCommission);
}

sub getSalesCommission {
  my $self = shift;
  return $self->_getAccountData('salescommission');
}

sub setTransactionCommission {
  my $self = shift;
  my $transactionCommission = shift;
  $self->_setAccountData('transcommission', $transactionCommission);
}

sub getTransactionCommission {
  my $self = shift;
  return $self->_getAccountData('transcommission');
}

sub setExtraCommission {
  my $self = shift;
  my $extraCommission = shift;
  $self->_setAccountData('extracommission', $extraCommission);
}

sub getExtraCommission {
  my $self = shift;
  return $self->_getAccountData('extracommission');
}

sub setTransDate {
  my $self = shift;
  my $date = shift;

  $self->_setAccountData('trans_date',$date);
}

sub setBillAuthDate {
  my $self = shift;
  my $date = shift;

  $self->_setAccountData('billauthdate',$date);
}

sub getBillAuthDate {
  my $self = shift;
  return $self->_getAccountData('billauthdate');
}


sub setGatewayAccountName {
  my $self = shift;
  my $name = lc shift;
  $name =~ s/[^a-z0-9]//g;
  $self->_setAccountData('username',$name);
}

sub getGatewayAccountName {
  my $self = shift;
  return $self->_getAccountData('username');
}

sub getPaymentMethod{
  my $self = shift;

  return $self->_getAccountData('paymentmethod');
}

sub setPaymentMethod{
  my $self = shift;
  my $method = shift;
  $method =~ s/[^a-zA-Z]//g;
  $self->_setAccountData('paymentmethod',$method);
}

sub getPaymentVehicles {
  my $self = shift;

  my $vehicleInfo = new PlugNPay::Transaction::PaymentVehicle();

  my @vehicles;

  if ((defined $self->getCardProcessor() && $self->getCardProcessor() ne '') ||
      (defined $self->getTDSProcessor()  && $self->getTDSProcessor ne '')) {
    $vehicleInfo->load('CARD');
    push @vehicles,$vehicleInfo->getID();
  }

  if (defined $self->getCheckProcessor() && $self->getCheckProcessor() ne '') {
    $vehicleInfo->load('ACH');
    push @vehicles,$vehicleInfo->getID();
  }

  if (defined $self->getWalletProcessor() && $self->getWalletProcessor() ne '') {
    $vehicleInfo->load('WALLET');
    push @vehicles,$vehicleInfo->getID();
  }

  return \@vehicles;
}

sub getPaymentVehicleSubtypes {
  my $self = shift;

  my $vehicles = $self->getPaymentVehicles();

  my $vehicleSubtypeInfo = new PlugNPay::Transaction::PaymentVehicle::Subtype();

  my @subtypes;

  foreach my $vehicleID (@{$vehicles}) {
    my $vehicleSubtypes = $vehicleSubtypeInfo->getSubtypesForVehicle($vehicleID);
    foreach my $subtype (@{$vehicleSubtypes}) {
      push @subtypes,$subtype->{'id'};
    }
  }
  return \@subtypes;
}

##########################################################################
# Internal status methods                                                #
# These should not be called directly, use the set[STATUS] methods below #
##########################################################################
sub _setStatus {
  my $self = shift;
  return if (ref($self) ne caller());
  my $status = shift;

  # prevent uncancelling an account
  if (!$self->isCancelled() || $self->getForceStatusChange()) {
    $self->_setAccountData('status',$status);
  }
}

sub getStatus {
  my $self = shift;
  return $self->_getAccountData('status');
}

sub setNAICS {
  my $self = shift;
  my $naics = shift;
  $self->_setAccountData('naics', $naics);
}

sub getNAICS {
  my $self = shift;
  return $self->_getAccountData('naics');
}

sub setDescription {
  my $self = shift;
  my $description = shift;
  $self->_setAccountData('description', $description);
}

sub getDescription {
  my $self = shift;
  return $self->_getAccountData('description');
}

sub setForceStatusChange {
  my $self = shift;
  my $force = shift || 0;
  $self->{'force_status_change'} = $force;
}

sub getForceStatusChange {
  my $self = shift;
  return $self->{'force_status_change'} || 0;
}

sub _setStatusReason {
  my $self = shift;
  return if (ref($self) ne caller());
  my $reason = shift;

  $self->_setAccountData('reason',$reason);
}

sub getStatusReason {
  my $self = shift;
  return $self->_getAccountData('reason');
}

###################
# Contact methods #
###################
sub setMainContact {
  my $self = shift;
  my $contact = shift;
  $self->_setAccountData('name',$contact->getFullName());
  $self->_setAccountData('company',$contact->getCompany());
  $self->_setAccountData('addr1',$contact->getAddress1());
  $self->_setAccountData('addr2',$contact->getAddress2());
  $self->_setAccountData('city',$contact->getCity());
  $self->_setAccountData('country',$contact->getCountry());
  $self->_setAccountData('zip',$contact->getPostalCode());
  $self->_setAccountData('state',$contact->getState());
  $self->_setAccountData('tel',$contact->getPhone());
  $self->_setAccountData('fax',$contact->getFax());
  $self->_setAccountData('merchemail',$contact->getEmailAddress());
}

sub getMainContact {
  my $self = shift;
  my $contact = new PlugNPay::Contact();
  # this seems inefficient but it's the only way to ensure
  # that the contact object and the contact data stay in
  # sync
  $contact->setFullName($self->_getAccountData('name'));
  $contact->setCompany($self->_getAccountData('company'));
  $contact->setAddress1($self->_getAccountData('addr1'));
  $contact->setAddress2($self->_getAccountData('addr2'));
  $contact->setCity($self->_getAccountData('city'));
  $contact->setCountry($self->_getAccountData('country'));
  $contact->setState($self->_getAccountData('state'));
  $contact->setPostalCode($self->_getAccountData('zip'));
  $contact->setPhone($self->_getAccountData('tel'));
  $contact->setFax($self->_getAccountData('fax'));
  $contact->setEmailAddress($self->_getAccountData('merchemail'));
  return $contact;
}

sub setBillingContact {
  my $self = shift;
  my $contact = shift;
  $self->{'billingContact'} = $contact;
  $self->_setAccountData('email',$contact->getEmailAddress());
}


sub getBillingContact {
  my $self = shift;
  my $contact = $self->{'billingContact'};
  if (!$contact) {
    $contact = new PlugNPay::Contact();
  }
  $contact->setEmailAddress($self->_getAccountData('email'));
  return $contact;
}

sub setTechnicalContact {
  my $self = shift;
  my $contact = shift;
  $self->{'technicalContact'} = $contact;
  $self->_setAccountData('techname',$contact->getFullName());
  $self->_setAccountData('techtel',$contact->getPhone());
  $self->_setAccountData('techemail',$contact->getEmailAddress());
}

sub getTechnicalContact {
  my $self = shift;
  my $contact = $self->{'technicalContact'};
  if (!$contact) {
    $contact = new PlugNPay::Contact();
  }
  $contact->setFullName($self->_getAccountData('techname'));
  $contact->setPhone($self->_getAccountData('techtel'));
  $contact->setEmailAddress($self->_getAccountData('techemail'));
  return $contact;
}

sub getCompanyName {
  my $self = shift;
  return $self->getMainContact()->getCompany();
}

sub setCompanyName {
  my $self = shift;
  my $companyName = shift;
  my $contact = $self->getMainContact();
  $contact->setCompany($companyName);
  $self->setMainContact($contact);
}

sub setURL {
  my $self = shift;
  my $url = shift;
  $self->_setAccountData('url',$url);
}

sub getURL {
  my $self = shift;
  return$self->_getAccountData('url');
}

################################
# Merchant Account Information #
################################
sub setMerchantBank {
  my $self = shift;
  my $bank = shift;
  $self->_setAccountData('merchant_bank',$bank);
}

sub getMerchantBank {
  my $self = shift;
  $self->_getAccountData('merchant_bank');
}

sub setMerchantID {
  die('use PlugNPay::Processor::Account to set MID');
}

sub getMerchantID {
  die('use PlugNPay::Processor::Account to load MID');
}

sub setTerminalID {
  die('use PlugNPay::Processor::Account to set TID');
}

sub getTerminalID {
  die('use PlugNPay::Processor::Account to load TID');
}

sub getSECCodes {
  my $self = shift;

  my $processor = new PlugNPay::Processor({shortName => $self->getOnlineCheckProcessor()});
  my $secCodes = new PlugNPay::Processor::Settings::SECCodes({gatewayAccount => $self,
                                                                 processorID => $processor->getID()});
  return @{$secCodes->getSECCodes()};
}

sub getCardTypes {
  my $self = shift;
  return $self->getAllowedCardTypes();
}

sub getAllowedCardTypes {
  my $self = shift;

  my %allowedCardTypes = map { lc $_ => 1} @{$self->getFeatures()->getFeatureValues('card-allowed')};
  my @types = keys %allowedCardTypes;
  return \@types;
}

sub setAllowedCardTypes {
  my $self = shift;
  my $typeArrayRef = shift;

  my $features = $self->getFeatures();
  $features->setFeatureValues('card-allowed',$typeArrayRef);
  $self->_setAccountData('features',$features->getFeatureString());
}

sub addAllowedCardType {
  my $self = shift;
  my $type = lc shift;
  $type =~ s/[\s,=]//g;

  my %allowedTypes = map { $_ => 1 } @{$self->getAllowedCardTypes()};
  $allowedTypes{$type} = 1;
  my @allowedTypesArray = keys %allowedTypes;
  $self->setAllowedCardTypes(\@allowedTypesArray);
}

sub removeAllowedCardType {
  my $self = shift;
  my $type = lc shift;

  my %allowedTypes = map { $_ => 1 } @{$self->getAllowedCardTypes()};
  delete $allowedTypes{$type};
  my @allowedTypesArray = keys %allowedTypes;
  $self->setAllowedCardTypes(\@allowedTypesArray);
}

sub setCardsAllowed {
  my $self = shift;
  my $cardsAllowed = shift;
  $self->_setAccountData('cards_allowed', $cardsAllowed);
}

sub getCardsAllowed {
  my $self = shift;
  return $self->_getAccountData('cards_allowed');
}

sub setContactDate {
  my $self = shift;
  my $contactDate = shift;
  $self->_setAccountData('contact_date', $contactDate);
}

sub getContactDate {
  my $self = shift;
  return $self->_getAccountData('contact_date');
}

sub setBank {
  my $self = shift;
  my $bank = shift;
  $self->_setAccountData('bank',$bank);
}

sub getBank {
  my $self = shift;
  return $self->_getAccountData('bank');
}

################################
# Merchant Billing Information #
################################
sub getPaymentInitialOrderId {
  my $self = shift;
  die('Use PlugNPay::Recurring::PaymentSource')
}

sub getPaymentType {
  my $self = shift;
  die('Use PlugNPay::Recurring::PaymentSource')
}

sub setPaymentRoutingNumber {
  my $self = shift;
  die('Use PlugNPay::Recurring::PaymentSource')
}

sub getPaymentRoutingNumber {
  my $self = shift;
  die('Use PlugNPay::Recurring::PaymentSource')
}

sub setPaymentAccountNumber {
  my $self = shift;
  die('Use PlugNPay::Recurring::PaymentSource')
}

sub getPaymentAccountNumber {
  my $self = shift;
  die('Use PlugNPay::Recurring::PaymentSource')
}

sub setPaymentAccountType {
  my $self = shift;
  die('Use PlugNPay::Recurring::PaymentSource')
}

sub getPaymentAccountType {
  my $self = shift;
  die('Use PlugNPay::Recurring::PaymentSource')
}

sub setPaymentSECCode {
  my $self = shift;
  die('Use PlugNPay::Recurring::PaymentSource')
}

sub getPaymentSECCode {
  my $self = shift;
  die('Use PlugNPay::Recurring::PaymentSource')
}

sub setAccountType {
  my $self = shift;
  die('Use PlugNPay::Recurring::PaymentSource')
}

sub getAccountType {
  my $self = shift;
  die('Use PlugNPay::Recurring::PaymentSource')
}

sub setPaymentCreditCard {
  my $self = shift;
  die('Use PlugNPay::Recurring::PaymentSource')
}

sub getPaymentCreditCard {
  my $self = shift;
  die('Use PlugNPay::Recurring::PaymentSource')
}

sub setPaymentCheckingInfo {
  my $self = shift;
  die('Use PlugNPay::Recurring::PaymentSource')
}

sub getPaymentCheckingInfo {
  my $self = shift;
  die('Use PlugNPay::Recurring::PaymentSource')
}

sub setOrderID {
  my $self = shift;
  my $value = shift;
  $self->_setAccountData('orderid', $value);
}

sub getOrderID {
  my $self = shift;
  return $self->_getAccountData('orderid') || '';
}

sub setAccountCode4 {
  my $self = shift;
  my $value = shift;
  $self->_setAccountData('acctcode4',$value);
}

sub getAccountCode4 {
  my $self = shift;
  return $self->_getAccountData('acctcode4') || '';
}

#######################################
# Billing Details: Fees, Limits, etc. #
#######################################
sub getLimits {
  my $self = shift;
  my $limits = $self->_getAccountData('limits');

  return $limits;
}

sub setLimits {
  my $self = shift;
  my $limits = shift;

  $self->_setAccountData('limits',$limits);
}

sub setSetupFee {
  my $self = shift;
  my $fee = shift;
  $fee =~ s/[^0-9\.]//g;
  $self->_setAccountData('setupfee',$fee);
}

sub getSetupFee {
  my $self = shift;
  my $fee = $self->_getAccountData('setupfee');
  $fee =~ s/[^0-9\.]//g;
  return $fee;
}

sub setExtraFees {
  my $self = shift;
  my $fee = shift;
  $fee =~ s/[^0-9\.]//g;
  $self->_setAccountData('extrafees',$fee);
}

sub getExtraFees {
  my $self = shift;
  my $fee = $self->_getAccountData('extrafees');
  $fee =~ s/[^0-9\.]//g;
  return $fee;
}

sub setBillingMode {
  my $self = shift;
  my $type = shift;

  $type =~ /(trans|percent)/;
  $type = $1;

  $self->_setAccountData('pcttype',$type);
}

sub getBillingMode {
  my $self = shift;
  return $self->_getAccountData('pcttype');
}


########################################
# Capabilities Permissions, and Status #
########################################
sub isActive {
  my $self = shift;
  return !$self->isCancelled() && !$self->isPending();
}

sub canProcessTransactions {
  my $self = shift;
  return $self->isActive() && !$self->isOnHold();
}

sub canProcessAuthorizations {
  my $self = shift;
  return ($self->canProcessTransactions() && $self->getProcessingType() ne 'returnonly');
}

sub canProcessReturns {
  my $self = shift;
  return $self->canProcessTransactions();
}

sub setCanProcessCredits {
  my $self = shift;
  my $canProcess = shift;
  # this looks funky but the way it works is any value that's truthy other than "no" will mean yes
  $self->_setAccountData('noreturns', $canProcess && $canProcess ne 'no' ? '' : 'yes');
}

sub canProcessCredits {
  my $self = shift;
  return ($self->_getAccountData('noreturns') ne 'yes');
}

sub canProcessCreditFundTransfers {
  my $self = shift;
  return ($self->getCreditCardProcessor() eq 'payvision' && $self->getFeatures->get('enableCFT') eq '1');
}

sub setCanBypassIpCheck {
  my $self = shift;
  my $canBypass = shift;
  $self->_setAccountData('bypassipcheck', $canBypass);
}

sub canBypassIpCheck {
  my $self = shift;
  return ($self->_getAccountData('bypassipcheck') eq 'yes');
}

sub setDebug {
  my $self = shift;
  my $reason = shift || '';

  $self->_setStatus('debug');
  $self->_setStatusReason($reason);
}

sub isDebug {
  my $self = shift;
  return ($self->getStatus() eq 'debug');
}

sub setAsReseller {
  my $self = shift;
  my $reason = shift || '';
  $self->_setStatus('reseller');
  $self->_setStatusReason($reason);
}

sub isReseller {
  my $self = shift;
  return ($self->getStatus() eq 'reseller');
}

sub setLive {
  my $self = shift;
  my $reason = shift || '';
  $self->_setStatus('live');
  $self->_setStatusReason($reason);
}

sub isLive {
  my $self = shift;
  return ($self->getStatus() eq 'live');
}

sub setFraud {
  my $self = shift;
  my $reason = shift || '';
  $self->_setStatus('fraud');
  $self->_setStatusReason($reason);
}

sub isFraud {
  my $self = shift;
  return ($self->getStatus() eq 'fraud');
}

sub setPending {
  my $self = shift;
  my $reason = shift || '';
  $self->_setStatus('pending');
  $self->_setStatusReason($reason);
}

sub isPending {
  my $self = shift;
  return ($self->getStatus() eq 'pending');
}

sub setTest {
  my $self = shift;
  my $reason = shift || '';
  $self->_setStatus('test');
  $self->_setStatusReason($reason);
}

sub isTest {
  my $self = shift;
  return ($self->getStatus() eq 'test');
}

sub setCancelled {
  my $self = shift;
  my $reason = shift || '';
  my $today = new PlugNPay::Sys::Time()->inFormat('yyyymmdd');
  $self->_setStatus('cancelled');
  $self->_setStatusReason($reason);
  $self->_setAccountData('cancelleddate',$today);
}

sub isCancelled {
  my $self = shift;
  return ($self->getStatus() eq 'cancelled');
}

sub setCancelledDate {
  my $self = shift;
  my $cancelleddate = shift;
  $self->_setAccountData('cancelleddate', $cancelleddate);
}

sub getCancelledDate {
  my $self = shift;
  return $self->_getAccountData('cancelleddate');
}

sub setOnHold {
  my $self = shift;
  my $reason = shift || '';
  $self->_setStatus('hold');
  $self->_setStatusReason($reason);
}

sub isOnHold {
  my $self = shift;
  return ($self->getStatus() eq 'hold');
}

sub canProcessCreditCards {
  my $self = shift;
  return $self->canProcessCards();
}

sub canProcessCards {
  my $self = shift;
  if ($self->getCardProcessor() ne '') {
    return 1;
  }
  return 0;
}

sub canProcessEMVTransactions {
  my $self = shift;
  return $self->canProcessEMV();
}

sub canProcessEMV {
  my $self = shift;
  my $canProcessEMV = 0;
  if($self->getEmvProcessor() ne '') {
    $canProcessEMV = new PlugNPay::Processor({'shortName' => $self->getEmvProcessor()})->getAllowsEMV();
  }
  return $canProcessEMV;
}

sub canProcessOnlineChecks {
  my $self = shift;
  return $self->canProcessChecks();
}

sub canProcessChecks {
  my $self = shift;
  if ($self->getCheckProcessor() ne '') {
    return 1;
  }
  return 0;
}

############
# Currency #
############
sub setDefaultCurrency {
  my $self = shift;
  my $currency = shift;
  $currency =~ s/[^a-zA-Z]//g;
  $currency = $self->_checkCurrencyName($currency);
  $self->_saveProcessorAccountData('currency',$currency);
  $self->{'processorAccountData'}{'currency'} = $currency;
  $self->refactorLog(join('->',caller()), 'setDefaultCurrency');
}

sub getDefaultCurrency {
  my $self = shift;
  my $currency = $self->{'processorAccountData'}{'currency'};

  if (!$currency) {
    $currency = $self->_loadProcessorAccountData('currency') || 'usd';
    $self->{'processorAccountData'}{'currency'} = $currency;
  }

  $self->refactorLog(join('->',caller()), 'getDefaultCurrency');
  return $currency;
}

sub _checkCurrencyName {
  my $self = shift;
  my $currency = uc shift;

  if (length($currency) == 3){
    my $currencyObj = new PlugNPay::Currency($currency);
    return $currencyObj->getCurrencyCode();
  }
  else {
    $self->{'errors'} = 1;
    return '';
  }
}

sub setDCCAccount {
  my $self = shift;
  my $dccAccount = lc shift;
  $dccAccount =~ s/[^a-z0-9]//g;
  $self->_setAccountData('dcc',$dccAccount);
}

sub getDCCAccount {
  my $self = shift;
  return $self->_getAccountData('dcc');
}

sub getCurrenciesAllowed {
  my $self = shift;
  return $self->getFeatures->get('curr_allowed');
}

sub setParentAccount {
  my $self = shift;
  my $parentAcct = shift;
  $self->_setAccountData('parentacct', $parentAcct);
}

sub getParentAccount {
  my $self = shift;
  return $self->_getAccountData('parentacct');
}

sub setSubAccount {
  my $self = shift;
  my $subacct = shift;
  $self->_setAccountData('subacct', $subacct);
}

sub getSubAccount {
  my $self = shift;
  return $self->_getAccountData('subacct');
}

####################################
# Additional Settings and Features #
####################################
sub getSendingEmailAddress {
  my $self = shift;
  my $features = $self->getFeatures();
  return $features->get('pubemail');
}

sub getRawFeatures {
  my $self = shift;
  return $self->getFeatures()->getFeatureString();
}

sub getFeatures {
  my $self = shift;
  my $features = new PlugNPay::Features($self->getGatewayAccountName(),'general');
  return $features;
}

sub setFeatures {
  my $self = shift;
  my $features = shift;

  if (ref($features) =~ /^PlugNPay::Features/) {
    $features = $features->getFeatureString();
  }

  $self->getFeatures()->parseFeatureString($features); # to update cached copy of features object
  $self->_setAccountData('features',$features); # so features gets saved
}

sub setFraudConfig {
  my $self = shift;
  my $fraudConfig = lc shift;

  if (ref($fraudConfig) =~ /^PlugNPay::Features/) {
    $fraudConfig = $fraudConfig->getFeatureString();
  }

  $self->getParsedFraudConfig()->parseFeatureString($fraudConfig); # to update cached copy of fraud config object
  $self->_setAccountData('fraud_config',$fraudConfig); # so fraud config gets saved
}

sub getParsedFraudConfig {
  my $self = shift;
  my $fraudConfig = new PlugNPay::Features($self->getGatewayAccountName(),'fraud_config');
  $fraudConfig->parseFeatureString($self->_getAccountData('fraud_config'));

  return $fraudConfig;
}

sub getFraudConfig {
  my $self = shift;
  return $self->_getAccountData('fraud_config');
}

sub inheritFrom {
  my $self = shift;
  my $accountName = shift;

  my $parent;

  eval {
    $parent = new PlugNPay::GatewayAccount($accountName);
  };

  if($@) {
    my $datalog = new PlugNPay::Logging::DataLog({'collection' => 'gatewayaccount'});
    $datalog->log({
      'error' => "Unable to create the gateway account, caused by: $@",
      'username' => $accountName
    });
    die("Unable to create gateway account, caused by: $@");
  }

  my $inheritList = $parent->getFeatures()->getFeatureValues('inherit');
  my %inherit = map { $_ => 1 } @{$inheritList};

  # inherit from should die if _inheritRemoteClient ip dies.
  if ($inherit{'features'}) {
    $self->_inheritFeatures($parent);
  }

  if ($inherit{'ip'}) {
    eval {
      $self->_inheritRemoteClientIP($parent);
    };
    if($@) {
      my $datalog = new PlugNPay::Logging::DataLog({'collection' => 'gatewayaccount'});
      $datalog->log({
        'error' => "Unable to inherit remote ip settings, caused by: $@",
        'parent' => $parent->getGatewayAccountName(),
        'inheritor' => $self->getGatewayAccountName()
      });
      die("Could not inherit ip, caused by: $@");
    }
  }
}

sub _inheritFeatures {
  my $self = shift;
  my $parent = shift;

  # get feature details needed to copy features correctly
  my $parentSetFeatures = new PlugNPay::Util::UniqueList($parent->getFeatures()->getSetFeatures());
  my $ignoreFeatures = $parent->getFeatures()->getNonInheritableFeatureNames();

  # remove features that are not supposed to be inherited.
  foreach my $ignoredFeature (@{$ignoreFeatures}) {
    $parentSetFeatures->removeItem($ignoredFeature);
  }

  my $features = $self->getFeatures();

  foreach my $feature ($parentSetFeatures->getArray()) {
    if ($feature !~ /^reseller_/) {
      $features->set($feature, $parent->getFeatures()->get($feature));
    }
  }

  $self->_setAccountData('features',$features->getFeatureString());

  # Logs settings
  my $settings = {
    'features' => $self->_getAccountData('features')
  };

  my $datalog = new PlugNPay::Logging::DataLog({'collection' => 'gatewayaccount'});
  $datalog->log($settings);
}

sub _inheritRemoteClientIP {
  my $self = shift;
  my $parent = shift;

  eval {
    # load the parent settings, set the new username, then save..
    my $remoteClientSettings = new PlugNPay::RemoteClient($parent->getGatewayAccountName());
    $remoteClientSettings->setGatewayAccount($self->getGatewayAccountName());
    $remoteClientSettings->save();
  };

  if($@) {
    # logs settings
    my $settings = {
      'parent' => $parent->getGatewayAccountName(),
      'inheritor' => $self->getGatewayAccountName(),
      'error' => $@
    };

    my $datalog = new PlugNPay::Logging::DataLog({'collection' => 'gatewayaccount'});
    $datalog->log($settings);

    die("Error trying to save remote client settings, caused by: $@\n");
  }
}


sub filterGatewayAccountName {
  my $self = shift;
  my $gatewayAccount = lc (shift || $self);
  $gatewayAccount =~ s/[^a-z0-9]//g;
  return $gatewayAccount;
}

sub enableTestMode {
  my $self = shift;
  $self->_setAccountData('testmode','yes');
}

sub disableTestMode {
  my $self = shift;
  $self->_setAccountData('testmode','no');
}

sub getTestMode {
  my $self = shift;
  return $self->_getAccountData('testmode');
}

sub isTestModeEnabled {
  my $self = shift;
  return ($self->_getAccountData('testmode') ne 'yes' ? 0 : 1)
}

sub getErrors {
  my $self = shift;

  return $self->{'errors'};
}

sub setSSNum {
  my $self = shift;
  $self->_setAccountData('ssnum',shift);
}

sub getSSNum {
  my $self = shift;
  return $self->_getAccountData('ssnum');
}

sub setSwitchTime {
  my $self = shift;
  my $switchTime = shift;
  $self->_setAccountData('switchtime', $switchTime);
}

sub getSwitchTime {
  my $self = shift;
  return $self->_getAccountData('switchtime');
}

#############################
# GatewayAccount/Private.pm #
#############################
sub setAccountDataFromRow {
  my $self = shift;
  my $accountData = shift;

  # Remove these to preven accidental data change
  foreach my $key (keys %{$accountData}) {
    if (!inArray($key,\@_columns_)) {
      delete $accountData->{$key};
    }
  }
  $self->{'rawAccountData'} = $accountData;
}

#########################
# For internal use only #
#########################
sub _setAccountData {
  my $self = shift;
  return if (ref($self) ne caller());
  my $key = shift;
  my $value = shift;
  $self->{'rawAccountData'}{$key} = $value;
}

sub _getAccountData {
  my $self = shift;
  return if (ref($self) ne caller());
  my $key = shift;
  return $self->{'rawAccountData'}{$key};
}

sub _setSetupsData {
  my $self = shift;
  return if (ref($self) ne caller());
  my $key = shift;
  my $value = shift;
  $self->{'rawSetupsData'}{$key} = $value;
}

sub _getSetupsData {
  my $self = shift;
  return if (ref($self) ne caller());
  my $key = shift;
  return $self->{'rawSetupsData'}{$key};
}

sub _saveProcessorAccountData {
  my $self = shift;
  my $key = shift;
  my $value = shift;

  $self->refactorLog($key, 'set');

  eval {
    my $processorID = new PlugNPay::Processor({'shortName' => $self->_getAccountData('processor')})->getID();
    my $processorAccount = new PlugNPay::Processor::Account({'gatewayAccount' => $self->getGatewayAccountName(), 'processorID' => $processorID});
    $processorAccount->setSettingValue($key, $value);
    $processorAccount->save();
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'gatewayAccount'});
    $logger->log({'message' => 'processor settings save error', 'account' => $self->getGatewayAccountName(), 'error' => $@, 'setting' => $key});
  }
}


sub _loadProcessorAccountData {
  my $self = shift;
  my $key = shift;
  my $value;

  eval {
    my $processorID = new PlugNPay::Processor({'shortName' => $self->_getAccountData('processor')})->getID();
    my $processorAccount = new PlugNPay::Processor::Account({'gatewayAccount' => $self->getGatewayAccountName(), 'processorID' => $processorID});
    $value = $processorAccount->getSettingValue($key);
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'gatewayAccount'});
    $logger->log({'message' => 'processor settings load error', 'account' => $self->getGatewayAccountName(), 'error' => $@, 'setting' => $key});
  }

  return $value;
}

sub refactorLog {
  my $self = shift;
  my $caller = shift;
  my $function = shift;

  my $message = {
                  'message' => 'GatewayAccount outdated function call detected, refactor code',
                  'caller' => $caller,
                  'function' => $function,
                  'username' => $self->getGatewayAccountName(),
                  'alternateModuleToCall' => 'PlugNPay::Processor::Account'
  };
  new PlugNPay::Logging::DataLog({'collection' => 'refactor_me'})->log($message);
}

sub getCustomerId {
  my $self = shift;

  my $iid = new PlugNPay::GatewayAccount::InternalID();
  my $id = $iid->getIdFromUsername($self->getGatewayAccountName());
  return $id;
}

sub getTransactionCustomerId {
  my $self = shift;

  my $iid = new PlugNPay::GatewayAccount::InternalID();
  my $id = $iid->getMerchantID($self->getGatewayAccountName());
  return $id;
}

1;
