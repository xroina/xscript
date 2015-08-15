#!/usr/bin/perl

BEGIN {
    unshift @INC, map "$_/lib", $0 =~ /^(.*?)[^\/]+$/;
    unshift @INC, map "$_/lib", readlink($0) =~ /^(.*?)[^\/]+$/ if -l $0;
}

use strict;
use warnings;
use utf8;

use Utility;

binmode STDIN , ':utf8';
binmode STDOUT, ':utf8';

my $param = {width=>115, padding=>10};
Utility::getStartOption($param, ['output=*', 'width=#', 'padding=#', 'help']);
my($progpath, $prog) = $0 =~ /^(.*?)([^\/]+)$/;
if($param->{help}) {
    print <<"USAGE";
usage $prog [OPTION]...

diff結果をソースレビュー可能なテキストに変換しつつ、ステップ数をカウントします。

INPUT
  通常は標準入力を利用します。エンコードはUTF-8でお願いします

OPTION:
  -o, -output [FILE]        出力ファイルを指定します。
                            指定しない場合は、標準出力へ出力します。
  -w, -width [width]        ソースファイル+行番号の幅を指定します。(省略時115文字)
                            行番号は4文字＋区切り文字の計5文字使用します
  -p, -padding [padding]    比較元と比較先の間の文字数を指定します。(省略時10文字)
                            最低でも6文字の偶数を指定してください。
                            (それ以外はどうなっても保証できません。)

NOTE
  入力のdiffオプションで、ユニファイド diff(-u または -U [NUM])を指定してください。
  その他の方式はサポートしていません。
  差分での空白無視などの指定はdiffのオプションで指定してください。
  diffの-pオプション(C関数表示)にも対応しています。

SAMPLE
  diff -bptwBE -U 5 旧ファイル 新ファイル | diffcount > 差分ファイル
  diff -rbptwBE -U 5 旧フォルダ 新フォルダ | diffcount > 差分ファイル

USAGE

    exit 0;
}

my $ln = '+' . ('-' x ($param->{width} - 2)) . '+';
my $padstr  = ' ' x $param->{padding};
my $LINE_LEN = 4;
my $line = [];
my $buf = {left=>{line=>[]}, right=>{line=>[]}};
my $STEP_INIT = {add=>0, del=>0};
my $sumfile = 0;
while(<STDIN>) {
    chomp;
    my $index = @$line;

    # ステップカウント
    if(/^([ \-\+])(.*)$/ && $buf->{file}) {
        my $op;
        $op = 'del' if $1 eq '-';
        $op = 'add' if $1 eq '+';
        my $str = $2;
        $str =~ s#/\*.*?\*/##;  # 複数行コメントが１行に現れた場合の対処
        my $cm_end = $str =~ s#^.*?\*/##;  # 複数行コメントの終わり
        undef $cm_end, delete $buf->{step}->{comment} if $buf->{step}->{comment} && $cm_end;
        unless($buf->{step}->{comment}) {
            # 複数行コメントの終わりが先に現れた場合そこまでのカウントはなかったことにする。
            delete $buf->{step} if $cm_end;
            $str =~ s#//.*$##;      # 一行コメントの除去
            $buf->{step}->{comment} = 1 if $str =~ s#/\*.*$##;    # 複数行コメントマークとその後ろの文字除去
            $str =~ s/^\s*#.*$//;  # defineとかincludeとかカウントしない
            $str =~ s/[^\w]//g;    # 英数_以外の除去
            if($op && $str) {
                $buf->{step} = {} unless exists $buf->{step};
                $buf->{step}->{$op} = 0 unless exists $buf->{step}->{$op};
                $buf->{step}->{$op}++ 
            }
        }
    }

    my $flag;
    # 差分出力
    if(/^\//) {
        push @$line, $_;
        delete $buf->{file};
        $flag = 1;
    }
    elsif(/^diff/) {
        die "diffは-uまたは-Uを指定して実行してください\n" unless /\-\w*?u/i;
        push @$line, $_;
        delete $buf->{file};
        $flag = 1;
    }
    elsif(/^\-{3}\s*(.*?)\s*(\d+-\d+-\d+\s+\d+:\d+:[\d]+)/) {
        $buf->{file} = $1;
        $buf->{tm}   = $2;
        $flag = 1;
    }
    elsif(/^\+{3}\s*(.*?)\s*(\d+-\d+-\d+\s+\d+:\d+:[\d]+)/) {
        my $file = $1;
        my $tm   = $2;
        push @$line, '';
        push @$line, join $padstr,
            Left("file:". substr($buf->{file}, -($param->{width} - 5)), $param->{width}),
            Left(substr($file, -$param->{width}), $param->{width});
        push @$line, join $padstr,
            Left("time:$buf->{tm}", $param->{width}),
            Left($tm, $param->{width});
        delete $buf->{step};
        delete $buf->{stepcount};
    }
    elsif(/^\@\@\s*\-(\d+),(\d+)\s*\+(\d+),(\d+)\s*\@\@(.*)$/) {
        $buf->{left}->{count}  = $1;
        $buf->{right}->{count} = $3;
        push @$line, '';
        push @$line, "[[[ メソッド:$5 ]]]", '' if $5;
        sumcount();
    }
    elsif(/^ (.*)$/) {
        push @$line, ' ' . linemake($buf->{left}->{count}, $1) . ' ';
        $buf->{left}->{count}++;
        $buf->{right}->{count}++;
    }
    elsif(/^\-(.*)$/) {     # 削除または修正
        push @{$buf->{left}->{line}},  '|'.linemake($buf->{left}->{count}, $1).'|';
        $buf->{left}->{count}++;
        next;
    }
    elsif(/^\+(.*)$/) {     # 追加
        push @{$buf->{right}->{line}}, '|'.linemake($buf->{right}->{count}, $1).'|';
        $buf->{right}->{count}++;
        next;
    }

    my $leftlen  = @{$buf->{left}->{line}};
    my $rightlen = @{$buf->{right}->{line}};
    if($leftlen && $rightlen) {     # 更新
        my $len = $leftlen > $rightlen ? $leftlen : $rightlen;
        my $pad = '-' x int(($param->{padding} - 6) / 2);
        $pad =  Left("$pad(変更)$pad", $param->{padding});
        splice @$line, $index, 0, ("$ln$padstr$ln",
            map{
                my $left  = $buf->{left}->{line}->[$_];
                my $right = $buf->{right}->{line}->[$_];
                $left  = $ln if $leftlen  == $_;
                $right = $ln if $rightlen == $_;
                $left = Left('', $param->{width}) unless defined $left;
                $right = '' unless defined $right;
                my $ret = "$left$pad$right";
                $pad = $padstr;
                $ret;
            } (0..$len));
    }
    elsif($leftlen) {               # 削除
        my $pad = '-' x int(($param->{padding} - 6) / 2);
        $pad =  Left("$pad(削除)$pad", $param->{padding});
        splice @$line, $index, 0, ($ln,
            map{
                my $left  = $buf->{left}->{line}->[$_];
                $left = $ln if $leftlen == $_;
                my $ret = "$left$pad";
                $pad = '';
                $ret;
            } (0..$leftlen));
    }
    elsif($rightlen) {              # 追加
        my $pad = '-' x int(($param->{padding} - 6) / 2);
        $pad =  Left("$pad(追加)$pad", $param->{padding});
        my $left = Left('', $param->{width});
        my $leftline = '-' x $param->{width};
        splice @$line, $index, 0, ("$left$padstr$ln",
            map{
                my $right = $buf->{right}->{line}->[$_];
                $right = $ln if $rightlen  == $_;
                my $ret = "$leftline$pad$right";
                $pad = $padstr;
                $leftline = $left;
                $ret;
            } (0..$rightlen));
    }
    $buf->{left}->{line}  = [];
    $buf->{right}->{line} = [];

    sumout($index) if $flag;
}
sumout(0+@$line);

