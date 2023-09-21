package PlugNPay::Sys::Time;

BEGIN {
  require Exporter;

  our @ISA = qw(Exporter);
  our @EXPORT = qw(yy yyyy mm);
}

use strict;
use Time::Local;
use Time::HiRes;
use PlugNPay::DBConnection;
use Env::C;
use POSIX qw(tzname tzset);

## Usage
##
## Use for time manipulation and comparison of time formats that Plug and Pay uses frequently.
## It's object oriented, so you compare time objects with each other using methods, set a time of an object with
## a method, etc.
##
## Assumes all times are GMT unless otherwise specified.

# Formats
# Higher confidence gives priority
my $formats = {
  log => {validation => '/^(\d{2})\/(\d{2})\/(\d{4}) (\d{2}):(\d{2}):(\d{2})$/'},
  db_gm => {validation => '/^(\d{4})\-(\d{2})\-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/'},
  iso => {validation => '/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(\-\d{3})?Z$/i'},
  year2 => {
    validation => '/^\d{2}$/',
    confidence => 5
  },
  yy => {
    validation => '/^\d{2}$/',
    confidence => 7
  },
  'mm/yy' => {validation => '/^\d{2}\/\d{2}$/'},
  mmyy => {
    validation => '/^\d{2}\d{2}$/',
    confidence => 10
  },
  yyyymmdd => {
    validation => '/^\d{4}\d{2}\d{2}$/',
    confidence => 10
  },
  gendatetime => {
    validation => '/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$/',
    confidence => 10
  },
  unix => {
    validation => '/^\d{10}$/',
    confidence => 10
  },
  hex => {
    validation => '/^[a-fA-F0-9]+$/',
    confidence => 1
  }
};

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $format = shift || undef;
  my $fromString = shift || undef;

  my @time = localtime(Time::HiRes::time());
  $self->{'offset'} = Time::Local::timegm(@time) - Time::Local::timelocal(@time);
  $self->{'time'} = Time::HiRes::time();
  if (defined $format) {
    if (defined $fromString) {
      $self->fromFormat($format,$fromString);
    } else {
      return $self->inFormat($format);
    }
  }
  return $self;
}

sub copyFrom {
  my $self = shift;
  my $another = shift;
  if (ref($another) ne 'PlugNPay::Sys::Time') {
    die('cannot copy from non-time object');
  }
  
  $self->{'offset'} = $another->{'offset'};
  $self->{'time'} = $another->{'time'};
}

## These eight functions are pretty self explanitory
sub addDays {
  my $self = shift;
  my $days = shift;
  $self->{'time'} += ($days * 3600 * 24);
}

sub subtractDays {
  my $self = shift;
  my $days = shift;
  $self->{'time'} -= ($days * 3600 * 24);
}

sub addHours {
  my $self = shift;
  my $hours = shift;
  $self->{'time'} += ($hours * 3600);
}

sub subtractHours {
  my $self = shift;
  my $hours = shift;
  $self->{'time'} -= ($hours * 3600);
}

sub addMinutes {
  my $self = shift;
  my $minutes = shift;
  $self->{'time'} += ($minutes * 60);
}

sub subtractMinutes {
  my $self = shift;
  my $minutes = shift;
  $self->{'time'} -= ($minutes * 60);
}

sub addSeconds {
  my $self = shift;
  my $seconds = shift;
  $self->{'time'} += $seconds;
}

sub subtractSeconds {
  my $self = shift;
  my $seconds = shift;
  $self->{'time'} -= $seconds;
}

sub setTimeZone {
  my $self = shift;
  my $timeZone = shift;

  $self->{'timezone'} = $timeZone;
}

sub getTimeZone {
  my $self = shift;
  return $self->{'timezone'} || 'GMT';
}

sub getTimeZoneCode {
  my $self = shift;

  my $originalTimeZone = $ENV{'TZ'};
  Env::C::setenv('TZ', $self->getTimeZone(), 1);
  my $code = POSIX::strftime('%Z',localtime());
  Env::C::setenv('TZ', $originalTimeZone, 1);

  return $code;
}


