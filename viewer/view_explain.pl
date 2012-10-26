#!/usr/bin/env perl

# This code contains the modified "mysqldumpslow".
# (line 108-252)
# It is applied by the GPL2 license.
# Other places have copyrighted by studio3104.
# WITHOUT ANY WARRANTY.
#
# Copyright (c) 2000-2002, 2005-2008 MySQL AB, 2008, 2009 Sun Microsystems, Inc.
# Use is subject to license terms.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU Library General Public
# License as published by the Free Software Foundation; version 2
# of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Library General Public License for more details.
#
# You should have received a copy of the GNU Library General Public
# License along with this library; if not, write to the Free
# Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
# MA 02110-1301, USA

# mysqldumpslow - parse and summarize the MySQL slow query log

# Original version by Tim Bunce, sometime in 2000.
# Further changes by Tim Bunce, 8th March 2001.
# Handling of strings with \ and double '' by Monty 11 Aug 2001.

use MongoDB;
use strict;
use warnings;
use Data::Dumper;
use Data::Page;
use Log::Minimal;
use Getopt::Long;

#use FindBin::libs;
use lib './lib';
use mypager;

#use dumpslow;

#$ENV{LM_DEBUG} = 'true';

use Mojolicious::Lite;
plugin 'xslate_renderer';

my $title = {
  title     => 'SlowQuerySummarizationTool',
  subtitles => [qw/History Summarize/],
};

my $connection = MongoDB::Connection->new();
my $database   = $connection->mysqlslow;

my @collection_names = $database->collection_names;
my $collections;
foreach (@collection_names) {
  push( @$collections, $_ ) unless ( $_ =~ /\./ );
}

get "/$title->{subtitles}->[0]" => sub {
  my $self             = shift;
  my $entries_per_page = 5;
  my $host             = $self->param('host') || $collections->[0];
  my $current_page     = $self->param('current_page') || 1;
  $title->{me} = $title->{subtitles}->[0];

  my $collection = $database->$host;
  my $total_entries = $collection->find( { _id => { '$exists' => 1 } } )->count;

  my $page = Data::Page->new( $total_entries, $entries_per_page, $current_page );
  my $find_result
    = $collection->find( {}, {} )->limit($entries_per_page)->skip( $page->first - 1 )->sort( { _id => -1 } );

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

  my $mypager = mypager->new( $self, $total_entries, $entries_per_page, $current_page );
  my ( $url_str, $pager ) = $mypager->pager;

  $self->render(
    handler      => 'tx',
    title        => $title,
    url_str      => $url_str,
    pager        => $pager,
    fetched_rows => $fetched_rows,
    collections  => $collections,
    host         => $host,
  );

} => 'dd';

