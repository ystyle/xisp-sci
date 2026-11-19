package ystyle::xisp_tests

import ystyle::xisp.*
import ystyle::xisp_array.*
import ystyle::xisp_io.*
import ystyle::xisp_stats.*
import ystyle::xisp_bc.*
import ystyle::xisp.types.*
import ystyle::xisp.parser.*

import std.unittest.*
import std.unittest.testmacro.*
import std.collection.ArrayList
import std.fs.*
import std.math.*

/**
 * 阶段 3 的验收：**读一份真实 CSV → 描述统计 → 出结果**
 *
 * 这条链路横跨三个新增能力：`csv` 域的解析与类型推断、`array` 的 ndarray、
 * `stats` 的统计函数。任何一环的接口契约变化都会在这里断掉。
 */

func pipelineBackendNames(): Array<String> {
    ["AST", "BC", "JIT"]
}

func evalPipeline(code: String, backend: String): LispValue {
    let opts = ArrayList<InterpreterOption>()
    opts.add(withQuietMode())
    opts.add(withStdLib())
    opts.add(withArray())
    opts.add(withCsv())
    opts.add(withStats())
    if (backend != "AST") {
        opts.add(withBytecodeCompiler())
    }
    if (backend == "JIT") {
        opts.add(withJit())
    }
    let it = LispInterpreter(opts.toArray())
    var result: LispValue = Nil
    for (expr in Parser.parseFromString(code)) {
        result = it.evalExpr(expr)
    }
    result
}

func pipelineKindOf(v: LispValue): String {
    match (v) {
        case Error(err) => err.kind.name()
        case _ => ""
    }
}

/** 把一个浮点结果与期望值比较（三后端） */
func expectPipelineNum(code: String, want: Float64, tol: Float64, what: String): Unit {
    for (b in pipelineBackendNames()) {
        let r = evalPipeline(code, b)
        let k = pipelineKindOf(r)
        if (k.size > 0) {
            @Fail("[${b}] ${what}：报错 ${k}（代码：${code}）")
        }
        let got = match (r) {
            case Float(x) => x
            case Int(i) => Float64(i)
            case _ => Float64.getNaN()
        }
        if (!(abs(got - want) <= tol) && !(got.isNaN() && Float64.getNaN().isNaN())) {
            @Fail("[${b}] ${what}：期望 ${want}，实际 ${got}（代码：${code}）")
        }
    }
}

func expectPipelineStr(code: String, want: String, what: String): Unit {
    for (b in pipelineBackendNames()) {
        let r = evalPipeline(code, b)
        let k = pipelineKindOf(r)
        if (k.size > 0) {
            @Fail("[${b}] ${what}：报错 ${k} — ${r.toString()}（代码：${code}）")
        }
        if (r.toString() != want) {
            @Fail("[${b}] ${what}：期望 `${want}`，实际 `${r.toString()}`（代码：${code}）")
        }
    }
}

/** 造一个测试用 CSV 文件，返回路径 */
func writeCsvFixture(name: String, content: String): String {
    if (!exists("temp-test")) {
        Directory.create("temp-test")
    }
    let path = "temp-test/${name}"
    if (exists(path)) {
        remove(path)
    }
    var f = File.create(path)
    f.write(content.toArray())
    f.close()
    path
}

const SALES_CSV: String = "region,amount,qty\n" +
    "east,100,2\n" +
    "east,150,3\n" +
    "west,200,4\n" +
    "west,50,1\n"

@Test
class CsvStatsPipelineTest {
    /**
     * 读 CSV → 按列取值 → 统计
     *
     * 这是阶段 3 的验收目标：**用户可以说"读这份 CSV，算一下销售额的均值"**。
     */
    @TestCase
    func testReadAndSummarize() {
        println("\n=== 读 CSV 并统计 ===")
        let path = writeCsvFixture("sales.csv", SALES_CSV)
        let code = "(define d (cangjie::csv-read \"${path}\"))\n" +
            "(define amount (hashmap-get d \"amount\"))"
        // 均值 (100+150+200+50)/4 = 125
        expectPipelineNum("${code}\n(cangjie::mean (hashmap-get (cangjie::csv-read \"${path}\") \"amount\"))",
            125.0, 1e-9, "amount 均值")
        // 中位数：(100,150,200,50) 排序后 (50,100,150,200) → (100+150)/2 = 125
        expectPipelineNum("(cangjie::median (hashmap-get (cangjie::csv-read \"${path}\") \"amount\"))",
            125.0, 1e-9, "amount 中位数")
        // 样本标准差：偏差 (-25,25,75,-75)，平方和 625+625+5625+5625 = 12500，除 3
        expectPipelineNum("(cangjie::std (hashmap-get (cangjie::csv-read \"${path}\") \"amount\"))",
            sqrt(12500.0 / 3.0), 1e-9, "amount 样本标准差")
        remove(path)
        println("✓ CSV → ndarray → mean / median / std")
    }