## Takes an input format name and an input string and sets the internal time of the object according to the format.
## Returns true if it worked, undef if it didn't work, but seriously, who is going to check that.
##
## Look through this function to find acceptable formats, most frequently used formats would probably be 'db_gm','mm/yy_(end|begin)' and 'unix'
sub fromFormat {
  my $self = shift;
  my ($format,$fromString) = @_;

  $self->{'time'} = undef;

  if (!defined $format) {
    $self->{'error'} = 'Format not specified';
  } elsif (!defined $fromString) {
    $self->{'error'} = 'Input string not specified';
  } elsif ($fromString eq '') {
    $self->{'error'} = 'Cannot generate a time from a null string';
  } elsif ($format eq 'unix' ) {
    # strip off decimal from Time::HiRes
    $fromString =~ s/\.\d+$//;
    if ($fromString =~ /^\d+$/) {
      $self->{'time'} = $fromString;
      return 1;
    } else {
      $self->{'error'} = 'Input string is not in unix format';
    }
  } elsif ($format =~ /^iso(_(gm|local))?$/) { # modified iso 8601: YYYYMMddTHHMMSSZ format, 'iso' defaults to gmtime
    $fromString =~ /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z|\-\d{3})?$/i;
    if ($fromString !~ /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z|\-\d{3})?$/i)  {
      $self->{'error'} = 'Input string is not in iso date format';
    } else {
      my ($year,$month,$day,$hour,$minute,$second) = ($1,$2,$3,$4,$5,$6);
      $year -= 1900;
      $month -= 1;
      if ($format eq 'iso' || $format eq 'iso_gm') {
        $self->{'time'} = timegm($second,$minute,$hour,$day,$month,$year);
      } elsif ($format eq 'iso_local') {
        $self->{'time'} = timelocal($second,$minute,$hour,$day,$month,$year);
      }
      return 1;
    }
  } elsif ($format =~ /^db(_(gm|local))?$/) { # YYYY-MM-dd HH:MM:SS format, db defaults to gmtime
    $fromString =~ /^(\d{4})\-(\d{2})\-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/;
    if ($fromString !~ /^(\d{4})\-(\d{2})\-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/) {
      $self->{'error'} = 'Input string is not in db date format';
    } else {
      my ($year,$month,$day,$hour,$minute,$second) = ($1,$2,$3,$4,$5,$6);
      $year -= 1900;
      $month -= 1;
      if ($format eq 'db' || $format eq 'db_gm') {
        $self->{'time'} = timegm($second,$minute,$hour,$day,$month,$year);
      } elsif ($format eq 'db_local') {
        $self->{'time'} = timelocal($second,$minute,$hour,$day,$month,$year);
      }
      return 1;
    }
  } elsif ($format =~ /^gendatetime/) { # YYYYMMDDHHMMSS
    $fromString =~ /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$/;
    if ($fromString !~ /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$/) {
      $self->{'error'} = 'Input string is not in gen date format';
    } else {
      my ($year,$month,$day,$hour,$minute,$second) = ($1,$2,$3,$4,$5,$6);
      $year -= 1900;
      $month -= 1;
      $self->{'time'} = timegm($second,$minute,$hour,$day,$month,$year);
      return 1;
    }
  } elsif ($format =~ /^log(_(gm|local))?$/) {
    $fromString =~ /^(\d{2})\/(\d{2})\/(\d{4}) (\d{2}):(\d{2}):(\d{2})$/;
    if ($fromString !~ /^(\d{2})\/(\d{2})\/(\d{4}) (\d{2}):(\d{2}):(\d{2})$/) {
      $self->{'error'} = 'Input string is not in log format';
    } else {
      my ($month,$day,$year,$hour,$minute,$second) = ($1,$2,$3,$4,$5,$6);
      $year -= 1900;
      $month -= 1;
      if ($format eq 'log' || $format eq 'log_gm') {
        $self->{'time'} = timegm($second,$minute,$hour,$day,$month,$year);
      } elsif ($format eq 'log_local') {
        $self->{'time'} = timelocal($second,$minute,$hour,$day,$month,$year);
      }
      return 1;
    }
  } elsif ($format =~ /^mm\/yy_(end|begin)(_(gm|local))?/i) { ## mm/yy format
    if ($fromString !~ /^(\d\d)\/(\d\d)$/) {
      $self->{'error'} = 'Input string is not in mm/yy format';
    } else {
      my $currentYear = new PlugNPay::Sys::Time('year2');

      my $month = $1 - 1;
      my $year = $2 + ($2 > $currentYear + 10 ?  1900 : 2000);
      my $secondOffset = 0;

      # if the end of the month, add 1 to month and subtract 1 second
      if ($format =~ /end/) {
        $month = $month + 1;
        if ($month == 12) {
          $month = 0;
          $year++;
        }
        $secondOffset = -1;
      } elsif ($format !~ /begin/) {
        $self->{'warning'} = 'Ambiguous mm/dd format requested';
      }

      if ($format =~ /_local$/) {
        $self->{'time'} = Time::Local::timelocal(0,0,0,1,$month,$year) + $secondOffset;
      } else {
        $self->{'time'} = Time::Local::timegm(0,0,0,1,$month,$year) + $secondOffset;
      }
      return 1;
    }
  } elsif ($format =~ /^yyyymmdd(_(gm|local))?/i) {
    if ($fromString !~ /^(\d\d\d\d)(\d\d)(\d\d)$/) {
      $self->{'error'} = 'Input string is not in yyyymmdd format';
    } else {
      my $year = $1 - 1900;
      my $month = $2 - 1;
      my $mday = $3;
      if ($format =~ /_local$/) {
        $self->{'time'} = Time::Local::timelocal(0,0,0,$mday,$month,$year);
      } else {
        $self->{'time'} = Time::Local::timegm(0,0,0,$mday,$month,$year);
      }
      return 1;
    }
  } elsif ($format =~ /^hex$/) { ## hex format
    if ($fromString =~ /^[A-Fa-z0-9]+$/) {
      $self->{'time'} = unpack('I*',pack('h*',$fromString)) - $self->{'offset'};
      return 1;
    } else {
      $self->{'error'} = 'Input string contains non-hex characters';
    }

   } else {
    $self->{'error'} = 'Invalid format specified.';
  }

  return undef;
}

