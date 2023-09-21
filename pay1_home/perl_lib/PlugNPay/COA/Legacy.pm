package PlugNPay::COA::Legacy;

use strict;
use CGI;
use PlugNPay::DBConnection;
use PlugNPay::Environment;
use PlugNPay::Features;
use PlugNPay::ResponseLink;
use PlugNPay::Sys::Time;
use PlugNPay::Util::UniqueID;
use PlugNPay::COA::Server;
use URI::Escape;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;


  my $gatewayAccount = shift;

  my $calculationURL = PlugNPay::COA::Server::getCalculationURL();
  $self->setCalculationURL($calculationURL);

  if (!defined $gatewayAccount) {
    $self->setGatewayAccount(new PlugNPay::Environment()->get('PNP_ACCOUNT'));
  } else {
    $self->setGatewayAccount($gatewayAccount);
  }

  # load settings
  if ($self->getGatewayAccount() ne '') {
    $self->loadSettings();
  }

  return $self;
}

sub setGatewayAccount {
  my $self = shift;
  my $account = lc shift;
  $account =~ s/[^a-z0-9]//g;
  $self->{'account'} = $account;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'account'};
}

sub setState {
  my $self = shift;
  my $state = shift;
  $self->{'state'} = $state;
}

sub getState {
  my $self = shift;
  return $self->{'state'} || {};;
}

sub setFormula {
  my $self = shift;
  my $formula = shift;
  $self->{'formula'} = $formula;
}

sub getFormula {
  my $self = shift;
  return $self->{'formula'};
}

sub setCalculationURL {
  my $self = shift;
  my $url = shift;
  $self->{'calculationURL'} = $url;
}

sub getCalculationURL {
  my $self = shift;
  return $self->{'calculationURL'};
}

sub setEnabled {
  my $self = shift;
  $self->{'settings'}{'enabled'} = shift;
}

sub getEnabled {
  my $self = shift;
  return $self->{'settings'}{'enabled'};
}

sub setModel {
  my $self = shift;
  my $model = lc shift;
  $model =~ s/[^a-z0-9_]//g;
  $self->loadModelData($model);
  $self->{'settings'}{'model'} = $model;
}

sub getModel {
  my $self = shift;
  return $self->{'settings'}{'model'};
}

sub setThreshold {
  my $self = shift;
  my $threshold = shift;
  $threshold =~ s/[^0-9\.]//g;
  $self->{'settings'}{'threshold'} = $threshold;
}

sub getThreshold {
  my $self = shift;
  return $self->{'settings'}{'threshold'};
}

sub setCOAAccountNumber {
  my $self = shift;
  my $accountNumber = shift;
  $self->{'settings'}{'coaAccountNumber'} = $accountNumber;
}

sub getCOAAccountNumber {
  my $self = shift;
  return $self->{'settings'}{'coaAccountNumber'};
}

sub setCOAAccountIdentifier {
  my $self = shift;
  my $identifier = shift;
  $self->{'settings'}{'coaAccountIdentifier'} = $identifier;
}

sub getCOAAccountIdentifier {
  my $self = shift;
  return $self->{'settings'}{'coaAccountIdentifier'};
}

sub setSplit {
  my $self = shift;
  my $split = shift;
  $split =~ s/[^0-9\.]//g;
  $self->{'settings'}{'split'} = abs($split);
}

sub getSplit {
  my $self = shift;
  return $self->{'settings'}{'split'};
}


sub setSurcharge {
  my $self = shift;
  my $isSurcharge = shift;
  $self->{'settings'}{'isSurcharge'} = ($isSurcharge ? 1 : 0);
}

sub getSurcharge {
  my $self = shift;
  return ($self->{'settings'}{'isSurcharge'} ? 1 : 0);
}

sub isSurcharge {
  my $self = shift;
  return $self->getSurcharge();
}

sub isOptional {
  return 0;
}

sub setDiscount {
  my $self = shift;
  my $isDiscount = shift;
  $self->{'settings'}{'isDiscount'} = ($isDiscount ? 1 : 0);
}

sub isFee {
  my $self = shift;
  return !($self->isSurcharge() || $self->isDiscount());
}

sub getDiscount {
  my $self = shift;
  return ($self->{'settings'}{'isDiscount'} ? 1 : 0);
}

sub isDiscount {
  my $self = shift;
  return $self->getDiscount();
}

