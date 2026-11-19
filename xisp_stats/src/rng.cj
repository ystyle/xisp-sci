package ystyle::xisp_stats

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp.core.eval.*
import ystyle::xisp_array.*

/**
 * 随机数族：均匀 / 正态 / 整数 / 排列 / 抽样
 *
 * ## 为什么种子是参数，而不是域内状态
 *
 * 本仓的能力域声明为「纯函数、无副作用」：同一个表达式求值两次必须得到同一个值。
 * 随机数一旦在域里存状态（`(rand-seed! 42)` 这种形态），这条不变量就破了 ——
 * 求值顺序、并发求值、重放都会改变结果，还得为它单独标 `escapable`、过沙箱审计。
 *
 * 种子作为**参数**传进来，同一个种子永远给同一串数：可复现性由类型（参数）保证，
 * 而不是由约定保证。代价是每次调用都得写种子，收益是随机数变成与 `mean` /
 * `norm-cdf` 同级的纯函数 —— 沙箱不用知道它的存在。
 *
 * ## 为什么自己写 PRNG，而不用运行库
 *
 * 三个要求缺一不可：
 *
 * 1. **可复现** —— 同一个种子在任何平台、任何编译器版本上给同一串数。算法必须钉死在
 *    这里：运行库换一版实现，昨天的分析就复现不了了。
 * 2. **零依赖** —— 本仓成员的 `[dependencies]` 只有同族模块（见仓内 AGENTS）。
 * 3. **质量** —— 统计模拟对均匀性与周期有要求，线性同余（`x = a·x + c`）的低位周期短、
 *    连续样本相关，不能用于这类用途。
 *
 * 选 **xoshiro256\*\***（Blackman & Vigna, 2018）：256 位状态、周期 2^256−1、
 * 通过作者的小池测试套件，实现只有十几行 —— 十几行的好处是可以逐位对照参考实现验证
 * （见 `rng_test.cj` 里的已知序列），这比「相信库」强得多。
 *
 * ## 三种均匀化，各管一件事
 *
 * | 需要的 | 做法 | 为什么不是别的 |
 * |---|---|---|
 * | `[0,1)` 浮点 | 取**高 53 位** × 2^−53 | `x / 2^64` 让靠 0 的一端概率偏大（见 `nextUniform`） |
 * | `[lo,hi)` 整数 | 拒绝采样 | `x % n` 有模偏差（见 `nextBounded`） |
 * | 正态 | **逆变换** `Φ⁻¹(u)` | 一行代码，且直接复用 `distributions.cj` 的 `normQuantile` |
 *
 * 正态不用 Box-Muller / Ziggurat：逆变换法只需要一个均匀数，生成器消耗可预测，
 * 而且它把「正态的正确性」归约到「`normQuantile` 的正确性 + 均匀数的正确性」——
 * 两者在各自的测试里已经钉住了。多一套算法就多一处要独立验证的地方。
 *
 * ## 排列与抽样是同一个操作
 *
 * `(cangjie::rand-sample n k seed)` 就是 `(cangjie::rand-permutation n seed)` 的**前 k 个**：
 * Fisher-Yates 抽 k 个只需要洗前 k 个位置。两者都走 `shuffledPrefix`，`k = n` 时前者
 * 退化成后者 —— 这不是巧合，是同一个洗牌的前缀，测试里有一条等式钉住它。
 */

// ───────────────────────── 常量 ─────────────────────────
//
// 仓颉要求顶层 `let` 先定义后使用，所以常量放在最前面。

/** SplitMix64 的步进增量：`⌊2^64/φ⌋`，与 xoshiro 作者参考实现一致 */
let SPLITMIX_GAMMA: UInt64 = 0x9E3779B97F4A7C15

/** SplitMix64 finalizer 的第一个乘子（MurmurHash3 的 fmix64 常量） */
let SPLITMIX_MUL1: UInt64 = 0xBF58476D1CE4E5B9

/** SplitMix64 finalizer 的第二个乘子 */
let SPLITMIX_MUL2: UInt64 = 0x94D049BB133111EB

/** `2^−53`：把 53 位尾数缩放成 `[0,1)` 的浮点 */
let TWO_POW_M53: Float64 = 1.0 / 9007199254740992.0

