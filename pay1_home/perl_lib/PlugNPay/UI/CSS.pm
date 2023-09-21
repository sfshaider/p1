package PlugNPay::UI::CSS;

use strict;

use PlugNPay::DBConnection;
use PlugNPay::GatewayAccount::InternalID;
use Digest::SHA qw(sha256);
use PlugNPay::Util::Hash;
use PlugNPay::Util::Memcached;
use PlugNPay::Debug;

sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  my $memcached = new PlugNPay::Util::Memcached('UI::CSS');
  $self->{'memcached'} = $memcached;

  my $settingsHashRef = shift;

  if ($settingsHashRef) {
    my $id;
    if ($settingsHashRef->{'gatewayAccount'}) {
      $self->setGatewayAccount($settingsHashRef->{'gatewayAccount'});
      $self->setContext($settingsHashRef->{'context'});
      $id = new PlugNPay::GatewayAccount::InternalID()->getIdFromUsername($settingsHashRef->{'gatewayAccount'});
      $self->mapMerchantToCSSFile($id);
    }

    if (!$id || ($id && !$self->getCSSFile())) {
      $self->setContext($settingsHashRef->{'context'});
      $self->setSecurityLevel($settingsHashRef->{'securityLevel'});
      $self->setReseller($settingsHashRef->{'reseller'});
      $self->setCobrand($settingsHashRef->{'cobrand'});
      $self->setLogin($settingsHashRef->{'login'});
      $self->setTemplate($settingsHashRef->{'template'});
      $self->setSubmittedTemplate($settingsHashRef->{'submitted_template'});
      $self->load();
    }
  }
  return $self;
}

###########
# Setters #
###########

sub setContext {
  my $self = shift;
  my $context = shift;
  $context =~ s/[^A-Za-z0-9_\-]//g;
  $self->{'context'} = $context;
}

sub setSecurityLevel {
  my $self = shift;
  my $securityLevel = shift;
  $securityLevel =~ s/[^A-Za-z0-9_\-]//g;
  $self->{'securityLevel'} = $securityLevel;
}

sub setReseller {
  my $self = shift;
  my $reseller = lc shift;
  $reseller =~ s/[^A-Za-z0-9_\-]//g;
  $self->{'reseller'} = $reseller;
}

sub setCobrand {
  my $self = shift;
  my $cobrand = lc shift;
  $cobrand =~ s/[^A-Za-z0-9_\-]//g;
  $self->{'cobrand'} = $cobrand;
}

sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = lc shift;
  $gatewayAccount =~ s/[^A-Za-z0-9_\-]//g;
  $self->{'gatewayAccount'} = $gatewayAccount;
}

sub setLogin {
  my $self = shift;
  my $login = shift;
  $login =~ s/[^A-Za-z0-9_\-]//g;
  $self->{'login'} = $login;
}

sub setTemplate {
  my $self = shift;
  my $template = lc shift;
  $template =~ s/[^a-z0-9_-]//;
  $self->{'template'} = $template;
}

sub setSubmittedTemplate {
  my $self = shift;
  my $submitted_template = lc shift;
  $submitted_template =~ s/[^a-z0-9_]//;
  $self->{'submitted_template'} = $submitted_template;
}

sub setCSSFile {
  my $self = shift;
  my $file = shift;
  $self->{'css_file'} = $file;
}

##################
# End of setters #
##################

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

sub getCSSFile {
  my $self = shift;
  return $self->{'css_file'};
}

sub getUserContexts {
  my $self = shift;

  my $dbh = PlugNPay::DBConnection::database('pnpmisc');
  my $sth = $dbh->prepare(q/
    SELECT context
    FROM context
    WHERE user_css_modifiable = ?
  /);

  $sth->execute('1');

  return map { $_->{'context'}; } @{$sth->fetchall_arrayref({})};
}

