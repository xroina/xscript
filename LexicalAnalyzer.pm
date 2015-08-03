package Token;

use strict;
use warnings;
use utf8;

sub new {
    my($this, $text, $kind) = @_;
    $text = '' unless defined $text;
    $kind = '' unless defined $kind;
    $this = bless {prv=>undef, nxt=>undef, kind=>$kind, text=>$text}, $this;
    if(ref($text) =~ /^(HASH|Token)$/ ) { $this->{$_} = $text->{$_} foreach keys %$text }
    $this->{prv} = $this;
    $this->{nxt} = $this;
    return $this;
}

sub text {
    my($this, $text) = @_;
    $this->{text} = $text if defined $text;
    $this->{text};
}

sub kind {
    my($this, $kind) = @_;
    $this->{kind} = $kind if defined $kind;
    $this->{kind};
}

sub value {
    my($this) = @_;
    $this->kind() .'_'. $this->text();
}

sub next {
    my($this, $kind, $end) = @_;
    return $this->{nxt} unless $kind;
    my $flag; $flag = 1, $kind = $1 if $kind =~ /^!(.*)$/;
    while(!$this->eof($end)) {
        $this = $this->next();
        last if $flag ? $this->value() !~ /^($kind)$/ : $this->value() =~ /^($kind)$/;
    }
    return $this;
}

sub prev {
    my($this, $kind, $end) = @_;
    return $this->{prv} unless $kind;
    my $flag; $flag = 1, $kind = $1 if $kind =~ /^!(.*)$/;
    while(!$this->bof($end)) {
        $this = $this->prev();
        last if $flag ? $this->value() !~ /^($kind)$/ : $this->value() =~ /^($kind)$/;
    }
    return $this;
}

sub add {
    my $this = shift;
    foreach(@_) {
        my $add = $_;
        if('ARRAY' eq ref $add) {
            $this->add($_), $this = $this->next foreach @$add;
            return;
        }
        $add = new Token($add) unless'Token' eq ref $add;

        $add->{nxt} = $this->next if !$this->eof && $add->eof;
        $add->{prv} = $this;
        $this->next->{prv} = $add if !$this->eof;
        $this->{nxt} = $add;
#print '"'.$add->value , '"'."\n";
    }
}

sub insert {
    my $this = shift;
    foreach(@_) {
        my $ins = $_;
        if('ARRAY' eq ref $ins) {
            $this->insert($_) foreach @$ins;
            return;
        }
        $ins = new Token($ins) unless'Token' eq ref $ins;

        $ins->{prv} = $this->prev unless $this->bof;
        $ins->{nxt} = $this;
        $this->prev->{nxt} = $ins unless $this->bof;
        $this->{prv} = $ins;
    }
}

sub delete {
    my($this, $tuple) = @_;
    if('ARRAY' eq ref $tuple) {
        $this->delete($_) foreach @$tuple;
        return;
    } elsif('Token' eq ref $tuple) {
    	$tuple->delete();
    	return;
    }
    $this->prev()->{nxt} = $this->next();
    $this->next()->{prv} = $this->prev();
}

sub eof {
    my($this, $end) = @_;
    $end = new Token() unless 'Token' eq ref $end;
    return $this->next() == $this || $end->next() == $this;
}

sub bof {
    my($this, $end) = @_;
    $end = new Token() unless 'Token' eq ref $end;
    return $this->prev() == $this || $end->prev() == $this;
}

sub begin {
    my($this) = @_;
    my $ret = $this->prev();
    $ret = $ret->prev() while !$ret->bof();
    return $ret;
}

sub end {
    my($this) = @_;
    my $ret = $this->next();
    $ret = $ret->next() while !$ret->eof();
    return $ret;
}

sub debug {
    my($this) = @_;
    "[$this] text=".$this->text()." kind=".$this->kind()." prev=".$this->prev()." next=".$this->next();
}

sub line {
    my($this) = @_;
    my $line = 1;
    for(my $t = $this->begin(); !$t->eof($this); $t = $t->next()) {
        $line++ if $t->text() =~ /\n/;
    }
    return $line;
}

