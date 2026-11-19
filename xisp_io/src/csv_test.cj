package ystyle::xisp_io

import ystyle::xisp.types.*
import ystyle::xisp_array.*
import std.unittest.*
import std.unittest.testmacro.*
import std.collection.ArrayList
import std.fs.*
import std.math.*

/**
 * CSV 解析与类型推断的白盒测试
 *
 * 重点在两处容易写错的地方：**引号内的换行**（这是不能"按行读文件"的原因）
 * 与**缺失值不冒充 0**（含空串的整数列必须提升成 float64 + NaN）。
 */

func expectInt(actual: Int64, want: Int64, what: String): Unit {
    if (actual != want) {
        @Fail("${what}：期望 ${want}，实际 ${actual}")
    }
}

func cells(rows: Array<Array<String>>): String {
    var out = ""
    var i: Int64 = 0
    while (i < rows.size) {
        if (i > 0) {
            out = out + "|"
        }
        var j: Int64 = 0
        while (j < rows[i].size) {
            if (j > 0) {
                out = out + ","
            }
            out = out + rows[i][j]
            j++
        }
        i++
    }
    out
}

func expectCells(text: String, want: String, what: String): Unit {
    let got = cells(parseTextTable(text))
    if (got != want) {
        @Fail("${what}：期望 `${want}`，实际 `${got}`")
    }
}

/** 造一个临时 CSV 文件，返回路径 */
func writeTempCsv(name: String, content: String): String {
    let dir = "temp-test"
    if (!exists(dir)) {
        Directory.create(dir)
    }
    let path = "${dir}/${name}"
    if (exists(path)) {
        remove(path)
    }
    var f = File.create(path)
    f.write(content.toArray())
    f.close()
    path
}

@Test
class CsvParseTest {
    @TestCase
    func testBasic() {
        println("\n=== 基本解析 ===")
        expectCells("a,b\n1,2", "a,b|1,2", "两行两列")
        expectCells("a,b,c", "a,b,c", "单行")
        // 行尾不带换行
        expectCells("a,b\n1,2\n", "a,b|1,2", "末尾换行不多出空行")
        println("✓ 基本解析")
    }

    /**
     * 引号字段里的逗号不能当分隔符
     */
    @TestCase
    func testQuotedComma() {
        println("\n=== 引号内的逗号 ===")
        expectCells("\"a,b\",c", "a,b,c", "引号内逗号是一个字段")
        expectCells("\"1,000\",x", "1,000,x", "千分位")
        println("✓ 引号内的逗号保留在字段里")
    }

    /**
     * **引号内允许换行** —— RFC 4180
     *
     * 这是"不能按行读文件"的根本原因：一个逻辑行可能跨多个物理行。
     * 状态机必须跨块保持 `inQuotes`。
     */
    @TestCase
    func testQuotedNewline() {
        println("\n=== 引号内的换行 ===")
        expectCells("a,\"x\ny\",b", "a,x\ny,b", "引号内换行")
        expectCells("\"line1\r\nline2\",z", "line1\r\nline2,z", "引号内 CRLF")
        println("✓ 引号内的换行属于字段内容")
    }

    @TestCase
    func testEscapedQuote() {
        println("\n=== 双写引号 ===")
        expectCells("\"a\"\"b\"", "a\"b", "\"\" 表示一个引号")
        expectCells("\"\"\"\"", "\"", "只有转义引号")
        println("✓ \"\" 解成一个 \"")
    }

    @TestCase
    func testLineEndings() {
        println("\n=== 行结束符 ===")
        expectCells("a,b\r\n1,2", "a,b|1,2", "CRLF")
        expectCells("a,b\r1,2", "a,b|1,2", "单独的 CR")
        expectCells("a,b\n1,2", "a,b|1,2", "LF")
        println("✓ CRLF / CR / LF 都算行结束")
    }

    @TestCase
    func testBom() {
        println("\n=== 开头 BOM ===")
        expectCells("\u{FEFF}a,b\n1,2", "a,b|1,2", "BOM 不进入第一个字段")
        println("✓ UTF-8 BOM 被忽略")
    }

