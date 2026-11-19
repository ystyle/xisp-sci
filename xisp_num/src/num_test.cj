package ystyle::xisp_num

import ystyle::xisp.types.*
import ystyle::xisp_array.*
import std.unittest.*
import std.unittest.testmacro.*
import std.collection.ArrayList
import std.math.*

/**
 * 数值方法的白盒测试
 *
 * 数值算法的测试要点不是"跑通"，而是**误差量级符合理论**：
 * 插值要在节点上精确、Simpson 要比梯形高一阶、RK4 的收敛阶要是 4 而不是 2。
 */

func expectClose(actual: Float64, want: Float64, tol: Float64, what: String): Unit {
    if (abs(actual - want) > tol) {
        @Fail("${what}：期望 ${want}，实际 ${actual}（差 ${abs(actual - want)}）")
    }
}

func expectInt(actual: Int64, want: Int64, what: String): Unit {
    if (actual != want) {
        @Fail("${what}：期望 ${want}，实际 ${actual}")
    }
}

func expectErr(body: () -> Unit, what: String): Unit {
    var caught = false
    try {
        body()
    } catch (e: IllegalArgumentException) {
        caught = true
    }
    if (!caught) {
        @Fail("${what}：应当报错，但没有")
    }
}

@Test
class InterpTest {
    /**
     * 线性插值：**在节点上必须精确**，节点之间按线性
     */
    @TestCase
    func testLinear() {
        println("\n=== 线性插值 ===")
        let x = [0.0, 1.0, 2.0, 3.0]
        let y = [0.0, 10.0, 20.0, 30.0]
        // 节点上精确
        let atNodes = interp1Raw(x, y, [0.0, 1.0, 2.0, 3.0])
        expectClose(atNodes[0], 0.0, 1e-12, "x=0")
        expectClose(atNodes[1], 10.0, 1e-12, "x=1")
        expectClose(atNodes[3], 30.0, 1e-12, "x=3")
        // 中点
        let mid = interp1Raw(x, y, [0.5, 1.5, 2.5])
        expectClose(mid[0], 5.0, 1e-12, "x=0.5")
        expectClose(mid[1], 15.0, 1e-12, "x=1.5")
        expectClose(mid[2], 25.0, 1e-12, "x=2.5")
        println("✓ 节点精确、中点线性")
    }

    /**
     * 区间外的外推
     *
     * 线性插值没有外推的依据，这里**clamp 到端点**而不是硬外推 ——
     * 硬外推在金融/工程数据上会给出荒唐的值。
     */
    @TestCase
    func testClampOutside() {
        println("\n=== 区间外 ===")
        let x = [0.0, 1.0, 2.0]
        let y = [0.0, 10.0, 20.0]
        let out = interp1Raw(x, y, [-1.0, 3.0])
        expectClose(out[0], 0.0, 1e-12, "左端外 clamp")
        expectClose(out[1], 20.0, 1e-12, "右端外 clamp")
        println("✓ 区间外 clamp 到端点")
    }

    @TestCase
    func testErrors() {
        println("\n=== 参数错误 ===")
        // 长度不一致
        expectErr({ => interp1Raw([0.0, 1.0], [0.0], [0.5]) }, "长度不一致")
        // 少于 2 点
        expectErr({ => interp1Raw([0.0], [0.0], [0.5]) }, "单点")
        // x 非升序
        expectErr({ => interp1Raw([1.0, 0.0], [0.0, 1.0], [0.5]) }, "x 降序")
        // x 有重复
        expectErr({ => interp1Raw([0.0, 0.0], [0.0, 1.0], [0.5]) }, "x 重复")
        println("✓ 四类参数错误都报错")
    }
}

@Test
class PolyfitTest {
    /**
     * 拟合一个已知的二次多项式
     *
     * `y = 2x² + 3x + 1`，采样 5 个点，拟合 2 阶应精确还原系数。
     */
    @TestCase
    func testFitQuadratic() {
        println("\n=== 二次拟合 ===")
        let xs = [-2.0, -1.0, 0.0, 1.0, 2.0]
        let ys = ArrayList<Float64>()
        for (x in xs) {
            ys.add(2.0 * x * x + 3.0 * x + 1.0)
        }
        let coef = polyfitRaw(xs, ys.toArray(), 2)
        expectInt(coef.size, 3, "系数个数")
        expectClose(coef[0], 2.0, 1e-9, "二次项系数")
        expectClose(coef[1], 3.0, 1e-9, "一次项系数")
        expectClose(coef[2], 1.0, 1e-9, "常数项")
        println("✓ 精确还原 y = 2x² + 3x + 1")
    }

