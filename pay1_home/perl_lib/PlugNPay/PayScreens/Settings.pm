package PlugNPay::PayScreens::Settings;

###
# Module for setting elements to db table pnpmisc::ui_payscreens_general_settings.
#
# Methods:
#  setGeneralSettings($upload_type, $file_url, $username => $element);
#  getGeneralSettings($username, $settingName);
#


sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  return $self;
}

sub setGeneralSettings {
  my $self = shift;
  my ($upload_type, $file_url, $username) = @_;
  my $settingName;

  if ($upload_type eq 'logos') {
    $settingName = 'logoURL';

  } elsif ($upload_type eq 'backgrounds') {
    $settingName = 'backgroundURL';
  }

  my $dbh = PlugNPay::DBConnection::database('pnpmisc');

  if (defined $settingName) {
    my $sth_pay_settings = $dbh->prepare(q{
        DELETE
          FROM ui_payscreens_general_settings
         WHERE type=?
           AND identifier=?
           AND setting_name=?
      }) or die($DBI::errstr);

    if ($sth_pay_settings) {
      $sth_pay_settings->execute('account', $username, $settingName) or die($DBI::errstr);
    }

    $sth_pay_settings = $dbh->prepare(q{
        INSERT
          INTO ui_payscreens_general_settings
               (type,identifier,setting_name,setting_value)
        VALUES (?,?,?,?)
      }) or die($DBI::errstr);

    if ($sth_pay_settings) {
      $sth_pay_settings->execute('account', $username, $settingName, $file_url) or die($DBI::errstr);
    }
  }
}

sub getGeneralSettings {
  my $self = shift;
  my $select = q/ SELECT setting_value
                    FROM ui_payscreens_general_settings
                   WHERE identifier=?
                     AND setting_name=? /;
  my $dbs = new PlugNPay::DBCOnnection();
  my $rows = $dbs->fetchallOrDie('pnpmisc', $select,[$username, $settingName], {})->{'result'};

  return $rows;
}
1;
