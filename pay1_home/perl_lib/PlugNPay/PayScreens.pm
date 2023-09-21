package PlugNPay::PayScreens;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Environment;
use PlugNPay::Util::UniqueID;
use PlugNPay::Sys::Time;
use PlugNPay::PayScreens::Items;
use PlugNPay::UI::Template;


our %_cache;

sub new
{
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self, $class;

  my $gatewayAccount = lc shift;
  my $session = shift;

  my $uid = new PlugNPay::Util::UniqueID();

  if ($gatewayAccount) {
    $self->setGatewayAccount($gatewayAccount);
    if (!$session || !$uid->validateUniqueID($session)) {
      $session = $uid->inHex();
    }
    $self->setSession($session);
  }

  return $self;
}  

sub getSession {
  my $self = shift;
  return $self->{'session'};
}

sub setSession {
  my $self = shift;
  my $session = shift;
  $session =~ s/[^A-Za-z0-9]//g;
  $self->{'session'} = $session;
}

sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;

  $self->{'gatewayAccount'} = $gatewayAccount;
  $self->loadPayscreensData();
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

sub jsonQueryString {
  my $self = shift;
  my $passedParametersRef = shift;

  my %options;

  foreach my $parameter (keys %{$passedParametersRef}) {
    if (exists $_cache{'apiMappings'}{$parameter}) {
      my $element = $_cache{'apiMappings'}{$parameter}{'element'};
      my $setting = $passedParametersRef->{$parameter};
      if ($setting =~ /^(yes|no)$/) {
        $setting = ($setting eq 'yes' ? 1 : 0);
      }
      $options{$element} = $setting;
    }
  }

  my $string = join('&', map { $_ .= '=' . $options{$_} } keys %options);
  return $string;
}

# this function is in development, do not call it yet
sub displaySettings {
  my $self = shift;

  my %settings;

  foreach my $type ('default','reseller','cobrand','account') {
    foreach my $row (@{$self->{'fieldData'}}) {
      if ($row->{'type'} eq $type) {
        $settings{'enabled'}{$row->{'transaction_type'}}{$row->{'element'}} = $row->{'enabled'};
        $settings{'visible'}{$row->{'transaction_type'}}{$row->{'element'}} = $row->{'visible'};
      }
    }
    foreach my $row (@{$self->{'tabData'}}) {
      if ($row->{'type'} eq $type) {
        $settings{'tabOrder'}{$row->{'element'}} = $row->{'order'};
      }
    }
  }

  return \%settings;
}

sub metaIdentifiers {
  return $_cache{'payscreensTextMappings'};
}  

sub fieldData {
  my $self = shift;
  return $self->{'fieldData'};
}

sub tabData {
  my $self = shift;
  return $self->{'tabData'};
}

sub getSetting {
  my $self = shift;
  my $setting = shift;
  return $self->{'generalSettings'}{$setting};
}

sub setSetting {
  my $self = shift;
  my $setting = shift;
  my $value = shift;
  $self->{'generalSettings'}{$setting} = $value;
}

sub generateItemHTML {
  my $self = shift;

  my $items = new PlugNPay::PayScreens::Items();
  
  return $items->generateItemHTML(@_);
}

sub generateFormPopulationJavascript {
  my $self = shift;
  my $hashRef = shift;

  my $javascript = '';

  foreach my $field (keys %{$hashRef}) {
    # skip generating javascript for the card number.
    if (($field eq "pt_card_number") || ($field eq "pt_ach_account_number")) { next; }
    my $value = $hashRef->{$field};
    # escape double quotes
    $field =~ s/[^a-z0-9_]//g;
    $value =~ s/"/\\"/g;
    my @valueArray = $value =~ /(.{1,4})/g;
    $value = '["' . join('","',@valueArray) . '"]';
    if ($value ne "") {
      $javascript .= qq/\tPayScreens.setInputValueFromArray("$field",$value);\n/;
    }
  }
  return $javascript;
}

sub generatePassedFieldJavaScriptObject {
  my $self = shift;
  my $hashRef = shift;

  my $javascript = '';

  foreach my $field (keys %{$hashRef}) {
    # skip generating javascript for the card number.
    if (($field eq "pt_card_number") || ($field eq "pt_ach_account_number")) { next; }
    my $value = $hashRef->{$field};
    # escape double quotes
    $field =~ s/[^a-z0-9_]//g;
    $value =~ s/"/\\"/g;
    if ($value ne "") {
      $javascript .= qq/"$field": "$value",/;
    }
  }
  return $javascript;
}

#returns a string of key=value from a passed parameter set, using ":" as delimiter.
sub getKeyValuePairs{
  my $self = shift;
  my $hashRef = shift;

  my $keyValue = "";
  
  while (my($key, $value) = each (%{$hashRef})) {
    
    unless ($key eq "pd_transaction_payment_type" ) {
      $keyValue .= "&" . $key . "=" . $value;
    }
  }
  
  return $keyValue;
}


