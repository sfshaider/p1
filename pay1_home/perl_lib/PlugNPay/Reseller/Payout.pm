package PlugNPay::Reseller::Payout;

use strict;
use PlugNPay::Contact;
use PlugNPay::CreditCard;
use PlugNPay::OnlineCheck;
use PlugNPay::DBConnection;


sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $username = shift;

  if (defined $username){
    $self->setGatewayAccount($username);
    $self->load();
    if (!defined $self->getGatewayAccount() || $self->getGatewayAccount() eq ''){
      $self->setGatewayAccount($username);
      $self->load();
    }
  }

  return $self;
}

sub exists {
  my $self = shift;
  my $account = shift;

  # the following is so that it can be called without having an instance of GatewayAccount
  if (!defined $account) {
    if (ref($self)) {
      $account = $self->getGatewayAccount();
    } else {
      $account = $self;
    }
  }

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnppaydata');
  my $sth = $dbh->prepare(q/
    SELECT count(username) as `exists`
    FROM customer
    WHERE username = ?
  /);

  $sth->execute($account);

  my $results = $sth->fetchall_arrayref({});
  if ($results && $results->[0]) {
    return ($results->[0]{'exists'} == 1);
  }
  return 0;
}

sub setGatewayAccount{
  my $self = shift;
  $self->_setAccountData('username',shift);
}

sub getGatewayAccount {
  my $self = shift;
  return $self->_getAccountData('username');
}

sub setBillUsername {
  my $self = shift;
  $self->setBillUsername('billusername',shift);
}

sub getBillUsername {
  my $self = shift;
  return $self->getBillUsername('billusername');
}

sub setExpDate {
  my $self = shift;
  my $month = shift;
  my $year = shift;
  
  $self->_setAccountData('exp', $month . $year);
}

sub getExpData {
  my $self = shift;
  return $self->_getAccountData('exp');
}
  
sub setContact {
  my $self = shift;
  my $contact = shift;
  $self->{'mainContact'} = $contact;
  $self->_setAccountData('name',$contact->getFullName());
  $self->_setAccountData('company',$contact->getCompany());
  $self->_setAccountData('addr1',$contact->getAddress1());
  $self->_setAccountData('addr2',$contact->getAddress2());
  $self->_setAccountData('city',$contact->getCity());
  $self->_setAccountData('state',$contact->getState());
  $self->_setAccountData('zip',$contact->getPostalCode());
  $self->_setAccountData('country',$contact->getCountry());
  $self->_setAccountData('phone',$contact->getPhone());
  $self->_setAccountData('fax',$contact->getFax());
  $self->_setAccountData('email',$contact->getEmailAddress());
}

sub getContact {
  my $self = shift;
  my $contact = $self->{'mainContact'};
  if (!$contact) {
    $contact = new PlugNPay::Contact();
  }
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
  $contact->setPhone($self->_getAccountData('phone'));
  $contact->setFax($self->_getAccountData('fax'));
  $contact->setEmailAddress($self->_getAccountData('email'));
  return $contact;
}

sub setShipContact {
  my $self = shift;
  my $contact = shift;
  $self->{'mainContact'} = $contact;
  $self->_setAccountData('shipname',$contact->getFullName());
  $self->_setAccountData('shipaddr1',$contact->getAddress1());
  $self->_setAccountData('shipaddr2',$contact->getAddress2());
  $self->_setAccountData('shipcity',$contact->getCity());
  $self->_setAccountData('shipstate',$contact->getState());
  $self->_setAccountData('shipzip',$contact->getPostalCode());
  $self->_setAccountData('shipcountry',$contact->getCountry());
}

sub getShipContact {
  my $self = shift;
  my $contact = $self->{'mainContact'};
  if (!$contact) {
    $contact = new PlugNPay::Contact();
  }
  # this seems inefficient but it's the only way to ensure
  # that the contact object and the contact data stay in
  # sync
  $contact->setFullName($self->_getAccountData('shipname'));
  $contact->setAddress1($self->_getAccountData('shipaddr1'));
  $contact->setAddress2($self->_getAccountData('shipaddr2'));
  $contact->setCity($self->_getAccountData('shipcity'));
  $contact->setState($self->_getAccountData('shipstate'));
  $contact->setPostalCode($self->_getAccountData('shipzip'));
  $contact->setCountry($self->_getAccountData('shipcountry'));
  return $contact;
}

sub setOrderID{
  my $self = shift;
  $self->_setAccountData('orderid',shift);
}

sub getOrderID {
  my $self = shift;
  return $self->_getAccountData('orderid');
}

