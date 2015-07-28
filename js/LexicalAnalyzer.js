function Token(text, kind) {
	if(!text) text = '';
	if(getType(kind) !== 'String') kind = '';
	if(getType(text).match(/^(Array|Object|Function)$/)) {
		this.text = '';
		for(i in text) this[i] = text[i]
	} else this.text = text;
	this.kind = kind;
	this.nxt  = this;
	this.prv  = this;
};

Token.prototype.eof = function(end) {
	if('Object' !== getType(end)) end = new Token();
	return this.nxt == this || end.nxt == this;
};

Token.prototype.bof = function(end) {
	if('Object' !== getType(end)) end = new Token();
	return this.prv == this || end.prv == this;
};

Token.prototype.value = function() {
	return this.kind + '_' + this.text;
};

Token.prototype.next = function(kind, end) {
	if(!kind) return this.nxt;
	var flag = false, t = this;
	if(kind.match(/^!(.*)$/)) { flag = true, kind = RegExp.$1; }
	var re = new RegExp('/^(' + kind + ')$/');
	while(!t.eof(end)) {
		t = this.nxt;
		if(flag ? !t.value().match(re) : t.value().match(re)) break;
	}
	return t;
};

Token.prototype.prev  = function(kind, end) {
	if(!kind) return this.prv;
	var flag = false, t = this;
	if(kind.match(/^!(.*)$/)) { flag = true, kind = RegExp.$1; }
	var re = new RegExp('/^(' + kind + ')$/');
	while(!t.bof(end)) {
		t = t.prv;
		if(flag ? !t.value().match(re) : t.value().match(re)) break;
	}
	return t;
};

Token.prototype.add = function() {
	for(var i in arguments) {
		var add = arguments[i];
		if('ARRAY' === getType(add)) {
			var t = this;
			for(var j in add) { t.add(add[j]); t = t.nxt; }
			return;
		}
		if('Object' !== getType(add)) add = new Token(add);
		if(!this.eof() && add.eof()) add.nxt = this.nxt;
		add.prv = this;
		if(!this.eof()) this.nxt.prv = add;
		this.nxt = add;
	}
};

Token.prototype.insert = function() {
	for(var i in arguments) {
		var ind = arguments[i];
		if('ARRAY' === getType(ins)) {
			for(var j in ins) this.insert(ins[j]);
			return;
		}
		if('Object' !== getType(ins)) ins = new Token(ins);
		if(!this.bof) ins.prv = this.prv;
		ins.nxt = this;
		if(!this.bof) this.prev().nxt = ins;
		this.prv = ins;
	}
};

Token.prototype.remove = function(tuple) {
	if('ARRAY' === getType(tuple)) {
		for(var i in tuple) this.remove(tuple[i]);
		return;
	} else if(tuple) {
		tuple.remove();
		return;
	}
	this.prv.nxt = this.nxt;
	this.nxt.prv = this.prv;
};

Token.prototype.begin = function() {
	var ret = this.prv;
	while(!ret.bof()) ret = ret.prv;
	return ret;
};

Token.prototype.end = function() {
	var ret = this.nxt;
	while(!ret.eof()) ret = ret.nxt;
	return ret;
};

Token.prototype.debug = function() {
	"[this] text=" + this.text + " kind=" + this.kind + " prev=" + this.prv + " next=" + this.nxt;
};

//==============================================================================
function TokenHeadder(params) {
	this.b = new Token();
	this.e = new Token();
	this.esc = '\\';
	this.comment = [ {begin:'/*', end:'*/'}, {begin:'//', end:'\n'} ];
	this.b.add(this.e);
	for(var keys in params) this[keys] = params[keys];
};

TokenHeadder.prototype.begin = function() {
	return this.b.nxt;
};

TokenHeadder.prototype.end = function() {
	return this.e.prv;
};

