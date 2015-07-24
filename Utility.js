this.br = "<BR>\n";
this.sp = "&nbsp;";
this.DEBUG = 0;

var that = this;

// Dateオブジェクトに関数を追加
Date.prototype.ToString = function() {
	return this.getFullYear() + "/"
		+ ("0"+(this.getMonth() + 1)).slice(-2) + "/"
		+ ("0"+ this.getDate()      ).slice(-2);
};
// Dateオブジェクトに関数を追加
Date.prototype.ToStringLong = function() {
	return this.ToString() + " "
		+ ("0"+ this.getHours()).slice(-2) + ":"
		+ ("0"+ this.getMinutes()).slice(-2) + ":"
		+ ("0"+ this.getSeconds()).slice(-2) + "."
		+ ("00"+this.getMilliseconds()).slice(-3)
};

String.prototype.toHTML = function() {
	return this.replace(/&/gm, '&amp;').replace(/</gm, '&lt;').
		replace(/>/gm, '&gt;').replace(/ /gm, sp).
		replace(/\t/gm, sp+sp+sp+sp).replace(/\n/gm, br);
};

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

String.prototype.toEscape = function() {
	return this.replace(/[\x00-\x1f]/gm, function(s) {
		return '\\x' + ("0" + Number(s.charCodeAt(0)).toString(16)).slice(-2);
	});
}


// ブラウザの判定
this.agent = window.navigator.userAgent.toLowerCase();
this.GetBrowser = function() {
    if((agent.match(/msie/) || agent.match(/trident/)) && agent.match(/windows/)) return true;
    return false;
};

// ファイル名取得
this.url = document.URL.replace(/\\/gm, '/');
this.GetFileName = function() {
    return url.replace(/^[^\/]+\/\/(.+\.[^\.]+)$/, function(s, p) { return p; });
};

// イベントハンドラの登録
this.AddEvent = function(element, type, func) {
    if(element.addEventListener) element.addEventListener(type, func, false);
    else if(element.attachEvent) element.attachEvent('on' + type,
            function() { func.apply(element, arguments); } );
    else element['on' + type] = func;
};

//イベントハンドラの削除
this.DelEvent = function(element, type, funcname) {
    if(element.removeEventListener) element.removeEventListener(type, funcname, false );
    else if(element.detachEvent) element.detachEvent('on' + type, funcname );
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

    AddEvent(textarea, 'focus',  function() { adjustTa(); });
    AddEvent(textarea, 'keyup',  function() { adjustTa(); });
    AddEvent(textarea, 'change', function() { adjustTa(); resetTa(); });
    AddEvent(textarea, 'blur',   function() { adjustTa(); /*resetTa();*/ });
};

//折りたたみ処理
this.FolderOperation = function(name) {
    var element = document.getElementById(name);
    if(element.className === 'close') {
        element.style.display = 'block';
        element.className     = 'open';
    } else {
        element.style.display = 'none';
        element.className     = 'close';
    }
};

// タグの取得
this.getTags = function(name) {
    var tags;
    if(document.querySelectorAll) tags = document.querySelectorAll(name);
    else if(GetBrowser()) tags = document.all.tags(name);
    else alert('getTags Not Support Browser!!');
    return tags;
};

// 型を取得
this.getType = function(obj) {
    if(undefined === obj || null === obj) return 'Null';
    var type = Object.prototype.toString.call(obj).slice(8, -1);
	if('Number' === type && !isFinite(obj)) type = 'Null';
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
 */

function OpenObject(obj) {
	var type = getType(obj);
	if(type.match(/^String$/)) {
		obj.replace(/[\x00-\x1f]/gm, function(s) {
			'\\x' + ("0" + Number(s.charCodeAt(0)).toString(16)).slice(-2);
		});
		return "'" + obj + "'";
	}
    if(type.match(/^Null$/))   return 'null';
    if(type.match(/^Date$/))   return obj.ToStringLong();
    if(type.match(/^RegExp$/)) return obj.toString();
    if(type.match(/^(Number|Boolean)$/)) return new String(obj);
    var s = '';
    for(var i in obj) {
    	if(s.length > 0) s += ',';
    	s +=  i + '=' + OpenObject(obj[i]);
    }
    return '{ ' + s + ' }';
}

// デバック用表示処理
function putObject(head, obj, color) {
    var d = new Date();
    if(!color) color = 'black';
    var ins = document.createElement('p');
    ins.style.color = color;
    ins.style.fontSize = 'x-small';
    ins.style.border   = '1px solid gray';
    ins.className = 'STDOUT';
    ins.innerHTML = '[' + d.ToStringLong() + '][' + head + ']' + OpenObject(obj);
    document.body.appendChild(ins);

};

this.error = function(e, text) { putObject('ERROR:' + text.fontcolor('red').bold(), e, 'palevioletred') };
this.trace = function(text)    { if(that.DEBUG >= 2) putObject("TRACE", text) };
this.debug = function(text)    { if(that.DEBUG >= 1) putObject("DEBUG", text) };
this.info  = function(text)    { putObject("INFO", text) };

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