sub formInitialzation {
  my $self = shift;
  my $template = lc shift;
  my $submitted_template = lc shift;
  $template =~ s/[^a-z0-9_-]//g;
  $submitted_template =~ s/[^a-z0-9_]//g;

  my $ga = new PlugNPay::GatewayAccount($self->getGatewayAccount());

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
  my $sth = $dbh->prepare(q{
    SELECT type,identifier,context,content,version
    FROM ui_payscreens_form_initialization
    WHERE ((type = 'default'  AND identifier = ?)
      OR (type = 'reseller' AND identifier = ?)
      OR (type = 'reseller_template' AND identifier = ?)
      OR (type = 'cobrand'  AND identifier = ?)
      OR (type = 'cobrand_template'  AND identifier = ?)
      OR (type = 'account' AND identifier = ?)
      OR (type = 'template' AND identifier = ?)
      OR (type = 'account_template' AND identifier = ?)
      OR (type = 'component'))
    AND context = ?
  });
  $sth->execute('default',
             $ga->getReseller(),
             $ga->getReseller() . '-' . $submitted_template,
             $ga->getCobrand(),
             $ga->getCobrand() . '-' . $submitted_template, 
             $ga->getGatewayAccountName(),
             $ga->getReseller() . '-' . $template,
             $ga->getGatewayAccountName() . '-' . $submitted_template,
             'payscreens'
             );

  my $formInitializationRules;

  my $rows = $sth->fetchall_arrayref({});

  my %templates;
  my %components;

  # create hash of templates and hash of components;
  foreach my $row (@{$rows}) {
    if ($row->{'type'} ne 'component') {
      $templates{$row->{'type'}} = $row->{'content'};
    } else {
      $components{$row->{'identifier'}} = $row->{'content'};
    }
  }

  my $hasResults = 0;
  my $loadedType;
  my $formInitializationVersion = 2;

  my @types = ('account_template','login','account','cobrand_template','cobrand','reseller_template','template','reseller','default');
  foreach my $type (@types)  {
    foreach my $row (@{$rows}) {
      if (($row->{'type'} eq $type) && ($row->{'content'} ne '')) {
        $formInitializationRules = $row->{'content'};
        $loadedType = $type;
        $formInitializationVersion = $row->{'version'};
        last;
      }
    }
    if (defined $formInitializationRules) {
        last;
    }
  }

  my $formInitializationParser = new PlugNPay::UI::Template();

  foreach my $type (keys %templates) {
    if ($type ne $loadedType) { # prevent infinite loops
      $formInitializationParser->setVariable('inherit-' . $type, $templates{$type});
    }
  }

  # do not look at this subroutine.  do not move this subroutine.
  # do not touch this subroutine.
  # if you need someone to explain why, ask chris.
  sub recurse {
    my $componentText = shift;
    my $toTheLimit = shift;

    my $template = new PlugNPay::UI::Template();

    foreach my $fhqwhgads (keys %components) {
      $template->setVariable('component-' . $fhqwhgads,$components{$fhqwhgads});
    }

    my $text = $template->parseTemplate($componentText);

    if ($toTheLimit && $text =~ /<meta.*var(iable|=)/) {
      $text = recurse($text,$toTheLimit - 1);
    }

    return $text;
  }

  foreach my $component (keys %components) {
    $formInitializationParser->setVariable('component-' . $component,recurse($components{$component},10));
  }

  $formInitializationRules = $formInitializationParser->parseTemplate($formInitializationRules);

  if (wantarray) {
    return ($formInitializationRules,$formInitializationVersion);
  }

  return $formInitializationRules;
}

sub storeCustomFields {
  my $self = shift;
  my $customFieldsHashRef = shift;
 
  my $time = new PlugNPay::Sys::Time()->inFormat('gendatetime');

  if (keys %{$customFieldsHashRef} > 1000) {
    return 0;
  }

  # create the placeholders for the insert statement
  my $placeholders = join(',',map { '(?,?,?,?)' } grep {/^pt_custom_(name|value)_\d+$/} keys %{$customFieldsHashRef}) || '';

  # create the value array for the execute call
  my @valueArray;
  foreach my $key (grep {/^pt_custom_(name|value)_\d+$/} keys %{$customFieldsHashRef}) {
    my @tempArray;
    push @tempArray, $self->{'session'};
    push @tempArray, $time;
    push @tempArray, $key;
    push @tempArray, $customFieldsHashRef->{$key};

    # push the temp array onto the value array
    push @valueArray,@tempArray;
  }


  # only do the query if custom fields were sent
  if ($placeholders ne '') {
    my $query = 'INSERT INTO paypairs (rowref,trans_time,name,value) VALUES ' . $placeholders;
    my $dbh = PlugNPay::DBConnection::database('pnpmisc');
    my $sth = $dbh->prepare($query);
    $sth->execute(@valueArray);
    $sth->finish;
  }

  return 1;
}

