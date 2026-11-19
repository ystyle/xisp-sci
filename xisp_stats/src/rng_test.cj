package ystyle::xisp_stats

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp.core.eval.*
import ystyle::xisp_array.*
import std.unittest.*
import std.unittest.testmacro.*
import std.collection.ArrayList
import std.math.*

/**
 * 随机数族的测试
 *
 * ## 四套互相独立的证据
 *
 * 随机数的错法很特别：**它永远不报错，只是悄悄偏了**。所以光看「跑得通」毫无意义，
 * 得让每一条性质都有一个不依赖本实现的来源：
 *
 * 1. **已知序列（外部锚点）** —— `xoshiro256**` 的参考实现（Blackman & Vigna 发布的 C）
 *    以及一份独立写的 Python 实现，对同一组状态给出的输出逐位相同。本文件把那些值
 *    钉在常量里，本仓的实现必须一模一样。种子扩展（SplitMix64）与三种均匀化
 *    （53 位浮点 / 拒绝采样整数 / Fisher-Yates 洗牌）也照同一套做法钉住。
 *    **这条最重要**：它把「算法实现对了」与「我自己的两段代码互相一致」区分开了。
 * 2. **结构不变量** —— 排列必须恰好是 `0..n-1` 的排列（用 seen 标记查重，不靠排序后比对）、
 *    无放回抽样必须互不相同、有放回抽样必须能出现重复。这些是**定义级**的性质，
 *    与分布参数无关，任何实现都不能例外。
 * 3. **统计性质** —— 一阶/二阶矩、分位数覆盖、卡方拟合优度。矩对上只能说明均值方差对，
 *    所以还要卡方：它检验的是整条分布的形状。卡方用的 p 值来自 `chisqCdf`，
 *    顺带验证两个模块能互相配合。
 * 4. **Lisp 层接线** —— 符号真的注册进域声明了、参数顺序没写反、离散族返回 `Int`
 *    而不是 `Float`、非法参数在 Lisp 层变成 `TypeError` 而不是一串莫名其妙的数。
 *
 * ## 容差为什么不是一个数
 *
 * - 已知序列：**逐位相等**（0 容差）—— 确定性算法没有"差不多"
 * - 矩：1e-2（n = 100000 时均值的标准误约 3e-3，1e-2 是 3 个标准误；种子固定，所以
 *   不是概率问题，而是「偏了就该被抓住」）
 * - 覆盖概率：5e-3（100000 样本的伯努利标准误约 1.5e-3）
 * - 卡方 p 值：只要求 > 0.01，不要求接近某个值 —— 好种子下 p 是均匀分布的，
 *   钉死具体数值等于把「恰好」当成正确
 */

// ───────────────────────── 已知序列（外部锚点） ─────────────────────────
//
// 取值来源：上游 `xoshiro256starstar.c` 的 next() 与 SplitMix64 参考实现，
// 同一套输入用 C 和 Python 各跑一遍，两份结果逐位相同（见文件头说明）。
// 顶层 `let` 必须先定义后使用，所以全部常量放在最前。

/** 参考实现的固定状态：`s = {1, 2, 3, 4}` */
let KAT_CORE_STATE: Array<UInt64> = [1, 2, 3, 4]

/** `s = {1,2,3,4}` 时的前 8 个输出字（上游 C 与 Python 一致） */
let KAT_CORE_OUTPUT: Array<UInt64> = [
    0x0000000000002D00, 0x0000000000000000, 0x000000005A007080, 0x10E0000000009D80,
    0x10E0B61CE1009D80, 0x0870021CE143AD00, 0xE071C3C2E143F089, 0x75A1690EF7A20380]

/** 种子 42：SplitMix64 展开后的 4 个状态字 */
let KAT_SEED42_BITS: Array<UInt64> = [
    0x15780B2E0C2EC716, 0x6104D9866D113A7E, 0xAE17533239E499A1, 0xECB8AD4703B360A1]

/** 种子 0（SplitMix64 的关键用例：种子 0 不能退化成全零状态） */
let KAT_SEED0_BITS: Array<UInt64> = [
    0x99EC5F36CB75F2B4, 0xBF6E1F784956452A, 0x1A5F849D4933E6E0, 0x6AA594F1262D2D2C]

/** 种子 −1（负数走二补码，即 `0xFFFFFFFFFFFFFFFF`） */
let KAT_SEED_NEG1_BITS: Array<UInt64> = [
    0x8F5520D52A7EAD08, 0xC476A018CAA1802D, 0x81DE31C0D260469E, 0xBF658D7E065F3C2F]

/** 种子 42 的前 4 个 `[0,1)` 样本（高 53 位 × 2^−53） */
let KAT_SEED42_UNIFORM: Array<Float64> = [
    0.083862971059882163, 0.37898025066266861, 0.68004341102813937, 0.92469294532538759]

/** 种子 42 的 `[0,100)` 整数前 8 个（拒绝采样路径） */
let KAT_SEED42_INT_0_100: Array<Int64> = [42, 2, 9, 93, 76, 84, 54, 7]

/** 种子 7 的 `[−5,5)` 整数前 12 个（跨零点的区间：位型相减不能出错） */
let KAT_SEED7_INT_M5_5: Array<Int64> = [-1, -1, 3, -1, -1, -4, 1, 1, 3, 4, -2, 1]

/** 种子 42 的 `0..9` 全排列 */
let KAT_SEED42_PERM10: Array<Int64> = [2, 1, 3, 7, 8, 9, 4, 0, 6, 5]

/** 种子 42 的 `0..9` 中无放回抽 4 个（应等于上面排列的前 4 个） */
let KAT_SEED42_SAMPLE10X4: Array<Int64> = [2, 1, 3, 7]

/** 种子 42 的 `[0,6)` 有放回抽 6 个（有重复才对） */
let KAT_SEED42_RESAMPLE6: Array<Int64> = [0, 0, 5, 5, 4, 0]