// ───────────────────────── 位型转换与溢出 ─────────────────────────
//
// 仓颉的整数算术**默认检查溢出并抛异常**（`@OverflowThrowing`），而随机数生成器
// 每一步都在模 2^64 的意义下运算 —— 那些「溢出」是设计本身，不是错误。
// 所以这几个小函数显式声明 `@OverflowWrapping`（高位截断），语义与参考实现一致。

/**
 * `Int64` → `UInt64` 的**位型**转换
 *
 * 仓颉默认的整型转换带范围检查（`UInt64(-1)` 会抛异常），但种子的语义是「一串位」，
 * 不是「一个非负数」。负数种子走二补码：`-1` 与 `0xFFFFFFFFFFFFFFFF` 是同一个种子。
 */
@OverflowWrapping
func bitsOf(v: Int64): UInt64 {
    UInt64(v)
}

/** `UInt64` → `Int64` 的位型转换（最高位为 1 时结果是负数） */
@OverflowWrapping
func intOfBits(v: UInt64): Int64 {
    Int64(v)
}

/** 64 位循环左移 */
@OverflowWrapping
func rotateLeft(x: UInt64, k: Int64): UInt64 {
    (x << k) | (x >> (64 - k))
}

/**
 * SplitMix64 的一步：先前进状态，再由 finalizer 混淆出一个输出字
 *
 * 用途是**种子扩展**：把任意一个 64 位种子（含 0、含负数）摊成 4 个状态字。
 * 直接拿种子的前 4 个字节填状态是错的 —— 相近的种子会给出高度相关的序列
 * （比如种子 1 与 2 只差状态里的一个位，前几百个输出可能几乎一样）。
 */
@OverflowWrapping
func splitMixStep(state: UInt64): (UInt64, UInt64) {
    let next = state + SPLITMIX_GAMMA
    var z = next
    z = (z ^ (z >> 30)) * SPLITMIX_MUL1
    z = (z ^ (z >> 27)) * SPLITMIX_MUL2
    (next, z ^ (z >> 31))
}

// ───────────────────────── xoshiro256** ─────────────────────────

/**
 * xoshiro256\*\* 的状态机
 *
 * 一个实例 = 一条确定的随机序列，种子决定起点。它**不是**全局状态：每个 `rand-*`
 * 调用造一个、用完就丢 —— 这是「纯函数 + 显式种子」在实现层的样子。
 *
 * 状态是 4 个 `UInt64`（256 位）。`**` 指输出函数 `rotl(s1 * 5, 7) * 9`：
 * 把状态里最"好"的那个字过一遍乘法再取高位，避免 xorshift 类生成器在高维上的
 * 线性相关（这正是它比纯 xorshift 强的地方）。
 */
class Rng {
    private var s: Array<UInt64>

    /**
     * 直接用 4 个状态字构造
     *
     * 只给测试用：参考实现公布的已知序列是按固定状态给出的，要逐位对照
     * 就必须能绕过种子扩展这一步。
     */
    init(s0: UInt64, s1: UInt64, s2: UInt64, s3: UInt64) {
        this.s = [s0, s1, s2, s3]
    }

    /** 从 `Int64` 种子构造：先用 SplitMix64 展开出 4 个状态字 */
    init(seed: Int64) {
        let words = Array<UInt64>(4, repeat: 0)
        var state = bitsOf(seed)
        var i = 0
        while (i < 4) {
            let step = splitMixStep(state)
            state = step[0]
            words[i] = step[1]
            i++
        }
        this.s = words
    }

    /**
     * 取一个 64 位随机字（xoshiro256\*\* 的一步）
     *
     * 逐行对应 Blackman & Vigna 的参考实现。**六行的顺序不能改**：
     * `s[1]` 同时参与输出与状态更新，先算 `result` 再动状态就是全部秘密。
     */
    @OverflowWrapping
    func nextBits(): UInt64 {
        let result = rotateLeft(this.s[1] * 5, 7) * 9
        let t = this.s[1] << 17
        this.s[2] ^= this.s[0]
        this.s[3] ^= this.s[1]
        this.s[1] ^= this.s[2]
        this.s[0] ^= this.s[3]
        this.s[2] ^= t
        this.s[3] = rotateLeft(this.s[3], 45)
        result
    }

