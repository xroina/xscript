package Utility;

use strict;
use warnings;
use utf8;
use Encode;

my $optionRegexp = sub {
	my($str) = @_;
	return '--?'. substr($str, 0, 1) . '(?:'. quotemeta(substr($str, 1)) . ')?';
};

sub getLine {
	my ($str) = @_;
	chomp $str;
	$str =~ s/^\s*(.*?)\s*$/$1/;
	$str =~ s/#.*$//;
	return $str;
}

sub getStartOption {
	my($param, $options, $path) = @_;

	$path = 'path' unless $path;
	$param = {} unless $param;
	$param->{$path} = [] unless 'ARRAY' eq ref $param->{$path};

	my $regex = [];
	foreach(@$options) {
		$_ = getLine($_);
		next unless $_;

		my $obj = {name=>$_, type=>'bool', regex=>''};
		if(/^(.*?)\s*=\s*(.*)$/) {
			($obj->{name}, $obj->{type}) = ($1, $2);
			$obj->{regex} = &$optionRegexp($obj->{name}) . '[=:]?';
			if($obj->{type} eq '#' || $obj->{type} =~ /^I(Int(eger)?)?$/i ) {
				$obj->{regex} .= '(\\d+)?';
				$obj->{type} = 'int';
			}
			elsif($obj->{type} eq '*' || $obj->{type} =~ /^S(tr(ing)?)?$/i) {
				$obj->{regex} .= '(.+)?';
				$obj->{type} = 'string'
			}
			elsif($obj->{type} eq '@' || $obj->{type} =~ /^A(rray)?$/i) {
				$obj->{regex} .= '(.+)?';
				$obj->{type} = 'array'
			}
			elsif($obj->{type} eq '&' || $obj->{type} =~ /^F(ile)?/i) {
				$obj->{regex} .= '(.+)?';
				$obj->{type} = 'file';
			}
		} else {
			$obj->{regex} = &$optionRegexp($_);
		}
		push @$regex, $obj;
	}

	foreach my $arg(@ARGV) {
		my $flag;
		foreach my $reg(@$regex) {
			my($n, $r, $t) = (lc $reg->{name}, "^$reg->{regex}\$", $reg->{type});
			my $f = "$n\_flag";
			if($arg =~ /$r/i) {
				if($t eq 'bool') {
					$param->{$n} = 0 unless exists $param->{$n};
					$param->{$n} = !$param->{$n};
				}
				elsif($1) {
					if($t eq 'int') { $param->{$n} = $1 + 0; }
					elsif($t eq 'array') {
						$param->{$n} = [] if 'ARRAY' eq ref $param->{$n};
						push @{$param->{$n}}, Encode::decode('utf8', $1);
					}
					else { $param->{$n} = Encode::decode('utf8', $1); }
				}
				else { $param->{$f} = 1; }
				$flag = 1;
			}
			elsif($param->{$f}) {
				if($t eq 'int') { $param->{$n} = $arg + 0; }
				elsif($t eq 'array') {
					$param->{$n} = [] if 'ARRAY' eq ref $param->{$n};
					push @{$param->{$n}}, Encode::decode('utf8', $arg);
				}
				else { $param->{$n} = Encode::decode('utf8', $arg); }
				delete $param->{$f};
				$flag = 1;
			}
			if('file' eq $t && $param->{$n}) {
				use FileHandle;
				my $fh = new FileHandle($param->{$n}) or die "$param->{$n} file open error:$!";
				$fh->binmode(':utf8');
				while(<$fh>) {
					$_ = getLine($_);
					next unless $_;

					if(/^(\w+)\s*=\s*(.*)$/) {
						$param->{lc $1} = $2;
					} else {
						push(@{$param->{$path}}, split ' ', $_);
					}
				}
			}
		}

		push @{$param->{$path}}, Encode::decode('utf8', $_) unless $flag;
	}
}

sub createSymLink {
	my($prog) = $0 =~ /^(.*?)[^\/]+$/;
	($prog) = readlink($0) =~ /^(.*?)([^\/]+)$/ if -l $0;
	foreach('js', 'css', 'img') {
		if(-d "$prog/$_") {
			unlink $_ if -d $_;
			symlink "$prog/$_", $_;
		}
	}
}

sub toHtml {
	($_) = @_;
	s/&/&amp;/gm;
	s/</&lt;/gm;
	s/>/&gt;/gm;
	s/"/&quot;/gm;
	s/\t/    /gm;
	s/\n/&nbsp;\n/gm;
	s/ /&nbsp;/gm;
	
	return $_;
}

sub getRecursivePath {
	my($in, $ext) = @_;
	my $ret = [];
	foreach my $path(@$in) {
		if(-d $path) {
			$path =~ s#/$##;
			no warnings 'recursion';
			getRecursivePath($_, $ext) foreach glob "$path/*";
		}
		elsif(-f $path) {
			next if $ext && $path !~ /\.($ext)$/;
			unless($path =~ m#^/#) {
				use Cwd 'getcwd';
				$path = getcwd()."/$path";
			}
			$path =~ s#/(\.?/)+#/#mg;
			$path =~ s#[^/]+/\.\./##mg;
			push @$ret, $path;
		}
		elsif($path =~ /\*/) {
			no warnings 'recursion';
			getRecursivePath($_, $ext) foreach glob $path;
		}
	}
}

1;