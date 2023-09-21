package PlugNPay::Transaction::MobileSignature;

use strict;
use PlugNPay::DBConnection;
use MIME::Base64;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  $self->{'dbh'} = PlugNPay::DBConnection::database('transaction_data');

  return $self;
}

# does order id exist
# return 1 if it does and 0 if it does not
sub getEntryExists {
  my $self = shift;
  my $orderID = shift;
  my $username = shift;

  my $qry = q/select exists
	     (select 1 
	      from signature_data 
	      where orderid=? and username=?)/;
  my $dbh = $self->{'dbh'};
  my $sth = $dbh->prepare($qry);
  my $result = $sth->execute($orderID, $username);

  if ($result) {
    return $sth->fetchrow_array;
  } else {
    return 2;
  }
}

# overwrite existing signature (as binary) for an OrderID 
sub setNewSignature {
  my $self = shift;
  my $orderID = shift;
  my $username = shift;
  my $signature = shift;
  my $type = lc shift;

  my $qry = q/update signature_data 
	      set image=?, type=?
	      where orderid=? and username=?/;
  my $dbh = $self->{'dbh'};
  my $sth = $dbh->prepare($qry);

  #decode - turns Base64 back into a byte array
  $signature =~ s/\%(..)/pack("H2",$1)/ge;
  $signature = decode_base64($signature);
  my $result = $sth->execute($signature, $type, $orderID, $username);

  return $result;
}

# insert signature (as binary)
sub setSignature {
  my $self = shift;
  my $orderID = shift;
  my $username = shift;
  my $signature = shift;
  my $type = lc shift;

  my $qry = q/insert 
	      into signature_data (orderid, username, image, type) 
	      values (?, ?, ?, ?)/;
  my $dbh = $self->{'dbh'};
  my $sth = $dbh->prepare($qry);
 
  #decode - turns Base64 signature back into a byte array 
  $signature =~ s/\%(..)/pack("H2",$1)/ge;
  $signature = decode_base64($signature);
  my $result = $sth->execute($orderID, $username,  $signature, $type);

  return $result;  
}

# retrieve signature (as Base64)
sub getSignature {
  my $self = shift;
  my $orderID = shift;
  my $username = shift;

  my $qry = q/select image 
	      from signature_data 
	      where orderid=? and username=?/;
  my $dbh = $self->{'dbh'};
  my $sth = $dbh->prepare($qry);
  my $result = $sth->execute($orderID, $username);
 
  if ($result) {
    # encode - turns byte array back into Base64
    return encode_base64($sth->fetchrow_array);
  } else {
    return "err";
  }
}

1;
