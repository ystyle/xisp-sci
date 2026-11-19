package ystyle::xisp_io

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp.core.eval.*
import ystyle::xisp_array.*
import std.collection.ArrayList
import std.collection.HashMap
import std.fs.*
import std.convert.*
import std.math.*
import std.sort.*

/**
 * CSV 能力域
 *
 * 符号统一 `cangjie::` 前缀，与 `json` / `net` / `httpd` / `array` 一致。
 *
 * **与 `xisp_json` 的分工**：本域只做 CSV 与表格文本，不做 JSON —— JSON 已有独立
 * 模块 `ystyle::xisp_json`，重复实现只会让两条解析路径的转义规则逐渐分叉。
 *
 * ## 两种用法
 *
 * | 场景 | 用法 |
 * |---|---|
 * | 小文件、要按列做统计 | `(cangjie::csv-read path)` → `HashMap<列名, 列值>` |
 * | 大文件、逐行流式处理 | `(cangjie::csv-open path)` + `csv-next` / `csv-each` + `csv-close` |
 *
 * 流式的内存占用与文件大小**无关**（按 64KB 块推进状态机）。
 */

let CSV_SYMBOLS: Array<String> = [
    "cangjie::csv-read", "cangjie::csv-parse",
    "cangjie::csv-open", "cangjie::csv-next", "cangjie::csv-each", "cangjie::csv-close",
    "cangjie::csv-write", "cangjie::csv-format"]

public func csvDomain(): LispCapability {
    SimpleCapability(
        "csv",
        CSV_SYMBOLS,
        { ctx => registerCsv(ctx) },
        // 读写宿主文件 → 触及宿主资源。这个域**不会**进 PRESET_PURE：
        // 纯环境里根本读不到文件，声明成纯只是自欺欺人。
        escapable: false,
        hostPolicy: true)
}

/** 把内部异常转成 Lisp 错误值 */
func guardedIo(action: () -> LispValue): LispValue {
    try {
        action()
    } catch (e: IllegalArgumentException) {
        LispValue.Error(XispError(ErrorType.TypeError, e.message))
    } catch (e: Exception) {
        LispValue.Error(XispError(ErrorType.IOError, e.message))
    }
}

func asStr(v: LispValue, who: String): String {
    match (v) {
        case Str(s) => s
        case _ => throw IllegalArgumentException("${who} 需要字符串，得到 ${v.toString()}")
    }
}

func asCursor(v: LispValue, who: String): CsvCursor {
    match (v) {
        case External(e) =>
            match (e) {
                case c: CsvCursor => c
                case _ => throw IllegalArgumentException("${who} 需要 csv 游标，得到外部值 ${e.typeName}")
            }
        case _ => throw IllegalArgumentException("${who} 需要 csv 游标，得到 ${v.toString()}")
    }
}

func fieldsToLisp(fields: Array<String>): LispValue {
    var r: LispValue = Nil
    var i = fields.size - 1
    while (i >= 0) {
        r = consValue(LispValue.Str(fields[i]), r)
        i--
    }
    r
}

/**
 * 列类型
 *
 * `Floats` 不是"有小数"，而是"不能表示成整数"——含缺失值（空串）的整数列也是
 * `Floats`，因为缺失要用 `NaN` 表示，而 `Int64` 装不下 `NaN`。
 */
enum ColumnKind {
    | Ints
    | Floats
    | Texts
}

func tryParseFloat(s: String): Option<Float64> {
    let t = s.trimAscii()
    if (t.size == 0) {
        return None
    }
    try {
        Some(Float64.parse(t))
    } catch (e: Exception) {
        None
    }
}

func tryParseInt(s: String): Option<Int64> {
    let t = s.trimAscii()
    if (t.size == 0) {
        return None
    }
    try {
        Some(Int64.parse(t))
    } catch (e: Exception) {
        None
    }
}

/**
 * 推断一列的类型
 *
 * - 全是整数且无空 → `Ints`
 * - 全是数字（可能有空）→ `Floats`（空位置填 `NaN`）
 * - 否则 → `Texts`
 */
func inferColumn(values: Array<String>): ColumnKind {
    var hasEmpty = false
    var allInt = true
    var allFloat = true
    for (v in values) {
        if (v.trimAscii().size == 0) {
            hasEmpty = true
            continue
        }
        if (tryParseInt(v).isNone()) {
            allInt = false
        }
        if (tryParseFloat(v).isNone()) {
            allFloat = false
        }
    }
    if (allFloat) {
        if (allInt && !hasEmpty) {
            return ColumnKind.Ints
        }
        return ColumnKind.Floats
    }
    ColumnKind.Texts
}

