var br = "<BR>\n";
var sp = "&nbsp;";
var DEBUG = 0;

// Dateオブジェクトに関数を追加
// "YYYY/MM/DD"形式の文字列を取得
Date.prototype.ToString = function() {
	return this.getFullYear() + '/'
		+ ('0' + (this.getMonth() + 1)).slice(-2) + '/'
		+ ('0' + this.getDate()).slice(-2);
};

// "YYYY/MM/DD hh:mm:ss.nnn"形式の文字列を取得
Date.prototype.ToStringLong = function() {
	return this.ToString() + ' '
		+ ('0' + this.getHours()).slice(-2) + ":"
		+ ('0' + this.getMinutes()).slice(-2) + ":"
		+ ('0' + this.getSeconds()).slice(-2) + "."
		+ ('00' + this.getMilliseconds()).slice(-3)
};

// Stringオブジェクトに関数を追加
// コントロールコードをエスケープシーケンスに変換
String.prototype.toEscape = function() {
	return this.replace(/\\/gm, '\\\\').replace(/"/gm, '\\"')	//'
		.replace(/[\x00-\x1f]/gm, function(s) {
			var c = new Number(s.charCodeAt(0));
			if(c = 0x0a) return '\\n';
			if(c = 0x09) return '\\t';
			return '\\x' + ("0" + c.toString(16)).slice(-2);
		}
	);
}

// HTMLで出力できない文字列を&xx;形式に変換する
String.prototype.toHTML = function() {
	return this.replace(/&/gm, '&amp;').replace(/</gm, '&lt;').
		replace(/>/gm, '&gt;').replace(/ /gm, sp).
		replace(/\t/gm, sp+sp+sp+sp).replace(/\n/gm, br);
};

// 全角を2文字、半角を1文字として文字列長を取得
String.prototype.jpLength = function() {
	var len = 0;
	for(var i = 0; i < this.length; i++) {
		len++;
		if(!this.charAt(i).match(/[\x00-\x7f]/)) len++;
	}
	return len;
};

// 全角文字列を半角字列に変換する
String.prototype.toOneByte = function() {
	return this.replace(/[\uff01-\uff5e]/g, function(s) {
		return String.fromCharCode(s.charCodeAt(0) - 0xFEE0);
	});
};
 
// 半角英字列を全角文字列に変換する
String.prototype.toTwoByte = function() {
	return this.replace(/[\x21-\x7e]/g, function(s) {
		return String.fromCharCode(s.charCodeAt(0) + 0xFEE0);
	});
};

// ブラウザの判定
var agent = window.navigator.userAgent.toLowerCase();
function GetBrowser() {
	if((agent.match(/msie/) || agent.match(/trident/)) && agent.match(/windows/)) return true;
	return false;
};

// ファイル名取得
var url = document.URL.replace(/\\/gm, '/');
function GetFileName() {
	var file = url.replace(/^[^\/]+\/\/(.+)$/, function(s, p) { return p; });
	return file;
};

// イベントハンドラの登録
function AddEvent(element, type, func) {
	if(element.addEventListener) element.addEventListener(type, func, false);
	else if(element.attachEvent) element.attachEvent('on' + type, function() { func.apply(element, arguments); } );
	else element['on' + type] = func;
};

//イベントハンドラの削除
function DelEvent(element, type, funcname) {
	if(element.removeEventListener) element.removeEventListener(type, funcname, false );
	else if(element.detachEvent)    element.detachEvent('on' + type, funcname );
	else element['on' + type] = null;
};

//テキストエリアのリサイズ関数
this.TextareaAdjuster = function(textarea) {
	textarea.style.overflow = 'hidden';
	var defaultHeight = textarea.offsetHeight;

	function adjustTa() {
		textarea.style.height = defaultHeight + 'px';
		var tmp_sh = textarea.scrollHeight;
		while(tmp_sh > textarea.scrollHeight) {
			tmp_sh = textarea.scrollHeight;
			textarea.scrollHeight++;
		}
		if(textarea.scrollHeight > textarea.offsetHeight) {
			textarea.style.height = textarea.scrollHeight + 'px';
		}
	}
	function resetTa(){
		textarea.scrollTop = 0;
		textarea.style.height = defaultHeight + 'px';
	}

	AddEvent(textarea, 'focus',	 function() { adjustTa(); });
	AddEvent(textarea, 'keyup',	 function() { adjustTa(); });
	AddEvent(textarea, 'change', function() { adjustTa(); resetTa(); });
	AddEvent(textarea, 'blur',	 function() { adjustTa(); /*resetTa();*/ });
};

//折りたたみ処理
function FolderOperation(name) {
	var element = document.getElementById(name);
	if(element.className === 'close') {
		element.style.display = 'block';
		element.className	  = 'open';
	} else {
		element.style.display = 'none';
		element.className	  = 'close';
	}
};

// タグの取得
function getTags(name) {
	var tags;
	if(document.querySelectorAll) tags = document.querySelectorAll(name);
	else if(GetBrowser()) tags = document.all.tags(name);
	else alert('getTags Not Support Browser!!');
	return tags;
};

// 型を取得
function getType(obj) {
	var type = 'Unknown';
	try {
		if(undefined === obj || null === obj) return 'Null';
		type = Object.prototype.toString.call(obj).slice(8, -1);
		if('Number' === type && !isFinite(obj)) type = 'Null';
	} catch(e) {}
	return type;
};
/*
	Null
	String
	Number
	Boolean
	Date
	Error
	Array
	Function
	RegExp
	Object
	Unknown
*/

var OpenObjectMax = 3;
function OpenObject(obj, count) {
	if(count) count++; else count = 1;
	if(count > OpenObjectMax) return 'OverRange:"' + (new String(obj)).toEscape().toHTML() + '"';

	var type = getType(obj);
	if(type.match(/^(String|Number|Boolean|RegExp|Function)$/))
		return '"' + (new String(obj)).toEscape().toHTML() + '"';
	if(type.match(/^(Null|Unknown)$/)) return type;
	if(type.match(/^Date$/)) return obj.ToStringLong();

	var ary = [];
	for(var i in obj) {
		var o = obj[i];
		var str = i + ':';
		try {
			str += OpenObject(o, count);
		} catch(e) {
			str += '[' + getType(o) + ']' + o;
		}
		ary.push(str);
	}
	return '{' + ary.join(',') + '}';
}

// デバック用表示処理
function putObject(head, obj, color) {
	var ins = document.createElement('p');
	if(color) ins.style.color = color;
	ins.style.fontSize = 'x-small';
	ins.style.border   = '1px solid gray';
	ins.className = 'STDOUT';
	ins.innerHTML = '[' + (new Date()).ToStringLong() + '][' + head + ']' + OpenObject(obj);
	document.body.appendChild(ins);
};

// デバック表示領域のクリア
function clearMessage() {
	var tags = getTags('p');
	for(var i = tags.length; i > 0; i--) {
		var tag = tags[i-1];
		if(!tag.className) continue;
		if(!tag.className.match(/STDOUT/)) continue;
		tag.innerHTML = '';
		if(tag.revoveElement) tag.revoveElement();
		else if(tag.removeNode) tag.removeNode();
	}
};

this.error = function(e, text) { putObject('ERROR:' + text.fontcolor('red').bold(), e, 'palevioletred') };
this.trace = function(text)	   { if(DEBUG >= 2) putObject("TRACE", text) };
this.debug = function(text)	   { if(DEBUG >= 1) putObject("DEBUG", text) };
this.info  = function(text)	   { putObject("INFO", text) };