    @TestCase
    func testSkipBlankLines() {
        println("\n=== 空行 ===")
        expectCells("a,b\n\n1,2\n\n", "a,b|1,2", "空行跳过")
        println("✓ 全空行跳过")
    }

    @TestCase
    func testEmptyFields() {
        println("\n=== 空字段 ===")
        expectCells("a,,c", "a,,c", "中间空字段")
        expectCells(",a", ",a", "开头空字段")
        expectCells("a,", "a,", "末尾空字段")
        println("✓ 空字段保留为 \"\"")
    }

    @TestCase
    func testChineseContent() {
        println("\n=== 中文内容 ===")
        // 按字节扫描时，UTF-8 多字节字符不能被分隔符劈开
        expectCells("姓名,金额\n张三,100", "姓名,金额|张三,100", "中文表头与内容")
        println("✓ 多字节字符完整")
    }
}

@Test
class CsvTypeInferTest {
    @TestCase
    func testIntColumn() {
        println("\n=== 整数列 ===")
        let col = columnToLisp(["1", "2", "3"])
        match (col) {
            case External(e) =>
                match (e) {
                    case a: NDArray =>
                        if (a.dtype != DType.Ints) {
                            @Fail("应推断为 int64，实际 ${a.dtype.name()}")
                        }
                        expectInt(a.length(), 3, "长度")
                    case _ => @Fail("应返回 ndarray")
                }
            case _ => @Fail("应返回 ndarray")
        }
        println("✓ 全整数 → int64 数组")
    }

    /**
     * **含空串的整数列必须提升为 float64 + NaN**
     *
     * 把空当 0 会让"缺失"和"真的是 0"混为一谈 —— 均值、求和全都跟着错。
     */
    @TestCase
    func testMissingValueBecomesNaN() {
        println("\n=== 缺失值 ===")
        let col = columnToLisp(["1", "", "3"])
        match (col) {
            case External(e) =>
                match (e) {
                    case a: NDArray =>
                        if (a.dtype != DType.Floats) {
                            @Fail("含空串应提升为 float64，实际 ${a.dtype.name()}")
                        }
                        let v1 = match (a.at(1)) { case Float(x) => x; case _ => 0.0 }
                        if (!v1.isNaN()) {
                            @Fail("缺失位置应为 NaN，实际 ${v1}")
                        }
                    case _ => @Fail("应返回 ndarray")
                }
            case _ => @Fail("应返回 ndarray")
        }
        println("✓ 含空串 → float64，空位置是 NaN 而不是 0")
    }

    @TestCase
    func testFloatColumn() {
        println("\n=== 浮点列 ===")
        let col = columnToLisp(["1.5", "2", "3.25"])
        match (col) {
            case External(e) =>
                match (e) {
                    case a: NDArray =>
                        if (a.dtype != DType.Floats) {
                            @Fail("应为 float64")
                        }
                    case _ => @Fail("应返回 ndarray")
                }
            case _ => @Fail("应返回 ndarray")
        }
        println("✓ 含小数 → float64")
    }

    @TestCase
    func testTextColumn() {
        println("\n=== 文本列 ===")
        let col = columnToLisp(["abc", "def"])
        match (col) {
            case Cons(_) =>
                var cur = col
                var n: Int64 = 0
                var go = true
                while (go) {
                    match (cur) {
                        case Cons(c) =>
                            n++
                            cur = c.cdr
                        case _ => go = false
                    }
                }
                expectInt(n, 2, "文本列表长度")
            case _ => @Fail("文本列应为列表，实际 ${col.toString()}")
        }
        println("✓ 非数字列 → Str 列表")
    }