sub setChargeAccount {
  my $self = shift;
  my $account = lc shift;
  $account =~ s/[^a-z0-9]//g;
  $self->{'settings'}{'chargeAccount'} = $account;
}

sub getChargeAccount {
  my $self = shift;
  return $self->{'settings'}{'chargeAccount'};
}

sub setFailureRule {
  my $self = shift;
  my $failureRule = lc shift;
  $self->{'settings'}{'failureRule'} = $failureRule;
}

sub getFailureRule {
  my $self = shift;
  return  $self->{'settings'}{'failureRule'};
}

sub getCustomerCanOverride {
  return 0;
}

sub getOverrideCheckboxIsChecked {
  return 0;
}

sub getCheckCustomerState {
  return 0;
}

#############################
# Fixed Fee Setters/Getters #
#############################

sub setCreditFixedFee {
  my $self = shift;
  my $fixed = shift;
  $self->setFixedFee('credit',$fixed);
}

sub setDebitFixedFee {
  my $self = shift;
  my $fixed = shift;
  $self->setFixedFee('debit',$fixed);
}

sub setACHFixedFee {
  my $self = shift;
  my $fixed = shift;
  $self->setFixedFee('ach',$fixed);
}

sub setFixedFee {
  my $self = shift;
  my $type = shift || 'all';
  my $fixed = shift;
  $fixed =~ s/[^0-9\.]//g;
  $self->{'settings'}{'fixedFee'}{$type} = $fixed;
}

sub getCreditFixedFee {
  my $self = shift;
  return (defined $self->getFixedFee('credit') ? $self->getFixedFee('credit') : $self->getFixedFee());
}

sub getDebitFixedFee {
  my $self = shift;
  return (defined $self->getFixedFee('debit') ? $self->getFixedFee('debit') : $self->getFixedFee());
}

sub getACHFixedFee {
  my $self = shift;
  return (defined $self->getFixedFee('ach') ? $self->getFixedFee('ach') : $self->getFixedFee());
}

sub getFixedFee {
  my $self = shift;
  my $type = shift || 'all';
  return $self->{'settings'}{'fixedFee'}{$type};
}

##############################
# Total Rate Setters/Getters #
##############################

sub setCreditTotalRate {
  my $self = shift;
  my $rate = shift;
  $self->setTotalRate('credit',$rate);
}

sub setDebitTotalRate {
  my $self = shift;
  my $rate = shift;
  $self->setTotalRate('debit',$rate);
}

sub setACHTotalRate {
  my $self = shift;
  my $rate = shift;
  $self->setTotalRate('ach',$rate);
}

sub setTotalRate {
  my $self = shift;
  my $type = shift || 'all';
  my $rate = shift;
  $rate =~ s/[^0-9\.]//g;
  $self->{'settings'}{'totalRate'}{$type} = $rate;
}

sub getCreditTotalRate {
  my $self = shift;
  return (defined $self->getTotalRate('credit') ? $self->getTotalRate('credit') : $self->getTotalRate());
}

sub getDebitTotalRate {
  my $self = shift;
  return (defined $self->getTotalRate('debit') ? $self->getTotalRate('debit') : $self->getTotalRate());
}

sub getACHTotalRate {
  my $self = shift;
  return (defined $self->getTotalRate('debit') ? $self->getTotalRate('ach') : $self->getTotalRate());
}

sub getTotalRate {
  my $self = shift;
  my $type = shift || 'all';
  return $self->{'settings'}{'totalRate'}{$type};
}

sub setCOAAmount {
  my $self = shift;
  my $amount = shift;
  $self->{'coaAmount'} = $amount;
}

sub getCOAAmount {
  my $self = shift;
  return $self->{'coaAmount'};
}

############################
# COA Rate Setters/Getters #
############################

sub setCreditCOARate {
  my $self = shift;
  my $rate = shift;
  $self->setCOARate('credit',$rate);
}

sub setDebitCOARate {
  my $self = shift;
  my $rate = shift;
  $self-setCOARate('debit',$rate);
}

sub setACHCOARate {
  my $self = shift;
  my $rate = shift;
  $self->setCOARate('ach',$rate);
}

sub setCOARate {
  my $self = shift;
  my $type = shift || 'all';
  my $rate = shift;
  $self->{'settings'}{'coaRate'}{$type} = $rate;
}

sub getCreditCOARate {
  my $self = shift;
  return (defined $self->getCOARate('credit') ? $self->getCOARate('credit') : $self->getCOARate());
}

