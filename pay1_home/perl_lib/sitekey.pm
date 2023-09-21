#!/usr/bin/perl

use strict;
use miscutils;

package sitekey;


# Create a new instance of this object, then use that object to access all other methods!
sub new
{
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  $self->{'dbh'} = $self->connectToDB();

  return $self;
}


# the destructor, do not call this directly or you will be sorry.
sub _DESTROY
{
  my $self = shift;
  $self->disconnectFromDB();
}

# returns the domain for a sitekey
sub domainAndMerchantForSiteKey
{
  my $self = shift;
  my $siteKey = shift;

  my $sth = $self->getDBH()->prepare('select domain,merchant from merchant_sitekeys where sitekey = ?');
  $sth->execute($siteKey);

  if (my $row = $sth->fetchrow_hashref())
  {
    my $domain = $row->{'domain'};
    $domain =~ s/(https?:\/\/[^\/]+)\/.*/$1\//;
    return ($domain ,$row->{'merchant'});
  }
}


# generates a new sitekey that does not exist in the database
sub generateKey
{
  my $self = shift;

  my @characterSet = ('A'..'Z','a'..'z','0'..'9');
  
  my $randomKey = '';
  my $tryLimit = 100;
  while ($tryLimit-- > 0 && ($randomKey eq '' || $self->siteKeyExists($randomKey)))
  {
    for (my $x = 10; $x > 0; $x--)
    {
      $randomKey .= $characterSet[int(rand() * $#characterSet)];
    }
  }

  return $randomKey;
}

# add a domain for a merchant, returns the sitekey for that domain.
sub addDomainForMerchant
{
  my $self = shift;
  my ($domain,$merchant) = @_;

  $domain = $self->scrubDomain($domain);
  #$domain =~ s/\/+$//;
  $merchant = $self->scrubMerchant($merchant);

  if (!$self->domainExistsForMerchant($domain,$merchant))
  {
    my $newSiteKey = $self->generateKey();

    my $sth = $self->getDBH()->prepare('insert into merchant_sitekeys(sitekey,merchant,domain) values(?,?,?)');
    $sth->execute($newSiteKey,$merchant,$domain);
    $sth->finish;

    return $newSiteKey;
  }
}

# returns a hash of all sitekeys and domains.  sitekey is the key, domain is the value.
sub siteKeysForMerchant
{
  my $self = shift;
  my $merchant = shift;

  $merchant = $self->scrubMerchant($merchant);

  my %siteKeys;

  my $sth = $self->getDBH()->prepare('select sitekey,domain from merchant_sitekeys where merchant = ?');
  $sth->execute($merchant);

  while (my $row = $sth->fetchrow_hashref())
  {
    $row->{'domain'} =~ s/(https?:\/\/[^\/]+)\/.*/$1\//;
    $siteKeys{$row->{'sitekey'}} = $row->{'domain'};
  }

  $sth->finish;

  return %siteKeys;
}

# remove a sitekey from the database, validating that it exists for the merchant first
sub removeSiteKeyForMerchant
{
  my $self = shift;
  my $siteKey = shift;
  my $merchant = shift;

  # no need to scrub since each function called scrubs

  my %siteKeysForMerchant = $self->siteKeysForMerchant($merchant);

  if (exists $siteKeysForMerchant{$siteKey})
  {
    $self->removeSiteKey($siteKey);
  }
}

# remove a sitekey from the database, only requires the sitekey to do this.
sub removeSiteKey
{
  my $self = shift;
  my $siteKey = shift;
  
  $siteKey = $self->scrubSiteKey($siteKey);

  my $sth = $self->getDBH()->prepare('delete from merchant_sitekeys where sitekey = ?');
  $sth->execute($siteKey);
  $sth->finish;
}
  

sub scrubSiteKey
{
  my $self = shift;
  my $siteKey = shift;
  $siteKey =~ s/[^A-z0-9]//g;
  return $siteKey;
}

# removes non allowed characters from domains
sub scrubDomain
{
  my $self = shift;
  my ($domain) = @_;
  $domain = lc($domain);
  $domain =~ s/[^a-z0-9:\/\.\-\*]//g;
  $domain =~ s/(https?:\/\/\*?.*?)\/.*/$1/;
  return $domain;
}

# removes non allowed characters from merchants
sub scrubMerchant
{
  my $self = shift;
  my ($merchant) = @_;
  $merchant = lc($merchant);
  $merchant =~ s/[^a-z0-9]//g;
  return $merchant;
}
  

# checks to see if a domain already exists for a merchant.  not really useful outside the object though, but used internally.
sub domainExistsForMerchant
{
  my $self = shift;
  my ($domain,$merchant) = @_;

  $domain = $self->scrubDomain($domain);
  $merchant = $self->scrubMerchant($merchant);

  my $found = 0;

  my $sth = $self->getDBH()->prepare('select count(sitekey) as found from merchant_sitekeys where merchant = ? and domain = ?');
  $sth->execute($merchant,$domain);

  if (my $row = $sth->fetchrow_hashref())
  {
    $found = $row->{'found'};
  }
  
  return $found;
}


# checks to see if a key exists, returns 0 if it does not, 1 if it does
sub siteKeyExists
{
  my $self = shift;
  my $siteKey = shift;

  $siteKey = $self->scrubSiteKey($siteKey);

  my $found = 0;

  my $sth = $self->getDBH()->prepare('select count(sitekey) as found from merchant_sitekeys where sitekey = ?');
  $sth->execute($siteKey);

  if (my $row = $sth->fetchrow_hashref()) # && $row->{'sitekey'} eq $key)
  {
    $found = $row->{'found'};
  } 

  $sth->finish;

  return $found;
}


# connects to db, used internally
sub connectToDB
{
  my $self = shift;
  return miscutils::dbhconnect('pnpmisc');
}

# disconnects from db, used internally
sub disconnectFromDB
{
  my $self = shift;
  if ($self->{'dbh'})
  {
    $self->{'dbh'}->disconnect();
  }
}

# gets a dbh, used internally
sub getDBH
{
  my $self = shift;
  if (!$self->{'dbh'})
  {
    $self->{'dbh'} = $self->connectToDB();
  }

  return $self->{'dbh'}
}



1;