sub saveTo {
  my $self = shift;
  my $type = shift;
  my $identifier = lc shift;
  my $context = shift;

  # Delete existing css when uploading new css
  my $dbh = PlugNPay::DBConnection::database('pnpmisc');
  my $sth = $dbh->prepare(q/
    DELETE FROM ui_css
    WHERE type = ? AND identifier = ? and context = ?
  /);

  $sth->execute($type,$identifier,$context);

  my @arrayOfInsertArrays;

  # just to make this code easier to understand
  my $enabled = 1;

  foreach my $mediaQuery (keys %{$self->{'css'}}) {
    foreach my $selector (keys %{$self->{'css'}{$mediaQuery}}) {
      foreach my $attribute (keys %{$self->{'css'}{$mediaQuery}{$selector}}) {
        foreach my $value (@{$self->{'css'}{$mediaQuery}{$selector}{$attribute}}) {
          my @insertArray = ($context,$type,$identifier,$mediaQuery,$selector,$attribute,$value,$enabled);
          push @arrayOfInsertArrays,\@insertArray;
        }
      }
    }
  }

  $sth = $dbh->prepare(q/
    INSERT INTO ui_css
      (context,type,identifier,media_query,selector,attribute,value,enabled,hash_key)
    VALUES
      (?,?,?,?,?,?,?,?,?)
  /);

  # insert, avoiding duplicates so we don't get primary key errors
  my %alreadyInserted;
  foreach my $arrayRef (@arrayOfInsertArrays) {
    my $hash = sha256(join('\|',@{$arrayRef}));

    if (defined $alreadyInserted{$hash}) {
      next;
    } else {
      $sth->execute(@{$arrayRef},$hash);
      $alreadyInserted{$hash} = 1;
    }
  }
}

sub cacheKey() {
  my $self = shift;

  # cache key comprised of reseller, gatewayAccount, login, cobrand, securityLevel, context, template, and submitted_template
  # these are the values that can impact the selected template
  my $cacheKeyData = sprintf('%s-%s-%s-%s-%s-%s-%s-%s',
    $self->{'reseller'},
    $self->{'gatewayAccount'},
    $self->{'login'},
    $self->{'cobrand'},
    $self->{'securityLevel'},
    $self->{'context'},
    $self->{'template'},
    $self->{'submitted_template'}
  );

  my $hasher = new PlugNPay::Util::Hash();
  $hasher->add($cacheKeyData);
  my $key = $hasher->sha256('0x');

  return $key;
}

