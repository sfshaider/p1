package PlugNPay::Legacy::MckUtils::Transition;

use strict;
use warnings FATAL => 'all';

use URI;
use HTML::Entities;
use PlugNPay::WebDataFile;
use PlugNPay::DBConnection;
use PlugNPay::API;
use PlugNPay::Die;
use PlugNPay::Features;

sub transitionPage {
  # new way, send a hashref
  my $fieldsHashRef = shift;
  my $allData = shift;
  my $alwaysUsePost = shift;

  my %transitionFields = %{$fieldsHashRef};

  my $gatewayAccount = $transitionFields{'merchant'} || $transitionFields{'publisher-name'} || $transitionFields{'publisher_name'};
  $gatewayAccount =~ s/[^0-9a-zA-Z]//g;

  my $skipTransitionTemplate = $allData->{'skipTransitionTemplate'} || 0;

  my $features = new PlugNPay::Features($gatewayAccount,'general');

  my $updatedTransitionFields = filterTransitionFields({
    transitionFields => \%transitionFields,
    allData => $allData,
    features => $features
  });

  my ($url);
  if ( !defined $allData->{'FinalStatus'} ) {
    die('FinalStatus is not defined');
  }

  if ( $allData->{'FinalStatus'} eq "fraud" ) {
    $url = $allData->{'badcard-link'};
  } else {
    my $key = ($allData->{'FinalStatus'} || '') . '-link';
    $url = $allData->{$key};
  }

  if (!defined $url || $url eq '') {
    die(sprintf('no url defined for FinalStatus of "%s"',$transitionFields{'FinalStatus'}));
  }

  %transitionFields = %{$updatedTransitionFields};

  my $requestedTransitionPage = $transitionFields{'transition_page'} || $transitionFields{'transitionpage'} || $transitionFields{'pb_transition_template'} || '';
  my $transitionTemplate = &getTransitionPage($gatewayAccount, $requestedTransitionPage);

  if (!$skipTransitionTemplate && (defined $transitionTemplate && $transitionTemplate ne '')) {
    return customRedirect($url, $transitionTemplate, \%transitionFields);
  }

  my $transitionType = $allData->{'transitiontype'} || $features->get('transitiontype');
  if ( (defined $transitionType && $transitionType eq 'post') || $alwaysUsePost) {
    return postRedirect($url, \%transitionFields);
  }

  return defaultRedirect($url,\%transitionFields);
}

sub filterTransitionFields {
  my $input = shift;

  my %transitionFields = %{$input->{'transitionFields'}};
  my %allData = %{$input->{'allData'}};
  my $features = $input->{'features'};

    # filter sensitive fields out of the data before doing anything else
  my $filtered = filterRedirectFields(\%transitionFields);
  %transitionFields = %{$filtered};

  if ( defined $transitionFields{'auth-code'} ) {
    $transitionFields{'auth-code'} = substr( $transitionFields{'auth-code'}, 0, 6 );
  }
  if ( defined $transitionFields{'auth_code'} ) {
    $transitionFields{'auth_code'} = substr( $transitionFields{'auth_code'}, 0, 6 );
  }
  
  if ( ( defined $transitionFields{'client'} && $transitionFields{'client'} =~ /coldfusion/i ) ||
       ( defined $transitionFields{'CLIENT'} && $transitionFields{'CLIENT'} =~ /coldfusion/i ) ) {
    my @array = %transitionFields;
    %transitionFields = output_cold_fusion(@array);
  }

  # the sort here is important!
  # it is there so customname always comes before customvalue, so that when making
  # custom pairs, the value is not deleted before the pair is created.
  foreach my $key ( sort keys %transitionFields ) {
    if ( !defined $transitionFields{$key} || $transitionFields{$key} eq '') {
      delete $transitionFields{$key};
      next;
    }
    if ( ( $key =~ /^customname(\d+)$/ ) && ( defined($transitionFields{$key}) && $transitionFields{$key} ne "" ) && ( defined($transitionFields{"customvalue$1"}) && $transitionFields{"customvalue$1"} ne "" ) ) {
      $transitionFields{ $transitionFields{$key} } = $transitionFields{"customvalue$1"};
    }
    if ( defined $features->get('suppress_custom') && $features->get('suppress_custom') eq '1' ) {
      delete $transitionFields{$key};
      delete $transitionFields{"customvalue$1"};
    }
  }

  # rename "submit" key if present as it prevents javascript from submitting forms
  if (defined $transitionFields{'submit'}) {
    $transitionFields{'_submit'} = $transitionFields{'submit'};
    delete $transitionFields{'submit'};
  }

  # do this so we send back a masked card number in pt_card_number
  $transitionFields{'card-number'} = $transitionFields{'receiptcc'};

  # convert parameters to new payscreens if that's where they came from
  if ( isPayscreensVersion2(\%transitionFields) || forceLegacyFeatureIsSet($features) ) {
    delete $transitionFields{'customname99999999'};
    delete $transitionFields{'customvalue99999999'};

    my $api = new PlugNPay::API('payscreens');
    %transitionFields = %{ $api->convertLegacyParameters( \%transitionFields ) };
  }

  return \%transitionFields;
}

