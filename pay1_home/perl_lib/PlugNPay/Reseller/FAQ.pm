package PlugNPay::Reseller::FAQ;

use strict;
use HTML::Entities;
use URI::Escape;
use PlugNPay::DBConnection;
use PlugNPay::InputValidator;
use PlugNPay::Environment;
use PlugNPay::Sys::Time;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  # Allows proper section names to be used easily
  $self->{'sections'} = $self->retrieveSections();

  return $self;
}

###############################
# Retrieve by Issue ID Number #
###############################
sub get {
  my $self = shift;
  my $issueID = uc(shift);
  my $storeSearch = shift;
  if (!defined $storeSearch){
    $storeSearch = 1;
  }

  unless ($issueID =~ /^[a-zA-Z]*/){
    $issueID = 'ID' . $issueID;
  }
 
  if (!defined $self->{'issues'} ){
    $self->loadIssues();
  }

  my $returnHash = $self->{'issues'}{$issueID};
  foreach my $sub (keys %$returnHash){
    $returnHash->{$sub} = $self->cleanData($returnHash->{$sub});
  }
  $returnHash->{'sectionTitle'} = $self->{'sections'}{$returnHash->{'category'}};

  if ($storeSearch) {
   $self->storeSearchTerm($issueID,1);
  }

  return $returnHash;
}

######################
# Search by Key Word #
######################
sub searchKeywords {
  my $self  = shift;
  my $words = shift;
  my $category = shift;
  my $storeSearch = shift;

  if (!defined $storeSearch){
    $storeSearch = 1;
  }
  my @keywords = split(',',$words);
  my $completedHash = {};

  if (!defined $self->{'issues'} ){
    $self->loadIssues();
  }

  if (defined $keywords[1] && $keywords[1] ne ''){

    foreach my $searchWord (@keywords){

      if (substr($searchWord,0,1) eq ' '){
        $searchWord = substr($searchWord,1);
      }

      my $wLen = length($searchWord);
      if(substr($searchWord,($wLen - 1),1) eq ' '){
        $searchWord = substr($searchWord,0,$wLen-1);
      }

      my $tempHash = $self->search($searchWord,$category,$storeSearch);
      foreach my $id (keys %$tempHash){
        if (!defined $completedHash->{$id}) {
          $completedHash->{$id} = $tempHash->{$id};
          $completedHash->{$id}{'matches'} = 1;
        } else {
          $completedHash->{$id}{'matches'} += 1;
        }
      }
    }

  } else {
    my $tempHash = $self->search($words,$category,$storeSearch);
    foreach my $id (keys %$tempHash){
        if (!defined $completedHash->{$id}) {
          $completedHash->{$id} = $tempHash->{$id};
          $completedHash->{$id}{'matches'} = 1;
        } else {
          $completedHash->{$id}{'matches'} += 1;
        }
      }

  }

  return $completedHash;
}

# Search and SearchKeywords were separated to ensure proper functionality
# Something weird was happening before the separation
sub search{
  my $self = shift;
  my $idSearch = 0;
  my $returnHash = {};
  my $searchWord = shift;
  my $category = shift;
  my $storeSearch = shift;
  if (!defined $storeSearch){
    $storeSearch = 1;
  }
 
  if (!defined $self->{'issues'} ){
    $self->loadIssues();
  }
  my $issues = $self->{'issues'};
  
  #Searched by Keyword and category
    foreach my $key (keys %{$issues}){
      my $questionIndex = index(uc($issues->{$key}{'question'}),uc($searchWord));
      my $keyWordIndex = index(uc($issues->{$key}{'keywords'}),uc($searchWord));
      my $answerIndex = index(uc($issues->{$key}{'answer'}),uc($searchWord));
      my $issueIDIndex = (uc($key) eq uc($searchWord) ? 1 : 0);

      if ($issueIDIndex) {
        $idSearch = 1;
      }

      if( $keyWordIndex != -1 || $questionIndex != -1 || $answerIndex != -1 || $issueIDIndex){

        my @questionArray = split(/\?/,$issues->{$key}{'question'});

        if($category ne 'all'){
          if ($issues->{$key}{'category'} eq $category){
            $returnHash->{$key}{'category'} = $category;
            $returnHash->{$key}{'issueID'} = $key;
            $returnHash->{$key}{'question'} = $issues->{$key}{'question'};
            $returnHash->{$key}{'keywords'} = $issues->{$key}{'keywords'};
            $returnHash->{$key}{'answer'} = $issues->{$key}{'answer'};
            $returnHash->{$key}{'sectionTitle'} = $self->{'sections'}{$category};
            if(defined $questionArray[1] && $questionArray[1] ne ' '){
              $returnHash->{$key}{'shortQuestion'} = $questionArray[0] . '...';
            } else {
              $returnHash->{$key}{'shortQuestion'} = $issues->{$key}{'question'};
            }
          }
        } else {
          $returnHash->{$key}{'category'} = $issues->{$key}{'category'};
          $returnHash->{$key}{'issueID'} = $key;
          $returnHash->{$key}{'question'} = $issues->{$key}{'question'};
          $returnHash->{$key}{'keywords'} = $issues->{$key}{'keywords'};
          $returnHash->{$key}{'answer'} = $issues->{$key}{'answer'};
          my $cat = $issues->{$key}{'category'};
          $returnHash->{$key}{'sectionTitle'} = $self->{'sections'}{$cat};
          if(defined $questionArray[1] && $questionArray[1] ne ' '){
            $returnHash->{$key}{'shortQuestion'} = $questionArray[0] . '...';
          } else {
            $returnHash->{$key}{'shortQuestion'} = $issues->{$key}{'question'};
          }
        }
      }
    } 
  
  if ($storeSearch) {
    $self->storeSearchTerm($self->cleanData($searchWord),$idSearch);
  }

  return $returnHash;
}

