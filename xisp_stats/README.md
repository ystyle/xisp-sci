# xisp_stats

星枢科学计算统计：描述统计、分位数、相关、直方图、假设检验、分布函数。

```lisp
(define d (cangjie::csv-read "sales.csv"))
(cangjie::mean (hashmap-get d "amount"))     ; 均值
(cangjie::std (hashmap-get d "amount"))      ; 样本标准差
(cangjie::median (hashmap-get d "region"))   ; 中位数
(cangjie::corr (hashmap-get d "amount") (hashmap-get d "qty"))
(cangjie::norm-cdf 1.96 0 1)                 ; 0.9750 —— 分布函数
```

## 符号

| 符号 | 说明 |
|---|---|
| `cangjie::mean` | 算术平均 |
| `cangjie::median` | 中位数 |
| `cangjie::std` | **样本**标准差（除 `n-1`） |
| `cangjie::std-pop` | 总体标准差（除 `n`） |
| `cangjie::var` | 样本方差 |
| `cangjie::quantile` | 分位数（线性插值，与 NumPy 默认一致） |
| `cangjie::cov` | 协方差（样本） |
| `cangjie::corr` | 皮尔逊相关系数 |
| `cangjie::histogram` | 直方图 → `{"edges": …, "counts": …}` |
| `cangjie::min` | 最小值（**跳过 NaN**） |
| `cangjie::max` | 最大值（**跳过 NaN**） |
| `cangjie::group-by` | 按类别分组 → `[[key, ndarray] …]` |
| `cangjie::group-agg` | 分组后聚合 → `[[key, 聚合值] …]` |
| `cangjie::t-test1` | 单样本 t 检验 → `{t, df, p, mean, se, n}` |
| `cangjie::t-test2` | 双样本 Welch t 检验 → `{t, df, p, mean1, mean2, …}` |
| `cangjie::ci` | 均值置信区间 → `{lo, hi, mean, se, df, tcrit}` |
| `cangjie::five-num` | 箱线图数据（五数概括 + 离群点） |
| `cangjie::corr-matrix` | 相关矩阵（热力图数据） |
| `cangjie::norm-pdf` / `norm-cdf` / `norm-quantile` | 正态 `N(μ, σ²)` |
| `cangjie::t-pdf` / `t-cdf` / `t-quantile` | Student t |
| `cangjie::chisq-pdf` / `chisq-cdf` / `chisq-quantile` | 卡方 |
| `cangjie::f-pdf` / `f-cdf` / `f-quantile` | F 分布 |
| `cangjie::pois-pmf` / `pois-cdf` / `pois-quantile` | 泊松 |
| `cangjie::binom-pmf` / `binom-cdf` / `binom-quantile` | 二项 |

同时接受 ndarray 与普通列表：`(cangjie::mean arr)` 与 `(cangjie::mean [1 2 3])` 都能用。

## 分组聚合

```lisp
;; 一行出结果：各物种的花瓣长度均值
(cangjie::group-agg (hashmap-get d "species") (hashmap-get d "petal_length") cangjie::mean)
;; → (("setosa" 1.464) ("versicolor" 4.260) ("virginica" 5.552))

;; 或者先分组，再用 map 自己聚合
(map (lambda (kv) (list (car kv) (cangjie::quantile (cadr kv) 0.9)))
     (cangjie::group-by (hashmap-get d "species") (hashmap-get d "speed")))
```

**返回 alist 而不是 HashMap**，是因为 alist 有确定顺序（按类别**首次出现**），
而 HashMap 的迭代顺序不保证 —— 报告和图表都依赖顺序稳定。alist 还能直接喂给 `map`。

**一次遍历完成分组**（O(n)），不是"对每个类别扫一遍全表"（O(k·n)）。类别一多，
后者会慢成几倍。

组内**保持原始顺序**（不排序）—— 对时间序列类数据很重要。

## 假设检验

```lisp
;; 男女生的期末成绩差异显著吗
(define g (cangjie::group-by (hashmap-get d "sex") (hashmap-get d "G3")))
(cangjie::t-test2 (cadr (car g)) (cadr (cadr g)))
;; → {"t": -2.065, "df": 390.569, "p": 0.039577, ...}

;; 均值的 95% 置信区间
(cangjie::ci (hashmap-get d "G3") 0.95)
;; → {"lo": 9.9619, "hi": 10.8683, "mean": 10.4151, "tcrit": 1.9660, ...}
```