sub getDebitCOARate {
  my $self = shift;
  return (defined $self->getCOARate('debit') ? $self->getCOARate('debit') : $self->getCOARate());
}

sub getACHCOARate {
  my $self = shift;
  return (defined $self->getCOARate('ach') ? $self->getCOARate('ach') : $self->getCOARate());
}

sub getCOARate {
  my $self = shift;
  my $type = shift || 'all';
  return $self->{'settings'}{'coaRate'}{$type};
}

sub setAuthorizationType {
  my $self = shift;
  my $type = shift;
  $self->{'settings'}{'authType'} = $type;
}

sub getAuthorizationType {
  my $self = shift;
  return $self->{'settings'}{'authType'};
}

sub loadModelData {
  my $self = shift;
  my $model = shift;

  $model =~ s/[^a-z0-9]//g;

  my $dbh = PlugNPay::DBConnection::database('pnpmisc');
  my $sth = $dbh->prepare(q/
                            SELECT model,formula,message_template,use_threshold,is_surcharge,is_discount
                            FROM coa_model
                            WHERE model = ?
                          /);

  $sth->execute($model);

  my $row = $sth->fetchrow_hashref;
  my $modelData = { formula => $row->{'formula'},
                    messageTemplate => $row->{'message_template'},
                    use_threshold => $row->{'use_threshold'}
                  };

  $self->setFormula($row->{'formula'});
  $self->setSurcharge($row->{'is_surcharge'});
  $self->setDiscount($row->{'is_discount'});
  
  return $modelData;
}

sub loadSettings {
  my $self = shift;
  
  if (!$self->_loadSettingsFromDatabase()) {
    $self->_loadSettingsFromFeatures();
    if ($self->getEnabled()) {
      $self->saveSettings();
    }
  }
}

sub saveSettings {
  my $self = shift;
  # not yet working on new site
  #$self->_saveSettingsToDatabase();
}

sub _loadSettingsFromDatabase {
  my $self = shift;
  
  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q/
    SELECT coa_account_number, coa_account_identifier, coa_model,
           coa_rate,total_rate,fixed_fee,
           credit_coa_rate,debit_coa_rate,ach_coa_rate,
           credit_total_rate,debit_total_rate,ach_total_rate,
           credit_fixed_fee,debit_fixed_fee,ach_fixed_fee,
           split_ratio,fee_account,failure_mode,threshold,
           authorization_type
      FROM coa_settings
     WHERE username = ?
  /);

  $sth->execute($self->getGatewayAccount());

  my $result = $sth->fetchrow_hashref;

  $self->setState($result);

  if ($result) {
    $self->setEnabled(1);
    $self->setCOAAccountNumber($result->{'coa_account_number'});
    $self->setCOAAccountIdentifier($result->{'coa_account_identifier'});
    $self->setModel($result->{'coa_model'});
    $self->setCOARate('all',$result->{'coa_rate'});
    $self->setCOARate('credit',$result->{'credit_coa_rate'});
    $self->setCOARate('debit',$result->{'debit_coa_rate'});
    $self->setCOARate('ach',$result->{'ach_coa_rate'});
    $self->setTotalRate('all',$result->{'credit_total_rate'});
    $self->setTotalRate('credit',$result->{'credit_total_rate'});
    $self->setTotalRate('debit',$result->{'debit_total_rate'});
    $self->setTotalRate('ach',$result->{'ach_total_rate'});
    $self->setFixedFee('all',$result->{'fixed_fee'});
    $self->setFixedFee('credit',$result->{'credit_fixed_fee'});
    $self->setFixedFee('debit',$result->{'debit_fixed_fee'});
    $self->setFixedFee('ach',$result->{'ach_fixed_fee'});
    $self->setSplit($result->{'split_ratio'});
    $self->setThreshold($result->{'threshold'});
    $self->setChargeAccount($result->{'fee_account'});
    $self->setFailureRule($result->{'failure_mode'});
    $self->setAuthorizationType($result->{'authorization_type'});
    return 1;
  }
  return 0;
}