// トークン取得
TokenHeadder.prototype.get = function(begin, end, kind) {
	if(!kind) kind = '';
	var flag = false;
	if(kind.match(/^!(.*)$/)) { flag = true; kind = RegExp.$1; }
	var re = new RegExp('/^(' + kind + ')$/');
	if(begin && end) {
		if('Object' !== getType(begin)) begin = this.get(begin).next();
		if('Object' !== getType(end)  ) end	  = this.get(end);
		var ret = [];
		for(var t = begin; !t.eof(end); t = t.next())
			if(flag ? !t.value().match(re) : t.value().match(re)) ret.push(t);
		return ret;
	}

	if(begin) {
		var ret;
		if('Number' !== getType(begin)) { ret = begin; } else {
			for(var t = this.begin(), i = 0; !t.eof(); t = t.next(), i++)
				if(i == begin) { ret = t; break; }
		}
		if(flag ? !ret.value().match(re) : ret.value().match(re)) return ret;
		return new Token();
	}

	var ret = [];
	for(var t = this.begin(); !t.eof(); t = t.next())
		if(flag ? !this.value().match(re) : this.value().match(re)) ret.push(t);
	return ret;
};

// トークン文字列取得
TokenHeadder.prototype.tokens = function(begin, end) {
	if(!begin) begin = this.begin();
	if(!end)   end	 = this.end();
	var ar = [], t = begin;
	if(t.prv.bof()) ar.push('[BOF]');
	while(!t.eof(end)) {
		if(!t.kind.match(/^(space|comment)$/)) ar.push(t.text) ;
		t = t.nxt;
	}
	if(t.eof()) ar.push('[EOF]') ;
	return ar.join(' ');
};

// トークン文字列取得２
TokenHeadder.prototype.string = function(begin, end) {
	if(!begin) begin = this.begin();
	if(!end)   end	 = this.end();
	var s = '';
	for(var t = begin; !t.eof(end); t = t.next()) {
		if(t.kind.match(/^comment$/)) continue;
		if(t.kind.match(/^space$/)) s += ' ';
		else s += t.text;
	}
	return s.replace(/\s+/mg, ' ').replace(/^ ?(.*?) ?$/, function(s, p) { return p; });
};

// トークン文字列取得
TokenHeadder.prototype.print = function(begin, end) {
	if(!begin) begin = this.begin();
	if(!end)   end	 = this.end();
	var ar = [], t = begin;
	ar.push("begin:", begin.debug(), "\n");
	ar.push("end:"	, end.debug(),	 "\n");
	try {
		if(t.prv.bof()) ar.push('[BOF]');
		while(!t.eof(end)) {
			ar.push("'" + t.value() + "'");
			t = t.nxt;
		}
		if(t.eof()) ar.push('[EOF]');
		if(t === end) ar.push('[END]');
	} catch(e) {
		return t + OpenObject(e) + OpenObject(t);
	}
	return ar.join(',').toEscape();
};

//==============================================================================
// レキシカルアナライザ
//==============================================================================
function LexicalAnalyzer(params) {
	TokenHeadder.apply(this, arguments);
//	this.prototype = new TokenHeadder(params);
	if(this.file) {
		this.debug("Read:this[file]");
		var fh = new FileHandle(this.file, F_READ);
		var code = '';
		while(!fh.eof()) code += fh.readline() + "\n";
		fh.close();
		this.code = code;
	}
	this.Analyze();
	this.setLine();

//	delete this.code;
};
LexicalAnalyzer.prototype = new TokenHeadder();

