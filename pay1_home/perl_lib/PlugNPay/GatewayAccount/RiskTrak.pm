package PlugNPay::GatewayAccount::RiskTrak;

use strict;
use PlugNPay::DBConnection;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  return $self;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'username'};
}

sub setGatewayAccount {
  my $self = shift;
  my $username = shift;
  $self->{'username'} = $username;
}

sub getUsernameList {
  my $self = shift;
  return $self->{'usernameList'};
}

sub setUsernameList {
  my $self = shift;
  my $usernames = shift;
  $self->{'usernameList'} = $usernames;
}

sub getUsernameData {
  my $self = shift;
  return $self->{'usernameData'};
}

sub setUsernameData {
  my $self = shift;
  my $usernames = shift;
  $self->{'usernameData'} = $usernames;
}

sub getPageNumber {
  my $self = shift;
  return $self->{'pageNumber'};
}

#  
#  get/set wrapper for the 'limits' returned by getLimits
#   

sub getSettings {
  my $self = shift;
  my $username = $self->getGatewayAccount();
  
  my $settings = $self->{'settings'};
  if (!$settings) {
    $settings = $self->getLimits($username);
    $self->setSettings($settings);
  }
  
  return $settings;
}

sub setSettings {
  my $self = shift;
  my $settings = shift;
  $self->{'settings'} = $settings;
}

#  Original: details
#
#  The 'limits' column in the customer database is a list of settings that either 
#   suspends or freezes a transaction based on the number of sales or returns.

sub getLimits {
  my $self = shift;
  my $username = $self->getGatewayAccount();
  my $result = {};

  my $dbh = PlugNPay::DBConnection::connections->getHandleFor('pnpmisc');
  my $sth = $dbh->prepare(q/
	SELECT limits
	FROM customers
	WHERE username=?
  /);
  $sth->execute($username);
  my $ref = $sth->fetchall_arrayref({});
  my $strLimit = $ref->[0]{'limits'};	# username is a unique key in table pnpmisc.customers, so we only expect one row.

  my @array = split(/\,/, $strLimit);	# the limits exist in single column as a comma delimited string. Why this design was chosen I do not know.
  foreach my $entry (@array) {
    my($name, $value) = split(/\=/,$entry);
    $result->{$name} = $value;
  }

  return $result;
}

#
#  This function returns a hash of transactions for a given merchant.
#

sub getStats {
  my $self = shift;
  my $options = shift || {};

  my $size = $options->{'size'} || 500;
  my $offset = $options->{'offset'} || 0;

  my $username = $self->getGatewayAccount();

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
  my $sth = $dbh->prepare(q/
	SELECT  volume AS Volume, 
		type AS Type, 
		count AS Count, 
		trans_date AS TransDate
	FROM merch_stats
	WHERE username = ?
	LIMIT ?, ?
  /);
  $sth->execute($username, $offset, $size);
  my $ref = $sth->fetchall_arrayref({});

  return $ref;
}

#
# This function is a test, to try and return an ordersummary per a given orderid
#

sub getSummary {
  my $self = shift;
  my $orderid = shift || '';
  my $username = $self->getGatewayAccount();
 
  return if ($orderid eq '');

  my $results = {};
  my $dbh_pnpdata = PlugNPay::DBConnection::connections()->getHandleFor('pnpdata');

  my $sth_oplog = $dbh_pnpdata->prepare(q/
	SELECT  orderid AS OID,
                username AS GatewayAccount,
                card_name AS CardName,
                lastop AS Op,
                currency AS Cur,
                amount AS Amount,
                avs AS AVS,
                cvvresp AS CVV,
                card_addr AS CardAddr,
                card_city AS CardCity,
                card_state AS CardState,
                card_zip AS CardZip,
                card_country AS CardCountry,
                cardtype AS CardType,
                card_number AS CardNumber,
                card_exp AS CardDate,
                ipaddress AS IPAddress,
                lastoptime AS OpTime,
                lastopstatus AS OpStatus
	FROM operation_log
	WHERE username = ?
	AND orderid = ?
  /);

  my $dbh_fraud = PlugNPay::DBConnection::connections()->getHandleFor('fraudtrack');
  my $sth_geo = $dbh_fraud->prepare(q/
	SELECT country_code AS CountryCode
	FROM ip_country
	WHERE ipnum_to >= ?
	LIMIT 1
  /);
  
  $sth_oplog->execute($username, $orderid);
  my $ref_oplog = $sth_oplog->fetchall_arrayref({});

  my $ip = $ref_oplog->[0]{'IPAddress'};

  if ($ip !~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/) {
    return;
  }

  my $w = $1;
  my $x = $2;
  my $y = $3;
  my $z = $4;

  my $ipnum = int(16777216*$w + 65536*$x + 256*$y + $z);

  if (length($ipnum) > 11) {
    return;
  }

  $sth_geo->execute($ipnum);
  my $ref_geo = $sth_geo->fetchall_arrayref({});

  $results->{'oplog'} = $ref_oplog->[0];
  $results->{'geo'} = $ref_geo->[0];

  return $results;
}

