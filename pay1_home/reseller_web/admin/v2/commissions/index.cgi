#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Reseller;
use PlugNPay::UI::HTML;
use PlugNPay::Sys::Time;
use PlugNPay::UI::Template;
use PlugNPay::Reseller::Admin;

## Get Reseller Account settings
my $reseller = new PlugNPay::Reseller($ENV{'REMOTE_USER'});

## Check if commissions are paid out
if ($reseller->getPayAllFlag() != 1 || $reseller->getCommissionsFlag() ) {
  ## INIT
  my $time = new PlugNPay::Sys::Time();
  my $admin = new PlugNPay::Reseller::Admin();
  my $main = $admin->getTemplate();
  my $builder = new PlugNPay::UI::HTML();

  my $months = {};
  for (my $i = 1; $i < 13; $i++){
    my $month = $i;
    if ($month < 10 ) {
       $month = '0' . $month;
    }
    $months->{$month} = $month;
  }

  
  my $year = substr($time->inFormat('yyyymmdd'),0,4);
  my $Years = {};
  
  for (my $i = 2009; $i <= $year; $i++){
    $Years->{$i} = $i;
  }

  my $yearOptions = {'selectOptions' => $Years, 
                     'selected' => $year};
  my $monthOptions = {'selectOptions' => $months,
                      'selected' => '01'};
  
  ## Build Template
  my $template = new PlugNPay::UI::Template();
  $main->setVariable('headTags', $template->loadTemplate('reseller/admin/commissions','head'));
  $template->reset();
  $template->setVariable('pt_gateway_account',$ENV{'REMOTE_USER'});
  $template->setVariable('StartMonth', '<select class="reseller-input-control" name="startmonth">' . $builder->selectOptions($monthOptions) . '</select>');
  $template->setVariable('StartYear', '<select name="startyear" class="reseller-input-control">' . $builder->selectOptions($yearOptions) . '</select>');
  $template->setVariable('EndMonth', '<select name="endmonth" class="reseller-input-control">' . $builder->selectOptions($monthOptions) . '</select>');
  $template->setVariable('EndYear', '<select class="reseller-input-control" name="endyear">' . $builder->selectOptions($yearOptions) . '</select>');
  $main->setVariable('content',$template->loadTemplate('reseller/admin/commissions','index'));
   
  ## Send to browser
  print 'content-type:text/html' . "\n\n";
  print $main->render();
  
}else {
  ## Build and send error response page
  my $main = new PlugNPay::Reseller::Admin()->getTemplate();
  my $template = new PlugNPay::UI::Template();
  $main->setVariable('headTags', $template->loadTemplate('reseller/admin/commissions','head'));
  $main->setVariable('content', $template->loadTemplate('reseller/admin/commissions','payall'));
  print 'content-type:text/html' . "\n\n" . $main->render();
}

exit;