// ───────────────────────── 测试小工具 ─────────────────────────
//
// 注意：`expectInt` / `expectNum` / `expectNear` / `closeEnough` 已经在同包的
// stats_test.cj 与 hypothesis_test.cj 里了，直接复用，不重复定义。

/** 两个 `Float64` 是否逐位相等（0.0 与 −0.0 算相等，NaN 不算） */
func sameBits(a: Float64, b: Float64): Bool {
    if (a != a || b != b) {
        return false
    }
    a == b
}

/** 整数数组逐元素比对 */
func expectIntArray(actual: Array<Int64>, want: Array<Int64>, what: String): Unit {
    if (actual.size != want.size) {
        @Fail("${what}：长度 ${actual.size} ≠ ${want.size}\n  实际 ${actual}\n  期望 ${want}")
    }
    var i: Int64 = 0
    while (i < actual.size) {
        if (actual[i] != want[i]) {
            @Fail("${what}：第 ${i} 个 ${actual[i]} ≠ ${want[i]}\n  实际 ${actual}\n  期望 ${want}")
        }
        i++
    }
}

/** 位型数组逐元素比对（下标用 Int64） */
func expectBitsArray(actual: Array<UInt64>, want: Array<UInt64>, what: String): Unit {
    if (actual.size != want.size) {
        @Fail("${what}：长度 ${actual.size} ≠ ${want.size}")
    }
    var i: Int64 = 0
    while (i < actual.size) {
        if (actual[i] != want[i]) {
            @Fail("${what}：第 ${i} 个 ${actual[i]} ≠ ${want[i]}")
        }
        i++
    }
}

/** 浮点数组逐元素比对（逐位相等） */
func expectFloatArray(actual: Array<Float64>, want: Array<Float64>, what: String): Unit {
    if (actual.size != want.size) {
        @Fail("${what}：长度 ${actual.size} ≠ ${want.size}")
    }
    var i: Int64 = 0
    while (i < actual.size) {
        if (!sameBits(actual[i], want[i])) {
            @Fail("${what}：第 ${i} 个 ${actual[i]} ≠ ${want[i]}")
        }
        i++
    }
}

/** 取 `n` 个 64 位随机字（不经过任何均匀化，直接看 PRNG 输出） */
func rawBitsOf(seed: Int64, n: Int64): Array<UInt64> {
    let rng = Rng(seed)
    let out = Array<UInt64>(n, repeat: 0)
    var i: Int64 = 0
    while (i < n) {
        out[i] = rng.nextBits()
        i++
    }
    out
}

/**
 * 检查 `values` 恰好是 `0..n-1` 的一个排列
 *
 * 用 seen 标记而不是「排序后逐位比」：排序法只能发现"内容不对"，
 * 而这里能发现重复（重复是洗牌写错最常见的症状 —— 交换写成赋值、下标算错）。
 */
func checkPermutation(values: Array<Int64>, n: Int64, what: String): Unit {
    if (values.size != n) {
        @Fail("${what}：长度 ${values.size} ≠ ${n}")
    }
    let seen = Array<Bool>(n, repeat: false)
    var i: Int64 = 0
    while (i < values.size) {
        let v = values[i]
        if (v < 0 || v >= n) {
            @Fail("${what}：第 ${i} 个值 ${v} 落在 [0,${n}) 之外")
        }
        if (seen[v]) {
            @Fail("${what}：值 ${v} 重复出现（下标 ${i}）")
        }
        seen[v] = true
        i++
    }
}

/** 卡方统计量与拟合优度 p 值；`expected` 是每箱的期望计数 */
func chiSquareFit(counts: Array<Int64>, expected: Float64): (Float64, Float64) {
    var chi2 = 0.0
    for (c in counts) {
        let d = Float64(c) - expected
        chi2 = chi2 + d * d / expected
    }
    // 自由度 = 箱数 − 1（每箱的期望由总数固定，只有箱数−1 个自由分量）
    let p = 1.0 - chisqCdf(chi2, Float64(counts.size - 1))
    (chi2, p)
}

/** 把 `[0,1)` 样本装进 `k` 个等宽箱 */
func binCounts(samples: Array<Float64>, k: Int64): Array<Int64> {
    let counts = Array<Int64>(k, repeat: 0)
    for (u in samples) {
        var idx = Int64(floor(u * Float64(k)))
        if (idx < 0) {
            idx = 0
        }
        if (idx >= k) {
            idx = k - 1
        }
        counts[idx] = counts[idx] + 1
    }
    counts
}

// ───────────────────────── Lisp 层小工具 ─────────────────────────

/** 建一个装了 stats 域（含随机数族）的解释器，跑一段 Lisp 代码 */
func evalRng(code: String): LispValue {
    let opts = ArrayList<InterpreterOption>()
    opts.add(withQuietMode())
    opts.add(withStdLib())
    opts.add(withArray())
    opts.add(withStats())
    let it = LispInterpreter(opts.toArray())
    it.eval(code)
}

/** 从 Lisp 返回值里取 ndarray */
func asNdarray(v: LispValue, what: String): NDArray {
    match (v) {
        case External(e) =>
            match (e) {
                case a: NDArray => a
                case _ => throw IllegalArgumentException("${what}：外部值不是 ndarray（${e.typeName}）")
            }
        case _ => throw IllegalArgumentException("${what}：期望 ndarray，得到 ${v.toString()}")
    }
}

/** 取 ndarray 里的浮点元素（`Int` 也收，但记录下类型） */
func floatElems(a: NDArray, what: String): Array<Float64> {
    let out = ArrayList<Float64>()
    var i: Int64 = 0
    while (i < a.length()) {
        match (a.at(i)) {
            case Float(x) => out.add(x)
            case Int(x) => out.add(Float64(x))
            case other => throw IllegalArgumentException(
                "${what} 第 ${i} 个元素不是数值：${other.toString()}")
        }
        i++
    }
    out.toArray()
}