    /**
     * 拟合带噪声的数据：系数应接近但不必精确
     */
    @TestCase
    func testFitNoisy() {
        println("\n=== 带噪声拟合 ===")
        let xs = [-3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0]
        // 理论值 y = x²，加一点噪声
        let noise = [0.01, -0.02, 0.03, -0.01, 0.02, -0.03, 0.01]
        let ys = ArrayList<Float64>()
        var i: Int64 = 0
        while (i < xs.size) {
            ys.add(xs[i] * xs[i] + noise[i])
            i++
        }
        let coef = polyfitRaw(xs, ys.toArray(), 2)
        // 二次项应接近 1，一次项与常数项接近 0
        expectClose(coef[0], 1.0, 0.05, "二次项")
        expectClose(coef[1], 0.0, 0.05, "一次项")
        println("✓ 噪声下系数仍接近真值")
    }

    @TestCase
    func testPolyval() {
        println("\n=== 多项式求值 ===")
        // 2x² + 3x + 1 在 x=2 处 = 8+6+1 = 15
        expectClose(polyvalRaw([2.0, 3.0, 1.0], 2.0), 15.0, 1e-12, "Horner 求值")
        expectClose(polyvalRaw([2.0, 3.0, 1.0], 0.0), 1.0, 1e-12, "常数项")
        expectClose(polyvalRaw(Array<Float64>(), 5.0), 0.0, 1e-12, "空系数")
        println("✓ Horner 求值")
    }

    @TestCase
    func testFitErrors() {
        println("\n=== 拟合参数错误 ===")
        // 点不够
        expectErr({ => polyfitRaw([1.0, 2.0], [1.0, 2.0], 3) }, "3 阶只用 2 点")
        // 负阶数
        expectErr({ => polyfitRaw([1.0, 2.0], [1.0, 2.0], -1) }, "负阶数")
        println("✓ 点不足与负阶数报错")
    }
}

@Test
class IntegralTest {
    /**
     * 梯形法则对线性函数**精确**
     */
    @TestCase
    func testTrapzLinear() {
        println("\n=== 梯形对线性函数 ===")
        // y = x 在 [0,1] 上积分 = 0.5
        let y = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
        expectClose(trapzUniform(y, 0.1), 0.5, 1e-12, "线性函数积分")
        println("✓ y=x 在 [0,1] 积分 = 0.5")
    }

    /**
     * **Simpson 比梯形高一阶**
     *
     * 同一个二次函数上，Simpson 精确而梯形有误差 —— 这是 Simpson 的核心价值。
     */
    @TestCase
    func testSimpsonBetterThanTrapz() {
        println("\n=== Simpson 精度 ===")
        // y = x² 在 [0,1] 上积分 = 1/3
        let n: Int64 = 11
        let y = Array<Float64>(n, repeat: 0.0)
        var i: Int64 = 0
        while (i < n) {
            let t = Float64(i) / Float64(n - 1)
            y[i] = t * t
            i++
        }
        let h = 1.0 / Float64(n - 1)
        let simpson = simpsonRaw(y, h)
        let trapz = trapzUniform(y, h)
        expectClose(simpson, 1.0 / 3.0, 1e-12, "Simpson 对二次函数精确")
        // 梯形有明显误差（约 1e-3 量级）
        if (abs(trapz - 1.0 / 3.0) < 1e-6) {
            @Fail("梯形对二次函数不该这么精确，检查测试假设")
        }
        println("✓ Simpson 精确（1e-12），梯形有误差 —— 阶数差异得到验证")
    }

    @TestCase
    func testTrapzVariable() {
        println("\n=== 变距梯形 ===")
        // 不等距的 x，但 y = x 是线性的，梯形应精确
        let x = [0.0, 0.1, 0.5, 1.0]
        let y = [0.0, 0.1, 0.5, 1.0]
        expectClose(trapzVar(x, y), 0.5, 1e-12, "变距线性函数")
        println("✓ 变距积分对线性函数精确")
    }

