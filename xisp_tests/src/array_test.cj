package ystyle::xisp_tests

import ystyle::xisp.*
import ystyle::xisp_array.*
// `BuiltinFunctions.presetFull()` 用于检查域名不与 core 预置域撞车
import ystyle::xisp.core.builtin.*

import std.unittest.*
import std.unittest.testmacro.*

/**
 * 数组能力域（`array`）的契约测试
 *
 * 当前 `xisp_array` 只有域声明、没有符号。这组用例钉的是**结构与接缝**：
 * 域能被装配、追加装配不污染已有能力、声明的符号清单与安装结果一致、
 * 域名不与 core 已有域撞车。符号级用例在 API 面落定后加在同一个类里。
 */
@Test
class ArrayDomainTest {
    func makeInterp(): LispInterpreter {
        LispInterpreter([withQuietMode(), withStdLib(), withArray()])
    }

    @TestCase
    func testDomainMetadata() {
        println("\n=== array 域元数据 ===")
        let d = arrayDomain()
        if (d.name != "array") {
            @Fail("域名应为 array，实际 `${d.name}`")
        }
        if (d.symbols.size != 15) {
            @Fail("符号清单应有 15 个，实际 ${d.symbols.size} 个：${d.symbols}")
        }
        // 数组运算不执行宿主传入的代码 → 不逃逸；这条决定它能否进 PRESET_PURE
        if (d.escapable) {
            @Fail("array 域声明为 escapable，但它不该能绕过权限检查")
        }
        if (d.hostPolicy) {
            @Fail("array 域声明为 hostPolicy，但纯计算不触及宿主资源")
        }
        println("✓ name=array / 15 个符号 / escapable=false / hostPolicy=false")
    }

    /**
     * 追加装配不得顶掉已有能力
     *
     * `withArray()` 是 `replace: false` 的追加语义。若误写成 replace，宿主装完
     * 数组就没有 `+` / `println` 了 —— 这类错误只在真实使用时才暴露。
     */
    @TestCase
    func testInstallKeepsBuiltins() {
        println("\n=== 追加装配保留默认内建 ===")
        let it = makeInterp()
        let r = it.eval("(+ 1 2)")
        if (r.toString() != "3") {
            @Fail("装配数组域后 `(+ 1 2)` 不再是 3，实得 `${r.toString()}`")
        }
        println("✓ (+ 1 2) => 3")
    }

    /** 域可重复装配（幂等）：后装者覆盖先装者，不应报错也不应破坏已有能力 */
    @TestCase
    func testInstallTwiceIsIdempotent() {
        println("\n=== 重复装配幂等 ===")
        let it = LispInterpreter([
            withQuietMode(), withStdLib(), withArray(), withArray()
        ])
        let r = it.eval("(+ 1 2)")
        if (r.toString() != "3") {
            @Fail("重复装配数组域后基本求值失效，实得 `${r.toString()}`")
        }
        println("✓ 装两次仍然 (+ 1 2) => 3")
    }

    /**
     * 声明的符号清单必须与安装后实际注册的一致
     *
     * 空域阶段这条恒真，但断言位置先占好：将来往 `arrayDomain().symbols`
     * 加了符号却忘了在 `install` 里注册（或反之），这里立刻红。
     * 清单失真的后果是沙箱审计放过本应拦截的符号、文档生成缺项。
     */
    @TestCase
    func testSymbolsMatchInstall() {
        println("\n=== 符号清单与安装一致 ===")
        let d = arrayDomain()
        let it = makeInterp()
        var missing = 0
        for (s in d.symbols) {
            let probe = "(procedure? ${s})"
            if (it.eval(probe).toString() != "true") {
                missing++
                println("  ✗ 域声明了 `${s}`，但装完不是可调用值")
            }
        }
        if (missing > 0) {
            @Fail("${missing} 个声明符号装完后不可调用")
        }
        println("✓ 声明 ${d.symbols.size} 个符号，全部可用")
    }

    /**
     * 域名不得与 core 已有域撞车
     *
     * 域是"注册集合"，同名域后装者覆盖先装者 —— 撞名不会报错，只会静默顶掉
     * core 的域。数组族将来还有 io / linalg / stats / signal，都会撞上 core 的
     * `io` 类域名，这条用例把检测点前移到这里。
     */
    @TestCase
    func testDomainNameNotTakenByCore() {
        println("\n=== 域名不与 core 预置域冲突 ===")
        var clash = ""
        for (d in BuiltinFunctions.presetFull()) {
            if (d.name == "array") {
                clash = d.name
            }
        }
        if (clash.size > 0) {
            @Fail("core 的 PRESET_FULL 里已有同名域 `${clash}`")
        }
        println("✓ core 预置域里没有 array")
    }
}
