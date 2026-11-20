# 分组与假设检验

## 分组聚合

「不同物种的花瓣长度差多少」、「各地区的销量分布」，第一步都是按类别把数据切开。

```lisp
(define d (cangjie::csv-read "iris.csv"))

(cangjie::group-agg (hashmap-get d "species") (hashmap-get d "petal_length") cangjie::mean)
;; → (("setosa" 1.464) ("versicolor" 4.260) ("virginica" 5.552))
```

一行出结果。需要更多控制时先分组再自己聚合：

```lisp
(map (lambda (kv) (list (car kv) (cangjie::quantile (cadr kv) 0.9)))
     (cangjie::group-by (hashmap-get d "species") (hashmap-get d "speed")))
```

### 返回 alist 而不是 HashMap

`group-by` 返回 `[[key, values] …]`，按类别**首次出现的顺序**排列。

这不是随意选的：报告和图表都依赖顺序稳定，而 `HashMap` 的迭代顺序不保证。
alist 还能直接喂给 `map` / `filter`。

### 一次遍历

分组是 O(n) 的一次遍历，不是「对每个类别扫一遍全表」（O(k·n)）。类别一多，
后者会慢成几倍，而分组这个功能存在的全部意义就是避免这种情况。

组内保持**原始顺序**，不排序。对时间序列类数据这很重要。

## 假设检验

### 为什么 p 值值得算

「A 组均值比 B 组高 2 分」本身没有信息量：两组各只有 3 个样本时，这 2 分可能纯属
偶然；各有 3000 个样本时，它几乎一定是真的。

**p 值回答的是「这个差异有多可能是偶然」**。没有它就没法判断一个差异值不值得当回事。

```lisp
;; 男女生的期末成绩差异显著吗
(define g (cangjie::group-by (hashmap-get d "sex") (hashmap-get d "G3")))
(cangjie::t-test2 (cadr (car g)) (cadr (cadr g)))
;; → {"t": -2.065, "df": 390.569, "p": 0.039577,
;;    "mean1": 9.966, "mean2": 10.914, "se": 0.459, "n1": 208, "n2": 187}
```

`p = 0.0396 < 0.05`，差异显著。但均值只差 0.95 分：统计显著不等于实际重要，
样本量足够大时任何微小差异都会「显著」。

### 单样本

```lisp
(cangjie::t-test1 x 3.0)      ; H₀: μ = 3
```

### 双样本用 Welch，不用合并方差

Welch 不假设两组方差相等。这不只是「更保险」：

方差相等这个前提在真实数据里经常不成立。两组样本量差很多时，合并方差会把大方差
那组过度加权，让 p 值系统性地偏小，也就是更容易误报「显著」。

自由度用 Welch–Satterthwaite 近似，所以 `df` 通常是小数（如 390.57）。

## 置信区间

```lisp
(cangjie::ci (hashmap-get d "G3") 0.95)
;; → {"lo": 9.9619, "hi": 10.8683, "mean": 10.4151, "se": 0.2327,
;;    "df": 394, "tcrit": 1.9660, "n": 395}
```

`level` 是**置信水平**（0.95），不是显著性水平（0.05）。

区间宽度随置信水平单调增加：90% < 95% < 99%。这是定义最直接的体现，也常被搞反。

## 更多检验

t 检验只回答「两组均值差多少」。下面这几种覆盖其余常见问题：

```lisp
(cangjie::cor-test x y)                 ; 这个相关系数显著吗
(cangjie::chisq-test observed expected) ; 频数分布符不符合预期
(cangjie::chisq-test table)             ; 两个分类变量有关联吗
(cangjie::wilcox-test x y)              ; 不假设正态的两组比较
(cangjie::anova g1 g2 g3)               ; 多组均值是否都一样
```

### 什么时候用哪个

