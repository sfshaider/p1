package CCLibMCK;

require Exporter;
@ISA = (Exporter);
@EXPORT = qw();
@EXPORT_OK = qw(GetQuery);

sub GetQuery {
  my $q = new CGI();
  my %params = $q->Vars();
  return %params;
}

1;
