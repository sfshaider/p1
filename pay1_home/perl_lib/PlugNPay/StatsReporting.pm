package PlugNPay::StatsReporting;

use PlugNPay::Database;
use PlugNPay::DBConnection;
use strict;

sub new {
  my $type = shift;

  return [], $type;
}

sub queryTrans_log {
  my $this = shift;
  my $startdate = shift;

  my %reseller_hash = ();
  my($reseller_records_arrayref);

  my @requestedData = ('username','operation','finalstatus','accttype','substr(amount,1,3)','count(username)', 'sum(substr(amount,4))');
  my @params = ('trans_date',"$startdate",'operation',['auth','postauth','return'],'finalstatus',['success','badcard','problem','fraud','pending']);
  my @orderby = ();
  my @groupby = ('username','operation','finalstatus','accttype','substr(amount,1,3)');

  my $dbase = new PlugNPay::Database();
  my @results = $dbase->databaseQuery('pnpdata','trans_log',\@requestedData,\@params,\@orderby,\@groupby);

  return \@results;
}

sub storeStats {
  my $this = shift;
  my $trans_date = shift;
  my $stats = shift;
  my $reseller_hash = shift;

  my ($payment_type);

  my $dbase = new PlugNPay::Database();

  foreach my $data (@$stats) {
    if ($data->{'username'} eq "") {
      next;
    }
    if ($data->{'accttype'} =~ /checking|savings/) {
      $payment_type="ach";
    }
    elsif ($data->{'accttype'} =~ /^seqr/) {
      $payment_type="seqr";
    }
    else {
      $payment_type="credit";
    }
    my $currency = $data->{'substr(amount,1,3)'};
    if ($currency !~ /[a-z]{3}/) {
      $currency = "NA";
    }

    ## Delete records for merchant for given day
    my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

    my $sth = $dbh->prepare(qq{
        delete from merchant_reporting_stats
        where username=? and trans_date=? 
      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
    $sth->execute($data->{'username'},$trans_date) or die "Can't execute: $DBI::errstr";
    $sth->finish;

    ## Insert
    my %insertData = ('username',$data->{'username'},'trans_date',$trans_date,'operation',$data->{'operation'},'status',$data->{'finalstatus'},'transaction_count',$data->{'count(username)'},
                    'transaction_sum',$data->{'sum(substr(amount,4))'},'currency',$currency,'payment_type',$payment_type);
    $dbase->databaseInsert('pnpmisc','merchant_reporting_stats',\%insertData);
  }

  return;



}

sub queryStats {
  my $this = shift;
  my $startdate = shift;

  my @requestedData = ('username','trans_date','operation','status','transaction_count','transaction_sum','payment_type','currency');
  my @params = ('trans_date',"$startdate");
  my @orderby = ();
  my @groupby = ();
  
  my $dbase = new PlugNPay::Database();
  my @results = $dbase->databaseQuery('pnpmisc','merchant_reporting_stats',\@requestedData,\@params,\@orderby,\@groupby);

  return \@results;
}

sub getResellerList {
  my $this = shift;
  my $username_array = shift;

  my @requestedData = ('username','reseller');
  my @params = ('username',$username_array,'status',['live','debug','test']);
  my @orderby=();
  my @groupby=();

  my $dbase = new PlugNPay::Database();
  my @results = $dbase->databaseQuery('pnpmisc','customers',\@requestedData,\@params,\@orderby,\@groupby);

  return \@results;
}

sub __clear_merchant_stats {
  my $this = shift;

  ### Only Here for Testing
  my $dbh_misc = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
  my $sth = $dbh_misc->prepare(qq{
      delete from merchant_reporting_stats
    }) or die "Can't prepare: $DBI::errstr";
  $sth->execute() or die "Can't execute: $DBI::errstr";
  $sth->finish;
  $dbh_misc->disconnect;
}

1;