/** 取 ndarray 里的整数元素；返回 `Float` 说明离散族返回类型错了，直接判失败 */
func intElems(a: NDArray, what: String): Array<Int64> {
    let out = ArrayList<Int64>()
    var i: Int64 = 0
    while (i < a.length()) {
        match (a.at(i)) {
            case Int(x) => out.add(x)
            case Float(x) => throw IllegalArgumentException(
                "${what} 第 ${i} 个元素是 Float(${x})，期望 Int")
            case other => throw IllegalArgumentException(
                "${what} 第 ${i} 个元素类型不对：${other.toString()}")
        }
        i++
    }
    out.toArray()
}

/** 错误类别名；不是错误返回空串 */
func rngErrorKind(v: LispValue): String {
    match (v) {
        case Error(e) => e.kind.name()
        case _ => ""
    }
}

/** 错误消息；不是错误返回空串 */
func rngErrorMessage(v: LispValue): String {
    match (v) {
        case Error(e) => e.message
        case _ => ""
    }
}

/**
 * Lisp 层的非法参数必须是 `TypeError`，而且消息里要点出**是哪个参数**
 *
 * 只查类别不够：`sigma` 越界报成「df 必须 > 0」虽然也是 TypeError，
 * 但用户会去改一个根本不存在的参数。
 */
func expectRngTypeError(code: String, mustMention: String): Unit {
    let v = evalRng(code)
    let kind = rngErrorKind(v)
    let msg = rngErrorMessage(v)
    if (kind != "TypeError") {
        @Fail("`${code}`：期望 TypeError，得到 `${kind}`（值 ${v.toString()}）")
    }
    if (mustMention.size > 0 && !msg.contains(mustMention)) {
        @Fail("`${code}`：错误消息里没提到 ${mustMention}，实际为「${msg}」")
    }
    println("  ✓ ${code}\n      → TypeError: ${msg}")
}

// ───────────────────────── 1. 已知序列 ─────────────────────────

@Test
class RngKnownAnswerTest {
    /**
     * 核心生成器 vs 上游参考实现
     *
     * `s = {1,2,3,4}` 是参考实现自带的固定状态，前 8 个输出字在这里钉死。
     * 这一条不通过，说明 6 行的状态更新写错了一行（顺序、轮转位数、乘数 5/9 任一）。
     */
    @TestCase
    func testCoreReferenceVector() {
        println("\n=== xoshiro256** 已知序列（对照上游参考实现）===")
        let rng = Rng(KAT_CORE_STATE[0], KAT_CORE_STATE[1], KAT_CORE_STATE[2], KAT_CORE_STATE[3])
        let got = Array<UInt64>(8, repeat: 0)
        var i: Int64 = 0
        while (i < 8) {
            got[i] = rng.nextBits()
            i++
        }
        expectBitsArray(got, KAT_CORE_OUTPUT, "s={1,2,3,4} 的前 8 个输出")
        println("✓ s={1,2,3,4} 的前 8 个输出与参考实现逐位一致")
    }

    /**
     * 种子扩展（SplitMix64）vs 参考实现
     *
     * 种子 0 是最容易写错的：如果实现里"种子为 0 就换个数"，或直接拿种子的位去填状态，
     * 这里的已知序列立刻对不上。负数种子走二补码，−1 就是 `0xFFFFFFFFFFFFFFFF`。
     */
    @TestCase
    func testSeedExpansion() {
        println("\n=== 种子扩展（SplitMix64）已知序列 ===")
        expectBitsArray(rawBitsOf(42, 4), KAT_SEED42_BITS, "种子 42 的前 4 个输出")
        expectBitsArray(rawBitsOf(0, 4), KAT_SEED0_BITS, "种子 0 的前 4 个输出")
        expectBitsArray(rawBitsOf(-1, 4), KAT_SEED_NEG1_BITS, "种子 −1 的前 4 个输出")
        println("✓ 种子 42 / 0 / −1 的前 4 个字都与参考实现一致")
    }

    /** `[0,1)` 均匀化的已知序列：钉住"取高 53 位 × 2^−53"这条转换 */
    @TestCase
    func testUniformBits() {
        println("\n=== [0,1) 均匀的已知序列 ===")
        expectFloatArray(uniformSamples(4, 42), KAT_SEED42_UNIFORM, "种子 42 的前 4 个均匀样本")
        // 高 53 位为 0 时结果必须是精确的 0.0（上界开区间，下界闭）
        let zeros = uniformSamples(4, 42)
        for (u in zeros) {
            if (!(u >= 0.0 && u < 1.0)) {
                @Fail("均匀样本落在 [0,1) 之外：${u}")
            }
        }
        println("✓ 前 4 个均匀样本与参考实现逐位一致，且都在 [0,1)")
    }

    /** 整数拒绝采样的已知序列：钉住 `threshold = 2^64 mod range` 这条路径 */
    @TestCase
    func testIntStream() {
        println("\n=== 整数抽样的已知序列（拒绝采样）===")
        expectIntArray(intSamples(8, 0, 100, 42), KAT_SEED42_INT_0_100, "种子 42 的 [0,100) 前 8 个")
        expectIntArray(intSamples(12, -5, 5, 7), KAT_SEED7_INT_M5_5, "种子 7 的 [−5,5) 前 12 个")
        println("✓ 整数抽样与参考实现一致（含跨零点的区间）")
    }

    /** 洗牌 / 抽样的已知序列：钉住 Fisher-Yates 的方向与取值方式 */
    @TestCase
    func testShuffleStream() {
        println("\n=== 洗牌与抽样的已知序列 ===")
        expectIntArray(permutationOf(10, 42), KAT_SEED42_PERM10, "种子 42 的 0..9 全排列")
        expectIntArray(sampleWithoutReplacement(10, 4, 42), KAT_SEED42_SAMPLE10X4,
            "种子 42 从 0..9 无放回抽 4 个")
        expectIntArray(resampleOf(6, 42), KAT_SEED42_RESAMPLE6, "种子 42 从 [0,6) 有放回抽 6 个")
        println("✓ 排列 / 无放回 / 有放回都逐位一致")
    }
}

// ───────────────────────── 2. 可复现 ─────────────────────────

