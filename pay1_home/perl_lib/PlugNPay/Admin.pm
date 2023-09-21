package PlugNPay::Admin;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::UI::Template;
use PlugNPay::Environment;
use PlugNPay::Security::CSRFToken;
use PlugNPay::GatewayAccount;
use PlugNPay::GatewayAccount::Services;

our $pathData;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!defined $pathData) {
    $self->loadPaths();
  }

  return $self;
}

sub loadPaths {
  my $self = shift;


  my $dbh = PlugNPay::DBConnection::database('pnpmisc');

  my $sth = $dbh->prepare(q/
    SELECT path,name
      FROM ui_admin_paths
  /);

  $sth->execute();

  my $results = $sth->fetchall_arrayref({});

  foreach my $result (@{$results}) {
    $pathData->{$result->{'path'}}{'name'} = $result->{'name'};
  }
}

sub getPathBarHTML {
  my $self = shift;
  my $path = shift;

  # Chop off index.cgi if and only if script's name is index.cgi, preserving the trailing slash.
  $path =~ s/\/index\.cgi$/\//;

  # remove duplicate slashes
  $path =~ s/\/\//\//g;

  # Find superpaths
  my @paths;

  push @paths,$path if $path !~ /\/$/;

  # if the path does not end in a slash, chop it down to the directory before entering the loop.
  # if we don't do this, we will get the same path twice.
  # otherwise we can just enter the loop as is
  if ($path !~ /\/$/) {
    $path =~ s/[^\/]+$//;
  }

  

  while ($path ne '/' && $path ne '') {
    unshift @paths,$path;
    $path =~ s/[^\/]+\/$//;
  }

  my $pathHTML;

  my $locationTemplate = new PlugNPay::UI::Template();

  my $pathMarkerTemplate = new PlugNPay::UI::Template();
  $pathMarkerTemplate->loadTemplate('/admin/pathBar','pathMarker');

  my $html;

  while (my $path = shift @paths) {
    $locationTemplate->setVariable('url',$path);
    $locationTemplate->setVariable('name',$pathData->{$path}{'name'});

    $html .= $locationTemplate->loadTemplate('admin/pathBar','location');

    if (@paths) {
      $html .= $pathMarkerTemplate->loadTemplate('/admin/pathBar','pathMarker');
    }
  }

  return $html;
}

sub buildMenuHTML {
  my $self = shift;

  my $template = new PlugNPay::UI::Template();
  $template->setCategory('/admin/');
  $template->setName('index_menu_item');

  my $menuSettings = $self->getMenuSettings();

  my $menuHTML = '';

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT text, url, font_awesome_icon_name, css_id, windowed, legacy_switch_name, legacy_url
      FROM merchant_admin_menu_item
     WHERE enabled = ?
     ORDER BY `order`
  /);

  $sth->execute(1);

  my $results = $sth->fetchall_arrayref({});

  if ($results) {
    foreach my $menuItem (@{$results}) {
      # 
      my $url = ($menuSettings->{$menuItem->{'legacy_switch_name'}} ? $menuItem->{'url'} : $menuItem->{'legacy_url'});
      if (!$url) {
        next; # skip if no url
      }

      $template->setVariable('linkCSSID',$menuItem->{'css_id'});
      $template->setVariable('url',$url);
      $template->setVariable('fontAwesomeIconName',$menuItem->{'font_awesome_icon_name'});
      $template->setVariable('text',$menuItem->{'text'});
      if ($menuItem->{'windowed'}) {
        $template->setVariable('openMode','target="_blank"');
      }

      # set the active menu item
      my $matchURL = $menuItem->{'url'};
      $matchURL =~ s/\//\\\//g;
      if ($ENV{'SCRIPT_NAME'} =~ /^$matchURL/) {
        $template->setVariable('liClass','menu-item-active');
      }

      $menuHTML .= $template->render();
      $template->reset();
    }
  }

  return $menuHTML;
}

sub getMenuSettings {
  my $env = new PlugNPay::Environment();
  my $gatewayAccountUsername = $env->get('PNP_ACCOUNT');
  my $gatewayAccount = new PlugNPay::GatewayAccount($gatewayAccountUsername);
  my $services = new PlugNPay::GatewayAccount::Services($gatewayAccountUsername);

  my $features = $gatewayAccount->getFeatures();

  my $settings = {};

  if ($features->get('useOrders') eq '1' || $gatewayAccount->usesUnifiedProcessing()) {
    $settings->{'orders'} = 1;
  } else {
    $settings->{'orders'} = 0;
  }

  if ($services->getRecurringVersion() == 2) {
    $settings->{'membership'} = 1;
    $settings->{'customers'} = 1;
    $settings->{'hosts'} = 1;
  }

  return $settings;
};


sub getTemplate {
  my $self = shift;

  my $env = new PlugNPay::Environment();
  my $template = new PlugNPay::UI::Template();
  my $gatewayAccount = new PlugNPay::GatewayAccount($env->get('PNP_ACCOUNT'));

  my $csrfToken = new PlugNPay::Security::CSRFToken()->getToken();

  # Get the url and take 'index.cgi' off the end if it's there
  my $url = $ENV{'SCRIPT_NAME'};
  $url =~ s/index\.cgi$//;

  my $securityLevel = $env->get('PNP_SECURITY_LEVEL');

  if ($self->canSecurityLevelAccessURL($securityLevel,$url)) {
    $template->setTemplate('/admin/','index');
  } else {
    $template->setTemplate('/admin/','unauthorized');
  }

  $template->setVariable('menuHTML',$self->buildMenuHTML());
  $template->setVariable('login',$env->get('PNP_USER'));
  $template->setVariable('gatewayAccount',$env->get('PNP_ACCOUNT'));
  $template->setVariable('csrfToken','<meta name="request-token" content="' . $csrfToken . '">');
  $template->setVariable('companyName',$gatewayAccount->getCompanyName());

  return $template;
}

sub canAccessURL {
  my $self = shift;
  
  my $env = new PlugNPay::Environment();

  return $self->canSecurityLevelAccessURL($env->get('PNP_SECURITY_LEVEL'),$ENV{'SCRIPT_NAME'});
}

sub canSecurityLevelAccessURL {
  my $self = shift;
  my $securityLevel = shift;
  my $url = shift;

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q/
    SELECT count(*) as permitted
      FROM admin_security_level
     WHERE url = ?
       AND security_level = ? 
  /);

  $sth->execute($url,$securityLevel);

  my $result = $sth->fetchrow_hashref;

  return ($result && $result->{'permitted'});
}
  
1;