sub load() {
  my $self = shift;

  my $cacheKey = $self->cacheKey() . '-data';

  my $cachedCSS = $self->{'memcached'}->get($cacheKey);

  if ($cachedCSS) {
    $self->{'css'} = $cachedCSS;
    debug { message => "css in cache" };
    return;
  } else {
    debug { message => "css not in cache, adding" };
  }


  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
  my $sth = $dbh->prepare(q{
    SELECT type,identifier,selector,attribute,value,media_query
    FROM ui_css
    WHERE (
         (type = 'default'  AND identifier = ?)
      OR (type = 'default'  AND identifier = ?)
      OR (type = 'reseller' AND identifier = ?)
      OR (type = 'reseller_template' AND identifier = ?)
      OR (type = 'cobrand'  AND identifier = ?)
      OR (type = 'cobrand_template'  AND identifier = ?)
      OR (type = 'account'  AND identifier = ?)
      OR (type = 'login'    AND identifier = ?)
      OR (type = 'template' AND identifier = ?)
      OR (type = 'account_template' AND identifier = ?)
      OR (type = 'securitylevel' AND identifier = ?))
    AND context = ?
    AND enabled = 1
  });
  $sth->execute('all',
                'default',
                $self->{'reseller'},
                $self->{'reseller'} . '-' . $self->{'submitted_template'},
                $self->{'cobrand'},
                $self->{'cobrand'} . '-' . $self->{'submitted_template'},
                $self->{'gatewayAccount'},
                $self->{'login'},
                $self->{'reseller'} . '-' . $self->{'template'},
		$self->{'gatewayAccount'} . '-' . $self->{'submitted_template'},
                $self->{'securitylevel'},
                $self->{'context'}
               );

  my %cssData;

  my $rows = $sth->fetchall_arrayref({});
  $sth->finish;

  # apply the css for "all" first so it can be overridden if need be
  foreach my $row (@{$rows}) {
    if ($row->{'type'} eq 'default' && $row->{'identifier'} eq 'all') {
      if (ref($cssData{$row->{'media_query'}}{$row->{'selector'}}{$row->{'attribute'}}) ne 'ARRAY') {
        $cssData{$row->{'media_query'}}{$row->{'selector'}}{$row->{'attribute'}} = [];
      }
      push(@{$cssData{$row->{'media_query'}}{$row->{'selector'}}{$row->{'attribute'}}},$row->{'value'});
    }
  }

  # then find the most specific css to apply
  foreach my $type ('security_level','account_template','login','account','cobrand_template','cobrand','reseller_template','template','reseller','default') {
    my $hasCSS = 0;

    foreach my $row (@{$rows}) {
      # skip inserting the attributes for default:all since we already did that above.
      if ($type eq 'default' && $row->{'identifier'} eq 'all') { 
        next; 
      }
      if ($row->{'type'} eq $type) {
        $hasCSS++;

        if (ref($cssData{$row->{'media_query'}}{$row->{'selector'}}{$row->{'attribute'}}) ne 'ARRAY') {
          $cssData{$row->{'media_query'}}{$row->{'selector'}}{$row->{'attribute'}} = [];
        }
        push(@{$cssData{$row->{'media_query'}}{$row->{'selector'}}{$row->{'attribute'}}},$row->{'value'});
      }
    }

    if ($hasCSS) {
      last;
    }
  }

  $self->{'memcached'}->set($cacheKey, \%cssData, 900);

  $self->{'css'} = \%cssData;
}

sub cssMarkup {
  my $self = shift;
  my $readable = shift;

  my $cacheKey = $self->cacheKey() . '-markup';

  my $cachedCSS = $self->{'memcached'}->get($cacheKey);

  if ($cachedCSS ne '') {
    debug { message => 'using cached css markup' };
    return $cachedCSS;
  }

  my $newline = '';

  if ($readable) {
    $newline = "\n";
  }

  my $cssString;

  foreach my $mediaQuery (sort keys %{$self->{'css'}}) {
    my $indent = '';
    my $indentAmount = 0;

    if ($readable) {
      $indent = '  ';
    }

    if ($mediaQuery ne '') {
      $cssString .= '@media ' . $mediaQuery . '{ ' . $newline;
      if ($readable) {
        $indentAmount += 1;
      }
    } 

    foreach my $selector (sort keys %{$self->{'css'}{$mediaQuery}}) {
      $cssString .= ($indent x $indentAmount) . $selector . '{' . $newline;
      foreach my $attribute (sort keys %{$self->{'css'}{$mediaQuery}{$selector}}) {
        foreach my $attributeValue (@{$self->{'css'}{$mediaQuery}{$selector}{$attribute}}) {
          $cssString .= ($indent x ($indentAmount + 1)) . $attribute . ':' . $attributeValue . ';' . $newline;
        }
      }
      $cssString .= ($indent x $indentAmount) . '}' . $newline;
    }

    if ($mediaQuery ne '') {
      $cssString .=  '}' . $newline;
    }
  }

  $self->{'memcached'}->set($cacheKey, $cssString, 900);

  return $cssString;
}

