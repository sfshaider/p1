package PlugNPay::Merchant::API::Policy;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::RandomString;
use PlugNPay::API::REST::WebHook;
use PlugNPay::Debug;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $random = uc new PlugNPay::Util::RandomString()->randomAlphaNumeric(12);
  $self->setPolicyNumber($random);

  return $self;
}

sub setID {
  my $self = shift;
  $self->{'id'} = shift;
}

sub getID {
  my $self = shift;
  if (!defined $self->{'id'}) {
    die('ID not loaded.');
  }
  return $self->{'id'};
}

sub setPolicyNumber {
  my $self = shift;
  $self->{'policyNumber'} = shift;
}

sub getPolicyNumber {
  my $self = shift;
  return $self->{'policyNumber'};
}

sub setCustomerID {
  my $self = shift;
  $self->{'customerID'} = shift;
}

sub getCustomerID {
  my $self = shift;
  return $self->{'customerID'};
}

sub setName {
  my $self = shift;
  $self->{'name'} = shift;
}

sub getName {
  my $self = shift;
  return $self->{'name'};
}

sub load {
  my $self = shift;


  my $dbs = new PlugNPay::DBConnection();

  eval {
    my $sth = $dbs->prepare('pnpmisc',q/
      SELECT id,policy_number,customer_id,name
        FROM merchant_api_policy
       WHERE id = ? OR (customer_id = ? AND policy_number = ?) OR (customer_id = ? AND name = ?)
    /) or die($DBI::errstr);

    $sth->execute($self->{'id'},
                  $self->{'customerID'},$self->{'policyNumber'},
                  $self->{'customerID'},$self->{'name'}) or die($DBI::errstr);

    my $result = $sth->fetchall_arrayref({}) or die($DBI::errstr);

    if ($result && $result->[0]) {
      my $row = $result->[0];
      $self->setID($row->{'id'});
      $self->setCustomerID($row->{'customer_id'});
      $self->setPolicyNumber($row->{'policy_number'});
      $self->setName($row->{'name'});
    }
  };

  if ($@) {
    die('Failed to load policy.');
  }
}

sub save {
  my $self = shift;

  eval {
    if (defined $self->{'id'} || $self->policyNumberExists()) {
      $self->_update();
      $self->load();
    } else {
      my $dbs = new PlugNPay::DBConnection();

      my $sth = $dbs->prepare('pnpmisc',q/
        INSERT IGNORE into merchant_api_policy
          (customer_id,policy_number,name)
        VALUES
          (?,?,?)
      /) or die($DBI::errstr);

      $sth->execute($self->{'customerID'},$self->{'policyNumber'},$self->{'name'}) or die($DBI::errstr);

      $self->load();
    }
  };

  if ($@) {
    die('Failed to save policy.');
  }
}

sub _update {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();

  eval {
    my $sth = $dbs->prepare('pnpmisc',q/
      UPDATE merchant_api_policy
         SET name = ?
       WHERE id = ? OR (customer_id = ? AND policy_number = ?)
    /) or die($DBI::errstr);

    $sth->execute($self->{'id'},$self->{'customerID'}, $self->{'policyNumber'}) or die($DBI::errstr);
  };

  if ($@) {
    die('Failed to update policy.');
  }
}

sub policyNumberExists {
  my $self = shift;

  my $exists = 0;

  my $dbs = new PlugNPay::DBConnection();

  eval {
    my $sth = $dbs->prepare('pnpmisc',q/
      SELECT count(id)
        FROM merchant_api_policy
       WHERE customer_id = ? AND policy_number = ?
    /) or die($DBI::errstr);

    $sth->execute($self->{'customerID'},$self->{'policyNumber'}) or die($DBI::errstr);

    my $result = $sth->fetchrow_arrayref();


    if ($result && $result->[0]) {
      $exists = $result->[0][0];
    }
  };

  if ($@) {
    die('Failed to check if policy number exists.');
  }

  return $exists;
}

sub linkToAPIKey {
  my $self = shift;
  my $apiKeyID = shift;


  if ($self->validateLink($apiKeyID)) {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnpmisc',q/
      INSERT INTO merchant_api_policy_api_key_link
        (policy_id,key_id)
      VALUES
        (?,?)
    /);

    $sth->execute($self->getID(),$apiKeyID);
  }
}

sub unlinkFromAPIKey {
  my $self = shift;
  my $apiKeyID = shift;

  if ($apiKeyID) {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnpmisc',q/
      DELETE FROM merchant_api_policy_api_key_link
       WHERE policy_id = ? AND key_id = ?
    /);

    $sth->execute($self->getID(),$apiKeyID);
  }
}

sub validateLink {
  my $self = shift;
  my $apiKeyID = shift;

  my $apiKey = new PlugNPay::API::Key();
  $apiKey->setID($apiKeyID);
  $apiKey->load();

  my $policy = new PlugNPay::Merchant::API::Policy();
  $policy->setID($self->{'policyID'});
  $policy->load();

  # only valid if the customer id's are the same
  return ($apiKey->getCustomerID() == $policy->getCustomerID());
}

sub urlsForWebHook {
  my $self = shift;
  my $params = shift || $self;

  my $keyID = $params->{'keyID'};
  my $contextID = $params->{'contextID'};
  my $webhookID = $params->{'webhookID'};
  my $customerID = $params->{'customerID'};
  my @urls;

  my @values = ($webhookID);

  my $query;

  if (defined $params->{'keyID'}) {
    $query = q/
      SELECT DISTINCT wawu.url as url
        FROM merchant_api_webhook_url wawu,
             merchant_api_policy_webhook mapw,
             merchant_api_policy mpol,
             merchant_api_policy_api_key_link mapakl,
             api_webhook wh
       WHERE mapw.webhook_id = ?
         AND mapw.policy_id = mpol.id  AND mapw.url_id = wawu.id
         AND mapw.policy_id = mapakl.policy_id AND mapakl.key_id = ?
    /;
    push @values,$keyID;
  } else {
    $query = q/
      SELECT DISTINCT wawu.url as url
        FROM merchant_api_webhook_url wawu,
             merchant_api_policy_webhook mapw,
             merchant_api_policy mpol,
             merchant_api_policy_context_link mapcl,
             api_webhook wh
       WHERE mapw.webhook_id = ?
         AND mapw.policy_id = mpol.id  AND mapw.url_id = wawu.id
         AND mapw.policy_id = mapcl.policy_id AND mapcl.context_id = ?
         AND mpol.customer_id = ?/;
    push @values,$contextID;
    push @values,$customerID;

    debug { query => $query, values => \@values };
  }

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnpmisc',$query);
    $sth->execute(@values) or die($DBI::errstr);

    my $results = $sth->fetchall_arrayref({}) or die($DBI::errstr);
    if ($results) {
      foreach my $row (@{$results}) {
        push @urls,$row->{'url'};
      }
    }
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({ collection => 'restful_api' });
    $logger->log({error => $@, keyID => $keyID, contextID => $contextID, webhookID => $webhookID}, {"stackTraceEnabled" => 1});
  }

  return \@urls;
}

1;
