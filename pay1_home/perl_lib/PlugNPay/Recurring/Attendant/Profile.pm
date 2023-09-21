package PlugNPay::Recurring::Attendant::Profile;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;

sub new {
  my $class = shift; 
  my $self = {};
  bless $self, $class;

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

sub setAddr1 {
  my $self = shift;
  my $addr1 = shift;
  $self->{'addr1'} = $addr1;
}

sub getAddr1 {
  my $self = shift;
  return $self->{'addr1'};
}

sub setAddr2 {
  my $self = shift;
  my $addr2 = shift;
  $self->{'addr2'} = $addr2;
}

sub getAddr2 {
  my $self = shift;
  return $self->{'addr2'};
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

sub setZip {
  my $self = shift;
  my $zip = shift;
  $self->{'zip'} = $zip;
}

sub getZip {
  my $self = shift;
  return $self->{'zip'};
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

sub setShippingAddr1 {
  my $self = shift;
  my $shipaddr1 = shift;
  $self->{'shipaddr1'} = $shipaddr1;
}

sub getShippingAddr1 {
  my $self = shift;
  return $self->{'shipaddr1'};
}

sub setShippingAddr2 {
  my $self = shift;
  my $shipaddr2 = shift;
  $self->{'shipaddr2'} = $shipaddr2;
}

sub getShippingAddr2 {
  my $self = shift;
  return $self->{'shipaddr2'};
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

sub setShippingZip {
  my $self = shift;
  my $shipzip = shift;
  $self->{'shipzip'} = $shipzip;
}

sub getShippingZip {
  my $self = shift;
  return $self->{'shipzip'};
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
  $self->{'phone'} = $phone;
}

sub getPhone {
  my $self = shift;
  return $self->{'phone'};
}

sub setFax {
  my $self = shift;
  my $fax = shift;
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

sub setMonthly {
  my $self = shift;
  my $monthly = shift;
  $self->{'monthly'} = $monthly;
}

sub getMonthly {
  my $self = shift;
  return $self->{'monthly'};
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
  $self->{'balance'} = $balance;
}

sub getBalance {
  my $self = shift;
  return $self->{'balance'};
}

sub loadProfile {
  my $self = shift;
  my $customer = lc shift;
  my $merchant = shift || $self->getGatewayAccount();

  my $errorMsg;
  eval {
    if ($merchant && $customer) {
      my $dbs = new PlugNPay::DBConnection();
      my $sth = $dbs->prepare($merchant, q/SELECT username,
                                                  name,
                                                  email,
                                                  password,
                                                  company,
                                                  addr1,
                                                  addr2,
                                                  city,
                                                  state,
                                                  zip,
                                                  country,
                                                  shipname,
                                                  shipaddr1,
                                                  shipaddr2,
                                                  shipcity,
                                                  shipstate,
                                                  shipzip,
                                                  shipcountry,
                                                  phone,
                                                  fax,
                                                  status,
                                                  monthly,
                                                  balance,
                                                  billcycle,
                                                  startdate,
                                                  enddate
                                           FROM customer
                                           WHERE LOWER(username) = ?/) or die $DBI::errstr;
      $sth->execute($customer) or die $DBI::errstr;

      my $rows = $sth->fetchall_arrayref({});
      if (@{$rows} > 0) {
        my $row = $rows->[0];
        $self->setUsername($row->{'username'});
        $self->setName($row->{'name'});
        $self->setEmail($row->{'email'});
        $self->setPassword($row->{'password'});
        $self->setCompany($row->{'company'});
        $self->setAddr1($row->{'addr1'});
        $self->setAddr2($row->{'addr2'});
        $self->setCity($row->{'city'});
        $self->setState($row->{'state'});
        $self->setZip($row->{'zip'});
        $self->setCountry($row->{'country'});
        $self->setShippingName($row->{'shipname'});
        $self->setShippingAddr1($row->{'shipaddr1'});
        $self->setShippingAddr2($row->{'shipaddr2'});
        $self->setShippingCity($row->{'shipcity'});
        $self->setShippingState($row->{'shipstate'});
        $self->setShippingZip($row->{'shipzip'});
        $self->setShippingCountry($row->{'shipcountry'});
        $self->setPhone($row->{'phone'});
        $self->setFax($row->{'fax'});
        $self->setStatus($row->{'status'});
        $self->setMonthly($row->{'monthly'});
        $self->setBalance($row->{'balance'});
        $self->setBillCycle($row->{'billcycle'});
        $self->setStartDate($row->{'startdate'});
        $self->setEndDate($row->{'enddate'});
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

sub saveProfile {
  my $self = shift;
  my $data = shift;
  my $customer = lc shift;
  my $merchant = shift || $self->getGatewayAccount();

  my $errorMsg;
  eval {
    if (!$merchant) {
      $errorMsg = 'Failed to save profile. No gateway account specified.';
      die;
    }

    if (!$customer) {
      $errorMsg = 'Failed to save profile. No customer specified.';
      die;
    }

    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare($merchant, q/INSERT into customer
                                         ( username,
                                           name,
                                           email,
                                           password,
                                           company,
                                           addr1,
                                           addr2,
                                           city,
                                           state,
                                           zip,
                                           country,
                                           shipname,
                                           shipaddr1,
                                           shipaddr2,
                                           shipcity,
                                           shipstate,
                                           shipzip,
                                           shipcountry,
                                           phone,
                                           fax,
                                           status,
                                           startdate,
                                           enddate,
                                           billcycle,
                                           monthly,
                                           balance )
                                         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)/) or die $DBI::errstr;
    $sth->execute($customer,
                  $data->{'name'},
                  $data->{'email'},
                  $data->{'password'},
                  $data->{'company'},
                  $data->{'addr1'},
                  $data->{'addr2'},
                  $data->{'city'},
                  $data->{'state'},
                  $data->{'zip'},
                  $data->{'country'},
                  $data->{'shippingName'},
                  $data->{'shippingAddr1'},
                  $data->{'shippingAddr2'},
                  $data->{'shippingCity'},
                  $data->{'shippingState'},
                  $data->{'shippingZip'},
                  $data->{'shippingCountry'},
                  $data->{'phone'},
                  $data->{'fax'},
                  $data->{'status'},
                  $data->{'startDate'},
                  $data->{'endDate'},
                  $data->{'billCycle'},
                  $data->{'recurringFee'},
                  $data->{'balance'}) or die $DBI::errstr;
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

sub updateProfile {
  my $self = shift;
  my $updateData = shift;
  my $customer = lc shift;
  my $merchant = shift || $self->getGatewayAccount();

  my $errorMsg;
  eval {
    if (!$merchant) {
      $errorMsg = 'Failed to update profile. No gateway account specified.';
      die;
    }

    if (!$customer) {
      $errorMsg = 'Failed to update profile. No customer specified.';
      die;
    }

    if (!$self->loadProfile($customer, $merchant)) {
      $errorMsg = 'Failed to update profile. Failed to load customer data.';
      die;
    }

    my $name        = (exists $updateData->{'name'}        ? $updateData->{'name'}        : $self->getName());
    my $email       = (exists $updateData->{'email'}       ? $updateData->{'email'}       : $self->getEmail());
    my $password    = (exists $updateData->{'password'}    ? $updateData->{'password'}    : $self->getPassword());
    my $company     = (exists $updateData->{'company'}     ? $updateData->{'company'}     : $self->getCompany());
    my $addr1       = (exists $updateData->{'addr1'}       ? $updateData->{'addr1'}       : $self->getAddr1());
    my $addr2       = (exists $updateData->{'addr2'}       ? $updateData->{'addr2'}       : $self->getAddr2());
    my $city        = (exists $updateData->{'city'}        ? $updateData->{'city'}        : $self->getCity());
    my $state       = (exists $updateData->{'state'}       ? $updateData->{'state'}       : $self->getState());
    my $zip         = (exists $updateData->{'zip'}         ? $updateData->{'zip'}         : $self->getZip());
    my $country     = (exists $updateData->{'country'}     ? $updateData->{'country'}     : $self->getCountry());

    my $shipname    = (exists $updateData->{'shippingName'}    ? $updateData->{'shippingName'}    : $self->getShippingName());
    my $shipaddr1   = (exists $updateData->{'shippingAddr1'}   ? $updateData->{'shippingAddr1'}   : $self->getShippingAddr1());
    my $shipaddr2   = (exists $updateData->{'shippingAddr2'}   ? $updateData->{'shippingAddr2'}   : $self->getShippingAddr2());
    my $shipcity    = (exists $updateData->{'shippingCity'}    ? $updateData->{'shippingCity'}    : $self->getShippingCity());
    my $shipstate   = (exists $updateData->{'shippingState'}   ? $updateData->{'shippingState'}   : $self->getShippingState());
    my $shipzip     = (exists $updateData->{'shippingZip'}     ? $updateData->{'shippingZip'}     : $self->getShippingZip());
    my $shipcountry = (exists $updateData->{'shippingCountry'} ? $updateData->{'shippingCountry'} : $self->getShippingCountry());

    my $phone       = (exists $updateData->{'phone'}        ? $updateData->{'phone'}        : $self->getPhone());
    my $fax         = (exists $updateData->{'fax'}          ? $updateData->{'fax'}          : $self->getFax());
    my $status      = (exists $updateData->{'status'}       ? $updateData->{'status'}       : $self->getStatus());
    my $startDate   = (exists $updateData->{'startDate'}    ? $updateData->{'startDate'}    : $self->getStartDate());
    my $endDate     = (exists $updateData->{'endDate'}      ? $updateData->{'endDate'}      : $self->getEndDate());
    my $monthly     = (exists $updateData->{'recurringFee'} ? $updateData->{'recurringFee'} : $self->getMonthly());
    my $balance     = (exists $updateData->{'balance'}      ? $updateData->{'balance'}      : $self->getBalance());
    my $billCycle   = (exists $updateData->{'billCycle'}    ? $updateData->{'billCycle'}    : $self->getBillCycle());

    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare($merchant, q/UPDATE customer
                                         SET name = ?,
                                             email = ?,
                                             password = ?,
                                             company = ?,
                                             addr1 = ?,
                                             addr2 = ?,
                                             city = ?,
                                             state = ?,
                                             zip = ?,
                                             country = ?,
                                             shipname = ?,
                                             shipaddr1 = ?,
                                             shipaddr2 = ?,
                                             shipcity = ?,
                                             shipstate = ?,
                                             shipzip = ?,
                                             shipcountry = ?,
                                             phone = ?,
                                             fax = ?,
                                             status = ?,
                                             startdate = ?,
                                             enddate = ?,
                                             monthly = ?,
                                             balance = ?,
                                             billcycle = ?
                                         WHERE LOWER(username) = ?/) or die $DBI::errstr;
    $sth->execute($name,
                  $email,
                  $password,
                  $company,
                  $addr1,
                  $addr2,
                  $city,
                  $state,
                  $zip,
                  $country,
                  $shipname,
                  $shipaddr1,
                  $shipaddr2,
                  $shipcity,
                  $shipstate,
                  $shipzip,
                  $shipcountry,
                  $phone,
                  $fax,
                  $status,
                  $startDate,
                  $endDate,
                  $monthly,
                  $balance,
                  $billCycle,
                  $customer) or die $DBI::errstr;
  };

  if ($@) {
    if (!$errorMsg) {
      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'recurring_attendant' });
      $logger->log({ 'error' => $@,
                     'subroutine' => 'updateProfile',
                     'customer' => $customer,
                     'merchant' => $merchant });
      $errorMsg = 'Failed to update profile.';
    }

    return { 'status' => 0, 'errorMessage' => $errorMsg };
  }

  return { 'status' => 1 };
}

sub deleteProfile {
  my $self = shift;
  my $customer = lc shift;
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
    my $sth = $dbs->prepare($merchant, q/DELETE
                                         FROM customer
                                         WHERE LOWER(username) = ?/) or die $DBI::errstr;
    $sth->execute($customer) or die $DBI::errstr;
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

1;
