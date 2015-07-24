#!/usr/bin/perl

use strict;
use warnings;
use utf8;

BEGIN { unshift @INC, ("$ENV{HOME}/bin", "$ENV{HOME}/workspace/develop/MACP/MFOP/test/MFOPTESTCM0010/script"); }

use FileHandle;
use Data::Dumper;

use LexicalAnalyzer;

# パス設定
my $sdk       = $ENV{BASE_ENV};
my $workspace = "$ENV{HOME}/workspace";
my $develop   = "$workspace/develop";

print "sdk = $sdk\n";
print "dev = $develop\n";

# 設定ファイル
my $conf = 'stub.txt';

# 出力ファイル
my $outd = 'CC_STUB.h';
my $outc = 'CC_STUB.cpp';

my $stub = {debug=>1};

# 設定ファイルから情報をとりだし、ヘッダを解析する
my $fh = new FileHandle($conf, 'r') or die "$conf file open error:$!\n";
while(<$fh>) {
    chomp; s/#.+$//;
    next unless my($class, $func, $result) = /(\w*(?:::)?\w+)::(\w+)\s+(.+)/; # +
    find_define($class, $func, $result);
}
$fh->close();

# 不必要になった情報を削除する
while(my($class, $s) = each %$stub) {
    next unless 'HASH' eq ref $s;
    my $flag;
    foreach my $func(keys %{$s->{func}}) {
        my $f = $s->{func}->{$func};
        $flag = 1, next if @{$f->{p}};
        debug("[Flash] $class\::$func");
        delete $s->{func}->{$func};
    }
    debug("[Flash] $class"), delete $stub->{$class} unless $flag;
}

# nmコマンドで.soからシンボル情報を検索する
while(my($class, $s) = each %$stub) {
    next unless 'HASH' eq ref $s;
    foreach my $func(keys %{$s->{func}}) {
        my $f = $s->{func}->{$func};

        $f->{nm} = {};

        my $path = [grep {-d $_} ("$sdk/lib", "$develop/lib", "$develop/lib/RHEL6.5")];
#        push @$path, "$workspace/*/Debug" unless @$path;

        my $nm = "nm -o " . join(' ', map{"$_/*.so"} @$path) . " | grep '$func'";
        $nm .= join'', map{" | grep '$_'"} split('::', $class);
        debug("[sh] $nm");
        foreach(`$nm`) {
            chomp;
            next unless my($so, $type, $name, $file) = m/^(.+):[0-9a-f]+ (\w) (\w+)\s*(.*)$/;
            next if $f->{nm}->{$name};
            my($method) = `c++filt -i $name`;
            next unless $method =~ /^$class\::$func\(/ && $method =~ /\)$/;
            $f->{nm}->{$name} = {so=>$so, lex=>new LexicalAnalyzer({code=>$method}), method=>$method, file=>$file};
        }
        debug("[nm]". $f->{nm}->{$_}->{lex}->tokens(). " >> $f->{nm}->{$_}->{so} : $_") foreach keys %{$f->{nm}}
    }
}

# フックおよびスタブのコードを生成する
my $head    = [];
my $define  = [];
my $foot    = [];

my $include = [];
my $static  = [];
my $code    = [];

push @$head, '#ifndef __CC_STUB_H__';
push @$head, '#define __CC_STUB_H__';
push @$head, '';
push @$head, '#include "AC_STUB.h"';

push @$define, 'namespace HOOK {';

push @$static, 'using std::cout;';
push @$static, 'using std::endl;';
push @$static, '';
push @$static, 'namespace HOOK {';
push @$static, '';

push @$include, '#include <iostream>';
push @$include, '#include "CC_STUB.h"';

