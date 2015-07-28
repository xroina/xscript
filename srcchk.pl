#!/usr/bin/perl

use strict;
use FileHandle;


my $file = $ARGV[0];
my $lines=[];
my $num;
{
	my $line="\r";
	my $fh = FileHandle->new($file);
	(chomp, $line .= "$_\r") while <$fh>;
	$fh->close;
	$_ = $line;

	s {/\*.*?\*/} [\r]gsx;		# コメント
	s/\/\/.*\r/\r/gsm;			# コメント(C++)
	s/\r\s*([^\r])/\r$1/gsm;	# ブランク削除
	s/([^\r])\s*\r/$1\r/gsm;	# ブランク削除
	s/[\t ]*\\\r//gsm;			# \cr を消す
	
	# インクルードを消す
	s/\#(include|undef)[^\r]*//gsm;
#	print("$_\n") foreach(/(\#define[^\r]*)/gsm);
#	print("$_\n") foreach(/\#define[^\r]*\{[^\r]*\}/gsm);
	s/\#define([^\r]*)\{([^\r]*)\}/define$1\{\r$2\r\}/gsm;
	s/\#define[^\r]*//gsm;

	# 変数宣言を消す
	s/\r\w+(?:\s+\w+)*(?:\s+|\s*\*\s*)[\w\[\]]+;//gsm;
	# キャストを消す
	s/(?:\*\s*)?\([\w\s\*&]*\)\s*&//gs;
	# 変数宣言+初期化
	s/\r\w+\s+([\w\[\]]+\s*=\s*[\w\{\}]+\s*[\w\[\]]*\s*;)/\r$1/gsm;
	s/(?:\*\s*)?\([\w\s\*&]*\)\s*([\(&a-zA-Z])/$1/gsm;

	s/\r\}\s*([^\r])/\r\}\r$1/gsm;
	
	#ifマクロの後ろに{をつける
	s/\r(\#if[^\r]*)/\r;\r$1\r\{\r/gsm;
	#endifマクロを}に変換
	s/\r(\#endif[^\r]*)/\r\;\r}\r/gsm;
	#elseマクロの前後に{}をつける
	s/\r\#else/\r\}\r;\r\#else\r\{\r/gsm;

	# 行末文字で分割
	foreach(/.*?[\:\;\{\}]\r/gsm) {
		s/\r//gsm;
		s/^\s+//gsm;	s/\s+$//gsm;	# ブランク削除
		s/^\;$//gsm;	#先頭;の削除
		push(@$lines, $_) if length;
	}
}
#{
#	my $fh = FileHandle->new(">l1.txt");
#	$fh->print(join"\n", @$lines);
#	$fh->close;
#	
#	my $fh = FileHandle->new(">l2.txt");
#	$fh->print($line);
#	$fh->close;
#}
#print join"\n", split "\r", $line;
#push(@$lines, $line) if length $line;
#foreach my $i(0..10){
#	print "$lines->[$i]\n";
#}

{
	# ネスト解析
	my $func = stack();
	
	# ステートメント解析
	my $l = fnc($func->{data});
	
	# ファイル出力
	my $fh = FileHandle->new(">$file.ss.txt");
	$fh->print(join "\n", @$l);
	$fh->close;

	exit;

	view($func);

	exit;
}

sub view{
	my $dat = shift;
	my $l   = shift;

	if( 'ARRAY' eq ref $dat ) {
		for(my $i=0; $i<=$#{$dat}; $i++){
			print(' ' x $l) if $i > 0;
			my $n = "[$i]->";
			print $n;
			view($dat->[$i], $l + length $n);
		}
		print("\n") if($#{$dat} < 0);
	}
	elsif( 'HASH' eq ref $dat ) {
		my $f = 0;
		foreach my $k (keys %$dat) {
			print(' ' x $l) if $f;
			my $n = "{$k}->";
			print $n;
			view($dat->{$k}, $l + length $n);
			$f = 1;
		}
	}
	else{
		print "'$dat'\n";
	}
}

sub fnc {
	my $dat = shift;
	my $ret = [];
	
	return $ret unless 'ARRAY' eq ref $dat;
	
	# ヘッダ
	my $hedder = '+------------------';
	my $fieldn = '| @@@@@@@@@@@@ |   ';
	my $field0 = '|              |   ';
	my $fotter = '+--------------    ';
	# フッダ追加処理
	my $fotterchg = sub {
		my ($ary, $sch, $chg) = @_;
		my ($a, $s) = ($#{$ary}, length $sch);
		return 0 unless $sch eq substr $ary->[$a], 0, $s;
		pop(@$ary) if $sch eq $ary->[$a];
		substr($ary->[$a], 0, $s) = $chg;
		return 1;
	};
	my $last;

	foreach my $d (@$dat) {
		$_ = $d->{method};

		next if 0 == length;

		my $line = [];
		my $l = {};
		my $flag = 0;

		my $openclose;		# 括弧の正規表現
		$openclose = qr/\(([^()]*(?:(??{$openclose})[^()]*)*)\)/;
		my ($dep) = /$openclose/;	# 最初の一つの括弧を取得
		my $aft = $';	#'			# 括弧の後の文字列取得
		$dep =~ s/^\s+//gs;	$dep =~ s/\s+$//gs;	# ブランク削除
		$aft =~ s/^\s+//gs;	$aft =~ s/\s+$//gs;	# ブランク削除
		$aft = "" unless $dep;
		my $hed = $dep ? '@' : 'o';
		my $status;

		if(/^(\#if\S*)\s+(\w+)/) {			# #if マクロ
			($hed, $dep, $flag) = ($1, $2, 1);
		}

		if(/^((if)|(for)|(switch))\s*\(/) {	# if/for/switch文
			($hed, $status) = ($1, $aft);
			$flag = 1 if $2;
			$flag = 2 if $3;
			$flag = 3 if $4;
		}
		elsif(/^(\#?else)/) {				# else(#elseマクロ込み)
			($hed, $flag) = ($1, 1);
			$fotterchg->($ret, $fotter, $field0);
			if(/if\s*\(/) {	$hed .= " if";	$status = $aft;	}
			else {	undef $dep;	}
		}
		elsif(/^(while|until)\s*\(/) {		# while/until文
			($hed, $flag) = ($1, 3);
			($status, $flag) = ($aft, 2) unless $last =~ /^do/;
		}
		elsif(/^do/) {						# do～while/until文
			($hed, $flag) = ('do', 2);
			undef $dep;
		}

		# ライン追加
		my $lineadd = sub {
			return unless @$ret;
			return if '|' eq $ret->[$#{$ret}];
			push @$ret, '|';
		};

		$lineadd->() if $ret->[$#{$ret}] =~ /^[^o]/;
		if('@' eq $hed && @{$d->{data}} > 0) {
			push(@$ret, "[ $_ ]");
			$lineadd->();
			$hed = $hedder;
		}

		# ステートメントだったら判定内容を展開
		if($flag) {
			my $h = $hedder;
			substr($h, 2, length $hed) = $hed;
			substr($h, -3, 1) = '>' if $flag == 1;
			substr($h, -4, 1) = '+' if $flag == 2;
			substr($h, -4) = '    ' if $flag == 3;
			push @$line, $h;

			if(defined $dep) {	# 判定内容を展開
				my $l = 0;		# @の文字数カウント
				$l++ while($fieldn =~ /\@/g);
				foreach my $b (unpack "a$l" x (1+ int(length($dep) / $l)), $dep) {
					my $a = $fieldn;
					$b = sprintf "%-${l}s", $b;
					$a =~ s/\@+/$b/;
					push @$line, $a;
				}
			}
			else {				# 判定無しなら空フィールド追加
				push @$line, $field0;
			}
		}
		elsif(1 == length $hed) {
			# 変数代入、関数呼出の追加
			push @$line, "$hed $_";
		}
		else {
			# サブフィールドあり
			push @$line, $hed, $field0;
			$flag = 1;
		}

		# 階層下の処理呼出
		my $n = fnc(length $status ? [ { method => $status, data => [] } ] : $d->{data});

		# 階層下と本体の結合処理
		if(@$n > 0) {
			$flag = 1;
			if(@$line > @$n) {	# 階層下のほうが少ない
				$line->[$_] = "$line->[$_]$n->[$_]" foreach 0..$#{$n};
			}
			else {				# 階層下の方が多い
				$line->[$_] = "$line->[$_]$n->[$_]" foreach 0..$#{$line};
				# 空フィールド＋階層下を追加
				push(@$line, "$field0$n->[$_]") foreach @$line..$#{$n};
				# フッダ追加処理
				$flag = 0 if $fotterchg->($line, $field0, $fotter);
			}
		}

		# フッタ追加
		push(@$line, $fotter) if $flag;

		push(@$ret, @$line);

		$last = $_;
	}
	return($ret);
}

# ネスト解析処理
sub stack {
	my ($method) = @_;
	my $dat = {data =>[]};
	
	$dat->{method} = $method if $method;
	
	while($num <= $#{$lines}) {
		my $line = $lines->[$num];
		($num++, next) unless length $line;
		if($line =~ s/^\}//) {	# ネスト減
			$lines->[$num] = $line;
			last;
		}elsif($line =~ s/\{$//) {	# ネスト
			$lines->[$num] = $line;
			$num++;
			push(@{$dat->{data}}, stack($line));
		}
		else {
			$num++;
			push(@{$dat->{data}}, {method => $line, data =>[]});
		}
	}
	return $dat;
}

#■ エスケープされていないダブルクォート
#$reg = qr/(?<!\\)(?:\\\\)*\"/;
#my @define = qw/__DEBUG __WRITELOG/; # define を指定する
# $src にソースを丸ごとつっこむ
# #if-#endif
#$src =~ s|^#if\s+(\w+)(.*?)^(#else(.*?))?^#endif|($1)?$2:$4|emsg;
# #ifdef-#endif
#$src =~ s|^#ifdef\s+(\w+)(.*?)^(#else(.*?))?^#endif|(grep {$_ eq $1 } @define)?$2:$4|emsg;
# #ifndef-#endif
#$src =~ s|^#ifndef\s+(\w+)(.*?)^(#else(.*?))?^#endif|(grep {$_ eq $1 } @define)?$4:$2|emsg;
