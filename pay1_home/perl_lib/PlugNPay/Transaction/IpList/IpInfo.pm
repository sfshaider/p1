package PlugNPay::Transaction::IpList::IpInfo;

use strict;
use PlugNPay::Sys::Time();
use PlugNPay::Util::Array qw(inArray);

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub ip {
  my $self = shift;
  return $self->{'ip'} || '';
}

sub setIp {
  my $self = shift;
  my $ip = shift || '';
  $self->{'ip'} = $ip;
}

sub accountUsername {
  my $self = shift;
  return $self->{'accountUsername'} || '';
}

sub setAccountUsername {
  my $self = shift;
  my $accountUsername = shift || '';
  $self->{'accountUsername'} = $accountUsername;
}

sub allow {
  my $self = shift;
  return $self->{'status'} eq 'neutral' || $self->{'status'} eq 'allow';
}

sub recommendation {
  my $self = shift;
  return $self->{'recommendation'} || 'allow';
}

sub setRecommendation {
  my $self = shift;
  my $recommendation = shift || 'allow';

  if (!inArray($recommendation,['allow','deny'])) {
    die('invalid recommendtation');
  }

  $self->{'recommendation'} = $recommendation;
}

sub forcedStatus {
  my $self = shift;
  return $self->{'status'} || 'neutral';
}

sub setForcedStatus {
  my $self = shift;
  my $status = shift @_ || 'neutral';

  if (!inArray($status,['positive','neutral','negative'])) {
    die('invalid force status value');
  }

  $self->{'status'} = $status;
}

sub reason {
  my $self = shift;
  return $self->{'reason'} || 'no reason specified';
}

sub setReason {
  my $self = shift;
  my $reason = shift || 'no reason specified';
  $self->{'reason'} = $reason;
}

sub positiveCount {
  my $self = shift;
  return $self->{'positiveCount'} || 0;
}

sub setPositiveCount {
  my $self = shift;
  my $count = shift;
  $self->{'positiveCount'} = $count || 0;
}

sub negativeCount {
  my $self = shift;
  return $self->{'negativeCount'} || 0;
}

sub setNegativeCount {
  my $self = shift;
  my $count = shift;
  $self->{'negativeCount'} = $count || 0;
}

sub recentRequests {
  my $self = shift;
  return $self->{'recentRequests'} || [];
}

sub setRecentRequests {
  my $self = shift;
  my $recentRequests = shift || [];
  $self->{'recentRequests'} = $recentRequests;
}

1;