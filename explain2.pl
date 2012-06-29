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
my $handler     = DBIx::Handler->new("DBI:mysql:database=mysql:127.0.0.1", $db_user, $db_passwd, $db_opt);

while(my $json = <STDIN>){

  # STDINがJSONじゃなかったら何もしない
  my $decode = eval { decode_json($json); };
  unless ($@) {

    # STDINで受け取ったJSONに"sql"があり、さらにSELECT句が含まれていなければ、
    # 受け取ったJSONをそのままMessagePackにして放出
    if (defined $decode->{sql}) {
      my ($select) = ($decode->{sql} =~ /(select[^\;]+)/i);

      # もっとイケてる書き方がきっとある・・・
      my ($db) = ($decode->{sql} =~ /^use ([^\;]+)/i) if ($decode->{sql} =~ /^use [^\;]+/i);

      if (defined $select){
        my $result;
        my %data = %$decode;

        # td-agent起動直後に$dbが未定義になってしまうことの対策
        # 未定義だった場合は、全データベースでexplainしてみて、結果が返ってきた時のDB名を$dbにセット
        # ただ、コレだと異なるデータベースに同名のテーブルがあったときにどうしようという感じ・・・
        # (シャーディングされたのをがっちゃんこした場合とかはスキーマも同じになるから厄介)
        if (defined $db) {
          $handler->dbh->do("use $db");
          $result = eval { $handler->dbh->selectall_arrayref( "explain $select", +{ Slice => {} } ); };
        }else{
          my $databases = $handler->dbh->selectcol_arrayref("show databases");
          foreach (@$databases) {
            $handler->dbh->do("use $_");
            my $result = eval { $handler->dbh->selectall_arrayref( "explain $select", +{ Slice => {} } ); };
            if (defined $result) {
              $db = $_; 
              last;
            }   
          }
        }

        # explain結果が$resultに入ってないとdieしてwhile抜けちゃうので定義済みの場合のみ
        if (defined $result){
          for (my $i=0;$i < (@$result);$i++){
            my $key = "explain$i";
            my %explains;
            %explains = (%explains, ($key  => $result->[$i]));
            %data = (%data, %explains);
          }
        }

        # どのDBへのEXPLAINかどうかわかるように。
        %data = (%data, (database => $db));
        print $mp->pack(\%data);
      }else{
        print $mp->pack($decode);
      }
    }
  }
}
