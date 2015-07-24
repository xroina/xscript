var MSExcel12_OLE_Driver  = 'Provider=Microsoft.ACE.OLEDB.12.0; Extended Properties="Excel 12.0 XML;HDR=NO;IMEX=1"; Data Source=${file};';
var MSExcel_8_OLE_Driver  = 'Provider=Microsoft.Jet.OLEDB.4.0; Extended Properties="Excel 8.0;HDR=NO;IMEX=1"; Data Source=${file};';
var MSExcel12_ODBC_Driver = 'Driver={Microsoft Excel Driver (*.xls, *.xlsx, *.xlsm, *.xlsb)}; DBQ=${file}; ReadOnly=${readonly};';
var MSExcel_8_ODBC_Driver = 'Driver={Microsoft Excel Driver (*.xls)}; DBQ=${file}; ReadOnly=${readonly};';

var Connection = function(drivar, param) {

	var rs = null;			// RecordSetオブジェクト
	var cn = null;			// Connectionオブジェクト
	var alias = {};			// フィールド別名ハッシュ
	var saila = {};			// 逆引きフィールド別名ハッシュ
	var sel = null;			// Selectしているテーブル

	this.table  = [];		// Table一覧プロパティ
	this.exists = false;	// 接続しているかを示すフラグプロパティ

	this.select = function(sql) {
		sql = "SELECT " + sql + ";"; debug(sql);
		if(sql.match(/FROM \[([^\$]+\$)/i)) sel = RegExp.$1; // '
		try { rs = cn.Execute(sql) } catch(e) { error(e, sql); this.close(); }
	}
	this.insert = function(sql) {
		sql = "INSERT " + sql + ";"; debug(sql);
		try { cn.Execute(sql) } catch(e) { error(e, sql); this.close(); }
	}
	this.update = function(sql) {
		sql = "UPDATE " + sql + ";"; debug(sql);
		try { cn.Execute(sql) } catch(e) { error(e, sql); this.close(); }
	}
	this.eof    = function()  { return rs == null || rs.Eof; }
	this.name   = function(i) { try{ return getType(i) === "Number" ? rs.Fields(i).Name  : rs.Fields(alias[sel][i]).Name;  } catch(e) { error(e, "name error:" + sel + ":" + i + (getType(i) === "Number" ? '' : '->' + alias[sel][i])); } }
	this.item   = function(i) { try{ return getType(i) === "Number" ? rs.Fields(i).Value : rs.Fields(alias[sel][i]).Value; } catch(e) { error(e, "item error:" + sel + ":" + i + (getType(i) === "Number" ? '' : '->' + alias[sel][i])); } }
	this.set    = function(i, v) { try{ if(getType(i) === "Number") rs.Fields(i).Value = v; else rs.Fields(alias[sel][i]).Value = v; } catch(e) { error(e, "set error:" + sel + ":" + i + (getType(i) === "Number" ? '' : '->' + alias[sel][i])) + " := " + v; } }
	this.count  = function()  { try{ return rs.Fields.Count; } catch(e) { error(e, "rs.Fields.Count fail"); } }
	this.next   = function()  { try{ rs.MoveNext(); } catch(e) { error(e, "rs.MoveNext fail"); } }
	this.regist = function()  { try{ rs.Update();   } catch(e) { error(e, "rs.Update fail");   } }
	this.close  = function()  { if(rs != null) rs.Close(); rs = null; sel = null; }
	this.final  = function()  { this.close(); if(cn != null) cn.Close(); cn = null; this.exists = false; debug('[disconnect]'.bold()); }
	this.row    = function(table, name) {
		if(table in alias && name in alias[table]) return "[" + alias[table][name] + "]";
		error({}, "row name is undef " + table + " " + name);
		var s = []; for(var i in alias[table]) s.push(i + "=" + alias[table][i]); debug(s.join(", "));
	}
	this.names  = function(table) {
		if(!table) table = sel;
		var ret = [];
		for(var i in alias[table]) {
			var n = alias[table][i];
			if(!(n in ret)) ret[n] = [];
			ret[n].push(i);
		}
		return ret;
	}
	this.alias = function(table) {
		if(!table) table = sel;
		return saila[table];
	}

	// 接続文字列構成
	var drv = drivar.replace(/\$\{([^\}]+)\}/g, function(s,p){return param[p]});
	debug('[connect]'.bold() + drv);

	// 接続
	try{
		cn = new ActiveXObject("ADODB.connection");
		if(param.readonly) cn.Mode = 1;
		cn.Open(drv);
	} catch(e) {
		error(e, drv);
		return;
	}
	this.exists = true;

	// テーブル一覧取得
	var ct = new ActiveXObject("ADOX.Catalog");
	ct.ActiveConnection = cn;
	var e = new Enumerator(ct.Tables);
	for(e.moveFirst(); !e.atEnd(); e.moveNext()) {
		var t = e.item().name, p = [], r = {};
		if(!t.match(/^('?)(.+\$)\1$/)) continue; // '
		t = RegExp.$2;

		// ROW項目名の取得
		this.select("TOP 1 * FROM [" + t + "]");
		if(this.eof()) { this.close(); continue; }	// １件もなければ登録しない
		this.table.push(t);	// Table名の登録

		// Aliasの定義(A-Z,AA-ZZとかRC方式でアクセスしたい)
		for(var i = 0; i < this.count(); i++) {
			var name = this.name(i);
			// HDR=NOなら Fnnとかいうフィールド名なのでnn部を元にA-Z,AA-ZZを取得する
			var no = name.match(/^F(\d+)$/) ? parseInt(RegExp.$1) : -1;
			if(no < 0) for(var j = i - 1, k = 1; j >= 0; j--, k++) {
				if(!this.name(j).match(/^F(\d+)$/)) continue;
				no = parseInt(RegExp.$1) + k
				break;
			}
			if(no < 0) for(var j = i + 1, k = 1; j < this.count(); j++, k++) {
				if(!this.name(j).match(/^F(\d+)$/)) continue;
				no = parseInt(RegExp.$1) - k
				break;
			}
			if(drivar.match(/HDR=NO;/)) no--;
			var az = NoToAtoZ(no), rc = 'R' + (no + 1);
			r[name] = r[az] = r[rc] = name;
			p[i] = [name, az, rc];
		}
		this.close();
		
		alias[t] = r;
		saila[t] = p;
	}
	ct = null;
	e = null;
	
	function NoToAtoZ(no) {
		var A = "A".charCodeAt(0), Z = "Z".charCodeAt(0) - A + 1;
		var ZZ = Z - 1;
		var m = no - Z;
		return re = Z > no ? String.fromCharCode(A + no) : String.fromCharCode(A + m / ZZ, A + m % ZZ);
	}
};