@Test
class RngReproducibilityTest {
    /**
     * 同种子 → 同一串数
     *
     * 这是整个设计的立身之本：种子传进来就是参数，结果不依赖调用时间、调用顺序、
     * 之前调用过什么。逐位比较（不是"近似相等"）。
     */
    @TestCase
    func testSameSeedSameStream() {
        println("\n=== 同种子可复现 ===")
        let a = uniformSamples(1000, 42)
        let b = uniformSamples(1000, 42)
        expectFloatArray(a, b, "两次 uniformSamples(1000, 42)")

        let na = normalSamples(500, 1.5, 2.5, 42)
        let nb = normalSamples(500, 1.5, 2.5, 42)
        expectFloatArray(na, nb, "两次 normalSamples(500, 1.5, 2.5, 42)")

        let ia = intSamples(500, -100, 100, 42)
        let ib = intSamples(500, -100, 100, 42)
        expectIntArray(ia, ib, "两次 intSamples(500, -100, 100, 42)")

        expectIntArray(permutationOf(200, 42), permutationOf(200, 42), "两次 permutationOf(200, 42)")
        expectIntArray(sampleWithoutReplacement(200, 20, 42),
            sampleWithoutReplacement(200, 20, 42), "两次 sampleWithoutReplacement(200, 20, 42)")
        expectIntArray(resampleOf(200, 42), resampleOf(200, 42), "两次 resampleOf(200, 42)")
        println("✓ 六个函数的同种子结果逐位相同")
    }

    /**
     * 不同种子 → 不同的串
     *
     * 只在**单个值**上比较是不够的（1000 个样本里偶然撞上一个相同的首元素很正常），
     * 所以比整段：两段 1000 个样本完全相同才算"种子没起作用"。
     */
    @TestCase
    func testDifferentSeedDifferentStream() {
        println("\n=== 不同种子给不同的串 ===")
        let a = uniformSamples(1000, 42)
        let b = uniformSamples(1000, 43)
        var sameCount = 0
        var i: Int64 = 0
        while (i < 1000) {
            if (sameBits(a[i], b[i])) {
                sameCount++
            }
            i++
        }
        // 两个独立均匀序列在同一位置撞上的期望是 1000 × 2^−53 ≈ 0，一个都不该有
        if (sameCount > 0) {
            @Fail("种子 42 与 43 的 1000 个样本里有 ${sameCount} 个完全相同，种子没起作用")
        }
        // 相邻种子（42 / 43）也必须看起来无关：SplitMix64 就是为这件事存在的
        let c = rawBitsOf(42, 4)
        let d = rawBitsOf(43, 4)
        var bitDiff = 0.0
        var k: Int64 = 0
        while (k < 4) {
            var x = c[k] ^ d[k]
            var bits = 0
            while (x != 0) {
                bits = bits + Int64(x & 1)
                x = x >> 1
            }
            bitDiff = bitDiff + Float64(bits)
            k++
        }
        let avgBits = bitDiff / 256.0
        if (avgBits < 0.4 || avgBits > 0.6) {
            @Fail("相邻种子的状态字差异 ${avgBits} 偏离 0.5 太远，种子扩展有相关性")
        }
        println("✓ 不同种子给不同的串；相邻种子的状态字差异 ${avgBits}（≈0.5 才算无关）")
    }

    /**
     * 负数种子
     *
     * 负数按位型转 `UInt64`（二补码），不是"取绝对值"，也不是拒绝。
     * 所以 −1 与 1 必须是两条完全不同的序列。
     */
    @TestCase
    func testNegativeSeed() {
        println("\n=== 负数种子 ===")
        expectFloatArray(uniformSamples(64, -1), uniformSamples(64, -1), "两次种子 −1")
        let neg = uniformSamples(256, -1)
        let pos = uniformSamples(256, 1)
        var sameCount = 0
        var i: Int64 = 0
        while (i < 256) {
            if (sameBits(neg[i], pos[i])) {
                sameCount++
            }
            i++
        }
        if (sameCount > 0) {
            @Fail("种子 −1 与 1 给出了相同的样本（负数种子可能被取了绝对值）")
        }
        // −1 与它的位型 `0xFFFFFFFFFFFFFFFF` 必须是同一个种子，不能静默换成别的数
        expectBitsArray(rawBitsOf(-1, 4), KAT_SEED_NEG1_BITS, "种子 −1")
        println("✓ 负数种子可复现，且与对应正数不同")
    }
}

// ───────────────────────── 3. 边界 ─────────────────────────

@Test
class RngRangeTest {
    /** `[0,1)` 是**左闭右开**：`0` 可以出现，`1` 绝对不出现 */
    @TestCase
    func testUniformHalfOpen() {
        println("\n=== 均匀样本的边界 ===")
        let n: Int64 = 100000
        let u = uniformSamples(n, 2024)
        var lo = u[0]
        var hi = u[0]
        var i: Int64 = 0
        while (i < n) {
            let x = u[i]
            if (!(x >= 0.0)) {
                @Fail("第 ${i} 个样本 ${x} < 0")
            }
            if (!(x < 1.0)) {
                @Fail("第 ${i} 个样本 ${x} 达到或超过 1（上界必须是开区间）")
            }
            if (x < lo) {
                lo = x
            }
            if (x > hi) {
                hi = x
            }
            i++
        }
        // 100000 个样本的最小值期望是 1/100001：远离 0 说明低位被削掉了
        if (lo > 1e-2) {
            @Fail("最小值 ${lo} 太靠近上界，说明样本没有铺满 [0,1)")
        }
        // 最大值期望是 1 − 1/100001；离 1 太远说明 53 位只用了高位那几位
        if (hi < 1.0 - 1e-2) {
            @Fail("最大值 ${hi} 离 1 太远，说明 53 位没有用满")
        }
        println("✓ 10 万个样本都在 [0,1)，最小值 ${lo}、最大值 ${hi}")
    }

