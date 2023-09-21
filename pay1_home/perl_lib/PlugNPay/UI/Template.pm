package PlugNPay::UI::Template;

use strict;
use POSIX;
use PlugNPay::Util::MetaTag;
use PlugNPay::UI::MetaPhrase;

my %templateCache;

our $env;
our $templateBase;

sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  require PlugNPay::Environment;
  $env = new PlugNPay::Environment() if !defined $env;
  $templateBase = $env->get('PNP_WEB_TXT') . '/templates/' if !defined $templateBase;

  my $sessionGenerator = new PlugNPay::Util::UniqueID();
  $sessionGenerator->generate();
  $self->{'session'} = $sessionGenerator->inHex();

  # create an instance of the metatag parser
  $self->{'metaTagParser'} = new PlugNPay::Util::MetaTag();

  my $category = shift;
  my $name = shift;

  if ($category && $name) {
    $self->setCategory($category);
    $self->setName($name);
  }

  return $self;
}

sub setCategory {
  my $self = shift;
  my $category = shift;
  $category =~ s/\.\.//g;
  $self->{'category'} = $category;
}

sub getCategory {
  my $self = shift;
  return $self->{'category'};
}

sub setName {
  my $self = shift;
  my $name = shift;
  $name =~ s/\///g;
  $self->{'name'} = $name;
}

sub getName {
  my $self = shift;
  return $self->{'name'};
}

sub setOptions {
  my $self = shift;
  my $options = shift;
  $self->{'options'} = $options;
}

sub getOptions {
  my $self = shift;
  return $self->{'options'};
}


sub setTemplate {
  my $self = shift;
  my $category = shift;
  my $name = shift;
  my $options = shift;

  $self->setCategory($category);
  $self->setName($name);
  $self->setOptions($options);
}



sub render {
  my $self = shift;

  return $self->loadTemplate($self->getCategory(),
                             $self->getName(),
                             $self->getOptions);
}


sub loadTemplate {
  my $self = shift;
  my ($category,$name,$options) = @_;

  # create variable to contain the template
  my $html = '';

  # remove all slashes from name
  $name =~ s/\///g;

  # remove all .. from category
  $category =~ s/\.\.//g;



  # check to see if the template exists in the cache
  if (exists $templateCache{$category}{$name}) {
    $html = $templateCache{$category}{$name};
  } else {
    # if the template does not exist in the cache, load it
    my $templatePath = $templateBase . '/' . $category . '/' . $name . '.template';
    if (-e $templatePath) {
      open(TEMPLATE,$templatePath);

      # read the contents of the template into a scalar.
      # the reason for using sysread is because it takes about 10% of the time as doing my $html = join('',<TEMPLATE>)
      # as well as using less CPU time
      sysread TEMPLATE, $html, -s TEMPLATE;

      # close the template file, we don't need it anymore
      close(TEMPLATE);

      # put the template into the cache
      $templateCache{$category}{$name} = $html;
    } else {
      $self->log('Template not found: [' . $templatePath . '] from [' . $category . '/' . $name . ']');
    }
  }

  return $self->parseTemplate($html,$options);
}

sub parseTemplate {
  my $self = shift;
  my $template = shift;
  my $options = shift;

  # expand shorthand
  $template =~ s/<metalang=['"](.*?),(.*?)['"]>/<meta type="template" content="type='metaphrase', context='$1', name='$2'" \/>/g;
  $template =~ s/<metainc=['"](.*?),(.*?)['"]>/<meta type="template" content="type='include', category='$1', name='$2'" \/>/g;
  $template =~ s/<metavar=['"](.*?)['"]>/<meta type="template" content="type='variable', name='$1'" \/>/g;
  $template =~ s/<metadyn=['"](.*?)['"]>/<meta type="template" content="type='dynamic-include', name='$1'" \/>/g;

  $self->{'metaTagParser'}->loadDocument($template);
  my @templateMetaTags = $self->{'metaTagParser'}->metaTagsOfType('template');
  foreach my $templateMetaTag (@templateMetaTags) {
    my $tag = $templateMetaTag->{'raw'};
    my $replacement = $self->evaluateTemplateMetaTag($templateMetaTag,$options);
    $template =~ s/$tag/$replacement/g;
  }
  return $template;
}

sub evaluateTemplateMetaTag {
  my $self = shift;
  my $templateMetaTag = shift;
  my $options = shift;

  my $html = '';

  my %parameters = %{$templateMetaTag->{'parameters'}};

  $self->log('Loading data for tag [' . $templateMetaTag->{'raw'} . ']');

  # include tags
  if ($parameters{'type'} eq 'include') {
    $html = $self->loadTemplate($parameters{'category'},$parameters{'name'});
    $html =~ s/^\s+//;
  }

  # dynamic include tags
  elsif ($parameters{'type'} eq 'dynamic-include') {
    my $category = $self->{'dynamicTemplates'}{$parameters{'name'}}{'category'};
    my $name = $self->{'dynamicTemplates'}{$parameters{'name'}}{'name'};
    if (!defined $category || !defined $name) {
      $self->log('Dynamic include information not found for [' . $parameters{'name'} . ']');
    } else {
      $html = $self->loadTemplate($category,$name);
      $html =~ s/^\s+//;
    }
  }

  # dynamic content
  elsif ($parameters{'type'} eq 'variable') {
    my $value = $self->{'variables'}{$parameters{'name'}};
    $html = "$value"; # the quotes here force the overload of an object to a string if a string overload is specified
  }

  # metaphrase content
  elsif ($parameters{'type'} eq 'metaphrase') {
    my $context = $parameters{'context'};
    my $key = $parameters{'name'};

    if (!$self->{'metaphrase'}) {
      $self->{'metaphrase'} = new PlugNPay::UI::MetaPhrase();
    }
    $html = $self->{'metaphrase'}->get($context,$key,(ref($options) eq 'HASH' ? $options->{'language'} : 'EN-US'));
  }

  chomp $html;

  return $html;
}

sub setVariable {
  my $self = shift;
  my ($name,$value) = @_;

  $self->{'variables'}{$name} = $value;
}

sub setVariables {
  my $self = shift;
  my $hashRef = shift;

  if (ref($hashRef) eq 'HASH') {
    foreach my $key (keys %{$hashRef}) {
      $self->{'variables'}{$key} = $hashRef->{$key};
    }
  }
}

sub setDynamicTemplate {
  my $self = shift;
  my ($dynamicName,$category,$name) = @_;

  $self->{'dynamicTemplates'}{$dynamicName}{'category'} = $category;
  $self->{'dynamicTemplates'}{$dynamicName}{'name'} = $name;
}

sub reset {
  my $self = shift;
  delete $self->{'variables'};
  delete $self->{'dynamicTemplates'};
}

sub log {
  my $self = shift;
  my $message = shift;
  chomp $message;

  my $timestamp = POSIX::strftime('%m/%d/%Y %H:%M:%S', localtime);
  push(@{$self->{'log'}},$timestamp . ' ' . $message);
}

sub getLog {
  my $self = shift;

  return @{$self->{'log'}};
}


1;
