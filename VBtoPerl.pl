#!/usr/bin/perl

BEGIN {
    unshift @INC, $0 =~ /^(.*?)[^\/]+$/;
    unshift @INC, readlink($0) =~ /^(.*?)[^\/]+$/ if -l $0;
}


use strict;
use warnings;
use utf8;
use FileHandle;

use LexicalAnalyzer;

# コマンド引数の取得
unless($ARGV[0]) {
    print "useage $0 [vb file name]\n";
    exit 0;
}
my $path = $ARGV[0];
my($file) = $path =~ /\/?(.*?\.(.+?))$/;

my $lex = new LexicalAnalyzer({file=>$path, debug=>1, comment=>[{begin=>"'", end=>'\n'}], esc=>''});

for(my $t = $lex->begin; !$t->eof; $t = $t->next) {
#print $t->value."\n";
    my $prev = $t->prev('!(space|comment)_.*');
    my $next = $t->next('!(space|comment)_.*');
    $_ = $t->value;

    if(/^comment_'/) {
        $t->{text} =~ s/^'/# /;
    }
    if(/^string_/) {
print $t->{line}.":".$t->value . " ". $next->value. "\n";
        if($t->text eq '""' && $t->next->text eq '""') {
            $t->text('"\""');
            $t->next->delete;
        }
        else {
            $t->{text} =~ s/\\/\\\\/gm;
        }
    }
    elsif(/^ident_(VERSION|Attribute|Option)$/) {
        my $end = $t->next('space_\n');
        $t->delete, $t = $t->next while !$t->eof($end);
        $t = $t->prev;
    }
    elsif(/^ident_End$/ && $next->value =~ /^ident_(Sub|Function|If|Select|Do|For|While)$/) {   # {
        $t->text('}');
        $t->kind('op');
        for(my $d = $t->next; !$d->eof($next); $d = $d->next) { $d->delete; }
    }
    elsif(/^ident_Exit$/) {
#print $t->{line}.":".$t->value . " ". $next->value. "\n";
        if($next->value =~ /^ident_(Sub|Function)$/){
            $t->text('return;');
            for(my $d = $t->next; !$d->eof($next); $d = $d->next) { $d->delete; }
        }
        elsif($next->value =~ /^ident_(Do|While|For)$/) {
            $t->text('break');
            for(my $d = $t->next; !$d->eof($next); $d = $d->next) { $d->delete; }
        }
    }
    elsif(/^ident_Wend$/) { # {
        $t->text('}');
        $t->kind('op');
    }
    elsif(/^ident_If$/) {
        my $then = $t->next('ident_Then');
        my $state = $then->next('ident_.*|comment_.*|space_\n');
        unless($state->kind eq 'ident') {
            for(my $o = $t->next; !$o->eof($then->prev); $o = $o->next) {
                $o->{text} = '==' if $o->value eq 'op_=' 
            }
            $t->text('if');
            $t->add(new Token('(', 'op'));
            $then->prev('!space_.*')->add(new Token(')', 'op'));
            $then->text('{');   # }
            $then->kind('op');
        }
    }
    elsif(/^ident_While$/) {
        $t->text('while');
        $t->add(new Token('(', 'op'));
        $t->next('comment_.*|space_\n')->prev('!space_.*')->add(new Token(') {', 'op')); # }
    }
    elsif(/^ident_Else$/) { $t->text('} else {'); }
    elsif(/^op_\.$/) { $t->text('->'); }
    elsif(/^op_<$/ && $t->next->value eq 'op_>')  { $t->text('!='); $t->next->delete; }
    elsif(/^ident_And$/) { $t->text('&&'); $t->kind('op'); }
    elsif(/^ident_Or$/ ) { $t->text('||'); $t->kind('op'); }
    elsif(/^ident_Not$/) { $t->text('!'); $t->kind('op');  }
    
}
    
for(my $t = $lex->begin; !$t->eof; $t = $t->next) {
    my $prev = $t->prev('!(space|comment)_.*');
    my $next = $t->next('!(space|comment)_.*');
    $_ = $t->value;

    if(/^ident_(Else)?If$/) {
        $t->text($1 ? 'elsif' : 'if');
        my $then = $t->next('ident_Then');
        for(my $o = $t->next; !$o->eof($then->prev); $o = $o->next) {
            $o->{text} = '==' if $o->value eq 'op_=' 
        }
        my $state = $then->next('ident_.*|comment_.*|space_\n');
        my $end = $state->next('comment_.*|space_\n')->prev('!space_.*');
        for(my $s = $state; !$s->eof($end); $s = $s->next) {
            $t->insert(new Token($s));
        }
        $t->insert(new Token(' ', 'space'));
        for(my $d = $then->next; !$d->eof($end); $d = $d->next) { $d->delete; }
        $then->text(';');
        $then->kind('op');
    }
    elsif(/^ident_Select$/ && $next->value eq 'ident_Case') {
        $t->text('switch');
        my $end = $next->next('comment_.*|space_\n')->prev('!space_.*');
        for(my $d = $t->next; !$d->eof($next); $d = $d->next) { $d->delete; }
        $next = $t->next('!(space|comment)_.*');
        $next->insert("(");
        $end->add(") {");
    }
    elsif(/^ident_Case$/) {
        $t->text('elsif');
        my $end = $next->next('comment_.*|space_\n')->prev('!space_.*');
        $next->insert("(");
        $end->add(") {");
    }
    elsif(/^ident_(Dim|Public|Private|Global|Protected)$/) {
        if($next->value =~ /^ident_(Sub|Function)$/) {
            $t->text('sub');
            $t->kind('keyword');
            for(my $d = $t->next; !$d->eof($next); $d = $d->next) { $d->delete; }
            $next = $t->next('!(space|comment)_.*');
            
        }
        elsif($next->kind eq 'ident') {
            $t->text('my');
            $t->kind('define');

            $t = $next;
            $next = $t->next('!(space|comment)_.*');
            $t->kind('valiable');
            $t->text('$'.$t->text);
            
            if($next->value eq 'ident_As') {
                for(my $d = $t->next; !$d->eof($next); $d = $d->next) { $d->delete; }
                $next = $t->next('!(space|comment)_.*');
                if($next->value eq 'ident_New') {
                    $next->text('new');
                    $next->kind('method');
                    $t = $next;
                    $next = $t->next('!(space|comment)_.*');
                } elsif($next->kind eq 'ident') {
                    for(my $d = $t->next; !$d->eof($next); $d = $d->next) { $d->delete; }
                    $t->add("; # $next->{text}");
                  #  $t->add(new Token(';', 'op'), new Token(' ', 'space'), new Token("# $next->{text}", 'comment'));
                }
            }
        }
    }
}
$lex->begin->insert(
    'use strict;', "\n",
    'use warnings;', "\n",
    'use utf8;', "\n",
    'use FileHandle;', "\n",
    "\n",
);

my $fh = new FileHandle("$file.pl", 'w') or die "file open error:$!\n";
$fh->binmode(":utf8");
my $title = $file;
for(my $t = $lex->begin; !$t->eof; $t = $t->next) {
    $fh->print($t->text);
}

exit;

