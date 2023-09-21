package PlugNPay::Util::MetaTag;

use strict;
use PlugNPay::Util::UniqueID;


sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  my $sessionGenerator = new PlugNPay::Util::UniqueID();
  $sessionGenerator->generate();
  $self->{'session'} = $sessionGenerator->inHex();

  return $self;
}

sub loadDocument {
  my $self = shift;
  $self->{'document'} = shift;
}

sub allMetaTags {
  my $self = shift;

  my @metaTags = ( $self->{'document'} =~ /(<meta .*?\/?>)/g );

  return @metaTags;
}

sub parseTag {
  my $self = shift;
  my $tag = shift;

  # pull out the name and content from the meta tag
  $tag =~ /<meta (.*)\/?>/;
  my ($name,$content,$type);
  $name = $content = $type = $tag;

  $name=~ s/.*name="(.*?)".*/$1/;
  $content =~ s/.*content="(.*?)".*/$1/;
  $type =~ s/.*type="(.*?)".*/$1/;

  # split the content into parameter pairs
  my @parameterPairs = split(/,\s*/,$content);

  my %parameters;

  # set up a key-value hash of the parameters and their values
  map {
    my ($parameter,$value) = split('=',$_);
    $value =~ s/["']//g;
    $parameters{$parameter} = $value;   
  } @parameterPairs;


  # create the hash to return for the tag
  my %tagHash;
  $tagHash{'name'} = $name;
  $tagHash{'content'} = $content;
  $tagHash{'type'} = $type;
  $tagHash{'raw'} = $tag;
  $tagHash{'parameters'} = \%parameters;

  return %tagHash;
}

sub metaTagsOfType {
  my $self = shift;
  my ($metaTagType) = @_;

  # get meta tags from the document
  my @metaTags = $self->allMetaTags();

  # put all tags in an array to return
  my @metaTagsToReturn;
  foreach my $metaTag (@metaTags) {
    my %metaTagHash = $self->parseTag($metaTag);
    if ($metaTagHash{'type'} eq $metaTagType) {
      push @metaTagsToReturn, \%metaTagHash;
    }
  }

  return @metaTagsToReturn;
}

sub metaTagByName {
  my $self = shift;
  my ($metaTagName) = @_;

  # get meta tags from the document
  my @metaTags = $self->allMetaTags();

  my $metaTag;
  map {
    my %metaTagHash = $self->parseTag($_);
    if (!defined $metaTagName || $metaTagHash{'name'} eq $metaTagName) {
      $metaTag = \%metaTagHash;
    }
  } @metaTags;

  return $metaTag;
}
    
1;
