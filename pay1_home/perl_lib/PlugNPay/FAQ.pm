package PlugNPay::FAQ;

########### PlugNPay::FAQ ###########
# Handles legacy style FAQ board    #
# Use submodule for different areas #
#                                   #
# Submodules:                       #
# Helpdesk (Admin)                  #
# Billpay (Billpay/Billpres)        #
# Reseller (Reseller obviously)     #
#                                   #
#####################################

use strict;
use PlugNPay::Environment;
use PlugNPay::WebDataFile;
use PlugNPay::Logging::DataLog;
use PlugNPay::Reseller;
use PlugNPay::GatewayAccount;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  return $self;
}

sub searchItems {
  my $self = shift;
  my $options = shift || {};

  # Load file
  my $fileName = $self->_getFAQFileName();
  my $relativePath = $self->_getFAQRelativePath();
  my $pathArea = $self->_getFAQFileArea($fileName);
  my $fileData = $self->_readFAQFile($pathArea, $relativePath, $fileName);

  # Get search critieria 
  my $searchKeys = $options->{'searchKeys'} || [];
  my $searchCategory = $options->{'category'} || 'all';
  my $exclusions = $options->{'exclusions'} || [];
  my $minimumMatch = $options->{'minimumMatchPercentage'};
  my $matchesFound = 0;
  my $searchKeyCount = @{$searchKeys};

  # Do search
  my $responseHash = {};
  my $prevRowColorSwitch = '0';
  foreach my $line (split("\n", $fileData)) {
    my ($category, $question, $answer, $keywords, $qaNumber) = split(/\t/, $line);
    my $matches = 0;
    my $count = 0;
    my $exclusionMatch = 0;
    my $matchPercentage = 0;

    if ($searchCategory eq $category || $searchCategory eq 'all') {
      if ($searchKeyCount == 0) {
        $matches = 1;
        $count++;
      } else {
        foreach my $searchWord (@{$searchKeys}) {
          if ($question =~ /$searchWord/i || $answer =~ /$searchWord/i || $keywords =~ /$searchWord/i || $qaNumber =~ /$searchWord/i) {
            $matches = 1;
            $count++;
          } 
        } 
        
        foreach my $excluded (@{$exclusions}) {
          if ($question =~ /$excluded/i || $answer =~ /$excluded/i || $keywords =~ /$excluded/i || $qaNumber =~ /$excluded/i) {
            $exclusionMatch = 1;
          }
        }
      }
    }

    if (!$exclusionMatch && $matches) {
      $matchesFound++;
      if ($searchKeyCount) {
        $matchPercentage = ($count / $searchKeyCount) * 100;
        $matchPercentage = $matchPercentage > 100 ? 100 : $matchPercentage;
      }
    }

    my $rowColorSwitch = $self->_getRowColorSwitch($prevRowColorSwitch);
    $category =~ s/(\t|\n|\r)//g;
    $question =~ s/(\t|\n|\r)//g;
    $qaNumber =~ s/(\t|\n|\r)//g;
    $responseHash->{$qaNumber} = {
      'rowColorSwitch'  => $rowColorSwitch,
      'matchColor'      => $self->_getMatchColor($matchPercentage),
      'matchCount'      => $count,
      'keyCount'        => $searchKeyCount,
      'rowThatMatches'  => [$category, $question, $answer, $keywords, $qaNumber],
      'matchPercentage' => $matchPercentage,
      'inMatchBounds'   => $matchPercentage >= $minimumMatch
    };

    $prevRowColorSwitch = $rowColorSwitch;
  }
  
  return $responseHash;
}

sub addItem {
  my $self = shift;  
  my $termData = shift;

  if (ref($termData) ne 'HASH') {
    die 'Missing required term data, cannot add to FAQ!' . "\n";
  }
  my $fileName = $self->_getFAQFileName();
  my $relativePath = $self->_getFAQRelativePath();
  my $pathArea = $self->_getFAQFileArea($fileName);

  my $qaNum = $self->generateQAIdentifier();
  my $newTerm = [
    $termData->{'category'},
    $termData->{'question'},
    $termData->{'answer'},
    $termData->{'keywords'},
    $qaNum
  ];

  my $currentFile = $self->_readFAQFile($pathArea, $relativePath, $fileName);
  $currentFile = join("\t", @{$newTerm}) . "\n" . $currentFile;
  my $writeErr = $self->_writeFAQFile($pathArea, $relativePath, $fileName, $currentFile);

  if (wantarray) {
    return $writeErr, $qaNum;
  }

  return $writeErr;
}

