package PlugNPay::API::REST::Documentation;

use strict;
use PlugNPay::API::REST::Documentation::JSON;
use PlugNPay::DBConnection;
use PlugNPay::UI::Template;
use JSON::XS;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $path = shift; 
  if(defined $path) { 
    $self->setResourcePath($path);
  } 

  return $self;
}

sub setResourcePath {
  my $self = shift;
  my $path = shift;
  $path =~ s/\/[\/]*/\//g;
  if (substr($path,0,1) ne '/') {
    $path = '/' . $path;
  }
  $self->{'path'} = $path;
}

sub getResourcePath {
  my $self = shift;
  return $self->{'path'};
}

sub getSubDirectories {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $root = $self->getRootPath();
  my $path = $self->{'path'} . '%';
  my $sth;

  if (defined $root) {
    $sth = $dbs->prepare(q/
                          SELECT resource
                          FROM api_url
                          WHERE resource LIKE ? AND root = ? AND public = ?
                          ORDER BY resource ASC
                          /); 
    $sth->execute($path,$root,1);

  } else {
    $sth = $dbs->prepare(q/
                          SELECT resource
                          FROM api_url
                          WHERE resource LIKE ? AND public = ?
                          ORDER BY resource ASC
                          /); 
    $sth->execute($path,1);
  }
  my $rows = $sth->fetchall_arrayref({});
  my @paths = ();
  foreach my $row (@{$rows}) {
    my @resources = split ('/',substr($row->{'resource'},length($self->{'path'})));
    my $singleDepthResource = $self->{'path'} . '/' . $resources[1];
    if($singleDepthResource ne $self->{'path'} && !grep( /^$singleDepthResource$/, @paths ) && $resources[1]) {
      #only insert if uniqe and not original path, this eleminates problems if root isn't passed
      push @paths,$singleDepthResource;
    }
  }
 
  return \@paths;
}

sub loadSchemas {
  my $self = shift;
  my $data = {};
  my @actions = ('OUTPUT','DELETE','UPDATE','CREATE','OPTIONS');
  my $JSON;

  foreach my $action (@actions) {
    my $schema = $self->getSchema($action);
    eval{$JSON = JSON::XS->new->utf8->decode($schema)};

    unless($@) {
      if (defined $schema && $schema ne ''){
        if ($self->getSchemaName() eq 'freeform') {
          $data->{'specs'}{$action}{'JSON'} = 'No specifications set';
        } else {
          $data->{'specs'}{$action} = $self->getSchemaSpecs(JSON::XS->new->utf8->decode($schema),'',0,'');
        }
      } 
    } else {
      if (defined $schema && $schema ne '') {
        $data->{'specs'}{$action}{'JSON'} = 'Bad schema format, cannot display specification';
      }
    }

    $data->{'examples'}{$action} = $self->getTestData($action);
  }
  
  return $data;
}

sub getSchema {
  my $self = shift;
  my $action = shift;  
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbs->prepare(q/
                           SELECT `schema`
                           FROM api_schema
                           WHERE schema_name = ? AND mode = ?
                           /);
  $sth->execute($self->getSchemaName(),$action) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});

  return $rows->[0]{'schema'};

}

sub getTestData {
  my $self = shift;
  my $action = shift;
  my $data = {};

  $data->{'JSON'} = new PlugNPay::API::REST::Documentation::JSON()->getTestData($action,$self->getSchemaName());
 
  return $data;
}

sub getSchemaSpecs {
  my $self = shift;
  my $schema = shift;
  my $lastKey = shift;
  my $opacity = shift || 0.1;
  my $keyPath = shift || '';
  my $spec = {
    'JSON' => new PlugNPay::API::REST::Documentation::JSON()->getSchemaSpecs($schema,$lastKey,$opacity,$keyPath),
  };


  return $spec;
}

