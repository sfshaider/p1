package PlugNPay::Transaction::IpList;

use strict;
use PlugNPay::ResponseLink::Microservice;
use PlugNPay::Transaction::IpList::IpInfo;
use PlugNPay::Util::Array qw(inArray);


our $ipListHost = '';

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub getHost {
  my $self = shift;

  if ($ipListHost ne '') {
    return $ipListHost;
  }

  my $envHost = $ENV{'PNP_IPLIST_HOST'};
  if ($envHost ne '') {
    $ipListHost = $envHost;
  } else {
    $ipListHost = 'http://microservice-iplist.local';
  }
}

sub enabled {
  my $self = shift;

  return ! -e '/home/pay1/etc/iplist_disabled';
}

sub updateOnly {
  my $self = shift;
  return -e '/home/pay1/etc/iplist_updateonly';
}

sub getBlacklist {
  my $self = shift;
  
  my $url = sprintf('%s/v1/blacklist',$self->getHost());

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($url);
  $ms->setMethod('GET');
  $ms->setTimeout(1);
  my $ok = $ms->doRequest();

  my $list;
  if ($ok) {
    $list = $ms->getDecodedResponse();
  }

  return $list->{'list'} || [];
}

sub getIpInfo {
  my $self = shift;
  my $input = shift;

  my $ip = $input->{'ip'};
  my $getRequests = $input->{'getRequests'} ? 1 : 0;

  my $url;
  if ($getRequests) {
    $url = sprintf('%s/v1/ip/%s/requests',$self->getHost(),$ip);
  } else {
    $url = sprintf('%s/v1/ip/%s',$self->getHost(),$ip);
  }

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($url);
  $ms->setMethod('GET');
  $ms->setTimeout(1);
  my $ok = $ms->doRequest();
  my $ipi = new PlugNPay::Transaction::IpList::IpInfo();
  if ($ok) {
    my $data = $ms->getDecodedResponse();

    $ipi->setForcedStatus($data->{'forcedStatus'});
    $ipi->setRecommendation($data->{'recommendation'});
    $ipi->setReason($data->{'reason'});
    $ipi->setPositiveCount($data->{'positives'});
    $ipi->setNegativeCount($data->{'negatives'});
    $ipi->setRecentRequests($data->{'recentRequests'});
  } else {
    $ipi->setRecommendation('allow');
    $ipi->setReason('requestFailed');
  }

  return $ipi;
}

sub deleteIpInfo {
  my $self = shift;
  my $input = shift;

  my $ip = $input->{'ip'};

  my $url = sprintf('%s/v1/ip',$self->getHost());

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($url);
  $ms->setMethod('DELETE');
  $ms->setContent({
    ip => $ip,
    reason => 'delete'
  });
  $ms->setTimeout(1);
  $ms->doRequest();
}

sub updateIpInfo {
  my $self = shift;
  my $input = shift;

  my $ip = $input->{'ip'};
  my $status = $input->{'status'};
  my $reason = $input->{'reason'};
  my $accountUsername = $input->{'accountUsername'};
  my $transactionId = $input->{'transactionId'};
  
  if (!defined $ip || $ip eq '') {
    die('ip is required');
  }

  if (!inArray($status,['negative','neutral','positive'])) {
    die('invalid status to update ip');
  }

  if (!defined $reason) {
    die('reason is required');
  }


  my $data = {
    ip => $ip,
    status => $status,
    reason => $reason,
    accountUsername => $accountUsername,
    trasnactionId => $transactionId
  };

  my $url = sprintf('%s/v1/ip',$self->getHost());

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($url);
  $ms->setMethod('POST');
  $ms->setContent($data);
  $ms->setTimeout(2);
  $ms->doRequest();
}

sub forceIpStatus {
  my $self = shift;
  my $input = shift;

  my $ip = $input->{'ip'};
  my $forceStatus = $input->{'status'};
  my $reason = $input->{'reason'};

  my $data = {
    ip => $ip,
    forceStatus => $forceStatus,
    reason => $reason,
  };

  my $url = sprintf('%s/v1/ip',$self->getHost());

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($url);
  $ms->setMethod('POST');
  $ms->setContent($data);
  $ms->setTimeout(5);
  $ms->doRequest();
}

1;