## returns a string in the format specified.
sub inFormat {
  my $self = shift;
  my $format = shift || undef;;

  if (!defined $format) {
    $self->{'error'} = 'Format not specified';
    return undef;
  } elsif (!defined $self->{'time'}) {
    return undef;
  }

  my $time = $self->{'time'};

  # Store current timezone, change to set timezone (Using Env::C::setenv()) if calling the timezone format.
  my $originalTimeZone = $ENV{'TZ'};
  if ($format =~ /_timezone$/) {
    Env::C::setenv('TZ',$self->getTimeZone, 1);
  }

  my ($sec,$min,$hr,$day,$mon,$year);
  if ($format =~ /_(local|timezone)$/) {
    ($sec, $min, $hr, $day, $mon, $year) = localtime($time);
  } else {
    ($sec, $min, $hr, $day, $mon, $year) = gmtime($time);
  }

  # If timezone format, restore the timezone to the orginal timezone.
  if ($format =~ /_timezone$/) {
    Env::C::setenv('TZ',$originalTimeZone, 1);
  }

  $year += 1900;
  $mon += 1;

  if ($format =~ /^log_(gm|local|timezone)/i) {
    return sprintf("%02d/%02d/%04d %02d:%02d:%02d", $mon, $day, $year, $hr, $min, $sec);
  } elsif ($format =~ /^db(_(gm|local))?$/i) {
    return sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year, $mon, $day, $hr, $min, $sec);
  } elsif ($format =~ /^iso(_(gm|local))?$/i) { #iso 8601 format: YYYYMMddTHHmmSSZ
    return sprintf("%04d%02d%02dT%02d%02d%02dZ", $year, $mon, $day, $hr, $min, $sec);
  } elsif ($format =~ /^iso_separated_gm$/i) { #iso 8601 format: YYYYMMddTHHmmSSZ
    return sprintf("%04d-%02d-%02dT%02d:%02d:%02dZ", $year, $mon, $day, $hr, $min, $sec);
  } elsif ($format eq 'iso_gm_nano_log') {
    my $timeString = sprintf("%04d-%02d-%02dT%02d:%02d:%02d", $year, $mon, $day, $hr, $min, $sec);
    my $nano = sprintf("%.6f",$time); # just the decimal portion
    $nano =~ s/.*\.//;
    $timeString = $timeString . '.' . $nano . 'Z';
    return $timeString;
  } elsif ($format =~ /^unix$/i) {
    $time =~ s/\..*$//;
    return $time;
  } elsif ($format =~ /^hex(_(gm|local))?$/i) {
    my $local = '';
    if ($format =~ /_local$/) {
      $local = '_local';
    }
    my $hex = unpack('h*',pack('I*',$self->inFormat('unix')));
    $hex =~ tr/a-z/A-Z/;
    return $hex;
  } elsif ($format =~ /^year2(_(gm|local))?/i) {
    return substr($year,2,2);
  } elsif ($format =~ /^mm\/yy(_(gm|local))?/i) {
    return sprintf("%02d",$mon) . '/' . substr($year,2,2);
  } elsif ($format =~ /^yyyymmdd(_(gm|local))?/i) {
    return sprintf("%04d%02d%02d",$year,$mon,$day);
  } elsif ($format eq 'gendatetime') {
     return sprintf("%04d%02d%02d%02d%02d%02d",$year,$mon,$day,$hr,$min,$sec);
  }
}

