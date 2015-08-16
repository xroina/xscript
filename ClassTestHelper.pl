#!/usr/bin/perl

BEGIN {
	unshift @INC, map "$_/lib", $0 =~ /^(.*?)[^\/]+$/;
	unshift @INC, map "$_/lib", readlink($0) =~ /^(.*?)[^\/]+$/ if -l $0;
}

use strict;
use warnings;
use utf8;

use FileHandle;
use Encode;

use Utility;
use LexicalAnalyzer;

binmode STDIN , ':utf8';
binmode STDOUT, ':utf8';

# コマンド引数の取得
my $param = {javascript =>['Utility.js', 'TableOperation.js']};
Utility::getStartOption($param, ['debug', 'input=&', 'output=*', 'title=*', 'help', 'xdg']);
$param->{help} = 1 unless @{$param->{path}};
my($progpath, $prog) = $0 =~ /^(.*?)([^\/]+)$/;
if($param->{help}) {
	print <<"USAGE";
usage $prog [OPTION]... [SORCE FILE]...

ソースファイルを元に試験項目表を作成します。

OPTION:
  -i, -input [FILE]         ソースファイルの存在するパスを記したテキストファイルを指定します。
  -o, -output [HTML]        出力先HTMLを指定します。
                            指定しない場合は、入力したソースファイルから適当に決定されます。
  -t, -title [TITLE]        HTMLのタイトルを指定します。
                            指定しない場合は、入力したソースファイルから適当に決定されます。
  -x, -xdg                  出力後、ディフォルトブラウザを自動起動します。
  -d, -debug                デバックモードで起動します。
                            デバックモードでは標準出力に大量のログを出力します
  -h, -help                 このヘルプを表示します。
USAGE
    exit 0;
}

my($title) = $param->{path}->[0] =~ /([^\/]+)\..+?$/;
$title = $prog unless $title;
$title = 'test' . $title;
$param->{output} = "$title.html" unless $param->{output};
$param->{title}  = $title        unless $param->{title};

my $class_name = $title;		# TODO classname処理
my $namespace_name = '.*';		# TODO namespace処理

my $test = {path=>[]};
foreach my $path(@{Utility::getRecursivePath($param->{path}, 'h|hpp|c|cc|cpp')}) {
	my($file, $name, $h) = $path =~ m#(([^/]+)\.(.+?))$#;
	my $lex = new LexicalAnalyzer({file=>$path, debug=>$param->{debug}});
	$lex->AnalyzeCPP();
	push @{$test->{path}}, {path=>$path, file=>$file, name=>$name, h=>$h, lex =>$lex};
}

my $lex;
foreach(sort{
	my $ret = $a->{name} cmp $b->{name};
	$ret = $b->{h} cmp $a->{h} unless $ret;
	$ret;
} @{$test->{path}}) {
	if($lex) { $lex->end->add($_->{lex}->begin); $lex->{end} = $_->{lex}->{end}; }
	else { $lex = $_->{lex}; }
}

for(my $t = $lex->{begin}; !$t->eof; $t = parse($t)) {}

# クラス変数のコメントを取得する
foreach my $ns(grep{/^(namespace|class)_/} keys %$test) {
	my $class = $test->{$ns};
	if($class && 'ARRAY' eq ref $class->{valiable}) {
		foreach my $t(@{$class->{valiable}}) {
			my $tt = $t->next('(space|comment)_.*')->next('!(space|comment)_.*');
			my $comment = getComment($t, $tt);
			$comment =~ s/^\s*(.*?)\s*$/$1/m;
			$t->{comment} = $comment;
		}
	}
}

CreateHtml();

Utility::createSymLink();

system "xdg-open $param->{output} > /dev/null 2>&1 &" if $param->{xdg};

debug("END");

exit;