    @TestCase
    func testTableToHashMap() {
        println("\n=== 整表转换 ===")
        let table = parseTextTable("name,score\nA,10\nB,20")
        let m = tableToLisp(table)
        match (m.get("name")) {
            case Some(v) =>
                let isList = match (v) { case Cons(_) => true; case _ => false }
                if (!isList) {
                    @Fail("name 列应为文本列表")
                }
            case None => @Fail("缺 name 列")
        }
        match (m.get("score")) {
            case Some(v) =>
                let ok = match (v) {
                    case External(e) => match (e) {
                        case a: NDArray => a.dtype == DType.Ints && a.length() == 2
                        case _ => false
                    }
                    case _ => false
                }
                if (!ok) {
                    @Fail("score 列应为长度 2 的 int64 数组")
                }
            case None => @Fail("缺 score 列")
        }
        println("✓ 表头作键，数值列是 ndarray，文本列是列表")
    }
}

@Test
class CsvStreamTest {
    /** 流式逐行读，结果要与一次性解析一致 */
    @TestCase
    func testStreamMatchesParse() {
        println("\n=== 流式与一次性一致 ===")
        let content = "a,b\n1,2\n3,4\n5,6\n"
        let path = writeTempCsv("stream1.csv", content)
        let viaParse = cells(parseTextTable(content))
        let reader = CsvReader(path)
        let rows = ArrayList<Array<String>>()
        while (true) {
            match (reader.nextRow()) {
                case Some(f) => rows.add(f)
                case None => break
            }
        }
        reader.close()
        let viaStream = cells(rows.toArray())
        if (viaParse != viaStream) {
            @Fail("流式 `${viaStream}` 与一次性 `${viaParse}` 不一致")
        }
        remove(path)
        println("✓ 两种方式结果一致")
    }

    /**
     * 引号内的换行跨"读块"也要正确
     *
     * 用远超 64KB 的字段逼出跨块：约 70KB 的引号内文本。
     */
    @TestCase
    func testQuotedNewlineAcrossBlocks() {
        println("\n=== 跨块的引号内换行 ===")
        let big = StringBuilder()
        var i: Int64 = 0
        while (i < 7000) {
            big.append("0123456789")
            i++
        }
        let longText = big.toString()   // 70KB
        let content = "a,b\n\"${longText}\",tail\n"
        let path = writeTempCsv("bigfield.csv", content)
        let reader = CsvReader(path)
        match (reader.nextRow()) {
            case Some(h) =>
                expectInt(h.size, 2, "表头列数")
            case None => @Fail("读不到表头")
        }
        match (reader.nextRow()) {
            case Some(f) =>
                expectInt(f.size, 2, "数据行列数")
                expectInt(f[0].size, 70000, "超长字段长度")
                if (f[1] != "tail") {
                    @Fail("第二个字段应为 tail，实际 `${f[1]}`")
                }
            case None => @Fail("读不到数据行")
        }
        reader.close()
        remove(path)
        println("✓ 70KB 字段跨块解析正确")
    }

    /** 逐行流式读大量行，内存占用与行数无关（这里只验正确性） */
    @TestCase
    func testManyRows() {
        println("\n=== 大量行 ===")
        let sb = StringBuilder()
        sb.append("n\n")
        var i: Int64 = 0
        while (i < 20000) {
            sb.append("${i}\n")
            i++
        }
        let path = writeTempCsv("many.csv", sb.toString())
        let reader = CsvReader(path)
        var count: Int64 = 0
        var last = ""
        while (true) {
            match (reader.nextRow()) {
                case Some(f) =>
                    count++
                    if (f.size > 0) {
                        last = f[0]
                    }
                case None => break
            }
        }
        reader.close()
        expectInt(count, 20001, "表头 + 20000 行")
        if (last != "19999") {
            @Fail("最后一行应为 19999，实际 `${last}`")
        }
        remove(path)
        println("✓ 20001 行流式读完，最后一行正确")
    }

    @TestCase
    func testCloseIsIdempotent() {
        println("\n=== 关闭幂等 ===")
        let path = writeTempCsv("close.csv", "a\n1\n")
        let reader = CsvReader(path)
        reader.close()
        reader.close()
        match (reader.nextRow()) {
            case Some(_) => @Fail("关闭后不应再返回数据")
            case None => ()
        }
        remove(path)
        println("✓ 重复 close 不报错，关闭后读到 EOF")
    }
}