    /**
     * `[0,1)` 均匀浮点：取**高 53 位**
     *
     * 双精度的尾数正好 53 位，所以取 53 位就能用满每个可表示的 `[0,1)` 值，
     * 且每个值的概率恰好是 2^−53。
     *
     * 为什么不写 `Float64(next()) / 2^64`：`2^64` 不是 `2^53` 的倍数（差 2^11），
     * 结果是把靠 0 的那 2^11 个 64 位字**压到同一个**双精度数上，而靠近 1 的那一端
     * 没有对应的压缩 —— 分布不再是均匀的。这个偏差在 `mean` 上小到看不出来，
     * 但在尾部概率和极值统计里是系统性的。
     */
    func nextUniform(): Float64 {
        Float64(this.nextBits() >> 11) * TWO_POW_M53
    }

    /**
     * `[0, range)` 均匀整数，**无模偏差**
     *
     * 直接 `x % range` 有偏差：`2^64` 通常不是 `range` 的倍数，余数小的那几个值
     * 会比别处多出现一次。`range = 3` 时偏差只有 3·10^−20，看着可以忽略；但
     * `range` 大到 `2^63` 量级时，一半的取值比另一半多一倍 —— 这是结构性的错，
     * 与样本量无关。
     *
     * 做法：算出 `threshold = 2^64 mod range`，丢掉落在 `[0, threshold)` 的样本再取。
     * 剩下的 `[threshold, 2^64)` 长度恰好是 `range` 的整数倍，`%` 就完全均匀。
     * 每次重取的概率 < range/2^64 ≤ 1/2，期望取 1~2 次。
     *
     * `range = 0` 表示「要整个 64 位域」（即 `rand-int` 的 `[Int64.MIN, Int64.MAX)`），
     * 这时取模是恒等，直接给一个整字。**不能**让它去算 `2^64 % 0`。
     */
    @OverflowWrapping
    func nextBounded(range: UInt64): UInt64 {
        if (range == 0) {
            return this.nextBits()
        }
        // `0 - range` 在模 2^64 下就是 `2^64 - range`，对它取模得到 `2^64 mod range`
        let threshold = (0 - range) % range
        var x = this.nextBits()
        while (x < threshold) {
            x = this.nextBits()
        }
        x % range
    }

    /**
     * `[lo, hi)` 均匀整数，调用方保证 `hi > lo`
     *
     * 宽度用**位型相减**算：`hi - lo` 在 `Int64` 上会溢出（`lo` 很负、`hi` 很正时），
     * 而 `UInt64` 的减法在模 2^64 意义下恰好等于真实的元素个数。偏移完再按位型转回
     * `Int64` —— 所以 `[Int64.MIN, Int64.MAX)` 这种满域请求也成立。
     */
    @OverflowWrapping
    func nextIntBetween(lo: Int64, hi: Int64): Int64 {
        let width = bitsOf(hi) - bitsOf(lo)
        intOfBits(bitsOf(lo) + this.nextBounded(width))
    }
}

// ───────────────────────── 生成（纯函数，无状态） ─────────────────────────

/** `n` 个 `[0,1)` 均匀样本 */
func uniformSamples(n: Int64, seed: Int64): Array<Float64> {
    let rng = Rng(seed)
    let out = Array<Float64>(n, repeat: 0.0)
    var i: Int64 = 0
    while (i < n) {
        out[i] = rng.nextUniform()
        i++
    }
    out
}

/**
 * `n` 个 `N(mu, sigma²)` 样本（逆变换法）
 *
 * `x = mu + sigma·Φ⁻¹(u)`：`u` 均匀则 `Φ⁻¹(u)` 是标准正态 —— 这是 CDF 定义式反着用，
 * 不需要 Box-Muller（那要两路独立随机数），也不需要接受-拒绝（那会让消耗的随机数
 * 个数变得不可预测）。
 *
 * `u = 0` 时 `Φ⁻¹` 是 −∞，必须重取。高 53 位全 0 的概率是 2^−53，不影响性能；
 * `u = 1` 不会出现 —— `nextUniform` 的上界是开区间。
 */
