package PlugNPay::Fraud::Frequency;

use strict;
use PlugNPay::Util::Status;
use PlugNPay::Fraud::Positive;
use PlugNPay::GatewayAccount::API::ACL::IP;
use PlugNPay::DBConnection;
use PlugNPay::Sys::Time;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;


  return $self;
}

sub checkFrequency {
  my $self = shift;
  my $options = shift;
  my $fraudConfig = $options->{'fraudConfig'};

  my $posCheck = $self->checkPositiveFrequency($options->{'gatewayAccount'}, $options->{'hashedCardNumber'}, $fraudConfig);
  my $checkPassedIP = $self->checkFrequencyLog($options->{'gatewayAccount'}, $options->{'ipAddress'}, $options->{'transactionTime'}, $fraudConfig);

  my $status = new PlugNPay::Util::Status(1);
  my @errors = ();

  if ($posCheck) {
    push @errors, 'Too many transactions within allotted time with this payment information';
  } 
 
  if ($checkPassedIP) {
    push @errors, 'Maximum number of attempts has been exceeded for this IP';
  }

  if (@errors > 0) {
    $status->setFalse();
    $status->setError('Transaction failed frequency check');
    $status->setErrorDetails(join(', ', @errors));
  }

  return $status;
}

sub checkPositiveFrequency {
  my $self = shift;
  my $username = shift;
  my $hashedCardNumber = shift;
  my $fraudConfig = shift;
  my $frequencyCheck = 0;
  my ($level,$days,$hours) = split(/\:/,$fraudConfig->get('freqchk'));

  if ($fraudConfig->get('freqchk') ne '' && $level > 0) {
    my $positiveData = new PlugNPay::Fraud::Positive();

    #get datetime
    my $timeAdjust = ($days * 24 * 3600) + ($hours * 3600);
    my $timeObj = new PlugNPay::Sys::Time();
    $timeObj->subtractSeconds($timeAdjust);
    my $dateTime = $timeObj->inFormat('gendatetime');
    my $positiveCount = 0;
    if ($hashedCardNumber && $username) {
      my $loaded = $positiveData->query({
        'start_time'    => $dateTime,
        'shacardnumber' => $hashedCardNumber,
        'result'        => 'success',
        'username'      => $username
      });

      $positiveCount = @{$loaded};
    }

    $frequencyCheck = $positiveCount > $level;
  }

  return $frequencyCheck;
}

sub checkFrequencyLog {
  my $self = shift;
  my $username = shift;
  my $ipAddress = shift;
  my $transTime = shift;
  my $fraudConfig = shift;
  my $ipCheck = 0;
  if ($ipAddress) {
    my $maxFrequency = $fraudConfig->get('ipfreq') || 5;
    my $count = 0;
    if ($ipAddress && !$fraudConfig->get('ipskip') && !$self->isExemptIP($username, $ipAddress, $fraudConfig)) {
      # Doing some needful
      $count = $self->getFrequencyCount($ipAddress);
      $self->addFrequencyLog($ipAddress, $transTime);
    }
    $ipCheck = $count > $maxFrequency;
  }
 
  return $ipCheck;
}

sub getFrequencyCount {
  my $self = shift;
  my $ipAddress = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $select = q/
    SELECT COUNT(*) AS `count`
      FROM freq_log
     WHERE ipaddr = ? 
       AND rawtime > ?
  /; 

  my $timeObj = new PlugNPay::Sys::Time();
  $timeObj->subtractMinutes(1);
  my $results = $dbs->fetchallOrDie('fraudtrack', $select, [$ipAddress, $timeObj->inFormat('unix')], {})->{'result'};

  return $results->[0]{'count'};
}

sub addFrequencyLog {
  my $self = shift;
  my $ipAddress = shift;
  my $transactionTime = shift;
 
  my $timeObj = new PlugNPay::Sys::Time();
  my $dbs = new PlugNPay::DBConnection();

  my $insert = q/
    INSERT INTO freq_log (`ipaddr`, `rawtime`, `trans_time`)
    VALUES (?,?,?)
  /; 

  eval {
    $dbs->executeOrDie('fraudtrack', $insert, [$ipAddress, $timeObj->nowInFormat('unix'), $transactionTime]);
  };

  return ($@ ? 0 : 1);
}

sub isExemptIP {
  my $self = shift; 
  my $username = shift;
  my $ipAddress = shift;
  my $fraudConfig = shift;
  my $shouldCheckExempt = $fraudConfig->get('ipexempt');
  my $response;

  #need fraud config setting: ipexempt
  if ($shouldCheckExempt) {
    my $client = new PlugNPay::GatewayAccount::API::ACL::IP($username);
    my $loaded = $client->loadIP($ipAddress, $username);
    my %data = map{$_->{'ipaddress'} => 1} @{$loaded};
    $response = $data{$ipAddress};
  }

  return $response;
}

1;