get "/$title->{subtitles}->[1]" => sub {

  # Copyright (c) 2000-2002, 2005-2008 MySQL AB, 2008, 2009 Sun Microsystems, Inc.
  # Use is subject to license terms.
  #
  # This program is free software; you can redistribute it and/or
  # modify it under the terms of the GNU Library General Public
  # License as published by the Free Software Foundation; version 2
  # of the License.
  #
  # This program is distributed in the hope that it will be useful,
  # but WITHOUT ANY WARRANTY; without even the implied warranty of
  # MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  # Library General Public License for more details.
  #
  # You should have received a copy of the GNU Library General Public
  # License along with this library; if not, write to the Free
  # Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
  # MA 02110-1301, USA

  # mysqldumpslow - parse and summarize the MySQL slow query log

  # Original version by Tim Bunce, sometime in 2000.
  # Further changes by Tim Bunce, 8th March 2001.
  # Handling of strings with \ and double '' by Monty 11 Aug 2001.

  my $self = shift;
  $title->{me} = $title->{subtitles}->[1];

  my $host          = $self->param('host') || $collections->[0];
  my $collection    = $database->$host;
  my $total_entries = $collection->find( { _id => { '$exists' => 1 } } )->count;
  my $find_result   = $collection->find( {}, {} )->limit(50)->sort( { _id => -1 } );

  my $sort_options = {
    al => { class => "" },
    ar => { class => "" },
    at => { class => "" },
    c  => { class => "" },
    l  => { class => "" },
    r  => { class => "" },
    t  => { class => "" },
  };
  my $sort_opt = "at";

  foreach my $key ( keys(%$sort_options) ) {
    if ( $self->param('sort') eq $key ) {
      $sort_opt = $key;
    }
  }
  $sort_options->{$sort_opt}->{class} = "active";

  # t=time, l=lock time, r=rows
  # at, al, and ar are the corresponding averages

  my %opt = ( s => $sort_opt, );

  GetOptions(
    \%opt,
    's=s',    # what to sort by (al, at, ar, c, t, l, r)
    'r!',     # reverse the sort order (largest last instead of first)
    't=i',    # just show the top n queries
    'a!',     # don't abstract all numbers to N and strings to 'S'
    'l!',     # don't subtract lock time from total time
  ) or usage("bad option");

  $opt{'help'} and usage();

  my @pending;
  my %stmt;
  $/ = ";\n#";    # read entire statements using paragraph mode
  while ( $_ = $find_result->next ) {
    my $user = $_->{user};
    my $host = $_->{host};
    my $sql  = $_->{sql};
    $sql =~ s/^use .+; //ig;
    $sql =~ s/^SET timestamp=\d+; //ig;
    my ( $t, $l, $r ) = ( $_->{query_time}, $_->{lock_time}, $_->{rows_sent} );
    $t -= $l unless $opt{l};

    unless ( $opt{a} ) {
      $sql =~ s/\b\d+\b/N/g;
      $sql =~ s/\b0x[0-9A-Fa-f]+\b/N/g;
      $sql =~ s/''/'S'/g;
      $sql =~ s/""/"S"/g;
      $sql =~ s/(\\')//g;
      $sql =~ s/(\\")//g;
      $sql =~ s/'[^']+'/'S'/g;
      $sql =~ s/"[^"]+"/"S"/g;

      # abbreviate massive "in (...)" statements and similar
      $sql =~ s!(([NS],){100,})!sprintf("$2,{repeated %d times}",length($1)/2)!eg;
    }
    my $s = $stmt{$sql} ||= { users => {}, hosts => {}, explain => $_->{explain} };
    $s->{c} += 1;
    $s->{t} += $t;
    $s->{l} += $l;
    $s->{r} += $r;
    $s->{users}->{$user}++ if $user;
    $s->{hosts}->{$host}++ if $host;
  }

  foreach ( keys %stmt ) {
    my $v = $stmt{$_} || die;
    my ( $c, $t, $l, $r ) = @{$v}{qw(c t l r)};
    $v->{at} = $t / $c;
    $v->{al} = $l / $c;
    $v->{ar} = $r / $c;
  }

  my @sorted = sort { $stmt{$b}->{ $opt{s} } <=> $stmt{$a}->{ $opt{s} } } keys %stmt;
  @sorted = @sorted[ 0 .. $opt{t} - 1 ] if $opt{t};
  @sorted = reverse @sorted             if $opt{r};

  my $summarized;
  foreach (@sorted) {
    my $v = $stmt{$_} || die;
    my ( $c, $t, $at, $l, $al, $r, $ar, $explain ) = @{$v}{qw(c t at l al r ar explain)};
    my @users = keys %{ $v->{users} };
    my $user  = ( @users == 1 ) ? $users[0] : sprintf "%dusers", scalar @users;
    my @hosts = keys %{ $v->{hosts} };
    my $host  = ( @hosts == 1 ) ? $hosts[0] : sprintf "%dhosts", scalar @hosts;
    push @$summarized,
      {
      count => sprintf( "%d",          $c ),
      time  => sprintf( "%.2fs (%ds)", $at, $t ),
      lock  => sprintf( "%.2fs (%ds)", $al, $l ),
      rows  => sprintf( "%.1f (%d)",   $ar, $r ),
      user    => "$user\@$host",
      query   => sprintf( "%s", $_ ),
      explain => $explain,
      };
  }

  # Count: 1  Time=0.00s (0s)  Lock=0.00s (0s)  Rows=1.0 (1), td-agent[td-agent]@localhost

  $self->render(
    handler     => 'tx',
    summarized  => $summarized,
    collections => $collections,
    host        => $host,
    title       => $title,
    sort_opts   => $sort_options,
  );
} => 'gg';

app->start;
