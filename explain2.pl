#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;
$|=1;
use DBIx::Handler;
use JSON::XS;
use Data::MessagePack;

my $mp = Data::MessagePack->new();

my $db_user     = "root";
my $db_passwd   = "";
my $db_opt      = { RaiseError => 0, PrintError => 1 };
my $handler     = DBIx::Handler->new("DBI:mysql:database=information_schema:127.0.0.1", $db_user, $db_passwd, $db_opt);

my $db;
my $long_query_time = $handler->dbh->selectrow_array("select VARIABLE_VALUE from GLOBAL_VARIABLES where VARIABLE_NAME = 'LONG_QUERY_TIME'");
$handler->dbh->do("SELECT SLEEP($long_query_time)");

while(my $json = <STDIN>){
  # STDINがJSONじゃなかったら何もしない
  my $decode = eval { decode_json($json); };
  next if ($@);

  # decodeしたJSONに"sql"キーがあり、そこにSELECT文が含まれていなければ、
  # そのままMessagePackで放出する
  my $select;
  if (defined $decode->{sql} && $decode->{sql} =~ /(select[^\;]+)/i){
    $select = $1;
  }else{
    print $mp->pack($decode);
    next;
  }

  # "use database"があれば、データベースを切り替える
  if ($decode->{sql} =~ /^use ([^\;]+)/i){
    $db = $1;
    $handler->dbh->do("use $db");
  }

  unless (defined $db){
    print $mp->pack($decode);
    next;
  }

  my $data   = $decode;
  my $result = eval { $handler->dbh->selectall_arrayref( "explain $select", +{Slice => {}});};

  # explain結果が$resultに入ってないとdieしてwhile抜けちゃうので定義済みの場合のみ
  if (defined $result){
    for (my $i=0;$i < (@$result);$i++){
      $data->{"explain$i"} = $result->[$i];
    }
    # どのDBへのEXPLAINかどうかわかるように。
    $data->{database} = $db;
  }

  print $mp->pack($data);
}
