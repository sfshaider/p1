package PlugNPay::PayScreens::Elements;

###
# Module for setting element settings on payscreens pages.
#
# Methods:
#  setElementSettings({ type => $type, identifier => $identifier, element => $element, transactionType => $transactionType, enabled => $enabled, visible => $visible });
#  getElementSettings({ type => $type, identifier => $identifier, element => $element, transactionType => $transactionType });
#  getAllElementSettings({ type => $type, identifier => $identifier });
#  removeElementSettings({ type => $type, identifier => $identifier, element => $element, transactionType => $transactionType });
#  generateSubstitutionJSArray();
#


sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  return $self;
}

sub setElementSettings {
  my $self = shift;
  my $request = shift;

  my $type            = $request->{'type'};
  my $identifier      = $request->{'identifier'};
  my $element         = $request->{'element'};
  my $transactionType = $request->{'transactionType'} || 'all';
  my $enabled         = ($request->{'enabled'} ? 1 : 0);
  my $visible         = ($request->{'visible'} ? 1 : 0);
  my $required        = ($request->{'required'} ? 1 : 0);

  my $dbh = PlugNPay::DBConnection::database('pnpmisc');

  my $sth = $dbh->prepare(q/
    SELECT count(*) as `exists`
      FROM ui_payscreens_elements
     WHERE element = ?
       AND type = ?
       AND identifier = ?
       AND transaction_type = ?
  /);

  $sth->execute($element,$type,$identifier,$transactionType) or die($DBI::errstr);

  my $result = $sth->fetchrow_hashref;

  $sth = undef;

  if ($result && $result->{'exists'}) {
    # UPDATE
    $sth = $dbh->prepare(q/
      UPDATE ui_payscreens_elements
         SET enabled = ?,
             visible = ?,
             required = ?
       WHERE element = ?
         AND type = ?
         AND identifier = ?
         AND transaction_type = ?
    /) or die($DBI::errstr);

  } elsif ($result) {
    # INSERT
    $sth = $dbh->prepare(q/
      INSERT INTO ui_payscreens_elements
        (enabled,visible,required,element,type,identifier,transaction_type)
      VALUES
        (?,?,?,?,?,?,?)
    /) or die($DBI::errstr);
  }

  if ($sth) {
    $sth->execute($enabled,$visible,$required,$element,$type,$identifier,$transactionType) or die($DBI::errstr);
  }
}

sub getElementSettings {
  my $self = shift;
  my $request = shift;

  my $type            = $request->{'type'};
  my $identifier      = $request->{'identifier'};
  my $element         = $request->{'element'};
  my $transactionType = $request->{'transactionType'} || 'all';

  my $dbh = PlugNPay::DBConnection::database('pnpmisc');

  my $sth = $dbh->prepare(q/
    SELECT enabled as enabled, visible as visible, required as required
      FROM ui_payscreens_elements
     WHERE type = ?
       AND identifier = ?
       AND element = ?
       AND transaction_type = ?
  /) or die($DBI::errstr);

  $sth->execute($type,$identifier,$element,$transactionType) or die($DBI::errstr);

  my $result = $sth->fetchrow_hashref;

  if ($result) {
    return $result;
  } else {
    return {};
  }
}

sub getAllElementSettings {
  my $self = shift;
  my $request = shift;

  my $type       = $request->{'type'};
  my $identifier = $request->{'identifier'};

  my $dbh = PlugNPay::DBConnection::database('pnpmisc');

  my $sth = $dbh->prepare(q/
    SELECT element,
           enabled,
           visible,
           required,
           transaction_type as transactionType
      FROM ui_payscreens_elements
     WHERE type = ?
       AND identifier = ?
     ORDER BY element
  /) or die($DBI::errstr);

  $sth->execute($type,$identifier) or die($DBI::errstr);

  my $results = $sth->fetchall_arrayref({});

  return $results;
}

sub removeElementSettings {
  my $self = shift;
  my $request = shift;

  my $type            = $request->{'type'};
  my $identifier      = $request->{'identifier'};
  my $element         = $request->{'element'};
  my $transactionType = $request->{'transactionType'} || 'all';

  my $dbs = PlugNPay::DBConnection::database('pnpmisc');

  my $sth = $dbs->prepare(q/
    DELETE FROM ui_payscreens_elements
     WHERE type = ?
       AND identifier = ?
       AND element = ?
       AND transaction_type = ?
  /) or die($DBI::errstr);

  $sth->execute($type,$identifier,$element,$transactionType) or die($DBI::errstr);
}


1;
