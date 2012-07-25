#!/usr/bin/env perl

use MongoDB;
use strict;
use warnings;
use Data::Dumper;
use Mojo::Parameters;

my $host        = 'localhost';
my $fetch_limit = 1;
my $fetch_skip  = 0;

my $connection = MongoDB::Connection->new( db_name => 'mysqloslow' );
my $database   = $connection->mysqlslow;
my $collection = $database->$host;

my $find_result
  = $collection->find( { "explain.type" => "ALL" }, {} )->limit($fetch_limit)
  ->skip($fetch_skip)->sort( { _id => -1 } );

my $fetched_rows = [];
while ( my $obj = $find_result->next ) {
   push @$fetched_rows, $obj;
}

print Dumper $fetched_rows;
