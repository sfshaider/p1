package PlugNPay::Recurring::Attendant;

use strict;

use JSON;
use PlugNPay::DBConnection;
use PlugNPay::Util::UniqueID;
use PlugNPay::API::REST::Session;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::RandomString;
use PlugNPay::ResponseLink::Microservice;
use PlugNPay::Environment;
use PlugNPay::Authentication;
use PlugNPay::Recurring::Username;

sub new {
  my $class = shift;
  my $self = {};

  bless $self,$class;

  return $self;
}

sub getSessionID {
  my $self = shift;

  return $self->{'sessionID'};
}

sub setSessionID {
  my $self = shift;
  my $sessionID = shift;

  $self->{'sessionID'} = $sessionID;
}

sub setURL {
  my $self = shift;
  my $url = shift;

  $self->{'url'} = $url;
}

sub getURL {
  my $self = shift;

  return $self->{'url'};
}

sub getCustomer {
  my $self = shift;

  return $self->{'customer'};
}

sub setCustomer {
  my $self = shift;
  my $customer = shift;

  $self->{'customer'} = $customer;
}

sub setMerchant {
  my $self = shift;
  my $merchant = shift;

  $self->{'merchant'} = $merchant;
}

sub getMerchant {
  my $self = shift;

  return $self->{'merchant'};
}

sub getPassword {
  my $self = shift;

  return $self->{'password'};
}

sub setPassword {
  my $self = shift;
  my $password = shift;

  $self->{'password'} = $password;
}

sub setAdditionalData {
  my $self = shift;
  my $data = shift;

  $self->{'additionalData'} = $data;
}

sub getAdditionalData {
  my $self = shift;

  return $self->{'additionalData'};
}

sub getSections {
  my $self = shift;

  return $self->{'additionalData'}{'sections'} || [];
}

sub createCredentials {
  my $self = shift;
  my $merchant = shift || $self->getMerchant();
  my $customer = shift || $self->getCustomer();

  my $domain = PlugNPay::Authentication::getDomain();
  my $url = $domain . '/recatten/user/' . $merchant;
  my $responseLink = new PlugNPay::ResponseLink::Microservice();

  $responseLink->setURL($url);
  $responseLink->setContentType('application/json');
  $responseLink->setContent({
    login    => $customer,
    password => $self->getPassword(),
    encrypt => 'false'
  });

  $responseLink->setMethod('POST');
  $responseLink->doRequest();

  my $response = $responseLink->getDecodedResponse();

  if($response->{'status'} =~ /success/i && $responseLink->getResponseCode() == 201) {
    $self->setURL('https://' . new PlugNPay::Environment()->get('PNP_SERVER_NAME') . '/recurring/startsession.cgi?session=' . $self->getSessionID());
    return 1;
  }
  return 0;
}


sub saveAttendantSession {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  $dbs->begin('pnpmisc');

  $self->setSessionID(new PlugNPay::API::REST::Session(new PlugNPay::Util::UniqueID()->inHex())->getSessionID());
  $self->setPassword(new PlugNPay::Util::RandomString()->randomAlphaNumeric(16));

  my $sth = $dbs->prepare('pnpmisc', q/
               INSERT INTO recurring_attendant_session_auth(merchant,customer,password,session_id,additional_data)
               VALUES(?,?,?,?,?) /);

  $sth->execute($self->getMerchant(), $self->getCustomer(), $self->getPassword(), $self->getSessionID(), encode_json($self->getAdditionalData()))  or die $DBI::errstr;

  if (!$self->createCredentials()) {
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'Attendant'});
    $logger->log({'status' => 'FAILURE', 'message' => 'Failed to create session credentials.'});
    $dbs->rollback('pnpmisc');
    return 0;
  }

  $dbs->commit('pnpmisc');
  return 1;
}

sub doesAttendantSessionExist {
  my $self = shift;
  my $sessionID = shift || $self->getSessionID();

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc', q/
    SELECT COUNT(session_id) as `exists`
    FROM recurring_attendant_session_auth
    WHERE session_id = ? /);

  $sth->execute($sessionID);

  my $row = $sth->fetchall_arrayref({});

  return $row->[0]{'exists'};
}

sub loadAttendantSession {
  my $self = shift;
  my $sessionID = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc', q/
            SELECT id, customer, password, merchant, additional_data
            FROM recurring_attendant_session_auth
            WHERE session_id = ? /);

  $sth->execute($sessionID) or die $DBI::errstr;

  my $row = $sth->fetchall_arrayref({});

  if($row->[0]) {
    $self->setSessionID($sessionID);
    $self->setPassword($row->[0]{'password'});
    $self->setCustomer($row->[0]{'customer'});
    $self->setMerchant($row->[0]{'merchant'});
    eval {
      $self->setAdditionalData(decode_json($row->[0]{'additional_data'}));
    };

    if ($@) {
      $self->setAdditionalData({});
    }
  }
}

sub removeAttendantSession {
  my $self = shift;
  my $sessionID = shift || $self->getSessionID();

  my $dbs = new PlugNPay::DBConnection();

  eval {
    my $sth = $dbs->prepare('pnpmisc', q/
              DELETE FROM recurring_attendant_session_auth
              WHERE session_id = ? /);
    $sth->execute($sessionID) or die $DBI::errstr;
  };

  if($@) {
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'Attendant'});
    $logger->log({'status' => 'FAILURE', 'message' => 'Failed to delete session.'});
    return 0;
  }

  return 1;
}

sub doesCustomerExist {
  my $self = shift;
  my $merchant = shift || $self->getMerchant();
  my $customer = lc shift || lc $self->getCustomer();
  my $exists = PlugNPay::Recurring::Username::exists({ merchant => $merchant, username => $customer });
  return $exists;
}

# sub doesCustomerExist {
#   my $self = shift;
#   my $merchant = shift || $self->getMerchant();
#   my $customer = lc shift || lc $self->getCustomer();
#   my $exists;
#   eval {
#     my $dbs = new PlugNPay::DBConnection();
#     my $sth = $dbs->prepare($merchant, q/
#     SELECT COUNT(username) as `exists`
#     FROM customer
#     WHERE LOWER(username) = ? /);
#     $sth->execute($customer) or die $DBI::errstr;
#
#     my $row = $sth->fetchall_arrayref({});
#     $exists = $row->[0]{'exists'};
#   };
#   if($@) {
#     my $logger = new PlugNPay::Logging::DataLog({'collection' => 'Attendant'});
#     $logger->log({'status' => 'FAILURE', 'message' => 'Failed to query customer from merchant database.'});
#   }
#   return $exists;
# }

1;
