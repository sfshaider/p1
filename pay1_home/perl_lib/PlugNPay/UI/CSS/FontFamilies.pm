package PlugNPay::UI::CSS::FontFamilies;

use strict;

use PlugNPay::DBConnection;

sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  return $self;
}

sub loadFontFamilies {
  my $self = shift;

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q{
    SELECT id,font_family
      FROM ui_font_families 
  });
  $sth->execute();

  my $results = $sth->fetchall_arrayref({}); 

  my %fonts;

  if ($results) {
    my $rows = $results;
    foreach my $row (@{$rows}) {
      $fonts{$row->{'id'}} = $row->{'font_family'};
    }

    my $fonts = \%fonts;
  }
}

1;
