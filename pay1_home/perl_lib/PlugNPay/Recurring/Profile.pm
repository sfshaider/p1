package PlugNPay::Recurring::Profile;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;
use PlugNPay::Die;
use PlugNPay::Recurring::PaymentSource;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  my $info = shift;
  my $options = shift;

  $self->{_options} = $options || {};

  if (ref($info) eq 'HASH') {
    my $merchant = $info->{'merchant'};
    my $customer = $info->{'customer'};
    $self->setGatewayAccount($merchant);
    $self->setUsername($customer);
    $self->load();
  }

  return $self;
}

sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;
  $self->{'gatewayAccount'} = $gatewayAccount;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

sub setUsername {
  my $self = shift;
  my $username = shift;
  $self->{'username'} = $username;
}

sub getUsername {
  my $self = shift;
  return $self->{'username'};
}

sub setName {
  my $self = shift;
  my $name = shift;
  $self->{'name'} = $name;
}

sub getName {
  my $self = shift;
  return $self->{'name'};
}

sub setEmail {
  my $self = shift;
  my $email = shift;
  $self->{'email'} = $email;
}

sub getEmail {
  my $self = shift;
  return $self->{'email'};
}

sub setPassword {
  my $self = shift;
  my $password = shift;
  $self->{'password'} = $password;
}

sub getPassword {
  my $self = shift;
  return $self->{'password'};
}

sub setCompany {
  my $self = shift;
  my $company = shift;
  $self->{'company'} = $company;
}

sub getCompany {
  my $self = shift;
  return $self->{'company'};
}

sub setAddress1 {
  my $self = shift;
  my $address1 = shift;
  $self->{'address1'} = $address1;
}

sub getAddress1 {
  my $self = shift;
  return $self->{'address1'};
}

sub setAddress2 {
  my $self = shift;
  my $address2 = shift;
  $self->{'address2'} = $address2;
}

sub getAddress2 {
  my $self = shift;
  return $self->{'address2'};
}

sub setCity {
  my $self = shift;
  my $city = shift;
  $self->{'city'} = $city;
}

sub getCity {
  my $self = shift;
  return $self->{'city'};
}

sub setState {
  my $self = shift;
  my $state = shift;
  $self->{'state'} = $state;
}

sub getState {
  my $self = shift;
  return $self->{'state'};
}

sub setPostalCode {
  my $self = shift;
  my $postalCode = shift;
  $self->{'postalCode'} = $postalCode;
}

sub getPostalCode {
  my $self = shift;
  return $self->{'postalCode'};
}

sub setCountry {
  my $self = shift;
  my $country = shift;
  $self->{'country'} = $country;
}

sub getCountry {
  my $self = shift;
  return $self->{'country'};
}

sub setShippingName {
  my $self = shift;
  my $shipname = shift;
  $self->{'shipname'} = $shipname;
}

sub getShippingName {
  my $self = shift;
  return $self->{'shipname'};
}

sub setShippingAddress1 {
  my $self = shift;
  my $shipaddress1 = shift;
  $self->{'shipaddress1'} = $shipaddress1;
}

sub getShippingAddress1 {
  my $self = shift;
  return $self->{'shipaddress1'};
}

sub setShippingAddress2 {
  my $self = shift;
  my $shipaddress2 = shift;
  $self->{'shipaddress2'} = $shipaddress2;
}

sub getShippingAddress2 {
  my $self = shift;
  return $self->{'shipaddress2'};
}

sub setShippingCity {
  my $self = shift;
  my $shipcity = shift;
  $self->{'shipcity'} = $shipcity;
}

sub getShippingCity {
  my $self = shift;
  return $self->{'shipcity'};
}

sub setShippingState {
  my $self = shift;
  my $shipstate = shift;
  $self->{'shipstate'} = $shipstate;
}

sub getShippingState {
  my $self = shift;
  return $self->{'shipstate'};
}

sub setShippingPostalCode {
  my $self = shift;
  my $shipPostalCode = shift;
  $self->{'shipPostalCode'} = $shipPostalCode;
}

sub getShippingPostalCode {
  my $self = shift;
  return $self->{'shipPostalCode'};
}

