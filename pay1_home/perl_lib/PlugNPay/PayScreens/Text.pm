package PlugNPay::PayScreens::Text;

###
# Module for editing labels in payscreens.  This is not meant to be used in scripts controlled
# by users.
#
# Methods: 
#  setMetaPhraseIdentifier({ selector => $selector, transactionType => $transactionType, identifier => $identifier, category => $category});
#  getMetaPhraseIdentifier({ selector => $selector, transactionType => $transactionType });
#  removeMetaPhraseIdentifier({ selector => $selector, transactionType => $transactionType });


sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  return $self;
}

sub setMetaPhraseIdentifier {
  my $self = shift;
  my $request = shift;

  if ($request->{'field'}) {
    $request->{'selector'} = '#' . $request->{'field'} . ' .label';
  }

  my $selector = $request->{'selector'};
  my $function = $request->{'function'};
  my $argument = $request->{'argument'};
  my $identifier = $request->{'metaIdentifier'};
  my $transactionType = $request->{'transactionType'} || 'all';
  my $category = $request->{'metaCategory'} || 'general';

  my $dbh = PlugNPay::DBConnection::database('pnpmisc');
    $sth = $dbh->prepare(q/
      INSERT INTO ui_payscreens_text
        (selector,mode,meta_identifier,meta_category,function,argument)
      VALUES
        (?,?,?,?,?,?)
      ON DUPLICATE KEY UPDATE meta_identifier=?, meta_category=?, function=?, argument=? 
    /);
    $sth->execute($selector,$transactionType,$identifier,$category,$function,$argument,$identifier,$category,$function,$argument) or print $DBI::errstr;
}

sub getMetaPhraseIdentifier{
  my $self = shift;
  my $request = shift;

  if ($request->{'field'}) {
    $request->{'selector'} = '#' . $request->{'field'} . ' .label';
  }

  if (!defined $request->{'transactionType'}) {
    $request->{'transactionType'} = 'all';
  }

  if ($request->{'selector'}) {
    my $dbh = PlugNPay::DBConnection::database('pnpmisc');

    my $sth = $dbh->prepare(q/
      SELECT meta_identifier
        FROM ui_payscreens_text
       WHERE selector = ?
         AND mode = ?
    /);

    $sth->execute($request->{'selector'},$request->{'transactionType'});

    my $identifier;

    my $results = $sth->fetchall_arrayref({});
    if ($results && @{$results} > 0) {
      $identifier = $results->[0]{'meta_identifier'};
    }

    return ($identifier,$category);
  }
}

sub removeMetaPhraseIdentifier {
  my $self = shift;
  my $request = shift;

  my $selector = $request->{'selector'};
  my $transactionType = $request->{'transactionType'} || 'all';

  my $dbh = PlugNPay::DBConnection::database('pnpmisc');

  my $sth = $dbh->prepare(q/
    DELETE FROM ui_payscreens_text
    WHERE selector = ?
      AND mode = ?
  /);

  $sth->execute($selector,$transactionType);
}

1;
