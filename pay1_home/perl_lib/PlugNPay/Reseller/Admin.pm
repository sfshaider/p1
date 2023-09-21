package PlugNPay::Reseller::Admin;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::UI::Template;
use PlugNPay::Environment;
use PlugNPay::Security::CSRFToken;

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

sub getTemplate {
  my $self = shift;

  my $env = new PlugNPay::Environment();
  my $template = new PlugNPay::UI::Template();

  my $csrfToken = new PlugNPay::Security::CSRFToken()->getToken();

  # Get the url and take 'index.cgi' off the end if it's there
  my $url = $ENV{'SCRIPT_NAME'};
  $url =~ s/index\.cgi$//;

  my $securityLevel = $env->get('PNP_SECURITY_LEVEL');

  if ($self->canSecurityLevelAccessURL($securityLevel,$url)) {
    $template->setTemplate('/reseller/admin/','index');
  } else {
    $template->setTemplate('/reseller/admin/','unauthorized');
  }

  $template->setVariable('login',$env->get('PNP_USER'));
  $template->setVariable('reseller',$env->get('PNP_ACCOUNT'));
  $template->setVariable('menuHTML',$self->buildMenuHTML());
  $template->setVariable('csrfToken','<meta name="request-token" content="' . $csrfToken . '">');

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

  # until resellers have sublogins and security levels, always return 1
  return 1;

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

sub buildMenuHTML {
  my $self = shift;

  my $template = new PlugNPay::UI::Template();
  $template->setCategory('/reseller/admin/');
  $template->setName('index_menu_item');

  my $menuHTML = '';

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT text, url, font_awesome_icon_name, css_id, windowed
      FROM reseller_admin_menu_item
     WHERE enabled = ?
     ORDER BY `order`
  /);

  $sth->execute(1);

  my $results = $sth->fetchall_arrayref({});

  if ($results) {
    foreach my $menuItem (@{$results}) {
      $template->setVariable('linkCSSID',$menuItem->{'css_id'});
      $template->setVariable('url',$menuItem->{'url'});
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
  
1;
