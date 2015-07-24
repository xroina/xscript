// ファイル操作用オブジェクト(windows ie でのみ有効)
var F_READ   = 1;
var F_WRITE  = 2;
var F_APPEND = 8;

var FileHandle = function(file, flag) {   // flag 1:read 2:write 8:append
    var fs, fh;
    var buf = [];
    
    if(GetBrowser()) {
        try {
            fs = new ActiveXObject("Scripting.FileSystemObject");
            fh = fs.OpenTextFile(file, flag, true);
        } catch(e) {
             error(e, file + ' file open error flag=' + flag);
        }
    }
    this.readline = function() {
        try {
            if(fh) return fh.ReadLine();
        } catch(e) {
             error(e, file + ' file read error flag=' + flag);
        }
        return '';
    }
    this.writeline = function(str) {
        buf.push(str);
        try {
            if(fh) return fh.WriteLine(str);
        } catch(e) {
             error(e, file + ' file read error flag=' + flag);
        }
    }
    this.eof = function() {
        if(fh) return fh.AtEndOfStream;
        return false;
    }
    this.close = function() {
        if(fh) fh.Close();
        fh = null;
        fs = null;
    }
    this.getBuffer = function() {
        buf.join("\n");
    }
};

var CreateFileField = function(name, data_file, filemode) {
	var list = [];
	var that = this;
	this.element = document.getElementById(name);

	this.sel = document.createElement('select');
	this.sel.id = this.sel.name = name + "_select";

	this.path = document.createElement('input');
	this.path.type = "text";
	this.path.id = this.path.name = name + "_path";
	this.path.size = 200;
	var f = GetFileName();
	if(!filemode) f = f.replace(/\/[^\/]+$/, '');
	this.path.value = f;

	this.sel.onchange = function() {
		that.path.value = this.value;
	};

	this.datafile = document.createElement('input');
	this.datafile.type = "hidden";
	this.datafile.id = this.datafile.name = name + "_data";
	this.datafile.value = data_file;

	this.file = document.createElement('input');
	this.file.type = "file";
	this.file.id = this.file.name = name + "_file"
	this.file.style.display = "none";
	this.file.onchange = function() {
		var f = this.value;
		if(!filemode) f = f.substr(0, f.lastIndexOf("\\"));
		that.path.value = f;
	};

	this.dialog = document.createElement('input');
	this.dialog.type = "button";
	this.dialog.id = this.dialog.name = name + "_dialog";
	this.dialog.value = "選択";
	this.dialog.onclick = function() {
		that.file.click();
	};

	this.del =  document.createElement('input');
	this.del.type = "button";
	this.del.id = this.del.name= name + "_del"
	this.del.value = "一覧から削除";
	this.del.onclick = function() {
		for(var i = list.length - 1; i >= 0; i--) if(list[i] === that.path.value) list.splice(i, 1);
		that.option();
	};

	this.element.appendChild(this.sel);
	this.element.appendChild(this.path);
	this.element.appendChild(this.datafile);
	this.element.appendChild(this.file);
	this.element.appendChild(this.dialog);
	this.element.appendChild(this.del);

	var fh = new FileHandle(data_file, F_READ);
	while(!fh.eof()) {
		var line = fh.readline().replace(/^\s*(.*?)\s*$/, function(s,p){return p}).replace(/#.*$/, '');
		if (line.length > 0) list.push(line);
	}
	fh.close();

	this.option = function() {
		that.sel.innerHTML = "";

		if(list.length > 0) {
			that.path.value = list[0];
			for(var i in list) {
				var option = new Option(list[i], list[i]);
				if(i == 0) option.selected;
				option.innerHTML = list[i];
				that.sel.appendChild(option);
			}
			that.sel.style.width = 30;
		}
		that.sel.selectIndex = 0;
	}

	this.option();
	
	this.write = function() {
		for(var i = list.length - 1; i >= 0; i--) if(list[i] === that.path.value) list.splice(i, 1);
		list.unshift(that.path.value);

		that.option();
		var fh = new FileHandle(data_file, F_WRITE);
		for(var i = 0; i < list.length && i < 10; i++)
			fh.writeline(list[i]);
		fh.close();
	}
	
}