sub getSchemaName {
  my $self = shift;
  my $schemaName = $self->{'schema_name'};
  if (!defined $schemaName){
    my $id = $self->getIDFromPath();
    my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
    my $sth = $dbs->prepare(q/
                           SELECT schema_name
                           FROM api_responder
                           WHERE id = ?
                           /);
    $sth->execute($id) or die $DBI::errstr;
    my $rows = $sth->fetchall_arrayref({});

    $schemaName = $rows->[0]{'schema_name'};
  }
  return $schemaName;
}

sub getIDFromPath{
  my $self = shift;
  my $id = $self->{'path_id'};

  if (!defined $id) {
    my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
    my $sth = $dbs->prepare(q/
                           SELECT responder_id
                           FROM api_url
                           WHERE resource=? AND root = ?
                           /);
    $sth->execute($self->getResourcePath(),$self->getRootPath()) or die $DBI::errstr;
    my $rows = $sth->fetchall_arrayref({});
    $id = $rows->[0]{'responder_id'};
  }

  return $id;
}

sub setRootPath {
  my $self = shift;
  my $root = shift;
  $self->{'root'} = $root;
}

sub getRootPath {
  my $self = shift;
  return $self->{'root'};
}

sub responseCodes {
  my $self = shift;
  my $directory = $self->getRootPath();
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbs->prepare(q/
                          SELECT code,message
                          FROM api_response_code
                          /);
  $sth->execute() or  die $DBI::errstr;

  my $rows = $sth->fetchall_arrayref({});

  my $codes;
  my $urlsection = new PlugNPay::UI::Template('api/doc/index','section.dirs');
  my $dirs = $self->getSubDirectories($directory);
  $urlsection->setVariable('title','Available Sub APIs');
  $urlsection->setVariable('id','dirs');
  my $dirList = '';
  foreach my $path (@{$dirs}) {
    $dirList .= '<a href="' . $directory . '/doc' . $path . '">' . $path . '</a>' . '<br>';
  }

  $urlsection->setVariable('spec',$dirList);
  my $header = '';
  my $urlHead = new PlugNPay::UI::Template('api/doc/index','header.item');
  $urlHead->setVariable('id','dirs');
  $urlHead->setVariable('Title','Sub APIs');
  $header .= $urlHead->render();

  #auth headers
  my $authSection = new PlugNPay::UI::Template('api/doc/index','section.auth');

  my $authHead = new PlugNPay::UI::Template('api/doc/index','header.item');
  $authHead->setVariable('id','authorization');
  $authHead->setVariable('Title','Authorization Headers');
  $header .= $authHead->render();



  my $main = new PlugNPay::UI::Template('/api/doc','index');
  my $content = new PlugNPay::UI::Template('/api/doc/index','section.codes');
  my $head = new PlugNPay::UI::Template('api/doc/index','header.item');
  foreach my $row (sort { $a->{'code'} <=> $b->{'code'} } @{$rows}) {
    my $message = $row->{'message'};
    my $status = 'fail';
    if ($row->{'code'} < 400) {
      $status = 'pass';
    }
     
    $codes .= '<div><span class="' . $status . '">' . $row->{'code'} . '</span>' . ' ==> <span class="info">' . $message . '</span></div>';
    
  }

  $head->setVariable('id','codes');
  $head->setVariable('Title','Response Codes');
  $header .= $head->render();

  $content->setVariable('title','API Response Codes');
  $content->setVariable('id','codes');
  $content->setVariable('spec',$codes);

  $main->setVariable('content',$urlsection->render() . $authSection->render() . $content->render());
  $main->setVariable('header', $header); 

  return $main->render();
}

