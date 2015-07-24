var TableOperation = function(tablename) {
	var tag = [], table;
	this.head = [];
	this.cols = 0;
	this.rows = 0;
	this.marge = false;

	if(getType(tablename) === 'String') table = document.getElementById(tablename);
	else {
		table = tablename;
		if(table.id) tablename = table.id;
		else if(table.className) tablename = table.className;
		else if(table.nodeName) tablename = table.nodeName;
		else tablename = '?';
	}

	var trs = table.getElementsByTagName('tr');
	this.rows = trs.length;

	try {
		// TR,TH,TDからなるテーブル要素をtag配列に格納する
		GetTableElement();
	} catch(e) {
		error(e, 'ERROR(' + tablename + ')');
	}

	// テーブルの最大列数取得
	for(var i in tag) if(this.cols < tag[i].length) this.cols = tag[i].length
	// テーブルヘッダオブジェクトの構成
	for(var i = 0; i < this.cols; i++) this.head.push({'sort':'no', 'len':0});
	for(var i in tag) {
		// 足りない部分は補完する
		if(tag[i].length < this.cols) {
			var node = tag[i][tag[i].length - 1].node;
			for(var j = tag[i].length; j < this.cols; j++) a.push({'text':'', 'node':node});
		}
		// 列の最大文字数取得
		for(var j in tag[i]) if(this.head[j].len < tag[i][j].text.length) this.head[j].len = tag[i][j].text.length
	}
	// ソート用文字列の構成
	for(var i in tag) for(var j in tag[i]) {
		var obj = tag[i][j];
		obj.sortstr = '';
		var len = this.head[j].len - obj.text.length;
		if(obj.text.match(/^\d/)) {
			for(var k = 0; k < len; k++) obj.sortstr += '0';
			obj.sortstr += obj.text;
		} else {
			obj.sortstr = obj.text;
			for(var k = 0; k < len; k++) obj.sortstr += ' ';
		}
	}

	// table,thead,tbody,tfootの要素を配列に格納して返す
	function GetTableElement() {
		for(var i in trs) {
			trs[i].RowIndex = i;
			var tds = trs[i].childNodes, a = [];
			for(var j in tds) {
				var t = tds[j];
				var node = t.nodeName;
				if(getType(node) !== 'String' || !node.match(/^(td|th)$/i)) continue;

				t.RowIndex = i;
				t.ColIndex = a.length;

				var obj = {};
				if(t.className && t.className.match(/nomarge/i)) obj.nomarge = true;
				obj.text = t.innerHTML.replace(/^\s*(.*?)\s*$/, function(s, p) { return p;} );
				obj.node = node;
				a.push(obj);
			}
			if(a.length > 0) tag.push(a);
		}
	}

	// データソート
	function SortTable(col, len, asc) {
		if(!getType(col).match(/^(Number|String)$/)) col = 0;
		if(!getType(len).match(/^(Number|String)$/)) len = 0;
		if(!getType(asc).match(/^(Number|String|Boolean)$/)) asc = true;
		col = parseInt(col); len = parseInt(len);

		tag.sort(
			function(a, b) {
				if(asc) return (SortString(a) > SortString(b)) ? 1 : -1;
				else	return (SortString(a) < SortString(b)) ? 1 : -1;
			}
		);

		// ソート用の文字列の取得
		function SortString(row) {
			var ret = '';
			for(var i = 0; i < len; i++) ret += row[col + i].sortstr;
			return ret;
		}
	}

	// 取得したtagオブジェクトの属性を初期化する
	function AttrClear() {
		for(var i in tag) for(var j in tag[i]) {
			var obj = tag[i][j];
			delete obj.hidden;
			obj.col = obj.row = 1;
		}
	}

	// テーブル結合処理
	function MargeTable() {
		for(var i = 0; i < tag.length; i++) for(var j = 0; j < tag[i].length; j++) {
			var base = tag[i][j];
			if(base.hidden || base.nomarge) continue;

			// 右側のセルがセルが無いもしくは同じ場合、そのセルをマージする。
			var jj; for(jj = j + 1; jj < tag[i].length; jj++) {
				var obj = tag[i][jj];
				if(obj.hidden || obj.nomarge || (obj.text.length > 0 && obj.text !== base.text)) break;
				obj.hidden = true;		// 対象セルを無効にする
			}
			base.col = jj - j;

			// セルの下側のセルが無いもしくは同じ場合はそのセルもマージする
			var ii; for(ii = i + 1; ii < tag.length; ii++) {
				// 対象セルがすべて対象かを確認
				var k; for(k = j; k < jj; k++) {
					var obj = tag[ii][k];
					if(obj.hidden || obj.nomarge || (obj.text.length > 0 && obj.text !== base.text)) break;
				}
				if(k < jj) break;	   // 対象セルがすべて対象ではない
			}
			if(i + 1 == ii) continue;

			// 対象セルを無効にする
			for(var y = i + 1; y < ii; y++) for(var x = j; x < jj; x++) tag[y][x].hidden = true;
			base.row = ii - i;
		}
	}

	// テーブル再構成処理
	function SetTableElement() {
		for(var i in trs) {
			if(parseInt(i) >= tag.length) continue;
			var tds = trs[i].childNodes, x = 0;
			for(var j in tds) with(tds[j]) {
				var obj = tag[i][x];
				var node = tds[j].nodeName;
				if(getType(node) !== 'String' || !node.match(/^(td|th)$/i)) continue;
				if(obj.hidden) {
					innerHTML = '';
					colSpan = 1;
					rowSpan = 1;
					hidden = true;
					style.display = 'none';
				} else {
					innerHTML = obj.text;
					colSpan = obj.col;
					rowSpan = obj.row;
					hidden = false;
					style.display = 'table-cell';
				}
				x++;
			}
		}
	}

	this.getTR = function(idx) { return trs[idx]; };
	
	// 結合のインターフェース
	this.doMarge = function() {
		AttrClear();
		try {
			MargeTable();
			SetTableElement();
		} catch(e) {
			error(e, 'doMarge(' + tablename + ')');
		}
		this.marge = true;
	}

	// 結合解除のインターフェース
	this.unMarge = function() {
		AttrClear();
		try {
			SetTableElement();
		} catch(e) {
			error(e, 'unMarge(' + tablename + ')');
		}
		this.marge = false;
	}

	// ソート処理のインターフェイス
	this.doSort = function(col, len, srt) {
		if(!getType(col).match(/^(Number|String)$/)) col = 0;
		if(!getType(len).match(/^(Number|String)$/)) len = 0;
		col = parseInt(col); len = parseInt(len);
		if(!getType(srt).match(/^(String)$/)) srt = '';

		var asc = srt.match(/^(asc|desc)$/) ? asc === 'asc' : this.head[col].sort === 'desc';
		
		for(var i in this.head) this.head[i].sort = 'no';
		try {
			SortTable(col, len, asc);
		} catch(e) {
			error(e, 'doSort(' + tablename + ')');
		}
		if(this.marge) this.doMarge(); else this.unMarge();

		this.head[col].sort = asc ? 'asc' : 'desc';
	}

	// デバック用テーブル要素表示処理
	this.DebugTable = function () {
		var tbl = document.createElement('table');
		var tbd = document.createElement('tbody');

		var tr = document.createElement('tr');
		var td = document.createElement('td');
		td.innerHTML = "/";
		tr.appendChild(td);
		for(var j in tag[0]) {
			var td = document.createElement('td');
			td.innerHTML = "" + j;
			tr.appendChild(td);
		}
		tbd.appendChild(tr);
		for(i in tag) {
			var tr = document.createElement('tr');
			var td = document.createElement('td');
			td.innerHTML = i;
			tr.appendChild(td);
			for(j in tag[i]) {
				var td = document.createElement('td');
				td.innerHTML = OpenObject(tag[i][j]);
				tr.appendChild(td);
			}
			tbd.appendChild(tr);
		}
		tbl.appendChild(tbd);

		var p = document.createElement('p');
		p.appendChild(tbl);
		document.body.appendChild(p);
	}
};
