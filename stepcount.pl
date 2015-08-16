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

my $param = {javascript =>['Utility.js', 'TableOperation.js']};
Utility::getStartOption($param, ['debug', 'input=&', 'output=*', 'csv=*', 'help', 'xdg']);
$param->{help} = 1 unless @{$param->{path}};
my($progpath, $prog) = $0 =~ /^(.*?)([^\/]+)$/;
if($param->{help}) {
	print <<"USAGE";
usage $prog [OPTION]... [FILE]...

ソースのステップ数をカウントします。カウント方法は「C++ソースステップカウンタ.xls」に準じます。

OPTION:
  -i, -input [FILE]         ソースファイルの存在するパスを記したテキストファイルを指定します。
  -o, -output [FILE]        出力HTMLファイルを指定します。
                            指定しない場合は、stepcount_YYYYMMDDhhmmsshtml になります。
  -c, -csv [FILE]           出力CSVファイルを指定します。指定しない場合は、標準出力へ出力します。
  -x, -xdg                  出力後、ディフォルトブラウザを自動起動します。
  -h, -help                 このヘルプを表示します。

FILE:
  ソースファイルのパスを指定します。

NOTE:
  パスは再帰的に検索ますので、フォルダ内にtestコードがあるとそれもカウント対象になります。

USAGE
	exit 0;
}

{	# 日付算出処理
	my ($sec, $min, $hour, $day, $mon, $year) = localtime(time);
	$year += 1900;
	$mon += 1;
	$param->{date} = "$year/$mon/$day-$hour:$min:$sec";
	unless($param->{output}) {
		$param->{output} = sprintf("stepcount_%04d%02d%02d%02d%02d%02d.html", $year, $mon, $day, $hour, $min, $sec);
	}
}

# ここから本体
my $step = {};
# パスを再帰的に検索し、ステップカウントを実施する。
print "file, StepCount, CodeLineCount, CommentLineCount, EmptyLineCount, LineCount\n";
foreach my $path(@{Utility::getRecursivePath($param->{path}, 'h|hpp|c|cc|cpp')}) {
	my $src = LoadFile($path);
	next unless $src;
	my($brief) = $src =~ /^\s*\*\s*\@brief\s*(.*)$/mg;	# ファイルヘッダ取得
	$brief =~ s/^.*利用する//;
	$brief =~ s/[のを].*$//;

	# ステップ数, 有効行数, コメント行数, 空白行数, 全行数
	my ($CodeLineCount, $StepCount, $CommentLineCount, $EmptyLineCount, $LineCount) = CountLines($src);

	# ファイル名クラス名を求める
	my($file, $class) = $path =~ m#(([^/]+)\..*)$#;
	print "$file, $StepCount, $CodeLineCount, $CommentLineCount, $EmptyLineCount, $LineCount\n";

	# 集計用ハッシュへ登録する
	$step->{$path} = {
		file				=> $file,
		class				=> $class,
		name				=> $brief,
		StepCount			=> $StepCount,
		CodeLineCount		=> $CodeLineCount,
		CommentLineCount	=> $CommentLineCount,
		EmptyLineCount		=> $EmptyLineCount,
		LineCount			=> $LineCount,
	};
}

CreateHTML();

Utility::createSymLink();

system "xdg-open $param->{output} > /dev/null 2>&1 &" if $param->{xdg};

exit;

