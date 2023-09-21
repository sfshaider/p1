package PlugNPay::UI::MetaPhrase;

use PlugNPay::DBConnection;
use PlugNPay::UI::Languages;
use PlugNPay::Username;
use PlugNPay::GatewayAccount;
use strict;



sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $login = shift;
  if (defined $login) {
    $self->setLogin($login);
  }

  $self->{'languages'} = new PlugNPay::UI::Languages();

  $self->setDefaultLanguage('EN-US');
  $self->setLanguage('EN-US');

  return $self;
}

sub setType {
  my $self = shift;
  my $type = shift;
  $type =~ s/[^a-z]//g;
  $self->{'type'} = $type;
}

sub getType {
  my $self = shift;
  return $self->{'type'};
}

sub setIdentifier {
  my $self = shift;
  my $identifier = shift;
  $self->{'identifier'} = $identifier;
}

sub getIdentifier {
  my $self = shift;
  return $self->{'identifier'};
}

sub setTemplate {
  my $self = shift;
  my $template = shift;
  $self->{'template'} = $template;
}

sub getTemplate {
  my $self = shift;
  return $self->{'template'};
}

sub setSubmittedTemplate {
  my $self = shift;
  my $template = shift;
  $self->{'submitted_template'} = $template;
}

sub getSubmittedTemplate {
  my $self = shift;
  return $self->{'submitted_template'};
}


sub setAccount {
  my $self = shift;
  my $account = shift;
  $self->{'account'} = $account;
  $self->setIdentifier($account);
}

sub getAccount {
  my $self = shift;
  return $self->{'account'};
}

sub setLogin {
  my $self = shift;
  my $login = shift;
  $login =~ s/[^a-z0-9_]//g;
  $self->{'login'} = $login;

  my $un = new PlugNPay::Username($login);
  $self->setAccount($un->getGatewayAccount());
}

sub getLogin {
  my $self = shift;
  return $self->{'login'};
}

sub setLanguage {
  my $self = shift;
  my $language = shift;
  $language = uc $language;
  $language =~ s/[^A-Z\-]//g;
  $self->{'language'} = $language;
}

sub getLanguage {
  my $self = shift;
  return $self->{'language'};
}

sub loadLanguage {
  my $self = shift;
  my $language = shift;
  $language = uc $language;


  if (!exists $self->{'customTextCache'}{$language}) {
    my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
    my $sth = $dbh->prepare(q/
      SELECT text_key,category,content,type
      FROM ui_metaphrase
      WHERE language = ? AND
        ((   type = 'default'  AND identifier = ?)
         OR (type = 'template' AND identifier = ?)
         OR (type = 'reseller_template' AND identifier = ?)
         OR (type = 'reseller' AND identifier = ?)
         OR (type = 'cobrand_template' AND identifier = ?)
         OR (type = 'cobrand'  AND identifier = ?)
         OR (type = 'account_template' AND identifier = ?)
         OR (type = 'account'  AND identifier = ?)
         OR (type = 'login'    AND identifier = ?))
    /);

    my $ga = new PlugNPay::GatewayAccount($self->getAccount());
  
    $sth->execute($language,
                  'default',
                  $ga->getReseller() . '-' . $self->getTemplate(),
                  $ga->getReseller() . '-' . $self->getSubmittedTemplate(),
                  $ga->getReseller(),
                  $ga->getCobrand() . '-' . $self->getSubmittedTemplate(),
                  $ga->getCobrand(),
                  $self->getAccount() . '-' . $self->getSubmittedTemplate(),
                  $self->getAccount(),
                  $self->getLogin());
  
    if (my $data = $sth->fetchall_arrayref({})) {
      $self->{'customTextData'} = {};
      foreach my $type ('security_level','account_template','login','account','cobrand_template','cobrand','reseller_template','template','reseller','default') {
        foreach my $row (@{$data}) {
          if ($row->{'type'} eq $type) {
            $self->{'currentLanguage'} = $language;
            if (!defined $self->{'customTextData'}->{$row->{'category'}}{$row->{'text_key'}} && defined $row->{'content'}) {
              $self->{'customTextData'}->{$row->{'category'}}{$row->{'text_key'}} = $row->{'content'};
            }
          }
        }
      }
      $self->{'customTextCache'}{$language} = $self->{'customTextData'};
    }

    $sth->finish;
  } else {
    $self->{'customTextData'} = $self->{'customTextCache'}{$language};
  }
}

sub getAll {
  my $self = shift;
  my $query = shift;

  my $type = $query->{'type'} || $self->getType();
  my $identifier = $query->{'identifier'} || $self->getIdentifier();
  
  my $dbh = PlugNPay::DBConnection::database('pnpmisc');

  my $sth = $dbh->prepare(q/
    SELECT text_key as meta_id,
	   category as meta_category,
           language,
           content as text
      FROM ui_metaphrase
     WHERE type = ?
       AND identifier = ?
  /) or die($DBI::errstr);

  $sth->execute($type,$identifier) or die($DBI::errstr);

  my $results = $sth->fetchall_arrayref({}) or die($DBI::errstr);

  return $results;
}