sub setPlan {
  my $self = shift;
  $self->_setAccountData('plan',shift);
}

sub getPlan {
  my $self = shift;
  return $self->_getAccountData('plan');
}

sub setStatus {
  my $self = shift;
  $self->_setAccountData('status',shift);
}

sub getStatus {
  my $self = shift;
  $self->_getAccountData('status');
}

sub setLastBilled {
  my $self = shift;
  $self->_setAccountData('lastbilled',shift);
}

sub getLastBilled {
  my $self = shift;
  return $self->_getAccountData('lastbilled');
}

sub setLastAttempted {
  my $self = shift;
  $self->_setAccountData('lastattempted',shift);
}

sub getLastAttempted {
  my $self = shift;
  return $self->_getAccountData('lastattempted');
}

sub setResult {
  my $self = shift;
  $self->_setAccountData('result',shift);
}

sub getResult {
  my $self = shift;
  return $self->_getAccountData('result');
}

sub setAccountCode {
  my $self = shift;
  $self->_setAccountData('acct_code',shift);
}

sub getAccountCode { 
  my $self = shift;
  return $self->_getAccountData('acct_code');
}

sub setAccountCode4 {
  my $self = shift;
  $self->_setAccountData('acct_code4',shift);
}

sub getAccountCode4 {
  my $self = shift;
  return $self->_getAccountData('acct_code4');
}

sub setSHACardNumber {
  my $self = shift;
  $self->_setAccountData('shacardnumber',shift);
}

sub getSHACardNumber {
  my $self = shift;
  return $self->_getAccountData('shacardnumber');
}

sub setAccountType {
  my $self = shift;
  $self->_setAccountData('accttype',shift);
}

sub getAccountType {
  my $self = shift;
  $self->_getAccoutnData('accttype');
}

sub setPurchaseID {
  my $self = shift;
  $self->_setAccountData('purchaseid',shift);
}

sub getPurchaseID {
  my $self = shift;
  $self->_getAccountData('purchaseid');
}

sub setBillCycle {
  my $self = shift;
  $self->_setAccountData('billcycle',shift);
}

sub getBillCycle {
  my $self = shift;
  $self->_getAccountdata('billcycle');
}

sub setStartDate {
  my $self = shift;
  $self->_setAccountData('startdate',shift);
}

sub getStartDate {
  my $self = shift;
  return $self->_getAccountData('startdate');
}

sub setEndDate {
  my $self = shift;
  $self->_setAccountData('enddate',shift);
}

sub getEndDate {
  my $self = shift;
  $self->_getAccountData('enddate');
}

sub setMonthly {
  my $self = shift;
  $self->_setAccoutnData('monthly', shift);
}

sub getMonthly {
  my $self = shift;
  return $self->_getAccountData('monthly');
}

sub setBalance {
  my $self = shift;
  $self->_setAccountData('balance',shift);
}

sub getBalance {
  my $self = shift;
  return $self->_getAccountData('balance');
}

sub setRoutingNumber {
  my $self = shift;
  $self->{'routing'} = shift;
}

sub getRoutingNumber {
  my $self = shift;
  return $self->{'routing'};
}

sub setAccountNumber {
  my $self = shift;
  $self->{'account'} = shift;
}

sub getAccountNumber {
  my $self = shift;
  return $self->{'account'};
}

sub getMaskedAccountNumber {
  my $self = shift;
  return $self->{'masked_account'};
}

sub getMaskedRoutingNumber {
  my $self = shift;
  return $self->{'masked_routing'};
}

sub isBusinessAccount {
  my $self = shift;
  $self->_setAccountData('commcardtype','business');
}

sub isPersonalAccount {
  my $self = shift;
  $self->_setAccountData('commcardtype','');
}

sub getCommCardType {
  my $self = shift;
  my $acctType = $self->_getAccountData('commcardtype');
  if ($acctType) {
    return 'Business';
  } else {
    return 'Personal';
  }
}

sub setMaskedNumber {
  my $self = shift;
  my $number = shift;
  my $routing  = shift || undef;
  
  if (defined $routing) {
    my $ach = new PlugNPay::OnlineCheck();
    $ach->setABARoutingNumber($routing);
    $ach->setAccountNumber($number);
    $self->setEncACHNum($routing,$number);
    $self->_setAccountData('cardnumber',$ach->getMaskedNumber());
    
  } else {
    my $card = new PlugNPay::CreditCard();
    $card->setNumber($number);
    $self->setEncCardNum($number);
    $self->_setAccountData('cardnumber',$card->getMaskedNumber(4,2,'*',2));
  }
}