#===============================================================================
package TokenHeadder;

use strict;
use warnings;
use utf8;

sub new {
    my($this, $params) = @_;
    $this = bless {begin=>new Token(), end=>new Token(), esc=>'\\',
        comment=>[ {begin=>'/*', end=>'*/'}, {begin=>'//', end=>'\n'} ]
    }, $this;
    $this->{begin}->add($this->{end});
#print "begin:",$this->{begin}->debug, "\n";
#print "end:",$this->{end}->debug, "\n";
    $this->{$_} = $params->{$_} foreach keys %$params;

    return $this;
}

sub begin {
    my($this) = @_;
    return $this->{begin}->next;
}

sub end {
    my($this) = @_;
    return $this->{end}->prev;
}

# トークン取得
sub get {
    my($this, $begin, $end, $kind) = @_;
    $kind = '' unless $kind;
    my $flag; $flag = 1, $kind = $1 if $kind =~ /^!(.*)$/;
    if(defined $begin && defined $end) {
        $begin = $this->get($begin)->next() unless 'Token' eq ref $begin;
        $end   = $this->get($end)           unless 'Token' eq ref $end;
        my $ret = [];
        for(my $t = $begin; !$t->eof($end); $t = $t->next()) {
            push @$ret, $t if $flag ? $t->value() !~ /^($kind)$/ : $t->value() =~ /^($kind)$/;
        }
        return $ret;
    }

    if(defined $begin) {
        my $ret;
        if('Token' eq ref $begin) { $ret = $begin; } else {
            for(my($t, $i) = ($this->begin(), 0); !$t->eof(); $t = $t->next(), $i++) {
                $ret = $t,last if $i == $begin;
            }
        }
        return $ret if $flag ? $this->value() !~ /^($kind)$/ : $this->value() =~ /^($kind)$/;
        return new Token();
    }

    my $ret = [];
    for(my $t = $this->begin(); !$t->eof(); $t = $t->next()) {
        push @$ret, $t if $flag ? $this->value() !~ /^($kind)$/ : $this->value() =~ /^($kind)$/;
    }
    return $ret;
}

# トークン文字列取得
sub tokens {
    my($this, $begin, $end) = @_;
    $begin = $this->begin() unless $begin;
    $end   = $this->end()   unless $end;
    my $ar = [];
    my $t = $begin;
    push @$ar, '[BOF]' if $t->prev->bof;
    while(!$t->eof($end)) {
        push @$ar, $t->text() if $t->kind() !~ /^(space|comment)$/;
        $t = $t->next;
    }
    push @$ar, '[EOF]' if $t->eof;
    return join ' ', @$ar;
}

# トークン文字列取得
sub print {
    my($this, $begin, $end) = @_;
    $begin = $this->begin() unless $begin;
    $end   = $this->end()   unless $end;
    my $ar = [];
    my $t = $begin;
    push @$ar, "begin:",$begin->debug, "\n";
    push @$ar, "end:",$end->debug, "\n";
    push @$ar, '[BOF]' if $t->prev->bof;
    while(!$t->eof($end)) {
        push @$ar, "'", $t->debug, "'";
        $t = $t->next;
    }
    push @$ar, '[EOF]' if $t->eof;
    push @$ar, '[END]' if $t == $end;
    return join '', @$ar;
}

# トークン文字列取得２
sub string {
    my($this, $begin, $end) = @_;
    $begin = $this->begin() unless defined $begin;
    $end   = $this->end()   unless defined $end;
    my $s = '';
    for(my $t = $begin; !$t->eof($end); $t = $t->next()) {
        my $text = $t->text(); $_ = $t->kind();
        next if /^comment$/;
        $text = ' ' if /^space$/;
        $s .= $text;
    }
    $s =~ s/\s+/ /mg; $s =~ s/^ ?(.*?) ?$/$1/;
    return $s;
}

#===============================================================================
package LexicalAnalyzer;

