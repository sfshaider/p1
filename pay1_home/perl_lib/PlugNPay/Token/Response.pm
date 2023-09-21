package PlugNPay::Token::Response;

use strict;
use JSON::XS;
use PlugNPay::Logging::Alert;
use PlugNPay::Logging::DataLog;

sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  my $responseString = shift;
  my $requestType = shift;

  $self->parseResponse($responseString,$requestType);

  return $self;
}

sub parseResponse {
  my $self = shift;
  my $responseString = shift;
  my $requestType = shift; 
  my $alerter = new PlugNPay::Logging::Alert();
  my $logger = new PlugNPay::Logging::DataLog({'collection' => 'token_server_response'});

  chomp $responseString;
  

  if ($responseString) {
    my %responseErrors;
    my %responseData;

    eval {
      my $responseHash = decode_json($responseString);
      my $dbError = $responseHash->{'error'};
      my $tokens = $responseHash->{'requests'} || {};
      my $values = $responseHash->{'redeems'} || {};

      if ($dbError) {
        $alerter->alert(1, 'Token server error: ' . $dbError);
        %responseErrors = ('error' => $dbError);
        %responseData = ();
      } else {
        foreach my $identifier (keys %{$tokens}) {
          my $token = $tokens->{$identifier}{'token'};
          my $error = $tokens->{$identifier}{'error'};

          if ($error) {
            $responseErrors{$identifier} = $error;
          } else {
            unless($token) {
              $alerter->alert(1,'Null token response');
            }
  
            $responseData{$identifier} = $token;
          }
        }

        foreach my $identifier (keys %{$values}) {
          my $value = $values->{$identifier}{'value'};
          my $error = $values->{$identifier}{'error'};

          if ($error) {
            $responseErrors{$identifier} = $error;
          } else {
            unless($value) {
              $alerter->alert(1,'Null token response value');
            }
  
            $responseData{$identifier} = $value;
          }
        }
      }
    };

    if ($@) {
      $alerter->alert(1,'Token server returned invalid response!');
      $logger->log($@);
    }

    $self->{'responseData'} = \%responseData;
    $self->{'responseErrors'} = \%responseErrors;

  } else {
    $alerter->alert(1,'Token server failed to respond!');
    $logger->log('Failed to connect to token server');
  }
}


sub get {
  my $self = shift;
  my $identifier = shift;
  if ($self->{'responseErrors'}{$identifier}) {
    die($self->{'responseErrors'}{$identifier});
  } else {
    return $self->{'responseData'}{$identifier};
  }
} 

sub getTokens {
  my $self = shift;
  return $self->{'responseData'};
}

1;
