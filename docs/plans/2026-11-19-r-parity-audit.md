# 对照 R：xisp-sci 的能力覆盖审计

> **状态**：**现行**。本文回答一个问题：*一个习惯用 R 做数据分析的人，到 xisp-sci 这里会缺什么？*
>
> 它是 [`scope-and-roadmap`](2026-11-19-scope-and-roadmap.md) 的**横向验证**，不改变路线图的阶段顺序。
> 路线图说「按什么顺序做」，本文说「做完了的这套东西，横向看还漏了什么」。
>
> **基准**：2026-11-19，xisp-sci 0.3.1，58 个 Lisp 符号。

---

## 1. 为什么拿 R 做基准

三个理由，按重要性排：

1. **R 是统计计算的事实标准。** `MASS`（Venables & Ripley）和 `ISLR2`（James et al.）不是随便挑的两本书 ——
   前者的函数清单覆盖了经典统计的完整面，后者是「一个分析师从数据到结论」的标准路线。两者合起来，
   就是「统计计算该有什么」的现成答案。
2. **阶段 2 已经用 R 的约定做过数值对照。** pandas 的 `std(ddof=1)` 与 `quantile` 线性插值默认值都与 R 一致
   （见路线图附录）。既然正确性的参照已经选定了 R，覆盖面的参照也选同一个，口径才统一。
3. **不照搬 API，只对照能力。** R 的 `d/p/q/r` 前缀、`formula` 语法、S3 分派都是它的语言特性，
   不是统计能力本身。本仓有自己的命名与调用约定（`cangjie::` 前缀 + kebab-case），照搬写法没有意义。

> ⚠️ **这份文档补的是一个此前的空洞**：阶段 2 的基准验证了「**算得对不对**」（12 个数值列 × 7 个统计量，
> 与 pandas 全对），但从来没有验证过「**有没有**」。正确性 100% 而覆盖面只有三成，是完全可能的
> —— 而且正是本仓 0.3.1 的实际状态。

### 1.1 对照口径

只对照**「算数」**（路线图 §2.4 判据一），因此：

- ✅ 进对照表：描述统计、分布、假设检验、矩阵分解、数值方法、信号处理
- ❌ 不进对照表：绘图（`plot` / `lattice` / `ggplot2`）、建模公式与 S3 分派（`formula` / `update`）、
  数据框语义（`data.frame` / `subset` / `with`）、包管理与帮助系统

一个函数「在不在表里」本身就是判断：`lda`（判别分析）进表，`plot.lda` 不进表。

---

## 2. 现状：58 个符号

| 域 | 符号数 | 内容 |
|---|---|---|
| `xisp_array` | 10 | `ndarray` `vector` `array` `zeros` `ones` `arange` `shape` `reshape` `transpose` `slice` |
| `xisp_stats` | 18 | `mean` `median` `std` `std-pop` `var` `quantile` `min` `max` `corr` `cov` `corr-matrix` `histogram` `five-num` `ci` `t-test1` `t-test2` `group-by` `group-agg` |
| `xisp_linalg` | 9 | `matmul` `trace` `det` `solve` `inv` `lu` `qr` `cholesky` `lstsq` |
| `xisp_signal` | 6 | `fft` `ifft` `fft-magnitude` `conv` `filter` `window` |
| `xisp_num` | 7 | `interp1` `polyfit` `polyval` `fmin` `rk4` `simpson` `trapz` |
| `xisp_io` | 8 | `csv-open` `csv-next` `csv-read` `csv-write` `csv-parse` `csv-format` `csv-close` `csv-each` |

---

## 3. 逐域对照

图例：**✅ 覆盖** / **⚠️ 部分** / **❌ 缺** / **🚫 判据排除**

### 3.1 数组与数据操作

| R | xisp-sci | |
|---|---|---|
| `c` `matrix` `array` `vector` | `array` `vector` `ndarray` | ✅ |
| `dim` `nrow` `ncol` `length` | `shape` | ✅ |
| `t` `aperm` | `transpose` | ✅ |
| `[` `[[` 下标与切片 | `slice` | ✅ |
| `seq` `rep` | `arange` | ✅ |
| `%*%` `crossprod` `outer` | `matmul`（+ `transpose` 可拼） | ✅ |
| `sort` `order` `rank` `unique` `rev` | —— | ❌ |
| `cumsum` `cumprod` `diff` | —— | ❌ |
| `apply` `sapply` `lapply` `tapply` | `group-agg` 覆盖了聚合这一支 | ⚠️ |
| `subset` `with` `within` | —— | 🚫 数据框语义，不是算数 |

