package PlugNPay::VirtualTerminal;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Environment;
use PlugNPay::Util::UniqueID;
use PlugNPay::Sys::Time;


our %_cache;

sub new
{
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self, $class;

  my $user = lc shift || new PlugNPay::Environment()->get('PNP_USER');
  my $session = shift;

  my $uid = new PlugNPay::Util::UniqueID();

  if ($user) {
    $self->setUser($user);
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
  $self->setUser($gatewayAccount);
}

sub setUser {
  my $self = shift;
  my $user = shift;

  $self->{'user'} = $user;
  my $env = new PlugNPay::Environment($user);
  $self->{'env'} = $env;
  $self->loadVirtualTerminalData();
}

sub getUser {
  my $self = shift;
  return $self->{'user'};
}

sub displayOptionsQueryString {
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

sub loadDisplaySettings {
  my $self = shift;

  my %settings;

  foreach my $type ('default','reseller','cobrand','account') {
    foreach my $row (@{$self->{'fieldData'}}) {
      if ($row->{'type'} eq $type) {
        $settings{'display'}{$row->{'transaction_type'}}{$row->{'element'}}{'enabled'} = $row->{'enabled'};
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


sub fieldData {
  my $self = shift;
  return $self->{'fieldData'};
}

sub tabData {
  my $self = shift;
  return $self->{'tabData'};
}

sub loadSettings {
  my $self = shift;
  my $user = $self->getUser();
  my %settings;
  my $dbh = PlugNPay::DBConnection::database('pnpmisc');
  my $sth = $dbh->prepare(q/
                            SELECT * FROM ui_admin_virtual_terminal_settings
                            WHERE login = ?
                          /);

  $sth->execute($user);
  my $results = $sth->fetchrow_hashref;
  delete $results->{'account'};

  return $results;
}

sub saveSettings {
  my $self = shift;
  my $inputParametersRef = shift;


  my $user = $self->getUser();

  my @settingsFields = @{$_cache{'virtualTerminalSettingsFields'}};

  # convert yes to 1 and blank to 0
  foreach my $field (@settingsFields) {
    if ($inputParametersRef->{$field} eq 'yes') {
      $inputParametersRef->{$field} = 1;
    } elsif (!defined $inputParametersRef->{$field} || $inputParametersRef->{$field} eq '') {
      $inputParametersRef->{$field} = 0;
    } else {
      $inputParametersRef->{$field} =~ s/[^a-z0-9_]//g;
    }
  }

  # insert or update?
  my $dbh = PlugNPay::DBConnection::database('pnpmisc');
  my $sth = $dbh->prepare(q/
                            SELECT count(login) AS `exists`
                            FROM ui_admin_virtual_terminal_settings
                            WHERE login = ?
                          /);
  $sth->execute($user);

  my $row = $sth->fetchrow_hashref;

  my $query = '';
  my @parameters;
  foreach my $parameter (@settingsFields) {
    push @parameters,$inputParametersRef->{$parameter};
  }
  push @parameters,$user;

  if ($row->{'exists'}) { # do an update
    $query = 'UPDATE ui_admin_virtual_terminal_settings' . "\n";;
    $query .= 'SET ' . join(",\n",map { $_ . ' = ?' } @settingsFields) . "\n";
    $query .= 'WHERE login = ?';
  } else { # do an insert
    $query = 'INSERT INTO ui_admin_virtual_terminal_settings' . "\n";
    $query .= '(' . join(',',(@settingsFields,'login')) . ') ' . "\n";
    $query .= 'VALUES(' . '?,' x @settingsFields . '?)';
  }

  $sth = $dbh->prepare($query);
  $sth->execute(@parameters); 
}


sub loadVirtualTerminalData {
  my $self = shift;

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
      FROM ui_admin_virtualterminal_display_options
    });
    $sth->execute();
  
    my $results = $sth->fetchall_arrayref({});
    $sth->finish;
  
    foreach my $rowRef (@{$results}) {
      $_cache{'apiMappings'}{$rowRef->{'api_mapping'}}{'element'} = $rowRef->{'element'};
    }
  }

  #############################################################
  # Load the names of fields that represent savable settings. #
  ###################################################################
  ## This is not merchant specific so we can cache it in the module #
  ###################################################################
  if (!exists $_cache{'savableSettings'}) {
    $sth = $dbh->prepare(q{
       SELECT column_name FROM information_schema.columns
       WHERE table_name=? AND column_name <> ?
    });
    
    $sth->execute('ui_admin_virtual_terminal_settings','login');
    my @fieldNames = map { $_->{'column_name'} } @{$sth->fetchall_arrayref({})};
    $_cache{'virtualTerminalSettingsFields'} = \@fieldNames;
  }

  ######################
  # Load text mappings #
  ###################################################################
  ## This is not merchant specific so we can cache it in the module #
  ###################################################################

  if (!exists $_cache{'virtualterminalTextMappings'}) {
    $sth = $dbh->prepare(q{
      SELECT selector,mode,meta_identifier,meta_category
      FROM ui_admin_virtualterminal_text
    });

    $sth->execute();
    $_cache{'virtualterminalTextMappings'} = $sth->fetchall_arrayref({});
  }

  #########################################
  # Load merchant specific field settings #
  #########################################
  $sth = $dbh->prepare(q{
    SELECT  identifier,type,element,transaction_type,
       CAST(enabled AS UNSIGNED INTEGER) as enabled,
       CAST(required AS UNSIGNED INTEGER) as required 
    FROM ui_admin_virtualterminal_elements
    WHERE (type = 'default'  AND identifier = ?)
       OR (type = 'reseller' AND identifier = ?)
       OR (type = 'cobrand'  AND identifier = ?)
       OR (type = 'account'  AND identifier = ?)
  });
  
  $sth->execute('default',
                $self->{'env'}->get('PNP_RESELLER'),
                $self->{'env'}->get('PNP_COBRAND'),
                $self->{'env'}->get('PNP_ACCOUNT')
               );
  $self->{'fieldData'} = $sth->fetchall_arrayref({});

  ####################################
  # Load merchant specific tab order #
  ####################################
  $sth = $dbh->prepare(q{
    SELECT identifier, type, element, ordinal
    FROM ui_admin_virtualterminal_tab_order
    WHERE (type = 'default'  AND identifier = ?)
       OR (type = 'reseller' AND identifier = ?)
       OR (type = 'cobrand'  AND identifier = ?)
       OR (type = 'account'  AND identifier = ?)
  });
  $sth->execute('default',
                $self->{'env'}->get('PNP_RESELLER'),
                $self->{'env'}->get('PNP_COBRAND'),
                $self->{'env'}->get('PNP_ACCOUNT')
               );
  $self->{'tabData'} = $sth->fetchall_arrayref({});
}

1;
