#!/usr/local/bin/perl

package CertiTax;

use IO::Socket;
#use strict;

#
# This subroutine creates the shipping string
#
sub createShipString
{
   my $self = shift;

   my ($company,
       $serialNumber,
       $refMerchantID,
       $addr1,
       $addr2,
       $city,
       $county,
       $state,
       $zip) = @_;
#print "\$company=$company\n";
#print "\$serialNumber=$serialNumber\n";
#print "\$addr1=$addr1\n";
#print "\$addr2=$addr2\n";
#print "\$city=$city\n";
#print "\$country=$country\n";
#print "\$state=$state\n";
#print "\$zip=$zip\n";

   "0001=$serialNumber;" .
   ($refMerchantID ? "0109=$refMerchantID;" : "") .
   "0210=2;" .
   "0221=$company;" .
   "0222=$addr1;" .
   "0223=$addr2;" .
   "0224=$city;" .
   "0225=$county;" .
   "0226=$state;" .
   "0227=$zip;" .
   "0120=1" .
   "0111=y;";
}

#
# These subroutines create a line item request string
#
sub createLineItemString
{
   my $self = shift;

   my ($id,
       $stock_unit,
       $units,
       $price,
       $prod_code) = @_;
#print "\$id=$id\n";
#print "\$stock_unit=$stock_unit\n";
#print "\$units=$units\n";
#print "\$price=$price\n";
#print "\$prod_code=$prod_code\n";
   my $rc;

   $rc = "0300={0301=$id;" .
         "0302=$stock_unit;" .
         "0303=$units;" .
	 "0305=$price;";

   if ($prod_code) {
     $rc .= "0310=$prod_code";
   }

   $rc .= '}';

   $rc;
}

sub createLineItemsString
{
   my $self = shift;

   my ($line_items) = @_;
#print "\$line_items=$line_items\n";

   #
   # Since an line item can contain many line items and each line item is
   # composed of multiple parts we split them apart before buiding the
   # request string
   #
   my $rc;
   my @items = split (/[{}]/, $line_items);
#print "\@items=",join('|',@items),"\n";

   foreach my $item (@items) {
      next if (! $item);

      if ($item && ($item !~ /[{}]/)) {
	 my @tokens = split (/[,]/, $item);

	 $rc .= &createLineItemString ($self,
				       @tokens);
      }
   }

   $rc;
}

#
# This subroutine creates the calculation request string
#
sub createCalcString
{
   my $self = shift;

   my ($company,
       $serialNumber,
       $refMerchantID,
       $addr1,
       $addr2,
       $city,
       $country,
       $state,
       $zip,
       $verify,
       $breakdown,
       $total,
       $lineItems) = @_;
   my $rc;
#print "\$serialNumber=$serialNumber\n";
#print "\$company=$company\n";
#print "\$addr1=$addr1\n";
#print "\$addr2=$addr2\n";
#print "\$city=$city\n";
#print "\$country=$country\n";
#print "\$state=$state\n";
#print "\$zip=$zip\n";
#print "\$verify=$verify\n";
#print "\$breakdown=$breakdown\n";
#print "\$total=$total\n";
#print "\$lineItems=lineItems\n";

   $rc = "0001=$serialNumber;" .
         ($refMerchantID ? "0109=$refMerchantID;" : "") .
         "0210=2;" .
	 "0221=$company;" .
	 "0222=$addr1;" .
	 "0223=$addr2;" .
         "0224=$city;" .
	 "0225=$country;" .
	 "0226=$state;" .
	 "0227=$zip;" .
         "0120=$total;" .
         "0110=y;";

   if ($verify =~ /[yY]/) {
      $rc .= "0111=y;";
   } else {
      $rc .= "0111=n;";
   }

   $rc .= &createLineItemsString ($self,
				  $lineItems);

   $rc;
}

#
# This subroutine creates the commit request string
#
sub createCommitString
{
   my $self = shift;

   my ($serial,
       $refMerchID,
       $tranID) = @_;
#print "\$serial=$serial\n";
#print "\$tranID=$tranID\n";

   "9801=$serial;" .
   ($refMerchantID ? "0109=$refMerchantID;" : "") .
   "9804=$tranID;" .
   "9810=F;";
}

#
# This subroutine processes the response sent back after a calculate
# request
#
sub processCalcResponse
{
   my $self = shift;

   my ($tokens) = @_;

   my $tranID = delete $$tokens{'1004'};

   my $totalTax = delete $$tokens{'5001'};

   my $rc = "tranID=$tranID;totalTax=$totalTax;\n";

   if ($self->{'_BREAKDOWN'} =~ /[yY]/)  {
      $rc .= &processTaxBreakdownResponse ($self,
					   $tokens);
   }

   if ($self->{'_VERIFICATION'} =~ /[yY]/) {
      $rc .= &processAddressVerificationResponse ($self,
						  $tokens);
   }

   $rc;
}

