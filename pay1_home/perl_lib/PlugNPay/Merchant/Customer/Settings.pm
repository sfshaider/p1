package PlugNPay::Merchant::Customer::Settings;

use PlugNPay::DBConnection;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  $self->_load();
  return $self;
}

sub setSetting {
  my $self = shift;
  my $key = shift;
  my $value = shift;
  $self->{'settings'}{$key} = $value;
}

sub getSetting {
  my $self = shift;
  my $key = shift;
  return $self->{'settings'}{$key};
}

sub _load {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $rows = $dbs->fetchallOrDie('merchant_cust',
    q/SELECT `key`, `value`
      FROM global_settings/, [], {})->{'result'};
  if (@{$rows} > 0) {
    foreach my $row (@{$rows}) {
      $self->{'dbExists'}{$row->{'key'}} = 1;
      $self->{'settings'}{$row->{'key'}} = $row->{'value'};
    }
  }
}

sub save {
  my $self = shift;
  my $newSettings = $self->{'settings'};
  if (keys %{$newSettings} > 0) {
    my @params = ();
    my @placeholders = ();
    foreach my $settingKey (keys %{$newSettings}) {
      if (!$self->{'dbExists'}{$settingKey}) {
        push (@params, $settingKey, $newSettings->{$settingKey});
        push (@placeholders, '(?,?)');
      }
    }

    if (@params > 0) {
      my $dbs = new PlugNPay::DBConnection();
      $dbs->executeOrDie('merchant_cust',
        q/INSERT INTO global_settings ( `key`, `value` )
          VALUES / . join(',', @placeholders), \@params);
    }
  }
}

1;