**为什么 p 值值得算**：「A 组均值比 B 组高 2 分」本身没有信息量 —— 两组各 3 个样本时
这 2 分可能纯属偶然，各 3000 个样本时几乎一定是真的。p 值回答的是「这个差异有多可能
是偶然」。

**双样本用 Welch 而不是合并方差版本**。方差相等这个前提在真实数据里几乎从不成立：
两组样本量差很多时，合并方差会把大方差那组过度加权，让 p 值系统性地偏小。

**返回 HashMap 而不是 alist**（与 `group-by` 相反）：检验结果没有顺序语义，
按名字取值比按位置取更不容易错。

**t 分布从零实现**：仓颉的 `std.math` 没有 `lgamma`/`tgamma`（探测过），所以
Gamma 函数用 Lanczos 近似、不完全 Beta 用连分式 + Lentz 算法、分位数用二分反解。
验证方式是拿**教科书 t 分位数表**逐个对（df=1 → 12.706、df=30 → 2.042），
容差 1e-3 全过。

## 分布函数

```lisp
(cangjie::norm-cdf 1.96 0 1)          ; → 0.975002
(cangjie::norm-quantile 0.975 0 1)    ; → 1.959964
(cangjie::t-cdf 2.0 5)                ; → 0.949030
(cangjie::chisq-quantile 0.95 1)      ; → 3.841459
(cangjie::f-quantile 0.95 3 20)       ; → 3.098391
(cangjie::pois-pmf 2 2.5)             ; → 0.256516
(cangjie::binom-cdf 5 10 0.3)         ; → 0.952651
```

**这组函数解决的是「除了 `t-test1` / `t-test2`，其余检验都算不出 p 值」这个问题。**

统计推断的出口永远是 p 值，而 p 值永远是「某个统计量落在某个分布尾部的概率」。之前
`dist.cj` 里虽然已经有 `tCdf` / `betaInc` 这些基础设施，但一个都没暴露到 Lisp 层 ——
能力被封在三个打包好的检验函数里。想算个卡方统计量对应的 p、想找一个 95% 分位点、
想自己搭一个检验，都没有入口。现在它们有了。

### 参数顺序

| 家族 | 形式 |
|---|---|
| `norm-*` | `(x mu sigma)` / `(p mu sigma)` |
| `t-*` | `(t df)` / `(p df)` |
| `chisq-*` | `(x df)` / `(p df)` |
| `f-*` | `(x d1 d2)` / `(p d1 d2)` |
| `pois-*` | `(k lambda)` / `(q lambda)` |
| `binom-*` | `(k n p)` / `(q n p)` |

**分位数函数（`*-quantile`）的第一个参数是概率**，其余与同族 `pdf` / `cdf` 一致。

### 三条命名约定

**① 分布名在前。** `norm-` / `t-` / `chisq-` / `f-` / `pois-` / `binom-` 前缀让排序时同族
挨在一起，文档按前缀分组也不会散。

**② 连续用 `-pdf`，离散用 `-pmf`。** R 的 `d` 前缀不分这个，但「概率密度」与「概率质量」
是不同量纲的东西：连续分布的 `-pdf` 值可以大于 1，离散的 `-pmf` 不能。

**③ 不抄 R 的 `d/p/q/r` 缩写。** 本仓已有 `std` 对 `std-pop` 的先例 —— 用描述性后缀区分
语义，不靠单字母记忆。R 用户看名字能反推回 `pnorm` / `qnorm`，反过来不成立。

### 返回类型

`-pmf` / `-pdf` / `-cdf` 返回 `Float`，**`pois-quantile` / `binom-quantile` 返回 `Int`**。
离散分布的分位数按定义取**下侧**：最小的 `k` 使 `CDF(k) ≥ p`。返回值拿去当数组下标不会出错。

### 非法参数报 `TypeError`，不会静默返回 `nan`

```lisp
(cangjie::norm-cdf 1 0 0)      ; Error: cangjie::norm-cdf 的 sigma 必须 > 0，得到 0
(cangjie::chisq-cdf -1 4)      ; Error: cangjie::chisq-cdf：参数超出分布的定义域
```

数学层对越界参数返回 `NaN`，这是数值代码的惯例（NaN 可以继续传播，由调用方决定）；
但 Lisp 层拦下来转成明确错误 —— 否则 `nan` 会一路飘到最终结果，用户只看到
「算出来是 NaN」，根本不知道是哪个参数错了。

