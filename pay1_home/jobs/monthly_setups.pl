#!/bin/env perl

use lib $ENV{'PNP_PERL_LIB'};

use strict;
use Spreadsheet::WriteExcel;
use miscutils;

my @months = ("December","January","February","March","April","May","June","July","August","September",
              "October","November"); #off by one because it runs for the month prior
my $month = &monthcolumn();

#my $emailaddress = 'chris@plugnpay.com';
my $emailaddress = 'michelle@plugnpay.com';

####  Step 1;
####  Set up a working directory for this runtime
####
my $workingdir = "/tmp/setups.$$";
if (!-d $workingdir) {
  print "Creating working directory $workingdir\n";
  system("mkdir $workingdir");
}
if (!-d $workingdir) {
  die("Could not create working directory: $workingdir\n");
}
print "Working Directory is now $workingdir\n";


####  Step 2;
####  Set up the database connection
####
print "Setting up database connection\n";
my $dbh = &miscutils::dbhconnect("pnpmisc","yes");
  if ($dbh eq "") {
    &head("Database Failure");
    print "<h2>Database connection failed</h2>";
    &tail();
    die();
  }


####  Step 3;
####  Collect reseller list
####
print "Collecting reseller list for setups\n";
my $sth = $dbh->prepare(qq(select username from salesforce)) or die("Can't prepare: $DBI::errstr");
$sth->execute() or die("Can't execute: $DBI::errstr");

# array to hold reseller list
my @resellers;

# populate array from query
while (my @row = $sth->fetchrow_array()) {
  push (@resellers,$row[0]);
}
$sth->finish;

my $numresellers = @resellers;

####  Step 4;
####  Create XLS file for each reseller
####

# keep track of how many queries we do, sleep once in a while so as to
# not overwhelm the database
my $sleepcounter;
my @resellers_nonempty;
my $resellercount = 0;

foreach my $reseller (@resellers) {
  my $row;
  my $numrows = 0;
  $resellercount++;
  $sleepcounter++;
  if ($sleepcounter % 21 == 0) { $sleepcounter = 0; sleep 3;}

  $sth = $dbh->prepare(qq(select c.username as username,
                                 c.status as status,
                                 c.name as name,
                                 c.merchant_id as merchant_id,
                                 pnp.submit_date as submitdate,
                                 company
                          from customers c,pnpsetups pnp
                          where c.username=pnp.username
                            and c.status regexp '(live|debug|hold)'
                            and pnp.submit_date regexp '^$month'
                            and c.reseller='$reseller'));
  $sth->execute;

  ### Excel Code here ###
  print "\nGenerating XLS for $reseller ($resellercount of $numresellers)\n";
  my $filename = xlsfilename($reseller);
  print "--> Creating file $filename\n";
  my $workbook = Spreadsheet::WriteExcel->new($filename);
  my $worksheet = $workbook->addworksheet("$reseller");

  # worksheet basic layout
  $worksheet->set_column(0,0,13);
  $worksheet->set_column(1,1,25);
  $worksheet->set_column(2,2,23);
  $worksheet->set_column(3,3,12);
  $worksheet->set_column(4,4,8);
  $worksheet->set_column(5,5,35);

  # heading
  $worksheet->write_string(0,1, "$reseller setups for " . $months[(localtime)[4]]);

  # column headings
  $worksheet->write_string(2,0,"Username");
  $worksheet->write_string(2,1,"Name");
  $worksheet->write_string(2,2,"Merchant ID");
  $worksheet->write_string(2,3,"Submit Date");
  $worksheet->write_string(2,4,"Status");
  $worksheet->write_string(2,5,"Company Name");

  my $rowbase = 2;
  while ($row = $sth->fetchrow_hashref()) {
    $numrows++;
    my %rowhash = %$row;
    my $workingrow = $rowbase + $numrows;
    $worksheet->write_string($workingrow, 0, $rowhash{"username"});
    $worksheet->write_string($workingrow, 1, $rowhash{"name"});
    $worksheet->write_string($workingrow, 2, $rowhash{"merchant_id"});
    $worksheet->write_string($workingrow, 3, &datecolumn($rowhash{"submitdate"}));
    $worksheet->write_string($workingrow, 4, $rowhash{"status"});
    $worksheet->write_string($workingrow, 5, $rowhash{"company"});
  }
  $sth->finish;

  $worksheet->write_string($numrows + $rowbase + 2, 1, "Total");
  $worksheet->write_string($numrows + $rowbase + 2, 2, $numrows);


  if ($numrows == 0) {
    print "<-- Removing empty file $filename\n";
    system("rm $filename");
    next;
  } #don't create file for reseller with no new merchants

  ### put non-empty resellers into a list of files to zip up
  push(@resellers_nonempty,$reseller);
}

####
####  Zip up and email the xls files
####
# build xls file list
print "Generating list of files to zip\n";
my $xlsfilelist;
foreach my $reseller (@resellers_nonempty) {
  $xlsfilelist .= xlsfilename($reseller) . " ";
}

my $compressedfile = $workingdir . "/setups" . $month . ".zip";
print "Compressing files...\n";
`zip -j $compressedfile $xlsfilelist`;
print "E-mailing zip archive to $emailaddress\n";
`/usr/bin/uuencode $compressedfile setups.zip|/bin/mailx -s "setups.zip" $emailaddress`;

print "Removing working directory $workingdir\n";
if (-d $workingdir) {
  system("rm -r $workingdir");
}


sub monthcolumn {
  my $year = (localtime)[5] + 1900;
  my $month = (localtime)[4];
  if ($month == 0) {$month = 12;}
  if ($month < 10) {$month = "0" . $month;}
  if ($month == 12) {$year--;}
  return "$year$month";
}

sub datecolumn {
  my ($datestring) = @_;
  my $year = substr($datestring,0,4);
  my $month = substr($datestring,4,2);
  my $day = substr($datestring,6,2);
  return "$month/$day/$year";
}

sub xlsfilename {
  my ($reseller) = @_;
  my $month = monthcolumn();
  return $workingdir . "/" . $reseller . substr($month,4,2) . substr($month,2,2) . ".xls";
}