func normalSamples(n: Int64, mu: Float64, sigma: Float64, seed: Int64): Array<Float64> {
    let rng = Rng(seed)
    let out = Array<Float64>(n, repeat: 0.0)
    var i: Int64 = 0
    while (i < n) {
        var u = rng.nextUniform()
        while (u <= 0.0) {
            u = rng.nextUniform()
        }
        out[i] = mu + sigma * normQuantile(u, 0.0, 1.0)
        i++
    }
    out
}

/** `n` 个 `[lo, hi)` 均匀整数 */
func intSamples(n: Int64, lo: Int64, hi: Int64, seed: Int64): Array<Int64> {
    let rng = Rng(seed)
    let out = Array<Int64>(n, repeat: 0)
    var i: Int64 = 0
    while (i < n) {
        out[i] = rng.nextIntBetween(lo, hi)
        i++
    }
    out
}

/**
 * 洗出 `0..n-1` 的排列的**前 k 个**（Fisher-Yates，升序）
 *
 * 第 `i` 步从 `[i, n)` 里均匀取一个 `j` 与 `a[i]` 交换。洗到第 `k` 步停下，
 * `a[0..k)` 就是 `[0,n)` 里无放回均匀抽出的 k 个（顺序也均匀）；洗完 `n` 步是整排列。
 *
 * 于是 `rand-sample n k` 与 `rand-permutation n` 的前 k 个**逐位相同**，
 * `k = n` 时前者退化成后者 —— 测试里有一条等式钉住这个关系。
 *
 * 代价：为了这条等式，抽 k 个也要先铺开 n 个下标（O(n) 时间与内存）。
 * 这是可验证性的价格；要抽 10 个却传 n = 10^8 请先想清楚内存，否则会分配 800 MB。
 */
func shuffledPrefix(n: Int64, k: Int64, seed: Int64): Array<Int64> {
    let rng = Rng(seed)
    let a = Array<Int64>(n, repeat: 0)
    var i: Int64 = 0
    while (i < n) {
        a[i] = i
        i++
    }
    i = 0
    while (i < k) {
        let j = i + rng.nextIntBetween(0, n - i)
        let tmp = a[i]
        a[i] = a[j]
        a[j] = tmp
        i++
    }
    let out = Array<Int64>(k, repeat: 0)
    i = 0
    while (i < k) {
        out[i] = a[i]
        i++
    }
    out
}

/** `0..n-1` 的随机排列 */
func permutationOf(n: Int64, seed: Int64): Array<Int64> {
    shuffledPrefix(n, n, seed)
}

/** `0..n-1` 中**无放回**抽 `k` 个（`k ≤ n`） */
func sampleWithoutReplacement(n: Int64, k: Int64, seed: Int64): Array<Int64> {
    shuffledPrefix(n, k, seed)
}

/**
 * **有放回**抽 `n` 个下标（bootstrap 重采样）
 *
 * 每次从 `[0, n)` 独立取：抽出来的是「原始 n 个观测各被选中几次」，
 * 所以同一个下标会重复出现 —— 这正是 bootstrap 需要的（重采样样本的大小
 * 与原样本相同，且原样本里没出现的观测在新样本里也不会出现）。
 */
func resampleOf(n: Int64, seed: Int64): Array<Int64> {
    let rng = Rng(seed)
    let out = Array<Int64>(n, repeat: 0)
    var i: Int64 = 0
    while (i < n) {
        out[i] = rng.nextIntBetween(0, n)
        i++
    }
    out
}

// ───────────────────────── Lisp 接口 ─────────────────────────
//
// 与 `dist_ops.cj` 同一个分层：数学/算法在上面的纯函数里，这里只做**参数校验 + 装箱**。
// 非法参数在接口层抛 `IllegalArgumentException`，由 `guardedStats` 转成 Lisp 的
// `TypeError` —— 用户看到的是「cangjie::rand-int 需要 lo < hi，得到 lo=5、hi=5」，
// 而不是一个气势汹汹的运行时错误或者一串莫名其妙的数。

/**
 * 个数参数：必须 ≥ 0
 *
 * `n = 0` 合法，返回空 ndarray —— 「还没抽」不是参数错误，按批大小循环的脚本
 * 传 0 进来不该炸。负数才是错的。
 */
func countArg(v: LispValue, who: String, name: String): Int64 {
    let n = intArg(v, who, name)
    if (n < 0) {
        throw IllegalArgumentException("${who} 的 ${name} 必须 ≥ 0，得到 ${n}")
    }
    n
}

