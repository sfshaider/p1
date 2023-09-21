package PlugNPay::UI::HTML::Date;

use strict;
use PlugNPay::UI::HTML;
use PlugNPay::Sys::Time;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;


  return $self;
}

sub createHourSelect {
  my $self = shift;
  my $selected = shift;

  my $hours = {};
  for( my $i = 0; $i <= 23; $i++) {
    my $amPm = $i >= 12 ? 'PM' : 'AM';
    my $hour = $i > 12 ? $i - 12 : $i;
    if ($i eq 0) {
      $hour = 12
    }
    my $amPmHour = "$hour:00 $amPm";

    $hours->{sprintf("%02i",$i)} = $amPmHour;
  }

  my $hourOptions = {'selected' => $selected,
                     'selectOptions' => {'Select Hour' => $hours}
                     };

  my $htmlBuilder = new PlugNPay::UI::HTML();
  return $htmlBuilder->selectOptions($hourOptions);
}

sub createDaySelect {
  my $self = shift;
  my $selected = shift;
  my $first = shift;
  
  if (!$first) {
    $first = '0';
  }
  
  my $sysTime = new PlugNPay::Sys::Time();
  my $htmlBuilder = new PlugNPay::UI::HTML();
  my $datetime = $sysTime->inFormat('db');
  my $maxDay = $sysTime->getLastOfMonth(substr($datetime,5,2));
  
  if ($selected eq 'first') {
    $selected = '01';
  } elsif ($selected eq 'last' || $selected > $maxDay) {
    $selected = $maxDay;
  }
  
  my $days = {};
  for (my $i = 1; $i <= $maxDay; $i++) {
    $days->{sprintf("%02i",$i)} = sprintf("%02i",$i);
  }
  
  my $date = $htmlBuilder->selectOptions({ 'selected' => $selected,
                    'selectOptions' => {'Select Day' => $days}
                  });
  
  return $date;
}

sub createMonthSelect {
  my $self = shift;
  my $selected = shift;
  my $first = shift || '0';

  if (!$selected || $selected > 12 || $selected < 1) {
    my $time = new PlugNPay::Sys::Time();
    my $datetime = $time->inFormat('db_gm');
    $selected = substr($datetime,5,2)
  }

  my $months = {};
  for( my $i = 1; $i <= 12; $i++) {
    my $month = $i;
    $months->{sprintf("%02i",$i)} = sprintf('%02i',$month);
  }

  my $monthOptions = {'selected' => $selected,
                      'selectOptions' => {'Select Month' => $months}
                     };

  my $htmlBuilder = new PlugNPay::UI::HTML();
  return $htmlBuilder->selectOptions($monthOptions);
}

sub createYearSelect {
  my $self = shift;
  my $startingYear = shift;
  my $first = shift || '0';

  my $time = new PlugNPay::Sys::Time();
  my $datetime = $time->inFormat('db_gm');
  my $year = substr($datetime,0,4);
  if (!defined $startingYear || $startingYear !~ /^\d{4}$/ || ($year - $startingYear) > 3 || ($year - $startingYear) < 1) {
    $startingYear = $year - 1;
  }
  
  my $yearDifferential = $year - $startingYear;
  my $years = {};
  for(my $i = 0; $i <= $yearDifferential; $i++) {
    $years->{$startingYear + $i} = $startingYear + $i;
  }
  
  my $yearOptions = {'selected' => $year,
                     'selectOptions' => {'Select Year' => $years}
                    };
  my $htmlBuilder = new PlugNPay::UI::HTML(); 
  my $yearSelectOptions = $htmlBuilder->selectOptions($yearOptions);
}

1;