/**
 * 一列字符串 → Lisp 值
 *
 * 数值列变成 ndarray；文本列变成 `Str` 的列表。
 *
 * 数值列里混了空串时整列提升为 `float64`、空填 `NaN` —— 这是"缺失值不冒充 0"
 * 的唯一诚实表示，统计函数会自动跳过 `NaN`。
 */
func columnToLisp(values: Array<String>): LispValue {
    match (inferColumn(values)) {
        case ColumnKind.Ints =>
            let buf = Array<Int64>(values.size, repeat: 0)
            var i: Int64 = 0
            while (i < values.size) {
                buf[i] = match (tryParseInt(values[i])) {
                    case Some(v) => v
                    case None => 0
                }
                i++
            }
            LispValue.External(ndarrayFromInts(buf))
        case ColumnKind.Floats =>
            let buf = Array<Float64>(values.size, repeat: 0.0)
            var i: Int64 = 0
            while (i < values.size) {
                buf[i] = match (tryParseFloat(values[i])) {
                    case Some(v) => v
                    case None => Float64.getNaN()
                }
                i++
            }
            LispValue.External(ndarrayFromFloats(buf))
        case ColumnKind.Texts =>
            var result: LispValue = Nil
            var i = values.size - 1
            while (i >= 0) {
                result = consValue(LispValue.Str(values[i]), result)
                i--
            }
            result
    }
}

/**
 * 二维字符串表 → `HashMap<列名, 列值>`（首行是表头）
 *
 * 行长度与表头不一致时：缺的当空串、多的丢弃 —— 不猜测性修复，只保证不越界。
 */
func tableToLisp(table: Array<Array<String>>): HashMap<String, LispValue> {
    let out = HashMap<String, LispValue>()
    if (table.size == 0) {
        return out
    }
    let header = table[0]
    var c: Int64 = 0
    while (c < header.size) {
        let name = header[c].trimAscii()
        let col = ArrayList<String>()
        var r: Int64 = 1
        while (r < table.size) {
            let rowVals = table[r]
            if (c < rowVals.size) {
                col.add(rowVals[c])
            } else {
                col.add("")
            }
            r++
        }
        out.add(name, columnToLisp(col.toArray()))
        c++
    }
    out
}

/** 用游标把整张表读出来；`limit < 0` 表示不限行数 */
func readTableWithLimit(path: String, limit: Int64): Array<Array<String>> {
    let reader = CsvReader(path)
    let rows = ArrayList<Array<String>>()
    var n: Int64 = 0
    while (limit < 0 || n < limit) {
        match (reader.nextRow()) {
            case Some(fields) =>
                rows.add(fields)
                n++
            case None => break
        }
    }
    reader.close()
    rows.toArray()
}

func writeTextFile(path: String, text: String): Unit {
    if (exists(path)) {
        remove(path)
    }
    var f = File.create(path)
    f.write(text.toArray())
    f.close()
}

/** 一个字段编码成 CSV（需要时加引号） */
func encodeField(s: String): String {
    var needsQuote = s.indexOf(",").isSome() || s.indexOf("\"").isSome() ||
        s.indexOf("\n").isSome() || s.indexOf("\r").isSome()
    if (!needsQuote && s.size > 0) {
        needsQuote = s.toRuneArray()[0] == r' ' || s.toRuneArray()[s.size - 1] == r' '
    }
    if (!needsQuote) {
        return s
    }
    let sb = StringBuilder()
    sb.append('"')
    for (c in s.toRuneArray()) {
        if (c == r'"') {
            sb.append('"')
        }
        sb.append(c)
    }
    sb.append('"')
    sb.toString()
}

func encodeRow(fields: Array<String>): String {
    var out = ""
    var i: Int64 = 0
    while (i < fields.size) {
        if (i > 0) {
            out = out + ","
        }
        out = out + encodeField(fields[i])
        i++
    }
    out
}

/** 单元格转字符串：`NaN` 写成空（CSV 里空才是缺失） */
func cellToString(v: LispValue): String {
    match (v) {
        // **必须取 Str 的原始内容**：`LispValue.Str("x").toString()` 是带引号的 `"x"`，
        // 直接用它会让每个文本单元格都被包一层引号，写出再读回就多出一层。
        case Str(s) => s
        case Nil => ""
        case Float(f) =>
            if (f.isNaN()) {
                ""
            } else if (f.isInf()) {
                if (f > 0.0) { "inf" } else { "-inf" }
            } else {
                f.toString()
            }
        case Error(_) => ""
        case _ => v.toString()
    }
}