use strict;
use warnings;
use utf8;

use base 'TokenHeadder';

# レキシカルアナライザ
sub new {
    my($this, $params) = @_;
    $this = bless new TokenHeadder($params), $this;
    if($this->{file}) {
        use FileHandle;
        $this->debug("Read:$this->{file}");

        my $fh = new FileHandle($this->{file}, 'r') or die "$this->{file} file open error:$!\n";
        $fh->binmode();
        my $code = '';
        $code .= $_ while <$fh>;
        $fh->close();

        use Encode;
        use Encode::Guess qw/sjis euc-jp 7bit-jis/;

        my $decoder = Encode::Guess->guess($code);
        die $decoder unless ref $decoder;

        $this->debug("text encode : ". $decoder->name);

        $this->{code} = $decoder->decode($code);
    }
    $this->Analyze();
    $this->setLine();

#$this->debug("KIND:".$this->{end}->kind());
#$this->debug("begin:$this->{begin},prv:$this->{begin}->prev(),nxt:$this->{begin}->next()");
#for(my $t = $this->begin(); !$t->eof(); $t = $t->next()) {
#	$this->debug("$t:$t->kind():$t->text() ");
#}
#$this->debug("end:$this->{end},prv:$this->{end}->prev(),nxt:$this->{end}->next()");
#exit;

    delete $this->{code};
    return $this;
}