    /** `rand-int` 落在 `[lo, hi)` 且**两个端点都能取到**（端点覆盖是模偏差/BUG 的照妖镜） */
    @TestCase
    func testIntEndpoints() {
        println("\n=== 整数抽样的端点覆盖 ===")
        let n: Int64 = 100000
        let v = intSamples(n, 0, 10, 42)
        let seen = Array<Bool>(10, repeat: false)
        var i: Int64 = 0
        while (i < n) {
            let x = v[i]
            if (x < 0 || x >= 10) {
                @Fail("第 ${i} 个值 ${x} 落在 [0,10) 之外")
            }
            seen[x] = true
            i++
        }
        var k: Int64 = 0
        while (k < 10) {
            if (!seen[k]) {
                @Fail("值 ${k} 一次都没出现（[0,10) 上均匀抽样必须都出现）")
            }
            k++
        }
        // 跨零点的区间：lo 为负，hi 为正
        let w = intSamples(n, -5, 5, 7)
        let seenW = Array<Bool>(10, repeat: false)
        i = 0
        while (i < n) {
            let x = w[i]
            if (x < -5 || x >= 5) {
                @Fail("第 ${i} 个值 ${x} 落在 [−5,5) 之外")
            }
            seenW[x + 5] = true
            i++
        }
        k = 0
        while (k < 10) {
            if (!seenW[k]) {
                @Fail("值 ${k - 5} 一次都没出现")
            }
            k++
        }
        println("✓ [0,10) 与 [−5,5) 的 10 个值全部被取到，且无越界")
    }

    /**
     * 满域整数：`[Int64.MIN, Int64.MAX)`
     *
     * 这条专门打「用 `hi - lo` 算宽度」的实现：`Int64.MAX - Int64.MIN` 在 `Int64` 上溢出。
     * 本实现用位型相减，宽度恰好是 `2^64 − 1`，所以能跑通。
     */
    @TestCase
    func testIntFullDomain() {
        println("\n=== 满域整数 [Int64.MIN, Int64.MAX) ===")
        let v = intSamples(100, Int64.Min, Int64.Max, 3)
        expectInt(v.size, 100, "满域样本个数")
        var hasNegative = false
        var hasPositive = false
        for (x in v) {
            if (x < 0) {
                hasNegative = true
            }
            if (x >= 0) {
                hasPositive = true
            }
        }
        if (!hasNegative || !hasPositive) {
            @Fail("满域抽样没有同时出现正负值，宽度可能算错了")
        }
        // 相邻的满域请求应当给不同的值（不是常数）
        if (v[0] == v[1] && v[1] == v[2]) {
            @Fail("满域抽样连续三个值相同，生成器退化了")
        }
        println("✓ [Int64.MIN, Int64.MAX) 可抽（位型相减不溢出），且正负都出现")
    }
}

// ───────────────────────── 4. 统计性质 ─────────────────────────

@Test
class RngMomentTest {
    /**
     * 均匀性：均值 0.5、方差 1/12
     *
     * `U(0,1)` 的方差是 `1/12 ≈ 0.08333`。均值对上而方差不对，常见原因是
     * 「用了 `x/2^64`」之类的低位问题 —— 均值几乎不受影响，方差会偏。
     */
    @TestCase
    func testUniformMoments() {
        println("\n=== 均匀样本的矩（n = 100000）===")
        let u = uniformSamples(100000, 2024)
        let m = meanOf(u)
        let var0 = varianceOf(u, 0)
        expectNum(m, 0.5, 1e-2, "均匀样本均值")
        expectNum(var0, 1.0 / 12.0, 1e-2, "均匀样本方差")
        println("✓ 均值 ${m}（0.5）、方差 ${var0}（0.0833）")
    }

    /**
     * 正态：均值 `mu`、标准差 `sigma`
     *
     * 逆变换法如果漏了 `sigma` 乘子、或把 `Φ⁻¹` 用成了 `Φ`，标准差会变成 1 或别的量，
     * 而均值可能仍然是对的 —— 两个矩都要查。
     */
    @TestCase
    func testNormalMoments() {
        println("\n=== 正态样本的矩（n = 100000）===")
        let x = normalSamples(100000, 5.0, 2.0, 42)
        let m = meanOf(x)
        let sd = sqrt(varianceOf(x, 0))
        expectNum(m, 5.0, 1e-2, "正态样本均值")
        expectNum(sd, 2.0, 1e-2, "正态样本标准差")
        // 再查一组非默认参数：mu 负、sigma 小于 1
        let y = normalSamples(100000, -3.0, 0.5, 99)
        expectNum(meanOf(y), -3.0, 1e-2, "N(−3, 0.25) 的均值")
        expectNum(sqrt(varianceOf(y, 0)), 0.5, 1e-2, "N(−3, 0.25) 的标准差")
        println("✓ N(5,4)：均值 ${m}、std ${sd}；N(−3,0.25) 也对")
    }

    /**
     * 正态的分布形状（不只是前两阶矩）
     *
     * 两条覆盖概率：`P(X ≤ mu) = 0.5`、`P(|X − mu| ≤ 1.96σ) = 0.95`。
     * 这直接由 `normCdf` 算理论值 —— 与前两阶矩无关，能抓住"两个矩碰巧对了但形状错"的情况。
     */
    @TestCase
    func testNormalCoverage() {
        println("\n=== 正态样本的覆盖概率 ===")
        let mu = 10.0
        let sigma = 3.0
        let x = normalSamples(100000, mu, sigma, 7)
        var below = 0
        var inside = 0
        for (v in x) {
            if (v <= mu) {
                below++
            }
            if (abs(v - mu) <= 1.96 * sigma) {
                inside++
            }
        }
        let pBelow = Float64(below) / Float64(x.size)
        let pInside = Float64(inside) / Float64(x.size)
        expectNum(pBelow, 0.5, 5e-3, "P(X ≤ mu)")
        expectNum(pInside, 0.95, 5e-3, "P(|X − mu| ≤ 1.96σ)")
        println("✓ P(X ≤ mu) = ${pBelow}（0.5）、P(|X−mu| ≤ 1.96σ) = ${pInside}（0.95）")
    }

