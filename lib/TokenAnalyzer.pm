#===============================================================================
package TokenAnalyzer;

BEGIN {
    unshift @INC, $0 =~ /^(.*?)[^\/]+$/;
    unshift @INC, readlink($0) =~ /^(.*?)[^\/]+$/ if -l $0;
}

use strict;
use warnings;
use utf8;
use Token;


# オブジェクト作成
sub new {
    my($this, $params) = @_;
    $this = bless {
    	begin=>new Token(),
    	end=>new Token(),
    	esc=>'\\',
        comment=>[
        	{begin=>'/*', end=>'*/'},
        	{begin=>'//', end=>'\n'}
        ]
    }, $this;
    $this->{begin}->add($this->{end});
    $this->{$_} = $params->{$_} foreach keys %$params;

    return $this;
}

# トークンの先頭を取得
sub begin {
    my($this) = @_;
    return $this->{begin}->next;
}

# トークンの末尾を取得
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
        $begin = $this->get($begin)->next unless 'Token' eq ref $begin;
        $end   = $this->get($end)         unless 'Token' eq ref $end;
        my $ret = [];
        for(my $t = $begin; !$t->eof($end); $t = $t->next) {
            push @$ret, $t if $flag ? $t->value !~ /^($kind)$/ : $t->value =~ /^($kind)$/;
        }
        return $ret;
    }

    if(defined $begin) {
        my $ret;
        if('Token' eq ref $begin) { $ret = $begin; } else {
            for(my($t, $i) = ($this->begin, 0); !$t->eof; $t = $t->next, $i++) {
                $ret = $t,last if $i == $begin;
            }
        }
        return $ret if $flag ? $this->value !~ /^($kind)$/ : $this->value =~ /^($kind)$/;
        return new Token();
    }

    my $ret = [];
    for(my $t = $this->begin; !$t->eof; $t = $t->next) {
        push @$ret, $t if $flag ? $this->value !~ /^($kind)$/ : $this->value =~ /^($kind)$/;
    }
    return $ret;
}

# トークン文字列取得
sub tokens {
    my($this, $begin, $end) = @_;
    $begin = $this->begin unless $begin;
    $end   = $this->end   unless $end;
    my $ar = [];
    my $t = $begin;
    push @$ar, '[BOF]' if $t->prev->bof;
    while(!$t->eof($end)) {
        push @$ar, $t->text if $t->kind !~ /^(space|comment)$/;
        $t = $t->next;
    }
    push @$ar, '[EOF]' if $t->eof;
    return join ' ', @$ar;
}

# トークン文字列取得2
sub print {
    my($this, $begin, $end) = @_;
    $begin = $this->begin unless $begin;
    $end   = $this->end   unless $end;
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

# トークン文字列取得3
sub string {
    my($this, $begin, $end) = @_;
    $begin = $this->begin unless defined $begin;
    $end   = $this->end   unless defined $end;
    my $s = '';
    for(my $t = $begin; !$t->eof($end); $t = $t->next) {
        my $text = $t->text; $_ = $t->kind;
        next if /^comment$/;
        $text = ' ' if /^space$/;
        $s .= $text;
    }
    $s =~ s/\s+/ /mg; $s =~ s/^ ?(.*?) ?$/$1/;
    return $s;
}

1;