sub getMaskedCardNumber {
  my $self = shift;
  my $maskedData = $self->_getAccountData('cardnumber');

  return $maskedData;
}

sub getPaymentInfo {
  my $self = shift;
  unless ($self->{'accttype'} eq 'ach') {
    return $self->getCardNumber();
  } else {
    return $self->getACHAccount();
  }
}

sub getCardNumber {
  my $self = shift;
  my $card = new PlugNPay::CreditCard();
  $card->setNumberFromEncryptedNumber($self->getEncNum());
  my $data = $card->getNumber();
  return $data;
}

sub getACHAccount {
  my $self = shift;
  my $ach = new PlugNPay::OnlineCheck();
  return $ach->decryptAccountInfo($self->getEncNum());
}

sub setEncCardNum {
  my $self = shift;
  my $number = shift;
  my $card;
  
  $card = new PlugNPay::CreditCard($number);
  $self->_setAccountData('enccardnumber',$card->getYearMonthEncryptedNumber());
  $self->setLength(length($card->getYearMonthEncryptedNumber()));
  $self->setAccountType('credit');
}

sub setEncACHNum {
  my $self = shift;
  my $ach = new PlugNPay::OnlineCheck();
  my $account = shift;
  my $routing = shift;

  $ach->setABARoutingNumber($routing);
  $ach->setAccountNumber($account);
  my $enc = $ach->encryptAccountInfo();

  $self->_setAccountData('enccardnumber',$enc);
  $self->setLength(length($enc));
  $self->setAccountType('ach');
}

sub getEncNum { 
  my $self = shift;
  return $self->_getAccountData('enccardnumber');
}

sub setLength {
  my $self = shift;
  $self->_setAccountData('length',shift);
}

sub getLength {
  my $self = shift;
  return $self->_getAccountData('length');
}

sub load {
  my $self = shift;
  my $dbconn = new PlugNPay::DBConnection()->getHandleFor('pnppaydata');
  my $sth = $dbconn->prepare(q/
                             SELECT username,name,addr1,addr2,city,state,
                             zip,country,email,phone,fax,acct_code,accttype,
                             cardnumber,enccardnumber,orderid,status,result,
                             length,shipname,shipaddr1,shipaddr2,shipcity,
                             shipstate,shipzip,shipcountry,billcycle,startdate,
                             enddate,monthly,balance,exp,billusername,commcardtype,
                             lastattempted,shacardnumber,acct_code4,plan,purchaseid,
                             password,company,lastbilled
                             FROM customer
                             WHERE username=?
                             /);
  $sth->execute($self->_getAccountData('username'));
  my $row = $sth->fetchrow_hashref();
  $self->{'rawAccountData'} = $row;

  if ($self->{'rawAccountData'}{'accttype'} eq 'ach') {
    my $infoHash = new PlugNPay::OnlineCheck()->decryptAccountInfo($self->{'rawAccountData'}{'enccardnumber'});
    $self->{'masked_routing'} = substr($infoHash->{'routing'},0,4) . $self->generateMaskedDisplay(length($infoHash->{'routing'}) - 4);
    $self->{'masked_account'} = $self->generateMaskedDisplay(length($infoHash->{'account'}) - 4) . substr($infoHash->{'account'},length($infoHash->{'account'}) - 4,4);
  }
}

sub save {
  my $self = shift;

  my @fields = sort keys %{$self->{'rawAccountData'}};
  my @fieldValues = map { $self->_getAccountData($_) } @fields;
  my $fieldNamesString = join(',',map { $_ } @fields);
  my $insertPlaceholdersString = join(',',map { '?' } @fields);
  my $updateString = join(',',map { $_ . ' = ?' } @fields);

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnppaydata');
  my $insert = 'INSERT INTO customer (' . $fieldNamesString . ') VALUES (' . $insertPlaceholdersString . ')';
  my $update = 'UPDATE customer SET ' . $updateString . ' WHERE username=?';
  my $sth;
  if ($self->exists()){
    $sth = $dbh->prepare($update);
    $sth->execute(@fieldValues,$self->getGatewayAccount()) or die($DBI::errstr);
  } else {
    $sth = $dbh->prepare($insert);
    $sth->execute(@fieldValues) or die($DBI::errstr);
  }
}

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

sub generateMaskedDisplay {
  my $self = shift;
  my $length = shift;
  my $masked;
  for (my $i = 0; $i < $length; $i++){
    $masked .= '*';
  } 
  return $masked;
}

1;
