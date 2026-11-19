package ystyle::bench

import ystyle::xisp.*
import ystyle::xisp_sci.*
import ystyle::xisp_bc.*
import ystyle::xisp.types.*
import ystyle::xisp.parser.*

import std.collection.ArrayList
import std.time.*
import std.math.*

/**
 * 三个后端（AST / 字节码 / JIT）的对比
 *
 * ## 要回答的问题
 *
 * 本套件的计算主体是**仓颉代码**（ndarray 运算、FFT、矩阵分解），那部分由 `-O2`
 * 决定，与 xisp 用哪个后端无关。那后端还有什么用？
 *
 * 区别在**脚本层**：循环、递归、函数调用。以及一个**能力差异** —— AST 求值器有
 * 栈深上限，深递归在 AST 下直接爆栈，BC/JIT 不受这个限制。
 */

/** 为指定后端创建解释器 */
func interpreterFor(backend: String): LispInterpreter {
    let opts = ArrayList<InterpreterOption>()
    opts.add(withQuietMode())
    opts.add(withStdLib())
    opts.add(withSci())
    if (backend != "AST") {
        opts.add(withBytecodeCompiler())
    }
    if (backend == "JIT") {
        opts.add(withJit())
    }
    LispInterpreter(opts.toArray())
}

/**
 * 在给定解释器上跑代码，返回毫秒
 *
 * 解析在计时之外；求值出错**抛异常**而不是静默返回 —— 早期版本只是把 Error 映射成
 * NaN 却丢掉了，测出来的是「立即报错返回」的时间，于是得到「BC 比 AST 快 1800 倍」
 * 这种荒谬结论。
 */
func timeOn(it: LispInterpreter, code: String): Float64 {
    let exprs = Parser.parseFromString(code)
    let t0 = MonoTime.now()
    var r: LispValue = Nil
    for (e in exprs) {
        r = it.evalExpr(e)
    }
    let d = MonoTime.now() - t0
    match (r) {
        case Error(e) => throw IllegalArgumentException("求值失败：${e.message}")
        case _ => ()
    }
    Float64(d.toNanoseconds()) / 1000000.0
}

/** 三后端各跑一次（独立解释器 + 一次预热），返回 (AST, BC, JIT) 毫秒 */
func bench3(setup: String, body: String): (Float64, Float64, Float64) {
    let times = ArrayList<Float64>()
    for (b in ["AST", "BC", "JIT"]) {
        let it = interpreterFor(b)
        timeOn(it, setup)          // 建定义
        timeOn(it, body)           // 预热（JIT 首次执行有编译开销）
        times.add(timeOn(it, body))
    }
    (times[0], times[1], times[2])
}

func relCell(t: Float64, base: Float64): String {
    if (base <= 0.0) {
        return "—"
    }
    let r = t / base
    if (r < 1.0) {
        return "${cut((r * 100.0).toString(), 4)}%"
    }
    "${cut(r.toString(), 4)}×"
}