sub parse {
	my($t) = @_;
	my $prev = $t;
	$t = $t->next('!(space|comment).*');

	$_ = $t->value();
#print("stack $stack->[0]->{file}($stack->[0]->{line}):".$stack->[0]->value() ."\n");
#print("tuple $t->{file}($t->{line}):$_\n");
	if(/^directive_/)  {	 # TODO プリプロセッサ用処理
		$t = $t->next("space_\n");
	}
	elsif(/^accsess_/) {
		$t = $t->next;
	}
	elsif(/^op_[;,]$/) {	# 文の終わり
		$t = statement($prev->{token}->[0], $t);
	}
	elsif(/^op_([\(\{\[])$/) {	 # 括弧
		my $bounce = $1;
		my $this = $t;
		$t = statement($prev->{token}->[0], $t) if $bounce eq '{';
		while(!$t->eof() && $t->value() !~ /^op_[\)\}\]]$/) {
			no warnings 'recursion';
			$t = parse($t)
		}
		$t = statement($prev->{token}->[0], $this, $t) if $bounce =~ /[\[\(]/;
		$t = parse($t)
	}
	return $t;
}

sub parse_err {
	my($t) = @_;
	die "parse err : $t->{file}($t->{line})" . $t->debug();
}

sub statement {
	my($begin, $this, $end) = @_;
	$begin = $this unless $begin;
	$end   = $this unless $end;
	my $dem = $end->value =~ /^op_[;\{]$/ ? $end : $end->next('op_[;\{]');
	my $type = '';
	my $name = '';
	my $ns	 = '';
	my $class;
	if('ARRAY' eq ref $this->{class}) {
		$class = $this->{class}->[0];
		$type = $class->{type};
		$name = $class->{name};
		if($name !~ /^::/ && $name !~ /(\.|->)/) {
			foreach(1..$#{$this->{class}}) {
				my $c = $this->{class}->[$_];
				$name = "$c->{name}\::$name" if $c->{type} =~ /^(namespace|class|method)$/;
			}
		}
		$ns = "$type\_$name";

		# 前方コメント抽出
		$class->{comment} = '';
		my $t = $begin->prev('!(op|space)_.*');
		if($t->kind eq 'comment') {
			for(;!$t->bof; $t = $t->prev) {
				$_ = $t->value;
				last unless /^(comment|space)_/;
				last if /^space_\n$/ && $t->prev->value eq "space_\n";
			}
			$class->{comment} = getComment($t, $begin);
		}
		# 後方コメント抽出
		$class->{after_comment} = getComment($begin, $dem->next('space_\n'));
	}

debug("start($ns):".$lex->tokens($begin, $end));

	# ステートメント
	if($type eq 'statement' && $end->value eq 'op_)') {	   # TODO(これでいいのか？)
		$_ = $ns;
		my($ns, $name) = /^statement_(.*)::(.*?)$/;
		# ステートメントを分類して適当にまとめる
		$name =~ s/(switch|catch)/if/;
		$name =~ s/while/for/;
		$name =~ s/(continue|break|throw)/goto/;
		$name =~ s/throw/return/;
debug("<$type,$ns, $name> ".$lex->tokens($begin, $end->next()));
		($ns) = grep{/^method_$ns$/} keys %$test;
		if($ns && $test->{$ns}) {
			my $commnet = join "\n", $class->{comment}, $class->{after_comment};
			$test->{$ns}->{$name} = [] unless $test->{$ns}->{$name};
			my $statement = {begin=>$begin, end=>$end, this=>$this, comment=>$commnet};
			hash_marge($statement, $class);
			push @{$test->{$ns}->{$name}}, $statement;
debug("<append> test->{$ns}->{$name}")
		}
		return $end;

	}
	# ネームスペース、クラスの定義
	if($type =~ /^(namespace|class)$/ && $end->value eq 'op_{') {
debug("<$type>". $lex->tokens($begin, $end));
debug("<create> test->{$ns}"), $test->{$ns} = {} unless $test->{$ns};
		$test->{$ns}->{begin} = $begin;
		$test->{$ns}->{end}	  = $end->prev;
		$test->{$ns}->{name} = $name;
		hash_marge($test->{$ns}, $class);
		return $end;
	}
	# メソッド
	if($type eq 'method' && $end->value eq 'op_)') {	# TODO(これでいいのか？)

debug("<$type> ". $lex->tokens($begin, $end->next));

		if($begin->{class}->[0]->{type} =~ /^namespace|class$/) {

			# リターンの抽出
			my $def = [];
			for(my $t = $begin; !$t->eof($this->prev); $t = $t->next) {
				push @$def, $t if $t->value() =~ /^define_/;
			}
	debug("ret ". join ',', map{$_->value()} @$def);

			# コンストラクタ・デストラクタの判定
			my $ructor = $name =~ /(\w+)::~?\1$/;
			unless($ructor) {
				foreach my $i(1..$#{$this->{class}}) {
					next unless $this->{class}->[$i]->{type} eq 'class';
					my $nm = $this->{class}->[$i]->{name};
					$ructor = 1,last if $name =~ /~?$nm/;
				}
			}
			if(@$def || $ructor) {
				# メソッドの定義
	debug("<create> test->{$ns} : $ructor"), $test->{$ns} = {} unless $test->{$ns};
				$test->{$ns}->{name}  = $name;
				$test->{$ns}->{begin} = $begin;
				$test->{$ns}->{end}	  = $end;

				my($n) = $ns =~ /^method_(.*)::(.*?)$/;
				($n) = grep{/^(namespace|class)_$n$/} keys %$test;
				$test->{$ns}->{base} = $test->{$n} if $n;	# 所属クラス

				if($dem->value eq 'op_{') {		# メソッドの本体

	debug("<define> ". $lex->tokens($begin, $end->next) . " this:". $this->value. " end:". $end->value);

					# 引数情報の抽出
					my $arg = [];
					for(my($t, $i) = ($this->next, 0); !$t->eof($end->prev); $t = $t->next) {
						$i++ if $t->value() eq 'op_,';
						next unless $t->kind eq 'valiable';
						unless($arg->[$i]) {
							# 関数コメントから抽出
							my $name = $t->text;
							my $comment = '';
							$comment = "$1 $2" if $class->{comment} =~ /\@param\s*(.*?)\s*$name([^\@]*)/m;
							$comment = $1	   if $class->{comment} =~ /^$name\s*:(.*)$/m;
							$comment =~ s/^\s*(.*?)\s*$/$1/m;
							unless($comment) {
								# 引数コメントから抽出
								my $tt = $t->next('op_[,\)]')->next('((define|ident|valiable)_.*|op_[\{;])');
								$comment = getComment($t, $tt);
								$comment =~ s/^\s*(.*?)\s*$/$1/m;
							}
							$comment = $name unless $comment;
							$t->{comment} = $comment;
							$arg->[$i] = $t;
	debug("<arg_commnet> index=$i line=$t->{line} ". $t->value. " comment=$comment");
						}
					}
					$test->{$ns}->{arg}	 = $arg;
	debug("arg ". join ',', map{$_->value} @$arg);

					hash_marge($test->{$ns}, $class);
				} # end if($dem->value eq 'op_{')	# メソッドの本体
				else {	  # メソッドのプロトタイプ
	debug("<prototype> ". $lex->tokens($begin, $end->next()));
					for(my $t = $begin; !$t->eof($this->prev); $t = $t->next) {
						$test->{$ns}->{$t->text} = 1 if $t->kind eq 'keyword';
					}
				}
			}	# end if(@$def || $ructor)
		}
		else {	  # メソッドの利用
debug("<use> ". $lex->tokens($begin, $end->next()));
		}
	}	# end if($type eq 'method')

	return $end;
}

sub getComment {
	my($begin, $end) = @_;
	my $comment = "";
	for(my $t = $begin; !$t->eof($end); $t = $t->next) {
		next unless $t->kind eq 'comment';
		my $text = $t->text;
		$text =~ s/^\/[\*\/]//;
		$text =~ s/\*\/$//;
		$text =~ s/^\s*\*//gm;
		$text =~ s/　/ /g;
		$text =~ s/\s+/ /g;
		$text =~ s/^\s*(.*?)\s*$/$1/;
		next unless $text;

		$comment .= "\n" if $comment;
		$comment .= $text;
	}
	return $comment;
}

sub hash_marge{
	my($base, $marge) = @_;
	while(my($k,$v)=each %$marge) {
		$base->{$k} = $v unless $base->{$k};
	}
}

sub CreateHtml {
	use CGI;
	CGI::charset("utf-8");
	my $q = new CGI;

	my $fh = new FileHandle($param->{output}, 'w') or die "$param->{output}:file open error:$!\n";
	$fh->binmode(":utf8");
	$fh->print($q->start_html(
		-title=>$param->{title}, -lang =>'ja',
		-head=>[
			$q->meta({
				'http-equiv'=>'Content-Type',
				-content	=>'text/html; charset=UTF-8'}),
			$q->meta({-charset=>'UTF-8'}),
			$q->link({-rel=>'stylesheet', href=>'css/base.css'}),
			(map{ $q->script({-type=>'text/javascript', -src=>"js/$_"}, "") } @{$param->{javascript}}),
			$q->script({-langage=>"text/javascript"}, "<!--\n", <<'JAVASCRIPT'
JAVASCRIPT
			, '// -->')
	   ]
	));

	foreach my $class(qw{namespace class}) {
		my $jp = $class eq 'class' ? 'クラス' : 'ネームスペース';
		$fh->print($q->a({-name=>$class}, $q->h1("$jp\定義")), "\n");
		$fh->print($q->start_table, "\n");
		$fh->print($q->thead($q->Tr({-align=>'center', -valign=>'top'}, $q->th(['file', 'line', $jp, '内容']))), "\n");
		$fh->print($q->start_tbody, "\n");
		foreach(sort{$a cmp $b} grep{/^$class\_/} keys %$test) {
			my ($file) = $test->{$_}->{begin}->{file} =~ /([^\/]+)$/;
			my $line = $test->{$_}->{begin}->{line};
			my $name = $test->{$_}->{name};
			$name =~ s/^.*:://;
			my $comment = putComment($test->{$_}->{comment});
			$fh->print($q->Tr({-align=>'left', -valign=>'top'},
				$q->td([$file, $line, $q->a({-href=>"#$_"}, $name), $comment])), "\n");
		}
		$fh->print($q->end_tbody, "\n");
		$fh->print($q->end_table, "\n");
	}

	$fh->print($q->a({-name=>'method'},$q->h1("メソッド定義")), "\n");
	$fh->print($q->start_table, "\n");
	$fh->print($q->thead($q->Tr({-align=>'center', -valign=>'top'}, $q->th(['file', 'line', 'メソッド', '内容']))), "\n");
	$fh->print($q->start_tbody, "\n");
	foreach(sort{
		my $ret = $test->{$a}->{begin}->{file} cmp $test->{$b}->{begin}->{file};
		$ret = $test->{$a}->{begin}->{line} <=> $test->{$b}->{begin}->{line} unless $ret;
		$ret;
	} grep{/^method_/} keys %$test) {
		my ($file) = $test->{$_}->{begin}->{file} =~ /([^\/]+)$/;
		my $line = $test->{$_}->{begin}->{line};
		my $name = $test->{$_}->{name};
		$name =~ s/^.*:://;
		my $comment = putComment($test->{$_}->{comment});
		$fh->print($q->Tr({-align=>'left', -valign=>'top'}),
			$q->td([$file, $line, $q->a({-href=>"#$_"}, $name), $comment]), "\n");
	}
	$fh->print($q->end_tbody, "\n");
	$fh->print($q->end_table, "\n");

	foreach my $ns(sort{
		my $ret = $test->{$a}->{begin}->{file} cmp $test->{$b}->{begin}->{file};
		$ret = $test->{$a}->{begin}->{line} <=> $test->{$b}->{begin}->{line} unless $ret;
		$ret;
	} grep{/^method_/} keys %$test) {
		my $class = $test->{$ns}->{base};
		my $func = $test->{$ns};
		my $name = $test->{$ns}->{name};
		$name =~ s/^.*:://;
		$fh->print($q->a({-name=>$ns}, $q->h1("メソッド $name テストパターン")));
		$fh->print($q->start_table, "\n");
		$fh->print($q->thead($q->Tr({-align=>'center', -valign=>'top'}, $q->th(['file', 'line', 'テスト観点項目', '', '', '', '内容']))), "\n");
		$fh->print($q->start_tbody, "\n");

		# 入力
		## データパターン
		### 引数
		if($func->{arg} && @{$func->{arg}}) {
			foreach my $arg(@{$func->{arg}}) {
				my ($file) = $arg->{file} =~ /([^\/]+)$/;
				my $line = $arg->{line};
				my $text = "";
				$text .= $arg->{comment} if $arg->{comment};
				$text .= "(". $arg->text. ")";
				$fh->print($q->Tr({-align=>'left', -valign=>'top'},
					$q->td([$file, $line, '入力', 'データパターン', '引数', '正常', putComment($text)])), "\n");
				$fh->print($q->Tr({-align=>'left', -valign=>'top'},
					$q->td([$file, $line, '入力', 'データパターン', '引数', '異常', putComment($text)])), "\n");
			}
		}

		## 初期状態
		### クラス内変数
		if(!$func->{static} && $class && 'ARRAY' eq ref $class->{valiable}) {
			foreach my $menber(@{$class->{valiable}}) {
				my ($file) = $menber->{file} =~ /([^\/]+)$/;
				my $line = $menber->{line};
				my $text = "";
				$text .= $menber->{comment} if $menber->{comment};
				$text .= "(". $menber->text. ")";
				$fh->print($q->Tr({-align=>'left', -valign=>'top'},
					$q->td([$file, $line, '入力', '初期状態', 'クラス内変数', '正常', putComment($text)])), "\n");
				$fh->print($q->Tr({-align=>'left', -valign=>'top'},
					$q->td([$file, $line, '入力', '初期状態', 'クラス内変数', '異常', putComment($text)])), "\n");
			}
		}

		### メモリ(ヒープ、共有)
		### ファイル
		### エンティティ
		### 共通アダプテーション
		### 個別アダプテーション

		# 処理
		## 内部状態
		### 条件分岐
		if($func->{if} && @{$func->{if}}) {
			foreach(@{$func->{if}}) {
				my ($file) = $_->{begin}->{file} =~ /([^\/]+)$/;
				my $line = $_->{begin}->{line};
				my $text = "";
				$text .= "$_->{comment}\n" if $_->{comment};
				$text .= $lex->string($_->{begin}, $_->{end});
				$fh->print($q->Tr({-align=>'left', -valign=>'top'},
					$q->td([$file, $line, '処理', '内部状態', '条件分岐', '正常', putComment($text)])), "\n");
				$fh->print($q->Tr({-align=>'left', -valign=>'top'},
					$q->td([$file, $line, '処理', '内部状態', '条件分岐', '異常', putComment($text)])), "\n");
			}
		}

		### 繰り返し
		if($func->{for} && @{$func->{for}}) {
			foreach(@{$func->{'for'}}) {
				my ($file) = $_->{begin}->{file} =~ /([^\/]+)$/;
				my $line = $_->{begin}->{line};
				my $text = "";
				$text .= "$_->{comment}\n" if $_->{comment};
				$text .= $lex->string($_->{begin}, $_->{end});
				$fh->print($q->Tr({-align=>'left', -valign=>'top'},
					$q->td([$file, $line, '処理', '内部状態', '繰り返し', '正常', putComment($text)])), "\n");
			}
		}
		### 演算

		## メソッド呼出結果
		### 自クラス
		### 他クラス
		### 基盤
		### TP基盤

		## 値の取得
		### 設定情報
		### エンティティ

		# 出力
		## 引数（出力）
		## 戻り値
		## ログ

		## 保存
		### クラス内変数
		if(!$func->{static} && $class && 'ARRAY' eq ref $class->{valiable}) {
			foreach my $menber(@{$class->{valiable}}) {
				my ($file) = $menber->{file} =~ /([^\/]+)$/;
				my $line = $menber->{line};
				my $text = "";
				$text .= $menber->{comment} if $menber->{comment};
				$text .= "(". $menber->text. ")";
				$fh->print($q->Tr({-align=>'left', -valign=>'top'},
					$q->td([$file, $line, '出力', '保存', 'クラス内変数', '正常', putComment($text)])), "\n");
				$fh->print($q->Tr({-align=>'left', -valign=>'top'},
					$q->td([$file, $line, '出力', '保存', 'クラス内変数', '異常', putComment($text)])), "\n");
			}
		}
		### ファイル
		### エンティティ
		### KVS
		### メモリ(ヒープ、共有)
		### 共通アダプテーション
		### 個別アダプテーション

		# 維持管理
		## 入力チェック
		### 引数
		if($func->{arg} && @{$func->{arg}}) {
			my ($file) = $func->{arg}->[0]->{file} =~ /([^\/]+)$/;
			my $line   = $func->{arg}->[0]->{line};
			$fh->print($q->Tr({-align=>'left', -valign=>'top'},
				$q->td([$file, $line, '維持管理', '入力チェック', '引数', '正常'])), "\n");
			$fh->print($q->Tr({-align=>'left', -valign=>'top'},
				$q->td([$file, $line, '維持管理', '入力チェック', '引数', '異常'])), "\n");
		}

		## 例外処理
		## catch|try|throw

		$fh->print($q->end_tbody, "\n");
		$fh->print($q->end_table, "\n");
	}

	$fh->print($q->end_html);
	$fh->close();
}

sub putComment {
	my($comment) = @_;
	return '' unless $comment;
	return Utility::toHtml(join "<br>\n", split "\n", $comment);
}

sub debug {
	print '[TEST] '. join(' ', @_) . "\n" if $param->{debug};
}
