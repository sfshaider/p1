package PlugNPay::Processor::SocketConnector;

use strict;
use JSON::XS qw(encode_json decode_json);
use IO::Socket::SSL;
use PlugNPay::DBConnection;
use PlugNPay::Processor::ID;
use PlugNPay::Util::Cache::LRUCache;
use PlugNPay::Logging::DataLog;
use PlugNPay::ResponseLink::Microservice;
use PlugNPay::Die;

our $cache;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  if (!defined $cache) {
    $cache = new PlugNPay::Util::Cache::LRUCache(3);
  }

  $self->getProcessorPorts();

  return $self;
}

sub getProcessorPorts { #Gets port/host for the server where processor JAVA code is running
  my $self = shift;
  my $ports;
  if (!$cache->contains('processor_ports')) {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnpmisc',q/
                              SELECT processor,port,host,max_connections,path
                              FROM processor_socket_info
    /);
    $sth->execute() or die $DBI::errstr;
    my $rows = $sth->fetchall_arrayref({});
    my $loadedPorts = {};
    my $connections = {};
    foreach my $row (@{$rows}){
      my $proc_id = $row->{'processor'};
      $loadedPorts->{$proc_id}{'port'} = $row->{'port'};
      $loadedPorts->{$proc_id}{'host'} = $row->{'host'};
      my $method = 'socket';
      if ($row->{'path'} ne '') {
        $method = 'http';
        $loadedPorts->{$proc_id}{'path'} = $row->{'path'};
      } elsif ($row->{'host'} eq 'lambda') {
        $method = 'lambda';
      }

      $loadedPorts->{$proc_id}{'method'} = $method;
      $connections->{$proc_id} = $row->{'max_connection'};
    }
    $self->{'processor_connections'} = $connections;
    $cache->set('processor_ports',$loadedPorts);
  }

  $ports = $cache->get('processor_ports');
  $self->{'processor_ports'} = $ports;
  

  return $ports
}

# Socket connection, loads host/port based on processor ID #
sub connectToProcessor {
  my $self = shift;
  my $socketData = shift;
  my $processorID = shift;
  my $procIDTranslator = new PlugNPay::Processor::ID();

  my $hostPortInfo = $self->getProcessorPorts();
  my $port = $hostPortInfo->{$procIDTranslator->getProcessorName($processorID)}{'port'};
  my $host = $hostPortInfo->{$procIDTranslator->getProcessorName($processorID)}{'host'};
  my $method = $hostPortInfo->{$procIDTranslator->getProcessorName($processorID)}{'method'};
  my $response;

  if ($method eq 'http') {
    my $path = $hostPortInfo->{$procIDTranslator->getProcessorName($processorID)}{'path'};
    $response = $self->_connectThruWeb($socketData, $processorID, $host, $port, $path);
  } elsif ($method eq 'lambda') {
    $response = $self->_connectToLambda($socketData, $processorID);
  } else {
    $response = $self->_connectViaSocket($socketData, $processorID, $host, $port);
  }

  return $response;
}

sub _connectThruWeb {
  my $self = shift;
  my $webData = shift;
  my $processorID = shift;
  my $host = shift;
  my $port = shift;
  my $path = shift;

  if ($path !~ /^\//) {
    $path = '/' . $path; 
  }
  
  my $microservice = new PlugNPay::ResponseLink::Microservice('http://' . $host . ':' . $port . $path);
  $microservice->setMethod('POST');
  $microservice->setContent($webData);
  $microservice->setContentType('application/json');
  my $status = $microservice->doRequest();
  if (!$status) {
    my $procIDTranslator = new PlugNPay::Processor::ID();
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'socketConnection'});
    $logger->log({'message' => 'Microservice request error occurred', 'error' => join(', ',$microservice->getErrors()) , 'processor' => $procIDTranslator->getProcessorName($processorID)});
    die "Request to service failed, contact support for assistance.";
  }

  return $microservice->getRawResponse();
}

sub _connectViaSocket {
  my $self = shift;
  my $socketData = shift;
  my $processorID = shift;
  my $host = shift;
  my $port = shift;
  my $socket;

  eval {
    $socket = IO::Socket::SSL->new (
        # where to connect
        PeerHost => $host,
        PeerPort => $port,
        Timeout => 60,
        # certificate verification
        SSL_verify_mode => 0x00,
        SSL_cipher_list => 'AECDH-AES256-SHA:ADH-AES256-GCM-SHA384:ADH-AES256-SHA256:ADH-AES256-SHA:AECDH-AES128-SHA:ADH-AES128-GCM-SHA256:ADH-AES128-SHA256:ADH-AES128-SHA'
    );
  };

  if ($@ || !defined $socket) {
    my $procIDTranslator = new PlugNPay::Processor::ID();
    my $errorReason = (defined $socket ? $@ : 'Unable to create socket instance');
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'socketConnection'});
    $logger->log({'message' => 'Socket error occurred', 'error' =>  $errorReason, 'processor' => $procIDTranslator->getProcessorName($processorID)});
    die "Connection error occured, contact support for assistance.";
  }
  print $socket $socketData . "\n";
  my $response = '';
  $response = <$socket>;
  return $response;
}

sub _connectToLambda {
  my $self = shift;
  my $rawRequest = shift;
  my $processorID = shift;
  my $managerURL =  &PlugNPay::AWS::ParameterStore::getParameter('/PROCESSOR/MANAGER/SERVER');
  if (!$managerURL) {
    die "Failed to load processor manager URL!\n";
  }

  my $microservice = new PlugNPay::ResponseLink::Microservice($managerURL); #'http://' . $host . ':' . $port . $path);
  $microservice->setMethod('POST');
  $microservice->setContent(decode_json($rawRequest));
  $microservice->setContentType('application/json');
  my $status = $microservice->doRequest();
  if (!$status) {
    my $procIDTranslator = new PlugNPay::Processor::ID();
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'socketConnection'});
    $logger->log({'message' => 'Microservice request error occurred', 'error' => join(', ',$microservice->getErrors()) , 'processor' => $procIDTranslator->getProcessorName($processorID)});
    die "Request to processor failed, contact support for assistance.";
  }

  return $microservice->getRawResponse();

}

1;
