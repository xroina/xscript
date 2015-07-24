my $str_qu = {string='"', char="'"};

sub LexicalAnalyzer {
	my($file) = @_;
	my $tokens = [];
	print "[READ] $file\n";
	
	open FH, $file or die "$file file open error\n";
	
	my $state = '';
	my $token = '';
	my $line = 1;
	my $redo = 0;
	my $c;
	
	for(;;) {
		my $eof;
		$eof = read FH, $c, 1 unless $redo;
		$token .= $c;
		my $kind = '';
		if(!$state) {
			if   ($c =~ /\d/    ) { $state = 'number'; }
			elsif($c =~ /\w/    ) { $state = 'ident';  }
			elsif($c =~ /[#@]/  ) { $state = 'prog';   }
			elsif($c eq '"'     ) { $state = 'string'; }
			elsif($c eq "'"     ) { $state = 'char';   }
			elsif($c =~ /[\n\r]/) { $kind = 'cr';      }
			elsif($c =~ /\s/    ) { $state = 'space';  }
			elsif($c =~ /[\(\)\{\}\[\]\.,;]/) { $kind = "op_$c";  }
			else                  { $state = 'op';     }
		}
		elsif($state eq 'number' && $c !~ /\d/) { $kind = $state; $redo = 1; }
		elsif($state eq 'ident'  && $c !~ /\w/) { $kind = $state; $redo = 1; }
		elsif($state eq 'prog'   && $c !~ /\w/) { $kind = $state; $redo = 1; }
		elsif($state eq 'space'  && $c !~ /\s/) { $kind = $state; $redo = 1; }
		elsif($state =~ /^(string|char)$/) {
			if($c eq $str_qu->{$state}) { $kind = $state; }
			elsif($c eq '\\') { $state .= '_esc'; }
		}
		elsif($state =~ /^(.*)_esc$/) { $state = $1; }
		elsif($state eq 'op') {
			if($token =~ /^\/[\/\*]$/) { $state = "comment$token"; }
			elsif($c =~ /[\w#@"'\s\(\)\{\}\[\]\.,;]/) { $kind = $state; $redo = 1; }
		}
		elsif($state eq 'comment/*') { $kind = $state if $token =~ /\*\/$/; }
		elsif($state eq 'comment//') { $kind = $state if $c =~ /[\n\r]/;    }
		
		$line++ if $c =~ /[\n\r]/;
		
		$kind = $state if !$eof;
		if($kind) {
			$token = substr $token, 0, length($token) - 1 if $redo;
			$kind .= "_$token" if $kind eq 'op';
			last if $kind eq 'op_';
			
			push @$tokens, {kind=>$kind, value=>$token, line=$line};
			$state = '';
			$token = '';
			redo if $redo;
		}
		last if !$eof
	} # end for(;;)
	
	close FH;
	
	return $tokens;
}