**判断**：`sort` / `order` / `rank` 是**真缺口**，而且便宜 —— 它们是排序与秩，纯数组操作。
`cumsum` / `cumprod` 同理。这几项在「拿着一列数据做探索」时几乎必然用到。

### 3.2 描述统计

| R | xisp-sci | |
|---|---|---|
| `mean` `median` `sd` `var` | `mean` `median` `std` `var` `std-pop` | ✅ |
| `cov` `cor` | `cov` `corr` `corr-matrix` | ✅ |
| `quantile` `fivenum` `summary` | `quantile` `five-num` | ✅ |
| `min` `max` `range` `mad` | `min` `max`（nan-aware） | ⚠️ 缺 `range` `mad` |
| `sum` `prod` | core 的 `sum` / `product` | ✅ |
| `table` `xtabs`（列联表） | `group-by` 可拼出等价物 | ⚠️ |
| `summary`（一体化） | —— | ❌ |

**判断**：这一域基本齐了，这是本仓最扎实的部分 —— 阶段 2 的基准就是围绕它建的。
`mad`（中位数绝对偏差）缺失值得补：它是稳健统计的最小单元，实现成本几行。

### 3.3 分布函数 —— ✅ **已补（2026-11-19）**

R 的 `d/p/q/r` 四前缀体系是统计计算的地基：**密度 / 累积 / 分位数 / 随机**。
任何一个统计量要变成 p 值，都必须过 `p*` 这一关。

| 分布族 | R | xisp-sci |
|---|---|---|
| 正态 | `dnorm` `pnorm` `qnorm` `rnorm` | ❌ |
| t | `dt` `pt` `qt` `rt` | ❌（**内部有实现，但没暴露**） |
| 卡方 | `dchisq` `pchisq` `qchisq` | ❌ |
| F | `df` `pf` `qf` | ❌ |
| 泊松 | `dpois` `ppois` `qpois` | ❌ |
| 二项 | `dbinom` `pbinom` `qbinom` | ❌ |
| 伽马 | `dgamma` `pgamma` `qgamma` | ❌ |
| Beta | `dbeta` `pbeta` `qbeta` | ❌ |
| 指数 / 均匀 / 对数正态 / 威布尔 / 几何 / 负二项 / 超几何 / 柯西 | 各自 `d/p/q` | ❌ |
| Wilcoxon / 符号秩 | `dwilcox` `pwilcox` `qwilcox` 等 | ❌ |

**这里原本是最刺眼的一处**：`xisp_stats/src/dist.cj` 早有 `lgammaOf`、`betaCF`（Lentz 连分式）、
`betaInc`（正则不完全 Beta）、`tCdf`、`tCritical`、`tTwoSidedP` —— 却**一个都没注册成 Lisp 符号**。
用户拿 `t-test1` 能拿到 p 值（因为打包在里面），可一旦自己想算点别的 ——
「这个卡方统计量对应多大 p 值」「95% 分位点在哪」—— 就完全没有入口。
库的统计推断能力被封在三个函数里。

**已于 2026-11-19 补齐**，六族 18 个符号：

| 家族 | 密度 / 质量 | 累积 | 分位数 |
|---|---|---|---|
| 正态 | `norm-pdf` | `norm-cdf` | `norm-quantile` |
| t | `t-pdf` | `t-cdf` | `t-quantile` |
| 卡方 | `chisq-pdf` | `chisq-cdf` | `chisq-quantile` |
| F | `f-pdf` | `f-cdf` | `f-quantile` |
| 泊松 | `pois-pmf` | `pois-cdf` | `pois-quantile` |
| 二项 | `binom-pmf` | `binom-cdf` | `binom-quantile` |

