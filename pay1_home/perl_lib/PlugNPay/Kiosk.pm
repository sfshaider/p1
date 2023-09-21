package PlugNPay::Kiosk;

use strict;
use POSIX;
use PlugNPay::Util::UniqueID;
use PlugNPay::DBConnection;


sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  my $sessionGenerator = new PlugNPay::Util::UniqueID();
  $sessionGenerator->generate();
  $self->{'session'} = $sessionGenerator->inHex();

  $self->{'dbh'} = PlugNPay::DBConnection::database('pnpmisc');

  return $self;
}


# returns a hash, kiosk id is key, url is the value
sub kioskIDListForUsername {
  my $self = shift;
  my $username = shift;

  $username = $self->filterUsername($username);

  my $sth = $self->{'dbh'}->prepare(q/ SELECT kiosk_id,url FROM kiosk_ids
                                       WHERE username = ?
                                    /) or die($DBI::errstr);

  $sth->execute($username);

  my %results;

  while (my $row = $sth->fetchrow_hashref) {
    $results{$row->{'kiosk_id'}} = $row->{'url'};
  }
  
  return %results;
}

# returns the url for a kioskID, returning the default url if it exists if a specific url for that kiosk id does not exist
sub urlForKioskIDForUsername
{
  my $self = shift;
  my ($kioskID,$username) = @_;

  $username = $self->filterUsername($username);
  $kioskID =~ $self->filterKioskID($kioskID);


  my $sth = $self->{'dbh'}->prepare(q/ SELECT url FROM kiosk_ids 
                             WHERE username = ? 
                             AND kiosk_id = ? 
                          /) or die($DBI::errstr);

  $sth->execute($username,$kioskID) or die($DBI::errstr);
  my $result = $sth->fetchrow_hashref;
  if ($result) {
    return $result->{'url'};
  } else {
    my $defaultURL = $self->defaultURLForUsername($username);
    if ($defaultURL ne '') {
      return $self->defaultURLForUsername($username) . $kioskID;
    }
  }
}


sub urlForKioskIDForUsernameExists
{
  my $self = shift;
  my ($kioskID,$username) = @_;
 
  $username =~ s/[^A-z0-9]//g;
  $kioskID =~ s/[^A-z0-9_\-]//g;

  my $sth = $self->{'dbh'}->prepare(q/ SELECT count(url) AS id_exists FROM kiosk_ids
                                       WHERE username = ?
                                       AND kiosk_id = ?
                          /) or die($DBI::errstr);

  $sth->execute($username,$kioskID) or die($DBI::errstr);
  my $row = $sth->fetchrow_hashref;
  if ($row->{'id_exists'} == 1) {
    return 1;
  }
  return 0;
}

sub setURLForKioskIDForUsername
{
  my $self = shift;
  my ($url,$kioskID,$username) = @_;

  $url =~ s/[`"\>#<']//g;
  $username =~ s/[^A-z0-9]//g;
  $kioskID =~ s/[^A-z0-9_\-]//g;

  my $sth;

  if ($self->urlForKioskIDForUsernameExists($kioskID,$username)) {
    $sth = $self->{'dbh'}->prepare(q/ UPDATE kiosk_ids
                            SET url = ?
                            WHERE username = ?
                            AND kiosk_id = ?
                         /) or die($DBI::errstr);
  } else {
    $sth = $self->{'dbh'}->prepare(q/ INSERT INTO kiosk_ids (url,username,kiosk_id)
                            VALUES (?,?,?)
                         /) or die($DBI::errstr);
  }
  
  $sth->execute($url,$username,$kioskID);
  $sth->finish;
}

sub deleteKioskIDForUsername
{
  my $self = shift;
  my ($kioskID,$username) = @_;

  $kioskID = $self->filterKioskID($kioskID);
  $username = $self->filterUsername($username);

  my $sth = $self->{'dbh'}->prepare(q/ DELETE FROM kiosk_ids
                                      WHERE kiosk_id = ?
                                      AND username = ?
                                   /) or die($DBI::errstr);

  $sth->execute($kioskID,$username);
  $sth->finish;
}



# returns the default url for a username, if one exists
sub defaultURLForUsername
{
  my $self = shift;
  my ($username) = @_;

  $username =~ s/[^A-z0-9]//g;


  my $sth = $self->{'dbh'}->prepare(q/ SELECT url FROM kiosk_default_urls 
                                       WHERE username = ? 
                                    /) or die "$DBI::errstr";

  $sth->execute($username) or die "$DBI::errstr";
  my $result = $sth->fetchrow_hashref;

  my $url;

  if ($result) {
    $url = $result->{'url'};
  } else {
    $url = undef;
  }

  return $url;
}



# set a default URL for a username
sub setDefaultURLForUsername
{
  my $self = shift;
  my ($defaultURL,$username) = @_;

  $username =~ s/[^A-z0-9]//g;
  $defaultURL =~ s/[`"\>#<']//g;


  my $currentURL = $self->defaultURLForUsername($username);

  my $sth = undef;


  if (defined $currentURL) 
  {
    # do an update
    $sth = $self->{'dbh'}->prepare(q/ UPDATE kiosk_default_urls
                            SET url = ?
                            WHERE username = ?
                         /);
  } else {
    # do an insert
    $sth = $self->{'dbh'}->prepare(q/ INSERT INTO kiosk_default_urls (url,username)
                            VALUES (?,?)
                         /);
  }

  $sth->execute($defaultURL,$username);
  $sth->finish;
}



sub deleteDefaultURLForUsername
{
  my $self = shift;
  my ($username) = @_;

  $username =~ s/[^A-z0-9]//g;

  
  my $sth = $self->{'dbh'}->prepare(q/ DELETE FROM kiosk_default_urls
                             WHERE username = ?
                          /);

  $sth->execute($username);
  $sth->finish;
}



sub DESTROY
{
  my $self = shift;
  $self->{'dbh'}->disconnect();

  if ($self->{'kioskFileHandle'}) {
    close($self->{'kioskFileHandle'});
    delete $self->{'kioskFileHandle'};
  }
}


sub filterURL {
  my $self = shift;
  my $url = shift;
  $url =~ s/[`"\>#<']//g;
  return $url;
}

sub filterUsername {
  my $self = shift;
  my $username = shift;
  $username =~ s/[^A-z0-9]//g;
  return $username;
}

sub filterKioskID {
  my $self = shift;
  my $kioskID = shift;
  $kioskID =~ s/[^A-z0-9_\-]//g;
  return $kioskID;
}

1;
