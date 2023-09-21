#!/bin/env perl

# Purpose: Generates Captcha Graphic

require 5.001;
$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use GD::SecurityImage;
use CGI;
use pnp_environment;
use miscutils;
use strict;

## allow Proxy Server to modify ENV variable 'REMOTE_ADDR'
if ($ENV{'HTTP_X_FORWARDED_FOR'} ne '') {
  $ENV{'REMOTE_ADDR'} = $ENV{'HTTP_X_FORWARDED_FOR'};
}

# pnp_environment doesn't work in modperl on dev this works though
my $webtxt = &pnp_environment::get('PNP_WEB_TXT');
my $fontPath = $webtxt . '/captcha/';
my @bgColors = ('#00aaaa');
my @fonts = ('font1.ttf','font2.ttf','font4.ttf','font7.ttf','font9.ttf');
my @styles = ('default', 'rect', 'circle', 'ellipse', 'ec');

# we only accepet captchaID
my $query = new CGI;
my $captchaID = $query->param('captchaID');
$captchaID =~ s/[^0-9a-fA-F]//g;

my $captchaIP = '';
if (defined $ENV{'REMOTE_ADDR'}) {
  $captchaIP = $ENV{'REMOTE_ADDR'};
}

&create_captcha($captchaID, $captchaIP);

exit;

sub create_captcha {
  my ($captchaID, $captchaIP) = @_;

  # get captcha answer from database 
  my $answer = '';
  my $dbh = &miscutils::dbhconnect('pnpmisc');
  if (defined $dbh) {
    my $sth = $dbh->prepare(q{
        SELECT answer
        FROM captchaclient
        WHERE id=?
        AND ipaddress=?
      });
    $sth->execute("$captchaID","$captchaIP");
    ($answer) = $sth->fetchrow();
    $sth->finish;
    $dbh->disconnect;
  }

  # if answer is empty try to display an error message
  if ($answer eq '') {
    $answer = 'ERROR';
  }

  # specify the random settings
  my $lines = int(rand(30));
  #my $font = $fonts[int(rand($#fonts+1))];
  my $font = 'font1.ttf';
  my $bgColor = $bgColors[int(rand($#bgColors+1))];

  # now start to define the captch image params
  my $image = GD::SecurityImage->new(
     width      => 320,
     height     => 100,
     ptsize	=> 30,
     thickness	=> 1,
     lines      => 20,
     rndmax     => 4,
     scramble   => 0,
     send_ctobg => 1,
     bgcolor    => $bgColor,
     font       => $fontPath . $font
  );

  # set the captcha answer for display in the captcha graphic
  $image->random($answer);

  # define the creation params of the captcha
  my $method = 'ttf';
  my $style = $styles[int(rand($#styles+1))];
  my $text_color = '#f4f4f4';
  my $line_color = '#999999';
  $image->create($method, $style, $text_color, $line_color);
  $image->particle();

  # define the comment tag
  $image->info_text(
     x      => 'right',
     y      => 'down',
     gd     => 1,
     strip  => 1,
     color  => '#000000',
     scolor => '#FFFFFF',
     text   => 'Captcha Required',
  );

  # now build the image
  my($image_data, $mime_type) = $image->out(force => 'png', compress => 1);

  # output the completed image to the screen.
  print "Content-Type: $mime_type\n\n";
  print $image_data;

  return;
}

