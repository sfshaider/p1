#!/usr/local/bin/perl

package fraudtrack;
 
require 5.001;
 
use MD5;
use miscutils;
use SHA;
use strict;
use constants qw(%constants::countries3to2);


sub new {
  my $type = shift;

  my (%query) = @_;

  my (%fraud_config);

  %fraudtrack::query = %query;
  %fraudtrack::fraud_config_hash = ();
  $fraudtrack::version = "20051106.00001";
  $fraudtrack::allow_overview = 0;
  $fraudtrack::frauddb = "fraudtrack";

  my $fconfig = $fraudtrack::query{'fconfig'};

  my @array = split(/\,/,$fconfig);
  foreach my $entry (@array) {
    my($name,$value) = split(/\=/,$entry);
    $fraud_config{$name} = $value;
    $fraud_config{'fraudtrack'} = 1;
  }

  %fraudtrack::fraud_config = %fraud_config;

  $fraudtrack::query{'username'} = $ENV{'REMOTE_USER'};
  $fraudtrack::query{'subacct'} = $ENV{'SUBACCT'};
 
  if (($fraudtrack::query{'merchant'} ne "") && ($ENV{'SCRIPT_NAME'} =~ /overview/)) {
    my $dbh = &miscutils::dbhconnect("pnpmisc");
    my $sth = $dbh->prepare(qq{
        select overview  
        from salesforce  
        where username='$ENV{'REMOTE_USER'}'
        }) or die "Can't do: $DBI::errstr";
    $sth->execute or die "Can't execute: $DBI::errstr";
    ($fraudtrack::allow_overview) = $sth->fetchrow;
    $sth->finish; 
    $dbh->disconnect;
  }
   
  if ($fraudtrack::allow_overview == 1) {
    $fraudtrack::username = &overview($ENV{'REMOTE_USER'},$fraudtrack::query{'merchant'});
  } 

  &init_vars();
 
  return [], $type;
}