# ステップカウントの結果をHTMLに出力する。
sub CreateHTML {
	use CGI;
	CGI::charset("utf-8");
	my $q = new CGI;

	use FileHandle;
	my $fh = new FileHandle($param->{output}, 'w') or die "'$param->{output}' file open error:$!\n";
	$fh->binmode(":utf8");

	my $title = "C++ステップカウンタ($param->{date})";
	$fh->print($q->start_html(-title=>$title, -lang =>'ja',
		-head=>[
			$q->meta({
				'http-equiv'=>'Content-Type',
				-content	=>'text/html; charset=UTF-8'}),
			$q->meta({-charset=>'UTF-8'}),
			$q->Link({-rel=>'stylesheet', href=>'css/base.css'}),
			(map{ $q->script({-type=>'text/javascript', -src=>"js/$_"}, "") } @{$param->{javascript}}),
			$q->script({-langage=>"text/javascript"}, "<!--\n", <<'JAVASCRIPT'

var ohead;
var obody;
var ofoot;

function doMarge() {
	ohead.doMarge();
	obody.doMarge();
	ofoot.doMarge();
}

function unMarge() {
	ohead.unMarge();
	obody.unMarge();
	ofoot.unMarge();
}

function ToggleMarge() {
	if(obody.marge) unMarge();
	else doMarge();
}

var sortchr = {'desc':'▲', 'asc':'▼', 'no':'▶'};

AddEvent(window, 'load', function() {
	ohead = new TableOperation('table_head');
	obody = new TableOperation('table_body');
	ofoot = new TableOperation('table_foot');
	doMarge();

	for(var i = 0; i < ohead.rows; i++) {
		var ths = ohead.getTR(i).getElementsByTagName('th');
		for(var j in ths) {
			if(!ths[j].innerHTML || ths[j].innerHTML.match(/^\s*$/)) continue;
			var span = document.createElement('span');
			span.style.color = 'blue';
			ths[j].appendChild(span);
			AddEvent(ths[j], 'click', function() { Sort(this); });
		}
	}
	AddSortChar();
});

function Sort(tag) {
	obody.doSort(tag.ColIndex, tag.colSpan);
	AddSortChar();
	var span = tag.getElementsByTagName('span');
	span[0].innerHTML = sp + sortchr[obody.head[tag.ColIndex].sort];
}

function AddSortChar() {
	for(var i = 0; i < ohead.rows; i++) {
		var ths = ohead.getTR(i).getElementsByTagName('th');
		for(var j in ths) {
			if(!ths[j].innerHTML || ths[j].innerHTML.match(/^\s*$/)) continue;
			var span = ths[j].getElementsByTagName('span');
			span[0].innerHTML = sp + sortchr.no;
		}
	}
}
JAVASCRIPT
			, '// -->')
	   ]
	));

	$fh->print($q->h1("C++ステップカウンタ 作成日時：($param->{date})"), "\n");
	$fh->print($q->input({-type=>'button', -value=>'表示切替', -onclick=>'ToggleMarge();'}));

	$fh->print($q->start_table, "\n");

	$fh->print($q->start_thead({-id=>'table_head'}), "\n");
	$fh->print($q->start_Tr({-align=>'center', -valign=>'top'}), "\n");
	$fh->print($q->th(['no','path','','','','','','','','','','','','','','','','file','Class','和名','行数',    '',    '',      '',    '',    '比率',   '',   '',        '',    '新規<br>(step)']), "\n");
	$fh->print($q->end_Tr, "\n");

	$fh->print($q->start_Tr({-align=>'center', -valign=>'top'}), "\n");
	$fh->print($q->th(['', '',	   '','','','','','','','','','','','','','','','',    '',     '',   'ステップ','有効','コメント','空白','合計','ステップ','有効','コメント','空白','']), "\n");
	$fh->print($q->end_Tr, "\n");
	$fh->print($q->end_thead, "\n");

	my $sum = {StepCount=>0, CodeLineCount=>0, CommentLineCount=>0, EmptyLineCount=>0, LineCount=>0};
	$fh->print($q->start_tbody({-id=>'table_body'}), "\n");
	my $count = 0;
	foreach my $path(sort{$a cmp $b} keys %$step) {
		$count++;

		my $data = $step->{$path};

		$fh->print($q->start_Tr({-align=>'right', -valign=>'top'}), "\n");
		my $td = [];
		$td->[0] = $q->td($count);
		my $col = 1;
		$td->[$_] = $q->td({-align=>'left'}) foreach 1..19;
		foreach(split "/", $path) {
			next unless $_;
			next if $_ eq $data->{file};
			$td->[$col] = $q->td({-align=>'left'}, $_);
			$col++;
		}

		$td->[17] = $q->td({-align=>'left'}, $data->{file});	# ファイル名
		$td->[18] = $q->td({-align=>'left'}, $data->{class});	# クラス名(想定)
		$td->[19] = $q->td({-align=>'left'}, $data->{name});	# 日本語名

		$td->[20] = $q->td({-class=>'nomarge'}, $data->{StepCount});
		$td->[21] = $q->td({-class=>'nomarge'}, $data->{CodeLineCount});
		$td->[22] = $q->td({-class=>'nomarge'}, $data->{CommentLineCount});
		$td->[23] = $q->td({-class=>'nomarge'}, $data->{EmptyLineCount});
		$td->[24] = $q->td({-class=>'nomarge'}, $data->{LineCount});
		$td->[25] = $q->td({-class=>'nomarge'}, ParLine($data->{StepCount}, $data->{LineCount}));
		$td->[26] = $q->td({-class=>'nomarge'}, ParLine($data->{CodeLineCount}, $data->{LineCount}));
		$td->[27] = $q->td({-class=>'nomarge'}, ParLine($data->{CommentLineCount}, $data->{LineCount}));
		$td->[28] = $q->td({-class=>'nomarge'}, ParLine($data->{EmptyLineCount}, $data->{LineCount}));
		$td->[29] = $q->td({-class=>'nomarge'}, $data->{StepCount});

		$sum->{StepCount}		+= $data->{StepCount};
		$sum->{CodeLineCount}	+= $data->{CodeLineCount};
		$sum->{CommentLineCount}+= $data->{CommentLineCount};
		$sum->{EmptyLineCount}	+= $data->{EmptyLineCount};
		$sum->{LineCount}		+= $data->{LineCount};


		$fh->print($_) foreach @$td;

		$fh->print("\n", $q->end_Tr, "\n");
	}
	$fh->print($q->end_tbody, "\n");

	$fh->print($q->start_tfoot({-id=>'table_foot'}), "\n");
	$fh->print($q->start_Tr({-align=>'right', -valign=>'top'}), "\n");
	my $th = [];
	$th->[$_] = $q->th('') foreach 0..19;
	$th->[0] = $q->th('合計');
	$th->[20] = $q->th($sum->{StepCount});
	$th->[21] = $q->th($sum->{CodeLineCount});
	$th->[22] = $q->th($sum->{CommentLineCount});
	$th->[23] = $q->th($sum->{EmptyLineCount});
	$th->[24] = $q->th($sum->{LineCount});
	$th->[25] = $q->th(ParLine($sum->{StepCount}, $sum->{LineCount}));
	$th->[26] = $q->th(ParLine($sum->{CodeLineCount}, $sum->{LineCount}));
	$th->[27] = $q->th(ParLine($sum->{CommentLineCount}, $sum->{LineCount}));
	$th->[28] = $q->th(ParLine($sum->{EmptyLineCount}, $sum->{LineCount}));
	$th->[29] = $q->th($sum->{StepCount});
	$fh->print($_) foreach @$th;
	$fh->print("\n", $q->end_Tr, "\n");
	$fh->print($q->end_tfoot, "\n");

	$fh->print($q->end_table, "\n");
	$fh->print($q->end_html);
	$fh->close();

}