# same as inFormat, but updates the time before returning the format
sub nowInFormat {
  my $self = shift;
  my $format = shift || undef;

  if (!defined $format) {
    return undef;
  }

  $self->{'time'} = Time::HiRes::time();
  return $self->inFormat($format);
}

sub inFormatDetectType {
  my $self = shift;
  my $newFormat = shift || '';
  my $input = shift || '';
  my $options = shift || {};

  my $detectedFormat = $self->detectFormat($input,$options);

  if ($detectedFormat) {
    $self->{'error'} = ''; # clear any previous error
    $self->fromFormat($detectedFormat,$input);
    return $self->inFormat($newFormat);
  }

  $self->{'error'} = 'Unable to detect format';
  return undef;
}

sub validateFormat {
  my $self = shift;
  my $format = shift;
  my $input = shift;

  if ($format eq 'db') { # db and db_gm are the same format
    $format = $format . '_gm';
  }

  my $validationString = $formats->{$format}{'validation'};
  my $result;
  eval "\$result = (\$input =~ $validationString)";
  return $result;
}

### detectFormat
## note that this assumes anything in db format is in GM time unless told otherwise
sub detectFormat {
  my $self = shift;
  my $input = shift;
  my $options = shift || {};

  $options->{'localtime'} ||= 0; # set localtime to false if not defined to prevent warnings.
  my $localtime = 0;
  if (ref($options) eq 'HASH' && $options->{'localtime'}) {
    $localtime = 1;
  }

  my $currentConfidence = -1;
  my $currentKey = undef;

  foreach my $key (keys %{$formats}) {
    if ($self->validateFormat($key,$input)) {
      $formats->{$key}{'confidence'} ||= 0; # set to zero if undefined to avoid warning on comparison
      my $keyConfidence = $formats->{$key}{'confidence'};

      # check to see if we're supposed to assume local time instead of gmt
      if ($key =~ /_gm$/ && $localtime) {
        $key =~ s/_gm$//;
      }

      if ($keyConfidence > $currentConfidence) {
        $currentKey = $key;
        $currentConfidence = $keyConfidence;
      }
    }
  }

  return $currentKey;
}

# takes a time object and compares it's time with the caller's time.  if it is before, returns true, else returns false
sub isBefore {
  my $self = shift;

  my $compareTime = shift || undef;

  if (!defined $compareTime) {
    $self->{'error'} = 'Cannot compare time to undefined time';
  }

  if (ref($compareTime) eq ref($self)) {
    return ($self->_timeCompare($self->{'time'}, $compareTime->time()) == -1);
  }
  return undef;
}