######################
# Search by Category #
######################
sub list {
  my $self = shift;
  my $iv = new PlugNPay::InputValidator();
  $iv->changeContext('reseller_faq');
  my $category = $iv->filter('ps_issue_category', shift);
  my $returnHash = {};

  if (!defined $self->{'issues'} ){
    $self->loadIssues();
  }  

  if(defined $category && $category ne 'all'){
    foreach my $key (keys %{$self->{'issues'}} ){
      if ($self->{'issues'}{$key}{'category'} = $category ) {
        $returnHash->{$key} = $self->{'issues'}{$key};
      }
    }
  } else {
    #all Categories
    $returnHash = $self->{'issues'};
  }

  return $returnHash;
}

#################################
# Read annoying 'Database' file #
#################################
sub loadIssues {
  my $self = shift;
  my $dbconn = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbconn->prepare(q/ SELECT id,category,question,answer,keywords
                                FROM faq_items
                              /); 
  $sth->execute();
  my $rows = $sth->fetchall_arrayref({});
  foreach my $row (@$rows){
    my $id = $row->{'id'};
    $self->{'issues'}{$id}{'category'} = $row->{'category'};
    $self->{'issues'}{$id}{'question'} = $row->{'question'}; 
    $self->{'issues'}{$id}{'answer'} = $row->{'answer'}; 
    $self->{'issues'}{$id}{'keywords'} = $row->{'keywords'};
    $self->{'issues'}{$id}{'issueID'} = $id;
  }

}

######################################
# Get Sections for Category Dropdown #
######################################
sub getSections {
  my $self = shift;
  
  return $self->{'sections'};
}

sub retrieveSections{
  my $self = shift;
  my $dbh = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbh->prepare(q/
                          SELECT category,description
                          FROM faq_select_sections
                          WHERE hidden = ? 
                          ORDER BY id ASC
                          /);
  $sth->execute(0);
  my $rows = $sth->fetchall_arrayref({});
  my $sections;
  foreach my $item (@$rows){
    $sections->{$item->{'category'}} = $item->{'description'};
  }
  return $sections;
}


#######################################################
# This cleans up the DB code, removes HTML and pipes  #
# Whoever designed that should be beaten with a stick #
#######################################################
sub cleanData {
  my $self = shift;
  my $data = encode_entities(shift);

  $data =~ s/<br>/\n/g;
  $data =~ s/&amp;/&/g;
  $data =~ s/&nbsp;/ /g;
  $data =~ s/&quot;/\"/g;
  $data =~ s/&lt;/</g;
  $data =~ s/&gt;/>/g;
  $data =~ s/&#39;/'/g;
  return uri_unescape($data);
}

sub storeSearchTerm {
  my $self = shift;
  my $searchTerm = lc(shift) || '';
  my $issueIDFlag = shift || 0;
  my $time = new PlugNPay::Sys::Time()->inFormat('yyyymmdd'); 
  if ($searchTerm ne '') { 
    my $dbconn = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
    my $sth = $dbconn->prepare(q/
                              INSERT INTO faq_search_stats
                              (term,date,count,is_issue_id)
                              VALUES (?,?,?,?)
                              ON DUPLICATE KEY UPDATE date=?, count = count + 1
                              /);
    $sth->execute($searchTerm,$time,1,$issueIDFlag,$time) or die $DBI::errstr;
    $sth->finish();
  }
  
}

sub addFAQIssue {
  my $self = shift;
  my $category = shift;
  my $question = shift;
  my $answer = shift;
  my $keywords = shift;
  my $id = uc shift;
  my @values = ($category,$question,$answer,$keywords);

  my $dbconn = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbconn->prepare(q/
                              INSERT INTO faq_items
                              (id,category,question,answer,keywords)
                              VALUES (?,?,?,?,?,?)
                              ON DUPLICATE KEY UPDATE category=?,question=?,answer=?,keywords=?
                              /);
  $sth->execute($id,@values,@values) or die $DBI::errstr;

  return 1;
}

sub deleteFAQIssue {
  my $self = shift;
  my $id = uc shift;
  
  my $dbconn = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbconn->prepare(q/
                              DELETE FROM faq_items 
                              WHERE id = ?
                             /);
  $sth->execute($id) or die $DBI::errstr;
  
  return 1;
}

sub mostSearched {
  my $self = shift;
  my $getIDsOnly = shift || 0;

  my $dbconn = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbconn->prepare(q/
                              SELECT term
                              FROM faq_search_stats
                              WHERE is_issue_id = ? 
                              ORDER BY count DESC
                              LIMIT 25
                              /);
  $sth->execute($getIDsOnly);
  my $rows = $sth->fetchall_arrayref({});
  return $rows;
}

1;
