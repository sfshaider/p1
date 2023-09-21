package PlugNPay::Merchant::API::WebHook;

use strict;
use PlugNPay::DBConnection;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub setID {
  my $self = shift;
  $self->{'id'} = shift;
}

sub getID {
  my $self = shift;
  if (!defined $self->{'id'}) {
    die ('ID not loaded.');
  }
  return $self->{'id'};
}

sub setPolicyID {
  my $self = shift;
  $self->{'policyID'} = shift;
}

sub getPolicyID {
  my $self = shift;
  return $self->{'policyID'};
}

sub setUrlID {
  my $self = shift;
  $self->{'urlID'} = shift;
}

sub getUrlID {
  my $self = shift;
  return $self->{'urlID'};
}

sub setWebHookID {
  my $self = shift;
  $self->{'webhookID'} = shift;
}

sub getWebHookID {
  my $self = shift;
  return $self->{'webhookID'};
}

sub load {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();

  eval {
    my $sth = $dbs->prepare('pnpmisc',q/
      SELECT id, policy_id, url_id, webhook_id
        FROM merchant_api_policy_webhook
       WHERE id = ? OR (policy_id = ? AND url_id = ? AND webhook_id = ?)
    /) or die($DBI::errstr);

    $sth->execute($self->{'id'},
                  $self->{'policyID'},
                  $self->{'urlID'},
                  $self->{'webhookID'}) or die($DBI::errstr);
  };

  if ($@) {
    die("Failed to load merchant webhook setting.");
  }
}

sub save {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();

  eval {
    # insert ignore because entire row, besides id, is unique
    my $sth = $dbs->prepare('pnpmisc',q/
      INSERT IGNORE INTO merchant_api_policy_webhook
        (policy_id,url_id,webhook_id)
      VALUES
        (?,?,?)
    /) or die($DBI::errstr);
  
    $sth->execute($self->{'policyID'},
                  $self->{'urlID'},
                  $self->{'webhookID'}) or die($DBI::errstr);

    $self->load();
  };

  if ($@) {
    die("Failed to apply merchant webhook setting.");
  }
}
 
1;
