package PlugNPay::Legacy::MckUtils::Receipt;

use strict;
use PlugNPay::WebDataFile;
use PlugNPay::Features;

sub getReceipt {
  my $input = shift;

  my $data = $input->{'mckutils_merged'};
  my $reseller = $input->{'reseller'};
  my $table = $input->{'tableContent'};
  my $ruleIds = $input->{'ruleIds'} || []; # optional
  my $templateContent = $input->{'templateContent'}; # optional

  # ensure auth code is only 6 characters to prevent data leakage
  $data->{'auth-code'} = substr($data->{'auth-code'},0,6);

  my $isAch = (($data->{'routingnum'} =~ /\d{9}/) || ($data->{'micr'} =~ /\w/));

  my $templateType;
  if ( $data->{'FinalStatus'} =~ /^(success|pending)$/ ) {
    $templateType = "thankyou";
  } elsif ( $data->{'FinalStatus'} =~ /^(badcard|fraud)$/ ) {
    $templateType = "badcard";
  } else {
    $templateType = $data->{'FinalStatus'} || '';
  }

  # ensure that $ruleIds is an array reference
  if (ref($ruleIds) ne 'ARRAY') {
    $ruleIds = [];
  }

  my $username = $data->{'merchant'} || $data->{'publisher_name'} || $data->{'publisher-name'};
  my $features = new PlugNPay::Features($username,'general');
  my $cobrand = $features->get('cobrand');

  my $receipt = _generateReceipt({
    templateType => $templateType,
    client => $data->{'client'},
    mode => $data->{'mode'},
    username => $username,
    reseller => $reseller,
    cobrand => $cobrand,
    receiptType => $data->{'receipt_type'} || $data->{'receipt-type'},
    payMethod => $data->{'paymethod'},
    isAch => $isAch,
    templateName => $data->{'paytemplate'},
    ruleIds => $ruleIds,
    templateContent => $templateContent
  },{
    query => $data,
    tableContent => $table
  });

  return $receipt;
}

