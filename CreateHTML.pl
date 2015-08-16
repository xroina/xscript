#!/usr/bin/perl

BEGIN {
	unshift @INC, map "$_/lib", $0 =~ /^(.*?)[^\/]+$/;
	unshift @INC, map "$_/lib", readlink($0) =~ /^(.*?)[^\/]+$/ if -l $0;
}

use strict;
use warnings;
use utf8;

use FileHandle;
use CGI;
use Encode;

use Utility;
use CppAnalyzer;

binmode STDIN , ':utf8';
binmode STDOUT, ':utf8';

# コマンド引数の取得
my $param = {javascript =>['Utility.js', 'TableOperation.js', 'FileHandle.js']};
Utility::getStartOption($param, ['debug', 'input=&', 'output=*', 'title=*', 'help', 'xdg']);
$param->{help} = 1 unless @{$param->{path}};
my($progpath, $prog) = $0 =~ /^(.*?)([^\/]+)$/;
if($param->{help}) {
	print <<"USAGE";
usage $prog [OPTION]... [SORCE FILE]...

ソースファイルをレビュー可能なHTMLに変換します。

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
$param->{output} = "$title.html" unless $param->{output};
$param->{title}	 = $title		 unless $param->{title};

my $src = {};
foreach my $path(@{Utility::getRecursivePath($param->{path}, 'h|hpp|c|cc|cpp')}) {
	my($file, $class) = $path =~ m#(([^/]+)\..*)$#;
	$src->{$file}->{lex} = new CppAnalyzer({file=>$path, debug=>$param->{debug}});
}

my $lex;
foreach(sort{
	my($a_name, $a_h) = $a =~ /([^\/]+)\.(.+?)$/;
	my($b_name, $b_h) = $b =~ /([^\/]+)\.(.+?)$/;
	my $ret = $a_name cmp $b_name;
	$ret = $b_h cmp $a_h unless $ret;
	$ret;
} keys %$src) {
	if($lex) { $lex->end->add($src->{$_}->{lex}->begin); $lex->{end} = $src->{$_}->{lex}->{end}; }
	else { $lex = $src->{$_}->{lex}; }
}

CreateHtml($lex);

Utility::createSymLink();

system "xdg-open $param->{output} > /dev/null 2>&1 &" if $param->{xdg};

debug("END");

exit;

sub CreateHtml {
	my($lex) = @_;
	CGI::charset("utf-8");
	my $q = new CGI;

	my $fh = new FileHandle($param->{output}, 'w') or die "$param->{output}:file open error:$!\n";
	$fh->binmode(":utf8");

	$fh->print($q->start_html(-title=>$param->{title}, -lang =>'ja',
		-head=>[
			$q->meta({
				'http-equiv'=> 'Content-Type',
				-content	=> 'text/html; charset=UTF-8'}),
			$q->meta({
				'http-equiv'=> 'X-UA-Compatible',
				-content	=> 'IE=10'}),
			$q->meta({-charset=>'UTF-8'}),
			$q->Link({-rel=>'stylesheet', href=>'css/base.css'}),
			$q->style({-type=>'text/css'}, "\n", <<"CSS"

div.line {
	position : relative;
}

.comment {
	color : darkgreen;
}
.string, .char {
	color : blue;
}
.statement, .class, .using, .namespace, .directive {
	color : indigo;
	font-weight : bold;
}
.method {
	font-weight : bold;
}
.define {
	color : darkolivegreen;
	font-weight : bold;
}
.valiable {
	font-style : italic;
}
.ident {
	color : red;
}

textarea {
	width			: 480px;
	font-size		: 9pt;
	border			: solid 1px #999;
	background-color: #f0e68c
}

* {
   box-sizing: border-box;
}

.box {
   position : relative;
   background: #f0e68c;
   width	: 500px;
   margin-bottom: 20px;
   padding	: 5px;
   border	: 1px solid #999;
}

.box:before, .box:after {
   content	: '';
   position : absolute;
   display	: block;
}

.box.left:before {
   top	: 0px;
   left : -9px;
   border-top	:  5px solid transparent;
   border-right : 10px solid #999;
   border-bottom:  5px solid transparent;
}

.box.left:after {
   top	: 0px;
   left : -8px;
   border-top	:  5px solid transparent;
   border-right : 10px solid #f0e68c;
   border-bottom:  5px solid transparent;
}

.fukidashi {
   position		 : absolute;
   top			 : 0;
   left			 : 80ex;
   display		 : table-cell;
   vertical-align: bottom;
   padding-left	 : 15px;
   padding-right : 175px;
/* position:relative absolute; top : -1em; */
}
CSS
),
			(map{ $q->script({-type=>'text/javascript', -src=>"js/$_"}, "") } @{$param->{javascript}}),
			$q->script({-langage=>"text/javascript"}, "<!--\n", <<'JAVASCRIPT'

var ie = GetBrowser();
var datafile = GetFileName() + '.dat';

if(ie) {
	AddEvent(window, 'load', function() {
		// コメントデータファイル読み込み
		var fc = new FileHandle(datafile, 1);
		var name = '';
		var text = '';
		while(!fc.eof()) {
			var str = fc.readline();
			if(str.match(/^<<(.+?)( \d+)?>>$/)) {
				var file = RegExp.$1;
				var line = new Number(RegExp.$2);
				if(name.length > 0 && text.length > 0) comment_edit(name, text);
				if(file === 'EOF') break;
				name = file.replace(/\./g, '_') + '_' + line;
				text = '';
				continue;
			}
			if(text.length > 0) text += "\n";
			text += str;
		}
		fc.close();
	});
}

// コメントの追加
function comment_edit(name, value) {
	document.getElementById('line_' + name).style.backgroundColor = 'yellow';

	var view = document.getElementById('view_' + name);
	if(view.childNodes.length > 0) {
		document.getElementById('comment_' + name).focus();
		return;
	}

	view.className = 'fukidashi';

	var div = document.createElement('div');
	div.className= 'box left';
	div.onclick = new Function('document.getElementById("comment_' + name + '").focus();');

	var oInput = document.createElement('textarea');
	oInput.setAttribute('id', 'comment_' + name);
	if(value) oInput.value = value;
	AddEvent(oInput, 'blur', function() { commnet_clear(name); });
	var obj = new TextareaAdjuster(oInput);
	div.appendChild(oInput);

	view.appendChild(div);

	if(name.match(/^(.+):/)) headder_color(RegExp.$1);

	oInput.focus();
}

// コメントを除去する
function commnet_clear(name) {
	var text = document.getElementById('comment_' + name).value;

	if(text !== '') return;

	document.getElementById('line_' + name).style.backgroundColor = 'transparent';

	var view = document.getElementById('view_' + name);
	view.removeChild(view.childNodes[0]);
	view.removeAttribute('class');
	view.removeAttribute('style');

	if(name.match(/^(.+):/)) headder_color(RegExp.$1);
}

function headder_color(name) {
	var tag	 = document.getElementById(name + '_code');
	var head = document.getElementById(name + '_title');
	if(!tag || !head) return;
	if(tag.getElementsByTagName('textarea').length > 0) head.style.backgroundColor = 'yellow';
	else head.style.backgroundColor = "transparent";
}

// 出力ボタンの処理
function commnet_output() {

	var win = window.open('', '_blank');
	var doc = win.document;
	doc.open();

	var html = doc.createElement('html');
	html.setAttribute('lang', 'ja');

	var head = doc.createElement('head');
	var title = doc.createElement('title');
	title.innerHTML = datafile;
	head.appendChild(title);

	var content = doc.createElement('meta');
	content.setAttribute('content', 'text/html; charset=UTF-8');
	content.setAttribute('http-equiv', 'Content-Type');
	head.appendChild(content);

	var charset = doc.createElement('meta');
	charset.setAttribute('charset', 'UTF-8');
	head.appendChild(charset);
	html.appendChild(head);

	var body = doc.createElement('body');

	var tbl = doc.createElement('table');
	var thd = doc.createElement('thead');

	var tr = doc.createElement('tr');
	var th = doc.createElement('th');
	th.innerHTML = 'ファイル'; tr.appendChild(th);
	var th = doc.createElement('th');
	th.innerHTML = 'ライン';   tr.appendChild(th);
	var th = doc.createElement('th');
	th.innerHTML = 'コメント'; tr.appendChild(th);
	thd.appendChild(tr);
	tbl.appendChild(thd);

	var tbd = doc.createElement('tbody');
	var fc = new FileHandle(datafile, 2);
	var comments = getTags("textarea");
	for(var i = 0; i < comments.length; i++) {
		if(!comments[i].id.match(/^comment_(.+):(\d+)$/)) continue;
		var file = RegExp.$1, line = RegExp.$2, text = comments[i].value;
		var texts = text.split(/(\x0d\x0a|\x0a|\x0d)/);
		fc.writeline('<<' + file + ' ' + line + '>>');
		for(var j in texts) fc.writeline(texts[j]);

		text = text.replace(/&/g, '&amp;');
		text = text.replace(/</g, '&lt;');
		text = text.replace(/>/g, '&gt;');
		text = text.replace(/"/g, '&quot;');
		text = text.replace(/'/g, '&#x27;');
		text = text.replace(/(\x0d\x0a|\x0a|\x0d)/g, "<br>\n");

		var tr = doc.createElement('tr');
		var td = doc.createElement('td');
		td.innerHTML = file; tr.appendChild(td);
		var td = doc.createElement('td');
		td.innerHTML = line; tr.appendChild(td);
		var td = doc.createElement('td');
		td.innerHTML = text; tr.appendChild(td);
		tbd.appendChild(tr);
	}
	fc.writeline('<<EOF>>');
	fc.close();
	tbl.appendChild(tbd);
	body.appendChild(tbl);

	var oH5 = doc.createElement('H5');
	if(ie) {
		oH5.innerHTML = 'コメントデータファイル(' + datafile + ')を作成しました';
	} else {
		oH5.innerHTML = 'コメントデータファイル(' + datafile + ')はwindowsのIEでないと作成できません<br>' +
		   '必要な場合はwindowsで作成しなおしてください。';
	}
	body.appendChild(oH5);

	html.appendChild(body);
	doc.appendChild(html);
}

function SrcOperation(id) {
	FolderOperation(id);
	var span = document.getElementById(id + '_str');
	var src = document.getElementById(id);
	if(src.className === 'close') span.innerHTML = '▶';
	else span.innerHTML = '▼';
}

JAVASCRIPT
			, '// -->')
		]
	));

	my($name, $path, $file) = ('', '', '');
	for(my $t = $lex->begin; !$t->eof; $t = $t->next) {
		if($t->prev->text =~ /\n/ || $t->prev->bof) {
			unless($path eq $t->{file}) {
				$fh->print($q->end_ol, $q->end_div, $q->end_code, "\n") if $path;
				$path = $t->{file};
				($file) = $path =~ m#([^/]+)$#;
				$fh->print(
					$q->h1({-id=>"$file\_title",
					-onclick=>"SrcOperation('$file');",
					-onmouseover=>"this.style.backgroundColor = 'skyblue';",
					-onmouseout =>"headder_color('$file');"
				}, $q->span({-style=>'color:blue', -id=>"$file\_str"}, '▶'), "ソースファイル名：$file"), "\n");
				$fh->print($q->start_div({-id=>"$file", -style=>'display:none; position:relative;', -class=>'close'}));
				$fh->print($q->h2("ファイルフルパス：$path"), "\n");
				$fh->print($q->start_code({-id=>"$file\_code"}));
				$fh->print($q->start_ol, "\n");
			}
			$name = "$file:$t->{line}";
			$fh->print($q->li);
			$fh->print($q->start_div({-id=>"line_$name", -onClick=>"comment_edit('$name');", -class=>'line'}));
		}

		my $title = $t->kind;
		$title .= "\ntoken:". join ' ', map {$_->text} @{$t->{token}};
		my $class = $t->{class};
		if('ARRAY' eq ref $class) {
			for(my $i = 0; $i < @$class; $i++) {
				my $c = $class->[$i];
				$title .= "\n$i:$c->{type}($c->{name}):";
				$title .= join ' ', map {$_->text} @{$c->{token}};
				$title .= "\nvar{". join(',', map{$_->text} @{$c->{valiable}}) ."}" if 'ARRAY' eq ref $c->{valiable};
				$title .= "\nmethod{". join(',', map{$_->text} @{$c->{method}}) ."}" if 'ARRAY' eq ref $c->{method};
				$title .= "\nbase=$c->{base}->{type}($c->{base}->{name})" if $c->{base};
			}
		}

		my $att = {-title=>$title, -class=>$t->kind,
			-onmouseover=>'this.style.backgroundColor="skyblue";',
			-onmouseout =>'this.style.backgroundColor="";',
		};

		$fh->print($q->span($att, Utility::toHtml($t->text)));

		if($t->text =~ /\n/ || $t->next->eof) {
			$fh->print($q->div({-id=>"view_$name"}));
			$fh->print($q->end_div, "\n");
		}
	}
	$fh->print($q->end_ol, $q->end_div, $q->end_code, "\n");

	$fh->print($q->input({-type=>'button', -value=>'出力', -onclick=>'commnet_output();'}));
	$fh->print($q->end_html, "\n");
	$fh->close();
}

sub debug {
	print '[CreateHTML] '. join(' ', @_) . "\n" if $param->{debug};
}