#
# This function returns some data from pnpmisc.risk_log for a given user and search query
#

sub getHistory {
  my $self = shift;
  my $options = shift || {};
  my $username = $self->getGatewayAccount();

  my $modifier = $options->{'modifier'};
  my $columnID = $options->{'columnID'};
  my $filter = $options->{'filter'};
  my $pageLength = $options->{'pageLength'} || 500;
  my $pageNumber = $options->{'pageNumber'} || 0;
  my $offset = $pageNumber * $pageLength;

  # search handling
  my $vars = [];
  my $where = '';

  my $sql = {
    TransTime => 'trans_time',
    OID => 'orderid',
    IPAddress => 'ipaddress',
    Action => 'action',
    Desription => 'description'
  };

    if ( grep { /^$columnID$/ } (keys %{$sql}) && $filter ne '') {
      if ($modifier eq /starts/) {
        $filter = $filter . '%';
      } elsif ($modifier eq /ends/) {
        $filter = '%' . $filter;
      } elsif ($modifier eq /contains/) {
        $filter = '%' . $filter . '%';
      }
      push @$vars, $filter;
      $where .= 'AND ' . $sql->{$columnID} . ' LIKE ? ';
    }

  my $dbh_pnpmisc = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
  my $query = q/
        SELECT  trans_time AS TransTime,
		orderid AS OID,
		ipaddress AS IPAddress,
		action AS Action,
		description AS Description
	FROM risk_log
	WHERE username = ?
	/ . $where . q/
	ORDER BY trans_time DESC
	LIMIT ?, ?
  /;
  my $sth = $dbh_pnpmisc->prepare($query);
  $sth->execute($username, @$vars, $offset, $pageLength);
  my $ref = {};

  my $result = $sth->fetchall_arrayref({});
  my $history = $result;

  my $returnData = {list => $history, count => $self->getHistoryCount($options)};
  return $returnData;
}

#
# A helper method for client side table pagination.   
# The total number of entries is needed to know how many page buttons to make.
#

sub getHistoryCount {
  my $self = shift;
  my $options = shift || {};
  my $username = $self->getGatewayAccount();
  my $modifier = $options->{'modifier'};
 
  # search handling
  my $vars = [];
  my $where = '';

  my $sql = {
    TransTime => 'trans_time',
    OID => 'orderid',
    IPAddress => 'ipaddress',
    Action => 'action',
    Desription => 'description'
  };

  foreach my $row (keys %{$options}) {
    if ( grep { /^$row$/ } (keys %{$sql})) {
      my $var = $options->{$row};
      if ($modifier =~ /starts/) {
        $var = $var . '%';
      } elsif ($modifier =~ /ends/) {
        $var = '%' . $var;
      } elsif ($modifier =~ /contains/) {
        $var = '%' . $var . '%';
      }
      push @$vars , $var;
      $where .= 'AND ' . $sql->{$row} . ' LIKE ? ';
    }
  }

  my $dbh_pnpmisc = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
  my $sth = $dbh_pnpmisc->prepare(q/
        SELECT  COUNT(trans_time) AS count
        FROM risk_log
        WHERE username = ?
        / . $where . q/
  /);
  $sth->execute($username, @$vars);
  my $result = $sth->fetchall_arrayref({});

  if ($result && $result->[0]) {
    return $result->[0]{'count'};
  }

  return 0;
}

1;