// レキシカルアナライザ本体
LexicalAnalyzer.prototype.Analyze = function() {
	if(!this.code) return;
	this.debug("Analyze");

	var qu = {string:'"', char:"'"};
	var op = ['!#$%&()*+,-./:;"\'<=>?@[\\]^`{|}' +
	'　、。・「」【】『』〔〕〈〉《》☆★※○●◎◇◆□■▽△▼▲' +
	'①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳',
	['==', '!=', '<=', '>=', '<<', '>>', '+=', '-=', '*=', '/=', '%=', '|=',
	'&=', '^=', '++', '--', '->', '=>', '=<', '::', '||', '&&', '/*','*/','//',
	'##', "\\\n"], ['<<=', '>>=', '===', '!=='] ];

	var code = this.code + "\0\0\0";
	var t = new Token();
	var state, redo;
	for(var i = 0; i < code.length; i++) {
		redo = false;
		var c = code.charAt(i);
		if(c !== "\0") t.text += c;
		if(!state) {
			if(op[0].indexOf(c) >= 0) state = 'op';	// オペレータ
			else if(c.match(/\d/)) state = 'number';		// 数字
			else if(c.match(/\s/)) state = 'space';			// スペース
			else state = 'ident';							// それ以外はident
		}
		else if(state === 'number' && !c.match(/\d/)) { t.kind = state; redo = true; }
		else if(state === 'space'  && !c.match(/\s/)) { t.kind = state; redo = true; }
		else if(state === 'ident'  && (c.match(/\s/) || op[0].indexOf(c) >= 0)) { t.kind = state; redo = true; }
		// 文字列の処理
		else if(state.match(/^(string|char)$/)) {
			if(c === qu[state]) t.kind = state;
			else if(c === this.esc) state += '_esc';
		}
		else if(state.match(/^(.+)_esc$/)) state = RegExp.$1;
		// コメントの処理
		else if('ARRAY' === getType(this.comment)) {
			for(var j in this.comment) {
				var cmt = this.comment[j];
				if(state === 'comment_' + cmt.begin && t.text.slice(-cmt.end.length) === cmt.end) { t.kind = state; break; }
			}
		}

		// オペレータの処理
		if(state === 'op') {
			if(t.text === '　') { t.text = '  ', state = 'space'; }
			var cc = '';
			for(var j in op) { j = parseInt(j);
				cc += code.charAt(i + j);
				if(j > 0) for(var k in op[j]) if(cc === op[j][k]) {
					t.text = cc[j];
					i += j;
				}
			}
			if('ARRAY' === getType(this.comment)) {
				for(var j in this.comment) {
					var cmt = this.comment[j];
					if(t.text === cmt.begin) state = 'comment_' + cmt.begin;
				}
			}
			if(state === 'op') for(var k in qu) if(t.text === qu[k]) state = k ;
			if(state === 'op') t.kind = state;
		}

		if(c.match(/^\0$/)) t.kind = state;
		if(c.match(/\012|\015/)) {
			t.kind = state.match(/^(.+?)_/) ? RegExp.$1 : state;
			t.text = t.text.slice(0, -1);
			if(t.value().match(/^space_.*\t/)) t.text = t.text.replace(/\t/gm, '    ');
			if(t.value().match(/^space_.*　/)) t.text = t.text.replace(/　/gm, '  ');
			if(t.text !== '') this.end().add(t);
			this.end().add(new Token("\n", 'space'));
			t = new Token();
			if('ARRAY' === getType(this.comment)) for(var j in this.comment) {
				var cmt = this.comment[j];
				if(state === 'comment_' + cmt.begin && cmt.end === '\n') state = undefined;
			}
			if(c.match(/\015/) && code[i+1].match(/\012/)) i++;
		} else if(t.kind) {
			if(t.kind.match(/^(.+)_/)) t.kind = RegExp.$1;
			if(redo) t.text = t.text.slice(0, -1);
			if(t.value().match(/^space_.*\t/)) t.text = t.text.replace(/\t/gm, '    ');
			if(t.value().match(/^space_.*　/)) t.text = t.text.replace(/　/gm, '  ');
			if(t.text !== '') this.end().add(t);
			t = new Token();
			state = undefined;
			if(redo) i--;
		}
		if(c.match(/^\0$/)) break;
	}
};

LexicalAnalyzer.prototype.setLine = function() {
	var line = 1, colum = 1;
	for(var t = this.begin(); !t.eof(); t = t.next()) {
		if(this.file) t.file = this.file;
		t.line = line;
		t.colum= colum;
		t.len = t.text.jpLength();
		colum += t.len;
		t.colend = colum;
		if(t.text.match(/\n/)) { colum = 1; line++; }
	}
};

LexicalAnalyzer.prototype.debug = function(msg) {
	debug(["[LexicalAnalyzer] ", msg]);
};