sub _generateReceiptLoadRules {
  my $receiptTemplateInfo = shift;

  my $username = $receiptTemplateInfo->{'username'};
  my $reseller = $receiptTemplateInfo->{'reseller'};
  my $cobrand  = $receiptTemplateInfo->{'cobrand'};
  my $mode   = $receiptTemplateInfo->{'mode'};
  my $client = $receiptTemplateInfo->{'client'};
  my $templateType = $receiptTemplateInfo->{'templateType'};
  my $requestedTemplateName = $receiptTemplateInfo->{'templateName'};
  my $payMethod = $receiptTemplateInfo->{'payMethod'};
  my $isAch = $receiptTemplateInfo->{'isAch'};
  my $receiptType = $receiptTemplateInfo->{'receiptType'};

  my @webDataInfo;

  ##########################
  # Mobile Level Templates #
  ##########################
  if ($client =~ /mobile/) {
    push @webDataInfo, {
      rule => 1.1,
      fileName => sprintf('%s.html' ,$username),
      subPrefix => sprintf('%s/%s/',$client,$templateType)
    };

    if ($receiptType ne '') {
      push @webDataInfo, {
        rule => 2.1,
        fileName => sprintf('%s.htm',$reseller),
        subPrefix => sprintf('%s/%s/',$client,$templateType)
      };
    }

    push @webDataInfo, {
      rule => 3.1,
      fileName => 'mobile.html',
      subPrefix => sprintf('%s/%s/',$client,$templateType)
    };
  } elsif ($client eq 'iphone') {
    push @webDataInfo, {
      rule => 4.1,
      fileName => 'iphone.htm',
      subPrefix => sprintf('%s/',$templateType)
    };
  }

  ##################################
  # SMPS/virtualterminal templates #
  ##################################
  if ($mode ne '') {
    if ($isAch) { # ach templates
      push @webDataInfo, {
        rule => 5.1,
        fileName => sprintf('%s_ach_%s.htm' ,$username,$mode),
        subPrefix => sprintf('virtualterm/%s/', $templateType)
      };

      if ($cobrand) {
        push @webDataInfo, {
          rule => 6.1,
          fileName => sprintf('%s_ach_%s.htm' ,$cobrand,$mode),
          subPrefix => sprintf('virtualterm/cobrand/%s/', $templateType)
        }; # This is preferred over rule 6.2

        push @webDataInfo, {
          rule => 6.2,
          fileName => sprintf('%s_ach_%s.htm' ,$cobrand,$mode),
          subPrefix => sprintf('virtualterm/%s/cobrand/', $templateType)
        }; # left for compatibility, to load existing templates
      }
    } else {
      push @webDataInfo, {
        rule => 7.1,
        fileName => sprintf('%s_%s.htm' ,$username,$mode),
        subPrefix => sprintf('virtualterm/%s/', $templateType)
      };

      if ($cobrand) {
        push @webDataInfo, {
          rule => 8.1,
          fileName => sprintf('%s_%s.htm' ,$cobrand,$mode),
          subPrefix => sprintf('virtualterm/cobrand/%s/', $templateType)
        }; # This is preferred over rule 8.2

        push @webDataInfo, {
          rule => 8.2,
          fileName => sprintf('%s_%s.htm' ,$cobrand,$mode),
          subPrefix => sprintf('virtualterm/%s/cobrand/', $templateType)
        }; # left for compatibility, to load existing templates
      }
    }
  }

  ############################
  # merchant level templates #
  ############################

  # POS templates
  if ($receiptType =~ /^pos_/) {
    if ($requestedTemplateName ne '') { # only check theseif $requestedTemplateName is set, to reduce the number of potential GETs to s3
      if ($isAch) { # ach templates
        push @webDataInfo, {
          rule => 9.1,
          fileName => sprintf('%s_ach_pos_%s.htm' , $username, $requestedTemplateName),
          subPrefix => sprintf('%s/', $templateType)
        };
      }

      push @webDataInfo, {
        rule => 10.1,
        fileName => sprintf('%s_pos_%s.htm', $username, $requestedTemplateName),
        subPrefix => sprintf('%s/', $templateType)
      };
    }

    if ($isAch) {
      push @webDataInfo, {
        rule => 11.1,
        fileName => sprintf('%s_ach_pos.htm' , $username),
        subPrefix => sprintf('%s/', $templateType)
      };
    }

    push @webDataInfo,   {
      rule => 12.1,
      fileName => sprintf('%s_pos.htm' , $username),
      subPrefix => sprintf('%s/', $templateType)
    };
  }

  # Receipt template type requested other than pos?
  if ($receiptType ne '') {
    if ($requestedTemplateName ne '') { # only check theseif $requestedTemplateName is set, to reduce the number of potential GETs to s3
      if ($isAch) { # ach templates
        push @webDataInfo, {
          rule => 13.1,
          fileName => sprintf('%s_ach_std_%s.htm' , $username, $requestedTemplateName),
          subPrefix => sprintf('%s/', $templateType)
        };
      }

      push @webDataInfo,   {
        rule => 14.1,
        fileName => sprintf('%s_std_%s.htm' , $username, $requestedTemplateName),
        subPrefix => sprintf('%s/', $templateType)
      };
    }

    if ($isAch) {
      push @webDataInfo, {
        rule => 15.1,
        fileName => sprintf('%s_ach_std.htm' , $username),
        subPrefix => sprintf('%s/', $templateType)
      };
    }

    push @webDataInfo,   {
      rule => 16.1,
      fileName => sprintf('%s_std.htm' , $username),
      subPrefix => sprintf('%s/', $templateType)
    };
  }


  # no receipt type specified...also defaults
  if ($requestedTemplateName ne '') {
    if ($isAch) { # ach templates
      push @webDataInfo, {
        rule => 17.1,
        fileName => sprintf('%s_ach_%s.htm' , $username, $requestedTemplateName),
        subPrefix => sprintf('%s/', $templateType)
      };
    }

    push @webDataInfo,   {
      rule => 18.1,
      fileName => sprintf('%s_%s.htm' , $username, $requestedTemplateName),
      subPrefix => sprintf('%s/', $templateType)
    };
  }

  if ($isAch) {
    push @webDataInfo, {
      rule => 19.1,
      fileName => sprintf('%s_ach.htm' , $username),
      subPrefix => sprintf('%s/', $templateType)
    };
  }

  push @webDataInfo,   {
    rule => 20.1,
    fileName => sprintf('%s.htm' , $username),
    subPrefix => sprintf('%s/', $templateType)
  };

  push @webDataInfo,   {
    rule => 21.1,
    fileName => sprintf('%s_%s.htm' , $username, $payMethod),
    subPrefix => sprintf('%s/', $templateType)
  };

  # Cobrand
  if ($cobrand ne '') {
    if ($isAch) {
      push @webDataInfo, {
        rule => 22.1,
        fileName => sprintf('%s_ach.htm' , $cobrand),
        subPrefix => sprintf('%s/cobrand/', $templateType)
      };
    }

    push @webDataInfo,   {
      rule => 23.1,
      fileName => sprintf('%s.htm' , $cobrand),
      subPrefix => sprintf('%s/cobrand/', $templateType)
    };
  }

  # reseller
  if ($receiptType =~ /^pos_/) {
    if ($isAch) { # ach templates
      push @webDataInfo, {
        rule => 24.1,
        fileName => sprintf('%s_ach_pos.htm' , $reseller),
        subPrefix => sprintf('%s/', $templateType)
      };
    }

    push @webDataInfo,   {
      rule => 25.1,
      fileName => sprintf('%s_pos.htm' , $reseller),
      subPrefix => sprintf('%s/', $templateType)
    };
  }

  if ($receiptType ne '') {
    if ($isAch) {
      push @webDataInfo, {
        rule => 26.1,
        fileName => sprintf('%s_ach_std.htm' , $reseller),
        subPrefix => sprintf('%s/', $templateType)
      };
    }

    push @webDataInfo,   {
      rule => 27.1,
      fileName => sprintf('%s_std.htm' , $reseller),
      subPrefix => sprintf('%s/', $templateType)
    };
  }

  return \@webDataInfo;
}