func columnToStrings(v: LispValue, expectedRows: Int64): Array<String> {
    let out = ArrayList<String>()
    match (v) {
        case External(e) =>
            match (e) {
                case a: NDArray =>
                    var i: Int64 = 0
                    let n = a.length()
                    while (i < n) {
                        out.add(cellToString(a.at(i)))
                        i++
                    }
                case _ => out.add(cellToString(v))
            }
        case Cons(_) =>
            var cur = v
            var go = true
            while (go) {
                match (cur) {
                    case Cons(cell) =>
                        out.add(cellToString(cell.car))
                        cur = cell.cdr
                    case _ => go = false
                }
            }
        case _ => out.add(cellToString(v))
    }
    while (out.size < expectedRows) {
        out.add("")
    }
    out.toArray()
}

/** 列顺序：显式给就用给的，否则按列名字典序（可复现） */
func columnOrder(data: HashMap<String, LispValue>, given: Option<LispValue>): Array<String> {
    match (given) {
        case Some(v) =>
            let out = ArrayList<String>()
            var cur = v
            var go = true
            while (go) {
                match (cur) {
                    case Cons(cell) =>
                        match (cell.car) {
                            case Str(s) => out.add(s)
                            case _ => ()
                        }
                        cur = cell.cdr
                    case _ => go = false
                }
            }
            out.toArray()
        case None =>
            let names = ArrayList<String>()
            for (k in data.keys()) {
                names.add(k)
            }
            sort(names)
            names.toArray()
    }
}

func formatTable(data: HashMap<String, LispValue>, order: Array<String>): String {
    if (order.size == 0) {
        return ""
    }
    var rows: Int64 = 0
    for (name in order) {
        match (data.get(name)) {
            case Some(v) =>
                let n = match (v) {
                    case External(e) => match (e) {
                        case a: NDArray => a.length()
                        case _ => Int64(0)
                    }
                    case _ => Int64(0)
                }
                if (n > rows) {
                    rows = n
                }
            case None => ()
        }
    }
    let sb = StringBuilder()
    sb.append(encodeRow(order))
    sb.append("\n")
    let cols = ArrayList<Array<String>>()
    for (name in order) {
        match (data.get(name)) {
            case Some(v) => cols.add(columnToStrings(v, rows))
            case None =>
                let empty = ArrayList<String>()
                while (empty.size < rows) {
                    empty.add("")
                }
                cols.add(empty.toArray())
        }
    }
    var r: Int64 = 0
    while (r < rows) {
        let fields = ArrayList<String>()
        for (col in cols) {
            fields.add(col[r])
        }
        sb.append(encodeRow(fields.toArray()))
        sb.append("\n")
        r++
    }
    sb.toString()
}

func asTable(v: LispValue, who: String): HashMap<String, LispValue> {
    match (v) {
        case HashMap(m) => m
        case _ => throw IllegalArgumentException(
            "${who} 需要 hashmap（列名 → 列值），得到 ${v.toString()}")
    }
}