sub loadPage {
  my $self = shift;
  my $resourcePath = $self->getResourcePath();
  my $schemaData = $self->loadSchemas();
  my $specs = $schemaData->{'specs'};
  my $exps = $schemaData->{'examples'};
  my $dirs = $self->getSubDirectories();
  my $main = new PlugNPay::UI::Template('/api/doc','index');
  my $content = '';
  my $header = '';
  my @resourceList = split('/',$resourcePath);
  
  my $authSection = new PlugNPay::UI::Template('api/doc/index','section.auth');
  $content .= $authSection->render();

  my $authHead = new PlugNPay::UI::Template('api/doc/index','header.item');
  $authHead->setVariable('id','authorization');
  $authHead->setVariable('Title','Authorization Headers');
  $header .= $authHead->render();

  # Additional doc info
  my $additionalInfo = $self->getExtraDocumentation();
  if ($additionalInfo) {
    my $extraData = new PlugNPay::UI::Template('api/doc/index/','section.extra');
    $extraData->setVariable('data',$additionalInfo);
    $content .= $extraData->render();

    my $extraHead = new PlugNPay::UI::Template('api/doc/index','header.item');
    $extraHead->setVariable('id','documentation');
    $extraHead->setVariable('Title', 'Documentation');
    $header .= $extraHead->render();
  }

  #Resource section, disabled for now
  #my $resourceSection = new PlugNPay::UI::Template('api/doc/index','section.resources');
  #my $recVal = '';
  #foreach my $resourceKey (@resourceList) {
  #  $recVal .= '<label class="pass">' . $resourceKey . '</label><br>';
  #}
  #$resourceSection->setVariable('resources',$recVal);
  #$resourceSection->setVariable('path',$self->getRootPath . $resourcePath);
  #$content .= $resourceSection->render();

  #my $resourceHeader = new PlugNPay::UI::Template('api/doc/index','header.item');
  #$resourceHeader->setVariable('id','resources');
  #$resourceHeader->setVariable('Title','URL Resources');
  #$header .= $resourceHeader->render();

  if (defined $dirs && defined $dirs->[0]) {
    my $urlsection = new PlugNPay::UI::Template('api/doc/index','section.dirs');
    $urlsection->setVariable('title','Sub APIs');
    $urlsection->setVariable('id','dirs');
    my $dirList = '';
    foreach my $path (@{$dirs}) {
      my $linkName = substr($path,length($resourcePath));
      $dirList .= '<a href="' . $self->getRootPath() .'/doc' . $path . '">' . $linkName . '</a>' . '<br>';
    }

    $urlsection->setVariable('spec',$dirList);
    $content .= $urlsection->render();

    my $urlHead = new PlugNPay::UI::Template('api/doc/index','header.item');
    $urlHead->setVariable('id','dirs');
    $urlHead->setVariable('Title','Available Sub APIs');
    $header .= $urlHead->render();
  }

  if (keys %{$specs}) {
    $content .= '<h2>Methods</h2><hr><br>';
    foreach my $key (keys %{$specs}){
      my $section = new PlugNPay::UI::Template('api/doc/index','section');
      $section->setVariable('title',ucfirst($key));
      $section->setVariable('example_link_json','example_' . lc($key) . '_json');
      $section->setVariable('spec_link_json','spec_' . lc($key) . '_json');
      $section->setVariable('spec_json', $specs->{$key}{'JSON'});
      $section->setVariable('example_json',$exps->{$key}{'JSON'});
      $section->setVariable('id',lc($key));
      $content .= $section->render();
  
      my $headSection = new PlugNPay::UI::Template('api/doc/index','header.item');
      $headSection->setVariable('id',lc($key));
      $headSection->setVariable('Title',ucfirst($key));
      $header .= $headSection->render();
    }
    $content .= '<hr>';
  }


  $main->setVariable('content',$content);
  $main->setVariable('header',$header);

  my $html = $main->render();

  return $html;
}

sub getExtraDocumentation {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection();

  my $sth = $dbs->prepare('pnpmisc', q/
        SELECT documentation
        FROM api_responder
        WHERE id = ? /);
  $sth->execute($self->getIDFromPath()) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});

  return $rows->[0]{'documentation'};
}

1;
