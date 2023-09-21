package PlugNPay::Elements;

###
# Module for setting element settings on payscreens and VT pages.
#
# Methods:
#  setElementSettings({ context=>$context, type => $type, identifier => $identifier, element => $element, transactionType => $transactionType, enabled => $enabled, visible => $visible });
#  getElementSettings({ context=>$context, type => $type, identifier => $identifier, element => $element, transactionType => $transactionType });
#  getAllElementSettings({ context=>$context, type => $type, identifier => $identifier });
#  removeElementSettings({ context=>$context, type => $type, identifier => $identifier, element => $element, transactionType => $transactionType });
#  generateSubstitutionJSArray();
#


sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  return $self;
}

sub setTableName {
  my $self = shift;
  my $context = shift;

  my $table = "ui_payscreens_elements"; # default to payscreens table

  if ($context eq "virtualTerminal") {
    $table = "ui_admin_virtualterminal_elements";
  }

  $self->{'tableName'} = $table;
}

sub getTableName {
  my $self = shift;
  return $self->{'tableName'};
}

sub setElementSettings {
  my $self = shift;
  my $request = shift;

  $self->setTableName($request->{'context'});
  my $table = $self->getTableName();

  my $type            = $request->{'type'};
  my $identifier      = $request->{'identifier'};
  my $element         = $request->{'element'};
  my $transactionType = $request->{'transactionType'} || 'all';
  my $enabled         = ($request->{'enabled'} ? 1 : 0);
  my $visible         = ($request->{'visible'} ? 1 : 0);
  my $required        = ($request->{'required'} ? 1 : 0);

  my $dbh = PlugNPay::DBConnection::database('pnpmisc');

  my $sth = $dbh->prepare(q{
    SELECT count(*) as `exists`
      FROM } . $table . q{ 
     WHERE element = ?
       AND type = ?
       AND identifier = ?
       AND transaction_type = ?
  });

  $sth->execute($element,$type,$identifier,$transactionType) or die($DBI::errstr);

  my $result = $sth->fetchrow_hashref;

  $sth = undef;

  if ($result && $result->{'exists'}) {
    # UPDATE
    $sth = $dbh->prepare(q{
      UPDATE } . $table . q{ 
         SET enabled = ?,
             visible = ?,
             required = ?
       WHERE element = ?
         AND type = ?
         AND identifier = ?
         AND transaction_type = ?
    }) or die($DBI::errstr);

  } elsif ($result) {
    # INSERT
    $sth = $dbh->prepare(q{
      INSERT INTO } . $table . q{ 
        (enabled,visible,required,element,type,identifier,transaction_type)
      VALUES
        (?,?,?,?,?,?,?)
    }) or die($DBI::errstr);
  }

  if ($sth) {
    $sth->execute($enabled,$visible,$required,$element,$type,$identifier,$transactionType) or die($DBI::errstr);
  }
}

sub getElementSettings {
  my $self = shift;
  my $request = shift;

  $self->setTableName($request->{'context'});
  my $table = $self->getTableName();

  my $type            = $request->{'type'};
  my $identifier      = $request->{'identifier'};
  my $element         = $request->{'element'};
  my $transactionType = $request->{'transactionType'} || 'all';

  my $dbh = PlugNPay::DBConnection::database('pnpmisc');

  my $sth = $dbh->prepare(q{
    SELECT enabled as enabled, visible as visible, required as required
      FROM } . $table . q{ 
     WHERE type = ?
       AND identifier = ?
       AND element = ?
       AND transaction_type = ?
  }) or die($DBI::errstr);

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

  $self->setTableName($request->{'context'});
  my $table = $self->getTableName();

  my $type       = $request->{'type'};
  my $identifier = $request->{'identifier'};

  my $dbh = PlugNPay::DBConnection::database('pnpmisc');

  my $sth = $dbh->prepare(q{
    SELECT element,
           enabled,
           visible,
           required,
           transaction_type as transactionType
      FROM } . $table . q{
     WHERE type = ?
       AND identifier = ?
     ORDER BY element
  }) or die($DBI::errstr);

  $sth->execute($type,$identifier) or die($DBI::errstr);

  my $results = $sth->fetchall_arrayref({});

  return $results;
}

sub removeElementSettings {
  my $self = shift;
  my $request = shift;

  $self->setTableName($request->{'context'});
  my $table = $self->getTableName();

  my $type            = $request->{'type'};
  my $identifier      = $request->{'identifier'};
  my $element         = $request->{'element'};
  my $transactionType = $request->{'transactionType'} || 'all';

  my $dbs = PlugNPay::DBConnection::database('pnpmisc');

  my $sth = $dbs->prepare(q{
    DELETE FROM } . $table . q{ 
     WHERE type = ?
       AND identifier = ?
       AND element = ?
       AND transaction_type = ?
  }) or die($DBI::errstr);

  $sth->execute($type,$identifier,$element,$transactionType) or die($DBI::errstr);
}


1;