print "$_\n" foreach @$line;

if($sumfile > 1) {
    my $add = $buf->{allcount}->{add}; $add = 0 unless $add;
    my $del = $buf->{allcount}->{del}; $del = 0 unless $del;
    print "\n";
    print "[[[ 全合計 ]]]\n";
    print ' 追加 : '. substr((' ' x 5).$add, -5).' step', "\n";
    print ' 削除 : '. substr((' ' x 5).$del, -5).' step', "\n";
    print ' 合計 : '. substr((' ' x 5).($add+$del), -5).' step', "\n";
    print ' 差分 : '. substr((' ' x 5).($add-$del), -5).' step', "\n";
}

exit;

sub linemake {
    my($count, $text) = @_;
    return Left(substr((' ' x $LINE_LEN).$count, -$LINE_LEN).":$text", $param->{width} - 2);
}

sub sumcount {
    return unless $buf->{step};
    $buf->{stepcount} = {%$STEP_INIT} unless exists $buf->{stepcount};
    $buf->{allcount}  = {%$STEP_INIT} unless exists $buf->{allcount};
    
    foreach my $k(keys %$STEP_INIT) {
        next unless $buf->{step}->{$k};
        next unless $buf->{step}->{$k} =~ /^(\d+)$/;
        $buf->{stepcount}->{$k} += $1;
        $buf->{allcount}->{$k}  += $1;
    }
    delete $buf->{step};
}

sub sumout {
    my($index) = @_;
    return unless $buf->{step};
    sumcount();
    my $ary = [];
    if($buf->{stepcount}) {
        my $add = $buf->{stepcount}->{add};
        my $del = $buf->{stepcount}->{del};
        push @$ary, ' 追加 : '. substr((' ' x $LINE_LEN).$add, -$LINE_LEN).' step';
        push @$ary, ' 削除 : '. substr((' ' x $LINE_LEN).$del, -$LINE_LEN).' step';
        push @$ary, ' 合計 : '. substr((' ' x $LINE_LEN).($add+$del), -$LINE_LEN).' step';
        push @$ary, ' 差分 : '. substr((' ' x $LINE_LEN).($add-$del), -$LINE_LEN).' step';
        delete $buf->{stepcount};
    } else {
        push @$ary, ' 追加 : '. (' ' x ($LINE_LEN-1)).'0 step';
        push @$ary, ' 削除 : '. (' ' x ($LINE_LEN-1)).'0 step';
        push @$ary, ' 合計 : '. (' ' x ($LINE_LEN-1)).'0 step';
        push @$ary, ' 差分 : '. (' ' x ($LINE_LEN-1)).'0 step';
    }
    splice @$line, $index, 0, ('', @$ary, '');
    $sumfile += 1;
}

sub Left {
    my($str, $len) = @_;
    $str = '' unless defined $str;
    my $ret = '';
    my $col = 0;
    foreach(split //, $str) {
        my $l = /[\x00-\x7f]/ ? 1 : 2;
        last if ($col + $l) > $len;
        $col += $l;
        $ret .= $_;
    }
    foreach($col..($len-1)) {
        $ret .= ' ';
    }
    return $ret;
}


