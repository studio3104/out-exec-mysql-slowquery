#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;
use DBIx::Handler;
use JSON::XS;
use Data::MessagePack;

$| = 1;

my $mp = Data::MessagePack->new();

my $db_user   = "root";
my $db_passwd = "";
my $db_opt    = { RaiseError => 0, PrintError => 1 };
my $handler   = DBIx::Handler->new( "DBI:mysql:database=information_schema:127.0.0.1", $db_user, $db_passwd, $db_opt );

my $db;
my $long_query_time = $handler->dbh->selectrow_array(
  "SELECT VARIABLE_VALUE FROM GLOBAL_VARIABLES WHERE VARIABLE_NAME = 'LONG_QUERY_TIME'");
$handler->dbh->do("SELECT SLEEP($long_query_time)");

while ( my $json = <STDIN> ) {
  my $slowlog = eval { decode_json($json); };
  next if ($@);

  unless ( defined $slowlog->{sql} ) {
    print $mp->pack($slowlog);
    next;
  }

  my $select_statement;
  if ( $slowlog->{sql} =~ /(select[^\;]+)/i ) {
    $select_statement = $1;
  }

  if ( $slowlog->{sql} =~ /^use ([^\;]+)/i ) {
    $db = '`' . $1 . '`';
  }

  if ( defined $db && defined $select_statement ) {
    $handler->dbh->do("use $db");
    my $explains = eval { $handler->dbh->selectall_arrayref( "EXPLAIN $select_statement", +{ Slice => {} } ); };
    if ( ref $explains eq 'ARRAY' ) {
      $slowlog->{explain}  = $explains;
      $slowlog->{database} = $db;
    }
  }

  print $mp->pack($slowlog);
}
