#!/usr/bin/perl

BEGIN { unshift @INC, ("$ENV{HOME}/bin", "$ENV{HOME}/workspace/develop/MACP/MFOP/test/MFOPTESTCM0010/script"); }

use strict;
use warnings;
use utf8;

use FileHandle;
use CGI;
use Encode;

use LexicalAnalyzer;

binmode STDOUT, ":utf8";

# コマンド引数の取得
my $param = {path=>[], javascript =>['Utility.js', 'TableOperation.js']};
foreach(@ARGV) {
    if(/^-debug$/) { $param->{debug}   = 1; }
    elsif(/^-i(.*)$/) { if($1) { $param->{input}  = $1; } else { $param->{input_flag} = 1; } }
    elsif(/^-o(.*)$/) { if($1) { $param->{output} = $1; } else { $param->{output_flag} = 1;} }
    elsif(/^-t(.*)$/) { if($1) { $param->{title} = $1;  } else { $param->{title_flag} = 1; } }
    elsif(/^-h/)      { $param->{help} = 1; }
    elsif(/^-firefox$/)  { $param->{firefox} = 1; }
    elsif($param->{input_flag}) {
        $param->{input} = $_;
        delete $param->{input_flag};
    }
    elsif($param->{output_flag}) {
        $param->{output} = $_;
        delete $param->{output_flag};
    }
    elsif($param->{titleflag}) {
        $param->{title} = $_;
        delete $param->{titleflag};
    }
    else {
        push @{$param->{path}}, $_;
    }
}

if($param->{input}) {
    use FileHandle;
    my $fh = new FileHandle($param->{input}) or die "$param->{input} file open error:$!";
    while(<$fh>) {
        chomp;
        s/\s*(.*?)\s*/$1/;
        s/#.*$//;
        next unless $_;
        if(/^(\w+)\s*=\s*(.*)$/) {
            $param->{lc $1} = $2 unless $param->{lc $1};
        } else {
            push(@{$param->{path}}, $_);
        }
    }
}
$param->{help} = 1 unless @{$param->{path}};

my($progpath, $prog) = $0 =~ /^(.*?)([^\/]+)$/;
if($param->{help}) {
    print <<"USAGE";
usage $prog [OPTION]... [SORCE FILE]...

ソースファイルをレビュー可能なHTMLに変換します。

OPTION:
  -o [HTML FILE]            出力先HTMLを指定します。
                            指定しない場合は、入力したソースファイルから適当に決定されます。
  -t [TITLE]                HTMLのタイトルを指定します。
                            指定しない場合は、入力したソースファイルから適当に決定されます。
  -firefox                  出力後、FireFoxを自動起動します。
  -debug                    デバックモード
USAGE
    exit 0;
}

my($title) = $param->{path}->[0] =~ /([^\/]+)\..+?$/;
$title = $prog unless $title;
$param->{output} = "$title.html" unless $param->{output};
$param->{title}  = $title        unless $param->{title};
$param->{title} = Encode::decode('utf8', $param->{title});

my $src = {};
Execute(@{$param->{path}});

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

($progpath) = readlink($0) =~ /^(.*?)([^\/]+)$/ if -l $0;
if(-d "$progpath/js") {
    unlink 'js' if -d 'js';
    symlink "$progpath/js", 'js';
}

system "firefox $param->{output} > /dev/null 2>&1 &" if $param->{firefox};

exit;

sub Execute {
    my @paths = @_;
    foreach my $path(@paths) {
        if(-d $path) {
            $path =~ s/\/$//;
            Execute($_) foreach glob("$path/*");
        }
        elsif(-f $path) {
            next unless $path =~ /\.(h|c|cc|cpp)$/;
            # 絶対パスを求める
            use Cwd 'getcwd';
            $path = getcwd()."/$path" unless $path =~ m#^/#;
            $path =~ s#/(\.?/)+#/#mg;
            $path =~ s#[^/]+/\.\./##mg;

            # ファイル名を求める
            my($file, $class) = $path =~ m#(([^/]+)\..*)$#;
            
            $src->{$file}->{lex} = new LexicalAnalyzer({file=>$path, debug=>$param->{debug}});
            $src->{$file}->{lex}->AnalyzeCPP();
        }
        elsif($path =~ /\*/) {
            Execute($_) foreach glob("$path");
        }
    }
}