sub getOptions {
  my $self = shift;

  my $includePrivate = shift;

  $includePrivate = ($includePrivate ? 0 : 1);
  
  my $dbh = PlugNPay::DBConnection::database('pnpmisc');

  my $sth = $dbh->prepare(q/
    SELECT DISTINCT text_key as meta_id,
                    ui_metaphrase_category.name as categoryName,
                    ui_languages.category as meta_category
               FROM ui_languages,ui_metaphrase_category
              WHERE ui_languages.category = ui_metaphrase_category.category
                AND (ui_metaphrase_category.public = ? OR ui_metaphrase_category.public = ?)
  /);

  $sth->execute(1,$includePrivate);

  my $results = $sth->fetchall_arrayref({});

  my %categories = map { $_->{'meta_category'} => 1 } @{$results};

  foreach my $category (keys %categories) {
    $categories{$category} = {} if $categories{$category} == 1;
    $categories{$category}{'keys'} = () if !defined $categories{$category}{'keys'};
    foreach my $result (@{$results}) {
      $categories{$category}{'name'} = $result->{'categoryName'} if !defined $categories{$category}{'name'};
      if ($result->{'meta_category'} eq $category) {
        push @{$categories{$category}{'keys'}},$result->{'meta_id'};
      }
    }
    # convert keys array to a hash
    $categories{$category}{'keys'} = {map { $_ => $_ } sort @{$categories{$category}{'keys'}}};
  }

  return \%categories;
}


sub get {
  my $self = shift;
  my ($category,$text_key,$language) = @_;
  if (defined $language && $language ne '') {
    $self->setLanguage($language);
  }
  return $self->_get($category,$text_key,$language);
}

sub _get {
  my $self = shift;
  my ($category,$text_key,$language) = @_;
  if (defined $language && $language ne '') {
    $language = uc $language;
  } else {
    $language = $self->{'language'};
  }
  $self->loadLanguage($language);

  my $content = $self->{'customTextData'}->{$category}{$text_key};

  # if the content is blank, return the default version
  # checking the language here prevents infinite loops
  if (!defined $content) {
    if ($language ne $self->{'defaultLanguage'}) {
      $content = $self->getDefault($category,$text_key);
    } else {
      $content = $self->{'languages'}->get($category,$text_key,$self->{'language'});
    }
  }

  return $content;
}

sub set {
  my $self = shift;
  $self->_set(@_);
}

sub _set {
  my $self = shift;
  my $category = shift;
  my $text_key = shift;
  my $content = shift;

  $category =~ s/[^a-zA-Z0-9\-_]//g;
  $text_key =~ s/[^a-zA-Z0-9\-_]//g;

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth;

  $sth = $dbh->prepare(q/
    SELECT count(*) as `exists`
      FROM ui_metaphrase
     WHERE type = ? 
       AND identifier = ?
       AND text_key = ?
       AND category = ?
       AND language = ?
   /);

  $sth->execute( $self->getType(), $self->getIdentifier(), $text_key, $category, $self->getLanguage );

  my $result = $sth->fetchrow_hashref;
        
  if (!$result->{'exists'}) {
    ## INSERT ##
    $sth = $dbh->prepare(q/
      INSERT INTO ui_metaphrase
        (type,identifier,text_key,category,language,content)
       VALUES
        (?,?,?,?,?,?)
    /);
  
    eval {
      $sth->execute( $self->getType(), $self->getIdentifier(), $text_key, $category, $self->getLanguage(), $content);
    };
  } else {
    ## UPDATE ##
    $sth = $dbh->prepare(q/
      UPDATE ui_metaphrase
         SET content = ?
       WHERE type = ?
         AND identifier = ?
         AND text_key = ?
         AND category = ?
         AND language = ?
    /);

    $sth->execute( $content, $self->getType(), $self->getIdentifier(), $text_key, $category, $self->getLanguage() );
  }

  $self->flushCache();
}

sub delete {
  my $self = shift;
  $self->_delete(@_);
}

sub _delete {
  my $self = shift;
  my $category = shift;
  my $text_key = shift;

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
 
  my $sth = $dbh->prepare(q/
    DELETE FROM ui_metaphrase
     WHERE type = ?
       AND identifier = ?
       AND text_key = ?
       AND category = ?
       AND language = ?
  /);

  $sth->execute( $self->getType(), $self->getIdentifier(), $text_key, $category, $self->getLanguage() );

  $self->flushCache();
}

sub flushCache {
  my $self = shift;
  delete $self->{'customTextCache'};
}

sub getDefault {
  my $self = shift;
  my ($category,$text_key) = @_;

  # save the current language so we can restore it
  my $currentLanguage = $self->{'currentLanguage'};

  # load the value for the default languaage
  my $defaultContent = $self->_get($category,$text_key,$self->{'defaultLanguage'});

  # reload the previous language 
  $self->loadLanguage($currentLanguage);

  # return the default content
  return $defaultContent;
}
  
sub setDefaultLanguage {
  my $self = shift;
  my $language = shift;
  $self->{'defaultLanguage'} = $language;
  $self->{'languages'}->setDefaultLanguage($language);
}

1;