#
# This subroutine processes the response sent back after a commit request
#
# Format:
#    COMMIT 9904=<id>;9910=<final>;
#
sub processCommitResponse
{
   my $self = shift;

   my ($tokens) = @_;

   my $tranID = delete $$tokens{'9904'};

   my $final = delete $$tokens{'9910'};

   "tranID=$tranID;final=$final;\n";
}

#
# This subroutine processes the response sent back after an address
# verification request
#
sub processAddressVerificationResponse
{
   my $self = shift;

   my ($tokens) = @_;

   my $status = delete $$tokens{'1099'};

   my $name = delete $$tokens{'5101'};

   my $addr1 = delete $$tokens{'5102'};

   my $addr2 = delete $$tokens{'5103'};

   my $city = delete $$tokens{'5104'};

   my $state = delete $$tokens{'5105'};

   my $zip = delete $$tokens{'5106'};

   my $geo = delete $$tokens{'5107'};

   "status=$status;name=$name;addr1=$addr1;addr2=$addr2;city=$city;state=$state;zip=$zip;geo=$geo\n";
}

#
# This subroutine processes the response sent back after an address
# verification request
#
sub processTaxBreakdownResponse
{
   my $self = shift;

   my ($tokens) = @_;

   my $national = delete $$tokens{'5002'};

   my $state = delete $$tokens{'5003'};

   my $county = delete $$tokens{'5004'};

   my $city = delete $$tokens{'5005'};

   my $local = delete $$tokens{'5006'};

   my $nationalAuth = delete $$tokens{'5012'};

   my $stateAuth = delete $$tokens{'5013'};

   my $countyAuth = delete $$tokens{'5014'};

   my $cityAuth = delete $$tokens{'5015'};

   my $localAuth = delete $$tokens{'5016'};

   "nationalTax=$national;stateTax=$state;countyTax=$county;localTax=$local\n" .
   "nationalAuth=$nationalAuth;stateAuth=$stateAuth;countyAuth=$countyAuth;cityAuth=$cityAuth;localAuth=$localAuth\n";
}

#
# This subroutine determines what type of response was sent back and
# calls the appropriate subroutine to handle it
#
# Format:
#   ####=XXXX;
# where:
#   #### is a number (i.e. 1004, 5107, ...)
#   XXXX is the data
#
sub parseResponse
{
   my $self = shift;

   my ($response) = @_;
#print "\$response=$response\n";
   my %tokens = split (/[;=]/, $response);
   my $err;
   my $rc;

#print "\%tokens={";
#foreach $key (keys %tokens) { print "$key=>$tokens{$key},"; }
#print "}\n";
   #
   # Check to see if there were errors
   #
   if (($err=$tokens{'10000'})
       || ($err=$tokens{'9999'})) {
      # These seem to return their own error text
   } elsif (($err=$tokens{'1098'})
	    && ($tokens{'1098'} != 'ACPT')) { # Ack code ?
      #
      # This needs to be mapped to a textual error code
      #
      my (%err_map) = (
         'PKGE' => 'PACKAGE ERROR',
         'MRCH' => 'INVALID SERIAL NUMBER',
         'MRCS' => 'INVALID MERCHANT STATUS',
         'TRNE' => 'INVALID TRANSACTION NUMBER',
         'TRNS' => 'INVALID TRANSACTION STATUS',
         'TOT0' => 'INVALID ORDER TOTAL',
         'TOTN' => 'INVALID ORDER TOTAL',
         'SHPN' => 'INVALID SHIPPING COST',
         'HNDN' => 'INVALID HANDLING COST',
         'LOCI' => 'INVALID LOCATION ID',
      );

      if (! $err_map{$rc}) {
	 $err = 'UNKNOWN ERROR';
      }
   } else {
      #
      # Ya, I could have used an if statement but I find it simpler to update a
      # hash than an if statement
      #
      my (%map) = (
         'CALCULATE' => \&processCalcResponse,
         'COMMIT' => \&processCommitResponse,
         'SHIP' => \&processAddressVerificationResponse,
      );

      undef $err;

#print "\$map{$self->{'_COMMAND'}}\n";
      $rc = &{ $map{$self->{'_COMMAND'}} } ($self,
					    \%tokens);

      #
      # Note: Could check for extra tokens if desired.
      #
   }

   ($err, $rc);
}

