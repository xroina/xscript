#===============================================================================
# クラスオブジェクト
#===============================================================================
package Class;

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
	my($this, $name, $type) = @_;
	$name = '' unless defined $name;
	$type = 'namespace' unless defined $type;
	$this = bless {
		class => [],
		name  => $name,
		type  => $type,
		token => {
			begin => new Token(),
			end   => new Token(),
			lst   => new Token()
		},
		dic   => {}
	}, $this;
	$this->{dic}->{'.'} = $this;
	return $this;
}