sub deleteItem {
  my $self = shift;
  my $searchQANumber = shift || die 'No QA Identifier sent for deletion!' . "\n";

  # Load file
  my $fileName = $self->_getFAQFileName();
  my $relativePath = $self->_getFAQRelativePath();
  my $pathArea = $self->_getFAQFileArea($fileName);
  my $fileData = $self->loadFAQFile($pathArea, $relativePath, $fileName);

  # read file contents into memory
  my @newFile = ();
  foreach my $line (split("\n", $fileData)) {
    my ($category, $question, $answer, $keywords, $qaNumber) = split(/\t/, $line);
    if ($qaNumber eq $searchQANumber) {
      # when reached file question, skip it, else write the data
      push @newFile, $line;
    }
    # contine to read rest of file contents
  }

  return $self->writeFile($pathArea, $relativePath, $fileName, join("\n", @newFile));
}

sub updateItem {
  my $self = shift;
  my $updateOptions = shift;
  my $termData = $updateOptions->{'termData'};
  
  if (ref($termData) ne 'HASH' || $updateOptions->{'qaNumber'} !~ /^QA\d{14}$/) {
    $self->log({'method' => 'updateFAQ', 'updateOptions' => $updateOptions});
    die 'Invalid data sent to updateItem!' . "\n";
  }
  # Load file
  my $fileName = $self->_getFAQFileName();
  my $relativePath = $self->_getFAQRelativePath();
  my $pathArea = $self->_getFAQFileArea($fileName);
  my $fileData = $self->loadFAQFile($pathArea, $relativePath, $fileName);

  my @finalFile = ();
  foreach my $line (split("\n",$fileData)) {
    my ($category, $question, $answer, $keywords, $qaNumber) = split(/\t/, $line);
    if ($updateOptions->{'qaNumber'} eq $qaNumber) {
      my @newLine = (
        $termData->{'category'},
        $termData->{'question'},
        $termData->{'answer'},
        $termData->{'keywords'},
        $qaNumber
      );
      push @finalFile, join("\t", @newLine);
    } else {
      push @finalFile, $line;
    }
  }

  my $writeErr =  $self->writeFile($pathArea, $relativePath, $fileName, join("\n", @finalFile));
   
  if (wantarray) {
    return $writeErr, $updateOptions->{'qaNumber'};
  }

  return $writeErr;
}

sub viewAnswer {
  my $self = shift;
  my $searchQANumber = shift || die 'No answer identifier sent!' . "\n";

  # Load file
  my $fileName = $self->_getFAQFileName();
  my $relativePath = $self->_getFAQRelativePath();
  my $pathArea = $self->_getFAQFileArea($fileName);
  my $fileData = $self->loadFAQFile($pathArea, $relativePath, $fileName);

  my ($category, $question, $answer, $keywords, $qaNumber);
  foreach my $line (split("\n", $fileData)) {
    ($category, $question, $answer, $keywords, $qaNumber) = split(/\t/, $line);
    $category =~ s/(\t|\n|\r)//g;
    $question =~ s/(\t|\n|\r)//g;
    $qaNumber =~ s/(\t|\n|\r)//g;
    if ($qaNumber eq $searchQANumber) {
      last;
    }
  }

  # Am I cool now?
  if (wantarray) {
    return $category, $question, $answer, $keywords, $qaNumber;
  }

  return [$category, $question, $answer, $keywords, $qaNumber];
}

# Generate Question/Answer identifier
sub createQAIdentifier {
  my $time = new PlugNPay::Sys::Time();
  return 'QA' . $time->nowInFormat('gendatetime');
}