sub retrieveCustomFields {
  my $self = shift;

  my $customValueHashRef;

  my $dbh = PlugNPay::DBConnection::database('pnpmisc');
  my $sth = $dbh->prepare(q{
    SELECT name, value
    FROM paypairs
    WHERE rowref = ?
  });
  $sth->execute($self->getSession());
  
  my $resultsRef = $sth->fetchall_arrayref({});

  foreach my $row (@{$resultsRef}) {
    $customValueHashRef->{$row->{'name'}} = $row->{'value'};
  }

  $sth->finish;

  $sth = $dbh->prepare(q{
    DELETE FROM paypairs
    WHERE rowref = ?
  });
  $sth->execute($self->getSession());
  $sth->finish;

  return $customValueHashRef;
}

sub loadPayscreensData {
  my $self = shift;

  my $account = $self->getGatewayAccount();

  my $ga = new PlugNPay::GatewayAccount($account);
  
  my $reseller = $ga->getReseller();
  my $cobrand  = $ga->getCobrand();

  my $dbh = PlugNPay::DBConnection::database('pnpmisc');
  my $sth;

  ###########################################
  # Load parameter to json control mappings #
  ###################################################################
  ## This is not merchant specific so we can cache it in the module #
  ###################################################################
  if (!exists $_cache{'apiMappings'}) {
    $sth = $dbh->prepare(q{
      SELECT element, api_mapping
      FROM ui_payscreens_display_options
    });
    $sth->execute();
  
    my $results = $sth->fetchall_arrayref({});
    $sth->finish;
  
    foreach my $rowRef (@{$results}) {
      $_cache{'apiMappings'}{$rowRef->{'api_mapping'}}{'element'} = $rowRef->{'element'};
    }
  }

  ######################
  # Load text mappings #
  ###################################################################
  ## This is not merchant specific so we can cache it in the module #
  ###################################################################

  if (!exists $_cache{'payscreensTextMappings'}) {
    $sth = $dbh->prepare(q{
      SELECT selector,mode,meta_identifier,meta_category,function,argument
      FROM ui_payscreens_text
    });

    $sth->execute();
    $_cache{'payscreensTextMappings'} = $sth->fetchall_arrayref({});
    $sth->finish;
  }

  #########################################
  # Load merchant specific field settings #
  #########################################
  $sth = $dbh->prepare(q{
    SELECT  identifier,type,element,transaction_type,
       CAST(enabled AS UNSIGNED INTEGER) as enabled,
       CAST(visible AS UNSIGNED INTEGER) as visible,
       CAST(required AS UNSIGNED INTEGER) as required 
    FROM ui_payscreens_elements
    WHERE (type = 'default'  AND identifier = ?)
       OR (type = 'reseller' AND identifier = ?)
       OR (type = 'cobrand'  AND identifier = ?)
       OR (type = 'account'  AND identifier = ?)
  });
  
  $sth->execute('default',
                $reseller,
                $cobrand,
                $account
               );
  $self->{'fieldData'} = $sth->fetchall_arrayref({});
  $sth->finish;

  ####################################
  # Load merchant specific tab order #
  ####################################
  $sth = $dbh->prepare(q{
    SELECT identifier, type, element, ordinal
    FROM ui_payscreens_tab_order
    WHERE (type = 'default'  AND identifier = ?)
       OR (type = 'reseller' AND identifier = ?)
       OR (type = 'cobrand'  AND identifier = ?)
       OR (type = 'account'  AND identifier = ?)
  });
  $sth->execute('default',
                $reseller,
                $cobrand,
                $account
               );
  $self->{'tabData'} = $sth->fetchall_arrayref({});
  $sth->finish;

  ###################################
  # Load merchant specific settings #
  ###################################
  $sth = $dbh->prepare(q{
    SELECT setting_name, setting_value
    FROM ui_payscreens_general_settings
    WHERE (type = 'default'  AND identifier = ?)
       OR (type = 'reseller' AND identifier = ?)
       OR (type = 'cobrand'  AND identifier = ?)
       OR (type = 'account'  AND identifier = ?)
  });
  $sth->execute('default',
                $reseller,
                $cobrand,
                $account
               );
  my $settingsArray = $sth->fetchall_arrayref({});
  foreach my $setting (@{$settingsArray}) {
    $self->{'generalSettings'}{$setting->{'setting_name'}} = $setting->{'setting_value'};
  }
  $sth->finish;
}

1;
