package PlugNPay::API::REST::WebHook;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::ResponseLink;
use PlugNPay::API::Key::Name;
use PlugNPay::Util::StackTrace;
use PlugNPay::GatewayAccount::InternalID;
use PlugNPay::Logging::Performance;
use PlugNPay::API::REST::Context;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $params = shift;
  my $responderID = $params->{'responderID'};
  my $hookName = $params->{'hookName'};

  if ($responderID && $hookName) {
    $self->setResponderID($responderID);
    $self->setHookName($hookName);
    $self->load();
  }

  return $self;
}

sub setID {
  my $self = shift;
  $self->{'id'} = shift;
}

sub getID {
  my $self = shift;
  if (!defined $self->{'id'}) {
    die('ID not loaded. ' . new PlugNPay::Util::StackTrace()->string());
  }
  return $self->{'id'};
}

sub setResponderID {
  my $self = shift;
  $self->{'responderID'} = shift;
}

sub getResponderID {
  my $self = shift;
  return $self->{'responderID'};
}

sub setHookName {
  my $self = shift;
  $self->{'hookName'} = shift;
}

sub getHookName {
  my $self = shift;
  return $self->{'hookName'};
}

sub setDescription {
  my $self = shift;
  $self->{'description'} = shift;
}

sub getDescription {
  my $self = shift;
  return $self->{'description'};
}

sub setPublic {
  my $self = shift;
  $self->{'public'} = (shift @_ ? 1 : 0);
}

sub getPublic {
  my $self = shift;
  return $self->{'public'};
}

sub setDeprecated {
  my $self = shift;
  $self->{'deprecated'} = (shift @_ ? 1 : 0);
}

sub getDeprecated {
  my $self = shift;
  return $self->{'deprecated'};
}

sub exists {
  my $self = shift;
  return $self->{'exists'};
}

# load giving priority to id, but most likely responder_id and hook_name will be used.
sub load {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();

  eval {
    my $sth = $dbs->prepare('pnpmisc',q/
      SELECT id, responder_id, hook_name, description, public, deprecated
        FROM api_webhook
       WHERE id = ? OR (responder_id = ? AND hook_name = ?)
    /) or die($DBI::errstr);

    $sth->execute($self->{'id'}, $self->{'responderID'}, $self->{'hookName'}) or die($DBI::errstr);

    my $result = $sth->fetchall_arrayref({});

    if ($result && $result->[0]) {
      my $row = $result->[0];
      $self->setID($row->{'id'});
      $self->setResponderID($row->{'responderID'});
      $self->setHookName($row->{'hookName'});
      $self->setDescription($row->{'description'});
      $self->setPublic($row->{'public'});
      $self->setDeprecated($row->{'deprecated'});
      $self->{'exists'} = 1;
    } else {
      $self->{'exists'} = undef;
    }
  };

  if ($@) {
    die("Failed to load webhook data.");
  }
}

sub save {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();

  eval {
    my $sth = $dbs->prepare('pnpmisc',q/
      INSERT INTO api_webhook
        (responder_id,hook_name,description,public,deprecated)
      VALUES
        (?,?,?,?,?)
      ON DUPLICATE KEY UPDATE
        responder_id = VALUES(responder_id),
        hook_name = VALUES(hook_name),
        description = VALUES(description),
        public = VALUES(public),
        deprecated = VALUES(deprecated)
    /) or die($DBI::errstr);

    $sth->execute($self->{'responderID'},
                  $self->{'hookName'},
                  $self->{'description'},
                  $self->{'public'},
                  $self->{'deprecated'}) or die($DBI::errstr);

    $self->load();
  };

  if ($@) {
    die("Failed to save webhook data.");
  }
}

sub call {
  my $self = shift;
  my $params = shift;
  my $customerID = $params->{'customerID'};
  my $keyName = $params->{'keyName'};
  my $contextID = $params->{'contextID'};
  my $responder = $params->{'responder'};
  my $data = $params->{'data'};

  my $webhookID = $self->getID();

  # get key id if keyName is present
  my $keyID;
  if ($keyName) {
    my $apiKey = new PlugNPay::API::Key::Name();
    $apiKey->setCustomerID($customerID);
    $apiKey->setName($keyName);
    $apiKey->load();
    $keyID = $apiKey->getID();
  }

  # get the urls for this webhook for this api key
  my $urls = PlugNPay::Merchant::API::Policy::urlsForWebHook({
    webhookID => $webhookID,
    keyID => $keyID,
    customerID => $customerID,
    contextID => $contextID
  });

  my $rl = new PlugNPay::ResponseLink();

  my $internalIDObj = new PlugNPay::GatewayAccount::InternalID();
  my $username = $internalIDObj->getUsernameFromId($customerID);

  my $contextObj = new PlugNPay::API::REST::Context();
  $contextObj->setID($contextID);
  $contextObj->load();
  my $context = $contextObj->getName();

  my $dataWrapper = {};
  $dataWrapper->{'data'} = $data->{'data'};
  $dataWrapper->{'keyName'} = $keyName;
  $dataWrapper->{'context'} = $context;
  $dataWrapper->{'apiPath'} = '/' . join('/',@{$responder->getResourcePath()});
  $dataWrapper->{'resourceData'} = $responder->getResourceData();
  $dataWrapper->{'responseCode'} = $responder->getResponseCode();

  $rl->setUsername($username);
  $rl->setRequestMethod('POST');
  $rl->setRequestContentType('application/json');
  $rl->setRequestData($dataWrapper);
  $rl->setRequestTimeout(5); # this really should be long enough...

  foreach my $url (@{$urls}) {
    $rl->setRequestURL($url);
    new PlugNPay::Logging::Performance('Starting call for hookName "result" to url: $url.');
    $rl->doRequest();
    new PlugNPay::Logging::Performance('Completed call for hookName "result" to url: $url.');
  }
}


1;