补的过程中发现一件事值得记下来：**`erf` 根本不用单独实现**。
正态的 CDF 需要误差函数，但 `erf(x) = P(1/2, x²)` —— 不完全 Gamma 的换名而已。
于是卡方（`P(df/2, x/2)`）、泊松（`Q(k+1, λ)`）、正态（经 `erf`）三族共用同一个
`gammaIncLower` / `gammaIncUpper`，只补一种特殊函数就解锁了一整片。

命名走了 `-pdf` / `-pmf` / `-cdf` / `-quantile` 而不是 R 的 `d` / `p` / `q` / `r`，
理由写在 §6.1（已定，选 B）。

### 3.4 假设检验

| R | xisp-sci | |
|---|---|---|
| `t.test` | `t-test1` `t-test2` | ✅ |
| `wilcox.test`（秩和 / 符号秩） | —— | ❌ |
| `chisq.test` | —— | ❌ |
| `fisher.test` | —— | ❌ |
| `ks.test`（K-S 拟合优度） | —— | ❌ |
| `shapiro.test`（正态性） | —— | ❌ |
| `var.test`（方差齐性） | —— | ❌ |
| `prop.test` `binom.test`（比例） | —— | ❌ |
| `cor.test`（相关显著性） | —— | ❌ |
| `aov` `anova` `kruskal.test` `friedman.test` | —— | ❌ |
| `bartlett.test` `fligner.test` `ansari.test` `mood.test` | —— | ❌ |
| `pairwise.t.test` `power.t.test` | —— | ❌ |

**判断**：`t.test` 一个孤零零地立着。这不是「还差几个检验」的问题 —— 缺的是**检验的通用形状**：
每个检验都产出一个统计量，再经对应分布的 `p*` 转成 p 值。§3.3 补上之后，
这里的每一个都是「算统计量 + 查一次 CDF」，成本远低于现在看起来的样子。

`cor.test` 尤其值得补：已经有了 `corr` 和 `cov`，却没法回答「这个 r 显著吗」。

### 3.5 回归与建模

| R | xisp-sci | |
|---|---|---|
| `lm`（最小二乘） | `lstsq` | ✅ |
| `nls`（非线性） | `fmin` 可拼 | ⚠️ |
| `loess` `smooth.spline` | `interp1` 覆盖插值，不覆盖平滑 | ⚠️ |
| `glm`（广义线性） | —— | ❌ |
| `lm.ridge` `lasso`（正则化） | —— | ❌ |
| `rlm` `lqs` `ltsreg`（稳健回归） | —— | ❌ |
| `stepAIC` `addterm` `dropterm`（逐步选择） | —— | ❌ |
| `polr`（有序逻辑） | —— | ❌ |
| `loglm`（对数线性） | —— | ❌ |
| `glmmPQL`（混合模型） | —— | 🚫 需要公式系统与随机效应，远超「算数」 |
| `formula` `predict` `update` | —— | 🚫 模型 DSL，不是数值能力 |

**判断**：`lstsq` 覆盖了 `lm` 的核心（系数点估计）。缺的是**推断部分**（标准误 / t 值 / p 值 / R²）
—— 而这一块恰好也靠 §3.3 的分布函数。所以 §3.3 是这一域的真正前置。

### 3.6 矩阵分解与线性代数 —— **第二大缺口**

| R | xisp-sci | |
|---|---|---|
| `qr` `lu`（Matrix 包） | `qr` `lu` | ✅ |
| `chol` | `cholesky` | ✅ |
| `solve` `det` `t` | `solve` `det` `transpose` | ✅ |
| **`eigen`（特征值 / 特征向量）** | —— | ❌ |
| **`svd`（奇异值分解）** | —— | ❌ |
| `ginv`（Moore-Penrose 广义逆） | —— | ❌ |
| `rank`（矩阵秩） | —— | ❌ |
| `norm`（矩阵范数） | —— | ❌ |
| `cond`（条件数） | —— | ❌ |
| `kronecker` | —— | ❌ |

路线图 §5 阶段 4 原文：**「`eig` / `svd` 视难度单独排」** —— 这一排就排到了现在，实际上没做。

**为什么这是硬缺口**（不是「锦上添花」）：