sub _saveSettingsToDatabase {
  my $self = shift;
  
  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q/
    SELECT count(username) as `exists`
      FROM coa_settings
     WHERE username = ?
  /);

  $sth->execute($self->getGatewayAccount());

  my $result = $sth->fetchrow_hashref;

  if ($result && $result->{'exists'} == 0) {
    $sth = $dbh->prepare(q/
      INSERT INTO coa_settings
        (coa_account_number,
         coa_account_identifier,
         coa_model,
         coa_rate,
         total_rate,
         fixed_fee,
         credit_coa_rate,
         debit_coa_rate,
         ach_coa_rate,
         credit_total_rate,
         debit_total_rate,
         ach_total_rate,
         credit_fixed_fee,
         debit_fixed_fee,
         ach_fixed_fee,
         split_ratio,
         fee_account,
         failure_mode,
         threshold,
         authorization_type,
         username)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    /);
  } else {
    $sth = $dbh->prepare(q/
      UPDATE coa_settings
         SET coa_account_number = ?,
             coa_account_identifier = ?,
             coa_model = ?,
             coa_rate = ?,
             total_rate = ?,
             fixed_fee = ?,
             credit_coa_rate = ?,
             debit_coa_rate = ?,
             ach_coa_rate = ?,
             credit_total_rate = ?,
             debit_total_rate = ?,
             ach_total_rate = ?,
             credit_fixed_fee = ?,
             debit_fixed_fee = ?,
             ach_fixed_fee = ?,
             split_ratio = ?,
             fee_account = ?,
             failure_mode = ?,
             threshold = ?,
             authorization_type = ?
       WHERE username = ?
    /);
  }

  $sth->execute($self->getCOAAccountNumber(),
                $self->getCOAAccountIdentifier(),
                $self->getModel(),
                $self->getCOARate(),
                $self->getTotalRate(),
                $self->getFixedFee(),
                $self->getCOARate('credit'),
                $self->getCOARate('debit'),
                $self->getCOARate('ach'),
                $self->getTotalRate('credit'),
                $self->getTotalRate('debit'),
                $self->getTotalRate('ach'),
                $self->getFixedFee('credit'),
                $self->getFixedFee('debit'),
                $self->getFixedFee('ach'),
                $self->getSplit(),
                $self->getChargeAccount(),
                $self->getFailureRule(),
                $self->getThreshold(),
                $self->getAuthorizationType(),
                $self->getGatewayAccount());
}

sub _loadSettingsFromFeatures {
  my $self = shift;

  my %featureSettings;

  my $features = new PlugNPay::Features($self->getGatewayAccount(),'general');

  my $cardChargeFeatureString = $features->get('cardcharge');

  if ($cardChargeFeatureString) {
    # split this info out of the feature string
    %featureSettings = split(/[\|:]/,$cardChargeFeatureString);
    if ($cardChargeFeatureString =~ /identifier/ && $cardChargeFeatureString =~ /accountNumber/) {
      $self->setEnabled(1);
    }
    $self->setCOAAccountNumber($featureSettings{'accountNumber'});
    $self->setCOAAccountIdentifier($featureSettings{'identifier'});
    $self->setModel($featureSettings{'type'});
    $self->setCOARate($featureSettings{'baseRate'});
    $self->setTotalRate($featureSettings{'fixedRate'});
    $self->setFixedFee($featureSettings{'fixedFee'});
    $self->setSplit($featureSettings{'split'});
    $self->setThreshold($featureSettings{'threshold'});
    $self->setChargeAccount($featureSettings{'chargeAccount'});
    $self->setFailureRule($featureSettings{'failureRule'});
  }
}

sub getRaw {
  my $self = shift;
  my ($bin,$transactionAmount) = @_;

  if (!exists $self->{'resultsHash'}) {
    $self->get($bin,$transactionAmount);
  }

  # return a hash
  return %{$self->{'resultsHash'}};
}

sub getAdjustment {
  my $self = shift;
  my $bin = shift;
  my $transactionAmount = shift;
  my $transactionIdentifier = shift;

  my $resultData = $self->get($bin,$transactionAmount,$transactionIdentifier);

  return $resultData->{'adjustment'};
}

