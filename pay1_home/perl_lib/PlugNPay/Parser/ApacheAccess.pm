package PlugNPay::Parser::ApacheAccess;
#---------------------------------
# PlugNPay Parser for Apache Logs
#---------------------------------
# Reads a line from apache logs and returns a hash of values for the line read
# Requires the following format for CustomLog:
#  LogFormat "%h %l %U %t \"%m %U %H\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\" %T %v"
#

use strict;


sub new {
  my ($self) = @_;
  my %values;
  $self = \%values;
  bless $self,'PlugNPay::Parser::ApacheAccess';
  return $self;
}

sub parse {
  my ($self,$line) = @_;
  chomp $line;
  my $logFormat = qr{
    ^
    ([\d\.]+)\s+            # ip address
    ([A-z0-9\-]+)\s+        # username
    (\S+)\s+                # requested url
    (\[\S+\s+\S+\])\s+      # timestamp
    "(\S+\s+\S+\s+\S+)"\s+  # request
    (\d+)\s+                # status
    ([\d\-]+)\s+                # bytes
    "(.*?)"\s+              # referrer
    "(.*?)"\s+              # user agent
    (\d+)\s+                # pid
    (\d+)                   # time in seconds 
    }xms;
#  print $line . "\n";
#  print $logFormat  . "\n";
  $line =~ /$logFormat/;

  my %fields;
  $fields{'remote_ip'} = $1;
  $fields{'remote_user'} = $2;
  $fields{'url'} = $3;
  $fields{'timestamp'} = $4;
  $fields{'request'} = $5;

  my @req = split(/\s+/,$fields{'request'});
  $fields{'method'} = $req[0];
  $fields{'protocol'} = $req[2];
  $fields{'uri'} = $req[1];
  $fields{'status'} = $6;
  $fields{'bytes'} = $7;
  $fields{'referrer'} = $8;
  $fields{'useragent'} = $9;
  $fields{'pid'} = $10;
  $fields{'time'} = $11;

  return %fields;
}


1;