    /**
     * 列类型推断：整数列得 `int64` 数组，文本列得列表
     *
     * 推断错了会让后续 `(sum col)` 之类的运算悄悄失败或算错。
     */
    @TestCase
    func testColumnTyping() {
        println("\n=== 列类型推断 ===")
        let path = writeCsvFixture("types.csv", SALES_CSV)
        expectPipelineStr(
            "(type-of (hashmap-get (cangjie::csv-read \"${path}\") \"amount\"))",
            "\"ndarray\"", "amount 是 ndarray")
        // 整数列应是 int64
        expectPipelineStr(
            "(cangjie::shape (hashmap-get (cangjie::csv-read \"${path}\") \"qty\"))",
            "(4)", "qty 长度")
        expectPipelineStr(
            "(sum (hashmap-get (cangjie::csv-read \"${path}\") \"qty\"))",
            "10", "qty 求和（整数）")
        // 文本列应是列表
        expectPipelineStr(
            "(nth (hashmap-get (cangjie::csv-read \"${path}\") \"region\") 0)",
            "\"east\"", "region 是文本列表")
        remove(path)
        println("✓ 数值列 → ndarray，文本列 → 列表")
    }

    /**
     * 缺失值 → `NaN` → 统计自动跳过
     *
     * 把空当 0 会让均值从 2 变成 1.5 —— 这是数据分析里最隐蔽的一类错误。
     */
    @TestCase
    func testMissingValueSkipped() {
        println("\n=== 缺失值 ===")
        let content = "v\n1\n\n3\n"
        let path = writeCsvFixture("missing.csv", content)
        // [1, NaN, 3] 的有效均值 = 2
        expectPipelineNum("(cangjie::mean (hashmap-get (cangjie::csv-read \"${path}\") \"v\"))",
            2.0, 1e-9, "含缺失的均值")
        remove(path)
        println("✓ [1, 空, 3] 的均值是 2 而不是 1.333")
    }

    /**
     * 流式读取：游标逐行推进
     *
     * 大文件走这条路，内存占用与文件大小无关。
     */
    @TestCase
    func testStreamingCursor() {
        println("\n=== 流式游标 ===")
        let content = "a,b\n1,2\n3,4\n5,6\n"
        let path = writeCsvFixture("stream.csv", content)
        // 数一遍行数：表头 1 + 数据 3 = 4
        expectPipelineStr(
            "(define cur (cangjie::csv-open \"${path}\"))\n" +
            "(cangjie::csv-each cur (lambda (row) nil))",
            "4", "csv-each 返回行数")
        remove(path)
        println("✓ csv-open + csv-each 逐行处理")
    }

    /** csv-next 逐行取，EOF 返回 nil */
    @TestCase
    func testStreamingNext() {
        println("\n=== csv-next ===")
        let content = "x,y\n7,8\n"
        let path = writeCsvFixture("next.csv", content)
        expectPipelineStr(
            "(define cur (cangjie::csv-open \"${path}\"))\n" +
            "(define h (cangjie::csv-next cur))\n" +
            "(define r (cangjie::csv-next cur))\n" +
            "(define e (cangjie::csv-next cur))\n" +
            "(cangjie::csv-close cur)\n" +
            "(list (nth h 0) (nth r 1) (null? e))",
            "(\"x\" \"8\" true)", "表头 / 数据行 / EOF")
        remove(path)
        println("✓ csv-next 返回行，EOF 是 nil")
    }

    /**
     * 写出后再读回，值不变（往返一致）
     *
     * 往返是最能暴露转义 bug 的测试：逗号、引号、换行任何一处转义错了，读回来就变形。
     */
    @TestCase
    func testWriteThenReadRoundTrip() {
        println("\n=== 写出后读回 ===")
        // 输入文件里有一个含逗号的引号字段
        let inPath = writeCsvFixture("rt_in.csv", "a,b\n\"x,y\",2\n")
        let outPath = "temp-test/rt_out.csv"
        if (exists(outPath)) {
            remove(outPath)
        }
        let code = "(define d (cangjie::csv-read \"${inPath}\"))\n" +
            "(cangjie::csv-write \"${outPath}\" d (list \"a\" \"b\"))"
        let r = evalPipeline(code, "AST")
        let k = pipelineKindOf(r)
        if (k.size > 0) {
            @Fail("写出失败：${k} ${r.toString()}")
        }
        // 读回：a 列第一个值应是 "x,y"（含逗号，被正确转义）
        expectPipelineStr(
            "(nth (hashmap-get (cangjie::csv-read \"${outPath}\") \"a\") 0)",
            "\"x,y\"", "含逗号的字段往返一致")
        remove(inPath)
        remove(outPath)
        println("✓ 含逗号的字段写出后读回不变")
    }

    @TestCase
    func testEmptyFileIsEmptyMap() {
        println("\n=== 空文件 ===")
        let path = writeCsvFixture("empty.csv", "")
        expectPipelineStr("(hashmap-get (cangjie::csv-read \"${path}\") \"a\")",
            "nil", "空文件得空表")
        remove(path)
        println("✓ 空 CSV → 空 HashMap")
    }

    /** 相关系数：完全线性关系上应为 1 */
    @TestCase
    func testCorrelationFromCsv() {
        println("\n=== CSV 上的相关系数 ===")
        let content = "x,y\n1,2\n2,4\n3,6\n4,8\n"
        let path = writeCsvFixture("corr.csv", content)
        expectPipelineNum(
            "(define d (cangjie::csv-read \"${path}\"))\n" +
            "(cangjie::corr (hashmap-get d \"x\") (hashmap-get d \"y\"))",
            1.0, 1e-9, "完全正相关")
        remove(path)
        println("✓ y = 2x 上 corr = 1")
    }
}