sub _generateReceipt {
  my $receiptTemplateInfo = shift || {};
  my $substitutions = shift || {};

  my $templateType = $receiptTemplateInfo->{'templateType'};
  my $client = $receiptTemplateInfo->{'client'};
  my $mode   = $receiptTemplateInfo->{'mode'};
  my $username = $receiptTemplateInfo->{'username'};
  my $reseller = $receiptTemplateInfo->{'reseller'};
  my $receiptType = $receiptTemplateInfo->{'receiptType'};
  my $payMethod   = $receiptTemplateInfo->{'payMethod'};
  my $cobrand = $receiptTemplateInfo->{'cobrand'};
  my $isAch = $receiptTemplateInfo->{'isAch'};
  my $requestedTemplateName = $receiptTemplateInfo->{'templateName'};
  my %ruleIds = map { $_ => 1 } @{$receiptTemplateInfo->{'ruleIds'} || []};
  my $templateContent = $receiptTemplateInfo->{'templateContent'};

  my $query = $substitutions->{'query'};
  my $table = $substitutions->{'tableContent'};

  if (!defined $templateContent || $templateContent eq '') {
    my $templateRules = _generateReceiptLoadRules($receiptTemplateInfo);

    my $wdf = new PlugNPay::WebDataFile();

    my $ruleIdsCount = keys %ruleIds;

    foreach my $info (@{$templateRules}) {
      if ($ruleIdsCount == 0 || $ruleIds{$info->{'rule'}}) {
        $templateContent = $wdf->readFile({
          fileName => $info->{'fileName'},
          storageKey => 'merchantAdminTemplates',
          subPrefix => $info->{'subPrefix'}
        });
        if ($templateContent ne '') {
          last;
        }
      }
    }
  }


  while ($templateContent =~ /\[pnp_([a-zA-Z0-9\-\_]*)\]/) {
    my $value = $query->{$1};
    $templateContent =~ s/\[pnp_([a-zA-Z0-9\-\_]*)\]/$value/;
  }
  $templateContent =~ s/\[TABLE\]/$table/g;

  return $templateContent;
}

1;