sub init_vars {

  my %query = %fraudtrack::query;

  my $dbh = &miscutils::dbhconnect("pnpmisc");

  my $username = $fraudtrack::username;
  my $subacct = $fraudtrack::query{'subacct'};
  my ($allow_overview);

  my $maxapplevel = 5;

  my ($fraud_config);

  my %countries = %constants::countries;
  delete $countries{''};

  my $function = $query{"ffunction"};

  my $ip_block = $query{"ip_block"};
  my @ip_block_array = split('\|',$query{"ip_block_list"}); 

  my $bin_block = $query{"bin_block"};
  my @bin_block_array = split('\|',$query{"bin_block_list"});

  my $email_block = $query{"email_block"};
  my @email_block_array = split('\|',$query{"email_block_list2"});

  my $phone_block = $query{"phone_block"};
  $phone_block =~ s/[^0-9]//g;
  if (substr($phone_block,0,1) eq "1") {
    $phone_block = substr($phone_block,1);
  }
  my @phone_block_array = split('\|',$query{"phone_block_list"});

  my $db_query = "select fraud_config from customers where username=\'" . $username . "\'";

  my $sth = $dbh->prepare(qq{$db_query}) or  die "Can't prepare: ";
  $sth->execute() or die "Can't execute:";
  $sth->bind_columns(undef,\($fraud_config)); 
  $sth->fetch();
  $sth->finish();
  $dbh->disconnect();

  my $datetime = gmtime(time());
  open (DEBUG, ">>/home/p/pay1/database/debug/reseller_fraudtrack_change_log.txt");
  print DEBUG "DATE:$datetime, UN:$username, FUNC:$function, RU:$ENV{'REMOTE_USER'}, IP:$ENV{'REMOTE_ADDR'}, FC:$fraud_config, ";
  if ($function eq "update config") {
    print DEBUG "UPDATE: ";
    foreach my $key (keys %query) {
      my $s = $query{$key};
      print DEBUG "$key:$s, ";
    }
  }
  print DEBUG "\n";
  close (DEBUG);

  my %checkbox_hash = ("on","1","off","0","1","checked","0","");
  my %fraud_config_hash = ();
  if (($fraud_config ne "") && ($function ne "update config")) {
    my @fraud_config_array = split(/\,/,$fraud_config);
    foreach my $entry (@fraud_config_array) {
      my($name,$value) = split(/\=/,$entry);
      $fraud_config_hash{$name} = $value;
    }
    $fraud_config_hash{'cvv'} = $checkbox_hash{$fraud_config_hash{'cvv'}};
    $fraud_config_hash{'cvv_avs'} = $checkbox_hash{$fraud_config_hash{'cvv_avs'}};
    $fraud_config_hash{'int_avs'} = $checkbox_hash{$fraud_config_hash{'int_avs'}};
    $fraud_config_hash{'cvv_xpl'} = $checkbox_hash{$fraud_config_hash{'cvv_xpl'}};
    $fraud_config_hash{'cvv_ign'} = $checkbox_hash{$fraud_config_hash{'cvv_ign'}};
    $fraud_config_hash{'noemail'} = $checkbox_hash{$fraud_config_hash{'noemail'}};
    $fraud_config_hash{'nomrchemail'} = $checkbox_hash{$fraud_config_hash{'nomrchemail'}};
    $fraud_config_hash{'blkfrgnrvs'} = $checkbox_hash{$fraud_config_hash{'blkfrgnrvs'}};
    $fraud_config_hash{'blkfrgnmc'} = $checkbox_hash{$fraud_config_hash{'blkfrgnmc'}};
    $fraud_config_hash{'blkvs'} = $checkbox_hash{$fraud_config_hash{'blkvs'}};
    $fraud_config_hash{'blkmc'} = $checkbox_hash{$fraud_config_hash{'blkmc'}};
    $fraud_config_hash{'blkax'} = $checkbox_hash{$fraud_config_hash{'blkax'}};
    $fraud_config_hash{'blkds'} = $checkbox_hash{$fraud_config_hash{'blkds'}};

    $fraud_config_hash{'blkusip'} = $checkbox_hash{$fraud_config_hash{'blkusip'}};
    $fraud_config_hash{'reqfields'} = $checkbox_hash{$fraud_config_hash{'reqfields'}};
    $fraud_config_hash{'reqaddr'} = $checkbox_hash{$fraud_config_hash{'reqaddr'}};
    $fraud_config_hash{'reqzip'} = $checkbox_hash{$fraud_config_hash{'reqzip'}};

    $fraud_config_hash{'blkcntrys'} = $checkbox_hash{$fraud_config_hash{'blkcntrys'}};
    $fraud_config_hash{'blkemails'} = $checkbox_hash{$fraud_config_hash{'blkemails'}};
    $fraud_config_hash{'blkphone'} = $checkbox_hash{$fraud_config_hash{'blkphone'}};
#    $fraud_config_hash{'bounced'} = $checkbox_hash{$fraud_config_hash{'bounced'}};
    $fraud_config_hash{'blkipaddr'} = $checkbox_hash{$fraud_config_hash{'blkipaddr'}};
    $fraud_config_hash{'blksrcip'} = $checkbox_hash{$fraud_config_hash{'blksrcip'}};
    $fraud_config_hash{'blkbin'} = $checkbox_hash{$fraud_config_hash{'blkbin'}};
    $fraud_config_hash{'blkproxy'} = $checkbox_hash{$fraud_config_hash{'blkproxy'}};
    $fraud_config_hash{'matchcntry'} = $checkbox_hash{$fraud_config_hash{'matchcntry'}};
    $fraud_config_hash{'matchgeoip'} = $checkbox_hash{$fraud_config_hash{'matchgeoip'}};
    $fraud_config_hash{'matchzip'} = $checkbox_hash{$fraud_config_hash{'matchzip'}};
    $fraud_config_hash{'chkname'} = $checkbox_hash{$fraud_config_hash{'chkname'}};
    $fraud_config_hash{'netwrk'} = $checkbox_hash{$fraud_config_hash{'netwrk'}};
    $fraud_config_hash{'iTransact'} = $checkbox_hash{$fraud_config_hash{'iTransact'}};
    $fraud_config_hash{'chkaccts'} = $checkbox_hash{$fraud_config_hash{'chkaccts'}};
  }
  elsif ($function eq "update config") {
    $fraud_config_hash{'avs'} = $query{"avs"};
    $fraud_config_hash{'negative'} = $query{"negative"};
    $fraud_config_hash{'cvv'} = $checkbox_hash{$query{"cvv"}};
    $fraud_config_hash{'cvv_avs'} = $checkbox_hash{$query{"cvv_avs"}};
    $fraud_config_hash{'int_avs'} = $checkbox_hash{$query{"int_avs"}};
    $fraud_config_hash{'cvv_xpl'} = $checkbox_hash{$query{"cvv_xpl"}};
    $fraud_config_hash{'cvv_ign'} = $checkbox_hash{$query{"cvv_ign"}};
    $fraud_config_hash{'noemail'} = $checkbox_hash{$query{"noemail"}};
    $fraud_config_hash{'nomrchemail'} = $checkbox_hash{$query{"nomrchemail"}};
    $fraud_config_hash{'cybersource'} = $query{"cybersource"};
    $fraud_config_hash{'bounced_email'} = $query{"bounced_email"};
    $fraud_config_hash{'bounced_url'} = $query{"bounced_url"};
    if (($fraud_config_hash{'bounced_url'} ne "") && ($fraud_config_hash{'bounced_url'} !~ /^(http)/)) {
      $fraud_config_hash{'bounced_url'} = "http://" . $fraud_config_hash{'bounced_url'};
    }

    $fraud_config_hash{'ipfreq'} = $query{"ipfreq"};
    $fraud_config_hash{'matchcntry'} = $checkbox_hash{$query{"matchcntry"}};
    $fraud_config_hash{'matchgeoip'} = $checkbox_hash{$query{"matchgeoip"}};
    $fraud_config_hash{'chkname'} = $checkbox_hash{$query{"chkname"}};
    $fraud_config_hash{'netwrk'} = $checkbox_hash{$query{"netwrk"}};

    $fraud_config_hash{'iTransact'} = $checkbox_hash{$query{"iTransact"}};
    my $iTransUN = $query{"iTransactUN"};
    my $iTransPW = $query{"iTransactPW"};
    my $iTransLevel = $query{"iTransactLevel"};
    my $iTransRule = $query{"iTransactRule"};

    if ($checkbox_hash{$query{"iTransact"}} == 1) {
      $fraud_config_hash{'iTransConfig'}  = "$iTransUN:$iTransPW:$iTransLevel:$iTransRule";
    }

    my $freqlev = $query{"freqlev"};
    my $freqdays = $query{"freqdays"};
    my $freqhours = $query{"freqhours"};
    if ($freqlev > 0) {
      $fraud_config_hash{'freqchk'} = "$freqlev:$freqdays:$freqhours";
    }
    else {
      $fraud_config_hash{'freqchk'} = "";
    }
    $fraud_config_hash{'blkfrgnrvs'} = $checkbox_hash{$query{"blkfrgnrvs"}} ;
    $fraud_config_hash{'blkfrgnmc'} = $checkbox_hash{$query{"blkfrgnmc"}};

    $fraud_config_hash{'blkvs'} = $checkbox_hash{$query{"blkvs"}}; 
    $fraud_config_hash{'blkmc'} = $checkbox_hash{$query{"blkmc"}};
    $fraud_config_hash{'blkax'} = $checkbox_hash{$query{"blkax"}};
    $fraud_config_hash{'blkds'} = $checkbox_hash{$query{"blkds"}};

    $fraud_config_hash{'blkusip'} = $checkbox_hash{$query{"blkusip"}};

    $fraud_config_hash{'reqfields'} = $checkbox_hash{$query{"reqfields"}};
    $fraud_config_hash{'reqaddr'} = $checkbox_hash{$query{"reqaddr"}};
    $fraud_config_hash{'reqzip'} = $checkbox_hash{$query{"reqzip"}};

    $fraud_config_hash{'blkcntrys'} = $checkbox_hash{$query{"blkcntrys"}};
    $fraud_config_hash{'blkemails'} = $checkbox_hash{$query{"blkemails"}};
    $fraud_config_hash{'blkphone'} = $checkbox_hash{$query{"blkphone"}};
    $fraud_config_hash{'bounced'} = $query{"bounced"};
    $fraud_config_hash{'blkipaddr'} = $checkbox_hash{$query{"blkipaddr"}};
    $fraud_config_hash{'blksrcip'} = $checkbox_hash{$query{"blksrcip"}};
    $fraud_config_hash{'blkbin'} = $checkbox_hash{$query{"blkbin"}};
    $fraud_config_hash{'blkproxy'} = $checkbox_hash{$query{"blkproxy"}};
    $fraud_config_hash{'matchzip'} = $checkbox_hash{$query{"matchzip"}};

    $fraud_config_hash{'chkaccts'} = $checkbox_hash{$query{"chkaccts"}};
    $fraud_config_hash{'acctlist'} = $query{"acctlist"};
    $fraud_config_hash{'allowedage'} = $query{"allowedage"};
    $fraud_config_hash{'volimit'} = $query{"volimit"};

  }

  if (0) { 
  ##  Arrays for updating display pages 
  my @blocked_ip_array = &get_blocked_array("ip_fraud");
  my @blocked_bin_array = &get_blocked_array("bin_fraud");
  my @blocked_email_array = &get_blocked_array("email_fraud");
  my @blocked_phone_array = &get_blocked_array("phone_fraud");

  my @blocked_country_array = &get_blocked_array("country_fraud");

  my @default_blocked_email_array = ('hotmail.com','juno.com','yahoo.com','rocket.com','poboxes.com','hotbot.com','rocketmail.com','excite.com','nightmail.com','mail.com','bigfoot.com','address.com','ivillage.com');

  my @new_blocked_email_array = ();

  for (my $i=0;$i<=$#default_blocked_email_array;$i++) {
    push(@new_blocked_email_array,$default_blocked_email_array[$i]);
    foreach my $value (@blocked_email_array) {
      if ($value eq $default_blocked_email_array[$i]) {
        pop @new_blocked_email_array;
      }
    }
  }

  @default_blocked_email_array = @new_blocked_email_array;

  if (@blocked_country_array < 1) {
    @blocked_country_array = ('DZ','AO','AZ','BY','CU','GE','IR','IQ','LY','MM','SD','RU','NG','KP','YU');
  }

  my %blocked_country_hash = ();
  foreach my $brief (@blocked_country_array) {
    $blocked_country_hash{$brief} = $countries{$brief}; 
    delete $countries{$brief};
  }
  } ## End Disabled section 

  %fraudtrack::fraud_config_hash = %fraud_config_hash;
}

