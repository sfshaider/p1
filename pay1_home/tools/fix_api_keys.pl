#!/bin/env perl

use lib '/home/pay1/perl_lib';

use strict;
use PlugNPay::DBConnection;
use Data::Dumper;

my $dbs = new PlugNPay::DBConnection();

my $sth = $dbs->prepare('pnpmisc',q/
  SELECT username,key_name FROM api_key WHERE key_name_id = 0
/) or die ('Failed to prep query for api keys');

$sth->execute() or die('Failed to query for api keys');

my $rows = $sth->fetchall_arrayref({});

foreach my $row (@{$rows}) {
  my $username = $row->{'username'};
  my $keyName = $row->{'key_name'};

  print "username: $username, keyName: $keyName\n";
  print "Migrate this key? (y/n): ";
  my $answer = <>;
  chomp $answer;

  if ($answer eq 'y') {
    # try and insert customer into customer_id table, ignoring duplicate failure
    $sth = $dbs->prepare('pnpmisc',q/
      INSERT IGNORE INTO customer_id (username) values(?)
    /);
    $sth->execute($username);

    # get customer_id
    my $customerID = 0; # initial value
    $sth = $dbs->prepare('pnpmisc',q/
      SELECT id FROM customer_id WHERE username = ?
    /);
    $sth->execute($username);

    my $customerIDRows = $sth->fetchall_arrayref({});
    if (@{$customerIDRows} > 1) {
      print "ERROR: more than one id for $username\n";
      next;
    } elsif (@{$customerIDRows} == 1) {
      $customerID = $customerIDRows->[0]{'id'};
    }

    if ($customerID <= 0) {
      print "ERROR: customer id is invalid.\n";
      next;
    }

    print "CustomerID is $customerID\n";

    # try and insert into api_key_name for customer_id and key_name, ignoring duplicate failure
    $sth = $dbs->prepare('pnpmisc',q/
      INSERT IGNORE INTO api_key_name (customer_id,name) values (?,?)
    /);
    $sth->execute($customerID,$keyName);

    # get key name id
    $sth = $dbs->prepare('pnpmisc',q/
      SELECT id FROM api_key_name WHERE customer_id = ? AND name = ?
    /);
    $sth->execute($customerID,$keyName);

    my $keyNameID = 0;
    my $keyNameRows = $sth->fetchall_arrayref({});
    if (@{$keyNameRows} > 1) {
      print "ERROR: more than one id for $customerID and $keyName\n";
      next;
    } elsif (@{$keyNameRows} == 1) {
      $keyNameID = $keyNameRows->[0]{'id'};
    }

    if ($keyNameID <= 0) {
      print "ERROR: key name id is invalid.\n";
      next;
    }

    print "KeyNameID is $keyNameID\n";

    # update api_key table
    $sth = $dbs->prepare('pnpmisc',q/
      UPDATE api_key SET key_name_id = ? WHERE username = ? AND key_name = ? AND key_name_id = 0
    /);
    $sth->execute($keyNameID,$username,$keyName);
  }
}
