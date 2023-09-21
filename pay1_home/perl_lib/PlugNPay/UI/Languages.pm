package PlugNPay::UI::Languages;

use PlugNPay::DBConnection;
use strict;


our %languageCache;

sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  $self->setDefaultLanguage('EN-US');

  return $self;
}

sub setTextKey {
  my $self = shift;
  my $textKey = shift;
  $self->{'text_key'} = $textKey;
}

sub getTextKey {
  my $self = shift;
  return $self->{'text_key'};
}

sub setCategory {
  my $self = shift;
  my $category = shift;
  $self->{'category'} = $category;
}

sub getCategory {
  my $self = shift;
  return $self->{'category'};
}

sub setContent {
  my $self = shift;
  my $content = shift;
  $self->{'content'} = $content;
}

sub getContent {
  my $self = shift;
  return $self->{'content'};
}

sub delete {
  my $self = shift;

  if (($self->{'text_key'} ne "") && ($self->{'category'} ne "") && ($self->{'defaultLanguage'} ne "")) {
    my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
    my $sth = $dbh->prepare(q{
      DELETE FROM ui_languages
      WHERE text_key=? AND category=? AND language=?
    });
    $sth->execute($self->{'text_key'},$self->{'category'},$self->{'defaultLanguage'});
    my $rows = $sth->rows();
    return !($rows == 0);
  }
  return 0;
}

sub save {
  my $self = shift;

  if (($self->{'text_key'} ne "") && ($self->{'category'} ne "") && ($self->{'defaultLanguage'} ne "") && ($self->{'content'} ne "")) {
    my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
    my $sth = $dbh->prepare(q{
      INSERT INTO ui_languages
      (text_key,category,language,content)
      VALUES (?,?,?,?)
    });
    $sth->execute($self->{'text_key'},$self->{'category'},$self->{'defaultLanguage'},$self->{'content'});
    my $rows = $sth->rows();
    return !($rows == 0);
  }
  return 0;
}

sub update {
  my $self = shift;

  if (($self->{'text_key'} ne "") && ($self->{'category'} ne "") && ($self->{'defaultLanguage'} ne "") && ($self->{'content'} ne "")) {
    my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
    my $sth = $dbh->prepare(q{
      UPDATE ui_languages
      SET content=?
      WHERE text_key=? AND category=? AND language=?
    });
    $sth->execute($self->{'content'},$self->{'text_key'},$self->{'category'},$self->{'defaultLanguage'});
    my $rows = $sth->rows();
    return !($rows == 0);
  }
  return 0;
}

sub readLanguage {
  my $self = shift;
  my $language = shift;
  $language = uc $language;
  $self->loadLanguage($language);

  return $languageCache{$language};
}

sub loadLanguage {
  my $self = shift;
  my $language = shift;
  $language = uc $language;

  if (!exists $languageCache{$language}) {
    my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
    my $sth = $dbh->prepare(q{
      SELECT text_key,category,content
      FROM ui_languages
      WHERE language = ?
    });
  
    $sth->execute($language);
  
    if (my $data = $sth->fetchall_arrayref({})) {
      $self->{'languageData'} = {};
      foreach my $row (@{$data}) {
        $self->{'currentLanguage'} = $language;
        $self->{'languageData'}->{$row->{'category'}}{$row->{'text_key'}} = $row->{'content'};
      }
      $languageCache{$language} = $self->{'languageData'};
    }

    $sth->finish;
  } else {
    $self->{'languageData'} = $languageCache{$language};
  }
}

sub get {
  my $self = shift;
  my ($category,$text_key,$language) = @_;
  if (defined $language && $language ne '') {
    $language = uc $language;
    $self->loadLanguage($language);
  }
  my $content = $self->{'languageData'}->{$category}{$text_key};

  # if the content is blank, return the default version
  # checking the language here prevents infinite loops
  if ($content eq '' && $language ne $self->{'defaultLanguage'}) {
    $content = $self->getDefault($category,$text_key);
  }
  return $content;
}

sub getDefault {
  my $self = shift;
  my ($category,$text_key) = @_;

  # save the current language so we can restore it
  my $currentLanguage = $self->{'currentLanguage'};

  # load the value for the default languaage
  my $defaultContent = $self->get($category,$text_key,$self->{'defaultLanguage'});

  # reload the previous language 
  $self->loadLanguage($currentLanguage);

  # return the default content
  return $defaultContent;
}
  
sub setDefaultLanguage {
  my $self = shift;
  $self->{'defaultLanguage'} = shift;
}

1;
