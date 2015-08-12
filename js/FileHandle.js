// ファイル操作用オブジェクト(windows ie でのみ有効)
var F_READ   = 1, F_WRITE  = 2, F_APPEND = 8;

var FileHandle = function(file, flag) {	  // flag 1:read 2:write 8:append
	this.fs;
	this.fh;
	this.buf = [];
	this.file = file;
	this.flag = flag;
	
	if(GetBrowser()) {
		try {
			this.fs = new ActiveXObject("Scripting.FileSystemObject");
			this.fh = this.fs.OpenTextFile(this.file, this.flag, true);
		} catch(e) {
			 error(e, this.file + ' file open error flag=' + this.flag);
		}
	}
};

FileHandle.prototype.readline = function() {
	try {
		if(this.fh) return this.fh.ReadLine();
	} catch(e) {
		 error(e, this.file + ' file read error flag=' + this.flag);
	}
	return '';
};

FileHandle.prototype.writeline = function(str) {
	this.buf.push(str);
	try {
		if(this.fh) return this.fh.WriteLine(str);
	} catch(e) {
		 error(e, this.file + ' file read error flag=' + this.flag);
	}
};

FileHandle.prototype.eof = function() {
	if(this.fh) return this.fh.AtEndOfStream;
	return false;
};

FileHandle.prototype.close = function() {
	if(this.fh) this.fh.Close();
	this.fh = null;
	this.fs = null;
};

FileHandle.prototype.getBuffer = function() {
	this.buf.join("\n");
};

// ファイル選択用のフィールド表示
var CreateFileField = function(name, data_file, filemode) {
	var _super = this;
	this.list = [];
	this.data = data_file;
	this.base = document.getElementById(name);

	this.element =  document.createElement('span');

	// 履歴フィールドの作成
	this.sel = document.createElement('select');
	this.sel.id = this.sel.name = name + "_select";
	// 履歴フィールドが変更されたらパス名入力フィールドへ値を反映させる
	AddEvent(this.sel, 'change', function() {
		_super.path.value = this.value.replace(/\\/gm, '/');
	});
	this.element.appendChild(this.sel);

	// パス名入力フィールドの作成
	this.path = document.createElement('input');
	this.path.type = "text";
	this.path.id = this.path.name = name + "_path";
	this.path.size = 200;
	this.path.value = GetFileName();
	if(!filemode) this.path.value = this.path.value.replace(/\/[^\/]+$/, '');
	this.element.appendChild(this.path);

	// パス選択ダイアログ用ファイル入力フィールドの作成(非表示)
	this.file = document.createElement('input');
	this.file.type = "file";
	this.file.id = this.file.name = name + "_file"
	this.file.style.display = "none";
	// ファイル名が変更されたらパス名入力フィールドへ値を反映させる
	AddEvent(this.file, 'change', function() {
		var path = this.value.replace(/\\/gm, '/');
		if(!filemode) path = path.value.substr(0, path.lastIndexOf('/'));
		_super.path.value = path;
	});
	this.element.appendChild(this.file);

	// パス選択ダイアログ表示用ボタンの作成
	this.dialog = document.createElement('input');
	this.dialog.type = "button";
	this.dialog.id = this.dialog.name = name + "_dialog";
	this.dialog.value = "選択";
	// ボタンが押されたら、パス選択ダイアログ用ファイル入力フィールドのクリックを押したことにする。
	AddEvent(this.dialog, 'click', function() {
		_super.file.click();
	});
	this.element.appendChild(this.dialog);

	// 履歴フィールド削除ボタンの作成
	this.del = document.createElement('input');
	this.del.type = "button";
	this.del.id = this.del.name= name + "_del"
	this.del.value = "一覧から削除";
	// ボタンが押されたら、履歴リストから対象を削除し、履歴を再表示する。
	AddEvent(this.del, 'click', function() {
		for(var i = _super.list.length - 1; i >= 0; i--)
			if(_super.list[i] === _super.path.value)
				_super.list.splice(i, 1);
		_super.option();
	});
	this.element.appendChild(this.del);

	// ドラッグ中に当該エレメントへ侵入
	AddEvent(this.element, 'dragover', function(event) {
		if(!event) event = window.event;	// IE 用
		// デフォルトのドラッグを無効化（ドロップ操作を許可）
		if(event.stopPropagation) event.stopPropagation();
		if(event.preventDefault) event.preventDefault();

		_super.element.style.backgroundColor = 'skyblue';

		return false;
	});

	// ドラッグ中に当該エレメントから離脱
	AddEvent(this.element, 'dragleave', function(event) {
		if(!event) event = window.event;	// IE 用
		// デフォルトのドラッグを無効化（ドロップ操作を許可）
		if(event.stopPropagation) event.stopPropagation();
		if(event.preventDefault)  event.preventDefault();

		_super.element.style.backgroundColor = '';

		return false;
	});

	// ドロップされた
	AddEvent(this.element, 'drop', function(event) {
		if(!event) event = window.event;	// IE 用
		// デフォルトのドロップを無効化
		if(event.stopPropagation) event.stopPropagation();
		if(event.preventDefault)  event.preventDefault();

		putObject('Drop.dataTransfer', event.dataTransfer);

		if(event.dataTransfer.files && event.dataTransfer.files.length > 0) {
			putObject('files[0].slice', event.dataTransfer.files[0].slice());
			_super.path.value = event.dataTransfer.files[0].name;
		}

		return false;
	});

	this.base.appendChild(this.element);

	// ファイルから履歴情報を取得する。
	var fh = new FileHandle(this.data, F_READ);
	while(!fh.eof()) {
		var line = fh.readline().replace(/^\s*(.*?)\s*$/, function(s,p){return p}).replace(/#.*$/, '');
		if (line.length > 0) this.list.push(line);
	}
	fh.close();

	// 履歴情報の構成
	this.option();
};

// オブジェクトの履歴リストから履歴フィールドのオプションを作成する。
CreateFileField.prototype.option = function() {
	this.sel.innerHTML = "";
	// リストがある場合は、その先頭要素をパス名入力フィールドに反映する
	if(this.list.length > 0) this.path.value = this.list[0].replace(/\\/gm, '/');
	// リストの数分ループして、オプション領域を作成する。
	for(var i in this.list) {
		var option = new Option(this.list[i], this.list[i]);
		if(i == 0) option.selected;		// 先頭のオプションを選択したことにする
		option.innerHTML = this.list[i];
		this.sel.appendChild(option);
	}
	this.sel.style.width = '20pt';
	this.sel.selectIndex = 0;
};

// オブジェクトの履歴リストの上位10件のファイルに保存する。
CreateFileField.prototype.write = function() {
	// リストにパス名入力フィールドが含まれる場合はそれを一旦消す。
	for(var i = this.list.length - 1; i >= 0; i--)
		if(this.list[i] === this.path.value) this.list.splice(i, 1);
	// リストの先頭にパス名入力フィールドの値を足す。
	this.list.unshift(this.path.value);
	this.option();

	var fh = new FileHandle(this.data, F_WRITE);
	for(var i = 0; i < this.list.length && i < 10; i++)
		fh.writeline(this.list[i]);
	fh.close();
};
