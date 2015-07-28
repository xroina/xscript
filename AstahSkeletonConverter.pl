#!/usr/bin/perl

BEGIN {
    unshift @INC, $0 =~ /^(.*?)[^\/]+$/;
    unshift @INC, readlink($0) =~ /^(.*?)[^\/]+$/ if -l $0;
}

use strict;
use warnings;
use utf8;

use FileHandle;
use Encode;
use LexicalAnalyzer;

binmode STDOUT,":utf8";

# コマンド引数の取得
unless($ARGV[0]) {
    my($prog) = $0 =~ /([^\/]+)$/;
    print "usage $prog [-I[find path]] [-N[namespace name(jp)] [file name(not expend)|*]\n";
    exit 0;
}
my $ns_name = 'TODO(入力してください)';
my $path = [];
my $file = [];
my $debug;
foreach(@ARGV) {
    if(/^-I(.*)/) { push @$path, $1 }
    if(/^-N(.*)/) { $ns_name = Encode::decode('utf8', $1);}
    elsif(/^-debug$/) { $debug = 1 }
    else { push @$file, $_ }
}
push @$path, "." unless @$path;
print "$ENV{PWD}\n" if $debug;

my $glob = [];
foreach my $p(@$path) {
    foreach my $f(@$file) {
        push @$glob, "$p/$f.*";
    }
}
$glob = join ' ', @$glob;
my $conv = {};
foreach(glob $glob) {
    next unless /([^\/]*)\.(cpp|h)$/;
    $conv->{$1}->{$2}->{path} = $_;
    $conv->{$1}->{$2}->{file} = "$1.$2";
}

