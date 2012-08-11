package mypager;

use strict;
use warnings;
use Data::Dumper;
use Data::Page;

sub new {
  my $package          = shift;
  my $mojo_obj         = shift;
  my $total_entries    = shift;
  my $entries_per_page = shift;
  my $current_page     = shift;

  bless {
    mojo => $mojo_obj,
    page => Data::Page->new( $total_entries, $entries_per_page, $current_page ),
    total_entries => $total_entries,
    current_page => $current_page,
  }, $package;
}

sub pager {
  my $self = shift;
  my $page = $self->{page};
  my $url  = $self->{mojo}->url_with;

  my $pager = {
    next => { url => $url->clone->query( current_page => $self->{current_page} + 1 ) },
    prev => { url => $url->clone->query( current_page => $self->{current_page} - 1 ) },
  };
  my $url_str = { $self->{current_page} => { class => 'active' }, };

  for ( $self->{current_page} - 2 .. $self->{current_page} + 2 ) {
    next if ( $_ <= 0 || $_ > $page->last_page );
    $pager->{prev} = { class => 'disabled' } if ( $self->{current_page} == 1 );
    $pager->{next} = { class => 'disabled' } if ( $self->{current_page} == $page->last_page );
    unless ( $_ == $self->{current_page} ) {
      $url_str->{$_} = { url => $url->clone->query( current_page => $_ ) };
    }
  }

  if ( $self->{total_entries} >= 5 ) {
    if ( $self->{current_page} == 1 || $self->{current_page} == 2 ) {
      $url_str->{4} = { url => $url->clone->query( current_page => 4 ) };
      $url_str->{5} = { url => $url->clone->query( current_page => 5 ) };
    }
    if ( $self->{current_page} == $page->last_page || $self->{current_page} == $page->last_page - 1 ) {
      $url_str->{ $page->last_page - 3 } = { url => $url->clone->query( current_page => $page->last_page - 3 ) };
      $url_str->{ $page->last_page - 4 } = { url => $url->clone->query( current_page => $page->last_page - 4 ) };
    }
  }

  return $url_str, $pager;
}

1;