    /**
     * 卡方拟合优度：`rand-uniform` 的 10 个等宽箱
     *
     * 前两阶矩只约束均值和方差，任何一条方差相同的分布都能骗过去。卡方看的是
     * **整条分布的形状**：10 个箱的计数与均匀期望的偏离量，用 `chisqCdf`（9 自由度）
     * 换算成 p 值。
     *
     * 判据用 `p > 0.01` 而不是"p 接近某个数"：好种子下 p 本身就是均匀分布的，
     * 钉死具体数值等于把偶然当正确。这里同时验证了两个模块能互相配合。
     */
    @TestCase
    func testChisqGoodnessOfUniform() {
        println("\n=== 卡方拟合优度（均匀，10 箱，n = 100000）===")
        let n: Int64 = 100000
        let bins: Int64 = 10
        let u = uniformSamples(n, 2024)
        let counts = binCounts(u, bins)
        let (chi2, p) = chiSquareFit(counts, Float64(n) / Float64(bins))
        if (p <= 0.01) {
            @Fail("卡方拟合优度不合格：χ² = ${chi2}、p = ${p}（应 > 0.01）\n  计数 ${counts}")
        }
        println("✓ χ² = ${chi2}（df=9），p = ${p} > 0.01")
        println("  各箱计数：${counts}")
    }

    /**
     * 卡方拟合优度：`rand-int` 的 10 个取值
     *
     * 与上一条同构，但走的是**另一条代码路径**（拒绝采样 + 取模）。若拒绝采样写错
     * （比如阈值算反、或重取后忘了重新判断），分布会在最低的几档堆积 —— 卡方会抓出来。
     */
    @TestCase
    func testChisqGoodnessOfInt() {
        println("\n=== 卡方拟合优度（整数 0..9，n = 100000）===")
        let n: Int64 = 100000
        let bins: Int64 = 10
        let v = intSamples(n, 0, bins, 2024)
        let counts = Array<Int64>(bins, repeat: 0)
        for (x in v) {
            if (x < 0 || x >= bins) {
                @Fail("值 ${x} 落在 [0,${bins}) 之外")
            }
            counts[x] = counts[x] + 1
        }
        let (chi2, p) = chiSquareFit(counts, Float64(n) / Float64(bins))
        if (p <= 0.01) {
            @Fail("整数抽样的卡方不合格：χ² = ${chi2}、p = ${p}\n  计数 ${counts}")
        }
        println("✓ χ² = ${chi2}（df=9），p = ${p} > 0.01")
        println("  各值计数：${counts}")
    }
}

// ───────────────────────── 5. 排列与抽样 ─────────────────────────

@Test
class RngPermutationTest {
    /** 排列必须恰好是 `0..n-1` 的一个排列（定义级不变量，任何 n 都不能例外） */
    @TestCase
    func testPermutationIsPermutation() {
        println("\n=== 排列的定义级正确性 ===")
        let sizes = [1, 2, 3, 10, 100, 1000]
        for (n in sizes) {
            checkPermutation(permutationOf(n, 42), n, "permutationOf(${n}, 42)")
        }
        // 不同种子也各查一遍（种子 0 与负数是最容易出问题的输入）
        checkPermutation(permutationOf(50, 0), 50, "permutationOf(50, 0)")
        checkPermutation(permutationOf(50, -7), 50, "permutationOf(50, −7)")
        // n = 0 / 1 的退化情形
        expectInt(permutationOf(0, 42).size, 0, "permutationOf(0)")
        expectIntArray(permutationOf(1, 42), [0], "permutationOf(1)")
        println("✓ n ∈ {0,1,2,3,10,100,1000} 的排列都恰好是 0..n−1")
    }

    /**
     * 洗牌的均匀性：1000 个不同种子，看**首元素**的分布
     *
     * 每个位置上每个值出现的概率都应是 1/n。只查首元素就够抓常见错法：
     * 「洗牌方向写反」「j 取自 [0, n) 而不是 [i, n)」「交换写成赋值」——
     * 这些都会让某些值在首位的频率系统性偏高。
     *
     * 顺带检验种子扩展：1000 个相邻种子（0..999）如果扩展写错（比如种子只影响
     * 状态字的低字节），首元素分布会明显偏离均匀。
     */
    @TestCase
    func testPermutationFirstElementUniform() {
        println("\n=== 洗牌均匀性（1000 个种子的首元素分布）===")
        let n: Int64 = 10
        let trials: Int64 = 1000
        let counts = Array<Int64>(n, repeat: 0)
        var seed: Int64 = 0
        while (seed < trials) {
            let p = permutationOf(n, seed)
            counts[p[0]] = counts[p[0]] + 1
            seed++
        }
        let (chi2, p) = chiSquareFit(counts, Float64(trials) / Float64(n))
        if (p <= 0.01) {
            @Fail("首元素分布不够均匀：χ² = ${chi2}、p = ${p}\n  计数 ${counts}")
        }
        println("✓ χ² = ${chi2}（df=9），p = ${p} > 0.01，计数 ${counts}")
    }

    /** 无放回抽样：k 个互不相同的值，都在 `[0,n)` 内 */
    @TestCase
    func testSampleDistinct() {
        println("\n=== 无放回抽样：互不相同 ===")
        let cases: Array<(Int64, Int64)> = [(10, 3), (10, 10), (1000, 7), (1000, 999)]
        for (c in cases) {
            let n = c[0]
            let k = c[1]
            let s = sampleWithoutReplacement(n, k, 42)
            if (s.size != k) {
                @Fail("sample(${n},${k}) 长度 ${s.size} ≠ ${k}")
            }
            let seen = Array<Bool>(n, repeat: false)
            for (x in s) {
                if (x < 0 || x >= n) {
                    @Fail("sample(${n},${k}) 出界：${x}")
                }
                if (seen[x]) {
                    @Fail("sample(${n},${k}) 出现重复值 ${x}（无放回不允许重复）")
                }
                seen[x] = true
            }
        }
        // k = 0：空数组，不是错误
        expectInt(sampleWithoutReplacement(10, 0, 42).size, 0, "sample(10,0) 的长度")
        // k = n：等价于整排列
        checkPermutation(sampleWithoutReplacement(10, 10, 42), 10, "sample(10,10)")
        println("✓ 各 (n,k) 组合都互不相同、都在 [0,n) 内；k=0 为空、k=n 为整排列")
    }