# takes a time object and comares it's time with the callers's time.  if it is after, returns true, else returns false
sub isAfter {
  my $self = shift;

  my $compareTime = shift || undef;

  if (!defined $compareTime) {
    $self->{'error'} = 'Cannot compare time to undefined time';
  }

  if (ref($compareTime) eq ref($self)) {
    return ($self->_timeCompare($self->{'time'}, $compareTime->time()) == 1);
  }
  return undef;
}

sub time {
  my $self = shift;
  return $self->{'time'};
}

# utility function used by isBefore and isAfter
sub _timeCompare {
  my $self = shift;
  my ($time1, $time2) = @_;

  $time1 =~ s/[^\d\.]//g;
  $time2 =~ s/[^\d\.]//g;

  if ($time1 > $time2) { return 1; }
  elsif ($time1 == $time2) { return 0; }
  else { return -1; };
}

sub error {
  my $self = shift;
  return $self->{'error'};
}

sub warning {
  my $self = shift;
  return $self->{'warning'};
}


sub getTimeZoneOffset {
  my $self = shift;
  my $offset = 0;

  my $time = &time();

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
  my $sth = $dbh->prepare(q/
    SELECT offset,offset_dst
      FROM timezone
     WHERE timezone = ?
  /) or die($DBI::errstr);

  $sth->execute($self->getTimeZone()) or die($DBI::errstr);

  my $result = $sth->fetchall_arrayref({});
  if ($result) {
    my $originalTimeZone = $ENV{'TZ'};
    Env::C::setenv('TZ', $self->getTimeZone(), 1);
    my @localtime  = localtime(&time());
    my $isDST = $localtime[8];
    Env::C::setenv('TZ', $originalTimeZone, 1);

    my $offsetField = ($isDST ? 'offset_dst' : 'offset');

    # offset is in hours so multiply times 3600 to get seconds
    $offset = $result->[0]{$offsetField} * 3600;
  }
  return $offset;
}

sub getLastOfMonth {
  my $self = shift;
  my $month = shift;
  my $year = shift || undef;
  $month = sprintf('%02d',$month);

  my $shortMonths = {'04' => '30', '06' => '30', '09' => '30', '11' => '30' };

  if ($month eq '02') {
    if (defined $year && $year !~ /^\d{4}$/) {
      $year = '20' . substr($year,-2,2);
    }

    if (defined $year && $year % 4 == 0) {
      return '29';
    } else {
      return '28';
    }
  } elsif ( defined $shortMonths->{$month}){
    return '30';
  } else {
    return '31';
  }
}

sub isValidDateRange {
  my $self = shift;
  my $options = shift;

  # start params
  my $startDay   = $options->{'startDay'};
  my $startMonth = $options->{'startMonth'};
  my $startYear  = $options->{'startYear'};

  # end params
  my $endDay   = $options->{'endDay'};
  my $endMonth = $options->{'endMonth'};
  my $endYear  = $options->{'endYear'};

  my $validDateRange = 0;
  if ($startDay <= $endDay) {
    if ($startMonth <= $endMonth) {
      if ($startYear <= $endYear) {
        $validDateRange = 1;
      }
    } else {
      if ($startYear < $endYear) {
        $validDateRange = 1;
      }
    }
  } else {
    if ($startMonth < $endMonth) {
      if ($startYear <= $endYear) {
        $validDateRange = 1;
      }
    } else {
      if ($startYear < $endYear) {
        $validDateRange = 1;
      }
    }
  }

  return $validDateRange;
}

sub validDate {
  my $self = shift;
  my ($day, $month, $year) = @_;

  if ($year < 0) {
    return 0;
  } elsif ($month < 1 || $month > 12) {
    return 0;
  } elsif ($day < 0 || $day > $self->getLastOfMonth($month, $year)) {
    return 0;
  }

  return 1;
}

sub yy {
  my (undef, undef, undef, undef, undef, $year) = gmtime(time());
  return substr($year+1900,-2);
}

sub yyyy {
  my (undef, undef, undef, undef, undef, $year) = gmtime(time());
  return $year+1900;
}

sub mm {
  my (undef, undef, undef, undef, $mon, undef) = gmtime(time());
  return sprintf('%02d',$mon+1);
}

1;
