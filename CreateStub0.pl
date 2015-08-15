#/usr/bin/perl

BEGIN {
    unshift @INC, map "$_/lib", $0 =~ /^(.*?)[^\/]+$/;
    unshift @INC, map "$_/lib", readlink($0) =~ /^(.*?)[^\/]+$/ if -l $0;
}

use strict;
use warnings;
use utf8;

use FileHandle;

use LexicalAnalyzer;

binmode STDIN , ':utf8';
binmode STDOUT, ':utf8';

my $path = "$ENV{HOME}/workspace";
my $file = "stub.txt";
my $define = 'STUB_Define.h';
my $definec= 'STUB_Define.cpp';

my $stub = {debug=>1};
my $fh = new FileHandle($file, 'r') or die "$file file open error:$!\n";
while(<$fh>) {
    chomp; s/#.+$//; next unless /(\w+)::(\w+)\s+(.+)/; #+
    find_define($1, $2, $3);
}
$fh->close();

my $fd = new FileHandle($define, 'w') or die "$define file open error:$!\n";
$fd->print("#ifndef STUB_DEFINE_H__\n");
$fd->print("#define STUB_DEFINE_H__\n");
$fd->print("namespace TEST {\n");
$fd->print("class STUB {\n");
$fd->print("public:\n");

my $fc =  new FileHandle($definec, 'w') or die "$definec file open error:$!\n";
$fc->print("#include \"$define\"\n");
$fc->print("namespace TEST {\n");

while(my($class, $s) = each %$stub) {
    next unless 'HASH' eq ref $s;
    foreach my $func(keys %{$s->{func}}) {
        my $obj = $s->{func}->{$func};

        my $flag;
        foreach my $p(@{$obj->{p}}) {
            my $count    = "${class}_${func}_count";
            my $ignition = "${class}_${func}_ignition";
            my $result   = $obj->{result};

            my $lex = $s->{$p->{h}}->{lex};
            my $t = $p->{end}->next('op_\{')->next();
my $e = $t->next('op_;');
debug("[Execute before]$s->{$p->{h}}->{file}\n".$lex->tokens($p->{begin}, $e));
            $lex->insert($t, [
               {text=>"\n"},
               {text=>"// >>>>> STUB begin\n"},
               {text=>"::TEST::STUB::$count++;\n"},
               {text=>"if(::TEST::STUB::$count ==\n::TEST::STUB::$ignition)\n{ $result }\n"},
               {text=>"// <<<<< STUB end\n"},
            ]);
debug("[Executed after]\n".$lex->tokens($p->{begin}, $e));

            $s->{$p->{h}}->{create} = 1;

            next if $flag;
            $fd->print("static unsigned long $count;\n");
            $fd->print("static unsigned long $ignition;\n");
            $fc->print("unsigned long STUB::$count = 0;\n");
            $fc->print("unsigned long STUB::$ignition = 0;\n");
            $flag = 1;
        }
    }
}
$fd->print("};\n");
$fd->print("} // end namespace TEST\n");
$fd->print("#endif // STUB_DEFINE_H__\n");
$fd->close();

$fc->print("} // end namespace TEST\n");
$fc->close();

while(my($class, $s) = each %$stub) {
    next unless 'HASH' eq ref $s;

    foreach my $h(grep /^(h|cpp)$/, keys %$s) {
        next unless exists $s->{$h}->{create};

        my $fh = new FileHandle($s->{$h}->{file}, 'w') or die "s->{$h}->{file} file open error:$!\n";
        $fh->print("#include \"$define\"\n");

        my $lex = $s->{$h}->{lex};
        for(my $t = $lex->begin(); !$t->eof(); $t = $t->next()) {
            $fh->print($t->text());
        }
        $fh->close();

        my $diff = "sdiff -s $s->{$h}->{path} $s->{$h}->{file}";
#        my $diff = "sdiff -c5 $s->{$h}->{path} $s->{$h}->{file}";
        debug("[sh command] $diff");
        system($diff);
    }
}

## DEBUG
#while(my($class, $s) = each %$stub) {
#    foreach my $func (keys %{$s->{func}}) {
#        print "[DEBUG] $class,$func,$s->{result},$s->{h}->{file},$s->{cpp}->{file}\n";
#    }
#}

# 宣言を探す
sub find_define {
    my($class, $func, $result) = @_;

    $stub->{$class} = {func=>{}} unless exists $stub->{$class};
    $stub->{$class}->{func}->{$func} = {p=>[], result=>$result} unless exists $stub->{$class}->{func}->{$func};
    my $s = $stub->{$class};
    my $f = $s->{func}->{$func};

    # ファイル検索
    unless(exists $s->{h} && exists $s->{cpp}) {
        my $reg  = '(cpp|h)$';
        my $grep = "egrep \"\\.$reg\" | grep -v \".org/\" | grep -v \"/test/\"";
        my $find = "find $path -name \"$class.*\" | $grep";
        debug("[sh command] $find");

        foreach(`$find`) {
            chomp; /$reg/;
            $s->{$1}->{path} = $_;
            $s->{$1}->{file} = [reverse split '/']->[0];
        }
    }
    return 0 unless exists $s->{h} && exists $s->{cpp};

    # レキシカルアナライザ作成
    foreach my $h(grep /^(h|cpp)$/, keys %$s) {
        next if exists $s->{$h}->{lex};
        my $param = {file=>$s->{$h}->{path}, debug=>$stub->{debug}};
        $s->{$h}->{lex} = new LexicalAnalyzer($param);
    }

    # メソッドを検索する
    foreach my $h(grep /^(h|cpp)$/, keys %$s) {
        debug("[Find Method] $class::$func,$s->{$h}->{file}");
        my $lex = $s->{$h}->{lex};
        my $find = $lex->find_define($func);
        foreach(@$find) {
            my $t = $_->{end}->next('op_.*');
debug("[Execute]$s->{$h}->{file} ".$lex->tokens($_->{begin}, $t));
            next if $t->text() ne '{';
            $_->{h} = $h;
            push @{$f->{p}}, $_;
        }
    }
    return 1 if @{$f->{p}};   # 検索できた場合終了

    # クラスを検索する
    debug("[Find Extended Class] $class,$s->{h}->{file}");

    my $lex = $s->{h}->{lex};
    my $flag = 0;
    my $find = $lex->find_define($class);
    foreach(@$find) {
        my $t = $_->{end}->next('op_[;\{]');
        next if $t->text() ne '{';
        for(my $p = $_->{this}->next(); $p != $t; $p = $p->next()) {
            $_ = $p->kind();
            next if /space|comment/;
            next if /op/ && $p->text() =~ /[,:]/;
            last if /op/;
            next if /ident/ && $p->text() =~ /^(public|protected|private)$/;
            $flag |= find_define($p->text(), $func, $result);
            last if $flag;
        }
        last if $flag;
    }
    debug("[Extended Class not found]") unless $flag;
    return $flag;
}

sub debug {
    print "[STUB] $_[0]\n" if exists $stub->{debug};
}