    @TestCase
    func testSimpsonErrors() {
        println("\n=== Simpson 参数错误 ===")
        // 偶数个点 → 奇数个区间，Simpson 不适用
        expectErr({ => simpsonRaw([1.0, 2.0, 3.0, 4.0], 0.1) }, "偶数个点")
        expectErr({ => simpsonRaw([1.0, 2.0], 0.1) }, "点数不足")
        println("✓ 偶数点与点数不足都报错（不静默降级成梯形）")
    }
}

@Test
class OptimizeTest {
    /**
     * 黄金分割找抛物线最小值
     *
     * `(x-2)²` 在 `[0,5]` 上的最小值点是 `x=2`。
     */
    @TestCase
    func testGoldenSection() {
        println("\n=== 黄金分割 ===")
        let f: (Float64) -> Float64 = { x => (x - 2.0) * (x - 2.0) }
        let r = goldenSectionMin(f, 0.0, 5.0, 1e-10, 200)
        expectClose(r, 2.0, 1e-6, "抛物线最小值点")
        // 非对称区间
        let r2 = goldenSectionMin(f, 1.0, 10.0, 1e-10, 200)
        expectClose(r2, 2.0, 1e-6, "非对称区间")
        println("✓ 找到 x = 2")
    }

    /**
     * 端点附近的最小值
     */
    @TestCase
    func testMinNearBoundary() {
        println("\n=== 边界附近的极值 ===")
        // 最小值在 x = 0.1 附近
        let f: (Float64) -> Float64 = { x => (x - 0.1) * (x - 0.1) }
        let r = goldenSectionMin(f, 0.0, 1.0, 1e-10, 200)
        expectClose(r, 0.1, 1e-6, "近边界极值")
        println("✓ 近边界极值也能找到")
    }
}

@Test
class OdeTest {
    /**
     * `dy/dt = y, y(0) = 1` → `y(t) = eᵗ`
     *
     * RK4 的步长减半时误差应降到约 1/16（四阶收敛）。
     */
    @TestCase
    func testExponential() {
        println("\n=== 指数增长 ===")
        let f: (Float64, Float64) -> Float64 = { t, y => y }
        let r = rk4Raw(f, 1.0, 0.0, 1.0, 0.1)
        let ys = r[1]
        // h=0.1 时 RK4 的全局误差量级是 O(h^4) ≈ 1e-4·常数，实测 2e-6
        expectClose(ys[ys.size - 1], 2.718281828459045, 1e-5, "y(1) = e")
        println("✓ dy/dt = y 给出 y(1) = e")
    }

    /**
     * **验证收敛阶**：步长减半，误差应降约 16 倍
     *
     * 只验证"结果接近"是不够的 —— 一个二阶方法在粗步长下也可能看起来对，
     * 但外推到精细步长就会暴露。
     */
    @TestCase
    func testConvergenceOrder() {
        println("\n=== 收敛阶（RK4 应为 4 阶） ===")
        let f: (Float64, Float64) -> Float64 = { t, y => y }
        let exact = 2.718281828459045
        let coarse = rk4Raw(f, 1.0, 0.0, 1.0, 0.1)
        let fine = rk4Raw(f, 1.0, 0.0, 1.0, 0.05)
        let eCoarse = abs(coarse[1][coarse[1].size - 1] - exact)
        let eFine = abs(fine[1][fine[1].size - 1] - exact)
        if (eFine == 0.0 || eCoarse == 0.0) {
            @Fail("误差为 0，无法判断收敛阶（eCoarse=${eCoarse}, eFine=${eFine}）")
        }
        let ratio = eCoarse / eFine
        // 四阶方法步长减半，误差降 16 倍；容忍 8~32 的区间
        if (ratio < 8.0 || ratio > 32.0) {
            @Fail("收敛阶不符合四阶：误差比 ${ratio}（期望约 16）")
        }
        println("✓ 步长减半误差降 ${ratio} 倍（约 16，符合四阶）")
    }

    @TestCase
    func testOdeErrors() {
        println("\n=== ODE 参数错误 ===")
        let f: (Float64, Float64) -> Float64 = { t, y => y }
        // 步长为 0
        expectErr({ => rk4Raw(f, 1.0, 0.0, 1.0, 0.0) }, "步长 0")
        // 终止时间小于起始
        expectErr({ => rk4Raw(f, 1.0, 1.0, 0.0, 0.1) }, "t1 <= t0")
        println("✓ 步长与时间范围校验")
    }
}