# レキシカルアナライザ本体
sub Analyze {
    my($this) = @_;
    return unless $this->{code};
    $this->debug("Analyze");

    my $qu = {string=>'"', char=>"'"};
    my $op = [
        quotemeta '!#$%&()*+,-./:;"\'<=>?@[\]^`{|}　、。・，．（）「」｛｝【】『』〔〕［］〈〉《》☆★※○●◎◇◆□■▽△▼▲①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳',
        [qw{== != <= >= << >> += -= *= /= %= |= &= ^= ++ -- -> => =< :: || &&},'/*','*/','//','##',"\\\n"],
        [qw{<<= >>= === !==}]
    ];

    my $t = new Token();
    my $state;
    my $code = [split //, $this->{code}]; push @$code, ('','','');
    for(my $i = 0; $i < @$code; $i++) {
        my $redo;
        $_ = $code->[$i];
        $t->text($t->text().$_);
        unless($state) {
            if(/[$op->[0]]/) { $state = 'op'; } # オペレータ
            elsif(/\d/) { $state = 'number'; }  # 数字
            elsif(/\s/) { $state = 'space'; }   # スペース
            else { $state = 'ident'; }          # それ以外はident
        }
        elsif($state eq 'number' && !/\d/) { $t->kind($state); $redo = 1; }
        elsif($state eq 'space'  && !/\s/) { $t->kind($state); $redo = 1; }
        elsif($state eq 'ident'  && /[\s$op->[0]]/) { $t->kind($state); $redo = 1; }
        # 文字列の処理
        elsif($state =~ /^(string|char)$/) {
            if(/$qu->{$state}/) { $t->kind($state); }
            elsif($_ eq $this->{esc}) { $state .= '_esc'; }
        }
        elsif($state =~ /^(.+)_esc$/) { $state = $1; }
        # コメントの処理
        elsif('ARRAY' eq ref $this->{comment}) {
            foreach my $cmt(@{$this->{comment}}) {
                $t->kind($state) if $state eq "comment_$cmt->{begin}" && substr($t->text, -length($cmt->{end})) eq $cmt->{end};
            }
        }

        # オペレータの処理
        if($state eq 'op') {
            $t->text('  '), $state = 'space' if $t->text eq '　';
            my $c = [$_, $_.$code->[$i+1], $_.$code->[$i+1].$code->[$i+2]];
            foreach my $j(0..2) {
                $t->text($c->[$j]), $i += $j if $j > 0 && grep{$c->[$j] eq $_} @{$op->[$j]};
                if('ARRAY' eq ref $this->{comment}) {
                    foreach my $cmt(@{$this->{comment}}) {
                        $state = "comment_$cmt->{begin}" if $t->text eq $cmt->{begin};
                    }
                }
            }
            if($state eq 'op') {
                while(my($k, $v) = each %$qu) {
                    $state = $k if $t->text eq $v;
                }
            }
            $t->kind($state) if $state eq 'op';
        }

        $t->kind($state) if /^$/;
        if(/\012|\015/) {
            $t->kind($state =~ /^(.+)_/ ? $1 : $state);
            $t->text(substr $t->text(), 0, length($t->text()) - 1);
            $t->{text} =~ s/\t/    /gm if $t->value =~ /^space_.*\t/;
            $t->{text} =~ s/　/  /gm   if $t->value =~ /^space_.*　/;
            $this->end->add($t) unless $t->text eq '';
            $this->end->add(new Token("\n", 'space'));
            $t = new Token();
            if('ARRAY' eq ref $this->{comment}) {
                 foreach my $cmt(@{$this->{comment}}) {
                    undef $state if $state eq "comment_$cmt->{begin}" && $cmt->{end} eq '\n';
                 }
             }
            $i++ if /\015/ && $code->[$i+1] =~ /\012/;
        } elsif($t->kind()) {
            $t->kind($1) if $t->kind() =~ /^(.+)_/;
            $t->text(substr $t->text(), 0, length($t->text()) - 1) if $redo;
            $t->{text} =~ s/\t/    /gm if $t->value =~ /^space_.*\t/;
            $t->{text} =~ s/　/  /gm   if $t->value =~ /^space_.*　/;
            $this->end->add($t) unless $t->text eq '';
            $t = new Token();
            undef $state;
            redo if $redo;
        }
    } # end for
}

sub setLine {
    my($this) = @_;
    my $line = 1;
    my $colum = 1;
    for(my $t = $this->begin; !$t->eof; $t = $t->next) {
        $t->{file} = $this->{file};
        $t->{line} = $line;
        $t->{colum}= $colum;
        $t->{len} = 0;
        $t->{len} += $_ foreach map{/[\x20-\x7f]/ ? 1 : 2} split //, $t->text;
        $colum += $t->{len};
        $t->{colend} = $colum;
        $colum = 1, $line++ if $t->text =~ /\n/;
    }
}

#===============================================================================
# 宣言を探す
sub find_define {
    my($this, $name) = @_;
    my $ret = [];
#my $t = $this->{begin};print("{begin} $t->line():prev=".$t->prev()."/next=".$t->next().":".$t->kind()."=>".$t->text().":".$t->eof()."\n");
#   $t = $this->begin();print("begin() $t->line():prev=".$t->prev()."/next=".$t->next().":".$t->kind()."=>".$t->text().":".$t->eof()."\n");
    for(my $t = $this->begin(); !$t->eof(); $t = $t->next()) {
#print("$t->line():".$t->prev()."/".$t->next().":".$t->kind()."=>".$t->text()."\n");
        next unless $t->kind() eq 'ident' && $t->text() eq $name;

        my $debug = "[Find] (" . $t->line() . ") ".$t->text();

        my $def;                # 宣言かどうか
        my $count = 0;          # テンプレート用カウンタ
        my $cls;
        my($begin, $end) = ($t, $t);
        while(!$begin->bof()) {
            $begin = $begin->prev();
            $_ = $begin->value();
            next if /^(space_.*|comment_.*|op_[\*&]+)$/;
            $cls = 1,next if /^op_::$/;
            $def = 1,next if /^ident_/ && !$cls;
            undef($cls),next if /^ident_/;
            $count++,next if $_ eq 'op_>';
            $count--,next if $_ eq 'op_<';
            last if $count < 0;
            last unless $count > 0 && /^(number_.*|op_,)$/;
        }
        if($def && !$count) {
            while(!$end->eof()) {
                $end = $end->next();
                $_ = $end->value();
                next if /^(space|comment)_/;
                $count++,next if $_ eq 'op_(';
                if($_ eq 'op_)') {
                    $count--;
                    last if $count < 0;
                    $end = $end->next(),last unless $count;
                    next;
                }
                last if /^op_[\{;]$/;
            }
        }
        if($def && !$count) {
            $begin = $begin->next();
            $begin = $begin->next() while $begin->kind() =~ /^(space|comment)$/;
            $end   = $end->prev();
            $end   = $end->prev()   while $end->kind()   =~ /^(space|comment)$/;
            push @$ret, {begin=>$begin, end=>$end, this=>$t};

            $debug .= ' <HIT> ' . $this->tokens($begin, $end) if $this->{debug};
        }
        $this->debug($debug);
    }
    return $ret;
}

#===============================================================================


my $directive = [qw{define undef if ifdef ifndef elif else endif include import using line pragma error warning ident}];
my $directive_reg = join '|', @$directive;
my $keyword = [
#値に関するキーワード
'nullptr',
# 型に関するキーワード
# 基本型
qw{int long short signed unsigned}, qw{float double}, qw{bool true false},
qw{char wchar_t char16_t  char32_t}, qw{void auto},
# 複合型
qw{class struct union enum},
# 型修飾子
qw{const volatile extern register static mutable thread_local},
# 宣言指定子
qw{friend typedef},
# 関数指定子
qw{constexpr explicit inline virtual},
# クラスに関するキーワード
# アクセス制御
qw{public protected private},
# その他
qw{operator this},
# 文に関するキーワード
# 制御構造
qw{if else}, 'for', qw{while do}, qw{switch case default},
qw{break continue goto return }, qw{try catch},
# 式に関するキーワード
# 動的記憶域確保
qw{new delete},
# 型変換
qw{dynamic_cast static_cast const_cast reinterpret_cast},
# 式に関する情報
qw{alignof decltype sizeof typeid},
# 例外処理
qw{throw noexcept},
# 表明
'static_assert',
# テンプレートに関するキーワード
qw{template typename export},
# 名前空間に関するキーワード
'namespace',
# usingディレクティブ（usingを参照）
'using',
# インラインアセンブラ
'asm',
# アトリビュート
'alignas',
# 文脈依存のキーワード
qw{final override},
# 代替表現
qw{and and_eq bitand bitor compl not not_eq or or_eq xor xor_eq}
];

my $keyword_reg = join '|', @$keyword;
my $substitution = {'and'=>'&&','and_eq'=>'&=','bitand'=>'&','bitor'=>'|','compl'=>'~',
    'not'=>'!','not_eq'=>'!=','or'=>'||','or_eq'=>'|=','xor'=>'^','xor_eq'=>'^='};

#===============================================================================
sub AnalyzeCPP {
    my($this) = @_;
    $this->debug("AnalyzeCPP");

    my $t = $this->{begin};
    while(!$t->eof) {
        $t = parse($t);
    }

#    for(my $t = $this->begin;!$t->eof;$t=$t->next) {
# print "#### ", @{$t->{class}}. "\n" if 'ARRAY' eq ref $t->{class};
#    }
}
sub movenext {
    my($t) = @_;
    my $prev  = $t;
    $t = $t->next('!(space|comment).*');
    $_ = $t->value;
    # classを継承
    $t->{class} = $prev->{class};
    # tokenを継承
    $t->{token} = $prev->{token} unless /^op_([\!\^\-\+\/%=\|\{\(\[\?:;,]|\+\+|\-\-|&&|\|\||<<|>>|.+=)$/;
    $t->{token} = [] unless $t->{token};
    push @{$t->{token}}, $t unless /^(op_[\(\{\[\)\}\;,:]|ident_(private|protected|public))$/;
    return $t;
}

sub parse {
    my($t) = @_;
    my $prev  = $t;
    my $pprev = $t->prev('!(space|comment).*');
    my $token = $prev->{token};

    $t = movenext($t);
    my $next  = $t->next('!(space|comment).*');
#print"#### $t->{file}($t->{line}) ". $t->debug, "\n";
    $_ = $t->value;
    # PH01 ===============================================================================================
    # C++キーワード
    if(/^ident_($keyword_reg)$/) {
        my $req;
        # kindを振り分けます
        $t->kind('keyword');
        $t->kind('statement') if /_(if|else|switch|case|default|for|do|while|continue|break|goto|return|try|catch|throw)$/;
        $t->kind($1)          if /_(namespace|using|typedef|template)$/;
        $t->kind('class')     if /_(class|struct|enum|union|typename)$/;
        $t->kind('method')    if /_(new|delete|sizeof|typeid)$/;
        $t->kind('cast')      if /_cast$/;
        $t->kind('valiable')  if /_(true|false|nullptr)$/;
        $t->kind('define')    if /_(int|long|short|float|double|bool|char|.*_t|void|auto|(un)?signed)$/;
        $t->kind('ident')     if /_(const|this)$/;
        $t->kind('accsess')   if /_(private|protected|public)$/;
        # 代替表現をC本来のオペレータに変換しちゃいます。
        $t->kind('op'), $t->text($substitution->{$1}) if /_(and|and_eq|bitand|bitor|compl|not|not_eq|or|or_eq|xor|xor_eq)$/;

        # アクセスマーク
        if(/_(private|protected|public)$/) {
            #$next->delete() if $next->value() =~ /^op_:$/;
            #$t->delete();
            if(grep{$_->kind eq 'class'} @$token) { $req = 'ident_' }
            elsif(grep{$_ ne $t} @{$t->{token}}) { parse_error($t) }
        }
        # 各ステートメントが次に要求するトークン種別を設定します。
        $req = '(ident_|op_[;\{])' if /_namespace$/;                 # }
        $req = '(ident_|op_\{)'    if /_(class|struct|enum|union)$/; # }
        $req = '(ident_|op_::)'    if /_using$/;
        $req = '(ident_|op_::)'    if /_typedef$/;
        $req = 'op_<$'             if /_template$/;
        $req = 'ident_'            if /_typename$/;
        $req = '(ident_|op_(::|[;\{]))' if /_(static|extern|inline|virtual|explicit|volatile|friend|const)$/; # }
        $req = 'op_\('             if /_(if|switch|for|while|catch)$/;
        $req = '(op_\{|ident_)'    if /_else$/; # }
        $req = 'ident_'            if /_goto$/;
        $req = '(ident|number|char)_' if /_case$/;
        $req = 'op_:'              if /_default$/;
        $req = '(op_[&\*;\-\+\(]|(ident|number|string|char)_)' if /_return$/;
        $req = 'op_;'              if /_(continue|break)$/;
        $req = 'op_\{'             if /_(do|try)$/;
        $req = '(op_[&\*\(]|ident_|number_|string_|char_)' if /_throw$/;
        $req = '(op_\(|ident_)'    if /_new$/;
        $req = '(op_[\(\[]|ident)' if /_delete$/;
        $req = '(op_\(|ident_)'    if /_sizeof$/;
        $req = 'op_\('             if /_typeid$/;
        $req = 'op_<'              if /_cast$/;
        $req = '(op_[,\(\)\*&>]|ident_.*)$' if /_(int|long|short|float|double|bool|char|.*_t|void|auto|(un)?signed)$/;
        # 各ステートメントが次に要求するトークンと次のトークンが一致しなければエラーにします。
        parse_error($t, $req) if $req && $next->value !~ /^$req/;

        # 以下のトークンは、tokenが存在するはずがない
        parse_error($t) if /_(return|continue|break|do|try|throw|using|typedef)$/ && grep{$_ ne $t && $_->kind ne 'statement'} @$token;
        # typename はtemplate設定でしか使えない
        parse_error($t) if /_typename$/  && grep{$_ ne $t && $_->kind ne 'template'} @$token;
        # namesapce は typeが無いか、usingのことしかありえない
        parse_error($t) if /_namespace$/ && grep{$_ ne $t && $_->kind ne 'using'} @$token;
    }
    # ディレクティブ
    elsif($_ eq 'op_#' && $next->value =~ /^ident_($directive_reg)$/) {
        $t->text("#$1"); $t->kind('directive');
        $next->delete();
        # TODO プリプロセッサ用処理
        $t = $t->next("space_\n");
        $t->{token} = [];
    }
    # :: オペレータは周りのidentを巻き込んで大きなidentにまとめます
    elsif(/^op_::$/) {
        if($next->kind() eq 'ident') {
            $t->text('::' . $next->text);
            $next->delete();
        } else { parse_error($t); }
        $t->kind('ident');
    }
    $_ = $t->value;
    $next  = $t->next('!(space|comment).*');

    # PH02 ===============================================================================================
    # 括弧
    if(/^(op_[\(\{\[])$/) {
        my $last = 'op_)';
        $last = 'op_}' if $_ eq 'op_{';
        $last = 'op_]' if $_ eq 'op_[';
        # class要素の構成
        my $class = $t->{class};
        if(!@$token && $prev->value eq 'op_)') {
            $t->{class} = $pprev->{class};
        } else {
            my $type = 'none';
            my $name = '';
            foreach(@$token) {
                $type = $_->kind if $_->kind =~ /^(namespace|class|method|statement)$/;
                $name = $_->text if $_->kind =~ /^(method|statement)$/;
                $name = $_->text if !$name && $_->kind eq 'define';
            }
            my $newclass = {token=>$token, type=>$type, name=>$name};
            if('ARRAY' eq ref $class) {
                ($newclass->{base}) = grep{$_->{type} =~ /^(namespace|class)$/} @$class;
            }
            $t->{class} = [$newclass];
            push @{$t->{class}}, @$class if 'ARRAY' eq ref $class;
        }
#print "token($t->{line}:" .$t->value. "~$last):". join(' ', map{$_->text} @{$t->{class}->[0]->{token}}). "\n" if 'ARRAY' eq ref $t->{class} && 'ARRAY'eq ref $t->{class}->[0]->{token};
        while(!$t->eof() && $t->value ne $last) {
            no warnings 'recursion';
            $t = parse($t);
        }
#print "Token($t->{line}:" .$t->value. "):". join(' ', map{$_->text} @{$t->{class}->[0]->{token}}). "\n" if 'ARRAY' eq ref $t->{class} && 'ARRAY'eq ref $t->{class}->[0]->{token};
        $t->{token} = [];
        $t->{class} = $class;
        $t = parse($t);
    }
    # 括弧
    elsif($_ eq 'op_<') {
        my $bk = $t;
#print "<token($t->{line}:" .$t->value."\n";
        while(!$t->eof()) {
            no warnings 'recursion';
            $t = parse($t);
            last if $t->value =~ /^op_([^,\*&]||::)/
        }
#print ">token($t->{line}:" .$t->value."\n";
        if($t->value eq 'op_>') {
            $t = parse($t);
        } else {
            $t = $bk;
            $t->{token} = [];
        }
    }
    # identの処理
    elsif(/^ident_/) {
        # identの次が::の場合はオペレータは周りのidentを引き連れて大きなindentにする。
        while($next->value eq 'op_::') {
            last if $next->eof;
            $t->text($t->text . '::');
            $next->delete;
            $next = $next->next('!(space|comment).*');
            if($next->kind eq 'ident') {
                $t->text($t->text . $next->text);
                $next->delete;
                $next = $next->next('!(space|comment).*');
            }
            # 知らなかったが、::* ->* .* なんていうオペレータがあるらしいのでその処理
            elsif($next->value eq 'op_*') {
                my $n = $next->next('!(space|comment).*');
                if($n->kind eq 'ident') {
                    $t->text($t->text . '*' . $next->text);
                    $next->delete;
                    $n->delete;
                    $next = $n->next('!(space|comment).*');
                }
            }
        }
        # namespace|class|usingに続くidentはなにかの宣言なのでdefineに変える
        if(grep{$t ne $_ && $_->kind =~ /^(namespace|class|using)$/} @$token) {
            $t->kind('define');
        }
        # identが２つ続いていたら、最初のidentは宣言だ。
        $prev->kind('define') if $prev->kind eq 'ident';
        
        $t->kind('valiable') if $prev->kind eq 'define' && $next->value eq 'op_[';

        if($t->kind eq 'ident') {
            # カッコの始まりならメソッドだと思われます。
            if($next->value eq 'op_(') {
                $t->kind('method');
                # ただし、methodに所属している場合の、define,method,(の順は、クラスのインスタンス化なのでvaliableです。
                if($prev->kind() eq 'define' && 'ARRAY' eq $t->{class} && $t->{class}->[0]->{type} eq 'method') {
                    $t->kind('valiable');
                }
            }
            # 構文の終わりっぽいところだったら変数だと思われます。
            $t->kind('valiable') if $next->value =~ /^op_([\!\^\-\+\/%=\|\?;,\)]|\+\+|\-\-|&&|\|\||<<|>>|.+=)$/;

            # : の場合は、ラベルだったりすることがあるので、更にその前を見て判断します
            if($next->value eq 'op_:') {
                if($prev->value =~ /^(op_\?|statement_case)$/) {
                    $t->kind('valiable');
                } else {
                    $t->kind('label');
                }
            }
        }
        $_ = $t->value;
    }
    # 宣言の前がidentならそのidentは宣言だ
    elsif(/^define_/ && $prev->kind eq 'ident') {
        $prev->kind('define');
    }
    # ポインタと参照
    elsif(/^op_[&\*]$/) {
        if($prev->kind eq 'ident') {
            # 直前がidentで、その前が宣言か文の終わりっぽいものなら、直前のidentは宣言だ
            if($pprev->value =~ /^(define_.*|op_[\{\};:,]|)$/){
                $prev->kind('define');
            }
            if($pprev->value =~ /^(op_[\(\{;:,]|keyword_.*)$/ && $next->kind eq 'ident'){
                $prev->kind('define');
            }
            # 直前がidentで、その前が演算子なら直前のidentは変数だ
            elsif($pprev->value =~ /^(op_[\(\)\+\-\*\/%\|&])$/) {
                $prev->kind('valiable');
            }
        }
        # 直前が宣言なら、ポインタも宣言にしちゃえ
        $t->kind('define') if $prev->kind eq 'define';
    }
    # アロー演算子の前がidentならそれは変数だ
    elsif(/^op_(->|\.)$/) {
        if($prev->kind() eq 'ident') {
            $prev->kind('valiable');
        }
    }
    # PH3==========================================================
    if($prev->kind eq 'valiable' && $pprev->kind eq 'define' && 'ARRAY' eq ref $t->{class}) {
#print "+++++ ". $prev->value. "\n";
        my $p;
        for($p = $pprev; !$p->bof; $p = $p->prev('!(space|comment).*')) {
            last unless $p->kind eq 'define';
        }
        unless($p->value eq 'keyword_static') {
            $t->{class}->[0]->{valiable} = [] unless $t->{class}->[0]->{valiable};
            push @{$t->{class}->[0]->{valiable}}, $prev;
        }
    } elsif($prev->kind eq 'method' && 'ARRAY' eq ref $t->{class}) {
        $t->{class}->[0]->{method} = [] unless $t->{class}->[0]->{method};
        push @{$t->{class}->[0]->{method}}, $prev;
    }

    return $t;
}

sub parse_error {
    my($t, @msg) = @_;
    my $prev = $t->prev('!(space|comment).*');
    my $next = $t->next('!(space|comment).*');
    die "parse error : " . join(" ", caller 0) . "\n" .
    "$t->{file} ($t->{line})\nprev=". $prev->value. "\nthis=". $t->value. "\nnext=". $next->value. "\n".
    join(' ', map{$_->text} @{$t->{token}}). "\n" . join("\n",  @msg). "\n";
}

sub debug {
    my($this, $msg) = @_;
    print "[LexicalAnalyzer] $msg\n" if $this->{debug};
}

1;