sub isPayscreensVersion2 {
  my $fields = shift;

  my $payscreensVersion2 = 
    defined $fields->{'customname99999999'} && 
    $fields->{'customname99999999'} eq 'payscreensVersion' &&
    defined $fields->{'customvalue99999999'} &&
    $fields->{'customvalue99999999'} eq '2';

  return $payscreensVersion2;
}

sub forceLegacyFeatureIsSet {
  my $features = shift;

  return defined $features->get('forceLegacy') && $features->get('forceLegacy') ne "";
}

sub generateRedirectHiddenFields {
  my $transitionFields = shift;

  my @hiddenFields = map { 
    my $key = $_ || '';
    my $value = $transitionFields->{$_};
    if (!defined($value)) {
      $value = '';
    }
    sprintf('<input type="hidden" name="%s" value="%s">', encode_entities($key), encode_entities($value)) 
  } keys %{$transitionFields};
  my $hidden = join('',@hiddenFields);
  return $hidden;
}

sub generateRedirectQueryString {
  my $transitionFields = shift;

  my $u = new URI('','http');
  $u->query_form($transitionFields);
  return $u->query;
}

sub filterRedirectFields {
  my $transitionFields = shift;

  my %filtered;

  my @sensitiveDataFields = (
    qr/^card.number/i,
    qr/^card.cvv/i,
    qr/merch.txn/i,
    qr/cust.txn/i,
    qr/month.exp/i,
    qr/year.exp/i,
    qr/magstripe/i,
    qr/mpgiftcard/i,
    qr/mpcvv/i,
    qr/magensacc/i
  );

  DATA: foreach my $key (keys %{$transitionFields} ) {
    foreach my $skey ( @sensitiveDataFields ) {
      next DATA if ($key =~ $skey);
    }
    $filtered{$key} = $transitionFields->{$key};
  }

  return \%filtered;
}