/** 随机数族占用的 6 个符号 */
let RNG_SYMBOLS: Array<String> = [
    "cangjie::rand-uniform", "cangjie::rand-normal", "cangjie::rand-int",
    "cangjie::rand-permutation", "cangjie::rand-sample", "cangjie::rand-resample"]

func registerRng(ctx: CapabilityContext): Unit {
    let env = ctx.env

    // (cangjie::rand-uniform n seed) → ndarray（float64），n 个 [0,1) 均匀
    env.define("cangjie::rand-uniform", NativeFunc({ args =>
        guardedStats({ =>
            requireArity(args, 2, "cangjie::rand-uniform")
            let who = "cangjie::rand-uniform"
            let n = countArg(args[0], who, "n")
            let seed = intArg(args[1], who, "seed")
            LispValue.External(ndarrayFromFloats(uniformSamples(n, seed)))
        })
    }))

    // (cangjie::rand-normal n mu sigma seed) → ndarray（float64），N(mu, sigma²)
    env.define("cangjie::rand-normal", NativeFunc({ args =>
        guardedStats({ =>
            requireArity(args, 4, "cangjie::rand-normal")
            let who = "cangjie::rand-normal"
            let n = countArg(args[0], who, "n")
            let mu = numOf(args[1], who)
            let sigma = positiveArg(args[2], who, "sigma")
            let seed = intArg(args[3], who, "seed")
            LispValue.External(ndarrayFromFloats(normalSamples(n, mu, sigma, seed)))
        })
    }))

    // (cangjie::rand-int n lo hi seed) → ndarray（int64），[lo, hi) 均匀
    env.define("cangjie::rand-int", NativeFunc({ args =>
        guardedStats({ =>
            requireArity(args, 4, "cangjie::rand-int")
            let who = "cangjie::rand-int"
            let n = countArg(args[0], who, "n")
            let lo = intArg(args[1], who, "lo")
            let hi = intArg(args[2], who, "hi")
            if (lo >= hi) {
                throw IllegalArgumentException(
                    "${who} 需要 lo < hi，得到 lo=${lo}、hi=${hi}（区间是左闭右开）")
            }
            let seed = intArg(args[3], who, "seed")
            LispValue.External(ndarrayFromInts(intSamples(n, lo, hi, seed)))
        })
    }))

    // (cangjie::rand-permutation n seed) → ndarray（int64），0..n-1 的随机排列
    env.define("cangjie::rand-permutation", NativeFunc({ args =>
        guardedStats({ =>
            requireArity(args, 2, "cangjie::rand-permutation")
            let who = "cangjie::rand-permutation"
            let n = countArg(args[0], who, "n")
            let seed = intArg(args[1], who, "seed")
            LispValue.External(ndarrayFromInts(permutationOf(n, seed)))
        })
    }))

    // (cangjie::rand-sample n k seed) → ndarray（int64），0..n-1 中无放回抽 k 个
    //
    // 校验顺序先 k 与 n 的关系再生成：`k > n` 不是"少抽几个"，是无解的请求，
    // 必须报错（静默截断会让调用方拿到比预期短的数组，在按 k 定长循环里直接越界）。
    env.define("cangjie::rand-sample", NativeFunc({ args =>
        guardedStats({ =>
            requireArity(args, 3, "cangjie::rand-sample")
            let who = "cangjie::rand-sample"
            let n = countArg(args[0], who, "n")
            let k = countArg(args[1], who, "k")
            if (k > n) {
                throw IllegalArgumentException(
                    "${who} 的 k 不能大于 n（无放回抽样），得到 n=${n}、k=${k}")
            }
            let seed = intArg(args[2], who, "seed")
            LispValue.External(ndarrayFromInts(sampleWithoutReplacement(n, k, seed)))
        })
    }))

    // (cangjie::rand-resample n seed) → ndarray（int64），有放回抽 n 个下标
    env.define("cangjie::rand-resample", NativeFunc({ args =>
        guardedStats({ =>
            requireArity(args, 2, "cangjie::rand-resample")
            let who = "cangjie::rand-resample"
            let n = countArg(args[0], who, "n")
            let seed = intArg(args[1], who, "seed")
            LispValue.External(ndarrayFromInts(resampleOf(n, seed)))
        })
    }))
}
