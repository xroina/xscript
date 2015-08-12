// �t�@�C������p�I�u�W�F�N�g(windows ie �ł̂ݗL��)
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

// �t�@�C���I��p�̃t�B�[���h�\��
var CreateFileField = function(name, data_file, filemode) {
	var _super = this;
	this.list = [];
	this.data = data_file;
	this.base = document.getElementById(name);

	this.element =  document.createElement('span');

	// �����t�B�[���h�̍쐬
	this.sel = document.createElement('select');
	this.sel.id = this.sel.name = name + "_select";
	// �����t�B�[���h���ύX���ꂽ��p�X�����̓t�B�[���h�֒l�𔽉f������
	AddEvent(this.sel, 'change', function() {
		_super.path.value = this.value.replace(/\\/gm, '/');
	});
	this.element.appendChild(this.sel);

	// �p�X�����̓t�B�[���h�̍쐬
	this.path = document.createElement('input');
	this.path.type = "text";
	this.path.id = this.path.name = name + "_path";
	this.path.size = 200;
	this.path.value = GetFileName();
	if(!filemode) this.path.value = this.path.value.replace(/\/[^\/]+$/, '');
	this.element.appendChild(this.path);

	// �p�X�I���_�C�A���O�p�t�@�C�����̓t�B�[���h�̍쐬(��\��)
	this.file = document.createElement('input');
	this.file.type = "file";
	this.file.id = this.file.name = name + "_file"
	this.file.style.display = "none";
	// �t�@�C�������ύX���ꂽ��p�X�����̓t�B�[���h�֒l�𔽉f������
	AddEvent(this.file, 'change', function() {
		var path = this.value.replace(/\\/gm, '/');
		if(!filemode) path = path.value.substr(0, path.lastIndexOf('/'));
		_super.path.value = path;
	});
	this.element.appendChild(this.file);

	// �p�X�I���_�C�A���O�\���p�{�^���̍쐬
	this.dialog = document.createElement('input');
	this.dialog.type = "button";
	this.dialog.id = this.dialog.name = name + "_dialog";
	this.dialog.value = "�I��";
	// �{�^���������ꂽ��A�p�X�I���_�C�A���O�p�t�@�C�����̓t�B�[���h�̃N���b�N�����������Ƃɂ���B
	AddEvent(this.dialog, 'click', function() {
		_super.file.click();
	});
	this.element.appendChild(this.dialog);

	// �����t�B�[���h�폜�{�^���̍쐬
	this.del = document.createElement('input');
	this.del.type = "button";
	this.del.id = this.del.name= name + "_del"
	this.del.value = "�ꗗ����폜";
	// �{�^���������ꂽ��A�������X�g����Ώۂ��폜���A�������ĕ\������B
	AddEvent(this.del, 'click', function() {
		for(var i = _super.list.length - 1; i >= 0; i--)
			if(_super.list[i] === _super.path.value)
				_super.list.splice(i, 1);
		_super.option();
	});
	this.element.appendChild(this.del);

	// �h���b�O���ɓ��Y�G�������g�֐N��
	AddEvent(this.element, 'dragover', function(event) {
		if(!event) event = window.event;	// IE �p
		// �f�t�H���g�̃h���b�O�𖳌����i�h���b�v��������j
		if(event.stopPropagation) event.stopPropagation();
		if(event.preventDefault) event.preventDefault();

		_super.element.style.backgroundColor = 'skyblue';

		return false;
	});

	// �h���b�O���ɓ��Y�G�������g���痣�E
	AddEvent(this.element, 'dragleave', function(event) {
		if(!event) event = window.event;	// IE �p
		// �f�t�H���g�̃h���b�O�𖳌����i�h���b�v��������j
		if(event.stopPropagation) event.stopPropagation();
		if(event.preventDefault)  event.preventDefault();

		_super.element.style.backgroundColor = '';

		return false;
	});

	// �h���b�v���ꂽ
	AddEvent(this.element, 'drop', function(event) {
		if(!event) event = window.event;	// IE �p
		// �f�t�H���g�̃h���b�v�𖳌���
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

	// �t�@�C�����痚�������擾����B
	var fh = new FileHandle(this.data, F_READ);
	while(!fh.eof()) {
		var line = fh.readline().replace(/^\s*(.*?)\s*$/, function(s,p){return p}).replace(/#.*$/, '');
		if (line.length > 0) this.list.push(line);
	}
	fh.close();

	// �������̍\��
	this.option();
};

// �I�u�W�F�N�g�̗������X�g���痚���t�B�[���h�̃I�v�V�������쐬����B
CreateFileField.prototype.option = function() {
	this.sel.innerHTML = "";
	// ���X�g������ꍇ�́A���̐擪�v�f���p�X�����̓t�B�[���h�ɔ��f����
	if(this.list.length > 0) this.path.value = this.list[0].replace(/\\/gm, '/');
	// ���X�g�̐������[�v���āA�I�v�V�����̈���쐬����B
	for(var i in this.list) {
		var option = new Option(this.list[i], this.list[i]);
		if(i == 0) option.selected;		// �擪�̃I�v�V������I���������Ƃɂ���
		option.innerHTML = this.list[i];
		this.sel.appendChild(option);
	}
	this.sel.style.width = '20pt';
	this.sel.selectIndex = 0;
};

// �I�u�W�F�N�g�̗������X�g�̏��10���̃t�@�C���ɕۑ�����B
CreateFileField.prototype.write = function() {
	// ���X�g�Ƀp�X�����̓t�B�[���h���܂܂��ꍇ�͂������U�����B
	for(var i = this.list.length - 1; i >= 0; i--)
		if(this.list[i] === this.path.value) this.list.splice(i, 1);
	// ���X�g�̐擪�Ƀp�X�����̓t�B�[���h�̒l�𑫂��B
	this.list.unshift(this.path.value);
	this.option();

	var fh = new FileHandle(this.data, F_WRITE);
	for(var i = 0; i < this.list.length && i < 10; i++)
		fh.writeline(this.list[i]);
	fh.close();
};