sub setShippingCountry {
  my $self = shift;
  my $shipcountry = shift;
  $self->{'shipcountry'} = $shipcountry;
}

sub getShippingCountry {
  my $self = shift;
  return $self->{'shipcountry'};
}

sub setPhone {
  my $self = shift;
  my $phone = shift;
  $phone =~ s/[^0-9]//g;
  $self->{'phone'} = $phone;
}

sub getPhone {
  my $self = shift;
  return $self->{'phone'};
}

sub setFax {
  my $self = shift;
  my $fax = shift;
  $fax =~ s/[^0-9]//g;
  $self->{'fax'} = $fax;
}

sub getFax {
  my $self = shift;
  return $self->{'fax'};
}

sub setStatus {
  my $self = shift;
  my $status = shift;
  $self->{'status'} = $status;
}

sub getStatus {
  my $self = shift;
  return $self->{'status'};
}

sub setBillCycle {
  my $self = shift;
  my $billCycle = shift;
  $self->{'billCycle'} = $billCycle;
}

sub getBillCycle {
  my $self = shift;
  return $self->{'billCycle'};
}

sub setRecurringFee {
  my $self = shift;
  my $recurringFee = shift;
  $recurringFee =~ s/[^0-9\.]//g;
  $self->{'recurringFee'} = $recurringFee;
}

sub getRecurringFee {
  my $self = shift;
  return $self->{'recurringFee'};
}

sub setStartDate {
  my $self = shift;
  my $startDate = shift;
  $self->{'startDate'} = $startDate;
}

sub getStartDate {
  my $self = shift;
  return $self->{'startDate'};
}

sub setEndDate {
  my $self = shift;
  my $endDate = shift;
  $self->{'endDate'} = $endDate;
}

sub getEndDate {
  my $self = shift;
  return $self->{'endDate'};
}

sub setBalance {
  my $self = shift;
  my $balance = shift;
  $balance =~ s/[^0-9\.]//g;
  $self->{'balance'} = $balance;
}

sub getBalance {
  my $self = shift;
  return $self->{'balance'};
}

sub setAccountCode {
  my $self = shift;
  my $accountCode = shift;
  $self->{'accountCode'} = $accountCode;
}

sub getAccountCode {
  my $self = shift;
  return $self->{'accountCode'};
}

sub setPurchaseId {
  my $self = shift;
  my $purchaseId = shift;
  $self->{'purchaseId'} = $purchaseId;
}

sub getPurchaseId {
  my $self = shift;
  return $self->{'purchaseId'};
}

sub load {
  my $self = shift;
  my $merchant = shift || $self->getGatewayAccount();
  my $customer = shift;

  return if (!defined $merchant || !defined $customer);

  my $errorMsg;
  eval {
    if ($merchant && $customer) {
      my $dbs = new PlugNPay::DBConnection();

      my $commcardtypeSQL = '';
      if (!$self->{_options}{skipPaymentSourcePrefetch}) {
        my $columnInfo = $dbs->getColumnsForTable({ database => $merchant, table => 'customer'});
        if ($columnInfo->{'commcardtype'}) {
          $commcardtypeSQL = ', commcardtype';
        }
      }

      my $sth = $dbs->prepare($merchant, q/
        SELECT username, name, email, password, company, addr1, addr2,
               city, state, zip, country, shipname, shipaddr1, shipaddr2,
               shipcity, shipstate, shipzip, shipcountry, phone, fax, status,
               monthly, balance, billcycle, startdate, enddate, acct_code, purchaseid / .
               # the next line is used for prefetching payment source info, minimal cost to always do it
               qq/ exp, orderid, accttype $commcardtypeSQL / . q/
        FROM customer
        WHERE LOWER(username) = LOWER(?)/) or die $DBI::errstr;
      $sth->execute($customer) or die $DBI::errstr;

      my $rows = $sth->fetchall_arrayref({});
      if (@{$rows} > 0) {
        my $row = $rows->[0];
        $self->setProfileFromRow($row);
        if (!$self->{_options}{skipPaymentSourcePrefetch}) {
          my $ps = new PlugNPay::Recurring::PaymentSource();
          # prepare the data for the payment source prefetch function
          $row->{merchant} = $merchant;
          $row->{customer} = $row->{username};
          delete $row->{username};
          $ps->fromRecurringDbPrefetch($row);
        }
      }
    }
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'recurring_attendant' });
    $logger->log({ 'error' => $@,
                   'subroutine' => 'loadProfile',
                   'customer' => $customer,
                   'merchant' => $merchant });
    return 0;
  }



  return 1;
}