| 问题 | 用什么 | 前提 |
|---|---|---|
| 两组均值有差异吗 | `t-test2` | 数据近似正态 |
| 两组位置有差异吗 | `wilcox-test` | **不要求正态**，只要可比大小 |
| 多组均值有差异吗 | `anova` | 各组近似正态、方差相近 |
| 这两个变量相关吗 | `cor-test` | 线性关系、联合正态 |
| 分布符合预期吗 | `chisq-test`（拟合优度） | 频数数据 |
| 两个分类变量有关联吗 | `chisq-test`（列联表） | 频数数据、每格期望 ≥ 5 |

### 为什么不两两跑 t 检验

k 组两两比较有 `k(k−1)/2` 对，每对都有 5% 的假阳性率。6 组就是 15 对，
「至少有一对碰巧显著」的概率约 **54%** —— 你会发现「显著差异」几乎是必然的。

ANOVA 用一个 F 值一次回答「这些组的均值是不是都一样」，把整体错误率控制在设定水平。

### `wilcox-test` 的精确与近似

小样本用**精确零分布**（不是近似），大样本退回正态近似 —— 因为精确分布的方案数
随样本量组合爆炸，`30×30` 已经是三百多万种。

```lisp
(define r (cangjie::wilcox-test x y))
(hashmap-get r "method")     ; "exact" / "normal-approx" / "normal-approx-ties"
```

**离散检验的 p 值不会等于 1**。哪怕两组完全不分离、`U` 正好落在平衡点，
精确双侧 p 也可能只到 0.7 —— 因为精确分布是离散的。这不是 bug，
连续分布（如 t 检验）才有「统计量为 0 时 p 恰好为 1」。

### 稳健的离散程度

```lisp
(cangjie::mad x)      ; 中位数绝对偏差
(cangjie::range x)    ; 极差
```

标准差用平方，**一个离群点就能把它拉爆**。一份 `[1 2 3 4 5]` 的数据里混进一个
1000，标准差从 1.58 涨到 445，而 MAD 纹丝不动还是 1。看数据离散程度时，
两个都算一遍，差很多就说明有离群点。

## t 分布是自带的

仓颉的 `std.math` 没有 `lgamma` / `tgamma` / `erf`，所以整套从零实现：
`log Γ(x)` 用 Lanczos 近似、不完全 Beta 用连分式 + Lentz 算法、分位数用二分反解。

**验证方式**：拿教科书 t 分位数表逐个对。

| df | 本套件 | 教材表值 |
|---|---|---|
| 1 | 12.706205 | 12.706 |
| 5 | 2.570582 | 2.571 |
| 30 | 2.042272 | 2.042 |
| 120 | 1.979930 | 1.980 |

这一步必须先做：如果 `tCritical` 系统性偏小，所有 p 值都会偏小，于是**什么都「显著」**。
这种错误最难发现，因为结果看起来「有发现」。

## 分布函数

上面那套数值基础现在**全部暴露成公开符号**了。六个家族，每个三个函数：

| 家族 | 密度 | 累积 | 分位数 |
|---|---|---|---|
| 正态 `N(μ,σ²)` | `cangjie::norm-pdf` | `cangjie::norm-cdf` | `cangjie::norm-quantile` |
| Student t | `cangjie::t-pdf` | `cangjie::t-cdf` | `cangjie::t-quantile` |
| 卡方 | `cangjie::chisq-pdf` | `cangjie::chisq-cdf` | `cangjie::chisq-quantile` |
| F | `cangjie::f-pdf` | `cangjie::f-cdf` | `cangjie::f-quantile` |
| 泊松 | `cangjie::pois-pmf` | `cangjie::pois-cdf` | `cangjie::pois-quantile` |
| 二项 | `cangjie::binom-pmf` | `cangjie::binom-cdf` | `cangjie::binom-quantile` |

```lisp
(cangjie::norm-cdf 1.96 0 1)          ; → 0.975002
(cangjie::norm-quantile 0.975 0 1)    ; → 1.959964
(cangjie::t-cdf 2.0 5)                ; → 0.949030
(cangjie::chisq-quantile 0.95 1)      ; → 3.841459
(cangjie::f-quantile 0.95 3 20)       ; → 3.098391
(cangjie::pois-pmf 2 2.5)             ; → 0.256516
(cangjie::binom-cdf 5 10 0.3)         ; → 0.952651
```