#
# This method should be invoked to create the object.
#
sub new
{
   my $proto = shift;
   my $server = shift;
   my $port = shift;
   my $class = ref($proto) || $proto; # Determine if we're being called as a class method or an object method
   my $self = {};

   #
   # Initialize the 'object' variables
   #
   $self->{'_COMMAND'} = undef;
   $self->{'_SERVER'} = $server;
   $self->{'_PORT'} = $port;
   $self->{'_BREAKDOWN'} = undef;
   $self->{'_VERIFICATION'} = undef;
#print "\$self->{'_SERVER'}=$self->{'_SERVER'}\n";
#print "\$self->{'_PORT'}=$self->{'_PORT'}\n";

   #
   # Create a connection
   #
   $self->{'_SOCK'} = IO::Socket::INET->new ('Proto' => "tcp",
					     'PeerAddr' => $self->{'_SERVER'},
					     'PeerPort' => $self->{'_PORT'},
					     'Type' => SOCK_STREAM,
					     'Timeout' => 60) or die "Cannot connect to $self->{'_PORT'} at $self->{'_SERVER'} - $!";
   $self->{'_SOCK'}->autoflush (1); # Send things *now* - don't buffer

   bless ($self, $class); # Now it's an object

   return $self;
}

#
# This method is invoked to send an array of data to the server
#
# Format:
#    CALCULATE ip port company serial addr1 addr2 city county state zip [verify breakdown] [total | {line}[{line}]]
#    COMMIT ip port serial id
#    SHIP ip port company serial addr1 addr2 city county state zip
# where:
#    name     description                     example                   blank
#    ----     -----------                     -------                   -----
#    ip       IP address of server            192.168.1.111             N
#    port     IP port of server               1222                      N
#    company  Company/Firm name               "Test Company"            N
#    addr1    First address line of company   "580 2nd St."             N
#    addr2    Second address line of company  ""                        Y
#    state    State of company                "Oakland"                 N
#    zip      Zip code of company             "94600"                   N
#    serial   Serial number of transaction    "6C00-1004-7FD6-FA80"     N
#    county   County of company               ""                        Y
#    line     Line item                       "{1,9,3,650}{2,9,1,606}"  N
#    verify   Verify shipping address         "y"                       N
#    total    Total amount                    1299                      N
#    id       Transaction ID                  1099074111685700          N
#
sub send
{
   my $self = shift;

   #
   # All commands start with these three items
   #
   $self->{'_COMMAND'} = shift;
#print "\$self->{'_COMMAND'}=$self->{'_COMMAND'}\n";

   if ($self->{'_COMMAND'} eq 'CALCULATE') {
      $self->{'_VERIFICATION'} = $_[8];
      $self->{'_BREAKDOWN'} = $_[9];
#print "\$self->{'_BREAKDOWN'}=$self->{'_BREAKDOWN'}\n";
#print "\$self->{'_VERIFICATION'}=$self->{'_VERIFICATION'}\n";
    }

   #
   # Ya, I could have used an if statement but I find it simpler to update a
   # hash than an if statement
   #
   my (%map) = (
      'CALCULATE' => \&createCalcString,
      'COMMIT' => \&createCommitString,
      'SHIP' => \&createShipString,
   );

#print "\@_=",join("|",@_),"\n";
   my $request = &{ $map{$self->{'_COMMAND'}} } ($self,
						 @_);
#print "\$request=$request\n";

   #
   # Send the stuff to the server
   #
   my $SOCK = $self->{'_SOCK'};
   print $SOCK "$request\n";
}

#
# Called to process the information that comes back from the server
#
sub receive
{
   my $self = shift;
   my ($ALARM,$response);
   #
   # Since not all OSes (i.e. Windows) support an alarm we 'stub'
   # it out for those OSes that don't have it. Maybe someday it'll
   # be replaced with code that does the alarm functionality on
   # Windows
   #
   eval { alarm; };
   if ($@) { # Alarm isn't supported (i.e. Windows)
      $ALARM = sub { };
   } else {
      $ALARM = \&alarm;
   }

   #
   # Wait for a response (timeout if we don't get something in time)
   #
   eval {
      local $SIG{'ALRM'} = sub { die "timeout"; };
#      &{ $ALARM } (60);

      my $SOCK = $self->{'_SOCK'};
      $response = <$SOCK>;
      chomp ($response);

#      &{ $ALARM } (0);
   };
   if ($@ and $@ !~ /timeout/) { die "Timeout when reading from $self->{'_SERVER'}/$self->{'_PORT'}"; };

   #
   # Got a response - deal with it
   #
   &parseResponse ($self,
		   $response);
}

#
# Called when the class is destroyed/freed/removed
#
sub DESTROY
{
   my $self = shift;

   #
   # Clean up
   #
   close ($self->{'SOCK'}) || die "close: $!";
}

1; # so the require/use succeeds