sub get {
  my $self = shift;
  my ($bin,$transactionAmount,$transactionIdentifier) = @_;

  # make sure we only have the first 9 digits
  $bin =~ s/[^0-9]//g;
  $bin = reverse sprintf('%09s',scalar reverse $bin);
  $bin = substr($bin,0,9);
  # append 0's if shorter than 9 digits
  $bin .= '0' x (9 - length($bin));
 

  my $query = sprintf('account_number=%s&account_identifier=%s&bin=%s&transaction_amount=%s&transaction_identifier=%s',
                      uri_escape($self->getCOAAccountNumber()),
                      uri_escape($self->getCOAAccountIdentifier()),
                      uri_escape($bin),
                      uri_escape($transactionAmount),
                      uri_escape($transactionIdentifier || 'n/a'));
                
  # set up response link object
  my $rl = new PlugNPay::ResponseLink();
  $rl->setRequestURL($self->getCalculationURL());
  $rl->setUsername($self->getGatewayAccount());
  $rl->setRequestData($query);
  $rl->setResponseAPIType('json');
  $rl->setRequestMode('DIRECT');

  $rl->doRequest();
  my %resultsHash = $rl->getResponseAPIData();
  chomp %resultsHash;
  $self->{'resultsHash'} = \%resultsHash;

  my $responseContent = $rl->getResponseContent();
  $responseContent =~ s/^\n+//g;


  # local calculations and message generation

  my $calculatedAdjustment = '0.00';

  # Determine the type of transaction
  my $rateType = 'all';
  if ($resultsHash{'calculatedCOA'}{'debit'}) {
    $rateType = 'debit';
  } elsif ($bin eq ('0' x 9)) {
    $rateType = 'ach';
  } else {
    $rateType = 'credit';
  }

  my $data = {
           model     => $self->getModel(),
           split     => $self->getSplit(),
           coaRate   => $self->getCOARate($rateType),
           threshold => $self->getThreshold(),
           totalRate => $self->getTotalRate($rateType) || 0,
           fixedFee  => $self->getFixedFee($rateType)  || 0,
           total     => $transactionAmount || 0,
           debit     => $resultsHash{'calculatedCOA'}{'debit'} || 0,
           coa       => $resultsHash{'calculatedCOA'}{'coa'} || 0,
           achCOA    => $resultsHash{'calculatedCOA'}{'achCOA'} || 0,
           regCOA    => $resultsHash{'calculatedCOA'}{'regCOA'} || 0,
           minCOA    => $resultsHash{'calculatedCOA'}{'minCOA'} || 0,
           maxCOA    => $resultsHash{'calculatedCOA'}{'maxCOA'} || 0,
           regcoa    => $resultsHash{'calculatedCOA'}{'regCOA'} || 0, # for compatibility with existing scripts until they are changed to use regCOA
           mincoa    => $resultsHash{'calculatedCOA'}{'minCOA'} || 0, # for compatibility with existing scripts until they are changed to use minCOA
           maxcoa    => $resultsHash{'calculatedCOA'}{'maxCOA'} || 0, # for compatibility with existing scripts until they are changed to use maxCOA
           brand     => $resultsHash{'calculatedCOA'}{'brand'}  || 'unknown',
           type      => $resultsHash{'calculatedCOA'}{'type'}   || 'unknown'
         };

  my $adjustment = sprintf('%0.2f',$self->calculateRPN($self->getFormula(),$data));

  $self->setCOAAmount($adjustment);

  my %debitData = %{$data};
  $debitData{'coa'} = $debitData{'regCOA'};
  $debitData{'coaRate'} = $self->getCOARate('debit');
  $debitData{'totalRate'} = $self->getTotalRate('debit');
  $debitData{'fixedFee'} = $self->getFixedFee('debit');
  my $debitAdjustment = sprintf('%0.2f',$self->calculateRPN($self->getFormula(),\%debitData));

  my %achData = %{$data};
  $achData{'coa'} = $achData{'achCOA'};
  $achData{'coaRate'} = $self->getCOARate('ach');
  $achData{'totalRate'} = $self->getTotalRate('ach');
  $achData{'fixedFee'} = $self->getFixedFee('ach');
  my $achAdjustment = sprintf('%0.2f',$self->calculateRPN($self->getFormula(),\%achData));

  my %maxData = %{$data};
  $maxData{'coa'} = $maxData{'maxCOA'};
  my $maxAdjustment = sprintf('%0.2f',$self->calculateRPN($self->getFormula(),\%maxData));

  if ($bin eq '000000000') {
    $adjustment = $achAdjustment;
  }

  my $account = new PlugNPay::GatewayAccount($self->getGatewayAccount());
  my $canProcessACH = $account->canProcessOnlineChecks();

  my $responseData;
  $responseData->{'threshold'} = $data->{'threshold'};
  $responseData->{'adjustment'} = $adjustment;
  $responseData->{'debitAdjustment'} = $debitAdjustment;
  $responseData->{'achAdjustment'}   = $achAdjustment;
  $responseData->{'maxAdjustment'}   = $maxAdjustment;
  $responseData->{'displayDebitOption'} = (abs($adjustment - $debitAdjustment) > $data->{'threshold'} ? 1 : 0);
  $responseData->{'displayACHOption'}   = (($canProcessACH && $adjustment - $achAdjustment > $data->{'threshold'}) ? 1 : 0);
  $responseData->{'type'}  = $data->{'type'};
  $responseData->{'brand'} = $data->{'brand'};
  
  return $responseData;
}