sub loadHelpFile {
  my $self = shift;
  my $fileName = $self->_getFAQFileName('help');
  my $relativePath = $self->_getFAQRelativePath();
  my $pathArea = $self->_getFAQFileArea($fileName);
  return $self->loadFAQFile($pathArea, $relativePath, $fileName);
}

sub loadActivityFile {
  my $self = shift;
  my $fileName = $self->_getFAQFileName('activity');
  my $relativePath = $self->_getFAQRelativePath();
  my $pathArea = $self->_getFAQFileArea($fileName);
  return $self->loadFAQFile($pathArea, $relativePath, $fileName);
}


sub _getMatchColor {
  my $self = shift;
  my $matchPercentage = shift || 0;
  my $color = '000000';

  if ($matchPercentage >= 75) {
    $color = 'ff0000';
  } elsif ($matchPercentage < 75 && $matchPercentage >= 50){
    $color = '00dd00';
  } elsif ($matchPercentage < 50 && $matchPercentage >= 25) {
    $color = '0000dd';
  }

  return $color;
}

sub _getRowColorSwitch {
  my $self = shift;
  my $prevColor = shift;
  return $prevColor eq '1' ? '0' : '1';
}

sub _getFAQFileArea {
  my $self = shift;
  my $fileName = shift;

  my $area;
  if ($fileName eq 'faq.db') {
    $area = 'webtxt';
  } elsif ($fileName eq 'faq_help.htm' || $fileName eq 'faq_most_active.htm') {
    $area = 'web';
  }

  return $area;
}

sub _getFAQRelativePath {
  die "Not implemented in submodule!\n"
}

sub _getFAQFileName {
  my $self = shift;
  my $file = shift;

  my $fileName = 'faq.db';
  if ($file eq 'activity') {
    $fileName = 'faq_most_active.htm';
  } elsif ($file eq 'help') { 
    $fileName = 'faq_help.htm';
  }

  return $fileName;
}

sub _readFAQFile {
  my $self = shift;
  my $fileArea = shift;
  my $relativePath = shift || '/';
  my $fileName = shift;
  my $absolutePath = $self->getPathRoot($fileArea) . $relativePath; 
  $absolutePath =~ s/\/+/\//g;
  $absolutePath =~ s/\/$//;

  if ($absolutePath eq '/' || ($fileName eq '' || $fileName =~ /^\s+$/ || !defined $fileName)) {
    die 'Invalid file name or path sent to FAQ read' . "\n";
  }
  
  my $fileManager = new PlugNPay::WebDataFile();
  my $data = $fileManager->readFile({
    'localPath' => $absolutePath,
    'fileName'  => $fileName
  });

  return $data;
}

sub _writeFAQFile {
  my $self = shift;
  my $fileArea = shift;
  my $relativePath = shift || '/';
  my $fileName = shift;
  my $fileData = shift;

  my $absolutePath = $self->getPathRoot($fileArea) . $relativePath;
  $absolutePath =~ s/\/+/\//g;
  $absolutePath =~ s/\/$//;

  if ($absolutePath eq '/' || ($fileName eq '' || $fileName =~ /^\s+$/ || !defined $fileName)) {
    die 'Invalid file name or path sent to FAQ read' . "\n";
  } elsif (!defined $fileData || $fileData eq '' || $fileData =~ /^\s+$/) {
    die 'No data sent to write to file' . "\n";
  }

  my $fileManager = new PlugNPay::WebDataFile();
  my $error = $fileManager->writeFile({
    'localPath' => $absolutePath,
    'fileName'  => $fileName,
    'content'   => $fileData
  });

  return $error;
}

sub getPathRoot {
  my $self = shift;
  my $dir = lc shift;

  my $env = new PlugNPay::Environment();
  my $path;
  if ($dir eq 'webtxt') {
    $path = $env->get('PNP_WEB_TXT') || '/home/pay1/webtxt/'; 
  } elsif ($dir eq 'web') {
    $path = $env->get('PNP_WEB') || '/home/pay1/web/';
  } else {
    die 'No valid directory found for ' . $dir . "\n";
  }

  $path =~ s/\/p\//\//;
  $path .= '/' if $path !~ /\/$/;

  return $path;
}

sub log {
  die "Not implemented in submodule!\n"
}

1;
