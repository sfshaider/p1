package PlugNPay::Database::QueryBuilder;

use strict;
use PlugNPay::Sys::Time;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;


  return $self;
}

sub generateDateRange {
  my $self = shift;
  my $data = shift;
  my $time = new PlugNPay::Sys::Time();

  my $startDate = $time->inFormatDetectType('yyyymmdd',$data->{'start_date'});
  my $endDate = $time->inFormatDetectType('yyyymmdd',$data->{'end_date'});
  $startDate =~ s/[^\d]//g;
  $endDate =~ s/[^\d]//g;

  if (!$startDate && !$endDate) {
    $endDate = $time->nowInFormat('yyyymmdd');
    $time->subtractDays(90);

    $startDate = $time->inFormat('yyyymmdd');
  } elsif (!$startDate) {
    $time->fromFormat('yyyymmdd',$endDate);
    $time->subtractDays(90);

    $startDate = $time->inFormat('yyyymmdd');
  } elsif (!$endDate) {
    $time->fromFormat('yyyymmdd',$startDate);
    $time->addDays(90);

    $endDate = $time->inFormat('yyyymmdd');
  }

  my @params = ();
  my @values = ();
  $time->fromFormat('yyyymmdd',$startDate);
  do {
    my $tempDate = $time->inFormat('yyyymmdd');
    $tempDate =~ s/[^\d]//g;
    if ($tempDate) {
      push @values,$tempDate;
      push @params,'?'; 
    }
    $time->addDays(1);
  } while ($endDate >= $time->inFormat('yyyymmdd'));
  my $dateRange = {};
  $dateRange->{'values'} = \@values;
  $dateRange->{'params'} = join(',',@params);

  return $dateRange;
}

1;
