package PlugNPay::Logging::Alert;

use strict;
use Sys::Hostname;
use PlugNPay::Email;
use PlugNPay::Sys::Time;
use PlugNPay::DBConnection;
use PlugNPay::Util::StackTrace;
use PlugNPay::Util::Cache::LRUCache;
use Apache2::ServerRec;

our $cache;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  if (!defined $cache) {
    $cache = new PlugNPay::Util::Cache::LRUCache(3);
  }

  $self->{'alertCodes'} = $self->loadAlertCodes();

  return $self;
}

sub loadAlertCodes {
  my $self = shift;
  my $codes = {};
  if (!defined $cache->get('alert_codes')) {

    my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
    my $sth = $dbs->prepare(q/ SELECT c.code,c.description,s.severity AS `severity`, c.severity AS `slevel`
                                  FROM alert_code c, alert_severity_levels s
                                  WHERE s.id = c.severity
                              /);
    $sth->execute() or die $DBI::errstr;
    my $rows = $sth->fetchall_arrayref({});

    foreach my $row (@{$rows}){
      $codes->{$row->{'code'}} = $row;
    }

    $cache->set('alert_codes',$codes);
  } else {
    $codes = $cache->get('alert_codes');
  }

  return $codes;
}

sub alert {
  my $self = shift;
  my $alertCode = shift;
  my $alertDetails = shift;

  my $severity = $self->{'alertCodes'}{$alertCode}{'slevel'};
  my $description = $self->{'alertCodes'}{$alertCode}{'description'};
  my $apacheLogMessage = $description . ': ' . $alertDetails;

  if ($severity > 5) {
    eval { # log to error log if we can
      Apache2::ServerRec::err($apacheLogMessage);
    };

    if ($@) {
      print STDERR $apacheLogMessage . "\n";
    }
  }

  my $host = hostname;
  $alertDetails .= "\n\n" . 'Host: ' . $host . "\n\n";
  my $stackTrace = new PlugNPay::Util::StackTrace();
  $alertDetails .= "StackTrace: \n" . $stackTrace->string() . "\n";
  my $time = new PlugNPay::Sys::Time();

  my $dbs = new PlugNPay::DBConnection();
  $dbs->executeOrDie('pnpmisc',q/
    INSERT INTO alert
      (alert_code,alert_details,alert_date_time,status)
    VALUES (?,?,?,?)
  /, [$alertCode,$alertDetails,$time->inFormat('db_gm'),'UNSENT']);

  return 1;
}

sub getAlertRowId {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $result = $dbs->fetchallOrDie('pnpmisc',q/
    SELECT LAST_INSERT_ID() AS id
  /, [],{});

  my $rows = $result->{'rows'};
  return $rows->[0]{'id'};
}

sub getAlert {
  my $self = shift;
  my $id = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $result = $dbs->fetchallOrDie('pnpmisc',q/
    SELECT id,alert_code,alert_details,alert_date_time
    FROM alert
    WHERE id = ?
  /,[$id],{});

  my $rows = $result->{'rows'};
  my $alertRow = $rows->[0];
  if (!defined $alertRow) {
    return undef;
  }

  my $alertData = {
    id => $alertRow->{'id'},
    alertCode => $alertRow->{'alert_code'},
    alertDetails => $alertRow->{'alert_details'},
    alertDateTime => $alertRow->{'alert_date_time'}
  };

  return $alertData;
}

sub sendAlerts {
  my $self = shift;
  my $emailer = new PlugNPay::Email();
  $emailer->setVersion('legacy');
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/ SELECT id,alert_code,alert_details,alert_date_time
                             FROM alert
                             WHERE status = ? /);
  $sth->execute('UNSENT') or die $DBI::errstr;

  my $rows = $sth->fetchall_arrayref({});
  my @idArray = ();
  my $codes = $self->{'alertCodes'};
  my $time = new PlugNPay::Sys::Time();
  $time->subtractHours(3);
  my $dateTime = $time->inFormat('unix');
  my @expIDs = ();
  if(@{$rows} > 0) {
    foreach my $row (@{$rows}) {
      $time->fromFormat('db_gm',$row->{'alert_date_time'});
      if ($time->inFormat('unix') > $dateTime) {
        my $ccs = $self->_loadMessageCC($codes->{$row->{'alert_code'}}{'slevel'});
        my $message = 'An alert has been created!' . "\n\n";
        $message .= 'Alert Code: ' . $row->{'alert_code'} . "\n";
        $message .= 'Code Description: ' . $codes->{$row->{'alert_code'}}{'description'} . "\n";
        $message .= 'Code Severity: ' . $codes->{$row->{'alert_code'}}{'severity'} . "\n";
        $message .= 'Alert Time: ' . $row->{'alert_date_time'} . "\n";
        $message .= 'Details: ' . $row->{'alert_details'} . "\n\n";
        $message .= 'Sent by Alert Messenger to: ' . join(', ',@{$ccs->{'names'}}) . "\n";
        $emailer->setCC(join(',',@{$ccs->{'addressList'}}));
        $emailer->setTo('noc@plugnpay.com');
        $emailer->setFrom('noc@plugnpay.com');
        $emailer->setSubject('A system alert has occurred');
        $emailer->setContent($message);
        $emailer->setGatewayAccount($ENV{'REMOTE_USER'});
        $emailer->setFormat('text');
        $emailer->send();
        push @idArray,$row->{'id'};
      } else {
        push @expIDs,$row->{'id'};
      }
    }
    $dbs->begin('pnpmisc');

    my @params = map{'?'} @idArray;
    my $sthUpdate = $dbs->prepare('pnpmisc',q/
                                        UPDATE `alert`
                                        SET `status` = ?
                                        WHERE `id` IN (/ . join(',',@params) . ')');
    $sthUpdate->execute('SENT',@idArray) or die $DBI::errstr;

    $self->expireOldAlerts(\@expIDs);
    $dbs->commit('pnpmisc');
  }
  return 1;
}

sub _loadMessageCC {
  my $self = shift;
  my $severity = shift;
  if (!defined $self->{'message_ccs'}) {
    my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
    my $sth = $dbs->prepare(q/ SELECT name, address, severity_level
                               FROM alert_cc/);
    $sth->execute() or die $DBI::errstr;
    my $contacts = $sth->fetchall_arrayref({});
    $self->{'message_ccs'} = $contacts;
  }

  my @names = ();
  my @ccAddresses = ();
  foreach my $contact (@{$self->{'message_ccs'}}) {
      if ($severity >= $contact->{'severity_level'}) {
      unless ( grep($contact->{'name'},@names) ) {
        push @names,$contact->{'name'};
      }
      push @ccAddresses,$contact->{'address'};
    }
  }

  return {'names' => \@names, 'addressList' => \@ccAddresses};
}

sub expireOldAlerts {
  my $self = shift;
  my $ids = shift;

  if (ref($ids) ne 'ARRAY' || @{$ids} == 0) {
    return 0;
  }

  eval {
    my @params = map {'?'} @{$ids};
    my $dbs = new PlugNPay::DBConnection();
    $dbs->prepare('pnpmisc',q/
                           UPDATE `alert`
                           SET `status` = ?
                           WHERE `id` IN (/ . join(',',@params) . ')'
                  );
    $dbs->execute('EXPIRED',@{$ids}) or die $DBI::errstr;
  };

  return ($@ ? 0 : 1);
}

1;
