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
  "select VARIABLE_VALUE from GLOBAL_VARIABLES where VARIABLE_NAME = 'LONG_QUERY_TIME'");
$handler->dbh->do("SELECT SLEEP($long_query_time)");

while ( my $json = <STDIN> ) {
  my $decode = eval { decode_json($json); };
  next if ($@);

  unless ( defined $decode->{sql} ) {
    print $mp->pack($decode);
    next;
  }

  my $select;
  if ( $decode->{sql} =~ /(select[^\;]+)/i ) {
    $select = $1;
  }

  if ( $decode->{sql} =~ /^use ([^\;]+)/i ) {
    $db = $1;
  }

  if ( defined $db && defined $select ) {
    $handler->dbh->do("use $db");
    my $explains = eval { $handler->dbh->selectall_arrayref( "explain $select", +{ Slice => {} } ); };

    unless ( $@ || @$explains == 0 ) {
      $decode->{explain}  = $explains;
      $decode->{database} = $db;
    }
  }

  print $mp->pack($decode);
}