sub cssScanner {
  my $self = shift;
  my $css = shift;
  my $useExisting = shift;

  $css = $self->cssSpaceMinimizer($css);

  my $buffer = '';
  my $length = length($css);

  my $currentMediaQuery = '';
  my $currentSelector = '';
  my $currentAttributes = '';

  my %cssData;
  if ($useExisting) {
    %cssData = %{$self->{'css'}};
  }

  my %result;
  $result{'error'} = 0;
  
  for (my $i = 0; $i < $length; $i++) {
    my $currentChar = substr($css,$i,1);
    if ($buffer eq '' && $currentChar eq ' ') {
      # do nothing, ignore leading spaces
    } else {
      if ($buffer ne '' && $buffer =~ /^\@media/ && $currentChar eq '{') {
        # found a media query, save it so we know what media query we are working on
        $buffer =~ s/\@media\s+//;
        $buffer =~ s/\s+$//;
        $currentMediaQuery = $buffer;
        $buffer = '';
      } elsif ($currentChar eq '{') {
        # found a selector, save it so we know what selector we are working on
        $buffer =~ s/\s+$//;
        $currentSelector = $buffer;
        if (length($currentSelector) > 255) {
          $result{'error'} = 1;
          $result{'message'} = 'Selector greater than 255 characters found, CSS may not work as expected.';
        }
        $buffer = '';
      } elsif ($currentChar eq '}' && $currentSelector ne '') {
        # found end of selector, the buffer now contains the attributes and values for that selector.
        # parse the buffer and put the data into the hash
        my %attributes;
        foreach my $attributeValuePair (split(';',$buffer)) {
          my @parts = split(':',$attributeValuePair);
          my $attribute = shift @parts;
          my $value = join(':',@parts);
          if (ref($cssData{$currentMediaQuery}{$currentSelector}{$attribute}) ne 'ARRAY') {
            $cssData{$currentMediaQuery}{$currentSelector}{$attribute} = [];
          }
          push(@{$cssData{$currentMediaQuery}{$currentSelector}{$attribute}},$value);
        }
        $currentSelector = '';
        $buffer = '';
      } elsif ($currentChar eq '}' && $currentMediaQuery ne '') {
        # found end of media query... clear the media query name and the buffer.
        $currentMediaQuery = '';
        $buffer = '';
      } else {
        # in all other cases, add the current character to the buffer
        $buffer .= $currentChar;
      }
    }
  }

  $self->{'css'} = \%cssData;

  return \%result;
}

# THIS ONLY REDUCES WHITESPACE.
# It does not do cool stuff like turn "bold" into "400" to save one byte,
# or compress #FFFFFF into #FFF to save 3 bytes.  Granted, in a big CSS 
# file that kind of thing adds up, but the real purpose of this method 
# is to normalize the format of the css so the cssScanner() method can 
# parse it. 
sub cssSpaceMinimizer {
  my $self = shift;
  my $css = shift;


  # remove newlines 
  $css =~ s/\n//g;

  # remove comments
  # all css comments start with /* and end with */, there are no comments that start with //
  $css =~ s/\/\*.*?\*\///g;

  # replace all instances of multiple spaces with a single space
  $css =~ s/\s+/ /g;

  # remove all spaces after commas, colons, semicolons and brackets
  $css =~ s/([\{\}\,\(\):;])\s/$1/g;

  return $css;
}

sub saveCustom {
  my $self = shift;
  my $identifier = lc shift;
  my $parameters = shift;

  # Delete existing css when uploading new css
  my $dbh = PlugNPay::DBConnection::database('pnpmisc');
  my $sth = $dbh->prepare(q/
    DELETE FROM ui_payscreens_custom_css 
    WHERE identifier = ? 
  /);
  $sth->execute($identifier);

  $sth = $dbh->prepare(q/
    INSERT INTO ui_payscreens_custom_css
      (identifier,parameter_name,value)
    VALUES
      (?,?,?)
  /);

  foreach my $keys (keys %{$parameters}) {
    my $values = $parameters->{$keys};
    $sth->execute($identifier,$keys,$values);
  }

}

sub loadCustom {
  my $self = shift;
  my $identifier = lc shift;

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
  my $sth = $dbh->prepare(q{
    SELECT identifier,parameter_name,value
    FROM ui_payscreens_custom_css 
    WHERE identifier = ? 
  });
  $sth->execute($identifier);

  my %cssData;

  my $rows = $sth->fetchall_arrayref({});
  $sth->finish;

  foreach my $row (@{$rows}) {
    push(@{$cssData{$row->{'parameter_name'}}},$row->{'value'});
  }

  return \%cssData;
}