# パーセントを出力する処理
sub ParLine {
	my($line, $base) = @_;
	return '&nbsp;' unless defined $base;
	return '&nbsp;' unless defined $line;
	return '&nbsp;' if $base <= 0;

	my $par = $line / $base * 100;
	$par = 0 if $par > 100;
	int($par + 0.5) . "%";
}

# ここからがエクセルからの移植部位
# ソースファイル解析クラス(元ソース SourceFile.cls)

# ソースファイル読み取る処理
sub LoadFile {
	my($FilePath) = @_;
	# 1.処理前チェック
	# 1.1.フォルダの場合処理できない
	# 1.2.処理済みの場合処理する必要はない
	# 2.ファイル内容読取
	# 2.1.エンコード違いによる異常発生対処 -> 自動判定のため不要
	# 2.2.ADODBの機能を利用して読み取る -> FileHandleで読む
	use FileHandle;
	my $fh = new FileHandle($FilePath) or die "$FilePath file open error:$!\n";
	$fh->binmode;
	my $SourceTxt = join '', <$fh>;				# ソースファイルの全内容
	$fh->close;
	# 2.3.改行コード統一処理（LinuxでもWindowsでも同様に対応できるように、改行をLineFeed「"\n"」に統一）
	$SourceTxt =~ s/\015\012|\012|\015/\n/gm;
	return Utility::toUTF8($SourceTxt);
}

