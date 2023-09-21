package PlugNPay::Legacy::PayUtils::PayTemplate;

use strict;
use PlugNPay::Features;
use PlugNPay::WebDataFile;
use PlugNPay::Metrics;

sub loadTemplate {
  my $input = shift;

  my $gatewayAccount    = $input->{'gatewayAccount'};
  my $reseller          = $input->{'reseller'};
  my $cobrand           = $input->{'cobrand'};
  my $language          = $input->{'language'};
  my $client            = $input->{'client'};
  my $requestedTemplate = $input->{'requestedTemplate'};

  my $templateContent = "";
  $gatewayAccount =~ s/[^0-9a-zA-Z]//g;

  my @possibleTemplates;

  my $accountFeatures = new PlugNPay::Features( $gatewayAccount, 'general' );

  # PlugNPay::Features auto detects JSON objects and converts from an encoded form of JSON.
  # Storing raw json in features will actually break features parsing.
  # The paycgiTemplate feature is encoded json.
  my $paymentTemplate = $accountFeatures->get('paycgiTemplate');

  my $readFromFeature;

  if ( $paymentTemplate && ( !defined $requestedTemplate || $requestedTemplate eq '' ) ) {
    # client or language present requires walking through all possible options
    if ( (!defined $client || $client eq '') && (!defined $language || $language eq '') ) {
      push @possibleTemplates, $paymentTemplate;
      $readFromFeature = 1;
    }
  }

  # account language specific requested template
  if (defined $requestedTemplate && $requestedTemplate ne '') {
    if (defined $language && $language ne '') {
      push @possibleTemplates, 
        { 
        fileName => sprintf( '%s_%s_%s.txt', $gatewayAccount, $language, $requestedTemplate ),
        _md_ => { language => $language }
        };
    }

    # account specific requested template
    push @possibleTemplates, { fileName => sprintf( '%s_%s.txt', $gatewayAccount, $requestedTemplate ) };
  }

  if ( defined $language ) {
    push @possibleTemplates, 
      { 
      fileName => sprintf( '%s_%s_paytemplate.txt', $gatewayAccount, $language ),
      _md_ => { language => $language } 
      };
  }

  # account specific template
  push @possibleTemplates, { fileName => sprintf( '%s_paytemplate.txt', $gatewayAccount ) };

  # cobrand template
  if ($cobrand) {
    push @possibleTemplates,
      {
      fileName  => sprintf( '%s_paytemplate.txt', $cobrand ),
      subPrefix => 'cobrand/'
      };
  }

  # reseller template only for certain client strings? :woozy:
  # make tests crappy, hardcoded usernames do
  if ( $client =~ /^(affiniscape|aaronsinc|homesmrtin)$/ ) {
    push @possibleTemplates,
      {
      fileName => sprintf( '%s_paytemplate.txt', $reseller ),
      _md_ => { client => $client }
      };
  }

  push @possibleTemplates, { _md_ => { noTemplate => 1 } };

  my $wdf = new PlugNPay::WebDataFile();

  foreach my $templateInfo (@possibleTemplates) {
    my $subPrefix = sprintf( 'payscreen/%s', $templateInfo->{'subPrefix'} || '' );

    # Only try to load from webdatafile if there is a filename in the template info, or,
    # in other words, skip the noTemplate "possibleTemplate"
    if ( $templateInfo->{'fileName'} ) {
      $templateContent = $wdf->readFile(
        { fileName   => $templateInfo->{'fileName'},
          storageKey => 'merchantAdminTemplates',
          subPrefix  => $subPrefix
        }
      );
    }

    # if the template from the feature does not exist, set $readFromFeature to undef
    # so that a new template can be set
    if ( $templateContent eq '' && $readFromFeature ) {
      my $metric = new PlugNPay::Metrics();
      $metric->increment( { metric => 'paycgi.template.featureReadFailure' } );

      # TODO: the following is disabled until WebDataFile can detect
      # wether or not a file doesn't exist vs not being able to read the file.
      # enable the following line when this capability is added:
      # $readFromFeature = undef;
    }

    if ( $templateContent ne '' || $templateInfo->{'_md_'}{'noTemplate'} ) {
      if ( !$readFromFeature && !$requestedTemplate && !$templateInfo->{'_md_'}{'client'} && !$templateInfo->{'_md_'}{'language'} ) {
        # PlugNPay::Features auto detects objects and converts to an encoded form of JSON.
        # Storing raw json in features will actually break features parsing.
        $accountFeatures->set( 'paycgiTemplate', $templateInfo );
        $accountFeatures->saveContext();
      }
      last;
    }
  }

  return $templateContent;
}

1;
