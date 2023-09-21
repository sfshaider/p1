package PlugNPay::Reseller::MarketingInfo;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::UI::Template;

sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self, $class;

  return $self;
}

sub getDocs {
  my $self = shift;

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q/
	SELECT title, url, description
	FROM reseller_admin_marketing_info_docs
  /);

  $sth->execute();

  return $sth->fetchall_arrayref({});
}

sub getProductDocs {
  my $self = shift;

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q/
        SELECT title, url, description
        FROM reseller_admin_marketing_info_product_docs
  /);

  $sth->execute();

  return $sth->fetchall_arrayref({});
}

sub getEcheckDocs {
  my $self = shift;

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q/
        SELECT title, url, description
        FROM reseller_admin_marketing_info_echeck_docs
  /);

  $sth->execute();

  return $sth->fetchall_arrayref({});
}

sub buildDocHTML {
  my $self = shift;
  my $docs = shift;

  my $html = '';
  my $template = new PlugNPay::UI::Template;
  $template->setTemplate('/reseller/admin/MarketingInfo','marketing_info_item');
  foreach my $res (@{ $docs }) {
    $template->setVariable('title', $res->{'title'});
    $template->setVariable('url', $res->{'url'});
    $template->setVariable('description', $res->{'description'});
    $html .= $template->render();
    $template->reset();
  }

  return $html;
}

sub buildPageHTML {
  my $self = shift;

  my $html = '';
  my $template = new PlugNPay::UI::Template;

  $template->setTemplate('/reseller/admin/MarketingInfo','marketing_info');  

  my $docs = $self->buildDocHTML($self->getDocs());
  my $products = $self->buildDocHTML($self->getProductDocs());
  my $echecks = $self->buildDocHTML($self->getEcheckDocs());

  $template->setVariable('marketing_info_docs', $docs);
  $template->setVariable('marketing_info_product_docs', $products);
  $template->setVariable('marketing_info_echeck_docs', $echecks);

  $html .= $template->render();
  $template->reset();

  return $html;
}

1;