# ステップ、有効行、コメント行、空白行、それぞれの数値と合計を計算する処理
sub CountLines {
	my($SourceTxt) = @_;								# ソースファイルの全内容
	my $first = ''; # String							# 行の最初文字（有効ソース範囲）
	my $last = ''; # String								# 行の最後文字（有効ソース範囲）
	my $ss = '';										# ソース解析状態
	my $st = '';										# 行タイプ
	my $emptyLines = 0; # Long							# 空白行数
	my $commentLines = 0; # Long						# コメント行数
	my $codeLines = 0; # Long							# 有効行数
	my $stepLines = 0; # Long							# ステップ数

	# 行結末処理
	my $FinishLine = sub {								# 1.行数カウントアップ処理
		# 1.1.ソース解析状態によって違う処理をする
		if($st eq 'code') {								# 1.2.有効行の場合
			$codeLines++;								# 1.2.1.有効行数カウントアップ
			# 1.2.2.最初文字と最後文字によってステップ数カウントアップする
			$stepLines++ if $last =~ /^[;\{\}:]$/ || $first eq "#";
			$first = $last = '';						# 1.2.3.行の最初文字と行の最後文字をリセットする
		}
		elsif($st eq 'comment') {						# 1.3.コメントの場合
			$commentLines++;							# 1.3.1.コメント行数カウントアップ
		}
		elsif($st eq '') {								# 1.4.空白行の場合
			$emptyLines++;								# 1.4.1.空白行行数カウントアップ
		}
	};

	# 1.処理前チェック
	# 1.1.拡張子チェック(h, cpp, cのみ処理できる）
	# 1.2.フォルダの場合計算できない

	# 2.初期処理
	# 2.1.ソース解析状態、行タイプを初期値にセット
	# 2.2.1番目の文字から解析し始める
	# 3.解析処理
	my $code = ['', split(//, $SourceTxt), ''];
	for(my $i = 1; $i < $#$code; $i++) {				# 3.1.順番に1文字ずつ処理していく（文字をスキップすることもある）
		my $prevCh = $code->[$i - 1];					# 3.1.1.前文字取得
		my $ch = $code->[$i];							# 3.1.2.現文字取得
		my $nextCh = $code->[$i + 1];					# 3.1.3.次文字取得

		# 3.1.4.現在のソース解析状態を判断した上で違う処理をする
		if($ss eq 'code') {								# 3.1.5.有効ソースの場合
			# 3.1.5.1.現文字を判断した上で違う処理をする
			if ($ch eq '"') {							# 3.1.5.2.二重引用符の場合
				$ss = '"';								# 3.1.5.2.1.ソース解析状態を二重引用にする
				$last = $ch;							# 3.1.5.2.2.行の最後文字は現文字にする
			}
			elsif ($ch eq "'") {						# 3.1.5.3.引用符の場合
				$ss = "'";								# 3.1.5.3.1.ソース解析状態を引用にする
				$last = $ch;							# 3.1.5.3.2.行の最後文字は現文字にする
			}
			elsif ($ch eq '/') {						# 3.1.5.4.スラッシュの場合
				if($nextCh eq '/') {					# 3.1.5.4.1.次文字もスラッシュの場合
					$ss = 'single';						# 3.1.5.4.1.1.ソース解析状態をシングル行コメントにする
					$st = 'comment' if $st eq '';		# 3.1.5.4.1.2.行タイプは空白の場合、コメントにする（1回有効行と判断したらもうコメントに変えられない)
					$i++;								# 3.1.5.4.1.3.次文字は分かったのでスキップする
				}
				elsif($nextCh eq '*') {					# 3.1.5.4.2.次文字は星印の場合
					$ss = 'multi';						# 3.1.5.4.2.1.ソース解析状態をマルチ行コメントにする
					$st = 'comment' if $st eq '';		# 3.1.5.4.2.2.行タイプは空白の場合、コメントにする（1回有効行と判断したらもうコメントに変えられない)
					$i++;								# 3.1.5.4.2.3.次文字は分かったのでスキップする
				}
				else {									# 3.1.5.4.3.次文字は上記以外の場合
					$last = $ch;						# 3.1.5.4.3.1.行の最後文字は現文字にする
				}
			}
			elsif($ch eq "\n") {						# 3.1.5.5.改行の場合
				$ss = '';								# 3.1.5.5.1.ソース解析状態を初期値にする
				&$FinishLine;							# 3.1.5.5.2.行の結末処理をする
				$st = '';								# 3.1.5.5.3.行タイプを初期値に戻す
			}
			elsif($ch =~ /^\s$/) {						# 3.1.5.6.スペースまたはタブの場合
				# 3.1.5.6.1.何もしない
			}
			else {										# 3.1.5.7.上記以外の場合
				$last = $ch;							# 3.1.5.7.1.行の最後文字は現文字にする
			}
		}
		elsif($ss eq '"') {								# 3.1.6.二重引用の場合
			# 3.1.6.1.現文字を判断した上で違う処理をする
			if ($ch eq '"') {							# 3.1.6.2.二重引用符の場合
				if($prevCh eq '\\') {					# 3.1.6.2.1.前文字は「\」の場合（無視できる二重引用符）
					# 3.1.6.2.1.1.何もしない
				}
				elsif($nextCh eq '"') {					# 3.1.6.2.2.次文字も二重引用符の場合（二重引用符の中に、二重引用符が２つ連続する場合、無視できる）
					$i++;								# 3.1.6.2.2.1次文字は分かったのでスキップする
				}
				else {									# 3.1.6.2.3.上記以外の場合検討
					$ss = 'code';						# 3.1.6.2.3.1.ソース解析状態を有効ソースにする
				}
				$last = $ch;							# 3.1.6.2.4.行の最後文字は現文字にする
			}
			elsif($ch eq "\n") {						# 3.1.6.3.改行の場合
				$ss = '';								# 3.1.6.3.1.ソース解析状態を初期値にする
				&$FinishLine;							# 3.1.6.3.2.行を結末する
				$st = '';								# 3.1.6.3.3.行タイプを空白行（初期値として）にする
			}
			else {										# 3.1.6.4.上記以外の場合
				$last = $ch;							# 3.1.6.4.1.行の最後文字は現文字にする
			}
		}
		elsif($ss eq '') {								# 3.1.7.初期状態の場合
			# 3.1.7.1.現文字を判断した上で違う処理をする
			if ($ch eq '"') {							# 3.1.7.2.二重引用符の場合
				$ss = '"';								# 3.1.7.2.1.ソース解析状態を二重引用にする
				$st = 'code';							# 3.1.7.2.2.行タイプを有効ソースにする
				$first = $ch if 0 == length $first;		# 3.1.7.2.3.行の最初文字を現文字にする
				$last = $ch;							# 3.1.7.2.4.行の最後文字を現文字にする
			}
			elsif ($ch eq "'") {						# 3.1.7.2.引用符の場合
				$ss = "'";								# 3.1.7.2.1.ソース解析状態を引用にする
				$st = 'code';							# 3.1.7.2.2.行タイプを有効ソースにする
				$first = $ch if 0 == length $first;		# 3.1.7.2.3.行の最初文字を現文字にする
				$last = $ch;							# 3.1.7.2.4.行の最後文字を現文字にする
			}
			elsif ($ch eq '/') {						# 3.1.7.3.スラッシュの場合
				if($nextCh eq '/') {					# 3.1.7.3.1.次文字はスラッシュの場合
					$ss = 'single';						# 3.1.7.3.1.1.ソース解析状態をシングル行コメントにする
					$st = 'comment' if $st eq '';		# 3.1.7.3.1.2.行タイプをコメントにする
					$i++;								# 3.1.7.3.1.3.次文字は分かったのでスキップする
				}
				elsif($nextCh eq '*') {					# 3.1.7.3.2.次文字は星印の場合
					$ss = 'multi';						# 3.1.7.3.2.1.ソース解析状態をマルチ行コメントにする
					$st = 'comment' if $st eq ''	;	# 3.1.7.3.2.2.行タイプをコメントにする
					$i++;								# 3.1.7.3.2.3.次文字は分かったのでスキップする
				}
				else {									# 3.1.7.3.3.上記以外の場合
					$ss = 'code';						# 3.1.7.3.3.1.ソース解析状態を有効ソースにする
					$first = $ch if 0 == length $first;	# 3.1.7.3.3.2.行の最初文字を現文字にする
					$last = $ch;						# 3.1.7.3.3.3.行の最後文字を現文字にする
				}
			}
			elsif($ch =~ /^\s$/) {						# 3.1.7.4.スペースまたはタブの場合
				# 3.1.7.4.1.何もしない
			}
			elsif($ch eq "\n") {						# 3.1.7.5.改行の場合
				&$FinishLine;							# 3.1.7.5.1.行を結末する
				$st = '';								# 3.1.7.5.2.行タイプを空白行（初期値として）にする
			}
			else {										# 3.1.7.6.上記以外の場合
				$ss = 'code';							# 3.1.7.6.1.ソース解析状態を有効ソースにする
				$st = 'code';							# 3.1.7.6.2.行タイプを有効行にする
				$first = $ch if 0 == length $first;		# 3.1.7.6.3.行の最初文字を現文字にする
				$last = $ch;							# 3.1.7.6.4.行の最後文字を現文字にする
			}
		}
		elsif($ss eq 'multi') {							# 3.1.8.マルチ行コメントの場合
			# 3.1.8.1.現文字を判断した上で違う処理をする
			if($ch eq '*') {							# 3.1.8.2.星印の場合
				if($nextCh eq '/') {					# 3.1.8.2.1.次文字はスラッシュの場合
					$ss = '';							# 3.1.8.2.1.1.ソース解析状態を初期値にする
					$i++;								# 3.1.8.2.1.2.次文字は分かったのでスキップする
				}
			}
			elsif($ch eq "\n") {						# 3.1.8.3.改行の場合
				&$FinishLine;							# 3.1.8.3.1.行を結末する
				$st = 'comment';						# 3.1.8.3.2.行タイプをコメントにする
			}
			else {										# 3.1.8.4.上記以外の場合
				# 3.1.8.4.1.何もしない
			}
		}
		elsif($ss eq 'single') {						# 3.1.9.シングル行コメントの場合
			# 3.1.9.1.現文字を判断した上で違う処理をする
			if($ch eq "\n") {							# 3.1.9.2.改行の場合
				$ss = '';								# 3.1.9.2.1.ソース解析状態を初期値にする
				&$FinishLine;							# 3.1.9.2.2.行を結末する
				$st = '';								# 3.1.9.2.3.行タイプを空白行（初期値として）にする
			}
			else {										# 3.1.9.3.上記以外の場合
				# 3.1.9.3.1.何もしない
			}
		}
		elsif($ss eq "'") {								# 3.1.10.引用符の場合
			# 3.1.10.1.現文字を判断した上で違う処理をする
			if($ch eq "'") {							# 3.1.10.2.引用符の場合
				if($prevCh eq '\\') {					# 3.1.10.2.1.前文字は\の場合（無視できる）
					# 3.1.10.2.1.1.何もしない
				}
				else {									# 3.1.10.2.2.上記以外の場合
					$ss = 'code';						# 3.1.10.2.2.1.ソース解析状態を有効ソースにする
				}
				$last = $ch;							# 3.1.10.2.3.行の最後文字を現文字にする
			}
			elsif($ch eq "\n") {						# 3.1.10.3.改行の場合
				$ss = '';								# 3.1.10.3.1.ソース解析状態を初期値にする
				&$FinishLine;							# 3.1.10.3.2.行を結末する
				$st = '';								# 3.1.10.3.3.行タイプを空白行（初期値として）にする
			}
			else {										# 3.1.10.4.上記以外の場合
				$last = $ch;							# 3.1.10.4.1.行の最後文字を現文字にする
			}
		}
	}
	# 3.2.行を結末する（最後の改行コードはない。最後の文字が改行になってもその後ろは空白行が1行あると取り扱う）
	&$FinishLine;
	# 3.3.計算結果を返却する
	return($codeLines, $stepLines, $commentLines, $emptyLines, $codeLines + $commentLines + $emptyLines);
}