    /**
     * `rand-sample` 是 `rand-permutation` 的**前缀**
     *
     * 这是设计上刻意保证的等式（同一个 Fisher-Yates 洗牌），也是最省事的自检：
     * 两条路径只要有一处不一致，就说明抽样多取/少取了随机数。
     */
    @TestCase
    func testSampleIsPrefixOfPermutation() {
        println("\n=== 抽样 = 排列的前缀 ===")
        let n: Int64 = 50
        let perm = permutationOf(n, 12345)
        for (k in [0, 1, 5, 25, 50]) {
            let s = sampleWithoutReplacement(n, k, 12345)
            if (s.size != k) {
                @Fail("sample(${n},${k}) 长度 ${s.size} ≠ ${k}")
            }
            var i: Int64 = 0
            while (i < k) {
                if (s[i] != perm[i]) {
                    @Fail("sample(${n},${k}) 与排列前 ${k} 个不一致：第 ${i} 个 ${s[i]} ≠ ${perm[i]}")
                }
                i++
            }
        }
        println("✓ sample(n,k) 与 permutation(n) 的前 k 个逐位相同")
    }

    /**
     * 有放回抽样：允许且**必然**出现重复
     *
     * 从 `[0,1000)` 抽 1000 次，一个重复都没有的概率小到可以忽略（生日问题的另一边：
     * 约 10^−217）。所以"没有重复"就说明实现退化成了无放回 —— 这正是 bootstrap
     * 会用错的地方。
     */
    @TestCase
    func testResampleHasReplacement() {
        println("\n=== 有放回抽样（bootstrap）===")
        let n: Int64 = 1000
        let r = resampleOf(n, 42)
        expectInt(r.size, n, "重采样样本大小（应与原样本相同）")
        let seen = Array<Bool>(n, repeat: false)
        var distinct: Int64 = 0
        for (x in r) {
            if (x < 0 || x >= n) {
                @Fail("重采样出界：${x}")
            }
            if (!seen[x]) {
                seen[x] = true
                distinct++
            }
        }
        if (distinct == n) {
            @Fail("1000 次抽取没有一个重复值 —— 有放回抽样退化成了无放回")
        }
        // 有放回抽 n 次，被覆盖到的不同值个数约为 n(1 − e^−1) ≈ 632
        let expected = Float64(n) * (1.0 - 1.0 / 2.718281828459045)
        if (abs(Float64(distinct) - expected) > 0.08 * Float64(n)) {
            @Fail("不同值个数 ${distinct} 与 n(1−e^−1) ≈ ${expected} 差太远")
        }
        // 分布均匀性：10 个箱各应约 100 个
        let counts = Array<Int64>(10, repeat: 0)
        for (x in r) {
            counts[x % 10] = counts[x % 10] + 1
        }
        let (chi2, p) = chiSquareFit(counts, Float64(n) / 10.0)
        if (p <= 0.01) {
            @Fail("重采样的余数分布不均匀：χ² = ${chi2}、p = ${p}")
        }
        println("✓ 1000 次有放回抽样覆盖 ${distinct} 个不同值（理论 ≈ ${expected}），含重复")
        println("  卡方 χ² = ${chi2}（df=9），p = ${p}")
    }
}

// ───────────────────────── 6. Lisp 层接线 ─────────────────────────

@Test
class RngLispTest {
    /**
     * 6 个符号都在域声明里，且真的注册成功了
     *
     * 本仓有过「清单里声明了、实现里没有」的教训：`symbols` 是沙箱审计和文档生成的
     * 唯一来源，清单与实现对不上，上层会以为可用，直到真调用才炸。
     */
    @TestCase
    func testSymbolsDeclared() {
        println("\n=== 符号清单 ===")
        let want = ["cangjie::rand-uniform", "cangjie::rand-normal", "cangjie::rand-int",
            "cangjie::rand-permutation", "cangjie::rand-sample", "cangjie::rand-resample"]
        for (name in want) {
            var found = false
            for (s in statsDomain().symbols) {
                if (s == name) {
                    found = true
                }
            }
            if (!found) {
                @Fail("域声明里没有 ${name}")
            }
        }
        // 清单说了有，就必须真能调用（不是声明了却没实现）
        let v = evalRng("(cangjie::rand-uniform 3 42)")
        if (asNdarray(v, "rand-uniform").length() != 3) {
            @Fail("rand-uniform 返回的 ndarray 长度不对")
        }
        println("✓ 6 个符号都在 STATS_SYMBOLS 里，且都能调用")
    }

    /** 返回类型：连续族是 Float，离散族是 Int —— 拿去当下标不会错 */
    @TestCase
    func testReturnTypes() {
        println("\n=== Lisp 层返回类型 ===")
        let u = asNdarray(evalRng("(cangjie::rand-uniform 4 42)"), "rand-uniform")
        expectInt(u.length(), 4, "rand-uniform 长度")
        for (x in floatElems(u, "rand-uniform")) {
            if (!(x >= 0.0 && x < 1.0)) {
                @Fail("rand-uniform 返回了 [0,1) 之外的值 ${x}")
            }
        }
        let n = asNdarray(evalRng("(cangjie::rand-normal 4 0 1 42)"), "rand-normal")
        expectInt(n.length(), 4, "rand-normal 长度")
        // 离散族：元素必须是 LispValue.Int
        let i = asNdarray(evalRng("(cangjie::rand-int 6 0 5 42)"), "rand-int")
        let iv = intElems(i, "rand-int")
        expectInt(iv.size, 6, "rand-int 长度")
        for (x in iv) {
            if (x < 0 || x >= 5) {
                @Fail("rand-int 返回了 [0,5) 之外的值 ${x}")
            }
        }
        let p = intElems(asNdarray(evalRng("(cangjie::rand-permutation 6 42)"), "perm"), "perm")
        checkPermutation(p, 6, "(cangjie::rand-permutation 6 42)")
        let s = intElems(asNdarray(evalRng("(cangjie::rand-sample 6 3 42)"), "sample"), "sample")
        expectInt(s.size, 3, "(cangjie::rand-sample 6 3 42) 长度")
        let r = intElems(asNdarray(evalRng("(cangjie::rand-resample 6 42)"), "resample"), "resample")
        expectInt(r.size, 6, "(cangjie::rand-resample 6 42) 长度")
        println("✓ 连续族返回 Float、离散族返回 Int")
    }