1. **PCA 全靠它。** `eigen` 或 `svd` 缺一个，ISLR 第 12 章的主线（主成分分析）就做不了。
2. **`rank` 与 `cond` 是数值诊断的基本工具。** 现在只能靠 `det` 接近 0 来判断奇异，
   而 `det` 在维度稍大时既可能上溢又可能下溢，是个不可靠的代理。
3. **`lstsq` 现在走 QR。** 对病态矩阵，SVD 是更稳的路线；有 SVD 才能给出「这个解有多可信」。
4. **`ginv` 让非满秩最小二乘有解。** 目前 `solve` 对奇异矩阵只能报错。

### 3.7 降维与聚类

| R | xisp-sci | 判断 |
|---|---|---|
| `prcomp` `princomp`（PCA） | —— | ❌ **该做**：它是 `svd` 的直接应用，属算数 |
| `factanal`（因子分析） | —— | ❌ 需要 ML 拟合，单独评估 |
| `hclust` `kmeans` `cutree` | —— | ❌ 判为 ML 域，暂不做 |
| `isoMDS` `sammon`（MDS） | —— | ❌ 需要迭代优化 + 随机初始化 |
| `corresp` `mca`（对应分析） | —— | ❌ 同上 |

**判断**：PCA 的边界很干净 —— 它就是把中心化后的矩阵做 SVD，是**线性代数**，不是机器学习。
其余的都带迭代优化与随机性，先放着。

### 3.8 平滑与密度

| R | xisp-sci | |
|---|---|---|
| `hist` | `histogram` | ✅ |
| `approx` `spline` `splinefun` | `interp1` | ✅ |
| `density`（核密度估计） | —— | ❌ |
| `kde2d`（二维核密度） | —— | ❌ |
| `ecdf`（经验分布） | —— | ❌ |
| `ksmooth` `loess` | —— | ❌ |
| `bandwidth.nrd` `bcv` `ucv`（带宽选择） | —— | ❌ |

**判断**：`density` 值得做（一维 KDE 是几十行的卷积，且 `conv` 已经有了）；
`ecdf` 几乎免费。`loess` 是局部加权回归，属建模，暂不做。

### 3.9 信号与数值方法

| R | xisp-sci | |
|---|---|---|
| `fft` | `fft` `ifft` `fft-magnitude` | ✅ |
| `convolve` | `conv` | ✅ |
| `filter` | `filter` | ✅ |
| `window`（窗函数） | `window` | ✅ |
| `integrate` | `simpson` `trapz` | ✅ |
| `optim` `nlm` `nlminb` | `fmin` | ⚠️ 缺梯度法与约束 |
| `uniroot`（一维求根） | —— | ❌ |
| `ode`（deSolve 包） | `rk4` | ✅ |
| `polyroot`（多项式求根） | —— | ❌ |
| `area`（自适应积分，MASS） | `simpson` 是定步长 | ⚠️ |

**判断**：这一域覆盖得不错。`uniroot` 与 `polyroot` 是真缺口 —— 后者正好是 `polyfit` 的逆运算，
有了它才能「拟合完多项式后问根在哪」。

### 3.10 随机数与重采样

| R | xisp-sci | |
|---|---|---|
| `set.seed` `rnorm` `runif` `sample` | —— | ❌ |
| `mvrnorm`（多元正态） | —— | ❌ |
| bootstrap / 交叉验证（ISLR 第 5 章） | —— | ❌ |

**判断**：这是**唯一一个与「纯计算」定位有张力**的缺口。随机数需要**状态**（种子），
而本仓的域都声明为纯函数、无副作用。要做得干净，得先回答三个问题：
种子放哪（域内状态 / 显式传参 / 线程局部）、可复现性怎么保证、`escapable` 怎么标。
**这不是实现难度问题，是架构决策问题**，必须单独定，不能顺手加。

---

## 4. 三个地基级缺口

按「补上之后能解锁多少别的东西」排序：