func registerCsv(ctx: CapabilityContext): Unit {
    let env = ctx.env

    // ===== 流式 =====

    // (cangjie::csv-open path) → 游标
    env.define("cangjie::csv-open", NativeFunc({ args =>
        guardedIo({ =>
            if (args.size != 1) {
                throw IllegalArgumentException("cangjie::csv-open 需要 1 个路径参数")
            }
            LispValue.External(CsvCursor(asStr(args[0], "cangjie::csv-open")))
        })
    }))

    // (cangjie::csv-next cur) → 一行（Str 列表）或 nil（EOF）
    env.define("cangjie::csv-next", NativeFunc({ args =>
        guardedIo({ =>
            if (args.size != 1) {
                throw IllegalArgumentException("cangjie::csv-next 需要 1 个游标参数")
            }
            let cur = asCursor(args[0], "cangjie::csv-next")
            match (cur.next()) {
                case Some(fields) => fieldsToLisp(fields)
                case None => Nil
            }
        })
    }))

    // (cangjie::csv-each cur fn) → 对剩余每一行调用 fn，返回处理的行数
    env.define("cangjie::csv-each", NativeFunc({ args =>
        guardedIo({ =>
            if (args.size != 2) {
                throw IllegalArgumentException("cangjie::csv-each 需要游标与处理函数")
            }
            let cur = asCursor(args[0], "cangjie::csv-each")
            let fn = args[1]
            var n: Int64 = 0
            while (true) {
                match (cur.next()) {
                    case Some(fields) =>
                        let callArgs = ArrayList<LispValue>()
                        callArgs.add(fieldsToLisp(fields))
                        let r = ctx.invoke(fn, callArgs)
                        // 回调报错就中止，不要把错误当普通值继续遍历
                        if (let Error(_) <- r) {
                            return r
                        }
                        n++
                    case None => break
                }
            }
            LispValue.Int(n)
        })
    }))

    // (cangjie::csv-close cur)
    env.define("cangjie::csv-close", NativeFunc({ args =>
        guardedIo({ =>
            if (args.size != 1) {
                throw IllegalArgumentException("cangjie::csv-close 需要 1 个游标参数")
            }
            asCursor(args[0], "cangjie::csv-close").close()
            Nil
        })
    }))

    // ===== 一次性 =====

    // (cangjie::csv-read path [limit]) —— 首行当表头；limit 限制读入的行数（含表头）
    env.define("cangjie::csv-read", NativeFunc({ args =>
        guardedIo({ =>
            if (args.size < 1 || args.size > 2) {
                throw IllegalArgumentException("cangjie::csv-read 需要路径参数与可选的行数上限")
            }
            let path = asStr(args[0], "cangjie::csv-read")
            var limit: Int64 = -1
            if (args.size == 2) {
                limit = match (args[1]) {
                    case Int(n) => n
                    case _ => throw IllegalArgumentException("limit 必须是整数")
                }
            }
            let table = readTableWithLimit(path, limit)
            if (table.size == 0) {
                return LispValue.HashMap(HashMap<String, LispValue>())
            }
            LispValue.HashMap(tableToLisp(table))
        })
    }))

    // (cangjie::csv-parse "a,b\n1,2") —— 从字符串解析
    env.define("cangjie::csv-parse", NativeFunc({ args =>
        guardedIo({ =>
            if (args.size != 1) {
                throw IllegalArgumentException("cangjie::csv-parse 需要 1 个字符串参数")
            }
            let text = asStr(args[0], "cangjie::csv-parse")
            LispValue.HashMap(tableToLisp(parseTextTable(text)))
        })
    }))

    // ===== 写出 =====

    env.define("cangjie::csv-format", NativeFunc({ args =>
        guardedIo({ =>
            if (args.size < 1 || args.size > 2) {
                throw IllegalArgumentException("cangjie::csv-format 需要 1 或 2 个参数")
            }
            let data = asTable(args[0], "cangjie::csv-format")
            let order = columnOrder(data, if (args.size == 2) { Some(args[1]) } else { None })
            LispValue.Str(formatTable(data, order))
        })
    }))

    env.define("cangjie::csv-write", NativeFunc({ args =>
        guardedIo({ =>
            if (args.size < 2 || args.size > 3) {
                throw IllegalArgumentException("cangjie::csv-write 需要路径 + hashmap（+ 可选列序）")
            }
            let path = asStr(args[0], "cangjie::csv-write")
            let data = asTable(args[1], "cangjie::csv-write")
            let order = columnOrder(data, if (args.size == 3) { Some(args[2]) } else { None })
            writeTextFile(path, formatTable(data, order))
            Nil
        })
    }))
}

/** 从字符串解析成二维表（走内存中的 CsvReader，复用同一份状态机） */
func parseTextTable(text: String): Array<Array<String>> {
    let rows = ArrayList<Array<String>>()
    let runes = text.toRuneArray()
    let row = ArrayList<String>()
    var rowCells = ArrayList<String>()
    var field = ArrayList<UInt8>()
    var inQuotes = false
    var i: Int64 = 0
    if (runes.size > 0 && runes[0] == r'\u{FEFF}') {
        i = 1
    }
    func endField(): Unit {
        rowCells.add(String.fromUtf8(field.toArray()))
        field = ArrayList<UInt8>()
    }
    func endRow(): Unit {
        endField()
        let cells = rowCells.toArray()
        rowCells = ArrayList<String>()
        if (!(cells.size == 1 && cells[0].size == 0)) {
            rows.add(cells)
        }
    }
    while (i < runes.size) {
        let c = runes[i]
        if (inQuotes) {
            if (c == r'"') {
                if (i + 1 < runes.size && runes[i + 1] == r'"') {
                    field.add(BYTE_DQUOTE)
                    i = i + 2
                } else {
                    inQuotes = false
                    i = i + 1
                }
            } else {
                for (b in c.toString().toArray()) {
                    field.add(b)
                }
                i = i + 1
            }
            continue
        }
        if (c == r'"') {
            inQuotes = true
            i = i + 1
        } else if (c == r',') {
            endField()
            i = i + 1
        } else if (c == r'\r') {
            if (i + 1 < runes.size && runes[i + 1] == r'\n') {
                i = i + 1
            }
            endRow()
            i = i + 1
        } else if (c == r'\n') {
            endRow()
            i = i + 1
        } else {
            for (b in c.toString().toArray()) {
                field.add(b)
            }
            i = i + 1
        }
    }
    if (field.size > 0 || rowCells.size > 0) {
        endRow()
    }
    rows.toArray()
}