sub setProfileFromRow {
  my $self = shift;
  my $row = shift;

  $self->setUsername($row->{'username'});
  $self->setName($row->{'name'});
  $self->setEmail($row->{'email'});
  $self->setPassword($row->{'password'});
  $self->setCompany($row->{'company'});
  $self->setAddress1($row->{'addr1'});
  $self->setAddress2($row->{'addr2'});
  $self->setCity($row->{'city'});
  $self->setState($row->{'state'});
  $self->setPostalCode($row->{'zip'});
  $self->setCountry($row->{'country'});
  $self->setShippingName($row->{'shipname'});
  $self->setShippingAddress1($row->{'shipaddr1'});
  $self->setShippingAddress2($row->{'shipaddr2'});
  $self->setShippingCity($row->{'shipcity'});
  $self->setShippingState($row->{'shipstate'});
  $self->setShippingPostalCode($row->{'shipzip'});
  $self->setShippingCountry($row->{'shipcountry'});
  $self->setPhone($row->{'phone'});
  $self->setFax($row->{'fax'});
  $self->setStatus($row->{'status'});
  $self->setRecurringFee($row->{'monthly'});
  $self->setBalance($row->{'balance'});
  $self->setBillCycle($row->{'billcycle'});
  $self->setStartDate($row->{'startdate'});
  $self->setEndDate($row->{'enddate'});
  $self->setAccountCode($row->{'acct_code'});
  $self->setPurchaseId($row->{'purchaseid'});
}

sub saveProfile {
  my $self = shift;
  return $self->save(@_);
}

sub save {
  my $self = shift;
  my $customer = shift || $self->getUsername();
  my $merchant = shift || $self->getGatewayAccount();

  my $errorMsg;
  eval {
    if (!$merchant) {
      $errorMsg = 'Failed to save profile. No gateway account specified.';
      die($errorMsg);
    }

    if (!$customer) {
      $errorMsg = 'Failed to save profile. No customer specified.';
      die($errorMsg);
    }

    my $data = {
      'name'    => $self->{'name'},
      'email'   => $self->{'email'},
      'company' => $self->{'company'},
      'addr1'   => $self->{'address1'},
      'addr2'   => $self->{'address2'},
      'city'    => $self->{'city'},
      'state'   => $self->{'state'},
      'zip'     => $self->{'postalCode'},
      'country' => $self->{'country'},
      'shipname'  => $self->{'shippingName'},
      'shipaddr1' => $self->{'shippingAddress1'},
      'shipaddr2' => $self->{'shippingAddress2'},
      'shipcity'  => $self->{'shippingCity'},
      'shipstate' => $self->{'shippingState'},
      'shipzip'   => $self->{'shippingPostalCode'},
      'shipcountry' => $self->{'shippingCountry'},
      'phone'   => $self->{'phone'},
      'fax'     => $self->{'fax'},
      'status'  => $self->{'status'},
      'startdate' => $self->{'startDate'},
      'endDate'   => $self->{'endDate'},
      'billcycle' => $self->{'billCycle'},
      'monthly'   => $self->{'recurringFee'},
      'balance'   => $self->{'balance'},
      'acct_code' => $self->{'accountCode'},
      'purchaseid' => $self->{'purchaseId'}
    };

    if ($self->checkExists($customer,$merchant)) {
      $self->_update($customer,$merchant,$data)
    } else {
      $self->_insert($customer,$merchant,$data);
    }
  };

  if ($@) {
    if (!$errorMsg) {
      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'recurring_attendant' });
      $logger->log({ 'error' => $@,
                     'subroutine' => 'saveProfile',
                     'customer' => $customer,
                     'merchant' => $merchant });
      $errorMsg = 'Failed to save profile.';
    }

    return { 'status' => 0, 'errorMessage' => $errorMsg };
  }

  return { 'status' => 1 };
}

