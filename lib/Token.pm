#===============================================================================
# トークンオブジェクト
#===============================================================================
package Token;

use strict;
use warnings;
use utf8;

# オブジェクト作成
sub new {
	my($this, $text, $kind) = @_;
	$text = '' unless defined $text;
	$kind = '' unless defined $kind;
	$this = bless {
		prv=>undef,
		nxt=>undef,
		kind=>$kind,
		text=>$text
	}, $this;
	if(ref($text) =~ /^HASH$/ ) { $this->{$_} = $text->{$_} foreach keys %$text; }
	$this->{prv} = $this->{nxt} = $this;
	if(ref($text) =~ /^Token$/ ) { $this->{$_} = $text->{$_} foreach keys %$text; }
	return $this;
}

# テキスト取得設定
sub text {
	my($this, $text) = @_;
	$this->{text} = $text if defined $text;
	$this->{text};
}

# 種別取得設定
sub kind {
	my($this, $kind) = @_;
	$this->{kind} = $kind if defined $kind;
	$this->{kind};
}

# 種別-テキスト文字列取得
sub value {
	my($this) = @_;
	$this->kind .'_'. $this->text;
}

# 次トークン取得
sub next {
	my($this, $kind, $end) = @_;
	return $this->{nxt} unless $kind;
	my $flag; $flag = 1, $kind = $1 if $kind =~ /^!(.*)$/;
	while(!$this->eof($end)) {
		$this = $this->next;
		last if $flag ? $this->value !~ /^($kind)$/ : $this->value =~ /^($kind)$/;
	}
	return $this;
}

# 前トークン取得
sub prev {
	my($this, $kind, $end) = @_;
	return $this->{prv} unless $kind;
	my $flag; $flag = 1, $kind = $1 if $kind =~ /^!(.*)$/;
	while(!$this->bof($end)) {
		$this = $this->prev;
		last if $flag ? $this->value !~ /^($kind)$/ : $this->value =~ /^($kind)$/;
	}
	return $this;
}

# トークン追加
sub add {
	my $this = shift;
	foreach(@_) {
		my $add = $_;
		if('ARRAY' eq ref $add) {
			my $t = $this;
			$t->add($_), $t = $t->next foreach @$add;
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

# トークン挿入
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

# トークン削除
sub delete {
	my($this, $tuple) = @_;
	if('ARRAY' eq ref $tuple) {
		$this->delete($_) foreach @$tuple;
		return;
	} elsif('Token' eq ref $tuple) {
		$tuple->delete;
		return;
	}
	$this->prev->{nxt} = $this->next;
	$this->next->{prv} = $this->prev;
}

# トークン末尾判定
sub eof {
	my($this, $end) = @_;
	$end = new Token() unless 'Token' eq ref $end;
	return $this->next == $this || $end->next == $this;
}

# トークン先頭判定
sub bof {
	my($this, $end) = @_;
	$end = new Token() unless 'Token' eq ref $end;
	return $this->prev == $this || $end->prev == $this;
}

# トークン先頭取得
sub begin {
	my($this) = @_;
	my $ret = $this->prev;
	$ret = $ret->prev while !$ret->bof;
	return $ret;
}

# トークン末尾取得
sub end {
	my($this) = @_;
	my $ret = $this->next;
	$ret = $ret->next while !$ret->eof;
	return $ret;
}

# デバック用文字列取得
sub debug {
	my($this) = @_;
	"[$this] this=".$this->value." prev=".$this->value." next=".$this->value;
}

1;