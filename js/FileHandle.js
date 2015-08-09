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

	this.element =  document.createElement('div');

	this.sel = document.createElement('select');
	this.sel.id = this.sel.name = name + "_select";

	this.path = document.createElement('input');
	this.path.type = "text";
	this.path.id = this.path.name = name + "_path";
	this.path.size = 200;
	this.path.value = GetFileName();
	if(!filemode) this.path.value = this.path.value.replace(/\/[^\/]+$/, '');

	AddEvent(this.sel, 'change', function() {
		_super.path.value = this.value;
	});

	this.datafile = document.createElement('input');
	this.datafile.type = "hidden";
	this.datafile.id = this.datafile.name = name + "_data";
	this.datafile.value = this.data;

	this.file = document.createElement('input');
	this.file.type = "file";
	this.file.id = this.file.name = name + "_file"
	this.file.style.display = "none";

	AddEvent(this.file, 'change', function() {
		_super.path.value = this.value;
		if(!filemode) _super.path.value = _super.path.value.substr(0, _super.path.value.lastIndexOf('\\'));
	});

	this.dialog = document.createElement('input');
	this.dialog.type = "button";
	this.dialog.id = this.dialog.name = name + "_dialog";
	this.dialog.value = "選択";

	AddEvent(this.dialog, 'click', function() {
		_super.file.click();
	});

	this.del = document.createElement('input');
	this.del.type = "button";
	this.del.id = this.del.name= name + "_del"
	this.del.value = "一覧から削除";

	AddEvent(this.del, 'click', function() {
		for(var i = _super.list.length - 1; i >= 0; i--)
			if(_super.list[i] === _super.path.value)
				_super.list.splice(i, 1);
		_super.option();
	});

	this.element.appendChild(this.sel);
	this.element.appendChild(this.path);
	this.element.appendChild(this.datafile);
	this.element.appendChild(this.file);
	this.element.appendChild(this.dialog);
	this.element.appendChild(this.del);

	AddEvent(this.element, 'dragover', function(e) {
		if(!e) e = window.event;	// IE 用
		if(e.preventDefault) e.preventDefault();	// デフォルトのドラッグを無効化（ドロップ操作を許可）

		_super.element.style.backgroundColor = 'skyblue';

		return false;
	});

	AddEvent(this.element, 'dragleave', function(e) {
		if(!e) e = window.event;	// IE 用
		// デフォルトのドラッグを無効化（ドロップ操作を許可）
		if(e.stopPropagation) e.stopPropagation();
		if(e.preventDefault) e.preventDefault();

		_super.element.style.backgroundColor = '';

		return false;
	});

	AddEvent(this.element, 'drop', function(e) {
		if(!e) e = window.event;	// IE 用

		// デフォルトのドロップを無効化
		if(e.stopPropagation) e.stopPropagation();
		if(e.preventDefault) e.preventDefault();

		var files = e.dataTransfer.files;
		var files_info = "";
		for(var i=0; i<files.length; i++) {
			files_info += (i+1) + "つ目のファイル情報：" + "<b>[name]</b> "
			+ files[i].name + " <b>[size]</b> " + files[i].size + " <b>[type]</b> "
			+ files[i].type + "<br>";
		}
		info(files_info);

		return false;
	});

	
	this.base.appendChild(this.element);

	var fh = new FileHandle(this.data, F_READ);
	while(!fh.eof()) {
		var line = fh.readline().replace(/^\s*(.*?)\s*$/, function(s,p){return p}).replace(/#.*$/, '');
		if (line.length > 0) this.list.push(line);
	}
	fh.close();

	this.option();
};

CreateFileField.prototype.option = function() {
	this.sel.innerHTML = "";

	if(this.list.length > 0)
		this.path.value = this.list[0];
	for(var i in this.list) {
		var option = new Option(this.list[i], this.list[i]);
		if(i == 0) option.selected;
		option.innerHTML = this.list[i];
		this.sel.appendChild(option);
	}
	this.sel.style.width = 30;
	this.sel.selectIndex = 0;
};

CreateFileField.prototype.write = function() {
	for(var i = this.list.length - 1; i >= 0; i--)
		if(this.list[i] === this.path.value) this.list.splice(i, 1);
	this.list.unshift(this.path.value);

	this.option();

	var fh = new FileHandle(this.data, F_WRITE);
	for(var i = 0; i < this.list.length && i < 10; i++)
		fh.writeline(this.list[i]);
	fh.close();
};
