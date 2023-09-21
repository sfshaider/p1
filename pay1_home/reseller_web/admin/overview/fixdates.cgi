#!/bin/env perl 

require 5.001;
$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use CGI;
use sysutils;

print "Content-Type: text/html\n\n";

$path_orders = "orders.html"; 
$username = $ENV{"REMOTE_USER"};

$query = new CGI;
$merchant = &CGI::escapeHTML($query->param('merchant'));

#if ($username eq "pnpdemo") {
#  $path_orders = "orders_pnp.html";
#}

if ($ENV{'SEC_LEVEL'} > 9) {
  print "Your current security level is not cleared for this operation. <p>Please contact Technical Support if you believe this to be in error. ";
  exit;
}

($sec,$min,$hour,$mday,$mon,$yyear,$wday,$yday,$isdst) = localtime(time());
$mon++;
  $yyear += 1900;
if ($mday < 10){
  $mday = "0" . $mday; 
}
if ($yyear%4 == 0) {
  $leap = 1;
  if ($yyear%400 == 0){
    $leap = 1;
  }elsif($yyear%100 == 0){
    $leap = 0;
  }
}else{
  $leap = 0;
}

if ((($mon == "04")||($mon == "06")||($mon == "09")||($mon == "11")) && 
     ($mday == 30)){
  $endday = "01";
  $endmon = $mon + 1;
}elsif(($mon == "02")&&($mday == "28")&&($leap == 0)){
  $endday = "01";
  $endmon = $mon + 1;
}elsif(($mon == "02")&&($mday == "29")&&($leap == 1)){
  $endday = "01";
  $endmon = $mon + 1;
}elsif($mday == "31"){
  $endday = "01";
  $endmon = $mon + 1;
}else{
  $endday = $mday + 1;
  $endmon = $mon;
  if ($endday < 10){
    $endday = "0" . $endday;
  }
} 

if (($mon == "12")&& ($mday == "31")){
  $endyear = $yyear++;
  $endmon = "01";
}else{
  $endyear = $yyear;
}


if ($mon < 10){
  $mon = "0".$mon;
}
if  ($endmon < 10){
  $endmon = "0".$endmon;
}
#use mday,mon and yyear
$path_orders =~ s/[^a-zA-Z0-9\_\-\.\/]//g;
&sysutils::filelog("read","$path_orders");
open(INFILE,"$path_orders");
foreach(<INFILE>) {
  if ($_ =~ /\bstartmon\b/){
    $field = 1;
  }
  if ($_ =~ /\bstartday\b/){
    $field = 2;
  }
  if ($_ =~ /\bstartyear\b/){
    $field = 3;
  }

  if ($_ =~ /\bendmon\b/){
    $field = 4;
  }
  if ($_ =~ /\bendday\b/){
    $field = 5;
  }
  
  if ($_ =~ /\bendyear\b/){
    $field = 6;
  }
 
  if ($_ =~ /MERCHANT_NAME/) {
    s/MERCHANT_NAME/$merchant/g;
  } 

  if ($field == 1){
    #open(FILEF,">checking.txt");
    #print FILEF "$mon\n";
    #close(FILEF);
    if ($_ =~ /\b$mon\b/){
      s/HERE/selected/g;
    }else{
      s/HERE/ /g;
    }
  }

  if ($field == 2){
    if ($_ =~ /\b$mday\b/){
      s/HERE/selected/g;
    }else{
      s/HERE/ /g;
    }
  }
 
  if ($field == 3){
    if ($_ =~ /\b$yyear\b/){
      s/HERE/selected/g;
    }else{
      s/HERE/ /g;
    }
  }

  if ($field == 4){
    if ($_ =~ /\b$endmon\b/){
      s/HERE/selected/g;
    }else{
      s/HERE/ /g;
    }
  }

  if ($field == 5){
    if ($_ =~ /\b$endday\b/){
      s/HERE/selected/g;
    }else{
      s/HERE/ /g;
    }
  }

  if ($field == 6){
    if ($_ =~ /\b$endyear\b/){
      s/HERE/selected/g;
    }else{
      s/HERE/ /g;
    }
  }
  
  print;
}
close(INFILE);


exit;