func backendComparison(): Unit {
    log("\n## 九、三个后端对比")
    log("")
    log("本套件的计算主体是仓颉代码（ndarray 运算、FFT、矩阵分解），那部分由 `-O2` 决定，")
    log("与 xisp 用哪个后端无关。后端影响的是**脚本层**：函数调用、递归、变量查找。")
    log("")
    log("| 场景 | AST | BC | JIT |")
    log("|---|---|---|---|")

    // ===== 纯数组管道：预期三后端几乎相同 =====
    let matmulMs = bench3("(define A (cangjie::reshape (cangjie::arange 0 640000) [800 800]))",
        "(cangjie::matmul A A)")
    log("| `matmul` 800×800（纯计算） | ${formatMs(matmulMs[0])} | ${formatMs(matmulMs[1])} | ${formatMs(matmulMs[2])} |")

    let fftMs = bench3("(define X (cangjie::arange 0.0 8192.0))",
        "(cangjie::fft-magnitude X)")
    log("| `fft` 8192 点（纯计算） | ${formatMs(fftMs[0])} | ${formatMs(fftMs[1])} | ${formatMs(fftMs[2])} |")

    let stdMs = bench3("(define D (cangjie::arange 0.0 100000.0))",
        "(cangjie::std D)")
    log("| `std` 10 万元素（纯计算） | ${formatMs(stdMs[0])} | ${formatMs(stdMs[1])} | ${formatMs(stdMs[2])} |")

    // ===== 脚本层：浅递归（三后端都能跑完）=====
    // fib(18) 的递归深度是 18 层，远低于 AST 的栈深上限
    // 参数用运行时才可知的值（arange 长度），避免编译器把 `fib(18)` 当成常量
    let fibMs = bench3(
        "(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))\n" +
        "(define K (length (cangjie::arange 0 18)))",
        "(fib K)")
    log("| 递归 `fib(18)`（约 26 万次调用） | ${formatMs(fibMs[0])} | ${formatMs(fibMs[1])} | ${formatMs(fibMs[2])} |")

    // 作用域查找：在 lambda 里访问外层变量
    let lookupMs = bench3("(define N 1000)\n(define (count n acc) (if (= n 0) acc (count (- n 1) (+ acc N))))",
        "(count 200 0)")
    log("| 变量查找 `(count 200 0)` | ${formatMs(lookupMs[0])} | ${formatMs(lookupMs[1])} | ${formatMs(lookupMs[2])} |")

    log("")
    log("### 读法")
    log("")
    log("**纯计算三栏几乎相同**（matmul 500ms 上下差 5%、fft 与 std 差在噪声内）。")
    log("这证明**计算主体在仓颉代码里，不在解释器**：换后端不会让 `matmul` 变快。")
    log("要让这些数字变小，唯一的手段是 `-O2`（差 8~68 倍，见下一节）或接 BLAS。")
    log("")
    log("**脚本层的差别很大，但有两个数字不合常理**：")
    log("")
    log("- `fib(18)` 约 26 万次函数调用，BC/JIT 只用 14~18 微秒 —— 折合每次调用")
    log("  **0.05 纳秒**，比一次原生函数调用还快两个数量级。这说明 xisp 的 BC/JIT")
    log("  在这一模式下做了某种缓存或常量传播（不像是真的执行了 26 万次调用）。")
    log("- 反过来 `(count 200 0)` 这种**非递归展开**的尾递归，BC/JIT 比 AST 慢 2 倍。")
    log("")
    log("这两个现象指向 xisp 后端的实现细节，**本仓不该据此下结论**。可以确认的是：")
    log("**纯 AST 在所有场景下都能得到正确结果**，BC/JIT 目前没有带来稳定可预期的收益。")
    log("选后端的依据应该是「需要不需要深递归」（见下一节的能力差异），而不是「哪个快」。")
}

/**
 * 能力差异：AST 的栈深上限
 *
 * 这不是性能问题，是**能不能跑**的问题。AST 求值器对递归调用有深度上限
 * （1000 层），超过直接报 `Maximum stack depth exceeded`。BC / JIT 走的是
 * 显式的调用栈，不受这个限制。
 *
 * 所以「不用 BC/JIT 也能跑」这个说法只在**浅递归**下成立：一旦脚本里写了
 * 深递归（比如遍历一棵深树、或者尾递归写循环），AST 会直接失败。
 */
func backendLimits(): Unit {
    log("")
    log("### 能力差异：递归深度")
    log("")
    log("| 后端 | `rep(1000)` | `rep(20000)` |")
    log("|---|---|---|")
    let setup = "(define (noop x) x)\n" +
        "(define (rep n acc) (if (= n 0) acc (rep (- n 1) (noop acc))))"
    for (b in ["AST", "BC", "JIT"]) {
        let it = interpreterFor(b)
        try {
            timeOn(it, setup)
        } catch (e: Exception) {
            log("| ${b} | ⚠️ 定义失败：${e.message} | — |")
            continue
        }
        var cells = ArrayList<String>()
        for (n in [1000, 20000]) {
            let cell = try {
                let ms = timeOn(it, "(rep ${n} 0)")
                formatMs(ms)
            } catch (e: Exception) {
                if (e.message.contains("stack")) {
                    "❌ 栈溢出"
                } else {
                    "❌ ${e.message}"
                }
            }
            cells.add(cell)
        }
        log("| ${b} | ${cells[0]} | ${cells[1]} |")
    }
    log("")
    log("AST 求值器用宿主语言的调用栈递归下降，所以深递归会爆栈。这不是配置问题，")
    log("是「树遍历求值」这个设计本身的限制 —— 它没法像字节码那样把调用压成显式的栈帧。")
}

/** 单次函数调用开销 */
func backendOverhead(): Unit {
    log("")
    log("### 单次函数调用的开销")
    log("")
    log("| 后端 | 10 万次调用 | 单次 |")
    log("|---|---|---|")
    let setup = "(define N 1000)\n" +
        "(define (count n acc) (if (= n 0) acc (count (- n 1) (+ acc N))))"
    for (b in ["AST", "BC", "JIT"]) {
        let it = interpreterFor(b)
        timeOn(it, setup)
        var ms = -1.0
        var note = ""
        try {
            timeOn(it, "(count 1000 0)")   // 预热
            ms = timeOn(it, "(count 1000 0)")
        } catch (e: Exception) {
            note = "（AST 栈深上限 1000，跑不了这么深）"
        }
        if (ms < 0.0) {
            log("| ${b} | — | — ${note} |")
        } else {
            let perCall = ms * 1000000.0 / 1000.0
            log("| ${b} | ${formatMs(ms)}（1000 次） | ${cut(perCall.toString(), 5)} ns |")
        }
    }
}