sub CreateHtml {
    my($lex) = @_;
    CGI::charset("utf-8");
    my $q = new CGI;

    my $fh = new FileHandle($param->{output}, 'w') or die "$param->{output}:file open error:$!\n";
    $fh->binmode(":utf8");

    $fh->print($q->start_html(-title=>$param->{title}, -lang =>'ja',
        -head=>[
            $q->meta({
                'http-equiv'=>'Content-Type',
                -content    =>'text/html; charset=UTF-8'}),
            $q->meta({-charset=>'UTF-8'}),
            $q->style({-type=>'text/css'}, "\n", <<"CSS"

body {
    font-size : 9pt;
}
h1 {
    font-size : 10pt;
}
h2 {
    font-size : 9pt;
}
li {
    list-style-type : decimal-leading-zero;
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
    width           : 480px;
    font-size       : 9pt;
    border          : solid 1px #999;
    background-color: #f0e68c
}

* {
   box-sizing: border-box;
}

.box {
   position : relative;
   background: #f0e68c;
   width    : 500px;
   margin-bottom: 20px;
   padding  : 5px;
   border   : 1px solid #999;
}

.box:before, .box:after {
   content  : '';
   position : absolute;
   display  : block;
}

.box.left:before {
   top  : 0px;
   left : -9px;
   border-top   :  5px solid transparent;
   border-right : 10px solid #999;
   border-bottom:  5px solid transparent;
}

.box.left:after {
   top  : 0px;
   left : -8px;
   border-top   :  5px solid transparent;
   border-right : 10px solid #f0e68c;
   border-bottom:  5px solid transparent;
}

.fukidashi {
   position      : absolute;
   top           : 0;
   left          : 80ex;
   display       : table-cell;
   vertical-align: bottom;
   padding-left  : 15px;
   padding-right : 175px;
#    position:relative absolute; top : -1em;
}
CSS
),
            (map{ $q->script({-type=>'text/javascript', -src=>"js/$_"}, "") } @{$param->{javascript}}),
            $q->script({-langage=>"text/javascript"}, "<!--\n", <<'JAVASCRIPT'

var ie = GetBrowser();
var datafile = GetFileName() + '.dat';

// ファイル操作用オブジェクト(windows ie でのみ有効)
var FileHandle = function(file, flag) {   // flag 1:read 2:write 8:append
    var fs = new ActiveXObject("Scripting.FileSystemObject");
    var fh = fs.OpenTextFile(file, flag, true);

    this.readline = function() {
        return fh.ReadLine();
    }
    this.writeline = function(str) {
        return fh.WriteLine(str);
    }
    this.eof = function() {
        return fh.AtEndOfStream;
    }
    this.close = function() {
        fh.Close();
        fh = null;
        fs = null;
    }
};

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

    var oView = document.getElementById('view_' + name);
    if(oView.childNodes.length > 0) {
        document.getElementById('comment_' + name).focus();
        return;
    }

    oView.className = 'fukidashi';

    var oDiv = document.createElement('div');
    oDiv.className= 'box left';
    oDiv.onclick = new Function('document.getElementById("comment_' + name + '").focus();');

    var oInput = document.createElement('textarea');
    oInput.setAttribute('id', 'comment_' + name);
    if(value) oInput.value = value;
    AddEvent(oInput, 'blur', function() { commnet_clear(name); });
    var obj = new TextareaAdjuster(oInput);
    oDiv.appendChild(oInput);

    oView.appendChild(oDiv);

    oInput.focus();
}

// コメントを除去する
function commnet_clear(name) {
    var text = document.getElementById('comment_' + name).value;

    if(text !== '') return;

    document.getElementById('line_' + name).style.backgroundColor = "transparent";

    var oView = document.getElementById('view_' + name);
    oView.removeChild(oView.childNodes[0]);
    oView.removeAttribute('class');
    oView.removeAttribute('style');
}

// 出力ボタンの処理
function commnet_output() {

    var win = window.open('', '_blank');
    var doc = win.document;
    doc.open();

    var oHtml = doc.createElement('html');
    oHtml.setAttribute('lang', 'ja');

    var oHead = doc.createElement('head');
    var oTitle = doc.createElement('title');
    oTitle.innerHTML = datafile;
    oHead.appendChild(oTitle);

    var oMeta_content = doc.createElement('meta');
    oMeta_content.setAttribute('content', 'text/html; charset=UTF-8');
    oMeta_content.setAttribute('http-equiv', 'Content-Type');
    oHead.appendChild(oMeta_content);

    var oMeta_charset = doc.createElement('meta');
    oMeta_content.setAttribute('charset', 'UTF-8');
    oHead.appendChild(oMeta_content);

    oHtml.appendChild(oHead);

    var oBody = doc.createElement('body');

    var oTable = doc.createElement('table'); oTable.border = 1;
    var oTbody = doc.createElement('tbody');

    var oTr = doc.createElement('tr');
    var oTh = doc.createElement('th');
    oTh.innerHTML = 'ファイル'; oTr.appendChild(oTh);
    var oTh = doc.createElement('th');
    oTh.innerHTML = 'ライン';   oTr.appendChild(oTh);
    var oTh = doc.createElement('th');
    oTh.innerHTML = 'コメント'; oTr.appendChild(oTh);
    oTbody.appendChild(oTr);

	var comments;
	if(ie)	comments = document.all.tags("textarea");
	else	comments = document.querySelectorAll('textarea[id^="comment_"]');
    for(var i = 0; i < comments.length; i++) {
        comments[i].id.match(/^comment_(.+)_(\d+)$/);
        var line = RegExp.$2;
        var file = RegExp.$1.replace(/_/g, '.');
        var text = comments[i].value;
        text = text.replace(/&/g, '&amp;');
        text = text.replace(/</g, '&lt;');
        text = text.replace(/>/g, '&gt;');
        text = text.replace(/"/g, '&quot;');
        text = text.replace(/'/g, '&#x27;');
        text = text.replace(/(\x0d\x0a|\x0a|\x0d)/g, "<br>\n");

        var oTr = doc.createElement('tr');
        var oTd = doc.createElement('td');
        oTd.innerHTML = file; oTr.appendChild(oTd);
        var oTd = doc.createElement('td');
        oTd.innerHTML = line; oTr.appendChild(oTd);
        var oTd = doc.createElement('td');
        oTd.innerHTML = text; oTr.appendChild(oTd);
        oTbody.appendChild(oTr);
    }
    oTable.appendChild(oTbody);
    oBody.appendChild(oTable);

    var oH5 = doc.createElement('H5');

    if(ie) {
        // コメントデータファイルを書く
        var fc = new FileHandle(datafile, 2);
        for(var i = 0; i < comments.length; i++) {
            comments[i].id.match(/^comment_(.+)_(\d+)$/);
            var line = RegExp.$2;
            var file = RegExp.$1.replace(/_/g, '.');
            var text = comments[i].value;
            fc.writeline('<<' + file + ' ' + line + '>>');
            text = text.split(/(\x0d\x0a|\x0a|\x0d)/);
            for(var j in text) fc.writeline(text[j]);
        }
        fc.writeline('<<EOF>>');
        fc.close();

        oH5.innerHTML = 'コメントデータファイル(' + datafile + ')を作成しました';
    } else {
        oH5.innerHTML = 'コメントデータファイル(' + datafile + ')はwindowsのIEでないと作成できません<br>' +
           '必要な場合はwindowsで作成しなおしてください。';
    }
    oBody.appendChild(oH5);

    oHtml.appendChild(oBody);
    doc.appendChild(oHtml);
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

                $fh->print($q->h1({
                    -onclick=>"FolderOperation('$file');",
                    -onmouseover=>"this.style.backgroundColor='skyblue';",
                    -onmouseout =>"this.style.backgroundColor='';"
                }, "ソースファイル名：$file"), "\n");
                $fh->print($q->start_div({-id=>"$file", -style=>'display:none; position:relative;', -class=>'close'}));
                $fh->print($q->h2("ファイルフルパス：$path"), "\n");
                $fh->print($q->start_code);
                $fh->print($q->start_ol, "\n");
            }
            $name = "$file\_$t->{line}";
            $name =~ s/\./_/;
            $fh->print($q->start_li);
            $fh->print($q->start_div({-id=>"line_$name", -onClick=>"comment_edit('$name');"}));
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
                $title .= "\nbase=$c->{base}->{type}($c->{base}->{name})" if $c->{base};
            }
        }

        my $att = {-title=>$title, -class=>$t->kind,
            -onmouseover=>'this.style.backgroundColor="skyblue";',
            -onmouseout =>'this.style.backgroundColor="";',
        };

        $fh->print($q->span($att, put($t->text)));

        if($t->text =~ /\n/ || $t->next->eof) {
            $fh->print($q->end_div, "\n");
            $fh->print($q->div({-id=>"view_$name"}));
            $fh->print($q->end_li, "\n");
        }
    }
    $fh->print($q->end_ol, $q->end_div, $q->end_code, "\n");

    $fh->print($q->input({-type=>'button', -value=>'出力', -onclick=>'commnet_output();'}));
    $fh->print($q->end_html, "\n");
    $fh->close();
}

sub put {
    my($text) = @_;
    $text =~ s/&/&amp;/gm;
    $text =~ s/</&lt;/gm;
    $text =~ s/>/&gt;/gm;
    $text =~ s/"/&quot;/gm;
    $text =~ s/\t/    /gm;
    $text =~ s/\n/&nbsp;\n/gm;
    $text =~ s/ /&nbsp;/gm;

    return $text;
#    return Encode::decode('utf8', $text);
}