while(my($class, $s) = each %$stub) {
    next unless 'HASH' eq ref $s;
    next unless $s->{file};
    push @$head, "#include \"$s->{file}\"";

    foreach my $func(keys %{$s->{func}}) {
debug("******** $class\::$func");
        my $f = $s->{func}->{$func};

        my $ignition = "$class\_$func"; $ignition =~ s/::/_/;

        push @$define, "";
        push @$define, "class CC_$ignition : public AC_STUB {";
        push @$define, "public:";

        push @$foot,   "extern CC_$ignition $ignition;";

        my $names = [];

        my $i = 0;
        while(my($ln, $nm) = each %{$f->{nm}}) {
            $i++;
            push @$names, {func=>$ln, so=>$nm->{so}};
            my $p = $f->{p}->[0];
            my $arg = [];
            my $lex = $nm->{lex};
            my $begin = $lex->begin()->next('op_\(');
            my $end   = $lex->end()->prev('op_\)');
            my $count = 0;
            for(my($t, $a) = ($begin->next(), ''); !$t->eof($end); $t = $t->next()) {
                $_ = $t->value();
                next if /^comment/;
                $count++ if /^op_<$/;
                $count-- if /^op_>$/;
                $a .= $t->text() if $count || !/^op_[,\)]$/;
                if(!/^space/ && !$count && /^op_[,\)]$/) {
                    my $p = 'p' . (1 + @$arg);
                    $a =~ s/\s+/ /mg; $a =~ s/^ ?(.*?) ?$/$1/;
                    push(@$arg, {type=>$a, prm=>$p}) if $a;
                    $a='';
                }
            }
#debug("****". $lex->tokens($lex->{begin}, $lex->{end}));
#debug("****". $lex->tokens($begin, $end));
#debug("****" . " Dump ". Dumper($arg));
            my $def = '';
            my $ret = '';
            my $this;
            my $e = $p->{this}->prev();
#debug("****". $lex->tokens($p->{begin}, $e));
            for(my $t = $p->{begin}; !$t->eof($e); $t = $t->next()) {
                my $text = $t->text();
                $_ = $t->value();
                next if /^comment/;
                $this = 1,next if /^ident_static$/;
                $count-- if /^op_>$/;
                $ret .= $text if !$count && $text !~ /^(const|template|[<>])$/;
                $def .= $text if !$count && $text !~ /^(template|[<>])$/;
                $count++ if /^op_<$/;
            }
            $def =~ s/\s+/ /mg; $def =~ s/^ ?(.*?) ?$/$1/;
            $ret =~ s/\s+/ /mg; $ret =~ s/^ ?(.*?) ?$/$1/;

            my $type = "F$i";

            my $args = join ',', map{"$_->{type} $_->{prm}"} @$arg;

            unshift @$arg, {type=>'void*', prm=>'this'} unless $this;

            push @$define, "    typedef $ret (*$type)(" . join(', ', map{"$_->{type}"} @$arg) . ");";

            push @$code, "";
            push @$code, "$def $class\::$func($args) {";
            push @$code, "    if(::HOOK::AC_STUB::debug) cout << \"[HOOK] $class\::$func(\"";
            push @$code, "        ". join('<< ","', map{" << $_->{prm}"} @$arg) . " << ')';";
            push @$code, "    $ret ret;" unless $ret eq 'void';
            push @$code, "    if(::HOOK::$ignition.execute && ::HOOK::$ignition.ignition ==";
            push @$code, "            ++::HOOK::$ignition.count) {";
            push @$code, "        if(::HOOK::AC_STUB::debug) cout << \"!! Ignition !!\" << endl;";
            push @$code, "        $f->{result}";
            push @$code, "    }";
            push @$code, "    typedef const ::HOOK::CC_$ignition\::$type F;";
            push @$code, "    F org = (F)::HOOK::$ignition.getFunc(";
            push @$code, "            \"$ln\");";
            push @$code, "    ret = (*org)(" . join(',', map{$_->{prm}} @$arg) . ");";
            if($ret eq 'void') {
                push @$code, "    if(::HOOK::AC_STUB::debug) cout << endl;";
                push @$code, "    return;";
            } else {
                push @$code, "    if(::HOOK::AC_STUB::debug) cout << \"->ret=\" << ret << endl;";
                push @$code, "    return ret;";
            }
            push @$code, "}";
            push @$code, "";
        }

        push @$define, '';
        push @$define, "    CC_$ignition\();";
        push @$define, "    virtual ~CC_$ignition\();";
        push @$define, '';
        push @$define, 'private:';
        push @$define, '    static const T_so_func_list list;';
        push @$define, '';
        push @$define, "}; // end class CC_$ignition\()";

        push @$static, '';
        push @$static, '#ifdef STUB_CLASS_';
        push @$static, '#undef STUB_CLASS_';
        push @$static, '#endif';
        push @$static, "#define STUB_CLASS_ CC_$ignition";
        push @$static, '';
        push @$static, 'const T_so_func_list STUB_CLASS_::list = {';
        push @$static, join ",\n", map {"    T_so_func_pair(\"$_->{so}\", \"$_->{func}\")"} @$names;
        push @$static, "};";
        push @$static, '';
        push @$static, 'STUB_CLASS_::STUB_CLASS_() : AC_STUB(list) { }';
        push @$static, 'STUB_CLASS_::~STUB_CLASS_()                { }';
        push @$static, '';
        push @$static, "STUB_CLASS_ $ignition;";

    }
}
push @$foot, '} // end namespace HOOK';
push @$foot, '#endif // __CC_STUB_H__';

