package PlugNPay::GatewayAccount::Uplift;

use strict;
use PlugNPay::Contact;
use PlugNPay::DBConnection;
use PlugNPay::ResponseLink;
use PlugNPay::GatewayAccount;
use JSON::XS;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $gatewayAccount = shift;
  $self->setGatewayAccount($gatewayAccount);

  $self->{'apiUrl'} = $ENV{'PNP_UPLIFT_API'} || 'http://api.delivrd.co/v1/users/';

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

sub getUpliftKey{
  my $self = shift;
  my $key = $self->{'apiKey'};
   
  if (!defined $key) {
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbs->prepare(q/SELECT api_key 
                            FROM uplift_api_key 
                            WHERE key_name = ?
                           /);
  $sth->execute('plugnpay') or die $DBI::errstr;

  my $rows = $sth->fetchall_arrayref({});
  
    $key = $rows->[0]{'api_key'};
    $self->{'apiKey'} = $key;
  }
  
  return $key;
}

######################
#  Database Function #
######################

sub save {
  my $self = shift;
  my $data = shift;
  
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbs->prepare(q/
                           INSERT INTO uplift_account_information 
                           (merchant,login_url,uplift_id,status,creation_time) 
                           VALUES (?,?,?,?,?) 
                           /);
  $sth->execute($self->getGatewayAccount(),$data->{'autoLoginUrl'},$data->{'id'},$data->{'status'},$data->{'created'}) or die $DBI::errstr;
  $sth->finish();

  return {'id' => $data->{'id'}, 'login' => $data->{'autoLoginUrl'}};
}

sub update {
  my $self = shift;
  my $data = shift;
  
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbs->prepare(q/
                           UPDATE uplift_account_information SET
                           login_url = ?,status = ?,creation_time = ?
                           WHERE uplift_id = ?
                           /);
  $sth->execute($data->{'autoLoginUrl'},$data->{'status'},$data->{'created'},$data->{'id'}) or die $DBI::errstr;
  $sth->finish();

  return {'id' => $data->{'id'}, 'login' => $data->{'autoLoginUrl'}};
}

sub loadByID {
  my $self = shift;
  my $id = shift;
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbs->prepare(q/ SELECT login_url,status,creation_time,merchant
                             FROM uplift_account_information
                             WHERE uplift_id = ? 
                           /);
  $sth->execute($id) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  
  return $rows->[0];
}

sub loadByMerchant {
  my $self = shift;
  my $merchant = shift;
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbs->prepare(q/ SELECT login_url,status,creation_time,uplift_id
                             FROM uplift_account_information
                             WHERE merchant = ? 
                           /);
  $sth->execute($merchant) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});

  return $rows->[0];
}

sub exists {
  my $self = shift;
  my $id = shift;

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
  my $sth = $dbh->prepare(q/
    SELECT count(uplift_id) as `exists`
    FROM uplift_account_information
    WHERE uplift_id = ?
  /);

  $sth->execute($id) or die $DBI::errstr;

  my $results = $sth->fetchall_arrayref({});
  if ($results && $results->[0]) {
    return ($results->[0]{'exists'} == 1);
  } else {
    return 0;
  }
}

#################
# API functions #
#################

sub refreshUsers {
  my $self = shift;
  my $link = new PlugNPay::ResponseLink($self->getGatewayAccount(),$self->{'apiUrl'},{},'GET','JSON');
  $link->addHeader('accept','application/json');
  my $key = $self->getUpliftKey();
  $link->addRequestHeader('authorization',$key);
  $link->doRequest(1);
  my %responseHash = $link->getResponseAPIData();
  my $response = \%responseHash;
  my $upliftData = JSON::XS->new->utf8->decode($response->{'content'}{'data'});

  my $storedData = {};
  foreach my $user (@{$upliftData->{'data'}}){
    my $savedData = $self->update($user);   
    $storedData->{$savedData->{'id'}} = $savedData->{'login'};
  }

  return $storedData;
}

sub updateUser {
  my $self = shift;
  my $id = shift;
  my $data = shift;
  if ($self->exists($id)) {
    my $link = new PlugNPay::ResponseLink($self->getGatewayAccount(),$self->{'apiUrl'} . $id, $data, 'PATCH', 'JSON');
    $link->addHeader('accept','application/json');
    $link->setRequestContentType('application/x-www-form-urlencoded');
    $link->addRequestHeader('authorization',$self->getUpliftKey());
    $link->doRequest(1);
  
    my %responseHash = $self->getResponseAPIData();
    my $response = \%responseHash;
    my $upliftData = JSON::XS->new->utf8->decode($response->{'content'}{'data'});

    return $self->update($upliftData->{'data'});
  
  } else {
    return $self->createUser();
  }
}

sub createUser {
  my $self = shift;

  unless (defined $self->getGatewayAccount()) {die "Need to set username before creating account";}

  my $gatewayAccount = new PlugNPay::GatewayAccount($self->getGatewayAccount());
  my $apiKey = $self->getUpliftKey();

  my $contact = $gatewayAccount->getMainContact();
  my $info = {
                fullName => $contact->getFullName(),
                email    => $contact->getEmailAddress()
             };
  my $link = new PlugNPay::ResponseLink($gatewayAccount->getGatewayAccountName(),$self->{'apiUrl'},$info,'POST','JSON');
  $link->addHeader('accept','application/json');
  $link->setRequestContentType('application/x-www-form-urlencoded');
  $link->addRequestHeader('authorization',$apiKey);

  $link->doRequest(1);

  my %responseHash = $link->getResponseAPIData();
  my $response = \%responseHash;
  my $upliftData = JSON::XS->new->utf8->decode($response->{'content'}{'data'});

  return $self->save($upliftData->{'data'});
}

sub getUser {
  my $self = shift;
  my $id = shift;

  if (!defined $id) {
    $id = $self->getUpliftID();
  }

  return $self->_getUser($id);
}

sub getAllUser {
  my $self = shift;
  return $self->_getUser();
}

sub _getUser {
  my $self = shift;
  my $id = shift;
  my $link = new PlugNPay::ResponseLink($self->getGatewayAccount(), $self->{'apiUrl'} . $id, {},'GET','JSON');
  $link->addRequestHeader('authorization',$self->getUpliftKey());
  $link->addHeader('accept','application/json');
  $link->doRequest(1);
  my %responseHash = $link->getResponseAPIData();
  my $response = \%responseHash;
  my $upliftData = JSON::XS->new->utf8->decode($response->{'content'}{'data'});

  return $upliftData->{'data'};
}

##################
# Misc Functions #
##################
sub retrieveLogin {
  my $self = shift;
  my $username = shift;

  if (!defined $username) {
    $username = $self->getGatewayAccount();
  }

  my $data = $self->loadByMerchant($username);

  return $data->{'login_url'};
}

sub getUpliftID {
  my $self = shift;
  my $username = shift;
  
  if (!defined $username) {
    $username = $self->getGatewayAccount;
  }

  my $data = $self->loadByMerchant($username);

  return $data->{'uplift_id'};
}

1;
