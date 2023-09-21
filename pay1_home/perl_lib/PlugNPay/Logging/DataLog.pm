package PlugNPay::Logging::DataLog;

use strict;
use Fcntl;
use threads;
use JSON::XS;
use Data::UUID;
use File::Path;
use File::Spec;
use Sys::Syslog;
use Sys::Syslog qw(:extended :standard :macros);
use Sys::Hostname;
use PlugNPay::Sys::Time;
use PlugNPay::Util::Clone;
use PlugNPay::Util::UniqueID;
use PlugNPay::AWS::Lambda;
use PlugNPay::Util::StackTrace;
use PlugNPay::Environment;

sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self, $class;

  my $settings = shift;

  if ( !defined $settings->{'collection'} ) {
    die('Collection not specified for DataLog: ' . new PlugNPay::Util::StackTrace()->string(','));
  }

  $settings->{'collection'} = lc $settings->{'collection'};
  $self->{'settings'} = $settings;

  return $self;
}

sub log {
  my ( $self, $logData, $options ) = @_;
  my $data = $logData;

  my $callerDepth = ( defined $options->{'depth'} ? $options->{'depth'} + 1 : 1 );
  my $stackTraceEnabled = $options->{'stackTraceEnabled'};

  my $generator = new Data::UUID();
  my $uuid      = $generator->create_str();
  $uuid =~ s/\-//g;
  my $logID = $uuid;

  eval {
    my $cloner = new PlugNPay::Util::Clone();
    $data = $cloner->deepClone( $logData, { unbless => 1, maxDepth => 100 } );
  };

  if ($@) {
    print STDERR $@ . "\n";
  }

  my $host  = $self->{'settings'}{'server'} || $ENV{'PNP_DATALOG_SERVER'}          || 'datalog';
  my $port  = $self->{'settings'}{'port'}   || $ENV{'PNP_DATALOG_SERVER_PORT'}     || '514';
  my $proto = $self->{'settings'}{'proto'}  || $ENV{'PNP_DATALOG_SERVER_PROTOCOL'} || 'udp';

  my $json = undef;
  eval {    # if this fails we don't want it to affect the running process
    $data = { data => $data } if !ref($data);
    $data->{'logId'} = $logID;
    my $info = $self->getLoggingInfo( $callerDepth + 1, $stackTraceEnabled );    # the eval is a function call
    $data = { %{$data}, %{$info} };                                              # merge metadata hash with data hash
    $json = JSON::XS->new->utf8->encode($data);

    if ( -d '/home/pay1/log/local/datalog' ) {
      my $time = new PlugNPay::Sys::Time();
      eval {
        my @dateTime = split( ' ', $time->inFormat('db_gm') );
        my $logTime  = $dateTime[0] . 'T' . $dateTime[1] . 'Z' . '  ';
        my $dateFile = 'datalog.' . $dateTime[0] . '.log';
        sysopen( my $FH, '/home/pay1/log/local/datalog/' . $dateFile, O_CREAT|O_WRONLY|O_APPEND, 0666);
        print $FH $logTime . $data->{'__module__'} . ':' . $data->{'__function__'} . ':' . $data->{'__line_number__'} . "\n";
        close $FH;
      };
    }

    my $lambda_message = { LogEntry => $json };

    # log to send_log lambda
    if ( -e "/home/pay1/etc/datalog/sendlog") {
      $self->logViaSendLog($lambda_message);
    } else { 
      $self->logViaLogServer($data, $options);
    }
    
    #log to file if we can
    eval {
      my $path = '/home/pay1/log/datalog/' . $self->{'settings'}{'collection'};
      $path =~ s/\/[\/]+/\//g;

      if ( $ENV{'DATALOG_MAKEPATH'} eq '1' ) {
        File::Path::make_path( $path, { chmod => '0777' } );
      }

      if ( -d $path ) {
        unless ( substr( $path, -1 ) eq '/' ) {
          $path .= '/';
        }

        my $time = new PlugNPay::Sys::Time();
        my $originalUmask = umask 0111;
        eval {
          my @dateTime = split( ' ', $time->inFormat('db_gm') );
          my $logTime  = $dateTime[0] . 'T' . $dateTime[1] . 'Z' . '  ';
          my $dateFile = $self->{'settings'}{'collection'} . '.' . $dateTime[0] . '.log';
          sysopen( my $FH, $path . $dateFile, O_CREAT|O_WRONLY|O_APPEND, 0666);
          print $FH $logTime . $json . "\n";
          close $FH;
        };
        umask $originalUmask;
      }
    };

    if ($@) {
      print STDERR $@ . "\n";
    }
    

    if ( $ENV{'PNP_LOGGING_STDERR'} ) {
      print STDERR $self->{'settings'}{'collection'} . ': ' . $json . "\n";
    }

  };

  if ($@) {
    print STDERR $@ . "\n";
  }

  return $json, $logID;
}

sub getLoggingInfo {
  my $self              = shift;
  my $depth             = shift;
  my $stackTraceEnabled = shift;

  my @callerInfo = caller( 1 + $depth );

  my $file = File::Spec->rel2abs($0);

  my $stackTrace = undef;
  if ($stackTraceEnabled) {
    $stackTrace = new PlugNPay::Util::StackTrace($depth)->arrayRef;
  }


  my $info = {
    '__ip_address__'   => PlugNPay::Environment::getClientIP(),
    '__thread__'       => threads->tid(),                                            # this always returns 0 :shrug:
    '__pid__'          => $$,
    '__timestamp__'    => new PlugNPay::Sys::Time->nowInFormat('iso_gm_nano_log'),
    '__function__'     => $callerInfo[3],
    '__line_number__'  => $callerInfo[2],
    '__src_file__'     => $file,
    '__src_filename__' => $0,
    '__module__'       => $callerInfo[0],
    '__collection__'   => $self->{'settings'}{'collection'},
    '__hostname__'     => hostname,
    '__stacktrace__'   => $stackTrace
  };

  return $info;
}

sub logViaSendLog {
  my $self = shift;
  my $rawData = shift;

  my $userAgent = new LWP::UserAgent;
  $userAgent->agent('PNP Perl Datalog Module');
  $userAgent->timeout(5);
  $userAgent->parse_head(0);

  my $request = new HTTP::Request('POST' => 'http://localhost:10514/send_log');
  $request->content_type('application/json');
  
  my $requestData = encode_json($rawData);
  $request->content($requestData);

  $userAgent->request($request);
}

sub logViaLogServer {
  my $self = shift;
  my $logData = shift;
  my $options = shift;

  my $ms;

  if ($options->{confirm}) {
    $ms = new PlugNPay::ResponseLink::Microservice('http://microservice-logging.local/log/confirm');
  } else {
    $ms = new PlugNPay::ResponseLink::Microservice('http://microservice-logging.local/log');
  }

  $ms->setMethod('POST');

  my $success = $ms->doRequest($logData);
  if (!$success) {
    print STDERR "Error writing log to log server!  Error(s): " . join (@{$ms->getErrors()},',') . "\n";
  }
}
1;