push @$static, "";
push @$static, "} // end namespace HOOK";

# フックおよびスタブのコードを出力する
my $fd = new FileHandle($outd, 'w') or die "$define file open error:$!\n";
$fd->print(join "\n", @$head);    $fd->print("\n\n");
$fd->print(join "\n", @$define);  $fd->print("\n\n");
$fd->print(join "\n", @$foot);    $fd->print("\n\n");
$fd->close();

my $fc = new FileHandle($outc, 'w') or die "$define file open error:$!\n";
$fc->print(join "\n", @$include); $fc->print("\n\n");
$fc->print(join "\n", @$static);  $fc->print("\n\n");
$fc->print(join "\n", @$code);    $fc->print("\n\n");
$fc->close();

# できたソースコードを出力する。
debug("Created $outd");
system "cat $outd" if $stub->{debug};
debug("Created $outc");
system "cat $outc" if $stub->{debug};


# メソッド定義を検索する
sub find_define {
    my($class, $func, $result) = @_;
    debug("[Find Method] $class\::$func");

    $stub->{$class} = {func=>{}} unless exists $stub->{$class};
    $stub->{$class}->{func}->{$func} = {result=>$result} unless exists $stub->{$class}->{func}->{$func};
    my $s = $stub->{$class};
    my $f = $s->{func}->{$func};
    $f->{p} = [] unless exists $f->{p};

    # ファイル検索
    unless(exists $s->{path}) {
        my $path = [grep {-d $_} ("$workspace/TP_IIR_SDK/inc", $develop)];
        push @$path, $workspace unless @$path;

        my $cls = $class; $cls =~ s/^.+:://;

        my $find = "find " . join(' ', map{"$_/"} @$path) . " -name \"$cls.h\" | grep -v \".org/\" | grep -v \"/test/\"";
        debug("[sh] $find");
        ($_) = `$find`;
        if($_) {
            chomp;
            $s->{path} = $_;
            $s->{file} = [reverse split '/']->[0];
        }
    }
    return 0 unless exists $s->{path};

    # レキシカルアナライザ作成
    unless(exists $s->{lex}) {
        my $prm = {file=>$s->{path}, debug=>$stub->{debug}};
        $s->{lex} = new LexicalAnalyzer($prm);
    }

    # メソッドの検索
    debug("[Anlaize Method] $class\::$func -> $s->{file}");
    my $lex = $s->{lex};
    push @{$f->{p}}, $_ foreach @{$lex->find_define($func)};
    return 1 if @{$f->{p}};	# 検索できた場合は終了

    # 継承クラス検索
    debug("[NotFound Method] $class\::$func,$s->{file} -> [Anlaize Extended Class] $class");
    my $find = $lex->find_define($class);
    my $flag = 0;
    foreach(@$find) {
        my $end = $_->{end}->next('op_[;\{]');
        next unless $end->text() eq '{';
        for(my $t = $_->{this}->next(); !$t->eof($end); $t = $t->next()) {
            $_ = $t->value();
            next if /^(space|comment)/;
            next if /^op_[,:]/;
            last if /^op/;
            next if /^ident_(public|protected|private)$/;
            debug("Extended Class] $class -> ". $t->text());
            $flag |= find_define($t->text(), $func, $result);
            last if $flag;
        }
        last if $flag;
    }
    debug("[Extended Class Not Found]") unless $flag;
    return $flag;
}

sub debug {
    print "[STUB] $_[0]\n" if $stub->{debug};
}

