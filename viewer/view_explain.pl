#!/usr/bin/env perl

use MongoDB;
use strict;
use warnings;
use Data::Dumper;
use Data::Page;
use Log::Minimal;
#$ENV{LM_DEBUG} = 'true';

use Mojolicious::Lite;
plugin 'xslate_renderer';

my $connection = MongoDB::Connection->new( db_name => 'mysqlslow' );
my $database = $connection->mysqlslow;

my @collection_names = $database->collection_names;
my $collections;
foreach (@collection_names) {
  push( @$collections, $_ ) unless ( $_ =~ /\./ );
}
get '/' => sub {
  my $self             = shift;
  my $title            = 'SlowQueryAutoExplainTool';
  my $entries_per_page = 5;
  my $host             = $self->param('host') || $collections->[0];
  my $current_page     = $self->param('current_page') || 1;

  my $collection = $database->$host;
  my $total_entries = $collection->find( { _id => { '$exists' => 1 } } )->count;

  my $page = Data::Page->new( $total_entries, $entries_per_page, $current_page );
  my $find_result
    = $collection->find( {}, {} )->limit($entries_per_page)->skip( $page->first - 1 )->sort( { _id => -1 } );

# DateTimeなオブジェクトをJSTに変換している。
# MongoDBにInsertされた日時を取得しているが、SQLに含まれる「SET timestamp」を変換したほうがよいです。
  my $fetched_rows = [];
  while ( my $obj = $find_result->next ) {
    if ( $obj->{time} ) {
      my $dt = $obj->{time}->set_time_zone('Asia/Tokyo');
      $obj->{date} = $dt->ymd . ' ' . $dt->hms;
      delete $obj->{time};
    }
    $obj->{sql} =~ s/^use .+; //ig;
    $obj->{sql} =~ s/^SET timestamp=\d+; //ig;
    delete $obj->{_id};
    push @$fetched_rows, $obj;
  }

  my $u       = $self->url_with;
  my $pager = {
    next => { url => $u->clone->query(current_page => $current_page + 1) },
    prev => { url => $u->clone->query(current_page => $current_page - 1) },
  };
  my $url_str = { $current_page => { class => 'active' }, };
  
  for ($current_page -2 .. $current_page +2){
    next if ( $_ <= 0 || $_ > $page->last_page );
    $pager->{prev} = { class => 'disabled' } if ($current_page == 1);
    $pager->{next} = { class => 'disabled' } if ($current_page == $page->last_page);
    unless ($_ == $current_page) {
      $url_str->{$_} = { url => $u->clone->query( current_page => $_ ) };
    }
  }

  if ($total_entries >= 5) {
    if ($current_page == 1 || $current_page == 2) {
      $url_str->{4} = { url => $u->clone->query( current_page => 4 ) };
      $url_str->{5} = { url => $u->clone->query( current_page => 5 ) };
    }
    if ($current_page == $page->last_page || $current_page == $page->last_page -1) {
      $url_str->{$page->last_page-3} = { url => $u->clone->query( current_page => $page->last_page-3 ) };
      $url_str->{$page->last_page-4} = { url => $u->clone->query( current_page => $page->last_page-4 ) };
    }
  }

  $self->render(
    handler      => 'tx',
    title        => $title,
    url_str      => $url_str,
    pager        => $pager,
    fetched_rows => $fetched_rows,
    collections  => $collections,
    host         => $host,

    #    collection_names  => \$database->collection_names,
  );

} => 'dd';

app->start;
