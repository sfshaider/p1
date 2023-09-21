package PlugNPay::PayScreens::Substitutions;

###
# Module for doing (html) substitutions on payscreens pages.
#
# Methods:
#  setSelectorContent({ type => $type, identifier => $identifier, selector => $selector, content => $content });
#  getSelectorContent({ type => $type, identifier => $identifier, selector => $selector });
#  getAllSelectorContent({ type => $type, identifier => $identifier });
#  removeSelectorContent({ type => $type, identifier => $identifier, selector => $selector });
#  generateSubstitutionJSArray();
#


sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  return $self;
}

sub setSelectorContent {
  my $self = shift;
  my $request = shift;

  my $type       = $request->{'type'};
  my $identifier = $request->{'identifier'};
  my $selector   = $request->{'selector'};
  my $content    = $request->{'content'};;

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
  my $sth = $dbh->prepare(q/
    SELECT count(selector) as `exists`
      FROM ui_payscreens_substitutions
     WHERE type = ?
       AND identifier = ?
       AND selector = ?
  /);

  $sth->execute($type,$identifier,$selector);

  my $result = $sth->fetchrow_hashref;

  if ($result && $result->{'exists'}) {
    # update
    $sth = $dbh->prepare(q/
      UPDATE ui_payscreens_substitutions
         SET content = ?
       WHERE type = ?
         AND identifier = ?
         AND selector = ?
    /);
  } else {
    # insert
    $sth = $dbh->prepare(q/
      INSERT INTO ui_payscreens_substitutions
        (content,type,identifier,selector)
      VALUES
        (?,?,?,?)
    /);
  }

  $sth->execute($content,$type,$identifier,$selector);
}

sub getSelectorContent {
  my $self = shift;
  my $request = shift;

  my $type       = $request->{'type'};
  my $identifier = $request->{'identifier'};
  my $selector   = $request->{'selector'};

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q/
    SELECT content
      FROM ui_payscreens_substitutions
     WHERE type = ?
       AND identifier = ?
       AND selector = ?
  /);

  $sth->execute($type,$identifier,$selector);

  my $result = $sth->fetchrow_hashref;

  if ($result) {
    return $result->{'content'};
  }
}

sub getAllSelectorContent {
  my $self = shift;
  my $request = shift;

  my $type       = $request->{'type'};
  my $identifier = $request->{'identifier'};

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q/
    SELECT selector,content
      FROM ui_payscreens_substitutions
     WHERE type = ?
       AND identifier = ?
  /);

  $sth->execute($type,$identifier);

  my $result = $sth->fetchall_arrayref({});

  return $result;
}

sub removeSelectorContent {
  my $self = shift;
  my $request = shift;

  my $type       = $request->{'type'};
  my $identifier = $request->{'identifier'};
  my $selector   = $request->{'selector'};

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q/
    DELETE FROM ui_payscreens_substitutions
     WHERE type = ?
       AND identifier = ?
       AND selector = ?
  /);

  $sth->execute($type,$identifier,$selector);
}


sub generateSubstitutionArrayString {
  my $self = shift;
  my $account = lc shift;

  $account =~ s/[^a-z0-9]//;

  my $ga = new PlugNPay::GatewayAccount($account);

  my $reseller = $ga->getReseller();
  my $cobrand =  $ga->getCobrand();
  
  my $javascriptAssociativeArray = '';

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q{
    SELECT identifier, type, selector, content
      FROM ui_payscreens_substitutions
     WHERE (   (type = 'default'  AND identifier = ?)
            OR (type = 'reseller' AND identifier = ?)
            OR (type = 'cobrand'  AND identifier = ?)
            OR (type = 'account'  AND identifier = ?))
       AND enabled = ?
       AND approved = ?
  });
  $sth->execute('default', $reseller, $cobrand, $account, 1, 1);

  my $results = $sth->fetchall_arrayref({});
  $sth->finish;

  my %substitutions;
  foreach my $type ('default','reseller','cobrand','account') {
    foreach my $substitution (@{$results}) {
      if ($substitution->{'type'} eq $type) {
        my $selector = $substitution->{'selector'};
        my $contentEncoded = unpack('H*',$substitution->{'content'});
        $substitutions{$selector} = $contentEncoded;
      }
    }
  }

  return '{' . join(',',map { qq/'$_': '$substitutions{$_}'/ } keys %substitutions) . '}';
}

1;