sub customRedirect {
  my $url = shift;
  my $template = shift;
  my $transitionFields = shift;

  if (!defined $url || $url eq '') {
    die('url is empty');
  }

  if (!defined $template || $template eq '') {
    die('template is empty');
  }

  my $hiddenFields = generateRedirectHiddenFields($transitionFields);
  my $queryString  = generateRedirectQueryString($transitionFields);

  my %replacementData = map { $_ =~ s/[^0-9a-zA-Z\-_]//g; "pnp_$_" => $transitionFields->{$_} } keys %{$transitionFields};

  $replacementData{'pnp_STRTURL'} = $url;
  $replacementData{'pnp_ENDURL'} = '</a>';
  $replacementData{'pnp_HIDDEN'} = $hiddenFields;
  $replacementData{'pnp_QUERYSTR'} = '?' . $queryString;

  foreach my $token (keys %replacementData) {
    $template =~ s/\[$token\]/$replacementData{$token}/g;
  }

  # replace all unknown with empty string
  $template =~ s/\[pnp_[a-zA-Z0-9]+\]//g;

  return $template;
}

sub postRedirect {
  my $url = shift;
  my $transitionFields = shift;

  if (!defined $url || $url eq '') {
    die('url is empty');
  }

  if (!defined $transitionFields || ref($transitionFields) ne 'HASH') {
    die('transitionFields is undefined or not a hashref');
  }

  my $hidden = generateRedirectHiddenFields($transitionFields);

  my $html = qq|
<html>
  <head>
    <!-- default post template -->
    <title>Redirect</title>
  </head>
  <body>
    <form name="redirect" action="$url" method="POST">
      $hidden
    </form>
    <script language="javascript">document.redirect.submit();</script>
  </body>
</html>
|;

  return $html;
}

sub defaultRedirect {
  my $url = shift;
  my $transitionFields = shift;

  my $queryString = generateRedirectQueryString($transitionFields);

  my $html = <<"EOF";
<html>
  <head>
    <!-- default redirect template -->
    <title>Secure/Unsecure Transition</title>
    <META http-equiv=\"refresh\" content=\"5\; URL=$url?$queryString\">
  </head>
  <body bgcolor=\"#ffffff\">
    <div align=center>
      <font size=+1>
      The Secure Portion of your transaction has completed Successfully.
      </font>
      <p>
        <font size=+1>If you experience a delay, please <a href=\"$url?$queryString\">CLICK HERE.</a></font>
      </p>
    </div>
  </body>
</html>
EOF

  return $html;
}

sub getTransitionPage {
  my $gatewayAccount = shift;
  my $requestedTransitionPage = shift || '';

  my @possibleTemplates;
  my $templateContent = '';

  my $ga = new PlugNPay::GatewayAccount($gatewayAccount);
  my $reseller = $ga->getReseller();

  my $accountFeatures = new PlugNPay::Features($gatewayAccount,'general');
  my $authcgiTransitionTemplate = $accountFeatures->get('authcgiTransitionTemplate');

  my $readFromFeature;
  if (defined $authcgiTransitionTemplate && $authcgiTransitionTemplate ne '' && (!defined $requestedTransitionPage || $requestedTransitionPage eq '')) {
    push @possibleTemplates, $authcgiTransitionTemplate;
    $readFromFeature = 1;
  }

  # requested template
  push @possibleTemplates, {
    fileName => sprintf('%s_%s.html', $gatewayAccount, $requestedTransitionPage)
  };

  # default transition page for merchant
  push @possibleTemplates, {
    fileName => sprintf('%s_deftran.html',$gatewayAccount)
  };

  # cobrand
  push @possibleTemplates, {
    subPrefix => 'cobrand/',
    fileName  => sprintf('%s.html', $accountFeatures->get('cobrand') || ''),
  };

  # reseller
  push @possibleTemplates, {
    subPrefix => 'reseller/',
    fileName  => sprintf('%s.html', $reseller)
  };

  my $wdf = new PlugNPay::WebDataFile();

  foreach my $templateInfo (@possibleTemplates) {
    next if !defined $templateInfo->{'fileName'} || $templateInfo->{'fileName'} eq '';

    my $subPrefix = sprintf('transition/%s',$templateInfo->{'subPrefix'} || '');
    eval {
      $templateContent = $wdf->readFile({
        fileName   => $templateInfo->{'fileName'},
        storageKey => 'merchantAdminTemplates',
        subPrefix  => $subPrefix
      });
    };

    next if $@; #skip if error loading

    if (defined $templateContent && $templateContent ne '') {
      if (!$readFromFeature && !$requestedTransitionPage) {
        # PlugNPay::Features auto detects objects and converts to an encoded form of JSON
        # storing raw json in features will actually break features parsing
        $accountFeatures->set('authcgiTransitionTemplate',$templateInfo);
        $accountFeatures->saveContext();
      }
      last;
    }
  }

  return $templateContent;
}

# I'm not even going to bother renaming this because it probably just can go away
# TODO add a metric to track if it's called.
sub output_cold_fusion {
  my (%query) = @_;
  $query{'aux-msg'} =~ s/\:/ /g;
  $query{'auth-msg'} =~ s/\:/ /g;
  %query = hyphen_to_underscore(%query);
  %query = lower_to_uppercase(%query);
  return (%query);
}

1;