### 为什么这组函数重要

统计推断的出口永远是 p 值，而 p 值永远是「某个统计量落在某个分布尾部的概率」。
只有 `t-test1` / `t-test2` 的时候，**除了这两个检验，其余一律算不出 p 值** ——
想算个卡方统计量对应的 p、想找一个 95% 分位点、想自己搭一个检验，都没有入口。

现在有了。比如自己算一个卡方统计量：

```lisp
;; 观察频数 vs 期望频数，df = 类别数 − 1
(define stat (sum (map (lambda (p) (/ (* (- (car p) (cadr p)) (- (car p) (cadr p)))
                                     (cadr p)))
                     pairs)))
(- 1 (cangjie::chisq-cdf stat 2))     ; → p 值
```

### 命名：为什么不是 `pnorm` / `qnorm`

R 用 `d/p/q/r` 四个前缀分别表示密度、累积、分位数、随机数 —— 简洁，但要先记住这四个字母。
本仓已经有 `std` 对 `std-pop` 的先例（用描述性后缀区分语义），所以这里也走同一条路：
`-pdf` / `-pmf` / `-cdf` / `-quantile`。

**分布名放在前面**（`norm-` `t-` `chisq-` `f-` `pois-` `binom-`），排序时同族挨在一起。

**连续用 `-pdf`，离散用 `-pmf`** —— 概率密度与概率质量是不同量纲的东西：
连续分布的密度值可以大于 1，离散的质量不能。

### 离散分位数返回 `Int`

`pois-quantile` / `binom-quantile` 返回整数，不是浮点。按定义取**下侧**：
最小的 `k` 使 `CDF(k) ≥ p`。返回值拿去当数组下标不会出错。

### 参数错会报错，不会给你一个 `nan`

```lisp
(cangjie::norm-cdf 1 0 0)      ; Error: sigma 必须 > 0，得到 0
(cangjie::chisq-cdf -1 4)      ; Error: 参数超出分布的定义域
```

数学层对越界参数返回 `NaN`（数值代码的惯例），但 Lisp 层拦下来转成明确错误 ——
否则 `nan` 会一路飘到最终结果，你只看到「算出来是 NaN」，不知道是哪个参数错了。

### 还没有随机数

`rnorm` / `rt` 这类抽样需要**状态**（种子），而本仓所有域都是纯函数、无副作用。
种子放哪、可复现性怎么保证，是架构决策不是实现难度问题，要单独定。

## 模拟：多元正态

```lisp
(cangjie::rand-mvnorm 1000 [10.0 20.0]
  (cangjie::array [[4.0 3.0] [3.0 9.0]]) 42)
;; → 1000 个二维样本，每行一个
```

**它不只是一堆 `rand-normal`。** 独立跑 p 次 `rand-normal` 得到的是**各维互不相关**
的样本（协方差矩阵是对角阵）。但真实数据里维度之间几乎总是相关的 ——
身高与体重、温度与销量。

要让样本具备目标相关结构，得做线性变换：先把协方差矩阵分解成 `Σ = L·Lᵀ`（Cholesky），
再对每个标准正态样本 `z` 取 `x = μ + L·z`。这样样本的均值就是 `μ`、协方差就是 `Σ`。

```lisp
;; 验证：10000 个样本的协方差应该接近目标 [[4 3] [3 9]]
(define s (cangjie::rand-mvnorm 10000 [0.0 0.0] (cangjie::array [[4.0 3.0] [3.0 9.0]]) 42))
(cangjie::corr-matrix s)     ; 相关系数约 0.5，对应协方差 3/(2·3)
```

**协方差矩阵必须对称正定**，否则报错。不对称说明拿错了矩阵；非正定通常意味着
某两列完全共线、或某个方差为 0 —— 这两种情况在真实数据里都不罕见，
所以报错比给一个看着正常的样本有用。

同种子给同一批样本 —— 与其他 `rand-*` 一致。

## 下一步

- [回归：从相关到预测](/guide/06-regression) —— 多个变量一起看
