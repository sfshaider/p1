package PlugNPay::Util::Array;


BEGIN {
  require Exporter;

  our @ISA = qw(Exporter);
  our @EXPORT = qw(inArray unique);
}

sub inArray {
  my $value = shift;
  my $arrayRef = shift;

  my @match = grep { $value eq $_ } @{$arrayRef};
  return (@match > 0);
}

sub unique {
  my $array = shift;
  my $options = shift;

  my %values;
  my @result;

  if ($options->{'quote'}) {
    @result = grep { !$values{"$_"}++ } @{$array};
  } else {
    @result = grep { !$values{$_}++ } @{$array};
  }

  return \@result;
}

1;