sub checkExists {
  my $self = shift;
  my $customer = shift;
  my $merchant = shift;

  my $query = 'SELECT COUNT(username) as `exists` FROM customer WHERE LOWER(username) = LOWER(?)';

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare($merchant,$query) or die($DBI::errstr);
  $sth->execute($customer) or die($DBI::errstr);
  my $rows = $sth->fetchall_arrayref({}) or die($DBI::errstr);
  return $rows->[0]{'exists'};
}

sub _insert {
  my $self = shift;
  my $customer = shift;
  my $merchant = shift;
  my $data = shift;

  my %dataCopy = %{$data};
  $dataCopy{'username'} = $customer;

  my $query = 'INSERT INTO customer (`' . join('`,`',keys(%dataCopy)) . '`) VALUES (' . join(',',map { '?' } keys(%dataCopy)) . ')';

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare($merchant,$query) or die($DBI::errstr);
  $sth->execute(values(%dataCopy)) or die($DBI::errstr);
}

sub _update {
  my $self = shift;
  my $customer = shift;
  my $merchant = shift;
  my $data = shift;

  my $query = 'UPDATE customer SET ' . join(',',map { "$_ = ?" } keys %{$data}) . ' WHERE LOWER(username) = LOWER(?)';

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare($merchant,$query) or die($DBI::errstr);
  $sth->execute(values(%{$data}),$customer) or die($DBI::errstr);
}

sub deleteProfile {
  my $self = shift;
  my $customer = shift;
  my $merchant = shift || $self->getGatewayAccount();

  my $errorMsg;
  eval {
    if (!$merchant) {
      $errorMsg = 'Failed to delete profile. No gateway account specified.';
      die;
    }

    if (!$customer) {
      $errorMsg = 'Failed to delete profile. No customer specified.';
      die;
    }

    my $dbs = new PlugNPay::DBConnection();

    my $columns = $dbs->getColumnsForTable({ database => $merchant, table => 'customer' });
    my %data = map { $_ => '' } keys %{$columns};

    # Delete the username column since we want to preserve the case stored in the database
    delete $data{'username'};

    # Set status to 'DELETED'
    $data{'status'} = 'DELETED';

    # Build query
    my $query = 'UPDATE customer SET ' .
                   join(',',map { $_ . ' = ?' } keys %data) .
                'WHERE LOWER(username) = LOWER(?)';

    my @values = (values %data,$customer);

    my $sth = $dbs->prepare($merchant,$query) or die $DBI::errstr;
    $sth->execute(@values) or die $DBI::errstr;
  };

  if ($@) {
    if (!$errorMsg) {
      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'recurring_attendant' });
      $logger->log({ 'error' => $@,
                     'subroutine' => 'deleteProfile',
                     'customer' => $customer,
                     'merchant' => $merchant });
      $errorMsg = 'Failed to delete profile.';
    }

    return { 'status' => 0, 'errorMessage' => $errorMsg };
  }

  return { 'status' => 1 };
}

sub savePassword {
  my $self = shift;
  my $merchant = shift || $self->getGatewayAccount();
  my $customer = shift || $self->getUsername();
  my $password = shift || $self->getPassword();

  my $errorMsg;
  eval {
    if (!$merchant) {
       $errorMsg = 'Failed to save password. No gateway account specified.';
       die;
    }

    if (!$customer) {
       $errorMsg = 'Failed to save password. No customer specified.';
       die;
    }

    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare($merchant, q/UPDATE customer
                                         SET password = ?
                                         WHERE LOWER(username) = LOWER(?)/);
    $sth->execute($password, $customer);
  };

  if ($@) {
    if (!$errorMsg) {
       my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'recurring_attendant' });
       $logger->log({ 'error' => $@,
		      'subroutine' => 'savePassword',
		      'customer' => $customer,
		      'merchant' => $merchant });
       $errorMsg = 'Failed to save password';
    }

    return { 'status' => 0, 'errorMessage' => $errorMsg };
  }

  return { 'status' => 1 };
}

1;