sub calculateRPN {
  my $self = shift;
  my $formula = shift;
  my $dataRef = shift;

  my @input = split(/\s+/,$formula);
  my @stack;

  while (@input > 0) {
    my $nextInput = shift @input;

    # convert $nextInput to a value if it is a variable
    if ($nextInput =~ /^\$/) {
        $nextInput = substr($nextInput,1);
	$nextInput = $dataRef->{$nextInput};
    }

    # Operator Descriptions
    #-----------------------
    # +,-,*, and / are self explanitory.
    # zlt = zero less than, if operand1 is less than operand2, 
    #       push zero onto the stack, if not, push operand1 onto the stack
    # not = if operand is true, returns 0, if operand is false, returns 1

    if ($nextInput =~ /^(\+|\-|\*|\/|zlt)$/) {
      # perform the operation
      # we only do binary operators so pull two items
      # pull in reverse order because it's a stack!
      my $operand2 = shift @stack;
      my $operand1 = shift @stack;

      # perform the operation and put the result onto the stack
      if      ($nextInput eq '+') { unshift @stack,($operand1 + $operand2);
      } elsif ($nextInput eq '-') { unshift @stack,($operand1 - $operand2);
      } elsif ($nextInput eq '*') { unshift @stack,($operand1 * $operand2);
      } elsif ($nextInput eq '/') { unshift @stack,($operand1 / $operand2);
      } elsif ($nextInput eq 'zlt') { unshift @stack,($operand1 < $operand2 ? 0 : $operand1); 
      }
    } elsif ($nextInput =~ /^(not)$/) {
      my $operand = shift @stack;

      if ($nextInput eq 'not') { unshift @stack,(!$operand ? 1 : 0); }
    } else {
      # push the value onto the stack;
      unshift @stack,$nextInput;
    } 
  }

  return $stack[0];
}

sub startSession {
  my $self = shift;

  $self->cleanupSessions();

  my $sessionID;
  # only create a session if username exists.
  if ($self->getGatewayAccount()) {
    $sessionID = new PlugNPay::Util::UniqueID()->inHex();

    # save the current session to the object so we can possibly save a few database queries later
    $self->{'currentSession'} = $sessionID;

    my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
  
    my $sth = $dbh->prepare(q/
      INSERT INTO coa_session
        (session_id, session_start, username)
      VALUES (?,FROM_UNIXTIME(?),?)
    /);
  
    $sth->execute($sessionID,time(),$self->getGatewayAccount()) or die($DBI::errstr);
  } 

  return $sessionID;
}

sub cleanupSessions {
  my $self = shift;

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q/
    DELETE FROM coa_session 
     WHERE HOUR(TIMEDIFF(UTC_TIMESTAMP(),UNIX_TIMESTAMP(session_timestamp))) > 1
  /);

  $sth->execute();
}

sub verifySession {
  my $self = shift;
  my $sessionID = shift;

  # save a couple queries to the database if the session being checked is the current session
  if (defined $self->{'currentSession'}) {
    if ($sessionID eq $self->{'currentSession'}) {
      return 1;
    }
  }

  # uniqueID's are validatable, so if it's not valid, return false
  my $uniqueID = new PlugNPay::Util::UniqueID();
  $uniqueID->fromHex($sessionID);
  if (!$uniqueID->validate()) {
    return 0;
  }

  $self->cleanupSessions();

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q/
    SELECT count(session_id) AS `exists`
      FROM coa_session
     WHERE session_id = ?
  /);

  $sth->execute($sessionID);

  my $results = $sth->fetchrow_hashref;

  if ($results) {
    return $results->{'exists'};
  }

  return 0;
}

sub getAdjustmentIsTaxable {
  # always return 1, if they want to turn this off they have to upgrade to "adjustment"
  return 1;
}

1;