sub deleteCSS {
  my $self = shift;
  my $type = shift;
  my $identifier = lc shift;
  my $context = shift;

  # Delete existing css when uploading new css
  my $dbh = PlugNPay::DBConnection::database('pnpmisc');
  my $sth = $dbh->prepare(q/
    DELETE FROM ui_css
    WHERE type = ? AND identifier = ? and context = ?
  /);

  $sth->execute($type,$identifier,$context);
}

sub deleteAndReload {
  my $self = shift;
  my $type = shift;
  my $identifier = lc shift;
  my $context = shift;

  $self->deleteCSS($type,$identifier,$context);
  $self->{'css'} = "";
  $self->load($type,$identifier,$context);
}

sub mapMerchantToCSSFile {
  my $self = shift;
  my $id = shift || $self->getGatewayAccount();

  if ($id !~ /^\d+$/) {
    $id = new PlugNPay::GatewayAccount::InternalID()->getIdFromUsername($id);
  }

  my $cacheKey = "css-file-id-for-merchant-$id";
  my $cachedFileIds = $self->{'memcached'}->get($cacheKey);
  if ($cachedFileIds ne '') {
    $self->loadCSSFile($cachedFileIds);
    return;
  }

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc', q/
                                     SELECT css_file_id
                                     FROM ui_merchant_to_css_file_map
                                     WHERE merchant_id = ?/);
  $sth->execute($id) or die $DBI::errstr;
  my $results = $sth->fetchall_arrayref({});

  my $fileIDs = [];
  foreach my $row (@{$results}) {
    push (@{$fileIDs}, $row->{'css_file_id'});
  }


  $self->{'memcached'}->set($cacheKey,$fileIDs,300);
  

  if (@{$fileIDs}) {
    $self->loadCSSFile($fileIDs);
  }
}

sub loadCSSFile {
  my $self = shift;
  my $ids = shift;  # array ref

  if (@{$ids} == 0) {
    return;
  }
  
  my $context = $self->{'context'};
  my $placeholders = '(' . join(',', map{'?'} @{$ids}) . ')';

  my $query = q/SELECT css_file
                FROM ui_css_file
                WHERE context = ? 
                AND id IN / . $placeholders;
  
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc', $query);
  $sth->execute($context, @{$ids}) or die $DBI::errstr;
 
  my $results = $sth->fetchrow_hashref();
  $self->setCSSFile($results->{'css_file'});
}

sub saveMerchantToCSSFile {
  my $self = shift;
  my $cssFileID = shift;
  my $identifier = shift || $self->getGatewayAccount();

  my $id = new PlugNPay::GatewayAccount::InternalID()->getIdFromUsername($identifier);
 
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc', q/
                                  INSERT INTO ui_merchant_to_css_file_map (merchant_id, css_file_id)
                                  VALUES (?,?) ON DUPLICATE KEY UPDATE css_file_id = ?/);
  $sth->execute($id, $cssFileID, $cssFileID) or die $DBI::errstr;
}

sub deleteMerchantToCSSFile {
  my $self = shift;
  my $cssFileID = shift;
  my $identifier = shift || $self->getGatewayAccount();
 
  my $id = new PlugNPay::GatewayAccount::InternalID()->getIdFromUsername($identifier);

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc', q/
                                     DELETE FROM ui_merchant_to_css_file_map
                                     WHERE merchant_id = ? AND css_file_id = ?/);
  $sth->execute($id, $cssFileID) or die $DBI::errstr;
}

sub saveCSSFile {
  my $self = shift;
  my $cssFile = shift;
  my $context = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc', q/
                                  INSERT INTO ui_css_file (css_file, context)
                                  VALUES (?,?)/);
  $sth->execute($cssFile, $context) or die $DBI::errstr;
}

sub deleteCSSFile {
  my $self = shift;
  my $cssFileID = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc', q/
                                     DELETE FROM ui_css_file
                                     WHERE id = ?/);
  $sth->execute($cssFileID) or die $DBI::errstr;
}

1;