foreach my $class(keys %$conv) {
#print "$class $conv->{$class}->{h}->{path}\n";
    my $hlex = new LexicalAnalyzer({file=>$conv->{$class}->{h}->{path}, debug=>$debug});
#print "h:".$hlex->string(), "\n";
    next if $hlex->begin->value eq 'comment_/*!';   # 処理済みなら処理しない
    $hlex->AnalyzeCPP();
#print "$class $conv->{$class}->{cpp}->{path}\n";
    my $clex;
    if($conv->{$class}->{cpp}) {
        $clex = new LexicalAnalyzer({file=>$conv->{$class}->{cpp}->{path}, debug=>$debug});
#print "cpp:". $clex->string(), "\n";
        $clex->AnalyzeCPP();
    }
#print "end lex\n";
    # class コメント取得
    my $t = $hlex->{begin}->next('class_class');
    my $class_name = $t->next('define_.*')->text;

    my $end   = $t->prev('comment_.*');
    my $begin = $end->prev('!(comment|space)_.*')->next('comment_.*');

#print"get comment\n";
    my $lex = getComment($begin, $end);
    $begin = $begin->prev->next;
print"get comment > " . $lex->string() . "\n"  if $debug;
    # classコメント
    my $sp = ' ' x 20;
    my $comment = [];
    push @$comment,
        "", "\n",
        "//---- クラス定義", "\n",
        "/*!", "\n",
        " *", "\n",
        " * \@class $class_name $conv->{$class}->{h}->{file} \"inc/$conv->{$class}->{h}->{file}\"", "\n",
        " *", "\n",
        " * \@b   クラス論理名", "\n",
        " *", "\n",
        " *      $lex->{name}", "\n",
        " *", "\n",
        " * \@brief $lex->{name}のクラスを定義する。", "\n",
        " *", "\n",
        " * \@par 概要説明", "\n",
        " *", "\n",
        " * \@details", "\n"
    ;
    # details
    for(my $t = $lex->begin; !$t->eof; $t = $t->next) {
        if($t->prev->value =~ 'space_\n' || $t->prev->bof) {
            push @$comment, " *  ";
            push @$comment, "- " if $t->kind eq 'ident';
        }
        if($t->value eq 'op_・') {
            push @$comment, "    " unless $t->prev->value =~ /^space_ +/;
            unless($t->prev->kind eq 'ident' && $t->next->kind eq 'ident') {
                push @$comment, "- ";
                next;
            }
        }
        push @$comment, $t->text;
#        push @$comment, "'",$t->value, "' ";
    }
    push @$comment,
        " *", "\n",
        " * \@par 備考", "\n",
        " *    なし", "\n",
        " *", "\n",
        " * \@par 改訂", "\n",
        " *    なし", "\n",
        " *", "\n",
        " */", "\n"
    ;
    $begin->insert(@$comment);
    $end->next('class_class')->next('space_\n')->insert(
        new Token($sp, 'space'),
        new Token("/// $lex->{name}", "comment")
    );

    foreach($hlex, $clex) {
        next unless $_;
        # コメント挿入位置の取得
        my $inc = $_->{begin}->next('directive_#include');
        my $incend = $_->end->prev('directive_#include')->next('space_\n')->next;
        $inc = $_->begin if $inc->eof;
        my $ns = $_->{begin}->next('namespace_.*');

        # ファイルコメント
        my $cmt = ($_ eq $hlex ? 'クラス定義' : 'メソッド');
        $_->begin->insert(
            "/*!", "\n",
            " *",  "\n",
            " * \@file ", [reverse split '/', $_->{file}]->[0], "\n",
            " *", "\n",
            " * \@brief $lex->{name}\の$cmt\を記述する。", "\n",
            " *", "\n",
            " * \@par 備考", "\n",
            " *   なし", "\n",
            " *", "\n",
            " * COPYRIGHT(c) 2015. MITSUBISHI ELECTRIC CORPORATION ALL RIGHTS RESERVED.", "\n",
            " */", "\n");

        # includeコメント
        $inc->insert("//---- ヘッダファイルインクルード", "\n");
        $incend->insert(
                "", "\n",
                "//---- 他クラス定義", "\n",
        );

        # namespaseコメント
        if(!$ns->eof) {
            my $name = $ns->next('(define_.*|op_[;\{])')->text;
            my $name_jp = $ns_name;
            $name = '(not define)', $name_jp = 'なし' if !$name || $name =~ /[;\{]/;
            $ns->insert(
                "//---- 名前空間定義", "\n",
                "/*!", "\n",
                " * \@namespace $name", "\n",
                " * \@brief $name_jp", "\n",
                " */", "\n",
            );
        }
    }

    # メソッドコメント
    my $method = {};
    for(my $t = $hlex->begin->next('method_.*'); !$t->eof; $t = $t->next('method_.*')) {
        my $end   = $t->prev('comment_.*');
        my $begin = $end->prev('!(comment|space)_.*')->next('comment_.*');
#print "get $t->{text}($t->{file}:$t->{line}) comment\n" . $hlex->print($begin, $end). "\n";
        my $lex = getComment($begin, $end);
print"get $t->{text}($t->{file}:$t->{line}) comment > " . $lex->string() . "\n" if $debug;
        my $name = $class_name . "::" . $t->text;
        $method->{$t->text} = $lex->{name};

        my $this;
        if($clex) {
            $this = $clex->begin->next("method_$name");
            warn "$name method not found", next if $this->eof;
            $begin = $this->prev('space_\n')->next;
        } else {
            undef $begin;
        }

        # 関数パラメータコメントの構成
        my $prm = [];
        foreach($t, $this) {
            next unless $_;
            my $cpp = ($this && $_ == $this);
            my $spc = ' ' x ($cpp ? 8 : 12);
            my $t = $_->next('op_\(')->next;
            next if $t->value eq 'op_)';
            $t->insert(
                new Token("\n", 'space'),
                new Token($spc, 'space')
            );

            while(!$t->eof) {
                $t = $t->next('op_[,\)]');
                my $valiable = $t->prev('valiable_.*')->text;
                push @$prm, $valiable if $cpp;
                $t = $t->next if $t->value eq 'op_,';

                $t->insert(new Token($sp, 'space'), new Token("///< TODO($valiable)", 'comment'), new Token("\n", 'space'));
                if($t->value eq 'op_)') {
                    $t->insert(new Token("    ", 'space')) unless $cpp;
                    last;
                }
                $t->insert(new Token($spc, 'space'));
            }
        }
        next unless $this;

        my $ret = $this->prev('define_.*')->text;

        # メソッドDoxygenコメントの構成
        my $comment = [];
        push @$comment,
            "/*!", "\n",
            " *", "\n",
            " * \@b メンバ関数名", "\n",
            " *", "\n",
            " *  $lex->{name}", "\n",
            " *", "\n",
            " * \@brief $lex->{name}の処理を行う", "\n",
            " *", "\n",
            " * \@par 機能説明", "\n",
            " * \@details", "\n"
        ;
        # details
        for(my $t = $lex->begin; !$t->eof; $t = $t->next) {
            if($t->prev->value =~ 'space_\n' || $t->prev->bof) {
                push @$comment, " *  ";
                push @$comment, "- " if $t->kind eq 'ident';
            }
            if($t->value eq 'op_・') {
                push @$comment, "    " unless $t->prev->value =~ /^space_ +/;
                unless($t->prev->kind eq 'ident' && $t->next->kind eq 'ident') {
                    push @$comment, "- ";
                    next;
                }
            }
            push @$comment, $t->text;
        }
        push @$comment, " *", "\n";
        foreach(@$prm) {
            push @$comment, " * \@param [in]  $_             TODO($_)", "\n",
        }
        push @$comment, " *", "\n";
        if($ret && $ret ne 'void') {
            push @$comment, " * \@retval TODO($ret)", "\n",
        } else {
            push @$comment, " * \@retval なし", "\n",
        }
        push @$comment,
            " *", "\n",
            " * \@par 備考", "\n",
            " *  なし", "\n",
            " *", "\n",
            " */", "\n",
        ;
        $begin->insert(@$comment);
    }
    # ヘッダのメソッド名の後ろにコメントを書く
    for(my $t = $hlex->begin->next('method_.*'); !$t->eof; $t = $t->next('method_.*')) {
        my $name = $method->{$t->text};
        $t->next('space_\n')->insert(
            new Token($sp, 'space'),
            new Token("///< $name", "comment")
        );
    }

    foreach($hlex, $clex) {
        next unless $_;
        if($debug) {
            print "[[[ outfile ]]] $_->{file} ================================================\n";
            for(my $t = $_->begin(); !$t->eof(); $t = $t->next()) {
                print $t->text() if $debug;
            }
            print "[[[ EOF ]]]\n";
        } else {
            my $fh = new FileHandle($_->{file}, 'w') or die "$_->{file} file open error:$!\n";
            $fh->binmode(":utf8");
            for(my $t = $_->begin(); !$t->eof(); $t = $t->next()) {
                $fh->print($t->text());
            }
            $fh->close();
        }
    }
}

exit;

sub getComment {
    my($begin, $end) = @_;

    my $comment = "";
    for(my $t = $begin; !$t->eof($end); $t = $t->next) {
        $comment .= $t->text;
        $t->delete;
    }
    # コメント解析
    $comment =~ s/^\/\*//;
    $comment =~ s/\*\/$//;
print "commnet = $comment\n" if $debug;
    my $lex = new LexicalAnalyzer({code=>$comment, debug=>$debug});
    # 日本語名取得とその行削除
    my $jp = $lex->begin->next('ident_.*');
    for(my $t = $jp->prev('space_\n'); !$t->eof($jp); $t = $t->next) {
        $t->delete
    }
    $lex->{name} = $jp->text;

    # "*"と先頭のスペースの削除
    for(my $t = $lex->begin; !$t->eof; $t = $t->next) {
        if(($t->prev->value eq "space_\n" || $t->prev->bof) && $t->value =~ /^(space_( +|\n)|op_\*)$/) {
            $t->delete;
        }
    }
     if($debug) {
        print "commnet = \n";
        for(my $t = $lex->begin; !$t->eof; $t = $t->next) {
            print "'".$t->value."'"
        }
    }
    return $lex;
}