| # | 缺口 | 解锁什么 | 成本 | 状态 |
|---|---|---|---|---|
| **G1** | 分布函数没暴露 | §3.4 全部假设检验、§3.5 回归推断、`cor.test` | 低 | ✅ **已完成** |
| **G2** | **`svd` / `eigen` 缺失** | PCA、`rank`、`cond`、`ginv`、更稳的 `lstsq` | **中高** —— Jacobi / Golub-Reinsch 要仔细实现并用性质验 | 待做 |
| **G3** | **随机数缺失** | bootstrap、交叉验证、蒙特卡洛、`mvrnorm` | **中** —— 实现不难，但要先定架构（状态归属） | 卡在决策 |

**排序的理由**：G1 便宜且是其余一切的前置 —— 有了 `p*` / `q*`，`cor.test`、`shapiro.test`、
回归的标准误全都变成「算个统计量 + 查一次表」。G2 是硬骨头但边界清晰、产出可验证（用定义性质验，
不比手算值），而且它是路线图自己欠下的账。G3 卡在决策上，不是卡在代码上。

---

## 5. 明确不做的

| 类别 | 例子 | 判据 |
|---|---|---|
| 绘图 | `plot` `hist` 的渲染、`lattice`、`ggplot2` | 路线图 §2.3：展示不是算数。本仓最多输出结构化数据 |
| 模型 DSL | `formula` `update` `predict` 的语法糖 | 是语言特性，不是数值能力。等价逻辑在 Lisp 层用 `lstsq` + 闭包拼 |
| 数据框语义 | `data.frame` `subset` `with` `$` `merge` | 是数据结构，不是算数。CSV + 列数组已够 |
| 机器学习 | 树 / 随机森林 / boosting / SVM / 神经网络 | 需要训练循环与超参搜索，是独立领域 |
| 聚类 | `kmeans` `hclust` `MDS` | 需要随机初始化或迭代收敛，与 G3 耦合 |
| 混合模型 / 生存分析 | `glmmPQL` `survreg` | 需要公式系统 + 迭代拟合，远超本仓 |
| 时序分析 | `arima` `acf` `pacf` `decompose` | 需要完整的模型状态与信息准则，暂不碰 |

这张表比上面那些「❌」更重要：**它定义了本仓是什么**。

---

## 6. 建议的下一步

1. ✅ **G1 已完成**（18 个分布符号）。只做了分布函数本身；
   当初一并提到的 `mad` / `range` / `sort` / `order` / `rank` / `cumsum` **还没做** ——
   它们与分布函数不相关，属于「便宜的数组操作」，可以随时单独补。
2. **下一步做 G2**（`svd` / `eigen`）。用性质验（`U Σ Vᵀ = A`、`QᵀQ = I`、特征值之和 = 迹），
   不比手算值 —— 与 `qr` / `cholesky` 的验收方式保持一致。做完顺手给 `rank` / `cond` / `ginv` / PCA。
3. **G3 单独开决策**，不在实现任务里夹带。

### 6.1 G1 的命名选择（✅ 已定：方案 B）

R 的 `pnorm` / `qnorm` 命名依赖 `d/p/q/r` 四个字母的记忆。本仓的命名约定是
`cangjie::` + kebab-case（`std-pop` / `t-test1` / `five-num`），照搬 R 会让两个约定打架。

两条路：

| 方案 | 写法 | 优点 | 缺点 |
|---|---|---|---|
| A. 学 R | `cangjie::pnorm` `cangjie::qnorm` `cangjie::dnorm` | 与 R / SciPy 习惯一致，熟悉的人零学习成本 | `d` / `p` / `q` / `r` 要记；与 kebab-case 不一致 |
| B. 自解释 | `cangjie::norm-cdf` `cangjie::norm-quantile` `cangjie::norm-pdf` | 与现有符号风格统一，看名字知道是什么 | 名字长；与 R 用户的直觉不同 |

**实际选了 B**：本仓已有 `std` 与 `std-pop` 的先例 —— 用**描述性后缀**而不是缩写来区分语义。
而且 `t-test1` / `t-test2` 也没跟着 R 叫 `t.test(..., paired=FALSE)`。R 用户看 `norm-cdf`
能反推回 `pnorm`，反过来不成立（不熟悉 R 的人看到 `pnorm` 猜不出是什么）。

无论选哪个，都要把**分布名放在前面**（`norm-*` `t-*` `chisq-*`），这样按前缀排序时同族能挨在一起。