    /**
     * 验收样例：`(cangjie::rand-normal 5 0 1 42)`
     *
     * 返回 ndarray，且同一个种子两次调用逐位相同 —— 这就是"可复现"在用户眼里的样子。
     */
    @TestCase
    func testNormalSnippet() {
        println("\n=== 验收样例：(cangjie::rand-normal 5 0 1 42) ===")
        let first = evalRng("(cangjie::rand-normal 5 0 1 42)")
        let a = asNdarray(first, "rand-normal")
        println("  → ${first.toString()}")
        expectInt(a.length(), 5, "长度")
        let again = asNdarray(evalRng("(cangjie::rand-normal 5 0 1 42)"), "rand-normal")
        expectFloatArray(floatElems(a, "第一次"), floatElems(again, "第二次"), "两次同种子调用")
        // 与 Cangjie 层的同一调用完全一致（Lisp 层没有偷偷换个参数顺序）
        expectFloatArray(floatElems(a, "Lisp 层"), normalSamples(5, 0.0, 1.0, 42), "Lisp vs 仓颉层")
        // 参数顺序：mu=10, sigma=0.001 → 结果必须聚在 10 附近，而不是 0 附近
        let b = asNdarray(evalRng("(cangjie::rand-normal 5 10 0.001 42)"), "rand-normal(mu=10)")
        for (x in floatElems(b, "mu=10")) {
            if (abs(x - 10.0) > 0.01) {
                @Fail("mu=10、sigma=0.001 的样本 ${x} 离 10 太远，参数顺序可能错了")
            }
        }
        println("✓ 返回 ndarray、长度 5、同种子两次逐位相同、mu/sigma 顺序正确")
    }

    /** `n = 0` 与 `k = 0` 返回空数组，不报错 */
    @TestCase
    func testEmptyInputs() {
        println("\n=== 空输入 ===")
        expectInt(asNdarray(evalRng("(cangjie::rand-uniform 0 42)"), "uniform").length(), 0,
            "(cangjie::rand-uniform 0 42) 长度")
        expectInt(asNdarray(evalRng("(cangjie::rand-normal 0 0 1 42)"), "normal").length(), 0,
            "(cangjie::rand-normal 0 0 1 42) 长度")
        expectInt(asNdarray(evalRng("(cangjie::rand-int 0 0 10 42)"), "int").length(), 0,
            "(cangjie::rand-int 0 0 10 42) 长度")
        expectInt(asNdarray(evalRng("(cangjie::rand-permutation 0 42)"), "perm").length(), 0,
            "(cangjie::rand-permutation 0 42) 长度")
        expectInt(asNdarray(evalRng("(cangjie::rand-sample 5 0 42)"), "sample").length(), 0,
            "(cangjie::rand-sample 5 0 42) 长度")
        expectInt(asNdarray(evalRng("(cangjie::rand-resample 0 42)"), "resample").length(), 0,
            "(cangjie::rand-resample 0 42) 长度")
        println("✓ n=0 / k=0 都返回空 ndarray")
    }

    /**
     * 非法参数在 Lisp 层变成 `TypeError`，消息里点出具体参数
     *
     * 数学/算法层不做防御性检查（调用方保证前置条件），所以这一层是**唯一的**入口校验：
     * 漏一条，用户拿到的不是错误，而是一串看起来正常的数（比如 `sigma = −1` 会
     * 把正态镜像翻转，`n = −5` 会变成空数组）。
     */
    @TestCase
    func testTypeErrors() {
        println("\n=== 非法参数 → TypeError ===")
        expectRngTypeError("(cangjie::rand-uniform -1 42)", "n")
        expectRngTypeError("(cangjie::rand-uniform 5.0 42)", "n")
        expectRngTypeError("(cangjie::rand-uniform 5)", "")
        expectRngTypeError("(cangjie::rand-normal 10 0 0 42)", "sigma")
        expectRngTypeError("(cangjie::rand-normal 10 0 -1 42)", "sigma")
        expectRngTypeError("(cangjie::rand-int 10 5 5 42)", "lo < hi")
        expectRngTypeError("(cangjie::rand-int 10 5 4 42)", "lo < hi")
        expectRngTypeError("(cangjie::rand-permutation -3 42)", "n")
        expectRngTypeError("(cangjie::rand-sample 5 6 42)", "k")
        expectRngTypeError("(cangjie::rand-sample -1 0 42)", "n")
        expectRngTypeError("(cangjie::rand-resample -2 42)", "n")
        println("✓ 负数 n、k > n、sigma ≤ 0、lo ≥ hi、非整数参数、参数个数不对都报 TypeError")
    }

    /**
     * 负数种子在 Lisp 层也照常可用
     *
     * `(cangjie::rand-uniform 5 -1)` 必须能跑 —— 种子是 `Int64`，负数合法。
     * 若接口层误用了"必须 ≥ 0"的校验，这里会炸。
     */
    @TestCase
    func testNegativeSeedInLisp() {
        println("\n=== Lisp 层的负数种子 ===")
        let a = asNdarray(evalRng("(cangjie::rand-uniform 4 -1)"), "neg seed")
        expectInt(a.length(), 4, "负数种子的样本个数")
        let b = asNdarray(evalRng("(cangjie::rand-uniform 4 -1)"), "neg seed again")
        expectFloatArray(floatElems(a, "种子 −1"), floatElems(b, "种子 −1 第二次"), "负数种子可复现")
        println("✓ (cangjie::rand-uniform 4 -1) 可用且可复现")
    }
}