### 数值实现

全部从零实现，没有外部依赖：

| 需要的 | 怎么来的 |
|---|---|
| `log Γ(x)` | Lanczos 近似（g=7，9 项系数），负数走反射公式 |
| 不完全 Beta `I_x(a,b)` | 连分式 + Lentz 算法 |
| 不完全 Gamma `P(a,x)` / `Q(a,x)` | 级数展开（`x < a+1`）+ 连分式（否则） |
| `erf` / `erfc` | **没有专门实现** —— `erf(x) = P(1/2, x²)`，直接用上一层 |
| 分位数 | 二分反解 CDF（不用牛顿：t / F / 卡方的 PDF 在端点会溢出，导数法难写稳） |

仓颉的 `std.math` **没有** `lgamma` / `tgamma` / `erf`（探测过，`undeclared identifier`）。
正态 / 卡方 / 泊松三个族的 CDF 都归到同一个不完全 Gamma 上，所以补一种特殊函数就解锁一整片。

正确性验证用**三套互相独立的证据**（详见 `src/distributions_test.cj` 的文件注释）：
外部锚点（Python 标准库 `math.erfc`、逐项精确求和、`t` 的 df=1/2 闭式解）、
跨分布恒等式（`χ²₁ = Z²`、`χ²_{2k}` 与泊松、`F(1,v) = t(v)²`）、内部自洽（CDF 数值导数 = PDF、
分位数互逆）。

### 为什么没有随机数

`rnorm` / `rt` 这类抽样需要**状态**（种子），而本仓所有域都声明为纯函数、无副作用。
种子放哪（域内状态 / 显式传参 / 线程局部）、可复现性怎么保证、`escapable` 怎么标 ——
这是架构决策，不是实现难度问题，要单独定。

## 图表数据

本仓**不渲染**图表，只产出绘图层需要的数据结构。

散点图、折线图不需要专门函数 —— 要的就是数据本身。箱线图与相关矩阵需要真实计算：

```lisp
(cangjie::five-num col)
;; → {"q1": 1.4, "median": 1.5, "q3": 1.575, "iqr": 0.175,
;;    "low_whisker": 1.2, "high_whisker": 1.7, "outliers": #<ndarray ...>}

(cangjie::corr-matrix X)     ; X 是 n×p，输出 p×p
```

**箱线图的须不是 min/max**。Tukey 的 1.5·IQR 规则下，须止于**围栏内最远的实际数据点**，
围栏外的点单列为离群点。这个约定很重要 —— 若用极值当须，一个离群点会把箱体压扁到
看不出中位数在哪。

**相关系数用成对删除缺失**：某行在变量 i 上缺失、在 j 上没缺失时，这一行对 `(i,j)`
不可用，但对其它变量对仍然可用。改成整行删除会让样本量凭空少一大截。

## 设计要点

**缺失值跳过**。所有函数忽略 `NaN`（CSV 里的空单元格）。这是唯一不会把"缺失"和
"真的是 0"混为一谈的做法：`[1, NaN, 3]` 的均值是 2 而不是 1.333。

**`corr` / `cov` 成对过滤**。任一侧缺失就丢整个样本。若各自独立跳 `NaN`，两个数组会
错位 —— 算的是"1 号的价格对 5 号的销量"，数字看着正常，结论完全错。

**`cangjie::min` / `cangjie::max` 与 core 的 `min` / `max` 是两套语义**。

core 的 `(min x)` / `(max x)` 保持数学语义：NaN 参与比较后整体变成 NaN。这对数值计算是对的
（NaN 就该传播），但数据分析里 NaN 是「缺失」不是「无穷小」——一批数据里有一个空值就让
最大值变成 NaN 是不能接受的。

所以：**加 `cangjie::` 前缀 = 数据分析语义（跳过缺失）**，裸名 = 数学语义（NaN 传播）。
两者各有正确用法，不是重复实现。

**空输入返回 `NaN`** 而不是报错。"没有数据的均值"是未定义的，返回 0 会让调用方拿着一个
看起来正常的结果继续算下去；`NaN` 会一路传播，在最终结果处暴露。

**`std` 默认用样本自由度（`n-1`）**，注意这与 NumPy 相反（`np.std` 默认 `ddof=0`）。
提供 `std-pop` 给需要总体标准差的场景。选样本作默认是因为数据分析里手上的数据几乎总是样本。

## 许可

MIT