sub update_countries {
  my @block_list = split('\|',$fraudtrack::query{"country_block_list2"}); 
  my @allow_list = split('\|',$fraudtrack::query{"country_block_list1"});
  my $username = $fraudtrack::username;

  my $db_query = "delete from country_fraud where username=\'$username\'";

  my $dbh = &miscutils::dbhconnect("fraudtrack");
  my $sth = $dbh->prepare(qq{$db_query});
  $sth->execute();
  $sth->finish();

  $db_query = "insert into country_fraud (username,entry) values (?,?)";
  $sth = $dbh->prepare(qq{$db_query}) or die "insert country prepare fail";

  foreach my $country (@block_list) {
    if (($country ne "") && (length($country) == 2)){
      $sth->execute($username,$country) or die "insert country execute fail";
    }
  }
  $sth->finish();
  $dbh->disconnect();
}

sub get_blocked_array {
  shift;
  my ($table) = @_;
  my $username = $fraudtrack::username;
  my($dbusername,$blocked_entry);
  my @blocked_array = ();

  my $db_query = "select username,entry from $table where username=\'" . $username . "\'";

  my $dbh = &miscutils::dbhconnect("$fraudtrack::frauddb");
  my $sth = $dbh->prepare(qq{$db_query}) or die "failed prepare";
  my $rv = $sth->execute() or die "failed execute";
  $sth->bind_columns(undef,\($dbusername,$blocked_entry));
  while ($sth->fetch) {
    $blocked_array[++$#blocked_array] = $blocked_entry;
  }
  $sth->finish();
  $dbh->disconnect();

  return @blocked_array;
}

sub update_config {
  shift;
  my (%fraud_config_hash) = @_;

  my $username = $fraudtrack::username;

  my $config_string = "";
  if ($fraud_config_hash{'avs'} == -1) {
    delete $fraud_config_hash{'avs'};
  }
  foreach my $name (keys %fraud_config_hash) {
    $config_string .= $name . "\=" . $fraud_config_hash{$name} . "\,";
  }
  chop $config_string;

  my $db_query = "update customers set fraud_config=\'$config_string\' where username=\'$username\'";
  my $dbh = &miscutils::dbhconnect("pnpmisc");
  my $sth = $dbh->prepare(qq{$db_query});
  my $transaction_status = $sth->execute();
  $sth->finish();
  $dbh->disconnect();

}

sub update_entry {
  shift;
  my($table,$action,$block_list) = @_;
  my @block_list = split('\|',$block_list);

  $action = "update";

  my $username = $fraudtrack::username;

  my $dbh = &miscutils::dbhconnect("$fraudtrack::frauddb");
  my (%list);
  if ($action eq "update") {
    #foreach my $var (@block_list)  {
    #  $list{$var} = 1;
    #}
    #@$block_list = (keys %list);
    my $sth = $dbh->prepare(qq{
        delete from $table
        where username='$username'
    }) or die "failed prepare1.";
    my $transaction_status = $sth->execute() or die "failed execute.";
    $sth->finish();

    $sth = $dbh->prepare(qq{
        insert into $table (username,entry)
        values(?,?)
    }) or die "failed prepare.";
    foreach my $entryvalue (@block_list) {
     $sth->execute($username,$entryvalue);
    }
    $sth->finish;
  }
#  elsif ($action eq "add") {
#    my $sth = $dbh->prepare(qq{
#        insert into $table (username,entry)
#        values (?,?)
#    }) or die "failed insert prepare.";
#    $sth->execute($username,$block_list);
#    $sth->finish;
#  }
#  elsif ($action eq "remove") {
#    foreach my $entryvalue (@block_list) {
#      my $sth = $dbh->prepare(qq{
#          delete from $table
#          where username=? and entry=?
#       }) or die "failed prepare.";
#       $sth->execute("$username","$entryvalue") or die "failed execute.";
#       $sth->finish;
#    }
#  }
  $dbh->disconnect;

}


sub overview {  
  my($reseller,$merchant) = @_; 
  my ($db_merchant); 
           
  my $dbh = &miscutils::dbhconnect("pnpmisc");
       
  if ($reseller eq "cableand") {
    my $sth = $dbh->prepare(qq{
        select username 
        from customers 
        where reseller IN ('cableand','cccc','jncb','bdagov')
        and username='$merchant' 
        }) or die "Can't do: $DBI::errstr";
    $sth->execute or die "Can't execute: $DBI::errstr"; 
    ($db_merchant) = $sth->fetchrow; 
    $sth->finish; 
  }
  elsif ($reseller eq "volpayin") { 
    my $sth = $dbh->prepare(qq{
        select username  
        from customers 
        where processor='volpay'
        and username='$merchant'
    }) or die "Can't prepare: $DBI::errstr"; 
    $sth->execute or die "Can't execute: $DBI::errstr";
    ($db_merchant) = $sth->fetchrow;
    $sth->finish;
  }
  else {
    my $sth = $dbh->prepare(qq{
        select username
        from customers
        where reseller='$reseller' and username='$merchant'
        }) or die "Can't do: $DBI::errstr";
    $sth->execute or die "Can't execute: $DBI::errstr";
    ($db_merchant) = $sth->fetchrow;
    $sth->finish;
  }
 
  $dbh->disconnect;
 
  return $db_merchant;
 
}

sub overview {
  my($reseller,$merchant) = @_;
  my ($db_merchant);
   
  my $dbh = &miscutils::dbhconnect("pnpmisc");   
     
  if ($reseller eq "cableand") { 
    my $sth = $dbh->prepare(qq{
        select username 
        from customers 
        where reseller IN ('cableand','cccc','jncb','bdagov')
        and username='$merchant'
        }) or die "Can't do: $DBI::errstr"; 
    $sth->execute or die "Can't execute: $DBI::errstr";
    ($db_merchant) = $sth->fetchrow; 
    $sth->finish; 
  }
  else {
    my $sth = $dbh->prepare(qq{
        select username
        from customers
        where reseller='$reseller' and username='$merchant'
        }) or die "Can't do: $DBI::errstr";
    $sth->execute or die "Can't execute: $DBI::errstr";
    ($db_merchant) = $sth->fetchrow;
    $sth->finish;
  }
 
  $dbh->disconnect;
 
  return $db_merchant;
 
}

1;
